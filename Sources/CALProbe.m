//
//  CALProbe.m
//

#import "CALProbe.h"
#import "CALPrivateAPI.h"
#import <UIKit/UIKit.h>

/// 必须与 XiangKeIntent.swift 里的同名常量一致
static NSString * const kProbeFileName = @"xiangke-probe.log";

@implementation CALProbe

#pragma mark - 路径

+ (NSArray<NSString *> *)candidateDirs {
    NSMutableArray<NSString *> *dirs = [NSMutableArray array];
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                         NSUserDomainMask, YES).firstObject;
    if (docs.length) [dirs addObject:docs];
    [dirs addObject:@"/var/mobile/Documents"];
    [dirs addObject:@"/var/mobile/Library/Preferences"];
    [dirs addObject:NSTemporaryDirectory()];
    return dirs;
}

+ (NSArray<NSString *> *)candidatePaths {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (NSString *dir in [self candidateDirs]) {
        if (dir.length == 0) continue;
        [paths addObject:[dir stringByAppendingPathComponent:kProbeFileName]];
    }
    return paths;
}

+ (NSString *)timestamp {
    static NSDateFormatter *fmt = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fmt = [[NSDateFormatter alloc] init];
        fmt.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
        fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    });
    return [fmt stringFromDate:[NSDate date]];
}

/// 追加写入；文件不存在则新建
+ (BOOL)append:(NSString *)text toPath:(NSString *)path {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (data.length == 0) return NO;

    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:path]) {
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!handle) return NO;
        @try {
            [handle seekToEndOfFile];
            [handle writeData:data];
        } @catch (NSException *e) {
            [handle closeFile];
            return NO;
        }
        [handle closeFile];
        return YES;
    }
    return [data writeToFile:path atomically:YES];
}

#pragma mark - 探针主体

+ (NSString *)runWithTrigger:(NSString *)trigger {
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"[%@] 触发：%@\n", [self timestamp], trigger ?: @"未知"];

    // 锁屏的直接判据：受保护数据是否可访问。
    // NO = 设备处于锁屏（且已设密码），即本次确实是在锁屏下跑的。
    BOOL pda = [UIApplication sharedApplication].isProtectedDataAvailable;
    [s appendFormat:@"  设备锁屏：%@（isProtectedDataAvailable = %@）\n",
        pda ? @"否" : @"是", pda ? @"YES" : @"NO"];

    // 关键测试：锁屏时能否访问闹钟数据文件
    [s appendFormat:@"  %@\n", [self describeTargetFile]];

    NSString *body = [s copy];

    // 找第一个能写的目录落盘
    NSString *note = @"失败：所有候选目录都不可写";
    for (NSString *path in [self candidatePaths]) {
        NSString *line = [NSString stringWithFormat:@"%@  → 日志写入：成功（%@）\n\n", body, path];
        if ([self append:line toPath:path]) {
            note = [NSString stringWithFormat:@"成功（%@）", path];
            break;
        }
    }

    return [NSString stringWithFormat:@"%@  → 日志写入：%@", body, note];
}

+ (NSString *)describeTargetFile {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:CAL_ALARM_PLIST_PATH]) {
        return [NSString stringWithFormat:@"闹钟数据文件：不存在（%@）", CAL_ALARM_PLIST_PATH];
    }

    NSDictionary *attr = [fm attributesOfItemAtPath:CAL_ALARM_PLIST_PATH error:nil];
    unsigned long long size = [attr[NSFileSize] unsignedLongLongValue];
    NSString *protection = attr[NSFileProtectionKey] ?: @"(未设置)";
    NSData *content = [NSData dataWithContentsOfFile:CAL_ALARM_PLIST_PATH];
    BOOL readable = content.length > 0;

    return [NSString stringWithFormat:
            @"闹钟数据文件：存在  大小=%llu  保护等级=%@  可读=%@",
            size, protection, readable ? @"是" : @"否"];
}

#pragma mark - 读取

+ (NSString *)readLog {
    for (NSString *path in [self candidatePaths]) {
        NSString *content = [NSString stringWithContentsOfFile:path
                                                     encoding:NSUTF8StringEncoding
                                                        error:nil];
        if (content.length > 0) return content;
    }
    return nil;
}

@end

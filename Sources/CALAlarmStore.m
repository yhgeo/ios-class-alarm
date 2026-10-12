//
//  CALAlarmStore.m
//

#import "CALAlarmStore.h"
#import "CALDaemonReloader.h"
#import "CALPrivateAPI.h"

#pragma mark - CALSystemAlarm

@implementation CALSystemAlarm
- (NSString *)timeString {
    return [NSString stringWithFormat:@"%02ld:%02ld", (long)self.hour, (long)self.minute];
}
- (NSString *)description {
    return [NSString stringWithFormat:@"<CALSystemAlarm %@ %@ %@>",
            [self timeString], self.enabled ? @"开" : @"关", self.title];
}
@end

#pragma mark - 内部工具

/// 读取闹钟数据根字典（失败返回 nil）
static NSMutableDictionary *CALLoadAlarmRoot(void) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:CAL_ALARM_PLIST_PATH];
    return d ? [d mutableCopy] : nil;
}

/// 取一个闹钟字典作为模板：优先现有普通闹钟，退回睡眠闹钟
static NSMutableDictionary *CALTemplateAlarm(NSDictionary *alarmsRoot) {
    NSArray *existing = alarmsRoot[@"MTAlarms"];
    if ([existing isKindOfClass:[NSArray class]] && existing.count > 0) {
        NSDictionary *d = existing.firstObject[@"$MTAlarm"];
        if ([d isKindOfClass:[NSDictionary class]]) return [d mutableCopy];
    }
    NSArray *sleeps = alarmsRoot[@"MTSleepAlarms"];
    if ([sleeps isKindOfClass:[NSArray class]] && sleeps.count > 0) {
        NSDictionary *d = sleeps.firstObject[@"$MTAlarm"];
        if ([d isKindOfClass:[NSDictionary class]]) return [d mutableCopy];
    }
    return nil;
}

/// 落盘：备份 → CFPreferences 同步 → 直接写文件
static BOOL CALWriteAlarmRoot(NSDictionary *root) {
    NSFileManager *fm = [NSFileManager defaultManager];

    if ([fm fileExistsAtPath:CAL_ALARM_PLIST_PATH]) {
        [fm removeItemAtPath:CAL_ALARM_BACKUP_PATH error:nil];
        [fm copyItemAtPath:CAL_ALARM_PLIST_PATH toPath:CAL_ALARM_BACKUP_PATH error:nil];
    }

    // 走 cfprefsd，能让系统侧正确感知这次修改
    CFPreferencesSetValue(CFSTR("MTAlarms"),
                          (__bridge CFPropertyListRef)root[@"MTAlarms"],
                          CFSTR("com.apple.mobiletimerd"),
                          kCFPreferencesCurrentUser,
                          kCFPreferencesAnyHost);
    CFPreferencesAppSynchronize(CFSTR("com.apple.mobiletimerd"));

    // 直接落盘，双保险
    return [root writeToFile:CAL_ALARM_PLIST_PATH atomically:YES];
}

#pragma mark - CALAlarmStore

@implementation CALAlarmStore

+ (BOOL)isStorageAccessible {
    return [[NSFileManager defaultManager] isReadableFileAtPath:CAL_ALARM_PLIST_PATH];
}

+ (NSArray<CALSystemAlarm *> *)allAlarms {
    NSMutableArray<CALSystemAlarm *> *result = [NSMutableArray array];
    NSDictionary *root = CALLoadAlarmRoot();
    NSArray *list = root[@"MTAlarms"][@"MTAlarms"];
    if (![list isKindOfClass:[NSArray class]]) return result;

    for (NSDictionary *item in list) {
        NSDictionary *d = item[@"$MTAlarm"];
        if (![d isKindOfClass:[NSDictionary class]]) continue;

        CALSystemAlarm *a = [[CALSystemAlarm alloc] init];
        a.alarmID = [d[@"MTAlarmID"] isKindOfClass:[NSString class]] ? d[@"MTAlarmID"] : @"";
        a.hour = [d[@"MTAlarmHour"] integerValue];
        a.minute = [d[@"MTAlarmMinute"] integerValue];
        a.title = [d[@"MTAlarmTitle"] isKindOfClass:[NSString class]] ? d[@"MTAlarmTitle"] : @"";
        a.enabled = [d[@"MTAlarmEnabled"] boolValue];
        a.repeatSchedule = [d[@"MTAlarmRepeatSchedule"] integerValue];
        [result addObject:a];
    }
    return result;
}

+ (BOOL)addAlarmWithHour:(NSInteger)hour
                  minute:(NSInteger)minute
                   title:(NSString *)title {
    NSMutableDictionary *root = CALLoadAlarmRoot();
    if (!root) return NO;

    NSMutableDictionary *alarmsRoot = [root[@"MTAlarms"] mutableCopy];
    if (!alarmsRoot) return NO;

    NSMutableDictionary *alarm = CALTemplateAlarm(alarmsRoot);
    if (!alarm) return NO;

    alarm[@"MTAlarmHour"] = @(hour);
    alarm[@"MTAlarmMinute"] = @(minute);
    alarm[@"MTAlarmID"] = [[NSUUID UUID] UUIDString];
    alarm[@"MTAlarmEnabled"] = @1;
    alarm[@"MTAlarmIsSleep"] = @0;
    alarm[@"MTAlarmRepeatSchedule"] = @0;
    alarm[@"MTAlarmTitle"] = title;
    alarm[@"MTAlarmLastModifiedDate"] = [NSDate date];
    [alarm removeObjectForKey:@"MTAlarmFireDate"];
    [alarm removeObjectForKey:@"MTAlarmDismissDate"];
    [alarm removeObjectForKey:@"MTAlarmBedtimeFireDate"];

    NSMutableArray *list = [NSMutableArray arrayWithArray:alarmsRoot[@"MTAlarms"] ?: @[]];
    [list addObject:@{@"$MTAlarm": alarm}];
    alarmsRoot[@"MTAlarms"] = list;

    root[@"MTAlarms"] = alarmsRoot;
    root[@"MTAlarmModifiedDate"] = [NSDate date];

    return CALWriteAlarmRoot(root);
}

+ (NSInteger)removeAlarmsWithTitlePrefix:(NSString *)prefix {
    if (prefix.length == 0) return 0;

    NSMutableDictionary *root = CALLoadAlarmRoot();
    if (!root) return 0;

    NSMutableDictionary *alarmsRoot = [root[@"MTAlarms"] mutableCopy];
    NSArray *list = alarmsRoot[@"MTAlarms"];
    if (![list isKindOfClass:[NSArray class]] || list.count == 0) return 0;

    NSMutableArray *kept = [NSMutableArray array];
    NSInteger removed = 0;
    for (NSDictionary *item in list) {
        NSString *t = item[@"$MTAlarm"][@"MTAlarmTitle"];
        if ([t isKindOfClass:[NSString class]] && [t hasPrefix:prefix]) {
            removed++;
        } else {
            [kept addObject:item];
        }
    }
    if (removed == 0) return 0;

    alarmsRoot[@"MTAlarms"] = kept;
    root[@"MTAlarms"] = alarmsRoot;
    root[@"MTAlarmModifiedDate"] = [NSDate date];

    CALWriteAlarmRoot(root);
    return removed;
}

+ (BOOL)commitChanges {
    return [CALDaemonReloader restartAlarmDaemon];
}

@end

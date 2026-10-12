//
//  CALDaemonReloader.m
//

#import "CALDaemonReloader.h"
#import "CALPrivateAPI.h"

#import <signal.h>
#import <stdlib.h>
#import <string.h>
#import <sys/sysctl.h>

static NSString *const kAlarmDaemonName    = @"mobiletimerd";
static NSString *const kClockAppProcessName = @"MobileTimer";

/// 上一次 SIGKILL 掉的 mobiletimerd PID —— 用来判断「新进程是否真的起来了」
static pid_t gPreviousDaemonPID = -1;

@implementation CALDaemonReloader

#pragma mark - 进程查找

+ (pid_t)pidForProcessNamed:(NSString *)name {
    pid_t target = -1;

    // 主路径：sysctl 遍历进程表
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t size = 0;
    if (sysctl(mib, 4, NULL, &size, NULL, 0) == 0 && size > 0) {
        struct kinfo_proc *procs = malloc(size);
        if (procs) {
            if (sysctl(mib, 4, procs, &size, NULL, 0) == 0) {
                int count = (int)(size / sizeof(struct kinfo_proc));
                for (int i = 0; i < count; i++) {
                    if (strcmp(procs[i].kp_proc.p_comm, name.UTF8String) == 0) {
                        target = procs[i].kp_proc.p_pid;
                        break;
                    }
                }
            }
            free(procs);
        }
    }

    // 备用路径：libproc
    if (target < 0) {
        int pids[4096];
        int n = proc_listallpids(pids, sizeof(pids));
        for (int i = 0; i < n; i++) {
            char pname[256] = {0};
            proc_name(pids[i], pname, sizeof(pname));
            if (strcmp(pname, name.UTF8String) == 0) {
                target = pids[i];
                break;
            }
        }
    }
    return target;
}

+ (pid_t)alarmDaemonPID {
    return [self pidForProcessNamed:kAlarmDaemonName];
}

#pragma mark - 重启守护进程

+ (BOOL)restartAlarmDaemon {
    pid_t pid = [self alarmDaemonPID];
    if (pid < 0) return NO;

    // 用 SIGKILL 而非 SIGTERM：
    // 优雅退出时守护进程可能把内存里的旧状态写回文件，覆盖我们刚写入的数据。
    if (kill(pid, SIGKILL) != 0) return NO;

    gPreviousDaemonPID = pid;
    return YES;
}

+ (BOOL)waitUntilReadyWithTimeout:(NSTimeInterval)timeout {
    NSTimeInterval deadline = [NSDate date].timeIntervalSince1970 + timeout;
    pid_t oldPid = gPreviousDaemonPID;

    // 注意：SIGKILL 之后 launchd 往往立刻就把新进程拉起来（PID 马上就有了），
    // 所以「等旧进程消失」这个条件永远等不到 —— 必须改成「等 PID 变化」。
    while ([NSDate date].timeIntervalSince1970 < deadline) {
        pid_t now = [self alarmDaemonPID];
        if (now > 0 && now != oldPid) return YES;
        [NSThread sleepForTimeInterval:0.15];
    }
    return NO;
}

#pragma mark - 时钟 App

+ (BOOL)isClockAppRunning {
    return [self pidForProcessNamed:kClockAppProcessName] > 0;
}

+ (BOOL)killClockAppIfRunning {
    pid_t pid = [self pidForProcessNamed:kClockAppProcessName];
    if (pid < 0) return NO;

    // 时钟 App 把闹钟列表缓存在内存里，光让 mobiletimerd 重读数据它并不会刷新界面。
    // 让它退出，用户下次打开就是冷启动，直接读新数据。
    return kill(pid, SIGKILL) == 0;
}

#pragma mark - 二进制字符串扫描

+ (NSArray<NSString *> *)stringsInFile:(NSString *)path
                            containing:(NSString *)keyword
                                 limit:(NSUInteger)limit {
    NSData *data = [NSData dataWithContentsOfFile:path
                                          options:NSDataReadingMappedIfSafe
                                            error:nil];
    if (data.length == 0 || keyword.length == 0) return @[];

    const uint8_t *bytes = data.bytes;
    NSUInteger len = data.length;
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];

    NSUInteger runStart = NSNotFound;

    for (NSUInteger i = 0; i <= len; i++) {
        BOOL printable = NO;
        if (i < len) {
            uint8_t c = bytes[i];
            printable = (c >= 0x20 && c < 0x7F);
        }

        if (printable) {
            if (runStart == NSNotFound) runStart = i;
            continue;
        }

        if (runStart == NSNotFound) continue;

        NSUInteger start = runStart;
        NSUInteger length = i - start;
        runStart = NSNotFound;

        if (length < 6 || length > 300) continue;

        NSString *s = [[NSString alloc] initWithBytes:bytes + start
                                               length:length
                                             encoding:NSASCIIStringEncoding];
        if (!s) continue;
        if ([s rangeOfString:keyword options:NSCaseInsensitiveSearch].location == NSNotFound) {
            continue;
        }
        if ([seen containsObject:s]) continue;

        [seen addObject:s];
        [result addObject:s];
        if (result.count >= limit) break;
    }

    return result;
}

@end

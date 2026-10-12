//
//  CALDaemonReloader.m
//

#import "CALDaemonReloader.h"
#import "CALPrivateAPI.h"

#import <signal.h>
#import <stdlib.h>
#import <string.h>
#import <sys/sysctl.h>

static NSString *const kAlarmDaemonName = @"mobiletimerd";

@implementation CALDaemonReloader

+ (pid_t)alarmDaemonPID {
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
                    if (strcmp(procs[i].kp_proc.p_comm, kAlarmDaemonName.UTF8String) == 0) {
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
            char name[256] = {0};
            proc_name(pids[i], name, sizeof(name));
            if (strcmp(name, kAlarmDaemonName.UTF8String) == 0) {
                target = pids[i];
                break;
            }
        }
    }
    return target;
}

+ (BOOL)restartAlarmDaemon {
    pid_t pid = [self alarmDaemonPID];
    if (pid < 0) return NO;

    // 用 SIGKILL 而非 SIGTERM：
    // 优雅退出时守护进程可能把内存里的旧状态写回文件，覆盖我们刚写入的数据。
    int rc = kill(pid, SIGKILL);
    return rc == 0;
}

+ (BOOL)waitUntilReadyWithTimeout:(NSTimeInterval)timeout {
    NSTimeInterval deadline = [NSDate date].timeIntervalSince1970 + timeout;

    // 阶段一：等旧进程消失
    while ([NSDate date].timeIntervalSince1970 < deadline) {
        if ([self alarmDaemonPID] < 0) break;
        [NSThread sleepForTimeInterval:0.2];
    }
    // 阶段二：等新进程出现
    while ([NSDate date].timeIntervalSince1970 < deadline) {
        if ([self alarmDaemonPID] > 0) return YES;
        [NSThread sleepForTimeInterval:0.2];
    }
    return [self alarmDaemonPID] > 0;
}

@end

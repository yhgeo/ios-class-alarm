//
//  CALDaemonReloader.h
//  负责让 mobiletimerd 重新加载闹钟数据。
//  单独成模块，将来若找到更优雅的方式（正确的 Darwin 通知名 / XPC 协议），
//  只需替换这里的实现，上层无感。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CALDaemonReloader : NSObject

/// 当前 mobiletimerd 的 PID；未找到返回 -1
+ (pid_t)alarmDaemonPID;

/// 重启 mobiletimerd（launchd 会自动拉起并重读数据）
+ (BOOL)restartAlarmDaemon;

/// 等待守护进程重新就绪，最多等待 timeout 秒；返回是否就绪
+ (BOOL)waitUntilReadyWithTimeout:(NSTimeInterval)timeout;

@end

NS_ASSUME_NONNULL_END

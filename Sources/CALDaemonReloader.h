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

/// 等待守护进程重新就绪（PID 与重启前不同才算就绪），最多等待 timeout 秒
+ (BOOL)waitUntilReadyWithTimeout:(NSTimeInterval)timeout;

/// 时钟 App（MobileTimer）是否在运行
+ (BOOL)isClockAppRunning;

/// 让时钟 App 退出，清掉它的界面缓存。没在运行就什么都不做。
+ (BOOL)killClockAppIfRunning;

/// 扫描二进制里的可打印字符串（用于找系统通知名）
+ (NSArray<NSString *> *)stringsInFile:(NSString *)path
                            containing:(NSString *)keyword
                                 limit:(NSUInteger)limit;

@end

NS_ASSUME_NONNULL_END

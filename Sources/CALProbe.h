//
//  CALProbe.h
//  探针：记录「某次执行发生在什么时候、当时是否锁屏、能否访问系统文件」。
//
//  为什么需要它：iOS 锁屏时禁止打开 App / URL，所以快捷指令那条路在锁屏必定失败。
//  替代方案（后台刷新 / App Intent）都要求「App 进程能在锁屏时跑起来并干活」。
//  能不能跑起来是一回事，跑起来后能不能读写真系统文件是另一回事 ——
//  系统偏好文件受数据保护（Data Protection）限制，锁屏时可能直接读写失败。
//  这一层推理不出来，只能实测。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CALProbe : NSObject

/// 跑一次探针：追加写入日志并返回本次报告。
/// trigger 用来标记触发来源，如「手动」「后台刷新」「URL 唤起」。
+ (NSString *)runWithTrigger:(NSString *)trigger;

/// 读取探针日志；没有记录返回 nil。
+ (nullable NSString *)readLog;

/// 候选日志路径（供界面显示，便于排查「到底写哪了」）。
+ (NSArray<NSString *> *)candidatePaths;

@end

NS_ASSUME_NONNULL_END

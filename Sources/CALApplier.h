//
//  CALApplier.h
//  协调层：把「课表」与「系统闹钟」串起来。
//  整个项目里只有这一层知道完整流程，其余模块都各管一段。
//

#import <Foundation/Foundation.h>
#import "CALTimetable.h"

NS_ASSUME_NONNULL_BEGIN

/// 由 URL Scheme（xiangke://apply）触发应用完成后广播。
/// userInfo[@"log"] 为执行日志，界面收到即可刷新。
extern NSNotificationName const CALDidApplyNotification;

@interface CALApplier : NSObject

/// 按课表设置次日闹钟：先清理旧的「课表」闹钟，再建新的。
/// 返回可读的执行日志。
+ (NSString *)applyTimetable:(CALTimetable *)timetable;

/// 只清理本 App 创建的闹钟，返回清理条数
+ (NSInteger)clearManagedAlarms;

/// 状态摘要（供界面显示）
+ (NSString *)statusSummaryWithTimetable:(CALTimetable *)timetable;

/// 由 URL Scheme 唤起时调用：后台执行应用，完成后广播 CALDidApplyNotification。
/// 不依赖界面是否已加载 —— 逻辑跑完再通知，界面没起来也不会漏做。
+ (void)applyTimetableFromURLTrigger;

/// 上次执行「应用课表」的时间（手动 / 快捷指令 / 后台刷新 / 常驻定时都算）；从未执行为 nil
+ (nullable NSDate *)lastAppliedDate;

/// 上次执行时间的可读描述（如 "10-14 22:00"）；从未执行返回「从未」
+ (NSString *)lastAppliedDescription;

@end

NS_ASSUME_NONNULL_END

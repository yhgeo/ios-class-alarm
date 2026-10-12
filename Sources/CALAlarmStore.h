//
//  CALAlarmStore.h
//  系统闹钟读写引擎。
//  只负责「系统闹钟」这一层：读、增、删、提交。
//  不关心课表，也不关心什么时候该设闹钟 —— 那是上层的事。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - 闹钟对象

@interface CALSystemAlarm : NSObject
@property (nonatomic, copy) NSString *alarmID;
@property (nonatomic) NSInteger hour;
@property (nonatomic) NSInteger minute;
@property (nonatomic, copy) NSString *title;
@property (nonatomic) BOOL enabled;
/// 位掩码：1=周一 2=周二 4=周三 8=周四 16=周五 32=周六 64=周日；0=不重复；127=每天
@property (nonatomic) NSInteger repeatSchedule;
- (NSString *)timeString;
@end

#pragma mark - 读写引擎

@interface CALAlarmStore : NSObject

/// 读取系统中所有「普通闹钟」（不含睡眠闹钟）
+ (NSArray<CALSystemAlarm *> *)allAlarms;

/// 新增一个一次性闹钟
+ (BOOL)addAlarmWithHour:(NSInteger)hour
                  minute:(NSInteger)minute
                   title:(NSString *)title;

/// 删除标题以 prefix 开头的所有闹钟，返回删除条数
+ (NSInteger)removeAlarmsWithTitlePrefix:(NSString *)prefix;

/// 把改动推送给系统：写文件 + 重启 mobiletimerd 使其重载
+ (BOOL)commitChanges;

/// 闹钟数据文件是否可读写（用于自检）
+ (BOOL)isStorageAccessible;

@end

NS_ASSUME_NONNULL_END

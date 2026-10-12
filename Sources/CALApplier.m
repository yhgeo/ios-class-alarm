//
//  CALApplier.m
//

#import "CALApplier.h"
#import "CALAlarmStore.h"
#import "CALDaemonReloader.h"
#import "CALScheduleEngine.h"
#import "CALPrivateAPI.h"

#pragma mark - 小工具

static NSString *CALWeekdayName(NSDate *date) {
    NSInteger sys = [[NSCalendar currentCalendar] component:NSCalendarUnitWeekday fromDate:date];
    NSArray<NSString *> *names = @[@"周日", @"周一", @"周二", @"周三", @"周四", @"周五", @"周六"];
    if (sys < 1 || sys > 7) return @"";
    return names[sys - 1];
}

static NSString *CALShortDate(NSDate *date) {
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    f.dateFormat = @"MM-dd";
    return [f stringFromDate:date];
}

static NSDate *CALTomorrow(void) {
    NSDate *d = [[NSCalendar currentCalendar] dateByAddingUnit:NSCalendarUnitDay
                                                         value:1
                                                        toDate:[NSDate date]
                                                       options:0];
    return d ?: [NSDate dateWithTimeIntervalSinceNow:24 * 3600];
}

#pragma mark - CALApplier

@implementation CALApplier

+ (NSString *)applyTimetable:(CALTimetable *)timetable {
    NSMutableString *log = [NSMutableString string];
    NSDate *tomorrow = CALTomorrow();

    // 1) 清理旧的课表闹钟
    NSInteger removed = [CALAlarmStore removeAlarmsWithTitlePrefix:CAL_ALARM_TITLE_PREFIX];
    [log appendFormat:@"· 清理旧课表闹钟：%ld 个\n", (long)removed];

    // 2) 计算目标时间
    NSDate *target = [CALScheduleEngine alarmTimeForDate:tomorrow timetable:timetable];
    if (!target) {
        [log appendString:@"· 次日无课，不设闹钟\n"];
        [CALAlarmStore commitChanges];
        [log appendString:@"· 已提交并触发重载\n"];
        return log;
    }

    CALCourse *first = [timetable firstCourseForDate:tomorrow];
    NSDateComponents *c = [[NSCalendar currentCalendar]
        components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:target];

    NSString *name = first.name.length > 0 ? first.name : @"未命名";
    NSString *title = [NSString stringWithFormat:@"%@%@ %@",
                       CAL_ALARM_TITLE_PREFIX, CALWeekdayName(tomorrow), name];

    [log appendFormat:@"· 第一节课：%@ %@（%@）\n", CALShortDate(tomorrow), first.start, name];
    [log appendFormat:@"· 提前 %ld 分钟 → 闹钟 %02ld:%02ld\n",
        (long)timetable.advanceMinutes, (long)c.hour, (long)c.minute];

    // 3) 写入
    BOOL wrote = [CALAlarmStore addAlarmWithHour:c.hour minute:c.minute title:title];
    [log appendFormat:@"· 写入闹钟：%@\n", wrote ? @"成功" : @"失败"];

    // 4) 提交并等待就绪
    BOOL reloaded = [CALAlarmStore commitChanges];
    [log appendFormat:@"· 触发系统重载：%@\n", reloaded ? @"已发出" : @"失败（未找到守护进程）"];
    if (reloaded) {
        BOOL ready = [CALDaemonReloader waitUntilReadyWithTimeout:6.0];
        [log appendFormat:@"· 等待服务就绪：%@\n", ready ? @"完成" : @"超时（可稍后在时钟 App 查看）"];
    }

    return log;
}

+ (NSInteger)clearManagedAlarms {
    NSInteger n = [CALAlarmStore removeAlarmsWithTitlePrefix:CAL_ALARM_TITLE_PREFIX];
    if (n > 0) [CALAlarmStore commitChanges];
    return n;
}

+ (NSString *)statusSummaryWithTimetable:(CALTimetable *)timetable {
    NSMutableString *s = [NSMutableString string];
    NSDate *tomorrow = CALTomorrow();

    CALCourse *first = [timetable firstCourseForDate:tomorrow];
    if (first) {
        NSDate *t = [CALScheduleEngine alarmTimeForDate:tomorrow timetable:timetable];
        NSDateComponents *c = [[NSCalendar currentCalendar]
            components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:t];
        NSString *name = first.name.length > 0 ? first.name : @"未命名";
        [s appendFormat:@"明天 %@ 第一节 %@ %@\n", CALWeekdayName(tomorrow), first.start, name];
        [s appendFormat:@"应设闹钟 %02ld:%02ld", (long)c.hour, (long)c.minute];
    } else {
        [s appendFormat:@"明天 %@ 无课", CALWeekdayName(tomorrow)];
    }

    NSInteger managed = 0;
    for (CALSystemAlarm *a in [CALAlarmStore allAlarms]) {
        if ([a.title hasPrefix:CAL_ALARM_TITLE_PREFIX]) managed++;
    }
    [s appendFormat:@"\n系统内已有课表闹钟：%ld 个", (long)managed];
    return s;
}

@end

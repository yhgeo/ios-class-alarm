//
//  CALScheduleEngine.h
//  纯计算模块：根据课表算出「某天该设几点的闹钟」。
//  不读写任何文件，无副作用，方便单独验证。
//

#import <Foundation/Foundation.h>
#import "CALTimetable.h"

NS_ASSUME_NONNULL_BEGIN

@interface CALScheduleEngine : NSObject

/// 指定日期应设的闹钟时间；当天无课返回 nil
+ (nullable NSDate *)alarmTimeForDate:(NSDate *)date timetable:(CALTimetable *)timetable;

/// 次日应设的闹钟时间；无课返回 nil
+ (nullable NSDate *)tomorrowAlarmTimeWithTimetable:(CALTimetable *)timetable;

/// 次日第一节课；无课返回 nil
+ (nullable CALCourse *)firstCourseTomorrowWithTimetable:(CALTimetable *)timetable;

/// 次日是否有课
+ (BOOL)hasClassTomorrowWithTimetable:(CALTimetable *)timetable;

@end

NS_ASSUME_NONNULL_END

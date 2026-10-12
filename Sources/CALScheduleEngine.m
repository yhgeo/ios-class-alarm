//
//  CALScheduleEngine.m
//

#import "CALScheduleEngine.h"

@implementation CALScheduleEngine

+ (nullable CALCourse *)firstCourseTomorrowWithTimetable:(CALTimetable *)timetable {
    NSDate *tomorrow = [[NSCalendar currentCalendar] dateByAddingUnit:NSCalendarUnitDay
                                                                value:1
                                                               toDate:[NSDate date]
                                                              options:0];
    if (!tomorrow) tomorrow = [NSDate dateWithTimeIntervalSinceNow:24 * 3600];
    return [timetable firstCourseForDate:tomorrow];
}

+ (BOOL)hasClassTomorrowWithTimetable:(CALTimetable *)timetable {
    return [self firstCourseTomorrowWithTimetable:timetable] != nil;
}

+ (nullable NSDate *)alarmTimeForDate:(NSDate *)date timetable:(CALTimetable *)timetable {
    CALCourse *first = [timetable firstCourseForDate:date];
    if (!first) return nil;

    NSInteger startMinutes = [first startMinutesFromMidnight];
    if (startMinutes == NSNotFound) return nil;

    NSInteger alarmMinutes = startMinutes - timetable.advanceMinutes;
    if (alarmMinutes < 0) alarmMinutes = 0;

    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *dc = [cal components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay)
                                  fromDate:date];
    dc.hour = alarmMinutes / 60;
    dc.minute = alarmMinutes % 60;
    dc.second = 0;
    return [cal dateFromComponents:dc];
}

+ (nullable NSDate *)tomorrowAlarmTimeWithTimetable:(CALTimetable *)timetable {
    NSDate *tomorrow = [[NSCalendar currentCalendar] dateByAddingUnit:NSCalendarUnitDay
                                                                value:1
                                                               toDate:[NSDate date]
                                                              options:0];
    if (!tomorrow) tomorrow = [NSDate dateWithTimeIntervalSinceNow:24 * 3600];
    return [self alarmTimeForDate:tomorrow timetable:timetable];
}

@end

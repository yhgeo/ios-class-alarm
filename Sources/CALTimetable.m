//
//  CALTimetable.m
//

#import "CALTimetable.h"

#pragma mark - 日期工具

static NSDateFormatter *CALDayFormatter(void) {
    static NSDateFormatter *fmt = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fmt = [[NSDateFormatter alloc] init];
        fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        fmt.dateFormat = @"yyyy-MM-dd";
    });
    return fmt;
}

/// 系统 weekday：1=周日 … 7=周六  →  本项目：1=周一 … 7=周日
static NSInteger CALProjectWeekday(NSDate *date) {
    NSInteger sys = [[NSCalendar currentCalendar] component:NSCalendarUnitWeekday fromDate:date];
    return (sys == 1) ? 7 : (sys - 1);
}

#pragma mark - CALCourse

@implementation CALCourse

+ (instancetype)courseWithWeekday:(NSInteger)weekday
                            start:(NSString *)start
                              end:(NSString *)end
                             name:(NSString *)name {
    CALCourse *c = [[CALCourse alloc] init];
    c.weekday = weekday;
    c.start = start;
    c.end = end;
    c.name = name;
    return c;
}

+ (nullable instancetype)courseFromDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;
    NSString *start = dict[@"start"];
    if (![start isKindOfClass:[NSString class]] || start.length == 0) return nil;

    CALCourse *c = [[CALCourse alloc] init];
    c.weekday = [dict[@"weekday"] integerValue];
    c.start = start;
    c.end = [dict[@"end"] isKindOfClass:[NSString class]] ? dict[@"end"] : @"";
    c.name = [dict[@"name"] isKindOfClass:[NSString class]] ? dict[@"name"] : @"";
    return c;
}

- (NSDictionary *)dictionaryValue {
    return @{
        @"weekday": @(self.weekday),
        @"start": self.start ?: @"",
        @"end": self.end ?: @"",
        @"name": self.name ?: @"",
    };
}

- (NSInteger)startMinutesFromMidnight {
    NSArray<NSString *> *parts = [self.start componentsSeparatedByString:@":"];
    if (parts.count < 2) return NSNotFound;
    NSInteger h = [parts[0] integerValue];
    NSInteger m = [parts[1] integerValue];
    if (h < 0 || h > 23 || m < 0 || m > 59) return NSNotFound;
    return h * 60 + m;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<CALCourse 周%ld %@-%@ %@>",
            (long)self.weekday, self.start, self.end, self.name];
}

@end

#pragma mark - CALTimetable

@implementation CALTimetable

+ (instancetype)defaultTimetable {
    CALTimetable *tt = [[CALTimetable alloc] init];
    tt.advanceMinutes = 30;
    tt.courses = @[];
    tt.overrides = @{};
    return tt;
}

+ (nullable instancetype)timetableFromDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;

    CALTimetable *tt = [[CALTimetable alloc] init];
    tt.advanceMinutes = dict[@"advanceMinutes"] ? [dict[@"advanceMinutes"] integerValue] : 30;
    if (tt.advanceMinutes <= 0) tt.advanceMinutes = 30;

    NSMutableArray<CALCourse *> *courses = [NSMutableArray array];
    id rawCourses = dict[@"courses"];
    if ([rawCourses isKindOfClass:[NSArray class]]) {
        for (id item in rawCourses) {
            CALCourse *c = [CALCourse courseFromDictionary:item];
            if (c) [courses addObject:c];
        }
    }
    tt.courses = courses;

    NSMutableDictionary<NSString *, NSArray<CALCourse *> *> *overrides = [NSMutableDictionary dictionary];
    id rawOverrides = dict[@"overrides"];
    if ([rawOverrides isKindOfClass:[NSDictionary class]]) {
        [rawOverrides enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
            if (![key isKindOfClass:[NSString class]]) return;
            NSMutableArray<CALCourse *> *list = [NSMutableArray array];
            if ([value isKindOfClass:[NSArray class]]) {
                for (id item in (NSArray *)value) {
                    CALCourse *c = [CALCourse courseFromDictionary:item];
                    if (c) [list addObject:c];
                }
            }
            overrides[key] = list;
        }];
    }
    tt.overrides = overrides;
    return tt;
}

- (NSDictionary *)dictionaryValue {
    NSMutableArray *courses = [NSMutableArray array];
    for (CALCourse *c in self.courses) [courses addObject:[c dictionaryValue]];

    NSMutableDictionary *overrides = [NSMutableDictionary dictionary];
    [self.overrides enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSArray<CALCourse *> *list, BOOL *stop) {
        NSMutableArray *arr = [NSMutableArray array];
        for (CALCourse *c in list) [arr addObject:[c dictionaryValue]];
        overrides[key] = arr;
    }];

    return @{
        @"version": @1,
        @"advanceMinutes": @(self.advanceMinutes),
        @"courses": courses,
        @"overrides": overrides,
    };
}

- (NSArray<CALCourse *> *)coursesForDate:(NSDate *)date {
    NSString *key = [CALDayFormatter() stringFromDate:date];
    NSArray<CALCourse *> *override = self.overrides[key];
    if (override) return override;   // 覆盖存在（含空数组 = 当天无课）

    NSInteger weekday = CALProjectWeekday(date);
    NSMutableArray<CALCourse *> *result = [NSMutableArray array];
    for (CALCourse *c in self.courses) {
        if (c.weekday == weekday) [result addObject:c];
    }
    return result;
}

- (nullable CALCourse *)firstCourseForDate:(NSDate *)date {
    NSArray<CALCourse *> *list = [self coursesForDate:date];
    CALCourse *best = nil;
    NSInteger bestMinutes = NSNotFound;
    for (CALCourse *c in list) {
        NSInteger m = [c startMinutesFromMidnight];
        if (m == NSNotFound) continue;
        if (bestMinutes == NSNotFound || m < bestMinutes) {
            bestMinutes = m;
            best = c;
        }
    }
    return best;
}

@end

#pragma mark - CALTimetableStore

@implementation CALTimetableStore

+ (instancetype)shared {
    static CALTimetableStore *inst = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        inst = [[CALTimetableStore alloc] init];
        [inst reload];
    });
    return inst;
}

- (NSString *)storagePath {
    // 注意：no-sandbox 下 NSHomeDirectory() 返回 /var/mobile，
    // 所以优先用系统给出的沙箱路径，拿不到再退回固定目录。
    NSArray<NSString *> *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                                    NSUserDomainMask, YES);
    NSString *dir = docs.firstObject;
    if (dir.length == 0) dir = @"/var/mobile/Documents";
    return [dir stringByAppendingPathComponent:@"class-alarm-timetable.json"];
}

- (void)reload {
    CALTimetable *tt = nil;
    NSData *data = [NSData dataWithContentsOfFile:[self storagePath]];
    if (data.length > 0) {
        id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([obj isKindOfClass:[NSDictionary class]]) {
            tt = [CALTimetable timetableFromDictionary:obj];
        }
    }
    _timetable = tt ?: [CALTimetable defaultTimetable];
}

- (void)save {
    NSData *data = [NSJSONSerialization dataWithJSONObject:[self.timetable dictionaryValue]
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:nil];
    if (!data) return;
    NSString *path = [self storagePath];
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    [data writeToFile:path atomically:YES];
}

- (BOOL)importFromJSONData:(NSData *)data error:(NSError **)error {
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![obj isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"CAL" code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"JSON 顶层不是对象"}];
        }
        return NO;
    }
    CALTimetable *tt = [CALTimetable timetableFromDictionary:obj];
    if (!tt) return NO;
    _timetable = tt;
    [self save];
    return YES;
}

@end

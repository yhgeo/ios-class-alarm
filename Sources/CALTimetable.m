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

- (CALCourse *)duplicate {
    return [CALCourse courseWithWeekday:self.weekday
                                  start:self.start
                                    end:self.end
                                   name:self.name];
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

#pragma mark - 存储位置解析

static NSString * const kCALStorageFileName = @"class-alarm-timetable.json";

/// 候选目录，按优先级排列
static NSArray<NSString *> *CALStorageCandidateDirectories(void) {
    NSMutableArray<NSString *> *list = [NSMutableArray array];

    // 1) 系统给的 Documents：沙箱内 → 容器/Documents；no-sandbox → /var/mobile/Documents
    NSArray<NSString *> *docs =
        NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    if (docs.firstObject.length) [list addObject:docs.firstObject];

    // 2) 实测可写（闹钟 plist 就落在这里，已验证过）
    [list addObject:@"/var/mobile/Library/Preferences"];

    // 3) mobile 主目录
    [list addObject:@"/var/mobile/Documents"];

    // 4) 临时目录兜底：重启会丢，但至少 App 能跑
    NSString *tmp = NSTemporaryDirectory();
    if (tmp.length) [list addObject:tmp];

    return list;
}

/// 真写一个探针文件再读回来，确认目录确实可用（只看 fileExists 不够）
static BOOL CALDirectoryIsWritable(NSString *dir) {
    if (dir.length == 0) return NO;
    NSFileManager *fm = [NSFileManager defaultManager];

    if (![fm fileExistsAtPath:dir]) {
        if (![fm createDirectoryAtPath:dir
           withIntermediateDirectories:YES
                            attributes:nil
                                 error:nil]) {
            return NO;
        }
    }

    NSString *probe = [dir stringByAppendingPathComponent:@".cal-write-probe"];
    NSData *payload = [@"ok" dataUsingEncoding:NSUTF8StringEncoding];
    if (![payload writeToFile:probe atomically:YES]) return NO;

    NSData *back = [NSData dataWithContentsOfFile:probe];
    [fm removeItemAtPath:probe error:nil];
    return back.length == payload.length;
}

/// 解析真正使用的存储目录（进程内只算一次）
static NSString *CALStorageDirectory(void) {
    static NSString *dir = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSFileManager *fm = [NSFileManager defaultManager];

        // 1) 已有数据文件的目录优先 —— 免得换了路径读不到旧课表
        for (NSString *c in CALStorageCandidateDirectories()) {
            NSString *f = [c stringByAppendingPathComponent:kCALStorageFileName];
            if ([fm fileExistsAtPath:f]) {
                dir = c;
                break;
            }
        }

        // 2) 否则挑第一个真正可写的
        if (!dir) {
            for (NSString *c in CALStorageCandidateDirectories()) {
                if (CALDirectoryIsWritable(c)) {
                    dir = c;
                    break;
                }
            }
        }

        // 3) 兜底
        if (!dir) dir = NSTemporaryDirectory();
    });
    return dir;
}

#pragma mark - CALTimetableStore

@implementation CALTimetableStore

@synthesize lastSaveOK = _lastSaveOK;
@synthesize lastSaveError = _lastSaveError;

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
    return [CALStorageDirectory() stringByAppendingPathComponent:kCALStorageFileName];
}

- (void)reload {
    CALTimetable *tt = nil;
    NSString *path = [self storagePath];
    NSData *data = [NSData dataWithContentsOfFile:path];

    if (data.length > 0) {
        NSError *jsonError = nil;
        id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if ([obj isKindOfClass:[NSDictionary class]]) {
            tt = [CALTimetable timetableFromDictionary:obj];
        } else {
            NSLog(@"[CALTimetableStore] 课表 JSON 解析失败：%@",
                  jsonError.localizedDescription ?: @"顶层不是对象");
        }
    }

    _timetable = tt ?: [CALTimetable defaultTimetable];
}

- (BOOL)save {
    NSError *jsonError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:[self.timetable dictionaryValue]
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:&jsonError];
    if (!data) {
        _lastSaveOK = NO;
        _lastSaveError = [jsonError.localizedDescription copy] ?: @"JSON 序列化失败";
        return NO;
    }

    NSString *path = [self storagePath];
    NSString *dir = [path stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    NSError *writeError = nil;
    BOOL ok = [data writeToFile:path options:NSDataWritingAtomic error:&writeError];

    if (ok) {
        // 回读校验：有些路径会「假装」写入成功
        NSData *back = [NSData dataWithContentsOfFile:path];
        ok = (back.length == data.length);
        if (!ok) _lastSaveError = @"写入后回读校验失败（长度不一致）";
    } else {
        _lastSaveError = [writeError.localizedDescription copy] ?: @"写入失败";
    }

    _lastSaveOK = ok;
    if (ok) _lastSaveError = nil;
    return ok;
}

- (NSString *)storageDiagnostics {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *path = [self storagePath];
    NSString *dir = [path stringByDeletingLastPathComponent];

    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"目录：%@\n", dir];
    [s appendFormat:@"可写：%@\n", CALDirectoryIsWritable(dir) ? @"是" : @"否"];

    if ([fm fileExistsAtPath:path]) {
        NSDictionary *attr = [fm attributesOfItemAtPath:path error:nil];
        [s appendFormat:@"文件：%@（%llu 字节）\n", kCALStorageFileName,
                         [attr[NSFileSize] unsignedLongLongValue]];
    } else {
        [s appendString:@"文件：不存在\n"];
    }

    [s appendFormat:@"最近保存：%@", _lastSaveOK ? @"成功" : @"未成功"];
    if (_lastSaveError.length) [s appendFormat:@"（%@）", _lastSaveError];
    return s;
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
    return [self save];
}

@end

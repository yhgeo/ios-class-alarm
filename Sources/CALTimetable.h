//
//  CALTimetable.h
//  课表数据模型 + 持久化。
//  本模块不关心闹钟，只负责「课表长什么样」和「存哪里」。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - 单节课程

@interface CALCourse : NSObject

@property (nonatomic) NSInteger weekday;      ///< 1=周一 … 7=周日
@property (nonatomic, copy) NSString *start;  ///< "08:00"
@property (nonatomic, copy) NSString *end;    ///< "09:40"
@property (nonatomic, copy) NSString *name;

+ (instancetype)courseWithWeekday:(NSInteger)weekday
                            start:(NSString *)start
                              end:(NSString *)end
                             name:(NSString *)name;

+ (nullable instancetype)courseFromDictionary:(NSDictionary *)dict;
- (NSDictionary *)dictionaryValue;

/// "08:00" → 从零点起的分钟数；解析失败返回 NSNotFound
- (NSInteger)startMinutesFromMidnight;

@end

#pragma mark - 整份课表

@interface CALTimetable : NSObject

/// 提前量（分钟），闹钟 = 第一节课开始时间 − 该值
@property (nonatomic) NSInteger advanceMinutes;

/// 常规周课表
@property (nonatomic, strong) NSArray<CALCourse *> *courses;

/// 指定日期覆盖："2026-10-13" → 当天课程；空数组表示当天无课
@property (nonatomic, strong) NSDictionary<NSString *, NSArray<CALCourse *> *> *overrides;

+ (instancetype)defaultTimetable;
+ (nullable instancetype)timetableFromDictionary:(NSDictionary *)dict;
- (NSDictionary *)dictionaryValue;

/// 取某天实际生效的课程（override 优先于常规周课表）
- (NSArray<CALCourse *> *)coursesForDate:(NSDate *)date;

/// 取某天最早一节课；无课返回 nil
- (nullable CALCourse *)firstCourseForDate:(NSDate *)date;

@end

#pragma mark - 持久化

@interface CALTimetableStore : NSObject

@property (nonatomic, strong, readonly) CALTimetable *timetable;

+ (instancetype)shared;

- (void)reload;

/// 落盘。返回是否成功 —— 内部含「写后回读校验」，不只看 writeToFile 的返回值。
- (BOOL)save;

/// 数据文件位置
- (NSString *)storagePath;

/// 存储自检摘要（路径 / 可写性 / 文件大小 / 上次保存结果），供界面显示
- (NSString *)storageDiagnostics;

/// 最近一次保存是否成功
@property (nonatomic, readonly) BOOL lastSaveOK;

/// 最近一次保存的失败原因；成功时为 nil
@property (nonatomic, readonly, copy, nullable) NSString *lastSaveError;

/// 用远程 JSON 覆盖本地课表；失败返回 NO 并填充 error
- (BOOL)importFromJSONData:(NSData *)data error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

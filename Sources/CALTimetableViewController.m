//
//  CALTimetableViewController.m
//
//  两个平级页面，用导航栏的分段控件切换：
//    · 每周课表   —— courses，按星期分组（常规周课表）
//    · 自定义课表 —— overrides，按日期分组（某天单独安排的课）
//
//  两者互不干扰：自定义课表里某天的安排优先于常规周课表。
//  提前量不在这里，已挪到「设置」页。
//

#import "CALTimetableViewController.h"
#import "CALCourseEditorViewController.h"
#import "CALTimetable.h"

static NSString * const kCourseCellID = @"CALCourseCell";

typedef NS_ENUM(NSInteger, CALTimetableMode) {
    CALTimetableModeWeekly = 0,   // 每周课表
    CALTimetableModeCustom = 1,   // 自定义课表
};

#pragma mark - 工具

static NSArray<NSString *> *CALWeekdayNames(void) {
    static NSArray<NSString *> *names = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @[@"周一", @"周二", @"周三", @"周四", @"周五", @"周六", @"周日"];
    });
    return names;
}

static NSDateFormatter *CALDayKeyFormatter(void) {
    static NSDateFormatter *fmt = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fmt = [[NSDateFormatter alloc] init];
        fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        fmt.dateFormat = @"yyyy-MM-dd";
    });
    return fmt;
}

/// "2026-10-13" → "周二"
static NSString *CALWeekdayNameForDateKey(NSString *key) {
    NSDate *d = [CALDayKeyFormatter() dateFromString:key];
    if (!d) return @"";
    NSInteger sys = [[NSCalendar currentCalendar] component:NSCalendarUnitWeekday fromDate:d];
    NSArray<NSString *> *names = @[@"周日", @"周一", @"周二", @"周三", @"周四", @"周五", @"周六"];
    if (sys < 1 || sys > 7) return @"";
    return names[sys - 1];
}

#pragma mark -

@interface CALTimetableViewController () <UITableViewDataSource, UITableViewDelegate,
                                          CALCourseEditorDelegate>
@property (nonatomic, strong) UISegmentedControl *modeControl;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic) CALTimetableMode mode;

/// 每周课表用：有课的星期（升序）
@property (nonatomic, strong) NSArray<NSNumber *> *activeWeekdays;
/// 自定义课表用：有安排的日期（升序）
@property (nonatomic, strong) NSArray<NSString *> *overrideDates;

/// 当前编辑操作要写入的日期（自定义课表用）
@property (nonatomic, copy, nullable) NSString *pendingDateKey;
@end

@implementation CALTimetableViewController

#pragma mark - 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.mode = CALTimetableModeWeekly;

    [self buildUI];
    [self reloadData];
}

#pragma mark - UI

- (void)buildUI {
    self.modeControl = [[UISegmentedControl alloc] initWithItems:@[@"每周课表", @"自定义课表"]];
    self.modeControl.selectedSegmentIndex = 0;
    [self.modeControl addTarget:self
                         action:@selector(onModeChanged)
               forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = self.modeControl;

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds
                                                  style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kCourseCellID];
    [self.view addSubview:self.tableView];

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                      target:self
                                                      action:@selector(onAdd)];
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self
                                                      action:@selector(onDone)];
}

#pragma mark - 数据

- (CALTimetable *)timetable {
    return [CALTimetableStore shared].timetable;
}

- (void)reloadData {
    // 每周课表：有课的星期
    NSMutableOrderedSet<NSNumber *> *set = [NSMutableOrderedSet orderedSet];
    for (CALCourse *c in self.timetable.courses) {
        if (c.weekday >= 1 && c.weekday <= 7) [set addObject:@(c.weekday)];
    }
    self.activeWeekdays = [set.array sortedArrayUsingSelector:@selector(compare:)];

    // 自定义课表：有安排的日期（日期字符串的字典序即时间序）
    self.overrideDates = [self.timetable.overrides.allKeys
                             sortedArrayUsingSelector:@selector(compare:)];

    [self.tableView reloadData];
}

/// 当前模式下第 section 段的课程（已按开始时间排序）
- (NSArray<CALCourse *> *)coursesInSection:(NSInteger)section {
    if (section < 0) return @[];

    if (self.mode == CALTimetableModeWeekly) {
        if (section >= (NSInteger)self.activeWeekdays.count) return @[];
        NSInteger weekday = [self.activeWeekdays[section] integerValue];
        NSMutableArray<CALCourse *> *arr = [NSMutableArray array];
        for (CALCourse *c in self.timetable.courses) {
            if (c.weekday == weekday) [arr addObject:c];
        }
        [arr sortUsingComparator:^NSComparisonResult(CALCourse *a, CALCourse *b) {
            return [a.start compare:b.start];
        }];
        return arr;
    }

    if (section >= (NSInteger)self.overrideDates.count) return @[];
    NSString *key = self.overrideDates[section];
    NSArray<CALCourse *> *list = self.timetable.overrides[key] ?: @[];
    return [list sortedArrayUsingComparator:^NSComparisonResult(CALCourse *a, CALCourse *b) {
        return [a.start compare:b.start];
    }];
}

- (nullable CALCourse *)courseAtIndexPath:(NSIndexPath *)indexPath {
    NSArray<CALCourse *> *list = [self coursesInSection:indexPath.section];
    if (indexPath.row < 0 || indexPath.row >= (NSInteger)list.count) return nil;
    return list[indexPath.row];
}

/// 自定义模式下，该行是否为「当天无课」的占位
- (BOOL)isPlaceholderRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.mode != CALTimetableModeCustom) return NO;
    return indexPath.row >= (NSInteger)[self coursesInSection:indexPath.section].count;
}

/// 落盘；失败就把原因摊开
- (void)saveAndReport {
    CALTimetableStore *store = [CALTimetableStore shared];
    if ([store save]) return;

    UIAlertController *ac =
        [UIAlertController alertControllerWithTitle:@"保存失败"
                                            message:[store storageDiagnostics]
                                     preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"好"
                                           style:UIAlertActionStyleDefault
                                         handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.mode == CALTimetableModeWeekly
               ? (NSInteger)self.activeWeekdays.count
               : (NSInteger)self.overrideDates.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSInteger count = (NSInteger)[self coursesInSection:section].count;
    // 自定义课表里某天可能一节课都没有（停课）—— 给一行占位，好让用户能操作
    if (self.mode == CALTimetableModeCustom) return count > 0 ? count : 1;
    return count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCourseCellID
                                                            forIndexPath:indexPath];

    if ([self isPlaceholderRowAtIndexPath:indexPath]) {
        cell.textLabel.text = @"当天无课";
        cell.detailTextLabel.text = @"左滑恢复常规课表";
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    CALCourse *c = [self courseAtIndexPath:indexPath];
    cell.textLabel.text = c.name.length ? c.name : @"未命名";
    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ - %@",
                                 c.start ?: @"", (c.end.length ? c.end : @"")];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (nullable NSString *)tableView:(UITableView *)tableView
         titleForHeaderInSection:(NSInteger)section {
    NSUInteger count = [self coursesInSection:section].count;

    if (self.mode == CALTimetableModeWeekly) {
        if (section >= (NSInteger)self.activeWeekdays.count) return nil;
        NSInteger weekday = [self.activeWeekdays[section] integerValue];
        return [NSString stringWithFormat:@"%@（%lu 节）",
                CALWeekdayNames()[weekday - 1], (unsigned long)count];
    }

    if (section >= (NSInteger)self.overrideDates.count) return nil;
    NSString *key = self.overrideDates[section];
    if (count == 0) {
        return [NSString stringWithFormat:@"%@ %@ · 停课", key, CALWeekdayNameForDateKey(key)];
    }
    return [NSString stringWithFormat:@"%@ %@（%lu 节）",
            key, CALWeekdayNameForDateKey(key), (unsigned long)count];
}

- (nullable NSString *)tableView:(UITableView *)tableView
         titleForFooterInSection:(NSInteger)section {
    if (section != 0) return nil;

    if (self.mode == CALTimetableModeWeekly) {
        if (self.timetable.courses.count == 0) {
            return @"还没有课程。点右上角「+」添加，或到「设置」载入示例课表。";
        }
        return @"闹钟时间 = 当天第一节课开始时间 − 提前量（在「设置」里改）";
    }

    if (self.timetable.overrides.count == 0) {
        return @"还没有自定义课表。点右上角「+」为某一天单独排课，"
                "也可以从「导入课表」批量导入。";
    }
    return @"这里的安排优先于「每周课表」，只影响所填的那一天。";
}

#pragma mark - 编辑

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView
        commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
         forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;

    CALTimetableStore *store = [CALTimetableStore shared];

    if (self.mode == CALTimetableModeWeekly) {
        CALCourse *target = [self courseAtIndexPath:indexPath];
        if (!target) return;
        NSMutableArray<CALCourse *> *list = [store.timetable.courses mutableCopy];
        [list removeObjectIdenticalTo:target];
        store.timetable.courses = list;

    } else {
        if (indexPath.section >= (NSInteger)self.overrideDates.count) return;
        NSString *key = self.overrideDates[indexPath.section];
        NSMutableDictionary *ov = [store.timetable.overrides mutableCopy]
                                      ?: [NSMutableDictionary dictionary];

        if ([self isPlaceholderRowAtIndexPath:indexPath]) {
            // 占位行（当天无课）→ 删掉这天的自定义，恢复常规课表
            [ov removeObjectForKey:key];
        } else {
            CALCourse *target = [self courseAtIndexPath:indexPath];
            if (!target) return;
            NSMutableArray<CALCourse *> *list = [ov[key] mutableCopy];
            [list removeObjectIdenticalTo:target];
            ov[key] = list;   // 删空了就成空数组 = 当天停课
        }
        store.timetable.overrides = ov;
    }

    [self saveAndReport];
    [self reloadData];
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ([self isPlaceholderRowAtIndexPath:indexPath]) return;

    CALCourse *c = [self courseAtIndexPath:indexPath];
    if (!c) return;

    if (self.mode == CALTimetableModeCustom &&
        indexPath.section < (NSInteger)self.overrideDates.count) {
        self.pendingDateKey = self.overrideDates[indexPath.section];
    }
    [self presentEditorForCourse:c];
}

#pragma mark - 动作

- (void)onModeChanged {
    self.mode = (self.modeControl.selectedSegmentIndex == 0)
                    ? CALTimetableModeWeekly
                    : CALTimetableModeCustom;
    self.pendingDateKey = nil;
    [self reloadData];
}

- (void)onDone {
    // 从 Home push 进来时 pop；若是被 present 出来的，则 dismiss
    UINavigationController *nav = self.navigationController;
    if (nav && nav.viewControllers.count > 1) {
        [nav popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)onAdd {
    if (self.mode == CALTimetableModeWeekly) {
        self.pendingDateKey = nil;
        [self presentEditorForCourse:nil];
        return;
    }
    [self promptDateThenAdd];
}

/// 自定义课表：先问哪天，再进编辑表单
- (void)promptDateThenAdd {
    NSString *today = [CALDayKeyFormatter() stringFromDate:[NSDate date]];

    UIAlertController *ac =
        [UIAlertController alertControllerWithTitle:@"为哪一天排课？"
                                            message:@"按 YYYY-MM-DD 填写，例如 2026-10-13"
                                     preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = today;
        tf.placeholder = @"2026-10-13";
        tf.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [ac addAction:[UIAlertAction actionWithTitle:@"取消"
                                           style:UIAlertActionStyleCancel
                                         handler:nil]];

    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"下一步"
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *action) {
        NSString *key = [ac.textFields.firstObject.text
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

        if (![CALDayKeyFormatter() dateFromString:key]) {
            [weakSelf alertWithTitle:@"日期格式不对"
                             message:@"请按 YYYY-MM-DD 填写，例如 2026-10-13。"];
            return;
        }
        weakSelf.pendingDateKey = key;
        [weakSelf presentEditorForCourse:nil];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)presentEditorForCourse:(nullable CALCourse *)course {
    CALCourseEditorViewController *editor = [[CALCourseEditorViewController alloc] init];
    editor.delegate = self;
    editor.editingCourse = course;
    editor.hidesWeekdayField = (self.mode == CALTimetableModeCustom);

    if (!course) {
        editor.defaultWeekday = self.activeWeekdays.count > 0
                                    ? [self.activeWeekdays.firstObject integerValue]
                                    : 1;
    }
    [self.navigationController pushViewController:editor animated:YES];
}

- (void)alertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *ac =
        [UIAlertController alertControllerWithTitle:title
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"好"
                                           style:UIAlertActionStyleDefault
                                         handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

#pragma mark - CALCourseEditorDelegate

- (void)courseEditor:(CALCourseEditorViewController *)editor
 didFinishWithCourse:(CALCourse *)course {
    CALTimetableStore *store = [CALTimetableStore shared];

    if (self.mode == CALTimetableModeWeekly) {
        if (!editor.editingCourse) {
            NSMutableArray<CALCourse *> *list = [store.timetable.courses mutableCopy];
            [list addObject:course];
            store.timetable.courses = list;
        }
        // 编辑场景是就地改原对象，落盘即可

    } else if (self.pendingDateKey.length > 0) {
        NSString *key = self.pendingDateKey;
        NSMutableDictionary *ov = [store.timetable.overrides mutableCopy]
                                      ?: [NSMutableDictionary dictionary];
        NSMutableArray<CALCourse *> *list = ov[key] ? [ov[key] mutableCopy]
                                                    : [NSMutableArray array];
        if (!editor.editingCourse) [list addObject:course];
        ov[key] = list;
        store.timetable.overrides = ov;
    }

    [self saveAndReport];
    [self.navigationController popViewControllerAnimated:YES];
    [self reloadData];
}

- (void)courseEditorDidCancel:(CALCourseEditorViewController *)editor {
    [self.navigationController popViewControllerAnimated:YES];
}

@end

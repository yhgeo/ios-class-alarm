//
//  CALOverrideViewController.m
//
//  交互：
//    选日期 → 看到当天实际课程（常规 or 已覆盖）
//    「+」添加课程 —— 首次调整会以当天常规课表为底，不会把别的课弄丢
//    左滑删除 / 点行编辑
//    「设为停课」→ overrides[日期] = []（空数组表示当天无课）
//    「恢复常规」→ 删掉该日期的 override
//

#import "CALOverrideViewController.h"
#import "CALCourseEditorViewController.h"
#import "CALTimetable.h"
#import "CALPaddedLabel.h"

static NSString * const kCellID = @"CALOverrideCell";

#pragma mark - 布局常量

static const CGFloat kMargin  = 16.0;
static const CGFloat kButtonH = 44.0;
static const CGFloat kCorner  = 12.0;
static const CGFloat kGap     = 12.0;

#pragma mark - 工具

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

/// 系统 weekday：1=周日 … 7=周六  →  本项目：1=周一 … 7=周日
static NSInteger CALWeekdayForDate(NSDate *date) {
    NSInteger sys = [[NSCalendar currentCalendar] component:NSCalendarUnitWeekday fromDate:date];
    return (sys == 1) ? 7 : (sys - 1);
}

#pragma mark -

@interface CALOverrideViewController () <UITableViewDataSource, UITableViewDelegate,
                                         CALCourseEditorDelegate>
@property (nonatomic, strong) UIDatePicker *datePicker;
@property (nonatomic, strong) CALPaddedLabel *statusLabel;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIButton *dayOffButton;
@property (nonatomic, strong) UIButton *resetButton;
@end

@implementation CALOverrideViewController

#pragma mark - 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"临时调整";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    [self buildUI];
    [self reloadData];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutContent];
}

#pragma mark - UI

- (void)buildUI {
    self.datePicker = [[UIDatePicker alloc] init];
    self.datePicker.datePickerMode = UIDatePickerModeDate;
    self.datePicker.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    if (@available(iOS 14.0, *)) {
        self.datePicker.preferredDatePickerStyle = UIDatePickerStyleCompact;
    }
    [self.datePicker addTarget:self
                        action:@selector(onDateChanged)
              forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.datePicker];

    self.statusLabel = [[CALPaddedLabel alloc] init];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.font = [UIFont systemFontOfSize:14];
    self.statusLabel.padding = UIEdgeInsetsMake(12, 12, 12, 12);
    self.statusLabel.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.statusLabel.layer.cornerRadius = kCorner;
    self.statusLabel.clipsToBounds = YES;
    [self.view addSubview:self.statusLabel];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero
                                                  style:UITableViewStyleInsetGrouped];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kCellID];
    [self.view addSubview:self.tableView];

    self.dayOffButton = [self makeButton:@"设为停课" selector:@selector(onDayOff)];
    self.resetButton  = [self makeButton:@"恢复常规课表" selector:@selector(onReset)];
    [self.view addSubview:self.dayOffButton];
    [self.view addSubview:self.resetButton];

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                      target:self
                                                      action:@selector(onAdd)];
}

- (UIButton *)makeButton:(NSString *)title selector:(SEL)selector {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    b.backgroundColor = [UIColor secondarySystemBackgroundColor];
    b.layer.cornerRadius = kCorner;
    [b addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)layoutContent {
    UIEdgeInsets inset = self.view.safeAreaInsets;
    CGFloat w  = self.view.bounds.size.width;
    CGFloat x  = kMargin;
    CGFloat cw = w - kMargin * 2;
    CGFloat y  = inset.top + 12;

    self.datePicker.frame = CGRectMake(x, y, cw, 40);
    y += 40 + kGap;

    CGSize fit = [self.statusLabel sizeThatFits:CGSizeMake(cw, CGFLOAT_MAX)];
    self.statusLabel.frame = CGRectMake(x, y, cw, ceil(fit.height));
    y = CGRectGetMaxY(self.statusLabel.frame) + kGap;

    CGFloat buttonTop = self.view.bounds.size.height - inset.bottom - kGap - kButtonH;
    self.tableView.frame = CGRectMake(0, y, w, MAX(60.0, buttonTop - kGap - y));

    CGFloat halfW = (cw - kGap) / 2.0;
    self.dayOffButton.frame = CGRectMake(x, buttonTop, halfW, kButtonH);
    self.resetButton.frame  = CGRectMake(x + halfW + kGap, buttonTop, halfW, kButtonH);
}

#pragma mark - 数据

- (CALTimetable *)timetable {
    return [CALTimetableStore shared].timetable;
}

- (NSString *)dateKey {
    return [CALDayKeyFormatter() stringFromDate:self.datePicker.date];
}

/// 该日期是否已有覆盖（含「空数组 = 停课」）
- (BOOL)hasOverride {
    return self.timetable.overrides[[self dateKey]] != nil;
}

/// 当天实际生效的课程，按开始时间排序
- (NSArray<CALCourse *> *)sortedCourses {
    NSArray<CALCourse *> *list = [self.timetable coursesForDate:self.datePicker.date];
    return [list sortedArrayUsingComparator:^NSComparisonResult(CALCourse *a, CALCourse *b) {
        return [a.start compare:b.start];
    }];
}

/// 从「常规周课表」取出该日期对应的课程副本（改副本不影响常规课表）
- (NSMutableArray<CALCourse *> *)copiedRegularCourses {
    NSInteger weekday = CALWeekdayForDate(self.datePicker.date);
    NSMutableArray<CALCourse *> *list = [NSMutableArray array];
    for (CALCourse *c in self.timetable.courses) {
        if (c.weekday == weekday) [list addObject:[c duplicate]];
    }
    return list;
}

- (void)reloadData {
    NSString *key = [self dateKey];
    NSArray<CALCourse *> *list = [self sortedCourses];
    BOOL has = [self hasOverride];

    if (has && list.count == 0) {
        self.statusLabel.text = [NSString stringWithFormat:@"%@ 已设为停课（当天无课）", key];
    } else if (has) {
        self.statusLabel.text = [NSString stringWithFormat:@"%@ 已临时调整，共 %lu 节",
                                 key, (unsigned long)list.count];
    } else {
        self.statusLabel.text = [NSString stringWithFormat:@"%@ 使用常规课表，共 %lu 节",
                                 key, (unsigned long)list.count];
    }

    [self.tableView reloadData];
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

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[self sortedCourses].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellID
                                                            forIndexPath:indexPath];
    CALCourse *c = [self sortedCourses][indexPath.row];
    cell.textLabel.text = c.name.length ? c.name : @"未命名";
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ - %@",
                                 c.start ?: @"", (c.end.length ? c.end : @"")];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (nullable NSString *)tableView:(UITableView *)tableView
         titleForHeaderInSection:(NSInteger)section {
    return @"当天课程";
}

- (nullable NSString *)tableView:(UITableView *)tableView
         titleForFooterInSection:(NSInteger)section {
    if ([self sortedCourses].count == 0) {
        return @"当天没有课程。点右上角「+」添加，或点下方「恢复常规课表」。";
    }
    return @"点一行编辑，左滑删除。改动只影响这一天。";
}

#pragma mark - 编辑

- (void)tableView:(UITableView *)tableView
        commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
         forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;

    CALCourse *target = [self sortedCourses][indexPath.row];
    if (!target) return;

    NSMutableDictionary *ov = [self.timetable.overrides mutableCopy]
                                  ?: [NSMutableDictionary dictionary];
    NSString *key = [self dateKey];
    NSMutableArray<CALCourse *> *list = ov[key] ? [ov[key] mutableCopy]
                                                : [self copiedRegularCourses];
    [list removeObjectIdenticalTo:target];

    ov[key] = list;
    self.timetable.overrides = ov;
    [self saveAndReport];
    [self reloadData];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    CALCourse *c = [self sortedCourses][indexPath.row];
    if (c) [self presentEditorForCourse:c];
}

#pragma mark - 动作

- (void)onDateChanged {
    [self reloadData];
}

- (void)onAdd {
    [self presentEditorForCourse:nil];
}

- (void)presentEditorForCourse:(nullable CALCourse *)course {
    CALCourseEditorViewController *editor = [[CALCourseEditorViewController alloc] init];
    editor.delegate = self;
    editor.hidesWeekdayField = YES;   // 按日期覆盖，星期无意义
    editor.editingCourse = course;
    editor.defaultWeekday = CALWeekdayForDate(self.datePicker.date);
    [self.navigationController pushViewController:editor animated:YES];
}

- (void)onDayOff {
    NSMutableDictionary *ov = [self.timetable.overrides mutableCopy]
                                  ?: [NSMutableDictionary dictionary];
    ov[[self dateKey]] = @[];   // 空数组 = 当天无课
    self.timetable.overrides = ov;
    [self saveAndReport];
    [self reloadData];
}

- (void)onReset {
    if (![self hasOverride]) {
        [self reloadData];
        return;
    }
    NSMutableDictionary *ov = [self.timetable.overrides mutableCopy];
    [ov removeObjectForKey:[self dateKey]];
    self.timetable.overrides = ov;
    [self saveAndReport];
    [self reloadData];
}

#pragma mark - CALCourseEditorDelegate

- (void)courseEditor:(CALCourseEditorViewController *)editor
 didFinishWithCourse:(CALCourse *)course {
    NSString *key = [self dateKey];
    NSMutableDictionary *ov = [self.timetable.overrides mutableCopy]
                                  ?: [NSMutableDictionary dictionary];

    NSMutableArray<CALCourse *> *list;
    if (ov[key]) {
        list = [ov[key] mutableCopy];
    } else {
        // 首次调整这一天：以常规课表为底，避免「加一节 → 其它课全没了」
        list = [self copiedRegularCourses];
    }

    // 编辑场景是就地改原对象（见 CALCourseEditorViewController.onSave），
    // 对象已在 list 里，无需再插一次
    if (!editor.editingCourse) [list addObject:course];

    ov[key] = list;
    self.timetable.overrides = ov;
    [self saveAndReport];

    [self.navigationController popViewControllerAnimated:YES];
    [self reloadData];
}

- (void)courseEditorDidCancel:(CALCourseEditorViewController *)editor {
    [self.navigationController popViewControllerAnimated:YES];
}

@end

//
//  CALTimetableViewController.m
//
//  结构：
//    section 0        —— 「闹钟设置」，一行，改提前量
//    section 1..N     —— 有课的星期（升序），每行一节课
//

#import "CALTimetableViewController.h"
#import "CALCourseEditorViewController.h"
#import "CALTimetable.h"

static NSString * const kCourseCellID  = @"CALCourseCell";
static NSString * const kSettingCellID = @"CALSettingCell";

/// section 布局：0 = 闹钟设置，1 起 = 有课的星期
static const NSInteger kSettingSection      = 0;
static const NSInteger kFirstWeekdaySection = 1;

static NSArray<NSString *> *CALWeekdayNames(void) {
    static NSArray<NSString *> *names = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @[@"周一", @"周二", @"周三", @"周四", @"周五", @"周六", @"周日"];
    });
    return names;
}

@interface CALTimetableViewController () <UITableViewDataSource, UITableViewDelegate,
                                          CALCourseEditorDelegate>
@property (nonatomic, strong) UITableView *tableView;
/// 当前有课的星期（升序），缓存一份，避免每次算
@property (nonatomic, strong) NSArray<NSNumber *> *activeWeekdays;
@end

@implementation CALTimetableViewController

#pragma mark - 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"编辑课表";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds
                                                  style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kCourseCellID];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kSettingCellID];
    [self.view addSubview:self.tableView];

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                      target:self
                                                      action:@selector(onAdd)];
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self
                                                      action:@selector(onDone)];

    [self reloadData];
}

#pragma mark - 数据

- (CALTimetable *)timetable {
    return [CALTimetableStore shared].timetable;
}

- (void)reloadData {
    NSMutableOrderedSet<NSNumber *> *set = [NSMutableOrderedSet orderedSet];
    for (CALCourse *c in self.timetable.courses) {
        if (c.weekday >= 1 && c.weekday <= 7) [set addObject:@(c.weekday)];
    }
    self.activeWeekdays = [set.array sortedArrayUsingSelector:@selector(compare:)];
    [self.tableView reloadData];
}

/// 落盘；失败时把原因摊开给用户看，不静默吞掉
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

/// 某个星期下的课程，按开始时间升序
- (NSArray<CALCourse *> *)coursesForWeekday:(NSInteger)weekday {
    NSMutableArray<CALCourse *> *arr = [NSMutableArray array];
    for (CALCourse *c in self.timetable.courses) {
        if (c.weekday == weekday) [arr addObject:c];
    }
    [arr sortUsingComparator:^NSComparisonResult(CALCourse *a, CALCourse *b) {
        return [a.start compare:b.start];
    }];
    return arr;
}

- (NSInteger)weekdayForSection:(NSInteger)section {
    NSInteger idx = section - kFirstWeekdaySection;
    if (idx < 0 || idx >= (NSInteger)self.activeWeekdays.count) return 0;
    return [self.activeWeekdays[idx] integerValue];
}

- (nullable CALCourse *)courseAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger weekday = [self weekdayForSection:indexPath.section];
    if (weekday == 0) return nil;
    NSArray<CALCourse *> *list = [self coursesForWeekday:weekday];
    if (indexPath.row < 0 || indexPath.row >= (NSInteger)list.count) return nil;
    return list[indexPath.row];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return kFirstWeekdaySection + (NSInteger)self.activeWeekdays.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == kSettingSection) return 1;   // 提前量
    NSInteger weekday = [self weekdayForSection:section];
    if (weekday == 0) return 0;
    return (NSInteger)[self coursesForWeekday:weekday].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == kSettingSection) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kSettingCellID
                                                                forIndexPath:indexPath];
        cell.textLabel.text = @"提前提醒";
        cell.detailTextLabel.text =
            [NSString stringWithFormat:@"%ld 分钟", (long)self.timetable.advanceMinutes];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCourseCellID
                                                            forIndexPath:indexPath];
    CALCourse *c = [self courseAtIndexPath:indexPath];
    cell.textLabel.text = c.name.length ? c.name : @"未命名";
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ - %@",
                                 c.start ?: @"", (c.end.length ? c.end : @"")];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (nullable NSString *)tableView:(UITableView *)tableView
         titleForHeaderInSection:(NSInteger)section {
    if (section == kSettingSection) return @"闹钟设置";
    NSInteger weekday = [self weekdayForSection:section];
    if (weekday == 0) return nil;
    NSUInteger count = [self coursesForWeekday:weekday].count;
    return [NSString stringWithFormat:@"%@（%lu 节）",
            CALWeekdayNames()[weekday - 1], (unsigned long)count];
}

- (nullable NSString *)tableView:(UITableView *)tableView
         titleForFooterInSection:(NSInteger)section {
    if (section != kSettingSection) return nil;
    if (self.timetable.courses.count == 0) {
        return @"还没有课程。点右上角「+」添加，或回上一页载入示例课表。";
    }
    return @"闹钟时间 = 当天第一节课开始时间 − 提前量";
}

#pragma mark - 编辑（左滑删除）

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section >= kFirstWeekdaySection;
}

- (void)tableView:(UITableView *)tableView
        commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
         forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;

    CALCourse *target = [self courseAtIndexPath:indexPath];
    if (!target) return;

    NSMutableArray<CALCourse *> *list = [self.timetable.courses mutableCopy];
    [list removeObjectIdenticalTo:target];
    self.timetable.courses = list;
    [self saveAndReport];
    [self reloadData];
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == kSettingSection) {
        [self promptAdvanceMinutes];
        return;
    }
    CALCourse *c = [self courseAtIndexPath:indexPath];
    if (c) [self presentEditorForCourse:c];
}

#pragma mark - 动作

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
    [self presentEditorForCourse:nil];
}

- (void)presentEditorForCourse:(nullable CALCourse *)course {
    CALCourseEditorViewController *editor = [[CALCourseEditorViewController alloc] init];
    editor.delegate = self;
    editor.editingCourse = course;
    if (!course) {
        // 新增时默认落在已有课表的第一天，没有就用周一
        NSInteger def = self.activeWeekdays.count > 0
                            ? [self.activeWeekdays.firstObject integerValue]
                            : 1;
        editor.defaultWeekday = def;
    }
    [self.navigationController pushViewController:editor animated:YES];
}

- (void)promptAdvanceMinutes {
    NSInteger current = self.timetable.advanceMinutes;
    UIAlertController *ac =
        [UIAlertController alertControllerWithTitle:@"提前提醒"
                                            message:@"闹钟 = 第一节课开始时间 − 提前量（分钟）"
                                     preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.keyboardType = UIKeyboardTypeNumberPad;
        tf.placeholder = @"30";
        tf.text = [NSString stringWithFormat:@"%ld", (long)current];
    }];
    [ac addAction:[UIAlertAction actionWithTitle:@"取消"
                                           style:UIAlertActionStyleCancel
                                         handler:nil]];

    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"保存"
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *action) {
        NSInteger v = [ac.textFields.firstObject.text integerValue];
        if (v <= 0) v = 30;
        if (v > 600) v = 600;
        weakSelf.timetable.advanceMinutes = v;
        [weakSelf saveAndReport];
        [weakSelf reloadData];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

#pragma mark - CALCourseEditorDelegate

- (void)courseEditor:(CALCourseEditorViewController *)editor
 didFinishWithCourse:(CALCourse *)course {
    CALTimetableStore *store = [CALTimetableStore shared];

    if (editor.editingCourse) {
        // 编辑页是就地修改原对象（见 CALCourseEditorViewController.onSave），
        // 这里只需要把改动落盘。
    } else {
        NSMutableArray<CALCourse *> *list = [store.timetable.courses mutableCopy];
        [list addObject:course];
        store.timetable.courses = list;
    }
    [self saveAndReport];

    [self.navigationController popViewControllerAnimated:YES];
    [self reloadData];
}

- (void)courseEditorDidCancel:(CALCourseEditorViewController *)editor {
    [self.navigationController popViewControllerAnimated:YES];
}

@end

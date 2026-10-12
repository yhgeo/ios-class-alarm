//
//  CALHomeViewController.m
//  主界面：显示当前状态，提供「应用」「编辑课表」「载入示例」「清理」四个动作。
//  只调用 CALApplier / CALTimetableStore，不直接碰底层。
//

#import "CALHomeViewController.h"
#import "CALApplier.h"
#import "CALAlarmStore.h"
#import "CALTimetable.h"
#import "CALTimetableViewController.h"

@interface CALHomeViewController ()
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) NSArray<UIButton *> *buttons;
@end

@implementation CALHomeViewController

#pragma mark - 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"课表闹钟";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    [self buildUI];
    [self refreshStatus];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshStatus];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutContent];
}

#pragma mark - UI

- (void)buildUI {
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.font = [UIFont systemFontOfSize:14];
    self.statusLabel.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.statusLabel.layer.cornerRadius = 10;
    self.statusLabel.clipsToBounds = YES;
    [self.view addSubview:self.statusLabel];

    NSArray<NSString *> *titles = @[@"立即应用（设置次日闹钟）", @"编辑课表",
                                    @"载入示例课表", @"清理课表闹钟"];
    NSArray<NSString *> *selectors = @[@"onApply", @"onEditTimetable",
                                       @"onSample", @"onClear"];

    NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
    for (NSUInteger i = 0; i < titles.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        [b setTitle:titles[i] forState:UIControlStateNormal];
        [b setTitleColor:(i == 0 ? [UIColor whiteColor] : [UIColor labelColor])
                forState:UIControlStateNormal];
        b.backgroundColor = (i == 0 ? [UIColor systemBlueColor]
                                    : [UIColor secondarySystemBackgroundColor]);
        b.layer.cornerRadius = 10;
        [b addTarget:self
              action:NSSelectorFromString(selectors[i])
    forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:b];
        [buttons addObject:b];
    }
    self.buttons = buttons;

    self.logView = [[UITextView alloc] init];
    self.logView.editable = NO;
    self.logView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.logView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.logView.layer.cornerRadius = 10;
    self.logView.text = @"准备就绪。";
    [self.view addSubview:self.logView];
}

- (void)layoutContent {
    UIEdgeInsets inset = self.view.safeAreaInsets;
    CGFloat w = self.view.bounds.size.width;
    CGFloat x = 16;
    CGFloat cw = w - x * 2;

    CGFloat y = inset.top + 12;

    // 状态卡片
    self.statusLabel.frame = CGRectMake(x, y, cw, 84);
    y = CGRectGetMaxY(self.statusLabel.frame) + 16;

    // 按钮
    for (UIButton *b in self.buttons) {
        b.frame = CGRectMake(x, y, cw, 46);
        y += 56;
    }

    // 日志区填满剩余空间
    CGFloat logTop = y + 4;
    CGFloat logBottom = self.view.bounds.size.height - inset.bottom - 12;
    CGFloat logHeight = MAX(80, logBottom - logTop);
    self.logView.frame = CGRectMake(x, logTop, cw, logHeight);
}

#pragma mark - 状态

- (void)refreshStatus {
    CALTimetable *tt = [CALTimetableStore shared].timetable;
    NSString *summary = [CALApplier statusSummaryWithTimetable:tt];

    NSMutableString *s = [NSMutableString stringWithFormat:@"\n  %@\n", summary];
    if (tt.courses.count == 0) {
        [s appendString:@"  ⚠️ 课表为空，可点「载入示例课表」体验\n"];
    }
    [s appendString:[NSString stringWithFormat:@"  提前量：%ld 分钟\n", (long)tt.advanceMinutes]];
    self.statusLabel.text = s;
}

#pragma mark - 动作

- (void)onApply {
    self.logView.text = @"执行中…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        CALTimetable *tt = [CALTimetableStore shared].timetable;
        NSString *log = [CALApplier applyTimetable:tt];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.logView.text = log;
            [self refreshStatus];
        });
    });
}

- (void)onEditTimetable {
    CALTimetableViewController *vc = [[CALTimetableViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)onClear {
    self.logView.text = @"清理中…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSInteger n = [CALApplier clearManagedAlarms];
        NSString *msg = [NSString stringWithFormat:@"已清理 %ld 个课表闹钟。\n", (long)n];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.logView.text = msg;
            [self refreshStatus];
        });
    });
}

- (void)onSample {
    UIAlertController *ac =
        [UIAlertController alertControllerWithTitle:@"载入示例课表"
                                            message:@"会覆盖当前课表，确定继续？"
                                     preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"取消"
                                           style:UIAlertActionStyleCancel
                                         handler:nil]];
    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"载入"
                                           style:UIAlertActionStyleDestructive
                                         handler:^(UIAlertAction *action) {
        [weakSelf loadSampleTimetable];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)loadSampleTimetable {
    CALTimetableStore *store = [CALTimetableStore shared];
    store.timetable.advanceMinutes = 30;
    store.timetable.courses = @[
        [CALCourse courseWithWeekday:1 start:@"08:00" end:@"09:40" name:@"高等数学"],
        [CALCourse courseWithWeekday:1 start:@"10:00" end:@"11:40" name:@"大学英语"],
        [CALCourse courseWithWeekday:2 start:@"09:00" end:@"10:40" name:@"线性代数"],
        [CALCourse courseWithWeekday:3 start:@"08:00" end:@"09:40" name:@"数据结构"],
        [CALCourse courseWithWeekday:4 start:@"10:00" end:@"11:40" name:@"操作系统"],
        [CALCourse courseWithWeekday:5 start:@"08:30" end:@"10:10" name:@"计算机网络"],
    ];
    [store save];

    self.logView.text = [NSString stringWithFormat:@"已载入示例课表（6 节课）。\n\n保存位置：\n%@\n",
                         [store storagePath]];
    [self refreshStatus];
}

@end

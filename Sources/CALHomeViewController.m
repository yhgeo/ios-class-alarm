//
//  CALHomeViewController.m
//  主界面：显示当前状态，提供「应用」「清理」「载入示例」三个动作。
//  只调用 CALApplier / CALTimetableStore，不直接碰底层。
//

#import "CALHomeViewController.h"
#import "CALApplier.h"
#import "CALAlarmStore.h"
#import "CALTimetable.h"

@interface CALHomeViewController ()
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UITextView *logView;
@end

@implementation CALHomeViewController

#pragma mark - 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    [self buildUI];
    [self refreshStatus];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshStatus];
}

#pragma mark - UI

- (void)buildUI {
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 60, w - 32, 30)];
    title.text = @"课表闹钟";
    title.font = [UIFont boldSystemFontOfSize:20];
    title.textAlignment = NSTextAlignmentCenter;
    title.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:title];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 100, w - 32, 84)];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.font = [UIFont systemFontOfSize:14];
    self.statusLabel.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.statusLabel.layer.cornerRadius = 10;
    self.statusLabel.clipsToBounds = YES;
    self.statusLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:self.statusLabel];

    NSArray<NSString *> *titles = @[@"立即应用（设置次日闹钟）", @"载入示例课表", @"清理课表闹钟"];
    NSArray<NSString *> *selectors = @[@"onApply", @"onSample", @"onClear"];
    CGFloat y = 198;
    for (NSUInteger i = 0; i < titles.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(16, y, w - 32, 46);
        [b setTitle:titles[i] forState:UIControlStateNormal];
        [b setTitleColor:(i == 0 ? [UIColor whiteColor] : [UIColor labelColor])
                forState:UIControlStateNormal];
        b.backgroundColor = (i == 0 ? [UIColor systemBlueColor]
                                    : [UIColor secondarySystemBackgroundColor]);
        b.layer.cornerRadius = 10;
        b.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        SEL sel = NSSelectorFromString(selectors[i]);
        [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:b];
        y += 56;
    }

    CGFloat logTop = y + 8;
    self.logView = [[UITextView alloc] initWithFrame:CGRectMake(16, logTop, w - 32, h - logTop - 24)];
    self.logView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.logView.editable = NO;
    self.logView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.logView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.logView.layer.cornerRadius = 10;
    self.logView.text = @"准备就绪。";
    [self.view addSubview:self.logView];
}

#pragma mark - 动作

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
    CALTimetable *tt = [CALTimetable defaultTimetable];
    tt.advanceMinutes = 30;
    tt.courses = @[
        [CALCourse courseWithWeekday:1 start:@"08:00" end:@"09:40" name:@"高等数学"],
        [CALCourse courseWithWeekday:1 start:@"10:00" end:@"11:40" name:@"大学英语"],
        [CALCourse courseWithWeekday:2 start:@"09:00" end:@"10:40" name:@"线性代数"],
        [CALCourse courseWithWeekday:3 start:@"08:00" end:@"09:40" name:@"数据结构"],
        [CALCourse courseWithWeekday:4 start:@"10:00" end:@"11:40" name:@"操作系统"],
        [CALCourse courseWithWeekday:5 start:@"08:30" end:@"10:10" name:@"计算机网络"],
    ];
    [CALTimetableStore shared].timetable.courses = tt.courses;
    [CALTimetableStore shared].timetable.advanceMinutes = tt.advanceMinutes;
    [[CALTimetableStore shared] save];

    self.logView.text = [NSString stringWithFormat:@"已载入示例课表（6 节课）。\n\n保存位置：\n%@\n",
                         [[CALTimetableStore shared] storagePath]];
    [self refreshStatus];
}

@end

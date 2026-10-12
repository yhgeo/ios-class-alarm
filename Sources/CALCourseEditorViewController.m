//
//  CALCourseEditorViewController.m
//  布局走 safeAreaInsets，所有控件左右对齐、间距统一。
//

#import "CALCourseEditorViewController.h"

#pragma mark - 布局常量

static const CGFloat kMargin   = 16.0;   // 左右边距
static const CGFloat kLabelH   = 20.0;   // 字段标题高
static const CGFloat kLabelGap = 6.0;    // 标题与控件间距
static const CGFloat kControlH = 44.0;   // 控件高
static const CGFloat kGroupGap = 24.0;   // 字段块之间的间距

#pragma mark - 时间工具

static NSDateFormatter *CALTimeFormatter(void) {
    static NSDateFormatter *fmt = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fmt = [[NSDateFormatter alloc] init];
        fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        fmt.dateFormat = @"HH:mm";
    });
    return fmt;
}

static NSString *CALTimeString(NSDate *date) {
    return [CALTimeFormatter() stringFromDate:date];
}

static NSDate *CALDateFromTimeString(NSString *string) {
    NSDate *d = [CALTimeFormatter() dateFromString:string ?: @""];
    return d ?: [NSDate date];
}

#pragma mark -

@interface CALCourseEditorViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UISegmentedControl *weekdayControl;
@property (nonatomic, strong) UIDatePicker *startPicker;
@property (nonatomic, strong) UIDatePicker *endPicker;
@property (nonatomic, strong) UITextField *nameField;
/// 四个字段标题，顺序：星期 / 开始时间 / 结束时间 / 课程名
@property (nonatomic, strong) NSArray<UILabel *> *fieldLabels;
@end

@implementation CALCourseEditorViewController

#pragma mark - 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = self.editingCourse ? @"编辑课程" : @"新增课程";

    [self buildUI];
    [self fillForm];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutForm];
}

#pragma mark - UI

- (void)buildUI {
    NSArray<NSString *> *titles = @[@"星期", @"开始时间", @"结束时间", @"课程名"];
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    for (NSString *t in titles) {
        UILabel *l = [[UILabel alloc] init];
        l.text = t;
        l.font = [UIFont systemFontOfSize:14];
        l.textColor = [UIColor secondaryLabelColor];
        [self.view addSubview:l];
        [labels addObject:l];
    }
    self.fieldLabels = labels;

    // 星期
    self.weekdayControl = [[UISegmentedControl alloc]
        initWithItems:@[@"一", @"二", @"三", @"四", @"五", @"六", @"日"]];
    self.weekdayControl.selectedSegmentIndex = 0;
    [self.view addSubview:self.weekdayControl];

    // 起止时间
    self.startPicker = [self makeTimePicker];
    self.endPicker   = [self makeTimePicker];
    [self.view addSubview:self.startPicker];
    [self.view addSubview:self.endPicker];

    // 课程名
    self.nameField = [[UITextField alloc] init];
    self.nameField.borderStyle = UITextBorderStyleRoundedRect;
    self.nameField.placeholder = @"例如：高等数学";
    self.nameField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.nameField.returnKeyType = UIReturnKeyDone;
    self.nameField.delegate = self;
    [self.view addSubview:self.nameField];

    // 导航栏按钮
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                      target:self
                                                      action:@selector(onCancel)];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                                                      target:self
                                                      action:@selector(onSave)];
}

- (UIDatePicker *)makeTimePicker {
    UIDatePicker *p = [[UIDatePicker alloc] init];
    p.datePickerMode = UIDatePickerModeTime;
    p.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    p.minuteInterval = 5;
    if (@available(iOS 14.0, *)) {
        p.preferredDatePickerStyle = UIDatePickerStyleCompact;
    }
    return p;
}

/// 按 safeArea 从上往下排，四组字段左右对齐、间距一致
- (void)layoutForm {
    UIEdgeInsets inset = self.view.safeAreaInsets;
    CGFloat w  = self.view.bounds.size.width;
    CGFloat x  = kMargin;
    CGFloat cw = w - kMargin * 2;
    CGFloat y  = inset.top + 20;

    NSArray<UIView *> *controls = @[self.weekdayControl, self.startPicker,
                                    self.endPicker, self.nameField];
    for (NSUInteger i = 0; i < controls.count; i++) {
        self.fieldLabels[i].frame = CGRectMake(x, y, cw, kLabelH);
        y += kLabelH + kLabelGap;
        controls[i].frame = CGRectMake(x, y, cw, kControlH);
        y += kControlH + kGroupGap;
    }
}

#pragma mark - 数据填充

- (void)fillForm {
    CALCourse *c = self.editingCourse;
    if (c) {
        NSInteger idx = MAX(0, MIN(6, c.weekday - 1));
        self.weekdayControl.selectedSegmentIndex = idx;
        self.startPicker.date = CALDateFromTimeString(c.start);
        self.endPicker.date   = CALDateFromTimeString(c.end.length ? c.end : c.start);
        self.nameField.text   = c.name;
    } else {
        NSInteger idx = MAX(0, MIN(6, (self.defaultWeekday > 0 ? self.defaultWeekday : 1) - 1));
        self.weekdayControl.selectedSegmentIndex = idx;
        self.startPicker.date = CALDateFromTimeString(@"08:00");
        self.endPicker.date   = CALDateFromTimeString(@"09:40");
    }
}

#pragma mark - 动作

- (void)onCancel {
    [self.delegate courseEditorDidCancel:self];
}

- (void)onSave {
    NSString *name = [self.nameField.text
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (name.length == 0) name = @"未命名";

    CALCourse *c = self.editingCourse ?: [[CALCourse alloc] init];
    c.weekday = self.weekdayControl.selectedSegmentIndex + 1;
    c.start   = CALTimeString(self.startPicker.date);
    c.end     = CALTimeString(self.endPicker.date);
    c.name    = name;

    [self.delegate courseEditor:self didFinishWithCourse:c];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

@end

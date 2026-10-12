//
//  CALCourseEditorViewController.m
//

#import "CALCourseEditorViewController.h"

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

@interface CALCourseEditorViewController ()
@property (nonatomic, strong) UISegmentedControl *weekdayControl;
@property (nonatomic, strong) UIDatePicker *startPicker;
@property (nonatomic, strong) UIDatePicker *endPicker;
@property (nonatomic, strong) UITextField *nameField;
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

- (void)buildUI {
    CGFloat w = self.view.bounds.size.width;
    CGFloat y = 90;

    // 星期
    [self.view addSubview:[self makeLabel:@"星期" frame:CGRectMake(20, y, 80, 24)]];
    y += 30;
    NSArray<NSString *> *weekdays = @[@"一", @"二", @"三", @"四", @"五", @"六", @"日"];
    self.weekdayControl = [[UISegmentedControl alloc] initWithItems:weekdays];
    self.weekdayControl.frame = CGRectMake(16, y, w - 32, 34);
    self.weekdayControl.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.weekdayControl.selectedSegmentIndex = 0;
    [self.view addSubview:self.weekdayControl];
    y += 50;

    // 开始时间
    [self.view addSubview:[self makeLabel:@"开始时间" frame:CGRectMake(20, y, 120, 24)]];
    y += 30;
    self.startPicker = [self makeTimePicker:CGRectMake(16, y, w - 32, 44)];
    [self.view addSubview:self.startPicker];
    y += 56;

    // 结束时间
    [self.view addSubview:[self makeLabel:@"结束时间" frame:CGRectMake(20, y, 120, 24)]];
    y += 30;
    self.endPicker = [self makeTimePicker:CGRectMake(16, y, w - 32, 44)];
    [self.view addSubview:self.endPicker];
    y += 56;

    // 课程名
    [self.view addSubview:[self makeLabel:@"课程名" frame:CGRectMake(20, y, 120, 24)]];
    y += 30;
    self.nameField = [[UITextField alloc] initWithFrame:CGRectMake(16, y, w - 32, 44)];
    self.nameField.borderStyle = UITextBorderStyleRoundedRect;
    self.nameField.placeholder = @"例如：高等数学";
    self.nameField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
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

- (UILabel *)makeLabel:(NSString *)text frame:(CGRect)frame {
    UILabel *l = [[UILabel alloc] initWithFrame:frame];
    l.text = text;
    l.font = [UIFont systemFontOfSize:14];
    l.textColor = [UIColor secondaryLabelColor];
    return l;
}

- (UIDatePicker *)makeTimePicker:(CGRect)frame {
    UIDatePicker *p = [[UIDatePicker alloc] initWithFrame:frame];
    p.datePickerMode = UIDatePickerModeTime;
    p.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    p.minuteInterval = 5;
    if (@available(iOS 14.0, *)) {
        p.preferredDatePickerStyle = UIDatePickerStyleCompact;
    }
    return p;
}

#pragma mark - 数据填充

- (void)fillForm {
    CALCourse *c = self.editingCourse;
    if (c) {
        NSInteger idx = MAX(0, MIN(6, c.weekday - 1));
        self.weekdayControl.selectedSegmentIndex = idx;
        self.startPicker.date = CALDateFromTimeString(c.start);
        self.endPicker.date = CALDateFromTimeString(c.end.length ? c.end : c.start);
        self.nameField.text = c.name;
    } else {
        NSInteger idx = MAX(0, MIN(6, (self.defaultWeekday > 0 ? self.defaultWeekday : 1) - 1));
        self.weekdayControl.selectedSegmentIndex = idx;
        self.startPicker.date = CALDateFromTimeString(@"08:00");
        self.endPicker.date = CALDateFromTimeString(@"09:40");
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
    c.start = CALTimeString(self.startPicker.date);
    c.end = CALTimeString(self.endPicker.date);
    c.name = name;

    [self.delegate courseEditor:self didFinishWithCourse:c];
}

@end

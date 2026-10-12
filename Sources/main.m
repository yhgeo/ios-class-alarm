//
//  main.m
//  AlarmPoC
//
//  用途：验证在 TrollStore 环境下，能否通过私有框架 MobileTimer
//        （MTAlarmManager / MTAlarm）读写系统「时钟」App 的闹钟。
//
//  该验证是整个「课表闹钟自动化」方案的前提。若此处通过，
//  则后续可完全绕开 iOS 16 快捷指令「无法删除闹钟」的限制。
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

#pragma mark - objc_msgSend 强类型转换
// 私有类在编译期不可见，只能用运行时消息发送，因此需要显式转换函数指针类型。

typedef id   (*Send_Id)(id, SEL);
typedef id   (*Send_Id_Id)(id, SEL, id);
typedef void (*Send_Void_Id)(id, SEL, id);
typedef void (*Send_Void_Bool)(id, SEL, bool);
typedef id   (*Send_Id_UllUll)(id, SEL, unsigned long long, unsigned long long);

static NSString *const kMobileTimerPath =
    @"/System/Library/PrivateFrameworks/MobileTimer.framework/MobileTimer";

#pragma mark - 诊断

/// 读取系统当前所有闹钟，返回可读描述；失败时返回错误说明。
static NSString *DescribeExistingAlarms(id manager) {
    @try {
        id alarms = ((Send_Id)objc_msgSend)(manager, @selector(alarmsSync));
        if (!alarms) {
            return @"(alarmsSync 返回 nil)";
        }
        if ([alarms isKindOfClass:[NSArray class]]) {
            NSArray *arr = (NSArray *)alarms;
            NSMutableString *s = [NSMutableString stringWithFormat:@"共 %lu 个\n", (unsigned long)arr.count];
            for (id a in arr) {
                id title = ((Send_Id)objc_msgSend)(a, @selector(title));
                unsigned long long hour = ((unsigned long long (*)(id, SEL))objc_msgSend)(a, @selector(hour));
                unsigned long long minute = ((unsigned long long (*)(id, SEL))objc_msgSend)(a, @selector(minute));
                bool enabled = ((bool (*)(id, SEL))objc_msgSend)(a, @selector(isEnabled));
                [s appendFormat:@"    %02llu:%02llu  %@  %@\n",
                    hour, minute, enabled ? @"[开]" : @"[关]", title ?: @"(无标题)"];
            }
            return s;
        }
        return [alarms description];
    } @catch (NSException *e) {
        return [NSString stringWithFormat:@"读取异常: %@", e.reason];
    }
}

/// 完整诊断流程：加载框架 → 定位类 → 建实例 → 读旧闹钟 → 建新闹钟 → 写回 → 复读验证
static NSString *RunDiagnostics(void) {
    NSMutableString *out = [NSMutableString string];

    // 1. 加载私有框架
    void *handle = dlopen(kMobileTimerPath.UTF8String, RTLD_NOW);
    if (!handle) {
        const char *err = dlerror();
        [out appendFormat:@"[1] dlopen MobileTimer ........ 失败\n    %s\n", err ? err : "unknown"];
        return out;
    }
    [out appendString:@"[1] dlopen MobileTimer ........ 成功\n"];

    // 2. 定位私有类
    Class mgrCls   = NSClassFromString(@"MTAlarmManager");
    Class alarmCls = NSClassFromString(@"MTAlarm");
    [out appendFormat:@"[2] MTAlarmManager ............. %@\n", mgrCls ? @"找到" : @"缺失"];
    [out appendFormat:@"[3] MTAlarm ................... %@\n", alarmCls ? @"找到" : @"缺失"];
    if (!mgrCls || !alarmCls) {
        [out appendString:@"\n结论：框架存在但类缺失，方案需调整。\n"];
        return out;
    }

    // 3. 建实例（iOS 16 无 +alarmManager 单例，须 alloc/init）
    id manager = nil;
    @try {
        manager = ((Send_Id)objc_msgSend)(((Send_Id)objc_msgSend)(mgrCls, @selector(alloc)), @selector(init));
    } @catch (NSException *e) {
        [out appendFormat:@"[4] manager 实例 .............. 异常: %@\n", e.reason];
        return out;
    }
    [out appendFormat:@"[4] manager 实例 .............. %@\n", manager ? @"创建成功" : @"创建失败"];
    if (!manager) return out;

    // 4. 读旧闹钟（验证 XPC 通道是否打通）
    [out appendString:@"[5] 读取现有闹钟 ..............\n"];
    [out appendFormat:@"    %@\n", DescribeExistingAlarms(manager)];

    // 5. 构造 +5 分钟的一次性闹钟
    NSDate *fire = [NSDate dateWithTimeIntervalSinceNow:300];
    NSDateComponents *c = [[NSCalendar currentCalendar]
        components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:fire];

    id alarm = nil;
    @try {
        alarm = ((Send_Id_UllUll)objc_msgSend)(alarmCls, @selector(alarmWithHour:minute:),
                                               (unsigned long long)c.hour,
                                               (unsigned long long)c.minute);
    } @catch (NSException *e) {
        [out appendFormat:@"[6] 创建 MTAlarm .............. 异常: %@\n", e.reason];
        return out;
    }
    [out appendFormat:@"[6] 创建 MTAlarm .............. %@\n", alarm ? @"成功" : @"失败"];
    if (!alarm) return out;

    // 6. 设置属性
    @try {
        ((Send_Void_Id)objc_msgSend)(alarm, @selector(setTitle:), @"课表PoC");
        ((Send_Void_Bool)objc_msgSend)(alarm, @selector(setEnabled:), true);
        [out appendFormat:@"[7] 设置标题/启用 ............. 完成，目标时间 %02ld:%02ld\n",
            (long)c.hour, (long)c.minute];
    } @catch (NSException *e) {
        [out appendFormat:@"[7] 设置属性 .................. 异常: %@\n", e.reason];
    }

    // 7. 写回
    @try {
        id result = ((Send_Id_Id)objc_msgSend)(manager, @selector(addAlarm:), alarm);
        [out appendFormat:@"[8] addAlarm 调用 ............. %@\n", result ? @"有返回" : @"返回 nil"];
    } @catch (NSException *e) {
        [out appendFormat:@"[8] addAlarm 调用 ............. 异常: %@\n", e.reason];
        return out;
    }

    // 8. 等待 XPC 落盘后复读验证
    [NSThread sleepForTimeInterval:2.0];
    [out appendString:@"[9] 复读验证 (2 秒后) .........\n"];
    [out appendFormat:@"    %@\n", DescribeExistingAlarms(manager)];

    [out appendString:@"\n完成。请同时打开系统「时钟」App 核对。\n"];
    return out;
}

#pragma mark - UI

@interface ViewController : UIViewController
@property (nonatomic, strong) UITextView *textView;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    CGFloat w = self.view.bounds.size.width;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, 64, w - 40, 30)];
    title.text = @"MobileTimer 私有 API 验证";
    title.font = [UIFont boldSystemFontOfSize:17];
    title.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:title];

    UIButton *b1 = [UIButton buttonWithType:UIButtonTypeSystem];
    b1.frame = CGRectMake(20, 110, w - 40, 50);
    [b1 setTitle:@"创建闹钟（+5 分钟）" forState:UIControlStateNormal];
    [b1 setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b1.backgroundColor = [UIColor systemBlueColor];
    b1.layer.cornerRadius = 10;
    [b1 addTarget:self action:@selector(onRun) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:b1];

    self.textView = [[UITextView alloc]
        initWithFrame:CGRectMake(16, 180, w - 32, self.view.bounds.size.height - 200)];
    self.textView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    self.textView.editable = NO;
    self.textView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.textView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.textView.layer.cornerRadius = 10;
    self.textView.text = @"点击上方按钮开始验证。\n\n成功后请打开系统「时钟」App 查看是否出现 5 分钟后的闹钟。";
    [self.view addSubview:self.textView];
}

- (void)onRun {
    self.textView.text = @"执行中，请稍候…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *report = RunDiagnostics();
        dispatch_async(dispatch_get_main_queue(), ^{
            self.textView.text = report;
        });
    });
}

@end

#pragma mark - App 入口

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
        didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [[ViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}

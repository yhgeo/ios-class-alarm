//
//  main.m
//  AlarmPoC
//
//  v3 实测版
//
//  v2 诊断结论：
//    - entitlements 全部生效（platform-application / no-sandbox / private.mobiletimer）
//    - 沙箱完全穿透，可读 /var/mobile/Library/Preferences 并解析 com.apple.mobiletimerd.plist
//    - 真正的 XPC 服务名是 com.apple.MobileTimer.alarmserver
//      （v1/v2 一直用 com.apple.mobiletimerd，服务名是错的）
//    - MTAlarmManager 仍返回 nil，需判断是「服务名白名单」还是「服务端拒绝」
//
//  本版按优先级依次尝试三条创建路径，并各自报告结果：
//    A. XPC 直连正确服务名，拿到确切错误码
//    B. MTAlarmManager 正常调用
//    C. 直接改写 com.apple.mobiletimerd.plist（已验证可读可解析）
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <xpc/xpc.h>
#import <Security/Security.h>

typedef id (*Send_Id)(id, SEL);
typedef id (*Send_Id_Id)(id, SEL, id);
typedef void (*Send_Void_Id)(id, SEL, id);
typedef void (*Send_Void_Bool)(id, SEL, bool);
typedef id (*Send_Id_UllUll)(id, SEL, unsigned long long, unsigned long long);

// SecTask 为私有 API，公开头文件未导出
typedef struct CF_BRIDGED_TYPE(id) __SecTask *SecTaskRef;
extern SecTaskRef SecTaskCreateFromSelf(CFAllocatorRef allocator);
extern CFTypeRef SecTaskCopyValueForEntitlement(SecTaskRef task, CFStringRef entitlement, CFErrorRef *error);

static NSString *const kMobileTimerPath =
    @"/System/Library/PrivateFrameworks/MobileTimer.framework/MobileTimer";
static NSString *const kAlarmPlistPath =
    @"/var/mobile/Library/Preferences/com.apple.mobiletimerd.plist";
static const char *kAlarmServerName = "com.apple.MobileTimer.alarmserver";
static NSString *const kTimerdDomain = @"com.apple.mobiletimerd";

#pragma mark - 通用

static int gTargetHour = 0;
static int gTargetMinute = 0;

static void ComputeTargetTime(int offsetMinutes) {
    NSDateComponents *c = [[NSCalendar currentCalendar]
        components:(NSCalendarUnitHour | NSCalendarUnitMinute)
        fromDate:[NSDate dateWithTimeIntervalSinceNow:offsetMinutes * 60]];
    gTargetHour = (int)c.hour;
    gTargetMinute = (int)c.minute;
}

#pragma mark - A. XPC 直连正确的服务名

static NSString *ProbeAlarmServer(void) {
    __block NSString *result = @"(4 秒内无响应)";
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    typedef xpc_connection_t (*CreateMachFn)(const char *, dispatch_queue_t, uint64_t);
    typedef void (*SendWithReplyFn)(xpc_connection_t, xpc_object_t, dispatch_queue_t, void (^)(xpc_object_t));
    CreateMachFn createMach = (CreateMachFn)dlsym(RTLD_DEFAULT, "xpc_connection_create_mach_service");
    SendWithReplyFn sendWithReply = (SendWithReplyFn)dlsym(RTLD_DEFAULT, "xpc_connection_send_message_with_reply");
    if (!createMach || !sendWithReply) return @"dlsym 未找到 XPC 函数";

    xpc_connection_t conn = createMach(kAlarmServerName, NULL, 0);
    xpc_connection_set_event_handler(conn, ^(xpc_object_t event) {
        if (xpc_get_type(event) == XPC_TYPE_ERROR) {
            const char *d = xpc_dictionary_get_string(event, XPC_ERROR_KEY_DESCRIPTION);
            result = [NSString stringWithFormat:@"连接失败 — %s", d ? d : "unknown"];
            dispatch_semaphore_signal(sem);
        }
    });
    xpc_connection_resume(conn);

    xpc_object_t msg = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_string(msg, "kMsgType", "ping");
    sendWithReply(conn, msg, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^(xpc_object_t reply) {
        if (xpc_get_type(reply) == XPC_TYPE_ERROR) {
            const char *d = xpc_dictionary_get_string(reply, XPC_ERROR_KEY_DESCRIPTION);
            result = [NSString stringWithFormat:@"回复错误 — %s", d ? d : "unknown"];
        } else {
            result = @"服务可达（收到回复）";
        }
        dispatch_semaphore_signal(sem);
    });

    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC));
    return result;
}

#pragma mark - B. MTAlarmManager

static BOOL TryAlarmManager(int hour, int minute, NSMutableString *log) {
    void *h = dlopen(kMobileTimerPath.UTF8String, RTLD_NOW);
    if (!h) { [log appendString:@"    dlopen 失败\n"]; return NO; }

    Class mgrCls = NSClassFromString(@"MTAlarmManager");
    Class alarmCls = NSClassFromString(@"MTAlarm");
    if (!mgrCls || !alarmCls) { [log appendString:@"    类缺失\n"]; return NO; }

    id manager = ((Send_Id)objc_msgSend)(((Send_Id)objc_msgSend)(mgrCls, @selector(alloc)), @selector(init));
    if (!manager) { [log appendString:@"    manager 创建失败\n"]; return NO; }

    @try {
        id alarms = ((Send_Id)objc_msgSend)(manager, @selector(alarmsSync));
        [log appendFormat:@"    写入前 alarmsSync: %@\n", alarms ?: @"nil"];
        if (!alarms) {
            [log appendString:@"    → 读取仍为 nil，本条路径不可用\n"];
            return NO;
        }
    } @catch (NSException *e) {
        [log appendFormat:@"    alarmsSync 异常: %@\n", e.reason];
        return NO;
    }

    @try {
        id alarm = ((Send_Id_UllUll)objc_msgSend)(alarmCls, @selector(alarmWithHour:minute:),
                                                  (unsigned long long)hour, (unsigned long long)minute);
        ((Send_Void_Id)objc_msgSend)(alarm, @selector(setTitle:), @"课表PoC");
        ((Send_Void_Bool)objc_msgSend)(alarm, @selector(setEnabled:), true);
        ((Send_Id_Id)objc_msgSend)(manager, @selector(addAlarm:), alarm);
        [log appendString:@"    addAlarm 已调用\n"];
    } @catch (NSException *e) {
        [log appendFormat:@"    addAlarm 异常: %@\n", e.reason];
        return NO;
    }

    [NSThread sleepForTimeInterval:2.0];
    @try {
        id after = ((Send_Id)objc_msgSend)(manager, @selector(alarmsSync));
        [log appendFormat:@"    写入后 alarmsSync: %@\n", after ?: @"nil"];
        if ([after isKindOfClass:[NSArray class]] && [(NSArray *)after count] > 0) {
            [log appendString:@"    → 成功\n"];
            return YES;
        }
    } @catch (NSException *e) {
        [log appendFormat:@"    复读异常: %@\n", e.reason];
    }
    return NO;
}

#pragma mark - C. 直接改写 plist

static BOOL TryPlistWrite(int hour, int minute, NSMutableString *log) {
    NSFileManager *fm = [NSFileManager defaultManager];

    // 1) 备份到 App 沙箱
    NSString *backup = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/mobiletimerd-backup.plist"];
    [fm removeItemAtPath:backup error:nil];
    NSError *e = nil;
    if ([fm copyItemAtPath:kAlarmPlistPath toPath:backup error:&e]) {
        [log appendString:@"    已备份原文件到 App 沙箱\n"];
    } else {
        [log appendFormat:@"    备份失败（继续）: %@\n", e.localizedDescription];
    }

    // 2) 读
    NSMutableDictionary *root = [NSMutableDictionary dictionaryWithContentsOfFile:kAlarmPlistPath];
    if (!root) { [log appendString:@"    读取失败\n"]; return NO; }

    NSMutableDictionary *alarmsRoot = [root[@"MTAlarms"] mutableCopy];
    if (!alarmsRoot) { [log appendString:@"    缺少 MTAlarms 节点\n"]; return NO; }

    // 3) 模板：优先现有普通闹钟，退回睡眠闹钟
    NSDictionary *template = nil;
    NSArray *existing = alarmsRoot[@"MTAlarms"];
    if (existing.count > 0) {
        template = existing.firstObject[@"$MTAlarm"];
    } else {
        NSArray *sleeps = alarmsRoot[@"MTSleepAlarms"];
        if (sleeps.count > 0) template = sleeps.firstObject[@"$MTAlarm"];
    }
    if (!template) { [log appendString:@"    无可用模板\n"]; return NO; }

    // 4) 基于模板构造新闹钟
    NSMutableDictionary *a = [template mutableCopy];
    a[@"MTAlarmHour"] = @(hour);
    a[@"MTAlarmMinute"] = @(minute);
    a[@"MTAlarmID"] = [[NSUUID UUID] UUIDString];
    a[@"MTAlarmEnabled"] = @1;
    a[@"MTAlarmIsSleep"] = @0;
    a[@"MTAlarmRepeatSchedule"] = @0;
    a[@"MTAlarmTitle"] = @"课表PoC";
    a[@"MTAlarmLastModifiedDate"] = [NSDate date];
    [a removeObjectForKey:@"MTAlarmFireDate"];
    [a removeObjectForKey:@"MTAlarmDismissDate"];
    [a removeObjectForKey:@"MTAlarmBedtimeFireDate"];

    // 5) 追加
    NSMutableArray *list = [NSMutableArray arrayWithArray:existing ?: @[]];
    [list addObject:@{@"$MTAlarm": a}];
    alarmsRoot[@"MTAlarms"] = list;
    root[@"MTAlarms"] = alarmsRoot;
    root[@"MTAlarmModifiedDate"] = [NSDate date];

    // 6) 先走 CFPreferences（能正确通知 cfprefsd 与 mobiletimerd）
    CFPreferencesSetValue(CFSTR("MTAlarms"),
                          (__bridge CFPropertyListRef)alarmsRoot,
                          (__bridge CFStringRef)kTimerdDomain,
                          kCFPreferencesCurrentUser,
                          kCFPreferencesAnyHost);
    Boolean synced = CFPreferencesAppSynchronize((__bridge CFStringRef)kTimerdDomain);
    [log appendFormat:@"    CFPreferences 同步: %@\n", synced ? @"成功" : @"失败"];

    // 7) 再直接落盘（双保险）
    if ([root writeToFile:kAlarmPlistPath atomically:YES]) {
        [log appendString:@"    直接写文件: 成功\n"];
    } else {
        [log appendString:@"    直接写文件: 失败\n"];
    }

    // 8) 复读验证
    [NSThread sleepForTimeInterval:1.0];
    NSDictionary *check = [NSDictionary dictionaryWithContentsOfFile:kAlarmPlistPath];
    NSArray *after = check[@"MTAlarms"][@"MTAlarms"];
    [log appendFormat:@"    复读：普通闹钟数量 = %lu\n", (unsigned long)after.count];
    if (after.count > 0) {
        [log appendFormat:@"      最后一条标题 = %@\n", after.lastObject[@"$MTAlarm"][@"MTAlarmTitle"]];
        return YES;
    }
    return NO;
}

#pragma mark - 汇总

static NSString *RunAll(void) {
    NSMutableString *out = [NSMutableString string];
    ComputeTargetTime(5);

    [out appendFormat:@"目标闹钟时间：%02d:%02d（+5 分钟）\n\n", gTargetHour, gTargetMinute];

    [out appendString:@"===== A. XPC 直连 alarmserver =====\n"];
    [out appendFormat:@"    服务名: %s\n", kAlarmServerName];
    [out appendFormat:@"    结果: %@\n", ProbeAlarmServer()];

    [out appendString:@"\n===== B. MTAlarmManager 路径 =====\n"];
    BOOL okB = TryAlarmManager(gTargetHour, gTargetMinute, out);

    if (okB) {
        [out appendString:@"\n>>> 路径 B 成功，无需走 C。\n"];
        return out;
    }

    [out appendString:@"\n===== C. 直接改写 plist 路径 =====\n"];
    BOOL okC = TryPlistWrite(gTargetHour, gTargetMinute, out);

    [out appendString:@"\n===== 结论 =====\n"];
    if (okC) {
        [out appendString:@"    plist 写入成功。请打开系统「时钟」App 确认闹钟是否出现。\n"];
        [out appendString:@"    若出现 → 该路径可用；若未出现 → mobiletimerd 未重载，需另想办法。\n"];
    } else {
        [out appendString:@"    两条路径都未成功，请把本页结果发回。\n"];
    }
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
    title.text = @"AlarmPoC v3 实测";
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
    self.textView.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    self.textView.layer.cornerRadius = 10;
    self.textView.text = @"点上方按钮开始。\n\n会先备份闹钟数据到 App 沙箱，再尝试创建。";
    [self.view addSubview:self.textView];
}

- (void)onRun {
    self.textView.text = @"执行中，约需 10 秒…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *report = RunAll();
        dispatch_async(dispatch_get_main_queue(), ^{
            self.textView.text = report;
        });
    });
}

@end

#pragma mark - 入口

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

//
//  main.m
//  AlarmPoC
//
//  v2 诊断版
//
//  v1 结果：MTAlarmManager 能创建实例、能发消息，但 alarmsSync 返回 nil
//           → XPC 通道没打通。需定位是「entitlement 未生效」还是「服务端拒绝」。
//
//  本版一次性采集四组证据：
//    A. 进程实际持有的 entitlements（验证 ldid 注入是否真的生效）
//    B. 沙箱逃逸能力（能否读 /var/mobile/Library/Preferences）
//    C. 直连 com.apple.mobiletimerd 的 XPC 错误码
//    D. 闹钟数据文件 com.apple.mobiletimerd.plist 的真实结构
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <xpc/xpc.h>
#import <Security/Security.h>

typedef id   (*Send_Id)(id, SEL);
typedef id   (*Send_Id_Id)(id, SEL, id);
typedef void (*Send_Void_Id)(id, SEL, id);
typedef void (*Send_Void_Bool)(id, SEL, bool);
typedef id   (*Send_Id_UllUll)(id, SEL, unsigned long long, unsigned long long);

static NSString *const kMobileTimerPath =
    @"/System/Library/PrivateFrameworks/MobileTimer.framework/MobileTimer";
static NSString *const kAlarmPlistPath =
    @"/var/mobile/Library/Preferences/com.apple.mobiletimerd.plist";
static NSString *const kTimerdDomain = @"com.apple.mobiletimerd";

#pragma mark - A. entitlements

static NSString *CheckEntitlements(void) {
    NSMutableString *s = [NSMutableString string];
    SecTaskRef task = SecTaskCreateFromSelf(kCFAllocatorDefault);
    if (!task) {
        [s appendString:@"    SecTaskCreateFromSelf 失败\n"];
        return s;
    }
    NSArray *keys = @[
        @"platform-application",
        @"com.apple.private.security.no-sandbox",
        @"com.apple.private.mobiletimer",
        @"application-identifier",
        @"get-task-allow"
    ];
    for (NSString *k in keys) {
        CFTypeRef v = SecTaskCopyValueForEntitlement(task, (__bridge CFStringRef)k, NULL);
        [s appendFormat:@"    %@ = %@\n", k, v ? (__bridge id)v : @"(不存在)"];
        if (v) CFRelease(v);
    }
    CFRelease(task);
    return s;
}

#pragma mark - B. 文件系统

static NSString *CheckFilesystem(void) {
    NSMutableString *s = [NSMutableString string];
    NSFileManager *fm = [NSFileManager defaultManager];

    NSString *prefs = @"/var/mobile/Library/Preferences";
    NSError *e = nil;
    NSArray *list = [fm contentsOfDirectoryAtPath:prefs error:&e];
    if (list) {
        [s appendFormat:@"    可读 %@（%lu 项）\n", prefs, (unsigned long)list.count];
        NSMutableArray *hits = [NSMutableArray array];
        for (NSString *f in list) {
            NSString *lf = f.lowercaseString;
            if ([lf containsString:@"timer"] || [lf containsString:@"clock"] || [lf containsString:@"alarm"]) {
                [hits addObject:f];
            }
        }
        [s appendFormat:@"    相关文件: %@\n",
            hits.count ? [hits componentsJoinedByString:@", "] : @"(无)"];
    } else {
        [s appendFormat:@"    不可读 %@ — %@\n", prefs, e.localizedDescription ?: @"未知错误"];
    }

    BOOL exists = [fm fileExistsAtPath:kAlarmPlistPath];
    [s appendFormat:@"    com.apple.mobiletimerd.plist 存在: %@\n", exists ? @"是" : @"否"];

    if (exists) {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:kAlarmPlistPath];
        if (d) {
            [s appendFormat:@"    解析成功，%lu 个顶层键\n", (unsigned long)d.count];
            NSString *desc = [d description];
            NSUInteger cap = 2200;
            [s appendFormat:@"    ----- 内容开始 -----\n%@\n    ----- 内容结束（%@）-----\n",
                desc.length > cap ? [desc substringToIndex:cap] : desc,
                desc.length > cap ? @"已截断" : @"完整"];
        } else {
            [s appendString:@"    存在但解析失败（二进制 plist 或读取受限）\n"];
        }
    }
    return s;
}

#pragma mark - C. XPC 直连

static NSString *CheckXPC(void) {
    __block NSString *result = @"(4 秒内无响应)";
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    xpc_connection_t conn = xpc_connection_create_mach_service("com.apple.mobiletimerd", NULL, 0);
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
    xpc_connection_send_message_with_reply(conn, msg, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0),
        ^(xpc_object_t reply) {
            if (xpc_get_type(reply) == XPC_TYPE_ERROR) {
                const char *d = xpc_dictionary_get_string(reply, XPC_ERROR_KEY_DESCRIPTION);
                result = [NSString stringWithFormat:@"回复错误 — %s", d ? d : "unknown"];
            } else {
                result = @"收到正常回复（服务可达）";
            }
            dispatch_semaphore_signal(sem);
        });

    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC));
    return result;
}

#pragma mark - D. v1 路径复核

static NSString *CheckAlarmManager(void) {
    NSMutableString *s = [NSMutableString string];
    void *h = dlopen(kMobileTimerPath.UTF8String, RTLD_NOW);
    [s appendFormat:@"    dlopen: %@\n", h ? @"成功" : @"失败"];
    if (!h) return s;

    Class mgrCls = NSClassFromString(@"MTAlarmManager");
    if (!mgrCls) {
        [s appendString:@"    MTAlarmManager 缺失\n"];
        return s;
    }
    id manager = ((Send_Id)objc_msgSend)(((Send_Id)objc_msgSend)(mgrCls, @selector(alloc)), @selector(init));
    [s appendFormat:@"    manager: %@\n", manager ? @"创建成功" : @"创建失败"];
    if (!manager) return s;

    @try {
        id alarms = ((Send_Id)objc_msgSend)(manager, @selector(alarmsSync));
        [s appendFormat:@"    alarmsSync: %@\n", alarms ?: @"nil"];
    } @catch (NSException *e) {
        [s appendFormat:@"    alarmsSync 异常: %@\n", e.reason];
    }

    @try {
        id provider = ((Send_Id)objc_msgSend)(manager, @selector(connectionProvider));
        [s appendFormat:@"    connectionProvider: %@\n", provider ?: @"nil"];
    } @catch (NSException *e) {
        [s appendFormat:@"    connectionProvider 异常: %@\n", e.reason];
    }
    return s;
}

#pragma mark - 汇总

static NSString *RunDiagnostics(void) {
    NSMutableString *out = [NSMutableString string];
    [out appendString:@"===== A. 进程实际 entitlements =====\n"];
    [out appendString:CheckEntitlements()];
    [out appendString:@"\n===== B. 沙箱外文件访问 =====\n"];
    [out appendString:CheckFilesystem()];
    [out appendString:@"\n===== C. XPC 直连 mobiletimerd =====\n"];
    [out appendFormat:@"    %@\n", CheckXPC()];
    [out appendString:@"\n===== D. MTAlarmManager 复核 =====\n"];
    [out appendString:CheckAlarmManager()];
    [out appendString:@"\n===== 采集完成 ====="];
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
    title.text = @"MobileTimer 诊断 v2";
    title.font = [UIFont boldSystemFontOfSize:17];
    title.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:title];

    UIButton *b1 = [UIButton buttonWithType:UIButtonTypeSystem];
    b1.frame = CGRectMake(20, 110, w - 40, 50);
    [b1 setTitle:@"开始采集诊断信息" forState:UIControlStateNormal];
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
    self.textView.text = @"点上方按钮开始采集。\n\n只读诊断，不会修改任何数据。";
    [self.view addSubview:self.textView];
}

- (void)onRun {
    self.textView.text = @"采集中，约需 5 秒…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *report = RunDiagnostics();
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

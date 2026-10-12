//
//  main.m
//  AlarmPoC
//
//  v4 实测版
//
//  v3 结论：
//    - plist 写入成功（复读可见「课表PoC」），数据确实落盘
//    - 但系统时钟 App 未显示 → mobiletimerd 在内存维护状态，不会主动重读文件
//    - XPC 连 com.apple.MobileTimer.alarmserver 返回 "Connection interrupted"
//      （服务名正确、连接可建立，只是探测消息不符协议被断开）
//
//  本版目标：让 mobiletimerd 重新加载 preferences
//    1. 写入 plist
//    2. 发 Darwin 通知（若干候选名）
//    3. 重启 mobiletimerd 守护进程（launchd 会自动拉起并重读数据）
//    4. 复读验证
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <signal.h>
#import <errno.h>
#import <string.h>
#import <sys/sysctl.h>

// 私有 API 手写声明，避免依赖私有头文件
extern int proc_listallpids(void *buffer, int buffersize);
extern int proc_name(int pid, void *buffer, uint32_t buffersize);
extern uint32_t notify_post(const char *name);

static NSString *const kAlarmPlistPath =
    @"/var/mobile/Library/Preferences/com.apple.mobiletimerd.plist";
static NSString *const kBackupPath =
    @"/var/mobile/Library/Preferences/com.apple.mobiletimerd.plist.pocbak";
static NSString *const kTimerdDomain = @"com.apple.mobiletimerd";

static int gTargetHour = 0;
static int gTargetMinute = 0;

static void ComputeTargetTime(int offsetMinutes) {
    NSDateComponents *c = [[NSCalendar currentCalendar]
        components:(NSCalendarUnitHour | NSCalendarUnitMinute)
        fromDate:[NSDate dateWithTimeIntervalSinceNow:offsetMinutes * 60]];
    gTargetHour = (int)c.hour;
    gTargetMinute = (int)c.minute;
}

#pragma mark - 1. 写入 plist

static BOOL WriteAlarmToPlist(int hour, int minute, NSMutableString *log) {
    NSFileManager *fm = [NSFileManager defaultManager];

    // 备份（放在同目录，避免沙箱路径问题）
    [fm removeItemAtPath:kBackupPath error:nil];
    NSError *e = nil;
    if ([fm copyItemAtPath:kAlarmPlistPath toPath:kBackupPath error:&e]) {
        [log appendFormat:@"    已备份到 %@\n", kBackupPath];
    } else {
        [log appendFormat:@"    备份失败（继续）: %@\n", e.localizedDescription];
    }

    NSMutableDictionary *root = [NSMutableDictionary dictionaryWithContentsOfFile:kAlarmPlistPath];
    if (!root) { [log appendString:@"    读取失败\n"]; return NO; }

    NSMutableDictionary *alarmsRoot = [root[@"MTAlarms"] mutableCopy];
    if (!alarmsRoot) { [log appendString:@"    缺少 MTAlarms 节点\n"]; return NO; }

    NSDictionary *template = nil;
    NSArray *existing = alarmsRoot[@"MTAlarms"];
    if (existing.count > 0) {
        template = existing.firstObject[@"$MTAlarm"];
    } else {
        NSArray *sleeps = alarmsRoot[@"MTSleepAlarms"];
        if (sleeps.count > 0) template = sleeps.firstObject[@"$MTAlarm"];
    }
    if (!template) { [log appendString:@"    无可用模板\n"]; return NO; }

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

    NSMutableArray *list = [NSMutableArray arrayWithArray:existing ?: @[]];
    [list addObject:@{@"$MTAlarm": a}];
    alarmsRoot[@"MTAlarms"] = list;
    root[@"MTAlarms"] = alarmsRoot;
    root[@"MTAlarmModifiedDate"] = [NSDate date];

    CFPreferencesSetValue(CFSTR("MTAlarms"),
                          (__bridge CFPropertyListRef)alarmsRoot,
                          (__bridge CFStringRef)kTimerdDomain,
                          kCFPreferencesCurrentUser,
                          kCFPreferencesAnyHost);
    Boolean synced = CFPreferencesAppSynchronize((__bridge CFStringRef)kTimerdDomain);
    [log appendFormat:@"    CFPreferences 同步: %@\n", synced ? @"成功" : @"失败"];

    BOOL wrote = [root writeToFile:kAlarmPlistPath atomically:YES];
    [log appendFormat:@"    直接写文件: %@\n", wrote ? @"成功" : @"失败"];

    NSDictionary *check = [NSDictionary dictionaryWithContentsOfFile:kAlarmPlistPath];
    NSArray *after = check[@"MTAlarms"][@"MTAlarms"];
    [log appendFormat:@"    当前普通闹钟数量: %lu\n", (unsigned long)after.count];
    return wrote;
}

#pragma mark - 2. Darwin 通知

static void PostNotifications(NSMutableString *log) {
    const char *names[] = {
        "com.apple.mobiletimerd.alarmsChanged",
        "com.apple.mobiletimerd.prefsChanged",
        "com.apple.mobiletimer.alarmsChanged",
        "com.apple.mobiletimerd",
        "ApplePreferencesChanged",
    };
    for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
        uint32_t st = notify_post(names[i]);
        [log appendFormat:@"    notify_post(\"%s\") → %u\n", names[i], st];
    }
}

#pragma mark - 3. 重启 mobiletimerd

static pid_t FindTimerDaemon(NSMutableString *log) {
    pid_t target = -1;

    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t size = 0;
    if (sysctl(mib, 4, NULL, &size, NULL, 0) == 0 && size > 0) {
        struct kinfo_proc *procs = malloc(size);
        if (procs && sysctl(mib, 4, procs, &size, NULL, 0) == 0) {
            int count = (int)(size / sizeof(struct kinfo_proc));
            [log appendFormat:@"    [sysctl] 可见进程 %d 个\n", count];
            for (int i = 0; i < count; i++) {
                if (strcmp(procs[i].kp_proc.p_comm, "mobiletimerd") == 0) {
                    target = procs[i].kp_proc.p_pid;
                    [log appendFormat:@"    [sysctl] 命中 mobiletimerd pid=%d\n", target];
                    break;
                }
            }
        }
        if (procs) free(procs);
    } else {
        [log appendFormat:@"    [sysctl] 失败: %s\n", strerror(errno)];
    }

    if (target < 0) {
        int pids[4096];
        int n = proc_listallpids(pids, sizeof(pids));
        [log appendFormat:@"    [libproc] 可见进程 %d 个\n", n];
        for (int i = 0; i < n; i++) {
            char nm[256] = {0};
            proc_name(pids[i], nm, sizeof(nm));
            if (strcmp(nm, "mobiletimerd") == 0) {
                target = pids[i];
                [log appendFormat:@"    [libproc] 命中 mobiletimerd pid=%d\n", target];
                break;
            }
        }
    }
    return target;
}

static void RestartTimerDaemon(NSMutableString *log) {
    pid_t pid = FindTimerDaemon(log);
    if (pid < 0) {
        [log appendString:@"    未找到 mobiletimerd 进程\n"];
        return;
    }
    // 用 SIGKILL：避免它在退出时把内存状态写回、覆盖我们刚写入的数据
    if (kill(pid, SIGKILL) == 0) {
        [log appendString:@"    已发送 SIGKILL，launchd 将自动重新拉起\n"];
    } else {
        [log appendFormat:@"    kill 失败: %s (errno=%d)\n", strerror(errno), errno);
    }
}

#pragma mark - 汇总

static NSString *RunAll(void) {
    NSMutableString *out = [NSMutableString string];
    ComputeTargetTime(5);

    [out appendFormat:@"目标闹钟时间：%02d:%02d（+5 分钟）\n\n", gTargetHour, gTargetMinute];

    [out appendString:@"===== 1. 写入 plist =====\n"];
    BOOL wrote = WriteAlarmToPlist(gTargetHour, gTargetMinute, out);

    [out appendString:@"\n===== 2. 发送 Darwin 通知 =====\n"];
    PostNotifications(out);

    [out appendString:@"\n===== 3. 重启 mobiletimerd =====\n"];
    RestartTimerDaemon(out);

    [out appendString:@"\n===== 4. 等待并复读 =====\n"];
    [NSThread sleepForTimeInterval:3.0];
    NSDictionary *check = [NSDictionary dictionaryWithContentsOfFile:kAlarmPlistPath];
    NSArray *after = check[@"MTAlarms"][@"MTAlarms"];
    [out appendFormat:@"    普通闹钟数量: %lu\n", (unsigned long)after.count];
    for (NSDictionary *item in after) {
        NSDictionary *al = item[@"$MTAlarm"];
        [out appendFormat:@"      %@:%@  %@  enabled=%@\n",
            al[@"MTAlarmHour"], al[@"MTAlarmMinute"], al[@"MTAlarmTitle"], al[@"MTAlarmEnabled"]];
    }

    [out appendString:@"\n===== 结论 =====\n"];
    if (wrote) {
        [out appendString:@"    数据已写入。请打开系统「时钟」App 查看闹钟是否出现。\n"];
        [out appendString:@"    若出现 → 方案成立；若仍不出现 → 换用快捷指令官方动作方案。\n"];
    } else {
        [out appendString:@"    写入失败，请把本页结果发回。\n"];
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
    title.text = @"AlarmPoC v4 实测";
    title.font = [UIFont boldSystemFontOfSize:17];
    title.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:title];

    UIButton *b1 = [UIButton buttonWithType:UIButtonTypeSystem];
    b1.frame = CGRectMake(20, 110, w - 40, 50);
    [b1 setTitle:@"写入并重启闹钟服务" forState:UIControlStateNormal];
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
    self.textView.text = @"点上方按钮开始。\n\n流程：写入闹钟数据 → 发通知 → 重启 mobiletimerd 使其重载。\n会先把原数据备份到同目录 .pocbak。";
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

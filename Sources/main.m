//
//  main.m
//  响课（XiangKe）— 课表闹钟
//
//  入口与 App 生命周期。业务逻辑都在各 CAL* 模块里，这里只做装配。
//
//  两种触发方式：
//    1. 快捷指令 xiangke://apply —— 手机解锁时可用，时间精确
//    2. 后台自动刷新（BGTaskScheduler）—— 锁屏也能跑，由系统择机唤醒
//       为什么需要 2：iOS 在锁屏状态下禁止「打开 URL / 打开 App」，
//       所以快捷指令那条路在锁屏时必定失败，只能靠 App 自己在后台跑。
//

#import <UIKit/UIKit.h>
#import <BackgroundTasks/BackgroundTasks.h>

#import "CALHomeViewController.h"
#import "CALApplier.h"
#import "CALTimetable.h"
#import "CALProbe.h"

/// 快捷指令定时自动化用的 URL Scheme：xiangke://apply
static NSString * const kCALURLScheme = @"xiangke";

/// 后台自动刷新任务标识（需与 Info.plist 的 BGTaskSchedulerPermittedIdentifiers 一致）
static NSString * const kCALAutoRefreshTaskID = @"com.yhgeo.alarmpoc.autorefresh";

/// 每次排程至少间隔多久再让系统唤醒我们
static const NSTimeInterval kCALAutoRefreshInterval = 3 * 3600;   // 3 小时

#pragma mark - AppDelegate

@interface CALAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation CALAppDelegate

- (BOOL)application:(UIApplication *)application
        didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    CALHomeViewController *home = [[CALHomeViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:home];
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];

    [self registerAutoRefreshTask];
    [self scheduleAutoRefresh];

    // 冷启动就是被 URL 唤起的：URL 在 launchOptions 里，不走 openURL:
    NSURL *launchURL = launchOptions[UIApplicationLaunchOptionsURLKey];
    if ([launchURL isKindOfClass:[NSURL class]]) {
        [self handleURL:launchURL];
    }
    return YES;
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    // 进后台时补排一次，尽量让系统在夜间安排唤醒
    [self scheduleAutoRefresh];
}

- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
            options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options {
    return [self handleURL:url];
}

/// 解析 xiangke://apply。返回是否已接管该 URL。
- (BOOL)handleURL:(NSURL *)url {
    if (![url.scheme.lowercaseString isEqualToString:kCALURLScheme]) return NO;

    NSString *action = url.host.lowercaseString ?: @"";
    if (action.length == 0) {
        // 兼容 xiangke:///apply 这种写法
        action = [[url.path stringByTrimmingCharactersInSet:
                   [NSCharacterSet characterSetWithCharactersInString:@"/"]] lowercaseString];
    }

    if ([action isEqualToString:@"apply"]) {
        [CALProbe runWithTrigger:@"URL 唤起（快捷指令）"];
        [CALApplier applyTimetableFromURLTrigger];
    }
    return YES;
}

#pragma mark - 后台自动刷新

/// 注册后台任务处理器。必须在 didFinishLaunching 里完成注册。
- (void)registerAutoRefreshTask {
    [[BGTaskScheduler sharedScheduler]
        registerForTaskWithIdentifier:kCALAutoRefreshTaskID
                           usingQueue:nil
                        launchHandler:^(BGTask *task) {
        [self handleAutoRefresh:(BGAppRefreshTask *)task];
    }];
}

/// 排下一次后台唤醒。每次启动、进后台、跑完都重排一次。
- (void)scheduleAutoRefresh {
    BGTaskScheduler *scheduler = [BGTaskScheduler sharedScheduler];
    [scheduler cancelTaskRequestWithIdentifier:kCALAutoRefreshTaskID];

    BGAppRefreshTaskRequest *request =
        [[BGAppRefreshTaskRequest alloc] initWithIdentifier:kCALAutoRefreshTaskID];
    request.earliestBeginDate = [NSDate dateWithTimeIntervalSinceNow:kCALAutoRefreshInterval];

    NSError *error = nil;
    [scheduler submitTaskRequest:request error:&error];
    if (error) {
        NSLog(@"[响课·后台] 排程失败：%@", error.localizedDescription);
    }
}

- (void)handleAutoRefresh:(BGAppRefreshTask *)task {
    // 先把下一次排上，免得这次出问题以后就再也不跑了
    [self scheduleAutoRefresh];

    __block BOOL finished = NO;
    task.expirationHandler = ^{
        if (!finished) NSLog(@"[响课·后台] 被系统回收（时间不够）");
    };

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        // 记一条探针：后台唤醒常常发生在锁屏时，正好用来验证
        // 「锁屏下能不能访问系统文件」—— 这是整套方案的成败关键。
        NSLog(@"[响课·后台] %@", [CALProbe runWithTrigger:@"后台刷新（系统唤醒）"]);

        CALTimetable *timetable = [CALTimetableStore shared].timetable;
        NSString *log = [CALApplier applyTimetable:timetable];
        NSLog(@"[响课·后台] %@", log);

        finished = YES;
        [task setTaskCompletedWithSuccess:YES];
    });
}

@end

#pragma mark - 入口

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([CALAppDelegate class]));
    }
}

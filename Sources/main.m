//
//  main.m
//  响课（XiangKe）— 课表闹钟
//
//  入口与 App 生命周期。业务逻辑都在各 CAL* 模块里，这里只做装配。
//
//  模块划分：
//    CALTimetable                课表数据模型 + 持久化
//    CALAlarmStore               系统闹钟读写引擎
//    CALDaemonReloader           让 mobiletimerd 重新加载数据
//    CALScheduleEngine           纯计算：课表 → 目标时间
//    CALApplier                  协调层：把上面几块串起来
//    CALHomeViewController       主界面
//    CALTimetableViewController  课表列表页
//    CALCourseEditorViewController  单节课编辑表单
//    CALPaddedLabel              带内边距的 UILabel
//

#import <UIKit/UIKit.h>
#import "CALHomeViewController.h"
#import "CALApplier.h"

/// 快捷指令定时自动化用的 URL Scheme：xiangke://apply
static NSString * const kCALURLScheme = @"xiangke";

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

    // 冷启动就是被 URL 唤起的：URL 在 launchOptions 里，不走 openURL:
    NSURL *launchURL = launchOptions[UIApplicationLaunchOptionsURLKey];
    if ([launchURL isKindOfClass:[NSURL class]]) {
        [self handleURL:launchURL];
    }
    return YES;
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
        [CALApplier applyTimetableFromURLTrigger];
    }
    return YES;
}

@end

#pragma mark - 入口

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([CALAppDelegate class]));
    }
}

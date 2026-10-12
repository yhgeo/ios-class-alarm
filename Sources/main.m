//
//  main.m
//  ClassAlarm — 课表闹钟
//
//  入口与 App 生命周期。业务逻辑都在各 CAL* 模块里，这里只做装配。
//
//  模块划分：
//    CALTimetable           课表数据模型 + 持久化
//    CALAlarmStore          系统闹钟读写引擎
//    CALDaemonReloader      让 mobiletimerd 重新加载数据
//    CALScheduleEngine      纯计算：课表 → 目标时间
//    CALApplier             协调层：把上面几块串起来
//    CALHomeViewController  界面
//

#import <UIKit/UIKit.h>
#import "CALHomeViewController.h"

#pragma mark - AppDelegate

@interface CALAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation CALAppDelegate

- (BOOL)application:(UIApplication *)application
        didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [[CALHomeViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}

@end

#pragma mark - 入口

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([CALAppDelegate class]));
    }
}

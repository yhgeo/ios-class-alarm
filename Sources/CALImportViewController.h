//
//  CALImportViewController.h
//  导入课表的输入页。
//  只负责收集 URL 并回调，不负责下载 —— 下载由调用方处理。
//
//  为什么不用 UIAlertController：
//  系统 alert 的输入框在 iOS 16 上编辑菜单（长按粘贴）不稳定，而且一按按钮 alert 就关闭，
//  没法在用户点「粘贴」后回填文本。这里用独立页面 + 显式的剪贴板按钮绕开。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CALImportViewController;

@protocol CALImportDelegate <NSObject>
/// 用户点了「导入」
- (void)importController:(CALImportViewController *)controller
    didFinishWithURLString:(NSString *)urlString;
/// 用户取消
- (void)importControllerDidCancel:(CALImportViewController *)controller;
@end

@interface CALImportViewController : UIViewController

@property (nonatomic, weak, nullable) id<CALImportDelegate> delegate;

/// 预填内容（一般是上次用过的地址）
@property (nonatomic, copy, nullable) NSString *initialURLString;

@end

NS_ASSUME_NONNULL_END

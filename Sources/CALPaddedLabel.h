//
//  CALPaddedLabel.h
//  带内边距的 UILabel —— UILabel 原生没有 padding，文字会贴着圆角边缘。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CALPaddedLabel : UILabel

/// 内边距，默认 {14, 14, 14, 14}
@property (nonatomic) UIEdgeInsets padding;

@end

NS_ASSUME_NONNULL_END

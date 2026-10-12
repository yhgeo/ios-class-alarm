//
//  CALCourseEditorViewController.h
//  单节课程的编辑表单。
//  只负责收集用户输入并回调，不直接改动存储 —— 由列表页统一处理。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "CALTimetable.h"

NS_ASSUME_NONNULL_BEGIN

@class CALCourseEditorViewController;

@protocol CALCourseEditorDelegate <NSObject>
/// 用户点了保存
- (void)courseEditor:(CALCourseEditorViewController *)editor
    didFinishWithCourse:(CALCourse *)course;
/// 用户取消
- (void)courseEditorDidCancel:(CALCourseEditorViewController *)editor;
@end

@interface CALCourseEditorViewController : UIViewController

@property (nonatomic, weak, nullable) id<CALCourseEditorDelegate> delegate;

/// 传入表示编辑已有课程；传 nil 表示新增
@property (nonatomic, strong, nullable) CALCourse *editingCourse;

/// 新增时的默认星期（1=周一 … 7=周日）
@property (nonatomic) NSInteger defaultWeekday;

/// 隐藏「星期」字段。用于「临时调整」：按日期覆盖时星期没有意义。
@property (nonatomic) BOOL hidesWeekdayField;

@end

NS_ASSUME_NONNULL_END

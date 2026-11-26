#pragma once
#import <UIKit/UIKit.h>

@interface LCOSBackgroundView : UIView
@property (nonatomic, copy) void (^onHome)(void);
@property (nonatomic, copy) BOOL (^onActivateTask)(UIView *taskView);
@property (nonatomic, copy) BOOL (^onCloseTask)(UIView *taskView);
@property (nonatomic, copy) void (^onTaskPresented)(UIView *taskView);
- (void)setSourceDesktop:(UIView *)desktop;
- (void)setLiveTaskViews:(NSArray<UIView *> *)taskViews;
- (void)setTransitionProgress:(CGFloat)progress;
- (void)restoreTaskGeometry;
- (void)detachSourceDesktop;
- (void)prepareForTaskActivation;
- (void)removeTaskFromCards:(UIView *)task;
- (void)setSourceScales:(BOOL)scales;
@end

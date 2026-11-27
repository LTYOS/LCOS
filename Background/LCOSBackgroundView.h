#pragma once
#import <UIKit/UIKit.h>

@interface LCOSBackgroundView : UIView
@property (nonatomic, copy) void (^onHome)(void);
@property (nonatomic, copy) BOOL (^onActivateTask)(UIView *taskView);
@property (nonatomic, copy) BOOL (^onCloseTask)(UIView *taskView);
@property (nonatomic, copy) void (^onTaskPresented)(UIView *taskView);
@property (nonatomic, strong, readonly) UIView *cardCanvas;
@property (nonatomic, strong, readonly) UIVisualEffectView *blurView;
@property (nonatomic, strong, readonly) UIView *dimView;
@property (nonatomic, strong, readonly) UIScrollView *scrollView;
@property (nonatomic, copy, readonly) NSArray<UIView *> *taskViews;
@property (nonatomic, assign, readonly) NSUInteger placementCount;
@property (nonatomic, assign, readonly) NSUInteger cardCount;
- (void)setLiveTaskViews:(NSArray<UIView *> *)taskViews;
- (void)setTransitionProgress:(CGFloat)progress;
- (void)restoreTaskGeometry;
- (void)prepareForTaskActivation;
- (void)removeTaskFromCards:(UIView *)task;
- (void)setBackdropActive:(BOOL)active;
@end

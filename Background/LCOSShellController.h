#pragma once
#import <UIKit/UIKit.h>

@interface LCOSShellController : NSObject
@property (nonatomic, assign, readonly) BOOL fromLCOS;
@property (nonatomic, assign, readonly) BOOL hasActiveTask;
@property (nonatomic, assign, readonly) BOOL isBackgroundVisible;
@property (nonatomic, weak, readonly) UIView *navigationZone;
@property (nonatomic, weak, readonly) UIView *backgroundView;
- (instancetype)initWithOverlay:(UIWindow *)overlay fromLCOS:(BOOL)fromLCOS;
- (void)presentTask:(UIView *)task;
- (void)updateNavigation;
- (void)setLauncherView:(UIView *)launcherView;
- (void)showBackground;
- (void)hideBackground;
@end

#pragma once

#import <UIKit/UIKit.h>

@class LCOSLauncherView;

@interface LCOSFloatingButton : UIButton <UIGestureRecognizerDelegate>

@property (nonatomic, weak) LCOSLauncherView *launcher;

+ (instancetype)sharedButton;
- (void)showOnWindow:(UIWindow *)window;
- (void)hide;
- (void)toggleLauncher;

@end
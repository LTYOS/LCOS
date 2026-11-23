#pragma once

#import <UIKit/UIKit.h>

@class LCOSLauncherView;

@interface LCOSFloatingButton : UIButton

@property (nonatomic, weak) LCOSLauncherView *launcher;

+ (instancetype)sharedButton;
- (void)showOnWindow:(UIWindow *)window;
- (void)hide;

@end
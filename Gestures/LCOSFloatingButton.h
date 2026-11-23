#pragma once

#import <UIKit/UIKit.h>

@class LCOSCore;

@interface LCOSFloatingButton : UIButton

+ (instancetype)sharedButton;
- (void)showOnWindow:(UIWindow *)window;
- (void)hide;

@end
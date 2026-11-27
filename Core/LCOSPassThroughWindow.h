#pragma once
#import <UIKit/UIKit.h>

@interface LCOSPassThroughWindow : UIWindow
@property (nonatomic, weak) UIViewController *launcherContainer;
@property (nonatomic, weak) UIView *backgroundView;
@property (nonatomic, weak) UIView *navigationTouchZone;
@end

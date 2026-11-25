#pragma once
#import <UIKit/UIKit.h>

@interface LCOSNavigationBar : UIControl
@property (nonatomic, copy) void (^onHome)(void);
@property (nonatomic, copy) void (^onBackground)(void);
@property (nonatomic, copy) void (^onSettings)(void);
@end

#pragma once
#import <UIKit/UIKit.h>

@interface LCOSBackgroundView : UIView
@property (nonatomic, copy) void (^onClose)(void);
- (void)setApps:(NSArray *)apps;
@end

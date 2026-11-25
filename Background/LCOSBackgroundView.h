#pragma once
#import <UIKit/UIKit.h>

@interface LCOSBackgroundView : UIView
@property (nonatomic, copy) void (^onClose)(void);
@property (nonatomic, copy) void (^onEmptySpaceTapped)(void);
- (void)setApps:(NSArray *)apps;
- (void)prepareWithCurrentInterface:(UIView *)interfaceView;
- (void)setTransitionProgress:(CGFloat)progress;
@end

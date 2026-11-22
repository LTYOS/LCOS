#pragma once

#import <Foundation/Foundation.h>

@interface LCOSGestureHandler : NSObject

+ (void)handleThreeFingerSwipeUp;
+ (void)handleThreeFingerSwipeDown;
+ (void)handleThreeFingerLongPress;
+ (void)handleLeftEdgeGesture;

+ (void)registerGestureRecognizers;

@end
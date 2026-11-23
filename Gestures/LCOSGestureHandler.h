#pragma once

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface LCOSGestureHandler : NSObject <UIGestureRecognizerDelegate>

+ (instancetype)sharedHandler;
+ (void)registerGestureRecognizers;

@end
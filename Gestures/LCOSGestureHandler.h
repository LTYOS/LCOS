#pragma once

#import <Foundation/Foundation.h>

@interface LCOSGestureHandler : NSObject

+ (instancetype)sharedHandler;
+ (void)registerGestureRecognizers;

@end
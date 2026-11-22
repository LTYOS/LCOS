#pragma once

#import <Foundation/Foundation.h>

@interface LCOSBackground : NSObject

+ (void)startBackgroundProcess;
+ (void)stopBackgroundProcess;
+ (void)manageAppContainer;

@end
#pragma once

#import <Foundation/Foundation.h>

@interface LCOSAppContainer : NSObject

+ (void)ensureLCOSDirectoryExists;
+ (void)writeLog:(NSString *)message;
+ (void)writeError:(NSString *)message;

@end
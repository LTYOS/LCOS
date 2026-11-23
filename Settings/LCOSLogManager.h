#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LCOSLogManager : NSObject

+ (instancetype)sharedManager;
- (void)logError:(NSError *)error;
- (void)logMessage:(NSString *)message level:(NSString *)level;
+ (void)forceLog:(NSString *)message;
+ (void)clearLogs;
+ (NSData *)exportLogsAsJSON;

@end

NS_ASSUME_NONNULL_END
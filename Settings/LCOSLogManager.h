#pragma once

#import <Foundation/Foundation.h>

@interface LCOSLogManager : NSObject

@property (nonatomic, strong) NSString *logDirectory;
@property (nonatomic, strong) NSString *logFilePath;

+ (instancetype)sharedManager;
- (void)setupLogDirectory;
- (void)logError:(NSError *)error;
- (void)logMessage:(NSString *)message level:(NSString *)level;
- (void)writeLogLine:(NSString *)line;

@end
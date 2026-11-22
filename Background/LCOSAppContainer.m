//
//  LCOSAppContainer.m
//  LCOS.dylib
//

#import "LCOSAppContainer.h"

@implementation LCOSAppContainer

+ (void)ensureLCOSDirectoryExists {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *lcDir = [NSHomeDirectory() stringByAppendingPathComponent:@".LCOS"];
    
    if (![fm fileExistsAtPath:lcDir]) {
        [fm createDirectoryAtPath:lcDir withIntermediateDirectories:YES attributes:nil error:nil];
        NSLog(@"LCOS: Created .LCOS directory at %@", lcDir);
    }
}

+ (void)writeLog:(NSString *)message {
    [self ensureLCOSDirectoryExists];
    NSString *logPath = [NSHomeDirectory() stringByAppendingPathComponent:@".LCOS/lcos.log"];
    [message writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

+ (void)writeError:(NSString *)message {
    [self ensureLCOSDirectoryExists];
    NSString *errorPath = [NSHomeDirectory() stringByAppendingPathComponent:@".LCOS/lcos_error.log"];
    [message writeToFile:errorPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

@end
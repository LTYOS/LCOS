//
//  LCOSLogManager.m
//  LCOS.dylib
//

#import "LCOSLogManager.h"
#import "LCOSAppContainer.h"

@implementation LCOSLogManager

static LCOSLogManager *_sharedInstance = nil;

+ (instancetype)sharedManager {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[LCOSLogManager alloc] init];
    });
    return _sharedInstance;
}

- (void)setupLogDirectory {
    self.logDirectory = [NSHomeDirectory() stringByAppendingPathComponent:@".LCOS/logs"];
    NSFileManager *fm = [NSFileManager defaultManager];
    
    if (![fm fileExistsAtPath:self.logDirectory]) {
        [fm createDirectoryAtPath:self.logDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    self.logFilePath = [self.logDirectory stringByAppendingPathComponent:@"LCOS.log"];
}

- (void)logError:(NSError *)error {
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSString *timestamp = [df stringFromDate:[NSDate date]];
    
    NSString *line = [NSString stringWithFormat:@"[%@] [ERROR] %@: %@\n", timestamp, error.domain, error.localizedDescription];
    [self writeLogLine:line];
}

- (void)logMessage:(NSString *)message level:(NSString *)level {
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSString *timestamp = [df stringFromDate:[NSDate date]];
    
    NSString *line = [NSString stringWithFormat:@"[%@] [%@] %@\n", timestamp, level, message];
    [self writeLogLine:line];
}

- (void)writeLogLine:(NSString *)line {
    if (!self.logFilePath) {
        [self setupLogDirectory];
    }
    
    NSFileHandle *handle = nil;
    if (![NSFileManager.defaultManager fileExistsAtPath:self.logFilePath]) {
        handle = [NSFileHandle fileHandleForWritingAtPath:self.logFilePath];
        if (!handle) {
            handle = [[NSFileHandle alloc] initWithFileURL:[NSURL fileURLWithPath:self.logFilePath]];
        }
    } else {
        handle = [NSFileHandle fileHandleForWritingAtPath:self.logFilePath];
    }
    
    if (handle) {
        [handle seekToEndOfFile];
        [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [handle closeFile];
    }
}

@end
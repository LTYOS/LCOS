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
        [_sharedInstance setupLogDirectory];
    });
    return _sharedInstance;
}

- (void)setupLogDirectory {
    // Try home directory first, then fall back to container shared directory
    self.logDirectory = [NSHomeDirectory() stringByAppendingPathComponent:@".LCOS/logs"];
    self.containerLogDirectory = @"/LCOS/logs";
    NSFileManager *fm = [NSFileManager defaultManager];
    
    // Try creating in home directory
    BOOL created = NO;
    if (![fm fileExistsAtPath:self.logDirectory]) {
        created = [fm createDirectoryAtPath:self.logDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    // If home directory creation failed, try container path
    if (!created) {
        self.logDirectory = @"/tmp/LCOS/logs";
        if (![fm fileExistsAtPath:self.logDirectory]) {
            [fm createDirectoryAtPath:self.logDirectory withIntermediateDirectories:YES attributes:nil error:nil];
        }
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
    
    // Ensure log directory exists before writing
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:self.logDirectory]) {
        [self setupLogDirectory];
    }
    
    // Always write directly to file to avoid NSFileHandle issues
    // Use writeToFile:atomically:encoding:error: for iOS SDK compatibility
    BOOL writeSuccess = [line writeToFile:self.logFilePath atomically:YES
                                 encoding:NSUTF8StringEncoding error:nil];
    
    // If atomic write fails, try regular write
    if (!writeSuccess) {
        [line writeToFile:self.logFilePath encoding:NSUTF8StringEncoding error:nil];
    }
}

+ (void)forceLog:(NSString *)message {
    LCOSLogManager *manager = [LCOSLogManager sharedManager];
    // Ensure log directory is set up before forcing a log
    [manager setupLogDirectory];
    // Use logMessage:level: which will call writeLogLine:
    [manager logMessage:message level:@("FORCE")];
}

@end
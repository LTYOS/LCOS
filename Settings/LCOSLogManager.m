//
//  LCOSLogManager.m
//  LCOS.dylib
//  Simplified, robust logging based on LCOrbit architecture
//

#import "LCOSLogManager.h"
#import "LCOSAppContainer.h"
#import <sys/file.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>

static const NSUInteger kLogLimit = 262144; // 256KB

@interface LCOSLogManager ()
@property (nonatomic, strong) NSString *logDirectory;
@property (nonatomic, strong) NSString *runtimeLogPath;
@property (nonatomic, strong) NSString *runtimeOldPath;
@end

@implementation LCOSLogManager

static LCOSLogManager *_sharedInstance = nil;

+ (instancetype)sharedManager {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[LCOSLogManager alloc] init];
    });
    return _sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self setupLogPaths];
    }
    return self;
}

- (void)setupLogPaths {
    // Use App Group path like LCOrbit does, fallback to Documents
    NSString *rootPath = [self logRootPath];
    if (!rootPath) {
        NSLog(@"LCOS: Failed to get log root path");
        return;
    }
    
    self.logDirectory = [rootPath stringByAppendingPathComponent:@"logs"];
    self.runtimeLogPath = [self.logDirectory stringByAppendingPathComponent:@"runtime.json"];
    self.runtimeOldPath = [self.runtimeLogPath.stringByDeletingPathExtension stringByAppendingString:@".old.json"];
    
    // Ensure directory exists synchronously
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:self.logDirectory withIntermediateDirectories:YES attributes:nil error:nil];
}

- (NSString *)logRootPath {
    // Try App Group first (like LCOrbit)
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *groupURL = [fm containerURLForSecurityApplicationGroupIdentifier:@"group.com.lcos.livecontainer"];
    if (groupURL) {
        NSString *path = [groupURL.path stringByAppendingPathComponent:@"LCOS"];
        [fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
        return path;
    }
    
    // Fallback to Documents/LCOS
    NSArray *docPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    if (docPaths.count > 0) {
        NSString *path = [docPaths[0] stringByAppendingPathComponent:@"LCOS"];
        [fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
        return path;
    }
    
    // Last resort: /tmp/LCOS
    NSString *tmpPath = @"/tmp/LCOS";
    [fm createDirectoryAtPath:tmpPath withIntermediateDirectories:YES attributes:nil error:nil];
    return tmpPath;
}

- (BOOL)ensureDirectory:(NSString *)path {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil]) {
        return NO;
    }
    struct stat info;
    return lstat(path.fileSystemRepresentation, &info) == 0 && S_ISDIR(info.st_mode);
}

- (int)lockFile:(NSString *)path {
    NSString *lockPath = [path stringByAppendingString:@".lock"];
    if (![self ensureDirectory:[lockPath stringByDeletingLastPathComponent]]) {
        return -1;
    }
    
    int descriptor = open(lockPath.fileSystemRepresentation, O_CREAT | O_RDWR | O_NOFOLLOW, 0600);
    if (descriptor < 0) return -1;
    if (flock(descriptor, LOCK_EX) != 0) {
        close(descriptor);
        return -1;
    }
    return descriptor;
}

- (NSMutableArray *)readEventsFromPath:(NSString *)path {
    if (!path) return [NSMutableArray array];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) return [NSMutableArray array];
    
    NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
    if (attrs && [attrs fileSize] > kLogLimit) return [NSMutableArray array];
    
    NSData *bytes = [NSData dataWithContentsOfFile:path];
    if (!bytes) return [NSMutableArray array];
    
    NSDictionary *document = [NSJSONSerialization JSONObjectWithData:bytes options:0 error:nil];
    if (![document isKindOfClass:[NSDictionary class]]) return [NSMutableArray array];
    if (![document[@"schemaVersion"] isEqual:@1]) return [NSMutableArray array];
    if (![document[@"events"] isKindOfClass:[NSArray class]]) return [NSMutableArray array];
    
    for (id event in document[@"events"]) {
        if (![event isKindOfClass:[NSDictionary class]]) return [NSMutableArray array];
        if (![event[@"event"] isKindOfClass:[NSString class]]) return [NSMutableArray array];
    }
    
    return [document[@"events"] mutableCopy];
}

- (NSData *)encodeEvents:(NSArray *)events {
    return [NSJSONSerialization dataWithJSONObject:@{@"schemaVersion": @1, @"events": events}
                                       options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                         error:nil];
}

- (NSString *)oldPathForPath:(NSString *)path {
    return [path.stringByDeletingPathExtension stringByAppendingString:@".old.json"];
}

- (NSDictionary *)createEvent:(NSString *)event details:(id)details {
    NSISO8601DateFormatter *format = [[NSISO8601DateFormatter alloc] init];
    NSString *guestID = @"LCOS-Guest";
    
    NSMutableDictionary *record = [@{
        @"timestamp": [format stringFromDate:[NSDate date]],
        @"guestID": guestID,
        @"context": @"guest",
        @"pid": @(getpid()),
        @"event": [event isKindOfClass:[NSString class]] ? event : @"unknown"
    } mutableCopy];
    
    if (details) {
        record[@"details"] = details;
    }
    
    // Validate JSON serializable
    if (![NSJSONSerialization isValidJSONObject:record]) {
        record[@"details"] = [details description] ?: @"";
    }
    
    // Truncate if too large
    NSData *encoded = [self encodeEvents:@[record]];
    if (encoded.length > kLogLimit / 2) {
        NSString *text = [details description] ?: @"";
        record[@"details"] = [text substringToIndex:MIN(text.length, 8192)];
        record[@"truncated"] = @YES;
        record[@"event"] = [record[@"event"] substringToIndex:MIN([record[@"event"] length], 256)];
        record[@"guestID"] = [guestID substringToIndex:MIN(guestID.length, 512)];
    }
    
    return record;
}

- (void)writeLogInternal:(NSString *)event details:(id)details {
    @try {
        @synchronized(self) {
            int descriptor = [self lockFile:self.runtimeLogPath];
            if (descriptor < 0) return;
            
            @try {
                NSMutableArray *events = [self readEventsFromPath:self.runtimeLogPath];
                if (!events) events = [NSMutableArray array];
                
                NSDictionary *record = [self createEvent:event details:details];
                [events addObject:record];
                
                NSData *bytes = [self encodeEvents:events];
                if (bytes.length > kLogLimit) {
                    // Rotate: keep only last event, move rest to .old.json
                    NSArray *previous = [events subarrayWithRange:NSMakeRange(0, events.count - 1)];
                    NSData *oldData = [self encodeEvents:previous];
                    if (oldData.length <= kLogLimit) {
                        [oldData writeToFile:[self oldPathForPath:self.runtimeLogPath] atomically:YES];
                    }
                    bytes = [self encodeEvents:@[events.lastObject]];
                }
                
                if (bytes.length <= kLogLimit) {
                    [bytes writeToFile:self.runtimeLogPath atomically:YES];
                }
            } @finally {
                flock(descriptor, LOCK_UN);
                close(descriptor);
            }
        }
    } @catch (NSException *exception) {
        // Logging must never break the guest
    }
}

- (void)logError:(NSError *)error {
    [self writeLogInternal:@"error" details:@{@"domain": error.domain, @"code": @(error.code), @"description": error.localizedDescription}];
}

- (void)logMessage:(NSString *)message level:(NSString *)level {
    [self writeLogInternal:level details:@{@"message": message}];
}

+ (void)forceLog:(NSString *)message {
    LCOSLogManager *manager = [LCOSLogManager sharedManager];
    [manager writeLogInternal:@"force" details:@{@"message": message}];
}

+ (void)clearLogs {
    LCOSLogManager *manager = [LCOSLogManager sharedManager];
    @try {
        @synchronized(manager) {
            int descriptor = [manager lockFile:manager.runtimeLogPath];
            if (descriptor < 0) return;
            
            @try {
                NSData *emptyData = [manager encodeEvents:@[]];
                if ([emptyData writeToFile:manager.runtimeLogPath atomically:YES]) {
                    NSFileManager *fm = [NSFileManager defaultManager];
                    [fm removeItemAtPath:[manager oldPathForPath:manager.runtimeLogPath] error:nil];
                }
            } @finally {
                flock(descriptor, LOCK_UN);
                close(descriptor);
            }
        }
    } @catch (NSException *exception) {
    }
}

+ (NSData *)exportLogsAsJSON {
    LCOSLogManager *manager = [LCOSLogManager sharedManager];
    @try {
        @synchronized(manager) {
            int descriptor = [manager lockFile:manager.runtimeLogPath];
            if (descriptor < 0) return [manager encodeEvents:@[]];
            
            @try {
                NSMutableArray *allEvents = [NSMutableArray array];
                
                // Read .old.json first
                NSString *oldPath = [manager oldPathForPath:manager.runtimeLogPath];
                NSArray *oldEvents = [manager readEventsFromPath:oldPath];
                if (oldEvents) [allEvents addObjectsFromArray:oldEvents];
                
                // Read current
                NSArray *currentEvents = [manager readEventsFromPath:manager.runtimeLogPath];
                if (currentEvents) [allEvents addObjectsFromArray:currentEvents];
                
                return [manager encodeEvents:allEvents];
            } @finally {
                flock(descriptor, LOCK_UN);
                close(descriptor);
            }
        }
    } @catch (NSException *exception) {
        return [manager encodeEvents:@[]];
    }
}

@end
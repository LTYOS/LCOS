//
//  LCOSLogManager.m
//  LCOS.dylib
//  Ultra-minimal logging - paths resolved lazily on first write
//

#import "LCOSLogManager.h"
#import "LCOSAppContainer.h"
#import <sys/file.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>

static const NSUInteger kLogLimit = 262144; // 256KB

@interface LCOSLogManager ()
@property (nonatomic, strong) NSString *runtimeLogPath;
@property (nonatomic, strong) NSString *runtimeOldPath;
@property (nonatomic, assign) BOOL pathsResolved;
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
        // DO NOTHING in init - paths resolved lazily
        _pathsResolved = NO;
    }
    return self;
}

- (void)resolvePathsIfNeeded {
    if (_pathsResolved) return;
    
    @synchronized(self) {
        if (_pathsResolved) return;
        
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *rootPath = nil;
        
        // Try App Group first
        NSURL *groupURL = [fm containerURLForSecurityApplicationGroupIdentifier:@"group.com.lcos.livecontainer"];
        if (groupURL) {
            rootPath = [groupURL.path stringByAppendingPathComponent:@"LCOS"];
        }
        
        // Fallback to Documents
        if (!rootPath) {
            NSArray *docPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
            if (docPaths.count > 0) {
                rootPath = [docPaths[0] stringByAppendingPathComponent:@"LCOS"];
            }
        }
        
        // Last resort: /tmp
        if (!rootPath) {
            rootPath = @"/tmp/LCOS";
        }
        
        _runtimeLogPath = [rootPath stringByAppendingPathComponent:@"logs/runtime.json"];
        _runtimeOldPath = [_runtimeLogPath.stringByDeletingPathExtension stringByAppendingString:@".old.json"];
        
        // Create directory synchronously but with error handling
        NSError *error = nil;
        [fm createDirectoryAtPath:[_runtimeLogPath stringByDeletingLastPathComponent]
              withIntermediateDirectories:YES
                               attributes:nil
                                 error:&error];
        
        _pathsResolved = YES;
    }
}

- (NSMutableArray *)readEventsFromPath:(NSString *)path {
    if (!path) return [NSMutableArray array];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) return [NSMutableArray array];
    
    NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
    if (attrs && [attrs fileSize] > 262144) return [NSMutableArray array];
    
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
    
    if (![NSJSONSerialization isValidJSONObject:record]) {
        record[@"details"] = [details description] ?: @"";
    }
    
    NSData *encoded = [self encodeEvents:@[record]];
    if (encoded.length > 131072) { // 128KB limit per event
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
            [self resolvePathsIfNeeded];
            
            int descriptor = open([_runtimeLogPath stringByAppendingString:@".lock"].fileSystemRepresentation, O_CREAT | O_RDWR | O_NOFOLLOW, 0600);
            if (descriptor < 0) return;
            if (flock(descriptor, LOCK_EX) != 0) {
                close(descriptor);
                return;
            }
            
            @try {
                NSMutableArray *events = [self readEventsFromPath:_runtimeLogPath];
                if (!events) events = [NSMutableArray array];
                
                NSDictionary *record = [self createEvent:event details:details];
                [events addObject:record];
                
                NSData *bytes = [self encodeEvents:events];
                if (bytes.length > 262144) {
                    NSArray *previous = [events subarrayWithRange:NSMakeRange(0, events.count - 1)];
                    NSData *oldData = [self encodeEvents:previous];
                    if (oldData.length <= 262144) {
                        [oldData writeToFile:[_runtimeLogPath.stringByDeletingPathExtension stringByAppendingString:@".old.json"] atomically:YES];
                    }
                    bytes = [self encodeEvents:@[events.lastObject]];
                }
                
                if (bytes.length <= 262144) {
                    [bytes writeToFile:_runtimeLogPath atomically:YES];
                }
            } @finally {
                flock(descriptor, LOCK_UN);
                close(descriptor);
            }
        }
    } @catch (NSException *exception) {
        // Silent fail
    }
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
    
    if (![NSJSONSerialization isValidJSONObject:record]) {
        record[@"details"] = [details description] ?: @"";
    }
    
    return record;
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
            [manager resolvePathsIfNeeded];
            int descriptor = open([manager->_runtimeLogPath stringByAppendingString:@".lock"].fileSystemRepresentation, O_CREAT | O_RDWR | O_NOFOLLOW, 0600);
            if (descriptor < 0) return;
            if (flock(descriptor, LOCK_EX) != 0) { close(descriptor); return; }
            
            @try {
                NSData *emptyData = [manager encodeEvents:@[]];
                [emptyData writeToFile:manager->_runtimeLogPath atomically:YES];
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
            [manager resolvePathsIfNeeded];
            int descriptor = open([manager->_runtimeLogPath stringByAppendingString:@".lock"].fileSystemRepresentation, O_CREAT | O_RDWR | O_NOFOLLOW, 0600);
            if (descriptor < 0) return [manager encodeEvents:@[]];
            if (flock(descriptor, LOCK_EX) != 0) { close(descriptor); return [manager encodeEvents:@[]]; }
            
            @try {
                NSMutableArray *allEvents = [NSMutableArray array];
                
                NSString *oldPath = [manager->_runtimeLogPath.stringByDeletingPathExtension stringByAppendingString:@".old.json"];
                NSArray *oldEvents = [manager readEventsFromPath:oldPath];
                if (oldEvents) [allEvents addObjectsFromArray:oldEvents];
                
                NSArray *currentEvents = [manager readEventsFromPath:manager->_runtimeLogPath];
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
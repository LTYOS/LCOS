//
//  LCOSCore.m
//  LCOS.dylib
//

#import "LCOSCore.h"
#import "LCOSXPC.h"
#import "LCOSConfig.h"
#import "LCOSLogManager.h"
#import <mach/mach.h>

static NSMutableDictionary<NSUUID *, LCOSCore *> *_launches = nil;
static NSMutableDictionary<NSNumber *, LCOSCore *> *_processesByPID = nil;

@implementation LCOSCore

// Constructor entry point for LiveContainer plugin initialization
// This ensures startXPCServer is called when the dylib is loaded
__attribute__((constructor))
+ (void)constructorStartServer {
    // Write unconditional log to verify code execution
    [[LCOSLogManager sharedManager] forceLog:@("LCOS constructor: startServer invoked")];
    [LCOSCore startServer];
    [[LCOSLogManager sharedManager] forceLog:@("LCOS constructor: startServer completed")];
}

+ (void)startServer {
    [LCOSXPC startXPCServer];
}

+ (nullable LCOSCore *)processWithPID:(pid_t)pid {
    return [_processesByPID objectForKey:@(pid)];
}

+ (void)resolvePendingRequests {
    for (NSNumber *pidKey in [_launches allKeys]) {
        LCOSCore *process = [_launches objectForKey:pidKey];
        if (!process) continue;
        xpc_connection_t peer = [LCOSXPC pendingConnectionForPID:pidKey.intValue];
        xpc_object_t request = [LCOSXPC pendingRequestForPID:pidKey.intValue];
        if (process && !process.connection) {
            process.connection = peer;
            process.configurationRequest = request;
            [process deliverConfiguration];
        }
    }
}

+ (instancetype)initWithUUID:(NSUUID *)identifier configuration:(NSDictionary *)configuration {
    LCOSCore *core = [[LCOSCore alloc] init];
    core.identifier = identifier;
    NSError *error = nil;
    core.configurationData = [NSKeyedArchiver archivedDataWithRootObject:configuration requiringSecureCoding:NO error:&error];
    core.finished = NO;
    
    if (!_launches) _launches = [NSMutableDictionary new];
    if (!_processesByPID) _processesByPID = [NSMutableDictionary new];
    
    _launches[core.identifier] = core;
    // Get PID from process info for consistent lookup
    pid_t procPid = 0;
    // Use identifier as key for both dictionaries; processWithPID will use same key
    _processesByPID[@(procPid)] = core;
    
    [LCOSConfig loadDefaultConfig];
    
    return core;
}

#pragma mark - Instance Methods

- (void)deliverConfiguration {
    if (!self.configurationRequest || self.finished) return;
    xpc_object_t reply = xpc_dictionary_create_reply(self.configurationRequest);
    if (!reply) {
        [self failWithError:[NSError errorWithDomain:@"LCOSCore" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Invalid LivePlugIn launch request"}]];
        return;
    }
    xpc_dictionary_set_data(reply, "payload", self.configurationData.bytes, self.configurationData.length);
    xpc_connection_send_message(self.connection, reply);
    self.configurationRequest = nil;
    self.configurationData = nil;
    self.finished = YES;
}

- (void)failWithError:(NSError *)error {
    [[LCOSLogManager sharedManager] logError:error];
    [[NSUserDefaults standardUserDefaults] setObject:[NSString stringWithFormat:@"LCOS encountered an error: %@", error.localizedDescription] forKey:@"error"];
}

@end
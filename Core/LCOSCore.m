//
//  LCOSCore.m
//  LCOS.dylib
//

#import "LCOSCore.h"
#import "LCOSXPC.h"
#import "LCOSConfig.h"
#import "LCOSLogManager.h"
#import <mach/mach.h>

static NSMutableDictionary<NSUUID *, LCOSCore *> *_launches;
static NSMutableDictionary<NSNumber *, LCOSCore *> *_processesByPID;

@implementation LCOSCore

#pragma mark - Class Methods

+ (void)startServer {
    [LCOSXPC startXPCServer];
}

+ (nullable LCOSCore *)processWithPID:(pid_t)pid {
    NSNumber *pidKey = @(pid);
    LCOSCore *process = [_processesByPID objectForKey:pidKey];
    if (!process) {
        process = [_launches allValues].firstObject;
        if (process && process.pid == pid) {
            _processesByPID[pidKey] = process;
        }
    }
    return process;
}

+ (void)resolvePendingRequests {
    for (NSNumber *pidKey in [LCOSXPC pendingConnectionForPID:0 ? @[] : @[]]) {
        // delegate to LCOSXPC singleton
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
    
    _launches[identifier] = core;
    
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
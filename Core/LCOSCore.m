//
//  LCOSCore.m
//  LCOS.dylib
//

#import "LCOSCore.h"
#import "LCOSXPC.h"
#import "LCOSConfig.h"
#import "LCOSGestureHandler.h"
#import "LCOSLogManager.h"

static NSMutableDictionary<NSUUID *, LCOSCore *> *launches;

@implementation LCOSCore

#pragma mark - Class Methods

+ (void)startServer {
    // Delegate to LCOSXPC for bootstrap/XPC listener setup
    [LCOSXPC startXPCServer];
}

+ (void)resolvePendingRequests {
    BOOL isSpawning = NO;
    for (LCOSCore *process in launches.allValues) {
        if (!process.identifier) isSpawning = YES;
    }
    for (NSNumber *pid in [[LCOSXPC new] pendingRequests].allKeys) {
        LCOSCore *process = [LCOSXPC processWithPID:pid.intValue];
        xpc_connection_t peer = [[LCOSXPC new] pendingConnections][pid];
        xpc_object_t request = [[LCOSXPC new] pendingRequests][pid];
        if (process && !process.connection) {
            process.connection = peer;
            process.configurationRequest = request;
            [process deliverConfiguration];
        } else {
            continue;
        }
        [[[LCOSXPC new] pendingConnections] removeObjectForKey:pid];
        [[[LCOSXPC new] pendingRequests] removeObjectForKey:pid];
    }
}

+ (instancetype)initWithUUID:(NSUUID *)identifier configuration:(NSDictionary *)configuration {
    LCOSCore *core = [[LCOSCore alloc] init];
    core.identifier = identifier;
    NSError *error = nil;
    core.configurationData = [NSKeyedArchiver archivedDataWithRootObject:configuration requiringSecureCoding:NO error:&error];
    core.finished = NO;
    
    launches[core.identifier] = core;
    
    // Load default LCOS configuration
    [[LCOSConfig new] loadDefaultConfig];
    
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
}

- (void)failWithError:(NSError *)error {
    [[LCOSLogManager sharedManager] logError:error];
    [[NSUserDefaults standardUserDefaults] setObject:[NSString stringWithFormat:@"LCOS encountered an error: %@", error.localizedDescription] forKey:@"error"];
}

@end

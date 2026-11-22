//
//  LCOSCore.m
//  LCOS.dylib
//

#import "LCOSCore.h"
#import "LCOSXPC.h"
#import "LCOSConfig.h"
#import "LCOSGestureHandler.h"
#import "LCOSLogManager.h"

@interface LCOSCore ()

@property (nonatomic) NSUUID *identifier;
@property (nonatomic) NSData *configurationData;
@property (nonatomic) xpc_connection_t connection;
@property (nonatomic) xpc_object_t configurationRequest;
@property (nonatomic) BOOL finished;

@end

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
        if (!process.pid) isSpawning = YES;
    }
    for (NSNumber *pid in LCOSXPC.pendingRequests.allKeys) {
        LCOSCore *process = [LCOSXPC processWithPID:pid.intValue];
        xpc_connection_t peer = LCOSXPC.pendingConnections[pid];
        xpc_object_t request = LCOSXPC.pendingRequests[pid];
        if (process && !process.connection) {
            process.connection = peer;
            process.configurationRequest = request;
            [process deliverConfiguration];
        } else {
            continue;
        }
        [LCOSXPC.pendingConnections removeObjectForKey:pid];
        [LCOSXPC.pendingRequests removeObjectForKey:pid];
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
}

- (void)failWithError:(NSError *)error {
    [[LCOSLogManager sharedManager] logError:error];
    [NSUserDefaults.lcUserDefaults setObject:[NSString stringWithFormat:@"LCOS encountered an error: %@", error.localizedDescription] forKey:@"error"];
}

@end

//
//  LCOSXPC.m
//  LCOS.dylib
//

#import "LCOSXPC.h"
#import "LCOSCore.h"
#import "LCOSConfig.h"
#import "LCOSGestureHandler.h"
#import <xpc/xpc.h>
#import <mach/mach.h>
#import <dispatch/dispatch.h>
#import <spawn.h>

@implementation LCOSXPC

+ (void)startXPCServer {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        LCOSXPC *instance = [LCOSXPC new];
        [instance setupXPC];
    });
}

+ (void)resolvePendingRequests {
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

+ (id)processWithPID:(pid_t)pid {
    for (LCOSCore *process in LCOSXPC.processesByPID.allValues) {
        if (process.pid == pid) return process;
    }
    return nil;
}

- (void)setupXPC {
    NSString *appGroup = LCSharedUtils.appGroupID;
    if (!appGroup.length) {
        [[LCOSLogManager sharedManager] logError:[NSError errorWithDomain:@"LCOSXPC" code:1 description:@"Missing app group"]];
        return;
    }
    
    // Create XPC listener
    dispatch_queue_t xpcQueue = dispatch_queue_create("com.lcos.livecontainer.xpc.handling", DISPATCH_QUEUE_SERIAL);
    self.listener = xpc_connection_create(NULL, xpcQueue);
    
    if (!self.listener) {
        [[LCOSLogManager sharedManager] logError:[NSError errorWithDomain:@"LCOSXPC" code:2 description:@"Unable to create XPC listener"]];
        return;
    }
    
    xpc_connection_set_event_handler(self.listener, ^(xpc_object_t peer) {
        if (xpc_get_type(peer) != XPC_TYPE_CONNECTION) {
            [[LCOSLogManager sharedManager] logError:[NSError errorWithDomain:@"LCOSXPC" code:3 description:@"Invalid XPC connection"]];
            xpc_connection_cancel(peer);
            return;
        }
        
        xpc_connection_set_target_queue(peer, xpcQueue);
        __weak xpc_connection_t weakPeer = peer;
        xpc_connection_set_event_handler(peer, ^(xpc_object_t event) {
            xpc_connection_t peer = weakPeer;
            if (!peer) return;
            
            NSNumber *pid = @(LCXPCConnectionGetPID(peer));
            LCOSCore *process = [LCOSXPC processWithPID:pid.intValue];
            
            if (xpc_get_type(event) == XPC_TYPE_ERROR) {
                if (LCOSXPC.pendingConnections[pid] == peer) {
                    [LCOSXPC.pendingConnections removeObjectForKey:pid];
                    [LCOSXPC.pendingRequests removeObjectForKey:pid];
                }
                xpc_connection_cancel(peer);
                return;
            }
            
            if (xpc_get_type(event) != XPC_TYPE_DICTIONARY) {
                xpc_connection_cancel(peer);
                return;
            }
            
            int64_t command = xpc_dictionary_get_int64(event, "cmd");
            
            if (command == LCOSXPCCommandConnect) {
                if (pid.intValue <= 0 || process.connection || LCOSXPC.pendingConnections[pid]) {
                    xpc_connection_cancel(peer);
                    return;
                }
                LCOSXPC.pendingConnections[pid] = peer;
                [LCOSXPC resolvePendingRequests];
            } else if (command == LCOSXPCCommandLaunchConfiguration) {
                if (!process.connection) {
                    LCOSXPC.pendingConnections[pid] = nil; // 稍后通过 resolvePendingRequests 关联
                    LCOSXPC.pendingRequests[pid] = event;
                    [LCOSXPC resolvePendingRequests];
                } else {
                    xpc_connection_cancel(peer);
                }
            } else if (command == LCOSXPCCommandError) {
                if (process.connection == peer) {
                    const char *message = xpc_dictionary_get_string(event, "error");
                    xpc_object_t reply = xpc_dictionary_create_reply(event);
                    if (reply) xpc_connection_send_message(peer, reply);
                }
                xpc_connection_cancel(peer);
            } else {
                xpc_connection_cancel(peer);
            }
        });
        
        xpc_connection_resume(peer);
        
        // Timeout handler
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, LCOSXPCLaunchTimeout * NSEC_PER_SEC), xpcQueue, ^{
            NSNumber *pid = @(LCXPCConnectionGetPID(peer));
            LCOSCore *p = [LCOSXPC processWithPID:pid.intValue];
            if ([p.connection != peer]) xpc_connection_cancel(peer);
        });
    });
    
    xpc_connection_resume(self.listener);
    
    // Bootstrap setup for Mach service
    NSString *serviceName = [NSString stringWithFormat:@"%@.LCOS.%d", appGroup, getpid()];
    mach_port_t service = MACH_PORT_NULL;
    kern_return_t kr = bootstrap_check_in(mach_task_self(), [serviceName UTF8String], &service);
    
    if (kr != KERN_SUCCESS || !MACH_PORT_VALID(service)) {
        [[LCOSLogManager sharedManager] logError:[NSError errorWithDomain:@"LCOSXPC" code:4 description:[NSString stringWithFormat:@"Unable to register bootstrap service (%d)", kr]]];
        return;
    }
    
    // Create bootstrap source
    xpc_endpoint_t endpoint = xpc_endpoint_create(self.listener);
    self.bootstrapSource = endpoint ? dispatch_source_create(DISPATCH_SOURCE_TYPE_MACH_RECV, service, 0, NULL) : nil;
    
    if (!self.bootstrapSource) {
        xpc_connection_cancel(self.listener);
        self.listener = nil;
        mach_port_mod_refs(mach_task_self(), service, MACH_PORT_RIGHT_RECEIVE, -1);
        [[LCOSLogManager sharedManager] logError:[NSError errorWithDomain:@"LCOSXPC" code:5 description:@"Unable to create bootstrap source"]];
        return;
    }
    
    dispatch_source_set_event_handler(self.bootstrapSource, ^(void) {
        xpc_object_t request = nil;
        int error = xpc_pipe_receive(service, &request, 0);
        if (error || !request || xpc_get_type(request) != XPC_TYPE_DICTIONARY) return;
        
        xpc_object_t reply = xpc_dictionary_create_reply(request);
        if (!reply) return;
        
        audit_token_t audit = {{0}};
        xpc_dictionary_get_audit_token(request, &audit);
        
        if (audit.val[5] && xpc_dictionary_get_int64(request, @"cmd") == LCOSXPCCommandConnect) {
            xpc_dictionary_set_value(reply, @"listener", endpoint);
        } else {
            xpc_dictionary_set_string(reply, @"error", @"Invalid LCOS connection request");
        }
        
        xpc_pipe_routine_reply(reply);
    });
    
    dispatch_source_set_cancel_handler(self.bootstrapSource, ^{
        mach_port_mod_refs(mach_task_self(), service, MACH_PORT_RIGHT_RECEIVE, -1);
    });
    
    dispatch_resume(self.bootstrapSource);
}

@end
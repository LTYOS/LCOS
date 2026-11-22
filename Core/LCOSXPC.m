//
//  LCOSXPC.m
//  LCOS.dylib
//

#import "LCOSXPC.h"
#import "LCOSCore.h"
#import "LCOSConfig.h"
#import "LCOSLogManager.h"
#import <mach/mach.h>
#import <dispatch/dispatch.h>
#import <stdlib.h>

@implementation LCOSXPC {
    xpc_connection_t _listener;
    dispatch_source_t _bootstrapSource;
    NSMutableDictionary<NSNumber *, xpc_connection_t> *_pendingConnections;
    NSMutableDictionary<NSNumber *, xpc_object_t> *_pendingRequests;
    NSMutableDictionary<NSNumber *, LCOSCore *> *_processesByPID;
}

+ (void)startXPCServer {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        LCOSXPC *instance = [LCOSXPC new];
        [instance setupXPC];
    });
}

+ (void)resolvePendingRequests {
    for (NSNumber *pidKey in [_processesByPID allKeys]) {
        LCOSCore *process = [_processesByPID objectForKey:pidKey];
        xpc_connection_t peer = [_pendingConnections objectForKey:pidKey];
        xpc_object_t request = [_pendingRequests objectForKey:pidKey];
        if (process && peer && request) {
            process->_connection = peer;
            process->_configurationRequest = request;
            [process deliverConfiguration];
            [_pendingConnections removeObjectForKey:pidKey];
            [_pendingRequests removeObjectForKey:pidKey];
        }
    }
}

+ (nullable id)processWithPID:(pid_t)pid {
    NSNumber *pidKey = @(pid);
    return [_processesByPID objectForKey:pidKey];
}

+ (nullable xpc_connection_t)pendingConnectionForPID:(pid_t)pid {
    return [_pendingConnections objectForKey:@(pid)];
}

+ (nullable xpc_object_t)pendingRequestForPID:(pid_t)pid {
    return [_pendingRequests objectForKey:@(pid)];
}

+ (void)clearPendingForPID:(pid_t)pid {
    NSNumber *pidKey = @(pid);
    [_pendingConnections removeObjectForKey:pidKey];
    [_pendingRequests removeObjectForKey:pidKey];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _listener = nil;
        _bootstrapSource = nil;
        _pendingConnections = [NSMutableDictionary new];
        _pendingRequests = [NSMutableDictionary new];
        _processesByPID = [NSMutableDictionary new];
    }
    return self;
}

- (void)setupXPC {
    // Create XPC listener
    dispatch_queue_t xpcQueue = dispatch_queue_create("com.lcos.livecontainer.xpc.handling", DISPATCH_QUEUE_SERIAL);
    _listener = xpc_connection_create(NULL, xpcQueue);
    
    if (!_listener) {
        [[LCOSLogManager sharedManager] logError:[NSError errorWithDomain:@"LCOSXPC" code:2 userInfo:nil]];
        return;
    }
    
    xpc_connection_set_event_handler(_listener, ^(xpc_object_t peer) {
        if (xpc_get_type(peer) != XPC_TYPE_CONNECTION) {
            [[LCOSLogManager sharedManager] logError:[NSError errorWithDomain:@"LCOSXPC" code:3 userInfo:nil]];
            xpc_connection_cancel(peer);
            return;
        }
        
        xpc_connection_set_target_queue(peer, xpcQueue);
        __weak xpc_connection_t weakPeer = peer;
        xpc_connection_set_event_handler(peer, ^(xpc_object_t event) {
            xpc_connection_t peer = weakPeer;
            if (!peer) return;
            
            NSNumber *pid = [NSNumber numberWithInt:LCXPCConnectionGetPID(peer)];
            LCOSCore *process = [self processWithPID:pid.intValue];
            
            if (xpc_get_type(event) == XPC_TYPE_ERROR) {
                [LCOSXPC clearPendingForPID:pid.intValue];
                xpc_connection_cancel(peer);
                return;
            }
            
            if (xpc_get_type(event) != XPC_TYPE_DICTIONARY) {
                xpc_connection_cancel(peer);
                return;
            }
            
            int64_t command = xpc_dictionary_get_int64(event, "cmd");
            
            if (command == LCOSXPCCommandConnect) {
                if (pid.intValue <= 0) {
                    xpc_connection_cancel(peer);
                    return;
                }
                [_pendingConnections setObject:peer forKey:pid];
                [LCOSXPC resolvePendingRequests];
            } else if (command == LCOSXPCCommandLaunchConfiguration) {
                if (![_pendingConnections objectForKey:pid]) {
                    [_pendingRequests setObject:event forKey:pid];
                    [LCOSXPC resolvePendingRequests];
                } else {
                    xpc_connection_cancel(peer);
                }
            } else if (command == LCOSXPCCommandError) {
                if ([_pendingConnections objectForKey:pid] == peer) {
                    xpc_object_t reply = xpc_dictionary_create_reply(event);
                    if (reply) xpc_connection_send_message(peer, reply);
                }
                xpc_connection_cancel(peer);
            } else {
                xpc_connection_cancel(peer);
            }
        });
        
        xpc_connection_resume(peer);
    });
    
    xpc_connection_resume(_listener);
}

@end

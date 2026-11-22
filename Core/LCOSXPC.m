//
//  LCOSXPC.m
//  LCOS.dylib
//

#import "LCOSXPC.h"
#import "LCOSCore.h"
#import "LCOSConfig.h"
#import "LCOSLogManager.h"
#import "LCOSGestureHandler.h"
#import <mach/mach.h>
#import <dispatch/dispatch.h>

// Forward declarations for LiveContainer private XPC APIs
extern mach_port_t bootstrap_port;
extern kern_return_t bootstrap_check_in(mach_port_t bootstrap, const char *name, mach_port_t *port);
extern int xpc_pipe_receive(mach_port_t port, xpc_object_t _Nullable __strong * _Nonnull message, uint64_t flags);
extern int xpc_pipe_routine_reply(xpc_object_t reply);
extern void xpc_dictionary_get_audit_token(xpc_object_t dictionary, audit_token_t *token);
extern pid_t LCXPCConnectionGetPID(xpc_connection_t connection) __asm("_xpc_connection_get_pid");

@implementation LCOSXPC

// Static variables for XPC server state
static xpc_connection_t _listener = NULL;
static dispatch_source_t _bootstrapSource = NULL;
static NSMutableDictionary<NSNumber *, xpc_connection_t> *_pendingConnections = nil;
static NSMutableDictionary<NSNumber *, xpc_object_t> *_pendingRequests = nil;
static NSMutableDictionary<NSNumber *, LCOSCore *> *_processesByPID = nil;

// Class method to initialize static variables
+ (void)initialize {
    [super initialize];
    if (_pendingConnections == nil) {
        _pendingConnections = [NSMutableDictionary new];
    }
    if (_pendingRequests == nil) {
        _pendingRequests = [NSMutableDictionary new];
    }
    if (_processesByPID == nil) {
        _processesByPID = [NSMutableDictionary new];
    }
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
            [process setConnection:peer];
            [process setConfigurationRequest:request];
            [process deliverConfiguration];
            [_pendingConnections removeObjectForKey:pidKey];
            [_pendingRequests removeObjectForKey:pidKey];
        }
    }
}

+ (nullable id)processWithPID:(pid_t)pid {
    return [_processesByPID objectForKey:@(pid)];
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
    }
    return self;
}

- (void)setupXPC {
    // Create XPC listener
    dispatch_queue_t xpcQueue = dispatch_queue_create("com.lcos.livecontainer.xpc.handling", DISPATCH_QUEUE_SERIAL);
    _listener = xpc_connection_create(NULL, xpcQueue);
    
    if (!_listener) {
        [[LCOSLogManager sharedManager] logError:[NSError errorWithDomain:@"LCOSXPC" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Unable to create XPC listener"}]];
        return;
    }
    
    xpc_connection_set_event_handler(_listener, ^(xpc_object_t peer) {
        if (xpc_get_type(peer) != XPC_TYPE_CONNECTION) {
            [[LCOSLogManager sharedManager] logError:[NSError errorWithDomain:@"LCOSXPC" code:3 userInfo:@{NSLocalizedDescriptionKey: @"Invalid XPC connection"}]];
            xpc_connection_cancel(peer);
            return;
        }
        
        xpc_connection_set_target_queue(peer, xpcQueue);
        __weak xpc_connection_t weakPeer = peer;
        xpc_connection_set_event_handler(peer, ^(xpc_object_t event) {
            xpc_connection_t peer = weakPeer;
            if (!peer) return;
            
            // Get PID from the XPC connection using the proper API
            pid_t pid = LCXPCConnectionGetPID(peer);
            NSNumber *pidNum = @(pid);
            
            if (xpc_get_type(event) == XPC_TYPE_ERROR) {
                [LCOSXPC clearPendingForPID:pid];
                xpc_connection_cancel(peer);
                return;
            }
            
            if (xpc_get_type(event) != XPC_TYPE_DICTIONARY) {
                xpc_connection_cancel(peer);
                return;
            }
            
            int64_t command = xpc_dictionary_get_int64(event, "cmd");
            
            if (command == LCOSXPCCommandConnect) {
                if (pid <= 0) {
                    xpc_connection_cancel(peer);
                    return;
                }
                // Check if we already have a connection for this PID
                if ([_pendingConnections objectForKey:pidNum] == peer) {
                    // Already connected, just resume and resolve
                    xpc_connection_resume(peer);
                    [LCOSXPC resolvePendingRequests];
                    return;
                }
                // Store the new connection and resolve pending requests
                [_pendingConnections setObject:peer forKey:pidNum];
                [LCOSXPC resolvePendingRequests];
                xpc_connection_resume(peer);
            } else if (command == LCOSXPCCommandLaunchConfiguration) {
                if (![_pendingConnections objectForKey:pidNum]) {
                    [_pendingRequests setObject:event forKey:pidNum];
                    [LCOSXPC resolvePendingRequests];
                } else {
                    xpc_connection_cancel(peer);
                }
            } else if (command == LCOSXPCCommandError) {
                if ([_pendingConnections objectForKey:pidNum] == peer) {
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
    
    // Bootstrap setup for Mach service
    NSString *appGroup = LCOSConfig.appGroupID;
    NSString *serviceName = [NSString stringWithFormat:@"%@.LCOS.%d", appGroup, getpid()];
    mach_port_t service = MACH_PORT_NULL;
    kern_return_t kr = bootstrap_check_in(mach_task_self(), [serviceName UTF8String], &service);
    
    if (kr != KERN_SUCCESS || !MACH_PORT_VALID(service)) {
        NSString *errorDesc = [NSString stringWithFormat:@"Unable to register bootstrap service (%d)", (int)kr];
        [[LCOSLogManager sharedManager] logError:[NSError errorWithDomain:@"LCOSXPC" code:1 userInfo:@{NSLocalizedDescriptionKey: errorDesc}]];
        return;
    }
    
    // Create bootstrap source
    xpc_endpoint_t endpoint = xpc_endpoint_create(_listener);
    _bootstrapSource = endpoint ? dispatch_source_create(DISPATCH_SOURCE_TYPE_MACH_RECV, service, 0, NULL) : nil;
    
    if (!_bootstrapSource) {
        xpc_connection_cancel(_listener);
        _listener = nil;
        mach_port_mod_refs(mach_task_self(), service, MACH_PORT_RIGHT_RECEIVE, -1);
        [[LCOSLogManager sharedManager] logError:[NSError errorWithDomain:@"LCOSXPC" code:5 userInfo:@{NSLocalizedDescriptionKey: @"Unable to create bootstrap source"}]];
        return;
    }
    
    dispatch_source_set_event_handler(_bootstrapSource, ^(void) {
        xpc_object_t request = nil;
        int error = xpc_pipe_receive(service, &request, 0);
        if (error || !request || xpc_get_type(request) != XPC_TYPE_DICTIONARY) return;
        
        xpc_object_t reply = xpc_dictionary_create_reply(request);
        if (!reply) return;
        
        audit_token_t audit = {{0}};
        xpc_dictionary_get_audit_token(request, &audit);
        
        if (audit.val[5] && xpc_dictionary_get_int64(request, "cmd") == LCOSXPCCommandConnect) {
            xpc_dictionary_set_value(reply, "listener", endpoint);
        } else {
            xpc_dictionary_set_string(reply, "error", "Invalid LCOS connection request");
        }
        
        xpc_pipe_routine_reply(reply);
    });
    
    dispatch_source_set_cancel_handler(_bootstrapSource, ^{
        mach_port_mod_refs(mach_task_self(), service, MACH_PORT_RIGHT_RECEIVE, -1);
    });
    
    dispatch_resume(_bootstrapSource);
}

@end
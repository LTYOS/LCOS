#pragma once

#import <Foundation/Foundation.h>
#import <sys/types.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(int64_t, LCOSXPCCommand) {
    LCOSXPCCommandConnect = 1,
    LCOSXPCCommandLaunchConfiguration = 2,
    LCOSXPCCommandError = 3,
};

static const NSTimeInterval LCOSXPCLaunchTimeout = 30;

@interface LCOSXPC : NSObject

@property (nonatomic, readonly) xpc_connection_t listener;
@property (nonatomic, readonly) dispatch_source_t bootstrapSource;
@property (nonatomic, readonly, strong) NSMutableDictionary<NSNumber *, xpc_connection_t> *pendingConnections;
@property (nonatomic, readonly, strong) NSMutableDictionary<NSNumber *, xpc_object_t> *pendingRequests;
@property (nonatomic, readonly, strong) NSMutableDictionary<NSNumber *, id> *processesByPID;

+ (void)startXPCServer;
+ (void)resolvePendingRequests;
+ (id)processWithPID:(pid_t)pid;

@end

NS_ASSUME_NONNULL_END

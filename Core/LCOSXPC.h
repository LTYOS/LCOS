#pragma once

#import <Foundation/Foundation.h>
#import <xpc/xpc.h>
#import <sys/types.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(int64_t, LCOSXPCCommand) {
    LCOSXPCCommandConnect = 1,
    LCOSXPCCommandLaunchConfiguration = 2,
    LCOSXPCCommandError = 3,
};

static const NSTimeInterval LCOSXPCLaunchTimeout = 30;

@interface LCOSXPC : NSObject

/// 启动 XPC 服务端（bootstrap 注册 + 监听）
+ (void)startXPCServer;

/// 通过 pid 找到对应的 launch 记录
+ (nullable id)processWithPID:(pid_t)pid;

/// 把待处理的连接 / 请求与进程配对
+ (void)resolvePendingRequests;

/// 取某个 pid 上挂起的连接
+ (nullable xpc_connection_t)pendingConnectionForPID:(pid_t)pid;

/// 取某个 pid 上挂起的请求
+ (nullable xpc_object_t)pendingRequestForPID:(pid_t)pid;

/// 清理某个 pid 的挂起状态
+ (void)clearPendingForPID:(pid_t)pid;

@end

NS_ASSUME_NONNULL_END

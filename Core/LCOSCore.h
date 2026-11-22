#pragma once

#import <Foundation/Foundation.h>
#import <xpc/xpc.h>

NS_ASSUME_NONNULL_BEGIN

/// 一次 LiveContainer 应用启动的会话记录。
@interface LCOSCore : NSObject

@property (nonatomic, copy, nullable) NSUUID *identifier;
@property (nonatomic, copy, nullable) NSData *configurationData;
@property (nonatomic, assign) BOOL finished;
@property (nonatomic, assign) pid_t pid;
@property (nonatomic, assign) xpc_connection_t connection;
@property (nonatomic, assign) xpc_object_t configurationRequest;

+ (instancetype)initWithUUID:(NSUUID *)identifier configuration:(NSDictionary *)configuration;

/// 启动插件服务端（XPC 监听）
+ (void)startServer;

/// 拿到某个 pid 对应的会话
+ (nullable LCOSCore *)processWithPID:(pid_t)pid;

/// 把待处理的连接与请求配给会话
+ (void)resolvePendingRequests;

- (void)deliverConfiguration;
- (void)failWithError:(NSError *)error;

@end

NS_ASSUME_NONNULL_END

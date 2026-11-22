#pragma once

#import <Foundation/Foundation.h>
#import <xpc/xpc.h>

@interface LCOSCore : NSObject
@property (nonatomic, copy) NSUUID *identifier;
@property (nonatomic, copy) NSData *configurationData;
@property (nonatomic) xpc_connection_t connection;
@property (nonatomic) xpc_object_t configurationRequest;
@property (nonatomic) BOOL finished;

+ (instancetype)initWithUUID:(NSUUID *)identifier configuration:(NSDictionary *)configuration;
+ (void)startServer;
+ (void)resolvePendingRequests;
- (void)deliverConfiguration;
- (void)failWithError:(NSError *)error;
@end

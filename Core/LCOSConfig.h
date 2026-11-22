#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// LCOS 的配置读写入口。
@interface LCOSConfig : NSObject

/// LiveContainer 的 App Group 标识
+ (NSString *)appGroupID;

/// 默认配置字典
+ (NSDictionary *)defaultConfigurationData;

/// 首次运行时创建默认配置，已有配置则保持不变
+ (void)loadDefaultConfig;

/// 读取磁盘上的配置，失败时回落到默认值
+ (NSDictionary *)configuration;

/// 保存配置
+ (BOOL)saveConfiguration:(NSDictionary *)configuration;

@end

NS_ASSUME_NONNULL_END

#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LCOSConfig : NSObject

@property (nonatomic, copy) NSString *defaultAppGroupPath;
@property (nonatomic, copy) NSDictionary *defaultConfigurationData;

+ (void)loadDefaultConfig;
+ (NSString *)appGroupID;
+ (NSDictionary *)defaultConfigurationData;
+ (void)writeDefaultConfigToPath:(NSString *)path;
@end

NS_ASSUME_NONNULL_END

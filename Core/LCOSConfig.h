#pragma once

#import <Foundation/Foundation.h>
#import <NSArray/NSArray.h>

NS_ASSUME_NONNULL_BEGIN

@interface LCOSConfig : NSObject

@property (nonatomic, copy) NSString *defaultAppGroupPath;
@property (nonatomic, copy) NSDictionary *defaultConfigurationData;

@end

NS_ASSUME_NONNULL_END

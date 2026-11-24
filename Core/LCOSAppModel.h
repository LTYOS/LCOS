#pragma once

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 单个已安装应用的模型，对应 LiveContainer 内的一个 .app
@interface LCOSAppModel : NSObject

@property (nonatomic, copy, readonly) NSString *bundleIdentifier;
@property (nonatomic, copy, readonly) NSString *displayName;
@property (nonatomic, copy, readonly) NSString *bundlePath;
@property (nonatomic, strong, readonly) UIImage *icon;
@property (nonatomic, assign) BOOL isLaunching;

- (instancetype)initWithBundlePath:(NSString *)bundlePath NS_DESIGNATED_INITIALIZER;
- (void)launch;

/** 枚举 LiveContainer 已安装的所有应用 */
+ (NSArray<LCOSAppModel *> *)allInstalledApps;

@end

NS_ASSUME_NONNULL_END

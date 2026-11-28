#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// release: tag_name, version, body and browser_download_url for LCOS.dylib.
@interface LCOSUpdateManager : NSObject
+ (instancetype)shared;
- (NSString *)currentVersion;
- (void)checkForUpdatesWithCompletion:(void (^)(NSDictionary * _Nullable release, NSError * _Nullable error))completion;
- (void)ignoreRelease:(NSDictionary *)release;
- (void)downloadAndInstallRelease:(NSDictionary *)release completion:(void (^)(NSError * _Nullable error))completion;
- (void)signInstalledPluginWithCompletion:(void (^)(NSError * _Nullable error))completion;
@end

NS_ASSUME_NONNULL_END

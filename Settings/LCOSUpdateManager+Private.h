#pragma once

#import "LCOSUpdateManager.h"

@interface LCOSUpdateManager ()
@property (nonatomic, copy) NSString *resolvedPluginDirectory;
extern NSString *const kLCOSUpdateErrorDomain;
- (NSError *)error:(NSInteger)code description:(NSString *)description;
- (NSString *)currentVersion;
- (void)finishInstall:(void (^)(NSError *))completion error:(NSError *)error;
- (BOOL)replaceStagedBinary:(NSString *)staging error:(NSError **)error;
- (NSArray<NSURL *> *)candidateURLsForOfficialURL:(NSURL *)url;
- (void)performCandidates:(NSArray<NSURL *> *)urls index:(NSUInteger)index completion:(void (^)(NSData *, NSURLResponse *, NSError *, NSUInteger))completion;
@end

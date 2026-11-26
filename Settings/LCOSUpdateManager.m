#import "LCOSUpdateManager.h"
#import "LCOSLogManager.h"
#import <objc/runtime.h>
#import <objc/message.h>

#ifndef LCOS_VERSION_STRING
#define LCOS_VERSION_STRING "dev"
#endif
__attribute__((used)) static const char kLCOSVersion[] = LCOS_VERSION_STRING;
static NSString *const kLCOSIgnoredVersion = @"LCOSIgnoredReleaseVersion";
static NSString *const kLCOSUpdateErrorDomain = @"LCOSUpdateError";

@implementation LCOSUpdateManager

+ (instancetype)shared {
    static LCOSUpdateManager *manager;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ manager = [[self alloc] init]; });
    return manager;
}

- (NSString *)currentVersion {
    NSString *version = [NSString stringWithUTF8String:kLCOSVersion];
    return version.length && ![version isEqualToString:@"dev"] ? version : @"未标记版本";
}

- (NSError *)error:(NSInteger)code description:(NSString *)description {
    return [NSError errorWithDomain:kLCOSUpdateErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: description}];
}

- (NSArray<NSNumber *> *)versionComponents:(NSString *)version {
    NSString *value = [version hasPrefix:@"v"] ? [version substringFromIndex:1] : version;
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *part in [value componentsSeparatedByString:@"."]) {
        NSScanner *scanner = [NSScanner scannerWithString:part];
        NSInteger number = 0;
        if (![scanner scanInteger:&number] || !scanner.isAtEnd) return nil;
        [parts addObject:@(number)];
    }
    return parts;
}

- (NSComparisonResult)compareVersion:(NSString *)left with:(NSString *)right {
    NSArray<NSNumber *> *a = [self versionComponents:left];
    NSArray<NSNumber *> *b = [self versionComponents:right];
    if (!a || !b) return NSOrderedSame;
    for (NSInteger i = 0; i < MAX(a.count, b.count); i++) {
        NSInteger x = i < a.count ? a[i].integerValue : 0;
        NSInteger y = i < b.count ? b[i].integerValue : 0;
        if (x < y) return NSOrderedAscending;
        if (x > y) return NSOrderedDescending;
    }
    return NSOrderedSame;
}

- (void)checkForUpdatesWithCompletion:(void (^)(NSDictionary *, NSError *))completion {
    NSURL *url = [NSURL URLWithString:@"https://api.github.com/repos/LTYOS/LCOS/releases/latest"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 20;
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"LCOS-Updater" forHTTPHeaderField:@"User-Agent"];
    [[LCOSLogManager sharedManager] forceLog:@"LCOS Update: checking latest release"];
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!completion) return;
        if (error) { [self finish:completion release:nil error:error]; return; }
        if (![response isKindOfClass:NSHTTPURLResponse.class]) {
            [self finish:completion release:nil error:[self error:6 description:@"更新服务器响应无效"]]; return;
        }
        NSInteger status = ((NSHTTPURLResponse *)response).statusCode;
        if (status != 200) {
            [self finish:completion release:nil error:[self error:status description:[NSString stringWithFormat:@"检查更新失败（HTTP %ld）", (long)status]]];
            return;
        }
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![json isKindOfClass:NSDictionary.class] || [json[@"draft"] boolValue] || [json[@"prerelease"] boolValue]) {
            [self finish:completion release:nil error:[self error:1 description:@"更新信息格式无效"]];
            return;
        }
        NSString *tag = json[@"tag_name"];
        NSString *version = [tag hasPrefix:@"v"] ? [tag substringFromIndex:1] : tag;
        NSString *ignored = [NSUserDefaults.standardUserDefaults stringForKey:kLCOSIgnoredVersion];
        NSString *current = self.currentVersion;
        BOOL newer = [current isEqualToString:@"未标记版本"] || [self compareVersion:current with:version] == NSOrderedAscending;
        NSString *downloadURL = nil;
        for (NSDictionary *asset in json[@"assets"] ?: @[]) {
            if ([asset isKindOfClass:NSDictionary.class] && [asset[@"name"] isEqualToString:@"LCOS.dylib"]) {
                downloadURL = asset[@"browser_download_url"];
                break;
            }
        }
        if (!newer || [version isEqualToString:ignored]) {
            [self finish:completion release:nil error:nil];
            return;
        }
        if (!version.length || !downloadURL.length) {
            [self finish:completion release:nil error:[self error:2 description:@"最新发行版缺少 LCOS.dylib，请稍后重试"]];
            return;
        }
        [self finish:completion release:@{@"tag_name": tag, @"version": version,
            @"body": [json[@"body"] isKindOfClass:NSString.class] ? json[@"body"] : @"暂无更新说明",
            @"browser_download_url": downloadURL} error:nil];
    }] resume];
}

- (void)finish:(void (^)(NSDictionary *, NSError *))completion release:(NSDictionary *)release error:(NSError *)error {
    if (!completion) return;
    dispatch_async(dispatch_get_main_queue(), ^{ completion(release, error); });
}

- (void)ignoreRelease:(NSDictionary *)release {
    NSString *version = release[@"version"];
    if (!version.length) return;
    [NSUserDefaults.standardUserDefaults setObject:version forKey:kLCOSIgnoredVersion];
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Update: ignored %@", version]];
}

- (NSString *)pluginDirectory {
    // LCBootstrap.m sets this to the actual host Tweaks directory before
    // loading global tweaks. Do not guess a guest container's Documents path.
    const char *value = getenv("LC_GLOBAL_TWEAKS_FOLDER");
    if (!value) return nil;
    NSString *path = [NSFileManager.defaultManager stringWithFileSystemRepresentation:value length:strlen(value)];
    return path.length ? path.stringByStandardizingPath : nil;
}

- (BOOL)validPluginDirectory:(NSString *)directory error:(NSError **)error {
    BOOL directoryExists = NO;
    NSString *target = [directory stringByAppendingPathComponent:@"LCOS.dylib"];
    if (directory.length == 0 || ![directory.lastPathComponent isEqualToString:@"Tweaks"] ||
        ![NSFileManager.defaultManager fileExistsAtPath:directory isDirectory:&directoryExists] || !directoryExists ||
        ![NSFileManager.defaultManager fileExistsAtPath:target]) {
        if (error) *error = [self error:9 description:@"未确认 LiveContainer 的 LCOS 模块目录，已停止更新，旧版本未覆盖"];
        return NO;
    }
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Update: verified host tweaks directory %@", directory]];
    return YES;
}

- (BOOL)validBinary:(NSData *)data {
    if (data.length < 4) return NO;
    uint32_t magic = 0;
    [data getBytes:&magic length:sizeof(magic)];
    return magic == 0xfeedfacf || magic == 0xfeedface || magic == 0xbebafeca || magic == 0xbfbafeca;
}

- (void)downloadAndInstallRelease:(NSDictionary *)release completion:(void (^)(NSError *))completion {
    if (!completion) return;
    NSError *directoryError = nil;
    NSString *directory = self.pluginDirectory;
    if (![self validPluginDirectory:directory error:&directoryError]) {
        [self finishInstall:completion error:directoryError];
        return;
    }
    NSURL *url = [NSURL URLWithString:release[@"browser_download_url"]];
    if (![url.scheme isEqualToString:@"https"] ||
        !([url.host isEqualToString:@"github.com"] || [url.host hasSuffix:@".github.com"] || [url.host hasSuffix:@".githubusercontent.com"])) {
        completion([self error:3 description:@"下载地址无效"]); return;
    }
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Update: downloading %@", release[@"version"]]];
    [[NSURLSession.sharedSession downloadTaskWithURL:url completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        if (!completion) return;
        if (error) { [self finishInstall:completion error:error]; return; }
        if (![response isKindOfClass:NSHTTPURLResponse.class] || ((NSHTTPURLResponse *)response).statusCode != 200) {
            [self finishInstall:completion error:[self error:4 description:@"下载失败，请检查网络后重试"]]; return;
        }
        NSData *data = [NSData dataWithContentsOfURL:location];
        if (![self validBinary:data]) {
            [self finishInstall:completion error:[self error:5 description:@"下载内容不是有效的 LCOS 插件，未覆盖旧版本"]]; return;
        }
        NSString *staging = [directory stringByAppendingPathComponent:@".LCOS.dylib.download"];
        NSFileManager *fm = NSFileManager.defaultManager;
        NSError *writeError = nil;
        [fm createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&writeError];
        if (writeError || ![data writeToFile:staging options:NSDataWritingAtomic error:&writeError]) {
            [self finishInstall:completion error:writeError ?: [self error:6 description:@"无法写入插件目录"]]; return;
        }
        [self signAndReplace:staging release:release completion:completion];
    }] resume];
}

- (void)signAndReplace:(NSString *)staging release:(NSDictionary *)release completion:(void (^)(NSError *))completion {
    Class utils = NSClassFromString(@"LCUtils");
    SEL selector = NSSelectorFromString(@"signFilesWithZSignWithURLs:completionHandler:");
    if (![utils respondsToSelector:selector]) {
        [NSFileManager.defaultManager removeItemAtPath:staging error:nil];
        [self finishInstall:completion error:[self error:7 description:@"未找到 LiveContainer 签名接口，旧版本未覆盖"]];
        return;
    }
    typedef NSProgress *(*SignFiles)(id, SEL, NSArray *, void (^)(BOOL, NSError *));
    SignFiles sign = (SignFiles)objc_msgSend;
    sign(utils, selector, @[[NSURL fileURLWithPath:staging]], ^(BOOL success, NSError *error) {
        if (!success || error) {
            [NSFileManager.defaultManager removeItemAtPath:staging error:nil];
            [self finishInstall:completion error:error ?: [self error:8 description:@"模块签名失败，旧版本未覆盖"]];
            return;
        }
        NSError *replaceError = nil;
        [self replaceStagedBinary:staging error:&replaceError];
        [self finishInstall:completion error:replaceError];
    });
}

- (BOOL)replaceStagedBinary:(NSString *)staging error:(NSError **)error {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *target = [self.pluginDirectory stringByAppendingPathComponent:@"LCOS.dylib"];
    NSURL *targetURL = [NSURL fileURLWithPath:target];
    NSURL *stagingURL = [NSURL fileURLWithPath:staging];
    NSString *directory = target.stringByDeletingLastPathComponent;
    NSString *backup = [directory stringByAppendingPathComponent:@"LCOS.dylib.backup"];
    [fm removeItemAtPath:backup error:nil];
    if (![fm copyItemAtPath:target toPath:backup error:error]) {
        [fm removeItemAtPath:staging error:nil];
        return NO;
    }
    // Copy the verified download over the existing module rather than moving
    // it first: a failed write cannot leave the target missing.
    if (![fm removeItemAtPath:target error:error] || ![fm copyItemAtURL:stagingURL toURL:targetURL error:error]) {
        NSError *restoreError = nil;
        [fm removeItemAtPath:target error:nil];
        BOOL restored = [fm copyItemAtPath:backup toPath:target error:&restoreError];
        [fm removeItemAtPath:staging error:nil];
        if (error) *error = restoreError ?: *error;
        [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Update: replacement failed; backup restored=%d", restored]];
        return NO;
    }
    [fm removeItemAtPath:staging error:nil];
    [[LCOSLogManager sharedManager] forceLog:@"LCOS Update: installed signed LCOS.dylib; previous version backed up"];
    return YES;
}

- (void)finishInstall:(void (^)(NSError *))completion error:(NSError *)error {
    if (!completion) return;
    if (error) [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Update: failed %@", error.localizedDescription]];
    dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
}

@end

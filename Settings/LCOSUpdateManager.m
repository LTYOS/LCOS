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

@interface LCOSUpdateManager ()
@property (nonatomic, copy) NSString *resolvedPluginDirectory;
@end

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

- (NSArray<NSString *> *)pluginDirectoryCandidates {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    void (^add)(NSString *) = ^(NSString *path) {
        if (![path isKindOfClass:NSString.class] || !path.isAbsolutePath) return;
        NSString *standard = path.stringByStandardizingPath;
        if (!standard.length || [paths containsObject:standard]) return;
        [paths addObject:standard];
    };
    const char *value = getenv("LC_GLOBAL_TWEAKS_FOLDER");
    if (value) add([NSFileManager.defaultManager stringWithFileSystemRepresentation:value length:strlen(value)]);
    // The user-confirmed host layout is root/LCOS/logs and root/Tweaks.
    // Derive that sibling from the already working log writer, rather than
    // relying on a differently constructed App Group URL during updates.
    NSString *sibling = [[LCOSLogManager sharedManager] siblingTweaksDirectory];
    add(sibling);
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Update: log-derived Tweaks candidate %@", sibling ?: @"(unavailable)"]];
    @try {
        Class shared = NSClassFromString(@"LCSharedUtils");
        SEL groupSelector = NSSelectorFromString(@"appGroupPath");
        if ([shared respondsToSelector:groupSelector]) {
            id group = ((id (*)(id, SEL))objc_msgSend)(shared, groupSelector);
            if ([group isKindOfClass:NSURL.class]) add([[group path] stringByAppendingPathComponent:@"LiveContainer/Tweaks"]);
            else if ([group isKindOfClass:NSString.class]) add([group stringByAppendingPathComponent:@"LiveContainer/Tweaks"]);
        }
    } @catch (NSException *exception) {
        [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Update: App Group path unavailable: %@", exception.name]];
    }
    const char *home = getenv("LC_HOME_PATH");
    if (home) add([[NSFileManager.defaultManager stringWithFileSystemRepresentation:home length:strlen(home)] stringByAppendingPathComponent:@"Documents/Tweaks"]);
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    add([documents stringByAppendingPathComponent:@"Tweaks"]);
    return paths;
}

- (NSString *)pluginDirectory {
    // Do not create an empty candidate: only the existing LCOS.dylib proves
    // that this is the installed module directory and not a guest container.
    return [[self pluginDirectoryCandidates] firstObject];
}

- (BOOL)validPluginDirectory:(NSString *)directory error:(NSError **)error {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *failure = nil;
    for (NSString *candidate in [self pluginDirectoryCandidates]) {
        if (directory.length && ![candidate isEqualToString:directory]) continue;
        BOOL isDirectory = NO;
        if (![fm fileExistsAtPath:candidate isDirectory:&isDirectory] || !isDirectory) {
            failure = [NSString stringWithFormat:@"插件目录不存在：%@", candidate];
            continue;
        }
        NSString *target = [candidate stringByAppendingPathComponent:@"LCOS.dylib"];
        if (![fm fileExistsAtPath:target isDirectory:&isDirectory] || isDirectory) {
            failure = [NSString stringWithFormat:@"插件目录内没有 LCOS.dylib：%@", candidate];
            continue;
        }
        if (![fm isWritableFileAtPath:candidate] || ![fm isWritableFileAtPath:target]) {
            failure = [NSString stringWithFormat:@"插件目录或 LCOS.dylib 不可写：%@", candidate];
            continue;
        }
        self.resolvedPluginDirectory = candidate;
        [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Update: verified host tweaks directory %@", candidate]];
        return YES;
    }
    if (error) *error = [self error:9 description:[NSString stringWithFormat:@"%@，已停止更新，旧版本未覆盖。请确认 LCOS.dylib 位于与 LCOS 日志文件夹同级的 Tweaks 内", failure ?: @"未找到已安装的 LCOS.dylib"]];
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Update: no verified Tweaks directory: %@", failure ?: @"no candidates"]];
    return NO;
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
    NSString *installDirectory = self.resolvedPluginDirectory;
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
        NSString *staging = [installDirectory stringByAppendingPathComponent:@".LCOS.dylib.download"];
        NSFileManager *fm = NSFileManager.defaultManager;
        NSError *writeError = nil;
        if (![data writeToFile:staging options:NSDataWritingAtomic error:&writeError]) {
            [self finishInstall:completion error:writeError ?: [self error:6 description:@"无法写入插件目录"]]; return;
        }
        NSError *replaceError = nil;
        [self replaceStagedBinary:staging error:&replaceError];
        [self finishInstall:completion error:replaceError];
    }] resume];
}

- (void)signInstalledPluginWithCompletion:(void (^)(NSError *))completion {
    if (!completion) return;
    NSError *directoryError = nil;
    NSString *directory = self.pluginDirectory;
    if (![self validPluginDirectory:directory error:&directoryError]) {
        [self finishInstall:completion error:directoryError];
        return;
    }
    Class utils = NSClassFromString(@"LCUtils");
    SEL selector = NSSelectorFromString(@"signFilesWithZSignWithURLs:completionHandler:");
    if (![utils respondsToSelector:selector]) {
        [self finishInstall:completion error:[self error:7 description:@"未找到 LiveContainer 签名接口，请稍后重试"]];
        return;
    }
    NSString *target = [self.resolvedPluginDirectory stringByAppendingPathComponent:@"LCOS.dylib"];
    typedef NSProgress *(*SignFiles)(id, SEL, NSArray *, void (^)(BOOL, NSError *));
    SignFiles sign = (SignFiles)objc_msgSend;
    [[LCOSLogManager sharedManager] forceLog:@"LCOS Update: user requested installed module signing"];
    sign(utils, selector, @[[NSURL fileURLWithPath:target]], ^(BOOL success, NSError *error) {
        if (!success || error) {
            [self finishInstall:completion error:error ?: [self error:8 description:@"模块签名失败，请重试"]];
            return;
        }
        [[LCOSLogManager sharedManager] forceLog:@"LCOS Update: installed module signed by user"];
        [self finishInstall:completion error:nil];
    });
}

- (BOOL)replaceStagedBinary:(NSString *)staging error:(NSError **)error {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *directory = staging.stringByDeletingLastPathComponent;
    NSString *target = [directory stringByAppendingPathComponent:@"LCOS.dylib"];
    NSURL *targetURL = [NSURL fileURLWithPath:target];
    NSURL *stagingURL = [NSURL fileURLWithPath:staging];
    NSString *version = self.currentVersion;
    NSString *backupName = [NSString stringWithFormat:@"LCOS-%@.dylib.backup", version];
    NSString *backup = [directory stringByAppendingPathComponent:backupName];
    for (NSString *name in [fm contentsOfDirectoryAtPath:directory error:nil]) {
        if ([name hasPrefix:@"LCOS-"] && [name hasSuffix:@".dylib.backup"] && ![name isEqualToString:backupName]) {
            [fm removeItemAtPath:[directory stringByAppendingPathComponent:name] error:nil];
        }
    }
    [fm removeItemAtPath:backup error:nil];
    [fm removeItemAtPath:[directory stringByAppendingPathComponent:@"LCOS.dylib.backup"] error:nil];
    if (![fm copyItemAtPath:target toPath:backup error:error]) {
        [fm removeItemAtPath:staging error:nil];
        return NO;
    }
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
    [[LCOSLogManager sharedManager] forceLog:@"LCOS Update: installed LCOS.dylib; previous version backed up"];
    return YES;
}

- (void)finishInstall:(void (^)(NSError *))completion error:(NSError *)error {
    if (!completion) return;
    if (error) [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Update: failed %@", error.localizedDescription]];
    dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
}

@end

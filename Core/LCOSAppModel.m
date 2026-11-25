//
//  LCOSAppModel.m
//  LCOS.dylib
//

#import "LCOSAppModel.h"
#import "LCOSLogManager.h"
#import <objc/runtime.h>
#import <objc/message.h>

static NSString *const kLCOSAppsDirectory = @"Applications";

@implementation LCOSAppModel {
    NSString *_displayName;
    NSString *_bundleIdentifier;
    NSString *_bundlePath;
    NSString *_containerFolderName;
    UIImage *_icon;
}

- (instancetype)initWithBundlePath:(NSString *)bundlePath {
    self = [super init];
    if (self) {
        _bundlePath = bundlePath;
        _isLaunching = NO;
        _icon = [UIImage systemImageNamed:@"app.fill"]; // fallback
        
        // 优先通过 runtime 获取 LCAppInfo 类（LCOS 插件运行在 LiveContainer 进程内，类已加载）
        Class lcAppInfoClass = NSClassFromString(@"LCAppInfo");
        if (lcAppInfoClass) {
            id appInfo = ((id (*)(id, SEL))objc_msgSend)(lcAppInfoClass, @selector(alloc));
            appInfo = ((id (*)(id, SEL, NSString *))objc_msgSend)(appInfo, @selector(initWithBundlePath:), bundlePath);
            if (appInfo) {
                SEL displayNameSel = @selector(displayName);
                SEL bundleIdSel = @selector(bundleIdentifier);
                SEL iconSel = @selector(iconIsDarkIcon:);
                if ([appInfo respondsToSelector:displayNameSel]) {
                    _displayName = ((NSString *(*)(id, SEL))objc_msgSend)(appInfo, displayNameSel) ?: @"Unknown";
                }
                if ([appInfo respondsToSelector:bundleIdSel]) {
                    _bundleIdentifier = ((NSString *(*)(id, SEL))objc_msgSend)(appInfo, bundleIdSel) ?: @"Unknown";
                }
                if ([appInfo respondsToSelector:iconSel]) {
                    _icon = ((UIImage *(*)(id, SEL, BOOL))objc_msgSend)(appInfo, iconSel, NO) ?: [UIImage systemImageNamed:@"app.fill"];
                }
                SEL containerSel = @selector(dataUUID);
                if ([appInfo respondsToSelector:containerSel]) {
                    _containerFolderName = ((NSString *(*)(id, SEL))objc_msgSend)(appInfo, containerSel);
                }
                [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOSAppModel: loaded %@ via LCAppInfo", _displayName]];
            }
        }
        
        // Fallback：自己读取 Info.plist
        if (!_displayName || [_displayName isEqualToString:@"Unknown"]) {
            NSString *plistPath = [bundlePath stringByAppendingPathComponent:@"Info.plist"];
            NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:plistPath];
            if (plist) {
                if (!_displayName || [_displayName isEqualToString:@"Unknown"]) {
                    _displayName = plist[@"CFBundleDisplayName"] ?: plist[@"CFBundleName"] ?: @"Unknown";
                }
                if (!_bundleIdentifier || [_bundleIdentifier isEqualToString:@"Unknown"]) {
                    _bundleIdentifier = plist[@"CFBundleIdentifier"] ?: @"Unknown";
                }
                [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOSAppModel: loaded %@ via Info.plist fallback", _displayName]];
            }
        }
        
        if (!_containerFolderName) {
            NSDictionary *lcInfo = [NSDictionary dictionaryWithContentsOfFile:
                [bundlePath stringByAppendingPathComponent:@"LCAppInfo.plist"]];
            _containerFolderName = lcInfo[@"LCDataUUID"];
        }
        if (!_bundleIdentifier) {
            _bundleIdentifier = @"Unknown";
        }
    }
    return self;
}

- (NSURL *)launchURL {
    NSString *bundleName = _bundlePath.lastPathComponent;
    if (bundleName.length == 0) return nil;
    NSURLComponents *components = [[NSURLComponents alloc] init];
    components.host = @"livecontainer-launch";
    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray arrayWithObject:
        [NSURLQueryItem queryItemWithName:@"bundle-name" value:bundleName]];
    if (_containerFolderName.length > 0) {
        [items addObject:[NSURLQueryItem queryItemWithName:@"container-folder-name"
                                                     value:_containerFolderName]];
    }
    components.queryItems = items;
    return components.URL;
}

- (NSUserDefaults *)hostDefaults {
    SEL selector = NSSelectorFromString(@"lcUserDefaults");
    if (![NSUserDefaults respondsToSelector:selector]) return NSUserDefaults.standardUserDefaults;
    id defaults = ((id (*)(id, SEL))objc_msgSend)(NSUserDefaults.class, selector);
    return [defaults isKindOfClass:NSUserDefaults.class] ? defaults : NSUserDefaults.standardUserDefaults;
}

- (NSString *)hostURLScheme {
    SEL selector = NSSelectorFromString(@"lcAppUrlScheme");
    if ([NSUserDefaults respondsToSelector:selector]) {
        NSString *scheme = ((NSString *(*)(id, SEL))objc_msgSend)(NSUserDefaults.class, selector);
        if (scheme.length > 0) return scheme;
    }
    NSArray *urlTypes = NSBundle.mainBundle.infoDictionary[@"CFBundleURLTypes"];
    for (NSDictionary *type in urlTypes) {
        NSString *scheme = [type[@"CFBundleURLSchemes"] firstObject];
        if ([scheme isKindOfClass:NSString.class] && scheme.length > 0) return scheme;
    }
    return @"livecontainer";
}

- (void)launch {
    if (_isLaunching) return;
    _isLaunching = YES;

    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:
        @"LCOSAppModel: launching %@ bundle=%@ container=%@", _displayName,
        _bundlePath.lastPathComponent, _containerFolderName ?: @"(default)"]];

    NSURLComponents *components = [NSURLComponents componentsWithURL:self.launchURL
                                             resolvingAgainstBaseURL:NO];
    if (!components) {
        [[LCOSLogManager sharedManager] forceLog:@"LCOSAppModel: invalid launch URL"];
        _isLaunching = NO;
        return;
    }

    // LCSharedUtils writes the selected app/container and starts the guest itself.
    Class sharedUtils = NSClassFromString(@"LCSharedUtils");
    SEL directSelector = @selector(launchToGuestAppWithURL:);
    if ([sharedUtils respondsToSelector:directSelector]) {
        components.scheme = [self hostURLScheme];
        NSUserDefaults *defaults = [self hostDefaults];
        [defaults setBool:NO forKey:@"LCOpenSideStore"];
        [defaults removeObjectForKey:@"launchAppUrlScheme"];
        BOOL accepted = ((BOOL (*)(id, SEL, NSURL *))objc_msgSend)(sharedUtils,
                                                                    directSelector, components.URL);
        [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:
            @"LCOSAppModel: LCSharedUtils launch accepted=%d url=%@", accepted, components.URL]];
        if (!accepted) {
            [defaults removeObjectForKey:@"selected"];
            [defaults removeObjectForKey:@"selectedContainer"];
        }
        _isLaunching = NO;
        return;
    }

    // Host UI fallback: LiveContainer handles the same deep link in LCAppListView.
    components.scheme = [self hostURLScheme];
    NSURL *url = components.URL;
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:
        @"LCOSAppModel: opening LiveContainer launch URL %@", url]];
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:^(BOOL success) {
        [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:
            @"LCOSAppModel: deep link launch accepted=%d", success]];
        self.isLaunching = NO;
    }];
}

+ (NSArray<LCOSAppModel *> *)allInstalledApps {
    NSMutableArray *apps = [NSMutableArray array];
    
    // LiveContainer 应用安装在 Documents/Applications/
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    if (paths.count == 0) {
        [[LCOSLogManager sharedManager] forceLog:@"LCOSAppModel: no Documents directory"];
        return [apps copy];
    }
    
    NSString *appsDir = [paths.firstObject stringByAppendingPathComponent:kLCOSAppsDirectory];
    NSFileManager *fm = [NSFileManager defaultManager];
    
    if (![fm fileExistsAtPath:appsDir]) {
        [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOSAppModel: Applications dir not found: %@", appsDir]];
        return [apps copy];
    }
    
    NSArray *appDirs = [fm contentsOfDirectoryAtPath:appsDir error:nil];
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOSAppModel: found %lu app dirs", (unsigned long)appDirs.count]];
    
    for (NSString *appDir in appDirs) {
        if ([appDir hasSuffix:@".app"]) {
            NSString *bundlePath = [appsDir stringByAppendingPathComponent:appDir];
            LCOSAppModel *model = [[LCOSAppModel alloc] initWithBundlePath:bundlePath];
            [apps addObject:model];
        }
    }
    
    // 按显示名称排序
    [apps sortUsingComparator:^NSComparisonResult(LCOSAppModel *a, LCOSAppModel *b) {
        return [a.displayName compare:b.displayName options:NSCaseInsensitiveSearch];
    }];
    
    return [apps copy];
}

@end

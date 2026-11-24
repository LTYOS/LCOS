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
            id appInfo = ((id (*)(id, SEL, NSString *))objc_msgSend)(lcAppInfoClass, @selector(alloc), lcAppInfoClass);
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
        
        if (!_bundleIdentifier) {
            _bundleIdentifier = @"Unknown";
        }
    }
    return self;
}

- (void)launch {
    if (_isLaunching) return;
    _isLaunching = YES;
    
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOSAppModel: launching %@ (%@)", _displayName, _bundlePath]];
    
    // relativeBundlePath = bundlePath.lastPathComponent (e.g. "com.xxx.app")
    // This matches LCAppInfo.relativeBundlePath used by host LCAppListView.
    NSString *relativeBundlePath = _bundlePath.lastPathComponent ?: _bundlePath;
    
    // Method 1: URL scheme "livecontainer://livecontainer-launch?bundle-name=..."
    // Handled by host LCAppListView.swift (always available in host process).
    NSString *urlString = [NSString stringWithFormat:@"livecontainer://livecontainer-launch?bundle-name=%@", relativeBundlePath];
    NSURL *url = [NSURL URLWithString:urlString];
    if (url) {
        UIApplication *application = [UIApplication sharedApplication];
        if ([application respondsToSelector:@selector(openURL:options:completionHandler:)]) {
            [application openURL:url options:@{} completionHandler:^(BOOL success) {
                [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOSAppModel: openURL livecontainer-launch success=%d", success]];
            }];
        } else {
            [application openURL:url];
            [[LCOSLogManager sharedManager] forceLog:@"LCOSAppModel: openURL (legacy) called"];
        }
        _isLaunching = NO;
        return;
    }
    
    [[LCOSLogManager sharedManager] forceLog:@"LCOSAppModel: failed to build launch URL"];
    _isLaunching = NO;
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

//
//  LCOSConfig.m
//  LCOS.dylib
//

#import "LCOSConfig.h"
#import <UserNotifications/UserNotifications.h>

@implementation LCOSConfig

+ (NSString *)appGroupID {
    return @"group.com.lcos.livecontainer";
}

+ (NSDictionary *)defaultConfigurationData {
    static dispatch_once_t onceToken;
    static NSDictionary *config = nil;
    dispatch_once(&onceToken, ^{
        config = @{
                    @"launcherStyle": @"ios26_27_grid",
                    @"gestureEnter": @"three_finger_swipe_up",
                    @"gestureExit": @"three_finger_swipe_down",
                    @"gestureSettings": @"three_finger_long_press",
                    @"dockPosition": @"bottom",
                    @"gestureDirection": @"left",
                    @"logLevel": @"info",
                    @"autoGenerateLogs": @YES
                    };
    });
    return config;
}

+ (void)loadDefaultConfig {
    // Try to load existing config, fall back to defaults
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@".LCOS/config.plist"];
    NSFileManager *fm = [NSFileManager defaultManager];
    
    if (![fm fileExistsAtPath:path]) {
        // Create default config directory and file
        NSString *configDir = [path stringByDeletingLastPathComponent];
        [fm createDirectoryAtPath:configDir withIntermediateDirectories:YES attributes:nil error:nil];
        [self writeDefaultConfigToPath:path];
    }
    
    // Read config (placeholder - actual plist parsing can be added)
    // For now use defaults
    NSLog(@"LCOS: Using default configuration");
}

+ (void)writeDefaultConfigToPath:(NSString *)path {
    NSDictionary *defaultConfig = [LCOSConfig defaultConfigurationData];
    [defaultConfig writeToFile:path atomically:YES];
}

// New implementation for missing methods
+ (NSDictionary *)configuration {
    // Return the default configuration as fallback
    return [self defaultConfigurationData];
}

+ (BOOL)saveConfiguration:(NSDictionary *)configuration {
    // Save configuration to disk
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@".LCOS/config.plist"];
    NSFileManager *fm = [NSFileManager defaultManager];
    
    if (![fm fileExistsAtPath:path]) {
        // Create default config directory and file
        NSString *configDir = [path stringByDeletingLastPathComponent];
        [fm createDirectoryAtPath:configDir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    // Write configuration to disk
    return [configuration writeToFile:path atomically:YES];
}

@end
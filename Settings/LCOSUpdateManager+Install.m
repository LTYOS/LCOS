#import "LCOSUpdateManager+Private.h"
#import "LCOSLogManager.h"

@implementation LCOSUpdateManager (Install)

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

@end

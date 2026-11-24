//
//  LCOSWallpaper.m
//  LCOS.dylib
//

#import "LCOSWallpaper.h"
#import "LCOSLogManager.h"

@implementation LCOSWallpaper

+ (instancetype)shared {
    static LCOSWallpaper *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[LCOSWallpaper alloc] init]; });
    return s;
}

- (NSString *)wallpaperPath {
    NSArray *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *dir = [docs.firstObject stringByAppendingPathComponent:@"LCOS"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:@"wallpaper.jpg"];
}

- (UIImage *)currentWallpaper {
    NSString *path = [self wallpaperPath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;
    return [UIImage imageWithContentsOfFile:path];
}

- (void)setWallpaper:(UIImage *)image {
    if (!image) return;
    NSData *data = UIImageJPEGRepresentation(image, 0.85);
    BOOL ok = [data writeToFile:[self wallpaperPath] atomically:YES];
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Wallpaper: saved=%d bytes=%lu", ok, (unsigned long)data.length]];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"LCOSWallpaperDidChange" object:nil];
}

- (void)clearWallpaper {
    [[NSFileManager defaultManager] removeItemAtPath:[self wallpaperPath] error:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"LCOSWallpaperDidChange" object:nil];
}

@end
#pragma once

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Shared wallpaper storage - persisted to Documents/LCOS/wallpaper.jpg
@interface LCOSWallpaper : NSObject

+ (instancetype)shared;
- (nullable UIImage *)currentWallpaper;
- (void)setWallpaper:(UIImage *)image;
- (void)clearWallpaper;

@end

NS_ASSUME_NONNULL_END
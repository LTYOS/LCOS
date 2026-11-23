#pragma once

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// LCOS 核心控制器 - 管理 overlay window、悬浮按钮和启动器
@interface LCOSCore : NSObject

@property (nonatomic, strong, nullable) UIWindow *overlayWindow;
@property (nonatomic, strong, nullable) id floatingButton; // LCOSFloatingButton
@property (nonatomic, strong, nullable) id launcherView;   // LCOSLauncherView
@property (nonatomic, assign) BOOL isLauncherVisible;

+ (instancetype)sharedInstance;
- (void)initialize;
- (void)showLauncher;
- (void)hideLauncher;
- (void)toggleLauncher;
- (void)showFloatingButton;
- (void)hideFloatingButton;

@end

NS_ASSUME_NONNULL_END
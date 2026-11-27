#pragma once

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class LCOSLauncherView;
@class UIViewController;
@class LCOSShellController;

NS_ASSUME_NONNULL_BEGIN

/// LCOS 核心控制器 - 管理 Overlay、桌面、右侧导航和后台层
@interface LCOSCore : NSObject <UIGestureRecognizerDelegate>

@property (nonatomic, strong, nullable) UIWindow *overlayWindow;
@property (nonatomic, strong, nullable) LCOSLauncherView *launcherView;
@property (nonatomic, strong, nullable) UIViewController *launcherContainer;
@property (nonatomic, assign) BOOL isLauncherVisible;
@property (nonatomic, strong, nullable) LCOSShellController *nativeShell;
@property (nonatomic, strong, nullable) LCOSShellController *lcosShell;

+ (instancetype)sharedInstance;
- (void)initialize;
- (void)showLauncher;
- (void)showLauncherImmediately;
- (void)hideLauncher;
- (void)toggleLauncher;
- (void)showBackground;
- (void)hideBackground;
- (void)showSettings;

@end

NS_ASSUME_NONNULL_END

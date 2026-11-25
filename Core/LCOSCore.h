#pragma once

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class LCOSFloatingButton;
@class LCOSLauncherView;
@class UIViewController;

NS_ASSUME_NONNULL_BEGIN

/// LCOS 核心控制器 - 管理 overlay window、悬浮按钮和启动器
@interface LCOSCore : NSObject <UIGestureRecognizerDelegate>

@property (nonatomic, strong, nullable) UIWindow *overlayWindow;
@property (nonatomic, strong, nullable) LCOSFloatingButton *floatingButton;
@property (nonatomic, strong, nullable) LCOSLauncherView *launcherView;
@property (nonatomic, strong, nullable) UIViewController *launcherContainer;
@property (nonatomic, assign) BOOL isLauncherVisible;

+ (instancetype)sharedInstance;
- (void)initialize;
- (void)showLauncher;
- (void)showLauncherImmediately;
- (void)hideLauncher;
- (void)toggleLauncher;
- (void)showFloatingButton;
- (void)hideFloatingButton;

/** 原生 Dock 长按上滑、桌面三指下滑。 */
- (void)setUsesGestureLauncher:(BOOL)enabled;
- (BOOL)usesGestureLauncher;

@end

NS_ASSUME_NONNULL_END

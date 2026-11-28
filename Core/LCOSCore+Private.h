#pragma once

#import "LCOSCore.h"
#import "LCOSLauncherView.h"
#import "LCOSNavigationBar.h"
#import "LCOSBackgroundView.h"
#import "LCOSTaskRegistry.h"
#import "LCOSShellController.h"
#import "LCOSPassThroughWindow.h"

@interface LCOSNavigationTouchZone : UIView
@end

extern NSString *const kLCOSLauncherVisibleKey;

@interface LCOSCore ()
@property (nonatomic, strong) UILongPressGestureRecognizer *overlayLongPressGesture;
@property (nonatomic, strong) UILongPressGestureRecognizer *launcherLongPressGesture;
@property (nonatomic, strong) UIPanGestureRecognizer *nativeDockGesture;
@property (nonatomic, strong) UIPanGestureRecognizer *launcherDismissGesture;
@property (nonatomic, weak) UITabBar *nativeDock;
@property (nonatomic, assign) BOOL dockTransitionActive;
@property (nonatomic, assign) BOOL dockPreparingLauncher;
@property (nonatomic, assign) BOOL dockEndedWhilePreparing;
@property (nonatomic, assign) BOOL dockShouldOpenAfterPreparing;
@property (nonatomic, assign) BOOL launcherTransitionActive;
@property (nonatomic, assign) BOOL launcherDismissActive;
@property (nonatomic, assign) CGPoint dockGestureStart;
@property (nonatomic, strong) LCOSNavigationBar *navigationBar;
@property (nonatomic, strong) LCOSBackgroundView *backgroundView;
@property (nonatomic, strong) LCOSNavigationTouchZone *rightEdgeZone;
@property (nonatomic, assign) BOOL isBackgroundVisible;
@property (nonatomic, assign) BOOL isGuestNavigation;

- (void)finishHidingLauncher;
- (void)cancelDockPreparation;
- (void)updateInteractionState;
- (void)saveLauncherState;
- (void)layoutRadiusChanged;
- (void)registerGesturesOnOverlayWindow;
- (void)installNativeDockGestureIfNeeded;
- (BOOL)isBackgroundVisible;
- (UIView *)navigationTouchZone;
- (void)handleThreeFingerLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)showLauncherForDockInteraction;
- (void)setLauncherRoundedCorners:(BOOL)rounded;
- (void)prepareLauncherForInteractivePresentation;
- (void)completeDockPresentation:(BOOL)shouldOpen;
- (void)finishInteractivePresentation;
- (void)handleLauncherDismissGesture:(UIPanGestureRecognizer *)gesture;
- (BOOL)canSwitchShellFromLCOS:(BOOL)fromLCOS;
@end

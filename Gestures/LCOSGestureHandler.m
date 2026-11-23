//
//  LCOSGestureHandler.m
//  LCOS.dylib
//
//
#import "LCOSGestureHandler.h"
#import "LCOSLauncherView.h"
#import "LCOSSettingsView.h"
#import "LCOSFloatingButton.h"
#import "LCOSLogManager.h"
#import <UIKit/UIKit.h>

// Forward declaration for custom gesture recognizer
@interface ThreeFingerPanGestureRecognizer : UIPanGestureRecognizer
@end

@interface LCOSGestureHandler () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) LCOSLauncherView *sharedLauncher;
@property (nonatomic, strong) ThreeFingerPanGestureRecognizer *panGesture;
@property (nonatomic, strong) UILongPressGestureRecognizer *longPressGesture;
@property (nonatomic, strong) UIScreenEdgePanGestureRecognizer *edgeGesture;
@property (nonatomic, strong) UIWindow *hostWindow;
@end

@implementation LCOSGestureHandler

+ (instancetype)sharedHandler {
    static LCOSGestureHandler *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[LCOSGestureHandler alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _sharedLauncher = [[LCOSLauncherView alloc] init];
        // Don't setup gestures here - will be called from registerGestureRecognizers after window is ready
    }
    return self;
}

- (void)ensureHostWindow {
    if (!_hostWindow) {
        UIWindowScene *windowScene = [UIApplication sharedApplication].connectedScenes.anyObject;
        _hostWindow = windowScene ? windowScene.windows.firstObject : nil;
    }
}

- (void)setupFloatingButton {
    [self ensureHostWindow];
    if (!_hostWindow) {
        [[LCOSLogManager sharedManager] forceLog:@("LCOS FloatingButton: No host window, retry")];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self setupFloatingButton];
        });
        return;
    }
    
    LCOSFloatingButton *floatingButton = [LCOSFloatingButton sharedButton];
    floatingButton.launcher = _sharedLauncher;
    [floatingButton showOnWindow:_hostWindow];
    
    [[LCOSLogManager sharedManager] forceLog:@("LCOS FloatingButton: Setup complete")];
}

- (void)setupGestureRecognizers {
    [self ensureHostWindow];
    if (!_hostWindow) {
        [[LCOSLogManager sharedManager] forceLog:@("LCOS Gesture: No host window found, will retry")];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self setupGestureRecognizers];
        });
        return;
    }
    
    // Long press gesture for settings (this works per user report)
    _longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPressGesture:)];
    _longPressGesture.numberOfTouchesRequired = 3;
    _longPressGesture.minimumPressDuration = 1.0;
    _longPressGesture.delegate = self;
    [_hostWindow addGestureRecognizer:_longPressGesture];
    
    // Left edge swipe gesture for floating return
    _edgeGesture = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(handleEdgeGesture:)];
    _edgeGesture.edges = UIRectEdgeLeft;
    _edgeGesture.delegate = self;
    [_hostWindow addGestureRecognizer:_edgeGesture];
    
    [[LCOSLogManager sharedManager] forceLog:@("LCOS Gesture: Recognizers registered on window")];
    
    // Setup floating button after gestures
    [self setupFloatingButton];
}

- (void)handleLongPressGesture:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self handleThreeFingerLongPress];
    }
}

- (void)handleEdgeGesture:(UIScreenEdgePanGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateRecognized) {
        [self handleLeftEdgeGesture];
    }
}

- (void)handleThreeFingerLongPress {
    [[LCOSLogManager sharedManager] forceLog:@("LCOS Gesture: Three finger long press - showing settings")];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        LCOSSettingsView *settingsView = [[LCOSSettingsView alloc] initWithNibName:nil bundle:nil];
        UIWindowScene *windowScene = [UIApplication sharedApplication].connectedScenes.anyObject;
        UIWindow *window = windowScene.windows.firstObject;
        if (window && window.rootViewController) {
            [window.rootViewController presentViewController:settingsView animated:YES completion:nil];
        }
    });
}

- (void)handleLeftEdgeGesture {
    [[LCOSLogManager sharedManager] forceLog:@("LCOS Gesture: Left edge gesture - toggle launcher")];
    // Toggle launcher via floating button logic
    LCOSFloatingButton *floatingButton = [LCOSFloatingButton sharedButton];
    [floatingButton toggleLauncher];
}

+ (void)registerGestureRecognizers {
    // Called from constructor - ensures shared handler is created and gestures registered
    LCOSGestureHandler *handler = [LCOSGestureHandler sharedHandler];
    [handler setupGestureRecognizers];
}

@end

// Custom 3-finger pan gesture recognizer (kept for future gesture support)
@implementation ThreeFingerPanGestureRecognizer

- (BOOL)canBePreventedByGestureRecognizer:(UIGestureRecognizer *)preventingGestureRecognizer {
    return NO;
}

- (BOOL)canPreventGestureRecognizer:(UIGestureRecognizer *)preventedGestureRecognizer {
    return YES;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (touches.count >= 3) {
        [super touchesBegan:touches withEvent:event];
    }
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (touches.count >= 3) {
        [super touchesMoved:touches withEvent:event];
    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (touches.count >= 3) {
        [super touchesEnded:touches withEvent:event];
    }
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
}

@end
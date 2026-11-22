//
//  LCOSGestureHandler.m
//  LCOS.dylib
//
//
#import "LCOSGestureHandler.h"
#import "LCOSLauncherView.h"
#import "LCOSSettingsView.h"
#import "LCOSLogManager.h"
#import <UIKit/UIKit.h>

@interface LCOSGestureHandler ()
@property (nonatomic, strong) LCOSLauncherView *sharedLauncher;
@property (nonatomic, strong) UIPanGestureRecognizer *panGesture;
@property (nonatomic, strong) UILongPressGestureRecognizer *longPressGesture;
@property (nonatomic, strong) UIScreenEdgePanGestureRecognizer *edgeGesture;
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
        [self setupGestureRecognizers];
    }
    return self;
}

- (void)setupGestureRecognizers {
    // Use a custom 3-finger pan gesture recognizer
    _panGesture = [[ThreeFingerPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePanGesture:)];
    _panGesture.delegate = self;
    [_sharedLauncher.view addGestureRecognizer:_panGesture];
    
    // Add long press gesture for settings
    _longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPressGesture:)];
    _longPressGesture.numberOfTouchesRequired = 3;
    _longPressGesture.minimumPressDuration = 1.0;
    _longPressGesture.delegate = self;
    [_sharedLauncher.view addGestureRecognizer:_longPressGesture];
    
    // Add left edge swipe gesture
    _edgeGesture = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(handleEdgeGesture:)];
    _edgeGesture.edges = UIRectEdgeLeft;
    _edgeGesture.delegate = self;
    [_sharedLauncher.view addGestureRecognizer:_edgeGesture];
    
    [[LCOSLogManager sharedManager] forceLog:@("LCOS Gesture: Recognizers registered")];
}

- (void)handlePanGesture:(ThreeFingerPanGestureRecognizer *)gesture {
    CGPoint velocity = [gesture velocityInView:gesture.view];
    
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateRecognized) {
        if (velocity.y < -500) { // Swipe up
            [self handleThreeFingerSwipeUp];
        } else if (velocity.y > 500) { // Swipe down
            [self handleThreeFingerSwipeDown];
        }
    }
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

- (void)handleThreeFingerSwipeUp {
    [[LCOSLogManager sharedManager] forceLog:@("LCOS Gesture: Three finger swipe up - showing launcher")];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindowScene *windowScene = [UIApplication sharedApplication].connectedScenes.firstObject;
        UIWindow *window = windowScene.windows.firstObject;
        if (window && window.rootViewController) {
            [window.rootViewController presentViewController:_sharedLauncher animated:YES completion:nil];
        }
    });
}

- (void)handleThreeFingerSwipeDown {
    [[LCOSLogManager sharedManager] forceLog:@("LCOS Gesture: Three finger swipe down - dismissing launcher")];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (_sharedLauncher.presentedViewController) {
            [_sharedLauncher dismissViewControllerAnimated:YES completion:nil];
        }
    });
}

- (void)handleThreeFingerLongPress {
    [[LCOSLogManager sharedManager] forceLog:@("LCOS Gesture: Three finger long press - showing settings")];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        LCOSSettingsView *settingsView = [[LCOSSettingsView alloc] initWithNibName:nil bundle:nil];
        UIWindowScene *windowScene = [UIApplication sharedApplication].connectedScenes.firstObject;
        UIWindow *window = windowScene.windows.firstObject;
        if (window && window.rootViewController) {
            [window.rootViewController presentViewController:settingsView animated:YES completion:nil];
        }
    });
}

- (void)handleLeftEdgeGesture {
    [[LCOSLogManager sharedManager] forceLog:@("LCOS Gesture: Left edge gesture - floating return")];
    // Floating return button logic - for now just log
}

+ (void)registerGestureRecognizers {
    // Called from constructor - ensures shared handler is created
    [LCOSGestureHandler sharedHandler];
}

@end

// Custom 3-finger pan gesture recognizer
@interface ThreeFingerPanGestureRecognizer : UIPanGestureRecognizer
@end

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

// Gesture recognizer delegate
@interface LCOSGestureHandler () <UIGestureRecognizerDelegate>
@end

@implementation LCOSGestureHandler (GestureDelegate)

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

@end
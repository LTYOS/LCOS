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

static LCOSLauncherView *_sharedLauncher = nil;

+ (void)registerGestureRecognizers {
    // Get or create shared launcher instance
    if (!_sharedLauncher) {
        _sharedLauncher = [[LCOSLauncherView alloc] init];
    }
    
    // Add pan gesture recognizer for 3-finger swipe up/down
    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePanGesture:)];
    panGesture.numberOfTouchesRequired = 3;
    panGesture.delegate = self;
    [_sharedLauncher.view addGestureRecognizer:panGesture];
    
    // Add long press gesture for settings
    UILongPressGestureRecognizer *longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPressGesture:)];
    longPressGesture.numberOfTouchesRequired = 3;
    longPressGesture.minimumPressDuration = 1.0;
    longPressGesture.delegate = self;
    [_sharedLauncher.view addGestureRecognizer:longPressGesture];
    
    // Add left edge swipe gesture
    UIScreenEdgePanGestureRecognizer *edgeGesture = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(handleEdgeGesture:)];
    edgeGesture.edges = UIRectEdgeLeft;
    edgeGesture.delegate = self;
    [_sharedLauncher.view addGestureRecognizer:edgeGesture];
    
    [[LCOSLogManager sharedManager] forceLog:@("LCOS Gesture: Recognizers registered")];
}

+ (void)handlePanGesture:(UIPanGestureRecognizer *)gesture {
    CGPoint velocity = [gesture velocityInView:gesture.view];
    
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateRecognized) {
        if (velocity.y < -500) { // Swipe up
            [self handleThreeFingerSwipeUp];
        } else if (velocity.y > 500) { // Swipe down
            [self handleThreeFingerSwipeDown];
        }
    }
}

+ (void)handleLongPressGesture:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self handleThreeFingerLongPress];
    }
}

+ (void)handleEdgeGesture:(UIScreenEdgePanGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateRecognized) {
        [self handleLeftEdgeGesture];
    }
}

+ (void)handleThreeFingerSwipeUp {
    [[LCOSLogManager sharedManager] forceLog:@("LCOS Gesture: Three finger swipe up - showing launcher")];
    
    if (!_sharedLauncher) {
        _sharedLauncher = [[LCOSLauncherView alloc] init];
    }
    
    // Present launcher modally or as overlay
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = [UIApplication sharedApplication].windows.firstObject;
        if (window && window.rootViewController) {
            [window.rootViewController presentViewController:_sharedLauncher animated:YES completion:nil];
        }
    });
}

+ (void)handleThreeFingerSwipeDown {
    [[LCOSLogManager sharedManager] forceLog:@("LCOS Gesture: Three finger swipe down - dismissing launcher")];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (_sharedLauncher && _sharedLauncher.presentedViewController) {
            [_sharedLauncher dismissViewControllerAnimated:YES completion:nil];
        }
    });
}

+ (void)handleThreeFingerLongPress {
    [[LCOSLogManager sharedManager] forceLog:@("LCOS Gesture: Three finger long press - showing settings")];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        LCOSSettingsView *settingsView = [[LCOSSettingsView alloc] initWithNibName:nil bundle:nil];
        UIWindow *window = [UIApplication sharedApplication].windows.firstObject;
        if (window && window.rootViewController) {
            [window.rootViewController presentViewController:settingsView animated:YES completion:nil];
        }
    });
}

+ (void)handleLeftEdgeGesture {
    [[LCOSLogManager sharedManager] forceLog:@("LCOS Gesture: Left edge gesture - floating return")];
    // Floating return button logic - for now just log
}

@end

// Gesture recognizer delegate to allow simultaneous recognition
@interface LCOSGestureHandler () <UIGestureRecognizerDelegate>
@end

@implementation LCOSGestureHandler (GestureDelegate)

+ (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

@end
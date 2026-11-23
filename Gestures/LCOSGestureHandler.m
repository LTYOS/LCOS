//
//  LCOSGestureHandler.m
//  LCOS.dylib
//

#import "LCOSGestureHandler.h"
#import "LCOSFloatingButton.h"
#import "LCOSSettingsView.h"
#import "LCOSLogManager.h"
#import <UIKit/UIKit.h>

@interface LCOSGestureHandler ()
@property (nonatomic, strong) UILongPressGestureRecognizer *longPressGesture;
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
        [[LCOSLogManager sharedManager] forceLog:@"LCOS Gesture: init"];
    }
    return self;
}

- (void)ensureHostWindow {
    if (!_hostWindow) {
        UIScene *scene = [UIApplication sharedApplication].connectedScenes.anyObject;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        _hostWindow = windowScene ? windowScene.windows.firstObject : nil;
    }
}

- (void)setupGestureRecognizers {
    [self ensureHostWindow];
    if (!_hostWindow) {
        [[LCOSLogManager sharedManager] forceLog:@"LCOS Gesture: No host window found, will retry"];
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
    
    [[LCOSLogManager sharedManager] forceLog:@"LCOS Gesture: Three-finger long press recognizer registered for settings"];
}

- (void)handleLongPressGesture:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self handleThreeFingerLongPress];
    }
}

// UIGestureRecognizerDelegate - prevent intercepting floating button touches
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS GestureHandler: shouldReceiveTouch gesture=%@ touchView=%@", gestureRecognizer, touch.view]];
    // Don't intercept touches on the floating button (which is on overlay window)
    LCOSFloatingButton *floatingButton = [LCOSFloatingButton sharedButton];
    if (touch.view == floatingButton || [touch.view isDescendantOfView:floatingButton]) {
        [[LCOSLogManager sharedManager] forceLog:@"LCOS GestureHandler: shouldReceiveTouch -> NO (button touch)"];
        return NO;
    }
    [[LCOSLogManager sharedManager] forceLog:@"LCOS GestureHandler: shouldReceiveTouch -> YES"];
    return YES;
}

- (void)handleThreeFingerLongPress {
    [[LCOSLogManager sharedManager] forceLog:@"LCOS Gesture: Three finger long press - showing settings"];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        LCOSSettingsView *settingsView = [[LCOSSettingsView alloc] initWithNibName:nil bundle:nil];
        UIScene *scene = [UIApplication sharedApplication].connectedScenes.anyObject;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        UIWindow *window = windowScene.windows.firstObject;
        if (window && window.rootViewController) {
            [window.rootViewController presentViewController:settingsView animated:YES completion:nil];
        }
    });
}

+ (void)registerGestureRecognizers {
    // Called from constructor - ensures shared handler is created and gestures registered
    LCOSGestureHandler *handler = [LCOSGestureHandler sharedHandler];
    [handler setupGestureRecognizers];
}

@end
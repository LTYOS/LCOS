//
//  LCOSGestureHandler.m
//  LCOS.dylib
//

#import "LCOSGestureHandler.h"
#import "LCOSSettingsView.h"
#import "LCOSLogManager.h"
#import "LCOSCore.h"
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

// Now gestures are registered on overlay window by LCOSCore
// This handler is kept for backward compatibility but doesn't register gestures anymore
- (void)setupGestureRecognizers {
    [[LCOSLogManager sharedManager] forceLog:@"LCOS Gesture: Gesture registration moved to LCOSCore (overlay window)"];
}

+ (void)registerGestureRecognizers {
    // Called from constructor - gesture registration now handled by LCOSCore on overlay window
    LCOSGestureHandler *handler = [LCOSGestureHandler sharedHandler];
    [handler setupGestureRecognizers];
}

@end
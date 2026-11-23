//
//  LCOSPluginEntry.m
//  LCOS.dylib
//  LiveContainer plugin entry point - Minimal constructor, deferred init
//

#import "LCOSPluginEntry.h"
#import "LCOSCore.h"
#import "LCOSXPC.h"
#import "LCOSLogManager.h"
#import "LCOSGestureHandler.h"
#import <mach/mach.h>
#import <UIKit/UIKit.h>

// Static initialization - runs before constructor
static void LCOSInitialize(void) __attribute__((constructor));

static void LCOSInitialize(void) {
    // ABSOLUTELY MINIMAL: Just register for app activation notification
    // Do NOT call any LCOS code here - not even logging
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
        // Remove observer immediately - one-time only
        [[NSNotificationCenter defaultCenter] removeObserver:nil
                                                        name:UIApplicationDidBecomeActiveNotification
                                                      object:nil];
        
        // NOW it's safe to initialize - app is fully active
        dispatch_async(dispatch_get_main_queue(), ^{
            @autoreleasepool {
                [[LCOSLogManager sharedManager] forceLog:@("LCOS: App active, initializing...")];
                
                [LCOSCore startServer];
                [LCOSGestureHandler registerGestureRecognizers];
                
                [[LCOSLogManager sharedManager] forceLog:@("LCOS: Initialization complete")];
            }
        });
    }];
}

// Backup: +load also registers (in case constructor order differs)
@implementation LCOSPluginEntry

+ (void)load {
    // Same pattern - defer to app activation
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
        [[NSNotificationCenter defaultCenter] removeObserver:nil
                                                        name:UIApplicationDidBecomeActiveNotification
                                                      object:nil];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            @autoreleasepool {
                [[LCOSLogManager sharedManager] forceLog:@("LCOS: +load path - initializing...")];
                
                [LCOSCore startServer];
                [LCOSGestureHandler registerGestureRecognizers];
                
                [[LCOSLogManager sharedManager] forceLog:@("LCOS: +load path complete")];
            }
        });
    }];
}

@end
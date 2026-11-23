//
//  LCOSPluginEntry.m
//  LCOS.dylib
//  LiveContainer plugin entry point
//

#import "LCOSPluginEntry.h"
#import "LCOSCore.h"
#import "LCOSXPC.h"
#import "LCOSLogManager.h"
#import "LCOSGestureHandler.h"
#import <mach/mach.h>

// Constructor entry point - guaranteed to run when dylib is loaded
__attribute__((constructor))
static void LCOSPluginConstructor(void) {
    // Force log to verify dylib is loaded and executing
    [[LCOSLogManager sharedManager] forceLog:@("LCOS Plugin: Constructor called - dylib loaded")];
    
    // Defer all UIKit operations to main queue after app is ready
    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            [[LCOSLogManager sharedManager] forceLog:@("LCOS Plugin: Main queue init started")];
            
            // Start XPC server (will handle bootstrap failure gracefully)
            [LCOSCore startServer];
            
            // Register gesture handlers
            [LCOSGestureHandler registerGestureRecognizers];
            
            [[LCOSLogManager sharedManager] forceLog:@("LCOS Plugin: Main queue init complete")];
        }
    });
    
    [[LCOSLogManager sharedManager] forceLog:@("LCOS Plugin: Constructor queued main init")];
}

// Also provide +load as backup (in case constructor doesn't work)
@implementation LCOSPluginEntry

+ (void)load {
    // +load runs very early, defer to main queue
    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            [[LCOSLogManager sharedManager] forceLog:@("LCOS Plugin: +load main queue init started")];
            
            [LCOSCore startServer];
            [LCOSGestureHandler registerGestureRecognizers];
            
            [[LCOSLogManager sharedManager] forceLog:@("LCOS Plugin: +load main queue init complete")];
        }
    });
}

@end
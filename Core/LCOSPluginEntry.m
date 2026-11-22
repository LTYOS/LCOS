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
    
    // Start XPC server (will handle bootstrap failure gracefully)
    [LCOSCore startServer];
    
    // Register gesture handlers
    [LCOSGestureHandler registerGestureRecognizers];
    
    [[LCOSLogManager sharedManager] forceLog:@("LCOS Plugin: Initialization complete")];
}

// Also provide +load as backup (in case constructor doesn't work)
@implementation LCOSPluginEntry

+ (void)load {
    [[LCOSLogManager sharedManager] forceLog:@("LCOS Plugin: +load called")];
    [LCOSCore startServer];
    [LCOSGestureHandler registerGestureRecognizers];
}

@end
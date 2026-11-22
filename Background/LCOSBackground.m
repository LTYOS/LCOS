//
//  LCOSBackground.m
//  LCOS.dylib
//

#import "LCOSBackground.h"
#import "LCOSAppContainer.h"

@implementation LCOSBackground

static BOOL _isRunning = NO;

+ (void)startBackgroundProcess {
    if (_isRunning) return;
    _isRunning = YES;
    [LCOSAppContainer ensureLCOSDirectoryExists];
    NSLog(@"LCOS: Background process started");
}

+ (void)stopBackgroundProcess {
    _isRunning = NO;
    NSLog(@"LCOS: Background process stopped");
}

+ (void)manageAppContainer {
    [LCOSAppContainer ensureLCOSDirectoryExists];
}

@end
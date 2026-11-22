//
//  LCOSLauncherView.m
//  LCOS.dylib
//

#import "LCOSLauncherView.h"
#import "LCOSFolder.h"
#import "LCOSGrid.h"
#import "LCOSDock.h"
#import "LCOSLogManager.h"

@interface LCOSLauncherView ()

@end

@implementation LCOSLauncherView

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    // Setup grid
    self.grid = [[LCOSGrid alloc] initWithFrame:self.view.bounds];
    [self.view addSubview:self.grid];
    
    // Setup dock
    self.dock = [[LCOSDock alloc] initWithFrame:CGRectMake(0, self.view.frame.size.height - 100, self.view.frame.size.width, 100)];
    [self.view addSubview:self.dock];
    
    [[LCOSLogManager sharedManager] logMessage:@"LCOS Launcher UI loaded" level:@"INFO"];
}

@end
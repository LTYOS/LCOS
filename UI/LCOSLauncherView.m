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
@property (nonatomic, strong) LCOSGrid *grid;
@property (nonatomic, strong) LCOSDock *dock;
@end

@implementation LCOSLauncherView

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    // Setup grid
    self.grid = [[LCOSGrid alloc] initWithFrame:self.view.bounds];
    self.grid.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.grid];
    
    // Setup dock
    self.dock = [[LCOSDock alloc] initWithFrame:CGRectMake(0, self.view.frame.size.height - 100, self.view.frame.size.width, 100)];
    self.dock.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    [self.view addSubview:self.dock];
    
    [[LCOSLogManager sharedManager] forceLog:@("LCOS Launcher UI loaded, view bounds: " + NSStringFromCGRect(self.view.bounds))];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // Ensure grid fills the view above dock
    if (self.grid) {
        self.grid.frame = CGRectMake(0, 0, self.view.bounds.size.width, self.view.bounds.size.height - 100);
    }
    if (self.dock) {
        self.dock.frame = CGRectMake(0, self.view.bounds.size.height - 100, self.view.bounds.size.width, 100);
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [[LCOSLogManager sharedManager] forceLog:@("LCOS Launcher viewDidAppear")];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[LCOSLogManager sharedManager] forceLog:@("LCOS Launcher viewWillDisappear")];
}

@end
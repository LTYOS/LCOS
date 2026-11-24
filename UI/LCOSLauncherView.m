//
//  LCOSLauncherView.m
//  LCOS.dylib
//

#import "LCOSLauncherView.h"
#import "LCOSFolder.h"
#import "LCOSGrid.h"
#import "LCOSDock.h"
#import "LCOSLogManager.h"
#import "LCOSCore.h"

@implementation LCOSLauncherView

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        [[LCOSLogManager sharedManager] forceLog:@"LCOS Launcher: init START"];
        self.modalPresentationStyle = UIModalPresentationFullScreen;
    }
    return self;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [[LCOSLogManager sharedManager] forceLog:@"LCOS Launcher: init START"];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    [[LCOSLogManager sharedManager] forceLog:@"LCOS Launcher: viewDidLoad START"];
    
    // Add close button
    self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.closeButton setTitle:@"关闭" forState:UIControlStateNormal];
    self.closeButton.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [self.closeButton addTarget:self action:@selector(closeTapped:) forControlEvents:UIControlEventTouchUpInside];
    self.closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.closeButton];
    
    // Use view's layout guide for child VC compatibility
    UILayoutGuide *guide = self.view.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.closeButton.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-20],
        [self.closeButton.topAnchor constraintEqualToAnchor:guide.topAnchor constant:20],
    ]];
    
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Launcher: closeButton constraints set, guide.layoutFrame=%@", NSStringFromCGRect(guide.layoutFrame)]];
    
    // Setup grid
    self.grid = [[LCOSGrid alloc] initWithFrame:self.view.bounds];
    self.grid.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.grid];
    
    // Setup dock
    self.dock = [[LCOSDock alloc] initWithFrame:CGRectMake(0, self.view.frame.size.height - 100, self.view.frame.size.width, 100)];
    self.dock.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    [self.view addSubview:self.dock];
    
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Launcher UI loaded, view bounds: %@", NSStringFromCGRect(self.view.bounds)]];
}

- (void)closeTapped:(UIButton *)sender {
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Launcher close tapped, sender=%@", sender]];
    [[LCOSCore sharedInstance] hideLauncher];
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
    
    // Log closeButton frame after layout
    if (self.closeButton) {
        [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Launcher: closeButton frame=%@, superview=%@", NSStringFromCGRect(self.closeButton.frame), self.closeButton.superview ? self.closeButton.superview.description : @"nil"]];
    }
}

// Debug hitTest on the view
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *result = [self.view hitTest:point withEvent:event];
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS LauncherView.view: hitTest point=%@ -> %@", NSStringFromCGPoint(point), result ? result.description : @"nil"]];
    return result;
}
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
    [[LCOSLogManager sharedManager] forceLog:@"LCOS Launcher viewDidAppear"];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[LCOSLogManager sharedManager] forceLog:@"LCOS Launcher viewWillDisappear"];
}

@end
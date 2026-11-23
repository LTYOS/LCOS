//
//  LCOSFloatingButton.m
//  LCOS.dylib
//

#import "LCOSFloatingButton.h"
#import "LCOSCore.h"
#import "LCOSLogManager.h"
#import <UIKit/UIKit.h>

@interface LCOSFloatingButton ()
@property (nonatomic, assign) CGPoint initialTouchPoint;
@property (nonatomic, assign) BOOL isDragging;
@end

@implementation LCOSFloatingButton

+ (instancetype)sharedButton {
    static LCOSFloatingButton *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[LCOSFloatingButton alloc] initWithFrame:CGRectMake(0, 0, 60, 60)];
    });
    return sharedInstance;
}

- (instancetype)initWithFrame:(CGRect)frame {
    [[LCOSLogManager sharedManager] forceLog:@"LCOS FloatingButton: initWithFrame ENTRY"];
    self = [super initWithFrame:frame];
    if (self) {
        [self setupButton];
    }
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS FloatingButton: initWithFrame EXIT self=%@", self]];
    return self;
}

- (void)dealloc {
    [[LCOSLogManager sharedManager] forceLog:@"LCOS FloatingButton: dealloc called"];
}

- (void)setupButton {
    // Button appearance - circular floating button
    self.backgroundColor = [UIColor systemBlueColor];
    self.layer.cornerRadius = 30;
    // IMPORTANT: NO clipsToBounds/masksToBounds - it clips touch area!
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOffset = CGSizeMake(0, 2);
    self.layer.shadowOpacity = 0.3;
    self.layer.shadowRadius = 4;
    
    // Icon - home/grid symbol
    UIImage *icon = [UIImage systemImageNamed:@"square.grid.2x2.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightMedium]];
    [self setImage:icon forState:UIControlStateNormal];
    self.tintColor = [UIColor whiteColor];
    self.imageEdgeInsets = UIEdgeInsetsMake(15, 15, 15, 15);
    
    // Touch events - only tap to toggle launcher
    [self addTarget:self action:@selector(handleTap:) forControlEvents:UIControlEventTouchUpInside];
    
    // Initially hidden
    self.hidden = YES;
    self.alpha = 0.0;
    
    // Ensure button receives touches
    self.userInteractionEnabled = YES;
    self.exclusiveTouch = YES;
}

- (void)showOnWindow:(UIWindow *)window {
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS FloatingButton: showOnWindow called, window=%@", window]];
    
    if (!window || !window.rootViewController) {
        [[LCOSLogManager sharedManager] forceLog:@"LCOS FloatingButton: showOnWindow - no window or rootVC"];
        return;
    }
    
    // Check if already on this window's root view
    if (self.superview == window.rootViewController.view) {
        [[LCOSLogManager sharedManager] forceLog:@"LCOS FloatingButton: showOnWindow - already on this rootVC view"];
        self.hidden = NO;
        [UIView animateWithDuration:0.3 animations:^{
            self.alpha = 1.0;
        }];
        return;
    }
    
    // Remove from previous view if any
    [self removeFromSuperview];
    
    // Add to rootViewController.view (not window directly!)
    [window.rootViewController.view addSubview:self];
    [window.rootViewController.view bringSubviewToFront:self];
    
    // Position at bottom right by default
    CGRect screenBounds = window.bounds;
    self.frame = CGRectMake(screenBounds.size.width - 80, screenBounds.size.height - 180, 60, 60);
    
    // Animate in
    self.hidden = NO;
    [UIView animateWithDuration:0.3 animations:^{
        self.alpha = 1.0;
    }];
    
    // Ensure button is user interaction enabled
    self.userInteractionEnabled = YES;
    self.exclusiveTouch = YES;
    
    // Force to topmost layer
    self.layer.zPosition = CGFLOAT_MAX;
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS FloatingButton: Shown on window.rootViewController.view, frame=%@, layer.zPosition=%.0f", NSStringFromCGRect(self.frame), self.layer.zPosition]];
}

- (void)hide {
    [UIView animateWithDuration:0.2 animations:^{
        self.alpha = 0.0;
    } completion:^(BOOL finished) {
        self.hidden = YES;
        [self removeFromSuperview];
    }];
    [[LCOSLogManager sharedManager] forceLog:@"LCOS FloatingButton: Hidden"];
}

// Expand touchable area beyond visual bounds
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS FloatingButton: hitTest point=(%.0f,%.0f) bounds=%@", point.x, point.y, NSStringFromCGRect(self.bounds)]];
    // Expand hit test area by 20pt in all directions
    CGRect expandedBounds = CGRectInset(self.bounds, -20, -20);
    if (CGRectContainsPoint(expandedBounds, point)) {
        [[LCOSLogManager sharedManager] forceLog:@"LCOS FloatingButton: hitTest -> self (expanded)"];
        return self;
    }
    UIView *result = [super hitTest:point withEvent:event];
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS FloatingButton: hitTest -> %@", result ?: @"nil"]];
    return result;
}

- (void)handleTap:(UIButton *)sender {
    [[LCOSLogManager sharedManager] forceLog:@"LCOS FloatingButton: handleTap ENTRY"];
    
    if (self.isDragging) {
        [[LCOSLogManager sharedManager] forceLog:@"LCOS FloatingButton: handleTap - isDragging true, return"];
        return;
    }
    
    [[LCOSLogManager sharedManager] forceLog:@"LCOS FloatingButton: Tapped, calling LCOSCore toggleLauncher"];
    [[LCOSCore sharedInstance] toggleLauncher];
    [[LCOSLogManager sharedManager] forceLog:@"LCOS FloatingButton: handleTap EXIT"];
}

// UIGestureRecognizerDelegate - ensure button receives touches
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS FloatingButton: shouldReceiveTouch gesture=%@ touchView=%@", gestureRecognizer, touch.view]];
    // Allow all touches on the button itself
    if (touch.view == self || [touch.view isDescendantOfView:self]) {
        [[LCOSLogManager sharedManager] forceLog:@"LCOS FloatingButton: shouldReceiveTouch -> YES"];
        return YES;
    }
    [[LCOSLogManager sharedManager] forceLog:@"LCOS FloatingButton: shouldReceiveTouch -> NO"];
    return NO;
}

// Touch event overrides - trace responder chain
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS FloatingButton: touchesBegan touches=%@", touches]];
    [super touchesBegan:touches withEvent:event];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS FloatingButton: touchesEnded touches=%@", touches]];
    [super touchesEnded:touches withEvent:event];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS FloatingButton: touchesCancelled touches=%@", touches]];
    [super touchesCancelled:touches withEvent:event];
}

// Trace action sending
- (void)sendAction:(SEL)action to:(id)target forEvent:(UIEvent *)event {
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS FloatingButton: sendAction action=%@ target=%@ event=%@", NSStringFromSelector(action), target, event]];
    [super sendAction:action to:target forEvent:event];
    [[LCOSLogManager sharedManager] forceLog:@"LCOS FloatingButton: sendAction completed"];
}

@end
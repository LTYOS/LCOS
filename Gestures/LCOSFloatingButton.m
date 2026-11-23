//
//  LCOSFloatingButton.m
//  LCOS.dylib
//
//
#import "LCOSFloatingButton.h"
#import "LCOSLauncherView.h"
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
    [[LCOSLogManager sharedManager] forceLog:@("LCOS FloatingButton: initWithFrame ENTRY")];
    self = [super initWithFrame:frame];
    if (self) {
        [self setupButton];
    }
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS FloatingButton: initWithFrame EXIT self=%@", self]];
    return self;
}

- (void)dealloc {
    [[LCOSLogManager sharedManager] forceLog:@("LCOS FloatingButton: dealloc called")];
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
    
    // Touch events - use correct selector signatures matching method signatures
    [self addTarget:self action:@selector(handleTap:) forControlEvents:UIControlEventTouchUpInside];
    [self addTarget:self action:@selector(handleDragStart:forEvent:) forControlEvents:UIControlEventTouchDown];
    [self addTarget:self action:@selector(handleDragMove:forEvent:) forControlEvents:UIControlEventTouchDragInside];
    [self addTarget:self action:@selector(handleDragMove:forEvent:) forControlEvents:UIControlEventTouchDragOutside];
    [self addTarget:self action:@selector(handleDragEnd:forEvent:) forControlEvents:UIControlEventTouchUpInside];
    [self addTarget:self action:@selector(handleDragEnd:forEvent:) forControlEvents:UIControlEventTouchUpOutside];
    [self addTarget:self action:@selector(handleDragEnd:forEvent:) forControlEvents:UIControlEventTouchCancel];
    
    // Initially hidden
    self.hidden = YES;
    self.alpha = 0.0;
    
    // Ensure button receives touches
    self.userInteractionEnabled = YES;
    self.exclusiveTouch = YES;
}

- (void)showOnWindow:(UIWindow *)window {
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS FloatingButton: showOnWindow called, window=%@", window]];
    
    if (!window || self.superview == window) {
        [[LCOSLogManager sharedManager] forceLog:@("LCOS FloatingButton: showOnWindow - early return")];
        return;
    }
    
    // Remove from previous window if any
    [self removeFromSuperview];
    
    // Add to window at top level - use highest level to ensure tap works
    [window addSubview:self];
    [window bringSubviewToFront:self];
    
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
    
    // Log layer info for debugging
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS FloatingButton: Shown on window, frame=%@, superview=%@, layer.zPosition=%.0f", NSStringFromCGRect(self.frame), self.superview, self.layer.zPosition]];
    
    // Force to topmost layer
    self.layer.zPosition = CGFLOAT_MAX;
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS FloatingButton: layer.zPosition set to MAX=%.0f", self.layer.zPosition]];
}

// Expand touchable area beyond visual bounds
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS FloatingButton: hitTest point=(%.0f,%.0f) bounds=%@", point.x, point.y, NSStringFromCGRect(self.bounds)]];
    // Expand hit test area by 20pt in all directions
    CGRect expandedBounds = CGRectInset(self.bounds, -20, -20);
    if (CGRectContainsPoint(expandedBounds, point)) {
        [[LCOSLogManager sharedManager] forceLog:@("LCOS FloatingButton: hitTest -> self (expanded)")];
        return self;
    }
    UIView *result = [super hitTest:point withEvent:event];
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS FloatingButton: hitTest -> %@", result ?: @"nil"]];
    return result;
}

- (void)hide {
    [UIView animateWithDuration:0.2 animations:^{
        self.alpha = 0.0;
    } completion:^(BOOL finished) {
        self.hidden = YES;
        [self removeFromSuperview];
    }];
    [[LCOSLogManager sharedManager] forceLog:@("LCOS FloatingButton: Hidden")];
}

- (void)handleTap:(UIButton *)sender {
    [[LCOSLogManager sharedManager] forceLog:@("LCOS FloatingButton: handleTap ENTRY")];
    
    if (self.isDragging) {
        [[LCOSLogManager sharedManager] forceLog:@("LCOS FloatingButton: handleTap - isDragging true, return")];
        return;
    }
    
    [[LCOSLogManager sharedManager] forceLog:@("LCOS FloatingButton: Tapped, calling toggleLauncher")];
    [self toggleLauncher];
    [[LCOSLogManager sharedManager] forceLog:@("LCOS FloatingButton: handleTap EXIT")];
}

// UIGestureRecognizerDelegate - ensure button receives touches
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS FloatingButton: shouldReceiveTouch gesture=%@ touchView=%@", gestureRecognizer, touch.view]];
    // Allow all touches on the button itself
    if (touch.view == self || [touch.view isDescendantOfView:self]) {
        [[LCOSLogManager sharedManager] forceLog:@("LCOS FloatingButton: shouldReceiveTouch -> YES")];
        return YES;
    }
    [[LCOSLogManager sharedManager] forceLog:@("LCOS FloatingButton: shouldReceiveTouch -> NO")];
    return NO;
}

- (void)handleDragStart:(UIButton *)sender forEvent:(UIEvent *)event {
    [[LCOSLogManager sharedManager] forceLog:@("LCOS FloatingButton: handleDragStart ENTRY")];
    UITouch *touch = [[event allTouches] anyObject];
    if (touch) {
        self.initialTouchPoint = [touch locationInView:self];
        self.isDragging = NO;
    }
    [[LCOSLogManager sharedManager] forceLog:@("LCOS FloatingButton: handleDragStart EXIT")];
}

- (void)handleDragMove:(UIButton *)sender forEvent:(UIEvent *)event {
    [[LCOSLogManager sharedManager] forceLog:@("LCOS FloatingButton: handleDragMove ENTRY")];
    UITouch *touch = [[event allTouches] anyObject];
    if (!touch) {
        [[LCOSLogManager sharedManager] forceLog:@("LCOS FloatingButton: handleDragMove - no touch")];
        return;
    }
    
    CGPoint currentPoint = [touch locationInView:self];
    CGFloat dx = currentPoint.x - self.initialTouchPoint.x;
    CGFloat dy = currentPoint.y - self.initialTouchPoint.y;
    
    // If moved more than threshold, consider it dragging
    if (fabs(dx) > 5 || fabs(dy) > 5) {
        self.isDragging = YES;
        
        CGPoint newCenter = CGPointMake(self.center.x + dx, self.center.y + dy);
        
        // Constrain to window bounds with margin
        if (self.superview) {
            CGFloat margin = 40;
            CGRect bounds = self.superview.bounds;
            newCenter.x = MAX(margin, MIN(bounds.size.width - margin, newCenter.x));
            newCenter.y = MAX(margin, MIN(bounds.size.height - margin, newCenter.y));
        }
        
        self.center = newCenter;
    }
    [[LCOSLogManager sharedManager] forceLog:@("LCOS FloatingButton: handleDragMove EXIT")];
}

- (void)handleDragEnd:(UIButton *)sender forEvent:(UIEvent *)event {
    [[LCOSLogManager sharedManager] forceLog:@("LCOS FloatingButton: handleDragEnd ENTRY")];
    if (self.isDragging) {
        [[LCOSLogManager sharedManager] forceLog:@("LCOS FloatingButton: Drag ended")];
    }
    self.isDragging = NO;
    [[LCOSLogManager sharedManager] forceLog:@("LCOS FloatingButton: handleDragEnd EXIT")];
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
    [[LCOSLogManager sharedManager] forceLog:@("LCOS FloatingButton: sendAction completed")];
}

- (void)toggleLauncher {
    [[LCOSLogManager sharedManager] forceLog:@("LCOS FloatingButton: toggleLauncher called")];
    
    if (!self.launcher) {
        [[LCOSLogManager sharedManager] forceLog:@("LCOS FloatingButton: No launcher set")];
        return;
    }
    
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS FloatingButton: launcher=%@", self.launcher]];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[LCOSLogManager sharedManager] forceLog:@("LCOS FloatingButton: on main queue")];
        
        UIScene *scene = [UIApplication sharedApplication].connectedScenes.anyObject;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        UIWindow *window = windowScene ? windowScene.windows.firstObject : nil;
        if (!window) {
            [[LCOSLogManager sharedManager] forceLog:@("LCOS FloatingButton: No window")];
            return;
        }
        if (!window.rootViewController) {
            [[LCOSLogManager sharedManager] forceLog:@("LCOS FloatingButton: No rootViewController")];
            return;
        }
        
        [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS FloatingButton: rootVC=%@", window.rootViewController]];
        
        if (self.launcher.presentedViewController || self.launcher.isBeingPresented || self.launcher.isBeingDismissed) {
            // Dismiss - ensure we wait for completion before allowing re-present
            [[LCOSLogManager sharedManager] forceLog:@("LCOS FloatingButton: Dismissing launcher")];
            [self.launcher dismissViewControllerAnimated:YES completion:^{
                [[LCOSLogManager sharedManager] forceLog:@("LCOS FloatingButton: Dismissed launcher completion")];
            }];
        } else {
            // Present - ensure modalPresentationStyle is set
            [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS FloatingButton: Launcher modalPresentationStyle=%ld", (long)self.launcher.modalPresentationStyle]];
            [[LCOSLogManager sharedManager] forceLog:@("LCOS FloatingButton: Presenting launcher")];
            [window.rootViewController presentViewController:self.launcher animated:YES completion:^{
                [[LCOSLogManager sharedManager] forceLog:@("LCOS FloatingButton: Presented launcher completion")];
            }];
        }
    });
}

@end
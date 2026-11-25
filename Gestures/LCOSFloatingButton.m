//
//  LCOSFloatingButton.m
//  LCOS.dylib
//

#import "LCOSFloatingButton.h"
#import "LCOSCore.h"
#import "LCOSLogManager.h"
#import <UIKit/UIKit.h>

@interface LCOSFloatingButton () <UIGestureRecognizerDelegate>
@property (nonatomic, assign) BOOL isDragging;
@property (nonatomic, strong) UIPanGestureRecognizer *dragGesture;
@end

static NSString *const kLCOSButtonCenterX = @"LCOSFloatingButton.centerX";
static NSString *const kLCOSButtonCenterY = @"LCOSFloatingButton.centerY";

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
    
    self.dragGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDrag:)];
    self.dragGesture.delegate = self;
    self.dragGesture.maximumNumberOfTouches = 1;
    self.dragGesture.cancelsTouchesInView = NO;
    UILongPressGestureRecognizer *holdToDrag = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleHoldToDrag:)];
    holdToDrag.minimumPressDuration = 0.35;
    holdToDrag.allowableMovement = CGFLOAT_MAX;
    holdToDrag.cancelsTouchesInView = NO;
    [self addGestureRecognizer:holdToDrag];
    [self.dragGesture requireGestureRecognizerToFail:holdToDrag];
    self.dragGesture.enabled = NO;
    [self addGestureRecognizer:self.dragGesture];

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
    
    // Restore one persistent position; opening the launcher never resets it.
    self.bounds = CGRectMake(0, 0, 60, 60);
    [self restorePositionInWindow:window];
    
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

- (void)restorePositionInWindow:(UIWindow *)window {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    UIEdgeInsets safe = window.safeAreaInsets;
    CGFloat halfWidth = CGRectGetWidth(self.bounds) / 2.0;
    CGFloat halfHeight = CGRectGetHeight(self.bounds) / 2.0;
    CGFloat minX = safe.left + halfWidth + 8.0;
    CGFloat maxX = MAX(minX, CGRectGetWidth(window.bounds) - safe.right - halfWidth - 8.0);
    CGFloat minY = safe.top + halfHeight + 8.0;
    CGFloat maxY = MAX(minY, CGRectGetHeight(window.bounds) - safe.bottom - halfHeight - 8.0);
    BOOL hasSavedPosition = [defaults objectForKey:kLCOSButtonCenterX] != nil &&
                            [defaults objectForKey:kLCOSButtonCenterY] != nil;
    CGFloat x = hasSavedPosition ? [defaults doubleForKey:kLCOSButtonCenterX] : maxX;
    CGFloat y = hasSavedPosition ? [defaults doubleForKey:kLCOSButtonCenterY] : maxY - 100.0;
    self.center = CGPointMake(MIN(maxX, MAX(minX, x)), MIN(maxY, MAX(minY, y)));
}

- (void)handleHoldToDrag:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.isDragging = YES;
        self.dragGesture.enabled = YES;
        [self.superview bringSubviewToFront:self];
        [[LCOSLogManager sharedManager] forceLog:@"LCOS FloatingButton: long-press drag enabled"];
    }
}

- (void)handleDrag:(UIPanGestureRecognizer *)gesture {
    UIWindow *window = self.window;
    UIView *container = self.superview;
    if (!window || !container) return;
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.isDragging = YES;
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(resetDragging) object:nil];
    }
    if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [gesture translationInView:container];
        self.center = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
        [gesture setTranslation:CGPointZero inView:container];
        [self restorePositionInWindow:window];
    }
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        [NSUserDefaults.standardUserDefaults setDouble:self.center.x forKey:kLCOSButtonCenterX];
        [NSUserDefaults.standardUserDefaults setDouble:self.center.y forKey:kLCOSButtonCenterY];
        // A drag must not also activate TouchUpInside when the finger lifts.
        [self performSelector:@selector(resetDragging) withObject:nil afterDelay:0.15];
    }
}

- (void)resetDragging {
    self.isDragging = NO;
    self.dragGesture.enabled = NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return gestureRecognizer.view == self && otherGestureRecognizer.view == self;
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
    // The recognizer is attached to this button; its own touches must always
    // be accepted. Do not reject the drag gesture before it can begin.
    return gestureRecognizer == self.dragGesture &&
           (touch.view == self || [touch.view isDescendantOfView:self]);
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
//
//  LCOSDock.m
//  LCOS.dylib
//  Liquid Glass dock - iOS 26/27 style with edge highlights
//

#import "LCOSDock.h"
#import <objc/runtime.h>

// Private UICustomBlurEffect for pure gaussian blur without system gray tint
@interface UICustomBlurEffect : UIBlurEffect
+ (instancetype)effectWithBlurRadius:(CGFloat)radius;
+ (instancetype)effectWithStyle:(NSInteger)style;
@end

@interface LCOSDock ()
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UIView *tintView;
@property (nonatomic, strong) CAGradientLayer *edgeGradient;
@property (nonatomic, strong) CAGradientLayer *sheenGradient;
@end

@implementation LCOSDock

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupGlass];
    }
    return self;
}

- (UIBlurEffect *)liquidGlassBlur {
    // Use UICustomBlurEffect for pure gaussian blur (no system gray material).
    // iOS 26 Liquid Glass = gaussian blur of background, not a tinted material.
    Class customBlur = NSClassFromString(@"UICustomBlurEffect");
    if (customBlur) {
        // effectWithBlurRadius: gives pure blur without color tint
        if ([customBlur respondsToSelector:@selector(effectWithBlurRadius:)]) {
            return [customBlur effectWithBlurRadius:24.0];
        }
        // Fallback: style 1 = light, but without material saturation
        if ([customBlur respondsToSelector:@selector(effectWithStyle:)]) {
            UICustomBlurEffect *effect = [customBlur effectWithStyle:1];
            // Set blurRadius via KVC on the internal effect settings
            @try {
                [effect setValue:@24.0 forKey:@"blurRadius"];
            } @catch (NSException *e) {}
            return effect;
        }
    }
    // Ultimate fallback: systemThinMaterial (least gray of system materials)
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial];
}

- (void)setupGlass {
    self.backgroundColor = [UIColor clearColor];
    self.clipsToBounds = NO;
    
    // iOS 26/27 dock: continuous rounded corners, ~34pt radius
    CGFloat radius = 34.0;
    if (@available(iOS 13.0, *)) {
        self.layer.cornerCurve = kCACornerCurveContinuous;
    }
    self.layer.cornerRadius = radius;
    
    // Soft floating shadow
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOffset = CGSizeMake(0, 4);
    self.layer.shadowOpacity = 0.10;
    self.layer.shadowRadius = 16;
    
    // Pure gaussian blur (no system gray material)
    UIBlurEffect *blur = [self liquidGlassBlur];
    self.blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    self.blurView.layer.cornerRadius = radius;
    if (@available(iOS 13.0, *)) {
        self.blurView.layer.cornerCurve = kCACornerCurveContinuous;
    }
    self.blurView.layer.masksToBounds = YES;
    self.blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    
    // NO vibrancy - it adds system gray tint. Pure blur only.
    self.blurView.alpha = 0.9;
    [self addSubview:self.blurView];
    
    // Very subtle white tint (liquid glass feel) - minimal to avoid gray
    self.tintView = [[UIView alloc] init];
    self.tintView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.03];
    self.tintView.layer.cornerRadius = radius;
    if (@available(iOS 13.0, *)) {
        self.tintView.layer.cornerCurve = kCACornerCurveContinuous;
    }
    self.tintView.layer.masksToBounds = YES;
    self.tintView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tintView.userInteractionEnabled = NO;
    [self addSubview:self.tintView];
    
    // === GLASS EDGE HIGHLIGHTS ===
    // Top-left + bottom-right specular highlights via gradient stroke.
    self.edgeGradient = [CAGradientLayer layer];
    self.edgeGradient.frame = self.bounds;
    self.edgeGradient.cornerRadius = radius;
    if (@available(iOS 13.0, *)) {
        self.edgeGradient.cornerCurve = kCACornerCurveContinuous;
    }
    
    // Gradient colors: bright top-left -> dim middle -> bright bottom-right
    UIColor *bright = [UIColor colorWithWhite:1.0 alpha:0.65];
    UIColor *dim = [UIColor colorWithWhite:1.0 alpha:0.06];
    self.edgeGradient.colors = @[
        (id)bright.CGColor,
        (id)dim.CGColor,
        (id)dim.CGColor,
        (id)bright.CGColor
    ];
    self.edgeGradient.locations = @[@0.0, @0.25, @0.75, @1.0];
    // Diagonal from top-left (0,0) to bottom-right (1,1)
    self.edgeGradient.startPoint = CGPointMake(0, 0);
    self.edgeGradient.endPoint = CGPointMake(1, 1);
    
    // Mask so gradient only shows as a ~1.2pt stroke along the rounded edge
    CAShapeLayer *strokeMask = [CAShapeLayer layer];
    strokeMask.fillColor = [UIColor clearColor].CGColor;
    strokeMask.strokeColor = [UIColor blackColor].CGColor;
    strokeMask.lineWidth = 1.2;
    self.edgeGradient.mask = strokeMask;
    [self.layer addSublayer:self.edgeGradient];
    
    // === SOFT SHEEN ===
    // Subtle diagonal sheen sweeping across the glass for depth
    self.sheenGradient = [CAGradientLayer layer];
    self.sheenGradient.frame = self.bounds;
    self.sheenGradient.cornerRadius = radius;
    if (@available(iOS 13.0, *)) {
        self.sheenGradient.cornerCurve = kCACornerCurveContinuous;
    }
    self.sheenGradient.colors = @[
        (id)[UIColor colorWithWhite:1.0 alpha:0.10].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.06].CGColor
    ];
    self.sheenGradient.locations = @[@0.0, @0.35, @0.65, @1.0];
    self.sheenGradient.startPoint = CGPointMake(0, 0);
    self.sheenGradient.endPoint = CGPointMake(1, 1);
    self.sheenGradient.masksToBounds = YES;
    [self.layer addSublayer:self.sheenGradient];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.blurView.frame = self.bounds;
    self.tintView.frame = self.bounds;
    
    self.edgeGradient.frame = self.bounds;
    self.sheenGradient.frame = self.bounds;
    
    // Update stroke mask path for current bounds
    CAShapeLayer *strokeMask = (CAShapeLayer *)self.edgeGradient.mask;
    if ([strokeMask isKindOfClass:[CAShapeLayer class]]) {
        CGFloat inset = 0.6; // half of lineWidth so stroke is fully visible
        CGRect pathRect = CGRectInset(self.bounds, inset, inset);
        strokeMask.path = [UIBezierPath bezierPathWithRoundedRect:pathRect
                                                   cornerRadius:self.layer.cornerRadius - inset].CGPath;
        strokeMask.frame = self.bounds;
    }
}

@end
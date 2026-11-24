//
//  LCOSDock.m
//  LCOS.dylib
//  Liquid Glass dock - iOS 26/27 style
//

#import "LCOSDock.h"

@interface LCOSDock ()
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UIView *tintView;
@property (nonatomic, strong) UIView *highlightView;
@end

@implementation LCOSDock

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupGlass];
    }
    return self;
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
    self.layer.shadowOpacity = 0.12;
    self.layer.shadowRadius = 16;
    
    // Frosted glass: systemThinMaterial + vibrancy for wallpaper show-through
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial];
    self.blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    self.blurView.layer.cornerRadius = radius;
    if (@available(iOS 13.0, *)) {
        self.blurView.layer.cornerCurve = kCACornerCurveContinuous;
    }
    self.blurView.layer.masksToBounds = YES;
    self.blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    
    // Vibrancy for content inside the glass (icons will be added later)
    UIVibrancyEffect *vibrancy = [UIVibrancyEffect effectForBlurEffect:blur];
    UIVisualEffectView *vibrancyView = [[UIVisualEffectView alloc] initWithEffect:vibrancy];
    vibrancyView.frame = self.blurView.contentView.bounds;
    vibrancyView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.blurView.contentView addSubview:vibrancyView];
    
    // Reduce opacity so wallpaper shows through clearly
    self.blurView.alpha = 0.85;
    [self addSubview:self.blurView];
    
    // Very subtle white tint (liquid glass feel)
    self.tintView = [[UIView alloc] init];
    self.tintView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.08];
    self.tintView.layer.cornerRadius = radius;
    if (@available(iOS 13.0, *)) {
        self.tintView.layer.cornerCurve = kCACornerCurveContinuous;
    }
    self.tintView.layer.masksToBounds = YES;
    self.tintView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tintView.userInteractionEnabled = NO;
    [self addSubview:self.tintView];
    
    // Glass edge highlight (subtle top light)
    self.highlightView = [[UIView alloc] init];
    self.highlightView.backgroundColor = [UIColor clearColor];
    self.highlightView.layer.cornerRadius = radius;
    if (@available(iOS 13.0, *)) {
        self.highlightView.layer.cornerCurve = kCACornerCurveContinuous;
    }
    self.highlightView.layer.borderWidth = 0.5;
    self.highlightView.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.25].CGColor;
    self.highlightView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.highlightView.userInteractionEnabled = NO;
    [self addSubview:self.highlightView];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.blurView.frame = self.bounds;
    self.tintView.frame = self.bounds;
    self.highlightView.frame = self.bounds;
}

@end
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
    
    // Rounded capsule shape
    CGFloat radius = 28.0;
    self.layer.cornerRadius = radius;
    
    // Soft shadow for floating glass look
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOffset = CGSizeMake(0, 8);
    self.layer.shadowOpacity = 0.18;
    self.layer.shadowRadius = 24;
    
    // Frosted glass blur (system material adapts to light/dark)
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];
    self.blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    self.blurView.layer.cornerRadius = radius;
    self.blurView.layer.masksToBounds = YES;
    self.blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:self.blurView];
    
    // Subtle white tint for glass feel
    self.tintView = [[UIView alloc] init];
    self.tintView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.12];
    self.tintView.layer.cornerRadius = radius;
    self.tintView.layer.masksToBounds = YES;
    self.tintView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tintView.userInteractionEnabled = NO;
    [self addSubview:self.tintView];
    
    // Thin glass edge highlight (top brighter, like real glass)
    self.highlightView = [[UIView alloc] init];
    self.highlightView.backgroundColor = [UIColor clearColor];
    self.highlightView.layer.cornerRadius = radius;
    self.highlightView.layer.borderWidth = 0.5;
    self.highlightView.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.35].CGColor;
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
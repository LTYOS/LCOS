#import "LCOSNavigationBar.h"

@implementation LCOSNavigationBar
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.35];
        self.layer.cornerRadius = 3;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        NSArray<NSString *> *symbols = @[@"house.fill", @"square.stack.3d.up.fill", @"gearshape.fill"];
        NSArray<NSString *> *names = @[@"桌面", @"后台", @"设置"];
        NSArray<NSString *> *selectors = @[@"homeTapped", @"backgroundTapped", @"settingsTapped"];
        UIStackView *stack = [[UIStackView alloc] init];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 24;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:stack];
        for (NSInteger i = 0; i < symbols.count; i++) {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            button.tintColor = UIColor.whiteColor;
            UIImage *image = [UIImage systemImageNamed:symbols[i] withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightMedium]];
            [button setImage:image forState:UIControlStateNormal];
            button.accessibilityLabel = names[i];
            [button addTarget:self action:NSSelectorFromString(selectors[i]) forControlEvents:UIControlEventTouchUpInside];
            [button.widthAnchor constraintEqualToConstant:42].active = YES;
            [button.heightAnchor constraintEqualToConstant:44].active = YES;
            [stack addArrangedSubview:button];
        }
        [NSLayoutConstraint activateConstraints:@[
            [stack.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [stack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor]
        ]];
    }
    return self;
}
- (void)homeTapped { if (self.onHome) self.onHome(); }
- (void)backgroundTapped { if (self.onBackground) self.onBackground(); }
- (void)settingsTapped { if (self.onSettings) self.onSettings(); }
@end

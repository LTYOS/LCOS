#import "LCOSBackgroundView.h"
#import "LCOSAppModel.h"

@interface LCOSAppCardButton : UIButton
@property (nonatomic, strong) LCOSAppModel *appModel;
@end
@implementation LCOSAppCardButton
@end

@interface LCOSBackgroundView ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *stack;
@end

@implementation LCOSBackgroundView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0.04 alpha:0.92];
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(24, 70, 200, 40)];
        title.text = @"后台";
        title.font = [UIFont boldSystemFontOfSize:30];
        title.textColor = UIColor.whiteColor;
        [self addSubview:title];
        UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
        [close setTitle:@"返回桌面" forState:UIControlStateNormal];
        close.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:close];
        [NSLayoutConstraint activateConstraints:@[
            [close.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-24],
            [close.centerYAnchor constraintEqualToAnchor:title.centerYAnchor]
        ]];
        self.scrollView = [[UIScrollView alloc] init];
        self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
        self.scrollView.showsHorizontalScrollIndicator = NO;
        self.scrollView.decelerationRate = UIScrollViewDecelerationRateFast;
        [self addSubview:self.scrollView];
        self.stack = [[UIStackView alloc] init];
        self.stack.axis = UILayoutConstraintAxisHorizontal;
        self.stack.spacing = 18;
        self.stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.scrollView addSubview:self.stack];
        [NSLayoutConstraint activateConstraints:@[
            [self.scrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [self.scrollView.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:30],
            [self.scrollView.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-30],
            [self.stack.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor constant:24],
            [self.stack.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor constant:-24],
            [self.stack.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor],
            [self.stack.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor],
            [self.stack.heightAnchor constraintEqualToAnchor:self.scrollView.heightAnchor]
        ]];
    }
    return self;
}
- (void)setApps:(NSArray *)apps {
    for (UIView *view in self.stack.arrangedSubviews) {
        [self.stack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    for (LCOSAppModel *app in apps) {
        LCOSAppCardButton *card = [LCOSAppCardButton buttonWithType:UIButtonTypeCustom];
        card.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];
        card.layer.cornerRadius = 24;
        card.layer.cornerCurve = kCACornerCurveContinuous;
        card.clipsToBounds = YES;
        [card.widthAnchor constraintEqualToConstant:220].active = YES;
        UIImageView *image = [[UIImageView alloc] initWithImage:app.icon];
        image.contentMode = UIViewContentModeScaleAspectFit;
        image.layer.cornerRadius = 20;
        image.clipsToBounds = YES;
        image.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:image];
        UILabel *label = [[UILabel alloc] init];
        label.text = app.displayName;
        label.textColor = UIColor.whiteColor;
        label.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
        label.textAlignment = NSTextAlignmentCenter;
        label.lineBreakMode = NSLineBreakByTruncatingTail;
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:label];
        UILabel *placeholder = [[UILabel alloc] init];
        placeholder.text = @"应用入口";
        placeholder.font = [UIFont systemFontOfSize:12];
        placeholder.textColor = UIColor.tertiaryLabelColor;
        placeholder.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:placeholder];
        [NSLayoutConstraint activateConstraints:@[
            [image.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
            [image.topAnchor constraintEqualToAnchor:card.topAnchor constant:48],
            [image.widthAnchor constraintEqualToConstant:72],
            [image.heightAnchor constraintEqualToConstant:72],
            [label.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
            [label.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
            [label.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-42],
            [placeholder.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
            [placeholder.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:6]
        ]];
        [card addTarget:self action:@selector(launchApp:) forControlEvents:UIControlEventTouchUpInside];
        card.appModel = app;
        [self.stack addArrangedSubview:card];
    }
}
- (void)launchApp:(LCOSAppCardButton *)sender { [sender.appModel launch]; }
- (void)closeTapped { if (self.onClose) self.onClose(); }
@end

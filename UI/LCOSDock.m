//
//  LCOSDock.m
//  LCOS.dylib
//

#import "LCOSDock.h"

@implementation LCOSDock

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor systemGray6Color];
        self.layer.cornerRadius = 12;
        self.layer.masksToBounds = YES;
    }
    return self;
}

@end
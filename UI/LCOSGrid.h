#pragma once

#import <UIKit/UIKit.h>

@interface LCOSGrid : UIView

@property (nonatomic, strong) NSMutableArray *pages;
@property (nonatomic, strong) NSMutableArray *currentPageItems;

@end
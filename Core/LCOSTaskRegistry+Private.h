#pragma once

#import "LCOSTaskRegistry.h"
#import "LCOSTaskRecord.h"

@interface LCOSTaskRegistry ()
@property (nonatomic, strong) NSMutableArray<LCOSTaskRecord *> *records;
@property (nonatomic, weak) UIView *activeNativeTask;
@property (nonatomic, weak) UIView *activeLCOSTask;
@property (nonatomic, assign) BOOL hooksInstalled;
@property (nonatomic, strong) NSMutableDictionary<NSValue *, NSNumber *> *pendingPresentations;
- (LCOSTaskRecord *)recordForTask:(UIView *)view;
- (BOOL)isRunning:(UIView *)view;
- (void)presentTaskWhenReady:(UIView *)view fromLCOS:(BOOL)fromLCOS attempt:(NSUInteger)attempt;
- (NSValue *)pendingKeyForTask:(UIView *)view;
@end

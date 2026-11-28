#pragma once

#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString *const LCOSNativeInteractionPreferenceKey;
FOUNDATION_EXPORT BOOL LCOSNativeInteractionEnabled(void);
FOUNDATION_EXPORT void LCOSSetNativeInteractionEnabled(BOOL enabled);
FOUNDATION_EXPORT void LCOSRecordLaunchSource(NSString *uuid, BOOL fromLCOS);
FOUNDATION_EXPORT NSNumber *LCOSConsumeLaunchSource(NSString *uuid);

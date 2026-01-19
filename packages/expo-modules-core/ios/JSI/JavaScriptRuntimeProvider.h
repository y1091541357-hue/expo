#pragma once

#ifdef __cplusplus
#import "jsi.h"
#endif

@protocol JavaScriptRuntimeProvider

#ifdef __cplusplus
- (nonnull facebook::jsi::Runtime *)consume;
#endif

@end

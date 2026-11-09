//
//  OpenSwiftUIUIKitSubviews.m
//  OpenSwiftUI_SPI
//
//  Status: Complete
//  Audited for 6.5.4

#include "OpenSwiftUIUIKitSubviews.h"

#if OPENSWIFTUI_TARGET_OS_DARWIN

#include "OpenSwiftUICoreViewFunctions.h"
#include <QuartzCore/QuartzCore.h>
#if OPENSWIFTUI_TARGET_OS_IOS || OPENSWIFTUI_TARGET_OS_VISION
#include <UIKit/UIKit.h>
#else
#include <AppKit/AppKit.h>
#endif

// MARK: - UIKit Private API

OPENSWIFTUI_EXPORT CALayer * _Nullable CALayerGetSuperlayer(CALayer *layer);

@interface NSObject ()
- (void)_invalidateSubviewCache;
- (NSInteger)_perrySublayerCount;
- (CALayer *)_perrySublayerAtIndex:(NSInteger)index;
@end

// MARK: - UIKit Add Subview

void _OpenSwiftUIUIKitAddSubview(id child, id parent, NSInteger index) {
    CALayer *parentLayer = [parent layer];
    // Perry's layers answer for a sublayer without making the whole array,
    // which would be made again after each move.
    BOOL direct = [parentLayer respondsToSelector:@selector(_perrySublayerAtIndex:)];
    NSArray<CALayer *> *sublayers = direct ? nil : [parentLayer sublayers];
    NSUInteger count = direct ? (NSUInteger)[(id)parentLayer _perrySublayerCount] : (sublayers ? [sublayers count] : 0);
    #define SUBLAYER(i) (direct ? [(id)parentLayer _perrySublayerAtIndex:(NSInteger)(i)] : sublayers[(i)])
    CALayer *childLayer = [child layer];
    if (count > index && SUBLAYER(index) == childLayer) {
        return;
    }
    if (CALayerGetSuperlayer(childLayer) != parentLayer) {
        [parent openswiftui_insertRenderedSubview:child atIndex:(NSInteger)index];
    } else {
        NSUInteger nextIndex = index + 1;
        if (nextIndex < count && SUBLAYER(nextIndex) == childLayer) {
            childLayer = SUBLAYER(index);
            assert(childLayer);
            index = count;
        }
        [parentLayer insertSublayer:childLayer atIndex:(unsigned)index];
        [parent _invalidateSubviewCache];
    }
    #undef SUBLAYER
}

#endif /* OPENSWIFTUI_TARGET_OS_DARWIN */

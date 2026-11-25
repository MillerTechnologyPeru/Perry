//
//  _NSConstraintBasedLayoutHostingView.h
//  OpenSwiftUI_SPI

#ifndef _NSConstraintBasedLayoutHostingView_h
#define _NSConstraintBasedLayoutHostingView_h

#include "OpenSwiftUIBase.h"

#if TARGET_OS_OSX && __has_include(<AppKit/AppKit.h>)

#include <AppKit/AppKit.h>

typedef struct BaselineOffset {
    CGFloat firstTextBaseline;
    CGFloat lastTextBaseline;
} BaselineOffset;

@interface _NSConstraintBasedLayoutHostingView : NSView {
    BOOL _hasAddedConstraints;
}

@property (retain, nullable) NSView *hostedView;

+ (BOOL)requiresConstraintBasedLayout;

- (void)dealloc;
- (BaselineOffset)_baselineOffsetsAtSize:(CGSize)size;
- (void)_informContainerThatSubviewsNeedUpdateConstraints;
- (void)_intrinsicContentSizeInvalidatedForChildView:(id)view;
- (BOOL)_layoutHeightDependsOnWidth;
- (void)_layoutMetricsInvalidatedForHostedView;
- (CGSize)_layoutSizeThatFits:(CGSize)fits fixedAxes:(unsigned long long)axes;
- (void)_setFrameWithAlignmentRect:(CGRect)rect;
- (NSEdgeInsets)alignmentRectInsets;
- (void)constraintsDidChangeInEngine:(id)engine;
- (id)initWithHostedView:(id)view;
- (CGSize)sizeThatFits:(CGSize)fits;
- (void)sizeToFit;
- (void)updateConstraints;
- (void)willRemoveSubview:(id)subview;

@end

#endif /* __has_include(<AppKit/AppKit.h>) */

#endif /* _NSConstraintBasedLayoutHostingView_h */

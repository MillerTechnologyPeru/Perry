//
//  _UIConstraintBasedLayoutHostingView.h
//  OpenSwiftUI_SPI

#ifndef _UIConstraintBasedLayoutHostingView_h
#define _UIConstraintBasedLayoutHostingView_h

#include "OpenSwiftUIBase.h"

#if __has_include(<UIKit/UIKit.h>)

#include <UIKit/UIKit.h>

typedef struct BaselineOffset {
    CGFloat firstTextBaseline;
    CGFloat lastTextBaseline;
} BaselineOffset;

@interface _UIConstraintBasedLayoutHostingView : UIView {
    BOOL _hasAddedConstraints;
}

@property (retain, nonatomic, nullable) UIView *hostedView;

+ (BOOL)requiresConstraintBasedLayout;

- (id)initWithHostedView:(id)view;
- (void)willRemoveSubview:(id)subview;
- (void)_setFrameWithAlignmentRect:(CGRect)rect;
- (void)_intrinsicContentSizeInvalidatedForChildView:(id)view;
- (void)constraintsDidChangeInEngine:(id)engine;
- (void)_scheduleUpdateConstraintsPassAsEngineHostNeedingLayout:(BOOL)layout;
- (void)_layoutMetricsInvalidatedForHostedView;
- (void)updateConstraints;
- (UIEdgeInsets)alignmentRectInsets;
- (BOOL)_layoutHeightDependsOnWidth;
- (BaselineOffset)_baselineOffsetsAtSize:(CGSize)size;
- (CGSize)sizeThatFits:(CGSize)fits;
- (CGSize)_layoutSizeThatFits:(CGSize)fits fixedAxes:(unsigned long long)axes;

@end

#endif /* __has_include(<UIKit/UIKit.h>) */

#endif /* _UIConstraintBasedLayoutHostingView_h */

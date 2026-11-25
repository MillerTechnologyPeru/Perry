//
//  NSStringDrawing.h
//  OpenSwiftUI_SPI

#pragma once

#import "OpenSwiftUIBase.h"

#if OPENSWIFTUI_TARGET_OS_DARWIN

#import <Foundation/Foundation.h>

@class NSAttributedString;
@class NSString;
@class NSStringDrawingContext;

NS_HEADER_AUDIT_BEGIN(nullability, sendability)

OPENSWIFTUI_EXPORT API_AVAILABLE(macos(10.11), ios(6.0), tvos(9.0), watchos(2.0), visionos(1.0))
@interface NSStringDrawingContext : NSObject
@property (NS_NONATOMIC_IOSONLY) CGFloat minimumScaleFactor;
@property (readonly, NS_NONATOMIC_IOSONLY) CGFloat actualScaleFactor;
@property (readonly, NS_NONATOMIC_IOSONLY) CGRect totalBounds;
@end

@interface NSString (NSStringDrawing)
- (CGSize)sizeWithAttributes:(nullable NSDictionary<NSAttributedStringKey, id> *)attrs API_AVAILABLE(macos(10.0), ios(7.0), tvos(9.0), watchos(2.0), visionos(1.0));
- (void)drawAtPoint:(CGPoint)point withAttributes:(nullable NSDictionary<NSAttributedStringKey, id> *)attrs API_AVAILABLE(macos(10.0), ios(7.0), tvos(9.0), watchos(2.0), visionos(1.0));
- (void)drawInRect:(CGRect)rect withAttributes:(nullable NSDictionary<NSAttributedStringKey, id> *)attrs API_AVAILABLE(macos(10.0), ios(7.0), tvos(9.0), watchos(2.0), visionos(1.0));
@end

@interface NSAttributedString (NSStringDrawing)
- (CGSize)size API_AVAILABLE(macos(10.0), ios(6.0), tvos(9.0), watchos(2.0), visionos(1.0));
- (void)drawAtPoint:(CGPoint)point API_AVAILABLE(macos(10.0), ios(6.0), tvos(9.0), watchos(2.0), visionos(1.0));
- (void)drawInRect:(CGRect)rect API_AVAILABLE(macos(10.0), ios(6.0), tvos(9.0), watchos(2.0), visionos(1.0));
@end

typedef NS_OPTIONS(NSInteger, NSStringDrawingOptions) {
    NSStringDrawingUsesLineFragmentOrigin = 1 << 0,
    NSStringDrawingUsesFontLeading = 1 << 1,
    NSStringDrawingUsesDeviceMetrics = 1 << 3,
    NSStringDrawingTruncatesLastVisibleLine API_AVAILABLE(macos(10.5), ios(6.0), tvos(9.0), watchos(2.0), visionos(1.0)) = 1 << 5,
#if OPENSWIFTUI_HAS_SDK_26_ADDITIONS
    NSStringDrawingOptionsResolvesNaturalAlignmentWithBaseWritingDirection API_AVAILABLE(macos(26.0), ios(26.0), tvos(26.0), visionos(26.0), watchos(26.0)) = (1 << 9),
#endif
#if OPENSWIFTUI_TARGET_OS_OSX
    NSStringDrawingDisableScreenFontSubstitution API_DEPRECATED("", macos(10.0, 10.11)) = (1 << 2),
    NSStringDrawingOneShot API_DEPRECATED("", macos(10.0, 10.11)) = (1 << 4),
#endif
}
NS_SWIFT_NAME(NSString.DrawingOptions)
API_AVAILABLE(macos(10.0), ios(6.0), tvos(9.0), watchos(2.0), visionos(1.0));

@interface NSString (NSExtendedStringDrawing)
- (void)drawWithRect:(CGRect)rect options:(NSStringDrawingOptions)options attributes:(nullable NSDictionary<NSAttributedStringKey, id> *)attributes context:(nullable NSStringDrawingContext *)context API_AVAILABLE(macos(10.11), ios(7.0), tvos(9.0), watchos(2.0), visionos(1.0));
- (CGRect)boundingRectWithSize:(CGSize)size options:(NSStringDrawingOptions)options attributes:(nullable NSDictionary<NSAttributedStringKey, id> *)attributes context:(nullable NSStringDrawingContext *)context API_AVAILABLE(macos(10.11), ios(7.0), tvos(9.0), watchos(2.0), visionos(1.0));
@end

@interface NSAttributedString (NSExtendedStringDrawing)
- (void)drawWithRect:(CGRect)rect options:(NSStringDrawingOptions)options context:(nullable NSStringDrawingContext *)context API_AVAILABLE(macos(10.11), ios(6.0), tvos(9.0), watchos(2.0), visionos(1.0));
- (CGRect)boundingRectWithSize:(CGSize)size options:(NSStringDrawingOptions)options context:(nullable NSStringDrawingContext *)context API_AVAILABLE(macos(10.11), ios(6.0), tvos(9.0), watchos(2.0), visionos(1.0));
@end

NS_HEADER_AUDIT_END(nullability, sendability)

#endif

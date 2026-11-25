//
//  NSTextLineFragment.h
//  OpenSwiftUI_SPI

#pragma once

#import "OpenSwiftUIBase.h"

#if OPENSWIFTUI_TARGET_OS_DARWIN

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_HEADER_AUDIT_BEGIN(nullability, sendability)

API_AVAILABLE(macos(12.0), ios(15.0), tvos(15.0), visionos(1.0)) API_UNAVAILABLE(watchos)
@interface NSTextLineFragment : NSObject <NSSecureCoding>

- (instancetype)initWithAttributedString:(NSAttributedString *)attributedString range:(NSRange)range NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithString:(NSString *)string attributes:(NSDictionary<NSAttributedStringKey, id> *)attributes range:(NSRange)range;
- (instancetype)init NS_UNAVAILABLE;

@property (strong, readonly) NSAttributedString *attributedString;
@property (readonly) NSRange characterRange;
@property (readonly) CGRect typographicBounds;
@property (readonly) CGPoint glyphOrigin;

- (void)drawAtPoint:(CGPoint)point inContext:(CGContextRef)context;
- (CGPoint)locationForCharacterAtIndex:(NSInteger)index;
- (NSInteger)characterIndexForPoint:(CGPoint)point;
- (CGFloat)fractionOfDistanceThroughGlyphForPoint:(CGPoint)point;

@end

NS_HEADER_AUDIT_END(nullability, sendability)

#endif

//
//  NSParagraphStyle.h
//  OpenSwiftUI_SPI

#pragma once

#import "OpenSwiftUIBase.h"

#if OPENSWIFTUI_TARGET_OS_DARWIN

#import <Foundation/Foundation.h>
#import "NSText.h"
#import "NSCompositionLanguage.h"

@class NSTextList;
@class NSTextBlock;

NS_HEADER_AUDIT_BEGIN(nullability, sendability)

#if !__NSPARAGRAPH_STYLE_SHARED_SECTION__
#define __NSPARAGRAPH_STYLE_SHARED_SECTION__ 1

#if OPENSWIFTUI_TARGET_OS_OSX
typedef NS_ENUM(NSUInteger, NSLineBreakMode) {
    NSLineBreakByWordWrapping = 0,
    NSLineBreakByCharWrapping,
    NSLineBreakByClipping,
    NSLineBreakByTruncatingHead,
    NSLineBreakByTruncatingTail,
    NSLineBreakByTruncatingMiddle,
} API_AVAILABLE(macos(10.0), ios(6.0), watchos(2.0), tvos(9.0), visionos(1.0));
#else
typedef NS_ENUM(NSInteger, NSLineBreakMode) {
    NSLineBreakByWordWrapping = 0,
    NSLineBreakByCharWrapping,
    NSLineBreakByClipping,
    NSLineBreakByTruncatingHead,
    NSLineBreakByTruncatingTail,
    NSLineBreakByTruncatingMiddle,
} API_AVAILABLE(macos(10.0), ios(6.0), watchos(2.0), tvos(9.0), visionos(1.0));
#endif

typedef NS_OPTIONS(NSUInteger, NSLineBreakStrategy) {
    NSLineBreakStrategyNone = 0,
    NSLineBreakStrategyPushOut API_AVAILABLE(macos(10.11), ios(9.0), tvos(9.0), watchos(2.0), visionos(1.0)) = 1 << 0,
    NSLineBreakStrategyHangulWordPriority API_AVAILABLE(macos(11.0), ios(14.0), watchos(7.0), tvos(14.0), visionos(1.0)) = 1 << 1,
    NSLineBreakStrategyStandard API_AVAILABLE(macos(11.0), ios(14.0), watchos(7.0), tvos(14.0), visionos(1.0)) = 0xFFFF,
} API_AVAILABLE(macos(10.11), ios(9.0), tvos(9.0), watchos(2.0), visionos(1.0));

#endif // !__NSPARAGRAPH_STYLE_SHARED_SECTION__

typedef NS_ENUM(NSInteger, NSTextHorizontalAlignment) {
    NSTextHorizontalAlignmentNatural = 0,
    NSTextHorizontalAlignmentLeft = 2,
    NSTextHorizontalAlignmentRight = 3,
    NSTextHorizontalAlignmentCenter = 4,
};

typedef NSString * NSTextTabOptionKey NS_TYPED_ENUM API_AVAILABLE(macos(10.0), ios(7.0), tvos(9.0), watchos(2.0), visionos(1.0));
OPENSWIFTUI_EXPORT NSTextTabOptionKey NSTabColumnTerminatorsAttributeName API_AVAILABLE(macos(10.0), ios(7.0), tvos(9.0), watchos(2.0), visionos(1.0));

OPENSWIFTUI_EXPORT API_AVAILABLE(macos(10.0), ios(7.0), tvos(9.0), watchos(2.0), visionos(1.0))
@interface NSTextTab : NSObject <NSCopying, NSCoding, NSSecureCoding>

+ (NSCharacterSet *)columnTerminatorsForLocale:(nullable NSLocale *)aLocale API_AVAILABLE(macos(10.11), ios(7.0), tvos(9.0), watchos(2.0), visionos(1.0));

#if OPENSWIFTUI_HAS_SDK_27_ADDITIONS
- (instancetype)initWithTextAlignment:(NSTextAlignment)alignment location:(CGFloat)loc options:(NSDictionary<NSTextTabOptionKey, id> *)options NS_DESIGNATED_INITIALIZER;
@property (readonly, NS_NONATOMIC_IOSONLY) NSTextAlignment alignment;
#endif
@property (readonly, NS_NONATOMIC_IOSONLY) CGFloat location;
@property (readonly, NS_NONATOMIC_IOSONLY) NSDictionary<NSTextTabOptionKey, id> *options;

@end

OPENSWIFTUI_EXPORT API_AVAILABLE(macos(10.0), ios(6.0), tvos(9.0), watchos(2.0), visionos(1.0))
@interface NSParagraphStyle : NSObject <NSCopying, NSMutableCopying, NSSecureCoding>

#if OPENSWIFTUI_HAS_SDK_27_ADDITIONS
@property (readonly, NS_NONATOMIC_IOSONLY) NSTextAlignment alignment;
#endif
@property (class, readonly, copy, NS_NONATOMIC_IOSONLY) NSParagraphStyle *defaultParagraphStyle;

+ (NSWritingDirection)defaultWritingDirectionForLanguage:(nullable NSString *)languageName;

@property (readonly, NS_NONATOMIC_IOSONLY) CGFloat lineSpacing;
@property (readonly, NS_NONATOMIC_IOSONLY) CGFloat paragraphSpacing;
@property (readonly, NS_NONATOMIC_IOSONLY) CGFloat headIndent;
@property (readonly, NS_NONATOMIC_IOSONLY) CGFloat tailIndent;
@property (readonly, NS_NONATOMIC_IOSONLY) CGFloat firstLineHeadIndent;
@property (readonly, NS_NONATOMIC_IOSONLY) CGFloat minimumLineHeight;
@property (readonly, NS_NONATOMIC_IOSONLY) CGFloat maximumLineHeight;
@property (readonly, NS_NONATOMIC_IOSONLY) NSLineBreakMode lineBreakMode;
@property (readonly, NS_NONATOMIC_IOSONLY) NSWritingDirection baseWritingDirection;
@property (readonly, NS_NONATOMIC_IOSONLY) CGFloat lineHeightMultiple;
@property (readonly, NS_NONATOMIC_IOSONLY) CGFloat paragraphSpacingBefore;
@property (readonly, NS_NONATOMIC_IOSONLY) float hyphenationFactor;
@property (readonly, NS_NONATOMIC_IOSONLY) BOOL usesDefaultHyphenation API_AVAILABLE(macos(12.0), ios(15.0), tvos(15.0), watchos(8.0), visionos(1.0));
@property (readonly, copy, NS_NONATOMIC_IOSONLY) NSArray<NSTextTab *> *tabStops API_AVAILABLE(macos(10.0), ios(7.0), tvos(9.0), watchos(2.0), visionos(1.0));
@property (readonly, NS_NONATOMIC_IOSONLY) CGFloat defaultTabInterval API_AVAILABLE(macos(10.0), ios(7.0), tvos(9.0), watchos(2.0), visionos(1.0));
@property (readonly, copy, NS_NONATOMIC_IOSONLY) NSArray<NSTextList *> *textLists API_AVAILABLE(macos(10.0), ios(7.0), tvos(9.0), watchos(2.0), visionos(1.0));
#if OPENSWIFTUI_HAS_SDK_27_ADDITIONS
@property (readonly, copy, NS_NONATOMIC_IOSONLY) NSArray<__kindof NSTextBlock *> *textBlocks API_AVAILABLE(macos(10.0), ios(6.0), tvos(9.0), visionos(1.0), watchos(2.0));
#endif
@property (readonly, NS_NONATOMIC_IOSONLY) BOOL allowsDefaultTighteningForTruncation API_AVAILABLE(macos(10.11), ios(9.0), tvos(9.0), watchos(2.0), visionos(1.0));
@property (readonly, NS_NONATOMIC_IOSONLY) NSLineBreakStrategy lineBreakStrategy API_AVAILABLE(macos(10.11), ios(9.0), tvos(9.0), watchos(2.0), visionos(1.0));
#if OPENSWIFTUI_HAS_SDK_27_ADDITIONS && OPENSWIFTUI_TARGET_OS_OSX
@property (readonly) float tighteningFactorForTruncation;
@property (readonly) NSInteger headerLevel;
#endif

@end

OPENSWIFTUI_EXPORT API_AVAILABLE(macos(10.0), ios(6.0), tvos(9.0), watchos(2.0), visionos(1.0))
@interface NSMutableParagraphStyle : NSParagraphStyle

#if OPENSWIFTUI_HAS_SDK_27_ADDITIONS
@property (NS_NONATOMIC_IOSONLY) NSTextAlignment alignment;
#endif
@property (NS_NONATOMIC_IOSONLY) CGFloat lineSpacing;
@property (NS_NONATOMIC_IOSONLY) CGFloat paragraphSpacing;
@property (NS_NONATOMIC_IOSONLY) CGFloat firstLineHeadIndent;
@property (NS_NONATOMIC_IOSONLY) CGFloat headIndent;
@property (NS_NONATOMIC_IOSONLY) CGFloat tailIndent;
@property (NS_NONATOMIC_IOSONLY) NSLineBreakMode lineBreakMode;
@property (NS_NONATOMIC_IOSONLY) CGFloat minimumLineHeight;
@property (NS_NONATOMIC_IOSONLY) CGFloat maximumLineHeight;
@property (NS_NONATOMIC_IOSONLY) NSWritingDirection baseWritingDirection;
@property (NS_NONATOMIC_IOSONLY) CGFloat lineHeightMultiple;
@property (NS_NONATOMIC_IOSONLY) CGFloat paragraphSpacingBefore;
@property (NS_NONATOMIC_IOSONLY) float hyphenationFactor;
@property (readwrite, NS_NONATOMIC_IOSONLY) BOOL usesDefaultHyphenation API_AVAILABLE(macos(12.0), ios(15.0), tvos(15.0), watchos(8.0), visionos(1.0));
@property (null_resettable, copy, NS_NONATOMIC_IOSONLY) NSArray<NSTextTab *> *tabStops API_AVAILABLE(macos(10.0), ios(7.0), tvos(9.0), watchos(2.0), visionos(1.0));
@property (NS_NONATOMIC_IOSONLY) CGFloat defaultTabInterval API_AVAILABLE(macos(10.0), ios(7.0), tvos(9.0), watchos(2.0), visionos(1.0));
@property (NS_NONATOMIC_IOSONLY) BOOL allowsDefaultTighteningForTruncation API_AVAILABLE(macos(10.11), ios(9.0), tvos(9.0), watchos(2.0), visionos(1.0));
@property (NS_NONATOMIC_IOSONLY) NSLineBreakStrategy lineBreakStrategy API_AVAILABLE(macos(10.11), ios(9.0), tvos(9.0), watchos(2.0), visionos(1.0));
@property (NS_NONATOMIC_IOSONLY, copy) NSArray<NSTextList *> *textLists API_AVAILABLE(macos(10.0), ios(7.0), tvos(9.0), watchos(2.0), visionos(1.0));
#if OPENSWIFTUI_HAS_SDK_27_ADDITIONS
@property (copy, NS_NONATOMIC_IOSONLY) NSArray<__kindof NSTextBlock *> *textBlocks API_AVAILABLE(macos(10.0), ios(6.0), tvos(9.0), visionos(1.0), watchos(2.0));
#endif

- (void)addTabStop:(NSTextTab *)anObject API_AVAILABLE(macos(10.0), ios(9.0), tvos(9.0), watchos(2.0), visionos(1.0));
- (void)removeTabStop:(NSTextTab *)anObject API_AVAILABLE(macos(10.0), ios(9.0), tvos(9.0), watchos(2.0), visionos(1.0));
- (void)setParagraphStyle:(NSParagraphStyle *)obj API_AVAILABLE(macos(10.0), ios(9.0), tvos(9.0), watchos(2.0), visionos(1.0));

#if OPENSWIFTUI_HAS_SDK_27_ADDITIONS && OPENSWIFTUI_TARGET_OS_OSX
@property float tighteningFactorForTruncation;
@property NSInteger headerLevel;
#endif

@end

@interface NSMutableParagraphStyle (OpenSwiftUI_SPI)

@property (nonatomic) NSCompositionLanguage compositionLanguage_openswiftui_safe_wrapper
    OPENSWIFTUI_SWIFT_NAME(compositionLanguage);

@property (nonatomic) BOOL fullyJustified_openswiftui_safe_wrapper
    OPENSWIFTUI_SWIFT_NAME(fullyJustified);

@property (nonatomic) NSTextHorizontalAlignment horizontalAlignment_openswiftui_safe_wrapper
    OPENSWIFTUI_SWIFT_NAME(horizontalAlignment);

@property (nonatomic) BOOL spansAllLines_openswiftui_safe_wrapper
    OPENSWIFTUI_SWIFT_NAME(spansAllLines);

@property (nonatomic) NSLineBreakMode secondaryLineBreakMode_openswiftui_safe_wrapper
    OPENSWIFTUI_SWIFT_NAME(secondaryLineBreakMode);

@end

NS_HEADER_AUDIT_END(nullability, sendability)

#endif

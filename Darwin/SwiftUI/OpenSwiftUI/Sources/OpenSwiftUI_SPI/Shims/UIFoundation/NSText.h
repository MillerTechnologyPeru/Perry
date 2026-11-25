//
//  NSText.h
//  OpenSwiftUI_SPI

#pragma once

#import "OpenSwiftUIBase.h"

#if OPENSWIFTUI_TARGET_OS_DARWIN

#import <Foundation/Foundation.h>

NS_HEADER_AUDIT_BEGIN(nullability, sendability)

#if !__NSWRITING_DIRECTION_SHARED_SECTION__
#define __NSWRITING_DIRECTION_SHARED_SECTION__ 1
typedef NS_ENUM(NSInteger, NSWritingDirection) {
    NSWritingDirectionNatural = -1,
    NSWritingDirectionLeftToRight = 0,
    NSWritingDirectionRightToLeft = 1,
} API_AVAILABLE(macos(10.0), ios(6.0), watchos(2.0), tvos(9.0), visionos(1.0));
#endif // !__NSWRITING_DIRECTION_SHARED_SECTION__

#if !__NSTEXT_ALIGNMENT_SHARED_SECTION__
#define __NSTEXT_ALIGNMENT_SHARED_SECTION__ 1
typedef NS_ENUM(NSInteger, NSTextAlignment) {
    NSTextAlignmentLeft = 0,
#if TARGET_ABI_USES_IOS_VALUES
    NSTextAlignmentCenter = 1,
    NSTextAlignmentRight = 2,
#else
    NSTextAlignmentRight = 1,
    NSTextAlignmentCenter = 2,
#endif
    NSTextAlignmentJustified = 3,
    NSTextAlignmentNatural = 4,
} API_AVAILABLE(macos(10.0), ios(6.0), watchos(2.0), tvos(9.0), visionos(1.0));
#endif // !__NSTEXT_ALIGNMENT_SHARED_SECTION__

NS_HEADER_AUDIT_END(nullability, sendability)

#endif

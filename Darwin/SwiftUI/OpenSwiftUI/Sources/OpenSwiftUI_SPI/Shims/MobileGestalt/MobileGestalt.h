//
//  MobileGestalt.h
//  OpenSwiftUI_SPI

#ifndef LIBMOBILEGESTALT_H_
#define LIBMOBILEGESTALT_H_

#include "OpenSwiftUIBase.h"

#if OPENSWIFTUI_TARGET_OS_DARWIN

#include <CoreFoundation/CoreFoundation.h>

CF_EXTERN_C_BEGIN

CFTypeRef _Nullable MGCopyAnswer(CFStringRef _Nonnull question, CFDictionaryRef _Nullable options);

CF_EXTERN_C_END

#endif /* OPENSWIFTUI_TARGET_OS_DARWIN */

#endif /* LIBMOBILEGESTALT_H_ */

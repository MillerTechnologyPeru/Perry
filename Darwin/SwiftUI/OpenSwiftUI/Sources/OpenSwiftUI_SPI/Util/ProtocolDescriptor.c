//
//  ProtocolDescriptor.c
//  OpenSwiftUI_SPI
//
//  Audit for 6.5.4
//  Status: Complete

#include "ProtocolDescriptor.h"

// Swift symbols of the module's ABI name: SwiftUI when built to stand in for it.
#ifdef OPENSWIFTUI_AS_SWIFTUI
#define OPENSWIFTUI_MANGLED(name) $s7SwiftUI##name
#else
#define OPENSWIFTUI_MANGLED(name) $s11OpenSwiftUI##name
#endif

void _OpenSwiftUI_callVisitViewType(void *visitor_value,
                                    const void *view_type,
                                    const void *view_type2,
                                    const void *view_pwt);

OPENSWIFTUI_EXPORT
const void *OPENSWIFTUI_MANGLED(4ViewMp);

const void *_OpenSwiftUI_viewProtocolDescriptor(void) {
    return &OPENSWIFTUI_MANGLED(4ViewMp);
}

OPENSWIFTUI_EXPORT
const void *OPENSWIFTUI_MANGLED(12ViewModifierMp);

const void *_OpenSwiftUI_viewModifierProtocolDescriptor(void) {
    return &OPENSWIFTUI_MANGLED(12ViewModifierMp);
}

OPENSWIFTUI_EXPORT
const void *OPENSWIFTUI_MANGLED(7GestureMp);

const void *_OpenSwiftUI_gestureProtocolDescriptor(void) {
    return &OPENSWIFTUI_MANGLED(7GestureMp);
}

OPENSWIFTUI_EXPORT
const void *OPENSWIFTUI_MANGLED(15GestureModifierMp);

const void *_OpenSwiftUI_gestureModifierProtocolDescriptor(void) {
    return &OPENSWIFTUI_MANGLED(15GestureModifierMp);
}

OPENSWIFTUI_EXPORT
const void *OPENSWIFTUI_MANGLED(20DefaultStyleModifierMp);

const void *_OpenSwiftUI_defaultStyleModifierProtocolDescriptor(void) {
    return &OPENSWIFTUI_MANGLED(20DefaultStyleModifierMp);
}

OPENSWIFTUI_EXPORT
const void *OPENSWIFTUI_MANGLED(21StyleOverrideModifierMp);

const void *_OpenSwiftUI_styleOverrideModifierProtocolDescriptor(void) {
    return &OPENSWIFTUI_MANGLED(21StyleOverrideModifierMp);
}

OPENSWIFTUI_EXPORT
const void *OPENSWIFTUI_MANGLED(27StyleWriterOverrideModifierMp);

const void *_OpenSwiftUI_styleWriterOverrideModifierProtocolDescriptor(void) {
    return &OPENSWIFTUI_MANGLED(27StyleWriterOverrideModifierMp);
}

OPENSWIFTUI_EXPORT
const void *OPENSWIFTUI_MANGLED(12StyleContextMp);

const void *_OpenSwiftUI_styleContextProtocolDescriptor(void) {
    return &OPENSWIFTUI_MANGLED(12StyleContextMp);
}

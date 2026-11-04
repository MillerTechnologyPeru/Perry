//
//  ProtocolDescriptor.c
//  COpenSwiftUI
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

OPENSWIFTUI_EXPORT
const void *OPENSWIFTUI_MANGLED(5SceneMp);

OPENSWIFTUI_EXPORT
const void *OPENSWIFTUI_MANGLED(8CommandsMp);

OPENSWIFTUI_EXPORT
const void *OPENSWIFTUI_MANGLED(15PreviewProviderMp);

const void *_sceneProtocolDescriptor(void) {
    return &OPENSWIFTUI_MANGLED(5SceneMp);
}

const void *_commandsProtocolDescriptor(void) {
    return &OPENSWIFTUI_MANGLED(8CommandsMp);
}

const void *_previewProviderProtocolDescriptor(void) {
    return &OPENSWIFTUI_MANGLED(15PreviewProviderMp);
}

#if OPENSWIFTUI_OPENCOMBINE
OPENSWIFTUI_EXPORT
const void *$s11OpenCombine16ObservableObjectMp;

const void *_observableObjectProtocolDescriptor(void) {
    return &$s11OpenCombine16ObservableObjectMp;
}

#else
OPENSWIFTUI_EXPORT
const void *$s7Combine16ObservableObjectMp;

const void *_observableObjectProtocolDescriptor(void) {
    return &$s7Combine16ObservableObjectMp;
}
#endif

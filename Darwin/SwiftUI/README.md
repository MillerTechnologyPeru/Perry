# SwiftUI

Perry's SwiftUI.framework: OpenSwiftUI and the packages it builds on, built
for iOS arm64 with library evolution under SwiftUI's ABI names, so apps built
against Apple's SwiftUI bind to it by the same Swift symbols.
`Scripts/build-swiftui.sh` builds it on a Mac into the Swift runtime directory
(`PERRY_SWIFT_RUNTIME`). The loader finds `SwiftUI.framework/SwiftUI` there
and loads it as a Mach-O image.

## Sources

Only MIT-licensed sources are kept here. Each directory is a Swift package,
with its manifest, sources, tests and license:

- `OpenSwiftUI`: https://github.com/OpenSwiftUIProject/OpenSwiftUI at e693ac1,
  with the `perry` branch of https://github.com/MillerTechnologyPeru/OpenSwiftUI
  (537003386f; see below).
- `OpenAttributeGraph`: https://github.com/OpenSwiftUIProject/OpenAttributeGraph at 46f2e1b.
- `Compute`: https://github.com/OpenSwiftUIProject/Compute at 41ecaef. This is the
  attribute graph the build uses.
- `OpenRenderBox`: https://github.com/OpenSwiftUIProject/OpenRenderBox at 0bb9980.
- `OpenCoreGraphics`: https://github.com/OpenSwiftUIProject/OpenCoreGraphics at 3440823.

The build script fetches what these packages use under other licenses from
the same commits, into paths `.gitignore` lists:

- The Swift corelibs headers (`SwiftCorelibs`), `TargetConditionals.h`,
  `CFRuntime.h`, `SwiftBridging.h` and `CFCGTypes.h` copies, Apache 2.0.
- Swift's runtime headers, which upstream keeps as git submodules.

Swift Numerics, Swift Syntax (for macros), SymbolLocator and
DarwinPrivateFrameworks remain package dependencies.

`Stubs/libswiftDemangle.tbd` lists the exports of Swift's
`libswiftDemangle.dylib` that Compute calls. The iOS SDK does not ship this
library, but the Swift runtime directory does.

## Changes for Apple's ABI

The `perry` branch adds `OPENSWIFTUI_AS_SWIFTUI`, which the build script sets:

- Protocol descriptors and interposed symbols take the module's ABI name,
  `SwiftUI`.
- Xcode Preview hooks, preview shims and `DeveloperToolsSupport` are left
  out, since the iOS SDK's are Apple's SwiftUI.
- `SceneBuilder` is a struct, as SwiftUI declares it.
- `WindowGroup` has `init(id:title:lazyContent:)`, which SwiftUI's inlinable
  initializers call.

The build also compiles against a copy of the SDK's UIKit interface without
`import SwiftUICore`, which would otherwise bring in Apple's SwiftUI types
next to these, and against Perry's DeveloperToolsSupport
(`Scripts/build-framework.sh DeveloperToolsSupport`, built first if
missing) in place of the SDK's, whose resources' names and bundles SwiftUI
reads through Perry's SPI; SwiftUI links that framework by path.
`_MapKit_SwiftUI` (`Scripts/build-mapkit-swiftui.sh`) compiles against this
build's modules, so it is rebuilt after SwiftUI.

Observation is Swift's own, not OpenObservation, so views track the
`@Observable` types of apps built against Apple's SDK. SwiftUI records and
installs tracking through Observation's SPI (`ObservationTracking._AccessList`,
`_installTracking`, `init(_:)`, `changed`), which `libswiftObservation`
exports but the SDK's interface leaves out; the build compiles against a copy
of that interface declaring it. The access list Observation records into is
the thread-specific value of Darwin's reserved key 106, which
`ObservationThreadLocal.swift` reads and writes.

Compare the exported Swift symbols with an app's imports to find what is
still missing:

```sh
dyld_info -imports App.app/App | grep -o '_$s7SwiftUI[^ ]*' | sort -u \
  | comm -23 - <(nm -gU SwiftUI.framework/SwiftUI | awk '{print $3}' | sort -u)
```

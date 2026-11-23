# ObjectiveC

Perry's Swift overlay of the Objective-C runtime: `ObjCBool`, `Selector`,
`NSZone`, `NSObject`'s equality, hashing and C variadic encoding,
autorelease pools and `objc_enumerateClasses`, written for Perry from the
API in the macOS SDK's `ObjectiveC.swiftinterface`. It replaces the Swift
5.0 overlay Xcode ships as a file, which a runtime directory made for an
x86_64 Mac app used to take.

It is compiled as the module `ObjectiveC` over the SDK's headers:

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh ObjectiveC <runtime directory>

`Scripts/check-overlay.sh` compares its symbols with the Swift 5.0 overlay
and the SDK's `libswiftObjectiveC.tbd`. What it still lacks:

- the accessors and property descriptor of `ObjCBool._value` as a `Bool`,
  which the `.tbd` lists for its arm64e slices: `BOOL` is a `bool` there
  and a `signed char` on Intel, where `_value` is an `Int8` (as this
  overlay lays it out, from the platform it is built for).

`objc_enumerateClasses` is made from the runtime's class list
(`objc_copyClassList`, `class_getImageName`, `class_conformsToProtocol`,
`class_getSuperclass`) rather than the C function of the same name, which
older runtimes and Perry's lack. A `.image` handle is matched by opening
each class's image again with `RTLD_NOLOAD`; a `.machHeader` by its path
from `dladdr`.

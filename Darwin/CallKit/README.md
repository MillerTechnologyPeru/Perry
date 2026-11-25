# CallKit

Perry's Swift overlay of CallKit, written for Perry from the API in the iOS
SDK's `CallKit.swiftinterface`: `CXProviderConfiguration.supportedHandleTypes`
as a set of `CXHandle.HandleType`, over the set of `NSNumber`s the header
gives (which the API notes keep from Swift as `__supportedHandleTypes`).
It replaces the iOS Simulator's `libswiftCallKit.dylib`.

    Scripts/build-overlay.sh CallKit <runtime directory>

`Scripts/check-overlay.sh` finds nothing missing against the simulator's
library. A number that names no handle type is left out of the set.

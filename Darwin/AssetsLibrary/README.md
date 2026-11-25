# AssetsLibrary

Perry's Swift overlay of AssetsLibrary, written for Perry from the API in
the iOS SDK's `AssetsLibrary.swiftinterface`:
`ALAssetsLibrary.enumerateGroupsWithTypes(_:usingBlock:failureBlock:)`,
which takes the group types as a `UInt32`, as Swift 1 programs passed them,
and calls `enumerateGroups(withTypes:using:failureBlock:)`. It replaces the
iOS Simulator's `libswiftAssetsLibrary.dylib`.

    Scripts/build-overlay.sh AssetsLibrary <runtime directory>

`Scripts/check-overlay.sh` finds nothing missing against the simulator's
library.

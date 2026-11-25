# CarPlay

Perry's Swift overlay of CarPlay, written for Perry from the API in the iOS
SDK's `CarPlay.swiftinterface`: `CPNavigationWaypoint.entryPoints` and
`CPRouteSegment.coordinates` as Swift arrays. Their getters are emitted
into the programs that call them (`@_alwaysEmitIntoClient`), so the library
holds only the properties' descriptors. The interface's convenience
initializers are emitted into programs the same way and need nothing here.
It replaces the iOS Simulator's `libswiftCarPlay.dylib`.

    Scripts/build-overlay.sh CarPlay <runtime directory>

`swiftc-flags` gives it the `_swift_FORCE_LOAD_$_swiftCarPlay` symbol
programs built against the overlay reference. `Scripts/check-overlay.sh`
finds nothing missing against the simulator's library.

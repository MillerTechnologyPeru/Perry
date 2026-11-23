# GameplayKit

Perry's Swift overlay of GameplayKit: paths and polygon obstacles from
arrays of points, and the generic component and state lookups of
`GKEntity` and `GKStateMachine`, written for Perry from the API in the
macOS SDK's `GameplayKit.swiftinterface`. It replaces the Swift 5.0
overlay Xcode ships as a file, which a runtime directory made for an x86_64
Mac app used to take.

It is compiled as the module `GameplayKit` over the SDK's Objective-C
headers, as Apple builds its overlays, so its symbols are the overlay's:

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh GameplayKit <runtime directory>

`-[GKStateMachine stateForClass:]`, which the header keeps out of Swift, is
sent through an Objective-C protocol of that one method.

`Scripts/check-overlay.sh` compares its symbols with the Swift 5.0 overlay
and the SDK's `libswiftGameplayKit.tbd`. What it still lacks:

- the initializing entry points (`fc`) of the convenience initializers
  `GKPath.init(points:radius:cyclical:)` (both) and
  `GKPolygonObstacle.init(points:)`, which Swift doesn't emit for
  convenience initializers and which the OS's own overlay doesn't export
  either (only a subclass's initializer would call them); the allocating
  ones programs call are there.

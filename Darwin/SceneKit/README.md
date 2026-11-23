# SceneKit

Perry's Swift overlay of SceneKit: `SCNFloat`, the conversions between
`SCNVector3`/`SCNVector4`/`SCNMatrix4`, simd's vectors and matrices and
`CATransform3D`, geometry sources and elements from Swift arrays, bounding
volumes as tuples, `SCNSceneSource.entryWithIdentifier(_:withClass:)` and
`SCNVector3`/`SCNVector4` (and, off macOS, `SCNMatrix4`) bridged to
`NSValue`, written for Perry from the API in the macOS SDK's
`SceneKit.swiftinterface`. It replaces the Swift 5.0 overlay Xcode ships as
a file, which a runtime directory made for an x86_64 Mac app used to take.

It is compiled as the module `SceneKit` over the SDK's Objective-C
headers, as Apple builds its overlays, so its symbols are the overlay's:

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh SceneKit <runtime directory>

`SCNGeometryElement(indices:primitiveType:)` counts its primitives from the
indices: three per triangle, one per point, two per line, count - 2 for a
strip, and for polygons the number n of leading vertex counts that add up
to the indices after them.

`Scripts/check-overlay.sh` compares its symbols with the Swift 5.0 overlay
and the SDK's `libswiftSceneKit.tbd`. What it still lacks:

- the initializing entry points (`fc`) of the convenience initializers of
  `SCNGeometrySource` (`vertices:`, `normals:`, `textureCoordinates:`) and
  `SCNGeometryElement` (`indices:primitiveType:`), which Swift doesn't emit
  for convenience initializers and the OS's own overlay doesn't export
  either; the allocating ones programs call are there.

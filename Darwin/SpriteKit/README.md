# SpriteKit

Perry's Swift overlay of SpriteKit: `SKColor`, warp geometry grids from
arrays of positions, and the (deprecated) playground quick looks of
`SKShapeNode`, `SKSpriteNode`, `SKTexture` and `SKTextureAtlas`, written
for Perry from the API in the macOS SDK's `SpriteKit.swiftinterface`. It
replaces the Swift 5.0 overlay Xcode ships as a file, which a runtime
directory made for an x86_64 Mac app used to take.

It is compiled as the module `SpriteKit` over the SDK's Objective-C
headers, as Apple builds its overlays, so its symbols are the overlay's:

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh SpriteKit <runtime directory>

The quick looks are Perry's own choice of content: a texture is its image,
a sprite its texture (or its color), a shape node itself as a sprite, an
atlas its first texture by name.

`Scripts/check-overlay.sh` compares its symbols with the Swift 5.0 overlay
and the SDK's `libswiftSpriteKit.tbd`. What it still lacks:

- the initializing entry point (`fc`) of the convenience initializer
  `SKWarpGeometryGrid.init(columns:rows:sourcePositions:destinationPositions:)`,
  which Swift doesn't emit for convenience initializers and the OS's own
  overlay doesn't export either; the allocating one programs call is there.

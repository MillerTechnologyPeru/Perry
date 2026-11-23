# CoreGraphics

Perry's Swift overlay of CoreGraphics: the Swift API of the CoreGraphics
framework (geometry initializers, constants, coding and reflection,
`CGPathFillRule` and the path, context, color, color space and image
members over the Swift-private C calls, the math functions over
`CGFloat`, tone mapping, adaptive bitmap contexts, rendering buffer
providers, tagged PDF structure elements) and the C forms Swift 4 and 5
programs still link, written for Perry from the API in the macOS SDK's
`CoreGraphics.framework/Modules/CoreGraphics.swiftmodule`. It replaces the
Swift 5.0 overlay Xcode ships, which a runtime directory made for an
x86_64 Mac app used to take.

It is compiled as the module `CoreGraphics` over the SDK's C headers, as
Apple builds its overlays, so its symbols are the overlay's:

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh CoreGraphics <runtime directory>

`swiftc-flags` makes it force-loadable (`-autolink-force-load`), as
Apple's is.

## What belongs here

Since macOS 13 the SDK has no Swift overlay library of CoreGraphics:
`usr/lib/swift/libswiftCoreGraphics.tbd` only re-exports the framework,
whose own binary holds the Swift API, and `CGFloat` moved to the
CoreFoundation overlay (still named `CoreGraphics.CGFloat`, by
`@_originallyDefinedIn`). Programs built against the Swift 5.0 SDK bind
all of it to `/usr/lib/swift/libswiftCoreGraphics.dylib`; programs built
since bind the framework's Swift symbols to `CoreGraphics.framework`,
which Perry's loader looks up in `libswiftCoreGraphics.dylib` of the
runtime directory (the framework's Swift overlay) when its provider lacks
them. So this library has both: the 5.0 overlay's API and the framework's
public Swift API.

`CGFloat` itself, its conformances and the conversions of the integer and
floating-point types from it are not here: they are the CoreFoundation
overlay's (`Darwin/CoreFoundation`), as in the SDK. The loader sends a
5.0 program's `CoreGraphics.CGFloat` references bound to this library to
`libswiftCoreFoundation.dylib` (and finds a Swift symbol in any image
when the one it is bound to lacks it), so a Mac runtime directory needs
Perry's CoreFoundation overlay beside this one; with Xcode's 5.0
CoreFoundation overlay `CGFloat` would be in neither.

The math functions over `CGFloat` (`sin`, `pow`, …), `CGFloat.min`/`max`,
`CGFLOAT_MIN`/`MAX` and `%` are the framework's, so they are here.

## Approximations

- `CGColor` and `CGColorSpace` coding (new in macOS 27) and
  `CGColorCreateWithPropertyList`/`CGColorCopyPropertyList` use a form of
  Perry's own: a color space as its name, or its ICC profile when it has
  none; a color as its color space and components. Apple's form isn't
  documented. `CGColorSpaceCreateWithPropertyList`/`CopyPropertyList`
  here are the Swift entry points only: their C symbols are the
  framework's, declared in its header, so they aren't exported again.
- The nearly-equal comparisons (`CGPointNearlyEqualToPoint` and the rest)
  use a relative tolerance of 16 units in the last place when none is
  given; Apple's default isn't published.
- The path operations return an empty path (stroking, the boolean
  operations) or the path itself (dashing, normalizing, flattening) when
  the C call gives none, where the interface promises a path.
- An adaptive context's `onAllocate` provider is passed to CoreGraphics
  retained.
- A PDF structure element's language is set from
  `Locale.Language.minimalIdentifier`.

## What check-overlay still reports

`Scripts/check-overlay.sh` against the Swift 5.0 overlay and the
framework's `CoreGraphics.tbd` (the SDK's `libswiftCoreGraphics.tbd` has
no symbols) reports 515 missing:

- 133 of `CGFloat` (type, metadata, conformances, `Double.init(_:)` and the
  other conversions): the CoreFoundation overlay's, above. Against the
  5.0 overlay alone these are all that is missing.
- 382 of the framework's SPI, which its tbd exports but no public
  interface declares: `Region` and its options, points and operations;
  the `PDFObjectType`/`PDFReferenceType` protocols and the Swift members of
  `CGPDFArray`, `CGPDFDictionary`, `CGPDFObject`, `CGPDFStream` and
  `CGPDFString`; `CastOverride`, `CodingOverride(s)` and the
  `OptionsTopLevelEncoder`/`Decoder`; `NearlyEquatable` with
  `isNearlyEqual(to:tolerance:)` and `Double`/`Float.defaultTolerance`;
  `FloatRangeExpression` and `bounded` on `CGFloat` ranges; the
  `CGColorSpace` constants (`sRGBSpace` and the rest); `CGPoint.Interpolator`;
  `CGRect.area`/`unit`, `CGSize`/`CGVector` `angle`/`length`/`lengthSquared`;
  the `constrainedHeadroom` case of `CGContentToneMappingInfo.DynamicRange`.

Members the interface emits into programs but the framework exports for
programs built against earlier SDKs (`CGRect.minX`, `CGBitmapInfo.alpha`,
the image-format descriptions, …) are inlinable here, which exports
their symbols as well.

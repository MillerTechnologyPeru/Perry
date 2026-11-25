# UIKit

Perry's Swift overlay of UIKit, written for Perry from the API in the iOS
SDK's `UIKit.swiftinterface`. It replaces the Swift 5.0 overlay Xcode ships
as a file, which a runtime directory for iOS apps used to take, and holds
the Swift API newer SDKs keep in the framework itself:

- what the 5.0 overlay had (`Geometry.swift`, `Legacy.swift`,
  `Values.swift`): `UIEdgeInsets`, `NSDirectionalEdgeInsets`, `UIOffset`
  and `UIFloatRange` as `Equatable` and `Codable` values, the first three
  bridged to `NSValue`; `IndexPath`'s rows, items and sections; content
  size categories in order; focus; font metrics by text style; color and
  image literals; drag, drop and paste by Swift types that bridge to item
  provider classes; and the Swift 4 forms programs built then still call
  (the orientation functions, the printing error codes,
  `UIApplicationMain` with Swift 4's argv, and the variadic initializers of
  `UIAlertView` and `UIActionSheet`, which Swift can't import);
- the newer API (the other sources, once `Darwin/UIKitAdditions`): trait
  changes and definitions, button, list, cell and content configurations,
  diffable data sources and snapshots, layout regions, view shapes,
  attribute scopes, menu elements and the numeric raw values' arithmetic.

It is compiled as the module `UIKit` over the SDK's Objective-C headers,
for iOS and for Mac Catalyst:

    Scripts/build-overlay.sh UIKit <runtime directory>
    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-ios18.0-macabi Scripts/build-overlay.sh UIKit <runtime directory>

`include/` declares the SPI the Swift API calls that UIKit's public headers
don't (`_UIKitPrivate`).

`Scripts/check-overlay.sh` finds nothing missing against the 5.0 overlay:

    PERRY_CHECK_ARCH=arm64 Scripts/check-overlay.sh <dylib> \
      "$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift-5.0/iphoneos/libswiftUIKit.dylib"

Where the behaviour is Perry's own rather than a thin wrapper:

- the alert view's and action sheet's variadic initializers add the
  buttons in the order the Objective-C initializers lay them out: an
  action sheet's destructive button first and cancel button last, an
  alert's cancel button first;
- an image literal naming no image stops the program, as the initializer
  can't fail;
- a view's playground quick look is the view itself.

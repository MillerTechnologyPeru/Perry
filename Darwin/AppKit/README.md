# AppKit

Perry's Swift overlay of AppKit for Mac apps: `NSApplicationMain` and
`NSApplication.loadApplication()`, drawing rectangles and lists of them in
the current graphics context, window depths, animation effects, OpenGL
options, `NSEvent.SpecialKey`, the arithmetic of AppKit's numeric wrappers
(`_AppKitKitNumericRawRepresentable`: layout and toolbar priorities, window
levels, font weights and widths, AppKit versions), AppKit's Cocoa error
codes, color and image literals, playground quick looks, `IndexPath`'s item
and section, `URLResourceValues`' icons and thumbnails, `NSGradient`'s
colors and locations, and the macOS 14 menu helpers (section headers and
palettes). It is written for Perry from the API in the macOS SDK's
`AppKit.swiftinterface` and replaces the Swift 5.0 overlay Xcode ships as a
file.

It is compiled as the module `AppKit` over the SDK's Objective-C headers, as
Apple builds its overlays (`platform` marks it a macOS overlay):

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh AppKit <runtime directory>

`Scripts/check-overlay.sh` against the Swift 5.0 overlay and the SDK's
`libswiftAppKit.tbd` reports nothing missing. That stub re-exports
`AppKit.framework`, where macOS now keeps AppKit's Swift API, so it has no
Swift symbols of its own; the framework's own Swift API (diffable data
sources, the `NotificationCenter` messages of macOS 26 and 27, the
`NSViewController.ViewLoading` wrappers, the direction sets, glass and
scroll-edge effects, `NSWorkspace` and `NSWindow` additions and much private
API) is the framework's to provide, and isn't here.

The functions the headers refine for Swift (`NSBeep`, `NSRectFillList…`,
`NSBestDepth`, `NSShowAnimationEffect`, `NSOpenGLGetOption`…) are called
under their `__` names; `NSApplicationMain`, which this module's Swift
function of the same name hides, through `@_silgen_name`. AppKit's error
codes are the values of `AppKitErrors.h`, which Swift's import leaves out.

Approximations: an image literal copies the representations of the image
named in the main bundle (an empty image when there is none), and the
quick looks of `NSTouchBar` and of an `NSTouchBarItem` without a view are
text.

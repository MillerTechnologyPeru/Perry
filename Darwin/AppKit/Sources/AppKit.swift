// AppKit's Swift API that apps call as Swift: Perry's own, built over the
// SDK's AppKit headers into libswiftAppKit.dylib, which the loader looks
// in for AppKit's Swift symbols.

import Foundation

/// The Objective-C NSApplicationMain, which this module's Swift one of the
/// same name hides.
@_silgen_name("NSApplicationMain")
private func objectiveCApplicationMain(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32

/// What @main on an NSApplicationDelegate, and a main.swift that calls it,
/// starts the app with.
public func NSApplicationMain(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32 {
    objectiveCApplicationMain(argc, argv)
}

extension CGRect {
    /// Fills the rectangle in the current context with the current fill
    /// color.
    public func fill(using operation: NSCompositingOperation = .sourceOver) {
        __NSRectFillUsingOperation(self, operation)
    }

    /// Draws the rectangle's frame in the current context.
    public func frame(withWidth width: CGFloat = 1, using operation: NSCompositingOperation = .sourceOver) {
        __NSFrameRectWithWidthUsingOperation(self, width, operation)
    }
}

extension URLResourceValues {
    /// The icon the file shows: its custom icon, else its type's.
    public var effectiveIcon: AnyObject? { allValues[.effectiveIconKey] as AnyObject? }

    /// The file's custom icon, if it has one.
    public var customIcon: NSImage? { allValues[.customIconKey] as? NSImage }
}

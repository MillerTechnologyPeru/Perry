import Foundation

// Drawing rectangles in the current graphics context, window depths,
// animation effects and OpenGL options.

extension CGRect {
    /// Fills the rectangle in the current context with the current fill
    /// color.
    @available(swift 4)
    public func fill(using operation: NSCompositingOperation = NSGraphicsContext.current?.compositingOperation ?? .sourceOver) {
        __NSRectFillUsingOperation(self, operation)
    }

    /// Draws the rectangle's frame in the current context.
    @available(swift 4)
    public func frame(withWidth width: CGFloat = 1.0,
                      using operation: NSCompositingOperation = NSGraphicsContext.current?.compositingOperation ?? .sourceOver) {
        __NSFrameRectWithWidthUsingOperation(self, width, operation)
    }

    /// Intersects the current context's clip with the rectangle.
    @available(swift 4)
    public func clip() {
        __NSRectClip(self)
    }
}

extension Sequence where Element == CGRect {
    /// Fills the rectangles with the current fill color.
    @available(swift 4)
    public func fill(using operation: NSCompositingOperation = NSGraphicsContext.current?.compositingOperation ?? .sourceOver) {
        let rects = Array(self)
        rects.withUnsafeBufferPointer { __NSRectFillListUsingOperation($0.baseAddress!, $0.count, operation) }
    }

    /// Intersects the current context's clip with the rectangles' union.
    @available(swift 4)
    public func clip() {
        let rects = Array(self)
        rects.withUnsafeBufferPointer { __NSRectClipList($0.baseAddress!, $0.count) }
    }
}

extension Sequence where Element == (CGRect, NSColor) {
    /// Fills each rectangle with its color.
    @available(swift 4)
    public func fill(using operation: NSCompositingOperation = NSGraphicsContext.current?.compositingOperation ?? .sourceOver) {
        let pairs = Array(self)
        guard !pairs.isEmpty else { return }
        let rects = pairs.map(\.0), colors = pairs.map(\.1)
        rects.withUnsafeBufferPointer { rects in
            colors.withUnsafeBufferPointer { colors in
                __NSRectFillListWithColorsUsingOperation(rects.baseAddress!, colors.baseAddress!, rects.count, operation)
            }
        }
    }
}

extension Sequence where Element == (CGRect, gray: CGFloat) {
    /// Fills each rectangle with its gray, compositing with `operation`
    /// (which AppKit's function of grays doesn't take, so the context's is
    /// set while it draws).
    @available(swift 4)
    public func fill(using operation: NSCompositingOperation = NSGraphicsContext.current?.compositingOperation ?? .sourceOver) {
        let pairs = Array(self)
        guard !pairs.isEmpty else { return }
        let rects = pairs.map(\.0), grays = pairs.map(\.gray)
        let context = NSGraphicsContext.current
        let previous = context?.compositingOperation
        context?.compositingOperation = operation
        defer { if let previous { context?.compositingOperation = previous } }
        rects.withUnsafeBufferPointer { rects in
            grays.withUnsafeBufferPointer { grays in
                __NSRectFillListWithGrays(rects.baseAddress!, grays.baseAddress!, rects.count)
            }
        }
    }
}

extension NSWindow.Depth {
    /// The depth that best matches the parameters, and whether it matches
    /// all of them.
    @available(swift 4)
    public static func bestDepth(colorSpaceName: NSColorSpaceName, bitsPerSample: Int, bitsPerPixel: Int,
                                 isPlanar: Bool) -> (NSWindow.Depth, isExactMatch: Bool) {
        var exact: ObjCBool = false
        let depth = __NSBestDepth(colorSpaceName, bitsPerSample, bitsPerPixel, isPlanar, &exact)
        return (depth, exact.boolValue)
    }

    /// The depths windows can have, from AppKit's zero-terminated list.
    @available(swift 4)
    public static var availableDepths: [NSWindow.Depth] {
        var depths: [NSWindow.Depth] = []
        var depth = __NSAvailableWindowDepths()
        while depth.pointee.rawValue != 0 {
            depths.append(depth.pointee)
            depth += 1
        }
        return depths
    }
}

/// What an animation effect calls when it ends: the handler it was shown
/// with, retained through the effect's context.
private final class AnimationEffectEnd: NSObject {
    let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func animationEffectDidEnd(_ context: UnsafeMutableRawPointer?) {
        guard let context else { return }
        Unmanaged<AnimationEffectEnd>.fromOpaque(context).release()
        handler()
    }
}

@available(macOS, introduced: 10.9, deprecated: 14.0, message: "Use NSCursor.disappearingItemCursor instead")
extension NSAnimationEffect {
    @available(swift 4)
    public func show(centeredAt centerLocation: NSPoint, size: NSSize, completionHandler: @escaping () -> Void = { }) {
        let end = AnimationEffectEnd(completionHandler)
        __NSShowAnimationEffect(self, centerLocation, size, end, #selector(AnimationEffectEnd.animationEffectDidEnd(_:)),
                                Unmanaged.passRetained(end).toOpaque())
    }
}

@available(macOS, introduced: 10.9, deprecated: 10.14, message: "Please use Metal or MetalKit.")
extension NSOpenGLGlobalOption {
    /// The option's value, for all OpenGL contexts.
    @available(swift 4)
    public var globalValue: GLint {
        get {
            var value: GLint = 0
            __NSOpenGLGetOption(self, &value)
            return value
        }
        set {
            __NSOpenGLSetOption(self, newValue)
        }
    }
}

@available(macOS, introduced: 10.9, deprecated: 10.14, message: "Please use Metal or MetalKit.")
extension NSOpenGLContext {
    /// The version of AppKit's OpenGL support.
    @available(swift 4)
    public static var openGLVersion: (major: GLint, minor: GLint) {
        var major: GLint = 0, minor: GLint = 0
        __NSOpenGLGetVersion(&major, &minor)
        return (major, minor)
    }
}

import CPerryGeometry
import Glibc
import PerryObjCInterop

// More of NSGraphics.h's and NSOpenGL.h's C functions: filling and clipping
// to lists of rectangles, with a compositing operation; the "poof" an item
// removed from a collection shows; window depths; and NSOpenGL's global
// options. Fills composite through CoreGraphics' blend modes, which
// NSCompositingOperation's values map to as on Darwin.

/// NSCompositingOperation, as CoreGraphics' blend modes.
enum Compositing {
    /// CGContextSetBlendMode, looked up the first time an operation other
    /// than source-over is drawn with.
    nonisolated(unsafe) private static var setBlendMode: (@convention(c) (CGRef?, Int32) -> Void)?? = nil

    private static var blendModeFunction: (@convention(c) (CGRef?, Int32) -> Void)? {
        if let setBlendMode { return setBlendMode }
        let coreGraphics = "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"
        let symbol = Symbols.symbol(coreGraphics, "perry_native_CGContextSetBlendMode") ?? Symbols.symbol(coreGraphics, "_CGContextSetBlendMode")
        let function = symbol.map { unsafeBitCast($0, to: (@convention(c) (CGRef?, Int32) -> Void).self) }
        setBlendMode = .some(function)
        return function
    }

    /// The CGBlendMode for an NSCompositingOperation: the Porter-Duff
    /// operations (clear 0 through plus-lighter 13) are CGBlendMode's 16
    /// through 27, with highlight (12) drawn as source-over, and the blend
    /// modes (multiply 14 through luminosity 28) its 1 through 15.
    static func blendMode(_ operation: UInt) -> Int32 {
        switch operation {
        case 0, 1: return Int32(operation) + 16                 // clear, copy
        case 2, 12: return 0                                     // source-over, highlight
        case 3...11: return Int32(operation) + 15                // source-in … plus-darker
        case 13: return 27                                       // plus-lighter
        case 14...28: return Int32(operation) - 13               // multiply … luminosity
        default: return 0
        }
    }

    /// Runs `draw` in the current context with `operation`'s blend mode,
    /// the context's state as it was afterwards.
    static func drawing(_ operation: UInt, _ draw: (CGRef) -> Void) {
        guard let context = NSGraphicsContext.currentCG else { return }
        let mode = blendMode(operation)
        guard mode != 0, let setBlendMode = blendModeFunction else { return draw(context) }
        CG.saveGState(context)
        setBlendMode(context, mode)
        draw(context)
        CG.restoreGState(context)
    }

    /// Fills each rectangle, in its color when there are colors: each is
    /// set as NSColor -set sets it, so the last stays the current color,
    /// as Darwin leaves it.
    static func fill(_ rects: UnsafePointer<CGRect>?, _ count: Int, colors: [UnsafeMutableRawPointer?]? = nil, operation: UInt) {
        guard let rects, count > 0 else { return }
        drawing(operation) { context in
            for index in 0..<count {
                if let colors { Send.void(colors[index], "set") }
                CG.fillRect(context, rects[index])
            }
        }
        // The state the blend mode was set in is gone, and the color with it.
        if let last = colors?.last, blendMode(operation) != 0 { Send.void(last, "set") }
    }
}

@c(_NSRectFillListUsingOperation)
public func NSRectFillListUsingOperation(_ rects: UnsafePointer<CGRect>?, _ count: Int, _ operation: UInt) {
    Compositing.fill(rects, count, operation: operation)
}

@c(_NSRectFillListWithColors)
public func NSRectFillListWithColors(_ rects: UnsafePointer<CGRect>?, _ colors: UnsafePointer<UnsafeMutableRawPointer?>?, _ count: Int) {
    NSRectFillListWithColorsUsingOperation(rects, colors, count, 2)
}

@c(_NSRectFillListWithColorsUsingOperation)
public func NSRectFillListWithColorsUsingOperation(_ rects: UnsafePointer<CGRect>?, _ colors: UnsafePointer<UnsafeMutableRawPointer?>?,
                                                   _ count: Int, _ operation: UInt) {
    guard let colors, count > 0 else { return }
    Compositing.fill(rects, count, colors: Array(UnsafeBufferPointer(start: colors, count: count)), operation: operation)
}

/// Each rectangle in a gray from black (0) to white (1).
@c(_NSRectFillListWithGrays)
public func NSRectFillListWithGrays(_ rects: UnsafePointer<CGRect>?, _ grays: UnsafePointer<CGFloat>?, _ count: Int) {
    guard let grays, count > 0 else { return }
    let colors = (0..<count).map { NSColor(white: grays[$0], alpha: 1) }
    withExtendedLifetime(colors) {
        Compositing.fill(rects, count, colors: colors.map { Optional($0.objcObject) }, operation: 2)
    }
}

/// Clips to the rectangles' union.
@c(_NSRectClipList)
public func NSRectClipList(_ rects: UnsafePointer<CGRect>?, _ count: Int) {
    guard let context = NSGraphicsContext.currentCG, let rects, let path = CG.pathCreateMutable() else { return }
    for index in 0..<max(count, 0) { CG.pathAddRect(path, nil, rects[index]) }
    CG.addPath(context, path)
    CG.clip(context)
    CG.release(path)
}

// MARK: - Animation effects

/// NSShowAnimationEffect: there is no animation to show, so it ends at
/// once, and the delegate hears so (-animationEffectDidEnd: and its kin
/// take the context) on the main queue's next turn, as it would after
/// Darwin's animation.
@DarwinC("_NSShowAnimationEffect")
public func NSShowAnimationEffect(_ effect: UInt, _ center: CGPoint, _ size: CGSize, _ delegate: UnsafeMutableRawPointer?,
                                  _ didEndSelector: UnsafeRawPointer?, _ contextInfo: UnsafeMutableRawPointer?) {
    guard let delegate = ObjCRuntime.retain(delegate), let didEndSelector else { return }
    Dispatch.onMain {
        typealias DidEnd = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, UnsafeMutableRawPointer?) -> Void
        unsafeBitCast(ObjCRuntime.msgSend, to: DidEnd.self)(delegate, didEndSelector, contextInfo)
        ObjCRuntime.release(delegate)
    }
}

// MARK: - Window depths

/// NSWindowDepth's values before Mac OS X 10.6: the color space model in
/// the second byte (1 gray, 2 RGB) and the bits per sample in the first.
enum WindowDepths {
    static let gray2: Int32 = 0x102
    static let gray8: Int32 = 0x108
    static let rgb4: Int32 = 0x204
    static let rgb8: Int32 = 0x208
    static let rgb16: Int32 = 0x210
    static let rgb32: Int32 = 0x220

    /// The depths windows can have: Perry's are 8 bits per sample RGB.
    nonisolated(unsafe) static let available: UnsafeMutablePointer<Int32> = {
        let list = UnsafeMutablePointer<Int32>.allocate(capacity: 2)
        list[0] = rgb8
        list[1] = 0
        return list
    }()

    private static let grayNames: Set<String> = ["NSCalibratedWhiteColorSpace", "NSDeviceWhiteColorSpace",
                                                 "NSCalibratedBlackColorSpace", "NSDeviceBlackColorSpace"]
    private static let colorNames: Set<String> = ["NSCalibratedRGBColorSpace", "NSDeviceRGBColorSpace", "NSNamedColorSpace",
                                                  "NSPatternColorSpace", "NSCustomColorSpace"]

    /// The depth NSBestDepth chooses, and whether it matches, as macOS 14
    /// answers: gray is 2 bits for 1 or 2, else 8 (no match above 8); RGB
    /// is 4 bits for 1 through 4, 16 or 32 for those, else 8 (a match up to
    /// 32, as Darwin counts it); CMYK, which windows never are, is RGB and
    /// no match. Bits per pixel and planarity are not looked at.
    static func best(colorSpace: String?, bitsPerSample bps: Int) -> (depth: Int32, exact: Bool) {
        if let colorSpace, grayNames.contains(colorSpace) {
            switch bps {
            case 1...2: return (gray2, true)
            case ...8: return (gray8, true)
            default: return (gray8, false)
            }
        }
        if colorSpace == "NSDeviceCMYKColorSpace" { return (rgb8, false) }
        if colorSpace.map({ !colorNames.contains($0) }) ?? true {
            appKitWarning("NSBestDepth: bad color space name \(colorSpace ?? "(null)")")
        }
        switch bps {
        case 1...4: return (rgb4, true)
        case 16: return (rgb16, true)
        case 32: return (rgb32, true)
        case ...32: return (rgb8, true)
        default: return (rgb8, false)
        }
    }
}

@c(_NSBestDepth)
public func NSBestDepth(_ colorSpace: UnsafeMutableRawPointer?, _ bitsPerSample: Int, _ bitsPerPixel: Int, _ planar: Bool,
                        _ exactMatch: UnsafeMutablePointer<Bool>?) -> Int32 {
    let best = WindowDepths.best(colorSpace: colorSpace.map { String(objCArgument: $0) }, bitsPerSample: bitsPerSample)
    exactMatch?.pointee = best.exact
    return best.depth
}

/// A list ending in 0.
@c(_NSAvailableWindowDepths)
public func NSAvailableWindowDepths() -> UnsafePointer<Int32>? { UnsafePointer(WindowDepths.available) }

// MARK: - NSOpenGL's global options

/// NSOpenGLGlobalOption's values, which CGL kept for the process: the
/// pixel format cache's size (501), whether renderers stay loaded (503)
/// and the build cache (506) are kept as set; clearing the format cache
/// (502) and resetting the library (504) are actions, with nothing to
/// clear here, and read 0. Others are not options: getting one leaves
/// the value as it is, as Darwin does.
enum OpenGLGlobalOptions {
    nonisolated(unsafe) static var values: [UInt32: Int32] = [501: 5, 502: 0, 503: 1, 504: 0, 506: 0]
}

@c(_NSOpenGLSetOption)
public func NSOpenGLSetOption(_ name: UInt32, _ value: Int32) {
    guard [501, 503, 506].contains(name) else { return }
    OpenGLGlobalOptions.values[name] = value
}

@c(_NSOpenGLGetOption)
public func NSOpenGLGetOption(_ name: UInt32, _ value: UnsafeMutablePointer<Int32>?) {
    guard let current = OpenGLGlobalOptions.values[name] else { return }
    value?.pointee = current
}

/// The version of NSOpenGL's API, not OpenGL's: 1.2, as macOS answers.
@c(_NSOpenGLGetVersion)
public func NSOpenGLGetVersion(_ major: UnsafeMutablePointer<Int32>?, _ minor: UnsafeMutablePointer<Int32>?) {
    major?.pointee = 1
    minor?.pointee = 2
}

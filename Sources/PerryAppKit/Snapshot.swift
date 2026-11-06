import CPerryGeometry
import Glibc
import PerryObjCInterop

/// With PERRY_APPKIT_SNAPSHOT set to a path, the frontmost window is
/// written there as a PNG every couple of seconds while it draws, with its
/// view tree beside it in <path>.txt: to see what an app shows where the
/// desktop allows no screenshots.
enum Snapshot {
    nonisolated(unsafe) static let path: String? = getenv("PERRY_APPKIT_SNAPSHOT").map { String(cString: $0) }
    nonisolated(unsafe) private static var lastWrite = 0.0

    private typealias CreateWithURL = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
    private typealias AddImage = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
    private typealias Finalize = @convention(c) (UnsafeMutableRawPointer?) -> Bool

    private static let coreGraphics = "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"

    private static func function<T>(_ name: String, as type: T.Type) -> T? {
        guard let symbol = Symbols.symbol(coreGraphics, "perry_native_" + name) ?? Symbols.symbol(coreGraphics, "_" + name) else { return nil }
        return unsafeBitCast(symbol, to: type)
    }

    /// After the windows draw: the frontmost one, two seconds after the last.
    static func windowsDrew() {
        guard let path, Clock.now - lastWrite >= 2,
              let window = Windows.all.last(where: { $0.visible && $0.sdlWindow != nil }) else { return }
        lastWrite = Clock.now
        write(window, to: path)
    }

    static func write(_ window: NSWindow, to path: String) {
        guard let root = window.rootView, let layer = root.layer,
              let context = CG.makeContext(size: window.frame.size, scale: window.backingScale) else { return }
        defer { CG.release(context) }
        // Layers draw from the top; the bitmap context's y is upwards.
        CG.translateCTM(context, 0, window.frame.height)
        CG.scaleCTM(context, 1, -1)
        Send.void(layer.objcObject, "renderInContext:", context)
        guard let image = CG.bitmapContextCreateImage(context) else { return }
        defer { CG.release(image) }
        guard let create = function("CGImageDestinationCreateWithURL", as: CreateWithURL.self),
              let add = function("CGImageDestinationAddImage", as: AddImage.self),
              let finalize = function("CGImageDestinationFinalize", as: Finalize.self),
              let urlClass = Classes.named("NSURL"),
              let url = Send.object(urlClass.pointer, "fileURLWithPath:", NSObject(objCReturnValue: path.objCReturnValue()).objcObject)
        else { return }
        let type = NSObject(objCReturnValue: "public.png".objCReturnValue())
        guard let destination = create(url, type.objcObject, 1, nil) else { return }
        defer { CG.release(destination) }
        add(destination, image, nil)
        _ = finalize(destination)
        let tree = Trace.describe(root)
        if let file = fopen(path + ".txt", "w") {
            fputs(tree + "\n", file)
            fclose(file)
        }
    }
}

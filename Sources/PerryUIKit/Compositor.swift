import CPerryGeometry
import Glibc
import PerryObjCInterop

// The live view on the GPU: an SDL3 window and renderer, whose events are
// touches and typing, and whose frames QuartzCore composites from the
// windows' layers. libSDL3 is loaded at run time; without it the live view
// draws in software.

/// SDL3's C API, as the compositor calls it.
enum SDL {
    typealias Pointer = UnsafeMutableRawPointer

    nonisolated(unsafe) static var initialize: (@convention(c) (UInt32) -> Bool)!
    nonisolated(unsafe) static var createWindow: (@convention(c) (UnsafePointer<CChar>?, Int32, Int32, UInt64) -> Pointer?)!
    nonisolated(unsafe) static var createRenderer: (@convention(c) (Pointer?, UnsafePointer<CChar>?) -> Pointer?)!
    nonisolated(unsafe) static var rendererName: (@convention(c) (Pointer?) -> UnsafePointer<CChar>?)!
    nonisolated(unsafe) static var pollEvent: (@convention(c) (Pointer?) -> Bool)!
    nonisolated(unsafe) static var error: (@convention(c) () -> UnsafePointer<CChar>?)!
    nonisolated(unsafe) static var setWindowMinimumSize: (@convention(c) (Pointer?, Int32, Int32) -> Bool)?
    nonisolated(unsafe) static var primaryDisplay: (@convention(c) () -> UInt32)?
    nonisolated(unsafe) static var displayContentScale: (@convention(c) (UInt32) -> Float)?
    nonisolated(unsafe) static var displayUsableBounds: (@convention(c) (UInt32, UnsafeMutablePointer<Int32>?) -> Bool)?
    nonisolated(unsafe) static var startTextInput: (@convention(c) (Pointer?) -> Bool)?
    nonisolated(unsafe) static var stopTextInput: (@convention(c) (Pointer?) -> Bool)?

    static var lastError: String { error().map { String(cString: $0) } ?? "" }

    nonisolated(unsafe) private static var loaded: Bool?

    /// Before SDL starts: its renderer makes its GL contexts through EGL,
    /// as EAGLContext does, so the two can take turns being current on one
    /// thread, and renders with OpenGL ES 2.
    static func prepareEnvironment() {
        setenv("SDL_VIDEO_FORCE_EGL", "1", 0)
        setenv("SDL_RENDER_DRIVER", "opengles2", 0)
    }

    /// Binds SDL3 once; false without it.
    static func loadOnce() -> Bool {
        if let loaded { return loaded }
        let result = load()
        loaded = result
        return result
    }

    /// The desktop's scaling of the primary display (2 on a HiDPI desktop),
    /// starting SDL's video for the question; nil without SDL or a display.
    static func nativeScale() -> CGFloat? {
        prepareEnvironment()
        guard loadOnce(), initialize(0x20), let primaryDisplay, let displayContentScale else { return nil }
        let display = primaryDisplay()
        guard display != 0 else { return nil }
        let scale = displayContentScale(display)
        return scale > 0 ? CGFloat(scale) : nil
    }

    /// The primary display's usable area, without the desktop's panels, in
    /// pixels; nil without SDL or a display.
    static func usableDisplaySize() -> CGSize? {
        prepareEnvironment()
        guard loadOnce(), initialize(0x20), let primaryDisplay, let displayUsableBounds else { return nil }
        let display = primaryDisplay()
        var rect = [Int32](repeating: 0, count: 4)     // SDL_Rect: x, y, w, h
        guard display != 0, displayUsableBounds(display, &rect), rect[2] > 0, rect[3] > 0 else { return nil }
        return CGSize(width: CGFloat(rect[2]), height: CGFloat(rect[3]))
    }

    /// Binds SDL3's functions; false without libSDL3.
    static func load() -> Bool {
        guard let library = dlopen("libSDL3.so.0", RTLD_NOW) else { return false }
        var complete = true
        func bind<T>(_ name: String) -> T? {
            guard let symbol = dlsym(library, name) else {
                complete = false
                return nil
            }
            return unsafeBitCast(symbol, to: T.self)
        }
        initialize = bind("SDL_Init")
        createWindow = bind("SDL_CreateWindow")
        createRenderer = bind("SDL_CreateRenderer")
        rendererName = bind("SDL_GetRendererName")
        pollEvent = bind("SDL_PollEvent")
        error = bind("SDL_GetError")
        setWindowMinimumSize = dlsym(library, "SDL_SetWindowMinimumSize")
            .map { unsafeBitCast($0, to: (@convention(c) (Pointer?, Int32, Int32) -> Bool).self) }
        primaryDisplay = dlsym(library, "SDL_GetPrimaryDisplay").map { unsafeBitCast($0, to: (@convention(c) () -> UInt32).self) }
        displayContentScale = dlsym(library, "SDL_GetDisplayContentScale").map { unsafeBitCast($0, to: (@convention(c) (UInt32) -> Float).self) }
        displayUsableBounds = dlsym(library, "SDL_GetDisplayUsableBounds")
            .map { unsafeBitCast($0, to: (@convention(c) (UInt32, UnsafeMutablePointer<Int32>?) -> Bool).self) }
        startTextInput = dlsym(library, "SDL_StartTextInput").map { unsafeBitCast($0, to: (@convention(c) (Pointer?) -> Bool).self) }
        stopTextInput = dlsym(library, "SDL_StopTextInput").map { unsafeBitCast($0, to: (@convention(c) (Pointer?) -> Bool).self) }
        return complete
    }
}

final class Compositor {
    let window: SDL.Pointer
    let renderer: SDL.Pointer
    let scale: CGFloat

    /// SDL's renderer's EGL context, which an app's EAGLContext displaces
    /// when it draws on the same thread.
    private var rendererContext: EAGLContexts.Saved?

    /// A window `size` points across at `scale` pixels a point, on the GPU
    /// when SDL has a renderer for it. A resizable app's window can be
    /// resized, and its screen takes the window's size.
    init?(title: String, size: CGSize, scale: CGFloat) {
        guard SDL.initialize(0x20) else {
            uikitWarning("SDL could not start its video: \(SDL.lastError)")
            return nil
        }
        let width = Int32((size.width * scale).rounded()), height = Int32((size.height * scale).rounded())
        // SDL_WINDOW_RESIZABLE.
        guard let window = title.withCString({ SDL.createWindow($0, width, height, Screen.isResizable ? 0x20 : 0) }),
              let renderer = SDL.createRenderer(window, nil) else {
            uikitWarning("SDL could not make a window: \(SDL.lastError)")
            return nil
        }
        // The smallest an iPad app's window gets.
        if Screen.isResizable { _ = SDL.setWindowMinimumSize?(window, Int32(320 * scale), Int32(320 * scale)) }
        (self.window, self.renderer, self.scale) = (window, renderer, scale)
        rendererContext = EAGLContexts.save()
        let name = SDL.rendererName(renderer).map { String(cString: $0) } ?? "unknown"
        uikitWarning("live view composited by SDL's \(name) renderer")
    }

    /// Typed text arrives while text input is on, as for a keyboard on screen.
    func setTextInput(_ on: Bool) {
        _ = on ? SDL.startTextInput?(window) : SDL.stopTextInput?(window)
    }

    /// The touchscreen finger being followed, as SDL numbers it.
    private var finger: UInt64?

    /// Touchscreen fingers, mouse buttons, motion and the wheel as touches,
    /// and the keyboard's text and editing keys; true when the window was
    /// closed. The first finger down is the touch that works scroll views
    /// and controls; others down with it are touches of their own. The
    /// mouse events SDL makes from fingers are left out, as the fingers
    /// come themselves.
    func handleEvents() -> Bool {
        var event = [UInt64](repeating: 0, count: 16)
        var closed = false
        while event.withUnsafeMutableBytes({ SDL.pollEvent($0.baseAddress) }) {
            event.withUnsafeBytes { raw in
                let type = raw.load(fromByteOffset: 0, as: UInt32.self)
                func point() -> CGPoint {
                    CGPoint(x: CGFloat(raw.load(fromByteOffset: 28, as: Float.self)) / scale,
                            y: CGFloat(raw.load(fromByteOffset: 32, as: Float.self)) / scale)
                }
                /// A mouse event SDL made from a finger: SDL_TOUCH_MOUSEID.
                func fromFinger() -> Bool { raw.load(fromByteOffset: 20, as: UInt32.self) == UInt32.max }
                /// A finger's place: x and y from 0 to 1 across the window.
                func fingerPoint() -> CGPoint {
                    let size = Screen.bounds.size
                    return CGPoint(x: CGFloat(raw.load(fromByteOffset: 32, as: Float.self)) * size.width,
                                   y: CGFloat(raw.load(fromByteOffset: 36, as: Float.self)) * size.height)
                }
                switch type {
                case 0x100: // quit
                    closed = true
                case 0x700: // finger down: SDL_FingerID at 24
                    let id = raw.load(fromByteOffset: 24, as: UInt64.self)
                    if finger == nil {
                        finger = id
                        Touches.down(at: fingerPoint())
                    } else {
                        Touches.down(at: fingerPoint(), finger: id)
                    }
                    Display.markDirty()
                case 0x702: // finger motion
                    let id = raw.load(fromByteOffset: 24, as: UInt64.self)
                    if finger == id { Touches.move(to: fingerPoint()) } else { Touches.move(to: fingerPoint(), finger: id) }
                case 0x701, 0x703: // finger up, finger cancelled
                    let id = raw.load(fromByteOffset: 24, as: UInt64.self)
                    if finger == id {
                        finger = nil
                        Touches.up(at: fingerPoint())
                    } else {
                        Touches.up(at: fingerPoint(), finger: id, cancelled: type == 0x703)
                    }
                    Display.markDirty()
                case 0x400: // mouse motion
                    guard !fromFinger() else { break }
                    Touches.move(to: point())
                case 0x401, 0x402: // mouse button down and up
                    guard !fromFinger(), raw.load(fromByteOffset: 24, as: UInt8.self) == 1 else { break }
                    if type == 0x401 { Touches.down(at: point()) } else { Touches.up(at: point()) }
                    Display.markDirty()
                case 0x206: // window resized: its size at 20 and 24
                    let size = CGSize(width: CGFloat(raw.load(fromByteOffset: 20, as: Int32.self)) / scale,
                                      height: CGFloat(raw.load(fromByteOffset: 24, as: Int32.self)) / scale)
                    Screen.resize(to: size)
                case 0x300: // key down: SDL_Keycode at 28
                    switch raw.load(fromByteOffset: 28, as: UInt32.self) {
                    case 0x08: Keyboard.deleteBackward()
                    case 0x0D, 0x4000_0058: Keyboard.returnKey()   // return, keypad enter
                    case 0x1B: Keyboard.escape()
                    default: break
                    }
                case 0x303: // text input: UTF-8 at 24
                    if let text = raw.load(fromByteOffset: 24, as: UnsafePointer<CChar>?.self) {
                        Keyboard.insert(String(cString: text))
                    }
                case 0x403: // wheel: positive y scrolls up, unless flipped
                    let flipped = raw.load(fromByteOffset: 32, as: UInt32.self) == 1
                    let y = CGFloat(raw.load(fromByteOffset: 28, as: Float.self)) * (flipped ? -1 : 1)
                    let at = CGPoint(x: CGFloat(raw.load(fromByteOffset: 36, as: Float.self)) / scale,
                                     y: CGFloat(raw.load(fromByteOffset: 40, as: Float.self)) / scale)
                    Touches.wheel(at: at, by: -y * 40)
                    Display.markDirty()
                default:
                    Display.markDirty()
                }
            }
        }
        return closed
    }

    /// Has QuartzCore composite the windows' layers, back to front, and
    /// show the frame.
    func draw(_ windows: [UIWindow]) {
        // Layers display first, as an app's OpenGL ES drawing for a layer
        // makes its own context current; then the renderer's is again.
        QuartzCore.withRoots(windows) { QuartzCore.displayLayers?($0, $1) }
        rendererContext?.restore()
        _ = QuartzCore.withRoots(windows) { QuartzCore.composite?(renderer, scale, $0, $1) }
        // The renderer's context was current while it drew; the app's is
        // again.
        EAGLContexts.restore()
    }
}

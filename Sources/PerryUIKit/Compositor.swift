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
    /// SDL_GetDesktopDisplayMode: its SDL_DisplayMode, whose pixel_density
    /// (at 16) is the desktop's scaling of the display, fractional on a
    /// desktop scaled by 125%.
    nonisolated(unsafe) static var desktopDisplayMode: (@convention(c) (UInt32) -> UnsafeRawPointer?)?
    nonisolated(unsafe) static var windowPixelDensity: (@convention(c) (Pointer?) -> Float)?
    nonisolated(unsafe) static var setWindowSize: (@convention(c) (Pointer?, Int32, Int32) -> Bool)?
    nonisolated(unsafe) static var startTextInput: (@convention(c) (Pointer?) -> Bool)?
    nonisolated(unsafe) static var setViewport: (@convention(c) (Pointer?, UnsafeRawPointer?) -> Bool)?
    nonisolated(unsafe) static var outputSize: (@convention(c) (Pointer?, UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<Int32>?) -> Bool)?
    nonisolated(unsafe) static var stopTextInput: (@convention(c) (Pointer?) -> Bool)?

    static var lastError: String { error().map { String(cString: $0) } ?? "" }

    nonisolated(unsafe) private static var loaded: Bool?

    /// Before SDL starts: its renderer makes its GL contexts through EGL,
    /// as EAGLContext does, so the two can take turns being current on one
    /// thread. The renderer, OpenGL ES 2, is named where it is made, not
    /// with SDL_RENDER_DRIVER: the environment is the app's too, and an app
    /// with an SDL of its own (World of Goo 2's) would read it and choose
    /// OpenGL ES over Metal.
    static func prepareEnvironment() {
        setenv("SDL_VIDEO_FORCE_EGL", "1", 0)
        _ = videoDriver
    }

    /// The video driver the environment names for Perry's SDL (PortMaster
    /// sets SDL_VIDEODRIVER=wayland), taken out of the environment when
    /// UIKit starts, before the app runs: an app's own SDL reads it too, and
    /// World of Goo 2's, built for iOS, finds no such driver and stops. It
    /// reaches Perry's SDL as a hint instead. The audio driver (PortMaster's
    /// SDL_AUDIODRIVER=pulseaudio) goes too, which Perry's SDL does not use
    /// and an iOS SDL would find none of, opening no sound.
    nonisolated(unsafe) static let videoDriver: String? = {
        var driver: String?
        for name in ["SDL_VIDEO_DRIVER", "SDL_VIDEODRIVER"] {
            if let value = getenv(name) {
                driver = driver ?? String(cString: value)
                unsetenv(name)
            }
        }
        unsetenv("SDL_AUDIO_DRIVER")
        unsetenv("SDL_AUDIODRIVER")
        return driver
    }()

    /// Binds SDL3 once; false without it.
    static func loadOnce() -> Bool {
        if let loaded { return loaded }
        let result = load()
        loaded = result
        return result
    }

    /// The desktop's scaling of the primary display, as the native display
    /// gives it: its pixels per window coordinate (1.25 on a desktop scaled
    /// by 125%, 2 on a HiDPI one) times its content scale. Starts SDL's
    /// video for the question; nil without SDL or a display.
    static func nativeScale() -> CGFloat? {
        guard let display = primaryDisplayStarted() else { return nil }
        let content = displayContentScale.map { CGFloat($0(display)) } ?? 1
        let scale = displayDensity(display) * (content > 0 ? content : 1)
        return scale > 0 ? scale : nil
    }

    /// The primary display's pixels per window coordinate: its desktop
    /// mode's pixel density, else 1.
    static func displayDensity() -> CGFloat { primaryDisplayStarted().map(displayDensity) ?? 1 }

    private static func displayDensity(_ display: UInt32) -> CGFloat {
        guard let mode = desktopDisplayMode?(display) else { return 1 }
        let density = CGFloat(mode.load(fromByteOffset: 16, as: Float.self))
        return density > 0 ? density : 1
    }

    private static func primaryDisplayStarted() -> UInt32? {
        prepareEnvironment()
        guard loadOnce(), initialize(0x20), let primaryDisplay else { return nil }
        let display = primaryDisplay()
        return display != 0 ? display : nil
    }

    /// The primary display's usable area, without the desktop's panels, in
    /// pixels: SDL gives it in window coordinates, which a scaled desktop's
    /// pixel density turns to pixels. Nil without SDL or a display.
    static func usableDisplaySize() -> CGSize? {
        guard let display = primaryDisplayStarted(), let displayUsableBounds else { return nil }
        var rect = [Int32](repeating: 0, count: 4)     // SDL_Rect: x, y, w, h
        guard displayUsableBounds(display, &rect), rect[2] > 0, rect[3] > 0 else { return nil }
        let density = displayDensity(display)
        return CGSize(width: (CGFloat(rect[2]) * density).rounded(.down), height: (CGFloat(rect[3]) * density).rounded(.down))
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
        if let setHint = dlsym(library, "SDL_SetHint") {
            typealias SetHint = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Bool
            let hint = unsafeBitCast(setHint, to: SetHint.self)
            if let videoDriver { _ = hint("SDL_VIDEO_DRIVER", videoDriver) }
            // The window's Wayland app ID and X11 class: the app's desktop
            // entry's ID (DesktopEntry).
            if let id = DesktopEntry.id { _ = hint("SDL_APP_ID", id) }
        }
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
        desktopDisplayMode = dlsym(library, "SDL_GetDesktopDisplayMode")
            .map { unsafeBitCast($0, to: (@convention(c) (UInt32) -> UnsafeRawPointer?).self) }
        windowPixelDensity = dlsym(library, "SDL_GetWindowPixelDensity")
            .map { unsafeBitCast($0, to: (@convention(c) (Pointer?) -> Float).self) }
        setWindowSize = dlsym(library, "SDL_SetWindowSize")
            .map { unsafeBitCast($0, to: (@convention(c) (Pointer?, Int32, Int32) -> Bool).self) }
        startTextInput = dlsym(library, "SDL_StartTextInput").map { unsafeBitCast($0, to: (@convention(c) (Pointer?) -> Bool).self) }
        setViewport = dlsym(library, "SDL_SetRenderViewport")
            .map { unsafeBitCast($0, to: (@convention(c) (Pointer?, UnsafeRawPointer?) -> Bool).self) }
        outputSize = dlsym(library, "SDL_GetCurrentRenderOutputSize")
            .map { unsafeBitCast($0, to: (@convention(c) (Pointer?, UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<Int32>?) -> Bool).self) }
        stopTextInput = dlsym(library, "SDL_StopTextInput").map { unsafeBitCast($0, to: (@convention(c) (Pointer?) -> Bool).self) }
        return complete
    }
}

final class Compositor {
    let window: SDL.Pointer
    let renderer: SDL.Pointer
    let scale: CGFloat
    /// The window's pixels per window coordinate, which SDL gives events
    /// and sizes in: the desktop's scaling, fractional or whole.
    private(set) var density: CGFloat = 1

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
        // The window is made in window coordinates, the display's pixels
        // over its density, and drawn at its pixel density, so a desktop
        // scaled by a fraction shows it pixel for pixel rather than scaled.
        let estimate = SDL.displayDensity()
        let width = Int32((size.width * scale / estimate).rounded()), height = Int32((size.height * scale / estimate).rounded())
        // SDL_WINDOW_RESIZABLE, SDL_WINDOW_HIGH_PIXEL_DENSITY.
        let flags: UInt64 = (Screen.isResizable ? 0x20 : 0) | 0x2000
        guard let window = title.withCString({ SDL.createWindow($0, width, height, flags) }),
              let renderer = "opengles2".withCString({ SDL.createRenderer(window, $0) }) else {
            uikitWarning("SDL could not make a window: \(SDL.lastError)")
            return nil
        }
        let density = SDL.windowPixelDensity.map { CGFloat($0(window)) } ?? estimate
        // A compositor that draws the window at another density than the
        // display's has it resized, for the pixels the screen needs.
        if density > 0, abs(density - estimate) > 0.01 {
            _ = SDL.setWindowSize?(window, Int32((size.width * scale / density).rounded()), Int32((size.height * scale / density).rounded()))
        }
        // The smallest an iPad app's window gets.
        if Screen.isResizable {
            let side = Int32((320 * scale / max(density, 1)).rounded())
            _ = SDL.setWindowMinimumSize?(window, side, side)
        }
        (self.window, self.renderer, self.scale) = (window, renderer, scale)
        self.density = density > 0 ? density : 1
        fitted = Screen.fixed != nil && SDL.setViewport != nil && SDL.outputSize != nil
        rendererContext = EAGLContexts.save()
        let name = SDL.rendererName(renderer).map { String(cString: $0) } ?? "unknown"
        Display.gpuRenderer = name
        uikitWarning("live view composited by SDL's \(name) renderer, at \(scale) pixels a point, \(self.density) a window coordinate")
    }

    /// Typed text arrives while text input is on, as for a keyboard on screen.
    func setTextInput(_ on: Bool) {
        _ = on ? SDL.startTextInput?(window) : SDL.stopTextInput?(window)
    }

    /// Whether a fixed screen is fitted to the window: drawn in a viewport
    /// centered in it, at `scale`, with bars beside it.
    private var fitted = false
    /// The window's pixels, and where in them the viewport begins.
    private var output = CGSize.zero
    private var origin = CGPoint.zero

    /// Centers the viewport for the window as it is now.
    private func fit() {
        var w: Int32 = 0, h: Int32 = 0
        guard fitted, SDL.outputSize?(renderer, &w, &h) == true, w > 0, h > 0 else { return }
        output = CGSize(width: CGFloat(w), height: CGFloat(h))
        let size = Screen.bounds.size
        let width = (size.width * scale).rounded(), height = (size.height * scale).rounded()
        origin = CGPoint(x: ((output.width - width) / 2).rounded(.down), y: ((output.height - height) / 2).rounded(.down))
        var rect = (Int32(origin.x), Int32(origin.y), Int32(width), Int32(height))
        _ = withUnsafeBytes(of: &rect) { SDL.setViewport?(renderer, $0.baseAddress) }
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
                /// A mouse event's place, which SDL gives in window coordinates.
                func point() -> CGPoint {
                    CGPoint(x: (CGFloat(raw.load(fromByteOffset: 28, as: Float.self)) * density - origin.x) / scale,
                            y: (CGFloat(raw.load(fromByteOffset: 32, as: Float.self)) * density - origin.y) / scale)
                }
                /// A mouse event SDL made from a finger: SDL_TOUCH_MOUSEID.
                func fromFinger() -> Bool { raw.load(fromByteOffset: 20, as: UInt32.self) == UInt32.max }
                /// A finger's place: x and y from 0 to 1 across the window.
                func fingerPoint() -> CGPoint {
                    let x = CGFloat(raw.load(fromByteOffset: 32, as: Float.self)), y = CGFloat(raw.load(fromByteOffset: 36, as: Float.self))
                    if fitted, output.width > 0 {
                        return CGPoint(x: (x * output.width - origin.x) / scale, y: (y * output.height - origin.y) / scale)
                    }
                    let size = Screen.bounds.size
                    return CGPoint(x: x * size.width, y: y * size.height)
                }
                switch type {
                case 0x100, 0x210: // quit, window close requested
                    closed = true
                case 0x20E, 0x20F: // window focus gained, lost
                    Lifecycle.window(focused: type == 0x20E)
                case 0x203, 0x209: // window hidden, minimized
                    Lifecycle.window(visible: false)
                case 0x202, 0x20B: // window shown, restored
                    Lifecycle.window(visible: true)
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
                case 0x207 where !fitted: // window's pixel size changed: its pixels at 20 and 24
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
                case 0x303: // text input: the UTF-8 after the window ID, at a pointer's alignment
                    let textOffset = (20 + MemoryLayout<UnsafeRawPointer>.alignment - 1) & ~(MemoryLayout<UnsafeRawPointer>.alignment - 1)
                    if let text = raw.load(fromByteOffset: textOffset, as: UnsafePointer<CChar>?.self) {
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
        let start = Clock.now
        QuartzCore.withRoots(windows) { QuartzCore.displayLayers?($0, $1) }
        FrameWork.displayed = Clock.now - start
        // GL frames the GPU has finished reading back, to show in this one.
        Renderbuffers.collect()
        rendererContext?.restore()
        fit()
        _ = QuartzCore.withRoots(windows) { QuartzCore.composite?(renderer, Double(scale), $0, $1) }
        // The renderer's context was current while it drew; the app's is
        // again.
        EAGLContexts.restore()
    }
}

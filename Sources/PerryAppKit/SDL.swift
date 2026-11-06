import CPerryGeometry
import Glibc

// SDL3's C API, as AppKit's windows, events, cursor and screens call it.
// libSDL3 is loaded at run time, when the first window or screen is asked
// for, so nothing needs it without a display. SDL's window coordinates are
// AppKit's points: a window's pixels per coordinate is its backing scale.

enum SDL {
    typealias Pointer = UnsafeMutableRawPointer
    typealias Window = UnsafeMutableRawPointer

    nonisolated(unsafe) static var initialize: (@convention(c) (UInt32) -> Bool)!
    nonisolated(unsafe) static var createWindow: (@convention(c) (UnsafePointer<CChar>?, Int32, Int32, UInt64) -> Window?)!
    nonisolated(unsafe) static var destroyWindow: (@convention(c) (Window?) -> Void)!
    nonisolated(unsafe) static var createRenderer: (@convention(c) (Window?, UnsafePointer<CChar>?) -> Pointer?)!
    nonisolated(unsafe) static var destroyRenderer: (@convention(c) (Pointer?) -> Void)!
    nonisolated(unsafe) static var rendererName: (@convention(c) (Pointer?) -> UnsafePointer<CChar>?)!
    nonisolated(unsafe) static var pollEvent: (@convention(c) (Pointer?) -> Bool)!
    nonisolated(unsafe) static var waitEventTimeout: (@convention(c) (Pointer?, Int32) -> Bool)!
    nonisolated(unsafe) static var error: (@convention(c) () -> UnsafePointer<CChar>?)!
    nonisolated(unsafe) static var windowID: (@convention(c) (Window?) -> UInt32)!
    nonisolated(unsafe) static var windowPixelDensity: (@convention(c) (Window?) -> Float)!
    nonisolated(unsafe) static var setWindowSize: (@convention(c) (Window?, Int32, Int32) -> Bool)!
    nonisolated(unsafe) static var getWindowSize: (@convention(c) (Window?, UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<Int32>?) -> Bool)!
    nonisolated(unsafe) static var setWindowPosition: (@convention(c) (Window?, Int32, Int32) -> Bool)!
    nonisolated(unsafe) static var getWindowPosition: (@convention(c) (Window?, UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<Int32>?) -> Bool)!
    nonisolated(unsafe) static var setWindowTitle: (@convention(c) (Window?, UnsafePointer<CChar>?) -> Bool)!
    nonisolated(unsafe) static var showWindow: (@convention(c) (Window?) -> Bool)!
    nonisolated(unsafe) static var hideWindow: (@convention(c) (Window?) -> Bool)!
    nonisolated(unsafe) static var raiseWindow: (@convention(c) (Window?) -> Bool)!
    nonisolated(unsafe) static var minimizeWindow: (@convention(c) (Window?) -> Bool)!
    nonisolated(unsafe) static var setWindowFullscreen: (@convention(c) (Window?, Bool) -> Bool)!
    nonisolated(unsafe) static var setWindowResizable: (@convention(c) (Window?, Bool) -> Bool)!
    nonisolated(unsafe) static var setWindowMinimumSize: (@convention(c) (Window?, Int32, Int32) -> Bool)!
    nonisolated(unsafe) static var primaryDisplay: (@convention(c) () -> UInt32)!
    nonisolated(unsafe) static var displayBounds: (@convention(c) (UInt32, UnsafeMutablePointer<Int32>?) -> Bool)!
    nonisolated(unsafe) static var displayUsableBounds: (@convention(c) (UInt32, UnsafeMutablePointer<Int32>?) -> Bool)!
    /// SDL_GetDesktopDisplayMode: its SDL_DisplayMode, whose pixel_density
    /// (at 16) is the display's pixels per window coordinate and
    /// refresh_rate (at 20) its rate.
    nonisolated(unsafe) static var desktopDisplayMode: (@convention(c) (UInt32) -> UnsafeRawPointer?)!
    nonisolated(unsafe) static var showCursor: (@convention(c) () -> Bool)!
    nonisolated(unsafe) static var hideCursor: (@convention(c) () -> Bool)!
    nonisolated(unsafe) static var warpMouseInWindow: (@convention(c) (Window?, Float, Float) -> Void)!
    nonisolated(unsafe) static var setRelativeMouseMode: (@convention(c) (Window?, Bool) -> Bool)!
    nonisolated(unsafe) static var mouseState: (@convention(c) (UnsafeMutablePointer<Float>?, UnsafeMutablePointer<Float>?) -> UInt32)!
    nonisolated(unsafe) static var globalMouseState: (@convention(c) (UnsafeMutablePointer<Float>?, UnsafeMutablePointer<Float>?) -> UInt32)!
    nonisolated(unsafe) static var modState: (@convention(c) () -> UInt16)!
    nonisolated(unsafe) static var startTextInput: (@convention(c) (Window?) -> Bool)!
    nonisolated(unsafe) static var stopTextInput: (@convention(c) (Window?) -> Bool)!
    nonisolated(unsafe) static var showSimpleMessageBox: (@convention(c) (UInt32, UnsafePointer<CChar>?, UnsafePointer<CChar>?, Window?) -> Bool)!
    nonisolated(unsafe) static var setClipboardText: (@convention(c) (UnsafePointer<CChar>?) -> Bool)!
    nonisolated(unsafe) static var getClipboardText: (@convention(c) () -> UnsafeMutablePointer<CChar>?)!
    nonisolated(unsafe) static var free: (@convention(c) (UnsafeMutableRawPointer?) -> Void)!

    static var lastError: String { error().map { String(cString: $0) } ?? "" }

    // SDL_WindowFlags.
    static let windowFullscreen: UInt64 = 0x1
    static let windowHidden: UInt64 = 0x8
    static let windowBorderless: UInt64 = 0x10
    static let windowResizable: UInt64 = 0x20
    static let windowHighPixelDensity: UInt64 = 0x2000

    /// Before SDL starts: its renderer makes its GL contexts through EGL.
    /// The video driver the environment names (PortMaster sets
    /// SDL_VIDEODRIVER=wayland) is taken out of the environment, as UIKit
    /// does, and reaches Perry's SDL as a hint: an app's own SDL reads the
    /// environment too.
    static func prepareEnvironment() {
        setenv("SDL_VIDEO_FORCE_EGL", "1", 0)
        _ = videoDriver
    }

    nonisolated(unsafe) static let videoDriver: String? = {
        var driver: String?
        for name in ["SDL_VIDEO_DRIVER", "SDL_VIDEODRIVER"] {
            if let value = getenv(name) {
                driver = driver ?? String(cString: value)
                unsetenv(name)
            }
        }
        return driver
    }()

    /// Whether there is a display to open windows on: DISPLAY or
    /// WAYLAND_DISPLAY, unless PERRY_APPKIT_DISPLAY is 0.
    static var wanted: Bool {
        guard getenv("DISPLAY") != nil || getenv("WAYLAND_DISPLAY") != nil else { return false }
        if let setting = getenv("PERRY_APPKIT_DISPLAY"), String(cString: setting) == "0" { return false }
        return true
    }

    nonisolated(unsafe) private static var started: Bool?

    /// SDL bound and its video started, once; false without libSDL3 or a
    /// display.
    static func start() -> Bool {
        if let started { return started }
        prepareEnvironment()
        let result = wanted && load() && initialize(0x20)
        if wanted, !result { appKitWarning("no SDL3 video (\(loaded ? lastError : "libSDL3.so.0 is missing")); windows are not shown") }
        started = result
        return result
    }

    nonisolated(unsafe) private static var loaded = false

    private static func load() -> Bool {
        guard let library = dlopen("libSDL3.so.0", RTLD_NOW) else { return false }
        var complete = true
        func bind<T>(_ name: String) -> T? {
            guard let symbol = dlsym(library, name) else {
                appKitWarning("libSDL3 has no \(name)")
                complete = false
                return nil
            }
            return unsafeBitCast(symbol, to: T.self)
        }
        if let videoDriver, let setHint = dlsym(library, "SDL_SetHint") {
            typealias SetHint = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Bool
            _ = unsafeBitCast(setHint, to: SetHint.self)("SDL_VIDEO_DRIVER", videoDriver)
        }
        initialize = bind("SDL_Init")
        createWindow = bind("SDL_CreateWindow")
        destroyWindow = bind("SDL_DestroyWindow")
        createRenderer = bind("SDL_CreateRenderer")
        destroyRenderer = bind("SDL_DestroyRenderer")
        rendererName = bind("SDL_GetRendererName")
        pollEvent = bind("SDL_PollEvent")
        waitEventTimeout = bind("SDL_WaitEventTimeout")
        error = bind("SDL_GetError")
        windowID = bind("SDL_GetWindowID")
        windowPixelDensity = bind("SDL_GetWindowPixelDensity")
        setWindowSize = bind("SDL_SetWindowSize")
        getWindowSize = bind("SDL_GetWindowSize")
        setWindowPosition = bind("SDL_SetWindowPosition")
        getWindowPosition = bind("SDL_GetWindowPosition")
        setWindowTitle = bind("SDL_SetWindowTitle")
        showWindow = bind("SDL_ShowWindow")
        hideWindow = bind("SDL_HideWindow")
        raiseWindow = bind("SDL_RaiseWindow")
        minimizeWindow = bind("SDL_MinimizeWindow")
        setWindowFullscreen = bind("SDL_SetWindowFullscreen")
        setWindowResizable = bind("SDL_SetWindowResizable")
        setWindowMinimumSize = bind("SDL_SetWindowMinimumSize")
        primaryDisplay = bind("SDL_GetPrimaryDisplay")
        displayBounds = bind("SDL_GetDisplayBounds")
        displayUsableBounds = bind("SDL_GetDisplayUsableBounds")
        desktopDisplayMode = bind("SDL_GetDesktopDisplayMode")
        showCursor = bind("SDL_ShowCursor")
        hideCursor = bind("SDL_HideCursor")
        warpMouseInWindow = bind("SDL_WarpMouseInWindow")
        setRelativeMouseMode = bind("SDL_SetWindowRelativeMouseMode")
        mouseState = bind("SDL_GetMouseState")
        globalMouseState = bind("SDL_GetGlobalMouseState")
        modState = bind("SDL_GetModState")
        startTextInput = bind("SDL_StartTextInput")
        stopTextInput = bind("SDL_StopTextInput")
        showSimpleMessageBox = bind("SDL_ShowSimpleMessageBox")
        setClipboardText = bind("SDL_SetClipboardText")
        getClipboardText = bind("SDL_GetClipboardText")
        free = bind("SDL_free")
        loaded = complete
        return complete
    }

    /// An SDL_Rect's four Int32s as a rectangle.
    static func rect(_ values: [Int32]) -> CGRect {
        CGRect(x: CGFloat(values[0]), y: CGFloat(values[1]), width: CGFloat(values[2]), height: CGFloat(values[3]))
    }

    /// The primary display's bounds and usable bounds, in window
    /// coordinates, top-left origin; and its pixels per coordinate and
    /// refresh rate.
    struct Display {
        var bounds: CGRect
        var usable: CGRect
        var density: CGFloat
        var refreshRate: Double
    }

    static func primary() -> Display? {
        guard start() else { return nil }
        let display = primaryDisplay()
        guard display != 0 else { return nil }
        var bounds = [Int32](repeating: 0, count: 4), usable = [Int32](repeating: 0, count: 4)
        guard displayBounds(display, &bounds) else { return nil }
        if !displayUsableBounds(display, &usable) { usable = bounds }
        var density: CGFloat = 1, rate = 60.0
        if let mode = desktopDisplayMode(display) {
            let modeDensity = CGFloat(mode.load(fromByteOffset: 16, as: Float.self))
            if modeDensity > 0 { density = modeDensity }
            let modeRate = Double(mode.load(fromByteOffset: 20, as: Float.self))
            if modeRate > 0 { rate = modeRate }
        }
        return Display(bounds: rect(bounds), usable: rect(usable), density: density, refreshRate: rate)
    }
}

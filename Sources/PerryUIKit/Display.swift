import CPerryGeometry
import Glibc
import PerryObjCInterop

// The live view: with a display (DISPLAY or WAYLAND_DISPLAY set,
// PERRY_UIKIT_DISPLAY not "0"), the screen is a window showing the visible
// windows, redrawn after each update pass, as touches change things, and
// each frame while QuartzCore's layers change or animate.
// The mouse is a finger: pressing, dragging and releasing it are a touch,
// which Touches delivers; the wheel scrolls. With libSDL3, layers are
// composited on the GPU (Compositor); without it, or with
// PERRY_UIKIT_RENDERER=software, the window is an X11 window drawn in
// software. The libraries are loaded when the first window appears, so
// nothing needs them without a display. PERRY_UIKIT_DISPLAY_SCALE sets the
// window's pixels per point, which is otherwise chosen from the display.

enum Display {
    typealias Pointer = UnsafeMutableRawPointer
    nonisolated(unsafe) private static var started = false
    nonisolated(unsafe) private static var display: Pointer?
    nonisolated(unsafe) private static var window: UInt = 0
    nonisolated(unsafe) private static var gc: Pointer?
    nonisolated(unsafe) private static var image: Pointer?
    nonisolated(unsafe) private static var context: CGRef?
    nonisolated(unsafe) private static var deleteAtom: UInt = 0
    nonisolated(unsafe) private static var dirty = true
    nonisolated(unsafe) private static var lastDraw = 0.0
    /// The most points a screen's short side has: a landscape iPhone's
    /// height, the tallest the iPhone apps Perry runs lay out for.
    static let iPhoneShortSide: CGFloat = 430

    /// Window pixels per point: PERRY_UIKIT_DISPLAY_SCALE, else the native
    /// display's: the desktop's scaling of it, fractional as it may be
    /// (1.25 on a desktop scaled by 125%). An unscaled display (a
    /// handheld's, with no desktop) is paired with a scale as iOS pairs a
    /// screen with one: the least whole scale that gives its usable area's
    /// short side an iPhone's points at most, so a 1080p screen is 640 by
    /// 360 points at @3x rather than 1920 by 1080 at @1x; else 1.
    nonisolated(unsafe) static let scale: CGFloat = {
        let setting = getenv("PERRY_UIKIT_DISPLAY_SCALE").flatMap { Double(String(cString: $0)) }.flatMap { $0 > 0 ? CGFloat($0) : nil }
        // A fixed screen is drawn as large as fits the display, whatever
        // scale the app is told, unless the setting gives its points their
        // pixels: at 1, a @1x screen is drawn pixel for pixel, with nothing
        // scaled.
        if let fixed = Screen.fixed {
            if let setting { return setting }
            guard wanted, let pixels = SDL.usableDisplaySize() else { return fixed.scale }
            return min(pixels.width / fixed.size.width, pixels.height / fixed.size.height)
        }
        if let setting { return setting }
        let software = getenv("PERRY_UIKIT_RENDERER").map { String(cString: $0) == "software" } ?? false
        guard wanted, !software else { return 1 }
        let native = SDL.nativeScale() ?? 1
        guard let pixels = SDL.usableDisplaySize() else { return native }
        let fitting = (min(pixels.width, pixels.height) / iPhoneShortSide).rounded(.up)
        let chosen = native != 1 ? native : max(fitting, 1)
        // An iPhone's screen (PERRY_UIKIT_SCREEN=iphone) is a window that
        // fits the usable area, in quarter steps, however small that makes
        // it: 390 by 844 points is taller than a laptop's display at @3x.
        guard let setting = getenv("PERRY_UIKIT_SCREEN"), String(cString: setting) == "iphone" else { return chosen }
        let screen = Screen.bounds.size
        let fits = min(pixels.width / screen.width, pixels.height / screen.height)
        return min(chosen, max((fits * 4).rounded(.down) / 4, 0.5))
    }()

    private struct X {
        var pending: @convention(c) (Pointer?) -> Int32
        var nextEvent: @convention(c) (Pointer?, Pointer?) -> Int32
        var putImage: @convention(c) (Pointer?, UInt, Pointer?, Pointer?, Int32, Int32, Int32, Int32, UInt32, UInt32) -> Int32
        var flush: @convention(c) (Pointer?) -> Int32
    }
    nonisolated(unsafe) private static var x: X?

    typealias Function = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias DispatchAfter = @convention(c) (UInt64, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Function) -> Void
    typealias DispatchTime = @convention(c) (UInt64, Int64) -> UInt64
    nonisolated(unsafe) static var dispatchAfter: DispatchAfter?
    nonisolated(unsafe) static var dispatchTime: DispatchTime?

    static func load(_ lookup: (String, String) -> UnsafeMutableRawPointer?) {
        let library = "/usr/lib/system/libdispatch.dylib"
        dispatchAfter = lookup(library, "_dispatch_after_f").map { unsafeBitCast($0, to: DispatchAfter.self) }
        dispatchTime = lookup(library, "_dispatch_time").map { unsafeBitCast($0, to: DispatchTime.self) }
    }

    nonisolated(unsafe) private static var compositor: Compositor?
    /// SDL's renderer compositing the live view ("opengles2", "vulkan"…);
    /// nil without one.
    nonisolated(unsafe) static var gpuRenderer: String?

    static var wanted: Bool {
        guard getenv("DISPLAY") != nil || getenv("WAYLAND_DISPLAY") != nil else { return false }
        if let setting = getenv("PERRY_UIKIT_DISPLAY"), String(cString: setting) == "0" { return false }
        return true
    }

    /// Opens the window, once, when a window first shows.
    static func startIfWanted() {
        guard !started, wanted else { return }
        started = true
        // The app's name, as its home screen shows it.
        let title = NSBundle.main().infoObject(forKey: "CFBundleDisplayName")?.stringValue
            ?? NSBundle.main().infoObject(forKey: "CFBundleName")?.stringValue ?? "app"
        let software = getenv("PERRY_UIKIT_RENDERER").map { String(cString: $0) == "software" } ?? false
        SDL.prepareEnvironment()
        if !software, SDL.loadOnce(), let compositor = Compositor(title: title, size: Screen.bounds.size, scale: scale) {
            Display.compositor = compositor
            tick()
            return
        }
        guard let library = dlopen("libX11.so.6", RTLD_NOW) else {
            uikitWarning("no libX11 for the display; running without one")
            return
        }
        func bind<T>(_ name: String, _ type: T.Type) -> T? { dlsym(library, name).map { unsafeBitCast($0, to: T.self) } }
        typealias OpenDisplay = @convention(c) (UnsafePointer<CChar>?) -> Pointer?
        typealias ScreenOf = @convention(c) (Pointer?) -> Int32
        typealias RootWindow = @convention(c) (Pointer?, Int32) -> UInt
        typealias PointerOf = @convention(c) (Pointer?, Int32) -> Pointer?
        typealias DepthOf = @convention(c) (Pointer?, Int32) -> Int32
        typealias CreateWindow = @convention(c) (Pointer?, UInt, Int32, Int32, UInt32, UInt32, UInt32, UInt, UInt) -> UInt
        typealias StoreName = @convention(c) (Pointer?, UInt, UnsafePointer<CChar>?) -> Int32
        typealias SelectInput = @convention(c) (Pointer?, UInt, Int) -> Int32
        typealias MapWindow = @convention(c) (Pointer?, UInt) -> Int32
        typealias InternAtom = @convention(c) (Pointer?, UnsafePointer<CChar>?, Int32) -> UInt
        typealias SetProtocols = @convention(c) (Pointer?, UInt, UnsafeMutablePointer<UInt>?, Int32) -> Int32
        typealias CreateImage = @convention(c) (Pointer?, Pointer?, UInt32, Int32, Int32, Pointer?, UInt32, UInt32, Int32, Int32) -> Pointer?
        guard let open = bind("XOpenDisplay", OpenDisplay.self), let screenOf = bind("XDefaultScreen", ScreenOf.self),
              let root = bind("XRootWindow", RootWindow.self), let visualOf = bind("XDefaultVisual", PointerOf.self),
              let depthOf = bind("XDefaultDepth", DepthOf.self), let gcOf = bind("XDefaultGC", PointerOf.self),
              let create = bind("XCreateSimpleWindow", CreateWindow.self), let storeName = bind("XStoreName", StoreName.self),
              let selectInput = bind("XSelectInput", SelectInput.self), let map = bind("XMapWindow", MapWindow.self),
              let internAtom = bind("XInternAtom", InternAtom.self), let setProtocols = bind("XSetWMProtocols", SetProtocols.self),
              let createImage = bind("XCreateImage", CreateImage.self),
              let pending = bind("XPending", (@convention(c) (Pointer?) -> Int32).self),
              let nextEvent = bind("XNextEvent", (@convention(c) (Pointer?, Pointer?) -> Int32).self),
              let putImage = bind("XPutImage", (@convention(c) (Pointer?, UInt, Pointer?, Pointer?, Int32, Int32, Int32, Int32, UInt32,
                                                                 UInt32) -> Int32).self),
              let flush = bind("XFlush", (@convention(c) (Pointer?) -> Int32).self),
              let display = open(nil) else {
            uikitWarning("cannot open the X display; running without one")
            return
        }
        let screen = screenOf(display)
        let width = Int((Screen.bounds.width * scale).rounded()), height = Int((Screen.bounds.height * scale).rounded())
        let window = create(display, root(display, screen), 0, 0, UInt32(width), UInt32(height), 0, 0, 0)
        _ = title.withCString { storeName(display, window, $0) }
        // Key press, button press and release, pointer motion, exposure.
        _ = selectInput(display, window, 1 << 0 | 1 << 2 | 1 << 3 | 1 << 6 | 1 << 15)
        var atom = "WM_DELETE_WINDOW".withCString { internAtom(display, $0, 0) }
        _ = setProtocols(display, window, &atom, 1)
        deleteAtom = atom
        _ = map(display, window)
        guard let context = CG.makeContext(size: Screen.bounds.size, scale: scale, opaque: true),
              let data = CG.bitmapContextGetData(context),
              let image = createImage(display, visualOf(display, screen), UInt32(depthOf(display, screen)), 2, 0, data,
                                      UInt32(width), UInt32(height), 32, Int32(width * 4)) else { return }
        (Display.display, Display.window, Display.gc, Display.image, Display.context) = (display, window, gcOf(display, screen), image, context)
        x = X(pending: pending, nextEvent: nextEvent, putImage: putImage, flush: flush)
        _ = flush(display)
        tick()
    }

    static func markDirty() { dirty = true }

    /// QuartzCore's layers changed: the live view and the snapshot show it.
    static func layersChanged() {
        dirty = true
        Snapshot.requestWrite()
    }

    /// Turns the live view's text input on while something takes typing.
    static func setTextInput(_ on: Bool) { compositor?.setTextInput(on) }

    /// Whether frames are being shown.
    static var isLive: Bool { x != nil || compositor != nil }

    /// Handles the X events waiting, moves momentum scrolling on, and
    /// redraws when something changed; then again in a sixtieth of a second.
    private static func tick() {
        if let compositor {
            if compositor.handleEvents() { Lifecycle.terminate() }
            ObjCRuntime.autoreleasepool {
                Touches.step()
                Animations.step()
            }
            let now = Clock.now
            // QuartzCore's layers changed, or are animating.
            if QuartzCore.needsDisplay?() == true { dirty = true }
            if dirty || now - lastDraw > 0.5 {
                dirty = false
                lastDraw = now
                ObjCRuntime.autoreleasepool {
                    let windows = Windows.visible
                    for window in windows { window.layoutIfNeeded() }
                    compositor.draw(windows)
                }
            }
        } else if let x, let display {
            var event = [UInt64](repeating: 0, count: 24)
            while x.pending(display) > 0 {
                event.withUnsafeMutableBytes { _ = x.nextEvent(display, $0.baseAddress) }
                ObjCRuntime.autoreleasepool { handle(event) }
            }
            ObjCRuntime.autoreleasepool {
                Touches.step()
                Animations.step()
            }
            let now = Clock.now
            if QuartzCore.needsDisplay?() == true { dirty = true }
            if dirty || now - lastDraw > 0.5 {
                dirty = false
                lastDraw = now
                ObjCRuntime.autoreleasepool { draw() }
            }
        }
        startTimer()
    }

    nonisolated(unsafe) private static var ticker: DisplayTicker?

    /// Ticks sixty times a second from a timer on the main run loop in its
    /// common modes, not from the main queue: an app may run the run loop
    /// inside a block on the main queue (World of Goo 2 waits for frames
    /// so), and the main queue cannot run another block then.
    private static func startTimer() {
        guard ticker == nil else { return }
        let ticker = DisplayTicker()
        Display.ticker = ticker
        typealias Make = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, Double, UnsafeMutableRawPointer?,
                                         UnsafeRawPointer?, UnsafeMutableRawPointer?, Bool) -> UnsafeMutableRawPointer?
        typealias Get = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> UnsafeMutableRawPointer?
        typealias Add = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeMutableRawPointer?,
                                        UnsafeMutableRawPointer?) -> Void
        let timer = unsafeBitCast(ObjCRuntime.msgSend, to: Make.self)(
            ObjCRuntime.classObject("NSTimer"), ObjCRuntime.selector("timerWithTimeInterval:target:selector:userInfo:repeats:"),
            1.0 / 60, ticker.objcObject, ObjCRuntime.selector("_perryTick:"), nil, true)
        let main = unsafeBitCast(ObjCRuntime.msgSend, to: Get.self)(ObjCRuntime.classObject("NSRunLoop"),
                                                                   ObjCRuntime.selector("mainRunLoop"))
        unsafeBitCast(ObjCRuntime.msgSend, to: Add.self)(main, ObjCRuntime.selector("addTimer:forMode:"), timer,
                                                       "kCFRunLoopCommonModes".objCArgument())
    }

    /// The display timer's action.
    static func timerTick() { tick() }

    private static func handle(_ event: [UInt64]) {
        // Xlib's events: a button or motion event's x is eight words in (after
        // type, serial, send_event, display, window, root, subwindow and
        // time), its button 20 bytes after; a client message's data seven.
        let word = MemoryLayout<UInt>.size
        let x = 8 * word, button = x + 20, data = 7 * word
        event.withUnsafeBytes { raw in
            let type = raw.load(fromByteOffset: 0, as: Int32.self)
            func point() -> CGPoint {
                CGPoint(x: CGFloat(raw.load(fromByteOffset: x, as: Int32.self)) / scale,
                        y: CGFloat(raw.load(fromByteOffset: x + 4, as: Int32.self)) / scale)
            }
            switch type {
            case 4: // ButtonPress
                let button = raw.load(fromByteOffset: button, as: UInt32.self)
                switch button {
                case 1: Touches.down(at: point())
                case 4: Touches.wheel(at: point(), by: -40)
                case 5: Touches.wheel(at: point(), by: 40)
                default: break
                }
                dirty = true
            case 5: // ButtonRelease
                if raw.load(fromByteOffset: button, as: UInt32.self) == 1 { Touches.up(at: point()) }
                dirty = true
            case 6: // MotionNotify
                Touches.move(to: point())
            case 12: // Expose
                dirty = true
            case 33: // ClientMessage: the window was closed.
                if raw.load(fromByteOffset: data, as: UInt.self) == deleteAtom { Lifecycle.terminate() }
            default:
                break
            }
        }
    }

    /// Lays out and renders the visible windows into the X window.
    static func draw() {
        guard let context, let x, let display, let image else { return }
        for window in Windows.visible { window.layoutIfNeeded() }
        let black = UIColor.black()
        withExtendedLifetime(black) {
            CG.setFillColorWithColor(context, black.state.makeCGColor())
            CG.fillRect(context, Screen.bounds)
        }
        for window in Windows.visible {
            CG.saveGState(context)
            CG.concatCTM(context, window.state.geometry.toSuperlayer)
            window.state.layer.render(in: context)
            CG.restoreGState(context)
        }
        let width = UInt32((Screen.bounds.width * scale).rounded()), height = UInt32((Screen.bounds.height * scale).rounded())
        _ = x.putImage(display, window, gc, image, 0, 0, 0, 0, width, height)
        _ = x.flush(display)
    }
}

/// Monotonic seconds.
enum Clock {
    static var now: Double {
        var time = timespec()
        clock_gettime(CLOCK_MONOTONIC, &time)
        return Double(time.tv_sec) + Double(time.tv_nsec) / 1e9
    }
}

func uikitWarning(_ message: String) {
    let line = "perry: UIKit: \(message)\n"
    line.withCString { _ = write(2, $0, strlen($0)) }
}

/// Animations the live view runs, a step each frame: each calls its update
/// with its progress, eased, then its completion. Without a live view
/// nothing would show the steps, so an animation ends at once.
enum Animations {
    private struct Running {
        let start: Double
        let duration: Double
        let update: (CGFloat) -> Void
        let completion: () -> Void
    }

    nonisolated(unsafe) private static var running: [Running] = []

    static var live: Bool { Display.isLive }

    static func run(duration: Double, _ update: @escaping (CGFloat) -> Void, completion: @escaping () -> Void) {
        guard live, duration > 0 else {
            update(1)
            completion()
            return
        }
        update(0)
        running.append(Running(start: Clock.now, duration: duration, update: update, completion: completion))
        Display.markDirty()
    }

    static func step() {
        guard !running.isEmpty else { return }
        let now = Clock.now
        let current = running
        running = []
        var finished: [Running] = []
        for animation in current {
            let t = min(max((now - animation.start) / animation.duration, 0), 1)
            // Ease out: fast at first, settling at the end.
            animation.update(CGFloat(1 - pow(1 - t, 3)))
            if t >= 1 { finished.append(animation) } else { running.append(animation) }
        }
        Display.markDirty()
        for animation in finished { animation.completion() }
        if !finished.isEmpty { Updates.schedule() }
    }
}

/// The target of the display's timer.
@ObjCClass("_PerryDisplayTicker")
open class DisplayTicker: NSObject {
    @ObjCMethod("init") public required override init() { super.init() }
    @ObjCMethod("_perryTick:") func tick(_ timer: NSObject?) { Display.timerTick() }
}

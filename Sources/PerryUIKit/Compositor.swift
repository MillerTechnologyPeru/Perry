import CPerryGeometry
import Glibc
import PerryObjCInterop
import SDL3Swift

// The live view on the GPU: an SDL3 window and renderer, whose events are
// touches and typing, and whose frames QuartzCore composites from the
// windows' layers. SDL3Swift draws it; without a display the live view
// draws in software.

/// What UIKit asks of SDL3 before it has a window: the environment its renderer
/// starts in, and the primary display's scale and size.
enum SDLSetup {
    nonisolated(unsafe) private static var prepared = false

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

    /// The hints SDL starts with, given once and before it starts, which is
    /// after the Objective-C runtime is there to name the app.
    private static func applyHints() {
        guard !prepared else { return }
        prepared = true
        if let videoDriver { SDL.setHint("SDL_VIDEO_DRIVER", videoDriver) }
        // The window's Wayland app ID and X11 class: the app's desktop
        // entry's ID (DesktopEntry).
        if let id = DesktopEntry.id { SDL.setHint("SDL_APP_ID", id) }
    }

    /// SDL's video started, with its hints; false without a display.
    static func startVideo() -> Bool {
        prepareEnvironment()
        applyHints()
        return (try? SDL.initialize(subSystems: [.video])) != nil
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

    /// The desktop's scaling of the primary display, as the native display
    /// gives it: its pixels per window coordinate (1.25 on a desktop scaled
    /// by 125%, 2 on a HiDPI one) times its content scale. Starts SDL's
    /// video for the question; nil without a display.
    static func nativeScale() -> CGFloat? {
        guard let display = primaryDisplayStarted() else { return nil }
        let content = CGFloat(display.contentScale)
        let scale = displayDensity(display) * (content > 0 ? content : 1)
        return scale > 0 ? scale : nil
    }

    /// The primary display's pixels per window coordinate: its desktop
    /// mode's pixel density, else 1.
    static func displayDensity() -> CGFloat { primaryDisplayStarted().map(displayDensity) ?? 1 }

    private static func displayDensity(_ display: SDLVideoDisplay) -> CGFloat {
        guard let mode = try? SDLDisplayMode(display: display) else { return 1 }
        let density = CGFloat(mode.pixelDensity)
        return density > 0 ? density : 1
    }

    private static func primaryDisplayStarted() -> SDLVideoDisplay? {
        guard startVideo() else { return nil }
        let display = SDLVideoDisplay.primary
        return display.rawValue != 0 ? display : nil
    }

    /// The primary display's usable area, without the desktop's panels, in
    /// pixels: SDL gives it in window coordinates, which a scaled desktop's
    /// pixel density turns to pixels. Nil without a display.
    static func usableDisplaySize() -> CGSize? {
        guard let display = primaryDisplayStarted(), let rect = try? display.usableBounds, rect.width > 0, rect.height > 0 else { return nil }
        let density = displayDensity(display)
        return CGSize(width: (CGFloat(rect.width) * density).rounded(.down), height: (CGFloat(rect.height) * density).rounded(.down))
    }
}

final class Compositor {
    let window: SDLWindow
    let renderer: SDLRenderer
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
    init?(title: String, size screen: CGSize, scale: CGFloat) {
        // A turned screen's window is turned too.
        let size = Compositor.displayRotation != 0 ? CGSize(width: screen.height, height: screen.width) : screen
        guard SDLSetup.startVideo() else {
            uikitWarning("SDL could not start its video")
            return nil
        }
        // The window is made in window coordinates, the display's pixels
        // over its density, and drawn at its pixel density, so a desktop
        // scaled by a fraction shows it pixel for pixel rather than scaled.
        let estimate = SDLSetup.displayDensity()
        let width = Int((size.width * scale / estimate).rounded()), height = Int((size.height * scale / estimate).rounded())
        var options: BitMaskOptionSet<SDLWindow.Option> = [.highPixelDensity]
        if Screen.isResizable { options.insert(.resizable) }
        let window: SDLWindow, renderer: SDLRenderer
        do {
            window = try SDLWindow(title: title, width: width, height: height, options: options)
            renderer = try SDLRenderer(window: window, driver: SDLRenderer.Driver(name: "opengles2") ?? .default)
        } catch {
            uikitWarning("SDL could not make a window: \(error)")
            return nil
        }
        let density = CGFloat(window.pixelDensity)
        // A compositor that draws the window at another density than the
        // display's has it resized, for the pixels the screen needs.
        if density > 0, abs(density - estimate) > 0.01 {
            window.size = (Int((size.width * scale / density).rounded()), Int((size.height * scale / density).rounded()))
        }
        // The smallest an iPad app's window gets.
        if Screen.isResizable {
            let side = Int32((320 * scale / max(density, 1)).rounded())
            window.setMinimumSize(width: side, height: side)
        }
        (self.window, self.renderer, self.scale) = (window, renderer, scale)
        self.density = density > 0 ? density : 1
        fitted = Screen.fixed != nil
        rendererContext = EAGLContexts.save()
        let name = renderer.name.isEmpty ? "unknown" : renderer.name
        Display.gpuRenderer = name
        uikitWarning("live view composited by SDL's \(name) renderer, at \(scale) pixels a point, \(self.density) a window coordinate")
    }

    /// Destroying a window destroys its renderer, which is not destroyed again.
    deinit { _ = Unmanaged.passRetained(renderer) }

    /// Typed text arrives while text input is on, as for a keyboard on screen.
    func setTextInput(_ on: Bool) {
        _ = on ? try? window.startTextInput() : try? window.stopTextInput()
    }

    /// Whether a fixed screen is fitted to the window: drawn in a viewport
    /// centered in it, at `scale`, with bars beside it.
    private var fitted = false
    /// The window's pixels, and where in them the viewport begins.
    private var output = CGSize.zero
    private var origin = CGPoint.zero

    /// PERRY_UIKIT_DISPLAY_ROTATION, 90 or 270: the screen is shown turned a
    /// quarter clockwise or counterclockwise (QuartzCore's compositor turns
    /// it), so its viewport has its sides exchanged and touches turn back.
    /// Only for a fixed screen (PERRY_UIKIT_SCREEN).
    nonisolated(unsafe) static let displayRotation: Int = {
        guard Screen.fixed != nil,
              let setting = getenv("PERRY_UIKIT_DISPLAY_ROTATION").flatMap({ Int(String(cString: $0)) }) else { return 0 }
        return setting == 90 || setting == 270 || setting == -90 ? (setting + 360) % 360 : 0
    }()

    /// A point on the turned screen as the display shows it, in the app's.
    static func unturned(_ point: CGPoint) -> CGPoint {
        let size = Screen.bounds.size
        switch displayRotation {
        case 90: return CGPoint(x: point.y, y: size.height - point.x)
        case 270: return CGPoint(x: size.width - point.y, y: point.x)
        default: return point
        }
    }

    /// Centers the viewport for the window as it is now.
    private func fit() {
        guard fitted, let (w, h) = renderer.currentOutputSize, w > 0, h > 0 else { return }
        output = CGSize(width: CGFloat(w), height: CGFloat(h))
        var size = Screen.bounds.size
        if Self.displayRotation != 0 { size = CGSize(width: size.height, height: size.width) }
        let width = (size.width * scale).rounded(), height = (size.height * scale).rounded()
        origin = CGPoint(x: ((output.width - width) / 2).rounded(.down), y: ((output.height - height) / 2).rounded(.down))
        try? renderer.setViewport(SDLRect(x: Int32(origin.x), y: Int32(origin.y), width: Int32(width), height: Int32(height)))
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
        var closed = false
        while let event = SDL.pollEvent() {
            /// A mouse event's place, which SDL gives in window coordinates.
            func point(_ x: Float, _ y: Float) -> CGPoint {
                Self.unturned(CGPoint(x: (CGFloat(x) * density - origin.x) / scale, y: (CGFloat(y) * density - origin.y) / scale))
            }
            /// A finger's place: x and y from 0 to 1 across the window.
            func fingerPoint(_ x: Float, _ y: Float) -> CGPoint {
                let x = CGFloat(x), y = CGFloat(y)
                if fitted, output.width > 0 {
                    return Self.unturned(CGPoint(x: (x * output.width - origin.x) / scale, y: (y * output.height - origin.y) / scale))
                }
                let size = Screen.bounds.size
                return CGPoint(x: x * size.width, y: y * size.height)
            }
            switch event {
            case .quit, .window(_, .closeRequested):
                closed = true
            case .window(_, .focusGained):
                Lifecycle.window(focused: true)
            case .window(_, .focusLost):
                Lifecycle.window(focused: false)
            case .window(_, .hidden), .window(_, .minimized):
                Lifecycle.window(visible: false)
            case .window(_, .shown), .window(_, .restored):
                Lifecycle.window(visible: true)
                Display.markDirty()
            case .window(_, .exposed):
                // The window is drawn again.
                Display.markDirty()
            case let .fingerDown(_, _, id, x, y):
                if finger == nil {
                    finger = id.rawValue
                    Touches.down(at: fingerPoint(x, y))
                } else {
                    Touches.down(at: fingerPoint(x, y), finger: id.rawValue)
                }
                Display.markDirty()
            case let .fingerMotion(_, _, id, x, y):
                if finger == id.rawValue { Touches.move(to: fingerPoint(x, y)) } else { Touches.move(to: fingerPoint(x, y), finger: id.rawValue) }
            case let .fingerUp(_, _, id, x, y), let .fingerCanceled(_, _, id, x, y):
                var cancelled = false
                if case .fingerCanceled = event { cancelled = true }
                if finger == id.rawValue {
                    finger = nil
                    Touches.up(at: fingerPoint(x, y))
                } else {
                    Touches.up(at: fingerPoint(x, y), finger: id.rawValue, cancelled: cancelled)
                }
                Display.markDirty()
            case let .mouseMotion(_, which, _, x, y, _, _):
                // The mouse events SDL makes from fingers are left out, as the fingers come themselves.
                guard which != .touch else { break }
                Touches.move(to: point(x, y))
            case let .mouseButtonDown(_, which, button, _, x, y):
                guard which != .touch, button == .left else { break }
                Touches.down(at: point(x, y))
                Display.markDirty()
            case let .mouseButtonUp(_, which, button, _, x, y):
                guard which != .touch, button == .left else { break }
                Touches.up(at: point(x, y))
                Display.markDirty()
            case let .window(_, .pixelSizeChanged(width, height)) where !fitted:
                Screen.resize(to: CGSize(width: CGFloat(width) / scale, height: CGFloat(height) / scale))
                Display.markDirty()
            case let .keyDown(_, _, keycode, _, _):
                switch keycode.rawValue {
                case 0x08: Keyboard.deleteBackward()
                case 0x0D, 0x4000_0058: Keyboard.returnKey()   // return, keypad enter
                case 0x1B: Keyboard.escape()
                default: break
                }
            case let .textInput(_, text):
                Keyboard.insert(text)
            case let .mouseWheel(_, _, _, y, isFlipped, mouseX, mouseY):
                // Positive y scrolls up, unless flipped.
                let up = CGFloat(y) * (isFlipped ? -1 : 1)
                Touches.wheel(at: CGPoint(x: CGFloat(mouseX) / scale, y: CGFloat(mouseY) / scale), by: -up * 40)
                Display.markDirty()
            default:
                Display.markDirty()
            }
        }
        GamepadTouch.poll()
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
        _ = QuartzCore.withRoots(windows) { QuartzCore.composite?(UnsafeMutableRawPointer(renderer.unsafePointer), Double(scale), $0, $1) }
        // The renderer's context was current while it drew; the app's is
        // again.
        EAGLContexts.restore()
    }
}

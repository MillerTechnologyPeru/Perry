import CPerryGeometry
import Glibc
import SDL3Swift

// SDL3's display and start-up, as AppKit's windows, events, cursor and
// screens need them. SDL's video starts when the first window or screen is
// asked for, so nothing needs a display before. SDL's window coordinates
// are AppKit's points: a window's pixels per coordinate is its backing
// scale.

enum SDLSession {
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

    /// SDL's video started, once; false without a display.
    static func start() -> Bool {
        if let started { return started }
        prepareEnvironment()
        var result = false
        if wanted {
            if let videoDriver { SDL.setHint("SDL_VIDEO_DRIVER", videoDriver) }
            do {
                try SDL.initialize(subSystems: [.video])
                result = true
            } catch {
                appKitWarning("no SDL3 video (\(error)); windows are not shown")
            }
        }
        started = result
        return result
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

    private static func rect(_ rect: SDLRect) -> CGRect {
        CGRect(x: CGFloat(rect.x), y: CGFloat(rect.y), width: CGFloat(rect.width), height: CGFloat(rect.height))
    }

    static func primary() -> Display? {
        guard start() else { return nil }
        let display = SDLVideoDisplay.primary
        guard display.rawValue != 0, let bounds = try? display.bounds else { return nil }
        let usable = (try? display.usableBounds) ?? bounds
        var density: CGFloat = 1, rate = 60.0
        if let mode = try? SDLDisplayMode(display: display) {
            if mode.pixelDensity > 0 { density = CGFloat(mode.pixelDensity) }
            if mode.refreshRate > 0 { rate = mode.refreshRate }
        }
        return Display(bounds: rect(bounds), usable: rect(usable), density: density, refreshRate: rate)
    }
}

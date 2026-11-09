import CPerryGeometry
import Glibc
import PerryObjCInterop

/// A game pad that plays a touch game: PERRY_UIKIT_GAMEPAD_TOUCH names a text
/// file that says where on the screen each stick and button touches, and
/// the first game pad SDL finds works those places as fingers, all at once,
/// as a player's thumbs and fingers do.
///
/// The file has one setting a line, with # for comments; places are
/// fractions of the screen, across from the left and down from the top:
///
///     stick left move 0.18 0.70 0.10      # the touch moves from this place by up to
///                                         # 0.10 of the screen's height
///     stick right look 0.80 0.60 0.20 0.9 # the touch starts here and is dragged as fast
///                                         # as the stick is pushed (up to 0.9 screen
///                                         # heights a second), and starts again when
///                                         # it has gone 0.20 from here
///     button a 0.90 0.60                  # a tap while A is held
///
/// Buttons are a, b, x, y, back, start, l3, r3, l1, r1, up, down, left,
/// right, l2 and r2.
enum GamepadTouch {
    private enum Mode { case move, look }

    private struct Stick {
        var horizontal: Int32, vertical: Int32
        var mode: Mode
        var center: CGPoint
        var radius: CGFloat
        var speed: CGFloat
        var position = CGPoint.zero
        var finger: UInt64?
    }

    private struct Button {
        var index: Int32
        var place: CGPoint
        var finger: UInt64?
    }

    private static let path: String? = getenv("PERRY_UIKIT_GAMEPAD_TOUCH").map { String(cString: $0) }

    nonisolated(unsafe) private static var sticks: [Stick] = []
    nonisolated(unsafe) private static var buttons: [Button] = []
    nonisolated(unsafe) private static var started = false
    nonisolated(unsafe) private static var lastTime = 0.0
    nonisolated(unsafe) private static var lastSearch = 0.0

    // MARK: SDL's game pads

    private typealias GetGamepads = @convention(c) (UnsafeMutablePointer<Int32>?) -> UnsafeMutablePointer<UInt32>?
    private typealias OpenGamepad = @convention(c) (UInt32) -> UnsafeMutableRawPointer?
    private typealias GetAxis = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Int16
    private typealias GetButton = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Bool
    private typealias Free = @convention(c) (UnsafeMutableRawPointer?) -> Void

    nonisolated(unsafe) private static var getGamepads: GetGamepads?
    nonisolated(unsafe) private static var openGamepad: OpenGamepad?
    nonisolated(unsafe) private static var getAxis: GetAxis?
    nonisolated(unsafe) private static var getButton: GetButton?
    nonisolated(unsafe) private static var sdlFree: Free?
    nonisolated(unsafe) private static var gamepad: UnsafeMutableRawPointer?

    // SDL_GamepadAxis and SDL_GamepadButton.
    private static let axes: [String: Int32] = ["l2": 4, "r2": 5]
    private static let buttonIndexes: [String: Int32] = [
        "a": 0, "b": 1, "x": 2, "y": 3, "back": 4, "start": 6, "l3": 7, "r3": 8, "l1": 9, "r1": 10,
        "up": 11, "down": 12, "left": 13, "right": 14,
    ]

    private static func start() -> Bool {
        started = true
        guard let path, let library = dlopen("libSDL3.so.0", RTLD_NOW) else { return false }
        typealias Initialize = @convention(c) (UInt32) -> Bool
        typealias SetHint = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Bool
        guard let initialize = dlsym(library, "SDL_InitSubSystem").map({ unsafeBitCast($0, to: Initialize.self) }),
              let get = dlsym(library, "SDL_GetGamepads"), let open = dlsym(library, "SDL_OpenGamepad"),
              let axis = dlsym(library, "SDL_GetGamepadAxis"), let button = dlsym(library, "SDL_GetGamepadButton") else {
            uikitWarning("GamepadTouch: SDL has no game pad functions")
            return false
        }
        // The pad is read while another window has the keyboard, as it is
        // when the game's window is behind a front end's.
        if let hint = dlsym(library, "SDL_SetHint").map({ unsafeBitCast($0, to: SetHint.self) }) {
            _ = hint("SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS", "1")
        }
        getGamepads = unsafeBitCast(get, to: GetGamepads.self)
        openGamepad = unsafeBitCast(open, to: OpenGamepad.self)
        getAxis = unsafeBitCast(axis, to: GetAxis.self)
        getButton = unsafeBitCast(button, to: GetButton.self)
        sdlFree = dlsym(library, "SDL_free").map { unsafeBitCast($0, to: Free.self) }
        // SDL_INIT_GAMEPAD.
        guard initialize(0x2000) else {
            uikitWarning("GamepadTouch: SDL could not start its game pads")
            return false
        }
        guard parse(path) else {
            uikitWarning("GamepadTouch: no places in \(path)")
            return false
        }
        uikitWarning("GamepadTouch: \(sticks.count) sticks and \(buttons.count) buttons from \(path)")
        return true
    }

    private static func parse(_ path: String) -> Bool {
        guard let file = fopen(path, "r") else { return false }
        defer { fclose(file) }
        var line: UnsafeMutablePointer<CChar>?
        var capacity = 0
        defer { Glibc.free(line) }
        while getline(&line, &capacity, file) >= 0, let line {
            var text = String(cString: line)
            if let comment = text.firstIndex(of: "#") { text = String(text[..<comment]) }
            let words = text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }).map(String.init)
            switch words.first {
            case "stick" where words.count >= 6:
                // stick <left|right> <move|look> <x> <y> <radius> [speed]
                let numbers = words.dropFirst(3).compactMap { Double($0) }.map { CGFloat($0) }
                guard words[1] == "left" || words[1] == "right", numbers.count >= 3 else { continue }
                sticks.append(Stick(horizontal: words[1] == "left" ? 0 : 2, vertical: words[1] == "left" ? 1 : 3,
                                    mode: words[2] == "look" ? .look : .move, center: CGPoint(x: numbers[0], y: numbers[1]),
                                    radius: numbers[2], speed: numbers.count > 3 ? numbers[3] : 1))
            case "button" where words.count >= 4:
                // button <name> <x> <y>
                let numbers = words.dropFirst(2).compactMap { Double($0) }.map { CGFloat($0) }
                let name = words[1].lowercased()
                guard numbers.count >= 2 else { continue }
                let place = CGPoint(x: numbers[0], y: numbers[1])
                if let index = buttonIndexes[name] {
                    buttons.append(Button(index: index, place: place))
                } else if let trigger = axes[name] {
                    buttons.append(Button(index: 100 + trigger - 4, place: place))
                }
            default:
                break
            }
        }
        return !sticks.isEmpty || !buttons.isEmpty
    }

    // MARK: Fingers

    /// The fingers down now, by number: the first goes through the
    /// primary touch, the others through UIKit's other fingers.
    nonisolated(unsafe) private static var primary: UInt64?
    nonisolated(unsafe) private static var nextFinger: UInt64 = 0x6770_0000

    private static func screenPoint(_ fraction: CGPoint) -> CGPoint {
        let size = Screen.bounds.size
        return CGPoint(x: fraction.x * size.width, y: fraction.y * size.height)
    }

    private static func touchDown(at point: CGPoint) -> UInt64 {
        nextFinger += 1
        let id = nextFinger
        if primary == nil {
            primary = id
            Touches.down(at: point)
        } else {
            Touches.down(at: point, finger: id)
        }
        return id
    }

    private static func touchMove(_ id: UInt64, to point: CGPoint) {
        if primary == id { Touches.move(to: point) } else { Touches.move(to: point, finger: id) }
    }

    private static func touchUp(_ id: UInt64, at point: CGPoint) {
        if primary == id {
            primary = nil
            Touches.up(at: point)
        } else {
            Touches.up(at: point, finger: id)
        }
    }

    // MARK: Each frame

    /// The first game pad, found again each second while there is none.
    private static func find() {
        let now = Clock.now
        guard gamepad == nil, now - lastSearch >= 1 else { return }
        lastSearch = now
        var count: Int32 = 0
        guard let list = getGamepads?(&count), count > 0 else { return }
        gamepad = openGamepad?(list[0])
        sdlFree?(UnsafeMutableRawPointer(list))
    }

    /// Reads the pad and moves the fingers; called as the window's events
    /// are read, once a frame.
    static func poll() {
        guard path != nil else { return }
        if !started, !start() { return }
        if sticks.isEmpty && buttons.isEmpty { return }
        find()
        guard let pad = gamepad, let getAxis, let getButton else { return }
        let now = Clock.now
        let elapsed = lastTime == 0 ? 0 : min(now - lastTime, 0.1)
        lastTime = now
        let size = Screen.bounds.size

        for index in sticks.indices {
            var stick = sticks[index]
            let x = CGFloat(getAxis(pad, stick.horizontal)) / 32767, y = CGFloat(getAxis(pad, stick.vertical)) / 32767
            let length = (x * x + y * y).squareRoot()
            // Inside the dead zone the stick is let go; outside, its push
            // is scaled from there to the edge.
            let dead: CGFloat = 0.2
            let push = length > dead ? min((length - dead) / (1 - dead), 1) : 0
            let (px, py) = length > 0 ? (x / length * push, y / length * push) : (0, 0)
            let center = screenPoint(stick.center)
            switch stick.mode {
            case .move:
                if push > 0 {
                    let target = CGPoint(x: center.x + px * stick.radius * size.height, y: center.y + py * stick.radius * size.height)
                    if let finger = stick.finger { touchMove(finger, to: target) } else { stick.finger = touchDown(at: target) }
                    stick.position = target
                } else if let finger = stick.finger {
                    touchUp(finger, at: stick.position)
                    stick.finger = nil
                }
            case .look:
                if push > 0 {
                    if stick.finger == nil {
                        stick.position = center
                        stick.finger = touchDown(at: center)
                    }
                    let step = stick.speed * size.height * elapsed
                    stick.position = CGPoint(x: stick.position.x + px * step, y: stick.position.y + py * step)
                    if let finger = stick.finger {
                        let dx = stick.position.x - center.x, dy = stick.position.y - center.y
                        if (dx * dx + dy * dy).squareRoot() > stick.radius * size.height {
                            // Out of room: lifted, and down again in the middle.
                            touchUp(finger, at: stick.position)
                            stick.position = center
                            stick.finger = touchDown(at: center)
                        } else {
                            touchMove(finger, to: stick.position)
                        }
                    }
                } else if let finger = stick.finger {
                    touchUp(finger, at: stick.position)
                    stick.finger = nil
                }
            }
            sticks[index] = stick
        }

        for index in buttons.indices {
            var button = buttons[index]
            let pressed: Bool
            if button.index >= 100 {
                pressed = getAxis(pad, button.index - 100 + 4) > 16000
            } else {
                pressed = getButton(pad, button.index)
            }
            let point = screenPoint(button.place)
            if pressed, button.finger == nil {
                button.finger = touchDown(at: point)
            } else if !pressed, let finger = button.finger {
                touchUp(finger, at: point)
                button.finger = nil
            }
            buttons[index] = button
        }
    }
}

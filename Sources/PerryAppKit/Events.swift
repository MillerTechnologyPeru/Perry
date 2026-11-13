import CPerryGeometry
import Glibc
import PerryObjCInterop
import SDL3Swift

// SDL's events, taken while the application waits for one: the mouse and
// keyboard become NSEvents on the application's queue; window changes go
// to the window. SDL's text input, which follows the key that typed it,
// becomes that key event's characters, as a Mac keyboard layout types
// them. Closing the last window or quitting from the desktop sends
// -terminate:.

enum Events {
    /// SDL's mice that have scrolled by fractions: touchpads.
    nonisolated(unsafe) private static var preciseDevices: Set<UInt32> = []
    /// The modifier keys down at the last key event, for flags-changed events.
    nonisolated(unsafe) private static var modifiers: UInt = 0

    /// Takes every SDL event waiting.
    static func pump() {
        guard SDLSession.start(), let app = App.shared else { return }
        while let event = SDL.pollEvent() { handle(event, app) }
    }

    private static func handle(_ event: SDLEvent, _ app: NSApplication) {
        func enqueue(_ event: NSEvent) { app.queue.append(event) }
        /// A mouse event SDL made from a touch (its mouse is
        /// SDL_TOUCH_MOUSEID) is NSEventSubtypeTouch's.
        func markTouch(_ event: NSEvent, _ which: MouseID) {
            if which == .touch { event.subtype = 3 }
        }
        /// A mouse event's place, SDL's top-left window coordinates in the
        /// window's base coordinates.
        func location(_ x: Float, _ y: Float, in window: NSWindow?) -> CGPoint {
            CGPoint(x: CGFloat(x), y: (window?.frame.height ?? 0) - CGFloat(y))
        }
        switch event {
        case .quit:
            Trace.log("quit requested")
            Send.void(app.objcObject, "terminate:", nil)
        case let .window(id, change):
            let window = Windows.shown(sdl: id)
            switch change {
            case .closeRequested:
                guard let window else { break }
                Send.void(window.objcObject, "performClose:", nil)
            case .focusGained: window?.sdlFocus(true)
            case .focusLost: window?.sdlFocus(false)
            case .minimized: window?.sdlMinimized(true)
            case .restored, .shown: window?.sdlMinimized(false)
            case .moved, .resized: window?.sdlWindowChanged()
            case .pixelSizeChanged:
                window?.updateBackingScale()
                Windows.layersChanged()
            case .exposed: Windows.layersChanged()
            case .hidden, .maximized: break
            }
        case let .mouseMotion(id, which, buttons, x, y, relativeX, relativeY):
            let window = Windows.shown(sdl: id)
            let buttons = buttons.rawValue
            let kind: EventType = buttons & 0x1 != 0 ? .leftMouseDragged : buttons & 0x4 != 0 ? .rightMouseDragged
                : buttons & ~UInt32(0x5) != 0 ? .otherMouseDragged : .mouseMoved
            let ns = NSEvent(kind, window: window, location: location(x, y, in: window))
            ns.deltaX = CGFloat(relativeX)
            ns.deltaY = CGFloat(relativeY)
            ns.buttonNumber = kind == .rightMouseDragged ? 1 : kind == .otherMouseDragged ? 2 : 0
            markTouch(ns, which)
            enqueue(ns)
        case let .mouseButtonDown(id, which, button, clicks, x, y), let .mouseButtonUp(id, which, button, clicks, x, y):
            let window = Windows.shown(sdl: id)
            var down = false
            if case .mouseButtonDown = event { down = true }
            // SDL's buttons: left 1, middle 2, right 3, then X1 and X2;
            // AppKit's numbers: left 0, right 1, middle 2, then 3 and 4.
            let sdlButton = Int(button.rawValue)
            let number = [1: 0, 2: 2, 3: 1][sdlButton] ?? sdlButton - 1
            let bit: UInt = 1 << UInt(max(number, 0))
            if down { MouseButtons.pressed |= bit } else { MouseButtons.pressed &= ~bit }
            let kind: EventType = number == 0 ? (down ? .leftMouseDown : .leftMouseUp)
                : number == 1 ? (down ? .rightMouseDown : .rightMouseUp) : (down ? .otherMouseDown : .otherMouseUp)
            let ns = NSEvent(kind, window: window, location: location(x, y, in: window))
            ns.buttonNumber = number
            ns.clickCount = Int(clicks)
            markTouch(ns, which)
            enqueue(ns)
        case let .mouseWheel(id, which, wheelX, wheelY, flipped, mouseX, mouseY):
            let window = Windows.shown(sdl: id)
            let sign: CGFloat = flipped ? -1 : 1
            let x = CGFloat(wheelX), y = CGFloat(wheelY)
            // A wheel turns in whole notches, lines; a touchpad scrolls in
            // fractions of one, tenths of its points (SDL's unit is ten
            // pixels). A device that has scrolled a fraction is precise.
            let mouse = which.rawValue
            if x != x.rounded() || y != y.rounded() { preciseDevices.insert(mouse) }
            let precise = preciseDevices.contains(mouse)
            let ns = NSEvent(.scrollWheel, window: window, location: location(mouseX, mouseY, in: window))
            ns.deltaX = -x * sign
            ns.deltaY = y * sign
            ns.hasPreciseScrollingDeltas = precise
            ns.scrollingDeltaX = precise ? ns.deltaX * 10 : ns.deltaX
            ns.scrollingDeltaY = precise ? ns.deltaY * 10 : ns.deltaY
            ns.isDirectionInvertedFromDevice = flipped
            // Wheel events waiting together are one scroll, as AppKit
            // coalesces them: a fast spin redraws once.
            if let last = app.queue.last, last.type == .scrollWheel, last.window === ns.window,
               last.hasPreciseScrollingDeltas == precise, last.subtype == ns.subtype {
                (last.deltaX, last.deltaY) = (last.deltaX + ns.deltaX, last.deltaY + ns.deltaY)
                (last.scrollingDeltaX, last.scrollingDeltaY) = (last.scrollingDeltaX + ns.scrollingDeltaX, last.scrollingDeltaY + ns.scrollingDeltaY)
                break
            }
            enqueue(ns)
        case let .keyDown(id, scancode, keycode, modifiers, isRepeat), let .keyUp(id, scancode, keycode, modifiers, isRepeat):
            let window = Windows.shown(sdl: id)
            var isDown = false
            if case .keyDown = event { isDown = true }
            let scancode = scancode.rawValue, keycode = keycode.rawValue
            let flags = ModifierFlags.from(modifiers.rawValue)
            let code = KeyCodes.byScancode[scancode] ?? 0xFFFF
            let location = window.map { $0.mouseLocationOutsideOfEventStream() } ?? .zero
            if KeyCodes.isModifier(scancode) {
                guard flags != Events.modifiers else { break }
                Events.modifiers = flags
                let ns = NSEvent(.flagsChanged, window: window ?? Windows.key, location: location)
                ns.keyCode = code
                ns.modifierFlags = flags
                enqueue(ns)
                break
            }
            Events.modifiers = flags
            let ns = NSEvent(isDown ? .keyDown : .keyUp, window: window ?? Windows.key, location: location)
            ns.keyCode = code
            ns.modifierFlags = flags | (code >= 0x7B && code <= 0x7E ? ModifierFlags.numericPad | ModifierFlags.function : 0)
            let characters = KeyCodes.characters(scancode: scancode, keycode: keycode, shifted: flags & ModifierFlags.shift != 0)
            ns.characters = characters.typed
            ns.charactersIgnoringModifiers = characters.plain
            ns.isARepeat = isRepeat
            enqueue(ns)
        case let .textInput(_, text):
            guard !text.isEmpty, let last = app.queue.last(where: { $0.type == .keyDown }), !last.typedText else { break }
            last.characters = text
            last.typedText = true
        default:
            break
        }
    }
}

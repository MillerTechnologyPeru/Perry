import CPerryGeometry
import Glibc
import PerryObjCInterop

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
        guard SDL.start(), let app = App.shared else { return }
        var event = [UInt64](repeating: 0, count: 16)
        while event.withUnsafeMutableBytes({ SDL.pollEvent($0.baseAddress) }) {
            event.withUnsafeBytes { handle($0, app) }
        }
    }

    private static func handle(_ raw: UnsafeRawBufferPointer, _ app: NSApplication) {
        let type = raw.load(fromByteOffset: 0, as: UInt32.self)
        let window = Windows.shown(sdl: raw.load(fromByteOffset: 16, as: UInt32.self))
        func enqueue(_ event: NSEvent) { app.queue.append(event) }
        /// A mouse event SDL made from a touch (its mouse is
        /// SDL_TOUCH_MOUSEID) is NSEventSubtypeTouch's.
        func markTouch(_ event: NSEvent) {
            if raw.load(fromByteOffset: 20, as: UInt32.self) == 0xFFFF_FFFF { event.subtype = 3 }
        }
        /// A mouse event's place, SDL's top-left window coordinates in the
        /// window's base coordinates.
        func location(_ x: Int, _ y: Int) -> CGPoint {
            let px = CGFloat(raw.load(fromByteOffset: x, as: Float.self)), py = CGFloat(raw.load(fromByteOffset: y, as: Float.self))
            return CGPoint(x: px, y: (window?.frame.height ?? 0) - py)
        }
        switch type {
        case 0x100: // quit
            Trace.log("quit requested")
            Send.void(app.objcObject, "terminate:", nil)
        case 0x210: // window close requested
            guard let window else { break }
            Send.void(window.objcObject, "performClose:", nil)
        case 0x20E, 0x20F: // focus gained, lost
            window?.sdlFocus(type == 0x20E)
        case 0x209: // minimized
            window?.sdlMinimized(true)
        case 0x20B, 0x202: // restored, shown
            window?.sdlMinimized(false)
        case 0x205, 0x206: // moved, resized
            window?.sdlWindowChanged()
        case 0x207: // pixel size changed
            window?.updateBackingScale()
            Windows.layersChanged()
        case 0x204: // exposed
            Windows.layersChanged()
        case 0x400: // mouse motion: mouse at 20, buttons at 24, x and y at 28 and 32, relative at 36 and 40
            let buttons = raw.load(fromByteOffset: 24, as: UInt32.self)
            let kind: EventType = buttons & 0x1 != 0 ? .leftMouseDragged : buttons & 0x4 != 0 ? .rightMouseDragged
                : buttons & ~UInt32(0x5) != 0 ? .otherMouseDragged : .mouseMoved
            let ns = NSEvent(kind, window: window, location: location(28, 32))
            ns.deltaX = CGFloat(raw.load(fromByteOffset: 36, as: Float.self))
            ns.deltaY = CGFloat(raw.load(fromByteOffset: 40, as: Float.self))
            ns.buttonNumber = kind == .rightMouseDragged ? 1 : kind == .otherMouseDragged ? 2 : 0
            markTouch(ns)
            enqueue(ns)
        case 0x401, 0x402: // button down, up: mouse at 20, button at 24, clicks at 26
            let down = type == 0x401
            // SDL's buttons: left 1, middle 2, right 3, then X1 and X2;
            // AppKit's numbers: left 0, right 1, middle 2, then 3 and 4.
            let sdlButton = Int(raw.load(fromByteOffset: 24, as: UInt8.self))
            let number = [1: 0, 2: 2, 3: 1][sdlButton] ?? sdlButton - 1
            let bit: UInt = 1 << UInt(max(number, 0))
            if down { MouseButtons.pressed |= bit } else { MouseButtons.pressed &= ~bit }
            let kind: EventType = number == 0 ? (down ? .leftMouseDown : .leftMouseUp)
                : number == 1 ? (down ? .rightMouseDown : .rightMouseUp) : (down ? .otherMouseDown : .otherMouseUp)
            let ns = NSEvent(kind, window: window, location: location(28, 32))
            ns.buttonNumber = number
            ns.clickCount = Int(raw.load(fromByteOffset: 26, as: UInt8.self))
            markTouch(ns)
            enqueue(ns)
        case 0x403: // wheel: mouse at 20, x and y at 24 and 28, direction at 32, mouse at 36 and 40
            let flipped = raw.load(fromByteOffset: 32, as: UInt32.self) == 1
            let sign: CGFloat = flipped ? -1 : 1
            let x = CGFloat(raw.load(fromByteOffset: 24, as: Float.self)), y = CGFloat(raw.load(fromByteOffset: 28, as: Float.self))
            // A wheel turns in whole notches, lines; a touchpad scrolls in
            // fractions of one, tenths of its points (SDL's unit is ten
            // pixels). A device that has scrolled a fraction is precise.
            let mouse = raw.load(fromByteOffset: 20, as: UInt32.self)
            if x != x.rounded() || y != y.rounded() { preciseDevices.insert(mouse) }
            let precise = preciseDevices.contains(mouse)
            let ns = NSEvent(.scrollWheel, window: window, location: location(36, 40))
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
        case 0x300, 0x301: // key down, up: scancode at 24, keycode at 28, modifiers at 32, repeat at 37
            let scancode = raw.load(fromByteOffset: 24, as: UInt32.self)
            let keycode = raw.load(fromByteOffset: 28, as: UInt32.self)
            let flags = ModifierFlags.from(raw.load(fromByteOffset: 32, as: UInt16.self))
            let code = KeyCodes.byScancode[scancode] ?? 0xFFFF
            let location = window.map { $0.mouseLocationOutsideOfEventStream() } ?? .zero
            if KeyCodes.isModifier(scancode) {
                guard flags != modifiers else { break }
                modifiers = flags
                let ns = NSEvent(.flagsChanged, window: window ?? Windows.key, location: location)
                ns.keyCode = code
                ns.modifierFlags = flags
                enqueue(ns)
                break
            }
            modifiers = flags
            let ns = NSEvent(type == 0x300 ? .keyDown : .keyUp, window: window ?? Windows.key, location: location)
            ns.keyCode = code
            ns.modifierFlags = flags | (code >= 0x7B && code <= 0x7E ? ModifierFlags.numericPad | ModifierFlags.function : 0)
            let characters = KeyCodes.characters(scancode: scancode, keycode: keycode, shifted: flags & ModifierFlags.shift != 0)
            ns.characters = characters.typed
            ns.charactersIgnoringModifiers = characters.plain
            ns.isARepeat = raw.load(fromByteOffset: 37, as: Bool.self)
            enqueue(ns)
        case 0x303: // text input: UTF-8 at 24
            guard let text = raw.load(fromByteOffset: 24, as: UnsafePointer<CChar>?.self).map({ String(cString: $0) }), !text.isEmpty,
                  let last = app.queue.last(where: { $0.type == .keyDown }), !last.typedText else { break }
            last.characters = text
            last.typedText = true
        default:
            break
        }
    }
}

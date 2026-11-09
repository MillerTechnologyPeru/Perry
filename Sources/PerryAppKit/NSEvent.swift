import CPerryGeometry
import Glibc
import PerryObjCInterop

// NSEvent: AppKit's events, made from SDL's as the application asks for
// them. Keys carry the Mac's virtual key codes (kVK_…) and the characters
// a Mac keyboard types, with AppKit's function-key characters for the keys
// that type none; modifier flags carry the device-dependent left and right
// bits too, as games read them. Points are in the window's base
// coordinates, origin at the bottom left.

/// NSEventType.
enum EventType: UInt {
    case leftMouseDown = 1, leftMouseUp, rightMouseDown, rightMouseUp, mouseMoved, leftMouseDragged, rightMouseDragged
    case mouseEntered, mouseExited, keyDown, keyUp, flagsChanged, appKitDefined, systemDefined, applicationDefined
    case periodic, cursorUpdate
    case scrollWheel = 22
    case otherMouseDown = 25, otherMouseUp, otherMouseDragged

    var mask: UInt64 { 1 << UInt64(rawValue) }
    var isMouse: Bool {
        switch self {
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .mouseMoved, .leftMouseDragged, .rightMouseDragged,
             .mouseEntered, .mouseExited, .scrollWheel, .otherMouseDown, .otherMouseUp, .otherMouseDragged, .cursorUpdate:
            return true
        default:
            return false
        }
    }
    var isKey: Bool { self == .keyDown || self == .keyUp || self == .flagsChanged }
}

/// NSEventModifierFlags, with the device-dependent bits of each side.
enum ModifierFlags {
    static let capsLock: UInt = 1 << 16
    static let shift: UInt = 1 << 17
    static let control: UInt = 1 << 18
    static let option: UInt = 1 << 19
    static let command: UInt = 1 << 20
    static let numericPad: UInt = 1 << 21
    static let function: UInt = 1 << 23
    static let deviceIndependent: UInt = 0xffff_0000

    /// From SDL_Keymod.
    static func from(_ mod: UInt16) -> UInt {
        var flags: UInt = 0
        if mod & 0x0001 != 0 { flags |= shift | 0x02 }      // left shift, NX_DEVICELSHIFTKEYMASK
        if mod & 0x0002 != 0 { flags |= shift | 0x04 }      // right shift
        if mod & 0x0040 != 0 { flags |= control | 0x01 }    // left control
        if mod & 0x0080 != 0 { flags |= control | 0x2000 }  // right control
        if mod & 0x0100 != 0 { flags |= option | 0x20 }     // left option (alt)
        if mod & 0x0200 != 0 { flags |= option | 0x40 }     // right option
        if mod & 0x0400 != 0 { flags |= command | 0x08 }    // left command (super)
        if mod & 0x0800 != 0 { flags |= command | 0x10 }    // right command
        if mod & 0x2000 != 0 { flags |= capsLock }
        return flags
    }
}

/// SDL scancodes (USB usages) to the Mac's virtual key codes.
enum KeyCodes {
    nonisolated(unsafe) static let byScancode: [UInt32: UInt16] = {
        var map: [UInt32: UInt16] = [:]
        // A to Z, scancodes 4 to 29.
        let letters: [UInt16] = [0x00, 0x0B, 0x08, 0x02, 0x0E, 0x03, 0x05, 0x04, 0x22, 0x26, 0x28, 0x25, 0x2E,
                                 0x2D, 0x1F, 0x23, 0x0C, 0x0F, 0x01, 0x11, 0x20, 0x09, 0x0D, 0x07, 0x10, 0x06]
        for (index, code) in letters.enumerated() { map[UInt32(4 + index)] = code }
        // 1 to 9, then 0: scancodes 30 to 39.
        let digits: [UInt16] = [0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19, 0x1D]
        for (index, code) in digits.enumerated() { map[UInt32(30 + index)] = code }
        let others: [(UInt32, UInt16)] = [
            (40, 0x24), (41, 0x35), (42, 0x33), (43, 0x30), (44, 0x31),        // return, escape, backspace, tab, space
            (45, 0x1B), (46, 0x18), (47, 0x21), (48, 0x1E), (49, 0x2A),        // - = [ ] backslash
            (50, 0x2A), (51, 0x29), (52, 0x27), (53, 0x32), (54, 0x2B),        // non-US #, ; ' ` ,
            (55, 0x2F), (56, 0x2C), (57, 0x39),                                // . / caps lock
            (58, 0x7A), (59, 0x78), (60, 0x63), (61, 0x76), (62, 0x60), (63, 0x61),   // F1 to F6
            (64, 0x62), (65, 0x64), (66, 0x65), (67, 0x6D), (68, 0x67), (69, 0x6F),   // F7 to F12
            (70, 0x69), (71, 0x6B), (72, 0x71),                                // print screen, scroll lock, pause: F13 to F15
            (73, 0x72), (74, 0x73), (75, 0x74), (76, 0x75), (77, 0x77), (78, 0x79),   // insert (help), home, page up, delete, end, page down
            (79, 0x7C), (80, 0x7B), (81, 0x7D), (82, 0x7E),                    // right, left, down, up
            (83, 0x47), (84, 0x4B), (85, 0x43), (86, 0x4E), (87, 0x45), (88, 0x4C),   // keypad clear / * - + enter
            (89, 0x53), (90, 0x54), (91, 0x55), (92, 0x56), (93, 0x57), (94, 0x58),   // keypad 1 to 6
            (95, 0x59), (96, 0x5B), (97, 0x5C), (98, 0x52), (99, 0x41),        // keypad 7 to 9, 0, .
            (100, 0x0A), (103, 0x51),                                          // ISO §, keypad =
            (104, 0x69), (105, 0x6B), (106, 0x71), (107, 0x6A), (108, 0x40), (109, 0x4F), (110, 0x50), // F13 to F19
            (224, 0x3B), (225, 0x38), (226, 0x3A), (227, 0x37),                // left control, shift, option, command
            (228, 0x3E), (229, 0x3C), (230, 0x3D), (231, 0x36),                // right control, shift, option, command
        ]
        for (scancode, code) in others { map[scancode] = code }
        return map
    }()

    /// The modifier keys' scancodes, whose presses are flags-changed events.
    static func isModifier(_ scancode: UInt32) -> Bool { (224...231).contains(scancode) || scancode == 57 }

    /// The characters a key types, unshifted and as typed: printable keys
    /// from SDL's keycode (its Unicode character), others as AppKit gives
    /// them.
    static func characters(scancode: UInt32, keycode: UInt32, shifted: Bool) -> (typed: String, plain: String) {
        let special: [UInt32: UInt32] = [
            40: 0x0D, 41: 0x1B, 42: 0x7F, 43: 0x09, 88: 0x03,                   // return, escape, backspace, tab, enter
            79: 0xF703, 80: 0xF702, 81: 0xF701, 82: 0xF700,                     // arrows
            73: 0xF746, 74: 0xF729, 75: 0xF72C, 76: 0xF728, 77: 0xF72B, 78: 0xF72D, // help, home, page up, delete, end, page down
            70: 0xF710, 71: 0xF711, 72: 0xF712,                                 // F13 to F15
        ]
        if let scalar = special[scancode] ?? ((58...69).contains(scancode) ? 0xF704 + scancode - 58 : nil) {
            let text = Unicode.Scalar(scalar).map { String(Character($0)) } ?? ""
            return (text, text)
        }
        guard keycode < 0x4000_0000, keycode != 0, let scalar = Unicode.Scalar(keycode) else { return ("", "") }
        let plain = String(Character(scalar))
        return (shifted ? plain.uppercased() : plain, plain)
    }
}

/// The mouse buttons down, as NSEvent.pressedMouseButtons: bit 0 the left
/// button, 1 the right, 2 the middle.
enum MouseButtons {
    nonisolated(unsafe) static var pressed: UInt = 0
}

extension NSEvent {
    /// An event mask as an NSUInteger, which is 32 bits in 32-bit programs:
    /// all ones there is NSEventMaskAny.
    static func mask(fromWord word: UInt) -> UInt64 { word == .max ? .max : UInt64(word) }
}

@ObjCClass("NSEvent")
open class NSEvent: NSObject {
    var type: EventType = .applicationDefined
    var modifierFlags: UInt = 0
    var timestamp: Double = 0
    var window: NSWindow?
    var windowNumber = 0
    var locationInWindow = CGPoint.zero
    var keyCode: UInt16 = 0
    var characters = ""
    var charactersIgnoringModifiers = ""
    /// Whether the characters came from SDL's text input, as typed.
    var typedText = false
    var isARepeat = false
    var buttonNumber = 0
    var clickCount = 0
    var deltaX: CGFloat = 0
    var deltaY: CGFloat = 0
    var scrollingDeltaX: CGFloat = 0
    var scrollingDeltaY: CGFloat = 0
    var hasPreciseScrollingDeltas = false
    var isDirectionInvertedFromDevice = false
    var subtype: Int16 = 0
    var data1 = 0
    var data2 = 0
    var trackingArea: NSObject?
    var eventNumber = 0

    nonisolated(unsafe) static var lastNumber = 0

    @ObjCMethod("init")
    public required override init() {
        super.init()
        NSEvent.lastNumber += 1
        eventNumber = NSEvent.lastNumber
        timestamp = Clock.now
        modifierFlags = NSEvent.currentModifierFlags
    }

    init(_ type: EventType, window: NSWindow?, location: CGPoint) {
        super.init()
        NSEvent.lastNumber += 1
        eventNumber = NSEvent.lastNumber
        timestamp = Clock.now
        modifierFlags = NSEvent.currentModifierFlags
        self.type = type
        self.window = window
        windowNumber = window?.windowNumber ?? 0
        locationInWindow = location
    }

    /// The modifier keys down now, from SDL.
    static var currentModifierFlags: UInt { SDL.start() ? ModifierFlags.from(SDL.modState()) : 0 }

    @ObjCMethod("type") func eventType() -> UInt { type.rawValue }
    @ObjCMethod("subtype") func eventSubtype() -> Int16 { subtype }
    @ObjCMethod("modifierFlags") func eventModifierFlags() -> UInt { modifierFlags }
    @ObjCMethod("timestamp") func eventTimestamp() -> Double { timestamp }
    @ObjCMethod("window") func eventWindow() -> NSWindow? { window }
    @ObjCMethod("windowNumber") func eventWindowNumber() -> Int { windowNumber }
    @ObjCMethod("context") func context() -> NSObject? { nil }
    @ObjCMethod("locationInWindow") func eventLocationInWindow() -> CGPoint { locationInWindow }
    @ObjCMethod("keyCode") func eventKeyCode() -> UInt16 { keyCode }
    @ObjCMethod("characters") func eventCharacters() -> String? { type.isKey ? characters : nil }
    @ObjCMethod("charactersIgnoringModifiers") func eventCharactersIgnoringModifiers() -> String? {
        type.isKey ? charactersIgnoringModifiers : nil
    }
    @ObjCMethod("charactersByApplyingModifiers:") func characters(applyingModifiers flags: UInt) -> String? {
        guard type.isKey else { return nil }
        return flags & ModifierFlags.shift != 0 ? charactersIgnoringModifiers.uppercased() : charactersIgnoringModifiers
    }
    @ObjCMethod("isARepeat") func eventIsARepeat() -> Bool { isARepeat }
    /// NSEventSpecialKey: the function-key character, else 0.
    @ObjCMethod("specialKey") func specialKey() -> UInt {
        guard let scalar = charactersIgnoringModifiers.unicodeScalars.first?.value, scalar >= 0xF700 else { return 0 }
        return UInt(scalar)
    }
    @ObjCMethod("buttonNumber") func eventButtonNumber() -> Int { buttonNumber }
    @ObjCMethod("clickCount") func eventClickCount() -> Int { clickCount }
    @ObjCMethod("pressure") func pressure() -> Float { type == .leftMouseDown || type == .leftMouseDragged ? 1 : 0 }
    @ObjCMethod("deltaX") func eventDeltaX() -> CGFloat { deltaX }
    @ObjCMethod("deltaY") func eventDeltaY() -> CGFloat { deltaY }
    @ObjCMethod("deltaZ") func deltaZ() -> CGFloat { 0 }
    @ObjCMethod("scrollingDeltaX") func eventScrollingDeltaX() -> CGFloat { scrollingDeltaX }
    @ObjCMethod("scrollingDeltaY") func eventScrollingDeltaY() -> CGFloat { scrollingDeltaY }
    @ObjCMethod("hasPreciseScrollingDeltas") func eventHasPreciseScrollingDeltas() -> Bool { hasPreciseScrollingDeltas }
    @ObjCMethod("isDirectionInvertedFromDevice") func eventIsDirectionInvertedFromDevice() -> Bool { isDirectionInvertedFromDevice }
    /// NSEventPhase and momentum phase: none, as a wheel's scrolls have.
    @ObjCMethod("phase") func phase() -> UInt { 0 }
    @ObjCMethod("momentumPhase") func momentumPhase() -> UInt { 0 }
    @ObjCMethod("data1") func eventData1() -> Int { data1 }
    @ObjCMethod("data2") func eventData2() -> Int { data2 }
    @ObjCMethod("eventNumber") func eventEventNumber() -> Int { eventNumber }
    @ObjCMethod("trackingNumber") func trackingNumber() -> Int { 0 }
    @ObjCMethod("trackingArea") func eventTrackingArea() -> NSObject? { trackingArea }
    @ObjCMethod("userData") func userData() -> UnsafeMutableRawPointer? { nil }
    @ObjCMethod("CGEvent") func cgEvent() -> UnsafeMutableRawPointer? { nil }
    @ObjCMethod("isSwipeTrackingFromScrollEventsEnabled") func swipeTracking() -> Bool { false }
    @ObjCMethod("allTouches") func allTouches() -> NSObject? { nil }

    /// Where the mouse is, in screen coordinates: origin at the bottom left
    /// of the main screen.
    @ObjCClassMethod("mouseLocation")
    static func mouseLocation() -> CGPoint {
        guard SDL.start() else { return .zero }
        var x: Float = 0, y: Float = 0
        _ = SDL.globalMouseState(&x, &y)
        return CGPoint(x: CGFloat(x), y: Screens.height - CGFloat(y))
    }

    @ObjCClassMethod("pressedMouseButtons") static func pressedMouseButtons() -> UInt { MouseButtons.pressed }
    @ObjCClassMethod("modifierFlags") static func classModifierFlags() -> UInt { currentModifierFlags }
    @ObjCClassMethod("doubleClickInterval") static func doubleClickInterval() -> Double { 0.5 }
    @ObjCClassMethod("keyRepeatDelay") static func keyRepeatDelay() -> Double { 0.5 }
    @ObjCClassMethod("keyRepeatInterval") static func keyRepeatInterval() -> Double { 0.083 }
    @ObjCClassMethod("isMouseCoalescingEnabled") static func isMouseCoalescingEnabled() -> Bool { true }
    @ObjCClassMethod("setMouseCoalescingEnabled:") static func setMouseCoalescingEnabled(_ enabled: Bool) {}
    @ObjCClassMethod("isSwipeTrackingFromScrollEventsEnabled") static func classSwipeTracking() -> Bool { false }
    @ObjCClassMethod("startPeriodicEventsAfterDelay:withPeriod:") static func startPeriodicEvents(afterDelay delay: Double, period: Double) {}
    @ObjCClassMethod("stopPeriodicEvents") static func stopPeriodicEvents() {}

    /// An application-defined or other event, as apps post to wake their
    /// own event loops.
    @ObjCClassMethod("otherEventWithType:location:modifierFlags:timestamp:windowNumber:context:subtype:data1:data2:")
    static func otherEvent(type: UInt, location: CGPoint, modifierFlags: UInt, timestamp: Double, windowNumber: Int,
                           context: NSObject?, subtype: Int16, data1: Int, data2: Int) -> NSEvent? {
        let event = NSEvent(EventType(rawValue: type) ?? .applicationDefined, window: Windows.numbered(windowNumber), location: location)
        event.modifierFlags = modifierFlags
        event.timestamp = timestamp
        event.windowNumber = windowNumber
        event.subtype = subtype
        event.data1 = data1
        event.data2 = data2
        return event
    }

    @ObjCClassMethod("mouseEventWithType:location:modifierFlags:timestamp:windowNumber:context:eventNumber:clickCount:pressure:")
    static func mouseEvent(type: UInt, location: CGPoint, modifierFlags: UInt, timestamp: Double, windowNumber: Int,
                           context: NSObject?, eventNumber: Int, clickCount: Int, pressure: Float) -> NSEvent? {
        let event = NSEvent(EventType(rawValue: type) ?? .mouseMoved, window: Windows.numbered(windowNumber), location: location)
        event.modifierFlags = modifierFlags
        event.timestamp = timestamp
        event.clickCount = clickCount
        return event
    }

    @ObjCClassMethod("keyEventWithType:location:modifierFlags:timestamp:windowNumber:context:characters:charactersIgnoringModifiers:isARepeat:keyCode:")
    static func keyEvent(type: UInt, location: CGPoint, modifierFlags: UInt, timestamp: Double, windowNumber: Int, context: NSObject?,
                         characters: String?, charactersIgnoringModifiers: String?, isARepeat: Bool, keyCode: UInt16) -> NSEvent? {
        let event = NSEvent(EventType(rawValue: type) ?? .keyDown, window: Windows.numbered(windowNumber), location: location)
        event.modifierFlags = modifierFlags
        event.timestamp = timestamp
        event.characters = characters ?? ""
        event.charactersIgnoringModifiers = charactersIgnoringModifiers ?? ""
        event.isARepeat = isARepeat
        event.keyCode = keyCode
        return event
    }

    /// Local monitors see each event before it is sent, and may change or
    /// drop it; the returned token removes one.
    @ObjCClassMethod("addLocalMonitorForEventsMatchingMask:handler:")
    static func addLocalMonitor(mask wordMask: UInt, handler: ObjCBlock) -> NSObject? {
        let mask = NSEvent.mask(fromWord: wordMask)
        let monitor = EventMonitor(mask: mask, handler: handler)
        Monitors.local.append(monitor)
        return monitor
    }

    /// Global monitors see other apps' events: there are none here.
    @ObjCClassMethod("addGlobalMonitorForEventsMatchingMask:handler:")
    static func addGlobalMonitor(mask wordMask: UInt, handler: ObjCBlock) -> NSObject? {
        let mask = NSEvent.mask(fromWord: wordMask)
        return EventMonitor(mask: mask, handler: handler)
    }

    @ObjCClassMethod("removeMonitor:")
    static func removeMonitor(_ monitor: NSObject?) {
        guard let monitor else { return }
        Monitors.local.removeAll { $0.objcObject == monitor.objcObject }
    }
}

/// An event monitor's mask and handler.
@ObjCClass("_PerryEventMonitor")
open class EventMonitor: NSObject {
    var mask: UInt64 = 0
    var handler: ObjCBlock?

    init(mask: UInt64, handler: ObjCBlock) {
        super.init()
        self.mask = mask
        self.handler = handler
    }
}

enum Monitors {
    nonisolated(unsafe) static var local: [EventMonitor] = []

    /// The event after the local monitors: nil when one drops it.
    static func filter(_ event: NSEvent) -> UnsafeMutableRawPointer? {
        var current: UnsafeMutableRawPointer? = event.objcObject
        for monitor in local where monitor.mask & event.type.mask != 0 {
            guard let object = current, let handler = monitor.handler else { break }
            typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?
            current = handler.function(as: Invoke.self)(handler.object, object)
        }
        return current
    }
}

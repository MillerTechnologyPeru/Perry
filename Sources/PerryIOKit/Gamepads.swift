import Glibc
import PerryObjCInterop

// HID devices over SDL3's gamepads. Each gamepad SDL finds is a wired Xbox
// 360 controller (Microsoft's vendor and product IDs) with the elements
// the Mac's Xbox 360 driver gives it, which Mac games of its time map:
// buttons 1 to 15 are A, B, X, Y, the left and right shoulders, the left
// and right stick clicks, Start, Back, Guide and the D-pad's up, down,
// left and right; X and Y are the left stick, Rx and Ry the right (down
// and right positive, from -32768 to 32767), Z and Rz the left and right
// triggers (0 to 255). SDL maps whichever gamepad it is to that layout.
//
// The gamepads are read on the main queue sixty times a second, once the
// first HID manager or device is opened or scheduled. On each read, the
// managers hear of gamepads that came or went (looked for twice a second)
// through their matching and removal callbacks, then values that changed
// go to the input value callbacks: never during a call into IOKit, as a
// Mac's run loop calls them back later too.
// PERRY_HID_TRACE says what is found. Without SDL3 there are no devices.

enum Gamepads {
    /// Where an element's value comes from.
    enum Source {
        case button(Int32)
        case stick(Int32)
        case trigger(Int32)
    }

    final class Pad {
        let id: UInt32
        let gamepad: SDL.Pointer
        let device: HIDDevice
        let sources: [Source]

        init(id: UInt32, gamepad: SDL.Pointer, device: HIDDevice, sources: [Source]) {
            (self.id, self.gamepad, self.device, self.sources) = (id, gamepad, device, sources)
        }
    }

    nonisolated(unsafe) private(set) static var pads: [Pad] = []
    nonisolated(unsafe) private static var started = false
    nonisolated(unsafe) private static var ticks = 0
    nonisolated(unsafe) private static var nextLocation: UInt32 = 0x1410_0000

    nonisolated(unsafe) static let tracing = getenv("PERRY_HID_TRACE") != nil

    static func trace(_ message: @autoclosure () -> String) {
        guard tracing else { return }
        let line = "perry: IOKit: \(message())\n"
        line.withCString { _ = write(2, $0, strlen($0)) }
    }

    static var devices: [HIDDevice] { pads.map(\.device) }

    /// Opens SDL's gamepads now, and reads them from then on.
    static func start() {
        guard !started else { return }
        started = true
        guard SDL.load() else {
            trace("SDL3's gamepads aren't available; no HID devices")
            return
        }
        scan()
        schedule()
    }

    private static func schedule() {
        guard let dispatchAfter = Dispatch.after, let dispatchTime = Dispatch.time, let mainQueue = Dispatch.mainQueue else {
            trace("libdispatch's main queue isn't available; gamepads aren't read")
            return
        }
        dispatchAfter(dispatchTime(0, 16_666_667), mainQueue, nil) { _ in
            Gamepads.tick()
            Gamepads.schedule()
        }
    }

    private static func tick() {
        SDL.updateGamepads()
        ticks &+= 1
        if ticks % 30 == 0 { scan() }
        // Devices first, so that a manager hears of one before its values.
        HIDManagers.reportDevices()
        for pad in pads { read(pad, delivering: true) }
    }

    /// Adds the gamepads that came, removes those that went.
    private static func scan() {
        var count: Int32 = 0
        guard let ids = SDL.getGamepads(&count) else { return }
        let present = Set((0..<Int(count)).map { ids[$0] })
        SDL.free(ids)
        for pad in pads where !present.contains(pad.id) {
            trace("gamepad \(pad.id) went")
            SDL.closeGamepad(pad.gamepad)
        }
        pads.removeAll { !present.contains($0.id) }
        for id in present.sorted() where !pads.contains(where: { $0.id == id }) {
            guard let gamepad = SDL.openGamepad(id) else { continue }
            let pad = make(id: id, gamepad: gamepad)
            read(pad, delivering: false)
            pads.append(pad)
            trace("gamepad \(id) (\(SDL.getGamepadName(gamepad).map { String(cString: $0) } ?? "?")) is an Xbox 360 controller")
        }
    }

    /// SDL's buttons in the order of the Xbox 360 driver's: south, east,
    /// west, north, the shoulders, the stick clicks, start, back, guide,
    /// then the D-pad.
    private static let buttons: [Int32] = [0, 1, 2, 3, 9, 10, 7, 8, 6, 4, 5, 11, 12, 13, 14]

    /// The axes, by usage: X, Y and Z, then Rx, Ry and Rz.
    private static let axes: [(usage: UInt32, source: Source)] = [
        (0x30, .stick(0)), (0x31, .stick(1)), (0x32, .trigger(4)),
        (0x33, .stick(2)), (0x34, .stick(3)), (0x35, .trigger(5)),
    ]

    private static func make(id: UInt32, gamepad: SDL.Pointer) -> Pad {
        let device = HIDDevice()
        device.usages = [(1, 5)]                    // Generic Desktop, GamePad
        let location = nextLocation
        nextLocation &+= 0x0001_0000
        func number(_ value: Int) -> NSObject { NSNumber.make(int64: Int64(value)) }
        device.properties = NSMutableDictionary.of([
            ("VendorID", number(0x045E)),
            ("ProductID", number(0x028E)),
            ("VersionNumber", number(0x0114)),
            ("Product", NSObject.string("Xbox 360 Wired Controller")),
            ("Manufacturer", NSObject.string("Microsoft")),
            ("Transport", NSObject.string("USB")),
            ("LocationID", number(Int(location))),
            ("PrimaryUsagePage", number(1)),
            ("PrimaryUsage", number(5)),
            ("DeviceUsagePairs", NSMutableArray.of([NSMutableDictionary.of([("DeviceUsagePage", number(1)), ("DeviceUsage", number(5))])])),
        ])
        var sources: [Source] = []
        func add(_ type: UInt32, page: UInt32, usage: UInt32, range: ClosedRange<Int>, _ source: Source) {
            let element = HIDElement()
            element.cookie = UInt32(device.elements.count + 1)
            (element.type, element.usagePage, element.usage) = (type, page, usage)
            (element.logicalMinimum, element.logicalMaximum) = (range.lowerBound, range.upperBound)
            element.device = device.objcObject
            device.elements.append(element)
            sources.append(source)
        }
        for (index, button) in buttons.enumerated() {
            add(HIDElementType.button, page: 9, usage: UInt32(index + 1), range: 0...1, .button(button))
        }
        for (usage, source) in axes {
            if case .trigger = source {
                add(HIDElementType.axis, page: 1, usage: usage, range: 0...255, source)
            } else {
                add(HIDElementType.axis, page: 1, usage: usage, range: -32768...32767, source)
            }
        }
        return Pad(id: id, gamepad: gamepad, device: device, sources: sources)
    }

    /// Reads the pad's elements; with `delivering`, those that changed go
    /// to the callbacks.
    private static func read(_ pad: Pad, delivering: Bool) {
        for (element, source) in zip(pad.device.elements, pad.sources) {
            let now: Int
            switch source {
            case .button(let button): now = SDL.getGamepadButton(pad.gamepad, button) ? 1 : 0
            case .stick(let axis): now = Int(SDL.getGamepadAxis(pad.gamepad, axis))
            case .trigger(let axis): now = Int(max(SDL.getGamepadAxis(pad.gamepad, axis), 0)) >> 7
            }
            if let last = element.value, last.integer == now { continue }
            let value = HIDValue.make(element, now)
            element.value = value
            guard delivering else { continue }
            pad.device.deliver(value)
            HIDManagers.deliver(value, from: pad.device)
        }
    }
}

// MARK: - SDL3

enum SDL {
    typealias Pointer = UnsafeMutableRawPointer
    nonisolated(unsafe) static var updateGamepads: (@convention(c) () -> Void)!
    nonisolated(unsafe) static var getGamepads: (@convention(c) (UnsafeMutablePointer<Int32>) -> UnsafeMutablePointer<UInt32>?)!
    nonisolated(unsafe) static var openGamepad: (@convention(c) (UInt32) -> Pointer?)!
    nonisolated(unsafe) static var closeGamepad: (@convention(c) (Pointer) -> Void)!
    nonisolated(unsafe) static var getGamepadName: (@convention(c) (Pointer) -> UnsafePointer<CChar>?)!
    nonisolated(unsafe) static var getGamepadButton: (@convention(c) (Pointer, Int32) -> Bool)!
    nonisolated(unsafe) static var getGamepadAxis: (@convention(c) (Pointer, Int32) -> Int16)!
    nonisolated(unsafe) static var free: (@convention(c) (UnsafeMutableRawPointer?) -> Void)!

    /// SDL3, with its gamepad subsystem started; false without it.
    static func load() -> Bool {
        guard let library = dlopen("libSDL3.so.0", RTLD_NOW) else { return false }
        func bind<T>(_ name: String, _: T.Type) -> T? { dlsym(library, name).map { unsafeBitCast($0, to: T.self) } }
        typealias SetHint = @convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>) -> Bool
        typealias InitSubSystem = @convention(c) (UInt32) -> Bool
        guard let setHint = bind("SDL_SetHint", SetHint.self), let initSubSystem = bind("SDL_InitSubSystem", InitSubSystem.self),
              let updateGamepads = bind("SDL_UpdateGamepads", (@convention(c) () -> Void).self),
              let getGamepads = bind("SDL_GetGamepads", (@convention(c) (UnsafeMutablePointer<Int32>) -> UnsafeMutablePointer<UInt32>?).self),
              let openGamepad = bind("SDL_OpenGamepad", (@convention(c) (UInt32) -> Pointer?).self),
              let closeGamepad = bind("SDL_CloseGamepad", (@convention(c) (Pointer) -> Void).self),
              let getGamepadName = bind("SDL_GetGamepadName", (@convention(c) (Pointer) -> UnsafePointer<CChar>?).self),
              let getGamepadButton = bind("SDL_GetGamepadButton", (@convention(c) (Pointer, Int32) -> Bool).self),
              let getGamepadAxis = bind("SDL_GetGamepadAxis", (@convention(c) (Pointer, Int32) -> Int16).self),
              let free = bind("SDL_free", (@convention(c) (UnsafeMutableRawPointer?) -> Void).self) else { return false }
        // Read while the window isn't focused, too, as a game's controller is.
        _ = setHint("SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS", "1")
        // SDL_INIT_GAMEPAD, which brings the joystick subsystem.
        guard initSubSystem(0x2000) else { return false }
        (SDL.updateGamepads, SDL.getGamepads, SDL.openGamepad, SDL.closeGamepad) = (updateGamepads, getGamepads, openGamepad, closeGamepad)
        (SDL.getGamepadName, SDL.getGamepadButton, SDL.getGamepadAxis, SDL.free) = (getGamepadName, getGamepadButton, getGamepadAxis, free)
        return true
    }
}

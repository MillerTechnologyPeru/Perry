import Glibc
import PerryObjCInterop

// GameController over SDL3's gamepads. Each gamepad SDL finds is a
// GCController with the extended gamepad profile (and the older gamepad and
// micro gamepad profiles, sharing its elements): SDL's south, east, west
// and north buttons are A, B, X and Y, its sticks' up is positive, as
// Apple's is, and Start is Menu, which also calls the controller's paused
// handler. The gamepads are read on the main queue sixty times a second,
// which also finds gamepads coming and going and posts the connect and
// disconnect notifications; handlers are called as values change. Without
// SDL3 there are no controllers.

// MARK: - Elements

final class ButtonState {
    var value: Float = 0
    var pressed = false
    var valueChangedHandler: ObjCBlock?
    var pressedChangedHandler: ObjCBlock?
    /// The direction pad or profile it's in; not retained.
    var collection: UnsafeMutableRawPointer?
    var analog = false
}

final class AxisState {
    var value: Float = 0
    var valueChangedHandler: ObjCBlock?
    var collection: UnsafeMutableRawPointer?
}

final class DirectionPadState {
    let xAxis = Elements.axis()
    let yAxis = Elements.axis()
    let up = Elements.button()
    let down = Elements.button()
    let left = Elements.button()
    let right = Elements.button()
    var valueChangedHandler: ObjCBlock?
    var collection: UnsafeMutableRawPointer?
    var analog = false
}

/// The elements of the main-thread objects, by object.
enum Elements {
    nonisolated(unsafe) static var buttons: [UnsafeMutableRawPointer: ButtonState] = [:]
    nonisolated(unsafe) static var axes: [UnsafeMutableRawPointer: AxisState] = [:]
    nonisolated(unsafe) static var pads: [UnsafeMutableRawPointer: DirectionPadState] = [:]

    static func button() -> GCControllerButtonInput {
        let button = NSObject(GCControllerButtonInput.objCClass.pointer).newInstance().unsafeCast(to: GCControllerButtonInput.self)
        buttons[button.objcObject] = ButtonState()
        return button
    }

    static func axis() -> GCControllerAxisInput {
        let axis = NSObject(GCControllerAxisInput.objCClass.pointer).newInstance().unsafeCast(to: GCControllerAxisInput.self)
        axes[axis.objcObject] = AxisState()
        return axis
    }

    static func pad(analog: Bool) -> GCControllerDirectionPad {
        let pad = NSObject(GCControllerDirectionPad.objCClass.pointer).newInstance().unsafeCast(to: GCControllerDirectionPad.self)
        let state = DirectionPadState()
        state.analog = analog
        for button in [state.up, state.down, state.left, state.right] {
            buttons[button.objcObject]?.collection = pad.objcObject
            buttons[button.objcObject]?.analog = analog
        }
        for axis in [state.xAxis, state.yAxis] { axes[axis.objcObject]?.collection = pad.objcObject }
        pads[pad.objcObject] = state
        return pad
    }
}

@ObjCClass("GCControllerElement")
open class GCControllerElement: NSObject {
    @ObjCMethod("collection")
    func collection() -> NSObject? {
        let collection = Elements.buttons[objcObject]?.collection ?? Elements.axes[objcObject]?.collection
            ?? Elements.pads[objcObject]?.collection
        return collection.map { NSObject($0) }
    }

    @ObjCMethod("isAnalog")
    func isAnalog() -> Bool { Elements.buttons[objcObject]?.analog ?? Elements.pads[objcObject]?.analog ?? (Elements.axes[objcObject] != nil) }

    @ObjCMethod("isBoundToSystemGesture") func isBoundToSystemGesture() -> Bool { false }
    @ObjCMethod("localizedName") func localizedName() -> String? { nil }
    @ObjCMethod("sfSymbolsName") func sfSymbolsName() -> String? { nil }
}

@ObjCClass("GCControllerButtonInput")
open class GCControllerButtonInput: GCControllerElement {
    var button: ButtonState { Elements.buttons[objcObject]! }

    @ObjCMethod("value") func value() -> Float { button.value }
    @ObjCMethod("isPressed") func isPressed() -> Bool { button.pressed }
    @ObjCMethod("isTouched") func isTouched() -> Bool { button.pressed }
    @ObjCMethod("setValue:") func setValue(_ value: Float) { Controllers.set(self, value: value) }
    @ObjCMethod("valueChangedHandler") func valueChangedHandler() -> ObjCBlock? { button.valueChangedHandler }
    @ObjCMethod("setValueChangedHandler:") func setValueChangedHandler(_ handler: ObjCBlock?) { button.valueChangedHandler = handler }
    @ObjCMethod("pressedChangedHandler") func pressedChangedHandler() -> ObjCBlock? { button.pressedChangedHandler }
    @ObjCMethod("setPressedChangedHandler:") func setPressedChangedHandler(_ handler: ObjCBlock?) { button.pressedChangedHandler = handler }
}

@ObjCClass("GCControllerAxisInput")
open class GCControllerAxisInput: GCControllerElement {
    var axis: AxisState { Elements.axes[objcObject]! }

    @ObjCMethod("value") func value() -> Float { axis.value }
    @ObjCMethod("setValue:") func setValue(_ value: Float) { Controllers.set(self, value: value) }
    @ObjCMethod("valueChangedHandler") func valueChangedHandler() -> ObjCBlock? { axis.valueChangedHandler }
    @ObjCMethod("setValueChangedHandler:") func setValueChangedHandler(_ handler: ObjCBlock?) { axis.valueChangedHandler = handler }
}

@ObjCClass("GCControllerDirectionPad")
open class GCControllerDirectionPad: GCControllerElement {
    var pad: DirectionPadState { Elements.pads[objcObject]! }

    @ObjCMethod("xAxis") func xAxis() -> GCControllerAxisInput { pad.xAxis }
    @ObjCMethod("yAxis") func yAxis() -> GCControllerAxisInput { pad.yAxis }
    @ObjCMethod("up") func up() -> GCControllerButtonInput { pad.up }
    @ObjCMethod("down") func down() -> GCControllerButtonInput { pad.down }
    @ObjCMethod("left") func left() -> GCControllerButtonInput { pad.left }
    @ObjCMethod("right") func right() -> GCControllerButtonInput { pad.right }
    @ObjCMethod("setValueForXAxis:yAxis:") func setValue(x: Float, y: Float) { Controllers.set(self, x: x, y: y) }
    @ObjCMethod("valueChangedHandler") func valueChangedHandler() -> ObjCBlock? { pad.valueChangedHandler }
    @ObjCMethod("setValueChangedHandler:") func setValueChangedHandler(_ handler: ObjCBlock?) { pad.valueChangedHandler = handler }
}

// MARK: - Profiles

/// A controller's elements, which every profile of it shares.
final class ProfileState {
    let dpad = Elements.pad(analog: false)
    let leftThumbstick = Elements.pad(analog: true)
    let rightThumbstick = Elements.pad(analog: true)
    let buttonA = Elements.button()
    let buttonB = Elements.button()
    let buttonX = Elements.button()
    let buttonY = Elements.button()
    let leftShoulder = Elements.button()
    let rightShoulder = Elements.button()
    let leftTrigger = Elements.button()
    let rightTrigger = Elements.button()
    let leftThumbstickButton = Elements.button()
    let rightThumbstickButton = Elements.button()
    let buttonMenu = Elements.button()
    let buttonOptions = Elements.button()
    let buttonHome = Elements.button()
    /// The controller; not retained.
    var controller: UnsafeMutableRawPointer?
    /// Each profile's valueChangedHandler, by profile.
    var handlers: [UnsafeMutableRawPointer: ObjCBlock] = [:]
    var reportsAbsoluteDpadValues = false
    var allowsRotation = false

    var elements: [GCControllerElement] {
        [dpad, leftThumbstick, rightThumbstick, buttonA, buttonB, buttonX, buttonY, leftShoulder, rightShoulder, leftTrigger,
         rightTrigger, leftThumbstickButton, rightThumbstickButton, buttonMenu, buttonOptions, buttonHome]
    }

    init() {
        for trigger in [leftTrigger, rightTrigger] { Elements.buttons[trigger.objcObject]?.analog = true }
    }
}

/// Every profile of a controller, by profile object.
enum Profiles {
    nonisolated(unsafe) static var states: [UnsafeMutableRawPointer: ProfileState] = [:]

    static func make<Profile: GCPhysicalInputProfile>(_ type: Profile.Type, _ state: ProfileState) -> Profile {
        let profile = NSObject(Profile.objCClass.pointer).newInstance().unsafeCast(to: Profile.self)
        states[profile.objcObject] = state
        return profile
    }
}

@ObjCClass("GCPhysicalInputProfile")
open class GCPhysicalInputProfile: NSObject {
    var profile: ProfileState { Profiles.states[objcObject]! }

    @ObjCMethod("controller") func controller() -> NSObject? { profile.controller.map { NSObject($0) } }
    @ObjCMethod("device") func device() -> NSObject? { controller() }
    @ObjCMethod("hasRemappedElements") func hasRemappedElements() -> Bool { false }
    @ObjCMethod("lastEventTimestamp") func lastEventTimestamp() -> Double { Controllers.now() }
    @ObjCMethod("valueChangedHandler") func valueChangedHandler() -> ObjCBlock? { profile.handlers[objcObject] }
    @ObjCMethod("setValueChangedHandler:")
    func setValueChangedHandler(_ handler: ObjCBlock?) { profile.handlers[objcObject] = handler }
}

@ObjCClass("GCMicroGamepad")
open class GCMicroGamepad: GCPhysicalInputProfile {
    @ObjCMethod("dpad") func dpad() -> GCControllerDirectionPad { profile.dpad }
    @ObjCMethod("buttonA") func buttonA() -> GCControllerButtonInput { profile.buttonA }
    @ObjCMethod("buttonX") func buttonX() -> GCControllerButtonInput { profile.buttonX }
    @ObjCMethod("buttonMenu") func buttonMenu() -> GCControllerButtonInput { profile.buttonMenu }
    @ObjCMethod("reportsAbsoluteDpadValues") func reportsAbsoluteDpadValues() -> Bool { profile.reportsAbsoluteDpadValues }
    @ObjCMethod("setReportsAbsoluteDpadValues:") func setReportsAbsoluteDpadValues(_ value: Bool) { profile.reportsAbsoluteDpadValues = value }
    @ObjCMethod("allowsRotation") func allowsRotation() -> Bool { profile.allowsRotation }
    @ObjCMethod("setAllowsRotation:") func setAllowsRotation(_ value: Bool) { profile.allowsRotation = value }
}

/// The deprecated standard gamepad: the extended gamepad's face buttons,
/// direction pad and shoulders.
@ObjCClass("GCGamepad")
open class GCGamepad: GCPhysicalInputProfile {
    @ObjCMethod("dpad") func dpad() -> GCControllerDirectionPad { profile.dpad }
    @ObjCMethod("buttonA") func buttonA() -> GCControllerButtonInput { profile.buttonA }
    @ObjCMethod("buttonB") func buttonB() -> GCControllerButtonInput { profile.buttonB }
    @ObjCMethod("buttonX") func buttonX() -> GCControllerButtonInput { profile.buttonX }
    @ObjCMethod("buttonY") func buttonY() -> GCControllerButtonInput { profile.buttonY }
    @ObjCMethod("leftShoulder") func leftShoulder() -> GCControllerButtonInput { profile.leftShoulder }
    @ObjCMethod("rightShoulder") func rightShoulder() -> GCControllerButtonInput { profile.rightShoulder }
}

@ObjCClass("GCExtendedGamepad")
open class GCExtendedGamepad: GCPhysicalInputProfile {
    @ObjCMethod("dpad") func dpad() -> GCControllerDirectionPad { profile.dpad }
    @ObjCMethod("leftThumbstick") func leftThumbstick() -> GCControllerDirectionPad { profile.leftThumbstick }
    @ObjCMethod("rightThumbstick") func rightThumbstick() -> GCControllerDirectionPad { profile.rightThumbstick }
    @ObjCMethod("buttonA") func buttonA() -> GCControllerButtonInput { profile.buttonA }
    @ObjCMethod("buttonB") func buttonB() -> GCControllerButtonInput { profile.buttonB }
    @ObjCMethod("buttonX") func buttonX() -> GCControllerButtonInput { profile.buttonX }
    @ObjCMethod("buttonY") func buttonY() -> GCControllerButtonInput { profile.buttonY }
    @ObjCMethod("leftShoulder") func leftShoulder() -> GCControllerButtonInput { profile.leftShoulder }
    @ObjCMethod("rightShoulder") func rightShoulder() -> GCControllerButtonInput { profile.rightShoulder }
    @ObjCMethod("leftTrigger") func leftTrigger() -> GCControllerButtonInput { profile.leftTrigger }
    @ObjCMethod("rightTrigger") func rightTrigger() -> GCControllerButtonInput { profile.rightTrigger }
    @ObjCMethod("leftThumbstickButton") func leftThumbstickButton() -> GCControllerButtonInput { profile.leftThumbstickButton }
    @ObjCMethod("rightThumbstickButton") func rightThumbstickButton() -> GCControllerButtonInput { profile.rightThumbstickButton }
    @ObjCMethod("buttonMenu") func buttonMenu() -> GCControllerButtonInput { profile.buttonMenu }
    @ObjCMethod("buttonOptions") func buttonOptions() -> GCControllerButtonInput { profile.buttonOptions }
    @ObjCMethod("buttonHome") func buttonHome() -> GCControllerButtonInput { profile.buttonHome }
}

// MARK: - GCController

final class ControllerState {
    let gamepad: SDL.Pointer
    let id: UInt32
    let name: String
    let profile = ProfileState()
    let extended: GCExtendedGamepad
    let micro: GCMicroGamepad
    let standard: GCGamepad
    /// GCControllerPlayerIndex: unset -1.
    var playerIndex = -1
    var pausedHandler: ObjCBlock?
    /// SDL's buttons held at the last read, for tracing.
    var held: [Int] = []

    init(gamepad: SDL.Pointer, id: UInt32, name: String) {
        (self.gamepad, self.id, self.name) = (gamepad, id, name)
        extended = Profiles.make(GCExtendedGamepad.self, profile)
        micro = Profiles.make(GCMicroGamepad.self, profile)
        standard = Profiles.make(GCGamepad.self, profile)
    }
}

@ObjCClass("GCController")
open class GCController: NSObject {
    var controller: ControllerState { Controllers.states[objcObject]! }

    @ObjCClassMethod("controllers")
    static func controllers() -> NSObject {
        Controllers.start()
        let array = NSObject(NSMutableArray.objCClass.pointer).newInstance().unsafeCast(to: NSMutableArray.self)
        for controller in Controllers.connected { array.add(controller) }
        return array
    }

    @ObjCClassMethod("startWirelessControllerDiscoveryWithCompletionHandler:")
    static func startWirelessControllerDiscovery(completionHandler: ObjCBlock?) {
        Controllers.start()
        // Gamepads are found as they come; discovery itself ends at once.
        guard let completionHandler else { return }
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer) -> Void
        completionHandler.function(as: Invoke.self)(completionHandler.object)
    }

    @ObjCClassMethod("stopWirelessControllerDiscovery") static func stopWirelessControllerDiscovery() {}
    @ObjCClassMethod("current")
    static func current() -> GCController? {
        Controllers.start()
        return Controllers.connected.first
    }
    @ObjCClassMethod("shouldMonitorBackgroundEvents") static func shouldMonitorBackgroundEvents() -> Bool { false }
    @ObjCClassMethod("setShouldMonitorBackgroundEvents:") static func setShouldMonitorBackgroundEvents(_ monitor: Bool) {}
    @ObjCClassMethod("supportsHIDDevice:") static func supportsHIDDevice(_ device: NSObject?) -> Bool { false }

    @ObjCMethod("extendedGamepad") func extendedGamepad() -> GCExtendedGamepad? { controller.extended }
    @ObjCMethod("gamepad") func gamepad() -> GCGamepad? { controller.standard }
    @ObjCMethod("microGamepad") func microGamepad() -> GCMicroGamepad? { controller.micro }
    @ObjCMethod("physicalInputProfile") func physicalInputProfile() -> GCExtendedGamepad { controller.extended }
    @ObjCMethod("motion") func motion() -> NSObject? { nil }
    @ObjCMethod("battery") func battery() -> NSObject? { nil }
    @ObjCMethod("haptics") func haptics() -> NSObject? { nil }
    @ObjCMethod("light") func light() -> NSObject? { nil }
    @ObjCMethod("vendorName") func vendorName() -> String? { controller.name }
    @ObjCMethod("productCategory") func productCategory() -> String { "Gamepad" }
    /// A gamepad, not part of the device, as an MFi controller is.
    @ObjCMethod("isAttachedToDevice") func isAttachedToDevice() -> Bool { false }
    @ObjCMethod("isSnapshot") func isSnapshot() -> Bool { false }
    @ObjCMethod("playerIndex") func playerIndex() -> Int { controller.playerIndex }
    @ObjCMethod("setPlayerIndex:") func setPlayerIndex(_ index: Int) { controller.playerIndex = index }
    @ObjCMethod("controllerPausedHandler") func controllerPausedHandler() -> ObjCBlock? { controller.pausedHandler }
    @ObjCMethod("setControllerPausedHandler:") func setControllerPausedHandler(_ handler: ObjCBlock?) { controller.pausedHandler = handler }
    @ObjCMethod("handlerQueue") func handlerQueue() -> NSObject? { nil }
    @ObjCMethod("setHandlerQueue:") func setHandlerQueue(_ queue: NSObject?) {}
}

@ObjCWrapper("NSMutableArray")
class NSMutableArray: NSObject {
    @ObjCMethod("addObject:") func add(_ object: NSObject)
}

@ObjCWrapper("NSNotificationCenter")
class NSNotificationCenter: NSObject {
    @ObjCClassMethod("defaultCenter") static func defaultCenter() -> NSNotificationCenter
    @ObjCMethod("postNotificationName:object:userInfo:") func post(name: String, object: NSObject?, userInfo: NSObject?)
}

extension NSObject {
    @ObjCMethod("new") func newInstance() -> NSObject
}

@ObjCConstants
enum ControllerConstants {
    static let GCControllerDidConnectNotification = "GCControllerDidConnectNotification"
    static let GCControllerDidDisconnectNotification = "GCControllerDidDisconnectNotification"
    static let GCControllerDidBecomeCurrentNotification = "GCControllerDidBecomeCurrentNotification"
    static let GCControllerDidStopBeingCurrentNotification = "GCControllerDidStopBeingCurrentNotification"
    static let GCInputButtonA = "Button A"
    static let GCInputButtonB = "Button B"
    static let GCInputButtonX = "Button X"
    static let GCInputButtonY = "Button Y"
    static let GCInputDirectionPad = "Direction Pad"
    static let GCInputLeftThumbstick = "Left Thumbstick"
    static let GCInputRightThumbstick = "Right Thumbstick"
    static let GCInputLeftShoulder = "Left Shoulder"
    static let GCInputRightShoulder = "Right Shoulder"
    static let GCInputLeftTrigger = "Left Trigger"
    static let GCInputRightTrigger = "Right Trigger"
    static let GCInputButtonMenu = "Button Menu"
    static let GCInputButtonOptions = "Button Options"
    static let GCInputButtonHome = "Button Home"
}

// MARK: - Reading the gamepads

enum Controllers {
    /// The controllers, by object, and in the order they connected.
    nonisolated(unsafe) static var states: [UnsafeMutableRawPointer: ControllerState] = [:]
    nonisolated(unsafe) static var connected: [GCController] = []
    nonisolated(unsafe) private static var started = false
    nonisolated(unsafe) private static var ticks = 0

    typealias Function = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias DispatchAfter = @convention(c) (UInt64, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Function) -> Void
    typealias DispatchTime = @convention(c) (UInt64, Int64) -> UInt64
    nonisolated(unsafe) static var dispatchAfter: DispatchAfter?
    nonisolated(unsafe) static var dispatchTime: DispatchTime?
    nonisolated(unsafe) static var mainQueue: UnsafeMutableRawPointer?

    nonisolated(unsafe) static let tracing = getenv("PERRY_GAMECONTROLLER_TRACE") != nil

    static func trace(_ message: @autoclosure () -> String) {
        guard tracing else { return }
        let line = "perry: GameController: \(message())\n"
        line.withCString { _ = write(2, $0, strlen($0)) }
    }

    static func now() -> Double {
        var time = timespec()
        clock_gettime(CLOCK_MONOTONIC, &time)
        return Double(time.tv_sec) + Double(time.tv_nsec) / 1e9
    }

    static func load(_ lookup: (String, String) -> UnsafeMutableRawPointer?) {
        let library = "/usr/lib/system/libdispatch.dylib"
        dispatchAfter = lookup(library, "_dispatch_after_f").map { unsafeBitCast($0, to: DispatchAfter.self) }
        dispatchTime = lookup(library, "_dispatch_time").map { unsafeBitCast($0, to: DispatchTime.self) }
        mainQueue = lookup(library, "__dispatch_main_q")
    }

    /// Opens SDL's gamepads now, and reads them from then on.
    static func start() {
        guard !started else { return }
        started = true
        guard SDL.load() else {
            trace("SDL3's gamepads aren't available; no controllers")
            return
        }
        scan()
        schedule()
    }

    private static func schedule() {
        guard let dispatchAfter, let dispatchTime, let mainQueue else { return }
        dispatchAfter(dispatchTime(0, 16_666_667), mainQueue, nil) { _ in
            Controllers.tick()
            Controllers.schedule()
        }
    }

    private static func tick() {
        SDL.updateGamepads()
        ticks &+= 1
        // Gamepads coming and going, twice a second.
        if ticks % 30 == 0 { scan() }
        for controller in connected { read(controller) }
    }

    /// Connects the gamepads that came, disconnects those that went.
    private static func scan() {
        var count: Int32 = 0
        guard let ids = SDL.getGamepads(&count) else { return }
        let present = Set((0..<Int(count)).map { ids[$0] })
        SDL.free(ids)
        for controller in connected where !present.contains(controller.controller.id) {
            trace("disconnected \(controller.controller.name)")
            SDL.closeGamepad(controller.controller.gamepad)
            connected.removeAll { $0.objcObject == controller.objcObject }
            NSNotificationCenter.defaultCenter().post(name: ControllerConstants.GCControllerDidDisconnectNotification, object: controller, userInfo: nil)
        }
        let known = Set(connected.map(\.controller.id))
        for id in present.sorted() where !known.contains(id) {
            guard let gamepad = SDL.openGamepad(id) else { continue }
            let name = SDL.getGamepadName(gamepad).map { String(cString: $0) } ?? "Gamepad"
            let controller = NSObject(GCController.objCClass.pointer).newInstance().unsafeCast(to: GCController.self)
            let state = ControllerState(gamepad: gamepad, id: id, name: name)
            state.profile.controller = controller.objcObject
            states[controller.objcObject] = state
            connected.append(controller)
            trace("connected \(name)")
            NSNotificationCenter.defaultCenter().post(name: ControllerConstants.GCControllerDidConnectNotification, object: controller, userInfo: nil)
        }
    }

    // SDL_GamepadButton and SDL_GamepadAxis.
    private enum Button: Int32 {
        case south = 0, east, west, north, back, guide, start, leftStick, rightStick, leftShoulder, rightShoulder, up, down, left, right
    }
    private enum Axis: Int32 { case leftX = 0, leftY, rightX, rightY, leftTrigger, rightTrigger }

    private static func read(_ controller: GCController) {
        let state = controller.controller
        let profile = state.profile
        let gamepad = state.gamepad
        func button(_ button: Button) -> Float { SDL.getGamepadButton(gamepad, button.rawValue) ? 1 : 0 }
        if tracing {
            let held = (0..<26).filter { SDL.getGamepadButton(gamepad, Int32($0)) }
            if held != state.held {
                state.held = held
                trace("SDL buttons held: \(held)")
            }
        }
        for combination in quitButtons where !combination.isEmpty && combination.allSatisfy({ SDL.getGamepadButton(gamepad, $0.rawValue) }) {
            Quit.now()
        }
        func axis(_ axis: Axis) -> Float { max(-1, min(1, Float(SDL.getGamepadAxis(gamepad, axis.rawValue)) / 32767)) }
        /// A trigger, from rest at zero.
        func trigger(_ trigger: Axis) -> Float {
            let value = max(0, axis(trigger))
            return value < 0.05 ? 0 : value
        }
        let wasPaused = Elements.buttons[profile.buttonMenu.objcObject]?.pressed ?? false
        let changes: [(GCControllerButtonInput, Float)] = [
            (profile.buttonA, button(.south)), (profile.buttonB, button(.east)), (profile.buttonX, button(.west)),
            (profile.buttonY, button(.north)), (profile.leftShoulder, button(.leftShoulder)), (profile.rightShoulder, button(.rightShoulder)),
            (profile.leftTrigger, trigger(.leftTrigger)), (profile.rightTrigger, trigger(.rightTrigger)),
            (profile.leftThumbstickButton, button(.leftStick)), (profile.rightThumbstickButton, button(.rightStick)),
            (profile.buttonMenu, button(.start)), (profile.buttonOptions, button(.back)), (profile.buttonHome, button(.guide)),
        ]
        for (element, value) in changes { set(element, value: value) }
        if tracing, ticks % 120 == 0 {
            trace("pads: dpad \(profile.dpad.objcObject), left stick \(profile.leftThumbstick.objcObject), right stick \(profile.rightThumbstick.objcObject)")
        }
        set(profile.dpad, x: button(.right) - button(.left), y: button(.up) - button(.down))
        // Apple's sticks are up positive, SDL's down.
        let left = stick(axis(.leftX), -axis(.leftY)), right = stick(axis(.rightX), -axis(.rightY))
        set(profile.leftThumbstick, x: left.x, y: left.y)
        set(profile.rightThumbstick, x: right.x, y: right.y)
        if !wasPaused, Elements.buttons[profile.buttonMenu.objcObject]?.pressed == true, let handler = state.pausedHandler {
            typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer) -> Void
            handler.function(as: Invoke.self)(handler.object, controller.objcObject)
        }
    }

    /// With PERRY_GAMECONTROLLER_QUIT set to buttons joined by "+" (home,
    /// select, start, a, b, x, y, l1, r1, l3, r3), holding them all quits
    /// the app, as handhelds' ports quit with home and select; several
    /// combinations, separated by commas, each quit.
    nonisolated(unsafe) private static let quitButtons: [[Button]] = {
        guard let setting = getenv("PERRY_GAMECONTROLLER_QUIT") else { return [] }
        let names: [String: Button] = [
            "home": .guide, "guide": .guide, "select": .back, "back": .back, "start": .start, "a": .south, "b": .east,
            "x": .west, "y": .north, "l1": .leftShoulder, "r1": .rightShoulder, "l3": .leftStick, "r3": .rightStick,
        ]
        let combinations = String(cString: setting).lowercased().split(separator: ",").map { combination in
            combination.split(separator: "+").compactMap { names[String($0.filter { $0 != " " })] }
        }
        trace("quit with \(combinations)")
        return combinations
    }()

    /// How far a stick may lean, from 0 to 1, and still be at rest: as
    /// handhelds' sticks rest off center (the Retroid Pocket Flip 2's at
    /// up to 0.19 from it). PERRY_GAMECONTROLLER_DEADZONE sets it; 0.25 by
    /// default.
    nonisolated(unsafe) static let deadZone: Float = {
        guard let setting = getenv("PERRY_GAMECONTROLLER_DEADZONE"), let value = Float(String(cString: setting)) else { return 0.25 }
        return max(0, min(0.9, value))
    }()

    /// A stick's position past the dead zone, measured from the center so
    /// diagonals keep their direction, rescaled to start from zero at its
    /// edge.
    static func stick(_ x: Float, _ y: Float) -> (x: Float, y: Float) {
        let length = (x * x + y * y).squareRoot()
        guard length > deadZone else { return (0, 0) }
        let scale = min(1, (length - deadZone) / (1 - deadZone)) / length
        return (max(-1, min(1, x * scale)), max(-1, min(1, y * scale)))
    }

    // MARK: Setting values and calling handlers

    /// Sets a button, calling its handlers and its profile's when it changed.
    static func set(_ element: GCControllerButtonInput, value: Float, notifyProfile: Bool = true) {
        guard let state = Elements.buttons[element.objcObject], state.value != value else { return }
        let pressed = value > (state.analog ? 0.1 : 0.5)
        if notifyProfile { trace("button \(element.objcObject) \(value) pressed \(pressed)") }
        let pressedChanged = pressed != state.pressed
        (state.value, state.pressed) = (value, pressed)
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer, Float, Bool) -> Void
        if let handler = state.valueChangedHandler { handler.function(as: Invoke.self)(handler.object, element.objcObject, value, pressed) }
        if pressedChanged, let handler = state.pressedChangedHandler {
            handler.function(as: Invoke.self)(handler.object, element.objcObject, value, pressed)
        }
        if notifyProfile { profileChanged(element) }
    }

    static func set(_ element: GCControllerAxisInput, value: Float, notifyProfile: Bool = true) {
        guard let state = Elements.axes[element.objcObject], state.value != value else { return }
        state.value = value
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer, Float) -> Void
        if let handler = state.valueChangedHandler { handler.function(as: Invoke.self)(handler.object, element.objcObject, value) }
        if notifyProfile { profileChanged(element) }
    }

    /// Sets a direction pad's axes and its buttons from them.
    static func set(_ element: GCControllerDirectionPad, x: Float, y: Float) {
        guard let state = Elements.pads[element.objcObject] else { return }
        let old = (Elements.axes[state.xAxis.objcObject]?.value ?? 0, Elements.axes[state.yAxis.objcObject]?.value ?? 0)
        guard old != (x, y) else { return }
        trace("direction pad \(element.objcObject) x \(x) y \(y)")
        set(state.xAxis, value: x, notifyProfile: false)
        set(state.yAxis, value: y, notifyProfile: false)
        set(state.right, value: max(x, 0), notifyProfile: false)
        set(state.left, value: max(-x, 0), notifyProfile: false)
        set(state.up, value: max(y, 0), notifyProfile: false)
        set(state.down, value: max(-y, 0), notifyProfile: false)
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer, Float, Float) -> Void
        if let handler = state.valueChangedHandler { handler.function(as: Invoke.self)(handler.object, element.objcObject, x, y) }
        profileChanged(element)
    }

    /// Each profile's valueChangedHandler, with the element that changed.
    private static func profileChanged(_ element: GCControllerElement) {
        var collection = element.objcObject
        // An element of a direction pad tells the profile the pad changed.
        if let pad = Elements.buttons[collection]?.collection ?? Elements.axes[collection]?.collection { collection = pad }
        for (_, profile) in Profiles.states where profile.elements.contains(where: { $0.objcObject == collection }) {
            for (object, handler) in profile.handlers {
                typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer, UnsafeMutableRawPointer) -> Void
                handler.function(as: Invoke.self)(handler.object, object, collection)
            }
            return
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

// MARK: - Quitting

@ObjCWrapper("UIApplication")
class UIApplication: NSObject {
    @ObjCClassMethod("sharedApplication") static func sharedApplication() -> UIApplication
    @ObjCMethod("delegate") func delegate() -> NSObject?
    @ObjCMethod("_perryTerminate") func sendPerryTerminate()
}

extension NSObject {
    @ObjCMethod("applicationWillResignActive:") func sendApplicationWillResignActive(_ application: UIApplication)
    @ObjCMethod("applicationDidEnterBackground:") func sendApplicationDidEnterBackground(_ application: UIApplication)
    @ObjCMethod("applicationWillTerminate:") func sendApplicationWillTerminate(_ application: UIApplication)
}

/// Leaving the app as iOS has it leave: the delegate resigns active, goes
/// to the background and terminates, so the app saves, then the process
/// exits.
enum Quit {
    nonisolated(unsafe) private static var quitting = false

    static func now() {
        guard !quitting else { return }
        quitting = true
        Controllers.trace("quitting")
        let application = UIApplication.sharedApplication()
        // UIKit's own ending: the scenes and notifications too.
        if application.responds(to: "_perryTerminate") { application.sendPerryTerminate() }
        if let delegate = application.delegate() {
            if delegate.responds(to: "applicationWillResignActive:") { delegate.sendApplicationWillResignActive(application) }
            if delegate.responds(to: "applicationDidEnterBackground:") { delegate.sendApplicationDidEnterBackground(application) }
            if delegate.responds(to: "applicationWillTerminate:") { delegate.sendApplicationWillTerminate(application) }
        }
        exit(0)
    }
}

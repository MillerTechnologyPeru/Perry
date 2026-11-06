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

    // The elements by GameController's input names, as iOS 14 lists them.

    var namedButtons: [(String, GCControllerElement)] {
        let p = profile
        return [("Button A", p.buttonA), ("Button B", p.buttonB), ("Button X", p.buttonX), ("Button Y", p.buttonY),
                ("Left Shoulder", p.leftShoulder), ("Right Shoulder", p.rightShoulder),
                ("Left Trigger", p.leftTrigger), ("Right Trigger", p.rightTrigger),
                ("Left Thumbstick Button", p.leftThumbstickButton), ("Right Thumbstick Button", p.rightThumbstickButton),
                ("Button Menu", p.buttonMenu), ("Button Options", p.buttonOptions), ("Button Home", p.buttonHome)]
    }

    var namedDpads: [(String, GCControllerElement)] {
        [("Direction Pad", profile.dpad), ("Left Thumbstick", profile.leftThumbstick),
         ("Right Thumbstick", profile.rightThumbstick)]
    }

    @ObjCMethod("buttons") func buttons() -> NSObject { Collections.dictionary(namedButtons) }
    @ObjCMethod("dpads") func dpads() -> NSObject { Collections.dictionary(namedDpads) }
    @ObjCMethod("axes") func axes() -> NSObject { Collections.dictionary([]) }
    @ObjCMethod("touchpads") func touchpads() -> NSObject { Collections.dictionary([]) }
    @ObjCMethod("elements") func elements() -> NSObject { Collections.dictionary(namedButtons + namedDpads) }
    @ObjCMethod("allButtons") func allButtons() -> NSObject { Collections.set(namedButtons.map(\.1)) }
    @ObjCMethod("allDpads") func allDpads() -> NSObject { Collections.set(namedDpads.map(\.1)) }
    @ObjCMethod("allAxes") func allAxes() -> NSObject { Collections.set([]) }
    @ObjCMethod("allTouchpads") func allTouchpads() -> NSObject { Collections.set([]) }
    @ObjCMethod("allElements") func allElements() -> NSObject { Collections.set((namedButtons + namedDpads).map(\.1)) }
    @ObjCMethod("objectForKeyedSubscript:") func object(forKeyedSubscript key: String?) -> GCControllerElement? {
        (namedButtons + namedDpads).first { $0.0 == key }?.1
    }
}

/// Foundation collections of elements, autoreleased.
enum Collections {
    typealias Make = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafePointer<UnsafeMutableRawPointer?>?,
                                     UnsafePointer<UnsafeMutableRawPointer?>?, UInt) -> UnsafeMutableRawPointer?
    typealias MakeSet = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafePointer<UnsafeMutableRawPointer?>?,
                                        UInt) -> UnsafeMutableRawPointer?

    static func dictionary(_ entries: [(String, GCControllerElement)]) -> NSObject {
        let keys: [UnsafeMutableRawPointer?] = entries.map { $0.0.objCArgument() }
        let values: [UnsafeMutableRawPointer?] = entries.map { $0.1.objcObject }
        let dictionary = values.withUnsafeBufferPointer { values in
            keys.withUnsafeBufferPointer { keys in
                unsafeBitCast(ObjCRuntime.msgSend, to: Make.self)(ObjCRuntime.classObject("NSDictionary"),
                                                                ObjCRuntime.selector("dictionaryWithObjects:forKeys:count:"),
                                                                values.baseAddress, keys.baseAddress, UInt(values.count))
            }
        }
        return NSObject(objCReturnValue: dictionary)
    }

    static func set(_ elements: [GCControllerElement]) -> NSObject {
        let objects: [UnsafeMutableRawPointer?] = elements.map { $0.objcObject }
        let set = objects.withUnsafeBufferPointer {
            unsafeBitCast(ObjCRuntime.msgSend, to: MakeSet.self)(ObjCRuntime.classObject("NSSet"),
                                                               ObjCRuntime.selector("setWithObjects:count:"),
                                                               $0.baseAddress, UInt($0.count))
        }
        return NSObject(objCReturnValue: set)
    }
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
    /// For UIKit's accelerometer, which older programs read: the stick
    /// that stands for the device's tilt, and the tilt at its end in
    /// radians, as three floats.
    @ObjCClassMethod("_perryTiltStick:")
    static func tiltStick(_ stick: UnsafeMutablePointer<Float>?) {
        Controllers.start()
        let now = Tilt.stick()
        stick?[0] = now.x
        stick?[1] = now.y
        stick?[2] = Float(Tilt.limit)
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
    static let GCInputLeftThumbstickButton = "Left Thumbstick Button"
    static let GCInputRightThumbstickButton = "Right Thumbstick Button"
    static let GCInputXboxPaddleOne = "Paddle 1"
    static let GCInputXboxPaddleTwo = "Paddle 2"
    static let GCInputXboxPaddleThree = "Paddle 3"
    static let GCInputXboxPaddleFour = "Paddle 4"
    static let GCInputDualShockTouchpadOne = "Touchpad 1"
    static let GCInputDualShockTouchpadTwo = "Touchpad 2"
    static let GCInputDualShockTouchpadButton = "Touchpad Button"
    static let GCKeyboardDidConnectNotification = "GCKeyboardDidConnectNotification"
    static let GCKeyboardDidDisconnectNotification = "GCKeyboardDidDisconnectNotification"
    static let GCMouseDidConnectNotification = "GCMouseDidConnectNotification"
    static let GCMouseDidDisconnectNotification = "GCMouseDidDisconnectNotification"
    static let GCMouseDidBecomeCurrentNotification = "GCMouseDidBecomeCurrentNotification"
    static let GCMouseDidStopBeingCurrentNotification = "GCMouseDidStopBeingCurrentNotification"
    static let GCHapticsLocalityDefault = "Default"
    static let GCHapticsLocalityAll = "All"
    static let GCHapticsLocalityHandles = "Handles"
    static let GCHapticsLocalityLeftHandle = "Left Handle"
    static let GCHapticsLocalityRightHandle = "Right Handle"
    static let GCHapticsLocalityTriggers = "Triggers"
    static let GCHapticsLocalityLeftTrigger = "Left Trigger"
    static let GCHapticsLocalityRightTrigger = "Right Trigger"
    static let GCHapticDurationInfinite: Float = .greatestFiniteMagnitude
}

// MARK: - Reading the gamepads

enum Controllers {
    /// The controllers, by object, and in the order they connected.
    nonisolated(unsafe) static var states: [UnsafeMutableRawPointer: ControllerState] = [:]
    nonisolated(unsafe) static var connected: [GCController] = []
    /// The first connected controller's gamepad, for readers on any thread.
    nonisolated(unsafe) private static var firstGamepad: SDL.Pointer?
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
            firstGamepad = connected.first?.controller.gamepad
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
            firstGamepad = connected.first?.controller.gamepad
            NSNotificationCenter.defaultCenter().post(name: ControllerConstants.GCControllerDidConnectNotification, object: controller, userInfo: nil)
        }
        firstGamepad = connected.first?.controller.gamepad
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
        if !touchButtons.isEmpty, controller.objcObject == connected.first?.objcObject { touch(with: gamepad) }
        if !touchSticks.isEmpty, controller.objcObject == connected.first?.objcObject { slide(with: gamepad) }
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

    // MARK: Buttons that stand for touches

    /// With PERRY_GAMECONTROLLER_TOUCHES set to buttons and the points they
    /// touch, in the screen's coordinates ("a=608,329;b=32,327"), a finger
    /// is on the screen at a button's point for as long as the button is
    /// held: for a program whose own buttons only answer to touch. A
    /// button given two points ("a=800,250>800,480") drags: its finger
    /// goes down at the first, moves to the second over a quarter of a
    /// second and stays there until the button is let go, as a plunger is
    /// pulled and released. The buttons are the quit combinations', and
    /// l2, r2, up, down, left and right.
    nonisolated(unsafe) private static let touchButtons: [(name: String, x: Double, y: Double, toX: Double, toY: Double)] = {
        guard let setting = getenv("PERRY_GAMECONTROLLER_TOUCHES") else { return [] }
        return String(cString: setting).lowercased().split(separator: ";").compactMap { entry in
            let sides = entry.split(separator: "=")
            let points = (sides.last ?? "").split(separator: ">").map { point in
                point.split(separator: ",").compactMap { Double($0.filter { $0 != " " }) }
            }
            guard sides.count == 2, let start = points.first, start.count == 2, points.allSatisfy({ $0.count == 2 }) else { return nil }
            let end = points.count > 1 ? points[1] : start
            return (String(sides[0].filter { $0 != " " }), start[0], start[1], end[0], end[1])
        }
    }()

    /// The touch buttons held, by their place in the list, with the reads
    /// since each went down.
    nonisolated(unsafe) private static var touching: [Int: Int] = [:]
    /// The reads a drag takes: a quarter of a second's.
    private static let dragReads = 15

    /// PERRY_GAMECONTROLLER_HOLD, "button,seconds" or "button,from,until",
    /// several separated by semicolons and buttons joined by "+"
    /// ("l2+r2,20,21;a,24,27"): touch buttons held from that long after
    /// the program started, until then if a second time is given, to try
    /// what they touch without pressing them.
    nonisolated(unsafe) private static let pretended: [(names: [String], from: Double, until: Double)] = {
        guard let setting = getenv("PERRY_GAMECONTROLLER_HOLD") else { return [] }
        let start = now()
        return String(cString: setting).lowercased().split(separator: ";").compactMap { entry in
            let parts = entry.split(separator: ",")
            guard let names = parts.first else { return nil }
            return (names.split(separator: "+").map(String.init), start + (parts.count > 1 ? Double(parts[1]) ?? 0 : 0),
                    parts.count > 2 ? start + (Double(parts[2]) ?? 0) : .infinity)
        }
    }()

    /// Whether the button a setting names is held.
    private static func held(_ name: String, on gamepad: SDL.Pointer) -> Bool {
        if !pretended.isEmpty {
            let time = now()
            if pretended.contains(where: { $0.names.contains(name) && time >= $0.from && time < $0.until }) { return true }
        }
        switch name {
        case "l2": return SDL.getGamepadAxis(gamepad, Axis.leftTrigger.rawValue) > 16000
        case "r2": return SDL.getGamepadAxis(gamepad, Axis.rightTrigger.rawValue) > 16000
        case "up": return SDL.getGamepadButton(gamepad, Button.up.rawValue)
        case "down": return SDL.getGamepadButton(gamepad, Button.down.rawValue)
        case "left": return SDL.getGamepadButton(gamepad, Button.left.rawValue)
        case "right": return SDL.getGamepadButton(gamepad, Button.right.rawValue)
        default: return buttonNames[name].map { SDL.getGamepadButton(gamepad, $0.rawValue) } ?? false
        }
    }

    /// Whether the first gamepad's button of that name is held: for
    /// CoreMotion, which a button can shake.
    static func isHeld(_ name: String) -> Bool {
        if !pretended.isEmpty {
            let time = now()
            if pretended.contains(where: { $0.names.contains(name) && time >= $0.from && time < $0.until }) { return true }
        }
        return firstGamepad.map { held(name, on: $0) } ?? false
    }

    /// Puts down and lifts the fingers of the touch buttons that changed,
    /// and moves those that drag.
    private static func touch(with gamepad: SDL.Pointer) {
        for (index, button) in touchButtons.enumerated() {
            let isHeld = held(button.name, on: gamepad)
            func point(_ reads: Int) -> (x: Double, y: Double) {
                let part = Double(min(reads, dragReads)) / Double(dragReads)
                return (button.x + (button.toX - button.x) * part, button.y + (button.toY - button.y) * part)
            }
            if let reads = touching[index] {
                if !isHeld {
                    touching[index] = nil
                    let at = point(reads)
                    trace("touch up at \(at.x), \(at.y) for \(button.name)")
                    finger(index, phase: 2, x: at.x, y: at.y)
                } else if reads < dragReads, button.toX != button.x || button.toY != button.y {
                    touching[index] = reads + 1
                    let at = point(reads + 1)
                    finger(index, phase: 1, x: at.x, y: at.y)
                }
            } else if isHeld {
                touching[index] = 0
                trace("touch down at \(button.x), \(button.y) for \(button.name)")
                finger(index, phase: 0, x: button.x, y: button.y)
            }
        }
    }

    /// With PERRY_GAMECONTROLLER_STICK_TOUCH set to a stick, the point it
    /// rests at and how far it reaches across and down, in the screen's
    /// coordinates ("left=94,272,66,0"), a finger follows the stick: for a
    /// program steered by a slider or a pad drawn on the screen. The finger
    /// goes down at the resting point when the stick leaves its dead zone,
    /// is moved to the stick's place from there, and is lifted when the
    /// stick is let go. The sticks are left and right; several are
    /// separated by semicolons.
    nonisolated(unsafe) private static let touchSticks: [(right: Bool, x: Double, y: Double, across: Double, down: Double)] = {
        guard let setting = getenv("PERRY_GAMECONTROLLER_STICK_TOUCH") else { return [] }
        return String(cString: setting).lowercased().split(separator: ";").compactMap { entry in
            let sides = entry.split(separator: "=")
            let numbers = (sides.last ?? "").split(separator: ",").compactMap { Double($0.filter { $0 != " " }) }
            let name = sides.first.map { $0.filter { $0 != " " } }
            guard sides.count == 2, numbers.count >= 3, name == "left" || name == "right" else { return nil }
            return (name == "right", numbers[0], numbers[1], numbers[2], numbers.count > 3 ? numbers[3] : numbers[2])
        }
    }()

    /// The stick fingers down, by their place in the list.
    nonisolated(unsafe) private static var sliding: Set<Int> = []
    /// Their fingers are numbered after the touch buttons'.
    private static let firstStickFinger = 64

    /// Puts down, moves and lifts the fingers that follow sticks.
    private static func slide(with gamepad: SDL.Pointer) {
        func axis(_ axis: Axis) -> Float { max(-1, min(1, Float(SDL.getGamepadAxis(gamepad, axis.rawValue)) / 32767)) }
        for (index, pad) in touchSticks.enumerated() {
            let value = pad.right ? stick(axis(.rightX), -axis(.rightY)) : stick(axis(.leftX), -axis(.leftY))
            let at = (x: pad.x + Double(value.x) * pad.across, y: pad.y - Double(value.y) * pad.down)
            if value.x == 0, value.y == 0 {
                if sliding.remove(index) != nil {
                    trace("stick touch up at \(pad.x), \(pad.y)")
                    finger(firstStickFinger + index, phase: 2, x: pad.x, y: pad.y)
                }
            } else if sliding.contains(index) {
                finger(firstStickFinger + index, phase: 1, x: at.x, y: at.y)
            } else {
                // Down where the stick rests, which is where a slider's
                // knob is, and on from there at the next read.
                sliding.insert(index)
                trace("stick touch down at \(pad.x), \(pad.y)")
                finger(firstStickFinger + index, phase: 0, x: pad.x, y: pad.y)
            }
        }
    }

    /// Sends UIKit a finger of ours, numbered apart from a touchscreen's.
    private static func finger(_ index: Int, phase: Int, x: Double, y: Double) {
        typealias Send = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> UnsafeMutableRawPointer?
        typealias SendFinger = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UInt, Int, Double.ObjCType,
                                               Double.ObjCType) -> Void
        guard let cls = "UIApplication".withCString({ ObjCRuntime.functions.getClass($0) }),
              let application = unsafeBitCast(ObjCRuntime.msgSend, to: Send.self)(cls, ObjCRuntime.selector("sharedApplication"))
        else { return }
        // "perry" in the number's high bytes, as many as a word has; the
        // points as Darwin passes floating point.
        let ours = UInt(truncatingIfNeeded: UInt64(0x7065_7272_7900_0000) >> UInt64(64 - UInt.bitWidth))
        unsafeBitCast(ObjCRuntime.msgSend, to: SendFinger.self)(
            application, ObjCRuntime.selector("_perryFinger:phase:x:y:"), ours + UInt(index), phase, x.objCArgument(),
            y.objCArgument())
    }

    private static let buttonNames: [String: Button] = [
        "home": .guide, "guide": .guide, "select": .back, "back": .back, "start": .start, "a": .south, "b": .east,
        "x": .west, "y": .north, "l1": .leftShoulder, "r1": .rightShoulder, "l3": .leftStick, "r3": .rightStick,
    ]

    /// With PERRY_GAMECONTROLLER_QUIT set to buttons joined by "+" (home,
    /// select, start, a, b, x, y, l1, r1, l3, r3), holding them all quits
    /// the app, as handhelds' ports quit with home and select; several
    /// combinations, separated by commas, each quit.
    nonisolated(unsafe) private static let quitButtons: [[Button]] = {
        guard let setting = getenv("PERRY_GAMECONTROLLER_QUIT") else { return [] }
        let names = buttonNames
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

    /// How much a stick's lean counts for: PERRY_GAMECONTROLLER_SENSITIVITY
    /// multiplies it, so that at 2 half the way out is all the way; 1 by
    /// default. For sticks that don't reach their edge, and games that
    /// steer little for a full lean.
    nonisolated(unsafe) static let sensitivity: Float = {
        guard let setting = getenv("PERRY_GAMECONTROLLER_SENSITIVITY"), let value = Float(String(cString: setting)) else { return 1 }
        return max(0.1, min(10, value))
    }()

    /// A stick's position past the dead zone, measured from the center so
    /// diagonals keep their direction, rescaled to start from zero at its
    /// edge, and multiplied by the sensitivity.
    /// The first gamepad's left stick now, up and right positive; at rest
    /// without a gamepad. For CoreMotion, which takes it for a tilt.
    static func leftStick() -> (x: Float, y: Float) {
        guard let gamepad = firstGamepad else { return (0, 0) }
        func axis(_ axis: Axis) -> Float { max(-1, min(1, Float(SDL.getGamepadAxis(gamepad, axis.rawValue)) / 32767)) }
        return stick(axis(.leftX), -axis(.leftY))
    }

    static func stick(_ x: Float, _ y: Float) -> (x: Float, y: Float) {
        let length = (x * x + y * y).squareRoot()
        guard length > deadZone else { return (0, 0) }
        let scale = min(1, sensitivity * (length - deadZone) / (1 - deadZone)) / length
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

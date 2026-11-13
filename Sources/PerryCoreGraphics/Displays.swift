import CPerryGeometry
import Glibc
import PerryObjCInterop
import SDL3Swift

// Mac apps' alone: iOS has no display services or CGEvent, so armv7, which
// runs only iOS apps, has none of this.
#if !arch(arm)
// Quartz Display Services and the cursor, as games ask about the screen:
// one display, the primary one SDL3 reports, with its desktop mode and the full-screen modes
// SDL lists. Points are SDL's window coordinates, global coordinates have
// their origin at the display's top left, as Quartz's do. Without SDL or a
// display it is 1920 by 1080 at 60 Hz. Gamma tables are the identity and
// can't be changed; events made with CGEvent aren't posted anywhere.

/// The main display's CGDirectDisplayID.
private let mainDisplay: UInt32 = 1
/// kCGErrorSuccess, kCGErrorIllegalArgument.
private let success: Int32 = 0
private let illegalArgument: Int32 = 1001

/// A display mode: its size in points and pixels and its refresh rate.
final class DisplayModeState {
    let width: Int, height: Int, pixelWidth: Int, pixelHeight: Int
    let refreshRate: Double

    init(width: Int, height: Int, density: Double, refreshRate: Double) {
        (self.width, self.height) = (width, height)
        pixelWidth = Int((Double(width) * density).rounded())
        pixelHeight = Int((Double(height) * density).rounded())
        self.refreshRate = refreshRate
    }
}

@ObjCClass("CGDisplayMode")
public final class CGDisplayModeObject: NSObject {
    static let states = StateTable<DisplayModeState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        CGDisplayModeObject.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CGDisplayModeObject.objCClass.pointer)
    }
}

enum Displays {
    /// SDL3, started for its displays; nil without a display or when SDL can't start.
    nonisolated(unsafe) private static let display: SDLVideoDisplay? = {
        guard getenv("DISPLAY") != nil || getenv("WAYLAND_DISPLAY") != nil else { return nil }
        guard (try? SDL.initialize(subSystems: [.video])) != nil else { return nil }
        let primary = SDLVideoDisplay.primary
        return primary.rawValue == 0 ? nil : primary
    }()

    private static func mode(_ found: SDLDisplayMode) -> DisplayModeState {
        let density = found.pixelDensity, rate = found.refreshRate
        return DisplayModeState(width: found.width, height: found.height, density: density > 0 ? density : 1, refreshRate: rate > 0 ? rate : 60)
    }

    static var bounds: CGRect {
        let fallback = CGRect(origin: CGPoint(x: 0, y: 0), size: CGSize(width: 1920, height: 1080))
        guard let display, let rect = try? display.bounds else { return fallback }
        return CGRect(origin: CGPoint(x: CGFloat(rect.x), y: CGFloat(rect.y)), size: CGSize(width: CGFloat(rect.width), height: CGFloat(rect.height)))
    }

    static var current: DisplayModeState {
        if let display, let desktop = try? SDLDisplayMode(display: display) { return mode(desktop) }
        return DisplayModeState(width: Int(bounds.size.width), height: Int(bounds.size.height), density: 1, refreshRate: 60)
    }

    /// The full-screen modes, the desktop's first.
    static var all: [DisplayModeState] {
        var modes = [current]
        for found in (try? display?.modes()) ?? [] {
            let state = mode(found)
            if !modes.contains(where: { $0.width == state.width && $0.height == state.height && $0.refreshRate == state.refreshRate }) {
                modes.append(state)
            }
        }
        return modes
    }

    static func object(_ state: DisplayModeState) -> Ref { makeObject(CGDisplayModeObject.objCClass, CGDisplayModeObject.states, state) }

    static func warp(to point: CGPoint) { if display != nil { try? SDL.warpMouse(toGlobal: (Float(point.x), Float(point.y))) } }

    static var mouse: CGPoint {
        guard display != nil else { return CGPoint(x: 0, y: 0) }
        let state = SDL.globalMouseState
        return CGPoint(x: CGFloat(state.x), y: CGFloat(state.y))
    }
}

// MARK: - Displays

@c(_CGMainDisplayID) public func CGMainDisplayID() -> UInt32 { mainDisplay }

private func list(_ capacity: UInt32, _ displays: UnsafeMutablePointer<UInt32>?, _ count: UnsafeMutablePointer<UInt32>?) -> Int32 {
    if let displays, capacity > 0 { displays[0] = mainDisplay }
    count?.pointee = displays == nil ? 1 : min(capacity, 1)
    return success
}

@c(_CGGetOnlineDisplayList)
public func CGGetOnlineDisplayList(_ capacity: UInt32, _ displays: UnsafeMutablePointer<UInt32>?, _ count: UnsafeMutablePointer<UInt32>?) -> Int32 {
    list(capacity, displays, count)
}

@c(_CGGetActiveDisplayList)
public func CGGetActiveDisplayList(_ capacity: UInt32, _ displays: UnsafeMutablePointer<UInt32>?, _ count: UnsafeMutablePointer<UInt32>?) -> Int32 {
    list(capacity, displays, count)
}

@c(_CGGetDisplaysWithPoint)
public func CGGetDisplaysWithPoint(_ point: CGPoint, _ capacity: UInt32, _ displays: UnsafeMutablePointer<UInt32>?,
                                   _ count: UnsafeMutablePointer<UInt32>?) -> Int32 {
    list(capacity, displays, count)
}

@c(_CGDisplayBounds) public func CGDisplayBounds(_ display: UInt32) -> CGRect { Displays.bounds }
@c(_CGDisplayPixelsWide) public func CGDisplayPixelsWide(_ display: UInt32) -> Int { Int(Displays.bounds.size.width) }
@c(_CGDisplayPixelsHigh) public func CGDisplayPixelsHigh(_ display: UInt32) -> Int { Int(Displays.bounds.size.height) }

/// The display's size in millimeters, as if 96 points an inch.
@c(_CGDisplayScreenSize)
public func CGDisplayScreenSize(_ display: UInt32) -> CGSize {
    let bounds = Displays.bounds
    return CGSize(width: bounds.size.width / 96 * 25.4, height: bounds.size.height / 96 * 25.4)
}

@c(_CGDisplayIsMain) public func CGDisplayIsMain(_ display: UInt32) -> UInt32 { display == mainDisplay ? 1 : 0 }
@c(_CGDisplayIsActive) public func CGDisplayIsActive(_ display: UInt32) -> UInt32 { display == mainDisplay ? 1 : 0 }
@c(_CGDisplayIsOnline) public func CGDisplayIsOnline(_ display: UInt32) -> UInt32 { display == mainDisplay ? 1 : 0 }
@c(_CGDisplayIsBuiltin) public func CGDisplayIsBuiltin(_ display: UInt32) -> UInt32 { 0 }
@c(_CGDisplayIsInMirrorSet) public func CGDisplayIsInMirrorSet(_ display: UInt32) -> UInt32 { 0 }
@c(_CGDisplayIsAsleep) public func CGDisplayIsAsleep(_ display: UInt32) -> UInt32 { 0 }
@c(_CGDisplayMirrorsDisplay) public func CGDisplayMirrorsDisplay(_ display: UInt32) -> UInt32 { 0 }
@c(_CGDisplayPrimaryDisplay) public func CGDisplayPrimaryDisplay(_ display: UInt32) -> UInt32 { mainDisplay }
@c(_CGDisplayUnitNumber) public func CGDisplayUnitNumber(_ display: UInt32) -> UInt32 { 0 }
@c(_CGDisplayVendorNumber) public func CGDisplayVendorNumber(_ display: UInt32) -> UInt32 { 0 }
@c(_CGDisplayModelNumber) public func CGDisplayModelNumber(_ display: UInt32) -> UInt32 { 0 }
@c(_CGDisplaySerialNumber) public func CGDisplaySerialNumber(_ display: UInt32) -> UInt32 { 0 }
@c(_CGDisplayRotation) public func CGDisplayRotation(_ display: UInt32) -> Double { 0 }

/// Displays aren't reconfigured here: the callback is never called.
@c(_CGDisplayRegisterReconfigurationCallback)
public func CGDisplayRegisterReconfigurationCallback(_ callback: UnsafeRawPointer?, _ info: UnsafeMutableRawPointer?) -> Int32 { success }

@c(_CGDisplayRemoveReconfigurationCallback)
public func CGDisplayRemoveReconfigurationCallback(_ callback: UnsafeRawPointer?, _ info: UnsafeMutableRawPointer?) -> Int32 { success }

/// The display's Metal device: none, as MTLCreateSystemDefaultDevice
/// answers here.
@c(_CGDirectDisplayCopyCurrentMetalDevice)
public func CGDirectDisplayCopyCurrentMetalDevice(_ display: UInt32) -> Ref? { nil }

// MARK: - Display modes

@c(_CGDisplayCopyDisplayMode) public func CGDisplayCopyDisplayMode(_ display: UInt32) -> Ref? { Displays.object(Displays.current) }

@c(_CGDisplayCopyAllDisplayModes)
public func CGDisplayCopyAllDisplayModes(_ display: UInt32, _ options: Ref?) -> Ref? {
    let modes = Displays.all.map { state -> NSObject in
        let object = Displays.object(state)
        defer { ObjCRuntime.release(object) }
        return NSObject(object)
    }
    return NSMutableArray.of(modes).objCOwnedReturnValue()
}

/// Modes can't be changed: the current one stays.
@c(_CGDisplaySetDisplayMode)
public func CGDisplaySetDisplayMode(_ display: UInt32, _ mode: Ref?, _ options: Ref?) -> Int32 { success }

private func mode(_ object: Ref?) -> DisplayModeState? { CGDisplayModeObject.states[object] }

@c(_CGDisplayModeGetWidth) public func CGDisplayModeGetWidth(_ object: Ref?) -> Int { mode(object)?.width ?? 0 }
@c(_CGDisplayModeGetHeight) public func CGDisplayModeGetHeight(_ object: Ref?) -> Int { mode(object)?.height ?? 0 }
@c(_CGDisplayModeGetPixelWidth) public func CGDisplayModeGetPixelWidth(_ object: Ref?) -> Int { mode(object)?.pixelWidth ?? 0 }
@c(_CGDisplayModeGetPixelHeight) public func CGDisplayModeGetPixelHeight(_ object: Ref?) -> Int { mode(object)?.pixelHeight ?? 0 }
@c(_CGDisplayModeGetRefreshRate) public func CGDisplayModeGetRefreshRate(_ object: Ref?) -> Double { mode(object)?.refreshRate ?? 0 }
/// kDisplayModeValidFlag, kDisplayModeSafeFlag and kDisplayModeDefaultFlag.
@c(_CGDisplayModeGetIOFlags) public func CGDisplayModeGetIOFlags(_ object: Ref?) -> UInt32 { mode(object) == nil ? 0 : 0x7 }
@c(_CGDisplayModeGetIODisplayModeID) public func CGDisplayModeGetIODisplayModeID(_ object: Ref?) -> Int32 { 0 }
@c(_CGDisplayModeIsUsableForDesktopGUI) public func CGDisplayModeIsUsableForDesktopGUI(_ object: Ref?) -> Bool { mode(object) != nil }
@c(_CGDisplayModeRetain) public func CGDisplayModeRetain(_ object: Ref?) -> Ref? { ObjCRuntime.retain(object) }
@c(_CGDisplayModeRelease) public func CGDisplayModeRelease(_ object: Ref?) { ObjCRuntime.release(object) }
@c(_CGDisplayModeGetTypeID) public func CGDisplayModeGetTypeID() -> UInt { 0x10a }

// MARK: - Gamma

@c(_CGDisplayGammaTableCapacity) public func CGDisplayGammaTableCapacity(_ display: UInt32) -> UInt32 { 256 }

@c(_CGGetDisplayTransferByTable)
public func CGGetDisplayTransferByTable(_ display: UInt32, _ capacity: UInt32, _ red: UnsafeMutablePointer<Float>?,
                                        _ green: UnsafeMutablePointer<Float>?, _ blue: UnsafeMutablePointer<Float>?,
                                        _ count: UnsafeMutablePointer<UInt32>?) -> Int32 {
    let entries = min(capacity, 256)
    for index in 0..<Int(entries) {
        let value = entries > 1 ? Float(index) / Float(entries - 1) : 1
        red?[index] = value
        green?[index] = value
        blue?[index] = value
    }
    count?.pointee = entries
    return success
}

@c(_CGSetDisplayTransferByTable)
public func CGSetDisplayTransferByTable(_ display: UInt32, _ size: UInt32, _ red: UnsafePointer<Float>?, _ green: UnsafePointer<Float>?,
                                        _ blue: UnsafePointer<Float>?) -> Int32 { success }

@c(_CGSetDisplayTransferByFormula)
public func CGSetDisplayTransferByFormula(_ display: UInt32, _ redMin: Float, _ redMax: Float, _ redGamma: Float, _ greenMin: Float,
                                          _ greenMax: Float, _ greenGamma: Float, _ blueMin: Float, _ blueMax: Float,
                                          _ blueGamma: Float) -> Int32 { success }

@c(_CGDisplayRestoreColorSyncSettings) public func CGDisplayRestoreColorSyncSettings() {}

// MARK: - Capture and the cursor

@c(_CGDisplayCapture) public func CGDisplayCapture(_ display: UInt32) -> Int32 { success }
@c(_CGDisplayRelease) public func CGDisplayRelease(_ display: UInt32) -> Int32 { success }
@c(_CGCaptureAllDisplays) public func CGCaptureAllDisplays() -> Int32 { success }
@c(_CGReleaseAllDisplays) public func CGReleaseAllDisplays() -> Int32 { success }
@c(_CGDisplayHideCursor) public func CGDisplayHideCursor(_ display: UInt32) -> Int32 { success }
@c(_CGDisplayShowCursor) public func CGDisplayShowCursor(_ display: UInt32) -> Int32 { success }
@c(_CGDisplayMoveCursorToPoint)
public func CGDisplayMoveCursorToPoint(_ display: UInt32, _ point: CGPoint) -> Int32 {
    Displays.warp(to: point)
    return success
}

@c(_CGWarpMouseCursorPosition)
public func CGWarpMouseCursorPosition(_ point: CGPoint) -> Int32 {
    Displays.warp(to: point)
    return success
}

/// The cursor stays tied to the mouse; apps that untie it for relative
/// motion read SDL's relative deltas through AppKit's events anyway.
@c(_CGAssociateMouseAndMouseCursorPosition)
public func CGAssociateMouseAndMouseCursorPosition(_ connected: UInt32) -> Int32 { success }

@c(_CGCursorIsVisible) public func CGCursorIsVisible() -> UInt32 { 1 }

// MARK: - Events

/// A CGEvent: where it happened and its flags. Events aren't posted.
final class EventState {
    var location = CGPoint(x: 0, y: 0)
    var flags: UInt64 = 0
}

@ObjCClass("CGEvent")
public final class CGEventObject: NSObject {
    static let states = StateTable<EventState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        CGEventObject.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CGEventObject.objCClass.pointer)
    }
}

@ObjCClass("CGEventSource")
public final class CGEventSourceObject: NSObject {}

private func event(at location: CGPoint) -> Ref {
    let state = EventState()
    state.location = location
    return makeObject(CGEventObject.objCClass, CGEventObject.states, state)
}

@c(_CGEventSourceCreate)
public func CGEventSourceCreate(_ state: Int32) -> Ref? {
    let source = NSObject(CGEventSourceObject.objCClass.pointer).newInstance()
    return withExtendedLifetime(source) { ObjCRuntime.retain(source.objcObject) }
}
@c(_CGEventSourceKeyState) public func CGEventSourceKeyState(_ state: Int32, _ key: UInt16) -> Bool { false }
@c(_CGEventSourceButtonState) public func CGEventSourceButtonState(_ state: Int32, _ button: UInt32) -> Bool { false }
@c(_CGEventSourceFlagsState) public func CGEventSourceFlagsState(_ state: Int32) -> UInt64 { 0 }
@c(_CGEventSourceSetLocalEventsSuppressionInterval)
public func CGEventSourceSetLocalEventsSuppressionInterval(_ source: Ref?, _ seconds: Double) {}

/// A null event, where the mouse is now.
@c(_CGEventCreate) public func CGEventCreate(_ source: Ref?) -> Ref? { event(at: Displays.mouse) }

@c(_CGEventCreateMouseEvent)
public func CGEventCreateMouseEvent(_ source: Ref?, _ type: UInt32, _ location: CGPoint, _ button: UInt32) -> Ref? { event(at: location) }

@c(_CGEventCreateKeyboardEvent)
public func CGEventCreateKeyboardEvent(_ source: Ref?, _ key: UInt16, _ down: Bool) -> Ref? { event(at: Displays.mouse) }

/// Variadic in C: the wheel counts that follow are in registers, unread.
@c(_CGEventCreateScrollWheelEvent)
public func CGEventCreateScrollWheelEvent(_ source: Ref?, _ units: UInt32, _ count: UInt32, _ first: Int32) -> Ref? { event(at: Displays.mouse) }

@c(_CGEventGetLocation) public func CGEventGetLocation(_ object: Ref?) -> CGPoint { CGEventObject.states[object]?.location ?? Displays.mouse }
@c(_CGEventSetLocation) public func CGEventSetLocation(_ object: Ref?, _ location: CGPoint) { CGEventObject.states[object]?.location = location }
@c(_CGEventGetFlags) public func CGEventGetFlags(_ object: Ref?) -> UInt64 { CGEventObject.states[object]?.flags ?? 0 }
@c(_CGEventSetFlags) public func CGEventSetFlags(_ object: Ref?, _ flags: UInt64) { CGEventObject.states[object]?.flags = flags }
@c(_CGEventSetIntegerValueField) public func CGEventSetIntegerValueField(_ object: Ref?, _ field: UInt32, _ value: Int64) {}
@c(_CGEventGetIntegerValueField) public func CGEventGetIntegerValueField(_ object: Ref?, _ field: UInt32) -> Int64 { 0 }
@c(_CGEventSetType) public func CGEventSetType(_ object: Ref?, _ type: UInt32) {}
@c(_CGEventPost) public func CGEventPost(_ tap: UInt32, _ object: Ref?) {}

// MARK: - The session

/// The login session: on the console, as a game in front of its user is.
@c(_CGSessionCopyCurrentDictionary)
public func CGSessionCopyCurrentDictionary() -> Ref? {
    NSMutableDictionary.of([("kCGSSessionOnConsoleKey", NSNumber.make(bool: true)),
                            ("kCGSSessionUserIDKey", NSObject.number(Int(getuid())))]).objCOwnedReturnValue()
}

#endif

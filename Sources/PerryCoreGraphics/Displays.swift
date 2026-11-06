import CPerryGeometry
import Glibc
import PerryObjCInterop

// Quartz Display Services and the cursor, as games ask about the screen:
// one display, the primary one SDL3 reports (loaded at run time, as
// AppKit's windows do), with its desktop mode and the full-screen modes
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
    private struct SDLFunctions {
        var initialize: @convention(c) (UInt32) -> Bool
        var primaryDisplay: @convention(c) () -> UInt32
        var displayBounds: @convention(c) (UInt32, UnsafeMutablePointer<Int32>?) -> Bool
        var desktopMode: @convention(c) (UInt32) -> UnsafeRawPointer?
        var fullscreenModes: (@convention(c) (UInt32, UnsafeMutablePointer<Int32>?) -> UnsafeMutablePointer<UnsafeRawPointer?>?)?
        var free: (@convention(c) (UnsafeMutableRawPointer?) -> Void)?
        var warpMouseGlobal: (@convention(c) (Float, Float) -> Bool)?
        var globalMouseState: (@convention(c) (UnsafeMutablePointer<Float>?, UnsafeMutablePointer<Float>?) -> UInt32)?
    }

    /// SDL3, started for its displays; nil without it or a display.
    nonisolated(unsafe) private static let sdl: (functions: SDLFunctions, display: UInt32)? = {
        guard getenv("DISPLAY") != nil || getenv("WAYLAND_DISPLAY") != nil, let library = dlopen("libSDL3.so.0", RTLD_NOW) else { return nil }
        func bind<T>(_ name: String, _ type: T.Type) -> T? { dlsym(library, name).map { unsafeBitCast($0, to: T.self) } }
        guard let initialize = bind("SDL_Init", (@convention(c) (UInt32) -> Bool).self),
              let primary = bind("SDL_GetPrimaryDisplay", (@convention(c) () -> UInt32).self),
              let bounds = bind("SDL_GetDisplayBounds", (@convention(c) (UInt32, UnsafeMutablePointer<Int32>?) -> Bool).self),
              let desktop = bind("SDL_GetDesktopDisplayMode", (@convention(c) (UInt32) -> UnsafeRawPointer?).self) else { return nil }
        let functions = SDLFunctions(
            initialize: initialize, primaryDisplay: primary, displayBounds: bounds, desktopMode: desktop,
            fullscreenModes: bind("SDL_GetFullscreenDisplayModes",
                                  (@convention(c) (UInt32, UnsafeMutablePointer<Int32>?) -> UnsafeMutablePointer<UnsafeRawPointer?>?).self),
            free: bind("SDL_free", (@convention(c) (UnsafeMutableRawPointer?) -> Void).self),
            warpMouseGlobal: bind("SDL_WarpMouseGlobal", (@convention(c) (Float, Float) -> Bool).self),
            globalMouseState: bind("SDL_GetGlobalMouseState", (@convention(c) (UnsafeMutablePointer<Float>?, UnsafeMutablePointer<Float>?) -> UInt32).self))
        // SDL_INIT_VIDEO.
        guard functions.initialize(0x20) else { return nil }
        let display = functions.primaryDisplay()
        return display == 0 ? nil : (functions, display)
    }()

    /// An SDL_DisplayMode: w and h at 8 and 12, pixel_density and
    /// refresh_rate at 16 and 20.
    private static func mode(_ raw: UnsafeRawPointer) -> DisplayModeState {
        let density = Double(raw.load(fromByteOffset: 16, as: Float.self)), rate = Double(raw.load(fromByteOffset: 20, as: Float.self))
        return DisplayModeState(width: Int(raw.load(fromByteOffset: 8, as: Int32.self)), height: Int(raw.load(fromByteOffset: 12, as: Int32.self)),
                                density: density > 0 ? density : 1, refreshRate: rate > 0 ? rate : 60)
    }

    static var bounds: CGRect {
        guard let sdl else { return CGRect(origin: CGPoint(x: 0, y: 0), size: CGSize(width: 1920, height: 1080)) }
        var rect = [Int32](repeating: 0, count: 4)
        guard sdl.functions.displayBounds(sdl.display, &rect) else { return CGRect(origin: CGPoint(x: 0, y: 0), size: CGSize(width: 1920, height: 1080)) }
        return CGRect(origin: CGPoint(x: CGFloat(rect[0]), y: CGFloat(rect[1])), size: CGSize(width: CGFloat(rect[2]), height: CGFloat(rect[3])))
    }

    static var current: DisplayModeState {
        if let sdl, let raw = sdl.functions.desktopMode(sdl.display) { return mode(raw) }
        return DisplayModeState(width: Int(bounds.size.width), height: Int(bounds.size.height), density: 1, refreshRate: 60)
    }

    /// The full-screen modes, the desktop's first.
    static var all: [DisplayModeState] {
        var modes = [current]
        if let sdl, let list = sdl.functions.fullscreenModes {
            var count: Int32 = 0
            if let array = list(sdl.display, &count) {
                for index in 0..<Int(count) {
                    guard let raw = array[index] else { continue }
                    let found = mode(raw)
                    if !modes.contains(where: { $0.width == found.width && $0.height == found.height && $0.refreshRate == found.refreshRate }) {
                        modes.append(found)
                    }
                }
                sdl.functions.free?(array)
            }
        }
        return modes
    }

    static func object(_ state: DisplayModeState) -> Ref { makeObject(CGDisplayModeObject.objCClass, CGDisplayModeObject.states, state) }

    static func warp(to point: CGPoint) { _ = sdl?.functions.warpMouseGlobal?(Float(point.x), Float(point.y)) }

    static var mouse: CGPoint {
        var x: Float = 0, y: Float = 0
        _ = sdl?.functions.globalMouseState?(&x, &y)
        return CGPoint(x: CGFloat(x), y: CGFloat(y))
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

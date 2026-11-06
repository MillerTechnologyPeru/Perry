import CPerryGeometry
import Glibc
import PerryInterface
import PerryObjCInterop

// libPerryAppKit: the provider for AppKit.framework, for macOS apps. Its
// application runs the app's event loop over an SDL3 window per NSWindow,
// whose events become NSEvents; its views are backed by QuartzCore's
// layers, which QuartzCore composites into the window as it does UIKit's.
// PerryProviderPlugin generates the entry points from the module's
// Objective-C declarations; this file binds libobjc, libdispatch,
// CoreFoundation's run loop and QuartzCore first.

private let libobjc = "/usr/lib/libobjc.A.dylib"
private let libdispatch = "/usr/lib/system/libdispatch.dylib"
private let coreFoundation = "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"
let quartzCore = "/System/Library/Frameworks/QuartzCore.framework/QuartzCore"

func providerWillStart(_ info: perry_startup_info) -> Bool {
    guard info.version >= 2, let lookup = info.lookup_symbol else { return false }
    func symbol(_ library: String, _ name: String) -> UnsafeMutableRawPointer? {
        library.withCString { library in name.withCString { lookup(library, $0) } }
    }
    // Before the app's code runs, as an app's own SDL reads the environment.
    SDL.prepareEnvironment()
    guard ObjCRuntime.load({ symbol(libobjc, $0) }), ObjCRuntime.functions.getClass("NSString") != nil else {
        appKitFatal("AppKit needs libPerryobjc and libPerryFoundation, which are missing or incomplete")
    }
    Methods.implementation = symbol(libobjc, "_class_getMethodImplementation").map { unsafeBitCast($0, to: Methods.Implementation.self) }
    guard Methods.implementation != nil, Dispatch.load({ symbol(libdispatch, $0) }) else {
        appKitFatal("AppKit needs libdispatch's main queue")
    }
    guard RunLoop.load({ symbol(coreFoundation, $0) }) else { appKitFatal("AppKit needs CoreFoundation's run loop") }
    guard QuartzCore.load({ symbol(quartzCore, $0) }) else {
        appKitFatal("AppKit needs libPerryQuartzCore, which is missing or incomplete")
    }
    return true
}

/// AppKit's structure constants, which the loader asks for while binding
/// images.
func providerSymbol(_ name: String) -> UnsafeMutableRawPointer? { StructureConstants.values[name] }

enum StructureConstants {
    nonisolated(unsafe) static let values: [String: UnsafeMutableRawPointer] = {
        func value<T>(_ value: T) -> UnsafeMutableRawPointer {
            let storage = UnsafeMutablePointer<T>.allocate(capacity: 1)
            storage.initialize(to: value)
            return UnsafeMutableRawPointer(storage)
        }
        return [
            // NSAppKitVersionNumber: macOS 14's.
            "_NSAppKitVersionNumber": value(Double(2487)),
        ]
    }()
}

/// The application, as the NSApp global holds it; and the string constants
/// apps read.
@ObjCConstants
enum Constants {
    /// Set when the shared application is made.
    nonisolated(unsafe) static let NSApp: UnsafeMutableRawPointer? = nil
    static let NSApplicationDidFinishLaunchingNotification = "NSApplicationDidFinishLaunchingNotification"
    static let NSApplicationWillFinishLaunchingNotification = "NSApplicationWillFinishLaunchingNotification"
    static let NSApplicationDidBecomeActiveNotification = "NSApplicationDidBecomeActiveNotification"
    static let NSApplicationWillBecomeActiveNotification = "NSApplicationWillBecomeActiveNotification"
    static let NSApplicationDidResignActiveNotification = "NSApplicationDidResignActiveNotification"
    static let NSApplicationWillResignActiveNotification = "NSApplicationWillResignActiveNotification"
    static let NSApplicationWillTerminateNotification = "NSApplicationWillTerminateNotification"
    static let NSApplicationDidHideNotification = "NSApplicationDidHideNotification"
    static let NSApplicationDidUnhideNotification = "NSApplicationDidUnhideNotification"
    static let NSApplicationDidChangeScreenParametersNotification = "NSApplicationDidChangeScreenParametersNotification"
    static let NSApplicationLaunchUserNotificationKey = "NSApplicationLaunchUserNotificationKey"
    static let NSApplicationLaunchIsDefaultLaunchKey = "NSApplicationLaunchIsDefaultLaunchKey"
    static let NSWindowDidBecomeKeyNotification = "NSWindowDidBecomeKeyNotification"
    static let NSWindowDidResignKeyNotification = "NSWindowDidResignKeyNotification"
    static let NSWindowDidBecomeMainNotification = "NSWindowDidBecomeMainNotification"
    static let NSWindowDidResignMainNotification = "NSWindowDidResignMainNotification"
    static let NSWindowDidResizeNotification = "NSWindowDidResizeNotification"
    static let NSWindowDidMoveNotification = "NSWindowDidMoveNotification"
    static let NSWindowWillCloseNotification = "NSWindowWillCloseNotification"
    static let NSWindowDidChangeScreenNotification = "NSWindowDidChangeScreenNotification"
    static let NSWindowDidChangeBackingPropertiesNotification = "NSWindowDidChangeBackingPropertiesNotification"
    static let NSWindowDidEnterFullScreenNotification = "NSWindowDidEnterFullScreenNotification"
    static let NSWindowDidExitFullScreenNotification = "NSWindowDidExitFullScreenNotification"
    static let NSWindowWillEnterFullScreenNotification = "NSWindowWillEnterFullScreenNotification"
    static let NSWindowWillExitFullScreenNotification = "NSWindowWillExitFullScreenNotification"
    static let NSWindowDidMiniaturizeNotification = "NSWindowDidMiniaturizeNotification"
    static let NSWindowDidDeminiaturizeNotification = "NSWindowDidDeminiaturizeNotification"
    static let NSWindowDidChangeOcclusionStateNotification = "NSWindowDidChangeOcclusionStateNotification"
    static let NSViewFrameDidChangeNotification = "NSViewFrameDidChangeNotification"
    static let NSViewBoundsDidChangeNotification = "NSViewBoundsDidChangeNotification"
    static let NSModalPanelRunLoopMode = "NSModalPanelRunLoopMode"
    static let NSEventTrackingRunLoopMode = "NSEventTrackingRunLoopMode"
    static let NSPasteboardTypeString = "public.utf8-plain-text"
    static let NSPasteboardTypeURL = "public.url"
    static let NSPasteboardTypeFileURL = "public.file-url"
    static let NSPasteboardTypePNG = "public.png"
    static let NSDocumentTypeDocumentAttribute = "DocumentType"
    static let NSHTMLTextDocumentType = "NSHTML"
    static let NSPlainTextDocumentType = "NSPlainText"
    static let NSRTFTextDocumentType = "NSRTF"
    static let NSCharacterEncodingDocumentAttribute = "CharacterEncoding"
    static let NSFontAttributeName = "NSFont"
    static let NSForegroundColorAttributeName = "NSColor"
    static let NSBackgroundColorAttributeName = "NSBackgroundColor"
    static let NSParagraphStyleAttributeName = "NSParagraphStyle"
    static let NSLinkAttributeName = "NSLink"
    static let NSImageNameTouchBarPlayTemplate = "NSTouchBarPlayTemplate"
    static let NSImageNameTouchBarPauseTemplate = "NSTouchBarPauseTemplate"
    static let NSImageNameCaution = "NSCaution"
    static let NSImageNameApplicationIcon = "NSApplicationIcon"
    static let NSTouchBarItemIdentifierFixedSpaceSmall = "NSTouchBarItemIdentifierFixedSpaceSmall"
    static let NSTouchBarItemIdentifierFixedSpaceLarge = "NSTouchBarItemIdentifierFixedSpaceLarge"
    static let NSTouchBarItemIdentifierFlexibleSpace = "NSTouchBarItemIdentifierFlexibleSpace"
    static let NSTouchBarItemIdentifierOtherItemsProxy = "NSTouchBarItemIdentifierOtherItemsProxy"
    static let NSWorkspaceDidActivateApplicationNotification = "NSWorkspaceDidActivateApplicationNotification"
    static let NSWorkspaceDidWakeNotification = "NSWorkspaceDidWakeNotification"
    static let NSWorkspaceWillSleepNotification = "NSWorkspaceWillSleepNotification"
    static let NSDeviceResolution = "NSDeviceResolution"
    static let NSDeviceSize = "NSDeviceSize"
    static let NSDeviceIsScreen = "NSDeviceIsScreen"
    static let NSDeviceColorSpaceName = "NSDeviceColorSpaceName"
    static let NSCalibratedRGBColorSpace = "NSCalibratedRGBColorSpace"
    static let NSDeviceRGBColorSpace = "NSDeviceRGBColorSpace"
}

/// The application object, also kept in NSApp.
enum App {
    nonisolated(unsafe) static var shared: NSApplication? {
        didSet { ObjCConstantExports.shared.slot("NSApp")?.pointee = shared?.objcObject }
    }
}

func appKitFatal(_ message: String) -> Never {
    let line = "perry: AppKit: *** \(message)\n"
    line.withCString { _ = write(2, $0, strlen($0)) }
    abort()
}

func appKitWarning(_ message: String) {
    let line = "perry: AppKit: \(message)\n"
    line.withCString { _ = write(2, $0, strlen($0)) }
}

/// PERRY_APPKIT_TRACE: events and window changes, as they happen.
enum Trace {
    nonisolated(unsafe) static let enabled = getenv("PERRY_APPKIT_TRACE") != nil
    static func log(_ message: @autoclosure () -> String) {
        if enabled { appKitWarning(message()) }
    }
}

// MARK: - libdispatch and CoreFoundation's run loop

enum Dispatch {
    typealias Function = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias Async = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Function) -> Void
    nonisolated(unsafe) static var async: Async!
    nonisolated(unsafe) static var main: UnsafeMutableRawPointer!

    static func load(_ lookup: (String) -> UnsafeMutableRawPointer?) -> Bool {
        guard let async = lookup("_dispatch_async_f"), let main = lookup("__dispatch_main_q") else { return false }
        self.async = unsafeBitCast(async, to: Async.self)
        self.main = main
        return true
    }

    private final class Work {
        let body: () -> Void
        init(_ body: @escaping () -> Void) { self.body = body }
    }

    private static let run: Function = { context in
        guard let context else { return }
        ObjCRuntime.autoreleasepool { Unmanaged<Work>.fromOpaque(context).takeRetainedValue().body() }
    }

    static func onMain(_ body: @escaping () -> Void) { async(main, Unmanaged.passRetained(Work(body)).toOpaque(), run) }
}

/// The main run loop, which AppKit runs between events: timers, the main
/// queue and performs.
enum RunLoop {
    typealias RunInMode = @convention(c) (UnsafeMutableRawPointer?, Double, Bool) -> Int32
    nonisolated(unsafe) static var runInMode: RunInMode!
    /// kCFRunLoopDefaultMode's slot, read when the loop runs: Foundation
    /// fills it at its start.
    nonisolated(unsafe) static var defaultModeSlot: UnsafeMutableRawPointer?

    static func load(_ lookup: (String) -> UnsafeMutableRawPointer?) -> Bool {
        guard let run = lookup("_CFRunLoopRunInMode") else { return false }
        runInMode = unsafeBitCast(run, to: RunInMode.self)
        defaultModeSlot = lookup("_kCFRunLoopDefaultMode")
        return true
    }

    /// kCFRunLoopRunFinished: nothing to run.
    static let finished: Int32 = 1

    /// Runs the run loop for up to `seconds`, returning after one source;
    /// whether anything was there to run.
    @discardableResult
    static func run(for seconds: Double) -> Bool {
        runInMode(defaultModeSlot?.load(as: UnsafeMutableRawPointer?.self), max(seconds, 0), true) != finished
    }
}

/// Method lookups, to tell whether a class overrides a method.
enum Methods {
    typealias Implementation = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> UnsafeRawPointer?
    nonisolated(unsafe) static var implementation: Implementation!

    /// Whether `object`'s class implements `selector` other than as `base`
    /// does.
    static func overrides(_ object: UnsafeMutableRawPointer, _ selector: String, of base: UnsafeMutableRawPointer) -> Bool {
        let sel = ObjCRuntime.selector(selector)
        return implementation(ObjCRuntime.objectClass(object), sel) != implementation(base, sel)
    }
}

/// Monotonic seconds, and the time since boot an NSEvent's timestamp is.
enum Clock {
    static var now: Double {
        var time = timespec()
        clock_gettime(CLOCK_MONOTONIC, &time)
        return Double(time.tv_sec) + Double(time.tv_nsec) / 1e9
    }

    /// CFAbsoluteTime: seconds since 2001.
    static var absolute: Double {
        var time = timespec()
        clock_gettime(CLOCK_REALTIME, &time)
        return Double(time.tv_sec) + Double(time.tv_nsec) / 1e9 - 978_307_200
    }
}

/// Calling blocks AppKit is handed.
enum Blocks {
    static func call(_ block: ObjCBlock) {
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer) -> Void
        block.function(as: Invoke.self)(block.object)
    }

    static func call(_ block: ObjCBlock, _ argument: Int) {
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, Int) -> Void
        block.function(as: Invoke.self)(block.object, argument)
    }

    static func call(_ block: ObjCBlock, _ argument: UnsafeMutableRawPointer?) {
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?) -> Void
        block.function(as: Invoke.self)(block.object, argument)
    }

    static func call(_ block: ObjCBlock, _ first: UnsafeMutableRawPointer?, _ second: UnsafeMutableRawPointer?) {
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
        block.function(as: Invoke.self)(block.object, first, second)
    }
}

// MARK: - Foundation, as this provider calls it

public typealias CGFloat = Double

extension NSObject {
    @ObjCMethod("new") func newInstance() -> NSObject
    @ObjCMethod("alloc") func allocated() -> NSObject
    @ObjCMethod("init") func initialized() -> NSObject
    @ObjCMethod("description") func describedByObject() -> String?
    @ObjCMethod("timeIntervalSinceReferenceDate") func sendTimeIntervalSinceReferenceDate() -> Double
    var stringValue: String { String(objCArgument: objcObject) }
}

extension ObjCClass {
    var object: NSObject { NSObject(pointer) }
}

enum Classes {
    /// The class named `name`, if one is registered.
    static func named(_ name: String) -> ObjCClass? {
        name.withCString { ObjCRuntime.functions.getClass($0) }.map(ObjCClass.init)
    }
}

@ObjCWrapper("NSArray")
class NSArray: NSObject {
    @ObjCMethod("count") func count() -> UInt
    @ObjCMethod("objectAtIndex:") func object(at index: UInt) -> NSObject

    var elements: [NSObject] { (0..<count()).map { object(at: $0) } }
}

@ObjCWrapper("NSMutableArray")
class NSMutableArray: NSArray {
    @ObjCClassMethod("array") static func empty() -> NSMutableArray
    @ObjCMethod("addObject:") func add(_ object: NSObject)

    static func of(_ objects: [NSObject]) -> NSMutableArray {
        let array = empty()
        objects.forEach(array.add)
        return array
    }
}

@ObjCWrapper("NSDictionary")
class NSDictionary: NSObject {
    @ObjCMethod("objectForKey:") func object(forKey key: String) -> NSObject?
}

@ObjCWrapper("NSMutableDictionary")
class NSMutableDictionary: NSDictionary {
    @ObjCClassMethod("dictionary") static func empty() -> NSMutableDictionary
    @ObjCMethod("setObject:forKey:") func set(_ object: NSObject, forKey key: String)
}

@ObjCWrapper("NSNumber")
class NSNumber: NSObject {
    @ObjCClassMethod("numberWithDouble:") static func make(double: Double) -> NSNumber
    @ObjCClassMethod("numberWithUnsignedInt:") static func make(unsignedInt: UInt32) -> NSNumber
    @ObjCClassMethod("numberWithBool:") static func make(bool: Bool) -> NSNumber
}

@ObjCWrapper("NSValue")
class NSValue: NSObject {
    @ObjCClassMethod("valueWithBytes:objCType:") static func make(bytes: UnsafeRawPointer, objCType: UnsafePointer<CChar>) -> NSValue

    static func boxing<T: ObjCScalar>(_ value: T) -> NSValue {
        var value = value
        return T.objCTypeEncoding.withCString { type in withUnsafeBytes(of: &value) { make(bytes: $0.baseAddress!, objCType: type) } }
    }
}

@ObjCWrapper("NSBundle")
class NSBundle: NSObject {
    @ObjCClassMethod("mainBundle") static func main() -> NSBundle
    @ObjCMethod("objectForInfoDictionaryKey:") func infoObject(forKey key: String) -> NSObject?
    @ObjCMethod("bundlePath") func bundlePath() -> String
    @ObjCMethod("bundleIdentifier") func bundleIdentifier() -> String?
}

@ObjCWrapper("NSNotification")
class NSNotification: NSObject {
    @ObjCClassMethod("notificationWithName:object:userInfo:")
    static func make(name: String, object: NSObject?, userInfo: NSObject?) -> NSNotification

    static func make(name: String, object: NSObject?) -> NSNotification { make(name: name, object: object, userInfo: nil) }
}

@ObjCWrapper("NSNotificationCenter")
class NSNotificationCenter: NSObject {
    @ObjCClassMethod("defaultCenter") static func defaultCenter() -> NSNotificationCenter
    @ObjCMethod("postNotification:") func post(_ notification: NSNotification)
    @ObjCMethod("postNotificationName:object:") func post(name: String, object: NSObject?)
    @ObjCMethod("postNotificationName:object:userInfo:") func post(name: String, object: NSObject?, userInfo: NSObject?)
}

@ObjCWrapper("NSDate")
class NSDate: NSObject {
    @ObjCClassMethod("distantFuture") static func distantFuture() -> NSDate
    @ObjCClassMethod("dateWithTimeIntervalSinceReferenceDate:") static func make(timeIntervalSinceReferenceDate: Double) -> NSDate
}

@ObjCWrapper("NSURL")
class NSURL: NSObject {
    @ObjCClassMethod("fileURLWithPath:") static func make(fileURLWithPath path: String) -> NSURL?
    @ObjCMethod("absoluteString") func absoluteString() -> String?
}

/// Posts a notification from the default center.
func post(_ name: String, object: NSObject?, userInfo: NSObject? = nil) {
    if let userInfo {
        NSNotificationCenter.defaultCenter().post(name: name, object: object, userInfo: userInfo)
    } else {
        NSNotificationCenter.defaultCenter().post(name: name, object: object)
    }
}

// MARK: - Geometry, as Objective-C values

extension CGPoint: ObjCScalar {
    public static var objCTypeEncoding: String { "{CGPoint=dd}" }
    static let zero = CGPoint(x: 0, y: 0)
}

extension CGSize: ObjCScalar {
    public static var objCTypeEncoding: String { "{CGSize=dd}" }
    static let zero = CGSize(width: 0, height: 0)
}

extension CGRect: ObjCScalar {
    public static var objCTypeEncoding: String { "{CGRect={CGPoint=dd}{CGSize=dd}}" }
    static let zero = CGRect(origin: .zero, size: .zero)

    init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.init(origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height))
    }

    var minX: CGFloat { origin.x }
    var minY: CGFloat { origin.y }
    var maxX: CGFloat { origin.x + size.width }
    var maxY: CGFloat { origin.y + size.height }
    var width: CGFloat { size.width }
    var height: CGFloat { size.height }

    func contains(_ point: CGPoint) -> Bool {
        point.x >= minX && point.x < maxX && point.y >= minY && point.y < maxY
    }
}

extension CGPoint: Equatable {
    public static func == (a: CGPoint, b: CGPoint) -> Bool { a.x == b.x && a.y == b.y }
}

extension CGSize: Equatable {
    public static func == (a: CGSize, b: CGSize) -> Bool { a.width == b.width && a.height == b.height }
}

extension CGRect: Equatable {
    public static func == (a: CGRect, b: CGRect) -> Bool { a.origin == b.origin && a.size == b.size }
}

import CPerryGeometry
import Glibc
import PerryInterface
import PerryObjCInterop

// libPerryMapKit: the provider for MapKit. PerryProviderPlugin generates its
// entry points from the module's Objective-C declarations; this file binds
// libobjc and libdispatch first, and holds the UIKit, CoreLocation and
// Foundation calls the framework makes. Its views are UIKit's, so the loader
// starts it after UIKit.

private let libobjc = "/usr/lib/libobjc.A.dylib"
private let libSystem = "/usr/lib/libSystem.B.dylib"

func providerWillStart(_ info: perry_startup_info) -> Bool {
    guard info.version >= 2, let lookup = info.lookup_symbol else { return false }
    func symbol(_ library: String, _ name: String) -> UnsafeMutableRawPointer? {
        library.withCString { library in name.withCString { lookup(library, $0) } }
    }
    guard ObjCRuntime.load({ symbol(libobjc, $0) }), Dispatch.load({ symbol(libSystem, $0) }) else {
        let line = "perry: MapKit: *** MapKit needs libPerryobjc and libPerrySystem, which are missing or incomplete\n"
        line.withCString { _ = write(2, $0, strlen($0)) }
        abort()
    }
    return true
}

/// MapKit's structure constants, which the loader asks for while binding
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
            "_MKMapSizeWorld": value(MapGeometry.worldSize),
            "_MKMapRectWorld": value(MKMapRect(origin: MKMapPoint(x: 0, y: 0), size: MapGeometry.worldSize)),
            "_MKMapRectNull": value(MapGeometry.nullRect),
            "_MKCoordinateRegionInvalid": value(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: -180, longitude: -180),
                                                                   span: MKCoordinateSpan(latitudeDelta: 0, longitudeDelta: 0))),
        ]
    }()
}

/// libdispatch: delegate messages that follow a change run on the main
/// queue, as MapKit sends them once the map has moved.
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

    final class Work {
        let body: () -> Void
        init(_ body: @escaping () -> Void) { self.body = body }
    }

    private static let run: Function = { context in
        guard let context else { return }
        ObjCRuntime.autoreleasepool { Unmanaged<Work>.fromOpaque(context).takeRetainedValue().body() }
    }

    static func onMain(_ body: @escaping () -> Void) { async(main, Unmanaged.passRetained(Work(body)).toOpaque(), run) }
}

/// [super initWithFrame:] and [super initWithCoder:] from an initializer
/// defined on `cls`, for MapKit's views, whose superclass is UIKit's.
enum Super {
    static func initialize(_ object: UnsafeMutableRawPointer, frame: CGRect, definedOn cls: ObjCClass) {
        var superInfo = (object, cls.pointer)
        typealias Send = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer?, CGRect.ObjCType) -> UnsafeMutableRawPointer?
        _ = withUnsafeMutablePointer(to: &superInfo) {
            unsafeBitCast(ObjCRuntime.msgSendSuper2, to: Send.self)(UnsafeMutableRawPointer($0), ObjCRuntime.selector("initWithFrame:"), frame.objCArgument())
        }
    }

    static func initialize(_ object: UnsafeMutableRawPointer, coder: NSObject, definedOn cls: ObjCClass) {
        var superInfo = (object, cls.pointer)
        typealias Send = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer?, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
        _ = withUnsafeMutablePointer(to: &superInfo) {
            unsafeBitCast(ObjCRuntime.msgSendSuper2, to: Send.self)(UnsafeMutableRawPointer($0), ObjCRuntime.selector("initWithCoder:"),
                                                                    coder.objcObject)
        }
    }
}

/// A recursive mutex.
final class Lock: @unchecked Sendable {
    private let mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)

    init() {
        var attributes = pthread_mutexattr_t()
        pthread_mutexattr_init(&attributes)
        pthread_mutexattr_settype(&attributes, Int32(PTHREAD_MUTEX_RECURSIVE))
        pthread_mutex_init(mutex, &attributes)
        pthread_mutexattr_destroy(&attributes)
    }

    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return try body()
    }
}

/// Swift state for an Objective-C object, from creation until -dealloc.
class ObjectState {
    required init() {}
}

final class StateTable<State: ObjectState>: @unchecked Sendable {
    private let lock = Lock()
    private var states: [UnsafeMutableRawPointer: State] = [:]

    /// The object's state, made on first use.
    subscript(object: UnsafeMutableRawPointer) -> State {
        lock.withLock {
            if let state = states[object] { return state }
            let state = State()
            states[object] = state
            return state
        }
    }

    func remove(_ object: UnsafeMutableRawPointer) { _ = lock.withLock { states.removeValue(forKey: object) } }
}

// MARK: - UIKit, CoreLocation and Foundation, as this provider calls them

#if _pointerBitWidth(_32)
public typealias CGFloat = Float
#else
public typealias CGFloat = Double
#endif

extension CGPoint: ObjCStructure {
    #if _pointerBitWidth(_32)
    public typealias ObjCType = ObjCWords2
    public static var objCTypeEncoding: String { "{CGPoint=ff}" }
    #else
    public typealias ObjCType = CGPoint
    public static var objCTypeEncoding: String { "{CGPoint=dd}" }
    #endif
}
extension CGSize: ObjCStructure {
    #if _pointerBitWidth(_32)
    public typealias ObjCType = ObjCWords2
    public static var objCTypeEncoding: String { "{CGSize=ff}" }
    #else
    public typealias ObjCType = CGSize
    public static var objCTypeEncoding: String { "{CGSize=dd}" }
    #endif
}
extension CGRect: ObjCStructure {
    #if _pointerBitWidth(_32)
    public typealias ObjCType = ObjCWords4
    public static var objCTypeEncoding: String { "{CGRect={CGPoint=ff}{CGSize=ff}}" }
    #else
    public typealias ObjCType = CGRect
    public static var objCTypeEncoding: String { "{CGRect={CGPoint=dd}{CGSize=dd}}" }
    #endif
}

extension NSObject {
    @ObjCMethod("new") func newInstance() -> NSObject
    @ObjCMethod("alloc") func allocated() -> NSObject
    @ObjCMethod("init") func initialized() -> NSObject
    var stringValue: String { String(objCArgument: objcObject) }
}

extension ObjCClass {
    var object: NSObject { NSObject(pointer) }
}

@ObjCWrapper("UIView")
class UIView: NSObject {
    @ObjCMethod("bounds") func bounds() -> CGRect
    @ObjCMethod("frame") func frame() -> CGRect
    @ObjCMethod("setFrame:") func setFrame(_ frame: CGRect)
    @ObjCMethod("setBackgroundColor:") func setBackgroundColor(_ color: UIColor?)
    @ObjCMethod("setNeedsDisplay") func setNeedsDisplay()
    @ObjCMethod("convertPoint:toView:") func convert(_ point: CGPoint, to view: UIView?) -> CGPoint
    @ObjCMethod("convertPoint:fromView:") func convert(_ point: CGPoint, from view: UIView?) -> CGPoint
    @ObjCMethod("convertRect:toView:") func convert(_ rect: CGRect, to view: UIView?) -> CGRect
    @ObjCMethod("convertRect:fromView:") func convert(_ rect: CGRect, from view: UIView?) -> CGRect
}

@ObjCWrapper("UIColor")
class UIColor: NSObject {
    @ObjCClassMethod("colorWithRed:green:blue:alpha:") static func make(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) -> UIColor
}

@ObjCWrapper("CLLocation")
class CLLocation: NSObject {
    @ObjCMethod("initWithLatitude:longitude:") func initialize(latitude: Double, longitude: Double) -> CLLocation
    @ObjCMethod("coordinate") func coordinate() -> CLLocationCoordinate2D

    static func make(_ coordinate: CLLocationCoordinate2D) -> CLLocation {
        objCClass.object.allocated().unsafeCast(to: CLLocation.self).initialize(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

@ObjCWrapper("CLPlacemark")
class CLPlacemark: NSObject {
    @ObjCMethod("initWithLocation:addressDictionary:region:areasOfInterest:")
    func initializePlacemark(location: CLLocation?, addressDictionary: NSObject?, region: NSObject?, areasOfInterest: NSObject?) -> NSObject
    @ObjCMethod("location") func location() -> CLLocation?
    @ObjCMethod("name") func name() -> String?
    @ObjCMethod("ISOcountryCode") func isoCountryCode() -> String?
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

@ObjCWrapper("NSMutableSet")
class NSMutableSet: NSObject {
    @ObjCClassMethod("set") static func empty() -> NSMutableSet
    @ObjCMethod("addObject:") func add(_ object: NSObject)

    static func of(_ objects: [NSObject]) -> NSMutableSet {
        let set = empty()
        objects.forEach(set.add)
        return set
    }
}

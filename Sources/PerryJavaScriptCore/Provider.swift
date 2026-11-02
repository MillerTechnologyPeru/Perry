import CJavaScriptCore
import Glibc
import PerryInterface
import PerryObjCInterop

// libPerryJavaScriptCore: the provider for JavaScriptCore. The C API is
// WebKitGTK's JavaScriptCore itself, whose functions are Apple's: imports
// of them bind straight to it (providerSymbol). The Objective-C API
// (JSVirtualMachine, JSContext, JSValue, JSManagedValue, blocks as
// functions, JSExport) is built here on that C API.

private let libobjc = "/usr/lib/libobjc.A.dylib"
private let libSystem = "/usr/lib/libSystem.B.dylib"

/// libobjc's introspection and libSystem's blocks, which the interop layer
/// does not bind.
enum Runtime {
    typealias Pointer = UnsafeMutableRawPointer
    typealias CopyProtocolListFunction = @convention(c) (Pointer?, UnsafeMutablePointer<UInt32>?) -> UnsafeMutablePointer<Pointer?>?
    typealias ProtocolCopyProtocolListFunction = @convention(c) (Pointer?, UnsafeMutablePointer<UInt32>?) -> UnsafeMutablePointer<Pointer?>?
    typealias ConformsToProtocolFunction = @convention(c) (Pointer?, Pointer?) -> Bool
    typealias GetProtocolFunction = @convention(c) (UnsafePointer<CChar>) -> Pointer?
    typealias CopyMethodDescriptionsFunction = @convention(c) (Pointer?, Bool, Bool, UnsafeMutablePointer<UInt32>?) -> Pointer?
    typealias CopyPropertyListFunction = @convention(c) (Pointer?, UnsafeMutablePointer<UInt32>?) -> UnsafeMutablePointer<UnsafeRawPointer?>?
    typealias PropertyNameFunction = @convention(c) (UnsafeRawPointer?) -> UnsafePointer<CChar>?
    typealias PropertyAttributesFunction = @convention(c) (UnsafeRawPointer?) -> UnsafePointer<CChar>?
    typealias GetClassFunction = @convention(c) (Pointer?) -> Pointer?
    typealias SuperclassFunction = @convention(c) (Pointer?) -> Pointer?
    typealias IsMetaClassFunction = @convention(c) (Pointer?) -> Bool
    typealias InstanceMethodFunction = @convention(c) (Pointer?, UnsafeRawPointer?) -> Pointer?
    typealias ClassMethodFunction = @convention(c) (Pointer?, UnsafeRawPointer?) -> Pointer?
    typealias MethodTypesFunction = @convention(c) (Pointer?) -> UnsafePointer<CChar>?
    typealias BlockReleaseFunction = @convention(c) (Pointer?) -> Void
    nonisolated(unsafe) static var copyProtocolList: CopyProtocolListFunction!
    nonisolated(unsafe) static var protocolCopyProtocolList: ProtocolCopyProtocolListFunction!
    nonisolated(unsafe) static var conformsToProtocol: ConformsToProtocolFunction!
    nonisolated(unsafe) static var getProtocol: GetProtocolFunction!
    nonisolated(unsafe) static var copyMethodDescriptions: CopyMethodDescriptionsFunction!
    nonisolated(unsafe) static var copyPropertyList: CopyPropertyListFunction!
    nonisolated(unsafe) static var propertyName: PropertyNameFunction!
    nonisolated(unsafe) static var propertyAttributes: PropertyAttributesFunction!
    nonisolated(unsafe) static var getClass: GetClassFunction!
    nonisolated(unsafe) static var superclass: SuperclassFunction!
    nonisolated(unsafe) static var isMetaClass: IsMetaClassFunction!
    nonisolated(unsafe) static var instanceMethod: InstanceMethodFunction!
    nonisolated(unsafe) static var classMethod: ClassMethodFunction!
    nonisolated(unsafe) static var methodTypes: MethodTypesFunction!
    nonisolated(unsafe) static var blockRelease: BlockReleaseFunction!
    /// kCFBooleanTrue and kCFBooleanFalse, which become JavaScript booleans.
    nonisolated(unsafe) static var booleans: (Pointer?, Pointer?) = (nil, nil)
    nonisolated(unsafe) static var javaScriptCore: Pointer?

    static func load(_ lookup: (String, String) -> Pointer?) -> Bool {
        func bind<T>(_ name: String, _ type: T.Type, _ library: String = libobjc) -> T? {
            lookup(library, name).map { unsafeBitCast($0, to: T.self) }
        }
        copyProtocolList = bind("_class_copyProtocolList", CopyProtocolListFunction.self)
        protocolCopyProtocolList = bind("_protocol_copyProtocolList", ProtocolCopyProtocolListFunction.self)
        conformsToProtocol = bind("_protocol_conformsToProtocol", ConformsToProtocolFunction.self)
        getProtocol = bind("_objc_getProtocol", GetProtocolFunction.self)
        copyMethodDescriptions = bind("_protocol_copyMethodDescriptionList", CopyMethodDescriptionsFunction.self)
        copyPropertyList = bind("_protocol_copyPropertyList", CopyPropertyListFunction.self)
        propertyName = bind("_property_getName", PropertyNameFunction.self)
        propertyAttributes = bind("_property_getAttributes", PropertyAttributesFunction.self)
        getClass = bind("_object_getClass", GetClassFunction.self)
        superclass = bind("_class_getSuperclass", SuperclassFunction.self)
        isMetaClass = bind("_class_isMetaClass", IsMetaClassFunction.self)
        instanceMethod = bind("_class_getInstanceMethod", InstanceMethodFunction.self)
        classMethod = bind("_class_getClassMethod", ClassMethodFunction.self)
        methodTypes = bind("_method_getTypeEncoding", MethodTypesFunction.self)
        blockRelease = bind("__Block_release", BlockReleaseFunction.self, libSystem)
        if javaScriptCore == nil { javaScriptCore = dlopen("libjavascriptcoregtk-4.1.so.0", RTLD_NOW) }
        return copyProtocolList != nil && copyMethodDescriptions != nil && copyPropertyList != nil && conformsToProtocol != nil
            && getProtocol != nil && getClass != nil && isMetaClass != nil && methodTypes != nil && javaScriptCore != nil
    }
}

func providerWillStart(_ info: perry_startup_info) -> Bool {
    guard info.version >= 2, let lookup = info.lookup_symbol else { return false }
    func symbol(_ library: String, _ name: String) -> UnsafeMutableRawPointer? {
        library.withCString { library in name.withCString { lookup(library, $0) } }
    }
    guard ObjCRuntime.load({ symbol(libobjc, $0) }), Runtime.load(symbol) else {
        scriptFatal("JavaScriptCore needs libPerryobjc, libPerrySystem and WebKitGTK's JavaScriptCore, which are missing or incomplete")
    }
    return true
}

func providerDidStart(_ info: perry_startup_info) {
    guard let lookup = info.lookup_symbol else { return }
    func object(_ name: String) -> UnsafeMutableRawPointer? {
        "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation".withCString { library in
            name.withCString { lookup(library, $0) }
        }?.load(as: UnsafeMutableRawPointer?.self)
    }
    Runtime.booleans = (object("_kCFBooleanTrue"), object("_kCFBooleanFalse"))
}

/// The C API's functions and constants (JS…, kJS…) are WebKitGTK's. The
/// loader asks while images bind, before the provider starts.
func providerSymbol(_ name: String) -> UnsafeMutableRawPointer? {
    guard name.hasPrefix("_JS") || name.hasPrefix("_kJS") else { return nil }
    if Runtime.javaScriptCore == nil { Runtime.javaScriptCore = dlopen("libjavascriptcoregtk-4.1.so.0", RTLD_NOW) }
    guard let library = Runtime.javaScriptCore else { return nil }
    return dlsym(library, String(name.dropFirst()))
}

func scriptFatal(_ message: String) -> Never {
    let line = "perry: JavaScriptCore: *** \(message)\n"
    line.withCString { _ = write(2, $0, strlen($0)) }
    abort()
}

// MARK: - Foundation, as JavaScriptCore calls it

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
}

@ObjCWrapper("NSDictionary")
class NSDictionary: NSObject {
    @ObjCMethod("allKeys") func allKeys() -> NSArray
    @ObjCMethod("objectForKey:") func object(forKey key: NSObject) -> NSObject?
}

@ObjCWrapper("NSMutableDictionary")
class NSMutableDictionary: NSDictionary {
    @ObjCClassMethod("dictionary") static func empty() -> NSMutableDictionary
    @ObjCMethod("setObject:forKey:") func set(_ object: NSObject, forKey key: NSObject)
}

@ObjCWrapper("NSNumber")
class NSNumber: NSObject {
    @ObjCClassMethod("numberWithDouble:") static func make(double: Double) -> NSNumber
    @ObjCMethod("doubleValue") func doubleValue() -> Double
}

@ObjCWrapper("NSDate")
class NSDate: NSObject {
    @ObjCClassMethod("dateWithTimeIntervalSince1970:") static func make(since1970: Double) -> NSDate
    @ObjCMethod("timeIntervalSince1970") func timeIntervalSince1970() -> Double
}

@ObjCWrapper("NSNull")
class NSNull: NSObject {
    @ObjCClassMethod("null") static func null() -> NSNull
}

extension NSObject {
    @ObjCMethod("isKindOfClass:") func isKind(of cls: ObjCClass) -> Bool
    @ObjCMethod("new") func newInstance() -> NSObject
    @ObjCMethod("description") func describedByObject() -> String?

    static func string(_ value: String) -> NSObject { NSObject(objCReturnValue: value.objCArgument()) }
    func isA(_ name: String) -> Bool { isKind(of: ObjCClass(named: name)) }
    var stringValue: String { String(objCArgument: objcObject) }
}

extension ObjCClass {
    /// A new instance an autorelease pool also holds (+0).
    func autoreleasedInstance() -> NSObject {
        let instance = NSObject(pointer).newInstance()
        _ = ObjCRuntime.autorelease(ObjCRuntime.retain(instance.objcObject))
        return instance
    }
}

/// Swift state per Objective-C object, from creation until -dealloc.
final class StateTable<State: AnyObject>: @unchecked Sendable {
    private var lock = pthread_mutex_t()
    private var states: [UnsafeMutableRawPointer: State] = [:]

    init() { pthread_mutex_init(&lock, nil) }

    subscript(object: UnsafeMutableRawPointer?) -> State? {
        guard let object else { return nil }
        pthread_mutex_lock(&lock)
        defer { pthread_mutex_unlock(&lock) }
        return states[object]
    }

    func set(_ object: UnsafeMutableRawPointer, _ state: State) {
        pthread_mutex_lock(&lock)
        states[object] = state
        pthread_mutex_unlock(&lock)
    }

    func remove(_ object: UnsafeMutableRawPointer) {
        pthread_mutex_lock(&lock)
        let state = states.removeValue(forKey: object)
        pthread_mutex_unlock(&lock)
        _ = state
    }
}

import CPerryFoundation
import Glibc
import PerryObjCInterop

// Foundation is a client of the Objective-C runtime, as on Darwin: it uses
// libobjc's C API, looked up in libPerryobjc at startup, rather than
// linking the runtime's Swift engine (which would be a second copy).

public typealias id = UnsafeMutableRawPointer
public typealias SEL = UnsafePointer<CChar>
public typealias Class = UnsafeMutablePointer<perry_class_storage>

enum ObjC {
    typealias Lookup = (String) -> UnsafeMutableRawPointer?

    nonisolated(unsafe) static var msgSend: UnsafeRawPointer!
    nonisolated(unsafe) static var msgSendSuper2: UnsafeRawPointer!
    nonisolated(unsafe) static var retain: (@convention(c) (id?) -> id?)!
    nonisolated(unsafe) static var release: (@convention(c) (id?) -> Void)!
    nonisolated(unsafe) static var autorelease: (@convention(c) (id?) -> id?)!
    nonisolated(unsafe) static var initializeClassPair: (@convention(c) (Class?, SEL, Class, Class) -> Class?)!
    nonisolated(unsafe) static var registerClassPair: (@convention(c) (Class) -> Void)!
    nonisolated(unsafe) static var getClass: (@convention(c) (SEL) -> Class?)!
    nonisolated(unsafe) static var objectGetClass: (@convention(c) (id?) -> Class?)!
    nonisolated(unsafe) static var objectGetClassName: (@convention(c) (id?) -> SEL?)!
    nonisolated(unsafe) static var addMethod: (@convention(c) (Class, SEL, UnsafeRawPointer, SEL) -> Bool)!
    nonisolated(unsafe) static var replaceMethod: (@convention(c) (Class, SEL, UnsafeRawPointer, SEL) -> UnsafeRawPointer?)!
    nonisolated(unsafe) static var createInstance: (@convention(c) (Class, Int) -> id?)!
    nonisolated(unsafe) static var indexedIvars: (@convention(c) (id) -> UnsafeMutableRawPointer?)!
    nonisolated(unsafe) static var registerName: (@convention(c) (SEL) -> SEL)!
    nonisolated(unsafe) static var retainBlock: (@convention(c) (id?) -> id?)!
    nonisolated(unsafe) static var poolPush: (@convention(c) () -> UnsafeMutableRawPointer?)!
    nonisolated(unsafe) static var poolPop: (@convention(c) (UnsafeMutableRawPointer?) -> Void)!

    /// Binds every function; false if libobjc is missing one.
    static func load(_ lookup: Lookup) -> Bool {
        func bind<T>(_ name: String, _ type: T.Type) -> T? {
            lookup(name).map { unsafeBitCast($0, to: T.self) }
        }
        msgSend = lookup("_objc_msgSend").map(UnsafeRawPointer.init)
        msgSendSuper2 = lookup("_objc_msgSendSuper2").map(UnsafeRawPointer.init)
        retain = bind("_objc_retain", (@convention(c) (id?) -> id?).self)
        release = bind("_objc_release", (@convention(c) (id?) -> Void).self)
        autorelease = bind("_objc_autorelease", (@convention(c) (id?) -> id?).self)
        initializeClassPair = bind("_objc_initializeClassPair", (@convention(c) (Class?, SEL, Class, Class) -> Class?).self)
        registerClassPair = bind("_objc_registerClassPair", (@convention(c) (Class) -> Void).self)
        getClass = bind("_objc_getClass", (@convention(c) (SEL) -> Class?).self)
        objectGetClass = bind("_object_getClass", (@convention(c) (id?) -> Class?).self)
        objectGetClassName = bind("_object_getClassName", (@convention(c) (id?) -> SEL?).self)
        addMethod = bind("_class_addMethod", (@convention(c) (Class, SEL, UnsafeRawPointer, SEL) -> Bool).self)
        replaceMethod = bind("_class_replaceMethod", (@convention(c) (Class, SEL, UnsafeRawPointer, SEL) -> UnsafeRawPointer?).self)
        createInstance = bind("_class_createInstance", (@convention(c) (Class, Int) -> id?).self)
        indexedIvars = bind("_object_getIndexedIvars", (@convention(c) (id) -> UnsafeMutableRawPointer?).self)
        registerName = bind("_sel_registerName", (@convention(c) (SEL) -> SEL).self)
        retainBlock = bind("_objc_retainBlock", (@convention(c) (id?) -> id?).self)
        poolPush = bind("_objc_autoreleasePoolPush", (@convention(c) () -> UnsafeMutableRawPointer?).self)
        poolPop = bind("_objc_autoreleasePoolPop", (@convention(c) (UnsafeMutableRawPointer?) -> Void).self)
        guard let msgSend, let msgSendSuper2, let retain, let release, let autorelease, let retainBlock,
              let getClassRaw = lookup("_objc_getClass"), let objectGetClassRaw = lookup("_object_getClass"),
              let registerRaw = lookup("_sel_registerName"), let addRaw = lookup("_class_addMethod"),
              let replaceRaw = lookup("_class_replaceMethod"), let poolPush, let poolPop else { return false }
        ObjCRuntime.install(ObjCRuntimeFunctions(
            msgSend: msgSend, msgSendSuper2: msgSendSuper2,
            retain: retain, release: release, autorelease: autorelease, retainBlock: retainBlock,
            getClass: unsafeBitCast(getClassRaw, to: (@convention(c) (UnsafePointer<CChar>?) -> UnsafeMutableRawPointer?).self),
            objectGetClass: unsafeBitCast(objectGetClassRaw, to: (@convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?).self),
            registerSelector: unsafeBitCast(registerRaw, to: (@convention(c) (UnsafePointer<CChar>?) -> UnsafeRawPointer?).self),
            addMethod: unsafeBitCast(addRaw, to: (@convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeRawPointer?, UnsafePointer<CChar>?) -> Bool).self),
            replaceMethod: unsafeBitCast(replaceRaw, to: (@convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeRawPointer?, UnsafePointer<CChar>?) -> UnsafeRawPointer?).self)))
        ObjCRuntime.poolFunctions = (push: poolPush, pop: poolPop)
        return initializeClassPair != nil && registerClassPair != nil && getClass != nil && objectGetClass != nil
            && objectGetClassName != nil && addMethod != nil && replaceMethod != nil && createInstance != nil
            && indexedIvars != nil && registerName != nil
    }

    static func selector(_ name: String) -> SEL {
        name.withCString { registerName($0) }
    }

    static func className(_ object: id?) -> String {
        objectGetClassName(object).map { String(cString: $0) } ?? "nil"
    }

    /// Whether `object`'s class is `cls` or a subclass of it.
    static func isKind(_ object: id?, of cls: Class) -> Bool {
        var current = object.flatMap(objectGetClass)
        while let c = current {
            if c == cls { return true }
            current = c.pointee.superclass
        }
        return false
    }

    // MARK: - Sending

    static func send(_ receiver: id?, _ selector: SEL) -> id? {
        typealias Fn = @convention(c) (id?, SEL) -> id?
        return unsafeBitCast(msgSend, to: Fn.self)(receiver, selector)
    }

    static func send(_ receiver: id?, _ selector: SEL, _ argument: id?) -> id? {
        typealias Fn = @convention(c) (id?, SEL, id?) -> id?
        return unsafeBitCast(msgSend, to: Fn.self)(receiver, selector, argument)
    }

    static func sendInt(_ receiver: id?, _ selector: SEL, _ argument: id?) -> Int {
        typealias Fn = @convention(c) (id?, SEL, id?) -> Int
        return unsafeBitCast(msgSend, to: Fn.self)(receiver, selector, argument)
    }

    static func send(_ receiver: id?, _ selector: SEL, _ first: id?, _ second: id?) -> id? {
        typealias Fn = @convention(c) (id?, SEL, id?, id?) -> id?
        return unsafeBitCast(msgSend, to: Fn.self)(receiver, selector, first, second)
    }

    /// Runs `body` in an autorelease pool, as each run loop callout does.
    static func autoreleasepool<Result>(_ body: () -> Result) -> Result {
        let pool = poolPush()
        defer { poolPop(pool) }
        return body()
    }

    static func sendUInt(_ receiver: id?, _ selector: SEL) -> UInt {
        typealias Fn = @convention(c) (id?, SEL) -> UInt
        return unsafeBitCast(msgSend, to: Fn.self)(receiver, selector)
    }

    static func sendBool(_ receiver: id?, _ selector: SEL, _ argument: id?) -> Bool {
        typealias Fn = @convention(c) (id?, SEL, id?) -> Bool
        return unsafeBitCast(msgSend, to: Fn.self)(receiver, selector, argument)
    }

    /// [super dealloc] from a method defined on `cls`.
    static func superDealloc(_ object: id, from cls: Class) {
        var superInfo = (object, UnsafeMutableRawPointer(cls))
        typealias Fn = @convention(c) (UnsafeMutableRawPointer, SEL) -> Void
        withUnsafeMutablePointer(to: &superInfo) {
            unsafeBitCast(msgSendSuper2, to: Fn.self)(UnsafeMutableRawPointer($0), Selectors.dealloc)
        }
    }
}

/// Selectors Foundation sends.
enum Selectors {
    nonisolated(unsafe) static let dealloc = ObjC.selector("dealloc")
    nonisolated(unsafe) static let description = ObjC.selector("description")
    nonisolated(unsafe) static let isEqual = ObjC.selector("isEqual:")
    nonisolated(unsafe) static let hash = ObjC.selector("hash")
    nonisolated(unsafe) static let copyWithZone = ObjC.selector("copyWithZone:")
}

/// A class built in exported storage, or an existing class to extend.
/// @ObjCImplementation registration functions install into it.
struct ClassDefinition: ObjCMethodRegistrar {
    let cls: Class
    let metaclass: Class

    /// Builds a class in Foundation's exported storage with the given
    /// methods, and registers it. `isStatic` marks classes of objects the
    /// compiler emits (literals), which have no Swift state word.
    init(_ which: perry_foundation_class_id, name: String, superclass: Class?, isStatic: Bool = false,
         _ registrations: ObjCMethodRegistration...) {
        cls = perry_foundation_class(which)
        metaclass = perry_foundation_metaclass(which)
        _ = name.withCString { ObjC.initializeClassPair(superclass, $0, cls, metaclass) }
        for register in registrations { register(self) }
        ObjC.registerClassPair(cls)
        if isStatic { Storage.staticClasses.insert(cls) }
    }

    /// Adds methods to a class that already exists, like a category.
    init(extending cls: Class, _ registrations: ObjCMethodRegistration...) {
        self.cls = cls
        metaclass = cls.pointee.isa
        for register in registrations { register(self) }
    }

    func addMethod(_ selector: String, types: String, implementation: UnsafeRawPointer, isClassMethod: Bool) {
        let target = isClassMethod ? metaclass : cls
        let sel = ObjC.selector(selector)
        let encoding = UnsafePointer(strdup(types)!)
        if !ObjC.addMethod(target, sel, implementation, encoding) {
            _ = ObjC.replaceMethod(target, sel, implementation, encoding)
        }
    }
}

/// A variadic method's entry point in variadic.S, as an implementation.
func variadicEntry(_ entry: @convention(c) () -> Void) -> UnsafeRawPointer {
    unsafeBitCast(entry, to: UnsafeRawPointer.self)
}

/// retain, release and autorelease for static objects such as literals.
@ObjCClass("NSObject")
struct ImmortalObject {}

@ObjCImplementation
extension ImmortalObject {
    @ObjCMethod("retain") func retain() -> UnsafeMutableRawPointer { objcObject }
    @ObjCMethod("release", types: "Vv16@0:8") func release() {}
    @ObjCMethod("autorelease") func autorelease() -> UnsafeMutableRawPointer { objcObject }
    @ObjCMethod("retainCount") func retainCount() -> UInt { UInt.max }
}

/// +alloc for classes whose instances keep Swift state in an extra word.
@ObjCClass("NSObject")
struct StorageAllocated {}

@ObjCImplementation
extension StorageAllocated {
    @ObjCClassMethod("alloc")
    static func alloc(_ cls: ObjCClass) -> UnsafeMutableRawPointer? { Storage.allocate(cls.pointer) }

    @ObjCClassMethod("allocWithZone:")
    static func alloc(_ cls: ObjCClass, zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        Storage.allocate(cls.pointer)
    }
}

/// Each Foundation object keeps its Swift state in one extra word after its
/// ivars, allocated by +alloc through class_createInstance.
enum Storage {
    static let extraBytes = MemoryLayout<UnsafeRawPointer>.size

    /// Classes of static objects the compiler emits (literals), which have
    /// no extra word.
    nonisolated(unsafe) static var staticClasses: Set<Class> = []

    static func get<T: AnyObject>(_ object: id?, as type: T.Type) -> T? {
        guard let object, let cls = ObjC.objectGetClass(object), !staticClasses.contains(cls),
              let slot = ObjC.indexedIvars(object),
              let pointer = slot.load(as: UnsafeRawPointer?.self) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue() as? T
    }

    static func set(_ object: id, _ value: AnyObject?) {
        guard let slot = ObjC.indexedIvars(object) else { return }
        if let old = slot.load(as: UnsafeRawPointer?.self) {
            Unmanaged<AnyObject>.fromOpaque(old).release()
        }
        slot.storeBytes(of: value.map { UnsafeRawPointer(Unmanaged.passRetained($0).toOpaque()) },
                        as: UnsafeRawPointer?.self)
    }

    static func allocate(_ cls: id?) -> id? {
        guard let cls else { return nil }
        return ObjC.createInstance(cls.assumingMemoryBound(to: perry_class_storage.self), extraBytes)
    }
}

/// Reports an error that Foundation would raise as an exception. Perry
/// cannot unwind Mach-O frames yet, so these abort.
func foundationFatal(_ message: String) -> Never {
    let line = "perry: Foundation: *** \(message)\n"
    line.withCString { _ = write(2, $0, strlen($0)) }
    abort()
}

// MARK: - Foundation's C structs as Objective-C values

extension NSRange: ObjCScalar {
    public static var objCTypeEncoding: String { "{_NSRange=QQ}" }

    init(location: Int, length: Int) {
        self.init(location: UInt(location), length: UInt(length))
    }
}

extension NSOperatingSystemVersion: ObjCScalar {
    public static var objCTypeEncoding: String { "{NSOperatingSystemVersion=qqq}" }
}

extension AnyObjCObject {
    /// The wrapped object as Foundation's internal helpers take it.
    var id: id { objcObject }
}

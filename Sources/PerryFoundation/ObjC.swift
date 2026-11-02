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
        return msgSend != nil && msgSendSuper2 != nil && retain != nil && release != nil && autorelease != nil
            && initializeClassPair != nil && registerClassPair != nil && getClass != nil && objectGetClass != nil
            && objectGetClassName != nil && addMethod != nil && replaceMethod != nil && createInstance != nil
            && indexedIvars != nil && registerName != nil && retainBlock != nil && poolPush != nil && poolPop != nil
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
/// @ObjCImplementation method tables install into it.
struct ClassDefinition: ObjCMethodRegistrar {
    let cls: Class
    let metaclass: Class

    /// Builds a class in Foundation's exported storage, with `tables`'
    /// methods, and registers it.
    init(_ which: perry_foundation_class_id, name: String, superclass: Class?, _ tables: any ObjCMethodTable.Type...) {
        cls = perry_foundation_class(which)
        metaclass = perry_foundation_metaclass(which)
        _ = name.withCString { ObjC.initializeClassPair(superclass, $0, cls, metaclass) }
        for table in tables { table.register(self) }
        ObjC.registerClassPair(cls)
        // Literal classes read their objects in place and never allocate.
        if tables.contains(where: { $0 == ImmortalMethods.self }) {
            Storage.staticClasses.insert(cls)
        }
    }

    /// Adds methods to a class that already exists, like a category.
    init(extending cls: Class, _ tables: any ObjCMethodTable.Type...) {
        self.cls = cls
        metaclass = cls.pointee.isa
        for table in tables { table.register(self) }
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
@ObjCImplementation
enum ImmortalMethods {
    @ObjCMethod("retain") static func retain(_ object: id?) -> id? { object }
    @ObjCMethod("release", types: "Vv16@0:8") static func release(_ object: id?) {}
    @ObjCMethod("autorelease") static func autorelease(_ object: id?) -> id? { object }
    @ObjCMethod("retainCount") static func retainCount(_ object: id?) -> UInt { UInt.max }
}

/// +alloc for classes whose instances keep Swift state in an extra word.
@ObjCImplementation
enum StorageAllocation {
    @ObjCClassMethod("alloc") static func alloc(_ cls: id?) -> id? { Storage.allocate(cls) }
    @ObjCClassMethod("allocWithZone:") static func alloc(_ cls: id?, zone: UnsafeMutableRawPointer?) -> id? {
        Storage.allocate(cls)
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

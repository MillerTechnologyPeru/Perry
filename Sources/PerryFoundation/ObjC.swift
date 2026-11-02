import CPerryFoundation
import Glibc

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
        return msgSend != nil && msgSendSuper2 != nil && retain != nil && release != nil && autorelease != nil
            && initializeClassPair != nil && registerClassPair != nil && getClass != nil && objectGetClass != nil
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
}

/// Defines a class in exported storage and adds methods written as Swift
/// functions with C calling conventions: the Swift side of what
/// @implementation does in Objective-C.
struct ClassDefinition {
    let cls: Class
    let metaclass: Class

    init(_ which: perry_foundation_class_id, name: String, superclass: Class?) {
        cls = perry_foundation_class(which)
        metaclass = perry_foundation_metaclass(which)
        _ = name.withCString { ObjC.initializeClassPair(superclass, $0, cls, metaclass) }
    }

    func register() {
        ObjC.registerClassPair(cls)
    }

    /// Adds an instance method. `imp` must be a @convention(c) function.
    func method<Function>(_ name: String, _ types: String, _ imp: Function) {
        Self.add(cls, name, types, imp)
    }

    /// Adds a class method.
    func classMethod<Function>(_ name: String, _ types: String, _ imp: Function) {
        Self.add(metaclass, name, types, imp)
    }

    func method(_ name: String, _ types: String, address: UnsafeRawPointer) {
        Self.add(cls, name, types, address)
    }

    func classMethod(_ name: String, _ types: String, address: UnsafeRawPointer) {
        Self.add(metaclass, name, types, address)
    }

    static func add<Function>(_ cls: Class, _ name: String, _ types: String, _ imp: Function) {
        precondition(MemoryLayout<Function>.size == MemoryLayout<UnsafeRawPointer>.size)
        let address = unsafeBitCast(imp, to: UnsafeRawPointer.self)
        let selector = ObjC.selector(name)
        let encoding = UnsafePointer(strdup(types)!)
        if !ObjC.addMethod(cls, selector, address, encoding) {
            _ = ObjC.replaceMethod(cls, selector, address, encoding)
        }
    }
}

/// Each Foundation object keeps its Swift state in one extra word after its
/// ivars, allocated by +alloc through class_createInstance.
enum Storage {
    static let extraBytes = MemoryLayout<UnsafeRawPointer>.size

    static func get<T: AnyObject>(_ object: id?, as type: T.Type) -> T? {
        guard let object, let slot = ObjC.indexedIvars(object),
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

// Method signatures.
typealias IMPObject = @convention(c) (id?, SEL) -> id?
typealias IMPObjectObject = @convention(c) (id?, SEL, id?) -> id?
typealias IMPVoid = @convention(c) (id?, SEL) -> Void
typealias IMPVoidObject = @convention(c) (id?, SEL, id?) -> Void
typealias IMPUInt = @convention(c) (id?, SEL) -> UInt
typealias IMPInt = @convention(c) (id?, SEL) -> Int
typealias IMPBoolObject = @convention(c) (id?, SEL, id?) -> Bool
typealias IMPIntObject = @convention(c) (id?, SEL, id?) -> Int

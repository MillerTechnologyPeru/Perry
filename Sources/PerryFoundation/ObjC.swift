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
    nonisolated(unsafe) static var instanceMethod: (@convention(c) (Class?, SEL) -> UnsafeMutableRawPointer?)!
    nonisolated(unsafe) static var methodTypes: (@convention(c) (UnsafeMutableRawPointer?) -> SEL?)!
    nonisolated(unsafe) static var registerName: (@convention(c) (SEL) -> SEL)!
    nonisolated(unsafe) static var retainBlock: (@convention(c) (id?) -> id?)!
    nonisolated(unsafe) static var poolPush: (@convention(c) () -> UnsafeMutableRawPointer?)!
    nonisolated(unsafe) static var poolPop: (@convention(c) (UnsafeMutableRawPointer?) -> Void)!
    nonisolated(unsafe) static var allocateClassPair: (@convention(c) (Class?, SEL, Int) -> Class?)!
    nonisolated(unsafe) static var objectSetClass: (@convention(c) (id?, Class) -> Class?)!
    nonisolated(unsafe) static var methodImplementation: (@convention(c) (Class?, SEL) -> UnsafeRawPointer?)!
    nonisolated(unsafe) static var dispose: (@convention(c) (id?) -> id?)!
    /// Instance variables, for key-value coding's direct access.
    nonisolated(unsafe) static var instanceVariable: (@convention(c) (Class?, SEL) -> UnsafeMutableRawPointer?)?
    nonisolated(unsafe) static var ivarOffset: (@convention(c) (UnsafeMutableRawPointer?) -> Int)?
    nonisolated(unsafe) static var ivarType: (@convention(c) (UnsafeMutableRawPointer?) -> SEL?)?
    /// Darwin's dladdr, which knows the Mach-O images: the path of the
    /// image holding an address is its first word.
    nonisolated(unsafe) static var addressInfo: (@convention(c) (UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Int32)?

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
        instanceMethod = bind("_class_getInstanceMethod", (@convention(c) (Class?, SEL) -> UnsafeMutableRawPointer?).self)
        methodTypes = bind("_method_getTypeEncoding", (@convention(c) (UnsafeMutableRawPointer?) -> SEL?).self)
        registerName = bind("_sel_registerName", (@convention(c) (SEL) -> SEL).self)
        retainBlock = bind("_objc_retainBlock", (@convention(c) (id?) -> id?).self)
        poolPush = bind("_objc_autoreleasePoolPush", (@convention(c) () -> UnsafeMutableRawPointer?).self)
        poolPop = bind("_objc_autoreleasePoolPop", (@convention(c) (UnsafeMutableRawPointer?) -> Void).self)
        allocateClassPair = bind("_objc_allocateClassPair", (@convention(c) (Class?, SEL, Int) -> Class?).self)
        objectSetClass = bind("_object_setClass", (@convention(c) (id?, Class) -> Class?).self)
        methodImplementation = bind("_class_getMethodImplementation", (@convention(c) (Class?, SEL) -> UnsafeRawPointer?).self)
        dispose = bind("_object_dispose", (@convention(c) (id?) -> id?).self)
        instanceVariable = bind("_class_getInstanceVariable", (@convention(c) (Class?, SEL) -> UnsafeMutableRawPointer?).self)
        ivarOffset = bind("_ivar_getOffset", (@convention(c) (UnsafeMutableRawPointer?) -> Int).self)
        ivarType = bind("_ivar_getTypeEncoding", (@convention(c) (UnsafeMutableRawPointer?) -> SEL?).self)
        // PerrySystem's, which the loader has open; its lookup is the app's.
        if let system = dlopen("libPerrySystem.so", RTLD_NOW | RTLD_NOLOAD), let symbol = dlsym(system, "_dladdr") {
            addressInfo = unsafeBitCast(symbol, to: (@convention(c) (UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Int32).self)
        }
        // The interop layer's wrappers call the runtime through its own table.
        guard ObjCRuntime.load(lookup) else { return false }
        // Classes Foundation defines live in its exported storage.
        ObjCRuntime.classStorage = { name in
            var metaclass: Class?
            guard let cls = name.withCString({ perry_foundation_class_named($0, &metaclass) }), let metaclass else { return nil }
            return (UnsafeMutableRawPointer(cls), UnsafeMutableRawPointer(metaclass))
        }
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

    static func sendPointer(_ receiver: id?, _ selector: SEL) -> UnsafeRawPointer? {
        typealias Fn = @convention(c) (id?, SEL) -> UnsafeRawPointer?
        return unsafeBitCast(msgSend, to: Fn.self)(receiver, selector)
    }

    static func sendIndex(_ receiver: id?, _ selector: SEL, _ index: UInt) -> id? {
        typealias Fn = @convention(c) (id?, SEL, UInt) -> id?
        return unsafeBitCast(msgSend, to: Fn.self)(receiver, selector, index)
    }

    /// Whether `object`'s class implements `selector` itself rather than
    /// with `cls`'s method: a subclass this library does not define, such
    /// as Swift's bridged strings and collections, which keeps its own
    /// contents and implements its class cluster's primitive methods.
    static func overrides(_ object: id, _ selector: SEL, of cls: Class) -> Bool {
        methodImplementation(objectGetClass(object), selector) != methodImplementation(cls, selector)
    }

    /// The objects an NSEnumerator gives, until it gives nil.
    static func enumerated(_ enumerator: id?) -> [id] {
        var objects: [id] = []
        while let object = send(enumerator, Selectors.nextObject) {
            objects.append(object)
        }
        return objects
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
    nonisolated(unsafe) static let isEqual = ObjC.selector("isEqual:")
    nonisolated(unsafe) static let hash = ObjC.selector("hash")
    nonisolated(unsafe) static let copyWithZone = ObjC.selector("copyWithZone:")
    // The primitive methods of Foundation's class clusters.
    nonisolated(unsafe) static let count = ObjC.selector("count")
    nonisolated(unsafe) static let objectAtIndex = ObjC.selector("objectAtIndex:")
    nonisolated(unsafe) static let objectForKey = ObjC.selector("objectForKey:")
    nonisolated(unsafe) static let keyEnumerator = ObjC.selector("keyEnumerator")
    nonisolated(unsafe) static let getObjectsAndKeys = ObjC.selector("getObjects:andKeys:count:")
    nonisolated(unsafe) static let objectEnumerator = ObjC.selector("objectEnumerator")
    nonisolated(unsafe) static let nextObject = ObjC.selector("nextObject")
    nonisolated(unsafe) static let length = ObjC.selector("length")
    nonisolated(unsafe) static let bytes = ObjC.selector("bytes")
}

extension ObjCClass {
    /// The class's storage, as Foundation's helpers take it.
    var storage: Class { pointer.assumingMemoryBound(to: perry_class_storage.self) }

    /// Marks the class's objects as static (literals the compiler emits),
    /// which have no Swift state word.
    @discardableResult
    func markingStatic() -> ObjCClass {
        Storage.staticClasses.insert(storage)
        return self
    }
}

/// A variadic method's entry point in variadic.S, as an implementation.
func variadicEntry(_ entry: @convention(c) () -> Void) -> UnsafeRawPointer {
    unsafeBitCast(entry, to: UnsafeRawPointer.self)
}

/// Each Foundation object keeps its Swift state in extra words after its
/// ivars, allocated by +alloc through class_createInstance: a cookie made
/// from the object's address, then the state. The cookie tells these
/// objects from others of Foundation's classes, such as the arrays and
/// strings Swift's runtime allocates itself, whose memory after their
/// ivars holds their elements.
enum Storage {
    /// The cookie and the state, and room to align them: a class's
    /// instance size need not be a multiple of 8.
    static let extraBytes = 3 * MemoryLayout<UnsafeRawPointer>.size

    /// Classes of static objects the compiler emits (literals), which have
    /// no extra words.
    nonisolated(unsafe) static var staticClasses: Set<Class> = []

    private static func aligned(_ pointer: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer {
        pointer.alignedUp(for: UInt.self)
    }

    private static func cookie(_ object: id) -> UInt { UInt(bitPattern: object) ^ UInt(truncatingIfNeeded: 0x5065_7272_7953_7461 as UInt64) }

    /// The object's state word, when it has one: not a static object's,
    /// nor that of an object a program allocated itself at its class's
    /// instance size (JSONKit's JKArray, made with calloc), whose memory
    /// ends at its ivars, nor one Swift allocated. Instances come from
    /// malloc, so the allocation's usable size tells whether the words are
    /// there, and the cookie whether they are this library's.
    private static func slot(_ object: id) -> UnsafeMutableRawPointer? {
        guard let cls = ObjC.objectGetClass(object), !staticClasses.contains(cls),
              let extra = ObjC.indexedIvars(object).map(aligned) else { return nil }
        let end = object.distance(to: extra) + 2 * MemoryLayout<UInt>.size
        guard end > 0, perry_foundation_usable_size(object) >= end, extra.load(as: UInt.self) == cookie(object) else {
            return nil
        }
        return extra + MemoryLayout<UInt>.size
    }

    static func get<T: AnyObject>(_ object: id?, as type: T.Type) -> T? {
        guard let object, let slot = slot(object),
              let pointer = slot.load(as: UnsafeRawPointer?.self) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue() as? T
    }

    static func set(_ object: id, _ value: AnyObject?) {
        guard let slot = slot(object) else { return }
        if let old = slot.load(as: UnsafeRawPointer?.self) {
            Unmanaged<AnyObject>.fromOpaque(old).release()
        }
        slot.storeBytes(of: value.map { UnsafeRawPointer(Unmanaged.passRetained($0).toOpaque()) },
                        as: UnsafeRawPointer?.self)
    }

    static func allocate(_ cls: id?) -> id? {
        guard let cls,
              let object = ObjC.createInstance(cls.assumingMemoryBound(to: perry_class_storage.self), extraBytes),
              let extra = ObjC.indexedIvars(object).map(aligned) else { return nil }
        extra.storeBytes(of: cookie(object), as: UInt.self)
        return object
    }
}

/// Reports an error that Foundation would raise as an exception. Perry
/// cannot unwind Mach-O frames yet, so these abort.
func foundationFatal(_ message: String) -> Never {
    let line = "perry: Foundation: *** \(message)\n"
    line.withCString { _ = write(2, $0, strlen($0)) }
    abort()
}

// MARK: - Darwin's calling convention

/// A value a C function or an IMP returned as Darwin returns it (its
/// ObjCResultType, which on 32-bit Darwin is a double's or a 64-bit
/// integer's r0 and r1, a float's r0).
@inline(__always)
func darwinResult<Value: ObjCValue>(_ raw: Value.ObjCResultType, as type: Value.Type) -> Value {
    Value.objCValue(returnValue: Value.objCArgumentForm(ofResult: raw))
}

/// A value as a C function returns it to Darwin code.
@inline(__always)
func darwinResult<Value: ObjCValue>(_ value: Value) -> Value.ObjCResultType {
    Value.objCResult(value.objCReturnValue())
}

// MARK: - Foundation's C structs as Objective-C values

extension NSRange: ObjCStructure {
    public typealias ObjCType = NSRange
    #if _pointerBitWidth(_32)
    public static var objCTypeEncoding: String { "{_NSRange=II}" }
    #else
    public static var objCTypeEncoding: String { "{_NSRange=QQ}" }
    #endif

    init(location: Int, length: Int) {
        self.init(location: UInt(location), length: UInt(length))
    }
}

extension NSOperatingSystemVersion: ObjCStructure {
    public typealias ObjCType = NSOperatingSystemVersion
    #if _pointerBitWidth(_32)
    public static var objCTypeEncoding: String { "{NSOperatingSystemVersion=iii}" }
    #else
    public static var objCTypeEncoding: String { "{NSOperatingSystemVersion=qqq}" }
    #endif
}

extension AnyObjCObject {
    /// The wrapped object as Foundation's internal helpers take it.
    var id: id { objcObject }
}

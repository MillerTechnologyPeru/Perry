// The Objective-C runtime functions the interop layer calls.
//
// This library is linked into each provider that defines or uses
// Objective-C classes. libPerryobjc fills the table with its own functions;
// Foundation and other providers fill it with libobjc's exports, looked up
// through the loader. Each copy of the library has its own table.

/// libobjc's C API, as function pointers.
public struct ObjCRuntimeFunctions {
    public var msgSend: UnsafeRawPointer
    public var msgSendSuper2: UnsafeRawPointer
    /// objc_msgSend_stret and objc_msgSendSuper2_stret, for methods whose
    /// structures 32-bit Darwin returns through a pointer in r0; on arm64,
    /// which has none, objc_msgSend and objc_msgSendSuper2.
    public var msgSendStret: UnsafeRawPointer
    public var msgSendSuper2Stret: UnsafeRawPointer
    /// objc_msgSend_fpret, which i386 needs for floating-point results: nil
    /// must still leave one value on the x87 stack.
    public var msgSendFpret: UnsafeRawPointer
    public var retain: @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
    public var release: @convention(c) (UnsafeMutableRawPointer?) -> Void
    public var autorelease: @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
    public var retainBlock: @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
    public var getClass: @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutableRawPointer?
    public var objectGetClass: @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
    public var registerSelector: @convention(c) (UnsafePointer<CChar>?) -> UnsafeRawPointer?
    public var addMethod: @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeRawPointer?, UnsafePointer<CChar>?) -> Bool
    public var replaceMethod: @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeRawPointer?, UnsafePointer<CChar>?) -> UnsafeRawPointer?
    /// objc_initializeClassPair: builds a class in storage the caller provides.
    public var initializeClassPair: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
    /// objc_allocateClassPair.
    public var allocateClassPair: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Int) -> UnsafeMutableRawPointer?
    /// objc_registerClassPair.
    public var registerClassPair: @convention(c) (UnsafeMutableRawPointer?) -> Void

    public init(msgSend: UnsafeRawPointer, msgSendSuper2: UnsafeRawPointer,
                msgSendStret: UnsafeRawPointer? = nil, msgSendSuper2Stret: UnsafeRawPointer? = nil,
                msgSendFpret: UnsafeRawPointer? = nil,
                retain: @escaping @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?,
                release: @escaping @convention(c) (UnsafeMutableRawPointer?) -> Void,
                autorelease: @escaping @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?,
                retainBlock: @escaping @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?,
                getClass: @escaping @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutableRawPointer?,
                objectGetClass: @escaping @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?,
                registerSelector: @escaping @convention(c) (UnsafePointer<CChar>?) -> UnsafeRawPointer?,
                addMethod: @escaping @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeRawPointer?, UnsafePointer<CChar>?) -> Bool,
                replaceMethod: @escaping @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeRawPointer?, UnsafePointer<CChar>?) -> UnsafeRawPointer?,
                initializeClassPair: @escaping @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?,
                allocateClassPair: @escaping @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Int) -> UnsafeMutableRawPointer?,
                registerClassPair: @escaping @convention(c) (UnsafeMutableRawPointer?) -> Void) {
        self.msgSend = msgSend
        self.msgSendSuper2 = msgSendSuper2
        self.msgSendStret = msgSendStret ?? msgSend
        self.msgSendSuper2Stret = msgSendSuper2Stret ?? msgSendSuper2
        self.msgSendFpret = msgSendFpret ?? msgSend
        self.retain = retain
        self.release = release
        self.autorelease = autorelease
        self.retainBlock = retainBlock
        self.getClass = getClass
        self.objectGetClass = objectGetClass
        self.registerSelector = registerSelector
        self.addMethod = addMethod
        self.replaceMethod = replaceMethod
        self.initializeClassPair = initializeClassPair
        self.allocateClassPair = allocateClassPair
        self.registerClassPair = registerClassPair
    }
}

public enum ObjCRuntime {
    nonisolated(unsafe) private static var installed: ObjCRuntimeFunctions?

    /// Installs the runtime functions. Must run before any wrapper is used.
    public static func install(_ functions: ObjCRuntimeFunctions) {
        installed = functions
    }

    /// Binds libobjc's C API through `lookup`, which finds a Mach-O symbol
    /// name ("_objc_msgSend") in libobjc, and installs it, with the
    /// autorelease pool functions. False if libobjc lacks one.
    @discardableResult
    public static func load(_ lookup: (String) -> UnsafeMutableRawPointer?) -> Bool {
        func bind<Function>(_ name: String, as type: Function.Type) -> Function? {
            lookup(name).map { unsafeBitCast($0, to: type) }
        }
        typealias Object = UnsafeMutableRawPointer?
        guard let msgSend = lookup("_objc_msgSend"), let msgSendSuper2 = lookup("_objc_msgSendSuper2"),
              let retain = bind("_objc_retain", as: (@convention(c) (Object) -> Object).self),
              let release = bind("_objc_release", as: (@convention(c) (Object) -> Void).self),
              let autorelease = bind("_objc_autorelease", as: (@convention(c) (Object) -> Object).self),
              let retainBlock = bind("_objc_retainBlock", as: (@convention(c) (Object) -> Object).self),
              let getClass = bind("_objc_getClass", as: (@convention(c) (UnsafePointer<CChar>?) -> Object).self),
              let objectGetClass = bind("_object_getClass", as: (@convention(c) (Object) -> Object).self),
              let registerSelector = bind("_sel_registerName",
                                          as: (@convention(c) (UnsafePointer<CChar>?) -> UnsafeRawPointer?).self),
              let addMethod = bind("_class_addMethod", as: (@convention(c) (
                  Object, UnsafeRawPointer?, UnsafeRawPointer?, UnsafePointer<CChar>?) -> Bool).self),
              let replaceMethod = bind("_class_replaceMethod", as: (@convention(c) (
                  Object, UnsafeRawPointer?, UnsafeRawPointer?, UnsafePointer<CChar>?) -> UnsafeRawPointer?).self),
              let initializeClassPair = bind("_objc_initializeClassPair", as: (@convention(c) (
                  Object, UnsafePointer<CChar>?, Object, Object) -> Object).self),
              let allocateClassPair = bind("_objc_allocateClassPair",
                                           as: (@convention(c) (Object, UnsafePointer<CChar>?, Int) -> Object).self),
              let registerClassPair = bind("_objc_registerClassPair", as: (@convention(c) (Object) -> Void).self),
              let poolPush = bind("_objc_autoreleasePoolPush", as: (@convention(c) () -> Object).self),
              let poolPop = bind("_objc_autoreleasePoolPop", as: (@convention(c) (Object) -> Void).self) else {
            return false
        }
        ObjCPeers.load(lookup)
        install(ObjCRuntimeFunctions(
            msgSend: UnsafeRawPointer(msgSend), msgSendSuper2: UnsafeRawPointer(msgSendSuper2),
            msgSendStret: lookup("_objc_msgSend_stret").map(UnsafeRawPointer.init),
            msgSendSuper2Stret: lookup("_objc_msgSendSuper2_stret").map(UnsafeRawPointer.init),
            msgSendFpret: lookup("_objc_msgSend_fpret").map(UnsafeRawPointer.init),
            retain: retain, release: release, autorelease: autorelease, retainBlock: retainBlock,
            getClass: getClass, objectGetClass: objectGetClass, registerSelector: registerSelector,
            addMethod: addMethod, replaceMethod: replaceMethod, initializeClassPair: initializeClassPair,
            allocateClassPair: allocateClassPair, registerClassPair: registerClassPair))
        poolFunctions = (push: poolPush, pop: poolPop)
        if let store = bind("_objc_storeWeak", as: (@convention(c) (UnsafeMutablePointer<Object>?, Object) -> Object).self),
           let load = bind("_objc_loadWeakRetained", as: (@convention(c) (UnsafeMutablePointer<Object>?) -> Object).self) {
            weakFunctions = (store: store, loadRetained: load)
        }
        addIvarFunction = bind("_class_addIvar", as: AddIvar.self)
        guard let getProtocol = bind("_objc_getProtocol", as: (@convention(c) (UnsafePointer<CChar>?) -> Object).self),
              let allocateProtocol = bind("_objc_allocateProtocol",
                                          as: (@convention(c) (UnsafePointer<CChar>?) -> Object).self),
              let addProtocol = bind("_protocol_addProtocol", as: (@convention(c) (Object, Object) -> Void).self),
              let addMethodDescription = bind("_protocol_addMethodDescription", as: (@convention(c) (
                  Object, UnsafeRawPointer?, UnsafePointer<CChar>?, Bool, Bool) -> Void).self),
              let registerProtocol = bind("_objc_registerProtocol", as: (@convention(c) (Object) -> Void).self),
              let classAddProtocol = bind("_class_addProtocol", as: (@convention(c) (Object, Object) -> Bool).self) else {
            return false
        }
        protocolFunctions = ObjCProtocolFunctions(
            getProtocol: getProtocol, allocateProtocol: allocateProtocol, addProtocol: addProtocol,
            addMethodDescription: addMethodDescription, registerProtocol: registerProtocol,
            classAddProtocol: classAddProtocol)
        return true
    }

    @inline(__always)
    public static var functions: ObjCRuntimeFunctions {
        guard let installed else { objcInteropFatal("the Objective-C runtime functions are not installed") }
        return installed
    }

    /// objc_msgSend, to cast to a method's C signature.
    @inline(__always)
    public static var msgSend: UnsafeRawPointer { functions.msgSend }

    @inline(__always)
    public static var msgSendSuper2: UnsafeRawPointer { functions.msgSendSuper2 }

    /// The send for a method returning `Result`: objc_msgSend_stret when
    /// 32-bit Darwin returns it through memory, else objc_msgSend.
    @inline(__always)
    public static func msgSend<Result: ObjCValue>(returning type: Result.Type) -> UnsafeRawPointer {
        #if arch(i386)
        if Result.ObjCResultType.self == Double.self || Result.ObjCResultType.self == Float.self {
            return functions.msgSendFpret
        }
        #endif
        return Result.objCReturnsIndirectly ? functions.msgSendStret : functions.msgSend
    }

    @inline(__always)
    public static func msgSendSuper2<Result: ObjCValue>(returning type: Result.Type) -> UnsafeRawPointer {
        Result.objCReturnsIndirectly ? functions.msgSendSuper2Stret : functions.msgSendSuper2
    }

    @discardableResult @inline(__always)
    public static func retain(_ object: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { functions.retain(object) }

    @inline(__always)
    public static func release(_ object: UnsafeMutableRawPointer?) { functions.release(object) }

    @discardableResult @inline(__always)
    public static func autorelease(_ object: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        functions.autorelease(object)
    }

    // MARK: - Defining classes

    /// The provider's storage for a class it exports as an ELF symbol, if
    /// any: the class and its metaclass. Storage handed out through
    /// ObjCClassExports is used otherwise.
    nonisolated(unsafe) public static var classStorage: ((String) -> (UnsafeMutableRawPointer, UnsafeMutableRawPointer)?)?

    /// Classes this provider registers under names of its own, by their
    /// Swift-side names: classes another provider defines for the program,
    /// such as WKWebView, which a Mac app's WebKit has from AppKit while
    /// UIKit stands in for its CoreText. The provider still finds them by
    /// their public names. Set before the classes are defined.
    nonisolated(unsafe) public static var privateClassNames: [String: String] = [:]

    /// Defines a class: in the provider's exported storage when it has
    /// some, otherwise on the heap; installs `registrations`, then registers
    /// it. What @ObjCClass's defineObjCClass() calls.
    @discardableResult
    public static func defineClass(named name: String, superclass: ObjCClass?,
                                   _ registrations: [ObjCMethodRegistration]) -> ObjCClass {
        // A class registered under a private name is the provider's own,
        // on the heap; the public name stays free for another provider.
        let registeredName = privateClassNames[name] ?? name
        let created: UnsafeMutableRawPointer? = registeredName.withCString { cName in
            if registeredName == name, let (cls, metaclass) = classStorage?(name) ?? ObjCClassExports.shared.storage(for: name) {
                return functions.initializeClassPair(superclass?.pointer, cName, cls, metaclass)
            }
            return functions.allocateClassPair(superclass?.pointer, cName, 0)
        }
        guard let created else { objcInteropFatal("cannot define class \(registeredName); is the name taken?") }
        let cls = ObjCClass(created)
        for register in registrations { register(cls) }
        functions.registerClassPair(created)
        cacheLock.withLock { classes[name] = created }
        return cls
    }

    // MARK: - Selectors and classes

    nonisolated(unsafe) private static var selectors: [String: UnsafeRawPointer] = [:]
    nonisolated(unsafe) private static var classes: [String: UnsafeMutableRawPointer] = [:]
    private static let cacheLock = InteropLock()

    /// The selector named `name`, cached.
    public static func selector(_ name: String) -> UnsafeRawPointer {
        cacheLock.withLock {
            if let selector = selectors[name] { return selector }
            guard let selector = name.withCString({ functions.registerSelector($0) }) else {
                objcInteropFatal("cannot register selector \(name)")
            }
            selectors[name] = selector
            return selector
        }
    }

    /// The class the runtime has by `name`, and its metaclass; nil before
    /// the runtime's functions are installed, and for a class not defined
    /// yet.
    public static func registeredClassPair(_ name: String) -> (cls: UnsafeMutableRawPointer, metaclass: UnsafeMutableRawPointer)? {
        guard let installed, let cls = name.withCString({ installed.getClass($0) }),
              let metaclass = installed.objectGetClass(cls) else { return nil }
        return (cls, metaclass)
    }

    /// The class named `name`, cached once found.
    public static func classObject(_ name: String) -> UnsafeMutableRawPointer {
        if let cls = cacheLock.withLock({ classes[name] }) { return cls }
        guard let cls = name.withCString({ functions.getClass($0) }) else {
            objcInteropFatal("class \(name) is not registered")
        }
        cacheLock.withLock { classes[name] = cls }
        return cls
    }

    public static func objectClass(_ object: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? {
        functions.objectGetClass(object)
    }

    /// Whether `object`'s class is `cls` or a subclass of it.
    public static func isKind(_ object: UnsafeMutableRawPointer, of cls: UnsafeMutableRawPointer) -> Bool {
        var current = objectClass(object)
        while let c = current {
            if c == cls { return true }
            current = c.load(fromByteOffset: MemoryLayout<UnsafeRawPointer>.size, as: UnsafeMutableRawPointer?.self)
        }
        return false
    }

    /// [super dealloc] from a method defined on `cls`.
    public static func superDealloc(_ object: UnsafeMutableRawPointer, definedOn cls: UnsafeMutableRawPointer) {
        var superInfo = (object, cls)
        typealias Send = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer?) -> Void
        let dealloc = selector("dealloc")
        withUnsafeMutablePointer(to: &superInfo) {
            unsafeBitCast(msgSendSuper2, to: Send.self)(UnsafeMutableRawPointer($0), dealloc)
        }
    }

    /// Runs `body` in an autorelease pool.
    public static func autoreleasepool<Result>(_ body: () -> Result) -> Result {
        let pool = poolFunctions.push()
        defer { poolFunctions.pop(pool) }
        return body()
    }

    nonisolated(unsafe) public static var poolFunctions: (push: @convention(c) () -> UnsafeMutableRawPointer?,
                                                         pop: @convention(c) (UnsafeMutableRawPointer?) -> Void) =
        ({ nil }, { _ in })

    typealias AddIvar = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Int, UInt8, UnsafePointer<CChar>?) -> Bool
    nonisolated(unsafe) static var addIvarFunction: AddIvar?

    /// class_addIvar, for a class not yet registered.
    @discardableResult
    public static func addIvar(_ cls: ObjCClass, _ ivar: ObjCInstanceVariable) -> Bool {
        guard let addIvarFunction else { return false }
        return ivar.name.withCString { name in
            ivar.types.withCString { addIvarFunction(cls.pointer, name, ivar.size, ivar.alignment, $0) }
        }
    }

    /// objc_storeWeak and objc_loadWeakRetained; nil until bound, when
    /// weak references hold their objects unretained.
    nonisolated(unsafe) public static var weakFunctions: (
        store: @convention(c) (UnsafeMutablePointer<UnsafeMutableRawPointer?>?, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?,
        loadRetained: @convention(c) (UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UnsafeMutableRawPointer?
    )?
}

/// A weak reference to an Objective-C object, which reads nil once the
/// object is deallocated, as Darwin's delegate properties do.
public final class WeakObject {
    private let slot: UnsafeMutablePointer<UnsafeMutableRawPointer?>

    public init(_ object: UnsafeMutableRawPointer? = nil) {
        slot = .allocate(capacity: 1)
        slot.initialize(to: nil)
        self.object = object
    }

    deinit {
        if let weak = ObjCRuntime.weakFunctions { _ = weak.store(slot, nil) }
        slot.deallocate()
    }

    /// The object, or nil once it is gone; unretained.
    public var object: UnsafeMutableRawPointer? {
        get {
            guard let weak = ObjCRuntime.weakFunctions else { return slot.pointee }
            guard let object = weak.loadRetained(slot) else { return nil }
            ObjCRuntime.autorelease(object)
            return object
        }
        set {
            if let weak = ObjCRuntime.weakFunctions {
                _ = weak.store(slot, newValue)
            } else {
                slot.pointee = newValue
            }
        }
    }
}

/// Reports a misuse of the interop layer and aborts.
public func objcInteropFatal(_ message: String) -> Never {
    fatalError("perry: objc: \(message)")
}

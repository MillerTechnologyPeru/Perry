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

    @discardableResult @inline(__always)
    public static func retain(_ object: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { functions.retain(object) }

    @inline(__always)
    public static func release(_ object: UnsafeMutableRawPointer?) { functions.release(object) }

    @discardableResult @inline(__always)
    public static func autorelease(_ object: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        functions.autorelease(object)
    }

    // MARK: - Defining classes

    /// The provider's storage for a class it exports by symbol, if any:
    /// the class and its metaclass.
    nonisolated(unsafe) public static var classStorage: ((String) -> (UnsafeMutableRawPointer, UnsafeMutableRawPointer)?)?

    /// Defines a class: in the provider's exported storage when it has
    /// some, otherwise on the heap; installs `registrations`, then registers
    /// it. What @ObjCClass's defineObjCClass() calls.
    @discardableResult
    public static func defineClass(named name: String, superclass: ObjCClass?,
                                   _ registrations: [ObjCMethodRegistration]) -> ObjCClass {
        let created: UnsafeMutableRawPointer? = name.withCString { cName in
            if let (cls, metaclass) = classStorage?(name) {
                return functions.initializeClassPair(superclass?.pointer, cName, cls, metaclass)
            }
            return functions.allocateClassPair(superclass?.pointer, cName, 0)
        }
        guard let created else { objcInteropFatal("cannot define class \(name); is the name taken?") }
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
            current = c.load(fromByteOffset: 8, as: UnsafeMutableRawPointer?.self)
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
}

/// Reports a misuse of the interop layer and aborts.
public func objcInteropFatal(_ message: String) -> Never {
    fatalError("perry: objc: \(message)")
}

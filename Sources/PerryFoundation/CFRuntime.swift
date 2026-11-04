import Glibc

// CoreFoundation's runtime: C code defines its own CF types by registering a
// CFRuntimeClass and creating instances of the type ID it gets. Here each
// instance is an object of one Objective-C class, __NSCFType, laid out as
// CoreFoundation lays out its objects: the isa, a word of CF information
// (here the type ID), then the type's own bytes. The class's methods call
// the type's callbacks: dealloc its finalize, isEqual: and hash its equal
// and hash, description its copyDebugDesc.

/// CFRuntimeClass, as CFRuntime.h declares it.
struct CFRuntimeClass {
    var version: Int
    var className: UnsafePointer<CChar>?
    var initialize: (@convention(c) (id?) -> Void)?
    var copy: (@convention(c) (id?, id?) -> id?)?
    var finalize: (@convention(c) (id?) -> Void)?
    var equal: (@convention(c) (id?, id?) -> UInt8)?
    var hash: (@convention(c) (id?) -> UInt)?
    var copyFormattingDesc: (@convention(c) (id?, id?) -> id?)?
    var copyDebugDesc: (@convention(c) (id?) -> id?)?
    var reclaim: (@convention(c) (id?) -> Void)?
    var refcount: (@convention(c) (Int, id?) -> UInt32)?
    var requiredAlignment: UInt
}

enum CFRuntimeClasses {
    /// Type IDs given to registered classes start after CoreFoundation's own.
    static let firstTypeID: UInt = 256
    /// The CF information word follows the isa; the type's bytes follow it.
    static let headerSize = 2 * MemoryLayout<UInt>.size

    nonisolated(unsafe) static var classes: [UnsafePointer<CFRuntimeClass>] = []
    nonisolated(unsafe) static var objectClass: Class?
    nonisolated(unsafe) static let lock: UnsafeMutablePointer<pthread_mutex_t> = {
        let lock = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
        pthread_mutex_init(lock, nil)
        return lock
    }()

    static func withLock<T>(_ body: () -> T) -> T {
        pthread_mutex_lock(lock)
        defer { pthread_mutex_unlock(lock) }
        return body()
    }

    static func runtimeClass(_ typeID: UInt) -> UnsafePointer<CFRuntimeClass>? {
        withLock {
            typeID >= firstTypeID && typeID - firstTypeID < UInt(classes.count) ? classes[Int(typeID - firstTypeID)] : nil
        }
    }

    static func typeID(of object: id) -> UInt {
        object.load(fromByteOffset: MemoryLayout<UInt>.size, as: UInt.self)
    }

    static func runtimeClass(of object: id) -> UnsafePointer<CFRuntimeClass>? {
        runtimeClass(typeID(of: object))
    }

    /// __NSCFType, made the first time a type is registered.
    static func makeObjectClass() -> Class? {
        if let objectClass { return objectClass }
        guard let root = ObjC.getClass("NSObject"),
              let cls = ObjC.allocateClassPair(root, "__NSCFType", 0) else { return nil }
        let dealloc: @convention(c) (id, SEL) -> Void = { object, _ in
            if let finalize = CFRuntimeClasses.runtimeClass(of: object)?.pointee.finalize {
                finalize(object)
            }
            _ = ObjC.dispose(object)
        }
        let isEqual: @convention(c) (id, SEL, id?) -> Bool = { object, _, other in
            guard let other else { return false }
            if object == other { return true }
            guard ObjC.objectGetClass(other) == ObjC.objectGetClass(object),
                  CFRuntimeClasses.typeID(of: object) == CFRuntimeClasses.typeID(of: other),
                  let equal = CFRuntimeClasses.runtimeClass(of: object)?.pointee.equal else { return false }
            return equal(object, other) != 0
        }
        let hash: @convention(c) (id, SEL) -> UInt = { object, _ in
            CFRuntimeClasses.runtimeClass(of: object)?.pointee.hash?(object) ?? UInt(bitPattern: Int(bitPattern: object))
        }
        let description: @convention(c) (id, SEL) -> id? = { object, _ in
            let runtimeClass = CFRuntimeClasses.runtimeClass(of: object)
            if let copyDebugDesc = runtimeClass?.pointee.copyDebugDesc, let string = copyDebugDesc(object) {
                return ObjC.autorelease(string)
            }
            let name = runtimeClass?.pointee.className.map { String(cString: $0) } ?? "CFType"
            return Strings.autoreleased("<\(name) \(object)>")
        }
        let cfTypeID: @convention(c) (id, SEL) -> UInt = { object, _ in CFRuntimeClasses.typeID(of: object) }
        let methods: [(String, UnsafeRawPointer, String)] = [
            ("dealloc", unsafeBitCast(dealloc, to: UnsafeRawPointer.self), "v16@0:8"),
            ("isEqual:", unsafeBitCast(isEqual, to: UnsafeRawPointer.self), "B24@0:8@16"),
            ("hash", unsafeBitCast(hash, to: UnsafeRawPointer.self), "Q16@0:8"),
            ("description", unsafeBitCast(description, to: UnsafeRawPointer.self), "@16@0:8"),
            ("debugDescription", unsafeBitCast(description, to: UnsafeRawPointer.self), "@16@0:8"),
            ("_cfTypeID", unsafeBitCast(cfTypeID, to: UnsafeRawPointer.self), "Q16@0:8"),
        ]
        for (name, imp, types) in methods {
            _ = types.withCString { ObjC.addMethod(cls, ObjC.selector(name), imp, $0) }
        }
        ObjC.registerClassPair(cls)
        objectClass = cls
        return cls
    }
}

@c(__CFRuntimeRegisterClass)
public func _CFRuntimeRegisterClass(_ runtimeClass: UnsafeRawPointer?) -> UInt {
    guard let runtimeClass else { return 0 }
    return CFRuntimeClasses.withLock {
        CFRuntimeClasses.classes.append(runtimeClass.assumingMemoryBound(to: CFRuntimeClass.self))
        return CFRuntimeClasses.firstTypeID + UInt(CFRuntimeClasses.classes.count - 1)
    }
}

@c(__CFRuntimeGetClassWithTypeID)
public func _CFRuntimeGetClassWithTypeID(_ typeID: UInt) -> UnsafeRawPointer? {
    CFRuntimeClasses.runtimeClass(typeID).map(UnsafeRawPointer.init)
}

/// An instance of a registered type, retained, with `extraBytes` zeroed
/// after its CF header and the type's init callback run on it.
@c(__CFRuntimeCreateInstance)
public func _CFRuntimeCreateInstance(_ allocator: id?, _ typeID: UInt, _ extraBytes: Int,
                                     _ category: UnsafeMutablePointer<UInt8>?) -> id? {
    guard let runtimeClass = CFRuntimeClasses.runtimeClass(typeID) else { return nil }
    let cls = CFRuntimeClasses.withLock { CFRuntimeClasses.makeObjectClass() }
    // The class's instances are the isa alone; the CF information word is
    // the first of the extra bytes.
    guard let cls, let object = ObjC.createInstance(cls, MemoryLayout<UInt>.size + max(extraBytes, 0)) else {
        return nil
    }
    memset(object + MemoryLayout<UInt>.size, 0, MemoryLayout<UInt>.size + max(extraBytes, 0))
    object.storeBytes(of: typeID, toByteOffset: MemoryLayout<UInt>.size, as: UInt.self)
    runtimeClass.pointee.initialize?(object)
    return object
}

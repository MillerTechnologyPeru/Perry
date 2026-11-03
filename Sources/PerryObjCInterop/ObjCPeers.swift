#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

// Peers: Swift objects that are Objective-C objects, as Swift's objects are
// on Darwin. A class whose @ObjCMethod initializers are Swift initializers
// gets one Swift object per Objective-C object, made by the initializer and
// bound to the object in libPerryobjc, which counts references for both on
// the Swift object: retains from either side keep it, Objective-C's last
// release deallocates the object, and the Swift object's deinit runs as it
// goes. Methods run on that object, so its stored properties are the
// object's state.
//
// An -init message runs the Swift initializer of the receiver's class, or
// of its nearest ancestor this provider defines: NSObject's init() takes
// the receiver as the object to bind, rather than allocating one, as it
// does when Swift makes the object itself.
//
// Objects of classes that are not yet peers are wrapped as before: each
// wrapper holds a reference.

public enum ObjCPeers {
    typealias Bind = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Bool) -> Void
    typealias Peer = @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
    typealias WillDeinitialize = @convention(c) (UnsafeMutableRawPointer?) -> Bool

    nonisolated(unsafe) private static var bindFunction: Bind?
    nonisolated(unsafe) private static var peerFunction: Peer?
    nonisolated(unsafe) private static var willDeinitializeFunction: WillDeinitialize?

    /// libPerryobjc's peer functions, looked up through `lookup`.
    static func load(_ lookup: (String) -> UnsafeMutableRawPointer?) {
        bindFunction = lookup("_perry_objc_bindPeer").map { unsafeBitCast($0, to: Bind.self) }
        peerFunction = lookup("_perry_objc_peer").map { unsafeBitCast($0, to: Peer.self) }
        willDeinitializeFunction = lookup("_perry_objc_peerWillDeinitialize").map { unsafeBitCast($0, to: WillDeinitialize.self) }
    }

    /// For libPerryobjc itself, which calls its own functions.
    public static func install(bind: @escaping @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Bool) -> Void,
                               peer: @escaping @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?,
                               willDeinitialize: @escaping @convention(c) (UnsafeMutableRawPointer?) -> Bool) {
        (bindFunction, peerFunction, willDeinitializeFunction) = (bind, peer, willDeinitialize)
    }

    /// The object's Swift object, if it has one.
    public static func peer(of object: UnsafeMutableRawPointer) -> AnyObject? {
        guard let peerFunction, let peer = peerFunction(object) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(peer).takeUnretainedValue()
    }

    static func bind(_ object: UnsafeMutableRawPointer, _ peer: NSObject, retained: Bool) {
        guard let bindFunction else { objcInteropFatal("libPerryobjc cannot bind Swift objects to objects") }
        bindFunction(object, Unmanaged.passUnretained(peer).toOpaque(), retained)
    }

    /// The peer's deinit has begun: true when the object should now be
    /// deallocated, as Swift let go of it last.
    static func willDeinitialize(_ object: UnsafeMutableRawPointer) -> Bool { willDeinitializeFunction?(object) ?? false }

    // MARK: Classes

    private static let lock = InteropLock()
    nonisolated(unsafe) private static var classes: [UnsafeMutableRawPointer: NSObject.Type] = [:]

    /// Records the Swift class for a class this provider defines.
    static func register(_ cls: UnsafeMutableRawPointer, _ type: NSObject.Type) {
        lock.withLock { classes[cls] = type }
    }

    /// The Swift class for an object: its class's, or its nearest
    /// ancestor's, that is `base` or a subclass of it.
    public static func swiftClass<Base: NSObject>(of object: UnsafeMutableRawPointer, base: Base.Type) -> Base.Type {
        var current = ObjCRuntime.objectClass(object)
        while let cls = current {
            if let type = lock.withLock({ classes[cls] }), let match = type as? Base.Type { return match }
            current = cls.load(fromByteOffset: 8, as: UnsafeMutableRawPointer?.self)
        }
        return base
    }

    // MARK: Initializing

    /// Receivers of -init messages whose Swift initializers are running, by
    /// thread, innermost last, with the Swift class building each.
    nonisolated(unsafe) private static var receivers: [UInt: [(object: UnsafeMutableRawPointer, type: ObjectIdentifier)]] = [:]

    private static var thread: UInt {
        #if canImport(Glibc)
        UInt(pthread_self())
        #else
        UInt(bitPattern: pthread_self())
        #endif
    }

    /// Runs the -init method's Swift initializer for `receiver`, through
    /// `make`, given the Swift class to build: the receiver's own when the
    /// initializer is required, else `base`, whose initializer the
    /// receiver's class must not need overridden. Returns the object, +1,
    /// or nil having released the receiver, as a failed -init does.
    public static func initializing<Base: NSObject>(_ receiver: UnsafeMutableRawPointer, _ base: Base.Type, required: Bool,
                                                    _ make: (Base.Type) -> Base?) -> UnsafeMutableRawPointer? {
        let type = swiftClass(of: receiver, base: base)
        if !required, type != base {
            objcInteropFatal("\(type) inherits \(base)'s initializer, which must be required to build it")
        }
        let thread = thread
        lock.withLock { receivers[thread, default: []].append((receiver, ObjectIdentifier(type))) }
        let instance = make(type)
        let unclaimed = lock.withLock { () -> Bool in
            guard receivers[thread]?.last?.object == receiver else { return false }
            receivers[thread]?.removeLast()
            if receivers[thread]?.isEmpty == true { receivers[thread] = nil }
            return true
        }
        guard let instance else {
            if unclaimed { ObjCRuntime.release(receiver) }
            return nil
        }
        if unclaimed { objcInteropFatal("\(type)'s initializer did not reach NSObject's init()") }
        return instance.objcObject
    }

    /// The receiver an -init message's Swift initializer for `type` is
    /// building, which NSObject's init() binds; nil when Swift is making
    /// the object.
    static func takeReceiver(for type: NSObject.Type) -> UnsafeMutableRawPointer? {
        let thread = thread
        return lock.withLock {
            guard let last = receivers[thread]?.last, last.type == ObjectIdentifier(type) else { return nil }
            receivers[thread]?.removeLast()
            if receivers[thread]?.isEmpty == true { receivers[thread] = nil }
            return last.object
        }
    }

    /// A new object of `cls`, +1, from +alloc.
    static func allocate(_ cls: ObjCClass) -> UnsafeMutableRawPointer {
        typealias Send = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> UnsafeMutableRawPointer?
        guard let object = unsafeBitCast(ObjCRuntime.msgSend, to: Send.self)(cls.pointer, ObjCRuntime.selector("alloc")) else {
            objcInteropFatal("cannot allocate an instance of the class at \(cls.pointer)")
        }
        return object
    }
}

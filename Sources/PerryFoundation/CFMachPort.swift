import CPerryFoundation
import FoundationEssentials
import Glibc
import PerryObjCInterop

// CFMachPort over the ports within the process that PerrySystem's
// mach_port_allocate makes and its mach_msg carries. Once a port has a run
// loop source, a thread receives its messages, and the source, signalled,
// gives each to the program's callout on the loop.

/// CFMachPortCallBack: (port, message, size, info).
public typealias CFMachPortCallout = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?) -> Void

/// CFMachPortInvalidationCallBack: (port, info).
public typealias CFMachPortInvalidation = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void

final class MachPortStorage: FiringSource {
    typealias Callout = CFMachPortCallout
    typealias Invalidation = CFMachPortInvalidation

    let port: UInt32
    /// Whether CFMachPortCreate made the port, which goes with it.
    let ownsPort: Bool
    let callout: Callout?
    let context: InfoContext
    /// The CFMachPort, not retained: it owns this.
    var object: id?
    /// Guarded by MachPorts' lock.
    var valid = true
    var invalidation: Invalidation?
    var messages: [[UInt8]] = []
    var receiving = false
    var source: (object: id, storage: CustomSourceStorage)?

    init(port: UInt32, ownsPort: Bool, callout: Callout?, context: InfoContext) {
        (self.port, self.ownsPort, self.callout, self.context) = (port, ownsPort, callout, context)
    }

    /// The messages received since the last, on the loop.
    func fire() {
        let received = MachPorts.locked { () -> [[UInt8]] in
            defer { messages = [] }
            return valid ? messages : []
        }
        guard let object else { return }
        for var message in received {
            message.withUnsafeMutableBytes { callout?(object, $0.baseAddress, $0.count, context.info) }
        }
    }
}

enum MachPorts {
    nonisolated(unsafe) static var portClass: Class!

    typealias Message = @convention(c) (UnsafeMutableRawPointer?, Int32, UInt32, UInt32, UInt32, UInt32, UInt32) -> Int32
    typealias Allocate = @convention(c) (UInt32, Int32, UnsafeMutablePointer<UInt32>?) -> Int32
    typealias Destruct = @convention(c) (UInt32, UInt32, Int32, UInt64) -> Int32

    /// PerrySystem's mach_msg and the rest, which a program's are.
    nonisolated(unsafe) static let system = dlopen("libPerrySystem.so", RTLD_NOW | RTLD_NOLOAD)
    nonisolated(unsafe) static let message = system.flatMap { dlsym($0, "_mach_msg") }.map { unsafeBitCast($0, to: Message.self) }
    nonisolated(unsafe) static let allocate = system.flatMap { dlsym($0, "_mach_port_allocate") }.map { unsafeBitCast($0, to: Allocate.self) }
    nonisolated(unsafe) static let destruct = system.flatMap { dlsym($0, "_mach_port_destruct") }.map { unsafeBitCast($0, to: Destruct.self) }

    /// MACH_RCV_MSG | MACH_RCV_TIMEOUT, and MACH_RCV_TIMED_OUT.
    static let receiveWithTimeout: Int32 = 0x2 | 0x100
    static let receiveTimedOut: Int32 = 0x10004003

    nonisolated(unsafe) private static let mutex: UnsafeMutablePointer<pthread_mutex_t> = {
        let mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
        pthread_mutex_init(mutex, nil)
        return mutex
    }()
    /// The valid CFMachPorts, by their port.
    nonisolated(unsafe) static var byPort: [UInt32: id] = [:]

    static func storage(_ port: id?) -> MachPortStorage? { Storage.get(port, as: MachPortStorage.self) }

    static func locked<T>(_ body: () -> T) -> T {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return body()
    }

    static func make(port: UInt32, ownsPort: Bool, callout: MachPortStorage.Callout?, context: UnsafeRawPointer?) -> id? {
        guard let object = Storage.allocate(UnsafeMutableRawPointer(portClass)) else { return nil }
        let storage = MachPortStorage(port: port, ownsPort: ownsPort, callout: callout, context: InfoContext(retaining: context))
        storage.object = object
        Storage.set(object, storage)
        locked { byPort[port] = object }
        return object
    }

    /// Receives the port's messages for its source until it's invalid.
    static func receive(_ storage: MachPortStorage) {
        let started = locked { () -> Bool in
            guard storage.valid, !storage.receiving, message != nil else { return false }
            storage.receiving = true
            return true
        }
        guard started else { return }
        let retained = Unmanaged.passRetained(storage).toOpaque()
        var thread = pthread_t()
        pthread_create(&thread, nil, { context in
            let storage = Unmanaged<MachPortStorage>.fromOpaque(context!).takeRetainedValue()
            MachPorts.run(storage)
            return nil
        }, retained)
        pthread_detach(thread)
    }

    private static func run(_ storage: MachPortStorage) {
        guard let message else { return }
        let capacity = 65536
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 8)
        defer { buffer.deallocate() }
        while locked({ storage.valid }) {
            // A short timeout, so an invalidated port's thread ends.
            let result = message(buffer, receiveWithTimeout, 0, UInt32(capacity), storage.port, 100, 0)
            if result == receiveTimedOut { continue }
            guard result == 0 else {
                usleep(50_000)
                continue
            }
            // mach_msg_header_t: bits, then the message's size.
            let size = min(Int(buffer.load(fromByteOffset: 4, as: UInt32.self)), capacity)
            let bytes = Array(UnsafeRawBufferPointer(start: buffer, count: size))
            let source = locked { () -> CustomSourceStorage? in
                guard storage.valid else { return nil }
                storage.messages.append(bytes)
                return storage.source?.storage
            }
            source?.signal()
        }
    }

    /// Once: the invalidation callout, the source invalid, the port gone if
    /// CFMachPortCreate made it, and the info released.
    static func invalidate(_ storage: MachPortStorage) {
        let state = locked { () -> (source: (object: id, storage: CustomSourceStorage)?, invalidation: MachPortStorage.Invalidation?)? in
            guard storage.valid else { return nil }
            storage.valid = false
            storage.messages = []
            if byPort[storage.port] == storage.object { byPort[storage.port] = nil }
            defer { storage.source = nil }
            return (storage.source, storage.invalidation)
        }
        guard let state else { return }
        if let object = storage.object { state.invalidation?(object, storage.context.info) }
        if let source = state.source {
            source.storage.remove(from: nil)
            ObjC.release(source.object)
        }
        if storage.ownsPort { _ = destruct?(0, storage.port, 0, 0) }
        storage.object = nil
        storage.context.released()
    }
}

@ObjCClass("__NSCFMachPort")
final class NSCFMachPort: NSObject {
    override class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        MachPorts.portClass = cls.storage
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        MachPorts.storage(objcObject).map(MachPorts.invalidate)
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: MachPorts.portClass)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { 36 }
}

@c(_CFMachPortGetTypeID) public func CFMachPortGetTypeID() -> UInt { 36 }

/// A new port with a receive right, which goes when the CFMachPort is
/// invalidated.
@c(_CFMachPortCreate)
public func CFMachPortCreate(_ allocator: UnsafeRawPointer?, _ callout: CFMachPortCallout?, _ context: UnsafeRawPointer?,
                             _ shouldFreeInfo: UnsafeMutablePointer<UInt8>?) -> id? {
    shouldFreeInfo?.pointee = 0
    var port: UInt32 = 0
    guard let allocate = MachPorts.allocate, allocate(0, 1, &port) == 0, port != 0 else {
        shouldFreeInfo?.pointee = 1
        return nil
    }
    return MachPorts.make(port: port, ownsPort: true, callout: callout, context: context)
}

/// The CFMachPort of `port`: the one there is, retained, with
/// `shouldFreeInfo` set, as the program's context goes unused; or a new one.
@c(_CFMachPortCreateWithPort)
public func CFMachPortCreateWithPort(_ allocator: UnsafeRawPointer?, _ port: UInt32, _ callout: CFMachPortCallout?,
                                     _ context: UnsafeRawPointer?, _ shouldFreeInfo: UnsafeMutablePointer<UInt8>?) -> id? {
    if let existing = MachPorts.locked({ MachPorts.byPort[port] }) {
        shouldFreeInfo?.pointee = 1
        return ObjC.retain(existing)
    }
    shouldFreeInfo?.pointee = 0
    return MachPorts.make(port: port, ownsPort: false, callout: callout, context: context)
}

@c(_CFMachPortGetPort) public func CFMachPortGetPort(_ port: id?) -> UInt32 { MachPorts.storage(port)?.port ?? 0 }

@c(_CFMachPortGetContext)
public func CFMachPortGetContext(_ port: id?, _ context: UnsafeMutableRawPointer?) {
    MachPorts.storage(port)?.context.store(to: context)
}

@c(_CFMachPortInvalidate) public func CFMachPortInvalidate(_ port: id?) { MachPorts.storage(port).map(MachPorts.invalidate) }

@c(_CFMachPortIsValid)
public func CFMachPortIsValid(_ port: id?) -> Bool {
    guard let storage = MachPorts.storage(port) else { return false }
    return MachPorts.locked { storage.valid }
}

@c(_CFMachPortGetInvalidationCallBack)
public func CFMachPortGetInvalidationCallBack(_ port: id?) -> CFMachPortInvalidation? {
    guard let storage = MachPorts.storage(port) else { return nil }
    return MachPorts.locked { storage.invalidation }
}

/// Called at once on a port already invalid, as on Darwin.
@c(_CFMachPortSetInvalidationCallBack)
public func CFMachPortSetInvalidationCallBack(_ port: id?, _ callout: CFMachPortInvalidation?) {
    guard let port, let storage = MachPorts.storage(port) else { return }
    let valid = MachPorts.locked { () -> Bool in
        storage.invalidation = callout
        return storage.valid
    }
    if !valid { callout?(port, storage.context.info) }
}

/// The port's one source (+1), made the first time, which starts its
/// messages being received.
@c(_CFMachPortCreateRunLoopSource)
public func CFMachPortCreateRunLoopSource(_ allocator: UnsafeRawPointer?, _ port: id?, _ order: Int) -> id? {
    guard let storage = MachPorts.storage(port) else { return nil }
    let existing = MachPorts.locked { () -> id?? in
        guard storage.valid else { return .some(nil) }
        return storage.source.map { .some($0.object) }
    }
    if let existing { return existing.flatMap { ObjC.retain($0) } }
    guard let made = FiringSources.make(for: storage) else { return nil }
    let source = MachPorts.locked { () -> id in
        if let current = storage.source { return current.object }
        storage.source = made
        return made.0
    }
    if source != made.0 { ObjC.release(made.0) }
    MachPorts.receive(storage)
    return ObjC.retain(source)
}

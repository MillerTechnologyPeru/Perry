import CPerryFoundation
import Glibc
import PerryObjCInterop
import Socket

// CFSocket: an IPv4 or IPv6 socket whose readiness is reported by callbacks
// on the run loops its source is added to. One thread waits in poll() on
// every scheduled socket's armed callbacks; a callback that comes due is
// disarmed and made on the socket's run loop, then armed again when the
// socket's flags say so or the app enables it, as CoreFoundation does.

/// CFSocketCallBackType: read, accept and data are one choice in the low
/// two bits.
enum SocketCallBack {
    static let read: UInt = 1
    static let accept: UInt = 2
    static let data: UInt = 3
    static let connect: UInt = 4
    static let write: UInt = 8
    static let reading: UInt = 3
}

/// A socket's flags: which callbacks are armed again once made (the same
/// bits as the callback types), and whether invalidating closes it.
enum SocketFlag {
    static let closeOnInvalidate: UInt = 128
    /// What a new socket has: reads re-armed, closed when invalidated.
    static let initial: UInt = SocketCallBack.reading | closeOnInvalidate
}

/// An address, converted to and from the sockaddr Darwin apps pass: a
/// length byte and a family byte (IPv6 is 30), then the port and address
/// as Linux has them.
enum SocketEndpoint {
    case ipv4(IPv4SocketAddress)
    case ipv6(IPv6SocketAddress)

    init?(darwin bytes: UnsafeRawBufferPointer) {
        guard bytes.count >= 16 else { return nil }
        let port = UInt16(bytes[2]) << 8 | UInt16(bytes[3])
        switch bytes[1] {
        case 2:
            var address = in_addr()
            withUnsafeMutableBytes(of: &address) { $0.copyBytes(from: bytes[4 ..< 8]) }
            self = .ipv4(IPv4SocketAddress(address: IPv4Address(address), port: port))
        case 30 where bytes.count >= 28:
            var address = in6_addr()
            withUnsafeMutableBytes(of: &address) { $0.copyBytes(from: bytes[8 ..< 24]) }
            self = .ipv6(IPv6SocketAddress(address: IPv6Address(address), port: port))
        default:
            return nil
        }
    }

    var darwin: [UInt8] {
        switch self {
        case .ipv4(let address):
            var bytes = [UInt8](repeating: 0, count: 16)
            bytes[0 ..< 4] = [16, 2, UInt8(address.port >> 8), UInt8(address.port & 0xff)]
            address.address.withUnsafeBytes { bytes.replaceSubrange(4 ..< 8, with: $0.prefix(4)) }
            return bytes
        case .ipv6(let address):
            var bytes = [UInt8](repeating: 0, count: 28)
            bytes[0 ..< 4] = [28, 30, UInt8(address.port >> 8), UInt8(address.port & 0xff)]
            address.address.withUnsafeBytes { bytes.replaceSubrange(8 ..< 24, with: $0.prefix(16)) }
            return bytes
        }
    }
}

final class SocketStorage {
    typealias Callout = @convention(c) (id?, UInt, id?, UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Void
    typealias Release = @convention(c) (UnsafeRawPointer?) -> Void

    let descriptor: SocketDescriptor
    let isIPv6: Bool
    /// The callbacks the socket was made with.
    let types: UInt
    let callout: Callout?
    let info: UnsafeMutableRawPointer?
    let release: Release?
    /// The CFSocket, not retained; nil once it is invalid.
    var object: id?
    var flags = SocketFlag.initial
    var valid = true
    var armedRead: Bool
    var armedWrite: Bool
    /// A connection is being made in the background.
    var connecting = false
    var connected = false
    var loops: [RunLoopState] = []

    init(descriptor: SocketDescriptor, isIPv6: Bool, types: UInt, callout: Callout?, info: UnsafeMutableRawPointer?,
         release: Release?) {
        (self.descriptor, self.isIPv6, self.types) = (descriptor, isIPv6, types)
        (self.callout, self.info, self.release) = (callout, info, release)
        armedRead = types & SocketCallBack.reading != 0
        armedWrite = types & SocketCallBack.write != 0
    }

    /// What the watching thread waits for. A socket that reports its
    /// connection isn't writable until that's made.
    var awaited: FileEvents {
        var events: FileEvents = []
        if armedRead { events.insert(.read) }
        if connecting || (armedWrite && (connected || types & SocketCallBack.connect == 0)) { events.insert(.write) }
        return events
    }

    func bind(_ endpoint: SocketEndpoint) -> Errno? {
        do throws(Errno) {
            switch endpoint {
            case .ipv4(let address): try descriptor.bind(address)
            case .ipv6(let address): try descriptor.bind(address)
            }
            return nil
        } catch {
            return error
        }
    }

    func connect(_ endpoint: SocketEndpoint) -> Errno? {
        do throws(Errno) {
            switch endpoint {
            case .ipv4(let address): try descriptor.connect(to: address)
            case .ipv6(let address): try descriptor.connect(to: address)
            }
            return nil
        } catch {
            return error
        }
    }

    /// The next connection, and where it's from.
    func accept() -> (SocketDescriptor, SocketEndpoint)? {
        if isIPv6 {
            return (try? descriptor.accept(IPv6SocketAddress.self)).map { ($0.0, .ipv6($0.1)) }
        }
        return (try? descriptor.accept(IPv4SocketAddress.self)).map { ($0.0, .ipv4($0.1)) }
    }

    /// What has arrived, and where it's from.
    func receive() -> ([UInt8], SocketEndpoint)? {
        var bytes = [UInt8](repeating: 0, count: 65536)
        let received: (Int, SocketEndpoint)? = bytes.withUnsafeMutableBytes { buffer in
            if isIPv6 {
                return (try? descriptor.receive(into: buffer, fromAddressOf: IPv6SocketAddress.self)).map { ($0.0, .ipv6($0.1)) }
            }
            return (try? descriptor.receive(into: buffer, fromAddressOf: IPv4SocketAddress.self)).map { ($0.0, .ipv4($0.1)) }
        }
        return received.map { (Array(bytes.prefix($0.0)), $0.1) }
    }

    /// The error a finished connection attempt left, 0 for none.
    var pendingError: Int32 {
        var error: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        return getsockopt(descriptor.rawValue, SOL_SOCKET, SO_ERROR, &error, &length) == 0 ? error : errno
    }
}

/// A CFRunLoopSource: here always a socket's.
final class SocketSourceStorage {
    let socket: id

    init(socket: id) { self.socket = ObjC.retain(socket) ?? socket }
    deinit { ObjC.release(socket) }
}

enum Sockets {
    nonisolated(unsafe) static var socketClass: Class!
    nonisolated(unsafe) static var sourceClass: Class!

    nonisolated(unsafe) private static let mutex: UnsafeMutablePointer<pthread_mutex_t> = {
        let mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
        pthread_mutex_init(mutex, nil)
        return mutex
    }()
    /// The valid sockets scheduled on a run loop.
    nonisolated(unsafe) private static var watched: [SocketStorage] = []
    nonisolated(unsafe) private static var watching = false
    /// Written to when what the watching thread waits for has changed.
    private static let wake = SocketDescriptor(rawValue: eventfd(0, Int32(EFD_CLOEXEC | EFD_NONBLOCK)))

    static func storage(_ socket: id?) -> SocketStorage? { Storage.get(socket, as: SocketStorage.self) }
    static func source(_ source: id?) -> SocketSourceStorage? { Storage.get(source, as: SocketSourceStorage.self) }

    static func locked<T>(_ body: () -> T) -> T {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return body()
    }

    static func changed() { _ = eventfd_write(wake.rawValue, 1) }

    /// The address in a CFData holding a Darwin sockaddr.
    static func endpoint(_ data: id?) -> SocketEndpoint? {
        guard let data, let bytes = CFDataGetBytePtr(data) else { return nil }
        return SocketEndpoint(darwin: UnsafeRawBufferPointer(start: bytes, count: CFDataGetLength(data)))
    }

    static func make(_ storage: SocketStorage) -> id? {
        guard let object = Storage.allocate(UnsafeMutableRawPointer(socketClass)) else { return nil }
        storage.object = object
        Storage.set(object, storage)
        return object
    }

    static func schedule(_ storage: SocketStorage, on loop: RunLoopState) {
        let added = locked { () -> Bool in
            guard storage.valid, !storage.loops.contains(where: { $0 === loop }) else { return false }
            storage.loops.append(loop)
            if !watched.contains(where: { $0 === storage }) { watched.append(storage) }
            if !watching {
                watching = true
                var thread = pthread_t()
                pthread_create(&thread, nil, { _ in Sockets.watch() }, nil)
                pthread_detach(thread)
            }
            return true
        }
        guard added else { return }
        loop.addSource()
        changed()
    }

    /// Takes the socket off `loop`, or off every run loop.
    static func unschedule(_ storage: SocketStorage, from loop: RunLoopState?) {
        let removed = locked { () -> [RunLoopState] in
            let removed = storage.loops.filter { loop == nil || $0 === loop }
            storage.loops.removeAll { loop == nil || $0 === loop }
            if storage.loops.isEmpty { watched.removeAll { $0 === storage } }
            return removed
        }
        removed.forEach { $0.removeSource() }
        if !removed.isEmpty { changed() }
    }

    static func invalidate(_ storage: SocketStorage) {
        let wasValid = locked { () -> Bool in
            defer {
                storage.valid = false
                storage.object = nil
            }
            return storage.valid
        }
        guard wasValid else { return }
        unschedule(storage, from: nil)
        changed()
        if storage.flags & SocketFlag.closeOnInvalidate != 0 { try? storage.descriptor.close() }
        storage.release?(storage.info)
    }

    /// The watching thread: waits for what each scheduled socket has armed.
    private static func watch() -> UnsafeMutableRawPointer? {
        while true {
            var polls = [SocketDescriptor.Poll(socket: wake, events: .read)]
            let polled = locked { () -> [SocketStorage] in
                let waiting = watched.filter { $0.valid && !$0.awaited.isEmpty }
                polls += waiting.map { SocketDescriptor.Poll(socket: $0.descriptor, events: $0.awaited) }
                return waiting
            }
            try? polls.poll(timeout: -1)
            var value: eventfd_t = 0
            _ = eventfd_read(wake.rawValue, &value)
            for (index, storage) in polled.enumerated() {
                let events = polls[index + 1].returnedEvents
                if !events.isEmpty { ready(storage, events) }
            }
        }
    }

    /// Disarms the callbacks `events` make due and has the socket's run
    /// loop make them.
    private static func ready(_ storage: SocketStorage, _ events: FileEvents) {
        let due = locked { () -> (loop: RunLoopState, kinds: UInt)? in
            guard storage.valid, let loop = storage.loops.first else { return nil }
            // A failed socket is both readable and writable: reading or
            // writing it gives the error.
            let failed = !events.isDisjoint(with: [.error, .hangup, .invalidRequest])
            var kinds: UInt = 0
            if failed || events.contains(.write) {
                if storage.connecting {
                    storage.connecting = false
                    storage.connected = true
                    kinds |= storage.types & SocketCallBack.connect
                } else if storage.armedWrite {
                    storage.armedWrite = false
                    kinds |= SocketCallBack.write
                }
            }
            if storage.armedRead, failed || events.contains(.read) {
                storage.armedRead = false
                kinds |= storage.types & SocketCallBack.reading
            }
            return kinds == 0 ? nil : (loop, kinds)
        }
        guard let due else { return }
        due.loop.perform { deliver(storage, due.kinds) }
    }

    /// The socket to call back with, while it is valid.
    private static func target(_ storage: SocketStorage) -> id? { locked { storage.valid ? storage.object : nil } }

    private static func data(_ bytes: [UInt8]) -> id? { bytes.withUnsafeBufferPointer { CFDataCreate(nil, $0.baseAddress, $0.count) } }

    /// On the socket's run loop: makes the callbacks that came due, then
    /// arms again those the socket's flags say to. The app may invalidate
    /// and release the socket in any of them.
    private static func deliver(_ storage: SocketStorage, _ kinds: UInt) {
        let info = storage.info
        if kinds & SocketCallBack.connect != 0, let socket = target(storage) {
            // The data is the error's number when the connection failed.
            var error = storage.pendingError
            if error == 0 {
                storage.callout?(socket, SocketCallBack.connect, nil, nil, info)
            } else {
                withUnsafePointer(to: &error) { storage.callout?(socket, SocketCallBack.connect, nil, $0, info) }
            }
        }
        if kinds & SocketCallBack.write != 0, let socket = target(storage) {
            storage.callout?(socket, SocketCallBack.write, nil, nil, info)
        }
        switch kinds & SocketCallBack.reading {
        case SocketCallBack.read:
            if let socket = target(storage) { storage.callout?(socket, SocketCallBack.read, nil, nil, info) }
        case SocketCallBack.accept:
            // The data is the new connection's native socket.
            if let socket = target(storage), let (connection, peer) = storage.accept() {
                let address = data(peer.darwin)
                var native = connection.rawValue
                withUnsafePointer(to: &native) { storage.callout?(socket, SocketCallBack.accept, address, $0, info) }
                if let address { ObjC.release(address) }
            }
        case SocketCallBack.data:
            if let socket = target(storage), let (bytes, peer) = storage.receive() {
                let address = data(peer.darwin), received = data(bytes)
                storage.callout?(socket, SocketCallBack.data, address, received.map { UnsafeRawPointer($0) }, info)
                if let address { ObjC.release(address) }
                if let received { ObjC.release(received) }
            }
        default:
            break
        }
        locked {
            guard storage.valid else { return }
            if kinds & storage.flags & SocketCallBack.write != 0 { storage.armedWrite = true }
            let reading = kinds & SocketCallBack.reading
            if reading != 0, storage.flags & reading == reading { storage.armedRead = true }
        }
        changed()
    }
}

@ObjCClass("__NSCFSocket")
final class NSCFSocket: NSObject {
    override class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Sockets.socketClass = cls.storage
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Sockets.storage(objcObject).map(Sockets.invalidate)
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Sockets.socketClass)
    }
}

@ObjCClass("__NSCFRunLoopSource")
final class NSCFRunLoopSource: NSObject {
    override class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Sockets.sourceClass = cls.storage
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Sockets.sourceClass)
    }
}

// MARK: - CFSocket

/// A stream socket unless a datagram one (2) is asked for, IPv4 unless the
/// family is Darwin's PF_INET6 (30). The context is { version, info,
/// retain, release, copyDescription }.
@c(_CFSocketCreate)
public func CFSocketCreate(_ allocator: UnsafeRawPointer?, _ family: Int32, _ type: Int32, _ protocolID: Int32, _ types: UInt,
                           _ callout: (@convention(c) (UnsafeMutableRawPointer?, UInt, UnsafeMutableRawPointer?, UnsafeRawPointer?,
                                                       UnsafeMutableRawPointer?) -> Void)?,
                           _ context: UnsafeRawPointer?) -> UnsafeMutableRawPointer? {
    let datagram = type == 2
    let descriptor: SocketDescriptor?
    switch family {
    case 0, 2: descriptor = try? SocketDescriptor(datagram ? IPv4Protocol.udp : .tcp, flags: [.closeOnExec])
    case 30: descriptor = try? SocketDescriptor(datagram ? IPv6Protocol.udp : .tcp, flags: [.closeOnExec])
    default: descriptor = nil
    }
    guard let descriptor else { return nil }
    typealias Retain = @convention(c) (UnsafeRawPointer?) -> UnsafeRawPointer?
    var info = context?.load(fromByteOffset: DarwinLayout.contextInfo, as: UnsafeMutableRawPointer?.self)
    if let retain = context?.load(fromByteOffset: DarwinLayout.contextRetain, as: Retain?.self) {
        info = UnsafeMutableRawPointer(mutating: retain(info))
    }
    let release = context?.load(fromByteOffset: DarwinLayout.contextRelease, as: SocketStorage.Release?.self)
    return Sockets.make(SocketStorage(descriptor: descriptor, isIPv6: family == 30, types: types, callout: callout, info: info,
                                      release: release))
}

@c(_CFSocketGetNative)
public func CFSocketGetNative(_ socket: UnsafeMutableRawPointer?) -> Int32 {
    guard let storage = Sockets.storage(socket), storage.valid else { return -1 }
    return storage.descriptor.rawValue
}

@c(_CFSocketIsValid)
public func CFSocketIsValid(_ socket: UnsafeMutableRawPointer?) -> Bool { Sockets.storage(socket)?.valid ?? false }

@c(_CFSocketInvalidate)
public func CFSocketInvalidate(_ socket: UnsafeMutableRawPointer?) { Sockets.storage(socket).map(Sockets.invalidate) }

@c(_CFSocketGetSocketFlags)
public func CFSocketGetSocketFlags(_ socket: UnsafeMutableRawPointer?) -> UInt { Sockets.storage(socket)?.flags ?? 0 }

@c(_CFSocketSetSocketFlags)
public func CFSocketSetSocketFlags(_ socket: UnsafeMutableRawPointer?, _ flags: UInt) {
    guard let storage = Sockets.storage(socket) else { return }
    Sockets.locked { storage.flags = flags }
}

/// Arms callbacks the socket was made with.
@c(_CFSocketEnableCallBacks)
public func CFSocketEnableCallBacks(_ socket: UnsafeMutableRawPointer?, _ types: UInt) {
    guard let storage = Sockets.storage(socket) else { return }
    Sockets.locked {
        if types & storage.types & SocketCallBack.reading != 0 { storage.armedRead = true }
        if types & storage.types & SocketCallBack.write != 0 { storage.armedWrite = true }
    }
    Sockets.changed()
}

@c(_CFSocketDisableCallBacks)
public func CFSocketDisableCallBacks(_ socket: UnsafeMutableRawPointer?, _ types: UInt) {
    guard let storage = Sockets.storage(socket) else { return }
    Sockets.locked {
        if types & SocketCallBack.reading != 0 { storage.armedRead = false }
        if types & SocketCallBack.write != 0 { storage.armedWrite = false }
    }
    Sockets.changed()
}

/// Binds the socket and, as CoreFoundation does, has it listen. A
/// CFSocketError: 0, or -1 for an error.
@c(_CFSocketSetAddress)
public func CFSocketSetAddress(_ socket: UnsafeMutableRawPointer?, _ address: UnsafeMutableRawPointer?) -> Int {
    guard let storage = Sockets.storage(socket), storage.valid, let endpoint = Sockets.endpoint(address),
          storage.bind(endpoint) == nil else { return -1 }
    try? storage.descriptor.listen(backlog: 256)
    return 0
}

/// Connects, waiting up to `timeout` seconds; a negative one connects in
/// the background, which the connect callback reports. A CFSocketError:
/// 0, -1 for an error or -2 for a timeout.
@c(_CFSocketConnectToAddress)
public func CFSocketConnectToAddress(_ socket: UnsafeMutableRawPointer?, _ address: UnsafeMutableRawPointer?,
                                     _ timeout: Double) -> Int {
    guard let storage = Sockets.storage(socket), storage.valid, let endpoint = Sockets.endpoint(address) else { return -1 }
    let file = storage.descriptor.rawValue
    let status = fcntl(file, F_GETFL)
    let wasBlocking = status >= 0 && status & O_NONBLOCK == 0
    if wasBlocking, timeout != 0 { _ = fcntl(file, F_SETFL, status | O_NONBLOCK) }
    defer { if wasBlocking, timeout > 0 { _ = fcntl(file, F_SETFL, status) } }
    let error = storage.connect(endpoint)
    if timeout < 0, error == nil || error == .nowInProgress {
        Sockets.locked { storage.connecting = true }
        Sockets.changed()
        return 0
    }
    guard let error else {
        Sockets.locked { storage.connected = true }
        Sockets.changed()
        return 0
    }
    guard error == .nowInProgress, timeout > 0 else { return -1 }
    let events = (try? storage.descriptor.poll(for: .write, timeout: Int(timeout * 1000))) ?? []
    guard !events.isEmpty else { return -2 }
    guard storage.pendingError == 0 else { return -1 }
    Sockets.locked { storage.connected = true }
    Sockets.changed()
    return 0
}

// MARK: - Run loop sources

@c(_CFSocketCreateRunLoopSource)
public func CFSocketCreateRunLoopSource(_ allocator: UnsafeRawPointer?, _ socket: UnsafeMutableRawPointer?,
                                        _ order: Int) -> UnsafeMutableRawPointer? {
    guard let socket, let storage = Sockets.storage(socket), storage.valid,
          let object = Storage.allocate(UnsafeMutableRawPointer(Sockets.sourceClass)) else { return nil }
    Storage.set(object, SocketSourceStorage(socket: socket))
    return object
}

/// Every mode is the same run loop here.
@c(_CFRunLoopAddSource)
public func CFRunLoopAddSource(_ runLoop: UnsafeMutableRawPointer?, _ source: UnsafeMutableRawPointer?,
                               _ mode: UnsafeMutableRawPointer?) {
    guard let loop = RunLoops.state(runLoop), let storage = Sockets.storage(Sockets.source(source)?.socket) else { return }
    Sockets.schedule(storage, on: loop)
}

@c(_CFRunLoopRemoveSource)
public func CFRunLoopRemoveSource(_ runLoop: UnsafeMutableRawPointer?, _ source: UnsafeMutableRawPointer?,
                                  _ mode: UnsafeMutableRawPointer?) {
    guard let loop = RunLoops.state(runLoop), let storage = Sockets.storage(Sockets.source(source)?.socket) else { return }
    Sockets.unschedule(storage, from: loop)
}

@c(_CFRunLoopSourceInvalidate)
public func CFRunLoopSourceInvalidate(_ source: UnsafeMutableRawPointer?) {
    guard let storage = Sockets.storage(Sockets.source(source)?.socket) else { return }
    Sockets.unschedule(storage, from: nil)
}

import CPerryFoundation
import FoundationEssentials
import Glibc
import PerryObjCInterop
import Socket

// CFSocket's other functions: sockets made over a native socket or from a
// signature, their addresses and context, sending data, and the name
// registry. Addresses are Darwin's sockaddrs (a length byte, then the
// family: 2 for IPv4, 30 for IPv6, 1 for a local socket), converted to and
// from Linux's, whose family is a 16-bit word.

/// CFSocketCallBack: (socket, type, address, data, info).
public typealias CFSocketCallout = @convention(c) (UnsafeMutableRawPointer?, UInt, UnsafeMutableRawPointer?, UnsafeRawPointer?,
                                                   UnsafeMutableRawPointer?) -> Void

/// A CFSocket, not kept alive: the native socket's entry.
final class WeakSocket {
    weak var storage: SocketStorage?
    init(_ storage: SocketStorage) { self.storage = storage }
}

/// CFSocketSignature: { SInt32 protocolFamily, socketType, protocol;
/// CFDataRef address }, the address at the next word.
struct SocketSignature {
    let family: Int32
    let type: Int32
    let protocolID: Int32
    let address: id?

    static let addressOffset = (12 + DarwinLayout.word - 1) / DarwinLayout.word * DarwinLayout.word

    init?(_ pointer: UnsafeRawPointer?) {
        guard let pointer else { return nil }
        family = pointer.load(as: Int32.self)
        type = pointer.load(fromByteOffset: 4, as: Int32.self)
        protocolID = pointer.load(fromByteOffset: 8, as: Int32.self)
        address = pointer.load(fromByteOffset: Self.addressOffset, as: id?.self)
    }
}

extension Sockets {
    static let typeID: UInt = 61

    /// SO_SNDTIMEO, which glibc defines by time_t's size where it can be
    /// either, past what Swift imports: on the 32-bit loaders time_t is 32
    /// bits, the option's old form.
    #if _pointerBitWidth(_32)
    static let sendTimeoutOption = SO_SNDTIMEO_OLD
    #else
    static let sendTimeoutOption = SO_SNDTIMEO
    #endif

    /// Every CFSocket made, by its native socket.
    nonisolated(unsafe) static var byNative: [Int32: WeakSocket] = [:]

    /// A new CFSocket (+1) over `descriptor`, its context's info retained.
    static func make(descriptor: SocketDescriptor, isIPv6: Bool, types: UInt, callout: CFSocketCallout?,
                     context: UnsafeRawPointer?) -> id? {
        let info = InfoContext(retaining: context)
        let storage = SocketStorage(descriptor: descriptor, isIPv6: isIPv6, types: types, callout: callout, info: info.info,
                                    release: info.release)
        storage.context = info
        guard let object = make(storage) else { return nil }
        locked {
            byNative = byNative.filter { $0.value.storage?.valid ?? false }
            byNative[descriptor.rawValue] = WeakSocket(storage)
        }
        return object
    }

    /// The valid CFSocket over `native`, retained, if there is one.
    static func existing(_ native: Int32) -> id? {
        let object = locked { () -> id? in
            guard let storage = byNative[native]?.storage, storage.valid else { return nil }
            return storage.object
        }
        return object.flatMap { ObjC.retain($0) }
    }

    /// The family of a native socket's address, Linux's number.
    static func family(of native: Int32) -> Int32 {
        var address = sockaddr_storage()
        var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let result = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(native, $0, &length) }
        }
        return result == 0 ? Int32(address.ss_family) : -1
    }

    /// A Linux sockaddr's bytes as Darwin's.
    static func darwinAddress(_ bytes: UnsafeRawBufferPointer) -> [UInt8]? {
        guard bytes.count >= 2 else { return nil }
        let family = Int32(bytes.load(as: sa_family_t.self))
        var darwin: [UInt8]
        switch family {
        case AF_INET where bytes.count >= 16:
            darwin = Array(bytes.prefix(16))
            darwin[1] = 2
        case AF_INET6 where bytes.count >= 28:
            darwin = Array(bytes.prefix(28))
            darwin[1] = 30
        case AF_UNIX:
            // Darwin's path has room for 104 bytes.
            darwin = Array(bytes.prefix(106))
            darwin[1] = 1
        default:
            return nil
        }
        darwin[0] = UInt8(darwin.count)
        return darwin
    }

    /// A CFData of a Darwin sockaddr as Linux's bytes.
    static func linuxAddress(_ data: id?) -> [UInt8]? {
        guard let data, let pointer = CFDataGetBytePtr(data) else { return nil }
        let count = CFDataGetLength(data)
        guard count >= 2 else { return nil }
        var bytes = Array(UnsafeRawBufferPointer(start: pointer, count: count))
        let family: sa_family_t
        switch bytes[1] {
        case 2 where count >= 16:
            family = sa_family_t(AF_INET)
            bytes = Array(bytes.prefix(16))
        case 30 where count >= 28:
            family = sa_family_t(AF_INET6)
            bytes = Array(bytes.prefix(28))
        case 1:
            family = sa_family_t(AF_UNIX)
        default:
            return nil
        }
        withUnsafeBytes(of: family) { bytes.replaceSubrange(0 ..< 2, with: $0) }
        return bytes
    }

    /// The socket's own address, or its peer's, as a Darwin sockaddr in a
    /// CFData (+1).
    static func copyAddress(_ native: Int32, peer: Bool) -> id? {
        var address = sockaddr_storage()
        var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let result = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { peer ? getpeername(native, $0, &length) : getsockname(native, $0, &length) }
        }
        guard result == 0 else { return nil }
        let count = min(Int(length), MemoryLayout<sockaddr_storage>.size)
        guard let bytes = withUnsafeBytes(of: address, { darwinAddress(UnsafeRawBufferPointer(rebasing: $0.prefix(count))) }) else {
            return nil
        }
        return bytes.withUnsafeBufferPointer { CFDataCreate(nil, $0.baseAddress, $0.count) }
    }
}

@c(_CFSocketGetTypeID) public func CFSocketGetTypeID() -> UInt { Sockets.typeID }

/// A CFSocket (+1) over a socket the program made. As on Darwin, a socket
/// that already has a valid CFSocket gives that one, retained, and the
/// callbacks and context given are not used.
@c(_CFSocketCreateWithNative)
public func CFSocketCreateWithNative(_ allocator: UnsafeRawPointer?, _ native: Int32, _ types: UInt, _ callout: CFSocketCallout?,
                                     _ context: UnsafeRawPointer?) -> id? {
    guard native >= 0 else { return nil }
    if let existing = Sockets.existing(native) { return existing }
    return Sockets.make(descriptor: SocketDescriptor(rawValue: native), isIPv6: Sockets.family(of: native) == AF_INET6, types: types,
                        callout: callout, context: context)
}

/// A socket (+1) of the signature's family, type and protocol, bound to its
/// address and listening; NULL when it can't be bound.
@c(_CFSocketCreateWithSocketSignature)
public func CFSocketCreateWithSocketSignature(_ allocator: UnsafeRawPointer?, _ signature: UnsafeRawPointer?, _ types: UInt,
                                              _ callout: CFSocketCallout?, _ context: UnsafeRawPointer?) -> id? {
    guard let signature = SocketSignature(signature),
          let socket = CFSocketCreate(allocator, signature.family, signature.type, signature.protocolID, types, callout, context)
    else { return nil }
    guard CFSocketSetAddress(socket, signature.address) == 0 else {
        CFSocketInvalidate(socket)
        ObjC.release(socket)
        return nil
    }
    return socket
}

/// A socket (+1) connected to the signature's address, waiting up to
/// `timeout` seconds; a negative timeout connects in the background, which
/// the connect callback reports. NULL when the connection fails.
@c(_CFSocketCreateConnectedToSocketSignature)
public func CFSocketCreateConnectedToSocketSignature(_ allocator: UnsafeRawPointer?, _ signature: UnsafeRawPointer?, _ types: UInt,
                                                     _ callout: CFSocketCallout?, _ context: UnsafeRawPointer?,
                                                     _ timeout: Double.ObjCType) -> id? {
    guard let signature = SocketSignature(signature),
          let socket = CFSocketCreate(allocator, signature.family, signature.type, signature.protocolID, types, callout, context)
    else { return nil }
    guard CFSocketConnectToAddress(socket, signature.address, Double(objCArgument: timeout)) == 0 else {
        CFSocketInvalidate(socket)
        ObjC.release(socket)
        return nil
    }
    return socket
}

/// The address the socket is bound to, as a Darwin sockaddr (+1).
@c(_CFSocketCopyAddress)
public func CFSocketCopyAddress(_ socket: id?) -> id? {
    guard let storage = Sockets.storage(socket), storage.valid else { return nil }
    return Sockets.copyAddress(storage.descriptor.rawValue, peer: false)
}

/// The address of the socket's peer, as a Darwin sockaddr (+1); NULL for a
/// socket not connected.
@c(_CFSocketCopyPeerAddress)
public func CFSocketCopyPeerAddress(_ socket: id?) -> id? {
    guard let storage = Sockets.storage(socket), storage.valid else { return nil }
    return Sockets.copyAddress(storage.descriptor.rawValue, peer: true)
}

/// The context the socket was made with: { version, info, retain, release,
/// copyDescription }, the info as retained.
@c(_CFSocketGetContext)
public func CFSocketGetContext(_ socket: id?, _ context: UnsafeMutableRawPointer?) {
    Sockets.storage(socket)?.context.store(to: context)
}

/// Sends the data, to `address` if one is given (a datagram socket's), with
/// `timeout` seconds as the socket's send timeout, as Darwin sets it. A
/// CFSocketError: 0, or -1 when nothing was sent.
@c(_CFSocketSendData)
public func CFSocketSendData(_ socket: id?, _ address: id?, _ data: id?, _ timeout: Double.ObjCType) -> Int {
    guard let storage = Sockets.storage(socket), storage.valid, let data else { return -1 }
    let file = storage.descriptor.rawValue
    let seconds = Double(objCArgument: timeout)
    var limit = timeval()
    let forever = seconds <= 0 || seconds >= Double(Int32.max)
    limit.tv_sec = forever ? time_t(Int32.max) : time_t(seconds.rounded(.down))
    limit.tv_usec = forever ? 0 : suseconds_t((1e6 * (seconds - seconds.rounded(.down))).rounded(.down))
    _ = setsockopt(file, SOL_SOCKET, Sockets.sendTimeoutOption, &limit, socklen_t(MemoryLayout<timeval>.size))
    let length = CFDataGetLength(data)
    let bytes = CFDataGetBytePtr(data)
    let sent: Int
    if address != nil {
        guard let target = Sockets.linuxAddress(address) else { return -1 }
        sent = target.withUnsafeBytes {
            sendto(file, bytes, length, Int32(MSG_NOSIGNAL), $0.baseAddress?.assumingMemoryBound(to: sockaddr.self), socklen_t($0.count))
        }
    } else {
        sent = send(file, bytes, length, Int32(MSG_NOSIGNAL))
    }
    return sent > 0 ? 0 : -1
}

// MARK: - Name registry

// The registry is a server CFSocket asks over the network (port 2454 on
// the host the name server signature gives, by default this one). There
// is no such server here, so each request fails as Darwin's does when the
// server can't be reached: kCFSocketError, with nothing returned.

nonisolated(unsafe) private var nameRegistryPort: UInt16 = 2454

@c(_CFSocketGetDefaultNameRegistryPortNumber)
public func CFSocketGetDefaultNameRegistryPortNumber() -> UInt16 { nameRegistryPort }

@c(_CFSocketSetDefaultNameRegistryPortNumber)
public func CFSocketSetDefaultNameRegistryPortNumber(_ port: UInt16) { nameRegistryPort = port }

/// No name server answers: kCFSocketError.
@c(_CFSocketRegisterValue)
public func CFSocketRegisterValue(_ nameServer: UnsafeRawPointer?, _ timeout: Double.ObjCType, _ name: id?, _ value: id?) -> Int { -1 }

/// No name server answers: kCFSocketError, with no value or address.
@c(_CFSocketCopyRegisteredValue)
public func CFSocketCopyRegisteredValue(_ nameServer: UnsafeRawPointer?, _ timeout: Double.ObjCType, _ name: id?,
                                        _ value: UnsafeMutablePointer<id?>?, _ nameServerAddress: UnsafeMutablePointer<id?>?) -> Int {
    value?.pointee = nil
    nameServerAddress?.pointee = nil
    return -1
}

/// No name server answers: kCFSocketError.
@c(_CFSocketRegisterSocketSignature)
public func CFSocketRegisterSocketSignature(_ nameServer: UnsafeRawPointer?, _ timeout: Double.ObjCType, _ name: id?,
                                            _ signature: UnsafeRawPointer?) -> Int { -1 }

/// No name server answers: kCFSocketError, the signature left as it was
/// and no address.
@c(_CFSocketCopyRegisteredSocketSignature)
public func CFSocketCopyRegisteredSocketSignature(_ nameServer: UnsafeRawPointer?, _ timeout: Double.ObjCType, _ name: id?,
                                                  _ signature: UnsafeMutableRawPointer?,
                                                  _ nameServerAddress: UnsafeMutablePointer<id?>?) -> Int {
    nameServerAddress?.pointee = nil
    return -1
}

/// No name server answers: kCFSocketError.
@c(_CFSocketUnregister)
public func CFSocketUnregister(_ nameServer: UnsafeRawPointer?, _ timeout: Double.ObjCType, _ name: id?) -> Int { -1 }

// MARK: - Streams

/// +1 streams connected, when one opens, to the signature's address: a
/// TCP connection, as CFNetwork's streams are.
@c(_CFStreamCreatePairWithPeerSocketSignature)
public func CFStreamCreatePairWithPeerSocketSignature(_ allocator: UnsafeRawPointer?, _ signature: UnsafeRawPointer?,
                                                      _ read: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
                                                      _ write: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) {
    let pair = SocketSignature(signature).flatMap { signature -> (input: id, output: id)? in
        guard let (host, port) = peerHost(signature.address) else { return nil }
        return StreamSocket.pair(StreamSocket(host: host, port: port))
    }
    if let read { read.pointee = pair?.input } else { ObjC.release(pair?.input) }
    if let write { write.pointee = pair?.output } else { ObjC.release(pair?.output) }
}

/// A Darwin sockaddr's numeric host and port.
private func peerHost(_ address: id?) -> (String, Int)? {
    guard let address, let pointer = CFDataGetBytePtr(address) else { return nil }
    let bytes = Array(UnsafeRawBufferPointer(start: pointer, count: CFDataGetLength(address)))
    guard bytes.count >= 16 else { return nil }
    let port = Int(bytes[2]) << 8 | Int(bytes[3])
    let capacity = 64
    var text = [CChar](repeating: 0, count: capacity)
    switch bytes[1] {
    case 2:
        return ("\(bytes[4]).\(bytes[5]).\(bytes[6]).\(bytes[7])", port)
    case 30 where bytes.count >= 28:
        let converted = Array(bytes[8 ..< 24]).withUnsafeBytes { inet_ntop(AF_INET6, $0.baseAddress, &text, socklen_t(capacity)) }
        guard converted != nil else { return nil }
        return (text.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }, port)
    default:
        return nil
    }
}

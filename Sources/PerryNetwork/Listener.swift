import Glibc
import PerryObjCInterop

// nw_listener_t: a bound socket that hands the program a connection for
// each peer: an accepted TCP socket, or for UDP each address datagrams
// come from, which share the listener's socket. The application protocols
// of its parameters (TLS, WebSocket, framers) run as servers on them.
// Bonjour advertising is kept but not done.

/// nw_listener_state_t.
enum ListenerStatus {
    static let invalid: Int32 = 0
    static let waiting: Int32 = 1
    static let ready: Int32 = 2
    static let failed: Int32 = 3
    static let cancelled: Int32 = 4
}

/// A listener's UDP socket, which its peers' connections send on.
final class UDPListenerSocket: @unchecked Sendable {
    let fd: Int32
    private let lock = Lock()
    private var peers: [SocketAddress: (connection: ConnectionState, transport: SocketTransport)] = [:]

    init(fd: Int32) { self.fd = fd }

    func peer(_ address: SocketAddress) -> (ConnectionState, SocketTransport)? {
        lock.withLock { peers[address].map { ($0.connection, $0.transport) } }
    }

    func add(_ address: SocketAddress, _ connection: ConnectionState, _ transport: SocketTransport) {
        lock.withLock { peers[address] = (connection, transport) }
    }

    func remove(_ address: SocketAddress?) {
        guard let address else { return }
        _ = lock.withLock { peers.removeValue(forKey: address) }
    }
}

final class ListenerState: NWState {
    var object: UnsafeMutableRawPointer?
    let parametersObject: UnsafeMutableRawPointer
    let parameters: ParametersState
    let requestedPort: UInt16
    let queue: UnsafeMutableRawPointer

    private let lock = Lock()
    private var userQueue: UnsafeMutableRawPointer?
    private var stateHandler: ObjCBlock?
    private var newConnectionHandler: ObjCBlock?
    private var newGroupHandler: ObjCBlock?
    private var advertisedHandler: ObjCBlock?
    var advertiseDescriptor: UnsafeMutableRawPointer?
    var connectionLimit = UInt32.max
    private var status = ListenerStatus.invalid
    private var started = false
    private var holdsItself = false
    private var fd: Int32 = -1
    private var udp: UDPListenerSocket?
    private(set) var port: UInt16 = 0

    init(parameters: UnsafeMutableRawPointer, port: UInt16) {
        let copy = nw_parameters_copy(parameters) ?? ObjCRuntime.retain(parameters)!
        parametersObject = copy
        self.parameters = Parameters.state(copy)!
        requestedPort = port
        queue = Dispatch.serialQueue("com.apple.network.listener")
    }

    deinit {
        ObjCRuntime.release(parametersObject)
        ObjCRuntime.release(queue)
        ObjCRuntime.release(userQueue)
        ObjCRuntime.release(advertiseDescriptor)
    }

    override func objectDeallocated() {
        object = nil
        Dispatch.on(queue) { self.closeSocket() }
    }

    func setQueue(_ queue: UnsafeMutableRawPointer?) {
        let held = ObjCRuntime.retain(queue)
        let old = lock.withLock { () -> UnsafeMutableRawPointer? in
            let old = userQueue
            userQueue = held
            return old
        }
        ObjCRuntime.release(old)
    }

    func setStateHandler(_ block: ObjCBlock?) { lock.withLock { stateHandler = block } }
    func setNewConnectionHandler(_ block: ObjCBlock?) { lock.withLock { newConnectionHandler = block } }
    func setNewGroupHandler(_ block: ObjCBlock?) { lock.withLock { newGroupHandler = block } }
    func setAdvertisedHandler(_ block: ObjCBlock?) { lock.withLock { advertisedHandler = block } }
    var currentStatus: Int32 { lock.withLock { status } }

    private func onUserQueue(_ body: @escaping () -> Void) {
        let queue = lock.withLock { userQueue }
        Dispatch.on(queue, body)
    }

    private func setStatus(_ new: Int32, _ error: NetworkError?) {
        let handler = lock.withLock { () -> ObjCBlock? in
            status = new
            return stateHandler
        }
        guard let handler else { return }
        onUserQueue {
            let object = error?.object()
            handler.call(state: new, object)
            ObjCRuntime.release(object)
        }
    }

    func start() {
        let first = lock.withLock { () -> Bool in
            guard !started, status != ListenerStatus.cancelled else { return false }
            started = true
            return true
        }
        guard first, let object else { return }
        _ = ObjCRuntime.retain(object)
        lock.withLock { holdsItself = true }
        Dispatch.on(queue) { self.open() }
    }

    private func open() {
        let stack = parameters.stackState
        if stack.transportKind == .quic || stack.applicationBottomUp.contains(where: { $0.kind == .quic }) {
            networkWarning("QUIC listeners aren't supported")
            setStatus(ListenerStatus.failed, .protocolNotSupported)
            return
        }
        let isStream = stack.transportKind != .udp
        var local = Endpoints.state(parameters.localEndpoint)?.address
        if local != nil, requestedPort != 0 { local!.port = requestedPort }
        let version = stack.ipOptions?.ipVersion ?? 0
        var candidates: [SocketAddress] = []
        if let local {
            candidates = [local]
        } else {
            if version != 4 { candidates.append(.any(family: AF_INET6, port: requestedPort)) }
            if version != 6 { candidates.append(.any(family: AF_INET, port: requestedPort)) }
        }
        var lastError = NetworkError.posix(darwin: 49)
        for address in candidates {
            let socket = Sockets.make(family: address.family, type: isStream ? Int32(SOCK_STREAM.rawValue) : Int32(SOCK_DGRAM.rawValue))
            guard socket >= 0 else {
                lastError = .posix(linux: errno)
                continue
            }
            if isStream || parameters.reuseLocalAddress { Sockets.setOption(socket, SOL_SOCKET, SO_REUSEADDR, 1) }
            if parameters.reuseLocalAddress { Sockets.setOption(socket, SOL_SOCKET, SO_REUSEPORT, 1) }
            if address.family == AF_INET6 { Sockets.setOption(socket, Int32(IPPROTO_IPV6), IPV6_V6ONLY, version == 6 ? 1 : 0) }
            if address.withPointer({ bind(socket, $0, $1) }) != 0 || (isStream && listen(socket, 128) != 0) {
                lastError = .posix(linux: errno)
                close(socket)
                continue
            }
            if isStream { Sockets.apply(tcp: stack.transportOptions, ip: stack.ipOptions, to: socket) }
            else { Sockets.apply(ip: stack.ipOptions, to: socket) }
            fd = socket
            port = SocketAddress.local(socket)?.port ?? requestedPort
            if !isStream { udp = UDPListenerSocket(fd: socket) }
            EventLoop.shared.register(socket, queue: queue, events: EventLoop.readable) { [weak self] events in
                self?.readable(isStream: isStream)
            }
            setStatus(ListenerStatus.ready, nil)
            return
        }
        setStatus(ListenerStatus.failed, lastError)
    }

    private func readable(isStream: Bool) {
        guard fd >= 0 else { return }
        if isStream { acceptAll() } else { receiveAll() }
        if fd >= 0 { EventLoop.shared.arm(fd, events: EventLoop.readable) }
    }

    /// Takes one more connection, if the limit allows.
    private func admit() -> Bool {
        lock.withLock {
            if connectionLimit == 0 { return false }
            if connectionLimit != UInt32.max { connectionLimit -= 1 }
            return newConnectionHandler != nil
        }
    }

    private func acceptAll() {
        while fd >= 0 {
            var storage = sockaddr_storage()
            var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let client = withUnsafeMutablePointer(to: &storage) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { accept(fd, $0, &length) }
            }
            guard client >= 0 else { return }
            Sockets.nonBlocking(client)
            _ = fcntl(client, F_SETFD, FD_CLOEXEC)
            guard admit(), let address = SocketAddress(storage: storage, length: length) else {
                close(client)
                continue
            }
            hand(transport: SocketTransport(accepted: client), from: address)
        }
    }

    private func receiveAll() {
        guard let udp else { return }
        var buffer = [UInt8](repeating: 0, count: 65536)
        while fd >= 0 {
            var storage = sockaddr_storage()
            var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let count = buffer.withUnsafeMutableBytes { bytes in
                withUnsafeMutablePointer(to: &storage) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, bytes.baseAddress, bytes.count, 0, $0, &length) }
                }
            }
            guard count >= 0, let address = SocketAddress(storage: storage, length: length) else { return }
            let data = Array(buffer[0..<count])
            if let (connection, transport) = udp.peer(address) {
                Dispatch.on(connection.queue) { transport.inject(data) }
                continue
            }
            guard admit() else { continue }
            let transport = SocketTransport(listener: udp, peer: address)
            let connection = hand(transport: transport, from: address)
            udp.add(address, connection, transport)
            Dispatch.on(connection.queue) { transport.inject(data) }
        }
    }

    /// Makes the connection and hands it to the program.
    @discardableResult
    private func hand(transport: SocketTransport, from address: SocketAddress) -> ConnectionState {
        let endpoint = Endpoints.make(address: address)
        let state = ConnectionState(endpoint: endpoint, parameters: parametersObject, inbound: transport)
        ObjCRuntime.release(endpoint)
        let connection = Connections.make(state)
        let handler = lock.withLock { newConnectionHandler }
        onUserQueue {
            handler?.call(connection)
            ObjCRuntime.release(connection)
        }
        return state
    }

    func cancel() {
        Dispatch.on(queue) {
            guard self.currentStatus != ListenerStatus.cancelled else { return }
            self.closeSocket()
            self.setStatus(ListenerStatus.cancelled, nil)
            let release = self.lock.withLock { () -> Bool in
                let held = self.holdsItself
                self.holdsItself = false
                return held
            }
            if release, let object = self.object { self.onUserQueue { ObjCRuntime.release(object) } }
        }
    }

    private func closeSocket() {
        guard fd >= 0 else { return }
        EventLoop.shared.remove(fd)
        close(fd)
        fd = -1
    }
}

@ObjCClass("OS_nw_listener")
open class NWListenerObject: NWObject {}

private func listener(_ object: UnsafeMutableRawPointer?) -> ListenerState? { NWObjects.state(object, ListenerState.self) }

private func makeListener(_ parameters: UnsafeMutableRawPointer?, port: UInt16) -> UnsafeMutableRawPointer? {
    guard let parameters, Parameters.state(parameters) != nil else { return nil }
    let state = ListenerState(parameters: parameters, port: port)
    let object = NWObjects.make(NWListenerObject.objCClass, state)
    state.object = object
    return object
}

@c(_nw_listener_create)
public func nw_listener_create(_ parameters: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    makeListener(parameters, port: 0)
}

/// "0" or a number; NULL for a port that isn't one.
@c(_nw_listener_create_with_port)
public func nw_listener_create_with_port(_ port: UnsafePointer<CChar>?, _ parameters: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let port else { return nil }
    let text = String(cString: port)
    let number = portNumber(text)
    guard number != 0 || text == "0" else { return nil }
    return makeListener(parameters, port: number)
}

/// launchd hands no sockets over here.
@c(_nw_listener_create_with_launchd_key)
public func nw_listener_create_with_launchd_key(_ parameters: UnsafeMutableRawPointer?, _ key: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    nil
}

/// The listener for a connection's own parameters, as nw_listener_create_with_connection does.
@c(_nw_listener_create_with_connection)
public func nw_listener_create_with_connection(_ connection: UnsafeMutableRawPointer?, _ parameters: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    makeListener(parameters, port: 0)
}

@c(_nw_listener_set_queue)
public func nw_listener_set_queue(_ object: UnsafeMutableRawPointer?, _ queue: UnsafeMutableRawPointer?) { listener(object)?.setQueue(queue) }

@c(_nw_listener_set_state_changed_handler)
public func nw_listener_set_state_changed_handler(_ object: UnsafeMutableRawPointer?, _ handler: UnsafeMutableRawPointer?) {
    listener(object)?.setStateHandler(ObjCBlock.from(handler))
}

@c(_nw_listener_set_new_connection_handler)
public func nw_listener_set_new_connection_handler(_ object: UnsafeMutableRawPointer?, _ handler: UnsafeMutableRawPointer?) {
    listener(object)?.setNewConnectionHandler(ObjCBlock.from(handler))
}

/// QUIC's groups: none arrive.
@c(_nw_listener_set_new_connection_group_handler)
public func nw_listener_set_new_connection_group_handler(_ object: UnsafeMutableRawPointer?, _ handler: UnsafeMutableRawPointer?) {
    listener(object)?.setNewGroupHandler(ObjCBlock.from(handler))
}

@c(_nw_listener_set_advertised_endpoint_changed_handler)
public func nw_listener_set_advertised_endpoint_changed_handler(_ object: UnsafeMutableRawPointer?, _ handler: UnsafeMutableRawPointer?) {
    listener(object)?.setAdvertisedHandler(ObjCBlock.from(handler))
}

@c(_nw_listener_set_advertise_descriptor)
public func nw_listener_set_advertise_descriptor(_ object: UnsafeMutableRawPointer?, _ descriptor: UnsafeMutableRawPointer?) {
    guard let state = listener(object) else { return }
    let held = ObjCRuntime.retain(descriptor)
    ObjCRuntime.release(state.advertiseDescriptor)
    state.advertiseDescriptor = held
}

@c(_nw_listener_get_port)
public func nw_listener_get_port(_ object: UnsafeMutableRawPointer?) -> UInt16 { listener(object)?.port ?? 0 }

@c(_nw_listener_get_new_connection_limit)
public func nw_listener_get_new_connection_limit(_ object: UnsafeMutableRawPointer?) -> UInt32 { listener(object)?.connectionLimit ?? 0 }

@c(_nw_listener_set_new_connection_limit)
public func nw_listener_set_new_connection_limit(_ object: UnsafeMutableRawPointer?, _ limit: UInt32) { listener(object)?.connectionLimit = limit }

@c(_nw_listener_start)
public func nw_listener_start(_ object: UnsafeMutableRawPointer?) { listener(object)?.start() }

@c(_nw_listener_cancel)
public func nw_listener_cancel(_ object: UnsafeMutableRawPointer?) { listener(object)?.cancel() }

// MARK: - Advertise descriptors

final class AdvertiseDescriptorState: NWState {
    let name: String?
    let type: String?
    let domain: String?
    var noAutoRename = false
    var txtRecord: UnsafeMutableRawPointer?

    init(name: String?, type: String?, domain: String?) {
        self.name = name
        self.type = type
        self.domain = domain
    }

    deinit { ObjCRuntime.release(txtRecord) }
}

@ObjCClass("OS_nw_advertise_descriptor")
open class NWAdvertiseDescriptorObject: NWObject {}

private func advertise(_ descriptor: UnsafeMutableRawPointer?) -> AdvertiseDescriptorState? {
    NWObjects.state(descriptor, AdvertiseDescriptorState.self)
}

@c(_nw_advertise_descriptor_create_bonjour_service)
public func nw_advertise_descriptor_create_bonjour_service(_ name: UnsafePointer<CChar>?, _ type: UnsafePointer<CChar>?,
                                                           _ domain: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    guard let type else { return nil }
    return NWObjects.make(NWAdvertiseDescriptorObject.objCClass,
                          AdvertiseDescriptorState(name: name.map { String(cString: $0) }, type: String(cString: type),
                                                   domain: domain.map { String(cString: $0) }))
}

@c(_nw_advertise_descriptor_create_application_service)
public func nw_advertise_descriptor_create_application_service(_ name: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    guard let name else { return nil }
    return NWObjects.make(NWAdvertiseDescriptorObject.objCClass, AdvertiseDescriptorState(name: String(cString: name), type: nil, domain: nil))
}

@c(_nw_advertise_descriptor_set_no_auto_rename)
public func nw_advertise_descriptor_set_no_auto_rename(_ descriptor: UnsafeMutableRawPointer?, _ value: Bool) {
    advertise(descriptor)?.noAutoRename = value
}

@c(_nw_advertise_descriptor_get_no_auto_rename)
public func nw_advertise_descriptor_get_no_auto_rename(_ descriptor: UnsafeMutableRawPointer?) -> Bool {
    advertise(descriptor)?.noAutoRename ?? false
}

@c(_nw_advertise_descriptor_set_txt_record)
public func nw_advertise_descriptor_set_txt_record(_ descriptor: UnsafeMutableRawPointer?, _ bytes: UnsafeRawPointer?, _ length: Int) {
    guard let state = advertise(descriptor) else { return }
    let record = bytes.flatMap { nw_txt_record_create_with_bytes($0.assumingMemoryBound(to: UInt8.self), length) }
    ObjCRuntime.release(state.txtRecord)
    state.txtRecord = record
}

@c(_nw_advertise_descriptor_set_txt_record_object)
public func nw_advertise_descriptor_set_txt_record_object(_ descriptor: UnsafeMutableRawPointer?, _ record: UnsafeMutableRawPointer?) {
    guard let state = advertise(descriptor) else { return }
    let held = ObjCRuntime.retain(record)
    ObjCRuntime.release(state.txtRecord)
    state.txtRecord = held
}

@c(_nw_advertise_descriptor_copy_txt_record_object)
public func nw_advertise_descriptor_copy_txt_record_object(_ descriptor: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    ObjCRuntime.retain(advertise(descriptor)?.txtRecord)
}

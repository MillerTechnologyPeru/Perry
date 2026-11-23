import Glibc
import PerryObjCInterop

// nw_connection_group_t: a UDP socket that joins the multicast groups of
// its descriptor, hands the program each datagram with a context that
// remembers who sent it (for replies and the per-message lookups), and
// sends to the group or to one member. Multiplex groups are QUIC's, which
// isn't carried here: they fail with EPROTONOSUPPORT.

/// nw_connection_group_state_t.
enum GroupStatus {
    static let invalid: Int32 = 0
    static let waiting: Int32 = 1
    static let ready: Int32 = 2
    static let failed: Int32 = 3
    static let cancelled: Int32 = 4
}

final class GroupState: NWState {
    var object: UnsafeMutableRawPointer?
    let descriptor: UnsafeMutableRawPointer
    let parametersObject: UnsafeMutableRawPointer
    let queue: UnsafeMutableRawPointer

    private let lock = Lock()
    private var userQueue: UnsafeMutableRawPointer?
    private var stateHandler: ObjCBlock?
    private var receiveHandler: ObjCBlock?
    private var newConnectionHandler: ObjCBlock?
    private var maximumMessageSize = 65535
    private var rejectOversized = false
    private var status = GroupStatus.invalid
    private var started = false
    private var holdsItself = false
    private var fd: Int32 = -1

    init(descriptor: UnsafeMutableRawPointer, parameters: UnsafeMutableRawPointer) {
        self.descriptor = ObjCRuntime.retain(descriptor)!
        parametersObject = nw_parameters_copy(parameters) ?? ObjCRuntime.retain(parameters)!
        queue = Dispatch.serialQueue("com.apple.network.connection-group")
    }

    deinit {
        ObjCRuntime.release(descriptor)
        ObjCRuntime.release(parametersObject)
        ObjCRuntime.release(queue)
        ObjCRuntime.release(userQueue)
    }

    override func objectDeallocated() {
        object = nil
        Dispatch.on(queue) { self.closeSocket() }
    }

    var descriptorState: GroupDescriptorState? { NWObjects.state(descriptor, GroupDescriptorState.self) }

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

    func setReceiveHandler(_ block: ObjCBlock?, maximum: Int, rejectOversized: Bool) {
        lock.withLock {
            receiveHandler = block
            maximumMessageSize = maximum
            self.rejectOversized = rejectOversized
        }
    }

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
            guard !started, status != GroupStatus.cancelled else { return false }
            started = true
            return true
        }
        guard first, let object else { return }
        _ = ObjCRuntime.retain(object)
        lock.withLock { holdsItself = true }
        Dispatch.on(queue) { self.open() }
    }

    private func open() {
        guard let descriptor = descriptorState, descriptor.isMulticast else {
            networkWarning("multiplex connection groups (QUIC) aren't supported")
            setStatus(GroupStatus.failed, .protocolNotSupported)
            return
        }
        let groups = descriptor.endpoints.compactMap { Endpoints.state($0)?.address }
        guard let first = groups.first else {
            setStatus(GroupStatus.failed, .posix(darwin: 22))
            return
        }
        let socket = Sockets.make(family: first.family, type: Int32(SOCK_DGRAM.rawValue))
        guard socket >= 0 else {
            setStatus(GroupStatus.failed, .posix(linux: errno))
            return
        }
        Sockets.setOption(socket, SOL_SOCKET, SO_REUSEADDR, 1)
        Sockets.setOption(socket, SOL_SOCKET, SO_REUSEPORT, 1)
        var bound = descriptor.disableUnicastTraffic ? first : SocketAddress.any(family: first.family, port: first.port)
        if let local = Endpoints.state(Parameters.state(parametersObject)?.localEndpoint)?.address, local.port != 0 { bound.port = local.port }
        guard bound.withPointer({ bind(socket, $0, $1) }) == 0 else {
            let error = NetworkError.posix(linux: errno)
            close(socket)
            setStatus(GroupStatus.failed, error)
            return
        }
        let source = Endpoints.state(descriptor.specificSource)?.address
        for group in groups where !join(socket, group, source: source) {
            let error = NetworkError.posix(linux: errno)
            close(socket)
            setStatus(GroupStatus.failed, error)
            return
        }
        Sockets.apply(ip: Parameters.state(parametersObject)?.stackState.ipOptions, to: socket)
        fd = socket
        EventLoop.shared.register(socket, queue: queue, events: EventLoop.readable) { [weak self] _ in self?.readable() }
        setStatus(GroupStatus.ready, nil)
    }

    private func join(_ socket: Int32, _ group: SocketAddress, source: SocketAddress?) -> Bool {
        if group.family == AF_INET {
            let groupAddress = group.bytes.withUnsafeBytes { $0.load(fromByteOffset: 4, as: in_addr.self) }
            if let source, source.family == AF_INET {
                var request = ip_mreq_source()
                request.imr_multiaddr = groupAddress
                request.imr_sourceaddr = source.bytes.withUnsafeBytes { $0.load(fromByteOffset: 4, as: in_addr.self) }
                return setsockopt(socket, Int32(IPPROTO_IP), IP_ADD_SOURCE_MEMBERSHIP, &request, socklen_t(MemoryLayout<ip_mreq_source>.size)) == 0
            }
            var request = ip_mreqn()
            request.imr_multiaddr = groupAddress
            return setsockopt(socket, Int32(IPPROTO_IP), IP_ADD_MEMBERSHIP, &request, socklen_t(MemoryLayout<ip_mreqn>.size)) == 0
        }
        var request = ipv6_mreq()
        request.ipv6mr_multiaddr = group.bytes.withUnsafeBytes { $0.load(fromByteOffset: 8, as: in6_addr.self) }
        return setsockopt(socket, Int32(IPPROTO_IPV6), IPV6_JOIN_GROUP, &request, socklen_t(MemoryLayout<ipv6_mreq>.size)) == 0
    }

    private func readable() {
        guard fd >= 0 else { return }
        var buffer = [UInt8](repeating: 0, count: 65536)
        let local = SocketAddress.local(fd)
        while fd >= 0 {
            var storage = sockaddr_storage()
            var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let count = buffer.withUnsafeMutableBytes { bytes in
                withUnsafeMutablePointer(to: &storage) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, bytes.baseAddress, bytes.count, 0, $0, &length) }
                }
            }
            guard count >= 0 else { break }
            let (handler, maximum, reject) = lock.withLock { (receiveHandler, maximumMessageSize, rejectOversized) }
            guard let handler else { continue }
            if count > maximum, reject { continue }
            let data = Array(buffer[0..<min(count, maximum)])
            let state = ContextState(identifier: "group")
            state.remoteAddress = SocketAddress(storage: storage, length: length)
            state.localAddress = local
            state.group = self
            let context = Contexts.make(state)
            let content = data.isEmpty ? nil : Dispatch.data(data)
            let complete = count <= maximum
            onUserQueue {
                typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Bool) -> Void
                handler.function(as: Invoke.self)(handler.object, content, context, complete)
                ObjCRuntime.release(content)
                ObjCRuntime.release(context)
            }
        }
        if fd >= 0 { EventLoop.shared.arm(fd, events: EventLoop.readable) }
    }

    func send(_ data: [UInt8], to destination: SocketAddress?, completion: ObjCBlock?) {
        Dispatch.on(queue) {
            var error: NetworkError?
            let target = destination ?? self.descriptorState?.endpoints.lazy.compactMap { Endpoints.state($0)?.address }.first
            if self.fd < 0 {
                error = .posix(darwin: 57)
            } else if let target {
                let sent = data.withUnsafeBytes { bytes in target.withPointer { sendto(self.fd, bytes.baseAddress, bytes.count, 0, $0, $1) } }
                if sent < 0 { error = .posix(linux: errno) }
            } else {
                error = .posix(darwin: 39)
            }
            guard let completion else { return }
            self.onUserQueue {
                let object = error?.object()
                completion.call(object)
                ObjCRuntime.release(object)
            }
        }
    }

    func cancel() {
        Dispatch.on(queue) {
            guard self.lock.withLock({ self.status }) != GroupStatus.cancelled else { return }
            self.closeSocket()
            self.setStatus(GroupStatus.cancelled, nil)
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

@ObjCClass("OS_nw_connection_group")
open class NWConnectionGroupObject: NWObject {}

private func group(_ object: UnsafeMutableRawPointer?) -> GroupState? { NWObjects.state(object, GroupState.self) }

@c(_nw_connection_group_create)
public func nw_connection_group_create(_ descriptor: UnsafeMutableRawPointer?, _ parameters: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let descriptor, let parameters, NWObjects.state(descriptor, GroupDescriptorState.self) != nil else { return nil }
    let state = GroupState(descriptor: descriptor, parameters: parameters)
    let object = NWObjects.make(NWConnectionGroupObject.objCClass, state)
    state.object = object
    return object
}

@c(_nw_connection_group_copy_descriptor)
public func nw_connection_group_copy_descriptor(_ object: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    ObjCRuntime.retain(group(object)?.descriptor)
}

@c(_nw_connection_group_copy_parameters)
public func nw_connection_group_copy_parameters(_ object: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    ObjCRuntime.retain(group(object)?.parametersObject)
}

@c(_nw_connection_group_set_queue)
public func nw_connection_group_set_queue(_ object: UnsafeMutableRawPointer?, _ queue: UnsafeMutableRawPointer?) { group(object)?.setQueue(queue) }

@c(_nw_connection_group_set_state_changed_handler)
public func nw_connection_group_set_state_changed_handler(_ object: UnsafeMutableRawPointer?, _ handler: UnsafeMutableRawPointer?) {
    group(object)?.setStateHandler(ObjCBlock.from(handler))
}

@c(_nw_connection_group_set_receive_handler)
public func nw_connection_group_set_receive_handler(_ object: UnsafeMutableRawPointer?, _ maximum: UInt32, _ rejectOversized: Bool,
                                                    _ handler: UnsafeMutableRawPointer?) {
    group(object)?.setReceiveHandler(ObjCBlock.from(handler), maximum: maximum == 0 ? 65535 : Int(maximum), rejectOversized: rejectOversized)
}

/// Multicast groups get no new connections.
@c(_nw_connection_group_set_new_connection_handler)
public func nw_connection_group_set_new_connection_handler(_ object: UnsafeMutableRawPointer?, _ handler: UnsafeMutableRawPointer?) {
    group(object)?.setNewConnectionHandler(ObjCBlock.from(handler))
}

@c(_nw_connection_group_start)
public func nw_connection_group_start(_ object: UnsafeMutableRawPointer?) { group(object)?.start() }

@c(_nw_connection_group_cancel)
public func nw_connection_group_cancel(_ object: UnsafeMutableRawPointer?) { group(object)?.cancel() }

/// To `endpoint`, or to the group when it is NULL.
@c(_nw_connection_group_send_message)
public func nw_connection_group_send_message(_ object: UnsafeMutableRawPointer?, _ content: UnsafeMutableRawPointer?,
                                             _ endpoint: UnsafeMutableRawPointer?, _ context: UnsafeMutableRawPointer?,
                                             _ completion: UnsafeMutableRawPointer?) {
    guard let state = group(object) else { return }
    state.send(Dispatch.bytes(content), to: Endpoints.state(endpoint)?.address, completion: ObjCBlock.from(completion))
}

/// To whoever sent the inbound message.
@c(_nw_connection_group_reply)
public func nw_connection_group_reply(_ object: UnsafeMutableRawPointer?, _ inbound: UnsafeMutableRawPointer?, _ outbound: UnsafeMutableRawPointer?,
                                      _ content: UnsafeMutableRawPointer?) {
    guard let state = group(object), let remote = Contexts.state(inbound)?.remoteAddress else { return }
    state.send(Dispatch.bytes(content), to: remote, completion: nil)
}

@c(_nw_connection_group_copy_remote_endpoint_for_message)
public func nw_connection_group_copy_remote_endpoint_for_message(_ object: UnsafeMutableRawPointer?,
                                                                 _ context: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    Contexts.state(context)?.remoteAddress.map { Endpoints.make(address: $0) }
}

@c(_nw_connection_group_copy_local_endpoint_for_message)
public func nw_connection_group_copy_local_endpoint_for_message(_ object: UnsafeMutableRawPointer?,
                                                                _ context: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    Contexts.state(context)?.localAddress.map { Endpoints.make(address: $0) }
}

@c(_nw_connection_group_copy_path_for_message)
public func nw_connection_group_copy_path_for_message(_ object: UnsafeMutableRawPointer?, _ context: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let state = Contexts.state(context) else { return nil }
    let interfaces = Interfaces.with(address: state.localAddress).map { [$0] } ?? PathInfo.current(required: 0, prohibited: []).interfaces
    return PathInfo(status: PathStatus.satisfied, interfaces: interfaces, local: state.localAddress, remote: state.remoteAddress).object()
}

@c(_nw_connection_group_copy_protocol_metadata)
public func nw_connection_group_copy_protocol_metadata(_ object: UnsafeMutableRawPointer?, _ definition: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let kind = Definitions.kind(definition), kind == .udp || kind == .ip else { return nil }
    return Metadata.make(kind).0
}

@c(_nw_connection_group_copy_protocol_metadata_for_message)
public func nw_connection_group_copy_protocol_metadata_for_message(_ object: UnsafeMutableRawPointer?, _ context: UnsafeMutableRawPointer?,
                                                                   _ definition: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    if let metadata = Contexts.state(context)?.metadata(for: definition) { return ObjCRuntime.retain(metadata) }
    return nw_connection_group_copy_protocol_metadata(object, definition)
}

/// A connection of its own to one member (+1), not yet started.
@c(_nw_connection_group_extract_connection)
public func nw_connection_group_extract_connection(_ object: UnsafeMutableRawPointer?, _ endpoint: UnsafeMutableRawPointer?,
                                                   _ options: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let state = group(object), let endpoint else { return nil }
    return nw_connection_create(endpoint, state.parametersObject)
}

@c(_nw_connection_group_extract_connection_for_message)
public func nw_connection_group_extract_connection_for_message(_ object: UnsafeMutableRawPointer?,
                                                               _ context: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let state = group(object), let remote = Contexts.state(context)?.remoteAddress else { return nil }
    let endpoint = Endpoints.make(address: remote)
    defer { ObjCRuntime.release(endpoint) }
    return nw_connection_create(endpoint, state.parametersObject)
}

/// Extracted connections are connections of their own from then on.
@c(_nw_connection_group_reinsert_extracted_connection)
public func nw_connection_group_reinsert_extracted_connection(_ object: UnsafeMutableRawPointer?, _ connection: UnsafeMutableRawPointer?) -> Bool {
    false
}

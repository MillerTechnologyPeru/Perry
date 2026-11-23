import Glibc
import PerryObjCInterop

// A connection's protocol stack: a socket transport (TCP or UDP) at the
// bottom and the application protocols above it (TLS, WebSocket, framers),
// each a Layer. Layers run on their connection's queue. Bytes go down
// through send(), and come up through lowerReceived(): a stream's bytes
// with no context, a message's with its context and is_complete, and a
// stream's end as an empty, complete delivery with the final context.

typealias SendCompletion = (NetworkError?) -> Void

class Layer {
    /// The connection, which keeps its layers.
    unowned(unsafe) var connection: ConnectionState!
    weak var upper: Layer?
    var lower: Layer?

    /// Whether what this layer hands up is messages rather than a stream.
    var deliversMessages: Bool { lower?.deliversMessages ?? false }

    var kind: ProtocolKind { .tcp }

    // Down

    func start() {}

    func send(_ data: [UInt8], context: UnsafeMutableRawPointer?, isComplete: Bool, completion: SendCompletion?) {
        lower?.send(data, context: context, isComplete: isComplete, completion: completion)
    }

    /// No more is sent once what is queued has gone.
    func finish() { lower?.finish() }

    /// The connection is going away: let go of everything.
    func stop() {}

    // Up

    func lowerReady() { readyUp() }

    func lowerReceived(_ data: [UInt8], context: UnsafeMutableRawPointer?, isComplete: Bool) {
        deliverUp(data, context: context, isComplete: isComplete)
    }

    func lowerFailed(_ error: NetworkError) { failUp(error) }

    func readyUp() {
        if let upper { upper.lowerReady() } else { connection.stackReady() }
    }

    func deliverUp(_ data: [UInt8], context: UnsafeMutableRawPointer?, isComplete: Bool) {
        if let upper { upper.lowerReceived(data, context: context, isComplete: isComplete) }
        else { connection.received(data, context: context, isComplete: isComplete) }
    }

    func failUp(_ error: NetworkError) {
        if let upper { upper.lowerFailed(error) } else { connection.stackFailed(error) }
    }

    /// The end of a stream, sent up.
    func endUp() { deliverUp([], context: Contexts.finalSend, isComplete: true) }

    /// This layer's metadata (+1) for nw_connection_copy_protocol_metadata.
    func copyMetadata() -> UnsafeMutableRawPointer? { nil }
}

/// The bottom of the stack: a TCP or UDP socket, connected by the transport
/// itself, accepted by a listener, or (for UDP) shared with a listener that
/// hands it its peer's datagrams.
final class SocketTransport: Layer {
    let isStream: Bool
    private(set) var fd: Int32 = -1
    private var addresses: [SocketAddress] = []
    private var attempt = 0
    private var connecting = false
    private(set) var connected = false
    private var reading = true
    private var stopped = false
    private var writes: [(bytes: [UInt8], offset: Int, completion: SendCompletion?)] = []
    private var datagram: [UInt8] = []
    private var finishRequested = false
    private var timeoutGeneration = 0
    /// A listener's UDP socket and the peer it delivers for.
    private let shared: UDPListenerSocket?
    let peer: SocketAddress?

    private(set) var localAddress: SocketAddress?
    private(set) var remoteAddress: SocketAddress?
    var bytesSent: UInt64 = 0
    var bytesReceived: UInt64 = 0
    var packetsSent: UInt64 = 0
    var packetsReceived: UInt64 = 0
    var attempts = 0

    override var kind: ProtocolKind { isStream ? .tcp : .udp }
    override var deliversMessages: Bool { !isStream }

    init(isStream: Bool) {
        self.isStream = isStream
        shared = nil
        peer = nil
    }

    /// A socket a listener accepted.
    init(accepted fd: Int32) {
        isStream = true
        shared = nil
        peer = nil
        self.fd = fd
        connected = true
        localAddress = SocketAddress.local(fd)
        remoteAddress = SocketAddress.remote(fd)
    }

    /// A peer of a listener's UDP socket.
    init(listener: UDPListenerSocket, peer: SocketAddress) {
        isStream = false
        shared = listener
        self.peer = peer
        connected = true
        localAddress = SocketAddress.local(listener.fd)
        remoteAddress = peer
    }

    override func start() {
        if shared != nil {
            readyUp()
            return
        }
        if connected {
            watch()
            readyUp()
            return
        }
        connection.resolveRemote { [weak self] addresses, error in
            guard let self, !self.stopped else { return }
            guard !addresses.isEmpty else {
                self.connection.couldNotConnect(error ?? .noSuchRecord)
                return
            }
            self.addresses = addresses
            self.attempt = 0
            self.tryNext(lastError: nil)
        }
    }

    private var tcpOptions: OptionsState? { connection.parameters.stackState.transportOptions }
    private var ipOptions: OptionsState? { connection.parameters.stackState.ipOptions }

    private func tryNext(lastError: NetworkError?) {
        closeSocket()
        guard attempt < addresses.count else {
            connection.couldNotConnect(lastError ?? .posix(darwin: 61))
            return
        }
        let address = addresses[attempt]
        attempt += 1
        attempts += 1
        let ipVersion = ipOptions?.ipVersion ?? 0
        if (ipVersion == 4 && address.family != AF_INET) || (ipVersion == 6 && address.family != AF_INET6) {
            tryNext(lastError: lastError)
            return
        }
        let type = isStream ? Int32(SOCK_STREAM.rawValue) : Int32(SOCK_DGRAM.rawValue)
        let socket = Sockets.make(family: address.family, type: type)
        guard socket >= 0 else {
            tryNext(lastError: .posix(linux: errno))
            return
        }
        fd = socket
        let parameters = connection.parameters
        if parameters.reuseLocalAddress {
            Sockets.setOption(socket, SOL_SOCKET, SO_REUSEADDR, 1)
            Sockets.setOption(socket, SOL_SOCKET, SO_REUSEPORT, 1)
        }
        if let local = Endpoints.state(parameters.localEndpoint)?.address {
            var bound = local
            if bound.family != address.family { bound = .any(family: address.family, port: local.port) }
            if bound.withPointer({ bind(socket, $0, $1) }) != 0 {
                tryNext(lastError: .posix(linux: errno))
                return
            }
        }
        if let interface = Interfaces.state(parameters.requiredInterface) {
            _ = interface.nameText.withCString { setsockopt(socket, SOL_SOCKET, SO_BINDTODEVICE, $0, socklen_t(strlen($0) + 1)) }
        }
        if isStream {
            Sockets.apply(tcp: tcpOptions, ip: ipOptions, to: socket)
            if parameters.fastOpenEnabled || tcpOptions?.enableFastOpen == true {
                Sockets.setOption(socket, Int32(IPPROTO_TCP), 30 /* TCP_FASTOPEN_CONNECT */, 1)
            }
        } else {
            Sockets.apply(ip: ipOptions, to: socket)
        }
        let status = address.withPointer { Glibc.connect(socket, $0, $1) }
        if status == 0 {
            didConnect()
            return
        }
        let code = errno
        guard code == EINPROGRESS else {
            tryNext(lastError: .posix(linux: code))
            return
        }
        connecting = true
        EventLoop.shared.register(socket, queue: connection.queue, events: EventLoop.writable) { [weak self] events in
            self?.handle(events)
        }
        if let timeout = tcpOptions?.connectionTimeout, timeout > 0 {
            timeoutGeneration += 1
            let generation = timeoutGeneration
            Dispatch.after(Double(timeout), on: connection.queue) { [weak self] in
                guard let self, self.connecting, self.timeoutGeneration == generation else { return }
                self.tryNext(lastError: .posix(darwin: 60))
            }
        }
    }

    private func didConnect() {
        connecting = false
        connected = true
        localAddress = SocketAddress.local(fd)
        remoteAddress = SocketAddress.remote(fd)
        watch()
        readyUp()
    }

    /// Registers the socket for reading (it may already be registered for
    /// its connect).
    private func watch() {
        guard shared == nil, fd >= 0 else { return }
        EventLoop.shared.remove(fd)
        EventLoop.shared.register(fd, queue: connection.queue, events: interest) { [weak self] events in
            self?.handle(events)
        }
    }

    private var interest: UInt32 {
        var events: UInt32 = 0
        if reading { events |= EventLoop.readable }
        if !writes.isEmpty { events |= EventLoop.writable }
        return events
    }

    private func handle(_ events: UInt32) {
        guard fd >= 0, !stopped else { return }
        if connecting {
            let error = Sockets.socketError(fd)
            if error == 0 { didConnect() } else { tryNext(lastError: .posix(linux: error)) }
            return
        }
        if events & (EventLoop.readable | EventLoop.failed) != 0, reading { readAvailable() }
        guard fd >= 0, !stopped else { return }
        if events & EventLoop.writable != 0 || (events & EventLoop.failed != 0 && !writes.isEmpty) { flush() }
        guard fd >= 0, !stopped else { return }
        let events = interest
        if events != 0 { EventLoop.shared.arm(fd, events: events) }
    }

    private func readAvailable() {
        var buffer = [UInt8](repeating: 0, count: 65536)
        while fd >= 0, !stopped, reading {
            let count = buffer.withUnsafeMutableBytes { recv(fd, $0.baseAddress, $0.count, 0) }
            if count > 0 {
                bytesReceived += UInt64(count)
                packetsReceived += 1
                let data = Array(buffer[0..<count])
                if isStream {
                    deliverUp(data, context: nil, isComplete: false)
                } else {
                    deliverDatagram(data)
                }
                continue
            }
            if count == 0 {
                if !isStream {
                    // An empty datagram.
                    packetsReceived += 1
                    deliverDatagram([])
                    continue
                }
                reading = false
                endUp()
                return
            }
            let code = errno
            if code == EAGAIN || code == EWOULDBLOCK || code == EINTR { return }
            // A UDP peer's ICMP errors don't end the connection.
            if !isStream, code == ECONNREFUSED { continue }
            reading = false
            failUp(.posix(linux: code))
            return
        }
    }

    private func deliverDatagram(_ data: [UInt8]) {
        let context = Contexts.message("udp")
        deliverUp(data, context: context, isComplete: true)
        ObjCRuntime.release(context)
    }

    /// A datagram from the listener this transport's peer sent.
    func inject(_ data: [UInt8]) {
        guard !stopped else { return }
        bytesReceived += UInt64(data.count)
        packetsReceived += 1
        deliverDatagram(data)
    }

    override func send(_ data: [UInt8], context: UnsafeMutableRawPointer?, isComplete: Bool, completion: SendCompletion?) {
        guard !stopped else {
            completion?(.cancelled)
            return
        }
        if isStream {
            writes.append((data, 0, completion))
            flush()
        } else {
            datagram += data
            guard isComplete else {
                completion?(nil)
                return
            }
            let message = datagram
            datagram = []
            writes.append((message, 0, completion))
            flush()
        }
        if fd >= 0, shared == nil, !writes.isEmpty { EventLoop.shared.arm(fd, events: interest) }
    }

    private func flush() {
        while let first = writes.first {
            let remaining = first.bytes.count - first.offset
            if isStream, remaining == 0 {
                writes.removeFirst()
                first.completion?(nil)
                continue
            }
            let sent: Int
            if let shared, let peer {
                sent = first.bytes.withUnsafeBytes { bytes in peer.withPointer { sendto(shared.fd, bytes.baseAddress, bytes.count, 0, $0, $1) } }
            } else {
                guard fd >= 0 else { return }
                sent = first.bytes.withUnsafeBytes { Glibc.send(fd, $0.baseAddress! + first.offset, remaining, Int32(MSG_NOSIGNAL)) }
            }
            if sent < 0 {
                let code = errno
                if code == EAGAIN || code == EWOULDBLOCK || code == EINTR {
                    if shared != nil { Dispatch.after(0.005, on: connection.queue) { [weak self] in self?.flush() } }
                    return
                }
                writes.removeFirst()
                let error = NetworkError.posix(linux: code)
                first.completion?(error)
                if isStream {
                    failQueued(error)
                    failUp(error)
                }
                return
            }
            bytesSent += UInt64(sent)
            packetsSent += 1
            if isStream, sent < remaining {
                writes[0].offset += sent
                continue
            }
            writes.removeFirst()
            first.completion?(nil)
        }
        if finishRequested, isStream, fd >= 0 { shutdown(fd, Int32(SHUT_WR)) }
    }

    private func failQueued(_ error: NetworkError) {
        let pending = writes
        writes = []
        for write in pending { write.completion?(error) }
    }

    override func finish() {
        finishRequested = true
        if writes.isEmpty, isStream, fd >= 0 { shutdown(fd, Int32(SHUT_WR)) }
    }

    override func stop() {
        guard !stopped else { return }
        stopped = true
        failQueued(.cancelled)
        closeSocket()
        shared?.remove(peer)
    }

    private func closeSocket() {
        connecting = false
        guard fd >= 0, shared == nil else { return }
        EventLoop.shared.remove(fd)
        close(fd)
        fd = -1
    }

    override func copyMetadata() -> UnsafeMutableRawPointer? {
        let (object, state) = Metadata.make(isStream ? .tcp : .udp)
        if isStream { state.socket = fd }
        return object
    }

    /// TCP's round-trip time, in milliseconds, and its variance.
    var roundTrip: (smoothed: UInt64, variance: UInt64, retransmitted: UInt64) {
        guard isStream, fd >= 0 else { return (0, 0, 0) }
        var info = tcp_info()
        var length = socklen_t(MemoryLayout<tcp_info>.size)
        guard getsockopt(fd, Int32(IPPROTO_TCP), TCP_INFO, &info, &length) == 0 else { return (0, 0, 0) }
        return (UInt64(info.tcpi_rtt) / 1000, UInt64(info.tcpi_rttvar) / 1000, UInt64(info.tcpi_total_retrans) * UInt64(info.tcpi_snd_mss))
    }
}

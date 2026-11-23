import CPerryNetwork
import Glibc

// One thread waits on every socket with epoll. Sockets are registered
// one-shot: when one is ready its handler is queued on the queue it was
// registered with (a connection's own), and the handler arms it again with
// what it waits for next, once it has read or written what it could.

final class EventLoop: @unchecked Sendable {
    static let shared = EventLoop()

    private struct Registration {
        let generation: UInt32
        let queue: UnsafeMutableRawPointer
        let handler: (UInt32) -> Void
    }

    private let epoll: Int32
    private let lock = Lock()
    private var registrations: [Int32: Registration] = [:]
    private var nextGeneration: UInt32 = 1

    private init() {
        epoll = perry_epoll_create()
        guard epoll >= 0 else { networkFatal("epoll_create1 failed (\(errno))") }
        var thread = pthread_t()
        let context = Unmanaged.passRetained(self).toOpaque()
        guard pthread_create(&thread, nil, { context in
            Unmanaged<EventLoop>.fromOpaque(context!).takeUnretainedValue().run()
            return nil
        }, context) == 0 else { networkFatal("the network thread could not start") }
        pthread_detach(thread)
    }

    static let readable = UInt32(PERRY_EPOLL_IN)
    static let writable = UInt32(PERRY_EPOLL_OUT)
    static let failed = UInt32(PERRY_EPOLL_ERR) | UInt32(PERRY_EPOLL_HUP)

    /// Watches `fd` for `events`; `handler` runs on `queue` with what happened.
    func register(_ fd: Int32, queue: UnsafeMutableRawPointer, events: UInt32, handler: @escaping (UInt32) -> Void) {
        let generation = lock.withLock { () -> UInt32 in
            let generation = nextGeneration
            nextGeneration &+= 1
            registrations[fd] = Registration(generation: generation, queue: queue, handler: handler)
            return generation
        }
        control(add: true, fd, events: events, generation: generation)
    }

    /// Waits for `events` again.
    func arm(_ fd: Int32, events: UInt32) {
        guard let generation = lock.withLock({ registrations[fd]?.generation }) else { return }
        control(add: false, fd, events: events, generation: generation)
    }

    /// Stops watching `fd`, before it is closed.
    func remove(_ fd: Int32) {
        let removed = lock.withLock { registrations.removeValue(forKey: fd) != nil }
        if removed { _ = perry_epoll_remove(epoll, fd) }
    }

    private func control(add: Bool, _ fd: Int32, events: UInt32, generation: UInt32) {
        _ = perry_epoll_watch(epoll, fd, add ? 1 : 0, events, UInt64(generation) << 32 | UInt64(UInt32(bitPattern: fd)))
    }

    private func run() {
        var events = [perry_epoll_event](repeating: perry_epoll_event(), count: 64)
        while true {
            let count = perry_epoll_wait(epoll, &events, Int32(events.count))
            if count < 0 {
                if errno == EINTR { continue }
                networkWarning("epoll_wait failed (\(errno))")
                return
            }
            for index in 0..<Int(count) {
                let event = events[index]
                let fd = Int32(bitPattern: UInt32(truncatingIfNeeded: event.data))
                let generation = UInt32(truncatingIfNeeded: event.data >> 32)
                guard let registration = lock.withLock({ registrations[fd] }), registration.generation == generation else { continue }
                let what = event.events
                Dispatch.on(registration.queue) { [weak self] in
                    // Gone, or the descriptor was reused since.
                    guard let self, self.lock.withLock({ self.registrations[fd]?.generation }) == generation else { return }
                    registration.handler(what)
                }
            }
        }
    }
}

/// Socket calls that keep Linux's errno.
enum Sockets {
    static func nonBlocking(_ fd: Int32) {
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
    }

    static func setOption(_ fd: Int32, _ level: Int32, _ name: Int32, _ value: Int32) {
        var value = value
        _ = setsockopt(fd, level, name, &value, socklen_t(MemoryLayout<Int32>.size))
    }

    /// A new non-blocking socket.
    static func make(family: Int32, type: Int32, protocol: Int32 = 0) -> Int32 {
        socket(family, type | Int32(SOCK_NONBLOCK.rawValue) | Int32(SOCK_CLOEXEC.rawValue), `protocol`)
    }

    static func socketError(_ fd: Int32) -> Int32 {
        var value: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        _ = getsockopt(fd, SOL_SOCKET, SO_ERROR, &value, &length)
        return value
    }

    /// Applies TCP options to a socket.
    static func apply(tcp options: OptionsState?, ip: OptionsState?, to fd: Int32) {
        if let options {
            if options.noDelay { setOption(fd, Int32(IPPROTO_TCP), TCP_NODELAY, 1) }
            if options.enableKeepalive {
                setOption(fd, SOL_SOCKET, SO_KEEPALIVE, 1)
                if options.keepaliveIdleTime > 0 { setOption(fd, Int32(IPPROTO_TCP), TCP_KEEPIDLE, Int32(options.keepaliveIdleTime)) }
                if options.keepaliveInterval > 0 { setOption(fd, Int32(IPPROTO_TCP), TCP_KEEPINTVL, Int32(options.keepaliveInterval)) }
                if options.keepaliveCount > 0 { setOption(fd, Int32(IPPROTO_TCP), TCP_KEEPCNT, Int32(options.keepaliveCount)) }
            }
            if options.maximumSegmentSize > 0 { setOption(fd, Int32(IPPROTO_TCP), TCP_MAXSEG, Int32(options.maximumSegmentSize)) }
            if options.retransmitConnectionDropTime > 0 {
                setOption(fd, Int32(IPPROTO_TCP), TCP_USER_TIMEOUT, Int32(options.retransmitConnectionDropTime) * 1000)
            }
            if options.noPush { setOption(fd, Int32(IPPROTO_TCP), TCP_CORK, 1) }
        }
        apply(ip: ip, to: fd)
    }

    static func apply(ip options: OptionsState?, to fd: Int32) {
        guard let options else { return }
        let family = SocketAddress.local(fd)?.family ?? Int32(AF_INET)
        if options.hopLimit > 0 {
            if family == AF_INET6 {
                setOption(fd, Int32(IPPROTO_IPV6), IPV6_UNICAST_HOPS, Int32(options.hopLimit))
                setOption(fd, Int32(IPPROTO_IPV6), IPV6_MULTICAST_HOPS, Int32(options.hopLimit))
            } else {
                setOption(fd, Int32(IPPROTO_IP), IP_TTL, Int32(options.hopLimit))
                setOption(fd, Int32(IPPROTO_IP), IP_MULTICAST_TTL, Int32(options.hopLimit))
            }
        }
        if options.disableFragmentation, family == AF_INET {
            setOption(fd, Int32(IPPROTO_IP), IP_MTU_DISCOVER, Int32(IP_PMTUDISC_DO))
        }
        if options.disableMulticastLoopback {
            if family == AF_INET6 { setOption(fd, Int32(IPPROTO_IPV6), IPV6_MULTICAST_LOOP, 0) }
            else { setOption(fd, Int32(IPPROTO_IP), IP_MULTICAST_LOOP, 0) }
        }
    }
}

/// Name lookups, which block, on a global queue.
enum Resolver {
    struct Result {
        let addresses: [SocketAddress]
        let error: NetworkError?
        let milliseconds: UInt64
    }

    /// The addresses of `host`, for a socket of `type`, IPv6 and IPv4
    /// interleaved as a happy-eyeballs client tries them.
    static func resolve(_ host: String, port: UInt16, type: Int32, family: Int32, queue: UnsafeMutableRawPointer,
                        completion: @escaping (Result) -> Void) {
        Dispatch.background {
            let start = monotonicMilliseconds()
            var hints = addrinfo()
            hints.ai_family = family
            hints.ai_socktype = type
            hints.ai_flags = AI_ADDRCONFIG
            var list: UnsafeMutablePointer<addrinfo>?
            let status = getaddrinfo(host, String(port), &hints, &list)
            var v4: [SocketAddress] = []
            var v6: [SocketAddress] = []
            if status == 0 {
                var entry = list
                while let current = entry {
                    if let address = current.pointee.ai_addr {
                        let parsed = SocketAddress(linux: address, length: Int(current.pointee.ai_addrlen))
                        if parsed.family == AF_INET6 { if !v6.contains(parsed) { v6.append(parsed) } }
                        else if !v4.contains(parsed) { v4.append(parsed) }
                    }
                    entry = current.pointee.ai_next
                }
                freeaddrinfo(list)
            }
            var ordered: [SocketAddress] = []
            for index in 0..<max(v4.count, v6.count) {
                if index < v6.count { ordered.append(v6[index]) }
                if index < v4.count { ordered.append(v4[index]) }
            }
            let error: NetworkError? = ordered.isEmpty
                ? (status == EAI_NONAME || status == -5 /* EAI_NODATA */ || status == 0 ? .noSuchRecord : .dns(-65537))
                : nil
            let result = Result(addresses: ordered, error: error, milliseconds: monotonicMilliseconds() - start)
            Dispatch.on(queue) { completion(result) }
        }
    }
}

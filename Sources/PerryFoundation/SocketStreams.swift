import FoundationEssentials
import Glibc
import PerryObjCInterop

// Socket streams: the pair CFStreamCreatePairWithSocketToHost and
// +[NSStream getStreamsToHostWithName:port:inputStream:outputStream:] give,
// over one TCP connection, with TLS when the streams' properties ask for it
// (kCFStreamPropertySocketSecurityLevel, kCFStreamPropertySSLSettings).
//
// The connection is made on a thread of its own when the first stream
// opens, so opening returns at once as on Darwin; the thread then reads what
// arrives into a buffer the input stream reads from, and the streams' run
// loops hear of it. TLS is Security's Secure Transport, found when first
// wanted, as CFNetwork uses it on Darwin: its client certificate is what
// kCFStreamSSLCertificates gives (SSLSetCertificate).

/// Secure Transport's functions, in Security's provider when the program
/// has it loaded.
struct SecureTransport {
    typealias IO = @convention(c) (UnsafeRawPointer?, UnsafeMutableRawPointer?, UnsafeMutablePointer<Int>?) -> Int32
    let create: @convention(c) (UnsafeRawPointer?, Int32, Int32) -> id?
    let setIO: @convention(c) (id?, IO?, IO?) -> Int32
    let setConnection: @convention(c) (id?, UnsafeRawPointer?) -> Int32
    let setPeerName: @convention(c) (id?, UnsafePointer<CChar>?, Int) -> Int32
    let setCertificate: @convention(c) (id?, UnsafeRawPointer?) -> Int32
    let setOption: @convention(c) (id?, Int32, Bool) -> Int32
    let handshake: @convention(c) (id?) -> Int32
    let read: @convention(c) (id?, UnsafeMutableRawPointer?, Int, UnsafeMutablePointer<Int>?) -> Int32
    let write: @convention(c) (id?, UnsafeRawPointer?, Int, UnsafeMutablePointer<Int>?) -> Int32
    let close: @convention(c) (id?) -> Int32
    let copyPeerTrust: @convention(c) (id?, UnsafeMutablePointer<id?>?) -> Int32

    static let wouldBlock: Int32 = -9803, closedGraceful: Int32 = -9805, closedAbort: Int32 = -9806
    static let closedNoNotify: Int32 = -9816, peerAuthCompleted: Int32 = -9841

    nonisolated(unsafe) static let shared: SecureTransport? = {
        guard let library = dlopen("libPerrySecurity.so", RTLD_NOW | RTLD_NOLOAD) else { return nil }
        func find<T>(_ name: String, _ type: T.Type) -> T? { dlsym(library, name).map { unsafeBitCast($0, to: T.self) } }
        guard let create = find("_SSLCreateContext", (@convention(c) (UnsafeRawPointer?, Int32, Int32) -> id?).self),
              let setIO = find("_SSLSetIOFuncs", (@convention(c) (id?, IO?, IO?) -> Int32).self),
              let setConnection = find("_SSLSetConnection", (@convention(c) (id?, UnsafeRawPointer?) -> Int32).self),
              let setPeerName = find("_SSLSetPeerDomainName", (@convention(c) (id?, UnsafePointer<CChar>?, Int) -> Int32).self),
              let setCertificate = find("_SSLSetCertificate", (@convention(c) (id?, UnsafeRawPointer?) -> Int32).self),
              let setOption = find("_SSLSetSessionOption", (@convention(c) (id?, Int32, Bool) -> Int32).self),
              let handshake = find("_SSLHandshake", (@convention(c) (id?) -> Int32).self),
              let read = find("_SSLRead", (@convention(c) (id?, UnsafeMutableRawPointer?, Int, UnsafeMutablePointer<Int>?) -> Int32).self),
              let write = find("_SSLWrite", (@convention(c) (id?, UnsafeRawPointer?, Int, UnsafeMutablePointer<Int>?) -> Int32).self),
              let close = find("_SSLClose", (@convention(c) (id?) -> Int32).self),
              let copyPeerTrust = find("_SSLCopyPeerTrust", (@convention(c) (id?, UnsafeMutablePointer<id?>?) -> Int32).self)
        else { return nil }
        return SecureTransport(create: create, setIO: setIO, setConnection: setConnection, setPeerName: setPeerName,
                               setCertificate: setCertificate, setOption: setOption, handshake: handshake, read: read,
                               write: write, close: close, copyPeerTrust: copyPeerTrust)
    }()
}

/// PERRY_STREAM_TRACE: socket streams' connections, handshakes, ends and
/// failures are written to standard error.
enum StreamTrace {
    static let enabled = getenv("PERRY_STREAM_TRACE") != nil

    static func log(_ line: @autoclosure () -> String) {
        guard enabled else { return }
        let text = "perry: stream: " + line() + "\n"
        text.withCString { _ = Glibc.write(2, $0, strlen($0)) }
    }
}

/// One connection, which its two streams share.
final class StreamSocket: @unchecked Sendable {
    let host: String
    let port: Int
    let monitor = Monitor()
    /// Held around Secure Transport's reads and writes, which one context
    /// can't do at once.
    private let secureLock = Monitor()

    private var descriptor: Int32 = -1
    private var started = false
    private var connected = false
    /// The peer closed its side, and what it sent has all been buffered.
    private var finished = false
    private var failure: Int32?
    private var shutDown = false
    /// What arrived and has not been read.
    private var bytes: [UInt8] = []

    /// The streams, not retained (each retains this), and which have been
    /// opened and closed.
    private var input: id?
    private var output: id?
    private var inputOpen = false, outputOpen = false
    private var inputClosed = false, outputClosed = false

    private var secure = false
    /// kCFStreamPropertySSLSettings, retained.
    private var settings: id?
    private var context: id?

    init(host: String, port: Int) { (self.host, self.port) = (host, port) }

    /// A connection that exists: CFStreamCreatePairWithSocket's.
    init(descriptor: Int32) {
        (host, port) = ("", 0)
        self.descriptor = descriptor
        connected = true
    }

    deinit {
        if descriptor >= 0 { Glibc.close(descriptor) }
        ObjC.release(settings)
        ObjC.release(context)
    }

    /// The input and output streams of a connection, both +1.
    static func pair(_ socket: StreamSocket) -> (input: id, output: id)? {
        guard let input = Storage.allocate(UnsafeMutableRawPointer(Streams.inputClass)),
              let output = Storage.allocate(UnsafeMutableRawPointer(Streams.outputClass)) else { return nil }
        Storage.set(input, StreamStorage(.socketInput(socket)))
        Storage.set(output, StreamStorage(.socketOutput(socket)))
        (socket.input, socket.output) = (input, output)
        return (input, output)
    }

    // MARK: Properties

    func setProperty(_ name: String, _ value: id?) {
        StreamTrace.log("\(host):\(port) property \(name) set")
        monitor.locked {
            switch name {
            case "kCFStreamPropertySocketSecurityLevel":
                secure = Strings.value(of: value).map { $0 != "kCFStreamSocketSecurityLevelNone" } ?? false
            case "kCFStreamPropertySSLSettings":
                ObjC.release(settings)
                settings = ObjC.retain(value)
                if value != nil { secure = true }
            default:
                break
            }
        }
    }

    /// The server's trust, once there is one.
    func property(_ name: String) -> id? {
        guard name == "kCFStreamPropertySSLPeerTrust", let transport = SecureTransport.shared,
              let context = monitor.locked({ context }) else { return nil }
        var trust: id?
        _ = secureLock.locked { transport.copyPeerTrust(context, &trust) }
        return trust.flatMap { ObjC.autorelease($0) }
    }

    private func setting(_ key: String) -> id? {
        Dictionaries.entries(settings).first { Strings.value(of: $0.key) == key }?.value
    }

    // MARK: Opening and closing

    func open(_ object: id, input isInput: Bool) {
        StreamTrace.log("\(host):\(port) \(isInput ? "input" : "output") stream opened")
        let start: Bool = monitor.locked {
            if isInput { inputOpen = true } else { outputOpen = true }
            guard !started else { return false }
            started = true
            return true
        }
        if start {
            var thread = pthread_t()
            let context = Unmanaged.passRetained(self).toOpaque()
            let made = pthread_create(&thread, nil, { context in
                #if canImport(Darwin)
                let context = context
                #else
                guard let context else { return nil }
                #endif
                Unmanaged<StreamSocket>.fromOpaque(context).takeRetainedValue().run()
                return nil
            }, context)
            if made == 0 {
                pthread_detach(thread)
            } else {
                Unmanaged<StreamSocket>.fromOpaque(context).release()
                fail(code: made)
            }
        } else if monitor.locked({ connected && failure == nil }) {
            // The other stream opened the connection already.
            opened(object, input: isInput)
        }
    }

    /// Tells a stream it is open, and what it can do at once.
    private func opened(_ object: id, input isInput: Bool) {
        let storage = Streams.storage(object)
        guard storage.status == StreamStatus.opening else { return }
        storage.status = StreamStatus.open
        Streams.post(object, storage, StreamEvent.openCompleted)
        if isInput {
            if hasBytes { Streams.post(object, storage, StreamEvent.hasBytesAvailable) }
        } else {
            Streams.post(object, storage, StreamEvent.hasSpaceAvailable)
        }
    }

    /// The streams that are open or opening, retained for the caller.
    private func openStreams() -> [(object: id, input: Bool)] {
        monitor.locked {
            var streams: [(id, Bool)] = []
            if inputOpen, !inputClosed, let input { streams.append((ObjC.retain(input)!, true)) }
            if outputOpen, !outputClosed, let output { streams.append((ObjC.retain(output)!, false)) }
            return streams
        }
    }

    private func fail(code: Int32) {
        StreamTrace.log("\(host):\(port) failed with error \(code)")
        monitor.locked { failure = code }
        monitor.broadcast()
        for stream in openStreams() {
            Streams.fail(stream.object, Streams.storage(stream.object), code: code)
            ObjC.release(stream.object)
        }
    }

    func close(input isInput: Bool) {
        let both: Bool = monitor.locked {
            if isInput { inputClosed = true } else { outputClosed = true }
            return (inputClosed || !inputOpen && input == nil) && (outputClosed || !outputOpen && output == nil)
        }
        monitor.broadcast()
        if both { shutdown() }
    }

    /// A stream is going away: nothing more is told it, and the
    /// connection ends once both have.
    func detach(input isInput: Bool) {
        let both: Bool = monitor.locked {
            if isInput { (input, inputClosed) = (nil, true) } else { (output, outputClosed) = (nil, true) }
            return inputClosed && outputClosed
        }
        monitor.broadcast()
        if both { shutdown() }
    }

    /// Ends the connection; the thread reading it stops.
    private func shutdown() {
        let descriptor: Int32 = monitor.locked {
            guard !shutDown else { return -1 }
            shutDown = true
            return self.descriptor
        }
        if descriptor >= 0 { _ = Glibc.shutdown(descriptor, Int32(SHUT_RDWR)) }
        monitor.broadcast()
    }

    // MARK: The connection's thread

    private func run() {
        if !monitor.locked({ connected }) {
            guard let descriptor = connect() else { return }
            let stop: Bool = monitor.locked {
                self.descriptor = descriptor
                return shutDown
            }
            if stop { return }
        }
        StreamTrace.log("\(host):\(port) connected\(monitor.locked({ secure }) ? ", starting TLS" : "")")
        if monitor.locked({ secure }), let code = handshake() { return fail(code: code) }
        // Reads from here on never wait: the thread waits in poll, so a
        // write is not kept out while nothing arrives.
        let descriptor = monitor.locked { self.descriptor }
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        monitor.locked { connected = true }
        for stream in openStreams() {
            opened(stream.object, input: stream.input)
            ObjC.release(stream.object)
        }
        receive(descriptor)
        if let context = monitor.locked({ context }), let transport = SecureTransport.shared {
            _ = secureLock.locked { transport.close(context) }
        }
    }

    /// Resolves the host and connects, trying each address; nil, having
    /// failed the streams, when none answers.
    private func connect() -> Int32? {
        var hints = addrinfo()
        hints.ai_socktype = Int32(SOCK_STREAM.rawValue)
        var list: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &list) == 0, let first = list else {
            fail(code: ENOENT)
            return nil
        }
        defer { freeaddrinfo(first) }
        var code = ECONNREFUSED
        var next: UnsafeMutablePointer<addrinfo>? = first
        while let address = next {
            defer { next = address.pointee.ai_next }
            let descriptor = socket(address.pointee.ai_family, address.pointee.ai_socktype | Int32(SOCK_CLOEXEC.rawValue),
                                    address.pointee.ai_protocol)
            guard descriptor >= 0 else { continue }
            var result: Int32
            repeat { result = Glibc.connect(descriptor, address.pointee.ai_addr, address.pointee.ai_addrlen) } while result < 0 && errno == EINTR
            if result == 0 {
                var on: Int32 = 1
                _ = setsockopt(descriptor, Int32(IPPROTO_TCP), TCP_NODELAY, &on, socklen_t(MemoryLayout<Int32>.size))
                return descriptor
            }
            code = errno
            Glibc.close(descriptor)
        }
        fail(code: code)
        return nil
    }

    /// Secure Transport's read: what the socket has, up to what is asked.
    private static let secureRead: SecureTransport.IO = { connection, data, length in
        guard let connection, let data, let length else { return SecureTransport.closedAbort }
        let socket = Unmanaged<StreamSocket>.fromOpaque(connection).takeUnretainedValue()
        let wanted = length.pointee
        var count: Int
        repeat { count = recv(socket.descriptor, data, wanted, 0) } while count < 0 && errno == EINTR
        if count > 0 {
            length.pointee = count
            return count == wanted ? 0 : SecureTransport.wouldBlock
        }
        length.pointee = 0
        if count == 0 { return SecureTransport.closedGraceful }
        return errno == EAGAIN || errno == EWOULDBLOCK ? SecureTransport.wouldBlock : SecureTransport.closedAbort
    }

    /// Secure Transport's write: all of it, waiting for the socket to take it.
    private static let secureWrite: SecureTransport.IO = { connection, data, length in
        guard let connection, let data, let length else { return SecureTransport.closedAbort }
        let socket = Unmanaged<StreamSocket>.fromOpaque(connection).takeUnretainedValue()
        return socket.sendAll(UnsafeRawPointer(data), length.pointee) ? 0 : SecureTransport.closedAbort
    }

    /// Sends every byte, waiting when the socket's buffer is full.
    private func sendAll(_ data: UnsafeRawPointer, _ length: Int) -> Bool {
        var sent = 0
        while sent < length {
            let count = send(descriptor, data + sent, length - sent, Int32(MSG_NOSIGNAL))
            if count > 0 {
                sent += count
            } else if count < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                var wait = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
                _ = poll(&wait, 1, 1000)
                if monitor.locked({ shutDown }) { return false }
            } else if count < 0, errno == EINTR {
                continue
            } else {
                return false
            }
        }
        return true
    }

    /// The TLS handshake, with the settings' peer name and certificates;
    /// an error number when it fails.
    private func handshake() -> Int32? {
        guard let transport = SecureTransport.shared, let context = transport.create(nil, 1, 0) else { return EPROTO }
        monitor.locked { self.context = context }
        _ = transport.setIO(context, StreamSocket.secureRead, StreamSocket.secureWrite)
        _ = transport.setConnection(context, UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque()))
        // The name the certificate is checked against: the settings', else
        // the host; none with chain validation off.
        var validates = true
        if let value = setting("kCFStreamSSLValidatesCertificateChain") {
            validates = ObjC.sendBool(value, ObjC.selector("boolValue"), nil)
        }
        let name = setting("kCFStreamSSLPeerName").flatMap { Strings.value(of: $0) } ?? host
        if validates, !name.isEmpty {
            _ = name.withCString { transport.setPeerName(context, $0, strlen($0)) }
        } else if !validates {
            // kSSLSessionOptionBreakOnServerAuth: the chain is the program's to judge.
            _ = transport.setOption(context, 0, true)
        }
        if let certificates = setting("kCFStreamSSLCertificates") {
            let status = transport.setCertificate(context, UnsafeRawPointer(certificates))
            if status != 0 { return EPROTO }
        }
        var status: Int32
        repeat {
            status = transport.handshake(context)
        } while (status == SecureTransport.wouldBlock || status == SecureTransport.peerAuthCompleted) && !monitor.locked({ shutDown })
        StreamTrace.log("\(host):\(port) TLS handshake to \(name) \(status == 0 ? "done" : "failed with \(status)")"
            + (setting("kCFStreamSSLCertificates") != nil ? ", with a client certificate" : ""))
        return status == 0 ? nil : EPROTO
    }

    /// Reads what arrives until the peer closes or the streams do.
    private func receive(_ descriptor: Int32) {
        let transport = monitor.locked({ context }) != nil ? SecureTransport.shared : nil
        var chunk = [UInt8](repeating: 0, count: 16384)
        while true {
            // Room for more: a megabyte waits to be read at most.
            monitor.wait { bytes.count < 1 << 20 || shutDown }
            if monitor.locked({ shutDown }) { return }
            var wait = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&wait, 1, 1000)
            if monitor.locked({ shutDown }) { return }
            guard ready > 0 else { continue }
            var ended = false, failed: Int32?
            var received = 0
            while true {
                var count = 0
                if let transport {
                    let context = monitor.locked { self.context }
                    let status = secureLock.locked { transport.read(context, &chunk, chunk.count, &count) }
                    if count == 0 {
                        if status == SecureTransport.closedGraceful || status == SecureTransport.closedNoNotify { ended = true }
                        else if status != 0, status != SecureTransport.wouldBlock { failed = EPROTO }
                        break
                    }
                } else {
                    count = recv(descriptor, &chunk, chunk.count, 0)
                    if count == 0 { ended = true; break }
                    if count < 0 {
                        if errno == EINTR { continue }
                        if errno != EAGAIN, errno != EWOULDBLOCK { failed = errno }
                        break
                    }
                }
                monitor.locked { bytes.append(contentsOf: chunk[0..<count]) }
                received += count
                if received >= 1 << 20 { break }
            }
            if received > 0 || ended {
                monitor.locked { if ended { finished = true } }
                monitor.broadcast()
                let stream: id? = monitor.locked { inputOpen && !inputClosed ? ObjC.retain(input) : nil }
                if let stream {
                    Streams.post(stream, Streams.storage(stream), received > 0 ? StreamEvent.hasBytesAvailable : StreamEvent.endEncountered)
                    ObjC.release(stream)
                }
            }
            if let failed { return fail(code: failed) }
            if ended {
                StreamTrace.log("\(host):\(port) closed by the peer")
                return
            }
        }
    }

    // MARK: Reading and writing

    var hasBytes: Bool { monitor.locked { !bytes.isEmpty } }

    /// Up to `length` bytes of what has arrived, waiting for some; 0 at the
    /// end, -1 after a failure.
    func read(_ object: id, _ storage: StreamStorage, _ buffer: UnsafeMutablePointer<UInt8>, _ length: Int) -> Int {
        monitor.wait { !bytes.isEmpty || finished || failure != nil || inputClosed || shutDown }
        let (count, remaining, ended): (Int, Int, Bool) = monitor.locked {
            let taken = min(length, bytes.count)
            if taken > 0 {
                bytes.withUnsafeBufferPointer { memcpy(buffer, $0.baseAddress!, taken) }
                bytes.removeFirst(taken)
            }
            return (taken, bytes.count, finished)
        }
        monitor.broadcast()
        if count == 0 {
            guard ended else { return -1 }
            storage.status = StreamStatus.atEnd
            Streams.post(object, storage, StreamEvent.endEncountered)
            return 0
        }
        if remaining > 0 {
            Streams.post(object, storage, StreamEvent.hasBytesAvailable)
        } else if ended {
            Streams.post(object, storage, StreamEvent.endEncountered)
        }
        return count
    }

    func write(_ object: id, _ storage: StreamStorage, _ buffer: UnsafePointer<UInt8>, _ length: Int) -> Int {
        guard length > 0 else { return 0 }
        let (context, stopped) = monitor.locked { (self.context, shutDown || failure != nil) }
        guard !stopped else { return -1 }
        var written = 0
        if let context, let transport = SecureTransport.shared {
            let status = secureLock.locked { transport.write(context, buffer, length, &written) }
            if status != 0, written == 0 {
                fail(code: EPIPE)
                return -1
            }
        } else {
            guard sendAll(UnsafeRawPointer(buffer), length) else {
                fail(code: errno == 0 ? EPIPE : errno)
                return -1
            }
            written = length
        }
        Streams.post(object, storage, StreamEvent.hasSpaceAvailable)
        return written
    }
}

/// +1 streams to a host and port, connected when one is opened.
@c(_CFStreamCreatePairWithSocketToHost)
public func CFStreamCreatePairWithSocketToHost(_ allocator: UnsafeRawPointer?, _ host: UnsafeMutableRawPointer?, _ port: UInt32,
                                               _ read: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
                                               _ write: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) {
    let pair = Strings.value(of: host).flatMap { StreamSocket.pair(StreamSocket(host: $0, port: Int(port))) }
    StreamTrace.log("\(Strings.value(of: host) ?? "no host"):\(port) streams \(pair == nil ? "could not be made" : "made")")
    if let read { read.pointee = pair?.input } else { ObjC.release(pair?.input) }
    if let write { write.pointee = pair?.output } else { ObjC.release(pair?.output) }
}

/// +1 streams over a socket the program connected itself.
@c(_CFStreamCreatePairWithSocket)
public func CFStreamCreatePairWithSocket(_ allocator: UnsafeRawPointer?, _ socket: Int32,
                                         _ read: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
                                         _ write: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) {
    let pair = socket >= 0 ? StreamSocket.pair(StreamSocket(descriptor: socket)) : nil
    if let read { read.pointee = pair?.input } else { ObjC.release(pair?.input) }
    if let write { write.pointee = pair?.output } else { ObjC.release(pair?.output) }
}

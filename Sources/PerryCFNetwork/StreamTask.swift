import FoundationEssentials
import Glibc
import PerryObjCInterop
import PerryURLLoading

// NSURLSessionStreamTask, and what it shares with NSURLSessionWebSocketTask:
// tasks this module runs itself over a TCP socket (corelibs has neither),
// with Security's Secure Transport for TLS, as Foundation's socket streams
// use it. Each task's reads and writes run in order on threads of their
// own; completion handlers and delegate messages come on the session's
// delegate queue, as on Darwin.

// MARK: - Errors

enum SocketTaskErrors {
    /// Darwin's errno values, which programs compare NSPOSIXErrorDomain
    /// codes with.
    static let notConnected = 57, timedOut = 60, cancelled = 89, messageTooLong = 40, brokenPipe = 32, connectionReset = 54

    /// A Linux errno as Darwin numbers it.
    static func darwin(_ code: Int32) -> Int {
        switch code {
        case EPIPE: return 32
        case EMSGSIZE: return 40
        case EADDRNOTAVAIL: return 49
        case ENETUNREACH: return 51
        case ECONNABORTED: return 53
        case ECONNRESET: return 54
        case ENOTCONN: return 57
        case ETIMEDOUT: return 60
        case ECONNREFUSED: return 61
        case EHOSTUNREACH: return 65
        case ECANCELED: return 89
        case EPROTO: return 100
        default: return Int(code)
        }
    }

    static func posix(_ code: Int) -> NSError { NSError.make(domain: "NSPOSIXErrorDomain", code: code, userInfo: nil) }

    /// An NSURLErrorDomain error with its description and failing URL.
    static func urlError(_ code: Int, _ description: String, _ url: URL?) -> NSError {
        var info: [(String, NSObject)] = [("NSLocalizedDescription", NSObject.string(description))]
        if let url, let object = NSURL.of(url) {
            info.append((ErrorKeys.NSURLErrorFailingURLErrorKey, object))
            info.append((ErrorKeys.NSURLErrorFailingURLStringErrorKey, NSObject.string(url.absoluteString)))
        }
        return NSError.make(domain: ErrorKeys.NSURLErrorDomain, code: code, userInfo: NSMutableDictionary.of(info))
    }

    static func cancelledError(_ url: URL?) -> NSError { urlError(-999, "cancelled", url) }

    /// What a failed connection is to the program: the host not found,
    /// no answer in time, or no server listening.
    static func connectError(_ failure: Int, _ url: URL?) -> NSError {
        switch failure {
        case TaskSocket.hostNotFound: return urlError(-1003, "A server with the specified hostname could not be found.", url)
        case timedOut: return urlError(-1001, "The request timed out.", url)
        case cancelled: return cancelledError(url)
        default: return urlError(-1004, "Could not connect to the server.", url)
        }
    }

    static func secureConnectionFailed(_ url: URL?) -> NSError {
        urlError(-1200, "An SSL error has occurred and a secure connection to the server cannot be made.", url)
    }
}

// MARK: - Threads

enum TaskClock {
    /// Seconds on the monotonic clock.
    static func now() -> Double {
        var time = timespec()
        clock_gettime(CLOCK_MONOTONIC, &time)
        return Double(time.tv_sec) + Double(time.tv_nsec) / 1_000_000_000
    }
}

enum SocketTaskThreads {
    /// Runs `body` on a new detached thread.
    static func spawn(_ body: @escaping () -> Void) {
        let context = Unmanaged.passRetained(ClosureBox(body)).toOpaque()
        var thread = pthread_t()
        let made = pthread_create(&thread, nil, { context in
            #if canImport(Darwin)
            let context = context
            #else
            guard let context else { return nil }
            #endif
            let box = Unmanaged<ClosureBox>.fromOpaque(context).takeRetainedValue()
            ObjCRuntime.autoreleasepool { (box.body as? () -> Void)?() }
            return nil
        }, context)
        if made == 0 {
            pthread_detach(thread)
        } else {
            Unmanaged<ClosureBox>.fromOpaque(context).release()
            body()
        }
    }
}

/// Work done in order on a thread of its own, which ends when there is
/// none left.
final class SocketTaskQueue: @unchecked Sendable {
    private let lock = Lock()
    private var jobs: [() -> Void] = []
    private var running = false

    func async(_ job: @escaping () -> Void) {
        let start: Bool = lock.withLock {
            jobs.append(job)
            guard !running else { return false }
            running = true
            return true
        }
        if start { SocketTaskThreads.spawn { [self] in drain() } }
    }

    private func drain() {
        while true {
            let job: (() -> Void)? = lock.withLock {
                guard !jobs.isEmpty else {
                    running = false
                    return nil
                }
                return jobs.removeFirst()
            }
            guard let job else { return }
            ObjCRuntime.autoreleasepool { job() }
        }
    }
}

/// Opens once, with an error or none; waiters wait until then.
final class SocketTaskGate: @unchecked Sendable {
    private let mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
    private let condition = UnsafeMutablePointer<pthread_cond_t>.allocate(capacity: 1)
    private var opened = false
    private var failure: NSError?

    init() {
        pthread_mutex_init(mutex, nil)
        pthread_cond_init(condition, nil)
    }

    deinit {
        pthread_cond_destroy(condition)
        pthread_mutex_destroy(mutex)
        condition.deallocate()
        mutex.deallocate()
    }

    func open(_ failure: NSError?) {
        pthread_mutex_lock(mutex)
        if !opened {
            opened = true
            self.failure = failure
        }
        pthread_cond_broadcast(condition)
        pthread_mutex_unlock(mutex)
    }

    func wait() -> NSError? {
        pthread_mutex_lock(mutex)
        while !opened { pthread_cond_wait(condition, mutex) }
        let failure = failure
        pthread_mutex_unlock(mutex)
        return failure
    }
}

// MARK: - TLS

/// Secure Transport's functions, from Security's provider.
struct TaskSecureTransport {
    typealias Context = UnsafeMutableRawPointer
    typealias IO = @convention(c) (UnsafeRawPointer?, UnsafeMutableRawPointer?, UnsafeMutablePointer<Int>?) -> Int32
    let create: @convention(c) (UnsafeRawPointer?, Int32, Int32) -> Context?
    let setIO: @convention(c) (Context?, IO?, IO?) -> Int32
    let setConnection: @convention(c) (Context?, UnsafeRawPointer?) -> Int32
    let setPeerName: @convention(c) (Context?, UnsafePointer<CChar>?, Int) -> Int32
    let handshake: @convention(c) (Context?) -> Int32
    let read: @convention(c) (Context?, UnsafeMutableRawPointer?, Int, UnsafeMutablePointer<Int>?) -> Int32
    let write: @convention(c) (Context?, UnsafeRawPointer?, Int, UnsafeMutablePointer<Int>?) -> Int32
    let close: @convention(c) (Context?) -> Int32

    static let wouldBlock: Int32 = -9803, closedGraceful: Int32 = -9805, closedNoNotify: Int32 = -9816

    nonisolated(unsafe) static let shared: TaskSecureTransport? = {
        let security = "/System/Library/Frameworks/Security.framework/Security"
        let library = dlopen("libPerrySecurity.so", RTLD_NOW | RTLD_NOLOAD)
        func find<T>(_ name: String, _ type: T.Type) -> T? {
            if let lookup = providerSymbolLookup,
               let symbol = security.withCString({ path in name.withCString { lookup(path, $0) } }) {
                return unsafeBitCast(symbol, to: T.self)
            }
            return library.flatMap { dlsym($0, name) }.map { unsafeBitCast($0, to: T.self) }
        }
        guard let create = find("_SSLCreateContext", (@convention(c) (UnsafeRawPointer?, Int32, Int32) -> Context?).self),
              let setIO = find("_SSLSetIOFuncs", (@convention(c) (Context?, IO?, IO?) -> Int32).self),
              let setConnection = find("_SSLSetConnection", (@convention(c) (Context?, UnsafeRawPointer?) -> Int32).self),
              let setPeerName = find("_SSLSetPeerDomainName", (@convention(c) (Context?, UnsafePointer<CChar>?, Int) -> Int32).self),
              let handshake = find("_SSLHandshake", (@convention(c) (Context?) -> Int32).self),
              let read = find("_SSLRead", (@convention(c) (Context?, UnsafeMutableRawPointer?, Int, UnsafeMutablePointer<Int>?) -> Int32).self),
              let write = find("_SSLWrite", (@convention(c) (Context?, UnsafeRawPointer?, Int, UnsafeMutablePointer<Int>?) -> Int32).self),
              let close = find("_SSLClose", (@convention(c) (Context?) -> Int32).self)
        else { return nil }
        return TaskSecureTransport(create: create, setIO: setIO, setConnection: setConnection, setPeerName: setPeerName,
                                   handshake: handshake, read: read, write: write, close: close)
    }()
}

// MARK: - The socket

/// One TCP connection, with TLS when asked. Reads and writes may run on
/// two threads at once; closing wakes both.
final class TaskSocket: @unchecked Sendable {
    /// connect()'s failure when the host can't be resolved.
    static let hostNotFound = -1

    let host: String
    let port: Int
    private let lock = Lock()
    /// Held around Secure Transport's calls, which one context can't make
    /// at once.
    private let secureLock = Lock()
    private var descriptor: Int32 = -1
    private var context: TaskSecureTransport.Context?
    private var closed = false

    init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    deinit {
        if descriptor >= 0 { Glibc.close(descriptor) }
        if let context {
            ObjCRuntime.release(context)
        }
    }

    var isClosed: Bool { lock.withLock { closed } }
    var isSecure: Bool { lock.withLock { context != nil } }

    private func current() -> (Int32, TaskSecureTransport.Context?) { lock.withLock { (descriptor, context) } }

    /// Waits until the socket is ready for `events`: nil then, else
    /// Darwin's ETIMEDOUT past the deadline or ECANCELED once closed.
    private func wait(_ descriptor: Int32, _ events: Int32, _ deadline: Double?) -> Int? {
        while true {
            if isClosed { return SocketTaskErrors.cancelled }
            var slice: Int32 = 200
            if let deadline {
                let left = deadline - TaskClock.now()
                if left <= 0 { return SocketTaskErrors.timedOut }
                slice = Int32(min(200, max(1, left * 1000)))
            }
            var entry = pollfd(fd: descriptor, events: Int16(events), revents: 0)
            let ready = poll(&entry, 1, slice)
            if ready > 0 { return nil }
            if ready < 0, errno != EINTR { return SocketTaskErrors.darwin(errno) }
        }
    }

    /// Resolves the host and connects, trying each address: nil when
    /// connected, else hostNotFound or Darwin's errno.
    func connect(deadline: Double?) -> Int? {
        var hints = addrinfo()
        hints.ai_socktype = Int32(SOCK_STREAM.rawValue)
        var list: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &list) == 0, let first = list else { return TaskSocket.hostNotFound }
        defer { freeaddrinfo(first) }
        var failure = SocketTaskErrors.darwin(ECONNREFUSED)
        var next: UnsafeMutablePointer<addrinfo>? = first
        while let address = next {
            next = address.pointee.ai_next
            if isClosed { return SocketTaskErrors.cancelled }
            let made = socket(address.pointee.ai_family, address.pointee.ai_socktype | Int32(SOCK_CLOEXEC.rawValue),
                              address.pointee.ai_protocol)
            guard made >= 0 else { continue }
            _ = fcntl(made, F_SETFL, fcntl(made, F_GETFL) | O_NONBLOCK)
            var result = Glibc.connect(made, address.pointee.ai_addr, address.pointee.ai_addrlen)
            var code = result < 0 ? errno : 0
            if result < 0, code == EINPROGRESS || code == EINTR {
                if let waited = wait(made, Int32(POLLOUT), deadline) {
                    Glibc.close(made)
                    if waited == SocketTaskErrors.timedOut || waited == SocketTaskErrors.cancelled { return waited }
                    failure = waited
                    continue
                }
                var size = socklen_t(MemoryLayout<Int32>.size)
                code = 0
                _ = getsockopt(made, SOL_SOCKET, SO_ERROR, &code, &size)
                result = code == 0 ? 0 : -1
            }
            guard result == 0 else {
                failure = SocketTaskErrors.darwin(code)
                Glibc.close(made)
                continue
            }
            var on: Int32 = 1
            _ = setsockopt(made, Int32(IPPROTO_TCP), TCP_NODELAY, &on, socklen_t(MemoryLayout<Int32>.size))
            let stop: Bool = lock.withLock {
                guard !closed else { return true }
                descriptor = made
                return false
            }
            if stop {
                Glibc.close(made)
                return SocketTaskErrors.cancelled
            }
            return nil
        }
        return failure
    }

    // MARK: TLS

    /// Secure Transport's read: what the socket has, up to what is asked.
    private static let secureRead: TaskSecureTransport.IO = { connection, data, length in
        guard let connection, let data, let length else { return -9806 }
        let socket = Unmanaged<TaskSocket>.fromOpaque(connection).takeUnretainedValue()
        let wanted = length.pointee
        var count: Int
        repeat { count = recv(socket.descriptor, data, wanted, 0) } while count < 0 && errno == EINTR
        if count > 0 {
            length.pointee = count
            return count == wanted ? 0 : TaskSecureTransport.wouldBlock
        }
        length.pointee = 0
        if count == 0 { return TaskSecureTransport.closedGraceful }
        return errno == EAGAIN || errno == EWOULDBLOCK ? TaskSecureTransport.wouldBlock : -9806
    }

    /// Secure Transport's write: all of it, waiting for the socket to take it.
    private static let secureWrite: TaskSecureTransport.IO = { connection, data, length in
        guard let connection, let data, let length else { return -9806 }
        let socket = Unmanaged<TaskSocket>.fromOpaque(connection).takeUnretainedValue()
        return socket.sendAll(socket.descriptor, UnsafeRawPointer(data), length.pointee, deadline: nil) == nil ? 0 : -9806
    }

    /// The TLS handshake, checking the server's certificate against
    /// `peerName`: nil once secure, else an error number.
    func startTLS(peerName: String, deadline: Double?) -> Int? {
        let (descriptor, existing) = current()
        guard existing == nil else { return nil }
        guard descriptor >= 0, let transport = TaskSecureTransport.shared, let context = transport.create(nil, 1, 0) else {
            return SocketTaskErrors.darwin(EPROTO)
        }
        _ = transport.setIO(context, TaskSocket.secureRead, TaskSocket.secureWrite)
        _ = transport.setConnection(context, UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque()))
        _ = peerName.withCString { transport.setPeerName(context, $0, strlen($0)) }
        while true {
            let status = secureLock.withLock { transport.handshake(context) }
            if status == 0 { break }
            if status == TaskSecureTransport.wouldBlock, wait(descriptor, Int32(POLLIN), deadline) == nil { continue }
            ObjCRuntime.release(context)
            return SocketTaskErrors.darwin(EPROTO)
        }
        lock.withLock { self.context = context }
        return nil
    }

    /// Ends TLS (close_notify): the connection goes on in the clear.
    func stopTLS() {
        let context: TaskSecureTransport.Context? = lock.withLock {
            defer { self.context = nil }
            return self.context
        }
        guard let context else { return }
        if let transport = TaskSecureTransport.shared { _ = secureLock.withLock { transport.close(context) } }
        ObjCRuntime.release(context)
    }

    // MARK: Reading and writing

    enum ReadResult {
        case data([UInt8])
        case end
        /// Darwin's errno: ETIMEDOUT past the deadline, ECANCELED once closed.
        case failed(Int)
    }

    /// Some bytes, at most `limit`, waiting for them until the deadline.
    func read(limit: Int, deadline: Double?) -> ReadResult {
        var buffer = [UInt8](repeating: 0, count: max(1, limit))
        while true {
            let (descriptor, context) = current()
            if isClosed || descriptor < 0 { return .failed(SocketTaskErrors.cancelled) }
            if let context, let transport = TaskSecureTransport.shared {
                var count = 0
                let status = secureLock.withLock { buffer.withUnsafeMutableBytes { transport.read(context, $0.baseAddress, $0.count, &count) } }
                if count > 0 { return .data(Array(buffer[0..<count])) }
                if status == TaskSecureTransport.closedGraceful || status == TaskSecureTransport.closedNoNotify { return .end }
                if status != 0, status != TaskSecureTransport.wouldBlock {
                    return .failed(isClosed ? SocketTaskErrors.cancelled : SocketTaskErrors.connectionReset)
                }
            } else {
                let count = buffer.withUnsafeMutableBytes { recv(descriptor, $0.baseAddress, $0.count, 0) }
                if count > 0 { return .data(Array(buffer[0..<count])) }
                if count == 0 { return isClosed ? .failed(SocketTaskErrors.cancelled) : .end }
                let code = errno
                if code == EINTR { continue }
                if code != EAGAIN, code != EWOULDBLOCK {
                    return .failed(isClosed ? SocketTaskErrors.cancelled : SocketTaskErrors.darwin(code))
                }
            }
            if let failure = wait(descriptor, Int32(POLLIN), deadline) { return .failed(failure) }
        }
    }

    /// Sends every byte, waiting when the socket's buffer is full: nil,
    /// else Darwin's errno.
    fileprivate func sendAll(_ descriptor: Int32, _ data: UnsafeRawPointer, _ length: Int, deadline: Double?) -> Int? {
        var sent = 0
        while sent < length {
            let count = send(descriptor, data + sent, length - sent, Int32(MSG_NOSIGNAL))
            if count > 0 {
                sent += count
                continue
            }
            let code = count < 0 ? errno : EPIPE
            if code == EINTR { continue }
            if code == EAGAIN || code == EWOULDBLOCK {
                if let failure = wait(descriptor, Int32(POLLOUT), deadline) { return failure }
                continue
            }
            return isClosed ? SocketTaskErrors.cancelled : SocketTaskErrors.darwin(code)
        }
        return nil
    }

    /// Writes all of `bytes`: nil, else Darwin's errno.
    func write(_ bytes: [UInt8], deadline: Double?) -> Int? {
        guard !bytes.isEmpty else { return nil }
        let (descriptor, context) = current()
        if isClosed || descriptor < 0 { return SocketTaskErrors.cancelled }
        if let context, let transport = TaskSecureTransport.shared {
            var written = 0
            let status = secureLock.withLock { bytes.withUnsafeBytes { transport.write(context, $0.baseAddress, $0.count, &written) } }
            return status == 0 ? nil : (isClosed ? SocketTaskErrors.cancelled : SocketTaskErrors.brokenPipe)
        }
        return bytes.withUnsafeBytes { sendAll(descriptor, $0.baseAddress!, $0.count, deadline: deadline) }
    }

    func shutdownWrite() {
        let (descriptor, _) = current()
        if descriptor >= 0 { _ = Glibc.shutdown(descriptor, Int32(SHUT_WR)) }
    }

    func shutdownRead() {
        let (descriptor, _) = current()
        if descriptor >= 0 { _ = Glibc.shutdown(descriptor, Int32(SHUT_RD)) }
    }

    /// Ends the connection; reads and writes under way stop. The socket is
    /// closed once nothing uses it.
    func close() {
        let descriptor: Int32 = lock.withLock {
            guard !closed else { return -1 }
            closed = true
            return self.descriptor
        }
        if descriptor >= 0 { _ = Glibc.shutdown(descriptor, Int32(SHUT_RDWR)) }
    }

    /// Hands the socket over (to streams): this no longer reads, writes or
    /// closes it.
    func detach() -> Int32 {
        lock.withLock {
            let handed = descriptor
            descriptor = -1
            closed = true
            return handed
        }
    }
}

// MARK: - Tasks run here

/// A WebSocket or stream task's state. The session and the task object are
/// retained until the task completes, as Darwin's session holds its tasks.
class SocketTaskState: @unchecked Sendable {
    let identifier: Int
    let lock = Lock()
    let originalRequest: Request
    let queue: NSOperationQueue
    let session: UnsafeMutableRawPointer
    /// The task object, retained until completion.
    let object: UnsafeMutableRawPointer
    private var holding = true

    var taskDescription: String?
    var priority: Float = 0.5
    var taskDelegate: NSObject?
    private var stateValue = 1
    private var started = false
    private var storedResponse: Response?
    private var storedError: NSError?
    private var sent: Int64 = 0, received: Int64 = 0

    init(session: UnsafeMutableRawPointer, request: Request, object: UnsafeMutableRawPointer) {
        identifier = SocketTasks.nextIdentifier()
        originalRequest = request
        self.session = ObjCRuntime.retain(session)!
        self.object = ObjCRuntime.retain(object)!
        let sessionState = Sessions.state(session) ?? Sessions.adopt(session)
        queue = sessionState.queue
        sessionState.add(self)
    }

    /// NSURLSessionTaskState: running 0, suspended 1, canceling 2, completed 3.
    var currentState: Int { lock.withLock { stateValue } }
    var isCompleted: Bool { currentState == 3 }
    var response: Response? { lock.withLock { storedResponse } }
    var error: NSError? { lock.withLock { storedError } }
    var bytesSent: Int64 { lock.withLock { sent } }
    var bytesReceived: Int64 { lock.withLock { received } }

    func setResponse(_ response: Response) { lock.withLock { storedResponse = response } }
    func countSent(_ count: Int) { lock.withLock { sent += Int64(count) } }
    func countReceived(_ count: Int) { lock.withLock { received += Int64(count) } }

    /// Moves to canceling, once; false when the task is done or going.
    func beginCancelling() -> Bool {
        lock.withLock {
            guard stateValue < 2 else { return false }
            stateValue = 2
            return true
        }
    }

    func resume() {
        let first: Bool = lock.withLock {
            guard stateValue == 1 else { return false }
            stateValue = 0
            defer { started = true }
            return !started
        }
        if first { start() }
    }

    /// Suspending a connection that runs here doesn't stop it: the task is
    /// marked suspended until resumed.
    func suspend() {
        lock.withLock { if stateValue == 0 { stateValue = 1 } }
    }

    var hasStarted: Bool { lock.withLock { started } }

    /// The connection begins; subclasses start theirs.
    func start() {}

    func cancel() {}

    /// Runs `body` on the delegate queue.
    func deliver(_ body: @escaping () -> Void) {
        queue.addOperation(block: Closures.block { ObjCRuntime.autoreleasepool(body) })
    }

    /// Who is told of `selector`: the task's delegate, else the session's.
    func delegate(for selector: String) -> NSObject? {
        if let taskDelegate, taskDelegate.responds(to: selector) { return taskDelegate }
        if let delegate = Sessions.state(session)?.delegate, delegate.responds(to: selector) { return delegate }
        return nil
    }

    /// Calls a void block with one object argument (an NSError) on the
    /// delegate queue.
    func call(_ handler: ObjCBlock?, error: NSError?) {
        guard let handler else { return }
        nonisolated(unsafe) let block = handler
        deliver {
            block.function(as: (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void).self)(block.object, error?.objcObject)
        }
    }

    /// The task is done: the delegate hears of it (unless `notify` is
    /// false, for a task whose streams were captured), then the session and
    /// task are let go. Once only.
    func complete(_ error: NSError?, notify: Bool = true) {
        let first: Bool = lock.withLock {
            guard holding else { return false }
            holding = false
            stateValue = 3
            storedError = error
            return true
        }
        guard first else { return }
        Sessions.state(session)?.remove(self)
        let (session, object) = (self.session, self.object)
        deliver { [self] in
            if notify, let delegate = delegate(for: "URLSession:task:didCompleteWithError:") {
                unsafeBitCast(ObjCRuntime.msgSend, to: (@convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeMutableRawPointer?,
                                                                        UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void).self)(
                    delegate.objcObject, ObjCRuntime.selector("URLSession:task:didCompleteWithError:"), session, object, error?.objcObject)
            }
            ObjCRuntime.release(object)
            ObjCRuntime.release(session)
        }
    }
}

enum SocketTasks {
    static let states = StateTable<SocketTaskState>()
    private static let lock = Lock()
    nonisolated(unsafe) private static var next = 0

    /// Identifiers apart from corelibs' tasks', which count from 1.
    static func nextIdentifier() -> Int {
        lock.withLock {
            next += 1
            return 100_000 + next
        }
    }
}

// MARK: - Stream tasks

final class StreamTaskState: SocketTaskState {
    let host: String
    let port: Int
    let socket: TaskSocket
    private let reads = SocketTaskQueue()
    private let writes = SocketTaskQueue()
    private let connected = SocketTaskGate()
    /// Read and not yet given out; the reading thread's alone.
    private var buffer: [UInt8] = []
    private var ended = false
    /// A read that timed out fails the reads after it, as on Darwin.
    private var readFailure: NSError?
    private var readClosed = false
    private var writeClosed = false
    /// Why work fails once the task is cancelled or captured.
    private var terminal: NSError?

    init(session: UnsafeMutableRawPointer, host: String, port: Int, object: UnsafeMutableRawPointer) {
        self.host = host
        self.port = port
        socket = TaskSocket(host: host, port: port)
        super.init(session: session, request: Request(url: URL(string: "https://\(host):\(port)")), object: object)
    }

    private var url: URL? { originalRequest.url }
    private var finished: NSError? { lock.withLock { terminal } }

    override func start() {
        SocketTaskThreads.spawn { [self] in
            if let failure = socket.connect(deadline: TaskClock.now() + 60) {
                let error = SocketTaskErrors.connectError(failure, url)
                lock.withLock { if terminal == nil { terminal = error } }
                connected.open(error)
                complete(finished)
            } else {
                connected.open(nil)
            }
        }
    }

    /// Fails what waits once the connection is gone: why, else nil.
    private func ready() -> NSError? { connected.wait() ?? finished }

    func read(minimum: Int, maximum: Int, timeout: Double, handler: ObjCBlock?) {
        nonisolated(unsafe) let block = handler
        reads.async { [self] in
            var data: [UInt8]?
            var atEnd = false
            var error = ready() ?? readFailure
            if error == nil, lock.withLock({ readClosed }) {
                atEnd = true
            } else if error == nil {
                let deadline = timeout > 0 ? TaskClock.now() + timeout : nil
                let wanted = max(1, minimum)
                while buffer.count < wanted, !ended {
                    switch socket.read(limit: max(65536, maximum), deadline: deadline) {
                    case .data(let bytes):
                        buffer += bytes
                        countReceived(bytes.count)
                    case .end:
                        ended = true
                    case .failed(let code):
                        if code == SocketTaskErrors.cancelled {
                            error = finished ?? SocketTaskErrors.posix(SocketTaskErrors.notConnected)
                        } else {
                            error = SocketTaskErrors.posix(code)
                            if code == SocketTaskErrors.timedOut { readFailure = error }
                        }
                    }
                    if error != nil { break }
                }
                if error == nil {
                    let taken = min(max(maximum, 0), buffer.count)
                    if taken > 0 {
                        data = Array(buffer[0..<taken])
                        buffer.removeFirst(taken)
                    }
                    atEnd = ended && buffer.isEmpty
                }
            }
            guard let block else { return }
            let (bytes, end, failure) = (data, atEnd, error)
            deliver {
                let object = bytes.map { NSData.of(Data($0)) }
                block.function(as: (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Bool, UnsafeMutableRawPointer?) -> Void).self)(
                    block.object, object?.objcObject, end, failure?.objcObject)
            }
        }
    }

    func write(_ data: Data, timeout: Double, handler: ObjCBlock?) {
        writes.async { [self] in
            var error = ready()
            if error == nil, lock.withLock({ writeClosed }) {
                error = SocketTaskErrors.posix(SocketTaskErrors.notConnected)
            } else if error == nil {
                let deadline = timeout > 0 ? TaskClock.now() + timeout : nil
                if let code = socket.write([UInt8](data), deadline: deadline) {
                    error = code == SocketTaskErrors.cancelled ? finished ?? SocketTaskErrors.posix(code) : SocketTaskErrors.posix(code)
                } else {
                    countSent(data.count)
                }
            }
            call(handler, error: error)
        }
    }

    private func tell(_ selector: String) {
        deliver { [self] in
            guard let delegate = delegate(for: selector) else { return }
            unsafeBitCast(ObjCRuntime.msgSend, to: (@convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeMutableRawPointer?,
                                                                    UnsafeMutableRawPointer?) -> Void).self)(
                delegate.objcObject, ObjCRuntime.selector(selector), session, object)
        }
    }

    /// After the writes before it: the server reads the end of the stream.
    func closeWrite() {
        writes.async { [self] in
            guard ready() == nil else { return }
            lock.withLock { writeClosed = true }
            socket.shutdownWrite()
            tell("URLSession:writeClosedForStreamTask:")
        }
    }

    /// After the reads before it: later reads find the end.
    func closeRead() {
        reads.async { [self] in
            guard ready() == nil else { return }
            lock.withLock { readClosed = true }
            socket.shutdownRead()
            tell("URLSession:readClosedForStreamTask:")
        }
    }

    /// TLS from here on, checked against the host's name; a failed
    /// handshake fails the task.
    func startSecureConnection() {
        writes.async { [self] in
            guard ready() == nil else { return }
            if socket.startTLS(peerName: host, deadline: TaskClock.now() + 60) != nil {
                let error = SocketTaskErrors.secureConnectionFailed(url)
                lock.withLock { if terminal == nil { terminal = error } }
                socket.close()
                complete(error)
            }
        }
    }

    func stopSecureConnection() {
        writes.async { [self] in
            guard ready() == nil else { return }
            socket.stopTLS()
        }
    }

    /// Once the reads and writes asked for are done, the socket becomes a
    /// pair of streams for the delegate, and the task completes without
    /// a completion message, as on Darwin. Bytes read ahead and not yet
    /// given out, and TLS, don't carry over to the streams.
    func captureStreams() {
        writes.async { [self] in
            guard ready() == nil else { return }
            let drained = SocketTaskGate()
            reads.async { drained.open(nil) }
            _ = drained.wait()
            guard finished == nil else { return }
            let descriptor = socket.detach()
            lock.withLock { if terminal == nil { terminal = SocketTaskErrors.posix(SocketTaskErrors.notConnected) } }
            guard descriptor >= 0, let pair = SocketTaskStreams.pair(descriptor) else { return complete(finished) }
            let (input, output) = pair
            deliver { [self] in
                let selector = "URLSession:streamTask:didBecomeInputStream:outputStream:"
                if let delegate = delegate(for: selector) {
                    unsafeBitCast(ObjCRuntime.msgSend, to: (@convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeMutableRawPointer?,
                                                                            UnsafeMutableRawPointer?, UnsafeMutableRawPointer?,
                                                                            UnsafeMutableRawPointer?) -> Void).self)(
                        delegate.objcObject, ObjCRuntime.selector(selector), session, object, input, output)
                }
                ObjCRuntime.release(input)
                ObjCRuntime.release(output)
            }
            complete(nil, notify: false)
        }
    }

    /// NSURLErrorCancelled for the task and what it was asked to do; it
    /// completes after the reads and writes before it.
    override func cancel() {
        guard beginCancelling() else { return }
        let error = SocketTaskErrors.cancelledError(url)
        lock.withLock { if terminal == nil { terminal = error } }
        socket.close()
        connected.open(error)
        reads.async { [self] in writes.async { [self] in complete(error) } }
    }
}

/// Foundation's socket streams over a connected socket.
enum SocketTaskStreams {
    typealias Create = @convention(c) (UnsafeRawPointer?, Int32, UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
                                       UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Void

    nonisolated(unsafe) static let create: Create? = {
        guard let lookup = providerSymbolLookup else { return nil }
        let symbol = "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation".withCString { library in
            "_CFStreamCreatePairWithSocket".withCString { lookup(library, $0) }
        }
        return symbol.map { unsafeBitCast($0, to: Create.self) }
    }()

    /// The input and output streams (+1 each), which own the socket.
    static func pair(_ descriptor: Int32) -> (UnsafeMutableRawPointer, UnsafeMutableRawPointer)? {
        guard let create else {
            Glibc.close(descriptor)
            return nil
        }
        var input: UnsafeMutableRawPointer?, output: UnsafeMutableRawPointer?
        create(nil, descriptor, &input, &output)
        guard let input, let output else {
            ObjCRuntime.release(input)
            ObjCRuntime.release(output)
            return nil
        }
        return (input, output)
    }
}

enum StreamTasks {
    static func make(session: UnsafeMutableRawPointer, host: String, port: Int) -> NSObject {
        let object = NSURLSessionStreamTask.objCClass.autoreleasedInstance()
        SocketTasks.states.set(object.objcObject, StreamTaskState(session: session, host: host, port: port, object: object.objcObject))
        return object
    }

    static func state(_ object: UnsafeMutableRawPointer) -> StreamTaskState? { SocketTasks.states.get(object) as? StreamTaskState }
}

/// NSURLSessionStreamTask: a TCP connection to a host and port, read and
/// written in order, with TLS when asked.
@ObjCClass("NSURLSessionStreamTask")
open class NSURLSessionStreamTask: NSURLSessionTask {
    private var stream: StreamTaskState? { StreamTasks.state(objcObject) }

    /// The handler: void (^)(NSData *data, BOOL atEOF, NSError *error).
    /// A timeout of 0 waits as long as it takes.
    @ObjCMethod("readDataOfMinLength:maxLength:timeout:completionHandler:")
    func readData(minLength: UInt, maxLength: UInt, timeout: Double, completionHandler: ObjCBlock?) {
        stream?.read(minimum: Int(minLength), maximum: Int(maxLength), timeout: timeout, handler: completionHandler)
    }

    @ObjCMethod("writeData:timeout:completionHandler:")
    func write(_ data: NSData?, timeout: Double, completionHandler: ObjCBlock?) {
        stream?.write(data?.data ?? Data(), timeout: timeout, handler: completionHandler)
    }

    @ObjCMethod("captureStreams") func captureStreams() { stream?.captureStreams() }
    @ObjCMethod("closeWrite") func closeWrite() { stream?.closeWrite() }
    @ObjCMethod("closeRead") func closeRead() { stream?.closeRead() }
    @ObjCMethod("startSecureConnection") func startSecureConnection() { stream?.startSecureConnection() }
    @ObjCMethod("stopSecureConnection") func stopSecureConnection() { stream?.stopSecureConnection() }
}

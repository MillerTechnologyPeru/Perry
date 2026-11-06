import FoundationEssentials
import Glibc
import PerryObjCInterop
import PerryURLLoading

// NSURLConnection over the same URLSession as NSURLSession. A connection's
// delegate hears from it on the run loop of the thread that scheduled it
// (the one that made or started it), or on its delegate queue once it has
// one, as on Darwin. Each event waits until the delegate has seen it, so
// events stay in order. A connection holds itself and its delegate until it
// finishes, fails or is cancelled, and says nothing after -cancel.

@ObjCWrapper("NSThread")
class NSThread: NSObject {
    @ObjCClassMethod("currentThread") static func current() -> NSThread
}

extension NSObject {
    @ObjCMethod("performSelector:onThread:withObject:waitUntilDone:")
    func perform(_ selector: ObjCSelector, on thread: NSThread, with argument: NSObject?, waitUntilDone wait: Bool)
}

/// Runs a closure for a perform onto another thread.
@ObjCClass("_PerryURLConnectionCallback")
final class ConnectionCallback: NSObject {
    static let bodies = StateTable<ClosureBox>()

    @ObjCMethod("run")
    func run() {
        (ConnectionCallback.bodies.get(objcObject)?.body as? () -> Void)?()
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        ConnectionCallback.bodies.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: ConnectionCallback.objCClass.pointer)
    }

    /// Runs `body` on `thread`'s run loop and waits for it.
    static func run(on thread: NSThread, _ body: @escaping () -> Void) {
        let callback = objCClass.autoreleasedInstance()
        bodies.set(callback.objcObject, ClosureBox(body))
        callback.perform(ObjCSelector("run"), on: thread, with: nil, waitUntilDone: true)
    }
}

/// Where a connection's delegate hears from it.
enum Delivery {
    case thread(NSThread)
    case queue(NSOperationQueue)

    func run(_ body: @escaping () -> Void) {
        let pooled = { ObjCRuntime.autoreleasepool(body) }
        switch self {
        case .thread(let thread): ConnectionCallback.run(on: thread, pooled)
        case .queue(let queue): Hops.run(on: queue, pooled)
        }
    }
}

final class ConnectionState: @unchecked Sendable {
    let lock = Lock()
    var original: Request
    var current: Request
    var delegate: NSObject?
    var delivery: Delivery
    var session: Session?
    var task: Task?
    var started = false
    var cancelled = false

    init(request: Request, delegate: NSObject?, delivery: Delivery) {
        original = request
        current = request
        self.delegate = delegate
        self.delivery = delivery
    }

    var isCancelled: Bool { lock.withLock { cancelled } }
}

/// The connection's events, sent on to its delegate.
final class ConnectionEvents: SessionEvents, @unchecked Sendable {
    typealias Object = UnsafeMutableRawPointer?
    let connection: UnsafeMutableRawPointer
    let state: ConnectionState

    init(connection: UnsafeMutableRawPointer, state: ConnectionState) {
        self.connection = connection
        self.state = state
    }

    private var delegate: NSObject? { state.lock.withLock { state.cancelled ? nil : state.delegate } }
    private func send<Function>(_ type: Function.Type) -> Function { unsafeBitCast(ObjCRuntime.msgSend, to: type) }

    /// Runs `body` for the delegate, unless it lacks `name` or the
    /// connection was cancelled.
    private func tell(_ name: String, _ body: @escaping (NSObject, UnsafeRawPointer) -> Void) {
        guard let delegate, delegate.responds(to: name) else { return }
        let delivery = state.lock.withLock { state.delivery }
        delivery.run { [self] in
            guard !state.isCancelled else { return }
            body(delegate, ObjCRuntime.selector(name))
        }
    }

    /// connection:willSendRequest:redirectResponse:, which may change or
    /// refuse the request; without a delegate method, the request as is.
    func willSend(_ request: Request, redirect: Response?) -> Request? {
        let name = "connection:willSendRequest:redirectResponse:"
        guard let delegate, delegate.responds(to: name) else { return request }
        let delivery = state.lock.withLock { state.delivery }
        nonisolated(unsafe) var result: Request? = request
        delivery.run { [self] in
            let answer = send((@convention(c) (Object, UnsafeRawPointer, Object, Object, Object) -> Object).self)(
                delegate.objcObject, ObjCRuntime.selector(name), connection, Requests.object(request).objcObject,
                redirect.map(Responses.object)?.objcObject)
            result = answer.flatMap { Requests.states.get($0) }?.copy()
        }
        return result
    }

    func task(_ task: Task, didReceive response: Response, completion: @escaping @Sendable (Int) -> Void) {
        tell("connection:didReceiveResponse:") { [self] delegate, selector in
            send((@convention(c) (Object, UnsafeRawPointer, Object, Object) -> Void).self)(
                delegate.objcObject, selector, connection, Responses.object(response).objcObject)
        }
        completion(state.isCancelled ? 0 : 1)
    }

    func task(_ task: Task, didReceive data: Data) {
        tell("connection:didReceiveData:") { [self] delegate, selector in
            send((@convention(c) (Object, UnsafeRawPointer, Object, Object) -> Void).self)(
                delegate.objcObject, selector, connection, NSData.of(data).objcObject)
        }
    }

    func task(_ task: Task, willRedirect response: Response, to request: Request,
              completion: @escaping @Sendable (Request?) -> Void) {
        completion(willSend(request, redirect: response))
    }

    func task(_ task: Task, didSend bytes: Int64, total: Int64, expected: Int64) {
        tell("connection:didSendBodyData:totalBytesWritten:totalBytesExpectedToWrite:") { [self] delegate, selector in
            send((@convention(c) (Object, UnsafeRawPointer, Object, Int, Int, Int) -> Void).self)(
                delegate.objcObject, selector, connection, Int(bytes), Int(total), Int(expected))
        }
    }

    func task(_ task: Task, didWrite bytes: Int64, total: Int64, expected: Int64) {}
    func task(_ task: Task, didFinishDownloadingTo location: URL) {}

    func task(_ task: Task, didCompleteWith error: Failure?) {
        if let error {
            tell("connection:didFailWithError:") { [self] delegate, selector in
                send((@convention(c) (Object, UnsafeRawPointer, Object, Object) -> Void).self)(
                    delegate.objcObject, selector, connection, Errors.object(error)?.objcObject)
            }
        } else {
            tell("connectionDidFinishLoading:") { [self] delegate, selector in
                send((@convention(c) (Object, UnsafeRawPointer, Object) -> Void).self)(delegate.objcObject, selector, connection)
            }
        }
        Connections.finish(connection)
    }

    func sessionDidBecomeInvalid(_ error: Failure?) {}

    /// connection:willSendRequestForAuthenticationChallenge:, else
    /// connection:didReceiveAuthenticationChallenge: when the delegate can
    /// authenticate against the space; else default handling.
    func task(_ task: Task, didReceive challenge: Challenge, completion: @escaping @Sendable (Int, Credential?) -> Void) {
        let answer: @Sendable (Int, Credential?) -> Void = { disposition, credential in
            guard disposition == 1 else { return completion(disposition, credential) }
            let (fallback, stored) = CredentialStorage.defaultAnswer(challenge)
            completion(fallback, stored)
        }
        guard let delegate else { return answer(1, nil) }
        let name: String
        if delegate.responds(to: "connection:willSendRequestForAuthenticationChallenge:") {
            name = "connection:willSendRequestForAuthenticationChallenge:"
        } else if delegate.responds(to: "connection:didReceiveAuthenticationChallenge:") {
            name = "connection:didReceiveAuthenticationChallenge:"
        } else {
            return answer(1, nil)
        }
        let delivery = state.lock.withLock { state.delivery }
        delivery.run { [self] in
            guard !state.isCancelled else { return answer(2, nil) }
            let object = Challenges.object(challenge, answer: SenderState(answer, challenge: challenge))
            let check = "connection:canAuthenticateAgainstProtectionSpace:"
            if name.hasPrefix("connection:didReceive"), delegate.responds(to: check),
               let space = Challenges.states.get(object.objcObject)?.space,
               !send((@convention(c) (Object, UnsafeRawPointer, Object, Object) -> Bool).self)(
                   delegate.objcObject, ObjCRuntime.selector(check), connection, space.objcObject) {
                return answer(1, nil)
            }
            send((@convention(c) (Object, UnsafeRawPointer, Object, Object) -> Void).self)(
                delegate.objcObject, ObjCRuntime.selector(name), connection, object.objcObject)
        }
    }
}

enum Connections {
    static let states = StateTable<ConnectionState>()

    /// Starts loading: asks the delegate about the first request, then
    /// runs the task. The connection holds itself until it finishes.
    static func start(_ connection: UnsafeMutableRawPointer) {
        guard let state = states.get(connection) else { return }
        let begin = state.lock.withLock { () -> Bool in
            guard !state.started, !state.cancelled else { return false }
            state.started = true
            return true
        }
        guard begin else { return }
        _ = ObjCRuntime.retain(connection)
        let events = ConnectionEvents(connection: connection, state: state)
        nonisolated(unsafe) let connection = connection
        // The thread the connection is scheduled on runs this first message
        // after the caller returns, as Darwin's run loop source does.
        let pending = { @Sendable in
            guard let request = events.willSend(state.original, redirect: nil) else {
                finish(connection)
                return
            }
            let session = Session(configuration: .makeDefault(), events: events)
            let task = session.dataTask(request)
            let go = state.lock.withLock { () -> Bool in
                state.current = request
                state.session = session
                state.task = task
                return !state.cancelled
            }
            if go { task.resume() } else { finish(connection) }
        }
        Thread.detach(pending)
    }

    /// Drops the connection's hold on itself and its delegate.
    static func finish(_ connection: UnsafeMutableRawPointer) {
        guard let state = states.get(connection) else { return }
        let session = state.lock.withLock { () -> Session? in
            defer {
                state.delegate = nil
                state.session = nil
            }
            return state.session
        }
        session?.finishTasksAndInvalidate()
        ObjCRuntime.release(connection)
    }

    /// The thread a connection made or started now delivers to.
    static func currentDelivery() -> Delivery { .thread(NSThread.current()) }
}

/// A detached pthread for one closure.
enum Thread {
    final class Work {
        let body: @Sendable () -> Void
        init(_ body: @escaping @Sendable () -> Void) { self.body = body }
    }

    static func detach(_ body: @escaping @Sendable () -> Void) {
        var handle = pthread_t()
        let work = Unmanaged.passRetained(Work(body)).toOpaque()
        let result = pthread_create(&handle, nil, { context in
            guard let context else { return nil }
            let work = Unmanaged<Work>.fromOpaque(context).takeRetainedValue()
            keepingLinuxRegisters { work.body() }
            return nil
        }, work)
        if result == 0 { pthread_detach(handle) } else { Unmanaged<Work>.fromOpaque(work).release() }
    }
}

/// NSURLConnection.
@ObjCClass("NSURLConnection")
open class NSURLConnection: NSObject {
    var state: ConnectionState? { Connections.states.get(objcObject) }

    @ObjCMethod("dealloc")
    func dealloc() {
        Connections.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSURLConnection.objCClass.pointer)
    }

    @ObjCClassMethod("connectionWithRequest:delegate:")
    static func make(_ cls: ObjCClass, request: NSObject, delegate: NSObject?) -> NSObject {
        let connection = cls.autoreleasedInstance()
        Connections.states.set(connection.objcObject, ConnectionState(
            request: Requests.request(request.objcObject).copy(), delegate: delegate, delivery: Connections.currentDelivery()))
        Connections.start(connection.objcObject)
        return connection
    }

    @ObjCMethod("initWithRequest:delegate:")
    func initialize(request: NSObject, delegate: NSObject?) -> Self {
        initialize(request: request, delegate: delegate, startImmediately: true)
    }

    @ObjCMethod("initWithRequest:delegate:startImmediately:")
    func initialize(request: NSObject, delegate: NSObject?, startImmediately: Bool) -> Self {
        Connections.states.set(objcObject, ConnectionState(
            request: Requests.request(request.objcObject).copy(), delegate: delegate, delivery: Connections.currentDelivery()))
        if startImmediately { Connections.start(objcObject) }
        return self
    }

    @ObjCMethod("start") func start() { Connections.start(objcObject) }

    @ObjCMethod("cancel")
    func cancel() {
        guard let state else { return }
        let (task, started) = state.lock.withLock { () -> (Task?, Bool) in
            let wasCancelled = state.cancelled
            state.cancelled = true
            return (state.task, state.started && !wasCancelled)
        }
        task?.cancel()
        // A cancelled load says nothing more; its hold on itself goes now.
        if started && task != nil { Connections.finish(objcObject) }
    }

    @ObjCMethod("scheduleInRunLoop:forMode:")
    func schedule(in runLoop: NSObject, forMode mode: NSObject?) {
        state?.lock.withLock { state?.delivery = Connections.currentDelivery() }
    }

    @ObjCMethod("unscheduleFromRunLoop:forMode:") func unschedule(from runLoop: NSObject, forMode mode: NSObject?) {}

    @ObjCMethod("setDelegateQueue:")
    func setDelegateQueue(_ queue: NSOperationQueue?) {
        guard let state else { return }
        state.lock.withLock { state.delivery = queue.map { .queue($0) } ?? Connections.currentDelivery() }
    }

    @ObjCMethod("originalRequest")
    func originalRequest() -> NSObject? {
        guard let state else { return nil }
        return Requests.object(state.lock.withLock { state.original })
    }

    @ObjCMethod("currentRequest")
    func currentRequest() -> NSObject? {
        guard let state else { return nil }
        return Requests.object(state.lock.withLock { state.current })
    }

    @ObjCClassMethod("canHandleRequest:")
    static func canHandle(_ request: NSObject) -> Bool {
        let scheme = Requests.request(request.objcObject).url?.scheme?.lowercased() ?? ""
        return ["http", "https", "data", "file"].contains(scheme)
    }

    /// The session the class methods load in, shared and never
    /// invalidated, as a session per load would make and tear down a
    /// transfer engine each time.
    private static let oneShotSession = Session(configuration: .makeDefault(), events: nil)

    /// Loads at once on the calling thread, which waits, no longer than the
    /// request's timeout (and a moment more for the engine's own): then the
    /// load is cancelled and fails with NSURLErrorTimedOut, as on Darwin.
    @ObjCClassMethod("sendSynchronousRequest:returningResponse:error:")
    static func sendSynchronous(_ request: NSObject, returningResponse response: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
                                error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> NSData? {
        /// The load's outcome, and a semaphore it posts; the completion
        /// keeps both, as it may come after the caller stopped waiting.
        final class Outcome: @unchecked Sendable {
            let done = UnsafeMutablePointer<sem_t>.allocate(capacity: 1)
            var data: Data?
            var response: Response?
            var failure: Failure?
            init() { sem_init(done, 0, 0) }
            deinit {
                sem_destroy(done)
                done.deallocate()
            }
        }
        let outcome = Outcome()
        let load = Requests.request(request.objcObject).copy()
        let task = oneShotSession.dataTask(load) { data, response, failure in
            outcome.data = data
            outcome.response = response
            outcome.failure = failure
            sem_post(outcome.done)
        }
        task.resume()

        let timeout = load.timeout > 0 ? load.timeout : 60
        var deadline = timespec()
        clock_gettime(CLOCK_REALTIME, &deadline)
        let end = Double(deadline.tv_sec) + Double(deadline.tv_nsec) / 1e9 + timeout + 5
        deadline.tv_sec = Int(end)
        deadline.tv_nsec = Int((end - end.rounded(.down)) * 1e9)
        var finished = true
        while sem_timedwait(outcome.done, &deadline) != 0 {
            guard errno == EINTR else {
                finished = false
                break
            }
        }
        if !finished {
            task.cancel()
            response?.pointee = nil
            error?.pointee = Errors.object(Failure.timedOut(url: load.url))?.objcObject
            return nil
        }
        response?.pointee = outcome.response.map(Responses.object)?.objcObject
        error?.pointee = Errors.object(outcome.failure)?.objcObject
        return outcome.failure == nil ? NSMutableData.mutable(outcome.data ?? Data()) : nil
    }

    /// Loads, then runs the handler on `queue`: (response, data, error).
    @ObjCClassMethod("sendAsynchronousRequest:queue:completionHandler:")
    static func sendAsynchronous(_ request: NSObject, queue: NSOperationQueue, completionHandler: ObjCBlock) {
        nonisolated(unsafe) let queue = queue
        nonisolated(unsafe) let block = completionHandler
        oneShotSession.dataTask(Requests.request(request.objcObject).copy()) { data, response, failure in
            Hops.run(on: queue) {
                ObjCRuntime.autoreleasepool {
                    Blocks.call(block, response.map(Responses.object)?.objcObject,
                                failure == nil ? NSData.of(data ?? Data()).objcObject : nil,
                                Errors.object(failure)?.objcObject)
                }
            }
        }.resume()
    }
}

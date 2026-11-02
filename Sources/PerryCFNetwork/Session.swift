import FoundationEssentials
import PerryObjCInterop
import PerryURLLoading

// NSURLSession over corelibs' URLSession. A session's delegate and its
// tasks' completion handlers run on the session's delegate queue, an
// NSOperationQueue (a serial one the session makes when given none), as on
// Darwin: each event corelibs delivers on its own queue hops to that one.

/// NSURLErrorDomain and its keys.
@ObjCConstants
enum ErrorKeys {
    static let NSURLErrorDomain = "NSURLErrorDomain"
    static let NSURLErrorFailingURLErrorKey = "NSErrorFailingURLKey"
    static let NSURLErrorFailingURLStringErrorKey = "NSErrorFailingURLStringKey"
    static let NSErrorFailingURLStringKey = "NSErrorFailingURLStringKey"
    static let NSURLErrorFailingURLPeerTrustErrorKey = "NSURLErrorFailingURLPeerTrustErrorKey"
    static let NSURLErrorBackgroundTaskCancelledReasonKey = "NSURLErrorBackgroundTaskCancelledReasonKey"
    static let NSURLErrorNetworkUnavailableReasonKey = "NSURLErrorNetworkUnavailableReasonKey"
    static let NSURLSessionDownloadTaskResumeData = "NSURLSessionDownloadTaskResumeData"
}

enum Errors {
    /// An NSError for a failed load, with the failing URL in its user info.
    static func object(_ failure: Failure?) -> NSError? {
        guard let failure else { return nil }
        var info: [(String, NSObject)] = [("NSLocalizedDescription", NSObject.string(failure.description))]
        if let url = failure.failingURL, let object = NSURL.of(url) {
            info.append((ErrorKeys.NSURLErrorFailingURLErrorKey, object))
            info.append((ErrorKeys.NSURLErrorFailingURLStringErrorKey, NSObject.string(url.absoluteString)))
        }
        return NSError.make(domain: failure.domain, code: failure.code, userInfo: NSMutableDictionary.of(info))
    }
}

// MARK: - Configurations

enum Configurations {
    static let states = StateTable<Configuration>()

    static func configuration(_ object: UnsafeMutableRawPointer) -> Configuration {
        if let configuration = states.get(object) { return configuration }
        let configuration = Configuration.makeDefault()
        states.set(object, configuration)
        return configuration
    }

    static func object(_ configuration: Configuration) -> NSObject {
        let object = NSURLSessionConfiguration.objCClass.autoreleasedInstance()
        states.set(object.objcObject, configuration)
        return object
    }
}

/// NSURLSessionConfiguration.
@ObjCClass("NSURLSessionConfiguration")
open class NSURLSessionConfiguration: NSObject {
    var configuration: Configuration { Configurations.configuration(objcObject) }

    @ObjCMethod("dealloc")
    func dealloc() {
        Configurations.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSURLSessionConfiguration.objCClass.pointer)
    }

    @ObjCClassMethod("defaultSessionConfiguration")
    static func makeDefault() -> NSObject { Configurations.object(.makeDefault()) }

    @ObjCClassMethod("ephemeralSessionConfiguration")
    static func makeEphemeral() -> NSObject { Configurations.object(.makeEphemeral()) }

    @ObjCClassMethod("backgroundSessionConfigurationWithIdentifier:")
    static func makeBackground(identifier: String) -> NSObject { Configurations.object(.makeBackground(identifier: identifier)) }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
        ObjCRuntime.retain(Configurations.object(configuration.copy()).objcObject)!
    }

    @ObjCMethod("identifier") func identifier() -> String? { configuration.identifier }
    @ObjCMethod("timeoutIntervalForRequest") func timeoutForRequest() -> Double { configuration.timeoutForRequest }
    @ObjCMethod("setTimeoutIntervalForRequest:") func setTimeoutForRequest(_ value: Double) { configuration.timeoutForRequest = value }
    @ObjCMethod("timeoutIntervalForResource") func timeoutForResource() -> Double { configuration.timeoutForResource }
    @ObjCMethod("setTimeoutIntervalForResource:") func setTimeoutForResource(_ value: Double) { configuration.timeoutForResource = value }

    @ObjCMethod("HTTPAdditionalHeaders")
    func additionalHeaders() -> NSDictionary? {
        configuration.additionalHeaders.map { headers in
            NSMutableDictionary.of(headers.sorted { $0.key < $1.key }.map { ($0.key, NSObject.string($0.value)) })
        }
    }

    @ObjCMethod("setHTTPAdditionalHeaders:")
    func setAdditionalHeaders(_ headers: NSDictionary?) { configuration.additionalHeaders = headers?.strings }

    @ObjCMethod("HTTPShouldSetCookies") func setsCookies() -> Bool { configuration.setsCookies }
    @ObjCMethod("setHTTPShouldSetCookies:") func setSetsCookies(_ value: Bool) { configuration.setsCookies = value }
    @ObjCMethod("HTTPCookieAcceptPolicy") func cookieAcceptPolicy() -> UInt { UInt(configuration.cookieAcceptPolicy) }
    @ObjCMethod("setHTTPCookieAcceptPolicy:") func setCookieAcceptPolicy(_ value: UInt) { configuration.cookieAcceptPolicy = Int(value) }

    @ObjCMethod("HTTPCookieStorage")
    func cookieStorage() -> NSObject? { configuration.usesCookieStorage ? NSHTTPCookieStorage.sharedStorage() : nil }

    @ObjCMethod("setHTTPCookieStorage:")
    func setCookieStorage(_ storage: NSObject?) { configuration.usesCookieStorage = storage != nil }

    @ObjCMethod("URLCache") func urlCache() -> NSObject? { configuration.hasURLCache ? NSURLCache.sharedCache() : nil }
    @ObjCMethod("setURLCache:") func setURLCache(_ cache: NSObject?) {}

    @ObjCMethod("requestCachePolicy") func requestCachePolicy() -> UInt { UInt(configuration.requestCachePolicy) }
    @ObjCMethod("setRequestCachePolicy:") func setRequestCachePolicy(_ value: UInt) { configuration.requestCachePolicy = Int(value) }
    @ObjCMethod("HTTPMaximumConnectionsPerHost") func maximumConnections() -> Int { configuration.maximumConnectionsPerHost }
    @ObjCMethod("setHTTPMaximumConnectionsPerHost:")
    func setMaximumConnections(_ value: Int) { configuration.maximumConnectionsPerHost = value }
    @ObjCMethod("allowsCellularAccess") func allowsCellularAccess() -> Bool { configuration.allowsCellularAccess }
    @ObjCMethod("setAllowsCellularAccess:") func setAllowsCellularAccess(_ value: Bool) { configuration.allowsCellularAccess = value }
    @ObjCMethod("waitsForConnectivity") func waitsForConnectivity() -> Bool { configuration.waitsForConnectivity }
    @ObjCMethod("setWaitsForConnectivity:") func setWaitsForConnectivity(_ value: Bool) { configuration.waitsForConnectivity = value }
    @ObjCMethod("HTTPShouldUsePipelining") func usesPipelining() -> Bool { configuration.usesPipelining }
    @ObjCMethod("setHTTPShouldUsePipelining:") func setUsesPipelining(_ value: Bool) { configuration.usesPipelining = value }
    @ObjCMethod("protocolClasses") func protocolClasses() -> NSArray { NSMutableArray.of([]) }
    @ObjCMethod("setProtocolClasses:") func setProtocolClasses(_ classes: NSArray?) {}
}

/// NSURLCache: the shared cache's interface. corelibs keeps its own cache;
/// this one stores nothing.
@ObjCClass("NSURLCache")
open class NSURLCache: NSObject {
    nonisolated(unsafe) static var shared: NSObject?

    @ObjCClassMethod("sharedURLCache")
    static func sharedCache() -> NSObject {
        if let shared { return shared }
        let cache = objCClass.object.newInstance()
        shared = cache
        return cache
    }

    @ObjCClassMethod("setSharedURLCache:") static func setShared(_ cache: NSObject?) {}

    @ObjCMethod("initWithMemoryCapacity:diskCapacity:diskPath:")
    func initialize(memoryCapacity: UInt, diskCapacity: UInt, diskPath: String?) -> Self { self }

    @ObjCMethod("memoryCapacity") func memoryCapacity() -> UInt { 512_000 }
    @ObjCMethod("diskCapacity") func diskCapacity() -> UInt { 10_000_000 }
    @ObjCMethod("currentMemoryUsage") func currentMemoryUsage() -> UInt { 0 }
    @ObjCMethod("currentDiskUsage") func currentDiskUsage() -> UInt { 0 }
    @ObjCMethod("cachedResponseForRequest:") func cachedResponse(for request: NSObject) -> NSObject? { nil }
    @ObjCMethod("removeAllCachedResponses") func removeAllCachedResponses() {}
    @ObjCMethod("removeCachedResponseForRequest:") func removeCachedResponse(for request: NSObject) {}
}

// MARK: - Tasks

/// A task's Swift side and its completion handler.
final class TaskState {
    let task: Task

    init(_ task: Task) {
        self.task = task
    }
}

enum Tasks {
    static let states = StateTable<TaskState>()

    static func task(_ object: UnsafeMutableRawPointer) -> Task? { states.get(object)?.task }

    /// The object for a task (+0); the session holds another reference
    /// until the task completes, as Darwin's does.
    static func object(_ task: Task) -> NSObject {
        let cls: ObjCClass
        switch task.kind {
        case .data: cls = NSURLSessionDataTask.objCClass
        case .upload: cls = NSURLSessionUploadTask.objCClass
        case .download: cls = NSURLSessionDownloadTask.objCClass
        }
        let object = cls.autoreleasedInstance()
        states.set(object.objcObject, TaskState(task))
        task.owner = ObjCRuntime.retain(object.objcObject)
        return object
    }

    /// Drops the session's reference, when the task completes.
    static func finish(_ task: Task) {
        task.markCompleted()
        guard let owner = task.owner else { return }
        task.owner = nil
        ObjCRuntime.release(owner)
    }
}

/// NSURLSessionTask.
@ObjCClass("NSURLSessionTask")
open class NSURLSessionTask: NSObject {
    var task: Task? { Tasks.task(objcObject) }

    @ObjCMethod("dealloc")
    func dealloc() {
        Tasks.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSURLSessionTask.objCClass.pointer)
    }

    @ObjCMethod("taskIdentifier") func taskIdentifier() -> UInt { UInt(task?.identifier ?? 0) }
    @ObjCMethod("state") func state() -> Int { task?.state ?? 3 }
    @ObjCMethod("originalRequest") func originalRequest() -> NSObject? { task?.originalRequest.map { Requests.object($0) } }
    @ObjCMethod("currentRequest") func currentRequest() -> NSObject? { task?.currentRequest.map { Requests.object($0) } }
    @ObjCMethod("response") func response() -> NSObject? { task?.response.map(Responses.object) }
    @ObjCMethod("error") func error() -> NSError? { Errors.object(task?.error) }
    @ObjCMethod("countOfBytesReceived") func countOfBytesReceived() -> Int64 { task?.bytesReceived ?? 0 }
    @ObjCMethod("countOfBytesSent") func countOfBytesSent() -> Int64 { task?.bytesSent ?? 0 }
    @ObjCMethod("countOfBytesExpectedToReceive") func countOfBytesExpectedToReceive() -> Int64 { task?.bytesExpectedToReceive ?? 0 }
    @ObjCMethod("countOfBytesExpectedToSend") func countOfBytesExpectedToSend() -> Int64 { task?.bytesExpectedToSend ?? 0 }
    @ObjCMethod("taskDescription") func taskDescription() -> String? { task?.taskDescription }
    @ObjCMethod("setTaskDescription:") func setTaskDescription(_ text: String?) { task?.taskDescription = text }
    @ObjCMethod("priority") func priority() -> Float { task?.priority ?? 0.5 }
    @ObjCMethod("setPriority:") func setPriority(_ priority: Float) { task?.priority = priority }
    @ObjCMethod("resume") func resume() { task?.resume() }
    @ObjCMethod("suspend") func suspend() { task?.suspend() }
    @ObjCMethod("cancel") func cancel() { task?.cancel() }
}

@ObjCClass("NSURLSessionDataTask") open class NSURLSessionDataTask: NSURLSessionTask {}
@ObjCClass("NSURLSessionUploadTask") open class NSURLSessionUploadTask: NSURLSessionDataTask {}
@ObjCClass("NSURLSessionDownloadTask") open class NSURLSessionDownloadTask: NSURLSessionTask {}

// MARK: - Delegates

/// Sends a session's events to its Objective-C delegate on its queue.
final class DelegateEvents: SessionEvents, @unchecked Sendable {
    typealias Object = UnsafeMutableRawPointer?
    /// The NSURLSession, unretained: the session outlives its events.
    let session: UnsafeMutableRawPointer
    let delegate: NSObject
    let queue: NSOperationQueue

    init(session: UnsafeMutableRawPointer, delegate: NSObject, queue: NSOperationQueue) {
        self.session = session
        self.delegate = delegate
        self.queue = queue
    }

    private func responds(_ selector: String) -> Bool { delegate.responds(to: selector) }
    private func selector(_ name: String) -> UnsafeRawPointer { ObjCRuntime.selector(name) }
    private func send<Function>(_ type: Function.Type) -> Function { unsafeBitCast(ObjCRuntime.msgSend, to: type) }

    private func run(_ body: @escaping () -> Void) {
        Hops.run(on: queue) { ObjCRuntime.autoreleasepool(body) }
    }

    func task(_ task: Task, didReceive response: Response, completion: @escaping @Sendable (Int) -> Void) {
        let name = "URLSession:dataTask:didReceiveResponse:completionHandler:"
        guard responds(name) else { return completion(1) }
        run { [self] in
            let block = Closures.block(integer: completion)
            send((@convention(c) (Object, UnsafeRawPointer, Object, Object, Object, Object) -> Void).self)(
                delegate.objcObject, selector(name), session, task.owner, Responses.object(response).objcObject,
                block.objcObject)
        }
    }

    func task(_ task: Task, didReceive data: Data) {
        let name = "URLSession:dataTask:didReceiveData:"
        guard responds(name) else { return }
        run { [self] in
            send((@convention(c) (Object, UnsafeRawPointer, Object, Object, Object) -> Void).self)(
                delegate.objcObject, selector(name), session, task.owner, NSData.of(data).objcObject)
        }
    }

    func task(_ task: Task, willRedirect response: Response, to request: Request,
              completion: @escaping @Sendable (Request?) -> Void) {
        let name = "URLSession:task:willPerformHTTPRedirection:newRequest:completionHandler:"
        guard responds(name) else { return completion(request) }
        run { [self] in
            let block = Closures.block(object: { object in completion(object.flatMap { Requests.states.get($0) }) })
            send((@convention(c) (Object, UnsafeRawPointer, Object, Object, Object, Object, Object) -> Void).self)(
                delegate.objcObject, selector(name), session, task.owner, Responses.object(response).objcObject,
                Requests.object(request).objcObject, block.objcObject)
        }
    }

    func task(_ task: Task, didSend bytes: Int64, total: Int64, expected: Int64) {
        let name = "URLSession:task:didSendBodyData:totalBytesSent:totalBytesExpectedToSend:"
        guard responds(name) else { return }
        run { [self] in
            send((@convention(c) (Object, UnsafeRawPointer, Object, Object, Int64, Int64, Int64) -> Void).self)(
                delegate.objcObject, selector(name), session, task.owner, bytes, total, expected)
        }
    }

    func task(_ task: Task, didWrite bytes: Int64, total: Int64, expected: Int64) {
        let name = "URLSession:downloadTask:didWriteData:totalBytesWritten:totalBytesExpectedToWrite:"
        guard responds(name) else { return }
        run { [self] in
            send((@convention(c) (Object, UnsafeRawPointer, Object, Object, Int64, Int64, Int64) -> Void).self)(
                delegate.objcObject, selector(name), session, task.owner, bytes, total, expected)
        }
    }

    func task(_ task: Task, didFinishDownloadingTo location: URL) {
        let name = "URLSession:downloadTask:didFinishDownloadingToURL:"
        guard responds(name) else { return }
        run { [self] in
            send((@convention(c) (Object, UnsafeRawPointer, Object, Object, Object) -> Void).self)(
                delegate.objcObject, selector(name), session, task.owner, NSURL.of(location)?.objcObject)
        }
    }

    func task(_ task: Task, didCompleteWith error: Failure?) {
        let name = "URLSession:task:didCompleteWithError:"
        if responds(name) {
            run { [self] in
                send((@convention(c) (Object, UnsafeRawPointer, Object, Object, Object) -> Void).self)(
                    delegate.objcObject, selector(name), session, task.owner, Errors.object(error)?.objcObject)
            }
        }
        Tasks.finish(task)
    }

    func sessionDidBecomeInvalid(_ error: Failure?) {
        let name = "URLSession:didBecomeInvalidWithError:"
        if responds(name) {
            run { [self] in
                send((@convention(c) (Object, UnsafeRawPointer, Object, Object) -> Void).self)(
                    delegate.objcObject, selector(name), session, Errors.object(error)?.objcObject)
            }
        }
        Sessions.invalidated(session)
    }
}

// MARK: - Sessions

final class SessionState {
    let session: Session
    let queue: NSOperationQueue
    let configuration: NSObject
    /// Held until the session is invalidated, as Darwin holds it.
    var delegate: NSObject?

    init(session: Session, queue: NSOperationQueue, configuration: NSObject, delegate: NSObject?) {
        self.session = session
        self.queue = queue
        self.configuration = configuration
        self.delegate = delegate
    }
}

enum Sessions {
    static let states = StateTable<SessionState>()
    nonisolated(unsafe) static var shared: NSObject?

    static func state(_ object: UnsafeMutableRawPointer) -> SessionState? { states.get(object) }

    /// A serial queue for a session given none.
    static func serialQueue() -> NSOperationQueue {
        let queue = ObjCClass(named: "NSOperationQueue").object.newInstance().unsafeCast(to: NSOperationQueue.self)
        queue.setMaxConcurrentOperationCount(1)
        return queue
    }

    static func make(_ cls: ObjCClass, configuration: NSObject, delegate: NSObject?, queue: NSOperationQueue?) -> NSObject {
        let object = cls.autoreleasedInstance()
        let queue = queue ?? serialQueue()
        let copy = Configurations.configuration(configuration.objcObject).copy()
        let events = delegate.map { DelegateEvents(session: object.objcObject, delegate: $0, queue: queue) }
        let session = Session(configuration: copy, events: events)
        states.set(object.objcObject, SessionState(session: session, queue: queue, configuration: Configurations.object(copy),
                                                    delegate: delegate))
        return object
    }

    static func invalidated(_ session: UnsafeMutableRawPointer) {
        state(session)?.delegate = nil
    }
}

/// NSURLSession.
@ObjCClass("NSURLSession")
open class NSURLSession: NSObject {
    var state: SessionState? { Sessions.state(objcObject) }

    @ObjCMethod("dealloc")
    func dealloc() {
        Sessions.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSURLSession.objCClass.pointer)
    }

    /// The shared session, which is never invalidated.
    @ObjCClassMethod("sharedSession")
    static func sharedSession() -> NSObject {
        if let shared = Sessions.shared { return shared }
        let session = Sessions.make(objCClass, configuration: NSURLSessionConfiguration.makeDefault(), delegate: nil, queue: nil)
        Sessions.shared = session
        return session
    }

    @ObjCClassMethod("sessionWithConfiguration:")
    static func make(_ cls: ObjCClass, configuration: NSObject) -> NSObject {
        Sessions.make(cls, configuration: configuration, delegate: nil, queue: nil)
    }

    @ObjCClassMethod("sessionWithConfiguration:delegate:delegateQueue:")
    static func make(_ cls: ObjCClass, configuration: NSObject, delegate: NSObject?, delegateQueue: NSOperationQueue?) -> NSObject {
        Sessions.make(cls, configuration: configuration, delegate: delegate, queue: delegateQueue)
    }

    @ObjCMethod("configuration") func configuration() -> NSObject? { state?.configuration }
    @ObjCMethod("delegate") func delegate() -> NSObject? { state?.delegate }
    @ObjCMethod("delegateQueue") func delegateQueue() -> NSOperationQueue? { state?.queue }
    @ObjCMethod("sessionDescription") func sessionDescription() -> String? { state?.session.sessionDescription }
    @ObjCMethod("setSessionDescription:") func setSessionDescription(_ text: String?) { state?.session.sessionDescription = text }

    @ObjCMethod("finishTasksAndInvalidate")
    func finishTasksAndInvalidate() {
        guard objcObject != Sessions.shared?.objcObject else { return }
        state?.session.finishTasksAndInvalidate()
    }

    @ObjCMethod("invalidateAndCancel")
    func invalidateAndCancel() {
        guard objcObject != Sessions.shared?.objcObject else { return }
        state?.session.invalidateAndCancel()
    }

    // MARK: Completion handlers

    /// A data or upload completion handler, run on the delegate queue.
    private func dataCompletion(_ handler: ObjCBlock?) -> BoxedCompletion? {
        guard let handler, let state else { return nil }
        nonisolated(unsafe) let queue = state.queue
        let box = TaskBox()
        nonisolated(unsafe) let block = handler
        let body: Session.DataCompletion = { data, response, error in
            box.task?.markCompleted()
            Hops.run(on: queue) {
                ObjCRuntime.autoreleasepool {
                    Blocks.call(block, data.map(NSData.of)?.objcObject, response.map(Responses.object)?.objcObject,
                                Errors.object(error)?.objcObject)
                }
            }
            if let finished = box.task { Tasks.finish(finished) }
        }
        return BoxedCompletion(body: body, box: box)
    }

    private func dataTask(_ make: (Session.DataCompletion?) -> Task, _ handler: ObjCBlock?) -> NSObject {
        let completion = dataCompletion(handler)
        let box = completion?.box
        let task = make(completion?.body)
        box?.task = task
        return Tasks.object(task)
    }

    private func request(_ url: NSURL) -> Request { Request(url: url.url) }
    private func request(_ object: NSObject) -> Request { Requests.request(object.objcObject).copy() }

    @ObjCMethod("dataTaskWithURL:")
    func dataTask(with url: NSURL) -> NSObject { dataTask({ state!.session.dataTask(request(url), completion: $0) }, nil) }

    @ObjCMethod("dataTaskWithRequest:")
    func dataTask(with request: NSObject) -> NSObject {
        dataTask({ state!.session.dataTask(self.request(request), completion: $0) }, nil)
    }

    @ObjCMethod("dataTaskWithURL:completionHandler:")
    func dataTask(with url: NSURL, completionHandler: ObjCBlock?) -> NSObject {
        dataTask({ state!.session.dataTask(request(url), completion: $0) }, completionHandler)
    }

    @ObjCMethod("dataTaskWithRequest:completionHandler:")
    func dataTask(with request: NSObject, completionHandler: ObjCBlock?) -> NSObject {
        dataTask({ state!.session.dataTask(self.request(request), completion: $0) }, completionHandler)
    }

    @ObjCMethod("uploadTaskWithRequest:fromData:")
    func uploadTask(with request: NSObject, from data: NSData) -> NSObject {
        dataTask({ state!.session.uploadTask(self.request(request), data: data.data, completion: $0) }, nil)
    }

    @ObjCMethod("uploadTaskWithRequest:fromData:completionHandler:")
    func uploadTask(with request: NSObject, from data: NSData?, completionHandler: ObjCBlock?) -> NSObject {
        dataTask({ state!.session.uploadTask(self.request(request), data: data?.data ?? Data(), completion: $0) },
                 completionHandler)
    }

    @ObjCMethod("uploadTaskWithRequest:fromFile:")
    func uploadTask(with request: NSObject, fromFile file: NSURL) -> NSObject {
        dataTask({ state!.session.uploadTask(self.request(request), file: file.url!, completion: $0) }, nil)
    }

    @ObjCMethod("uploadTaskWithRequest:fromFile:completionHandler:")
    func uploadTask(with request: NSObject, fromFile file: NSURL, completionHandler: ObjCBlock?) -> NSObject {
        dataTask({ state!.session.uploadTask(self.request(request), file: file.url!, completion: $0) }, completionHandler)
    }

    /// A download's handler runs before the file is removed.
    private func downloadTask(_ request: Request, _ handler: ObjCBlock?) -> NSObject {
        guard let handler, let state else { return Tasks.object(self.state!.session.downloadTask(request)) }
        nonisolated(unsafe) let queue = state.queue
        let box = TaskBox()
        nonisolated(unsafe) let block = handler
        let task = state.session.downloadTask(request) { location, response, error in
            box.task?.markCompleted()
            Hops.run(on: queue) {
                ObjCRuntime.autoreleasepool {
                    Blocks.call(block, location.flatMap(NSURL.of)?.objcObject, response.map(Responses.object)?.objcObject,
                                Errors.object(error)?.objcObject)
                }
            }
            if let finished = box.task { Tasks.finish(finished) }
        }
        box.task = task
        return Tasks.object(task)
    }

    @ObjCMethod("downloadTaskWithURL:") func downloadTask(with url: NSURL) -> NSObject { downloadTask(request(url), nil) }
    @ObjCMethod("downloadTaskWithRequest:") func downloadTask(with request: NSObject) -> NSObject {
        downloadTask(self.request(request), nil)
    }

    @ObjCMethod("downloadTaskWithURL:completionHandler:")
    func downloadTask(with url: NSURL, completionHandler: ObjCBlock?) -> NSObject { downloadTask(request(url), completionHandler) }

    @ObjCMethod("downloadTaskWithRequest:completionHandler:")
    func downloadTask(with request: NSObject, completionHandler: ObjCBlock?) -> NSObject {
        downloadTask(self.request(request), completionHandler)
    }
}

/// The task a completion handler belongs to, known once the task is made.
final class TaskBox: @unchecked Sendable {
    var task: Task?
}

/// A completion handler with the box its task goes in.
struct BoxedCompletion {
    let body: Session.DataCompletion
    let box: TaskBox
}

import FoundationEssentials
import Glibc
import PerryInterface
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

/// NSURLSession's numeric constants.
@ObjCConstants
enum SessionNumbers {
    static let NSURLSessionTransferSizeUnknown: Int64 = -1
    static let NSURLSessionTaskPriorityDefault: Float = 0.5
    static let NSURLSessionTaskPriorityLow: Float = 0.25
    static let NSURLSessionTaskPriorityHigh: Float = 0.75
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

    /// The deprecated name of +backgroundSessionConfigurationWithIdentifier:.
    @ObjCClassMethod("backgroundSessionConfiguration:")
    static func makeBackground(deprecatedIdentifier identifier: String) -> NSObject {
        Configurations.object(.makeBackground(identifier: identifier))
    }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
        ObjCRuntime.retain(Configurations.object(configuration.copy()).objcObject)!
    }

    @ObjCMethod("identifier") func identifier() -> String? { configuration.identifier }

    @ObjCMethod("protocolClasses")
    func protocolClasses() -> NSObject {
        NSMutableArray.of((configuration.protocolClasses ?? []).map { NSObject($0) })
    }

    @ObjCMethod("setProtocolClasses:")
    func setProtocolClasses(_ classes: NSArray?) { configuration.protocolClasses = classes?.elements.map(\.objcObject) }
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

    /// The credential storage is the shared one whatever is set.
    @ObjCMethod("URLCredentialStorage") func credentialStorage() -> NSObject? { NSURLCredentialStorage.sharedCredentialStorage() }
    @ObjCMethod("setURLCredentialStorage:") func setCredentialStorage(_ storage: NSObject?) {}

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
    // Kept and read back; they don't change how requests go here.
    @ObjCMethod("networkServiceType") func networkServiceType() -> UInt { UInt(configuration.settings["networkServiceType"] ?? 0) }
    @ObjCMethod("setNetworkServiceType:") func setNetworkServiceType(_ value: UInt) { configuration.settings["networkServiceType"] = Int(value) }
    @ObjCMethod("allowsConstrainedNetworkAccess")
    func allowsConstrainedNetworkAccess() -> Bool { configuration.settings["allowsConstrainedNetworkAccess", default: 1] != 0 }
    @ObjCMethod("setAllowsConstrainedNetworkAccess:")
    func setAllowsConstrainedNetworkAccess(_ value: Bool) { configuration.settings["allowsConstrainedNetworkAccess"] = value ? 1 : 0 }
    @ObjCMethod("allowsExpensiveNetworkAccess")
    func allowsExpensiveNetworkAccess() -> Bool { configuration.settings["allowsExpensiveNetworkAccess", default: 1] != 0 }
    @ObjCMethod("setAllowsExpensiveNetworkAccess:")
    func setAllowsExpensiveNetworkAccess(_ value: Bool) { configuration.settings["allowsExpensiveNetworkAccess"] = value ? 1 : 0 }
    @ObjCMethod("isDiscretionary") func isDiscretionary() -> Bool { configuration.settings["discretionary"] ?? 0 != 0 }
    @ObjCMethod("setDiscretionary:") func setDiscretionary(_ value: Bool) { configuration.settings["discretionary"] = value ? 1 : 0 }
    @ObjCMethod("sessionSendsLaunchEvents") func sessionSendsLaunchEvents() -> Bool { configuration.settings["sendsLaunchEvents", default: 1] != 0 }
    @ObjCMethod("setSessionSendsLaunchEvents:") func setSessionSendsLaunchEvents(_ value: Bool) { configuration.settings["sendsLaunchEvents"] = value ? 1 : 0 }
    @ObjCMethod("shouldUseExtendedBackgroundIdleMode")
    func shouldUseExtendedBackgroundIdleMode() -> Bool { configuration.settings["extendedIdle"] ?? 0 != 0 }
    @ObjCMethod("setShouldUseExtendedBackgroundIdleMode:")
    func setShouldUseExtendedBackgroundIdleMode(_ value: Bool) { configuration.settings["extendedIdle"] = value ? 1 : 0 }
    @ObjCMethod("multipathServiceType") func multipathServiceType() -> Int { configuration.settings["multipath"] ?? 0 }
    @ObjCMethod("setMultipathServiceType:") func setMultipathServiceType(_ value: Int) { configuration.settings["multipath"] = value }
    /// SSLProtocol and tls_protocol_version_t values, as set.
    @ObjCMethod("TLSMinimumSupportedProtocol") func tlsMinimumProtocol() -> Int32 { Int32(configuration.settings["tlsMinimum"] ?? 0) }
    @ObjCMethod("setTLSMinimumSupportedProtocol:") func setTLSMinimumProtocol(_ value: Int32) { configuration.settings["tlsMinimum"] = Int(value) }
    @ObjCMethod("TLSMaximumSupportedProtocol") func tlsMaximumProtocol() -> Int32 { Int32(configuration.settings["tlsMaximum"] ?? 0) }
    @ObjCMethod("setTLSMaximumSupportedProtocol:") func setTLSMaximumProtocol(_ value: Int32) { configuration.settings["tlsMaximum"] = Int(value) }
    @ObjCMethod("TLSMinimumSupportedProtocolVersion")
    func tlsMinimumVersion() -> UInt16 { UInt16(configuration.settings["tlsMinimumVersion"] ?? 0x0301) }
    @ObjCMethod("setTLSMinimumSupportedProtocolVersion:")
    func setTLSMinimumVersion(_ value: UInt16) { configuration.settings["tlsMinimumVersion"] = Int(value) }
    @ObjCMethod("TLSMaximumSupportedProtocolVersion")
    func tlsMaximumVersion() -> UInt16 { UInt16(configuration.settings["tlsMaximumVersion"] ?? 0x0304) }
    @ObjCMethod("setTLSMaximumSupportedProtocolVersion:")
    func setTLSMaximumVersion(_ value: UInt16) { configuration.settings["tlsMaximumVersion"] = Int(value) }
    @ObjCMethod("sharedContainerIdentifier") func sharedContainerIdentifier() -> String? { configuration.sharedContainerIdentifier }
    @ObjCMethod("setSharedContainerIdentifier:") func setSharedContainerIdentifier(_ value: String?) { configuration.sharedContainerIdentifier = value }
    /// No proxies: requests go direct.
    @ObjCMethod("connectionProxyDictionary") func connectionProxyDictionary() -> NSObject? { nil }
    @ObjCMethod("setConnectionProxyDictionary:") func setConnectionProxyDictionary(_ value: NSObject?) {}

    @ObjCMethod("HTTPShouldUsePipelining") func usesPipelining() -> Bool { configuration.usesPipelining }
    @ObjCMethod("setHTTPShouldUsePipelining:") func setUsesPipelining(_ value: Bool) { configuration.usesPipelining = value }

    // Kept and read back like the network hints above: there is no
    // ultra-constrained network, TLS early data or DNSSEC here, and loading
    // is always "classic" (HTTP/1.1 over corelibs).
    @ObjCMethod("allowsUltraConstrainedNetworkAccess")
    func allowsUltraConstrainedNetworkAccess() -> Bool { configuration.settings["allowsUltraConstrainedNetworkAccess"] ?? 0 != 0 }
    @ObjCMethod("setAllowsUltraConstrainedNetworkAccess:")
    func setAllowsUltraConstrainedNetworkAccess(_ value: Bool) { configuration.settings["allowsUltraConstrainedNetworkAccess"] = value ? 1 : 0 }
    @ObjCMethod("enablesEarlyData") func enablesEarlyData() -> Bool { configuration.settings["enablesEarlyData"] ?? 0 != 0 }
    @ObjCMethod("setEnablesEarlyData:") func setEnablesEarlyData(_ value: Bool) { configuration.settings["enablesEarlyData"] = value ? 1 : 0 }
    @ObjCMethod("requiresDNSSECValidation")
    func requiresDNSSECValidation() -> Bool { configuration.settings["requiresDNSSECValidation"] ?? 0 != 0 }
    @ObjCMethod("setRequiresDNSSECValidation:")
    func setRequiresDNSSECValidation(_ value: Bool) { configuration.settings["requiresDNSSECValidation"] = value ? 1 : 0 }
    @ObjCMethod("usesClassicLoadingMode")
    func usesClassicLoadingMode() -> Bool { configuration.settings["usesClassicLoadingMode", default: 1] != 0 }
    @ObjCMethod("setUsesClassicLoadingMode:")
    func setUsesClassicLoadingMode(_ value: Bool) { configuration.settings["usesClassicLoadingMode"] = value ? 1 : 0 }
}

/// NSCachedURLResponse: a response and its data, as a cache is given them
/// to keep and as a session's delegate is asked whether to cache them.
@ObjCClass("NSCachedURLResponse")
open class NSCachedURLResponse: NSObject {
    var cachedResponse: NSObject? = nil
    var cachedData: NSObject? = nil
    var cachedUserInfo: NSObject? = nil
    /// NSURLCacheStoragePolicy: allowed 0, in memory only 1, not allowed 2.
    var cachedPolicy: UInt = 0

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithResponse:data:")
    public required init(response: NSObject?, data: NSObject?) {
        super.init()
        cachedResponse = response
        cachedData = data
    }

    @ObjCMethod("initWithResponse:data:userInfo:storagePolicy:")
    public required init(response: NSObject?, data: NSObject?, userInfo: NSObject?, storagePolicy: UInt) {
        super.init()
        cachedResponse = response
        cachedData = data
        cachedUserInfo = userInfo
        cachedPolicy = storagePolicy
    }

    @ObjCMethod("response") func response() -> NSObject? { cachedResponse }
    @ObjCMethod("data") func data() -> NSObject? { cachedData }
    @ObjCMethod("userInfo") func userInfo() -> NSObject? { cachedUserInfo }
    @ObjCMethod("storagePolicy") func storagePolicy() -> UInt { cachedPolicy }
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
    @ObjCMethod("initWithMemoryCapacity:diskCapacity:directoryURL:")
    func initialize(memoryCapacity: UInt, diskCapacity: UInt, directoryURL: NSObject?) -> Self { self }

    @ObjCMethod("memoryCapacity") func memoryCapacity() -> UInt { 512_000 }
    @ObjCMethod("diskCapacity") func diskCapacity() -> UInt { 10_000_000 }
    /// The cache keeps nothing, whatever room it is given.
    @ObjCMethod("setMemoryCapacity:") func setMemoryCapacity(_ capacity: UInt) {}
    @ObjCMethod("setDiskCapacity:") func setDiskCapacity(_ capacity: UInt) {}
    @ObjCMethod("currentMemoryUsage") func currentMemoryUsage() -> UInt { 0 }
    @ObjCMethod("currentDiskUsage") func currentDiskUsage() -> UInt { 0 }
    @ObjCMethod("cachedResponseForRequest:") func cachedResponse(for request: NSObject) -> NSObject? { nil }
    @ObjCMethod("removeAllCachedResponses") func removeAllCachedResponses() {}
    @ObjCMethod("removeCachedResponseForRequest:") func removeCachedResponse(for request: NSObject) {}
    /// The cache keeps nothing: responses stored are let go.
    @ObjCMethod("storeCachedResponse:forRequest:") func store(_ response: NSObject?, for request: NSObject?) {}
    @ObjCMethod("storeCachedResponse:forDataTask:") func store(_ response: NSObject?, forDataTask task: NSObject?) {}
    @ObjCMethod("getCachedResponseForDataTask:completionHandler:")
    func cachedResponse(forDataTask task: NSObject?, completionHandler: ObjCBlock?) {
        guard let completionHandler else { return }
        completionHandler.function(as: (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void).self)(
            completionHandler.object, nil)
    }
    @ObjCMethod("removeCachedResponseForDataTask:") func removeCachedResponse(forDataTask task: NSObject?) {}
    @ObjCMethod("removeCachedResponsesSinceDate:") func removeCachedResponses(since date: NSObject?) {}
}

// MARK: - Tasks

/// A task's Swift side and its completion handler.
final class TaskState {
    let task: Task
    /// When the task was made, where its metrics begin.
    let created = Date()
    /// Its own delegate, which hears of it before the session's.
    var delegate: NSObject?
    var metricsDelivered = false
    /// The NSURLSession, retained until the task completes: a session
    /// lives as long as its tasks run, whoever else lets go of it, and its
    /// delegate is handed it with each event.
    var session: UnsafeMutableRawPointer?
    /// What resuming does instead of starting the load: a task made from
    /// resume data that names nothing to load fails at once.
    var failsOnResume: (() -> Void)?
    /// The error the task failed with when corelibs never ran it.
    var failure: NSError?

    init(_ task: Task) {
        self.task = task
    }
}

enum Tasks {
    static let states = StateTable<TaskState>()

    static func task(_ object: UnsafeMutableRawPointer) -> Task? { states.get(object)?.task }

    /// The object for a task (+0); the session holds another reference
    /// until the task completes, as Darwin's does.
    static func object(_ task: Task, session: UnsafeMutableRawPointer? = nil) -> NSObject {
        let cls: ObjCClass
        switch task.kind {
        case .data: cls = NSURLSessionDataTask.objCClass
        case .upload: cls = NSURLSessionUploadTask.objCClass
        case .download: cls = NSURLSessionDownloadTask.objCClass
        }
        let object = cls.autoreleasedInstance()
        let state = TaskState(task)
        state.session = session.flatMap { ObjCRuntime.retain($0) }
        states.set(object.objcObject, state)
        task.owner = ObjCRuntime.retain(object.objcObject)
        return object
    }

    /// Drops the session's reference, when the task completes.
    static func finish(_ task: Task) {
        task.markCompleted()
        guard let owner = task.owner else { return }
        task.owner = nil
        if let state = states.get(owner), let session = state.session {
            state.session = nil
            ObjCRuntime.release(session)
        }
        ObjCRuntime.release(owner)
    }
}

/// NSProgress, for a task's progress.
@ObjCWrapper("NSProgress")
class NSProgress: NSObject {
    @ObjCClassMethod("discreteProgressWithTotalUnitCount:") static func discrete(total: Int64) -> NSProgress
    @ObjCMethod("setTotalUnitCount:") func setTotalUnitCount(_ count: Int64)
    @ObjCMethod("setCompletedUnitCount:") func setCompletedUnitCount(_ count: Int64)
    @ObjCMethod("setCancellable:") func setCancellable(_ value: Bool)
    @ObjCMethod("setPausable:") func setPausable(_ value: Bool)
    @ObjCMethod("setCancellationHandler:") func setCancellationHandler(_ block: NSObject?)
    @ObjCMethod("isCancelled") func isCancelled() -> Bool
    @ObjCMethod("cancel") func cancel()
}

/// What every task keeps whatever loads it: the scheduling hints a program
/// gives (kept and read back; tasks start when resumed) and its progress.
final class TaskExtras {
    var earliestBeginDate: NSObject?
    /// NSURLSessionTransferSizeUnknown until the program says.
    var expectsToSend: Int64 = -1
    var expectsToReceive: Int64 = -1
    var prefersIncrementalDelivery = true
    var progress: NSProgress?
    var cancelling = false
}

enum TaskExtrasTable {
    static let states = StateTable<TaskExtras>()

    static func extras(_ object: UnsafeMutableRawPointer) -> TaskExtras {
        if let extras = states.get(object) { return extras }
        let extras = TaskExtras()
        states.set(object, extras)
        return extras
    }

    /// The task is being cancelled: its progress is too.
    static func cancelled(_ object: UnsafeMutableRawPointer) {
        let found = extras(object)
        guard !found.cancelling else { return }
        found.cancelling = true
        if let progress = found.progress, !progress.isCancelled() { progress.cancel() }
    }

    static func remove(_ object: UnsafeMutableRawPointer) {
        if let progress = states.get(object)?.progress { progress.setCancellationHandler(nil) }
        states.remove(object)
    }
}

/// NSURLSessionTask. Data, upload and download tasks run in corelibs;
/// WebSocket and stream tasks (SocketTasks) here.
@ObjCClass("NSURLSessionTask")
open class NSURLSessionTask: NSObject {
    var task: Task? { Tasks.task(objcObject) }
    /// A WebSocket or stream task's state.
    var own: SocketTaskState? { SocketTasks.states.get(objcObject) }

    @ObjCMethod("dealloc")
    func dealloc() {
        Tasks.states.remove(objcObject)
        SocketTasks.states.remove(objcObject)
        TaskExtrasTable.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSURLSessionTask.objCClass.pointer)
    }

    @ObjCMethod("taskIdentifier") func taskIdentifier() -> UInt { UInt(own?.identifier ?? task?.identifier ?? 0) }

    @ObjCMethod("state")
    func state() -> Int {
        if let own { return own.currentState }
        if let state = Tasks.states.get(objcObject), state.failure != nil { return 3 }
        let value = task?.state ?? 3
        // corelibs leaves a cancelled task that never ran suspended (1);
        // Darwin's is canceling (2) at once, until it completes.
        if value == 1, TaskExtrasTable.states.get(objcObject)?.cancelling == true { return 2 }
        return value
    }

    @ObjCMethod("originalRequest")
    func originalRequest() -> NSObject? {
        if let own { return Requests.object(own.originalRequest.copy()) }
        return task?.originalRequest.map { Requests.object($0) }
    }

    @ObjCMethod("currentRequest")
    func currentRequest() -> NSObject? {
        if let own { return Requests.object(own.originalRequest.copy()) }
        return task?.currentRequest.map { Requests.object($0) }
    }

    @ObjCMethod("response")
    func response() -> NSObject? {
        if let own { return own.response.map(Responses.object) }
        return task?.response.map(Responses.object)
    }

    @ObjCMethod("error")
    func error() -> NSError? {
        if let own { return own.error }
        if let failure = Tasks.states.get(objcObject)?.failure { return failure }
        return Errors.object(task?.error)
    }

    @ObjCMethod("countOfBytesReceived") func countOfBytesReceived() -> Int64 { own?.bytesReceived ?? task?.bytesReceived ?? 0 }
    @ObjCMethod("countOfBytesSent") func countOfBytesSent() -> Int64 { own?.bytesSent ?? task?.bytesSent ?? 0 }
    @ObjCMethod("countOfBytesExpectedToReceive")
    func countOfBytesExpectedToReceive() -> Int64 { own != nil ? 0 : task?.bytesExpectedToReceive ?? 0 }
    @ObjCMethod("countOfBytesExpectedToSend") func countOfBytesExpectedToSend() -> Int64 { own != nil ? 0 : task?.bytesExpectedToSend ?? 0 }

    @ObjCMethod("delegate")
    func delegate() -> NSObject? {
        if let own { return own.taskDelegate }
        return Tasks.states.get(objcObject)?.delegate
    }

    @ObjCMethod("setDelegate:")
    func setDelegate(_ delegate: NSObject?) {
        if let own {
            own.taskDelegate = delegate
            return
        }
        Tasks.states.get(objcObject)?.delegate = delegate
    }

    @ObjCMethod("taskDescription") func taskDescription() -> String? { own?.taskDescription ?? task?.taskDescription }

    @ObjCMethod("setTaskDescription:")
    func setTaskDescription(_ text: String?) {
        if let own {
            own.taskDescription = text
            return
        }
        task?.taskDescription = text
    }

    @ObjCMethod("priority") func priority() -> Float { own?.priority ?? task?.priority ?? 0.5 }

    @ObjCMethod("setPriority:")
    func setPriority(_ priority: Float) {
        if let own {
            own.priority = priority
            return
        }
        task?.priority = priority
    }

    @ObjCMethod("resume") func resume() {
        if let own { return own.resume() }
        if let state = Tasks.states.get(objcObject), let fail = state.failsOnResume {
            state.failsOnResume = nil
            return fail()
        }
        // PERRY_URL_TRACE: each task as it starts, so ones that never finish show.
        if getenv("PERRY_URL_TRACE") != nil {
            let line = "perry: URL[\(time(nil) % 1000)]: start \(task?.originalRequest?.method ?? "GET") \(task?.originalRequest?.url?.absoluteString ?? "?") (timeout \(task?.originalRequest?.timeout ?? -1))\n"
            _ = line.withCString { Glibc.write(2, $0, strlen($0)) }
        }
        task?.resume()
    }

    @ObjCMethod("suspend")
    func suspend() {
        if let own { return own.suspend() }
        task?.suspend()
    }

    @ObjCMethod("cancel") func cancel() {
        TaskExtrasTable.cancelled(objcObject)
        if let own { return own.cancel() }
        // PERRY_URL_TRACE: who cancels a task, and which.
        if getenv("PERRY_URL_TRACE") != nil {
            perry_print_frames("perry: URL: cancel \(task?.originalRequest?.url?.absoluteString ?? "?")")
        }
        task?.cancel()
    }

    // MARK: Scheduling hints and progress

    /// When the program would have the task start: kept, as there is no
    /// background scheduler to wait for it.
    @ObjCMethod("earliestBeginDate") func earliestBeginDate() -> NSObject? { TaskExtrasTable.extras(objcObject).earliestBeginDate }
    @ObjCMethod("setEarliestBeginDate:") func setEarliestBeginDate(_ date: NSObject?) { TaskExtrasTable.extras(objcObject).earliestBeginDate = date }
    @ObjCMethod("countOfBytesClientExpectsToSend")
    func countOfBytesClientExpectsToSend() -> Int64 { TaskExtrasTable.extras(objcObject).expectsToSend }
    @ObjCMethod("setCountOfBytesClientExpectsToSend:")
    func setCountOfBytesClientExpectsToSend(_ count: Int64) { TaskExtrasTable.extras(objcObject).expectsToSend = count }
    @ObjCMethod("countOfBytesClientExpectsToReceive")
    func countOfBytesClientExpectsToReceive() -> Int64 { TaskExtrasTable.extras(objcObject).expectsToReceive }
    @ObjCMethod("setCountOfBytesClientExpectsToReceive:")
    func setCountOfBytesClientExpectsToReceive(_ count: Int64) { TaskExtrasTable.extras(objcObject).expectsToReceive = count }
    @ObjCMethod("prefersIncrementalDelivery")
    func prefersIncrementalDelivery() -> Bool { TaskExtrasTable.extras(objcObject).prefersIncrementalDelivery }
    @ObjCMethod("setPrefersIncrementalDelivery:")
    func setPrefersIncrementalDelivery(_ value: Bool) { TaskExtrasTable.extras(objcObject).prefersIncrementalDelivery = value }

    /// The task's progress: its bytes, cancellable (which cancels the
    /// task) but not pausable, as Darwin's.
    @ObjCMethod("progress")
    func progress() -> NSProgress {
        let extras = TaskExtrasTable.extras(objcObject)
        let progress: NSProgress
        if let existing = extras.progress {
            progress = existing
        } else {
            progress = NSProgress.discrete(total: 100)
            progress.setCancellable(true)
            progress.setPausable(false)
            // Unretained: the task holds the progress, not the other way.
            nonisolated(unsafe) let task = objcObject
            progress.setCancellationHandler(Closures.block {
                guard let extras = TaskExtrasTable.states.get(task), !extras.cancelling else { return }
                typealias Send = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> Void
                unsafeBitCast(ObjCRuntime.msgSend, to: Send.self)(task, ObjCRuntime.selector("cancel"))
            })
            extras.progress = progress
            if extras.cancelling { progress.cancel() }
        }
        let expected = countOfBytesExpectedToReceive(), received = countOfBytesReceived()
        if expected > 0 {
            progress.setTotalUnitCount(expected)
            progress.setCompletedUnitCount(received)
        } else if state() == 3, error() == nil {
            progress.setCompletedUnitCount(100)
        }
        return progress
    }
}

@ObjCClass("NSURLSessionDataTask") open class NSURLSessionDataTask: NSURLSessionTask {}
@ObjCClass("NSURLSessionUploadTask") open class NSURLSessionUploadTask: NSURLSessionDataTask {
    /// Uploads can't be resumed here: nil, as Darwin gives when the server
    /// doesn't support resumable uploads.
    @ObjCMethod("cancelByProducingResumeData:")
    func cancelByProducingResumeData(_ completionHandler: ObjCBlock?) { ResumeData.cancel(self, completionHandler) }
}

@ObjCClass("NSURLSessionDownloadTask") open class NSURLSessionDownloadTask: NSURLSessionTask {
    /// corelibs keeps no partial file to resume from: the handler is given
    /// nil, as Darwin gives for a download that can't be resumed.
    @ObjCMethod("cancelByProducingResumeData:")
    func cancelByProducingResumeData(_ completionHandler: ObjCBlock?) { ResumeData.cancel(self, completionHandler) }
}

/// Resume data: what cancelling gives, and tasks made from it.
enum ResumeData {
    /// Cancels the task and gives the handler nil on the session's queue.
    static func cancel(_ task: NSURLSessionTask, _ handler: ObjCBlock?) {
        let session = Tasks.states.get(task.objcObject)?.session
        let queue = session.flatMap { Sessions.state($0)?.queue }
        task.cancel()
        guard let handler else { return }
        nonisolated(unsafe) let block = handler
        let call = {
            ObjCRuntime.autoreleasepool {
                block.function(as: (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void).self)(block.object, nil)
            }
        }
        if let queue { queue.addOperation(block: Closures.block(call)) } else { call() }
    }

    /// The URL a download's resume data names (NSURLSessionDownloadURL).
    static func url(_ data: NSData?) -> URL? {
        guard let data, data.length() > 0,
              let list = NSPropertyListSerialization.propertyList(data: data, options: 0, format: nil, error: nil),
              list.isKind(of: ObjCClass(named: "NSDictionary")),
              let value = list.unsafeCast(to: NSDictionary.self).object(forKey: NSObject.string("NSURLSessionDownloadURL")),
              value.isString else { return nil }
        return URL(string: value.stringValue)
    }

    /// NSURLErrorUnsupportedURL, for resume data naming nothing to load.
    static func unsupported() -> NSError {
        NSError.make(domain: ErrorKeys.NSURLErrorDomain, code: -1002,
                     userInfo: NSMutableDictionary.of([("NSLocalizedDescription", NSObject.string("unsupported URL"))]))
    }
}

@ObjCWrapper("NSPropertyListSerialization")
class NSPropertyListSerialization: NSObject {
    @ObjCClassMethod("propertyListWithData:options:format:error:")
    static func propertyList(data: NSData, options: UInt, format: UnsafeMutableRawPointer?, error: UnsafeMutableRawPointer?) -> NSObject?
}

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
        run { [self] in Metrics.deliver(session: session, task: task, sessionDelegate: delegate) }
        if responds(name) {
            run { [self] in
                send((@convention(c) (Object, UnsafeRawPointer, Object, Object, Object) -> Void).self)(
                    delegate.objcObject, selector(name), session, task.owner, Errors.object(error)?.objcObject)
            }
        }
        Tasks.finish(task)
    }

    /// The task delegate's answer; without the method, default handling.
    func task(_ task: Task, didReceive challenge: Challenge, completion: @escaping @Sendable (Int, Credential?) -> Void) {
        let name = "URLSession:task:didReceiveChallenge:completionHandler:"
        let answer: @Sendable (Int, Credential?) -> Void = { disposition, credential in
            guard disposition == 1 else { return completion(disposition, credential) }
            let (fallback, stored) = CredentialStorage.defaultAnswer(challenge)
            completion(fallback, stored)
        }
        guard responds(name) else { return answer(1, nil) }
        let once = SenderState(answer, challenge: challenge)
        run { [self] in
            let block = Closures.block(integerObject: { disposition, credential in
                once.give(disposition, Credentials.credential(credential))
            })
            send((@convention(c) (Object, UnsafeRawPointer, Object, Object, Object, Object) -> Void).self)(
                delegate.objcObject, selector(name), session, task.owner, Challenges.object(challenge, answer: once).objcObject,
                block.objcObject)
        }
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
    /// The WebSocket and stream tasks it runs, until they complete.
    private let lock = Lock()
    private var running: [SocketTaskState] = []

    func add(_ task: SocketTaskState) { lock.withLock { running.append(task) } }
    func remove(_ task: SocketTaskState) { lock.withLock { running.removeAll { $0 === task } } }
    var socketTasks: [SocketTaskState] { lock.withLock { running } }

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

    /// State for a session made with +new or -init rather than a
    /// configuration: the default configuration's, with no delegate.
    static func adopt(_ object: UnsafeMutableRawPointer) -> SessionState {
        let copy = Configuration.makeDefault()
        let state = SessionState(session: Session(configuration: copy, events: nil), queue: serialQueue(),
                                 configuration: Configurations.object(copy), delegate: nil)
        states.set(object, state)
        return state
    }

    static func invalidated(_ session: UnsafeMutableRawPointer) {
        state(session)?.delegate = nil
    }
}

/// NSURLSession.
@ObjCClass("NSURLSession")
open class NSURLSession: NSObject {
    var state: SessionState? { Sessions.state(objcObject) ?? Sessions.adopt(objcObject) }

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
        state?.socketTasks.forEach { $0.cancel() }
        state?.session.invalidateAndCancel()
    }

    /// Runs a void block on the delegate queue.
    private func later(_ handler: ObjCBlock?) {
        guard let handler, let state else { return }
        nonisolated(unsafe) let block = handler
        state.queue.addOperation(block: Closures.block {
            ObjCRuntime.autoreleasepool {
                block.function(as: (@convention(c) (UnsafeMutableRawPointer?) -> Void).self)(block.object)
            }
        })
    }

    /// Nothing is kept to write out: cookies and credentials are stored as
    /// they are set. The handler runs on the delegate queue.
    @ObjCMethod("flushWithCompletionHandler:")
    func flush(completionHandler: ObjCBlock?) { later(completionHandler) }

    /// Darwin empties the session's cookie, cache and credential stores.
    /// Here those are the process's shared stores, which other sessions
    /// use too, so they are left as they are; the cache keeps nothing
    /// anyway. The handler runs on the delegate queue.
    @ObjCMethod("resetWithCompletionHandler:")
    func reset(completionHandler: ObjCBlock?) { later(completionHandler) }

    // MARK: Tasks

    /// The session's tasks, given to the handler on the delegate queue
    /// later: its data, upload and download tasks. Tasks under way are not
    /// listed, so each list is empty.
    @ObjCMethod("getTasksWithCompletionHandler:")
    func getTasks(completionHandler: ObjCBlock?) {
        guard let completionHandler, let state else { return }
        nonisolated(unsafe) let block = completionHandler
        state.queue.addOperation(block: Closures.block {
            ObjCRuntime.autoreleasepool {
                Blocks.call(block, NSMutableArray.of([]).objcObject, NSMutableArray.of([]).objcObject, NSMutableArray.of([]).objcObject)
            }
        })
    }

    @ObjCMethod("getAllTasksWithCompletionHandler:")
    func getAllTasks(completionHandler: ObjCBlock?) {
        guard let completionHandler, let state else { return }
        nonisolated(unsafe) let block = completionHandler
        state.queue.addOperation(block: Closures.block {
            ObjCRuntime.autoreleasepool {
                block.function(as: (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void).self)(
                    block.object, NSMutableArray.of([]).objcObject)
            }
        })
    }

    // MARK: Completion handlers

    /// A data or upload completion handler, run on the delegate queue.
    private func dataCompletion(_ handler: ObjCBlock?) -> BoxedCompletion? {
        guard let handler, let state else { return nil }
        nonisolated(unsafe) let queue = state.queue
        let box = TaskBox()
        nonisolated(unsafe) let block = handler
        nonisolated(unsafe) let session = objcObject
        nonisolated(unsafe) let sessionDelegate = state.delegate
        let body: Session.DataCompletion = { data, response, error in
            box.task?.markCompleted()
            Hops.run(on: queue) {
                ObjCRuntime.autoreleasepool {
                    if let task = box.task { Metrics.deliver(session: session, task: task, sessionDelegate: sessionDelegate) }
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
        return Tasks.object(task, session: objcObject)
    }

    /// A request for the URL; one without a URL for nil, as Apple's
    /// sessions make a task for nil (libraries ask for one in +load, to
    /// find the task classes).
    private func request(_ url: NSURL?) -> Request { Request(url: url?.url) }
    private func request(_ object: NSObject) -> Request { Requests.request(object.objcObject).copy() }

    @ObjCMethod("dataTaskWithURL:")
    func dataTask(with url: NSURL?) -> NSObject { dataTask({ state!.session.dataTask(request(url), completion: $0) }, nil) }

    @ObjCMethod("dataTaskWithRequest:")
    func dataTask(with request: NSObject) -> NSObject {
        dataTask({ state!.session.dataTask(self.request(request), completion: $0) }, nil)
    }

    @ObjCMethod("dataTaskWithURL:completionHandler:")
    func dataTask(with url: NSURL?, completionHandler: ObjCBlock?) -> NSObject {
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

    /// The body is the request's own, its data or stream, rather than one
    /// the delegate gives with URLSession:task:needNewBodyStream:.
    @ObjCMethod("uploadTaskWithStreamedRequest:")
    func uploadTask(withStreamedRequest request: NSObject) -> NSObject {
        dataTask({ state!.session.dataTask(self.request(request), completion: $0) }, nil)
    }

    /// A download's handler runs before the file is removed.
    private func downloadTask(_ request: Request, _ handler: ObjCBlock?) -> NSObject {
        guard let handler, let state else { return Tasks.object(self.state!.session.downloadTask(request), session: objcObject) }
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
        return Tasks.object(task, session: objcObject)
    }

    @ObjCMethod("downloadTaskWithURL:") func downloadTask(with url: NSURL?) -> NSObject { downloadTask(request(url), nil) }
    @ObjCMethod("downloadTaskWithRequest:") func downloadTask(with request: NSObject) -> NSObject {
        downloadTask(self.request(request), nil)
    }

    @ObjCMethod("downloadTaskWithURL:completionHandler:")
    func downloadTask(with url: NSURL?, completionHandler: ObjCBlock?) -> NSObject { downloadTask(request(url), completionHandler) }

    @ObjCMethod("downloadTaskWithRequest:completionHandler:")
    func downloadTask(with request: NSObject, completionHandler: ObjCBlock?) -> NSObject {
        downloadTask(self.request(request), completionHandler)
    }

    // MARK: Resume data

    /// A task that, once resumed, fails with NSURLErrorUnsupportedURL, as
    /// Darwin's made from resume data naming nothing does: its handler, or
    /// else the delegate, is told.
    private func failingTask(_ object: NSObject, _ handler: ObjCBlock?) -> NSObject {
        guard let taskState = Tasks.states.get(object.objcObject), let state else { return object }
        nonisolated(unsafe) let queue = state.queue
        nonisolated(unsafe) let block = handler
        nonisolated(unsafe) let session = objcObject
        nonisolated(unsafe) let task = object.objcObject
        taskState.failsOnResume = { [weak taskState] in
            let error = ResumeData.unsupported()
            taskState?.failure = error
            queue.addOperation(block: Closures.block {
                ObjCRuntime.autoreleasepool {
                    if let block {
                        Blocks.call(block, nil, nil, error.objcObject)
                    } else if let delegate = Sessions.state(session)?.delegate, delegate.responds(to: "URLSession:task:didCompleteWithError:") {
                        unsafeBitCast(ObjCRuntime.msgSend, to: (@convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeMutableRawPointer?,
                                                                                UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void).self)(
                            delegate.objcObject, ObjCRuntime.selector("URLSession:task:didCompleteWithError:"), session, task, error.objcObject)
                    }
                    // The session lets go of the task once it has been told.
                    if let finished = Tasks.task(task) { Tasks.finish(finished) }
                }
            })
        }
        return object
    }

    /// A download resuming from Darwin's resume data starts again from the
    /// URL it names: corelibs can't append to a partial file.
    private func downloadTask(resumeData: NSData?, _ handler: ObjCBlock?) -> NSObject {
        if let url = ResumeData.url(resumeData) { return downloadTask(Request(url: url), handler) }
        return failingTask(downloadTask(Request(url: nil), nil), handler)
    }

    @ObjCMethod("downloadTaskWithResumeData:")
    func downloadTask(withResumeData data: NSData?) -> NSObject { downloadTask(resumeData: data, nil) }

    @ObjCMethod("downloadTaskWithResumeData:completionHandler:")
    func downloadTask(withResumeData data: NSData?, completionHandler: ObjCBlock?) -> NSObject {
        downloadTask(resumeData: data, completionHandler)
    }

    /// Resumable uploads need a server that offers them and the partial
    /// upload's state, which this never produces: the task fails once
    /// resumed.
    @ObjCMethod("uploadTaskWithResumeData:")
    func uploadTask(withResumeData data: NSData?) -> NSObject {
        failingTask(dataTask({ state!.session.uploadTask(Request(url: nil), data: Data(), completion: $0) }, nil), nil)
    }

    @ObjCMethod("uploadTaskWithResumeData:completionHandler:")
    func uploadTask(withResumeData data: NSData?, completionHandler: ObjCBlock?) -> NSObject {
        failingTask(dataTask({ state!.session.uploadTask(Request(url: nil), data: Data(), completion: $0) }, nil), completionHandler)
    }

    // MARK: WebSocket and stream tasks

    /// A ws or wss URL's task; another scheme raises, as on Darwin.
    @ObjCMethod("webSocketTaskWithURL:")
    func webSocketTask(with url: NSURL?) -> NSObject { WebSocketTasks.make(session: objcObject, request: Request(url: url?.url), protocols: []) }

    @ObjCMethod("webSocketTaskWithURL:protocols:")
    func webSocketTask(with url: NSURL?, protocols: NSArray?) -> NSObject {
        WebSocketTasks.make(session: objcObject, request: Request(url: url?.url),
                            protocols: (protocols?.elements ?? []).filter(\.isString).map(\.stringValue))
    }

    @ObjCMethod("webSocketTaskWithRequest:")
    func webSocketTask(with request: NSObject) -> NSObject {
        WebSocketTasks.make(session: objcObject, request: self.request(request), protocols: [])
    }

    @ObjCMethod("streamTaskWithHostName:port:")
    func streamTask(withHostName host: String, port: Int) -> NSObject { StreamTasks.make(session: objcObject, host: host, port: port) }

    /// The service's resolved host and port. One not yet resolved has no
    /// host: its task fails to connect once resumed.
    @ObjCMethod("streamTaskWithNetService:")
    func streamTask(with service: NSObject?) -> NSObject {
        let host = service.flatMap { $0.responds(to: "hostName") ? $0.sendHostName() : nil } ?? ""
        let port = service.map { $0.responds(to: "port") ? $0.sendPort() : 0 } ?? 0
        return StreamTasks.make(session: objcObject, host: host, port: port)
    }
}

extension NSObject {
    @ObjCMethod("hostName") func sendHostName() -> String?
    @ObjCMethod("port") func sendPort() -> Int
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

@ObjCConstants
enum HTTPVersionConstants {
    static let kCFHTTPVersion1_0 = "HTTP/1.0"
    static let kCFHTTPVersion1_1 = "HTTP/1.1"
}

// MARK: - Asset downloads

/// AVFoundation's session for downloading HLS assets to play offline, here
/// because it is an NSURLSession: apps make one as they start (Crunchyroll
/// keeps it for its downloads, and takes none for an error). It is a
/// session like any other; nothing downloads assets yet, so its tasks are
/// nil.
@ObjCClass("AVAssetDownloadURLSession")
open class AVAssetDownloadURLSession: NSURLSession {
    @ObjCClassMethod("sessionWithConfiguration:assetDownloadDelegate:delegateQueue:")
    static func make(_ cls: ObjCClass, configuration: NSObject, assetDownloadDelegate: NSObject?,
                     delegateQueue: NSOperationQueue?) -> NSObject {
        Sessions.make(cls, configuration: configuration, delegate: assetDownloadDelegate, queue: delegateQueue)
    }

    @ObjCMethod("assetDownloadTaskWithURLAsset:assetTitle:assetArtworkData:options:")
    func assetDownloadTask(asset: NSObject?, title: NSObject?, artwork: NSObject?, options: NSObject?) -> NSObject? { nil }

    @ObjCMethod("aggregateAssetDownloadTaskWithURLAsset:mediaSelections:assetTitle:assetArtworkData:options:")
    func aggregateAssetDownloadTask(asset: NSObject?, mediaSelections: NSObject?, title: NSObject?, artwork: NSObject?,
                                    options: NSObject?) -> NSObject? { nil }

    @ObjCMethod("assetDownloadTaskWithConfiguration:")
    func assetDownloadTask(configuration: NSObject?) -> NSObject? { nil }
}

import FoundationEssentials
import PerryObjCInterop
import PerryURLLoading

// URL task metrics: what a task's delegate, then its session's, is told in
// URLSession:task:didFinishCollectingMetrics: as the task completes, before
// its completion handler runs, as Darwin's are. corelibs times no phases,
// so a task has one transaction, a network load, spanning the task: from
// when it was made to when it completed.

final class MetricsState {
    let start: Date
    let end: Date
    let request: NSObject?
    let response: NSObject?
    let redirectCount: Int

    init(start: Date, end: Date, request: NSObject?, response: NSObject?, redirectCount: Int) {
        (self.start, self.end, self.request, self.response, self.redirectCount) = (start, end, request, response, redirectCount)
    }
}

@ObjCClass("NSURLSessionTaskMetrics")
open class NSURLSessionTaskMetrics: NSObject {
    static let states = StateTable<MetricsState>()
    var metrics: MetricsState? { NSURLSessionTaskMetrics.states.get(objcObject) }

    @ObjCMethod("dealloc")
    func dealloc() {
        NSURLSessionTaskMetrics.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSURLSessionTaskMetrics.objCClass.pointer)
    }

    @ObjCMethod("transactionMetrics")
    func transactionMetrics() -> NSArray {
        guard let metrics else { return NSArray.make(objects: nil, count: 0) }
        let transaction = NSURLSessionTaskTransactionMetrics.objCClass.autoreleasedInstance()
        NSURLSessionTaskTransactionMetrics.states.set(transaction.objcObject, metrics)
        var object: UnsafeMutableRawPointer? = transaction.objcObject
        return withUnsafePointer(to: &object) { NSArray.make(objects: UnsafeRawPointer($0), count: 1) }
    }

    @ObjCMethod("taskInterval")
    func taskInterval() -> NSDateInterval {
        let start = metrics?.start ?? Date(), end = metrics?.end ?? start
        return NSDateInterval.make(start: NSDate.of(start), end: NSDate.of(end))
    }

    @ObjCMethod("redirectCount") func redirectCount() -> UInt { UInt(metrics?.redirectCount ?? 0) }
}

@ObjCClass("NSURLSessionTaskTransactionMetrics")
open class NSURLSessionTaskTransactionMetrics: NSObject {
    static let states = StateTable<MetricsState>()
    var metrics: MetricsState? { NSURLSessionTaskTransactionMetrics.states.get(objcObject) }

    @ObjCMethod("dealloc")
    func dealloc() {
        NSURLSessionTaskTransactionMetrics.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSURLSessionTaskTransactionMetrics.objCClass.pointer)
    }

    @ObjCMethod("request") func request() -> NSObject? { metrics?.request }
    @ObjCMethod("response") func response() -> NSObject? { metrics?.response }
    @ObjCMethod("fetchStartDate") func fetchStartDate() -> NSDate? { metrics.map { NSDate.of($0.start) } }
    @ObjCMethod("responseEndDate") func responseEndDate() -> NSDate? { metrics.map { NSDate.of($0.end) } }
    @ObjCMethod("requestStartDate") func requestStartDate() -> NSDate? { metrics.map { NSDate.of($0.start) } }
    @ObjCMethod("responseStartDate") func responseStartDate() -> NSDate? { metrics.map { NSDate.of($0.end) } }
    /// NSURLSessionTaskMetricsResourceFetchType: a network load, 1.
    @ObjCMethod("resourceFetchType") func resourceFetchType() -> Int { 1 }
    @ObjCMethod("networkProtocolName") func networkProtocolName() -> String? { "http/1.1" }
    @ObjCMethod("isProxyConnection") func isProxyConnection() -> Bool { false }
    @ObjCMethod("isReusedConnection") func isReusedConnection() -> Bool { false }
    @ObjCMethod("isCellular") func isCellular() -> Bool { false }
    @ObjCMethod("isExpensive") func isExpensive() -> Bool { false }
    @ObjCMethod("isConstrained") func isConstrained() -> Bool { false }
    @ObjCMethod("isMultipath") func isMultipath() -> Bool { false }
    @ObjCMethod("domainResolutionStartDate") func domainResolutionStartDate() -> NSDate? { nil }
    @ObjCMethod("domainResolutionEndDate") func domainResolutionEndDate() -> NSDate? { nil }
    @ObjCMethod("connectStartDate") func connectStartDate() -> NSDate? { nil }
    @ObjCMethod("connectEndDate") func connectEndDate() -> NSDate? { nil }
    @ObjCMethod("secureConnectionStartDate") func secureConnectionStartDate() -> NSDate? { nil }
    @ObjCMethod("secureConnectionEndDate") func secureConnectionEndDate() -> NSDate? { nil }
    @ObjCMethod("requestEndDate") func requestEndDate() -> NSDate? { metrics.map { NSDate.of($0.start) } }
}

enum Metrics {
    static let selector = "URLSession:task:didFinishCollectingMetrics:"

    /// Tells the task's delegate, then the session's, the task's metrics,
    /// once: on the caller's queue, before its completion is reported.
    static func deliver(session: UnsafeMutableRawPointer, task: Task, sessionDelegate: NSObject?) {
        guard let owner = task.owner, let state = Tasks.states.get(owner), !state.metricsDelivered else { return }
        state.metricsDelivered = true
        let receivers = [state.delegate, sessionDelegate].compactMap { $0 }.filter { $0.responds(to: selector) }
        guard !receivers.isEmpty else { return }
        let metrics = NSURLSessionTaskMetrics.objCClass.autoreleasedInstance()
        NSURLSessionTaskMetrics.states.set(metrics.objcObject, MetricsState(
            start: state.created, end: Date(), request: task.originalRequest.map { Requests.object($0) },
            response: task.response.map(Responses.object), redirectCount: 0))
        typealias Send = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer, UnsafeMutableRawPointer?,
                                         UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
        for receiver in receivers {
            unsafeBitCast(ObjCRuntime.msgSend, to: Send.self)(receiver.objcObject, ObjCRuntime.selector(selector), session, owner,
                                                             metrics.objcObject)
        }
    }
}

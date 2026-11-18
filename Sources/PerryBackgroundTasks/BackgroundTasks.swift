import Glibc
import PerryObjCInterop

// BGTaskScheduler and its requests. Registering and submitting succeed;
// nothing is ever launched.

@ObjCWrapper("NSError")
class NSError: NSObject {
    @ObjCClassMethod("errorWithDomain:code:userInfo:") static func make(domain: String, code: Int, userInfo: NSObject?) -> NSError
}

extension NSObject {
    @ObjCMethod("new") func newInstance() -> NSObject
}

/// An empty NSArray.
private func emptyArray() -> NSObject { NSObject(ObjCClass(named: "NSArray").pointer).newInstance() }

@ObjCClass("BGTaskScheduler")
open class BGTaskScheduler: NSObject {
    nonisolated(unsafe) static var shared = BGTaskScheduler()

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCClassMethod("sharedScheduler") static func sharedScheduler() -> BGTaskScheduler { shared }

    @ObjCMethod("registerForTaskWithIdentifier:usingQueue:launchHandler:")
    func register(identifier: String?, queue: UnsafeMutableRawPointer?, launchHandler: ObjCBlock?) -> Bool { true }

    @ObjCMethod("submitTaskRequest:error:")
    func submit(request: NSObject?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        error?.pointee = nil
        return true
    }

    @ObjCMethod("cancelTaskRequestWithIdentifier:") func cancel(identifier: String?) {}
    @ObjCMethod("cancelAllTaskRequests") func cancelAll() {}

    /// None are pending: the handler, `void (^)(NSArray *)`, gets an empty array.
    @ObjCMethod("getPendingTaskRequestsWithCompletionHandler:")
    func pending(completionHandler: ObjCBlock?) {
        guard let handler = completionHandler else { return }
        handler.function(as: (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void).self)(handler.object, emptyArray().objcObject)
    }
}

@ObjCClass("BGTaskRequest")
open class BGTaskRequest: NSObject {
    var name = ""
    var earliest: NSObject?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithIdentifier:")
    func initialize(identifier: String?) -> Self {
        name = identifier ?? ""
        return self
    }

    @ObjCMethod("identifier") func identifier() -> String { name }
    @ObjCMethod("earliestBeginDate") func earliestBeginDate() -> NSObject? { earliest }
    @ObjCMethod("setEarliestBeginDate:") func setEarliestBeginDate(_ value: NSObject?) { earliest = value }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> NSObject { self }
}

@ObjCClass("BGAppRefreshTaskRequest")
open class BGAppRefreshTaskRequest: BGTaskRequest {}

@ObjCClass("BGProcessingTaskRequest")
open class BGProcessingTaskRequest: BGTaskRequest {
    var network = false, power = false

    @ObjCMethod("requiresNetworkConnectivity") func requiresNetworkConnectivity() -> Bool { network }
    @ObjCMethod("setRequiresNetworkConnectivity:") func setRequiresNetworkConnectivity(_ value: Bool) { network = value }
    @ObjCMethod("requiresExternalPower") func requiresExternalPower() -> Bool { power }
    @ObjCMethod("setRequiresExternalPower:") func setRequiresExternalPower(_ value: Bool) { power = value }
}

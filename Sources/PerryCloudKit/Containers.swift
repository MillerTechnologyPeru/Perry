import Dispatch
import PerryObjCInterop

// CKContainer without iCloud: every container reports that no account is
// signed in, which apps handle by not syncing, and its databases fail each
// request the same way.

@ObjCClass("CKContainer")
open class CKContainer: NSObject {
    nonisolated(unsafe) static var containers: [String: CKContainer] = [:]

    static func named(_ identifier: String) -> CKContainer {
        if let container = containers[identifier] { return container }
        let container = NSObject(objCClass.pointer).newInstance().unsafeCast(to: CKContainer.self)
        containers[identifier] = container
        return container
    }

    @ObjCClassMethod("defaultContainer") static func defaultContainer() -> CKContainer { named("") }
    @ObjCClassMethod("containerWithIdentifier:") static func container(identifier: String) -> CKContainer { named(identifier) }

    /// CKAccountStatusNoAccount 3, with no error, on another queue, as
    /// CloudKit answers: apps start their loading indicators after asking.
    @ObjCMethod("accountStatusWithCompletionHandler:")
    func accountStatus(completionHandler: ObjCBlock?) {
        guard let completionHandler else { return }
        let handler = UnsafeSendableBlock(block: completionHandler)
        DispatchQueue.global().async {
            typealias Invoke = @convention(c) (UnsafeMutableRawPointer, Int, UnsafeMutableRawPointer?) -> Void
            handler.block.function(as: Invoke.self)(handler.block.object, 3, nil)
        }
    }

    @ObjCMethod("containerIdentifier")
    func containerIdentifier() -> String? { CKContainer.containers.first { $0.value.objcObject == objcObject }?.key }

    // The container's databases: one object for them all, which answers
    // every request with the error of an account that is not signed in.
    @ObjCMethod("privateCloudDatabase") func privateCloudDatabase() -> CKDatabase { CKDatabase.shared }
    @ObjCMethod("publicCloudDatabase") func publicCloudDatabase() -> CKDatabase { CKDatabase.shared }
    @ObjCMethod("sharedCloudDatabase") func sharedCloudDatabase() -> CKDatabase { CKDatabase.shared }
}

@ObjCWrapper("NSError")
class NSError: NSObject {
    @ObjCClassMethod("errorWithDomain:code:userInfo:") static func error(domain: String, code: Int, userInfo: NSObject?) -> NSError
}

/// A database without iCloud: records are neither fetched nor saved, and
/// each request's handler is given CKErrorNotAuthenticated, at once, as an
/// operation added to it is (Records.swift).
@ObjCClass("CKDatabase")
open class CKDatabase: NSObject {
    nonisolated(unsafe) static let shared = NSObject(objCClass.pointer).newInstance().unsafeCast(to: CKDatabase.self)

    /// CKErrorNotAuthenticated, 9.
    static func notAuthenticated() -> NSError { NSError.error(domain: CloudKitConstants.CKErrorDomain, code: 9, userInfo: nil) }

    /// Calls a handler that takes a result, none here, and an error.
    private func fail(_ handler: ObjCBlock?) {
        guard let handler else { return }
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
        handler.function(as: Invoke.self)(handler.object, nil, CKDatabase.notAuthenticated().objcObject)
    }

    /// CKDatabaseScope: private, 2.
    @ObjCMethod("databaseScope") func databaseScope() -> Int { 2 }
    @ObjCMethod("addOperation:")
    func addOperation(_ operation: NSObject?) {
        guard let operation, operation.is(CKOperation.self) else { return }
        operation.unsafeCast(to: CKOperation.self).finishWithoutAccount()
    }

    @ObjCMethod("fetchRecordWithID:completionHandler:")
    func fetchRecord(withID id: NSObject?, completionHandler: ObjCBlock?) { fail(completionHandler) }

    @ObjCMethod("saveRecord:completionHandler:")
    func save(record: NSObject?, completionHandler: ObjCBlock?) { fail(completionHandler) }

    @ObjCMethod("deleteRecordWithID:completionHandler:")
    func deleteRecord(withID id: NSObject?, completionHandler: ObjCBlock?) { fail(completionHandler) }

    @ObjCMethod("performQuery:inZoneWithID:completionHandler:")
    func perform(query: NSObject?, inZoneWithID zone: NSObject?, completionHandler: ObjCBlock?) { fail(completionHandler) }

    @ObjCMethod("fetchAllRecordZonesWithCompletionHandler:")
    func fetchAllRecordZones(completionHandler: ObjCBlock?) { fail(completionHandler) }

    @ObjCMethod("fetchAllSubscriptionsWithCompletionHandler:")
    func fetchAllSubscriptions(completionHandler: ObjCBlock?) { fail(completionHandler) }

    @ObjCMethod("saveSubscription:completionHandler:")
    func save(subscription: NSObject?, completionHandler: ObjCBlock?) { fail(completionHandler) }
}

extension NSObject {
    @ObjCMethod("new") func newInstance() -> NSObject
}

@ObjCConstants
enum CloudKitConstants {
    static let CKAccountChangedNotification = "CKAccountChangedNotification"
    static let CKErrorDomain = "CKErrorDomain"
    static let CKCurrentUserDefaultName = "__defaultOwner__"
}

/// A block carried to another queue, which CloudKit calls its completion
/// handlers on.
struct UnsafeSendableBlock: @unchecked Sendable {
    let block: ObjCBlock
}

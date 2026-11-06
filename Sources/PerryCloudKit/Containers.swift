import Dispatch
import PerryObjCInterop

// CKContainer without iCloud: every container reports that no account is
// signed in, which apps handle by not syncing.

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

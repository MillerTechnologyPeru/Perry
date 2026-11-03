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

    /// CKAccountStatusNoAccount 3, with no error.
    @ObjCMethod("accountStatusWithCompletionHandler:")
    func accountStatus(completionHandler: ObjCBlock?) {
        guard let completionHandler else { return }
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, Int, UnsafeMutableRawPointer?) -> Void
        completionHandler.function(as: Invoke.self)(completionHandler.object, 3, nil)
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

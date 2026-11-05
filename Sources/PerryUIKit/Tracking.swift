import PerryObjCInterop

// App Tracking Transparency and AdSupport, as on a device whose user has
// turned tracking off: authorization is denied, asking for it answers
// denied, and the advertising identifier is all zeros.

/// ATTrackingManagerAuthorizationStatus: not determined 0, restricted 1,
/// denied 2, authorized 3.
private let denied: UInt = 2

@ObjCClass("ATTrackingManager")
open class ATTrackingManager: NSObject {
    @ObjCClassMethod("trackingAuthorizationStatus")
    static func trackingAuthorizationStatus() -> UInt { denied }

    /// The handler hears denied after the current pass, as iOS answers
    /// later and on another queue, without showing anything.
    @ObjCClassMethod("requestTrackingAuthorizationWithCompletionHandler:")
    static func requestTrackingAuthorization(completionHandler: ObjCBlock?) {
        guard let completionHandler else { return }
        Updates.afterPass {
            typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UInt) -> Void
            completionHandler.function(as: Invoke.self)(completionHandler.object, denied)
        }
    }
}

@ObjCClass("ASIdentifierManager")
open class ASIdentifierManager: NSObject {
    nonisolated(unsafe) private static var shared: ASIdentifierManager?

    @ObjCClassMethod("sharedManager")
    static func sharedManager() -> ASIdentifierManager {
        if let shared { return shared }
        let manager = ASIdentifierManager.objCClass.object.allocated().initialized().unsafeCast(to: ASIdentifierManager.self)
        shared = manager
        return manager
    }

    /// The zero identifier, as when tracking is off.
    @ObjCMethod("advertisingIdentifier")
    func advertisingIdentifier() -> NSUUID? {
        NSUUID.objCClass.object.allocated().unsafeCast(to: NSUUID.self).initialize(uuidString: "00000000-0000-0000-0000-000000000000")
    }

    @ObjCMethod("isAdvertisingTrackingEnabled") func isAdvertisingTrackingEnabled() -> Bool { false }
    @ObjCMethod("clearAdvertisingIdentifier") func clearAdvertisingIdentifier() {}
}

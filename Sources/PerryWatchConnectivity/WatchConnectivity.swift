import Glibc
import PerryObjCInterop

// WCSession: not supported, never paired, never reachable.

@ObjCWrapper("NSError")
class NSError: NSObject {
    @ObjCClassMethod("errorWithDomain:code:userInfo:") static func make(domain: String, code: Int, userInfo: NSObject?) -> NSError
}

extension NSObject {
    @ObjCMethod("new") func newInstance() -> NSObject
}

/// An empty NSArray.
private func emptyArray() -> NSObject { NSObject(ObjCClass(named: "NSArray").pointer).newInstance() }

@ObjCClass("WCSession")
open class WCSession: NSObject {
    nonisolated(unsafe) static var shared = WCSession()
    var delegate: UnsafeMutableRawPointer?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCClassMethod("isSupported") static func isSupported() -> Bool { false }
    @ObjCClassMethod("defaultSession") static func defaultSession() -> WCSession { shared }

    @ObjCMethod("delegate") func getDelegate() -> NSObject? { delegate.map { NSObject($0) } }
    @ObjCMethod("setDelegate:") func setDelegate(_ value: NSObject?) { delegate = value?.objcObject }
    @ObjCMethod("activateSession") func activate() {}
    /// WCSessionActivationStateNotActivated.
    @ObjCMethod("activationState") func activationState() -> Int { 0 }
    @ObjCMethod("isPaired") func isPaired() -> Bool { false }
    @ObjCMethod("isWatchAppInstalled") func isWatchAppInstalled() -> Bool { false }
    @ObjCMethod("isComplicationEnabled") func isComplicationEnabled() -> Bool { false }
    @ObjCMethod("isReachable") func isReachable() -> Bool { false }
    @ObjCMethod("hasContentPending") func hasContentPending() -> Bool { false }
    @ObjCMethod("applicationContext") func applicationContext() -> NSObject { NSObject(ObjCClass(named: "NSDictionary").pointer).newInstance() }
    @ObjCMethod("receivedApplicationContext") func receivedApplicationContext() -> NSObject { NSObject(ObjCClass(named: "NSDictionary").pointer).newInstance() }
    @ObjCMethod("outstandingUserInfoTransfers") func outstandingUserInfoTransfers() -> NSObject { emptyArray() }
    @ObjCMethod("outstandingFileTransfers") func outstandingFileTransfers() -> NSObject { emptyArray() }

    /// WCErrorCodeSessionNotSupported.
    @ObjCMethod("updateApplicationContext:error:")
    func update(applicationContext: NSObject?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        error?.pointee = NSError.make(domain: "WCErrorDomain", code: 7001, userInfo: nil).objcObject
        return false
    }

    /// The error handler, `void (^)(NSError *)`, is told there is no session.
    @ObjCMethod("sendMessage:replyHandler:errorHandler:")
    func send(message: NSObject?, replyHandler: ObjCBlock?, errorHandler: ObjCBlock?) {
        guard let handler = errorHandler else { return }
        handler.function(as: (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void).self)(
            handler.object, NSError.make(domain: "WCErrorDomain", code: 7001, userInfo: nil).objcObject)
    }

    @ObjCMethod("transferUserInfo:") func transfer(userInfo: NSObject?) -> NSObject? { nil }
    @ObjCMethod("transferCurrentComplicationUserInfo:") func transferComplication(userInfo: NSObject?) -> NSObject? { nil }
}

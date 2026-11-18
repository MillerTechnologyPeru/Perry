import Glibc
import PerryObjCInterop

// PKPushRegistry and what it would give its delegate. No token is ever
// made and no push arrives.

@ObjCWrapper("NSError")
class NSError: NSObject {
    @ObjCClassMethod("errorWithDomain:code:userInfo:") static func make(domain: String, code: Int, userInfo: NSObject?) -> NSError
}

extension NSObject {
    @ObjCMethod("new") func newInstance() -> NSObject
}

/// An empty NSArray.
private func emptyArray() -> NSObject { NSObject(ObjCClass(named: "NSArray").pointer).newInstance() }

/// The push types; their values are their names.
@ObjCConstants
enum PushTypes {
    static let PKPushTypeVoIP = "PKPushTypeVoIP"
    static let PKPushTypeComplication = "PKPushTypeComplication"
    static let PKPushTypeFileProvider = "PKPushTypeFileProvider"
}

@ObjCClass("PKPushRegistry")
open class PKPushRegistry: NSObject {
    var delegate: UnsafeMutableRawPointer?
    var types: NSObject?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithQueue:") func initialize(queue: UnsafeMutableRawPointer?) -> Self { self }
    /// Kept, not retained, and never called.
    @ObjCMethod("delegate") func getDelegate() -> NSObject? { delegate.map { NSObject($0) } }
    @ObjCMethod("setDelegate:") func setDelegate(_ value: NSObject?) { delegate = value?.objcObject }
    @ObjCMethod("desiredPushTypes") func desiredPushTypes() -> NSObject? { types }
    @ObjCMethod("setDesiredPushTypes:") func setDesiredPushTypes(_ value: NSObject?) { types = value }
    @ObjCMethod("pushTokenForType:") func pushToken(forType type: NSObject?) -> NSObject? { nil }
}

@ObjCClass("PKPushCredentials")
open class PKPushCredentials: NSObject {
    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("token") func token() -> NSObject { NSObject(ObjCClass(named: "NSData").pointer).newInstance() }
    @ObjCMethod("type") func type() -> String { PushTypes.PKPushTypeVoIP }
}

@ObjCClass("PKPushPayload")
open class PKPushPayload: NSObject {
    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("dictionaryPayload") func dictionaryPayload() -> NSObject { NSObject(ObjCClass(named: "NSDictionary").pointer).newInstance() }
    @ObjCMethod("type") func type() -> String { PushTypes.PKPushTypeVoIP }
}

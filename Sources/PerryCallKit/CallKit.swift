import Glibc
import PerryObjCInterop

// CallKit's classes. Calls are not made or received here: observers see
// none, a provider's reports go nowhere, and a transaction asked of a call
// controller fails as one does where calling is not allowed.

@ObjCWrapper("NSError")
class NSError: NSObject {
    @ObjCClassMethod("errorWithDomain:code:userInfo:") static func make(domain: String, code: Int, userInfo: NSObject?) -> NSError
}

extension NSObject {
    @ObjCMethod("new") func newInstance() -> NSObject
    @ObjCMethod("addObject:") func sendAddObject(_ object: NSObject)
    @ObjCMethod("count") func sendCount() -> Int
    @ObjCMethod("objectAtIndex:") func sendObject(at index: Int) -> NSObject
}

/// NSArrays, made by Foundation, and read.
enum Arrays {
    static func of(_ objects: [NSObject]) -> NSObject {
        let array = NSObject(ObjCClass(named: "NSMutableArray").pointer).newInstance()
        for object in objects { array.sendAddObject(object) }
        return array
    }

    static func objects(_ array: NSObject) -> [NSObject] {
        guard array.responds(to: "objectAtIndex:") else { return [] }
        return (0..<array.sendCount()).map { array.sendObject(at: $0) }
    }
}

/// An NSError of CallKit's, by domain and code.
private func callError(_ domain: String, _ code: Int) -> NSObject? { NSError.make(domain: domain, code: code, userInfo: nil) }

/// Calls a completion handler, `void (^)(NSError *)`.
private func complete(_ handler: ObjCBlock?, error: NSObject? = nil) {
    guard let handler else { return }
    handler.function(as: (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void).self)(handler.object, error?.objcObject)
}

// MARK: - Observing

/// CXCallObserver: there are never any calls.
@ObjCClass("CXCallObserver")
open class CXCallObserver: NSObject {
    var delegate: UnsafeMutableRawPointer?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("calls") func calls() -> NSObject { NSObject(ObjCClass(named: "NSArray").pointer).newInstance() }
    /// The delegate is kept, not retained, and never told of a call.
    @ObjCMethod("setDelegate:queue:") func setDelegate(_ delegate: NSObject?, queue: UnsafeMutableRawPointer?) { self.delegate = delegate?.objcObject }
}

/// CXCall: none is ever given out; one made by hand has ended.
@ObjCClass("CXCall")
open class CXCall: NSObject {
    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("UUID") func uuid() -> NSObject { NSObject(ObjCClass(named: "NSUUID").pointer).newInstance() }
    @ObjCMethod("isOutgoing") func isOutgoing() -> Bool { false }
    @ObjCMethod("isOnHold") func isOnHold() -> Bool { false }
    @ObjCMethod("hasConnected") func hasConnected() -> Bool { false }
    @ObjCMethod("hasEnded") func hasEnded() -> Bool { true }
}

// MARK: - Handles and updates

@ObjCClass("CXHandle")
open class CXHandle: NSObject {
    var kind = 1
    var text = ""

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithType:value:")
    func initialize(type: Int, value: String?) -> Self {
        (kind, text) = (type, value ?? "")
        return self
    }

    @ObjCMethod("type") func type() -> Int { kind }
    @ObjCMethod("value") func value() -> String { text }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> NSObject { self }
}

/// CXCallUpdate: what an app says of a call, kept as given.
@ObjCClass("CXCallUpdate")
open class CXCallUpdate: NSObject {
    var handle: NSObject?
    var name: String?
    var holding = false, grouping = false, ungrouping = false, dtmf = false, video = false

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("remoteHandle") func remoteHandle() -> NSObject? { handle }
    @ObjCMethod("setRemoteHandle:") func setRemoteHandle(_ value: NSObject?) { handle = value }
    @ObjCMethod("localizedCallerName") func localizedCallerName() -> String? { name }
    @ObjCMethod("setLocalizedCallerName:") func setLocalizedCallerName(_ value: String?) { name = value }
    @ObjCMethod("supportsHolding") func supportsHolding() -> Bool { holding }
    @ObjCMethod("setSupportsHolding:") func setSupportsHolding(_ value: Bool) { holding = value }
    @ObjCMethod("supportsGrouping") func supportsGrouping() -> Bool { grouping }
    @ObjCMethod("setSupportsGrouping:") func setSupportsGrouping(_ value: Bool) { grouping = value }
    @ObjCMethod("supportsUngrouping") func supportsUngrouping() -> Bool { ungrouping }
    @ObjCMethod("setSupportsUngrouping:") func setSupportsUngrouping(_ value: Bool) { ungrouping = value }
    @ObjCMethod("supportsDTMF") func supportsDTMF() -> Bool { dtmf }
    @ObjCMethod("setSupportsDTMF:") func setSupportsDTMF(_ value: Bool) { dtmf = value }
    @ObjCMethod("hasVideo") func hasVideo() -> Bool { video }
    @ObjCMethod("setHasVideo:") func setHasVideo(_ value: Bool) { video = value }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> NSObject { self }
}

// MARK: - Actions

/// CXAction: an identifier, and whether it was fulfilled or failed.
@ObjCClass("CXAction")
open class CXAction: NSObject {
    var identifier = NSObject(ObjCClass(named: "NSUUID").pointer).newInstance()
    var complete = false
    var call: NSObject?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("UUID") func uuid() -> NSObject { identifier }
    @ObjCMethod("isComplete") func isComplete() -> Bool { complete }
    @ObjCMethod("timeoutDate") func timeoutDate() -> NSObject { NSObject(ObjCClass(named: "NSDate").pointer).newInstance() }
    @ObjCMethod("fulfill") func fulfill() { complete = true }
    @ObjCMethod("fail") func fail() { complete = true }
}

@ObjCClass("CXCallAction")
open class CXCallAction: CXAction {
    @ObjCMethod("initWithCallUUID:")
    func initialize(callUUID: NSObject?) -> Self {
        call = callUUID
        return self
    }

    @ObjCMethod("callUUID") func callUUID() -> NSObject { call ?? identifier }
}

@ObjCClass("CXStartCallAction")
open class CXStartCallAction: CXCallAction {
    var handle: NSObject?
    var contact: String?
    var video = false

    @ObjCMethod("initWithCallUUID:handle:")
    func initialize(callUUID: NSObject?, handle: NSObject?) -> Self {
        (call, self.handle) = (callUUID, handle)
        return self
    }

    @ObjCMethod("handle") func getHandle() -> NSObject? { handle }
    @ObjCMethod("setHandle:") func setHandle(_ value: NSObject?) { handle = value }
    @ObjCMethod("contactIdentifier") func contactIdentifier() -> String? { contact }
    @ObjCMethod("setContactIdentifier:") func setContactIdentifier(_ value: String?) { contact = value }
    @ObjCMethod("isVideo") func isVideo() -> Bool { video }
    @ObjCMethod("setVideo:") func setVideo(_ value: Bool) { video = value }
    @ObjCMethod("fulfillWithDateStarted:") func fulfill(dateStarted: NSObject?) { complete = true }
}

@ObjCClass("CXAnswerCallAction")
open class CXAnswerCallAction: CXCallAction {
    @ObjCMethod("fulfillWithDateConnected:") func fulfill(dateConnected: NSObject?) { complete = true }
}

@ObjCClass("CXEndCallAction")
open class CXEndCallAction: CXCallAction {
    @ObjCMethod("fulfillWithDateEnded:") func fulfill(dateEnded: NSObject?) { complete = true }
}

@ObjCClass("CXSetMutedCallAction")
open class CXSetMutedCallAction: CXCallAction {
    var muted = false

    @ObjCMethod("initWithCallUUID:muted:")
    func initialize(callUUID: NSObject?, muted: Bool) -> Self {
        (call, self.muted) = (callUUID, muted)
        return self
    }

    @ObjCMethod("isMuted") func isMuted() -> Bool { muted }
    @ObjCMethod("setMuted:") func setMuted(_ value: Bool) { muted = value }
}

@ObjCClass("CXSetHeldCallAction")
open class CXSetHeldCallAction: CXCallAction {
    var held = false

    @ObjCMethod("initWithCallUUID:onHold:")
    func initialize(callUUID: NSObject?, onHold: Bool) -> Self {
        (call, held) = (callUUID, onHold)
        return self
    }

    @ObjCMethod("isOnHold") func isOnHold() -> Bool { held }
    @ObjCMethod("setOnHold:") func setOnHold(_ value: Bool) { held = value }
}

/// CXTransaction: the actions an app asks for together.
@ObjCClass("CXTransaction")
open class CXTransaction: NSObject {
    var list: [NSObject] = []
    var identifier = NSObject(ObjCClass(named: "NSUUID").pointer).newInstance()

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithAction:")
    func initialize(action: NSObject?) -> Self {
        if let action { list = [action] }
        return self
    }

    @ObjCMethod("initWithActions:")
    func initialize(actions: NSObject?) -> Self {
        if let actions { list = Arrays.objects(actions) }
        return self
    }

    @ObjCMethod("UUID") func uuid() -> NSObject { identifier }
    @ObjCMethod("isComplete") func isComplete() -> Bool { true }
    @ObjCMethod("actions") func actions() -> NSObject { Arrays.of(list) }
    @ObjCMethod("addAction:") func add(action: NSObject?) { if let action { list.append(action) } }
}

// MARK: - Provider and controller

/// CXProviderConfiguration: kept as given.
@ObjCClass("CXProviderConfiguration")
open class CXProviderConfiguration: NSObject {
    var name: String?
    var ringtone: String?
    var icon: NSObject?
    var groups = 2, perGroup = 5
    var recents = true, video = false
    var handleTypes: NSObject?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithLocalizedName:")
    func initialize(localizedName: String?) -> Self {
        name = localizedName
        return self
    }

    @ObjCMethod("localizedName") func localizedName() -> String? { name }
    @ObjCMethod("ringtoneSound") func ringtoneSound() -> String? { ringtone }
    @ObjCMethod("setRingtoneSound:") func setRingtoneSound(_ value: String?) { ringtone = value }
    @ObjCMethod("iconTemplateImageData") func iconTemplateImageData() -> NSObject? { icon }
    @ObjCMethod("setIconTemplateImageData:") func setIconTemplateImageData(_ value: NSObject?) { icon = value }
    @ObjCMethod("maximumCallGroups") func maximumCallGroups() -> Int { groups }
    @ObjCMethod("setMaximumCallGroups:") func setMaximumCallGroups(_ value: Int) { groups = value }
    @ObjCMethod("maximumCallsPerCallGroup") func maximumCallsPerCallGroup() -> Int { perGroup }
    @ObjCMethod("setMaximumCallsPerCallGroup:") func setMaximumCallsPerCallGroup(_ value: Int) { perGroup = value }
    @ObjCMethod("includesCallsInRecents") func includesCallsInRecents() -> Bool { recents }
    @ObjCMethod("setIncludesCallsInRecents:") func setIncludesCallsInRecents(_ value: Bool) { recents = value }
    @ObjCMethod("supportsVideo") func supportsVideo() -> Bool { video }
    @ObjCMethod("setSupportsVideo:") func setSupportsVideo(_ value: Bool) { video = value }
    @ObjCMethod("supportedHandleTypes") func supportedHandleTypes() -> NSObject? { handleTypes }
    @ObjCMethod("setSupportedHandleTypes:") func setSupportedHandleTypes(_ value: NSObject?) { handleTypes = value }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> NSObject { self }
}

/// CXProvider: an app's side of its calls. What it reports goes nowhere, and a new incoming call can't be shown:
/// CXErrorCodeIncomingCallErrorUnentitled.
@ObjCClass("CXProvider")
open class CXProvider: NSObject {
    var settings: NSObject?
    var delegate: UnsafeMutableRawPointer?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithConfiguration:")
    func initialize(configuration: NSObject?) -> Self {
        settings = configuration
        return self
    }

    @ObjCMethod("configuration") func configuration() -> NSObject? { settings }
    @ObjCMethod("setConfiguration:") func setConfiguration(_ value: NSObject?) { settings = value }
    @ObjCMethod("setDelegate:queue:") func setDelegate(_ delegate: NSObject?, queue: UnsafeMutableRawPointer?) { self.delegate = delegate?.objcObject }
    @ObjCMethod("pendingTransactions") func pendingTransactions() -> NSObject { Arrays.of([]) }
    @ObjCMethod("pendingCallActionsOfClass:withCallUUID:") func pendingCallActions(ofClass cls: UnsafeRawPointer?, callUUID: NSObject?) -> NSObject { Arrays.of([]) }
    @ObjCMethod("invalidate") func invalidate() {}

    @ObjCMethod("reportNewIncomingCallWithUUID:update:completion:")
    func reportNewIncomingCall(uuid: NSObject?, update: NSObject?, completion: ObjCBlock?) {
        complete(completion, error: callError("com.apple.CallKit.error.incomingcall", 1))
    }

    @ObjCMethod("reportCallWithUUID:updated:") func reportCall(uuid: NSObject?, updated: NSObject?) {}
    @ObjCMethod("reportCallWithUUID:endedAtDate:reason:") func reportCall(uuid: NSObject?, endedAt date: NSObject?, reason: Int) {}
    @ObjCMethod("reportOutgoingCallWithUUID:startedConnectingAtDate:") func reportOutgoingCall(uuid: NSObject?, startedConnectingAt date: NSObject?) {}
    @ObjCMethod("reportOutgoingCallWithUUID:connectedAtDate:") func reportOutgoingCall(uuid: NSObject?, connectedAt date: NSObject?) {}

    @ObjCClassMethod("reportNewIncomingVoIPPushPayload:completion:")
    static func reportNewIncomingVoIPPush(payload: NSObject?, completion: ObjCBlock?) {
        complete(completion, error: callError("com.apple.CallKit.error.incomingcall", 1))
    }
}

/// CXCallController: an app's requests of the system's calls, which fail: CXErrorCodeRequestTransactionErrorUnentitled.
@ObjCClass("CXCallController")
open class CXCallController: NSObject {
    var observer = CXCallObserver()

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithQueue:") func initialize(queue: UnsafeMutableRawPointer?) -> Self { self }
    @ObjCMethod("callObserver") func callObserver() -> CXCallObserver { observer }

    @ObjCMethod("requestTransaction:completion:")
    func request(transaction: NSObject?, completion: ObjCBlock?) { complete(completion, error: callError("com.apple.CallKit.error.requesttransaction", 1)) }

    @ObjCMethod("requestTransactionWithActions:completion:")
    func request(actions: NSObject?, completion: ObjCBlock?) { complete(completion, error: callError("com.apple.CallKit.error.requesttransaction", 1)) }

    @ObjCMethod("requestTransactionWithAction:completion:")
    func request(action: NSObject?, completion: ObjCBlock?) { complete(completion, error: callError("com.apple.CallKit.error.requesttransaction", 1)) }
}

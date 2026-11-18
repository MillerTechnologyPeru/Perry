import Glibc
import PerryObjCInterop

// LAContext: no policy can be evaluated, as on a device with no passcode.

@ObjCWrapper("NSError")
class NSError: NSObject {
    @ObjCClassMethod("errorWithDomain:code:userInfo:") static func make(domain: String, code: Int, userInfo: NSObject?) -> NSError
}

extension NSObject {
    @ObjCMethod("new") func newInstance() -> NSObject
}

/// An empty NSArray.
private func emptyArray() -> NSObject { NSObject(ObjCClass(named: "NSArray").pointer).newInstance() }

@ObjCConstants
enum AuthenticationConstants {
    static let LAErrorDomain = "com.apple.LocalAuthentication"
}

/// LAErrorPasscodeNotSet.
private func notSet() -> NSObject? { NSError.make(domain: AuthenticationConstants.LAErrorDomain, code: -5, userInfo: nil) }

@ObjCClass("LAContext")
open class LAContext: NSObject {
    var fallback: String?, cancel: String?, reason: String?
    var reuse: Double = 0
    var notAllowed = false

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("canEvaluatePolicy:error:")
    func canEvaluate(policy: Int, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        error?.pointee = notSet()?.objcObject
        return false
    }

    /// The reply, `void (^)(BOOL, NSError *)`, is called at once with the failure.
    @ObjCMethod("evaluatePolicy:localizedReason:reply:")
    func evaluate(policy: Int, localizedReason: String?, reply: ObjCBlock?) {
        guard let reply else { return }
        reply.function(as: (@convention(c) (UnsafeMutableRawPointer?, Bool, UnsafeMutableRawPointer?) -> Void).self)(reply.object, false, notSet()?.objcObject)
    }

    @ObjCMethod("invalidate") func invalidate() {}
    /// LABiometryTypeNone.
    @ObjCMethod("biometryType") func biometryType() -> Int { 0 }
    @ObjCMethod("evaluatedPolicyDomainState") func evaluatedPolicyDomainState() -> NSObject? { nil }
    @ObjCMethod("localizedFallbackTitle") func localizedFallbackTitle() -> String? { fallback }
    @ObjCMethod("setLocalizedFallbackTitle:") func setLocalizedFallbackTitle(_ value: String?) { fallback = value }
    @ObjCMethod("localizedCancelTitle") func localizedCancelTitle() -> String? { cancel }
    @ObjCMethod("setLocalizedCancelTitle:") func setLocalizedCancelTitle(_ value: String?) { cancel = value }
    @ObjCMethod("localizedReason") func localizedReason() -> String { reason ?? "" }
    @ObjCMethod("setLocalizedReason:") func setLocalizedReason(_ value: String?) { reason = value }
    @ObjCMethod("touchIDAuthenticationAllowableReuseDuration") func allowableReuseDuration() -> Double { reuse }
    @ObjCMethod("setTouchIDAuthenticationAllowableReuseDuration:") func setAllowableReuseDuration(_ value: Double) { reuse = value }
    @ObjCMethod("interactionNotAllowed") func interactionNotAllowed() -> Bool { notAllowed }
    @ObjCMethod("setInteractionNotAllowed:") func setInteractionNotAllowed(_ value: Bool) { notAllowed = value }
    @ObjCMethod("setCredential:type:") func setCredential(_ credential: NSObject?, type: Int) -> Bool { false }
    @ObjCMethod("isCredentialSet:") func isCredentialSet(_ type: Int) -> Bool { false }
}

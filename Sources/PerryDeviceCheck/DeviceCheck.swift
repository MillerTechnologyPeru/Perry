import Glibc
import PerryObjCInterop

// DCDevice and DCAppAttestService: not supported. Their handlers get
// DCErrorFeatureUnsupported.

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
enum DeviceCheckConstants {
    static let DCErrorDomain = "com.apple.devicecheck.error"
}

/// Calls a handler of `void (^)(id, NSError *)` with DCErrorFeatureUnsupported.
private func unsupported(_ handler: ObjCBlock?) {
    guard let handler else { return }
    handler.function(as: (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void).self)(
        handler.object, nil, NSError.make(domain: DeviceCheckConstants.DCErrorDomain, code: 1, userInfo: nil).objcObject)
}

@ObjCClass("DCDevice")
open class DCDevice: NSObject {
    nonisolated(unsafe) static var shared = DCDevice()

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCClassMethod("currentDevice") static func currentDevice() -> DCDevice { shared }
    @ObjCMethod("isSupported") func isSupported() -> Bool { false }
    @ObjCMethod("generateTokenWithCompletionHandler:") func generateToken(completionHandler: ObjCBlock?) { unsupported(completionHandler) }
}

@ObjCClass("DCAppAttestService")
open class DCAppAttestService: NSObject {
    nonisolated(unsafe) static var shared = DCAppAttestService()

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCClassMethod("sharedService") static func sharedService() -> DCAppAttestService { shared }
    @ObjCMethod("isSupported") func isSupported() -> Bool { false }
    @ObjCMethod("generateKeyWithCompletionHandler:") func generateKey(completionHandler: ObjCBlock?) { unsupported(completionHandler) }

    @ObjCMethod("attestKey:clientDataHash:completionHandler:")
    func attest(key: String?, clientDataHash: NSObject?, completionHandler: ObjCBlock?) { unsupported(completionHandler) }

    @ObjCMethod("generateAssertion:clientDataHash:completionHandler:")
    func assertion(key: String?, clientDataHash: NSObject?, completionHandler: ObjCBlock?) { unsupported(completionHandler) }
}

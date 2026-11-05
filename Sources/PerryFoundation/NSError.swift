import CPerryFoundation
import Glibc
import PerryObjCInterop

enum Errors {
    nonisolated(unsafe) static var errorClass: Class!
    static var cocoaDomain: id { ErrorConstants.NSCocoaErrorDomainObject }
    static var localizedDescriptionKey: id { ErrorConstants.NSLocalizedDescriptionKeyObject }

    /// Where an NSError keeps its code, domain and user info: Apple's
    /// instance variables, after a reserved word. Swift's runtime reads and
    /// fills them in its errors boxed as NSErrors, and takes an NSError
    /// whose domain is set for one already made.
    static let codeOffset = 16, domainOffset = 24, userInfoOffset = 32

    static func isError(_ object: id?) -> Bool {
        guard let object else { return false }
        return ObjCRuntime.isKind(object, of: UnsafeMutableRawPointer(errorClass))
    }

    /// An error's domain, code and user info.
    static func parts(_ object: id?) -> (domain: id?, code: Int, userInfo: id?)? {
        guard let object, isError(object) else { return nil }
        return (object.load(fromByteOffset: domainOffset, as: id?.self),
                object.load(fromByteOffset: codeOffset, as: Int.self),
                object.load(fromByteOffset: userInfoOffset, as: id?.self))
    }

    /// Sets an error's domain, code and user info, copying them. The domain
    /// goes last: once set, the error is made.
    static func initialize(_ object: id, domain: id?, code: Int, userInfo: id?) {
        let oldDomain = object.load(fromByteOffset: domainOffset, as: id?.self)
        let oldUserInfo = object.load(fromByteOffset: userInfoOffset, as: id?.self)
        object.storeBytes(of: code, toByteOffset: codeOffset, as: Int.self)
        object.storeBytes(of: ObjC.send(userInfo, Selectors.copyWithZone, nil), toByteOffset: userInfoOffset, as: id?.self)
        object.storeBytes(of: ObjC.send(domain, Selectors.copyWithZone, nil), toByteOffset: domainOffset, as: id?.self)
        ObjC.release(oldDomain)
        ObjC.release(oldUserInfo)
    }

    /// Releases an error's domain and user info, as it is deallocated.
    static func deinitialize(_ object: id) {
        ObjC.release(object.load(fromByteOffset: domainOffset, as: id?.self))
        ObjC.release(object.load(fromByteOffset: userInfoOffset, as: id?.self))
    }

    /// A new error (+1).
    static func make(domain: id?, code: Int, userInfo: id?) -> id? {
        guard let error = ObjC.createInstance(errorClass, 0) else { return nil }
        initialize(error, domain: domain, code: code, userInfo: userInfo)
        return error
    }

    static func autoreleased(domain: id?, code: Int, description: String?) -> id? {
        let userInfo = description.map {
            Dictionaries.autoreleased([(key: localizedDescriptionKey, value: Strings.autoreleased($0))])
        }
        return ObjC.autorelease(make(domain: domain, code: code, userInfo: userInfo))
    }

    /// Blocks that supply user info values an error's dictionary lacks, by
    /// domain: id (^)(NSError *error, NSString *key).
    nonisolated(unsafe) static var providers: [String: id] = [:]

    /// The user info's value for `key`, or else its domain's provider's.
    static func value(_ object: id?, _ key: id) -> id? {
        guard let parts = parts(object) else { return nil }
        if let value = Dictionaries.value(parts.userInfo, for: key) { return value }
        guard let object, let domain = Strings.value(of: parts.domain), let provider = providers[domain] else { return nil }
        return Blocks.invoke(provider, as: (@convention(c) (id, id, id) -> id?).self)(provider, object, key)
    }

    /// A new error (+1) whose user info has `entries`.
    static func make(domain: id?, code: Int, entries: [(String, id)]) -> id? {
        make(domain: domain, code: code,
             userInfo: Dictionaries.autoreleased(entries.map { (key: Strings.autoreleased($0.0), value: $0.1) }))
    }

    /// The user info's description, or Foundation's generic one.
    static func localizedDescription(_ object: id?) -> String {
        guard let parts = parts(object) else { return "" }
        if let description = Strings.value(of: value(object, localizedDescriptionKey)) {
            return description
        }
        let domain = Strings.value(of: parts.domain) ?? ""
        if domain == "NSPOSIXErrorDomain", let message = posixMessage(Int32(truncatingIfNeeded: parts.code)) {
            return "The operation couldn’t be completed. \(message)"
        }
        return "The operation couldn’t be completed. (\(domain) error \(parts.code).)"
    }

    /// strerror for a Darwin errno: libSystem's, which knows Darwin's numbers.
    static func posixMessage(_ code: Int32) -> String? {
        typealias StrError = @convention(c) (Int32) -> UnsafePointer<CChar>?
        let darwin = dlsym(UnsafeMutableRawPointer(bitPattern: 0), "_strerror").map { unsafeBitCast($0, to: StrError.self) }
        return (darwin?(code) ?? UnsafePointer(strerror(code))).map { String(cString: $0) }
    }

}

/// Error domains and user info keys.
@ObjCConstants
enum ErrorConstants {
    static let NSCocoaErrorDomain = "NSCocoaErrorDomain"
    static let NSPOSIXErrorDomain = "NSPOSIXErrorDomain"
    static let NSLocalizedDescriptionKey = "NSLocalizedDescription"
    static let NSLocalizedFailureReasonErrorKey = "NSLocalizedFailureReason"
    static let NSFilePathErrorKey = "NSFilePath"
    static let NSUnderlyingErrorKey = "NSUnderlyingError"
    static let NSDebugDescriptionErrorKey = "NSDebugDescription"
    static let NSOSStatusErrorDomain = "NSOSStatusErrorDomain"
    static let NSMachErrorDomain = "NSMachErrorDomain"
    static let NSLocalizedRecoverySuggestionErrorKey = "NSLocalizedRecoverySuggestion"
    static let NSLocalizedRecoveryOptionsErrorKey = "NSLocalizedRecoveryOptions"
    static let NSRecoveryAttempterErrorKey = "NSRecoveryAttempter"
    static let NSHelpAnchorErrorKey = "NSHelpAnchor"
    // CoreFoundation's names for the same objects.
    static let kCFErrorDomainCocoa = NSCocoaErrorDomain
    static let kCFErrorDomainPOSIX = NSPOSIXErrorDomain
    static let kCFErrorDomainOSStatus = NSOSStatusErrorDomain
    static let kCFErrorDomainMach = NSMachErrorDomain
    static let kCFErrorLocalizedDescriptionKey = NSLocalizedDescriptionKey
    static let kCFErrorLocalizedFailureReasonKey = NSLocalizedFailureReasonErrorKey
    static let kCFErrorLocalizedRecoverySuggestionKey = NSLocalizedRecoverySuggestionErrorKey
    static let kCFErrorUnderlyingErrorKey = NSUnderlyingErrorKey
    static let kCFErrorFilePathKey = NSFilePathErrorKey
    static let kCFErrorDescriptionKey = "NSDescription"
}

/// NSError.
@ObjCClass("NSError")
public final class NSError: NSObject {
    /// Set-up after the class is defined.
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        Errors.errorClass = cls.storage
    }

    /// Apple's, which Swift's runtime reads (Errors.codeOffset…).
    override public class var objCInstanceVariables: [ObjCInstanceVariable] {
        [ObjCInstanceVariable("_reserved", types: "^v"), ObjCInstanceVariable("_code", types: "q"),
         ObjCInstanceVariable("_domain", types: "@\"NSString\""), ObjCInstanceVariable("_userInfo", types: "@\"NSDictionary\"")]
    }

    private var parts: (domain: id?, code: Int, userInfo: id?)? { Errors.parts(objcObject) }

    @ObjCClassMethod("errorWithDomain:code:userInfo:")
    static func error(_ cls: ObjCClass, domain: ObjCObject, code: Int, userInfo: ObjCObject?) -> NSError? {
        guard let error = ObjC.createInstance(cls.storage, 0) else { return nil }
        Errors.initialize(error, domain: domain.id, code: code, userInfo: userInfo?.id)
        return NSError(objCOwned: error)
    }

    @ObjCClassMethod("setUserInfoValueProviderForDomain:provider:")
    static func setUserInfoValueProvider(_ cls: ObjCClass, domain: String, provider: ObjCObject?) {
        ObjC.release(Errors.providers[domain])
        Errors.providers[domain] = provider.flatMap { ObjC.retainBlock($0.id) }
    }

    @ObjCClassMethod("userInfoValueProviderForDomain:")
    static func userInfoValueProvider(_ cls: ObjCClass, domain: String) -> ObjCObject? {
        Errors.providers[domain].map(ObjCObject.init)
    }

    @ObjCMethod("initWithDomain:code:userInfo:")
    func initialize(domain: ObjCObject, code: Int, userInfo: ObjCObject?) -> Self {
        Errors.initialize(objcObject, domain: domain.id, code: code, userInfo: userInfo?.id)
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Errors.deinitialize(objcObject)
        ObjC.superDealloc(objcObject, from: Errors.errorClass)
    }

    @ObjCMethod("domain") func domain() -> ObjCObject? { parts?.domain.map(ObjCObject.init) }
    @ObjCMethod("code") func code() -> Int { parts?.code ?? 0 }

    @ObjCMethod("userInfo")
    func userInfo() -> ObjCObject { ObjCObject(parts?.userInfo ?? Dictionaries.autoreleased([])) }

    @ObjCMethod("localizedDescription") func localizedDescription() -> String { Errors.localizedDescription(objcObject) }

    @ObjCMethod("localizedRecoverySuggestion")
    func localizedRecoverySuggestion() -> ObjCObject? {
        Errors.value(objcObject, ErrorConstants.NSLocalizedRecoverySuggestionErrorKeyObject).map(ObjCObject.init)
    }

    @ObjCMethod("localizedFailureReason")
    func localizedFailureReason() -> ObjCObject? {
        Errors.value(objcObject, ErrorConstants.NSLocalizedFailureReasonErrorKeyObject).map(ObjCObject.init)
    }

    /// Error Domain=D Code=1 "description" UserInfo={key=value}
    @ObjCMethod("description")
    func description() -> String {
        guard let parts = Errors.parts(objcObject) else { return "" }
        // The quoted part is the user info's description, not the generic one.
        let described = Strings.value(of: Dictionaries.value(parts.userInfo, for: Errors.localizedDescriptionKey))
        var text = "Error Domain=\(Strings.value(of: parts.domain) ?? "") Code=\(parts.code) "
            + "\"\(described ?? "(null)")\""
        let entries = Dictionaries.entries(parts.userInfo)
        if !entries.isEmpty {
            let pairs = entries.map { "\(Format.describe($0.key))=\(Format.describe($0.value))" }
            text += " UserInfo={" + pairs.joined(separator: ", ") + "}"
        }
        return text
    }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: ObjCObject?) -> Bool {
        guard let other, let a = Errors.parts(objcObject), let b = Errors.parts(other.id) else { return other?.id == objcObject }
        return a.code == b.code && Strings.value(of: a.domain) == Strings.value(of: b.domain)
    }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> NSError { self }
}

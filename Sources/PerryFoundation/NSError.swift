import CPerryFoundation
import PerryObjCInterop

/// An NSError's domain, code and user info.
final class ErrorStorage {
    let domain: id?
    let code: Int
    let userInfo: id?

    init(domain: id?, code: Int, userInfo: id?) {
        self.domain = ObjC.send(domain, Selectors.copyWithZone, nil)
        self.code = code
        self.userInfo = ObjC.send(userInfo, Selectors.copyWithZone, nil)
    }

    deinit {
        ObjC.release(domain)
        ObjC.release(userInfo)
    }
}

enum Errors {
    nonisolated(unsafe) static var errorClass: Class!
    static var cocoaDomain: id { ErrorConstants.NSCocoaErrorDomainObject }
    static var localizedDescriptionKey: id { ErrorConstants.NSLocalizedDescriptionKeyObject }

    static func storage(_ object: id?) -> ErrorStorage? {
        Storage.get(object, as: ErrorStorage.self)
    }

    static func autoreleased(domain: id?, code: Int, description: String?) -> id? {
        let userInfo = description.map {
            Dictionaries.autoreleased([(key: localizedDescriptionKey, value: Strings.autoreleased($0))])
        }
        guard let error = Storage.allocate(UnsafeMutableRawPointer(errorClass)) else { return nil }
        Storage.set(error, ErrorStorage(domain: domain, code: code, userInfo: userInfo))
        return ObjC.autorelease(error)
    }

    /// Blocks that supply user info values an error's dictionary lacks, by
    /// domain: id (^)(NSError *error, NSString *key).
    nonisolated(unsafe) static var providers: [String: id] = [:]

    /// The user info's value for `key`, or else its domain's provider's.
    static func value(_ object: id?, _ key: id) -> id? {
        guard let storage = storage(object) else { return nil }
        if let value = Dictionaries.value(storage.userInfo, for: key) { return value }
        guard let object, let domain = Strings.value(of: storage.domain), let provider = providers[domain] else { return nil }
        return Blocks.invoke(provider, as: (@convention(c) (id, id, id) -> id?).self)(provider, object, key)
    }

    /// The user info's description, or Foundation's generic one.
    static func localizedDescription(_ object: id?) -> String {
        guard let storage = storage(object) else { return "" }
        if let description = Strings.value(of: value(object, localizedDescriptionKey)) {
            return description
        }
        let domain = Strings.value(of: storage.domain) ?? ""
        return "The operation couldn’t be completed. (\(domain) error \(storage.code).)"
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
}

/// NSError.
@ObjCClass("NSError")
public final class NSError: NSObject {
    /// Set-up after the class is defined.
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Errors.errorClass = cls.storage
    }

    private var storage: ErrorStorage? { Errors.storage(objcObject) }

    @ObjCClassMethod("errorWithDomain:code:userInfo:")
    static func error(_ cls: ObjCClass, domain: ObjCObject, code: Int, userInfo: ObjCObject?) -> NSError? {
        guard let error = Storage.allocate(cls.pointer) else { return nil }
        Storage.set(error, ErrorStorage(domain: domain.id, code: code, userInfo: userInfo?.id))
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
        Storage.set(objcObject, ErrorStorage(domain: domain.id, code: code, userInfo: userInfo?.id))
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Errors.errorClass)
    }

    @ObjCMethod("domain") func domain() -> ObjCObject? { storage?.domain.map(ObjCObject.init) }
    @ObjCMethod("code") func code() -> Int { storage?.code ?? 0 }

    @ObjCMethod("userInfo")
    func userInfo() -> ObjCObject { ObjCObject(storage?.userInfo ?? Dictionaries.autoreleased([])) }

    @ObjCMethod("localizedDescription") func localizedDescription() -> String { Errors.localizedDescription(objcObject) }

    @ObjCMethod("localizedFailureReason")
    func localizedFailureReason() -> ObjCObject? {
        Dictionaries.value(storage?.userInfo, for: Strings.autoreleased("NSLocalizedFailureReason")).map(ObjCObject.init)
    }

    /// Error Domain=D Code=1 "description" UserInfo={key=value}
    @ObjCMethod("description")
    func description() -> String {
        guard let storage else { return "" }
        // The quoted part is the user info's description, not the generic one.
        let described = Strings.value(of: Dictionaries.value(storage.userInfo, for: Errors.localizedDescriptionKey))
        var text = "Error Domain=\(Strings.value(of: storage.domain) ?? "") Code=\(storage.code) "
            + "\"\(described ?? "(null)")\""
        let entries = Dictionaries.entries(storage.userInfo)
        if !entries.isEmpty {
            let pairs = entries.map { "\(Format.describe($0.key))=\(Format.describe($0.value))" }
            text += " UserInfo={" + pairs.joined(separator: ", ") + "}"
        }
        return text
    }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: ObjCObject?) -> Bool {
        guard let other, let a = storage, let b = Errors.storage(other.id) else { return other?.id == objcObject }
        return a.code == b.code && Strings.value(of: a.domain) == Strings.value(of: b.domain)
    }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> NSError { self }
}

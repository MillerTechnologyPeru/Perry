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
    nonisolated(unsafe) static var cocoaDomain: id!
    nonisolated(unsafe) static var localizedDescriptionKey: id!

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

    /// The user info's description, or Foundation's generic one.
    static func localizedDescription(_ object: id?) -> String {
        guard let storage = storage(object) else { return "" }
        if let description = Strings.value(of: Dictionaries.value(storage.userInfo, for: localizedDescriptionKey)) {
            return description
        }
        let domain = Strings.value(of: storage.domain) ?? ""
        return "The operation couldn’t be completed. (\(domain) error \(storage.code).)"
    }

    static func install(superclass: Class) {
        errorClass = ClassDefinition(PERRY_CLASS_NSError, name: "NSError", superclass: superclass,
                                     StorageAllocated.register, NSError.register).cls
        func constant(_ which: perry_foundation_constant_id, _ value: String) -> id {
            let string = Strings.make(value)
            perry_foundation_constant(which).pointee = string
            return string
        }
        cocoaDomain = constant(PERRY_CONSTANT_NSCocoaErrorDomain, "NSCocoaErrorDomain")
        _ = constant(PERRY_CONSTANT_NSPOSIXErrorDomain, "NSPOSIXErrorDomain")
        localizedDescriptionKey = constant(PERRY_CONSTANT_NSLocalizedDescriptionKey, "NSLocalizedDescription")
        _ = constant(PERRY_CONSTANT_NSFilePathErrorKey, "NSFilePath")
        _ = constant(PERRY_CONSTANT_NSUnderlyingErrorKey, "NSUnderlyingError")
    }
}

/// NSError.
@ObjCClass("NSError")
public struct NSError {}

@ObjCImplementation
extension NSError {
    private var storage: ErrorStorage? { Errors.storage(objcObject) }

    @ObjCClassMethod("errorWithDomain:code:userInfo:")
    static func error(_ cls: ObjCClass, domain: ObjCObject, code: Int, userInfo: ObjCObject?) -> NSError? {
        guard let error = Storage.allocate(cls.pointer) else { return nil }
        Storage.set(error, ErrorStorage(domain: domain.id, code: code, userInfo: userInfo?.id))
        return NSError(objCOwned: error)
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

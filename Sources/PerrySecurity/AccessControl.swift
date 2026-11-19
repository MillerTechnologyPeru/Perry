import PerryObjCInterop

// SecAccessControl: when a keychain item may be read (its protection, a
// kSecAttrAccessible value) and what must be shown first (flags: a passcode,
// biometry). It is kept as made; the keychain here has no passcode or
// biometry, and takes an item's access control as given (kSecAttrAccessControl
// is accepted and not enforced).

final class AccessControlState {
    /// The kSecAttrAccessible value, retained.
    let protection: UnsafeMutableRawPointer?
    /// SecAccessControlCreateFlags.
    let flags: UInt

    init(protection: UnsafeMutableRawPointer?, flags: UInt) {
        self.protection = ObjCRuntime.retain(protection)
        self.flags = flags
    }

    deinit { ObjCRuntime.release(protection) }
}

@ObjCClass("__SecAccessControl")
final class SecAccessControlObject: NSObject {
    static let states = StateTable<AccessControlState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        SecAccessControlObject.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SecAccessControlObject.objCClass.pointer)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { TypeIDs.accessControl }
}

@c(_SecAccessControlGetTypeID) public func SecAccessControlGetTypeID() -> UInt { TypeIDs.accessControl }

/// A new access control (+1). A missing protection is an error, as on iOS.
@c(_SecAccessControlCreateWithFlags)
public func SecAccessControlCreateWithFlags(_ allocator: UnsafeRawPointer?, _ protection: UnsafeMutableRawPointer?, _ flags: UInt,
                                            _ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UnsafeMutableRawPointer? {
    guard let protection else {
        error?.pointee = ObjCRuntime.retain(NSError.make(domain: "NSOSStatusErrorDomain", code: -50, userInfo: nil).objcObject)
        return nil
    }
    let object = SecAccessControlObject.objCClass.ownedInstance()
    SecAccessControlObject.states.set(object, AccessControlState(protection: protection, flags: flags))
    return object
}

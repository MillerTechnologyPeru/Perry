import Glibc

// The keychain API from before SecItem: identity searches, generic and
// internet passwords, the default keychain and its callbacks. There are no
// keychain files here, so every search ends at once and finds nothing, as
// it does on a Mac with an empty keychain; there is no default keychain,
// and items can't be added (programs then keep what they would have stored
// for the session, or ask again).

private let itemNotFound: Int32 = -25300        // errSecItemNotFound
private let notAvailable: Int32 = -25291        // errSecNotAvailable
private let noDefaultKeychain: Int32 = -25307   // errSecNoDefaultKeychain
private let invalidItem: Int32 = -25304         // errSecInvalidItemRef
private let policyNotFound: Int32 = -25241      // errSecPolicyNotFound

public typealias SecOut = UnsafeMutablePointer<UnsafeMutableRawPointer?>

// MARK: - Identity searches

@c(_SecIdentitySearchCreate)
public func SecIdentitySearchCreate(_ keychainOrArray: UnsafeMutableRawPointer?, _ keyUsage: UInt32, _ search: SecOut?) -> Int32 {
    search?.pointee = nil
    return itemNotFound
}

@c(_SecIdentitySearchCreateWithPolicy)
public func SecIdentitySearchCreateWithPolicy(_ policy: UnsafeMutableRawPointer?, _ identifier: UnsafeMutableRawPointer?, _ keyUsage: UInt32,
                                              _ keychainOrArray: UnsafeMutableRawPointer?, _ validOnly: UInt8, _ search: SecOut?) -> Int32 {
    search?.pointee = nil
    return itemNotFound
}

@c(_SecIdentitySearchCopyNext)
public func SecIdentitySearchCopyNext(_ search: UnsafeMutableRawPointer?, _ identity: SecOut?) -> Int32 {
    identity?.pointee = nil
    return itemNotFound
}

// MARK: - Keychains

@c(_SecKeychainCopyDefault)
public func SecKeychainCopyDefault(_ keychain: SecOut?) -> Int32 {
    keychain?.pointee = nil
    return noDefaultKeychain
}

@c(_SecKeychainSetDefault)
public func SecKeychainSetDefault(_ keychain: UnsafeMutableRawPointer?) -> Int32 { 0 }

/// Callbacks are kept by nothing: no keychain here changes.
@c(_SecKeychainAddCallback)
public func SecKeychainAddCallback(_ callback: UnsafeMutableRawPointer?, _ events: UInt32, _ context: UnsafeMutableRawPointer?) -> Int32 { 0 }

@c(_SecKeychainRemoveCallback)
public func SecKeychainRemoveCallback(_ callback: UnsafeMutableRawPointer?) -> Int32 { 0 }

// MARK: - Passwords

@c(_SecKeychainFindGenericPassword)
public func SecKeychainFindGenericPassword(_ keychainOrArray: UnsafeMutableRawPointer?, _ serviceLength: UInt32, _ service: UnsafePointer<CChar>?,
                                           _ accountLength: UInt32, _ account: UnsafePointer<CChar>?,
                                           _ passwordLength: UnsafeMutablePointer<UInt32>?, _ passwordData: SecOut?, _ item: SecOut?) -> Int32 {
    passwordLength?.pointee = 0
    passwordData?.pointee = nil
    item?.pointee = nil
    return itemNotFound
}

@c(_SecKeychainFindInternetPassword)
public func SecKeychainFindInternetPassword(_ keychainOrArray: UnsafeMutableRawPointer?, _ serverLength: UInt32, _ server: UnsafePointer<CChar>?,
                                            _ domainLength: UInt32, _ domain: UnsafePointer<CChar>?,
                                            _ accountLength: UInt32, _ account: UnsafePointer<CChar>?,
                                            _ pathLength: UInt32, _ path: UnsafePointer<CChar>?, _ port: UInt16,
                                            _ protocolType: UInt32, _ authenticationType: UInt32,
                                            _ passwordLength: UnsafeMutablePointer<UInt32>?, _ passwordData: SecOut?, _ item: SecOut?) -> Int32 {
    passwordLength?.pointee = 0
    passwordData?.pointee = nil
    item?.pointee = nil
    return itemNotFound
}

@c(_SecKeychainAddGenericPassword)
public func SecKeychainAddGenericPassword(_ keychain: UnsafeMutableRawPointer?, _ serviceLength: UInt32, _ service: UnsafePointer<CChar>?,
                                          _ accountLength: UInt32, _ account: UnsafePointer<CChar>?,
                                          _ passwordLength: UInt32, _ passwordData: UnsafeRawPointer?, _ item: SecOut?) -> Int32 {
    item?.pointee = nil
    return notAvailable
}

@c(_SecKeychainAddInternetPassword)
public func SecKeychainAddInternetPassword(_ keychain: UnsafeMutableRawPointer?, _ serverLength: UInt32, _ server: UnsafePointer<CChar>?,
                                           _ domainLength: UInt32, _ domain: UnsafePointer<CChar>?,
                                           _ accountLength: UInt32, _ account: UnsafePointer<CChar>?,
                                           _ pathLength: UInt32, _ path: UnsafePointer<CChar>?, _ port: UInt16,
                                           _ protocolType: UInt32, _ authenticationType: UInt32,
                                           _ passwordLength: UInt32, _ passwordData: UnsafeRawPointer?, _ item: SecOut?) -> Int32 {
    item?.pointee = nil
    return notAvailable
}

@c(_SecKeychainItemDelete)
public func SecKeychainItemDelete(_ item: UnsafeMutableRawPointer?) -> Int32 { invalidItem }

@c(_SecKeychainItemModifyAttributesAndData)
public func SecKeychainItemModifyAttributesAndData(_ item: UnsafeMutableRawPointer?, _ attributes: UnsafeRawPointer?, _ length: UInt32,
                                                   _ data: UnsafeRawPointer?) -> Int32 { invalidItem }

/// Content the find functions gave, which is none.
@c(_SecKeychainItemFreeContent)
public func SecKeychainItemFreeContent(_ attributes: UnsafeMutableRawPointer?, _ data: UnsafeMutableRawPointer?) -> Int32 { 0 }

// MARK: - Policies

@c(_SecPolicyCopy)
public func SecPolicyCopy(_ certificateType: UInt32, _ policyOID: UnsafeRawPointer?, _ policy: SecOut?) -> Int32 {
    policy?.pointee = nil
    return policyNotFound
}

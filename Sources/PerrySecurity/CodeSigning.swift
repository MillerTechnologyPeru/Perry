import FoundationEssentials
import Glibc
import PerryObjCInterop

// Code signing, as an app asks about its own: there is no code signature
// to check here, so the app's code (SecCode, SecStaticCode) is valid for
// any requirement (SecRequirement), as an untampered signed app is. Its
// signing information is what the app's embedded provisioning profile
// says: its team identifier and bundle identifier.

@ObjCClass("__SecCode")
final class SecCodeObject: NSObject {}

@ObjCClass("__SecRequirement")
final class SecRequirementObject: NSObject {}

/// errSecSuccess, errSecParam.
private let errSecSuccess: Int32 = 0
private let errSecParam: Int32 = -50

private func give(_ cls: ObjCClass, _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let out else { return errSecParam }
    out.pointee = cls.ownedInstance()
    return errSecSuccess
}

@c(_SecCodeCopySelf)
public func SecCodeCopySelf(_ flags: UInt32, _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    give(SecCodeObject.objCClass, out)
}

@c(_SecCodeCopyStaticCode)
public func SecCodeCopyStaticCode(_ code: UnsafeMutableRawPointer?, _ flags: UInt32,
                                  _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    give(SecCodeObject.objCClass, out)
}

@c(_SecStaticCodeCreateWithPath)
public func SecStaticCodeCreateWithPath(_ path: UnsafeMutableRawPointer?, _ flags: UInt32,
                                        _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    give(SecCodeObject.objCClass, out)
}

@c(_SecCodeCopyGuestWithAttributes)
public func SecCodeCopyGuestWithAttributes(_ host: UnsafeMutableRawPointer?, _ attributes: UnsafeMutableRawPointer?, _ flags: UInt32,
                                           _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    give(SecCodeObject.objCClass, out)
}

@c(_SecRequirementCreateWithString)
public func SecRequirementCreateWithString(_ text: UnsafeMutableRawPointer?, _ flags: UInt32,
                                           _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard text != nil else { return errSecParam }
    return give(SecRequirementObject.objCClass, out)
}

@c(_SecRequirementCreateWithStringAndErrors)
public func SecRequirementCreateWithStringAndErrors(_ text: UnsafeMutableRawPointer?, _ flags: UInt32,
                                                    _ errors: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
                                                    _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    errors?.pointee = nil
    return SecRequirementCreateWithString(text, flags, out)
}

@c(_SecRequirementCreateWithData)
public func SecRequirementCreateWithData(_ data: UnsafeMutableRawPointer?, _ flags: UInt32,
                                         _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard data != nil else { return errSecParam }
    return give(SecRequirementObject.objCClass, out)
}

@c(_SecCodeCheckValidity)
public func SecCodeCheckValidity(_ code: UnsafeMutableRawPointer?, _ flags: UInt32, _ requirement: UnsafeMutableRawPointer?) -> Int32 {
    code == nil ? errSecParam : errSecSuccess
}

@c(_SecCodeCheckValidityWithErrors)
public func SecCodeCheckValidityWithErrors(_ code: UnsafeMutableRawPointer?, _ flags: UInt32, _ requirement: UnsafeMutableRawPointer?,
                                           _ errors: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    errors?.pointee = nil
    return SecCodeCheckValidity(code, flags, requirement)
}

@c(_SecStaticCodeCheckValidity)
public func SecStaticCodeCheckValidity(_ code: UnsafeMutableRawPointer?, _ flags: UInt32, _ requirement: UnsafeMutableRawPointer?) -> Int32 {
    code == nil ? errSecParam : errSecSuccess
}

@c(_SecStaticCodeCheckValidityWithErrors)
public func SecStaticCodeCheckValidityWithErrors(_ code: UnsafeMutableRawPointer?, _ flags: UInt32, _ requirement: UnsafeMutableRawPointer?,
                                                 _ errors: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    errors?.pointee = nil
    return SecStaticCodeCheckValidity(code, flags, requirement)
}

/// The signing information: the identifier, the team identifier from the
/// provisioning profile, and the Info.plist.
@c(_SecCodeCopySigningInformation)
public func SecCodeCopySigningInformation(_ code: UnsafeMutableRawPointer?, _ flags: UInt32,
                                          _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard code != nil, let out else { return errSecParam }
    let bundle = NSBundle.main()
    var entries: [(String, NSObject)] = []
    if let identifier = bundle.bundleIdentifier() { entries.append((CodeSigningKeys.kSecCodeInfoIdentifier, NSObject.string(identifier))) }
    if let team = Signing.teamIdentifier { entries.append((CodeSigningKeys.kSecCodeInfoTeamIdentifier, NSObject.string(team))) }
    let info = NSMutableDictionary.of(entries)
    out.pointee = ObjCRuntime.retain(info.objcObject)
    return errSecSuccess
}

@ObjCConstants
enum CodeSigningKeys {
    static let kSecCodeInfoIdentifier = "identifier"
    static let kSecCodeInfoTeamIdentifier = "teamid"
    static let kSecCodeInfoPList = "info-plist"
    static let kSecCodeInfoFlags = "flags"
    static let kSecCodeInfoFormat = "format"
    static let kSecCodeInfoEntitlementsDict = "entitlements-dict"
    static let kSecCodeInfoCertificates = "certificates"
    static let kSecGuestAttributePid = "pid"
}

enum Signing {
    /// The team identifier in the app's embedded provisioning profile,
    /// whose property list sits in the clear inside its signature.
    nonisolated(unsafe) static let teamIdentifier: String? = {
        let bundle = NSBundle.main().bundlePath()
        for name in ["/Contents/embedded.provisionprofile", "/embedded.mobileprovision"] {
            guard let file = fopen(bundle + name, "rb") else { continue }
            defer { fclose(file) }
            var bytes: [UInt8] = []
            var buffer = [UInt8](repeating: 0, count: 16_384)
            while true {
                let count = fread(&buffer, 1, buffer.count, file)
                if count <= 0 { break }
                bytes += buffer[0..<count]
            }
            let text = String(decoding: bytes, as: UTF8.self)
            guard let key = text.range(of: "<key>TeamIdentifier</key>"),
                  let open = text.range(of: "<string>", range: key.upperBound..<text.endIndex),
                  let close = text.range(of: "</string>", range: open.upperBound..<text.endIndex) else { continue }
            return String(text[open.upperBound..<close.lowerBound])
        }
        return nil
    }()
}

import Glibc
import PerryObjCInterop

// Mac apps' alone: armv7 runs only iOS apps, so it has none of this.
#if !arch(arm)
// More of Launch Services: items' information and kinds, and the handlers
// for URLs and content types, of which there are none here, as no other
// app is installed; opening a URL in one fails the same way.

/// The quarantine properties' keys, which a downloaded file's
/// NSURLQuarantinePropertiesKey dictionary holds.
@ObjCConstants
enum QuarantineConstants {
    static let kLSQuarantineAgentNameKey = "LSQuarantineAgentName"
    static let kLSQuarantineAgentBundleIdentifierKey = "LSQuarantineAgentBundleIdentifier"
    static let kLSQuarantineTimeStampKey = "LSQuarantineTimeStamp"
    static let kLSQuarantineTypeKey = "LSQuarantineType"
    static let kLSQuarantineTypeWebDownload = "LSQuarantineTypeWebDownload"
    static let kLSQuarantineTypeOtherDownload = "LSQuarantineTypeOtherDownload"
    static let kLSQuarantineDataURLKey = "LSQuarantineDataURL"
    static let kLSQuarantineOriginURLKey = "LSQuarantineOriginURL"
}

private let applicationNotFound: Int32 = -10814   // kLSApplicationNotFoundErr

private func noApplication(_ what: String) -> Int32 {
    let line = "perry: CoreServices: no app here to open \(what)\n"
    line.withCString { _ = write(2, $0, strlen($0)) }
    return applicationNotFound
}

@c(_LSCopyDefaultApplicationURLForURL)
public func LSCopyDefaultApplicationURLForURL(_ url: UnsafeMutableRawPointer?, _ roles: UInt32,
                                              _ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UnsafeMutableRawPointer? {
    error?.pointee = nil
    return nil
}

@c(_LSCopyDefaultApplicationURLForContentType)
public func LSCopyDefaultApplicationURLForContentType(_ type: UnsafeMutableRawPointer?, _ roles: UInt32,
                                                      _ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UnsafeMutableRawPointer? {
    error?.pointee = nil
    return nil
}

@c(_LSCopyApplicationURLsForURL)
public func LSCopyApplicationURLsForURL(_ url: UnsafeMutableRawPointer?, _ roles: UInt32) -> UnsafeMutableRawPointer? { nil }

@c(_LSCopyAllHandlersForURLScheme)
public func LSCopyAllHandlersForURLScheme(_ scheme: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { nil }

@c(_LSCopyAllRoleHandlersForContentType)
public func LSCopyAllRoleHandlersForContentType(_ type: UnsafeMutableRawPointer?, _ roles: UInt32) -> UnsafeMutableRawPointer? { nil }

@c(_LSCopyDefaultRoleHandlerForContentType)
public func LSCopyDefaultRoleHandlerForContentType(_ type: UnsafeMutableRawPointer?, _ roles: UInt32) -> UnsafeMutableRawPointer? { nil }

/// OSStatus LSOpenFromURLSpec(const LSLaunchURLSpec *, CFURLRef *launched):
/// the spec starts with the application's URL, then the URLs to open.
@c(_LSOpenFromURLSpec)
public func LSOpenFromURLSpec(_ spec: UnsafeRawPointer?, _ launched: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    launched?.pointee = nil
    guard let spec else { return -50 }
    let urls = spec.loadUnaligned(fromByteOffset: 8, as: UInt.self)
    let text = UnsafeMutableRawPointer(bitPattern: urls).map { NSObject($0).describedByObject() } ?? "an app"
    return noApplication(text)
}

/// OSStatus LSOpenURLsWithRole(CFArrayRef, LSRolesMask, const AEKeyDesc *,
/// const LSApplicationParameters *, ProcessSerialNumber *, CFIndex).
@c(_LSOpenURLsWithRole)
public func LSOpenURLsWithRole(_ urls: UnsafeMutableRawPointer?, _ roles: UInt32, _ event: UnsafeRawPointer?, _ parameters: UnsafeRawPointer?,
                               _ processes: UnsafeMutableRawPointer?, _ maximum: Int) -> Int32 {
    noApplication(urls.map { NSObject($0).describedByObject() } ?? "URLs")
}

/// An item's path, its name's extension and whether it's a folder.
private func itemFacts(_ url: UnsafeMutableRawPointer) -> (path: String, leaf: String, pathExtension: String, stat: stat?)? {
    guard let path = DisplayNameURL(url).path() else { return nil }
    let leaf = String(path.split(separator: "/").last ?? "/")
    let dot = leaf.lastIndex(of: ".").flatMap { $0 == leaf.startIndex ? nil : $0 }
    let pathExtension = dot.map { String(leaf[leaf.index(after: $0)...]) } ?? ""
    var info = stat()
    return (path, leaf, pathExtension, lstat(path, &info) == 0 ? info : nil)
}

/// OSStatus LSCopyItemInfoForURL(CFURLRef, LSRequestedInfo, LSItemInfoRecord *):
/// the record is { flags, filetype, creator, CFStringRef extension } packed
/// to 2 bytes. Types and creators are 0, as files here have none.
@c(_LSCopyItemInfoForURL)
public func LSCopyItemInfoForURL(_ url: UnsafeMutableRawPointer?, _ requested: UInt32, _ record: UnsafeMutableRawPointer?) -> Int32 {
    guard let url, let record else { return -50 }
    for offset in stride(from: 0, to: 20, by: 4) { record.storeBytes(of: UInt32(0), toByteOffset: offset, as: UInt32.self) }
    guard let facts = itemFacts(url), let info = facts.stat else { return -43 }   // fnfErr
    let mode = info.st_mode & 0o170000
    var flags: UInt32 = 0
    if requested & 0x7D != 0 {   // any of the flags
        if mode == 0o040000 {   // a folder
            flags |= 0x8   // kLSItemInfoIsContainer
            let pathExtension = facts.pathExtension.lowercased()
            if ["app", "bundle", "framework", "plugin", "kext", "pkg", "rtfd", "xcodeproj", "bbprojectd"].contains(pathExtension) {
                flags |= 0x2   // kLSItemInfoIsPackage
            }
            if pathExtension == "app" { flags |= 0x4 | 0x80 }   // kLSItemInfoIsApplication, kLSItemInfoIsNativeApp
        } else {
            flags |= 0x1   // kLSItemInfoIsPlainFile
        }
        if mode == 0o120000 { flags |= 0x20 }   // kLSItemInfoIsSymlink
        if facts.leaf.hasPrefix(".") { flags |= 0x40 }   // kLSItemInfoIsInvisible
        if facts.path == "/" { flags |= 0x1000 }   // kLSItemInfoIsVolume
    }
    record.storeBytes(of: flags, as: UInt32.self)
    if requested & 0x1 != 0, !facts.pathExtension.isEmpty {   // kLSRequestExtension
        let pathExtension = NSObject.string(facts.pathExtension).objCOwnedReturnValue()
        record.storeBytes(of: UInt(bitPattern: pathExtension), toByteOffset: 12, as: UInt.self)
    }
    return 0
}

/// OSStatus LSCopyKindStringForTypeInfo(OSType, OSType creator, CFStringRef
/// extension, CFStringRef *): the kind the Finder shows, from the type
/// database's description of the extension's type.
@c(_LSCopyKindStringForTypeInfo)
public func LSCopyKindStringForTypeInfo(_ type: UInt32, _ creator: UInt32, _ pathExtension: UnsafeMutableRawPointer?,
                                        _ kind: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let kind else { return -50 }
    let result: String
    if type == 0x666F_6C64 {   // 'fold'
        result = "Folder"
    } else if type == 0x4150_504C {   // 'APPL'
        result = "Application"
    } else if let pathExtension {
        let name = String(objCArgument: pathExtension)
        let record = Database.preferred(tag: name, tagClass: TagClass.filenameExtension, conformingTo: nil)
        result = record.dynamic || record.description == nil ? "\(name.uppercased()) Document" : record.description!
    } else {
        result = "Document"
    }
    kind.pointee = NSObject.string(result).objCOwnedReturnValue()
    return 0
}

/// OSStatus LSGetExtensionInfo(UniCharCount, const UniChar[], UniCharCount *start):
/// where the name's extension starts, after its last period, or
/// kLSInvalidExtensionIndex when it has none (no period, or only a leading
/// or trailing one).
@c(_LSGetExtensionInfo)
public func LSGetExtensionInfo(_ length: Int, _ name: UnsafePointer<UInt16>?, _ start: UnsafeMutablePointer<Int>?) -> Int32 {
    guard let start, length >= 0, length == 0 || name != nil else { return -50 }
    start.pointee = -1   // kLSInvalidExtensionIndex, ULONG_MAX
    guard let name, length > 0 else { return 0 }
    let units = UnsafeBufferPointer(start: name, count: length)
    if let dot = units.lastIndex(of: 0x2E), dot > 0, dot < length - 1 {
        start.pointee = dot + 1
    }
    return 0
}
#endif

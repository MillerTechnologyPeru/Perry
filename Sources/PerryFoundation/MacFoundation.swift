import FoundationEssentials
import Glibc
import PerryObjCInterop

// CoreFoundation and Foundation functions macOS apps call as they start:
// a bundle's localizations and its URL from its executable's, canonical
// language identifiers and their Windows locale codes, hashing bytes,
// page rounding, and Foundation's zero geometry constants.

/// A class, by name, to send class messages to.
private func named(_ name: String) -> id? { name.withCString { ObjC.getClass($0) }.map { UnsafeMutableRawPointer($0) } }

@c(_CFBundleCopyBundleLocalizations)
public func CFBundleCopyBundleLocalizations(_ bundle: id?) -> id? { ObjC.retain(ObjC.send(bundle, ObjC.selector("localizations"))) }

@c(_CFBundleCopyPreferredLocalizationsFromArray)
public func CFBundleCopyPreferredLocalizationsFromArray(_ array: id?) -> id? {
    ObjC.retain(ObjC.send(named("NSBundle"), ObjC.selector("preferredLocalizationsFromArray:"), array))
}

@c(_CFBundleCopyLocalizationsForPreferences)
public func CFBundleCopyLocalizationsForPreferences(_ array: id?, _ preferences: id?) -> id? {
    ObjC.retain(ObjC.send(named("NSBundle"), ObjC.selector("preferredLocalizationsFromArray:forPreferences:"), array, preferences))
}

/// The bundle an executable is the executable of: X.app for
/// X.app/Contents/MacOS/X (or X.app/X, as iOS lays them out), or nil.
@c(__CFBundleCopyBundleURLForExecutableURL)
public func _CFBundleCopyBundleURLForExecutableURL(_ url: id?) -> id? {
    guard let path = ObjC.send(url, ObjC.selector("path")).map({ Strings.value(of: $0) ?? "" }), !path.isEmpty else { return nil }
    var components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard components.count > 1 else { return nil }
    components.removeLast()
    if components.count > 2, components[components.count - 1] == "MacOS", components[components.count - 2] == "Contents" {
        components.removeLast(2)
    }
    guard let last = components.last, last.hasSuffix(".app") || last.hasSuffix(".bundle") || last.hasSuffix(".framework") else { return nil }
    guard let bundleURL = URLs.wrapped(URL(filePath: components.joined(separator: "/"), directoryHint: .isDirectory)) else { return nil }
    return ObjC.retain(bundleURL.objcObject)
}

/// A function in a bundle's executable, by name, as dlsym finds it: in the
/// bundle's own Mach-O image, in the provider standing in for a system
/// framework, which has no executable here, or else in any image.
@c(_CFBundleGetFunctionPointerForName)
public func CFBundleGetFunctionPointerForName(_ bundle: id?, _ name: id?) -> UnsafeMutableRawPointer? {
    BundleLoading.symbol(bundle, name)
}

/// A variable in a bundle's executable, by name, found as functions are.
@c(_CFBundleGetDataPointerForName)
public func CFBundleGetDataPointerForName(_ bundle: id?, _ name: id?) -> UnsafeMutableRawPointer? {
    BundleLoading.symbol(bundle, name)
}

extension BundleLoading {
    nonisolated(unsafe) static var lookupSymbol: (@convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> UnsafeMutableRawPointer?)?

    static func symbol(_ bundle: id?, _ name: id?) -> UnsafeMutableRawPointer? {
        guard let lookupSymbol, let name = Strings.value(of: name) else { return nil }
        let symbol = "_" + name
        var libraries: [String] = []
        if let executable = ObjC.send(bundle, ObjC.selector("executablePath")).flatMap({ Strings.value(of: $0) }) {
            libraries.append(executable)
        }
        // A system framework's install name, Name.framework/Name, names its provider.
        if let path = ObjC.send(bundle, ObjC.selector("bundlePath")).flatMap({ Strings.value(of: $0) }),
           path.hasPrefix("/System/Library/"), path.hasSuffix(".framework") {
            let framework = String(path.split(separator: "/").last ?? "").replacing(".framework", with: "")
            libraries.append(path + "/" + framework)
        }
        for library in libraries {
            if let address = library.withCString({ library in symbol.withCString { lookupSymbol(library, $0) } }) { return address }
        }
        return symbol.withCString { lookupSymbol(nil, $0) }
    }
}

@c(_CFLocaleCreateCanonicalLanguageIdentifierFromString)
public func CFLocaleCreateCanonicalLanguageIdentifierFromString(_ allocator: UnsafeRawPointer?, _ string: id?) -> id? {
    ObjC.retain(ObjC.send(named("NSLocale"), ObjC.selector("canonicalLanguageIdentifierFromString:"), string))
}

/// The Windows locale code (LCID) of a locale identifier, for the
/// languages games are localized into; US English otherwise.
@c(_CFLocaleGetWindowsLocaleCodeFromLocaleIdentifier)
public func CFLocaleGetWindowsLocaleCodeFromLocaleIdentifier(_ identifier: id?) -> UInt32 {
    let name = (identifier.flatMap { Strings.value(of: $0) } ?? "en_US").replacing("-", with: "_")
    let codes: [String: UInt32] = [
        "en": 0x409, "en_US": 0x409, "en_GB": 0x809, "en_AU": 0xc09, "en_CA": 0x1009, "fr": 0x40c, "fr_FR": 0x40c, "fr_CA": 0xc0c,
        "de": 0x407, "de_DE": 0x407, "es": 0xc0a, "es_ES": 0xc0a, "es_MX": 0x80a, "it": 0x410, "it_IT": 0x410, "ja": 0x411,
        "ja_JP": 0x411, "ko": 0x412, "ko_KR": 0x412, "zh_Hans": 0x804, "zh_CN": 0x804, "zh_Hant": 0x404, "zh_TW": 0x404,
        "zh_HK": 0xc04, "pt": 0x416, "pt_BR": 0x416, "pt_PT": 0x816, "ru": 0x419, "ru_RU": 0x419, "pl": 0x415, "pl_PL": 0x415,
        "tr": 0x41f, "tr_TR": 0x41f, "vi": 0x42a, "vi_VN": 0x42a, "ms": 0x43e, "ms_MY": 0x43e, "hi": 0x439, "hi_IN": 0x439,
        "nl": 0x413, "sv": 0x41d, "da": 0x406, "fi": 0x40b, "nb": 0x414, "cs": 0x405, "hu": 0x40e, "uk": 0x422, "th": 0x41e,
    ]
    if let code = codes[name] { return code }
    let language = String(name.prefix { $0 != "_" })
    return codes[language] ?? 0x409
}

/// A hash of the bytes, as CFHash of CFData gives one.
@c(_CFHashBytes)
public func CFHashBytes(_ bytes: UnsafePointer<UInt8>?, _ length: Int) -> UInt {
    guard let bytes else { return 0 }
    // FNV-1a, in 64 bits; a 32-bit word keeps the low half.
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for index in 0..<max(length, 0) {
        hash ^= UInt64(bytes[index])
        hash = hash &* 0x0000_0100_0000_01b3
    }
    return UInt(truncatingIfNeeded: hash)
}

@c(_NSRoundUpToMultipleOfPageSize)
public func NSRoundUpToMultipleOfPageSize(_ bytes: UInt) -> UInt {
    let page = UInt(sysconf(Int32(_SC_PAGESIZE)))
    return (bytes + page - 1) / page * page
}

@c(_NSRoundDownToMultipleOfPageSize)
public func NSRoundDownToMultipleOfPageSize(_ bytes: UInt) -> UInt {
    let page = UInt(sysconf(Int32(_SC_PAGESIZE)))
    return bytes / page * page
}

/// NSZeroPoint, NSZeroSize and NSZeroRect: zeros, which never change.
enum ZeroGeometry {
    nonisolated(unsafe) static let storage: UnsafeMutableRawPointer = {
        let storage = UnsafeMutableRawPointer.allocate(byteCount: 32, alignment: 16)
        storage.initializeMemory(as: UInt8.self, repeating: 0, count: 32)
        return storage
    }()

    static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        ["_NSZeroPoint", "_NSZeroSize", "_NSZeroRect"].contains(name) ? storage : nil
    }
}

// MARK: - Property lists

/// A property list read from data, +1: NSPropertyListSerialization's, with
/// its format and, when it can't be read, the error, +1 too.
@c(_CFPropertyListCreateWithData)
public func CFPropertyListCreateWithData(_ allocator: id?, _ data: id?, _ options: UInt, _ format: UnsafeMutablePointer<UInt>?,
                                         _ error: UnsafeMutablePointer<id?>?) -> id? {
    typealias Read = @convention(c) (id?, SEL, id?, UInt, UnsafeMutablePointer<UInt>?, UnsafeMutablePointer<id?>?) -> id?
    let read = unsafeBitCast(ObjC.msgSend, to: Read.self)
    let made = read(named("NSPropertyListSerialization"), ObjC.selector("propertyListWithData:options:format:error:"),
                    data, options, format, error)
    if let error, let reported = error.pointee { error.pointee = ObjC.retain(reported) }
    return ObjC.retain(made)
}

/// A property list written as data in a format, +1.
@c(_CFPropertyListCreateData)
public func CFPropertyListCreateData(_ allocator: id?, _ plist: id?, _ format: UInt, _ options: UInt,
                                     _ error: UnsafeMutablePointer<id?>?) -> id? {
    typealias Write = @convention(c) (id?, SEL, id?, UInt, UInt, UnsafeMutablePointer<id?>?) -> id?
    let write = unsafeBitCast(ObjC.msgSend, to: Write.self)
    let made = write(named("NSPropertyListSerialization"), ObjC.selector("dataWithPropertyList:format:options:error:"),
                     plist, format, options, error)
    if let error, let reported = error.pointee { error.pointee = ObjC.retain(reported) }
    return ObjC.retain(made)
}

/// A deep copy of a property list, +1: mutable as `options` says.
@c(_CFPropertyListCreateDeepCopy)
public func CFPropertyListCreateDeepCopy(_ allocator: id?, _ plist: id?, _ options: UInt) -> id? {
    guard let data = CFPropertyListCreateData(allocator, plist, 200, 0, nil) else { return nil }
    defer { ObjC.release(data) }
    return CFPropertyListCreateWithData(allocator, data, options, nil, nil)
}

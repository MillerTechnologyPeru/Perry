import CPerryFoundation
import FoundationEssentials
import Glibc
import PerryObjCInterop

// More of CFBundle: the bundles made, and those in a directory; a bundle's
// folders, Info.plist, package type and creator, and resources, by URL as
// well as by bundle; localized strings and resources for a localization;
// the classic Mac OS language, region, script and encoding codes of a
// localization; the architectures its executable has, read from its
// Mach-O header; loading it with errors, its functions and variables by
// name, and its plug-in. There is no Resource Manager, so a bundle's
// Carbon resource files can't be opened.

// MARK: - Bundles

/// Every bundle made so far, the main bundle first, and the frameworks the
/// process has loaded, as Darwin's are made as they load. +0.
@c(_CFBundleGetAllBundles)
public func CFBundleGetAllBundles() -> id? {
    _ = NSBundle.frameworkBundles()
    let main = Bundles.main
    let others = Bundles.byPath.sorted { $0.key < $1.key }.map { $0.value }.filter { $0 != main }
    return Arrays.autoreleased([main].compactMap { $0 } + others)
}

/// The bundles in a directory whose extension is `bundleType` (any, when
/// NULL), +1; each's plug-in factories and types are registered, as on
/// Darwin.
@c(_CFBundleCreateBundlesFromDirectory)
public func CFBundleCreateBundlesFromDirectory(_ allocator: UnsafeRawPointer?, _ directoryURL: id?, _ bundleType: id?) -> id? {
    guard let directory = bundleDirectoryPath(directoryURL) else { return Arrays.make([]) }
    let type = Strings.value(of: bundleType).map { $0.hasPrefix(".") ? String($0.dropFirst()) : $0 }
    let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []).sorted()
    var bundles: [id] = []
    for name in names where !name.hasPrefix(".") {
        if let type, !type.isEmpty, Paths.pathExtension(name) != type { continue }
        let path = Paths.appending(directory, name)
        var info = stat()
        guard stat(path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, let bundle = Bundles.bundle(path: path) else { continue }
        PlugIns.registerContents(of: bundle)
        bundles.append(bundle)
    }
    return Arrays.make(bundles)
}

/// A file URL's path, without its trailing slash.
private func bundleDirectoryPath(_ url: id?) -> String? {
    guard let url = CFURLs.url(url), url.isFileURL else { return nil }
    var path = url.path(percentEncoded: false)
    if path.count > 1, path.hasSuffix("/") { path.removeLast() }
    return path
}

/// The bundle at a URL, read for the call and not kept.
private func bundleStorage(at url: id?) -> BundleStorage? {
    guard let path = bundleDirectoryPath(url) else { return nil }
    var info = stat()
    guard stat(path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { return nil }
    return BundleStorage(path: Bundles.standardized(path))
}

private func directoryURL(_ path: String) -> id? { CFURLs.make(URL(filePath: path, directoryHint: .isDirectory)) }

// MARK: - Folders

@c(_CFBundleCopyBuiltInPlugInsURL)
public func CFBundleCopyBuiltInPlugInsURL(_ bundle: id?) -> id? { ObjC.retain(ObjC.send(bundle, ObjC.selector("builtInPlugInsURL"))) }

@c(_CFBundleCopySharedFrameworksURL)
public func CFBundleCopySharedFrameworksURL(_ bundle: id?) -> id? { ObjC.retain(ObjC.send(bundle, ObjC.selector("sharedFrameworksURL"))) }

@c(_CFBundleCopySharedSupportURL)
public func CFBundleCopySharedSupportURL(_ bundle: id?) -> id? { ObjC.retain(ObjC.send(bundle, ObjC.selector("sharedSupportURL"))) }

/// The folder the bundle's support files are in: a Mac bundle's Contents,
/// an iOS bundle's own folder. +1.
@c(_CFBundleCopySupportFilesDirectoryURL)
public func CFBundleCopySupportFilesDirectoryURL(_ bundle: id?) -> id? {
    guard let storage = Bundles.storage(bundle) else { return nil }
    return directoryURL(storage.contentsPath)
}

// MARK: - Info.plist and package info

/// The Info.plist of the bundle in a directory, +1: empty when it has
/// none; NULL when there is no directory.
@c(_CFBundleCopyInfoDictionaryInDirectory)
public func CFBundleCopyInfoDictionaryInDirectory(_ bundleURL: id?) -> id? {
    guard let storage = bundleStorage(at: bundleURL) else { return nil }
    return ObjC.retain(PropertyValue.dictionary(storage.info).object() ?? Dictionaries.autoreleased([]))
}

/// The Info.plist for a URL, +1: a bundle directory's, or the one a
/// tool's executable embeds in its __TEXT,__info_plist section.
@c(_CFBundleCopyInfoDictionaryForURL)
public func CFBundleCopyInfoDictionaryForURL(_ url: id?) -> id? {
    guard let path = bundleDirectoryPath(url) else { return nil }
    var info = stat()
    guard stat(path, &info) == 0 else { return nil }
    if info.st_mode & S_IFMT == S_IFDIR { return CFBundleCopyInfoDictionaryInDirectory(url) }
    guard let bytes = MachOFiles.infoPlist(path), let (value, _) = PropertyLists.parse(bytes) else { return nil }
    return ObjC.retain(PropertyLists.object(value, mutability: 0))
}

/// A four-character code as a number, 'APPL' being 0x4150504C.
private func fourCharCode(_ text: String?) -> UInt32? {
    guard let text else { return nil }
    let bytes = Array(text.utf8)
    guard bytes.count == 4 else { return nil }
    return bytes.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
}

/// The type and creator: Info.plist's CFBundlePackageType and
/// CFBundleSignature, else the PkgInfo file's; nil when neither has them.
private func packageInfo(_ storage: BundleStorage) -> (type: UInt32, creator: UInt32)? {
    func string(_ key: String) -> String? {
        if case .string(let value)? = storage.info[key] { return value }
        return nil
    }
    let type = fourCharCode(string("CFBundlePackageType")), creator = fourCharCode(string("CFBundleSignature"))
    if type != nil || creator != nil { return (type ?? 0x424E_444C, creator ?? 0x3F3F_3F3F) }
    if let bytes = readPackageInfoFile(Paths.appending(storage.contentsPath, "PkgInfo")), bytes.count >= 8 {
        let code = { (start: Int) in bytes[start..<(start + 4)].reduce(UInt32(0)) { $0 << 8 | UInt32($1) } }
        return (code(0), code(4))
    }
    return nil
}

private func readPackageInfoFile(_ path: String) -> [UInt8]? {
    guard let file = fopen(path, "rb") else { return nil }
    defer { fclose(file) }
    var bytes = [UInt8](repeating: 0, count: 8)
    let count = fread(&bytes, 1, 8, file)
    return Array(bytes.prefix(count))
}

/// The bundle's package type and creator; 'BNDL' and '????' when it
/// doesn't say.
@c(_CFBundleGetPackageInfo)
public func CFBundleGetPackageInfo(_ bundle: id?, _ packageType: UnsafeMutablePointer<UInt32>?, _ packageCreator: UnsafeMutablePointer<UInt32>?) {
    let found = Bundles.storage(bundle).flatMap(packageInfo)
    packageType?.pointee = found?.type ?? 0x424E_444C
    packageCreator?.pointee = found?.creator ?? 0x3F3F_3F3F
}

/// The package type and creator of the bundle in a directory; false, with
/// 'BNDL' and '????', when it doesn't say or isn't there.
@c(_CFBundleGetPackageInfoInDirectory)
public func CFBundleGetPackageInfoInDirectory(_ url: id?, _ packageType: UnsafeMutablePointer<UInt32>?,
                                              _ packageCreator: UnsafeMutablePointer<UInt32>?) -> Bool {
    let found = bundleStorage(at: url).flatMap(packageInfo)
    packageType?.pointee = found?.type ?? 0x424E_444C
    packageCreator?.pointee = found?.creator ?? 0x3F3F_3F3F
    return found != nil
}

/// Info.plist's CFBundleDevelopmentRegion, +0; NULL when it has none.
@c(_CFBundleGetDevelopmentRegion)
public func CFBundleGetDevelopmentRegion(_ bundle: id?) -> id? {
    Dictionaries.value(CFBundleGetInfoDictionary(bundle), for: Strings.autoreleased("CFBundleDevelopmentRegion"))
}

// MARK: - Executables

/// Mach-O files' headers: the architectures they have, and the Info.plist
/// a tool embeds.
enum MachOFiles {
    private static func read(_ file: UnsafeMutablePointer<FILE>, _ offset: Int, _ count: Int) -> [UInt8]? {
        guard count >= 0, fseeko(file, off_t(offset), SEEK_SET) == 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: count)
        guard count == 0 || fread(&bytes, 1, count, file) == count else { return nil }
        return bytes
    }

    private static func word(_ bytes: [UInt8], _ at: Int, bigEndian: Bool) -> UInt32 {
        guard at + 4 <= bytes.count else { return 0 }
        let b = bytes[at..<(at + 4)].map { UInt32($0) }
        return bigEndian ? b[0] << 24 | b[1] << 16 | b[2] << 8 | b[3] : b[3] << 24 | b[2] << 16 | b[1] << 8 | b[0]
    }

    private static func doubleWord(_ bytes: [UInt8], _ at: Int, bigEndian: Bool) -> UInt64 {
        let first = UInt64(word(bytes, at, bigEndian: bigEndian)), second = UInt64(word(bytes, at + 4, bigEndian: bigEndian))
        return bigEndian ? first << 32 | second : second << 32 | first
    }

    /// A slice: its CPU type and where it starts.
    struct Slice {
        let cpuType: Int32
        let offset: Int
    }

    /// A thin file's one slice, or a universal file's, nil for a file
    /// that isn't Mach-O.
    static func slices(_ path: String) -> [Slice]? {
        guard let file = fopen(path, "rb") else { return nil }
        defer { fclose(file) }
        guard let header = read(file, 0, 8) else { return nil }
        let magic = word(header, 0, bigEndian: true)
        if magic == 0xCAFE_BABE || magic == 0xCAFE_BABF {
            let count = Int(word(header, 4, bigEndian: true))
            // Java's class files share the magic number, with a version here.
            guard count > 0, count < 64 else { return nil }
            let size = magic == 0xCAFE_BABF ? 32 : 20
            guard let table = read(file, 8, count * size) else { return nil }
            return (0..<count).map { index in
                let base = index * size
                let offset = magic == 0xCAFE_BABF ? Int(doubleWord(table, base + 8, bigEndian: true))
                                                  : Int(word(table, base + 8, bigEndian: true))
                return Slice(cpuType: Int32(bitPattern: word(table, base, bigEndian: true)), offset: offset)
            }
        }
        guard let bigEndian = byteOrder(header) else { return nil }
        return [Slice(cpuType: Int32(bitPattern: word(header, 4, bigEndian: bigEndian)), offset: 0)]
    }

    /// Whether a Mach-O header is big-endian; nil if it isn't one.
    private static func byteOrder(_ header: [UInt8]) -> Bool? {
        switch word(header, 0, bigEndian: false) {
        case 0xFEED_FACE, 0xFEED_FACF: return false
        default: break
        }
        switch word(header, 0, bigEndian: true) {
        case 0xFEED_FACE, 0xFEED_FACF: return true
        default: return nil
        }
    }

    /// The bytes of the first slice's __TEXT,__info_plist section.
    static func infoPlist(_ path: String) -> [UInt8]? {
        guard let slice = slices(path)?.first, let file = fopen(path, "rb") else { return nil }
        defer { fclose(file) }
        guard let header = read(file, slice.offset, 32), let bigEndian = byteOrder(header) else { return nil }
        let is64 = word(header, 0, bigEndian: bigEndian) == 0xFEED_FACF
        let commandCount = Int(word(header, 16, bigEndian: bigEndian))
        let commandsSize = Int(word(header, 20, bigEndian: bigEndian))
        guard commandsSize > 0, commandsSize < 16 << 20,
              let commands = read(file, slice.offset + (is64 ? 32 : 28), commandsSize) else { return nil }
        func name(_ at: Int) -> String {
            guard at + 16 <= commands.count else { return "" }
            return String(decoding: commands[at..<(at + 16)].prefix { $0 != 0 }, as: UTF8.self)
        }
        var at = 0
        for _ in 0..<commandCount {
            guard at + 8 <= commands.count else { break }
            let command = word(commands, at, bigEndian: bigEndian), size = Int(word(commands, at + 4, bigEndian: bigEndian))
            guard size >= 8 else { break }
            let segment: UInt32 = is64 ? 0x19 : 0x1
            if command == segment, name(at + 8) == "__TEXT" {
                let sectionCount = Int(word(commands, at + (is64 ? 64 : 48), bigEndian: bigEndian))
                let sectionSize = is64 ? 80 : 68
                var section = at + (is64 ? 72 : 56)
                for _ in 0..<sectionCount {
                    if name(section) == "__info_plist" {
                        let length = is64 ? Int(doubleWord(commands, section + 40, bigEndian: bigEndian))
                                          : Int(word(commands, section + 36, bigEndian: bigEndian))
                        let offset = Int(word(commands, section + (is64 ? 48 : 40), bigEndian: bigEndian))
                        guard length > 0, length < 16 << 20 else { return nil }
                        return read(file, slice.offset + offset, length)
                    }
                    section += sectionSize
                }
            }
            at += size
        }
        return nil
    }

    /// The CPU types, each once, as CFNumbers (+1 array): Darwin's
    /// kCFBundleExecutableArchitecture values are those.
    static func architectures(_ path: String?) -> id? {
        guard let path, let slices = slices(path) else { return nil }
        var types: [Int32] = []
        for slice in slices where !types.contains(slice.cpuType) { types.append(slice.cpuType) }
        let numbers = types.compactMap { type -> id? in
            var value = type
            return CFNumberCreate(nil, CFNumberTypes.sint32, &value)
        }
        defer { numbers.forEach { ObjC.release($0) } }
        return Arrays.make(numbers)
    }
}

/// The architectures of the bundle's executable, +1; NULL when it has no
/// Mach-O executable.
@c(_CFBundleCopyExecutableArchitectures)
public func CFBundleCopyExecutableArchitectures(_ bundle: id?) -> id? {
    MachOFiles.architectures(Bundles.storage(bundle)?.executablePath)
}

/// The architectures of the executable of the bundle at a URL, or of the
/// executable the URL names.
@c(_CFBundleCopyExecutableArchitecturesForURL)
public func CFBundleCopyExecutableArchitecturesForURL(_ url: id?) -> id? {
    if let storage = bundleStorage(at: url) { return MachOFiles.architectures(storage.executablePath) }
    return MachOFiles.architectures(bundleDirectoryPath(url))
}

/// Whether the executable could be loaded; the error is +1.
@c(_CFBundlePreflightExecutable)
public func CFBundlePreflightExecutable(_ bundle: id?, _ error: UnsafeMutablePointer<id?>?) -> Bool {
    var reported: id?
    let ok = withUnsafeMutablePointer(to: &reported) {
        ObjC.sendBool(bundle, ObjC.selector("preflightAndReturnError:"), UnsafeMutableRawPointer($0))
    }
    error?.pointee = ok ? nil : ObjC.retain(reported)
    return ok
}

/// Loads the executable; the error is +1.
@c(_CFBundleLoadExecutableAndReturnError)
public func CFBundleLoadExecutableAndReturnError(_ bundle: id?, _ error: UnsafeMutablePointer<id?>?) -> Bool {
    var reported: id?
    let ok = withUnsafeMutablePointer(to: &reported) {
        ObjC.sendBool(bundle, ObjC.selector("loadAndReturnError:"), UnsafeMutableRawPointer($0))
    }
    error?.pointee = ok ? nil : ObjC.retain(reported)
    return ok
}

/// Loaded code stays, as NSBundle's -unload says.
@c(_CFBundleUnloadExecutable)
public func CFBundleUnloadExecutable(_ bundle: id?) { _ = ObjC.sendBool(bundle, ObjC.selector("unload"), nil) }

/// Each function's address, by name, in the table; NULL for one not found.
@c(_CFBundleGetFunctionPointersForNames)
public func CFBundleGetFunctionPointersForNames(_ bundle: id?, _ names: id?, _ table: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) {
    guard let table else { return }
    for (index, name) in Arrays.elements(names).enumerated() { table[index] = BundleLoading.symbol(bundle, name) }
}

/// Each variable's address, by name, found as functions are.
@c(_CFBundleGetDataPointersForNames)
public func CFBundleGetDataPointersForNames(_ bundle: id?, _ names: id?, _ table: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) {
    CFBundleGetFunctionPointersForNames(bundle, names, table)
}

/// The bundle as a plug-in, +0, its factories and types registered, when
/// its Info.plist makes it one; NULL otherwise.
@c(_CFBundleGetPlugIn)
public func CFBundleGetPlugIn(_ bundle: id?) -> id? {
    guard let bundle, let storage = Bundles.storage(bundle) else { return nil }
    guard ["CFPlugInFactories", "CFPlugInDynamicRegistration", "CFPlugInTypes"].contains(where: { storage.info[$0] != nil }) else {
        return nil
    }
    PlugIns.registerContents(of: bundle)
    return bundle
}

// MARK: - Carbon resource maps

/// CFBundleRefNum: an int, a short on 32-bit systems.
private func storeRefNum(_ pointer: UnsafeMutableRawPointer?, _ value: Int32) {
    guard let pointer else { return }
    if MemoryLayout<Int>.size == 4 {
        pointer.storeBytes(of: Int16(truncatingIfNeeded: value), as: Int16.self)
    } else {
        pointer.storeBytes(of: value, as: Int32.self)
    }
}

/// There is no Resource Manager: no resource map opens, and -1, Darwin's
/// failure, is the reference number.
@c(_CFBundleOpenBundleResourceMap)
public func CFBundleOpenBundleResourceMap(_ bundle: id?) -> Int32 { -1 }

/// Neither resource file opens: both reference numbers are -1, and the
/// result -1.
@c(_CFBundleOpenBundleResourceFiles)
public func CFBundleOpenBundleResourceFiles(_ bundle: id?, _ refNum: UnsafeMutableRawPointer?, _ localizedRefNum: UnsafeMutableRawPointer?) -> Int32 {
    storeRefNum(refNum, -1)
    storeRefNum(localizedRefNum, -1)
    return -1
}

@c(_CFBundleCloseBundleResourceMap)
public func CFBundleCloseBundleResourceMap(_ bundle: id?, _ refNum: Int32) {}

// MARK: - Resources

/// A resource in a localization's folder, else outside any, +1.
@c(_CFBundleCopyResourceURLForLocalization)
public func CFBundleCopyResourceURLForLocalization(_ bundle: id?, _ name: id?, _ type: id?, _ subdirectory: id?, _ localization: id?) -> id? {
    typealias Send = @convention(c) (id?, SEL, id?, id?, id?, id?) -> id?
    return ObjC.retain(unsafeBitCast(ObjC.msgSend, to: Send.self)(
        bundle, ObjC.selector("URLForResource:withExtension:subdirectory:localization:"), name, type, subdirectory, localization))
}

/// A resource of the bundle at a URL, +1, found as CFBundleCopyResourceURL
/// finds one.
@c(_CFBundleCopyResourceURLInDirectory)
public func CFBundleCopyResourceURLInDirectory(_ bundleURL: id?, _ name: id?, _ type: id?, _ subdirectory: id?) -> id? {
    guard let storage = bundleStorage(at: bundleURL),
          let path = storage.resource(Strings.value(of: name), type: Strings.value(of: type), directory: Strings.value(of: subdirectory))
    else { return nil }
    return CFURLs.make(URL(filePath: path))
}

/// The resources of a type outside any localization and in one's folder,
/// as URLs (+1 array).
private func resourceURLs(_ storage: BundleStorage, type: String?, subdirectory: String?, localization: String?) -> id? {
    var paths = storage.resources(type: type, directory: subdirectory)
    if let localization, !localization.isEmpty {
        paths += storage.resources(type: type, directory: Paths.appending(subdirectory ?? "", localization + ".lproj"))
    }
    var seen: Set<String> = []
    let urls = paths.filter { seen.insert($0).inserted }.compactMap { URLs.autoreleased(URL(filePath: $0)) }
    return Arrays.make(urls)
}

/// The bundle's resources of a type (any, when NULL), in a subdirectory
/// or not, outside any localization and in the localization's. +1.
@c(_CFBundleCopyResourceURLsOfTypeForLocalization)
public func CFBundleCopyResourceURLsOfTypeForLocalization(_ bundle: id?, _ type: id?, _ subdirectory: id?, _ localization: id?) -> id? {
    guard let storage = Bundles.storage(bundle) else { return nil }
    return resourceURLs(storage, type: Strings.value(of: type), subdirectory: Strings.value(of: subdirectory),
                        localization: Strings.value(of: localization))
}

/// The resources of a type of the bundle at a URL: outside any
/// localization and in the one the user prefers. +1.
@c(_CFBundleCopyResourceURLsOfTypeInDirectory)
public func CFBundleCopyResourceURLsOfTypeInDirectory(_ bundleURL: id?, _ type: id?, _ subdirectory: id?) -> id? {
    guard let storage = bundleStorage(at: bundleURL) else { return nil }
    return resourceURLs(storage, type: Strings.value(of: type), subdirectory: Strings.value(of: subdirectory),
                        localization: preferredLocalization(storage))
}

/// The user's preferred localization of those a bundle has, else its
/// development region.
private func preferredLocalization(_ storage: BundleStorage) -> String? {
    var development: String?
    if case .string(let value)? = storage.info["CFBundleDevelopmentRegion"] { development = value }
    return Bundles.preferred(from: storage.localizations, preferences: nil) ?? development
}

/// The localizations of the bundle at a URL, or that an executable's
/// embedded Info.plist names (CFBundleLocalizations), +1.
@c(_CFBundleCopyLocalizationsForURL)
public func CFBundleCopyLocalizationsForURL(_ url: id?) -> id? {
    var names: [String] = []
    if let storage = bundleStorage(at: url) {
        names = storage.localizations
        if case .array(let listed)? = storage.info["CFBundleLocalizations"] {
            for case .string(let name) in listed where !names.contains(name) { names.append(name) }
        }
        if names.isEmpty, case .string(let development)? = storage.info["CFBundleDevelopmentRegion"] { names = [development] }
    } else if let info = CFBundleCopyInfoDictionaryForURL(url) {
        defer { ObjC.release(info) }
        let listed = Dictionaries.value(info, for: Strings.autoreleased("CFBundleLocalizations"))
        names = Arrays.elements(listed).compactMap { Strings.value(of: $0) }
    }
    return Arrays.make(names.map { Strings.autoreleased($0) })
}

/// The string for a key in a localization's table, else `value`, else
/// the key. +1.
@c(_CFBundleCopyLocalizedStringForLocalization)
public func CFBundleCopyLocalizedStringForLocalization(_ bundle: id?, _ key: id?, _ value: id?, _ table: id?, _ localization: id?) -> id? {
    typealias Send = @convention(c) (id?, SEL, id?, id?, id?, id?) -> id?
    return ObjC.retain(unsafeBitCast(ObjC.msgSend, to: Send.self)(
        bundle, ObjC.selector("localizedStringForKey:value:table:localization:"), key, value, table, localization))
}

/// The string in the first of the localizations, in their order, that
/// the bundle has. +1.
@c(_CFBundleCopyLocalizedStringForLocalizations)
public func CFBundleCopyLocalizedStringForLocalizations(_ bundle: id?, _ key: id?, _ value: id?, _ table: id?, _ localizations: id?) -> id? {
    let wanted = Arrays.elements(localizations).compactMap { Strings.value(of: $0) }
    let chosen = Bundles.storage(bundle).flatMap { storage in
        wanted.isEmpty ? nil : Bundles.preferred(from: storage.localizations, preferences: wanted)
    }
    return CFBundleCopyLocalizedStringForLocalization(bundle, key, value, table, chosen.map { Strings.autoreleased($0) })
}

// MARK: - Classic Mac OS localization codes

/// The Script Manager's language and region codes (langEnglish …,
/// verUS …), the script each language is written in, and its Mac encoding.
enum LocalizationCodes {
    static let languages: [Int32: String] = [
        0: "en", 1: "fr", 2: "de", 3: "it", 4: "nl", 5: "sv", 6: "es", 7: "da", 8: "pt", 9: "nb", 10: "he", 11: "ja",
        12: "ar", 13: "fi", 14: "el", 15: "is", 16: "mt", 17: "tr", 18: "hr", 19: "zh_TW", 20: "ur", 21: "hi", 22: "th",
        23: "ko", 24: "lt", 25: "pl", 26: "hu", 27: "et", 28: "lv", 29: "se", 30: "fo", 31: "fa", 32: "ru", 33: "zh_CN",
        34: "nl_BE", 35: "ga", 36: "sq", 37: "ro", 38: "cs", 39: "sk", 40: "sl", 41: "yi", 42: "sr", 43: "mk", 44: "bg",
        45: "uk", 46: "be", 47: "uz", 48: "kk", 49: "az", 51: "hy", 52: "ka", 53: "mo", 54: "ky", 55: "tg", 56: "tk",
        57: "mn", 59: "ps", 60: "ku", 61: "ks", 62: "sd", 63: "bo", 64: "ne", 65: "sa", 66: "mr", 67: "bn", 68: "as",
        69: "gu", 70: "pa", 71: "or", 72: "ml", 73: "kn", 74: "ta", 75: "te", 76: "si", 77: "my", 78: "km", 79: "lo",
        80: "vi", 81: "id", 82: "tl", 83: "ms", 85: "am", 86: "ti", 87: "om", 88: "so", 89: "sw", 90: "rw", 91: "rn",
        92: "ny", 93: "mg", 94: "eo", 128: "cy", 129: "eu", 130: "ca", 131: "la", 132: "qu", 133: "gn", 134: "ay",
        135: "tt", 136: "ug", 137: "dz", 138: "jv", 139: "su", 140: "gl", 141: "af", 142: "br", 143: "iu", 144: "gd",
        145: "gv", 147: "to", 148: "grc", 149: "kl", 151: "nn",
    ]

    static let regions: [Int32: String] = [
        0: "en_US", 1: "fr_FR", 2: "en_GB", 3: "de_DE", 4: "it_IT", 5: "nl_NL", 6: "nl_BE", 7: "sv_SE", 8: "es_ES",
        9: "da_DK", 10: "pt_PT", 11: "fr_CA", 12: "nb_NO", 13: "he_IL", 14: "ja_JP", 15: "en_AU", 16: "ar", 17: "fi_FI",
        18: "fr_CH", 19: "de_CH", 20: "el_GR", 21: "is_IS", 22: "mt_MT", 23: "el_CY", 24: "tr_TR", 25: "hr_HR",
        33: "hi_IN", 34: "ur_PK", 36: "it_CH", 39: "ro_RO", 41: "lt_LT", 42: "pl_PL", 43: "hu_HU", 44: "et_EE",
        45: "lv_LV", 46: "se", 47: "fo_FO", 48: "fa_IR", 49: "ru_RU", 50: "ga_IE", 51: "ko_KR", 52: "zh_CN",
        53: "zh_TW", 54: "th_TH", 56: "cs_CZ", 57: "sk_SK", 60: "bn", 61: "be_BY", 62: "uk_UA", 65: "sr_RS",
        66: "sl_SI", 67: "mk_MK", 68: "hr_HR", 71: "pt_BR", 72: "bg_BG", 73: "ca_ES",
    ]

    /// The script (smRoman …) and Mac encoding of a language.
    static func script(_ language: String) -> (script: Int32, encoding: UInt32) {
        switch language {
        case "ja": return (1, 1)
        case "zh_TW": return (2, 2)
        case "ko": return (3, 3)
        case "ar", "ur", "ps", "ku", "sd": return (4, 4)
        case "fa": return (4, 0x8C)
        case "he", "yi": return (5, 5)
        case "el", "grc": return (6, 6)
        case "ru", "bg", "be", "mk", "sr", "kk", "ky", "tg", "uz", "mn", "tt": return (7, 7)
        case "uk": return (7, 0x98)
        case "hi", "mr", "ne", "sa": return (9, 9)
        case "pa": return (10, 10)
        case "gu": return (11, 11)
        case "th": return (21, 21)
        case "zh_CN": return (25, 25)
        case "pl", "cs", "sk", "hu", "et", "lv", "lt": return (29, 29)
        case "tr": return (0, 35)
        case "hr", "sl": return (0, 36)
        case "is", "fo": return (0, 37)
        case "ro": return (0, 38)
        default: return (0, 0)
        }
    }

    /// The older English names localizations had.
    static let englishNames: [String: String] = [
        "english": "en", "french": "fr", "german": "de", "italian": "it", "dutch": "nl", "swedish": "sv", "spanish": "es",
        "danish": "da", "portuguese": "pt", "norwegian": "nb", "hebrew": "he", "japanese": "ja", "arabic": "ar",
        "finnish": "fi", "greek": "el", "icelandic": "is", "turkish": "tr", "korean": "ko", "polish": "pl",
        "hungarian": "hu", "russian": "ru", "czech": "cs", "chinese": "zh_CN",
    ]

    /// A localization's language as the table names it: zh_TW for
    /// traditional Chinese, zh_CN for simplified.
    static func language(_ localization: String) -> String {
        let name = englishNames[localization.lowercased()] ?? localization.replacing("-", with: "_")
        let parts = name.split(separator: "_").map(String.init)
        guard let base = parts.first?.lowercased() else { return name }
        if base == "zh" {
            return parts.dropFirst().contains { ["Hant", "TW", "HK", "MO"].contains($0) } ? "zh_TW" : "zh_CN"
        }
        if base == "nl", parts.dropFirst().contains("BE") { return "nl_BE" }
        if base == "no" { return "nb" }
        return base
    }
}

/// The localization for classic Mac OS codes, +1: the language's when it
/// is given (not -1), else the region's, else the script's or encoding's
/// usual language; NULL when none is known.
@c(_CFBundleCopyLocalizationForLocalizationInfo)
public func CFBundleCopyLocalizationForLocalizationInfo(_ languageCode: Int32, _ regionCode: Int32, _ scriptCode: Int32,
                                                        _ stringEncoding: UInt32) -> id? {
    if languageCode >= 0, let name = LocalizationCodes.languages[languageCode] { return Strings.make(name) }
    if regionCode >= 0, let name = LocalizationCodes.regions[regionCode] { return Strings.make(name) }
    let scripts: [Int32: String] = [0: "en", 1: "ja", 2: "zh_TW", 3: "ko", 4: "ar", 5: "he", 6: "el", 7: "ru", 21: "th", 25: "zh_CN", 29: "pl"]
    if scriptCode >= 0, let name = scripts[scriptCode] { return Strings.make(name) }
    let encodings: [UInt32: String] = [0: "en", 1: "ja", 2: "zh_TW", 3: "ko", 4: "ar", 5: "he", 6: "el", 7: "ru", 21: "th",
                                       25: "zh_CN", 29: "pl", 35: "tr", 36: "hr", 37: "is", 38: "ro", 0x8C: "fa", 0x98: "uk"]
    if stringEncoding != 0xFFFF_FFFF, let name = encodings[stringEncoding] { return Strings.make(name) }
    return nil
}

/// A localization's classic Mac OS language, region, script and encoding
/// codes (the user's first preferred language for NULL); false, with -1
/// codes, for a language without one.
@c(_CFBundleGetLocalizationInfoForLocalization)
public func CFBundleGetLocalizationInfoForLocalization(_ localization: id?, _ languageCode: UnsafeMutablePointer<Int32>?,
                                                       _ regionCode: UnsafeMutablePointer<Int32>?, _ scriptCode: UnsafeMutablePointer<Int32>?,
                                                       _ stringEncoding: UnsafeMutablePointer<UInt32>?) -> Bool {
    let name = Strings.value(of: localization) ?? Locale.preferredLanguages.first ?? "en"
    let language = LocalizationCodes.language(name)
    guard let code = LocalizationCodes.languages.filter({ $0.value == language }).map { $0.key }.min() else {
        languageCode?.pointee = -1
        regionCode?.pointee = -1
        scriptCode?.pointee = -1
        stringEncoding?.pointee = 0xFFFF_FFFF
        return false
    }
    // The region named, else the language's first.
    let normalized = name.replacing("-", with: "_")
    let region = LocalizationCodes.regions.filter { $0.value == normalized }.map { $0.key }.min()
        ?? LocalizationCodes.regions.filter { LocalizationCodes.language($0.value) == language }.map { $0.key }.min()
    let (script, encoding) = LocalizationCodes.script(language)
    languageCode?.pointee = code
    regionCode?.pointee = region ?? -1
    scriptCode?.pointee = script
    stringEncoding?.pointee = encoding
    return true
}

// MARK: - Whether an executable can be loaded (macOS)

extension MachOFiles {
    /// The CPU type of the program running, as Darwin numbers them: the
    /// architecture this provider is built for, which the program is.
    static var processCPUType: Int32 {
        #if arch(arm64)
        0x0100_000C
        #elseif arch(x86_64)
        0x0100_0007
        #elseif arch(i386)
        7
        #elseif arch(arm)
        12
        #elseif arch(powerpc)
        18
        #else
        -1
        #endif
    }

    /// Whether the Mach-O file at the path has a slice for the program
    /// running.
    static func isLoadable(_ path: String?) -> Bool {
        guard let path, let slices = slices(path) else { return false }
        return slices.contains { $0.cpuType == processCPUType }
    }
}

/// Whether code of a CPU type could be loaded into this program: only its
/// own.
@c(_CFBundleIsArchitectureLoadable)
public func CFBundleIsArchitectureLoadable(_ architecture: Int32) -> Bool { architecture == MachOFiles.processCPUType }

/// Whether the bundle's executable has a slice for this program.
@c(_CFBundleIsExecutableLoadable)
public func CFBundleIsExecutableLoadable(_ bundle: id?) -> Bool {
    MachOFiles.isLoadable(Bundles.storage(bundle)?.executablePath)
}

/// Whether the executable of the bundle at a URL, or the executable the URL
/// names, has a slice for this program.
@c(_CFBundleIsExecutableLoadableForURL)
public func CFBundleIsExecutableLoadableForURL(_ url: id?) -> Bool {
    if let storage = bundleStorage(at: url) { return MachOFiles.isLoadable(storage.executablePath) }
    return MachOFiles.isLoadable(bundleDirectoryPath(url))
}

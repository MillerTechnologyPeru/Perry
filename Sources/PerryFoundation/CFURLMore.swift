import CPerryFoundation
import FoundationEssentials
import Glibc
import PerryObjCInterop

// More of CFURL: its string's bytes and the byte ranges of its components,
// its net location, resource specifier and strict path; resource
// properties, which NSURL's resource values give, with the keys it lacks
// read from stat, statvfs and the mount table, and temporary ones kept
// per URL; file path and file reference URLs, which are the same here;
// and the older resource calls on files.

// MARK: - Components

/// A URL string's components, as ranges of its UTF-8 bytes (RFC 3986). A
/// URL with a scheme whose colon a "/" doesn't follow (mailto:) can't be
/// decomposed: it has only a scheme and a resource specifier. The ";"
/// parameters are part of the path, as CFURL has them since macOS 10.15.
struct URLComponentScanner {
    let bytes: [UInt8]
    var scheme: Range<Int>?
    var user: Range<Int>?
    var password: Range<Int>?
    var host: Range<Int>?
    var port: Range<Int>?
    var path: Range<Int>?
    var query: Range<Int>?
    var fragment: Range<Int>?
    /// After the scheme's colon, for a URL that can't be decomposed.
    var specifier: Range<Int>?
    var decomposable = true

    init(_ string: String) {
        bytes = Array(string.utf8)
        let count = bytes.count
        var index = 0
        // The scheme: a letter, then letters, digits, "+", "-" and ".", and a colon.
        if let first = bytes.first, URLComponentScanner.isAlpha(first) {
            var end = 1
            while end < count, URLComponentScanner.isSchemeByte(bytes[end]) { end += 1 }
            if end < count, bytes[end] == UInt8(ascii: ":") {
                scheme = 0..<end
                index = end + 1
            }
        }
        if scheme != nil, index >= count || bytes[index] != UInt8(ascii: "/") {
            decomposable = false
            if index < count { specifier = index..<count }
            return
        }
        // The authority: //user:password@host:port.
        if index + 1 < count, bytes[index] == UInt8(ascii: "/"), bytes[index + 1] == UInt8(ascii: "/") {
            let start = index + 2
            var end = start
            while end < count, !"/?#".utf8.contains(bytes[end]) { end += 1 }
            var hostStart = start
            if let at = (start..<end).last(where: { bytes[$0] == UInt8(ascii: "@") }) {
                if let colon = (start..<at).first(where: { bytes[$0] == UInt8(ascii: ":") }) {
                    user = start..<colon
                    password = (colon + 1)..<at
                } else {
                    user = start..<at
                }
                hostStart = at + 1
            }
            var hostEnd = end
            if hostStart < end, bytes[hostStart] == UInt8(ascii: "["),
               let close = (hostStart..<end).first(where: { bytes[$0] == UInt8(ascii: "]") }) {
                hostEnd = close + 1
            } else if let colon = (hostStart..<end).first(where: { bytes[$0] == UInt8(ascii: ":") }) {
                hostEnd = colon
            }
            if hostEnd < end, bytes[hostEnd] == UInt8(ascii: ":") { port = (hostEnd + 1)..<end }
            if hostEnd > hostStart { host = hostStart..<hostEnd }
            index = end
        }
        var pathEnd = index
        while pathEnd < count, bytes[pathEnd] != UInt8(ascii: "?"), bytes[pathEnd] != UInt8(ascii: "#") { pathEnd += 1 }
        if pathEnd > index { path = index..<pathEnd }
        index = pathEnd
        if index < count, bytes[index] == UInt8(ascii: "?") {
            var end = index + 1
            while end < count, bytes[end] != UInt8(ascii: "#") { end += 1 }
            query = (index + 1)..<end
            index = end
        }
        if index < count, bytes[index] == UInt8(ascii: "#") { fragment = (index + 1)..<count }
    }

    static func isAlpha(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte) || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
    }

    static func isSchemeByte(_ byte: UInt8) -> Bool {
        isAlpha(byte) || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) || "+-.".utf8.contains(byte)
    }

    func text(_ range: Range<Int>?) -> String? {
        range.map { String(decoding: bytes[$0], as: UTF8.self) }
    }

    /// The components in the order they appear.
    var atoms: [Range<Int>?] { [scheme, user, password, host, port, path, query, fragment] }

    /// The net location: user and password, host and port.
    var netLocation: Range<Int>? { span(1...4) }

    /// The range from the first to the last of a run of components present.
    func span(_ indices: ClosedRange<Int>) -> Range<Int>? {
        let present = indices.compactMap { atoms[$0] }
        guard let first = present.first, let last = present.last else { return nil }
        return first.lowerBound..<last.upperBound
    }

    /// The bytes of a run of components, and those with their separators:
    /// from the end of the component before to the start of the one after.
    /// A component that isn't there has no range, and a separators range
    /// of no bytes where it would go.
    func ranges(_ indices: ClosedRange<Int>) -> (CFRange, CFRange) {
        let atoms = self.atoms
        let before = atoms[..<indices.lowerBound].compactMap { $0 }.last?.upperBound ?? 0
        guard let range = span(indices) else {
            return (CFRange(location: -1, length: 0), CFRange(location: before, length: 0))
        }
        let after = atoms[(indices.upperBound + 1)...].compactMap { $0 }.first?.lowerBound ?? bytes.count
        return (CFRange(location: range.lowerBound, length: range.count),
                CFRange(location: before, length: after - before))
    }
}

/// The string a URL was made from, relative to its base, and its components.
private func scanned(_ url: id?) -> URLComponentScanner? {
    CFURLs.url(url).map { URLComponentScanner($0.relativeString) }
}

/// Whether the URL is hierarchical (RFC 1808), so that it has a net
/// location, path, query and fragment: a relative URL is as its base is.
@c(_CFURLCanBeDecomposed)
public func CFURLCanBeDecomposed(_ url: id?) -> Bool {
    guard let value = CFURLs.url(url) else { return false }
    let parts = URLComponentScanner(value.relativeString)
    if parts.scheme == nil, let base = value.baseURL { return URLComponentScanner(base.relativeString).decomposable }
    return parts.decomposable
}

/// "user:password@host:port", still percent-encoded; the base URL's for a
/// relative URL without one, or NULL. +1.
@c(_CFURLCopyNetLocation)
public func CFURLCopyNetLocation(_ url: id?) -> id? {
    var current = CFURLs.url(url)
    while let value = current {
        let parts = URLComponentScanner(value.relativeString)
        if parts.decomposable, let range = parts.netLocation { return Strings.make(parts.text(range) ?? "") }
        current = value.baseURL
    }
    return nil
}

/// Always NULL, as on Darwin for programs linked on or after macOS 10.15
/// and iOS 13: the ";" parameters are part of the path.
@c(_CFURLCopyParameterString)
public func CFURLCopyParameterString(_ url: id?, _ charactersToLeaveEscaped: id?) -> id? { nil }

/// What follows the path, its query and fragment with their separators;
/// for a URL that can't be decomposed, all after the scheme's colon. Not
/// taken from the base URL: NULL when the URL has none of its own. +1.
@c(_CFURLCopyResourceSpecifier)
public func CFURLCopyResourceSpecifier(_ url: id?) -> id? {
    guard let parts = scanned(url) else { return nil }
    if !parts.decomposable { return parts.text(parts.specifier).map(Strings.make) }
    guard let start = parts.query.map({ $0.lowerBound - 1 }) ?? parts.fragment.map({ $0.lowerBound - 1 }) else { return nil }
    return parts.text(start..<parts.bytes.count).map(Strings.make)
}

/// The URL's own path, percent-encoded, without its leading "/", which
/// `isAbsolute` says it had; NULL for no path. +1.
@c(_CFURLCopyStrictPath)
public func CFURLCopyStrictPath(_ url: id?, _ isAbsolute: UnsafeMutablePointer<UInt8>?) -> id? {
    guard let parts = scanned(url), parts.decomposable, var path = parts.text(parts.path), !path.isEmpty else { return nil }
    let absolute = path.hasPrefix("/")
    if absolute { path.removeFirst() }
    isAbsolute?.pointee = absolute ? 1 : 0
    return Strings.make(path)
}

/// CFURLComponentType: kCFURLComponentScheme (1) … kCFURLComponentFragment (12).
private enum URLComponentTypes {
    static let scheme = 1, netLocation = 2, path = 3, resourceSpecifier = 4, user = 5, password = 6, userInfo = 7
    static let host = 8, port = 9, parameterString = 10, query = 11, fragment = 12
}

/// The bytes of a component in CFURLGetBytes's, and those with the
/// separators around it; {kCFNotFound, 0} for one the URL doesn't have,
/// whose separators range is where it would go.
@c(_CFURLGetByteRangeForComponent)
public func CFURLGetByteRangeForComponent(_ url: id?, _ component: Int, _ rangeIncludingSeparators: UnsafeMutablePointer<CFRange>?) -> CFRange {
    let notFound = CFRange(location: -1, length: 0)
    guard let parts = scanned(url) else {
        rangeIncludingSeparators?.pointee = notFound
        return notFound
    }
    if !parts.decomposable {
        // Only the scheme, with its colon, and what follows it.
        switch component {
        case URLComponentTypes.scheme:
            guard let scheme = parts.scheme else { break }
            rangeIncludingSeparators?.pointee = CFRange(location: 0, length: scheme.count + 1)
            return CFRange(location: 0, length: scheme.count)
        case URLComponentTypes.resourceSpecifier:
            guard let specifier = parts.specifier else { break }
            let range = CFRange(location: specifier.lowerBound, length: specifier.count)
            rangeIncludingSeparators?.pointee = range
            return range
        default: break
        }
        rangeIncludingSeparators?.pointee = notFound
        return notFound
    }
    // Indices in URLComponentScanner.atoms.
    let indices: ClosedRange<Int>
    switch component {
    case URLComponentTypes.scheme: indices = 0...0
    case URLComponentTypes.netLocation: indices = 1...4
    case URLComponentTypes.path: indices = 5...5
    case URLComponentTypes.resourceSpecifier: indices = 6...7
    case URLComponentTypes.user: indices = 1...1
    case URLComponentTypes.password: indices = 2...2
    case URLComponentTypes.userInfo: indices = 1...2
    case URLComponentTypes.host: indices = 3...3
    case URLComponentTypes.port: indices = 4...4
    case URLComponentTypes.query: indices = 6...6
    case URLComponentTypes.fragment: indices = 7...7
    case URLComponentTypes.parameterString:
        // Part of the path: never a component of its own.
        let (_, separators) = parts.ranges(6...6)
        rangeIncludingSeparators?.pointee = separators
        return notFound
    default:
        rangeIncludingSeparators?.pointee = notFound
        return notFound
    }
    let (range, separators) = parts.ranges(indices)
    rangeIncludingSeparators?.pointee = separators
    return range
}

/// The URL's string's bytes, relative to its base, in UTF-8: the count
/// written, or needed when `buffer` is NULL; -1 when they don't fit.
@c(_CFURLGetBytes)
public func CFURLGetBytes(_ url: id?, _ buffer: UnsafeMutablePointer<UInt8>?, _ bufferLength: Int) -> Int {
    CFURLGetBytesUsingEncoding(url, buffer, bufferLength, 0x0800_0100)
}

/// CFURLGetBytes in an encoding; -1 when the string can't be put in it.
@c(_CFURLGetBytesUsingEncoding)
public func CFURLGetBytesUsingEncoding(_ url: id?, _ buffer: UnsafeMutablePointer<UInt8>?, _ bufferLength: Int, _ encoding: UInt32) -> Int {
    guard let value = CFURLs.url(url), let bytes = CFStringEncodings.encode(value.relativeString, encoding) else { return -1 }
    guard let buffer else { return bytes.count }
    guard bytes.count <= bufferLength else { return -1 }
    buffer.update(from: bytes, count: bytes.count)
    return bytes.count
}

/// The URL's string, relative to its base, as bytes in an encoding, +1;
/// with `escapeWhitespace`, its spaces, tabs and line breaks
/// percent-escaped, as RFC 2396 recommends.
@c(_CFURLCreateData)
public func CFURLCreateData(_ allocator: UnsafeRawPointer?, _ url: id?, _ encoding: UInt32, _ escapeWhitespace: Bool) -> id? {
    guard let value = CFURLs.url(url) else { return nil }
    var text = value.relativeString
    if escapeWhitespace {
        var escaped = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case " ": escaped += "%20"
            case "\t": escaped += "%09"
            case "\n": escaped += "%0A"
            case "\r": escaped += "%0D"
            default: escaped.unicodeScalars.append(scalar)
            }
        }
        text = escaped
    }
    guard let bytes = CFStringEncodings.encode(text, encoding) else { return nil }
    return ObjC.retain(DataObjects.autoreleased(Data(bytes)))
}

/// The absolute URL of bytes in an encoding resolved against a base, +1.
/// Compatibility mode (RFC 1808's resolution) resolves as RFC 3986 does.
@c(_CFURLCreateAbsoluteURLWithBytes)
public func CFURLCreateAbsoluteURLWithBytes(_ allocator: UnsafeRawPointer?, _ bytes: UnsafePointer<UInt8>?, _ length: Int,
                                            _ encoding: UInt32, _ base: id?, _ useCompatibilityMode: Bool) -> id? {
    guard let bytes, let text = CFStringEncodings.decode(UnsafeRawBufferPointer(start: bytes, count: max(length, 0)), encoding),
          let url = URL(string: text, relativeTo: CFURLs.url(base)) else { return nil }
    return CFURLs.make(url.absoluteURL)
}

/// A file system path's URL, relative to a base URL when the path is, +1.
@c(_CFURLCreateFromFileSystemRepresentationRelativeToBase)
public func CFURLCreateFromFileSystemRepresentationRelativeToBase(_ allocator: UnsafeRawPointer?, _ buffer: UnsafePointer<UInt8>?,
                                                                  _ length: Int, _ isDirectory: Bool, _ base: id?) -> id? {
    guard let buffer else { return nil }
    let path = String(decoding: UnsafeBufferPointer(start: buffer, count: max(length, 0)), as: UTF8.self)
    return CFURLCreateWithFileSystemPathRelativeToBase(allocator, Strings.autoreleased(path), 0, isDirectory, base)
}

// MARK: - File path and file reference URLs

/// Errors CFURL's file calls report, +1, in NSCocoaErrorDomain.
enum URLFileErrors {
    static let noSuchFile = 260, unsupportedScheme = 262

    static func make(_ code: Int, _ url: URL?) -> id? {
        let description = code == noSuchFile ? "The file couldn’t be opened because there is no such file."
            : code == unsupportedScheme ? "The file couldn’t be opened because the specified URL type isn’t supported."
            : "The operation couldn’t be completed."
        var entries: [(String, id)] = [("NSLocalizedDescription", Strings.autoreleased(description))]
        if let url {
            if url.isFileURL { entries.append(("NSFilePath", Strings.autoreleased(url.path(percentEncoded: false)))) }
            if let object = URLs.autoreleased(url) { entries.append(("NSURL", object)) }
        }
        return Errors.make(domain: Errors.cocoaDomain, code: code, entries: entries)
    }

    /// A POSIX error, +1, its code Darwin's for the errno.
    static func posix(_ code: Int32, _ url: URL?) -> id? {
        var entries: [(String, id)] = []
        if let url, url.isFileURL { entries.append(("NSFilePath", Strings.autoreleased(url.path(percentEncoded: false)))) }
        return Errors.make(domain: ErrorConstants.NSPOSIXErrorDomainObject, code: Int(darwinErrno(code)), entries: entries)
    }

    /// Linux's errno as Darwin numbers it: the same up to ERANGE.
    static func darwinErrno(_ code: Int32) -> Int32 {
        switch code {
        case 35: return 11      // EDEADLK
        case 36: return 63      // ENAMETOOLONG
        case 38: return 78      // ENOSYS
        case 39: return 66      // ENOTEMPTY
        case 40: return 62      // ELOOP
        case 95: return 45      // EOPNOTSUPP
        case 122: return 69     // EDQUOT
        default: return code
        }
    }
}

/// A file URL's path, without a trailing slash.
private func filePath(_ url: URL) -> String {
    var path = url.path(percentEncoded: false)
    if path.count > 1, path.hasSuffix("/") { path.removeLast() }
    return path
}

/// The absolute file path URL of a file URL, +1; NULL, with an error, for
/// any other URL.
@c(_CFURLCreateFilePathURL)
public func CFURLCreateFilePathURL(_ allocator: UnsafeRawPointer?, _ url: id?, _ error: UnsafeMutablePointer<id?>?) -> id? {
    error?.pointee = nil
    guard let value = CFURLs.url(url), value.isFileURL else {
        error?.pointee = URLFileErrors.make(URLFileErrors.unsupportedScheme, CFURLs.url(url))
        return nil
    }
    return CFURLs.make(value.absoluteURL)
}

/// There are no file reference URLs here, which name a file by its ID: a
/// file's reference URL is its absolute path URL, +1, for a file that
/// exists; NULL, with an error, for one that doesn't.
@c(_CFURLCreateFileReferenceURL)
public func CFURLCreateFileReferenceURL(_ allocator: UnsafeRawPointer?, _ url: id?, _ error: UnsafeMutablePointer<id?>?) -> id? {
    error?.pointee = nil
    guard let value = CFURLs.url(url), value.isFileURL else {
        error?.pointee = URLFileErrors.make(URLFileErrors.unsupportedScheme, CFURLs.url(url))
        return nil
    }
    var info = stat()
    guard lstat(filePath(value), &info) == 0 else {
        error?.pointee = URLFileErrors.make(URLFileErrors.noSuchFile, value)
        return nil
    }
    return CFURLs.make(value.absoluteURL)
}

/// No URL is a file reference URL.
@c(_CFURLIsFileReferenceURL)
public func CFURLIsFileReferenceURL(_ url: id?) -> Bool { false }

/// Whether a file URL's file is there; any other URL, which can't be
/// checked, isn't. The error is +1.
@c(_CFURLResourceIsReachable)
public func CFURLResourceIsReachable(_ url: id?, _ error: UnsafeMutablePointer<id?>?) -> Bool {
    error?.pointee = nil
    guard let value = CFURLs.url(url), value.isFileURL else {
        error?.pointee = URLFileErrors.make(URLFileErrors.unsupportedScheme, CFURLs.url(url))
        return false
    }
    var info = stat()
    guard lstat(filePath(value), &info) == 0 else {
        error?.pointee = URLFileErrors.make(URLFileErrors.noSuchFile, value)
        return false
    }
    return true
}

// MARK: - Volumes

/// A file system the mount table lists.
struct FileVolume {
    let source: String
    let mountPoint: String
    let type: String
    let options: [String]

    /// The mount table, from /proc/self/mounts.
    static func all() -> [FileVolume] {
        guard let bytes = readWholeFile("/proc/self/mounts") ?? readWholeFile("/proc/mounts") else {
            return [FileVolume(source: "/", mountPoint: "/", type: "", options: [])]
        }
        return String(decoding: bytes, as: UTF8.self).split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ").map { unescaped(String($0)) }
            guard fields.count >= 4 else { return nil }
            return FileVolume(source: fields[0], mountPoint: fields[1], type: fields[2],
                              options: fields[3].split(separator: ",").map(String.init))
        }
    }

    /// The volumes a person would see: the root and the file systems on
    /// devices, each once, the root first.
    static func browsable() -> [FileVolume] {
        var seen: Set<String> = []
        var volumes: [FileVolume] = []
        let table = all()
        let root = table.last { $0.mountPoint == "/" } ?? FileVolume(source: "/", mountPoint: "/", type: "", options: [])
        for volume in [root] + table where volume.mountPoint == "/" || volume.source.hasPrefix("/dev/") {
            guard !seen.contains(volume.mountPoint) else { continue }
            // Linux's own mounts aren't volumes on the Mac.
            if ["/boot", "/boot/efi", "/snap"].contains(where: { volume.mountPoint == $0 || volume.mountPoint.hasPrefix($0 + "/") }) {
                continue
            }
            if volume.type == "squashfs" || volume.type == "swap" { continue }
            seen.insert(volume.mountPoint)
            volumes.append(volume)
        }
        return volumes
    }

    /// The volume a path is on: the mount point that holds it most closely.
    static func containing(_ path: String) -> FileVolume? {
        var resolved = path
        if let real = realpath(path, nil) {
            resolved = String(cString: real)
            free(real)
        }
        return all().filter { volume in
            volume.mountPoint == "/" || resolved == volume.mountPoint || resolved.hasPrefix(volume.mountPoint + "/")
        }.max { $0.mountPoint.count < $1.mountPoint.count }
    }

    /// The name the Mac gives a volume: the startup volume's for the root.
    var name: String { mountPoint == "/" ? PathStyles.startupVolume : Paths.lastComponent(mountPoint) }

    var url: URL { URL(filePath: mountPoint, directoryHint: .isDirectory) }

    var isReadOnly: Bool { options.contains("ro") }

    /// File systems from Windows don't keep case, links or permissions apart.
    var isWindowsFormat: Bool { ["vfat", "msdos", "exfat", "ntfs", "ntfs3", "fuseblk"].contains(type) }

    var isJournaled: Bool { ["ext3", "ext4", "xfs", "btrfs", "jfs", "reiserfs", "f2fs", "apfs", "hfsplus"].contains(type) }

    var isLocal: Bool { !["nfs", "nfs4", "cifs", "smb3", "smbfs", "sshfs", "fuse.sshfs", "9p", "afs"].contains(type) }

    /// The mount table's octal escapes (\040 for a space).
    private static func unescaped(_ field: String) -> String {
        guard field.contains("\\") else { return field }
        var bytes: [UInt8] = []
        let source = Array(field.utf8)
        var index = 0
        while index < source.count {
            if source[index] == UInt8(ascii: "\\"), index + 3 < source.count,
               let value = UInt8(String(decoding: source[(index + 1)...(index + 3)], as: UTF8.self), radix: 8) {
                bytes.append(value)
                index += 4
            } else {
                bytes.append(source[index])
                index += 1
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}

/// A file's bytes, read to its end: procfs files report no size.
private func readWholeFile(_ path: String) -> [UInt8]? {
    guard let file = fopen(path, "rb") else { return nil }
    defer { fclose(file) }
    var bytes: [UInt8] = []
    var buffer = [UInt8](repeating: 0, count: 65536)
    while true {
        let count = fread(&buffer, 1, buffer.count, file)
        if count <= 0 { break }
        bytes.append(contentsOf: buffer[0..<count])
    }
    return bytes
}

// MARK: - Resource properties

/// A URL's resource properties: temporary ones the program set, then
/// NSURL's resource values, then the keys those don't cover, read from
/// the file. Nothing else is cached, so clearing the cache clears the
/// temporary properties, as on Darwin. Temporary properties are kept by
/// the URL's absolute string, so every URL object for a file shares them.
enum URLResourceProperties {
    private static let lock = Monitor()
    /// Retained values, by URL, then key.
    nonisolated(unsafe) private static var temporary: [String: [String: id]] = [:]

    static func cacheKey(_ url: URL) -> String { url.absoluteURL.absoluteString }

    static func temporaryValue(_ url: URL, _ key: String) -> id? {
        lock.locked { temporary[cacheKey(url)]?[key] }
    }

    static func setTemporary(_ url: URL, _ key: String, _ value: id?) {
        let old: id? = lock.locked {
            let old = temporary[cacheKey(url)]?[key]
            if let value {
                temporary[cacheKey(url), default: [:]][key] = ObjC.retain(value)
            } else {
                temporary[cacheKey(url)]?[key] = nil
            }
            return old
        }
        ObjC.release(old)
    }

    /// Clears one key, or all of them.
    static func clear(_ url: URL, _ key: String?) {
        let old: [id] = lock.locked {
            let name = cacheKey(url)
            guard let values = temporary[name] else { return [] }
            if let key {
                temporary[name]?[key] = nil
                return values[key].map { [$0] } ?? []
            }
            temporary[name] = nil
            return Array(values.values)
        }
        old.forEach { ObjC.release($0) }
    }

    /// NSURL's key for a CF key whose value differs.
    static func normalized(_ key: String) -> String {
        switch key {
        case "_NSURLPathKey": return URLResourceKeys.NSURLPathKey
        case "_NSURLIsApplicationKey": return URLResourceKeys.NSURLIsApplicationKey
        default: return key
        }
    }

    /// The value of a key, +0, nil when the file has none; false, with an
    /// error (+1), when the URL isn't a file's or its file isn't there.
    static func value(_ object: id?, _ key: String, _ error: UnsafeMutablePointer<id?>?) -> (found: Bool, value: id?) {
        guard let url = CFURLs.url(object) else { return (false, nil) }
        if let temporary = temporaryValue(url, key) { return (true, temporary) }
        guard url.isFileURL else {
            error?.pointee = URLFileErrors.make(URLFileErrors.unsupportedScheme, url)
            return (false, nil)
        }
        let path = filePath(url)
        var info = stat()
        guard lstat(path, &info) == 0 else {
            error?.pointee = URLFileErrors.make(URLFileErrors.noSuchFile, url)
            return (false, nil)
        }
        let name = normalized(key)
        if let value = resourceValue(object, name) { return (true, value) }
        return (true, fileValue(path, name, info))
    }

    /// NSURL's resource value, +0.
    private static func resourceValue(_ object: id?, _ key: String) -> id? {
        typealias Get = @convention(c) (id?, SEL, UnsafeMutablePointer<id?>?, id?, UnsafeMutablePointer<id?>?) -> Bool
        var value: id?
        let name = Strings.make(key)
        defer { ObjC.release(name) }
        _ = unsafeBitCast(ObjC.msgSend, to: Get.self)(object, ObjC.selector("getResourceValue:forKey:error:"), &value, name, nil)
        return value
    }

    private static func boolean(_ flag: Bool) -> id? { perry_foundation_boolean(flag ? 1 : 0) }

    private static func number(_ value: Int64) -> id? { Numbers.make(nil, .signed(value)) }

    /// Directories a Mac shows as one item.
    static let packageExtensions: Set<String> = [
        "app", "bundle", "framework", "plugin", "kext", "xpc", "appex", "qlgenerator", "mdimporter", "prefpane",
        "saver", "component", "wdgt", "rtfd", "pkg", "mpkg", "xcodeproj", "xcworkspace", "playground", "dsym",
        "xcarchive", "photoslibrary", "musiclibrary", "lproj-package", "docset", "xcplugin", "ideplugin",
    ]

    static func isPackage(_ path: String) -> Bool {
        packageExtensions.contains(Paths.pathExtension(path).lowercased())
    }

    /// Uniform type identifiers by extension, for the files programs most
    /// often ask about.
    private static let typeIdentifiers: [String: String] = [
        "txt": "public.plain-text", "text": "public.plain-text", "rtf": "public.rtf", "html": "public.html", "htm": "public.html",
        "xml": "public.xml", "json": "public.json", "plist": "com.apple.property-list", "strings": "com.apple.xcode.strings-text",
        "png": "public.png", "jpg": "public.jpeg", "jpeg": "public.jpeg", "gif": "com.compuserve.gif", "tif": "public.tiff",
        "tiff": "public.tiff", "bmp": "com.microsoft.bmp", "heic": "public.heic", "icns": "com.apple.icns", "pdf": "com.adobe.pdf",
        "mp3": "public.mp3", "m4a": "com.apple.m4a-audio", "wav": "com.microsoft.waveform-audio", "aiff": "public.aiff-audio",
        "aif": "public.aiff-audio", "caf": "com.apple.coreaudio-format", "mov": "com.apple.quicktime-movie",
        "mp4": "public.mpeg-4", "m4v": "com.apple.m4v-video", "zip": "public.zip-archive", "gz": "org.gnu.gnu-zip-archive",
        "tar": "public.tar-archive", "dmg": "com.apple.disk-image-udif", "c": "public.c-source", "h": "public.c-header",
        "m": "public.objective-c-source", "mm": "public.objective-c-plus-plus-source", "cpp": "public.c-plus-plus-source",
        "swift": "public.swift-source", "sh": "public.shell-script", "py": "public.python-script", "js": "com.netscape.javascript-source",
        "css": "public.css", "csv": "public.comma-separated-values-text", "ttf": "public.truetype-ttf-font",
        "otf": "public.opentype-font", "dylib": "com.apple.mach-o-dylib", "nib": "com.apple.interfacebuilder.document.cocoa",
        "xib": "com.apple.interfacebuilder.document.cocoa", "storyboard": "com.apple.dt.interfacebuilder.document.storyboard",
        "sqlite": "public.database",
    ]

    static func typeIdentifier(_ path: String, _ type: mode_t) -> String {
        let ext = Paths.pathExtension(path).lowercased()
        switch type {
        case S_IFDIR:
            if ext == "app" { return "com.apple.application-bundle" }
            if ext == "framework" { return "com.apple.framework" }
            if ext == "bundle" || ext == "plugin" { return "com.apple.bundle" }
            return isPackage(path) ? "com.apple.package" : "public.folder"
        case S_IFLNK: return "public.symlink"
        case S_IFREG: return typeIdentifiers[ext] ?? (access(path, X_OK) == 0 && ext.isEmpty ? "public.unix-executable" : "public.data")
        default: return "public.item"
        }
    }

    /// The keys NSURL's resource values don't cover, from the file's stat,
    /// its directory and the volume it is on.
    private static func fileValue(_ path: String, _ key: String, _ info: stat) -> id? {
        let type = info.st_mode & S_IFMT
        switch key {
        case URLResourceKeys.NSURLFileResourceTypeKey:
            let name: String
            switch type {
            case S_IFDIR: name = "NSURLFileResourceTypeDirectory"
            case S_IFREG: name = "NSURLFileResourceTypeRegular"
            case S_IFLNK: name = "NSURLFileResourceTypeSymbolicLink"
            case S_IFIFO: name = "NSURLFileResourceTypeNamedPipe"
            case S_IFCHR: name = "NSURLFileResourceTypeCharacterSpecial"
            case S_IFBLK: name = "NSURLFileResourceTypeBlockSpecial"
            case S_IFSOCK: name = "NSURLFileResourceTypeSocket"
            default: name = "NSURLFileResourceTypeUnknown"
            }
            return Strings.autoreleased(name)
        case URLResourceKeys.NSURLIsPackageKey: return boolean(type == S_IFDIR && isPackage(path))
        case URLResourceKeys.NSURLIsApplicationKey: return boolean(type == S_IFDIR && Paths.pathExtension(path).lowercased() == "app")
        case URLResourceKeys.NSURLIsVolumeKey:
            return boolean(path == "/" || FileVolume.all().contains { $0.mountPoint == path })
        case URLResourceKeys.NSURLParentDirectoryURLKey:
            guard path != "/" else { return nil }
            return URLs.autoreleased(URL(filePath: Paths.deletingLastComponent(path), directoryHint: .isDirectory))
        case URLResourceKeys.NSURLCanonicalPathKey:
            guard let real = realpath(path, nil) else { return Strings.autoreleased(path) }
            defer { free(real) }
            return Strings.autoreleased(String(cString: real))
        case "NSURLFileIdentifierKey": return Numbers.make(nil, .unsigned(UInt64(info.st_ino)))
        case URLResourceKeys.NSURLFileResourceIdentifierKey:
            // The device and inode, which only the same file shares.
            var identifier = Data()
            withUnsafeBytes(of: UInt64(info.st_dev)) { identifier.append(contentsOf: $0) }
            withUnsafeBytes(of: UInt64(info.st_ino)) { identifier.append(contentsOf: $0) }
            return DataObjects.autoreleased(identifier)
        case URLResourceKeys.NSURLVolumeIdentifierKey: return Numbers.make(nil, .unsigned(UInt64(info.st_dev)))
        case URLResourceKeys.NSURLPreferredIOBlockSizeKey: return number(Int64(info.st_blksize))
        case "NSURLDirectoryEntryCountKey":
            guard type == S_IFDIR else { return nil }
            return number(Int64((try? FileManager.default.contentsOfDirectory(atPath: path))?.count ?? 0))
        case URLResourceKeys.NSURLTypeIdentifierKey: return Strings.autoreleased(typeIdentifier(path, type))
        case URLResourceKeys.NSURLLabelNumberKey: return number(0)
        case "NSURLIsSparseKey": return boolean(type == S_IFREG && Int64(info.st_blocks) * 512 < Int64(info.st_size))
        case URLResourceKeys.NSURLIsUserImmutableKey, URLResourceKeys.NSURLIsSystemImmutableKey, URLResourceKeys.NSURLHasHiddenExtensionKey,
             URLResourceKeys.NSURLIsAliasFileKey, URLResourceKeys.NSURLIsMountTriggerKey, URLResourceKeys.NSURLIsUbiquitousItemKey,
             "NSURLIsPurgeableKey":
            return boolean(false)
        default:
            return volumeValue(path, key)
        }
    }

    /// The volume keys, of the file system the mount table has the path on.
    private static func volumeValue(_ path: String, _ key: String) -> id? {
        guard key.hasPrefix("NSURLVolume"), let volume = FileVolume.containing(path) else { return nil }
        let portable = !volume.isWindowsFormat
        switch key {
        case URLResourceKeys.NSURLVolumeURLKey: return URLs.autoreleased(volume.url)
        case URLResourceKeys.NSURLVolumeNameKey, URLResourceKeys.NSURLVolumeLocalizedNameKey: return Strings.autoreleased(volume.name)
        case "NSURLVolumeTypeNameKey": return Strings.autoreleased(volume.type)
        case URLResourceKeys.NSURLVolumeLocalizedFormatDescriptionKey: return Strings.autoreleased(volume.type)
        case "NSURLVolumeMountFromLocationKey": return Strings.autoreleased(volume.source)
        case URLResourceKeys.NSURLVolumeIsRootFileSystemKey: return boolean(volume.mountPoint == "/")
        case URLResourceKeys.NSURLVolumeIsReadOnlyKey: return boolean(volume.isReadOnly)
        case URLResourceKeys.NSURLVolumeIsLocalKey: return boolean(volume.isLocal)
        case URLResourceKeys.NSURLVolumeIsInternalKey: return boolean(volume.isLocal)
        case URLResourceKeys.NSURLVolumeIsBrowsableKey: return boolean(FileVolume.browsable().contains { $0.mountPoint == volume.mountPoint })
        case URLResourceKeys.NSURLVolumeIsJournalingKey, URLResourceKeys.NSURLVolumeSupportsJournalingKey: return boolean(volume.isJournaled)
        case URLResourceKeys.NSURLVolumeIsEjectableKey, URLResourceKeys.NSURLVolumeIsRemovableKey, URLResourceKeys.NSURLVolumeIsAutomountedKey,
             URLResourceKeys.NSURLVolumeIsEncryptedKey, URLResourceKeys.NSURLVolumeSupportsCompressionKey,
             URLResourceKeys.NSURLVolumeSupportsExtendedSecurityKey, "NSURLVolumeSupportsFileCloningKey",
             "NSURLVolumeSupportsSwapRenamingKey", "NSURLVolumeSupportsExclusiveRenamingKey", "NSURLVolumeSupportsImmutableFilesKey",
             "NSURLVolumeSupportsFileProtectionKey":
            return boolean(false)
        case URLResourceKeys.NSURLVolumeSupportsCaseSensitiveNamesKey, URLResourceKeys.NSURLVolumeSupportsSymbolicLinksKey,
             URLResourceKeys.NSURLVolumeSupportsHardLinksKey, URLResourceKeys.NSURLVolumeSupportsSparseFilesKey,
             URLResourceKeys.NSURLVolumeSupportsZeroRunsKey, "NSURLVolumeSupportsAccessPermissionsKey":
            return boolean(portable)
        case URLResourceKeys.NSURLVolumeSupportsCasePreservedNamesKey, URLResourceKeys.NSURLVolumeSupportsPersistentIDsKey,
             URLResourceKeys.NSURLVolumeSupportsAdvisoryFileLockingKey, URLResourceKeys.NSURLVolumeSupportsVolumeSizesKey,
             URLResourceKeys.NSURLVolumeSupportsRenamingKey, URLResourceKeys.NSURLVolumeSupportsRootDirectoryDatesKey:
            return boolean(true)
        case URLResourceKeys.NSURLVolumeMaximumFileSizeKey:
            var info = statvfs()
            guard statvfs(volume.mountPoint, &info) == 0 else { return nil }
            return number(volume.type == "vfat" || volume.type == "msdos" ? 4_294_967_295 : Int64.max)
        case URLResourceKeys.NSURLVolumeTotalCapacityKey, URLResourceKeys.NSURLVolumeAvailableCapacityKey,
             URLResourceKeys.NSURLVolumeAvailableCapacityForImportantUsageKey,
             URLResourceKeys.NSURLVolumeAvailableCapacityForOpportunisticUsageKey:
            var info = statvfs()
            guard statvfs(volume.mountPoint, &info) == 0 else { return nil }
            let block = Int64(info.f_frsize)
            return number(key == URLResourceKeys.NSURLVolumeTotalCapacityKey ? Int64(info.f_blocks) * block : Int64(info.f_bavail) * block)
        case URLResourceKeys.NSURLVolumeResourceCountKey:
            var info = statvfs()
            guard statvfs(volume.mountPoint, &info) == 0 else { return nil }
            return number(Int64(info.f_files) - Int64(info.f_ffree))
        default:
            return nil
        }
    }

    /// Sets a property: the name renames the file, the dates are the
    /// file's times; others, which this file system has no place for, are
    /// accepted, as NSURL's are. The error is +1.
    static func set(_ object: id?, _ key: String, _ value: id?, _ error: UnsafeMutablePointer<id?>?) -> Bool {
        guard let url = CFURLs.url(object) else { return false }
        guard url.isFileURL else {
            error?.pointee = URLFileErrors.make(URLFileErrors.unsupportedScheme, url)
            return false
        }
        let path = filePath(url)
        var info = stat()
        guard lstat(path, &info) == 0 else {
            error?.pointee = URLFileErrors.make(URLFileErrors.noSuchFile, url)
            return false
        }
        switch normalized(key) {
        case URLResourceKeys.NSURLNameKey:
            guard let name = Strings.value(of: value), !name.isEmpty, !name.contains("/") else { return false }
            let destination = Paths.appending(Paths.deletingLastComponent(path), name)
            guard destination != path else { return true }
            guard rename(path, destination) == 0 else {
                error?.pointee = URLFileErrors.posix(errno, url)
                return false
            }
            return true
        case URLResourceKeys.NSURLContentModificationDateKey, URLResourceKeys.NSURLContentAccessDateKey:
            guard let value, ObjC.isKind(value, of: Dates.dateClass) else { return false }
            let seconds = Dates.date(value).timeIntervalSince1970
            func time(_ spec: timespec) -> timeval { timeval(tv_sec: spec.tv_sec, tv_usec: spec.tv_nsec / 1000) }
            let given = timeval(tv_sec: Int(seconds.rounded(.down)), tv_usec: Int((seconds - seconds.rounded(.down)) * 1e6))
            let modification = key == URLResourceKeys.NSURLContentModificationDateKey
            var times = [modification ? time(info.st_atim) : given, modification ? given : time(info.st_mtim)]
            guard utimes(path, &times) == 0 else {
                error?.pointee = URLFileErrors.posix(errno, url)
                return false
            }
            return true
        default:
            return true
        }
    }
}

/// A resource property of a URL's file: true, with the value (+1, NULL
/// when the file has none) at `value`; false, with an error (+1), for a
/// URL that isn't a file's or whose file isn't there.
@c(_CFURLCopyResourcePropertyForKey)
public func CFURLCopyResourcePropertyForKey(_ url: id?, _ key: id?, _ value: UnsafeMutableRawPointer?,
                                            _ error: UnsafeMutablePointer<id?>?) -> Bool {
    error?.pointee = nil
    let slot = value?.assumingMemoryBound(to: id?.self)
    slot?.pointee = nil
    guard let name = Strings.value(of: key) else { return false }
    let (found, property) = URLResourceProperties.value(url, name, error)
    guard found else { return false }
    slot?.pointee = ObjC.retain(property)
    return true
}

/// The properties of the keys the file has values for, +1; NULL, with an
/// error (+1), as CFURLCopyResourcePropertyForKey fails.
@c(_CFURLCopyResourcePropertiesForKeys)
public func CFURLCopyResourcePropertiesForKeys(_ url: id?, _ keys: id?, _ error: UnsafeMutablePointer<id?>?) -> id? {
    error?.pointee = nil
    var entries: [(key: id, value: id)] = []
    for key in Arrays.elements(keys) {
        guard let name = Strings.value(of: key) else { continue }
        let (found, property) = URLResourceProperties.value(url, name, error)
        guard found else { return nil }
        if let property { entries.append((key, property)) }
    }
    return Dictionaries.make(entries)
}

/// Sets a property of the URL's file; see URLResourceProperties.set.
@c(_CFURLSetResourcePropertyForKey)
public func CFURLSetResourcePropertyForKey(_ url: id?, _ key: id?, _ value: id?, _ error: UnsafeMutablePointer<id?>?) -> Bool {
    error?.pointee = nil
    guard let name = Strings.value(of: key) else { return false }
    return URLResourceProperties.set(url, name, value, error)
}

/// Sets each of a dictionary's properties, stopping at the first that fails.
@c(_CFURLSetResourcePropertiesForKeys)
public func CFURLSetResourcePropertiesForKeys(_ url: id?, _ values: id?, _ error: UnsafeMutablePointer<id?>?) -> Bool {
    error?.pointee = nil
    for (key, value) in Dictionaries.entries(values) {
        guard let name = Strings.value(of: key) else { continue }
        // The name goes last: the others are set on the file before it moves.
        if name == URLResourceKeys.NSURLNameKey { continue }
        guard URLResourceProperties.set(url, name, value, error) else { return false }
    }
    if let name = Dictionaries.entries(values).first(where: { Strings.value(of: $0.key) == URLResourceKeys.NSURLNameKey }) {
        return URLResourceProperties.set(url, URLResourceKeys.NSURLNameKey, name.value, error)
    }
    return true
}

/// Clears the URL's cached properties: its temporary ones, as the others
/// are read fresh each time.
@c(_CFURLClearResourcePropertyCache)
public func CFURLClearResourcePropertyCache(_ url: id?) {
    guard let value = CFURLs.url(url) else { return }
    URLResourceProperties.clear(value, nil)
}

@c(_CFURLClearResourcePropertyCacheForKey)
public func CFURLClearResourcePropertyCacheForKey(_ url: id?, _ key: id?) {
    guard let value = CFURLs.url(url), let name = Strings.value(of: key) else { return }
    URLResourceProperties.clear(value, name)
}

/// A property the URL gives in place of the file's until the cache is
/// cleared; NULL removes it.
@c(_CFURLSetTemporaryResourcePropertyForKey)
public func CFURLSetTemporaryResourcePropertyForKey(_ url: id?, _ key: id?, _ value: id?) {
    guard let url = CFURLs.url(url), let name = Strings.value(of: key) else { return }
    URLResourceProperties.setTemporary(url, name, value)
}

// MARK: - The older resource calls

/// CFURLError: what the older resource calls report.
private enum URLResourceErrors {
    static let unknown: Int32 = -10, unknownScheme: Int32 = -11, notFound: Int32 = -12, accessViolation: Int32 = -13
    static let improperArguments: Int32 = -15, unknownProperty: Int32 = -16

    static func code(_ errnoValue: Int32) -> Int32 {
        switch errnoValue {
        case ENOENT, ENOTDIR: return notFound
        case EACCES, EPERM, EROFS: return accessViolation
        default: return unknown
        }
    }
}

/// CFTypeRef CFURLCreatePropertyFromResource(alloc, url, property, SInt32
/// *errorCode): one of a file's older properties, +1: whether it exists
/// (kCFURLFileExists), its directory's contents as URLs, its length, its
/// modification time, POSIX mode and owner. HTTP URLs' are not fetched.
@c(_CFURLCreatePropertyFromResource)
public func CFURLCreatePropertyFromResource(_ allocator: UnsafeRawPointer?, _ url: id?, _ property: id?,
                                            _ errorCode: UnsafeMutablePointer<Int32>?) -> id? {
    errorCode?.pointee = 0
    guard let value = CFURLs.url(url), let name = Strings.value(of: property) else {
        errorCode?.pointee = URLResourceErrors.improperArguments
        return nil
    }
    guard value.isFileURL else {
        errorCode?.pointee = URLResourceErrors.unknownScheme
        return nil
    }
    let path = filePath(value)
    var info = stat()
    let exists = stat(path, &info) == 0
    let failure = errno
    if name == "kCFURLFileExists" { return ObjC.retain(perry_foundation_boolean(exists ? 1 : 0)) }
    guard exists else {
        errorCode?.pointee = URLResourceErrors.code(failure)
        return nil
    }
    switch name {
    case "kCFURLFileDirectoryContents":
        guard info.st_mode & S_IFMT == S_IFDIR else {
            errorCode?.pointee = URLResourceErrors.notFound
            return nil
        }
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            errorCode?.pointee = URLResourceErrors.accessViolation
            return nil
        }
        let urls = names.sorted().compactMap { entry -> id? in
            let child = Paths.appending(path, entry)
            var childInfo = stat()
            let isDirectory = stat(child, &childInfo) == 0 && childInfo.st_mode & S_IFMT == S_IFDIR
            return URLs.autoreleased(URL(filePath: child, directoryHint: isDirectory ? .isDirectory : .notDirectory))
        }
        return Arrays.make(urls)
    case "kCFURLFileLength": return ObjC.retain(Numbers.make(nil, .signed(Int64(info.st_size))))
    case "kCFURLFileLastModificationTime":
        let seconds = Double(info.st_mtim.tv_sec) + Double(info.st_mtim.tv_nsec) / 1e9
        return ObjC.retain(Dates.autoreleased(Date(timeIntervalSince1970: seconds)))
    case "kCFURLFilePOSIXMode": return ObjC.retain(Numbers.make(nil, .signed(Int64(info.st_mode))))
    case "kCFURLFileOwnerID": return ObjC.retain(Numbers.make(nil, .signed(Int64(info.st_uid))))
    default:
        errorCode?.pointee = URLResourceErrors.unknownProperty
        return nil
    }
}

/// Boolean CFURLWriteDataAndPropertiesToResource(url, data, properties,
/// SInt32 *errorCode): writes a file's data, replacing it, or makes a
/// directory for a directory URL with no data; then sets its POSIX mode
/// (kCFURLFilePOSIXMode), the one property that can be written.
@c(_CFURLWriteDataAndPropertiesToResource)
public func CFURLWriteDataAndPropertiesToResource(_ url: id?, _ data: id?, _ properties: id?,
                                                  _ errorCode: UnsafeMutablePointer<Int32>?) -> Bool {
    errorCode?.pointee = 0
    guard let value = CFURLs.url(url) else {
        errorCode?.pointee = URLResourceErrors.improperArguments
        return false
    }
    guard value.isFileURL else {
        errorCode?.pointee = URLResourceErrors.unknownScheme
        return false
    }
    let path = filePath(value)
    if let data {
        guard let file = fopen(path, "wb") else {
            errorCode?.pointee = URLResourceErrors.code(errno)
            return false
        }
        let bytes = DataObjects.data(data)
        let written = bytes.withUnsafeBytes { $0.isEmpty ? 0 : fwrite($0.baseAddress, 1, $0.count, file) }
        fclose(file)
        guard written == bytes.count else {
            errorCode?.pointee = URLResourceErrors.unknown
            return false
        }
    } else if value.hasDirectoryPath {
        var info = stat()
        if stat(path, &info) != 0, mkdir(path, 0o777) != 0 {
            errorCode?.pointee = URLResourceErrors.code(errno)
            return false
        }
    }
    for (key, property) in Dictionaries.entries(properties) {
        switch Strings.value(of: key) {
        case "kCFURLFilePOSIXMode":
            let mode = mode_t(truncatingIfNeeded: Numbers.storage(property).int64)
            guard chmod(path, mode) == 0 else {
                errorCode?.pointee = URLResourceErrors.code(errno)
                return false
            }
        default:
            errorCode?.pointee = URLResourceErrors.unknownProperty
            return false
        }
    }
    return true
}

/// Boolean CFURLDestroyResource(url, SInt32 *errorCode): removes a file,
/// or an empty directory.
@c(_CFURLDestroyResource)
public func CFURLDestroyResource(_ url: id?, _ errorCode: UnsafeMutablePointer<Int32>?) -> Bool {
    errorCode?.pointee = 0
    guard let value = CFURLs.url(url) else {
        errorCode?.pointee = URLResourceErrors.improperArguments
        return false
    }
    guard value.isFileURL else {
        errorCode?.pointee = URLResourceErrors.unknownScheme
        return false
    }
    guard remove(filePath(value)) == 0 else {
        errorCode?.pointee = URLResourceErrors.code(errno)
        return false
    }
    return true
}

/// NULL: a Carbon alias record can't be resolved here, as there's no Alias
/// Manager, so there's no bookmark to make of it.
@c(_CFURLCreateBookmarkDataFromAliasRecord)
public func CFURLCreateBookmarkDataFromAliasRecord(_ allocator: UnsafeRawPointer?, _ aliasRecord: id?) -> id? { nil }

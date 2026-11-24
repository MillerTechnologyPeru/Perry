import CPerryFoundation
import FoundationEssentials
import Glibc
import PerryObjCInterop

/// An NSURL's value: swift-foundation's URL.
final class URLStorage {
    let url: URL
    private var fileSystemPath: UnsafeMutablePointer<CChar>?

    init(_ url: URL) {
        self.url = url
    }

    deinit {
        free(fileSystemPath)
    }

    /// -fileSystemRepresentation: valid as long as the URL.
    var fileSystemRepresentation: UnsafePointer<CChar>? {
        if fileSystemPath == nil { fileSystemPath = strdup(url.path(percentEncoded: false)) }
        return UnsafePointer(fileSystemPath)
    }
}

enum URLs {
    nonisolated(unsafe) static var urlClass: Class!

    /// +URLWithString:'s URL. Programs linked on or after iOS 17 get what
    /// Apple's Foundation gives them: a string with characters a URL cannot
    /// hold is percent-encoded rather than refused.
    static func parse(_ string: String) -> URL? {
        if let url = URL(string: string) { return url }
        guard Process.sdkVersion.majorVersion >= 17 else { return nil }
        return URL(string: string, encodingInvalidCharacters: true)
    }

    static func url(_ object: id?) -> URL? {
        Storage.get(object, as: URLStorage.self)?.url
    }

    static func autoreleased(_ url: URL?, cls: id? = nil) -> id? {
        guard let url, let object = Storage.allocate(cls ?? UnsafeMutableRawPointer(urlClass)) else { return nil }
        Storage.set(object, URLStorage(url))
        return ObjC.autorelease(object)
    }

    static func initialize(_ object: id?, _ url: URL?) -> id? {
        guard let object else { return nil }
        guard let url else {
            ObjC.release(object)
            return nil
        }
        Storage.set(object, URLStorage(url))
        return object
    }

    /// A file URL for `path`, as NSURL makes one: relative paths resolve
    /// against the current directory, and directories end in "/".
    static func fileURL(_ path: String, isDirectory: Bool?) -> URL {
        var absolute = path
        if !absolute.hasPrefix("/") {
            var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
            if getcwd(&buffer, buffer.count) != nil {
                let cwd = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                absolute = cwd + (cwd.hasSuffix("/") ? "" : "/") + path
            }
        }
        if let isDirectory {
            return URL(filePath: absolute, directoryHint: isDirectory ? .isDirectory : .notDirectory)
        }
        return URL(filePath: absolute, directoryHint: .checkFileSystem)
    }


    /// A file URL for `path` against a base: an absolute path ignores it,
    /// and without one a relative path is the current directory's, as
    /// +fileURLWithPath:relativeToURL: makes them.
    static func fileURL(_ path: String, isDirectory: Bool?, relativeTo base: URL?) -> URL {
        guard let base, !path.hasPrefix("/") else { return fileURL(path, isDirectory: isDirectory) }
        let hint: URL.DirectoryHint = isDirectory.map { $0 ? .isDirectory : .notDirectory } ?? .checkFileSystem
        return URL(filePath: path, directoryHint: hint, relativeTo: base)
    }

    /// The URL in a data representation, relative to a base: its bytes as
    /// UTF-8, else ISO Latin 1, with the characters a URL can't hold
    /// percent-encoded, as +URLWithDataRepresentation:relativeToURL: reads
    /// them. Empty data is the base's own URL, with nothing of its own.
    static func url(dataRepresentation data: Data, relativeTo base: URL?) -> URL? {
        let text = String(bytes: data, encoding: .utf8) ?? String(data.map { Character(Unicode.Scalar($0)) })
        if text.isEmpty { return base.flatMap { URL(string: "", relativeTo: $0) } ?? URL(string: "") }
        if let url = URL(string: text, relativeTo: base) { return url }
        guard let encoded = URL(string: text, encodingInvalidCharacters: true)?.relativeString else { return nil }
        return URL(string: encoded, relativeTo: base)
    }

    /// A new NSURL wrapped for returning, +0; nil for no URL.
    static func wrapped(_ url: URL?, cls: ObjCClass? = nil) -> NSURL? {
        autoreleased(url, cls: cls?.pointer).map { NSURL(objCReturnValue: $0) }
    }
}

/// NSURL.
@ObjCClass("NSURL")
public final class NSURL: NSObject {
    /// Set-up after the class is defined.
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        URLs.urlClass = cls.storage
    }

    /// Every NSURL has a URL once initialized.
    var url: URL { URLs.url(objcObject) ?? URL(filePath: "/") }

    private func setURL(_ url: URL?) -> Self? {
        guard let url else { return nil }
        Storage.set(objcObject, URLStorage(url))
        return self
    }

    // MARK: Creating
    //
    // A nil string makes no URL.

    @ObjCClassMethod("URLWithString:")
    static func url(_ cls: ObjCClass, string: String?) -> NSURL? { string.flatMap { URLs.wrapped(URLs.parse($0), cls: cls) } }

    @ObjCClassMethod("URLWithString:relativeToURL:")
    static func url(_ cls: ObjCClass, string: String?, relativeTo base: NSURL?) -> NSURL? {
        guard let string else { return nil }
        return URLs.wrapped(URL(string: string, relativeTo: base?.url), cls: cls)
    }

    /// With `encode`, characters a URL cannot hold are percent-encoded
    /// instead of making the string invalid.
    @ObjCClassMethod("URLWithString:encodingInvalidCharacters:")
    static func url(_ cls: ObjCClass, string: String?, encodingInvalidCharacters encode: Bool) -> NSURL? {
        string.flatMap { URLs.wrapped(URL(string: $0, encodingInvalidCharacters: encode), cls: cls) }
    }

    @ObjCMethod("initWithString:encodingInvalidCharacters:")
    func initialize(string: String?, encodingInvalidCharacters encode: Bool) -> Self? {
        setURL(string.flatMap { URL(string: $0, encodingInvalidCharacters: encode) })
    }

    @ObjCClassMethod("fileURLWithPath:")
    static func fileURL(_ cls: ObjCClass, path: String?) -> NSURL? {
        guard let path else { return nil }
        return URLs.wrapped(URLs.fileURL(path, isDirectory: nil), cls: cls)
    }

    /// The file URL of the path the components make (+[NSString pathWithComponents:]).
    @ObjCClassMethod("fileURLWithPathComponents:")
    static func fileURL(_ cls: ObjCClass, pathComponents components: NSArray) -> NSURL? {
        URLs.wrapped(URLs.fileURL(NSString.path(components: components), isDirectory: nil), cls: cls)
    }

    @ObjCClassMethod("fileURLWithPath:isDirectory:")
    static func fileURL(_ cls: ObjCClass, path: String?, isDirectory: Bool) -> NSURL? {
        guard let path else { return nil }
        return URLs.wrapped(URLs.fileURL(path, isDirectory: isDirectory), cls: cls)
    }

    @ObjCMethod("initWithString:")
    func initialize(string: String?) -> Self? { setURL(string.flatMap { URLs.parse($0) }) }

    @ObjCMethod("initWithString:relativeToURL:")
    func initialize(string: String?, relativeTo base: NSURL?) -> Self? { setURL(string.flatMap { URL(string: $0, relativeTo: base?.url) }) }

    /// The deprecated initializer: a file URL for the "file" scheme, else
    /// scheme://host and the path, percent-encoded where it needs it.
    @ObjCMethod("initWithScheme:host:path:")
    func initialize(scheme: String?, host: String?, path: String?) -> Self? {
        guard let scheme, let path else { return setURL(nil) }
        if scheme.lowercased() == "file", host?.isEmpty ?? true { return setURL(URLs.fileURL(path, isDirectory: nil)) }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host ?? ""
        components.path = path.isEmpty || path.hasPrefix("/") ? path : "/" + path
        return setURL(components.url)
    }

    @ObjCMethod("initFileURLWithPath:")
    func initialize(filePath path: String?) -> Self? { setURL(path.map { URLs.fileURL($0, isDirectory: nil) }) }

    @ObjCMethod("initFileURLWithPath:isDirectory:")
    func initialize(filePath path: String?, isDirectory: Bool) -> Self? {
        setURL(path.map { URLs.fileURL($0, isDirectory: isDirectory) })
    }

    /// Relative to a base: a relative path stays relative, and the base
    /// resolves it; an absolute one ignores the base.
    @ObjCClassMethod("fileURLWithPath:relativeToURL:")
    static func fileURL(_ cls: ObjCClass, path: String?, relativeTo base: NSURL?) -> NSURL? {
        guard let path else { return nil }
        return URLs.wrapped(URLs.fileURL(path, isDirectory: nil, relativeTo: base?.url), cls: cls)
    }

    @ObjCClassMethod("fileURLWithPath:isDirectory:relativeToURL:")
    static func fileURL(_ cls: ObjCClass, path: String?, isDirectory: Bool, relativeTo base: NSURL?) -> NSURL? {
        guard let path else { return nil }
        return URLs.wrapped(URLs.fileURL(path, isDirectory: isDirectory, relativeTo: base?.url), cls: cls)
    }

    @ObjCMethod("initFileURLWithPath:relativeToURL:")
    func initialize(filePath path: String?, relativeTo base: NSURL?) -> Self? {
        setURL(path.map { URLs.fileURL($0, isDirectory: nil, relativeTo: base?.url) })
    }

    @ObjCMethod("initFileURLWithPath:isDirectory:relativeToURL:")
    func initialize(filePath path: String?, isDirectory: Bool, relativeTo base: NSURL?) -> Self? {
        setURL(path.map { URLs.fileURL($0, isDirectory: isDirectory, relativeTo: base?.url) })
    }

    /// A path's bytes on disk are UTF-8 here.
    private static func path(fileSystemRepresentation bytes: UnsafePointer<CChar>?) -> String? {
        bytes.map { String(cString: $0) }
    }

    @ObjCClassMethod("fileURLWithFileSystemRepresentation:isDirectory:relativeToURL:")
    static func fileURL(_ cls: ObjCClass, fileSystemRepresentation bytes: UnsafePointer<CChar>?, isDirectory: Bool,
                        relativeTo base: NSURL?) -> NSURL? {
        guard let path = NSURL.path(fileSystemRepresentation: bytes) else { return nil }
        return URLs.wrapped(URLs.fileURL(path, isDirectory: isDirectory, relativeTo: base?.url), cls: cls)
    }

    @ObjCMethod("initFileURLWithFileSystemRepresentation:isDirectory:relativeToURL:")
    func initialize(fileSystemRepresentation bytes: UnsafePointer<CChar>?, isDirectory: Bool, relativeTo base: NSURL?) -> Self? {
        setURL(NSURL.path(fileSystemRepresentation: bytes).map { URLs.fileURL($0, isDirectory: isDirectory, relativeTo: base?.url) })
    }

    // MARK: Data representations

    @ObjCClassMethod("URLWithDataRepresentation:relativeToURL:")
    static func url(_ cls: ObjCClass, dataRepresentation data: ObjCObject?, relativeTo base: NSURL?) -> NSURL? {
        URLs.wrapped(URLs.url(dataRepresentation: DataObjects.data(data?.id), relativeTo: base?.url), cls: cls)
    }

    @ObjCMethod("initWithDataRepresentation:relativeToURL:")
    func initialize(dataRepresentation data: ObjCObject?, relativeTo base: NSURL?) -> Self? {
        setURL(URLs.url(dataRepresentation: DataObjects.data(data?.id), relativeTo: base?.url))
    }

    /// As +URLWithDataRepresentation:relativeToURL:, resolved to an absolute
    /// URL with no base.
    @ObjCClassMethod("absoluteURLWithDataRepresentation:relativeToURL:")
    static func absoluteURL(_ cls: ObjCClass, dataRepresentation data: ObjCObject?, relativeTo base: NSURL?) -> NSURL? {
        URLs.wrapped(URLs.url(dataRepresentation: DataObjects.data(data?.id), relativeTo: base?.url)?.absoluteURL, cls: cls)
    }

    @ObjCMethod("initAbsoluteURLWithDataRepresentation:relativeToURL:")
    func initialize(absoluteDataRepresentation data: ObjCObject?, relativeTo base: NSURL?) -> Self? {
        setURL(URLs.url(dataRepresentation: DataObjects.data(data?.id), relativeTo: base?.url)?.absoluteURL)
    }

    /// The URL's relative string, as UTF-8.
    @ObjCMethod("dataRepresentation")
    func dataRepresentation() -> NSData { DataObjects.owned(DataStorage(Data(url.relativeString.utf8))) }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: URLs.urlClass)
    }

    // MARK: Components

    @ObjCMethod("absoluteString") func absoluteString() -> String { url.absoluteString }
    @ObjCMethod("relativeString") func relativeString() -> String { url.relativeString }
    /// The path as given, not resolved against the base URL.
    @ObjCMethod("relativePath")
    func relativePath() -> String? { URL(string: url.relativeString).map { $0.path(percentEncoded: false) } ?? url.relativePath }
    /// Everything after the scheme's colon.
    @ObjCMethod("resourceSpecifier")
    func resourceSpecifier() -> String? {
        let text = url.absoluteString
        guard let colon = text.firstIndex(of: ":"), url.scheme != nil else { return text }
        return String(text[text.index(after: colon)...])
    }
    @ObjCMethod("absoluteURL") func absoluteURL() -> NSURL? { URLs.wrapped(url.absoluteURL) }
    /// With "." and ".." taken out of its path, as NSURL does.
    @ObjCMethod("standardizedURL") func standardizedURL() -> NSURL? { URLs.wrapped(url.standardized) }
    @ObjCMethod("baseURL") func baseURL() -> NSURL? { URLs.wrapped(url.baseURL) }
    @ObjCMethod("scheme") func scheme() -> String? { url.scheme }
    @ObjCMethod("host") func host() -> String? { url.host(percentEncoded: false) }
    @ObjCMethod("port") func port() -> NSNumber? { url.port.map { Numbers.wrapped(ObjCClass(UnsafeMutableRawPointer(Numbers.numberClass)), .signed(Int64($0))) } }
    @ObjCMethod("user") func user() -> String? { url.user(percentEncoded: false) }
    @ObjCMethod("password") func password() -> String? { url.password(percentEncoded: false) }

    /// Decoded, with no trailing slash, as NSURL's path is.
    /// Resource values are not kept (excluding from backup is moot), so
    /// setting one succeeds and reading one finds none.
    @ObjCMethod("setResourceValue:forKey:error:")
    func setResourceValue(_ value: ObjCObject?, forKey key: ObjCObject?, error: UnsafeMutablePointer<id?>?) -> Bool { true }

    @ObjCMethod("setResourceValues:error:")
    func setResourceValues(_ values: ObjCObject?, error: UnsafeMutablePointer<id?>?) -> Bool { true }

    /// A file's attributes, from stat: nil for other keys and other URLs,
    /// as for a key the file has no value for.
    func resourceValue(forKey key: String) -> id? {
        guard url.isFileURL else { return nil }
        let filePath = path()
        if key == URLResourceKeys.NSURLNameKey || key == URLResourceKeys.NSURLLocalizedNameKey {
            return Strings.autoreleased(Paths.lastComponent(filePath))
        }
        if key == URLResourceKeys.NSURLPathKey { return Strings.autoreleased(filePath) }
        if key == URLResourceKeys.NSURLIsExcludedFromBackupKey || key == URLResourceKeys.NSURLIsHiddenKey && !Paths.lastComponent(filePath).hasPrefix(".") {
            return Numbers.make(nil, .bool(false))
        }
        if key == URLResourceKeys.NSURLIsHiddenKey { return Numbers.make(nil, .bool(true)) }
        if let capacity = volumeCapacity(forKey: key, path: filePath) { return capacity }
        var info = stat()
        guard lstat(filePath, &info) == 0 else { return nil }
        let type = info.st_mode & S_IFMT
        func date(_ time: timespec) -> id? {
            Dates.autoreleased(Date(timeIntervalSince1970: Double(time.tv_sec) + Double(time.tv_nsec) / 1e9))
        }
        switch key {
        case URLResourceKeys.NSURLIsDirectoryKey: return Numbers.make(nil, .bool(type == S_IFDIR))
        case URLResourceKeys.NSURLIsRegularFileKey: return Numbers.make(nil, .bool(type == S_IFREG))
        case URLResourceKeys.NSURLIsSymbolicLinkKey: return Numbers.make(nil, .bool(type == S_IFLNK))
        case URLResourceKeys.NSURLIsReadableKey: return Numbers.make(nil, .bool(access(filePath, R_OK) == 0))
        case URLResourceKeys.NSURLIsWritableKey: return Numbers.make(nil, .bool(access(filePath, W_OK) == 0))
        case URLResourceKeys.NSURLIsExecutableKey: return Numbers.make(nil, .bool(access(filePath, X_OK) == 0))
        case URLResourceKeys.NSURLFileSizeKey, URLResourceKeys.NSURLTotalFileSizeKey:
            return type == S_IFREG ? Numbers.make(nil, .signed(Int64(info.st_size))) : nil
        case URLResourceKeys.NSURLFileAllocatedSizeKey, URLResourceKeys.NSURLTotalFileAllocatedSizeKey:
            return Numbers.make(nil, .signed(Int64(info.st_blocks) * 512))
        case URLResourceKeys.NSURLContentModificationDateKey, URLResourceKeys.NSURLAttributeModificationDateKey: return date(info.st_mtim)
        case URLResourceKeys.NSURLCreationDateKey: return date(info.st_ctim)
        case URLResourceKeys.NSURLContentAccessDateKey: return date(info.st_atim)
        case URLResourceKeys.NSURLLinkCountKey: return Numbers.make(nil, .signed(Int64(info.st_nlink)))
        default: return URLFileValues.value(forKey: key, path: filePath, info: info)
        }
    }

    /// A key's value: the file's, else one set with
    /// -setTemporaryResourceValue:forKey:.
    func resourceOrTemporaryValue(forKey key: String) -> id? {
        resourceValue(forKey: key) ?? URLResourceProperties.temporaryValue(url, key)
    }

    /// The size of the file system the file is on, and the room left on
    /// it, for the volume capacity keys; nil for any other key.
    private func volumeCapacity(forKey key: String, path: String) -> id? {
        let keys: Set<String> = [URLResourceKeys.NSURLVolumeTotalCapacityKey, URLResourceKeys.NSURLVolumeAvailableCapacityKey,
                                 URLResourceKeys.NSURLVolumeAvailableCapacityForImportantUsageKey,
                                 URLResourceKeys.NSURLVolumeAvailableCapacityForOpportunisticUsageKey]
        guard keys.contains(key) else { return nil }
        var info = statvfs()
        guard statvfs(path, &info) == 0 else { return nil }
        let block = Int64(info.f_frsize)
        let bytes = key == URLResourceKeys.NSURLVolumeTotalCapacityKey ? Int64(info.f_blocks) * block : Int64(info.f_bavail) * block
        return Numbers.make(nil, .signed(bytes))
    }

    @ObjCMethod("getResourceValue:forKey:error:")
    func getResourceValue(_ value: UnsafeMutablePointer<id?>?, forKey key: ObjCObject?, error: UnsafeMutablePointer<id?>?) -> Bool {
        value?.pointee = key.flatMap { Strings.value(of: $0.id) }.flatMap(resourceOrTemporaryValue(forKey:))
        return true
    }

    /// The keys' values the file has.
    @ObjCMethod("resourceValuesForKeys:error:")
    func resourceValues(forKeys keys: ObjCObject?, error: UnsafeMutablePointer<id?>?) -> UnsafeMutableRawPointer? {
        let entries = Arrays.elements(keys?.id).compactMap { key -> (key: id, value: id)? in
            guard let name = Strings.value(of: key), let value = resourceOrTemporaryValue(forKey: name) else { return nil }
            return (key, value)
        }
        return Dictionaries.autoreleased(entries)
    }

    // A promised item is one iCloud hasn't downloaded yet; with no iCloud,
    // every item is the file itself, so these are the plain forms.

    @ObjCMethod("getPromisedItemResourceValue:forKey:error:")
    func getPromisedItemResourceValue(_ value: UnsafeMutablePointer<id?>?, forKey key: ObjCObject?,
                                      error: UnsafeMutablePointer<id?>?) -> Bool {
        getResourceValue(value, forKey: key, error: error)
    }

    @ObjCMethod("promisedItemResourceValuesForKeys:error:")
    func promisedItemResourceValues(forKeys keys: ObjCObject?, error: UnsafeMutablePointer<id?>?) -> UnsafeMutableRawPointer? {
        resourceValues(forKeys: keys, error: error)
    }

    @ObjCMethod("checkPromisedItemIsReachableAndReturnError:")
    func checkPromisedItemIsReachable(error: UnsafeMutablePointer<id?>?) -> Bool { checkResourceIsReachable(error: error) }

    /// A value kept with the URL until its cache is cleared, which the
    /// file's own value for the key comes before. Every NSURL (and CFURL)
    /// of the same URL shares them.
    @ObjCMethod("setTemporaryResourceValue:forKey:")
    func setTemporaryResourceValue(_ value: ObjCObject?, forKey key: ObjCObject?) {
        guard let name = key.flatMap({ Strings.value(of: $0.id) }) else { return }
        URLResourceProperties.setTemporary(url, name, value?.id)
    }

    /// Only temporary values are cached here: the file's are read afresh.
    @ObjCMethod("removeCachedResourceValueForKey:")
    func removeCachedResourceValue(forKey key: ObjCObject?) {
        guard let name = key.flatMap({ Strings.value(of: $0.id) }) else { return }
        URLResourceProperties.clear(url, name)
    }

    @ObjCMethod("removeAllCachedResourceValues")
    func removeAllCachedResourceValues() { URLResourceProperties.clear(url, nil) }

    @ObjCMethod("path")
    func path() -> String {
        var path = url.path(percentEncoded: false)
        if path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }

    @ObjCMethod("query") func query() -> String? { url.query(percentEncoded: true) }
    @ObjCMethod("fragment") func fragment() -> String? { url.fragment(percentEncoded: true) }
    /// The ";parameters" of the last path segment (RFC 1808), which
    /// URLs no longer have: they are part of the path.
    @ObjCMethod("parameterString") func parameterString() -> String? { nil }
    @ObjCMethod("lastPathComponent") func lastPathComponent() -> String { url.lastPathComponent }
    @ObjCMethod("pathExtension") func pathExtension() -> String { url.pathExtension }
    @ObjCMethod("pathComponents") func pathComponents() -> NSArray { Arrays.owned(url.pathComponents.map { Strings.autoreleased($0) }) }
    @ObjCMethod("isFileURL") func isFileURL() -> Bool { url.isFileURL }
    /// File URLs are path URLs here: there are no file references.
    @ObjCMethod("isFileReferenceURL") func isFileReferenceURL() -> Bool { false }
    @ObjCMethod("filePathURL") func filePathURL() -> NSURL? { url.isFileURL ? URLs.wrapped(url.absoluteURL) : nil }
    @ObjCMethod("fileReferenceURL") func fileReferenceURL() -> NSURL? { filePathURL() }

    /// Whether a file URL's file exists; any other URL cannot be checked.
    @ObjCMethod("checkResourceIsReachableAndReturnError:")
    func checkResourceIsReachable(error: UnsafeMutablePointer<id?>?) -> Bool {
        if url.isFileURL, access(path(), F_OK) == 0 { return true }
        error?.pointee = url.isFileURL
            ? Errors.autoreleased(domain: Errors.cocoaDomain, code: 260, description: "The file couldn’t be opened because there is no such file.")
            : Errors.autoreleased(domain: Errors.cocoaDomain, code: 262, description: "The operation couldn’t be completed.")
        return false
    }
    // MARK: Bookmarks

    /// A bookmark is the URL itself here: there are no file IDs or volumes
    /// to find a moved file by, and nothing is security-scoped.
    static let bookmarkPrefix = "perry-bookmark:"

    static func bookmark(for url: URL) -> Data { Data((bookmarkPrefix + url.absoluteString).utf8) }

    static func bookmarkURL(_ data: Data) -> URL? {
        let text = String(decoding: data, as: UTF8.self)
        guard text.hasPrefix(bookmarkPrefix) else { return nil }
        return URL(string: String(text.dropFirst(bookmarkPrefix.count)))
    }

    @ObjCMethod("bookmarkDataWithOptions:includingResourceValuesForKeys:relativeToURL:error:")
    func bookmarkData(options: UInt, includingResourceValuesForKeys keys: ObjCObject?, relativeTo base: NSURL?,
                      error: UnsafeMutablePointer<id?>?) -> UnsafeMutableRawPointer? {
        DataObjects.autoreleased(NSURL.bookmark(for: url))
    }

    /// An alias file's bookmark: no file here is an alias file.
    @ObjCClassMethod("bookmarkDataWithContentsOfURL:error:")
    static func bookmarkData(withContentsOf bookmarkFile: NSURL?, error: UnsafeMutablePointer<id?>?) -> UnsafeMutableRawPointer? {
        let exists = bookmarkFile.map { access($0.path(), F_OK) == 0 } ?? false
        error?.pointee = exists
            ? Errors.autoreleased(domain: Errors.cocoaDomain, code: 259, description: "The file couldn’t be opened because it isn’t in the correct format.")
            : Errors.autoreleased(domain: Errors.cocoaDomain, code: 260, description: "The file couldn’t be opened because there is no such file.")
        return nil
    }

    @ObjCClassMethod("URLByResolvingBookmarkData:options:relativeToURL:bookmarkDataIsStale:error:")
    static func resolving(bookmarkData data: ObjCObject?, options: UInt, relativeTo base: NSURL?,
                          bookmarkDataIsStale stale: UnsafeMutablePointer<Bool>?, error: UnsafeMutablePointer<id?>?) -> NSURL? {
        stale?.pointee = false
        guard let url = bookmarkURL(DataObjects.data(data?.id)) else {
            error?.pointee = Errors.autoreleased(domain: Errors.cocoaDomain, code: 259,
                                                 description: "The file couldn’t be opened because it isn’t in the correct format.")
            return nil
        }
        return URLs.wrapped(url)
    }

    /// Writes the bookmark where an alias file would go.
    @ObjCClassMethod("writeBookmarkData:toURL:options:error:")
    static func writeBookmarkData(_ data: ObjCObject?, to url: NSURL?, options: UInt, error: UnsafeMutablePointer<id?>?) -> Bool {
        guard let url, let file = fopen(url.path(), "wb") else { return false }
        defer { fclose(file) }
        let bytes = DataObjects.data(data?.id)
        return bytes.withUnsafeBytes { fwrite($0.baseAddress, 1, $0.count, file) == $0.count }
    }

    @ObjCClassMethod("resourceValuesForKeys:fromBookmarkData:")
    static func resourceValues(forKeys keys: ObjCObject?, fromBookmarkData data: ObjCObject?) -> ObjCObject? { nil }

    @ObjCMethod("startAccessingSecurityScopedResource") func startAccessingSecurityScopedResource() -> Bool { true }
    @ObjCMethod("stopAccessingSecurityScopedResource") func stopAccessingSecurityScopedResource() {}

    @ObjCMethod("initByResolvingBookmarkData:options:relativeToURL:bookmarkDataIsStale:error:")
    func initialize(resolvingBookmarkData data: ObjCObject?, options: UInt, relativeTo base: NSURL?,
                    bookmarkDataIsStale stale: UnsafeMutablePointer<Bool>?, error: UnsafeMutablePointer<id?>?) -> Self? {
        stale?.pointee = false
        guard let url = NSURL.bookmarkURL(DataObjects.data(data?.id)) else {
            error?.pointee = Errors.autoreleased(domain: Errors.cocoaDomain, code: 259,
                                                 description: "The file couldn’t be opened because it isn’t in the correct format.")
            return setURL(nil)
        }
        return setURL(url)
    }

    /// Finder's alias files are symbolic links here, as Darwin counts them
    /// too: a link resolves to what it points at (through each link in
    /// turn); anything else, and an item that isn't there, is the URL itself.
    @ObjCClassMethod("URLByResolvingAliasFileAtURL:options:error:")
    static func resolvingAliasFile(_ cls: ObjCClass, at url: NSURL?, options: UInt, error: UnsafeMutablePointer<id?>?) -> NSURL? {
        guard let url else { return nil }
        guard url.url.isFileURL else { return URLs.wrapped(url.url, cls: cls) }
        var path = url.path()
        for _ in 0..<32 {
            var info = stat()
            guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFLNK else { break }
            var buffer = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
            let length = readlink(path, &buffer, Int(PATH_MAX))
            guard length > 0 else { break }
            let target = String(decoding: buffer.prefix(length).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            path = target.hasPrefix("/") ? target : Paths.appending(Paths.deletingLastComponent(path), target)
        }
        guard path != url.path() else { return URLs.wrapped(url.url, cls: cls) }
        return URLs.wrapped(URL(filePath: Paths.normalized(path), directoryHint: .checkFileSystem), cls: cls)
    }

    @ObjCMethod("hasDirectoryPath") func hasDirectoryPath() -> Bool { url.hasDirectoryPath }

    /// The path's bytes, with their terminating NUL, when they fit; any
    /// URL's path, as Darwin gives a web URL's too.
    @ObjCMethod("getFileSystemRepresentation:maxLength:")
    func getFileSystemRepresentation(_ buffer: UnsafeMutablePointer<CChar>?, maxLength: UInt) -> Bool {
        let bytes = Array(path().utf8CString)
        guard let buffer, bytes.count <= Int(maxLength) else { return false }
        buffer.update(from: bytes, count: bytes.count)
        return true
    }

    // MARK: Loading (NSURLHandle's, deprecated)

    /// The URL's contents, read as +[NSData dataWithContentsOfURL:] reads them.
    @ObjCMethod("resourceDataUsingCache:")
    func resourceData(usingCache: Bool) -> NSData? { NSData.contents(of: self).map { DataObjects.owned(DataStorage($0)) } }

    /// Writes a file URL's contents; other URLs can't be written.
    @ObjCMethod("setResourceData:")
    func setResourceData(_ data: ObjCObject?) -> Bool {
        url.isFileURL && (try? DataObjects.data(data?.id).write(to: url)) != nil
    }

    /// Loads the contents and tells the client, as NSURLHandle did:
    /// -URL:resourceDataDidBecomeAvailable: and -URLResourceDidFinishLoading:,
    /// or -URL:resourceDidFailLoadingWithReason:.
    @ObjCMethod("loadResourceDataNotifyingClient:usingCache:")
    func loadResourceData(notifyingClient client: ObjCObject?, usingCache: Bool) {
        guard let client else { return }
        if let bytes = NSData.contents(of: self) {
            _ = ObjC.send(client.id, ObjC.selector("URL:resourceDataDidBecomeAvailable:"), objcObject, DataObjects.autoreleased(bytes))
            _ = ObjC.send(client.id, ObjC.selector("URLResourceDidFinishLoading:"), objcObject)
        } else {
            _ = ObjC.send(client.id, ObjC.selector("URL:resourceDidFailLoadingWithReason:"), objcObject,
                          Strings.autoreleased("The resource could not be loaded."))
        }
    }

    /// There are no URL handles.
    @ObjCMethod("URLHandleUsingCache:") func urlHandle(usingCache: Bool) -> UnsafeMutableRawPointer? { nil }
    @ObjCMethod("propertyForKey:") func property(forKey key: ObjCObject?) -> UnsafeMutableRawPointer? { nil }
    @ObjCMethod("setProperty:forKey:") func setProperty(_ value: ObjCObject?, forKey key: ObjCObject?) -> Bool { false }

    @ObjCMethod("fileSystemRepresentation")
    func fileSystemRepresentation() -> UnsafePointer<CChar>? {
        Storage.get(objcObject, as: URLStorage.self)?.fileSystemRepresentation
    }

    // MARK: Deriving

    @ObjCMethod("URLByAppendingPathComponent:")
    func appending(component: String) -> NSURL? {
        URLs.wrapped(url.appending(path: component, directoryHint: url.isFileURL ? .checkFileSystem : .inferFromPath))
    }

    @ObjCMethod("URLByAppendingPathComponent:isDirectory:")
    func appending(component: String, isDirectory: Bool) -> NSURL? {
        URLs.wrapped(url.appending(path: component, directoryHint: isDirectory ? .isDirectory : .notDirectory))
    }

    @ObjCMethod("URLByAppendingPathExtension:")
    func appending(pathExtension: String) -> NSURL? { URLs.wrapped(url.appendingPathExtension(pathExtension)) }

    @ObjCMethod("URLByDeletingLastPathComponent")
    func deletingLastPathComponent() -> NSURL? { URLs.wrapped(url.deletingLastPathComponent()) }

    @ObjCMethod("URLByDeletingPathExtension")
    func deletingPathExtension() -> NSURL? { URLs.wrapped(url.deletingPathExtension()) }

    /// A file URL with its symbolic links resolved where the path exists;
    /// any other URL as it is.
    @ObjCMethod("URLByResolvingSymlinksInPath")
    func resolvingSymlinksInPath() -> NSURL? { URLs.wrapped(url.isFileURL ? url.resolvingSymlinksInPath() : url) }

    /// The path with . and .. taken out.
    @ObjCMethod("URLByStandardizingPath")
    func standardizingPath() -> NSURL? { URLs.wrapped(url.standardized) }

    // MARK: Comparing

    @ObjCMethod("description") func description() -> String { url.absoluteString }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: ObjCObject?) -> Bool {
        guard let other, other.is(NSURL.self) else { return false }
        return other.unsafeCast(to: NSURL.self).url == url
    }

    @ObjCMethod("hash") func hash() -> UInt { UInt(bitPattern: url.hashValue) }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> NSURL { self }
}

/// Resource keys, which name the values a URL's file has; each one's value
/// is its name.
@ObjCConstants
enum URLResourceKeys {
    static let NSURLNameKey = "NSURLNameKey"
    static let NSURLIsDirectoryKey = "NSURLIsDirectoryKey"
    static let NSURLIsRegularFileKey = "NSURLIsRegularFileKey"
    static let NSURLFileSizeKey = "NSURLFileSizeKey"
    static let NSURLCreationDateKey = "NSURLCreationDateKey"
    static let NSURLContentModificationDateKey = "NSURLContentModificationDateKey"
    static let NSURLContentTypeKey = "NSURLContentTypeKey"
    static let NSURLIsExcludedFromBackupKey = "NSURLIsExcludedFromBackupKey"
    static let NSURLLocalizedNameKey = "NSURLLocalizedNameKey"
    static let NSURLPathKey = "NSURLPathKey"
    static let NSURLIsHiddenKey = "NSURLIsHiddenKey"
    static let NSURLIsSymbolicLinkKey = "NSURLIsSymbolicLinkKey"
    static let NSURLIsReadableKey = "NSURLIsReadableKey"
    static let NSURLIsWritableKey = "NSURLIsWritableKey"
    static let NSURLIsExecutableKey = "NSURLIsExecutableKey"
    static let NSURLTotalFileSizeKey = "NSURLTotalFileSizeKey"
    static let NSURLFileAllocatedSizeKey = "NSURLFileAllocatedSizeKey"
    static let NSURLTotalFileAllocatedSizeKey = "NSURLTotalFileAllocatedSizeKey"
    static let NSURLAttributeModificationDateKey = "NSURLAttributeModificationDateKey"
    static let NSURLContentAccessDateKey = "NSURLContentAccessDateKey"
    static let NSURLLinkCountKey = "NSURLLinkCountKey"
    static let NSURLAddedToDirectoryDateKey = "NSURLAddedToDirectoryDateKey"
    static let NSURLCanonicalPathKey = "NSURLCanonicalPathKey"
    static let NSURLDocumentIdentifierKey = "NSURLDocumentIdentifierKey"
    static let NSURLErrorKey = "NSURLErrorKey"
    static let NSURLFileProtectionKey = "NSURLFileProtectionKey"
    static let NSURLFileResourceIdentifierKey = "NSURLFileResourceIdentifierKey"
    static let NSURLFileResourceTypeKey = "NSURLFileResourceTypeKey"
    static let NSURLFileSecurityKey = "NSURLFileSecurityKey"
    static let NSURLGenerationIdentifierKey = "NSURLGenerationIdentifierKey"
    static let NSURLHasHiddenExtensionKey = "NSURLHasHiddenExtensionKey"
    static let NSURLIsAliasFileKey = "NSURLIsAliasFileKey"
    /// Darwin's value has a leading underscore, as kCFURLIsApplicationKey's.
    static let NSURLIsApplicationKey = "_NSURLIsApplicationKey"
    static let NSURLIsMountTriggerKey = "NSURLIsMountTriggerKey"
    static let NSURLIsPackageKey = "NSURLIsPackageKey"
    static let NSURLIsSystemImmutableKey = "NSURLIsSystemImmutableKey"
    static let NSURLIsUbiquitousItemKey = "NSURLIsUbiquitousItemKey"
    static let NSURLIsUserImmutableKey = "NSURLIsUserImmutableKey"
    static let NSURLIsVolumeKey = "NSURLIsVolumeKey"
    static let NSURLLabelNumberKey = "NSURLLabelNumberKey"
    static let NSURLLocalizedLabelKey = "NSURLLocalizedLabelKey"
    static let NSURLLocalizedTypeDescriptionKey = "NSURLLocalizedTypeDescriptionKey"
    static let NSURLParentDirectoryURLKey = "NSURLParentDirectoryURLKey"
    static let NSURLPreferredIOBlockSizeKey = "NSURLPreferredIOBlockSizeKey"
    static let NSURLThumbnailDictionaryKey = "NSURLThumbnailDictionaryKey"
    static let NSURLTypeIdentifierKey = "NSURLTypeIdentifierKey"
    static let NSURLUbiquitousItemContainerDisplayNameKey = "NSURLUbiquitousItemContainerDisplayNameKey"
    static let NSURLUbiquitousItemDownloadRequestedKey = "NSURLUbiquitousItemDownloadRequestedKey"
    static let NSURLUbiquitousItemDownloadingErrorKey = "NSURLUbiquitousItemDownloadingErrorKey"
    static let NSURLUbiquitousItemDownloadingStatusKey = "NSURLUbiquitousItemDownloadingStatusKey"
    static let NSURLUbiquitousItemHasUnresolvedConflictsKey = "NSURLUbiquitousItemHasUnresolvedConflictsKey"
    static let NSURLUbiquitousItemIsDownloadingKey = "NSURLUbiquitousItemIsDownloadingKey"
    static let NSURLUbiquitousItemIsSharedKey = "NSURLUbiquitousItemIsSharedKey"
    static let NSURLUbiquitousItemIsUploadedKey = "NSURLUbiquitousItemIsUploadedKey"
    static let NSURLUbiquitousItemIsUploadingKey = "NSURLUbiquitousItemIsUploadingKey"
    static let NSURLUbiquitousItemUploadingErrorKey = "NSURLUbiquitousItemUploadingErrorKey"
    static let NSURLUbiquitousSharedItemCurrentUserPermissionsKey = "NSURLUbiquitousSharedItemCurrentUserPermissionsKey"
    static let NSURLUbiquitousSharedItemCurrentUserRoleKey = "NSURLUbiquitousSharedItemCurrentUserRoleKey"
    static let NSURLUbiquitousSharedItemMostRecentEditorNameComponentsKey = "NSURLUbiquitousSharedItemMostRecentEditorNameComponentsKey"
    static let NSURLUbiquitousSharedItemOwnerNameComponentsKey = "NSURLUbiquitousSharedItemOwnerNameComponentsKey"
    static let NSURLVolumeAvailableCapacityForImportantUsageKey = "NSURLVolumeAvailableCapacityForImportantUsageKey"
    static let NSURLVolumeAvailableCapacityForOpportunisticUsageKey = "NSURLVolumeAvailableCapacityForOpportunisticUsageKey"
    static let NSURLVolumeAvailableCapacityKey = "NSURLVolumeAvailableCapacityKey"
    static let NSURLVolumeCreationDateKey = "NSURLVolumeCreationDateKey"
    static let NSURLVolumeIdentifierKey = "NSURLVolumeIdentifierKey"
    static let NSURLVolumeIsAutomountedKey = "NSURLVolumeIsAutomountedKey"
    static let NSURLVolumeIsBrowsableKey = "NSURLVolumeIsBrowsableKey"
    static let NSURLVolumeIsEjectableKey = "NSURLVolumeIsEjectableKey"
    static let NSURLVolumeIsEncryptedKey = "NSURLVolumeIsEncryptedKey"
    static let NSURLVolumeIsInternalKey = "NSURLVolumeIsInternalKey"
    static let NSURLVolumeIsJournalingKey = "NSURLVolumeIsJournalingKey"
    static let NSURLVolumeIsLocalKey = "NSURLVolumeIsLocalKey"
    static let NSURLVolumeIsReadOnlyKey = "NSURLVolumeIsReadOnlyKey"
    static let NSURLVolumeIsRemovableKey = "NSURLVolumeIsRemovableKey"
    static let NSURLVolumeIsRootFileSystemKey = "NSURLVolumeIsRootFileSystemKey"
    static let NSURLVolumeLocalizedFormatDescriptionKey = "NSURLVolumeLocalizedFormatDescriptionKey"
    static let NSURLVolumeLocalizedNameKey = "NSURLVolumeLocalizedNameKey"
    static let NSURLVolumeMaximumFileSizeKey = "NSURLVolumeMaximumFileSizeKey"
    static let NSURLVolumeNameKey = "NSURLVolumeNameKey"
    static let NSURLVolumeResourceCountKey = "NSURLVolumeResourceCountKey"
    static let NSURLVolumeSupportsAdvisoryFileLockingKey = "NSURLVolumeSupportsAdvisoryFileLockingKey"
    static let NSURLVolumeSupportsCasePreservedNamesKey = "NSURLVolumeSupportsCasePreservedNamesKey"
    static let NSURLVolumeSupportsCaseSensitiveNamesKey = "NSURLVolumeSupportsCaseSensitiveNamesKey"
    static let NSURLVolumeSupportsCompressionKey = "NSURLVolumeSupportsCompressionKey"
    static let NSURLVolumeSupportsExtendedSecurityKey = "NSURLVolumeSupportsExtendedSecurityKey"
    static let NSURLVolumeSupportsHardLinksKey = "NSURLVolumeSupportsHardLinksKey"
    static let NSURLVolumeSupportsJournalingKey = "NSURLVolumeSupportsJournalingKey"
    static let NSURLVolumeSupportsPersistentIDsKey = "NSURLVolumeSupportsPersistentIDsKey"
    static let NSURLVolumeSupportsRenamingKey = "NSURLVolumeSupportsRenamingKey"
    static let NSURLVolumeSupportsRootDirectoryDatesKey = "NSURLVolumeSupportsRootDirectoryDatesKey"
    static let NSURLVolumeSupportsSparseFilesKey = "NSURLVolumeSupportsSparseFilesKey"
    static let NSURLVolumeSupportsSymbolicLinksKey = "NSURLVolumeSupportsSymbolicLinksKey"
    static let NSURLVolumeSupportsVolumeSizesKey = "NSURLVolumeSupportsVolumeSizesKey"
    static let NSURLVolumeSupportsZeroRunsKey = "NSURLVolumeSupportsZeroRunsKey"
    static let NSURLVolumeTotalCapacityKey = "NSURLVolumeTotalCapacityKey"
    static let NSURLVolumeURLForRemountingKey = "NSURLVolumeURLForRemountingKey"
    static let NSURLVolumeURLKey = "NSURLVolumeURLKey"
    static let NSURLVolumeUUIDStringKey = "NSURLVolumeUUIDStringKey"
}

/// The resource values NSURL reads beyond the basic ones: the file's type,
/// identity and flags, and what the volume it is on can do. Keys are
/// matched by their values, so newer keys need no constant here. Values
/// that need a service Linux lacks are what Darwin gives without it: no
/// file protection class, and nothing for iCloud's keys.
enum URLFileValues {
    /// An exported constant's object (NSURLFileResourceTypeRegular and its
    /// kin), the one programs compare against; else a string of its value.
    static func constant(_ name: String) -> id? {
        ObjCConstantExports.shared.slot(name)?.pointee ?? Strings.autoreleased(name)
    }

    private static func boolean(_ flag: Bool) -> id? { Numbers.make(nil, .bool(flag)) }

    private static func number(_ value: Int64) -> id? { Numbers.make(nil, .signed(value)) }

    private static func bytes<T>(_ values: T...) -> id? {
        var data = Data()
        for value in values { withUnsafeBytes(of: value) { data.append(contentsOf: $0) } }
        return DataObjects.autoreleased(data)
    }

    /// llistxattr, looked up as the C library has it.
    nonisolated(unsafe) private static let listAttributes = dlsym(UnsafeMutableRawPointer(bitPattern: 0), "llistxattr").map {
        unsafeBitCast($0, to: (@convention(c) (UnsafePointer<CChar>?, UnsafeMutablePointer<CChar>?, Int) -> Int).self)
    }

    static func value(forKey key: String, path: String, info: stat) -> id? {
        let type = info.st_mode & S_IFMT
        switch key {
        case URLResourceKeys.NSURLFileResourceTypeKey:
            switch type {
            case S_IFDIR: return constant("NSURLFileResourceTypeDirectory")
            case S_IFREG: return constant("NSURLFileResourceTypeRegular")
            case S_IFLNK: return constant("NSURLFileResourceTypeSymbolicLink")
            case S_IFIFO: return constant("NSURLFileResourceTypeNamedPipe")
            case S_IFCHR: return constant("NSURLFileResourceTypeCharacterSpecial")
            case S_IFBLK: return constant("NSURLFileResourceTypeBlockSpecial")
            case S_IFSOCK: return constant("NSURLFileResourceTypeSocket")
            default: return constant("NSURLFileResourceTypeUnknown")
            }
        // The inode: Darwin's content identifier is the file's too, until
        // a clone shares its content.
        case "NSURLFileIdentifierKey", "NSURLFileContentIdentifierKey": return Numbers.make(nil, .unsigned(UInt64(info.st_ino)))
        // The inode and then the device, as Darwin lays the identifier out.
        case URLResourceKeys.NSURLFileResourceIdentifierKey: return bytes(UInt64(info.st_ino), UInt64(info.st_dev))
        case URLResourceKeys.NSURLVolumeIdentifierKey: return bytes(UInt64(info.st_dev))
        case URLResourceKeys.NSURLPreferredIOBlockSizeKey: return number(Int64(info.st_blksize))
        case "NSURLDirectoryEntryCountKey":
            guard type == S_IFDIR else { return nil }
            return number(Int64((try? FileManager.default.contentsOfDirectory(atPath: path))?.count ?? 0))
        case "NSURLMayHaveExtendedAttributesKey":
            return boolean(path.withCString { (listAttributes?($0, nil, 0) ?? 0) > 0 })
        case "NSURLIsSparseKey": return boolean(type == S_IFREG && Int64(info.st_blocks) * 512 < Int64(info.st_size))
        // A symbolic link is an alias file to Darwin.
        case URLResourceKeys.NSURLIsAliasFileKey: return boolean(type == S_IFLNK)
        case URLResourceKeys.NSURLIsPackageKey: return boolean(type == S_IFDIR && URLResourceProperties.isPackage(path))
        case URLResourceKeys.NSURLIsApplicationKey: return boolean(type == S_IFDIR && Paths.pathExtension(path).lowercased() == "app")
        case URLResourceKeys.NSURLIsVolumeKey:
            return boolean(path == "/" || FileVolume.all().contains { $0.mountPoint == path })
        case URLResourceKeys.NSURLHasHiddenExtensionKey, URLResourceKeys.NSURLIsUserImmutableKey, URLResourceKeys.NSURLIsSystemImmutableKey,
             URLResourceKeys.NSURLIsMountTriggerKey, "NSURLIsPurgeableKey", "NSURLMayShareFileContentKey":
            return boolean(false)
        case URLResourceKeys.NSURLLabelNumberKey: return number(0)
        case URLResourceKeys.NSURLParentDirectoryURLKey:
            guard path != "/" else { return nil }
            return URLs.autoreleased(URL(filePath: Paths.deletingLastComponent(path), directoryHint: .isDirectory))
        case URLResourceKeys.NSURLCanonicalPathKey:
            guard let real = realpath(path, nil) else { return Strings.autoreleased(path) }
            defer { free(real) }
            return Strings.autoreleased(String(cString: real))
        case URLResourceKeys.NSURLTypeIdentifierKey: return Strings.autoreleased(URLResourceProperties.typeIdentifier(path, type))
        case URLResourceKeys.NSURLFileSecurityKey:
            return FileSecurities.autoreleased(owner: info.st_uid, group: info.st_gid, mode: UInt16(truncatingIfNeeded: info.st_mode))
        default:
            return key.hasPrefix("NSURLVolume") ? volumeValue(forKey: key, path: path) : nil
        }
    }

    /// File systems that keep Linux's immutable flag (chattr +i).
    private static let immutableFlagTypes: Set<String> = ["ext2", "ext3", "ext4", "xfs", "btrfs", "f2fs", "jfs", "reiserfs", "bcachefs"]
    /// File systems renameat2 can swap two names on (RENAME_EXCHANGE) and
    /// rename without replacing on (RENAME_NOREPLACE).
    private static let swapRenamingTypes: Set<String> = ["ext4", "ext3", "ext2", "xfs", "btrfs", "f2fs", "tmpfs", "shmem", "bcachefs", "overlay"]
    private static let exclusiveRenamingTypes = swapRenamingTypes.union(["vfat", "ubifs", "minix", "hfsplus", "jfs", "reiserfs", "nilfs2"])
    /// File systems that share a copy's blocks (reflinks).
    private static let cloningTypes: Set<String> = ["btrfs", "xfs", "bcachefs", "ocfs2"]

    /// What the volume can do, by its file system's type in the mount
    /// table. No volume here encrypts by protection class.
    private static func volumeValue(forKey key: String, path: String) -> id? {
        guard let volume = FileVolume.containing(path) else { return nil }
        switch key {
        case "NSURLVolumeTypeNameKey": return Strings.autoreleased(volume.type)
        case "NSURLVolumeMountFromLocationKey": return Strings.autoreleased(volume.source)
        case URLResourceKeys.NSURLVolumeURLKey: return URLs.autoreleased(volume.url)
        case URLResourceKeys.NSURLVolumeIsRootFileSystemKey: return boolean(volume.mountPoint == "/")
        case URLResourceKeys.NSURLVolumeIsReadOnlyKey: return boolean(volume.isReadOnly)
        case URLResourceKeys.NSURLVolumeIsLocalKey: return boolean(volume.isLocal)
        case "NSURLVolumeSupportsAccessPermissionsKey": return boolean(!volume.isWindowsFormat)
        case "NSURLVolumeSupportsImmutableFilesKey": return boolean(immutableFlagTypes.contains(volume.type))
        case "NSURLVolumeSupportsSwapRenamingKey": return boolean(swapRenamingTypes.contains(volume.type))
        case "NSURLVolumeSupportsExclusiveRenamingKey": return boolean(exclusiveRenamingTypes.contains(volume.type))
        case "NSURLVolumeSupportsFileCloningKey": return boolean(cloningTypes.contains(volume.type))
        case "NSURLVolumeSupportsFileProtectionKey": return boolean(false)
        case URLResourceKeys.NSURLVolumeSupportsSymbolicLinksKey, URLResourceKeys.NSURLVolumeSupportsHardLinksKey,
             URLResourceKeys.NSURLVolumeSupportsCaseSensitiveNamesKey, URLResourceKeys.NSURLVolumeSupportsSparseFilesKey:
            return boolean(!volume.isWindowsFormat)
        case URLResourceKeys.NSURLVolumeSupportsCasePreservedNamesKey: return boolean(true)
        default: return nil
        }
    }
}

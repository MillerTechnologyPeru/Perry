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
    static func url(_ cls: ObjCClass, string: String?) -> NSURL? { string.flatMap { URLs.wrapped(URL(string: $0), cls: cls) } }

    @ObjCClassMethod("URLWithString:relativeToURL:")
    static func url(_ cls: ObjCClass, string: String?, relativeTo base: NSURL?) -> NSURL? {
        guard let string else { return nil }
        return URLs.wrapped(URL(string: string, relativeTo: base?.url), cls: cls)
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
    func initialize(string: String?) -> Self? { setURL(string.flatMap { URL(string: $0) }) }

    @ObjCMethod("initWithString:relativeToURL:")
    func initialize(string: String?, relativeTo base: NSURL?) -> Self? { setURL(string.flatMap { URL(string: $0, relativeTo: base?.url) }) }

    @ObjCMethod("initFileURLWithPath:")
    func initialize(filePath path: String?) -> Self? { setURL(path.map { URLs.fileURL($0, isDirectory: nil) }) }

    @ObjCMethod("initFileURLWithPath:isDirectory:")
    func initialize(filePath path: String?, isDirectory: Bool) -> Self? {
        setURL(path.map { URLs.fileURL($0, isDirectory: isDirectory) })
    }

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
        default: return nil
        }
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
        value?.pointee = key.flatMap { Strings.value(of: $0.id) }.flatMap(resourceValue(forKey:))
        return true
    }

    /// The keys' values the file has.
    @ObjCMethod("resourceValuesForKeys:error:")
    func resourceValues(forKeys keys: ObjCObject?, error: UnsafeMutablePointer<id?>?) -> UnsafeMutableRawPointer? {
        let entries = Arrays.elements(keys?.id).compactMap { key -> (key: id, value: id)? in
            guard let name = Strings.value(of: key), let value = resourceValue(forKey: name) else { return nil }
            return (key, value)
        }
        return Dictionaries.autoreleased(entries)
    }

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

    @ObjCMethod("hasDirectoryPath") func hasDirectoryPath() -> Bool { url.hasDirectoryPath }

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

/// Resource keys, which name the values a URL's file has.
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
    static let NSURLIsApplicationKey = "NSURLIsApplicationKey"
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

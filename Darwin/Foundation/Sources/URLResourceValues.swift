// File URLs' resource values, read from the file system's own
// attributes. Of the values that can be set, a new name renames the file;
// whether it is excluded from backups is kept, there being no backups;
// whether it is hidden is taken and ignored.
//
// Their keys are NSURLResourceKey, which swift-foundation's own
// URLResourceKey hides by its Swift name here: only unavailable
// declarations may name it by its Objective-C name. Availability is the
// compiler's, and binds nothing.

#if canImport(Darwin)
import Darwin
#endif

@available(*, unavailable)
public struct URLResourceValues {
    var _values: [NSURLResourceKey: Any]
    var _keys: Set<NSURLResourceKey>

    /// Initializes an empty set of values, to set.
    public init() {
        _values = [:]
        _keys = []
    }

    init(keys: Set<NSURLResourceKey>, values: [NSURLResourceKey: Any]) {
        _values = values
        _keys = keys
    }

    private func value<T>(_ key: NSURLResourceKey) -> T? {
        _values[key] as? T
    }

    private mutating func set(_ key: NSURLResourceKey, _ value: Any?) {
        _keys.insert(key)
        _values[key] = value
    }

    /// All the values read or set, by key.
    public var allValues: [NSURLResourceKey: Any] { _values }

    /// The resource name provided by the file system.
    public var name: String? {
        get { value(.nameKey) }
        set { set(.nameKey, newValue) }
    }

    /// True if the resource is a regular file.
    public var isRegularFile: Bool? { value(.isRegularFileKey) }

    /// True if the resource is a directory.
    public var isDirectory: Bool? { value(.isDirectoryKey) }

    /// True if the resource is a symbolic link.
    public var isSymbolicLink: Bool? { value(.isSymbolicLinkKey) }

    /// True if the resource is normally not displayed to users.
    /// Settable, but a file stays as its name makes it: hidden when it
    /// begins with a dot.
    public var isHidden: Bool? {
        get { value(.isHiddenKey) }
        set { set(.isHiddenKey, newValue) }
    }

    /// The date the resource was created.
    public var creationDate: Date? { value(.creationDateKey) }

    /// The date the resource was last accessed.
    public var contentAccessDate: Date? { value(.contentAccessDateKey) }

    /// The time the resource content was last modified.
    public var contentModificationDate: Date? { value(.contentModificationDateKey) }

    /// True if the resource is a directory the system treats as one item: a
    /// bundle or a Swift package.
    public var isPackage: Bool? { value(.isPackageKey) }

    /// True if the resource is an application.
    public var isApplication: Bool? { value(.isApplicationKey) }

    /// True if the resource is an alias file: never, there are none here.
    public var isAliasFile: Bool? { value(.isAliasFileKey) }

    /// True if the resource is the root of a volume.
    public var isVolume: Bool? { value(.isVolumeKey) }

    /// The name shown to users: the file's own.
    public var localizedName: String? { value(.localizedNameKey) }

    /// The number of hard links to the file.
    public var linkCount: Int? { value(.linkCountKey) }

    /// The file's type identifier, as a uniform type identifier: a folder, a
    /// package, or by its extension a few common ones, else plain data.
    public var typeIdentifier: String? { value(.typeIdentifierKey) }

    /// The date the resource's attributes last changed.
    public var attributeModificationDate: Date? { value(.attributeModificationDateKey) }

    /// What names the file's content: its inode number.
    public var fileContentIdentifier: Int64? { value(.fileContentIdentifierKey) }

    /// What names the file on its volume: its inode number.
    public var fileResourceIdentifier: (any NSCopying & NSSecureCoding & NSObjectProtocol)? {
        value(.fileResourceIdentifierKey)
    }

    /// Whether the file's extension is hidden: never.
    public var hasHiddenExtension: Bool? {
        get { value(.hasHiddenExtensionKey) }
        set { set(.hasHiddenExtensionKey, newValue) }
    }

    /// True if the resource should be excluded from backups.
    public var isExcludedFromBackup: Bool? {
        get { value(.isExcludedFromBackupKey) }
        set { set(.isExcludedFromBackupKey, newValue) }
    }

    /// True if this process may read the resource.
    public var isReadable: Bool? { value(.isReadableKey) }

    /// True if this process may write the resource.
    public var isWritable: Bool? { value(.isWritableKey) }

    /// The file's size in bytes.
    public var fileSize: Int? { value(.fileSizeKey) }

    /// The size the file takes on disk, in bytes.
    public var fileAllocatedSize: Int? { value(.fileAllocatedSizeKey) }

    /// The file's size, as totalFileSize: no file here has more than one
    /// fork.
    public var totalFileSize: Int? { value(.totalFileSizeKey) }

    /// The resource's path.
    public var path: String? { value(.pathKey) }

    /// The path with every symbolic link resolved.
    public var canonicalPath: String? { value(.canonicalPathKey) }

    /// The bytes free on the volume the file is on.
    public var volumeAvailableCapacity: Int? { value(.volumeAvailableCapacityKey) }

    /// The same: nothing here is purged to make room for important uses.
    public var volumeAvailableCapacityForImportantUsage: Int64? { value(.volumeAvailableCapacityForImportantUsageKey) }

    /// The volume's size in bytes.
    public var volumeTotalCapacity: Int? { value(.volumeTotalCapacityKey) }
}

@available(*, unavailable)
extension URLResourceValues: @unchecked Sendable {}

/// Resources whose exclusion from backups was set, which nothing reads but
/// the resource values asked for later.
private let excludedFromBackup = LockedState<Set<String>>(initialState: [])

@available(*, unavailable)
extension URL {
    fileprivate static let packageExtensions: Set<String> = [
        "app", "framework", "bundle", "plugin", "appex", "xpc", "swiftpm", "playground", "xcodeproj", "xcworkspace",
        "xctest", "dSYM".lowercased(), "kext", "rtfd", "pkg",
    ]

    fileprivate static let typeIdentifiers: [String: String] = [
        "swift": "public.swift-source", "txt": "public.plain-text", "json": "public.json", "plist": "com.apple.property-list",
        "png": "public.png", "jpg": "public.jpeg", "jpeg": "public.jpeg", "pdf": "com.adobe.pdf", "md": "net.daringfireball.markdown",
        "h": "public.c-header", "c": "public.c-source", "m": "public.objective-c-source", "xml": "public.xml",
        "html": "public.html", "zip": "public.zip-archive", "swiftmodule": "public.data",
    ]

    private func noSuchFile() -> CocoaError {
        CocoaError(.fileReadNoSuchFile, userInfo: [NSURLErrorKey: self, NSFilePathErrorKey: path])
    }

    /// Returns whether the resource the URL points to can be reached: for
    /// a file URL, whether the file exists.
    public func checkResourceIsReachable() throws -> Bool {
        guard isFileURL else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSURLErrorKey: self])
        }
        var info = stat()
        guard lstat(path, &info) == 0 else { throw noSuchFile() }
        return true
    }

    /// Sets the resource values the URL's values were given.
    public mutating func setResourceValues(_ values: URLResourceValues) throws {
        guard isFileURL else { throw CocoaError(.fileWriteUnknown, userInfo: [NSURLErrorKey: self]) }
        if values._keys.contains(.isExcludedFromBackupKey) {
            let key = standardizedFileURL.path
            let exclude = values.isExcludedFromBackup ?? false
            excludedFromBackup.withLock { if exclude { $0.insert(key) } else { $0.remove(key) } }
        }
        if values._keys.contains(.nameKey), let name = values.name, name != lastPathComponent {
            let destination = deletingLastPathComponent().appendingPathComponent(name)
            try FileManager.default.moveItem(at: self, to: destination)
            self = destination
        }
    }

    /// Returns the resource values for the given keys, read from the file.
    public func resourceValues(forKeys keys: Set<NSURLResourceKey>) throws -> URLResourceValues {
        guard isFileURL else { throw CocoaError(.fileReadUnsupportedScheme, userInfo: [NSURLErrorKey: self]) }
        let path = self.path
        var link = stat()
        guard lstat(path, &link) == 0 else { throw noSuchFile() }
        var info = link
        let isLink = (link.st_mode & S_IFMT) == S_IFLNK
        if isLink { _ = stat(path, &info) }
        func date(_ time: timespec) -> Date {
            Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_nsec) / 1_000_000_000)
        }
        let type = info.st_mode & S_IFMT
        var values: [NSURLResourceKey: Any] = [:]
        for key in keys {
            switch key {
            case .nameKey: values[key] = lastPathComponent
            case .isRegularFileKey: values[key] = type == S_IFREG
            case .isDirectoryKey: values[key] = type == S_IFDIR
            case .isSymbolicLinkKey: values[key] = isLink
            case .isHiddenKey: values[key] = lastPathComponent.hasPrefix(".")
            case .creationDateKey: values[key] = date(info.st_birthtimespec)
            case .contentAccessDateKey: values[key] = date(info.st_atimespec)
            case .contentModificationDateKey: values[key] = date(info.st_mtimespec)
            case .isPackageKey: values[key] = type == S_IFDIR && URL.packageExtensions.contains(pathExtension.lowercased())
            case .isApplicationKey: values[key] = type == S_IFDIR && pathExtension.lowercased() == "app"
            case .isAliasFileKey: values[key] = false
            case .isVolumeKey: values[key] = path == "/"
            case .localizedNameKey: values[key] = lastPathComponent
            case .linkCountKey: values[key] = Int(info.st_nlink)
            case .typeIdentifierKey:
                let ext = pathExtension.lowercased()
                if isLink { values[key] = "public.symlink" }
                else if type == S_IFDIR { values[key] = URL.packageExtensions.contains(ext) ? "com.apple.package" : "public.folder" }
                else { values[key] = URL.typeIdentifiers[ext] ?? "public.data" }
            case .attributeModificationDateKey: values[key] = date(info.st_ctimespec)
            case .fileContentIdentifierKey: values[key] = Int64(bitPattern: UInt64(info.st_ino))
            case .fileResourceIdentifierKey: values[key] = NSNumber(value: UInt64(info.st_ino))
            case .hasHiddenExtensionKey: values[key] = false
            case .isExcludedFromBackupKey:
                let key2 = standardizedFileURL.path
                values[key] = excludedFromBackup.withLock { $0.contains(key2) }
            case .isReadableKey: values[key] = access(path, R_OK) == 0
            case .isWritableKey: values[key] = access(path, W_OK) == 0
            case .fileSizeKey, .totalFileSizeKey:
                if type == S_IFREG { values[key] = Int(info.st_size) }
            case .fileAllocatedSizeKey:
                if type == S_IFREG { values[key] = Int(info.st_blocks) * 512 }
            case .pathKey: values[key] = path
            case .canonicalPathKey:
                if let resolved = realpath(path, nil) {
                    values[key] = String(cString: resolved)
                    free(resolved)
                }
            case .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey:
                var volume = statfs()
                guard statfs(path, &volume) == 0 else { break }
                let blocks = key == .volumeTotalCapacityKey ? UInt64(volume.f_blocks) : UInt64(volume.f_bavail)
                let bytes = blocks * UInt64(volume.f_bsize)
                if key == .volumeAvailableCapacityForImportantUsageKey {
                    values[key] = Int64(clamping: bytes)
                } else {
                    values[key] = Int(clamping: bytes)
                }
            default: break
            }
        }
        return URLResourceValues(keys: keys, values: values)
    }
}

// File URLs' resource values, read from the file system's own
// attributes. Of the values that can be set, a new name renames the file;
// whether it is excluded from backups is kept, there being no backups.
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
    public var isHidden: Bool? { value(.isHiddenKey) }

    /// The date the resource was created.
    public var creationDate: Date? { value(.creationDateKey) }

    /// The date the resource was last accessed.
    public var contentAccessDate: Date? { value(.contentAccessDateKey) }

    /// The time the resource content was last modified.
    public var contentModificationDate: Date? { value(.contentModificationDateKey) }

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
}

@available(*, unavailable)
extension URLResourceValues: @unchecked Sendable {}

/// Resources whose exclusion from backups was set, which nothing reads but
/// the resource values asked for later.
private let excludedFromBackup = LockedState<Set<String>>(initialState: [])

@available(*, unavailable)
extension URL {
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
            default: break
            }
        }
        return URLResourceValues(keys: keys, values: values)
    }
}

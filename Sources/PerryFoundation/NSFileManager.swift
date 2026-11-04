import CPerryFoundation
import FoundationEssentials
import Glibc
import PerryObjCInterop

/// NSFileManager over swift-foundation's FileManager.
enum FileManagers {
    nonisolated(unsafe) static var managerClass: Class!
    nonisolated(unsafe) static var defaultManager: id!


    static func isDirectory(_ path: String) -> Bool? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return info.st_mode & S_IFMT == S_IFDIR
    }

    /// NSSearchPathDirectory values apps ask for, in the user's home.
    static func directory(_ kind: UInt) -> String? {
        let home = getenv("HOME").map { String(cString: $0) } ?? "/"
        switch kind {
        case 5: return home + "/Library"                        // NSLibraryDirectory
        case 9: return home + "/Documents"                      // NSDocumentDirectory
        case 13: return home + "/Library/Caches"                // NSCachesDirectory
        case 14: return home + "/Library/Application Support"   // NSApplicationSupportDirectory
        default: return nil
        }
    }
}

/// Item attribute keys and file types.
@ObjCConstants
enum FileAttributes {
    static let NSFileType = "NSFileType"
    static let NSFileTypeDirectory = "NSFileTypeDirectory"
    static let NSFileTypeRegular = "NSFileTypeRegular"
    static let NSFileTypeSymbolicLink = "NSFileTypeSymbolicLink"
    static let NSFileSize = "NSFileSize"
    static let NSFileModificationDate = "NSFileModificationDate"
    static let NSFilePosixPermissions = "NSFilePosixPermissions"
    static let NSFileSystemSize = "NSFileSystemSize"
    static let NSFileSystemFreeSize = "NSFileSystemFreeSize"
    static let NSFileSystemNodes = "NSFileSystemNodes"
    static let NSFileSystemFreeNodes = "NSFileSystemFreeNodes"
    static let NSFileSystemNumber = "NSFileSystemNumber"
}

/// NSFileManager.
@ObjCClass("NSFileManager")
final class NSFileManager: NSObject {
    /// Set-up after the class is defined.
    override class func didDefineObjCClass(_ cls: ObjCClass) {
        FileManagers.managerClass = cls.storage
        FileManagers.defaultManager = ObjC.createInstance(cls.storage, 0)
    }

    private var files: FileManager { FileManager.default }

    @ObjCClassMethod("defaultManager")
    static func defaultManager() -> UnsafeMutableRawPointer? { FileManagers.defaultManager }

    /// No path names no file.
    @ObjCMethod("fileExistsAtPath:")
    func exists(atPath path: String?) -> Bool { path.map { files.fileExists(atPath: $0) } ?? false }

    @ObjCMethod("fileExistsAtPath:isDirectory:")
    func exists(atPath path: String?, isDirectory: UnsafeMutablePointer<Bool>?) -> Bool {
        guard let path else { return false }
        guard let directory = FileManagers.isDirectory(path) else { return false }
        isDirectory?.pointee = directory
        return true
    }

    @ObjCMethod("isReadableFileAtPath:") func isReadable(_ path: String) -> Bool { access(path, R_OK) == 0 }
    @ObjCMethod("isWritableFileAtPath:") func isWritable(_ path: String) -> Bool { access(path, W_OK) == 0 }
    @ObjCMethod("isExecutableFileAtPath:") func isExecutable(_ path: String) -> Bool { access(path, X_OK) == 0 }
    @ObjCMethod("isDeletableFileAtPath:")
    func isDeletable(_ path: String) -> Bool { access(Paths.deletingLastComponent(path), W_OK) == 0 }

    @ObjCMethod("currentDirectoryPath") func currentDirectoryPath() -> String { files.currentDirectoryPath }

    @ObjCMethod("changeCurrentDirectoryPath:")
    func changeCurrentDirectory(_ path: String) -> Bool { files.changeCurrentDirectoryPath(path) }

    // MARK: Creating and reading

    @ObjCMethod("createDirectoryAtPath:withIntermediateDirectories:attributes:error:")
    func createDirectory(atPath path: String, intermediates: Bool, attributes: ObjCObject?,
                         error errorPointer: UnsafeMutablePointer<id?>?) -> Bool {
        do {
            try files.createDirectory(atPath: path, withIntermediateDirectories: intermediates)
            return true
        } catch {
            FileManagers.report(errorPointer, path)
            return false
        }
    }

    @ObjCMethod("createDirectoryAtURL:withIntermediateDirectories:attributes:error:")
    func createDirectory(at url: ObjCObject, intermediates: Bool, attributes: ObjCObject?,
                         error errorPointer: UnsafeMutablePointer<id?>?) -> Bool {
        createDirectory(atPath: URLs.url(url.id)?.path(percentEncoded: false) ?? "", intermediates: intermediates,
                        attributes: attributes, error: errorPointer)
    }

    @ObjCMethod("createFileAtPath:contents:attributes:")
    func createFile(atPath path: String, contents: NSData?, attributes: ObjCObject?) -> Bool {
        files.createFile(atPath: path, contents: contents?.data)
    }

    @ObjCMethod("contentsAtPath:")
    func contents(atPath path: String) -> NSData? {
        files.contents(atPath: path).map { DataObjects.owned(DataStorage($0)) }
    }

    @ObjCMethod("contentsOfDirectoryAtPath:error:")
    func contentsOfDirectory(atPath path: String, error errorPointer: UnsafeMutablePointer<id?>?) -> NSArray? {
        do {
            return Arrays.owned(try files.contentsOfDirectory(atPath: path).map { Strings.autoreleased($0) })
        } catch {
            FileManagers.report(errorPointer, path)
            return nil
        }
    }

    /// The directory's entries as file URLs. Properties are not prefetched;
    /// option 4 (NSDirectoryEnumerationSkipsHiddenFiles) leaves out names
    /// starting with ".".
    @ObjCMethod("contentsOfDirectoryAtURL:includingPropertiesForKeys:options:error:")
    func contentsOfDirectory(at url: ObjCObject, keys: ObjCObject?, options: UInt,
                             error errorPointer: UnsafeMutablePointer<id?>?) -> NSArray? {
        let path = URLs.url(url.id)?.path(percentEncoded: false) ?? ""
        do {
            let names = try files.contentsOfDirectory(atPath: path).filter { options & 4 == 0 || !$0.hasPrefix(".") }
            return Arrays.owned(names.compactMap { URLs.autoreleased(URLs.fileURL(Paths.appending(path, $0), isDirectory: nil)) })
        } catch {
            FileManagers.report(errorPointer, path)
            return nil
        }
    }

    @ObjCMethod("subpathsOfDirectoryAtPath:error:")
    func subpaths(atPath path: String, error errorPointer: UnsafeMutablePointer<id?>?) -> NSArray? {
        do {
            return Arrays.owned(try files.subpathsOfDirectory(atPath: path).sorted().map { Strings.autoreleased($0) })
        } catch {
            FileManagers.report(errorPointer, path)
            return nil
        }
    }

    /// The deprecated form, with no error: nil when the path is missing.
    @ObjCMethod("subpathsAtPath:")
    func subpaths(atPath path: String) -> NSArray? { subpaths(atPath: path, error: nil) }

    // MARK: Changing

    @ObjCMethod("removeItemAtPath:error:")
    func removeItem(atPath path: String, error errorPointer: UnsafeMutablePointer<id?>?) -> Bool {
        do {
            try files.removeItem(atPath: path)
            return true
        } catch {
            FileManagers.report(errorPointer, path)
            return false
        }
    }

    @ObjCMethod("removeItemAtURL:error:")
    func removeItem(at url: ObjCObject, error errorPointer: UnsafeMutablePointer<id?>?) -> Bool {
        removeItem(atPath: URLs.url(url.id)?.path(percentEncoded: false) ?? "", error: errorPointer)
    }

    @ObjCMethod("copyItemAtPath:toPath:error:")
    func copyItem(atPath source: String, toPath destination: String, error errorPointer: UnsafeMutablePointer<id?>?) -> Bool {
        do {
            try files.copyItem(atPath: source, toPath: destination)
            return true
        } catch {
            FileManagers.report(errorPointer, source)
            return false
        }
    }

    @ObjCMethod("moveItemAtPath:toPath:error:")
    func moveItem(atPath source: String, toPath destination: String, error errorPointer: UnsafeMutablePointer<id?>?) -> Bool {
        do {
            try files.moveItem(atPath: source, toPath: destination)
            return true
        } catch {
            FileManagers.report(errorPointer, source)
            return false
        }
    }

    /// NSFileType, NSFileSize, NSFileModificationDate, NSFileCreationDate
    /// and NSFilePosixPermissions.
    @ObjCMethod("attributesOfItemAtPath:error:")
    func attributes(atPath path: String, error errorPointer: UnsafeMutablePointer<id?>?) -> NSDictionary? {
        var info = stat()
        guard lstat(path, &info) == 0 else {
            FileManagers.report(errorPointer, path)
            return nil
        }
        let type: String
        switch info.st_mode & S_IFMT {
        case S_IFDIR: type = "NSFileTypeDirectory"
        case S_IFLNK: type = "NSFileTypeSymbolicLink"
        default: type = "NSFileTypeRegular"
        }
        let modified = Date(timeIntervalSince1970: Double(info.st_mtim.tv_sec) + Double(info.st_mtim.tv_nsec) / 1e9)
        var entries: [(key: id, value: id)] = []
        func add(_ key: String, _ value: id?) {
            if let value { entries.append((ObjCConstantExports.shared.object(key), value)) }
        }
        add("NSFileType", ObjCConstantExports.shared.object(type))
        add("NSFileSize", Numbers.make(nil, .unsigned(UInt64(info.st_size))))
        add("NSFileModificationDate", Dates.autoreleased(modified))
        add("NSFileCreationDate", Dates.autoreleased(FileManagers.creationDate(path) ?? modified))
        add("NSFilePosixPermissions", Numbers.make(nil, .unsigned(UInt64(info.st_mode & 0o7777))))
        return Dictionaries.owned(entries)
    }

    /// The deprecated form: the item's attributes, or the link's target's.
    @ObjCMethod("fileAttributesAtPath:traverseLink:")
    func fileAttributes(atPath path: String, traverseLink: Bool) -> NSDictionary? {
        guard traverseLink, let resolved = realpath(path, nil) else { return attributes(atPath: path, error: nil) }
        defer { free(resolved) }
        return attributes(atPath: String(cString: resolved), error: nil)
    }

    /// Permissions and the modification date are applied; other keys are
    /// accepted and left as they are.
    @ObjCMethod("setAttributes:ofItemAtPath:error:")
    func setAttributes(_ attributes: NSDictionary?, ofItemAtPath path: String, error errorPointer: UnsafeMutablePointer<id?>?) -> Bool {
        guard access(path, F_OK) == 0 else {
            FileManagers.report(errorPointer, path)
            return false
        }
        let constants = ObjCConstantExports.shared
        if let permissions = Dictionaries.value(attributes?.objcObject, for: constants.object("NSFilePosixPermissions")) {
            _ = chmod(path, mode_t(truncatingIfNeeded: ObjC.sendUInt(permissions, ObjC.selector("unsignedLongValue"))))
        }
        if let date = Dictionaries.value(attributes?.objcObject, for: constants.object("NSFileModificationDate")) {
            let seconds = Dates.date(date).timeIntervalSince1970
            var times = [timespec(tv_sec: 0, tv_nsec: (1 << 30) - 2), // UTIME_OMIT: the access time stays
                         timespec(tv_sec: Int(seconds), tv_nsec: Int((seconds - seconds.rounded(.down)) * 1e9))]
            _ = utimensat(AT_FDCWD, path, &times, 0)
        }
        return true
    }

    /// The size and free space of the file system holding `path`.
    @ObjCMethod("attributesOfFileSystemForPath:error:")
    func fileSystemAttributes(forPath path: String, error errorPointer: UnsafeMutablePointer<id?>?) -> NSDictionary? {
        var info = statvfs()
        guard statvfs(path, &info) == 0 else {
            FileManagers.report(errorPointer, path)
            return nil
        }
        let constants = ObjCConstantExports.shared
        let block = UInt64(info.f_frsize)
        var entries: [(key: id, value: id)] = []
        func add(_ key: String, _ value: UInt64) {
            if let number = Numbers.make(nil, .unsigned(value)) { entries.append((constants.object(key), number)) }
        }
        add("NSFileSystemSize", UInt64(info.f_blocks) * block)
        add("NSFileSystemFreeSize", UInt64(info.f_bavail) * block)
        add("NSFileSystemNodes", UInt64(info.f_files))
        add("NSFileSystemFreeNodes", UInt64(info.f_favail))
        add("NSFileSystemNumber", UInt64(info.f_fsid))
        return Dictionaries.owned(entries)
    }

    // MARK: Standard directories

    /// NSSearchPathDirectory in NSUserDomainMask: one URL, in the home directory.
    /// No iCloud: as when the user isn't signed in to it.
    @ObjCMethod("URLForUbiquityContainerIdentifier:")
    func urlForUbiquityContainer(identifier: ObjCObject?) -> NSURL? { nil }

    @ObjCMethod("ubiquityIdentityToken") func ubiquityIdentityToken() -> ObjCObject? { nil }

    @ObjCMethod("URLsForDirectory:inDomains:")
    func urls(for directory: UInt, inDomains domains: UInt) -> NSArray {
        let found = FileManagers.directory(directory).flatMap {
            URLs.autoreleased(URL(filePath: $0, directoryHint: .isDirectory))
        }
        return Arrays.owned(found.map { [$0] } ?? [])
    }

    /// The directory, made if asked; the item replacement directory is a
    /// new temporary one.
    @ObjCMethod("URLForDirectory:inDomain:appropriateForURL:create:error:")
    func url(for directory: UInt, in domain: UInt, appropriateFor url: ObjCObject?, create: Bool,
             error errorPointer: UnsafeMutablePointer<id?>?) -> NSURL? {
        let path: String
        if directory == 99 {    // NSItemReplacementDirectory
            path = (getenv("TMPDIR").map { String(cString: $0) } ?? "/tmp") + "/(A Document Being Saved By Perry \(UInt32.random(in: 0...UInt32.max)))"
        } else if let found = FileManagers.directory(directory) {
            path = found
        } else {
            FileManagers.report(errorPointer, "directory \(directory)")
            return nil
        }
        if create || directory == 99 {
            guard createDirectory(atPath: path, intermediates: true, attributes: nil, error: errorPointer) else { return nil }
        }
        return URLs.wrapped(URL(filePath: path, directoryHint: .isDirectory))
    }
}

extension FileManagers {
    /// Reports a failure as Foundation does: an NSError in the Cocoa domain.
    static func report(_ error: UnsafeMutablePointer<id?>?, _ path: String) {
        error?.pointee = Errors.autoreleased(domain: Errors.cocoaDomain, code: 4,
                                             description: "The operation couldn’t be completed. (\(path))")
    }
}

/// NSSearchPathForDirectoriesInDomains(directory, domains, expandTilde)
@c(_NSSearchPathForDirectoriesInDomains)
public func NSSearchPathForDirectoriesInDomains(_ directory: UInt, _ domains: UInt, _ expandTilde: Bool) -> UnsafeMutableRawPointer? {
    let path = FileManagers.directory(directory)
    return Arrays.autoreleased(path.map { [Strings.autoreleased($0)] } ?? [])
}

/// File attributes and protection classes; files here are not encrypted
/// by class, so protection is only recorded.
@ObjCConstants
enum FileProtectionConstants {
    static let NSFileCreationDate = "NSFileCreationDate"
    static let NSFileProtectionKey = "NSFileProtectionKey"
    static let NSFileProtectionNone = "NSFileProtectionNone"
    static let NSFileProtectionComplete = "NSFileProtectionComplete"
    static let NSFileProtectionCompleteUnlessOpen = "NSFileProtectionCompleteUnlessOpen"
    static let NSFileProtectionCompleteUntilFirstUserAuthentication = "NSFileProtectionCompleteUntilFirstUserAuthentication"
}

extension FileManagers {
    /// When the file was made: its birth time, which statx gives where the
    /// file system keeps it.
    static func creationDate(_ path: String) -> Date? {
        var seconds: Int64 = 0, nanoseconds: UInt32 = 0
        guard perry_foundation_birth_time(path, &seconds, &nanoseconds) else { return nil }
        return Date(timeIntervalSince1970: Double(seconds) + Double(nanoseconds) / 1e9)
    }
}

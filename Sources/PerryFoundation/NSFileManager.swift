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

    @ObjCMethod("fileExistsAtPath:")
    func exists(atPath path: String) -> Bool { files.fileExists(atPath: path) }

    @ObjCMethod("fileExistsAtPath:isDirectory:")
    func exists(atPath path: String, isDirectory: UnsafeMutablePointer<Bool>?) -> Bool {
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

    @ObjCMethod("subpathsOfDirectoryAtPath:error:")
    func subpaths(atPath path: String, error errorPointer: UnsafeMutablePointer<id?>?) -> NSArray? {
        do {
            return Arrays.owned(try files.subpathsOfDirectory(atPath: path).sorted().map { Strings.autoreleased($0) })
        } catch {
            FileManagers.report(errorPointer, path)
            return nil
        }
    }

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

    /// NSFileType, NSFileSize, NSFileModificationDate and NSFilePosixPermissions.
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
        add("NSFilePosixPermissions", Numbers.make(nil, .unsigned(UInt64(info.st_mode & 0o7777))))
        return Dictionaries.owned(entries)
    }

    // MARK: Standard directories

    /// NSSearchPathDirectory in NSUserDomainMask: one URL, in the home directory.
    @ObjCMethod("URLsForDirectory:inDomains:")
    func urls(for directory: UInt, inDomains domains: UInt) -> NSArray {
        let found = FileManagers.directory(directory).flatMap {
            URLs.autoreleased(URL(filePath: $0, directoryHint: .isDirectory))
        }
        return Arrays.owned(found.map { [$0] } ?? [])
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

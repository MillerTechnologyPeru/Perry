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
        // Every domain's directory is the home's, as an app's sandbox has them.
        switch kind {
        case 1, 100: return home + "/Applications"              // NSApplicationDirectory, NSAllApplicationsDirectory
        case 2: return home + "/Applications/Demos"             // NSDemoApplicationDirectory
        case 3: return home + "/Developer/Applications"         // NSDeveloperApplicationDirectory
        case 4: return home + "/Applications/Utilities"         // NSAdminApplicationDirectory
        case 5, 101: return home + "/Library"                   // NSLibraryDirectory, NSAllLibrariesDirectory
        case 6: return home + "/Developer"                      // NSDeveloperDirectory
        case 7: return "/" + home.split(separator: "/").dropLast().joined(separator: "/")   // NSUserDirectory: the homes' folder
        case 8: return home + "/Library/Documentation"          // NSDocumentationDirectory
        case 9: return home + "/Documents"                      // NSDocumentDirectory
        case 10: return home + "/Library/CoreServices"          // NSCoreServiceDirectory
        case 11: return home + "/Library/Autosave Information"  // NSAutosavedInformationDirectory
        case 12: return home + "/Desktop"                       // NSDesktopDirectory
        case 13: return home + "/Library/Caches"                // NSCachesDirectory
        case 14: return home + "/Library/Application Support"   // NSApplicationSupportDirectory
        case 15: return home + "/Downloads"                     // NSDownloadsDirectory
        case 16: return home + "/Library/Input Methods"         // NSInputMethodsDirectory
        case 17: return home + "/Movies"                        // NSMoviesDirectory
        case 18: return home + "/Music"                         // NSMusicDirectory
        case 19: return home + "/Pictures"                      // NSPicturesDirectory
        case 20: return home + "/Library/Printers/PPDs"         // NSPrinterDescriptionDirectory
        case 21: return home + "/Public"                        // NSSharedPublicDirectory
        case 22: return home + "/Library/PreferencePanes"       // NSPreferencePanesDirectory
        case 23: return home + "/Library/Application Scripts"   // NSApplicationScriptsDirectory
        case 102: return home + "/.Trash"                       // NSTrashDirectory
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
    /// HFS type and creator codes, which Linux's files have no place for:
    /// setting them changes nothing, and they read as 0.
    static let NSFileHFSTypeCode = "NSFileHFSTypeCode"
    static let NSFileHFSCreatorCode = "NSFileHFSCreatorCode"
    static let NSFileImmutable = "NSFileImmutable"
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
    /// A path from its bytes on disk, which are UTF-8 here.
    @ObjCMethod("stringWithFileSystemRepresentation:length:")
    func string(fileSystemRepresentation bytes: UnsafePointer<UInt8>?, length: UInt) -> String? {
        guard let bytes else { return nil }
        return String(decoding: UnsafeBufferPointer(start: bytes, count: Int(length)), as: UTF8.self)
    }

    @ObjCMethod("fileExistsAtPath:")
    func exists(atPath path: String?) -> Bool { path.map { files.fileExists(atPath: $0) } ?? false }

    /// The name Finder shows: the last path component, without the
    /// extension of a bundle (.app and the like), whose extension Finder
    /// hides. No file is localized here.
    @ObjCMethod("displayNameAtPath:")
    func displayName(atPath path: String?) -> String {
        guard let path, !path.isEmpty else { return "" }
        var name = path
        while name.count > 1, name.hasSuffix("/") { name.removeLast() }
        name = String(name.split(separator: "/").last ?? Substring(name))
        for suffix in [".app", ".bundle", ".framework", ".plugin"] where name.hasSuffix(suffix) {
            name.removeLast(suffix.count)
        }
        return name
    }

    /// Each component's display name, from the root.
    @ObjCMethod("componentsToDisplayForPath:")
    func componentsToDisplay(forPath path: String?) -> NSArray? {
        guard let path, path.hasPrefix("/") else { return nil }
        var components: [String] = [], prefix = ""
        for part in path.split(separator: "/") {
            prefix += "/" + part
            components.append(displayName(atPath: prefix))
        }
        return Arrays.owned(components.map { Strings.autoreleased($0) })
    }

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

    /// Before -createDirectoryAtPath:withIntermediateDirectories:attributes:error:'s day.
    @ObjCMethod("createDirectoryAtPath:attributes:")
    func createDirectory(atPath path: String, attributes: ObjCObject?) -> Bool {
        createDirectory(atPath: path, intermediates: false, attributes: attributes, error: nil)
    }

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
        createDirectory(atPath: FileManagers.path(URLs.url(url.id)), intermediates: intermediates,
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

    /// Before -contentsOfDirectoryAtPath:error:'s day.
    @ObjCMethod("directoryContentsAtPath:")
    func directoryContents(atPath path: String) -> NSArray? { contentsOfDirectory(atPath: path, error: nil) }

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
        let path = FileManagers.path(URLs.url(url.id))
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

    /// The directory's subpaths, as they are when it is made; none if it is
    /// missing. -skipDescendants and the attributes aren't supported.
    @ObjCMethod("enumeratorAtPath:")
    func enumerator(atPath path: String) -> ObjCObject {
        NSDirectoryEnumerator.make(((try? files.subpathsOfDirectory(atPath: path)) ?? []).sorted().map { Strings.autoreleased($0) })
    }

    /// The directory's contents as URLs, as they are when it is made, by
    /// NSDirectoryEnumerationOptions: 1 skips subdirectories' contents, 4
    /// hidden files. Missing directories give none; the keys and the error
    /// handler aren't used.
    @ObjCMethod("enumeratorAtURL:includingPropertiesForKeys:options:errorHandler:")
    func enumerator(at url: NSURL?, keys: ObjCObject?, options: UInt, errorHandler: ObjCObject?) -> ObjCObject? {
        guard let url else { return nil }
        let root = url.url.path(percentEncoded: false)
        let paths = options & 1 != 0
            ? (try? files.contentsOfDirectory(atPath: root)) ?? []
            : (try? files.subpathsOfDirectory(atPath: root)) ?? []
        let visible = options & 4 != 0 ? paths.filter { !$0.split(separator: "/").contains { $0.hasPrefix(".") } } : paths
        let base = root.hasSuffix("/") ? root : root + "/"
        return NSDirectoryEnumerator.make(visible.sorted().compactMap { URLs.wrapped(URL(filePath: base + $0))?.objcObject })
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

    @ObjCMethod("removeItemAtURL:error:")
    func removeItem(at url: ObjCObject, error errorPointer: UnsafeMutablePointer<id?>?) -> Bool {
        removeItem(atPath: FileManagers.path(URLs.url(url.id)), error: errorPointer)
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

    @ObjCMethod("copyItemAtURL:toURL:error:")
    func copyItem(at source: NSURL, to destination: NSURL, error errorPointer: UnsafeMutablePointer<id?>?) -> Bool {
        copyItem(atPath: FileManagers.path(source.url), toPath: FileManagers.path(destination.url), error: errorPointer)
    }

    @ObjCMethod("createSymbolicLinkAtPath:withDestinationPath:error:")
    func createSymbolicLink(atPath path: String, withDestinationPath destination: String, error errorPointer: UnsafeMutablePointer<id?>?) -> Bool {
        guard symlink(destination, path) == 0 else {
            FileManagers.report(errorPointer, path)
            return false
        }
        return true
    }

    @ObjCMethod("moveItemAtURL:toURL:error:")
    func moveItem(at source: NSURL, to destination: NSURL, error errorPointer: UnsafeMutablePointer<id?>?) -> Bool {
        moveItem(atPath: FileManagers.path(source.url), toPath: FileManagers.path(destination.url), error: errorPointer)
    }

    @ObjCMethod("destinationOfSymbolicLinkAtPath:error:")
    func destinationOfSymbolicLink(atPath path: String, error errorPointer: UnsafeMutablePointer<id?>?) -> String? {
        do {
            return try files.destinationOfSymbolicLink(atPath: path)
        } catch {
            FileManagers.report(errorPointer, path)
            return nil
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

    /// An app group's shared container: a directory of the group's in the
    /// app's container, made the first time it's asked for, as the app
    /// were the group's only member.
    @ObjCMethod("containerURLForSecurityApplicationGroupIdentifier:")
    func containerURL(forSecurityApplicationGroupIdentifier identifier: String?) -> NSURL? {
        guard let identifier, !identifier.isEmpty, !identifier.contains("/") else { return nil }
        let home = getenv("HOME").map { String(cString: $0) } ?? "/tmp"
        let path = home + "/Shared/AppGroup/" + identifier
        guard createDirectory(atPath: path, intermediates: true, attributes: nil, error: nil) else { return nil }
        return URLs.wrapped(URL(filePath: path, directoryHint: .isDirectory))
    }

    @ObjCMethod("URLsForDirectory:inDomains:")
    func urls(for directory: UInt, inDomains domains: UInt) -> NSArray {
        let found = FileManagers.directory(directory).flatMap {
            URLs.autoreleased(URL(filePath: $0, directoryHint: .isDirectory))
        }
        return Arrays.owned(found.map { [$0] } ?? [])
    }

    /// How the item is placed against a directory: 0 inside it, 1 the
    /// directory itself, 2 elsewhere. Paths are compared with their links
    /// resolved.
    private func relationship(ofDirectory directory: String, to item: String) -> Int {
        func resolved(_ path: String) -> String {
            guard let real = realpath(path, nil) else { return path }
            defer { free(real) }
            return String(cString: real)
        }
        let directory = resolved(directory), item = resolved(item)
        if directory == item { return 1 }
        return item.hasPrefix(directory.hasSuffix("/") ? directory : directory + "/") ? 0 : 2
    }

    @ObjCMethod("getRelationship:ofDirectory:inDomain:toItemAtURL:error:")
    func getRelationship(_ relationship: UnsafeMutablePointer<Int>?, ofDirectory directory: UInt, inDomain domain: UInt,
                         toItemAt url: ObjCObject, error errorPointer: UnsafeMutablePointer<id?>?) -> Bool {
        guard let path = FileManagers.directory(directory) else {
            FileManagers.report(errorPointer, "directory \(directory)")
            return false
        }
        relationship?.pointee = self.relationship(ofDirectory: path, to: FileManagers.path(URLs.url(url.id)))
        return true
    }

    @ObjCMethod("getRelationship:ofDirectoryAtURL:toItemAtURL:error:")
    func getRelationship(_ relationship: UnsafeMutablePointer<Int>?, ofDirectoryAt directory: ObjCObject,
                         toItemAt url: ObjCObject, error errorPointer: UnsafeMutablePointer<id?>?) -> Bool {
        relationship?.pointee = self.relationship(ofDirectory: FileManagers.path(URLs.url(directory.id)),
                                                  to: FileManagers.path(URLs.url(url.id)))
        return true
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
    /// A URL's file path as -path gives it: without the trailing slash of a
    /// directory URL, which would make a file's path a directory's.
    static func path(_ url: URL?) -> String {
        var path = url?.path(percentEncoded: false) ?? ""
        if path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }

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

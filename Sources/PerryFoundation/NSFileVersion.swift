import FoundationEssentials
import Glibc
import PerryObjCInterop

// NSFileVersion: a file's versions. Linux keeps no versions of a file and
// has no iCloud, so a file has only its current version, the one Darwin
// gives for a plain local file: the file itself, local, neither a conflict
// nor resolved, named by its file name, dated by its modification time,
// with an empty dictionary for its persistent identifier. There are no
// other versions nor conflicts, removing the others succeeds as there are
// none, and the current version can't be removed, replaced from, or made
// discardable, as on Darwin.

/// The version's file.
final class FileVersionStorage {
    let url: URL

    init(_ url: URL) { self.url = url }
}

/// Completion handlers of services Linux doesn't have, called as Darwin
/// calls them when the service has nothing: later, on a global queue, with
/// no result and the error.
enum FileServiceCompletions {
    private final class Call {
        let block: id
        let error: id?
        let takesResult: Bool

        init(_ block: id, _ error: id?, takesResult: Bool) {
            self.block = ObjC.retainBlock(block) ?? block
            self.error = ObjC.retain(error)
            self.takesResult = takesResult
        }

        deinit {
            ObjC.release(block)
            ObjC.release(error)
        }
    }

    /// Calls `block` with (nil, error), or with (error) alone when it takes
    /// no result.
    static func fail(_ block: id?, error: id?, takesResult: Bool) {
        guard let block, let queue = Dispatch.globalQueue?(0x15, 0), let async = Dispatch.async else { return }
        let context = Unmanaged.passRetained(Call(block, error, takesResult: takesResult)).toOpaque()
        async(queue, context) { context in
            guard let context else { return }
            let call = Unmanaged<Call>.fromOpaque(context).takeRetainedValue()
            ObjC.autoreleasepool {
                if call.takesResult {
                    Blocks.invoke(call.block, as: (@convention(c) (id, id?, id?) -> Void).self)(call.block, nil, call.error)
                } else {
                    Blocks.invoke(call.block, as: (@convention(c) (id, id?) -> Void).self)(call.block, call.error)
                }
            }
        }
    }

    /// The error Darwin gives for a file no file provider has, as every
    /// file here is.
    static func noFileProvider(_ url: URL?) -> id? {
        Errors.autoreleased(domain: Strings.autoreleased("NSFileProviderInternalErrorDomain"), code: 0,
                            description: "No valid file provider found from URL \(url?.absoluteString ?? "(null)").")
    }
}

@ObjCClass("NSFileVersion")
public final class NSFileVersion: NSObject {
    nonisolated(unsafe) static var versionClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        versionClass = cls.storage
    }

    private var storage: FileVersionStorage? { Storage.get(objcObject, as: FileVersionStorage.self) }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NSFileVersion.versionClass)
    }

    /// The current version of a file URL's item, autoreleased; none if
    /// there's no item.
    private static func current(_ url: NSURL?) -> id? {
        guard let url, url.url.isFileURL, access(FileManagers.path(url.url), F_OK) == 0,
              let object = Storage.allocate(UnsafeMutableRawPointer(versionClass)) else { return nil }
        Storage.set(object, FileVersionStorage(url.url))
        return ObjC.autorelease(object)
    }

    // MARK: Finding versions

    @ObjCClassMethod("currentVersionOfItemAtURL:")
    static func currentVersion(ofItemAt url: NSURL?) -> UnsafeMutableRawPointer? { current(url) }

    /// None: no versions are kept here.
    @ObjCClassMethod("otherVersionsOfItemAtURL:")
    static func otherVersions(ofItemAt url: NSURL?) -> UnsafeMutableRawPointer? { Arrays.autoreleased([]) }

    /// None: without iCloud nothing conflicts.
    @ObjCClassMethod("unresolvedConflictVersionsOfItemAtURL:")
    static func unresolvedConflictVersions(ofItemAt url: NSURL?) -> UnsafeMutableRawPointer? { Arrays.autoreleased([]) }

    /// iCloud's versions: no file provider has the file, so the handler
    /// gets Darwin's error for that, on a global queue.
    @ObjCClassMethod("getNonlocalVersionsOfItemAtURL:completionHandler:")
    static func getNonlocalVersions(ofItemAt url: NSURL?, completionHandler: ObjCObject?) {
        FileServiceCompletions.fail(completionHandler?.id, error: FileServiceCompletions.noFileProvider(url?.url), takesResult: true)
    }

    /// The one version there is, whose identifier any dictionary names,
    /// as Darwin finds a local file's.
    @ObjCClassMethod("versionOfItemAtURL:forPersistentIdentifier:")
    static func version(ofItemAt url: NSURL?, forPersistentIdentifier identifier: ObjCObject?) -> UnsafeMutableRawPointer? {
        current(url)
    }

    /// Succeeds: there are no others to remove.
    @ObjCClassMethod("removeOtherVersionsOfItemAtURL:error:")
    static func removeOtherVersions(ofItemAt url: NSURL?, error: UnsafeMutablePointer<id?>?) -> Bool { true }

    /// The Mac's version store, which Linux doesn't have: nothing is added.
    @ObjCClassMethod("addVersionOfItemAtURL:withContentsOfURL:options:error:")
    static func addVersion(ofItemAt url: NSURL?, withContentsOf contents: NSURL?, options: UInt,
                           error: UnsafeMutablePointer<id?>?) -> UnsafeMutableRawPointer? {
        error?.pointee = Errors.autoreleased(domain: Errors.cocoaDomain, code: 512, description: "The file couldn’t be saved.")
        return nil
    }

    // MARK: The version

    @ObjCMethod("URL")
    func url() -> NSURL? { URLs.wrapped(storage?.url) }

    /// The file's name.
    @ObjCMethod("localizedName")
    func localizedName() -> String? { storage.map { FileManagers.path($0.url) }.map(Paths.lastComponent) }

    /// None: the version was saved here, not on another computer.
    @ObjCMethod("localizedNameOfSavingComputer") func localizedNameOfSavingComputer() -> UnsafeMutableRawPointer? { nil }
    @ObjCMethod("originatorNameComponents") func originatorNameComponents() -> UnsafeMutableRawPointer? { nil }

    /// The file's modification date.
    @ObjCMethod("modificationDate")
    func modificationDate() -> UnsafeMutableRawPointer? {
        guard let storage else { return nil }
        var info = stat()
        guard stat(FileManagers.path(storage.url), &info) == 0 else { return nil }
        return Dates.autoreleased(Date(timeIntervalSince1970: Double(info.st_mtim.tv_sec) + Double(info.st_mtim.tv_nsec) / 1e9))
    }

    /// A current version's: an empty dictionary.
    @ObjCMethod("persistentIdentifier")
    func persistentIdentifier() -> UnsafeMutableRawPointer? { Dictionaries.autoreleased([]) }

    @ObjCMethod("isConflict") func isConflict() -> Bool { false }
    @ObjCMethod("isResolved") func isResolved() -> Bool { false }

    /// A current version is never a conflict to resolve: it stays as it is.
    @ObjCMethod("setResolved:") func setResolved(_ resolved: Bool) {}

    @ObjCMethod("isDiscardable") func isDiscardable() -> Bool { false }

    @ObjCMethod("setDiscardable:")
    func setDiscardable(_ discardable: Bool) {
        guard discardable else { return }
        Exceptions.raise(name: "NSGenericException",
                         reason: "-[NSFileVersion setDiscardable:]: You can't make the current version of a file discardable.")
    }

    @ObjCMethod("hasLocalContents") func hasLocalContents() -> Bool { true }
    @ObjCMethod("hasThumbnail") func hasThumbnail() -> Bool { false }

    /// The current version can't be put in its own place.
    @ObjCMethod("replaceItemAtURL:options:error:")
    func replaceItem(at url: NSURL?, options: UInt, error: UnsafeMutablePointer<id?>?) -> UnsafeMutableRawPointer? {
        Exceptions.raise(name: "NSGenericException",
                         reason: "-[NSFileVersion replaceItemAtURL:options:error:]: You can't use it with current versions.")
    }

    /// The current version can't be removed: Darwin's error for it.
    @ObjCMethod("removeAndReturnError:")
    func remove(error: UnsafeMutablePointer<id?>?) -> Bool {
        error?.pointee = Errors.autoreleased(domain: Errors.cocoaDomain, code: 512, description: "The file couldn’t be saved.")
        return false
    }

    // MARK: Comparing

    /// Versions of the same file are the same version.
    @ObjCMethod("isEqual:")
    func isEqual(_ other: UnsafeMutableRawPointer?) -> Bool {
        guard let mine = storage, let theirs = Storage.get(other, as: FileVersionStorage.self) else { return other == objcObject }
        return FileManagers.path(mine.url) == FileManagers.path(theirs.url)
    }

    @ObjCMethod("hash")
    func hash() -> UInt { UInt(bitPattern: (storage.map { FileManagers.path($0.url) } ?? "").hashValue) }

    @ObjCMethod("description")
    func description() -> String {
        let address = "0x" + String(UInt(bitPattern: objcObject), radix: 16)
        let path = storage.map { FileManagers.path($0.url) } ?? "(null)"
        return "<NSFileVersion: \(address)> type:Local forURL:'\(path)' contentsURL:'\(path)' name:'(null)'"
    }
}

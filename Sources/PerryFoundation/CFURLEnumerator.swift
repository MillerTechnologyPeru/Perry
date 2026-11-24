import CPerryFoundation
import FoundationEssentials
import Glibc
import PerryObjCInterop

// CFURLEnumerator: a directory's contents, the directory's own or all of
// its descendants', or the mounted volumes, one URL at a time. As on
// Darwin, symbolic links are returned but not followed, directories come
// before their contents unless only post-order is asked for, and the URL
// and error a call returns belong to the enumerator until its next call.
// The property keys to prefetch are taken and not needed: properties are
// read when they are asked for.

/// CFURLEnumeratorOptions.
enum URLEnumeratorOptions {
    static let descendRecursively: UInt = 1, skipInvisibles: UInt = 2, generateFileReferenceURLs: UInt = 4
    static let skipPackageContents: UInt = 8, includeDirectoriesPreOrder: UInt = 16, includeDirectoriesPostOrder: UInt = 32
    static let generateRelativePathURLs: UInt = 64
}

/// CFURLEnumeratorResult.
enum URLEnumeratorResults {
    static let success = 1, end = 2, error = 3, directoryPostOrderSuccess = 4
}

final class URLEnumeratorStorage {
    /// A directory being listed.
    struct Frame {
        let path: String
        /// The path from the enumerated directory, for relative URLs.
        let relative: String
        let names: [String]
        var index = 0
        /// The level of the directory's contents.
        let level: Int
        /// The directory's URL, to return after its contents in post-order.
        let url: URL?
    }

    let options: UInt
    let root: URL?
    var stack: [Frame] = []
    /// The volumes left to give, for a volume enumerator.
    var volumes: [URL]?
    /// The directory just returned, which the next call descends into.
    var pending: (path: String, relative: String, url: URL, level: Int)?
    var level = 0
    var started = false
    /// The URL and error last returned, retained until the next call.
    var currentURL: id?
    var currentError: id?

    init(root: URL?, options: UInt, volumes: [URL]?) {
        self.root = root
        self.options = options
        self.volumes = volumes
    }

    deinit {
        ObjC.release(currentURL)
        ObjC.release(currentError)
    }

    func has(_ option: UInt) -> Bool { options & option != 0 }

    /// Pre-order unless only post-order is asked for.
    var preOrder: Bool {
        has(URLEnumeratorOptions.includeDirectoriesPreOrder) || !has(URLEnumeratorOptions.includeDirectoriesPostOrder)
    }

    /// A directory's entries' names, sorted; errno when it can't be read.
    static func names(_ path: String) -> (names: [String]?, code: Int32) {
        guard let directory = opendir(path) else { return (nil, errno) }
        defer { closedir(directory) }
        var names: [String] = []
        while let entry = readdir(directory) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
            }
            if name != "." && name != ".." { names.append(name) }
        }
        return (names.sorted(), 0)
    }

    func makeURL(path: String, relative: String, isDirectory: Bool) -> URL {
        let hint: URL.DirectoryHint = isDirectory ? .isDirectory : .notDirectory
        if has(URLEnumeratorOptions.generateRelativePathURLs), let root {
            return URL(filePath: relative, directoryHint: hint, relativeTo: root)
        }
        return URL(filePath: path, directoryHint: hint)
    }

    /// Opens a directory to list, at a level, or fails with an error (+0).
    func push(path: String, relative: String, level: Int, url: URL?) -> id? {
        let listed = URLEnumeratorStorage.names(path)
        guard let names = listed.names else {
            return ObjC.autorelease(URLFileErrors.posix(listed.code, URL(filePath: path, directoryHint: .isDirectory)))
        }
        stack.append(Frame(path: path, relative: relative, names: names, level: level, url: url))
        return nil
    }

    /// The next result, its URL and its error, each +0.
    func next() -> (result: Int, url: URL?, error: id?) {
        if let volumes {
            guard let first = volumes.first else { return (URLEnumeratorResults.end, nil, nil) }
            self.volumes = Array(volumes.dropFirst())
            level = 1
            return (URLEnumeratorResults.success, first, nil)
        }
        if !started {
            started = true
            guard let root else { return (URLEnumeratorResults.end, nil, nil) }
            var path = root.path(percentEncoded: false)
            if path.count > 1, path.hasSuffix("/") { path.removeLast() }
            if let error = push(path: path, relative: "", level: 1, url: nil) { return (URLEnumeratorResults.error, nil, error) }
        }
        if let directory = pending {
            pending = nil
            let post = has(URLEnumeratorOptions.includeDirectoriesPostOrder) ? directory.url : nil
            if let error = push(path: directory.path, relative: directory.relative, level: directory.level + 1, url: post) {
                level = directory.level
                return (URLEnumeratorResults.error, nil, error)
            }
        }
        while var frame = stack.popLast() {
            guard frame.index < frame.names.count else {
                // The directory is done: post-order gives it now.
                if let url = frame.url {
                    level = frame.level - 1
                    return (URLEnumeratorResults.directoryPostOrderSuccess, url, nil)
                }
                continue
            }
            let name = frame.names[frame.index]
            frame.index += 1
            stack.append(frame)
            if has(URLEnumeratorOptions.skipInvisibles), name.hasPrefix(".") { continue }
            let path = Paths.appending(frame.path, name)
            let relative = frame.relative.isEmpty ? name : frame.relative + "/" + name
            var info = stat()
            let isDirectory = lstat(path, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR
            let url = makeURL(path: path, relative: relative, isDirectory: isDirectory)
            let descends = isDirectory && has(URLEnumeratorOptions.descendRecursively)
                && !(has(URLEnumeratorOptions.skipPackageContents) && URLResourceProperties.isPackage(path))
            if descends && !preOrder {
                // Post-order only: the directory comes after its contents.
                if let error = push(path: path, relative: relative, level: frame.level + 1, url: url) {
                    level = frame.level
                    return (URLEnumeratorResults.error, nil, error)
                }
                continue
            }
            if descends { pending = (path, relative, url, frame.level) }
            level = frame.level
            return (URLEnumeratorResults.success, url, nil)
        }
        return (URLEnumeratorResults.end, nil, nil)
    }
}

enum URLEnumerators {
    nonisolated(unsafe) static var enumeratorClass: Class!
    static let typeID: UInt = 72

    static func storage(_ object: id?) -> URLEnumeratorStorage? { Storage.get(object, as: URLEnumeratorStorage.self) }

    /// A new enumerator (+1).
    static func make(_ storage: URLEnumeratorStorage) -> id? {
        guard let object = Storage.allocate(UnsafeMutableRawPointer(enumeratorClass)) else { return nil }
        Storage.set(object, storage)
        return object
    }
}

@ObjCClass("__NSCFURLEnumerator")
final class NSCFURLEnumerator: NSObject {
    override class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        URLEnumerators.enumeratorClass = cls.storage
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: URLEnumerators.enumeratorClass)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { URLEnumerators.typeID }
}

@c(_CFURLEnumeratorGetTypeID) public func CFURLEnumeratorGetTypeID() -> UInt { URLEnumerators.typeID }

/// An enumerator of a directory's contents, +1; with
/// kCFURLEnumeratorDescendRecursively, of its descendants' too. NULL for
/// a URL that isn't a file's.
@c(_CFURLEnumeratorCreateForDirectoryURL)
public func CFURLEnumeratorCreateForDirectoryURL(_ allocator: UnsafeRawPointer?, _ directoryURL: id?, _ options: UInt,
                                                 _ propertyKeys: id?) -> id? {
    guard let url = CFURLs.url(directoryURL), url.isFileURL else { return nil }
    var path = url.path(percentEncoded: false)
    if path.count > 1, path.hasSuffix("/") { path.removeLast() }
    let root = URL(filePath: path, directoryHint: .isDirectory)
    return URLEnumerators.make(URLEnumeratorStorage(root: root, options: options, volumes: nil))
}

/// An enumerator of the mounted volumes, +1: the root, then the file
/// systems on devices that the mount table lists.
@c(_CFURLEnumeratorCreateForMountedVolumes)
public func CFURLEnumeratorCreateForMountedVolumes(_ allocator: UnsafeRawPointer?, _ options: UInt, _ propertyKeys: id?) -> id? {
    let volumes = FileVolume.browsable().map(\.url)
    return URLEnumerators.make(URLEnumeratorStorage(root: nil, options: options, volumes: volumes))
}

/// The next URL: kCFURLEnumeratorSuccess, kCFURLEnumeratorEnd,
/// kCFURLEnumeratorError for a directory that can't be read, with the
/// error, or kCFURLEnumeratorDirectoryPostOrderSuccess for a directory
/// after its contents. The URL and error are the enumerator's: valid
/// until the next call or the enumerator's release.
@c(_CFURLEnumeratorGetNextURL)
public func CFURLEnumeratorGetNextURL(_ enumerator: id?, _ url: UnsafeMutablePointer<id?>?, _ error: UnsafeMutablePointer<id?>?) -> Int {
    url?.pointee = nil
    error?.pointee = nil
    guard let storage = URLEnumerators.storage(enumerator) else { return URLEnumeratorResults.end }
    ObjC.release(storage.currentURL)
    ObjC.release(storage.currentError)
    storage.currentURL = nil
    storage.currentError = nil
    let (result, next, failure) = storage.next()
    storage.currentURL = next.flatMap { CFURLs.make($0) }
    storage.currentError = ObjC.retain(failure)
    url?.pointee = storage.currentURL
    error?.pointee = storage.currentError
    return result
}

/// Doesn't descend into the directory last returned.
@c(_CFURLEnumeratorSkipDescendents)
public func CFURLEnumeratorSkipDescendents(_ enumerator: id?) {
    URLEnumerators.storage(enumerator)?.pending = nil
}

/// The level of the URL last returned: 1 for the directory's own contents.
@c(_CFURLEnumeratorGetDescendentLevel)
public func CFURLEnumeratorGetDescendentLevel(_ enumerator: id?) -> Int { URLEnumerators.storage(enumerator)?.level ?? 0 }

/// Never: changes to the directory aren't watched, as on Darwin since 10.7.
@c(_CFURLEnumeratorGetSourceDidChange)
public func CFURLEnumeratorGetSourceDidChange(_ enumerator: id?) -> Bool { false }

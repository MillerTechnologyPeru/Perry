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

    static func install(superclass: Class) {
        urlClass = NSURL.defineObjCClass(StorageAllocated.registerObjCMethods).storage
    }

    /// A new NSURL wrapped for returning, +0; nil for no URL.
    static func wrapped(_ url: URL?, cls: ObjCClass? = nil) -> NSURL? {
        autoreleased(url, cls: cls?.pointer).map { NSURL(objCReturnValue: $0) }
    }
}

/// NSURL.
@ObjCClass("NSURL")
public final class NSURL: NSObject {
    /// Every NSURL has a URL once initialized.
    var url: URL { URLs.url(objcObject) ?? URL(filePath: "/") }

    private func setURL(_ url: URL?) -> Self? {
        guard let url else { return nil }
        Storage.set(objcObject, URLStorage(url))
        return self
    }

    // MARK: Creating

    @ObjCClassMethod("URLWithString:")
    static func url(_ cls: ObjCClass, string: String) -> NSURL? { URLs.wrapped(URL(string: string), cls: cls) }

    @ObjCClassMethod("URLWithString:relativeToURL:")
    static func url(_ cls: ObjCClass, string: String, relativeTo base: NSURL?) -> NSURL? {
        URLs.wrapped(URL(string: string, relativeTo: base?.url), cls: cls)
    }

    @ObjCClassMethod("fileURLWithPath:")
    static func fileURL(_ cls: ObjCClass, path: String) -> NSURL? {
        URLs.wrapped(URLs.fileURL(path, isDirectory: nil), cls: cls)
    }

    @ObjCClassMethod("fileURLWithPath:isDirectory:")
    static func fileURL(_ cls: ObjCClass, path: String, isDirectory: Bool) -> NSURL? {
        URLs.wrapped(URLs.fileURL(path, isDirectory: isDirectory), cls: cls)
    }

    @ObjCMethod("initWithString:")
    func initialize(string: String) -> Self? { setURL(URL(string: string)) }

    @ObjCMethod("initWithString:relativeToURL:")
    func initialize(string: String, relativeTo base: NSURL?) -> Self? { setURL(URL(string: string, relativeTo: base?.url)) }

    @ObjCMethod("initFileURLWithPath:")
    func initialize(filePath path: String) -> Self? { setURL(URLs.fileURL(path, isDirectory: nil)) }

    @ObjCMethod("initFileURLWithPath:isDirectory:")
    func initialize(filePath path: String, isDirectory: Bool) -> Self? {
        setURL(URLs.fileURL(path, isDirectory: isDirectory))
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: URLs.urlClass)
    }

    // MARK: Components

    @ObjCMethod("absoluteString") func absoluteString() -> String { url.absoluteString }
    @ObjCMethod("relativeString") func relativeString() -> String { url.relativeString }
    @ObjCMethod("absoluteURL") func absoluteURL() -> NSURL? { URLs.wrapped(url.absoluteURL) }
    @ObjCMethod("baseURL") func baseURL() -> NSURL? { URLs.wrapped(url.baseURL) }
    @ObjCMethod("scheme") func scheme() -> String? { url.scheme }
    @ObjCMethod("host") func host() -> String? { url.host(percentEncoded: false) }
    @ObjCMethod("port") func port() -> NSNumber? { url.port.map { Numbers.wrapped(ObjCClass(UnsafeMutableRawPointer(Numbers.numberClass)), .signed(Int64($0))) } }
    @ObjCMethod("user") func user() -> String? { url.user(percentEncoded: false) }
    @ObjCMethod("password") func password() -> String? { url.password(percentEncoded: false) }

    /// Decoded, with no trailing slash, as NSURL's path is.
    @ObjCMethod("path")
    func path() -> String {
        var path = url.path(percentEncoded: false)
        if path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }

    @ObjCMethod("query") func query() -> String? { url.query(percentEncoded: true) }
    @ObjCMethod("fragment") func fragment() -> String? { url.fragment(percentEncoded: true) }
    @ObjCMethod("lastPathComponent") func lastPathComponent() -> String { url.lastPathComponent }
    @ObjCMethod("pathExtension") func pathExtension() -> String { url.pathExtension }
    @ObjCMethod("pathComponents") func pathComponents() -> NSArray { Arrays.owned(url.pathComponents.map { Strings.autoreleased($0) }) }
    @ObjCMethod("isFileURL") func isFileURL() -> Bool { url.isFileURL }
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

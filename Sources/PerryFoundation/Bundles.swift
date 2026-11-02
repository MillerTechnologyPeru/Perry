import CPerryFoundation
import FoundationEssentials
import Glibc
import PerryObjCInterop

/// A bundle on disk. iOS bundles keep Info.plist, the executable and
/// resources at the top level; macOS bundles keep them under Contents.
final class BundleStorage {
    let path: String
    let contentsPath: String
    let resourcePath: String
    let info: [String: PropertyValue]
    /// The Info.plist as an NSDictionary, built once so it keeps its identity.
    private(set) lazy var infoDictionary: id = {
        let dictionary = PropertyValue.dictionary(info).object() ?? Dictionaries.autoreleased([])
        return ObjC.retain(dictionary)!
    }()

    init(path: String) {
        self.path = Paths.normalized(path)
        let macOS = FileManager.default.fileExists(atPath: self.path + "/Contents/Info.plist")
        contentsPath = macOS ? self.path + "/Contents" : self.path
        resourcePath = macOS ? contentsPath + "/Resources" : self.path
        let plist = (try? Data(contentsOf: URL(filePath: contentsPath + "/Info.plist")))
            .flatMap { try? PropertyListDecoder().decode(PropertyValue.self, from: $0) }
        if case .dictionary(let values) = plist {
            info = values
        } else {
            info = [:]
        }
        isMacOSLayout = macOS
    }

    let isMacOSLayout: Bool

    var identifier: String? {
        if case .string(let value) = info["CFBundleIdentifier"] { return value }
        return nil
    }

    var executablePath: String? {
        guard case .string(let name) = info["CFBundleExecutable"] else { return nil }
        return (isMacOSLayout ? contentsPath + "/MacOS/" : path + "/") + name
    }

    /// pathForResource:ofType:inDirectory: — the file name, with the type
    /// appended unless empty, in the resources directory or a subdirectory.
    func resource(_ name: String?, type: String?, directory: String?) -> String? {
        guard let name, !name.isEmpty else { return nil }
        var file = name
        if let type, !type.isEmpty { file += "." + type }
        var directoryPath = resourcePath
        if let directory, !directory.isEmpty { directoryPath = Paths.appending(directoryPath, directory) }
        let candidate = Paths.appending(directoryPath, file)
        return FileManager.default.fileExists(atPath: candidate) ? candidate : nil
    }

    func resources(type: String?, directory: String?) -> [String] {
        var directoryPath = resourcePath
        if let directory, !directory.isEmpty { directoryPath = Paths.appending(directoryPath, directory) }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directoryPath)) ?? []
        return names.sorted()
            .filter { type == nil || type!.isEmpty || Paths.pathExtension($0) == type }
            .map { Paths.appending(directoryPath, $0) }
    }
}

enum Bundles {
    nonisolated(unsafe) static var bundleClass: Class!
    nonisolated(unsafe) static var main: id!
    nonisolated(unsafe) private static var byPath: [String: id] = [:]

    static func storage(_ object: id?) -> BundleStorage? {
        Storage.get(object, as: BundleStorage.self)
    }

    /// One NSBundle per path, kept for the life of the process.
    static func bundle(path: String) -> id? {
        let key = Paths.normalized(path)
        if let existing = byPath[key] { return existing }
        var info = stat()
        guard stat(key, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              let object = Storage.allocate(UnsafeMutableRawPointer(bundleClass)) else { return nil }
        Storage.set(object, BundleStorage(path: key))
        byPath[key] = object
        return object
    }

    static func install(superclass: Class) {
        bundleClass = NSBundle.defineObjCClass(StorageAllocated.registerObjCMethods).storage
        // The app bundle, or the executable's directory for a bare executable.
        main = bundle(path: Process.bundlePath ?? Paths.deletingLastComponent(Process.executablePath))
    }
}

/// NSBundle.
@ObjCClass("NSBundle")
public final class NSBundle: NSObject {
    private var storage: BundleStorage {
        guard let storage = Bundles.storage(objcObject) else { foundationFatal("message sent to an uninitialized NSBundle") }
        return storage
    }

    @ObjCClassMethod("mainBundle")
    static func mainBundle() -> UnsafeMutableRawPointer? { Bundles.main }

    @ObjCClassMethod("bundleWithPath:")
    static func bundle(path: String) -> UnsafeMutableRawPointer? { Bundles.bundle(path: path) }

    @ObjCClassMethod("bundleWithURL:")
    static func bundle(url: NSURL) -> UnsafeMutableRawPointer? { Bundles.bundle(path: url.url.path(percentEncoded: false)) }

    @ObjCClassMethod("bundleWithIdentifier:")
    static func bundle(identifier: String) -> UnsafeMutableRawPointer? {
        Bundles.storage(Bundles.main)?.identifier == identifier ? Bundles.main : nil
    }

    // Bundles live for the whole process.
    @ObjCMethod("retain") func retain() -> UnsafeMutableRawPointer { objcObject }
    @ObjCMethod("release", types: "Vv16@0:8") func release() {}
    @ObjCMethod("autorelease") func autorelease() -> UnsafeMutableRawPointer { objcObject }

    @ObjCMethod("bundlePath") func bundlePath() -> String { storage.path }
    @ObjCMethod("bundleURL") func bundleURL() -> NSURL? { URLs.wrapped(URL(filePath: storage.path, directoryHint: .isDirectory)) }
    @ObjCMethod("resourcePath") func resourcePath() -> String { storage.resourcePath }
    @ObjCMethod("resourceURL") func resourceURL() -> NSURL? { URLs.wrapped(URL(filePath: storage.resourcePath, directoryHint: .isDirectory)) }
    @ObjCMethod("executablePath") func executablePath() -> String? { storage.executablePath }
    @ObjCMethod("executableURL") func executableURL() -> NSURL? { URLs.wrapped(storage.executablePath.map { URL(filePath: $0) }) }
    @ObjCMethod("bundleIdentifier") func bundleIdentifier() -> String? { storage.identifier }
    @ObjCMethod("isLoaded") func isLoaded() -> Bool { true }
    @ObjCMethod("load") func load() -> Bool { true }

    @ObjCMethod("infoDictionary")
    func infoDictionary() -> NSDictionary { NSDictionary(objCArgument: storage.infoDictionary) }

    @ObjCMethod("objectForInfoDictionaryKey:")
    func object(forInfoDictionaryKey key: ObjCObject) -> ObjCObject? {
        Dictionaries.value(storage.infoDictionary, for: key.id).map(ObjCObject.init)
    }

    @ObjCMethod("developmentLocalization")
    func developmentLocalization() -> String? {
        if case .string(let value) = storage.info["CFBundleDevelopmentRegion"] { return value }
        return "en"
    }

    // MARK: Resources

    @ObjCMethod("pathForResource:ofType:")
    func path(forResource name: String?, ofType type: String?) -> String? {
        storage.resource(name, type: type, directory: nil)
    }

    @ObjCMethod("pathForResource:ofType:inDirectory:")
    func path(forResource name: String?, ofType type: String?, inDirectory directory: String?) -> String? {
        storage.resource(name, type: type, directory: directory)
    }

    @ObjCMethod("URLForResource:withExtension:")
    func url(forResource name: String?, withExtension type: String?) -> NSURL? {
        URLs.wrapped(storage.resource(name, type: type, directory: nil).map { URL(filePath: $0) })
    }

    @ObjCMethod("URLForResource:withExtension:subdirectory:")
    func url(forResource name: String?, withExtension type: String?, subdirectory: String?) -> NSURL? {
        URLs.wrapped(storage.resource(name, type: type, directory: subdirectory).map { URL(filePath: $0) })
    }

    @ObjCMethod("pathsForResourcesOfType:inDirectory:")
    func paths(forResourcesOfType type: String?, inDirectory directory: String?) -> NSArray {
        Arrays.owned(storage.resources(type: type, directory: directory).map { Strings.autoreleased($0) })
    }

    /// Strings files are not read yet: returns `value`, or the key.
    @ObjCMethod("localizedStringForKey:value:table:")
    func localizedString(forKey key: String, value: String?, table: String?) -> String {
        guard let value, !value.isEmpty else { return key }
        return value
    }
}

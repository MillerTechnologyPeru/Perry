import CPerryFoundation
import FoundationEssentials
import Glibc
import PerryObjCInterop

/// A defaults domain: values the app set, kept in a property list at
/// ~/Library/Preferences/<suite>.plist as on Darwin, over registered
/// defaults that are never saved.
final class UserDefaultsStorage {
    let suite: String
    private var values: [String: PropertyValue] = [:]
    private var registered: [String: PropertyValue] = [:]

    init(suite: String) {
        self.suite = suite
        if let data = try? Data(contentsOf: url),
           case .dictionary(let stored)? = try? PropertyListDecoder().decode(PropertyValue.self, from: data) {
            values = stored
        }
    }

    private var url: URL {
        let home = getenv("HOME").map { String(cString: $0) } ?? "/tmp"
        return URL(filePath: home + "/Library/Preferences/" + suite + ".plist")
    }

    func value(_ key: String) -> PropertyValue? { values[key] ?? registered[key] ?? Self.global[key] }

    /// NSGlobalDomain's values that apps read as iOS always has them: the
    /// languages, most preferred first, and the locale.
    nonisolated(unsafe) static let global: [String: PropertyValue] = {
        let languages = Locale.preferredLanguages.isEmpty ? ["en"] : Locale.preferredLanguages
        return [
            "AppleLanguages": .array(languages.map { .string($0) }),
            "AppleLocale": .string(Locale.current.identifier.isEmpty ? "en_US" : Locale.current.identifier),
        ]
    }()

    func set(_ value: PropertyValue?, for key: String) {
        values[key] = value
        save()
    }

    /// Forgets every value set, as removing the domain does.
    func removeAll() {
        values = [:]
        save()
    }

    /// The values set, without the registered defaults: the domain as it
    /// is kept.
    var persistent: [String: PropertyValue] { values }

    /// Replaces every value set, as setting the domain does.
    func replace(_ domain: [String: PropertyValue]) {
        values = domain
        save()
    }

    func register(_ defaults: [String: PropertyValue]) {
        registered.merge(defaults) { _, new in new }
    }

    var all: [String: PropertyValue] { Self.global.merging(registered) { _, new in new }.merging(values) { _, set in set } }

    @discardableResult
    func save() -> Bool {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(PropertyValue.dictionary(values)) else { return false }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}

enum UserDefaults {
    nonisolated(unsafe) static var defaultsClass: Class!
    nonisolated(unsafe) static var standard: id?

    static func storage(_ object: id?) -> UserDefaultsStorage? {
        Storage.get(object, as: UserDefaultsStorage.self)
    }

}

/// NSUserDefaults.
@ObjCClass("NSUserDefaults")
final class NSUserDefaults: NSObject {
    /// Set-up after the class is defined.
    override class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        UserDefaults.defaultsClass = cls.storage
    }

    private var storage: UserDefaultsStorage {
        guard let storage = UserDefaults.storage(objcObject) else {
            foundationFatal("message sent to an uninitialized NSUserDefaults")
        }
        return storage
    }

    /// The app's domain, named by its bundle identifier.
    @ObjCClassMethod("standardUserDefaults")
    static func standard() -> UnsafeMutableRawPointer? {
        if let standard = UserDefaults.standard { return standard }
        let suite = Bundles.storage(Bundles.main)?.identifier ?? Process.name
        let object = Storage.allocate(UnsafeMutableRawPointer(UserDefaults.defaultsClass))
        if let object { Storage.set(object, UserDefaultsStorage(suite: suite)) }
        UserDefaults.standard = object
        return object
    }

    @ObjCClassMethod("resetStandardUserDefaults")
    static func resetStandard() {}

    @ObjCMethod("init")
    func initialize() -> Self {
        Storage.set(objcObject, UserDefaultsStorage(suite: Bundles.storage(Bundles.main)?.identifier ?? Process.name))
        return self
    }

    @ObjCMethod("initWithSuiteName:")
    func initialize(suiteName: String?) -> Self {
        Storage.set(objcObject, UserDefaultsStorage(suite: suiteName ?? Bundles.storage(Bundles.main)?.identifier ?? Process.name))
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: UserDefaults.defaultsClass)
    }

    // MARK: Reading

    @ObjCMethod("objectForKey:")
    func object(forKey key: String) -> ObjCObject? {
        storage.value(key)?.object().map { ObjCObject($0) }
    }

    /// Key-value coding reads and writes defaults, as Foundation's does.
    @ObjCMethod("valueForKey:")
    func value(forKey key: String) -> ObjCObject? { object(forKey: key) }

    @ObjCMethod("stringForKey:")
    func string(forKey key: String) -> String? {
        switch storage.value(key) {
        case .string(let value): return value
        case .integer(let value): return String(value)
        case .double(let value): return NumberStorage(.double(value)).description
        default: return nil
        }
    }

    /// Numbers, Booleans and numeric strings convert, as in Foundation.
    @ObjCMethod("integerForKey:")
    func integer(forKey key: String) -> Int {
        switch storage.value(key) {
        case .integer(let value): return Int(value)
        case .double(let value): return Int(value)
        case .bool(let value): return value ? 1 : 0
        case .string(let value): return Strings.integerPrefix(value)
        default: return 0
        }
    }

    @ObjCMethod("doubleForKey:")
    func double(forKey key: String) -> Double {
        switch storage.value(key) {
        case .integer(let value): return Double(value)
        case .double(let value): return value
        case .bool(let value): return value ? 1 : 0
        case .string(let value): return value.withCString { strtod($0, nil) }
        default: return 0
        }
    }

    @ObjCMethod("floatForKey:")
    func float(forKey key: String) -> Float { Float(double(forKey: key)) }

    @ObjCMethod("boolForKey:")
    func bool(forKey key: String) -> Bool {
        switch storage.value(key) {
        case .bool(let value): return value
        case .integer(let value): return value != 0
        case .double(let value): return value != 0
        case .string(let value): return ["yes", "true", "1"].contains(value.lowercased())
        default: return false
        }
    }

    @ObjCMethod("arrayForKey:")
    func array(forKey key: String) -> ObjCObject? {
        guard case .array? = storage.value(key) else { return nil }
        return object(forKey: key)
    }

    /// The array, when every element is a string.
    @ObjCMethod("stringArrayForKey:")
    func stringArray(forKey key: String) -> ObjCObject? {
        guard case .array(let values)? = storage.value(key),
              values.allSatisfy({ if case .string = $0 { return true } else { return false } }) else { return nil }
        return object(forKey: key)
    }

    /// A URL stored as its string (an absolute URL, or a path for a file).
    @ObjCMethod("URLForKey:")
    func url(forKey key: String) -> ObjCObject? {
        guard case .string(let text)? = storage.value(key) else { return nil }
        let url = text.hasPrefix("/") ? URL(filePath: text) : URL(string: text)
        return URLs.wrapped(url).map { ObjCObject($0.objcObject) }
    }

    @ObjCMethod("setURL:forKey:")
    func set(url: NSURL?, forKey key: String) {
        guard let url else { storage.set(nil, for: key); return }
        storage.set(.string(url.url.absoluteString), for: key)
    }

    @ObjCMethod("dictionaryForKey:")
    func dictionary(forKey key: String) -> ObjCObject? {
        guard case .dictionary? = storage.value(key) else { return nil }
        return object(forKey: key)
    }

    @ObjCMethod("dataForKey:")
    func data(forKey key: String) -> ObjCObject? {
        guard case .data? = storage.value(key) else { return nil }
        return object(forKey: key)
    }

    @ObjCMethod("dictionaryRepresentation")
    func dictionaryRepresentation() -> ObjCObject? {
        PropertyValue.dictionary(storage.all).object().map { ObjCObject($0) }
    }

    // MARK: Writing

    /// Only property list values can be stored.
    @ObjCMethod("setObject:forKey:")
    func set(_ value: ObjCObject?, forKey key: String) {
        guard let value else {
            storage.set(nil, for: key)
            return
        }
        guard let converted = PropertyValue(object: value.id) else {
            foundationFatal("Attempt to insert non-property list object \(Format.describe(value.id)) for key \(key)")
        }
        storage.set(converted, for: key)
    }

    @ObjCMethod("setValue:forKey:")
    func setValue(_ value: ObjCObject?, forKey key: String) { set(value, forKey: key) }

    @ObjCMethod("setInteger:forKey:")
    func set(integer: Int, forKey key: String) { storage.set(.integer(Int64(integer)), for: key) }

    @ObjCMethod("setDouble:forKey:")
    func set(double: Double, forKey key: String) { storage.set(.double(double), for: key) }

    @ObjCMethod("setFloat:forKey:")
    func set(float: Float, forKey key: String) { storage.set(.double(Double(float)), for: key) }

    @ObjCMethod("setBool:forKey:")
    func set(bool: Bool, forKey key: String) { storage.set(.bool(bool), for: key) }

    @ObjCMethod("removeObjectForKey:")
    func remove(forKey key: String) { storage.set(nil, for: key) }

    /// A domain's values as they are kept: the app's own, or another
    /// suite's of this app; nil for a domain with nothing set.
    @ObjCMethod("persistentDomainForName:")
    func persistentDomain(forName name: String?) -> ObjCObject? {
        guard let name else { return nil }
        let domain = name == storage.suite ? storage.persistent : UserDefaultsStorage(suite: name).persistent
        guard !domain.isEmpty else { return nil }
        return PropertyValue.dictionary(domain).object().map { ObjCObject($0) }
    }

    @ObjCMethod("setPersistentDomain:forName:")
    func setPersistentDomain(_ domain: ObjCObject?, forName name: String?) {
        guard let name, let domain, case .dictionary(let values)? = PropertyValue(object: domain.id) else { return }
        if name == storage.suite { storage.replace(values) } else { UserDefaultsStorage(suite: name).replace(values) }
    }

    /// The app's own domain only: other apps' domains aren't kept here.
    @ObjCMethod("removePersistentDomainForName:")
    func removePersistentDomain(forName name: String) {
        if name == storage.suite { storage.removeAll() }
    }

    @ObjCMethod("registerDefaults:")
    func register(_ defaults: ObjCObject) {
        guard case .dictionary(let values)? = PropertyValue(object: defaults.id) else { return }
        storage.register(values)
    }

    /// Values are saved as they change; this saves again.
    @ObjCMethod("synchronize")
    func synchronize() -> Bool { storage.save() }
}

@ObjCConstants
enum UserDefaultsConstants {
    static let NSUserDefaultsDidChangeNotification = "NSUserDefaultsDidChangeNotification"
}

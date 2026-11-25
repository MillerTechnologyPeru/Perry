import CPerryFoundation
import FoundationEssentials
import FoundationInternationalization
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

    /// Held around every use of the values: defaults are read and set from
    /// any thread, as NSUserDefaults allows.
    private let lock = Monitor()

    func value(_ key: String) -> PropertyValue? {
        Self.volatileLock.locked { Self.volatileDomains["NSArgumentDomain"]?[key] }
            ?? lock.locked { values[key] ?? suites.lazy.compactMap { $0.ownValue(key) }.first ?? registered[key] }
            ?? Self.globalValue(key)
    }

    /// The domain's own value, set and kept, alone.
    func ownValue(_ key: String) -> PropertyValue? { lock.locked { values[key] } }

    /// Suites -addSuiteNamed: added to the search list, searched after the
    /// domain's own values in the order added. Each is read when added.
    private var suites: [UserDefaultsStorage] = []

    func addSuite(_ name: String) {
        lock.locked { () -> Void in
            guard name != suite, !suites.contains(where: { $0.suite == name }) else { return }
            suites.append(UserDefaultsStorage(suite: name))
        }
    }

    func removeSuite(_ name: String) { lock.locked { suites.removeAll { $0.suite == name } } }

    /// The names of the domains kept on disk: the property lists in
    /// ~/Library/Preferences.
    static var persistentDomainNames: [String] {
        let home = getenv("HOME").map { String(cString: $0) } ?? "/tmp"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: home + "/Library/Preferences")) ?? []
        return names.filter { $0.hasSuffix(".plist") }.map { String($0.dropLast(6)) }.sorted()
    }

    /// The defaults given on the command line, each "-Key value": the
    /// argument domain, searched before every other. A value is a string.
    static func argumentDomain(_ arguments: [String]) -> [String: PropertyValue] {
        var found: [String: PropertyValue] = [:]
        var index = 1
        while index + 1 < arguments.count {
            let key = arguments[index]
            if key.hasPrefix("-"), key.count > 1, Double(key) == nil {
                found[String(key.dropFirst())] = .string(arguments[index + 1])
                index += 2
            } else {
                index += 1
            }
        }
        return found
    }

    /// NSGlobalDomain's values that apps read as iOS always has them: the
    /// languages, most preferred first, and the locale; and the locale's
    /// separators, symbols, names and formats under NeXT's keys, which Mac
    /// OS X still answers and apps of its first years read (iWork's text
    /// makes its decimal tab of NSDecimalSeparator).
    nonisolated(unsafe) static let global: [String: PropertyValue] = {
        let languages = Locale.preferredLanguages.isEmpty ? ["en"] : Locale.preferredLanguages
        let locale = Locale.current.identifier.isEmpty ? Locale(identifier: "en_US") : Locale.current
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        func strings(_ values: [String]) -> PropertyValue { .array(values.map { .string($0) }) }
        return [
            "AppleLanguages": strings(languages),
            "AppleLocale": .string(locale.identifier),
            "NSDecimalSeparator": .string(locale.decimalSeparator ?? "."),
            "NSThousandsSeparator": .string(locale.groupingSeparator ?? ","),
            "NSCurrencySymbol": .string(locale.currencySymbol ?? "$"),
            "NSDecimalDigits": strings((0...9).map(String.init)),
            "NSAMPMDesignation": strings([calendar.amSymbol, calendar.pmSymbol]),
            "NSMonthNameArray": strings(calendar.monthSymbols),
            "NSShortMonthNameArray": strings(calendar.shortMonthSymbols),
            "NSWeekDayNameArray": strings(calendar.weekdaySymbols),
            "NSShortWeekDayNameArray": strings(calendar.shortWeekdaySymbols),
            "NSDateFormatString": .string("%A, %B %e, %Y"),
            "NSShortDateFormatString": .string("%m/%d/%y"),
            "NSTimeFormatString": .string("%H:%M:%S"),
            "NSTimeDateFormatString": .string("%A, %B %e, %Y %I:%M:%S %p %Z"),
            "NSShortTimeDateFormatString": .string("%m/%d/%y %I:%M %p"),
        ]
    }()

    /// NSGlobalDomain's values the system sets as the app runs, which
    /// providers set through perry_foundation_set_global_default: AppKit's
    /// AppleInterfaceStyle, "Dark" while the desktop is dark and absent
    /// when it is light, as on macOS. Kept under volatileLock.
    nonisolated(unsafe) static var system: [String: PropertyValue] = [:]

    static func globalValue(_ key: String) -> PropertyValue? {
        volatileLock.locked { system[key] } ?? global[key]
    }

    func set(_ value: PropertyValue?, for key: String) {
        lock.locked {
            values[key] = value
            changed()
        }
    }

    /// Forgets every value set, as removing the domain does.
    func removeAll() {
        lock.locked {
            values = [:]
            changed()
        }
    }

    /// Whether values changed since they were last written.
    private var dirty = false

    /// Writes the values at each change, as macOS does: nothing waits for
    /// -synchronize or for the run loop, so a program that sets a value
    /// and exits has it kept.
    func changed() {
        lock.locked {
            dirty = true
            save()
        }
    }

    /// Writes the values if any change is still unwritten (a write that
    /// failed), as -synchronize asks for: otherwise there is nothing to do.
    @discardableResult
    func saveIfChanged() -> Bool {
        lock.locked { dirty ? save() : true }
    }

    /// The values set, without the registered defaults: the domain as it
    /// is kept.
    var persistent: [String: PropertyValue] { lock.locked { values } }

    /// Replaces every value set, as setting the domain does.
    func replace(_ domain: [String: PropertyValue]) {
        lock.locked {
            values = domain
            changed()
        }
    }

    func register(_ defaults: [String: PropertyValue]) {
        lock.locked { registered.merge(defaults) { _, new in new } }
    }

    /// The registration domain: what was registered.
    var registeredValues: [String: PropertyValue] {
        get { lock.locked { registered } }
        set { lock.locked { registered = newValue } }
    }

    /// Volatile domains other than registration, by name: kept for the
    /// session. NSArgumentDomain starts as the command line's defaults.
    nonisolated(unsafe) static var volatileDomains: [String: [String: PropertyValue]] = ["NSArgumentDomain": argumentDomain(Process.arguments)]
    static let volatileLock = Monitor()

    var all: [String: PropertyValue] {
        let arguments = Self.volatileLock.locked { Self.volatileDomains["NSArgumentDomain"] } ?? [:]
        let system = Self.volatileLock.locked { Self.system }
        return lock.locked {
            let added = suites.reversed().reduce(into: [String: PropertyValue]()) { $0.merge($1.persistent) { _, earlier in earlier } }
            return Self.global.merging(system) { _, set in set }.merging(registered) { _, new in new }
                .merging(added) { _, suite in suite }.merging(values) { _, set in set }
        }
            .merging(arguments) { _, given in given }
    }

    @discardableResult
    func save() -> Bool {
        lock.locked {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            guard let data = try? encoder.encode(PropertyValue.dictionary(values)) else { return false }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard (try? data.write(to: url, options: .atomic)) != nil else { return false }
            dirty = false
            return true
        }
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
class NSUserDefaults: NSObject {
    /// Set-up after the class is defined.
    override class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        UserDefaults.defaultsClass = cls.storage
    }

    fileprivate var storage: UserDefaultsStorage {
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

    /// Only the current user's defaults can be opened: nil for another user.
    @ObjCMethod("initWithUser:")
    func initialize(user: String?) -> Self? {
        guard let user, user == Strings.value(of: NSUserName()) else { return nil }
        return initialize()
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

    /// A volatile domain's values: NSRegistrationDomain's are what was
    /// registered; others are what was set for the session.
    @ObjCMethod("volatileDomainForName:")
    func volatileDomain(forName name: String?) -> ObjCObject? {
        guard let name else { return nil }
        let domain = name == "NSRegistrationDomain" ? storage.registeredValues
            : UserDefaultsStorage.volatileLock.locked { UserDefaultsStorage.volatileDomains[name] } ?? [:]
        return PropertyValue.dictionary(domain).object().map { ObjCObject($0) }
    }

    @ObjCMethod("setVolatileDomain:forName:")
    func setVolatileDomain(_ domain: ObjCObject?, forName name: String?) {
        guard let name, let domain, case .dictionary(let values)? = PropertyValue(object: domain.id) else { return }
        if name == "NSRegistrationDomain" {
            storage.registeredValues = values
        } else {
            UserDefaultsStorage.volatileLock.locked { UserDefaultsStorage.volatileDomains[name] = values }
        }
    }

    @ObjCMethod("removeVolatileDomainForName:")
    func removeVolatileDomain(forName name: String?) {
        guard let name else { return }
        if name == "NSRegistrationDomain" {
            storage.registeredValues = [:]
        } else {
            UserDefaultsStorage.volatileLock.locked { _ = UserDefaultsStorage.volatileDomains.removeValue(forKey: name) }
        }
    }

    @ObjCMethod("volatileDomainNames")
    func volatileDomainNames() -> ObjCObject? {
        let names = ["NSRegistrationDomain"] + UserDefaultsStorage.volatileLock.locked { Array(UserDefaultsStorage.volatileDomains.keys) }
        return PropertyValue.array(names.map { .string($0) }).object().map { ObjCObject($0) }
    }

    /// Searches another suite's values after the domain's own; NSGlobalDomain
    /// and the domain itself are searched already.
    @ObjCMethod("addSuiteNamed:")
    func addSuite(named name: String?) {
        guard let name, name != "NSGlobalDomain" else { return }
        storage.addSuite(name)
    }

    @ObjCMethod("removeSuiteNamed:")
    func removeSuite(named name: String?) { if let name { storage.removeSuite(name) } }

    /// No value is forced here: there are no managed preferences (a device
    /// management profile's) to force one.
    @ObjCMethod("objectIsForcedForKey:") func objectIsForced(forKey key: String?) -> Bool { false }
    @ObjCMethod("objectIsForcedForKey:inDomain:")
    func objectIsForced(forKey key: String?, inDomain domain: String?) -> Bool { false }

    /// The domains kept on disk, by name.
    @ObjCMethod("persistentDomainNames")
    func persistentDomainNames() -> ObjCObject? {
        PropertyValue.array(UserDefaultsStorage.persistentDomainNames.map { .string($0) }).object().map { ObjCObject($0) }
    }

    @ObjCMethod("registerDefaults:")
    func register(_ defaults: ObjCObject?) {
        // Nil, as from a plist that isn't there, registers nothing.
        guard let defaults, case .dictionary(let values)? = PropertyValue(object: defaults.id) else { return }
        storage.register(values)
    }

    /// Values are written soon after they change; this writes any not yet
    /// written, unless they were written within the last second.
    @ObjCMethod("synchronize")
    func synchronize() -> Bool { storage.saveIfChanged() }
}

/// iCloud's key-value store, with no iCloud: an NSObject, as on Darwin,
/// whose values are kept on the device, in a defaults domain of their own
/// beside the app's (<bundle identifier>.ubiquitous), as Darwin keeps them
/// while no account is signed in; nothing ever changes from elsewhere, so
/// NSUbiquitousKeyValueStoreDidChangeExternallyNotification never comes.
/// (Darwin keeps nothing at all for a program without the iCloud
/// entitlement: its getters answer nil and 0, and -synchronize NO.)
@ObjCClass("NSUbiquitousKeyValueStore")
final class NSUbiquitousKeyValueStore: NSObject {
    nonisolated(unsafe) private static var shared: UnsafeMutableRawPointer?
    nonisolated(unsafe) private static var storeClass: Class!

    override class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        storeClass = cls.storage
    }

    private static var suite: String { (Bundles.storage(Bundles.main)?.identifier ?? Process.name) + ".ubiquitous" }

    private var storage: UserDefaultsStorage {
        if let storage = UserDefaults.storage(objcObject) { return storage }
        let storage = UserDefaultsStorage(suite: Self.suite)
        Storage.set(objcObject, storage)
        return storage
    }

    @ObjCClassMethod("defaultStore")
    static func defaultStore(_ cls: ObjCClass) -> UnsafeMutableRawPointer? {
        if let shared { return shared }
        let object = Storage.allocate(cls.pointer)
        if let object { Storage.set(object, UserDefaultsStorage(suite: suite)) }
        shared = object
        return object
    }

    /// Another store over the same values, as Darwin's instances share them.
    @ObjCMethod("init")
    func initialize() -> Self {
        _ = storage
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Self.storeClass)
    }

    // MARK: Reading

    @ObjCMethod("objectForKey:")
    func object(forKey key: String?) -> ObjCObject? {
        key.flatMap { storage.ownValue($0) }?.object().map { ObjCObject($0) }
    }

    /// Each typed getter answers only for a value of its type.
    @ObjCMethod("stringForKey:")
    func string(forKey key: String?) -> ObjCObject? {
        guard let key, case .string? = storage.ownValue(key) else { return nil }
        return object(forKey: key)
    }

    @ObjCMethod("arrayForKey:")
    func array(forKey key: String?) -> ObjCObject? {
        guard let key, case .array? = storage.ownValue(key) else { return nil }
        return object(forKey: key)
    }

    @ObjCMethod("dictionaryForKey:")
    func dictionary(forKey key: String?) -> ObjCObject? {
        guard let key, case .dictionary? = storage.ownValue(key) else { return nil }
        return object(forKey: key)
    }

    @ObjCMethod("dataForKey:")
    func data(forKey key: String?) -> ObjCObject? {
        guard let key, case .data? = storage.ownValue(key) else { return nil }
        return object(forKey: key)
    }

    /// Numbers, as their values; 0 for anything else.
    @ObjCMethod("longLongForKey:")
    func longLong(forKey key: String?) -> Int64 {
        switch key.flatMap({ storage.ownValue($0) }) {
        case .integer(let value)?: return value
        case .double(let value)?: return Int64(exactly: value.rounded(.towardZero)) ?? 0
        case .bool(let value)?: return value ? 1 : 0
        default: return 0
        }
    }

    @ObjCMethod("doubleForKey:")
    func double(forKey key: String?) -> Double {
        switch key.flatMap({ storage.ownValue($0) }) {
        case .integer(let value)?: return Double(value)
        case .double(let value)?: return value
        case .bool(let value)?: return value ? 1 : 0
        default: return 0
        }
    }

    @ObjCMethod("boolForKey:")
    func bool(forKey key: String?) -> Bool {
        switch key.flatMap({ storage.ownValue($0) }) {
        case .integer(let value)?: return value != 0
        case .double(let value)?: return value != 0
        case .bool(let value)?: return value
        default: return false
        }
    }

    /// The values set, by key.
    @ObjCMethod("dictionaryRepresentation")
    func dictionaryRepresentation() -> ObjCObject? {
        PropertyValue.dictionary(storage.persistent).object().map { ObjCObject($0) }
    }

    // MARK: Writing

    /// Property list values only; nil removes the value.
    @ObjCMethod("setObject:forKey:")
    func set(_ value: ObjCObject?, forKey key: String?) {
        guard let key else { return }
        guard let value else { return storage.set(nil, for: key) }
        guard let converted = PropertyValue(object: value.id) else {
            return foundationWarning("NSUbiquitousKeyValueStore: \(Format.describe(value.id)) for key \(key) is not a property list value")
        }
        storage.set(converted, for: key)
    }

    @ObjCMethod("setString:forKey:") func set(string: ObjCObject?, forKey key: String?) { set(string, forKey: key) }
    @ObjCMethod("setData:forKey:") func set(data: ObjCObject?, forKey key: String?) { set(data, forKey: key) }
    @ObjCMethod("setArray:forKey:") func set(array: ObjCObject?, forKey key: String?) { set(array, forKey: key) }
    @ObjCMethod("setDictionary:forKey:") func set(dictionary: ObjCObject?, forKey key: String?) { set(dictionary, forKey: key) }

    @ObjCMethod("setLongLong:forKey:")
    func set(longLong: Int64, forKey key: String?) { if let key { storage.set(.integer(longLong), for: key) } }

    @ObjCMethod("setDouble:forKey:")
    func set(double: Double, forKey key: String?) { if let key { storage.set(.double(double), for: key) } }

    @ObjCMethod("setBool:forKey:")
    func set(bool: Bool, forKey key: String?) { if let key { storage.set(.bool(bool), for: key) } }

    @ObjCMethod("removeObjectForKey:")
    func remove(forKey key: String?) { if let key { storage.set(nil, for: key) } }

    /// Writes any value not yet written; YES, as with an account and the
    /// entitlement, unless the write fails.
    @ObjCMethod("synchronize")
    func synchronize() -> Bool { storage.saveIfChanged() }
}

@ObjCConstants
enum UserDefaultsConstants {
    static let NSUserDefaultsDidChangeNotification = "NSUserDefaultsDidChangeNotification"
    static let NSUbiquitousKeyValueStoreDidChangeExternallyNotification = "NSUbiquitousKeyValueStoreDidChangeExternallyNotification"
    static let NSUbiquitousKeyValueStoreChangeReasonKey = "NSUbiquitousKeyValueStoreChangeReasonKey"
    static let NSUbiquitousKeyValueStoreChangedKeysKey = "NSUbiquitousKeyValueStoreChangedKeysKey"
    static let NSUbiquityIdentityDidChangeNotification = "NSUbiquityIdentityDidChangeNotification"
    /// The search list's domains.
    static let NSArgumentDomain = "NSArgumentDomain"
    static let NSGlobalDomain = "NSGlobalDomain"
    static let NSRegistrationDomain = "NSRegistrationDomain"
}

/// Sets, or with a nil value removes, a string in NSGlobalDomain's values
/// the system keeps: for other providers, as AppKit sets
/// AppleInterfaceStyle when the desktop's appearance changes.
@c(perry_foundation_set_global_default)
public func perryFoundationSetGlobalDefault(_ key: UnsafePointer<CChar>?, _ value: UnsafePointer<CChar>?) {
    guard let key else { return }
    let name = String(cString: key)
    UserDefaultsStorage.volatileLock.locked { UserDefaultsStorage.system[name] = value.map { .string(String(cString: $0)) } }
}

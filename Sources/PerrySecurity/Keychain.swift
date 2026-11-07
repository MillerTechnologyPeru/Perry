import FoundationEssentials
import Glibc
import PerryObjCInterop

// The keychain: SecItemAdd, SecItemCopyMatching, SecItemUpdate and
// SecItemDelete over generic and internet passwords, keys and
// certificates. Items persist in a JSON file, $PERRY_KEYCHAIN or
// ~/Library/Keychains/perry-keychain.json, locked with flock() while each
// call reads and writes it, so processes share it as apps share a device's
// keychain. Each class has iOS's uniqueness attributes and defaults.

/// An attribute's value.
enum Value: Codable, Equatable {
    case string(String)
    case data(Data)
    case number(Int64)
    case double(Double)
    case bool(Bool)
    case date(Double)

    /// From an attribute's object: a string, data, number, CFBoolean or date.
    init?(_ object: NSObject) {
        if object.isString {
            self = .string(object.stringValue)
        } else if object.isData {
            self = .data(NSData(object.objcObject).data)
        } else if object.isDate {
            self = .date(object.unsafeCast(to: NSDate.self).timeIntervalSinceReferenceDate())
        } else if object.isNumber {
            let number = object.unsafeCast(to: NSNumber.self)
            let type = number.objCType().map { String(cString: $0) } ?? "q"
            switch type {
            case "c", "B": self = .bool(number.boolValue())
            case "f", "d": self = .double(number.doubleValue())
            default: self = .number(number.int64Value())
            }
        } else {
            return nil
        }
    }

    var object: NSObject {
        switch self {
        case .string(let text): return NSObject.string(text)
        case .data(let data): return NSData.of(data)
        case .number(let number): return NSNumber.make(int64: number)
        case .double(let number): return NSNumber.make(double: number)
        case .bool(let flag): return NSNumber.make(bool: flag)
        case .date(let interval): return NSDate.make(sinceReferenceDate: interval)
        }
    }

    var truth: Bool {
        switch self {
        case .bool(let flag): return flag
        case .number(let number): return number != 0
        case .double(let number): return number != 0
        case .string(let text): return ["1", "true", "yes"].contains(text.lowercased())
        default: return false
        }
    }

    /// Equal as an attribute: numbers and flags by value, strings and data
    /// by their bytes.
    func matches(_ other: Value) -> Bool {
        switch (self, other) {
        case (.string(let a), .data(let b)), (.data(let b), .string(let a)): return Data(a.utf8) == b
        case (.number, .bool), (.bool, .number), (.bool, .bool): return truth == other.truth
        case (.number(let a), .double(let b)), (.double(let b), .number(let a)): return Double(a) == b
        default: return self == other
        }
    }
}

struct Item: Codable {
    var id: Int
    var itemClass: String
    var attributes: [String: Value]
    var data: Data?
}

struct Store: Codable {
    var next = 1
    var items: [Item] = []
}

final class Keychain: @unchecked Sendable {
    static let shared = Keychain()

    private let lock = Lock()
    private let path: String

    init() {
        if let configured = getenv("PERRY_KEYCHAIN").map({ String(cString: $0) }), !configured.isEmpty {
            path = configured
        } else {
            let home = getenv("HOME").map { String(cString: $0) } ?? "/tmp"
            path = home + "/Library/Keychains/perry-keychain.json"
        }
    }

    /// The access group items get when a query names none: the app's
    /// bundle identifier, as its first keychain access group.
    lazy var defaultGroup: String = NSBundle.main().bundleIdentifier() ?? "perry"

    /// Runs `body` with the store loaded, saving it if `body` changed it.
    func withStore<T>(_ body: (inout Store) -> T) -> T {
        lock.withLock {
            let directory = String(path[..<(path.lastIndex(of: "/") ?? path.endIndex)])
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            let descriptor = open(path + ".lock", O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
            if descriptor >= 0 { flock(descriptor, LOCK_EX) }
            defer {
                if descriptor >= 0 {
                    flock(descriptor, LOCK_UN)
                    close(descriptor)
                }
            }
            let original = FileManager.default.contents(atPath: path)
            var store = original.flatMap { try? JSONDecoder().decode(Store.self, from: $0) } ?? Store()
            let result = body(&store)
            if let encoded = try? JSONEncoder().encode(store), encoded != original {
                let temporary = path + ".tmp"
                if FileManager.default.createFile(atPath: temporary, contents: encoded) {
                    rename(temporary, path)
                }
            }
            return result
        }
    }

    // MARK: Attributes

    /// Keys that steer a call rather than describe an item.
    static func isControl(_ key: String) -> Bool {
        key == ItemKeys.kSecClass || key.hasPrefix("r_") || key.hasPrefix("m_") || key.hasPrefix("u_") || key.hasPrefix("v_")
            || key == ItemKeys.kSecUseDataProtectionKeychain || key == ItemKeys.kSecAttrAccessControl
            || key == ItemKeys.kSecAttrIsPermanent || key == ItemKeys.kSecAttrTokenID
    }

    /// The attributes that make an item unique within its class.
    static func primaryKeys(_ itemClass: String) -> [String] {
        switch itemClass {
        case ItemKeys.kSecClassGenericPassword:
            return [ItemKeys.kSecAttrAccessGroup, ItemKeys.kSecAttrAccount, ItemKeys.kSecAttrService, ItemKeys.kSecAttrSynchronizable]
        case ItemKeys.kSecClassInternetPassword:
            return [ItemKeys.kSecAttrAccessGroup, ItemKeys.kSecAttrAccount, ItemKeys.kSecAttrSecurityDomain, ItemKeys.kSecAttrServer,
                    ItemKeys.kSecAttrProtocol, ItemKeys.kSecAttrAuthenticationType, ItemKeys.kSecAttrPort, ItemKeys.kSecAttrPath,
                    ItemKeys.kSecAttrSynchronizable]
        case ItemKeys.kSecClassCertificate:
            return [ItemKeys.kSecAttrAccessGroup, ItemKeys.kSecAttrCertificateType, ItemKeys.kSecAttrIssuer,
                    ItemKeys.kSecAttrSerialNumber, ItemKeys.kSecAttrSynchronizable]
        default:
            return [ItemKeys.kSecAttrAccessGroup, ItemKeys.kSecAttrKeyClass, ItemKeys.kSecAttrApplicationLabel,
                    ItemKeys.kSecAttrApplicationTag, ItemKeys.kSecAttrKeyType, ItemKeys.kSecAttrKeySizeInBits,
                    ItemKeys.kSecAttrEffectiveKeySize, ItemKeys.kSecAttrSynchronizable]
        }
    }

    static let classes: Set<String> = [ItemKeys.kSecClassGenericPassword, ItemKeys.kSecClassInternetPassword,
                                       ItemKeys.kSecClassCertificate, ItemKeys.kSecClassKey]

    static func attributes(_ query: NSDictionary) -> [String: Value] {
        var attributes: [String: Value] = [:]
        for (key, value) in query.entries where !isControl(key) {
            if let converted = Value(value) { attributes[key] = converted }
        }
        return attributes
    }

    private func isDuplicate(_ item: Item, in store: Store) -> Bool {
        let keys = Keychain.primaryKeys(item.itemClass)
        return store.items.contains { other in
            other.id != item.id && other.itemClass == item.itemClass && keys.allSatisfy { key in
                switch (item.attributes[key], other.attributes[key]) {
                case (nil, nil): return true
                case (let a?, let b?): return a.matches(b)
                default: return false
                }
            }
        }
    }

    // MARK: Matching

    private func matches(_ item: Item, _ query: NSDictionary, _ itemClass: String?) -> Bool {
        if let itemClass, item.itemClass != itemClass { return false }
        if let reference = query.object(ItemKeys.kSecValuePersistentRef).flatMap(Keychain.persistentID), reference != item.id {
            return false
        }
        if let reference = query.object(ItemKeys.kSecValueRef) {
            let data = Keys.state(reference.objcObject)?.external ?? Certificates.state(reference.objcObject)?.der
            if data != item.data { return false }
        }
        var sawSync = false
        for (key, value) in query.entries where !Keychain.isControl(key) {
            if key == ItemKeys.kSecAttrSynchronizable {
                sawSync = true
                if value.isString, value.stringValue == ItemKeys.kSecAttrSynchronizableAny { continue }
                if (item.attributes[key]?.truth ?? false) != value.truth { return false }
                continue
            }
            guard let wanted = Value(value), let present = item.attributes[key], present.matches(wanted) else { return false }
        }
        // Without kSecAttrSynchronizable, only items that do not sync.
        if !sawSync, item.attributes[ItemKeys.kSecAttrSynchronizable]?.truth ?? false { return false }
        return true
    }

    static func persistentID(_ object: NSObject) -> Int? {
        guard object.isData, let text = String(data: NSData(object.objcObject).data, encoding: .utf8),
              text.hasPrefix("perry:") else { return nil }
        return Int(text.split(separator: ":").last ?? "")
    }

    static func persistentReference(_ item: Item) -> Data { Data("perry:\(item.itemClass):\(item.id)".utf8) }

    // MARK: Results

    private func reference(_ item: Item) -> UnsafeMutableRawPointer? {
        guard let data = item.data else { return nil }
        switch item.itemClass {
        case ItemKeys.kSecClassKey:
            // An item added with no key class (as the common recipe for a
            // public key from a server or a license adds one) is whichever
            // its data reads as: a public key, else a private one.
            guard case .string(let type)? = item.attributes[ItemKeys.kSecAttrKeyType] else { return nil }
            let state: KeyState
            if case .string(let keyClass)? = item.attributes[ItemKeys.kSecAttrKeyClass] {
                guard let made = try? KeyState.make(type: type, isPrivate: keyClass == ItemKeys.kSecAttrKeyClassPrivate, data: data)
                else { return nil }
                state = made
            } else if let made = (try? KeyState.make(type: type, isPrivate: false, data: data))
                        ?? (try? KeyState.make(type: type, isPrivate: true, data: data)) {
                state = made
            } else {
                return nil
            }
            if case .string(let label)? = item.attributes[ItemKeys.kSecAttrLabel] { state.label = label }
            if case .data(let tag)? = item.attributes[ItemKeys.kSecAttrApplicationTag] { state.tag = tag }
            return Keys.object(state)
        case ItemKeys.kSecClassCertificate:
            return CertificateState(der: data).map(Certificates.object)
        default:
            return nil
        }
    }

    /// What a query's return flags ask for, for one item (+1).
    private func result(_ item: Item, _ query: NSDictionary) -> UnsafeMutableRawPointer? {
        let wantsData = query.object(ItemKeys.kSecReturnData)?.truth ?? false
        let wantsAttributes = query.object(ItemKeys.kSecReturnAttributes)?.truth ?? false
        let wantsReference = query.object(ItemKeys.kSecReturnRef)?.truth ?? false
        let wantsPersistent = query.object(ItemKeys.kSecReturnPersistentRef)?.truth ?? false
        let count = [wantsData, wantsAttributes, wantsReference, wantsPersistent].filter { $0 }.count
        if count == 1 && !wantsAttributes {
            if wantsData { return item.data.flatMap(Keys.returned) }
            if wantsReference { return reference(item) }
            return Keys.returned(Keychain.persistentReference(item))
        }
        var entries: [(String, NSObject)] = [(ItemKeys.kSecClass, NSObject.string(item.itemClass))]
        if wantsAttributes { entries += item.attributes.sorted { $0.key < $1.key }.map { ($0.key, $0.value.object) } }
        if wantsData, let data = item.data { entries.append((ItemKeys.kSecValueData, NSData.of(data))) }
        if wantsReference, let reference = reference(item) {
            entries.append((ItemKeys.kSecValueRef, NSObject(objCOwned: reference)))
        }
        if wantsPersistent { entries.append((ItemKeys.kSecValuePersistentRef, NSData.of(Keychain.persistentReference(item)))) }
        return ObjCRuntime.retain(NSMutableDictionary.of(entries).objcObject)
    }

    private func wantsResult(_ query: NSDictionary) -> Bool {
        [ItemKeys.kSecReturnData, ItemKeys.kSecReturnAttributes, ItemKeys.kSecReturnRef, ItemKeys.kSecReturnPersistentRef]
            .contains { query.object($0)?.truth ?? false }
    }

    // MARK: Operations

    func add(_ query: NSDictionary, result: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
        var itemClass = query.object(ItemKeys.kSecClass).flatMap { $0.isString ? $0.stringValue : nil }
        var attributes = Keychain.attributes(query)
        var data = query.object(ItemKeys.kSecValueData).map { $0.isData ? NSData($0.objcObject).data : Data($0.stringValue.utf8) }
        // A key or certificate object brings its own attributes.
        if let reference = query.object(ItemKeys.kSecValueRef) {
            if let key = Keys.state(reference.objcObject) {
                itemClass = itemClass ?? ItemKeys.kSecClassKey
                data = key.external
                for (name, value) in Keychain.keyAttributes(key) where attributes[name] == nil { attributes[name] = value }
            } else if let certificate = Certificates.state(reference.objcObject) {
                itemClass = itemClass ?? ItemKeys.kSecClassCertificate
                data = certificate.der
                for (name, value) in Keychain.certificateAttributes(certificate) where attributes[name] == nil { attributes[name] = value }
            }
        }
        guard let itemClass, Keychain.classes.contains(itemClass) else { return Status.param }
        return insert(itemClass: itemClass, attributes: attributes, data: data, query: query, result: result)
    }

    /// Adds a key SecKeyCreateRandomKey made permanent.
    func add(key: KeyState, attributes: NSDictionary?) -> Int32 {
        var values = attributes.map(Keychain.attributes) ?? [:]
        for (name, value) in Keychain.keyAttributes(key) where values[name] == nil { values[name] = value }
        return insert(itemClass: ItemKeys.kSecClassKey, attributes: values, data: key.external, query: nil, result: nil)
    }

    private func insert(itemClass: String, attributes: [String: Value], data: Data?, query: NSDictionary?,
                        result: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
        var attributes = attributes
        let now = Value.date(Date().timeIntervalSinceReferenceDate)
        attributes[ItemKeys.kSecAttrAccessGroup] = attributes[ItemKeys.kSecAttrAccessGroup] ?? .string(defaultGroup)
        attributes[ItemKeys.kSecAttrAccessible] = attributes[ItemKeys.kSecAttrAccessible] ?? .string(ItemKeys.kSecAttrAccessibleWhenUnlocked)
        attributes[ItemKeys.kSecAttrSynchronizable] = .number((attributes[ItemKeys.kSecAttrSynchronizable]?.truth ?? false) ? 1 : 0)
        attributes[ItemKeys.kSecAttrCreationDate] = now
        attributes[ItemKeys.kSecAttrModificationDate] = now
        if itemClass == ItemKeys.kSecClassGenericPassword {
            attributes[ItemKeys.kSecAttrAccount] = attributes[ItemKeys.kSecAttrAccount] ?? .string("")
            attributes[ItemKeys.kSecAttrService] = attributes[ItemKeys.kSecAttrService] ?? .string("")
        }
        return withStore { store in
            let item = Item(id: store.next, itemClass: itemClass, attributes: attributes, data: data)
            if isDuplicate(item, in: store) { return Status.duplicateItem }
            store.items.append(item)
            store.next += 1
            if let query, let result, wantsResult(query) { result.pointee = self.result(item, query) }
            return Status.success
        }
    }

    func copy(_ query: NSDictionary, result: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
        let itemClass = query.object(ItemKeys.kSecClass).flatMap { $0.isString ? $0.stringValue : nil }
        let persistent = query.object(ItemKeys.kSecValuePersistentRef) != nil
        guard itemClass.map(Keychain.classes.contains) ?? persistent else { return Status.param }
        let limit = query.object(ItemKeys.kSecMatchLimit)
        let all = limit.map { $0.isString ? $0.stringValue == ItemKeys.kSecMatchLimitAll : ($0.integer ?? 1) > 1 } ?? false
        let found = withStore { store in store.items.filter { matches($0, query, itemClass) } }
        guard !found.isEmpty else { return Status.itemNotFound }
        if let result, wantsResult(query) {
            if all {
                let objects = found.compactMap { self.result($0, query) }.map { NSObject(objCOwned: $0) }
                result.pointee = ObjCRuntime.retain(NSMutableArray.of(objects).objcObject)
            } else {
                result.pointee = self.result(found[0], query)
            }
        }
        return Status.success
    }

    func update(_ query: NSDictionary, _ changes: NSDictionary) -> Int32 {
        guard let itemClass = query.object(ItemKeys.kSecClass).flatMap({ $0.isString ? $0.stringValue : nil }),
              Keychain.classes.contains(itemClass) else { return Status.param }
        let attributes = Keychain.attributes(changes)
        let data = changes.object(ItemKeys.kSecValueData).map { NSData($0.objcObject).data }
        return withStore { store in
            let indexes = store.items.indices.filter { matches(store.items[$0], query, itemClass) }
            guard !indexes.isEmpty else { return Status.itemNotFound }
            var updated = store
            for index in indexes {
                for (name, value) in attributes { updated.items[index].attributes[name] = value }
                if let data { updated.items[index].data = data }
                updated.items[index].attributes[ItemKeys.kSecAttrModificationDate] = .date(Date().timeIntervalSinceReferenceDate)
                if isDuplicate(updated.items[index], in: updated) { return Status.duplicateItem }
            }
            store = updated
            return Status.success
        }
    }

    func delete(_ query: NSDictionary) -> Int32 {
        let itemClass = query.object(ItemKeys.kSecClass).flatMap { $0.isString ? $0.stringValue : nil }
        let persistent = query.object(ItemKeys.kSecValuePersistentRef) != nil
        guard itemClass.map(Keychain.classes.contains) ?? persistent else { return Status.param }
        return withStore { store in
            let before = store.items.count
            store.items.removeAll { matches($0, query, itemClass) }
            return store.items.count == before ? Status.itemNotFound : Status.success
        }
    }

    // MARK: Attributes of keys and certificates

    static func keyAttributes(_ key: KeyState) -> [String: Value] {
        var values: [String: Value] = [
            ItemKeys.kSecAttrKeyClass: .string(key.isPrivate ? ItemKeys.kSecAttrKeyClassPrivate : ItemKeys.kSecAttrKeyClassPublic),
            ItemKeys.kSecAttrKeyType: .string(key.isRSA ? ItemKeys.kSecAttrKeyTypeRSA : ItemKeys.kSecAttrKeyTypeECSECPrimeRandom),
            ItemKeys.kSecAttrKeySizeInBits: .number(Int64(key.bits)),
            ItemKeys.kSecAttrEffectiveKeySize: .number(Int64(key.bits)),
        ]
        if let label = try? Keys.applicationLabel(key) { values[ItemKeys.kSecAttrApplicationLabel] = .data(label) }
        if let tag = key.tag { values[ItemKeys.kSecAttrApplicationTag] = .data(tag) }
        if let label = key.label { values[ItemKeys.kSecAttrLabel] = .string(label) }
        return values
    }

    static func certificateAttributes(_ certificate: CertificateState) -> [String: Value] {
        var values: [String: Value] = [
            ItemKeys.kSecAttrCertificateType: .number(1),
            ItemKeys.kSecAttrCertificateEncoding: .number(3),
            ItemKeys.kSecAttrSerialNumber: .data(certificate.serial),
            ItemKeys.kSecAttrIssuer: .data(Data(String(describing: certificate.certificate.issuer).utf8)),
            ItemKeys.kSecAttrSubject: .data(Data(String(describing: certificate.certificate.subject).utf8)),
        ]
        if let summary = certificate.summary { values[ItemKeys.kSecAttrLabel] = .string(summary) }
        return values
    }
}

// MARK: - Functions

/// With PERRY_KEYCHAIN_TRACE set, each SecItem call is written to standard
/// error: the item's class, service, account, access group and tag, and
/// the status it returns.
enum KeychainTrace {
    nonisolated(unsafe) static let enabled = getenv("PERRY_KEYCHAIN_TRACE") != nil

    static func log(_ call: String, _ query: NSDictionary, _ status: Int32) -> Int32 {
        guard enabled else { return status }
        func field(_ key: String, _ name: String) -> String? {
            guard let value = query.object(key) else { return nil }
            if value.isString { return "\(name) \(value.stringValue)" }
            if value.isData { return "\(name) \(String(decoding: NSData(value.objcObject).data, as: UTF8.self))" }
            return "\(name) ?"
        }
        let fields = [(ItemKeys.kSecClass, "class"), (ItemKeys.kSecAttrService, "service"), (ItemKeys.kSecAttrAccount, "account"),
                      (ItemKeys.kSecAttrAccessGroup, "group"), (ItemKeys.kSecAttrApplicationTag, "tag")].compactMap(field)
        let line = "perry: Security: \(call) \(fields.joined(separator: ", ")): \(status)\n"
        line.withCString { _ = write(2, $0, strlen($0)) }
        return status
    }
}

@c(_SecItemAdd)
public func SecItemAdd(_ attributes: UnsafeMutableRawPointer?, _ result: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let attributes else { return Status.param }
    let dictionary = NSDictionary(attributes)
    return KeychainTrace.log("SecItemAdd", dictionary, Keychain.shared.add(dictionary, result: result))
}

@c(_SecItemCopyMatching)
public func SecItemCopyMatching(_ query: UnsafeMutableRawPointer?, _ result: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let query else { return Status.param }
    let dictionary = NSDictionary(query)
    return KeychainTrace.log("SecItemCopyMatching", dictionary, Keychain.shared.copy(dictionary, result: result))
}

@c(_SecItemUpdate)
public func SecItemUpdate(_ query: UnsafeMutableRawPointer?, _ attributes: UnsafeMutableRawPointer?) -> Int32 {
    guard let query, let attributes else { return Status.param }
    let dictionary = NSDictionary(query)
    return KeychainTrace.log("SecItemUpdate", dictionary, Keychain.shared.update(dictionary, NSDictionary(attributes)))
}

@c(_SecItemDelete)
public func SecItemDelete(_ query: UnsafeMutableRawPointer?) -> Int32 {
    guard let query else { return Status.param }
    let dictionary = NSDictionary(query)
    return KeychainTrace.log("SecItemDelete", dictionary, Keychain.shared.delete(dictionary))
}

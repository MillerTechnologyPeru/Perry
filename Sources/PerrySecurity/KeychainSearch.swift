import FoundationEssentials
import Glibc
import PerryObjCInterop

// The keychain's searches from before SecItem
// (SecKeychainSearchCreateFromAttributes, SecKeychainSearchCopyNext) and the
// content of the items they find (SecKeychainItemCopyContent), over the
// items SecItemAdd keeps (Keychain.swift). Darwin's attribute tags are the
// four characters SecItem's attribute keys spell ('acct' is
// kSecAttrAccount's "acct"), so a search's SecKeychainAttributeList is
// matched against those, each value laid out as Darwin lays out its tag's:
// strings as their UTF-8 bytes, four-character codes and numbers as 32-bit
// integers, dates as "YYYYMMDDhhmmSSZ". Every keychain is that one store,
// so the keychain or list a search names isn't looked at. A search finds
// passwords as SecKeychainItems, and certificates and keys as SecCertificates
// and SecKeys, which are keychain items on Darwin; items that sync are left
// out, as a Mac's file keychains don't have them.

private let invalidItemRef: Int32 = -25304      // errSecInvalidItemRef
private let invalidSearchRef: Int32 = -25305    // errSecInvalidSearchRef
private let noSuchClass: Int32 = -25306         // errSecNoSuchClass
private let dataNotAvailable: Int32 = -25316    // errSecDataNotAvailable

extension TypeIDs {
    static let keychainItem: UInt = 0x5345_0010
    static let keychainSearch: UInt = 0x5345_0011
}

// MARK: - Classes

/// SecItemClass codes and the SecItem classes they are.
enum LegacyClasses {
    static let internetPassword: UInt32 = 0x696E_6574   // 'inet'
    static let genericPassword: UInt32 = 0x6765_6E70    // 'genp'
    static let certificate: UInt32 = 0x8000_1000
    static let publicKey: UInt32 = 0x0F
    static let privateKey: UInt32 = 0x10
    static let symmetricKey: UInt32 = 0x11

    /// The SecItem class a code stands for, and for keys the key class.
    static func itemClass(_ code: UInt32) -> (itemClass: String, keyClass: String?)? {
        switch code {
        case internetPassword: return (ItemKeys.kSecClassInternetPassword, nil)
        case genericPassword: return (ItemKeys.kSecClassGenericPassword, nil)
        case certificate: return (ItemKeys.kSecClassCertificate, nil)
        case publicKey: return (ItemKeys.kSecClassKey, ItemKeys.kSecAttrKeyClassPublic)
        case privateKey: return (ItemKeys.kSecClassKey, ItemKeys.kSecAttrKeyClassPrivate)
        case symmetricKey: return (ItemKeys.kSecClassKey, ItemKeys.kSecAttrKeyClassSymmetric)
        default: return nil
        }
    }

    /// An item's code: a key without a key class is a public one.
    static func code(_ item: Item) -> UInt32 {
        switch item.itemClass {
        case ItemKeys.kSecClassInternetPassword: return internetPassword
        case ItemKeys.kSecClassGenericPassword: return genericPassword
        case ItemKeys.kSecClassCertificate: return certificate
        default:
            if case .string(let keyClass)? = item.attributes[ItemKeys.kSecAttrKeyClass] {
                if keyClass == ItemKeys.kSecAttrKeyClassPrivate { return privateKey }
                if keyClass == ItemKeys.kSecAttrKeyClassSymmetric { return symmetricKey }
            }
            return publicKey
        }
    }
}

// MARK: - Attributes

/// SecKeychainAttribute values, by tag.
enum LegacyAttributes {
    /// How a tag's value is laid out.
    enum Layout {
        case text, bytes, code, number, flag, date, authentication
    }

    static func layout(_ tag: String) -> Layout {
        switch tag {
        case "gena", "ssig": return .bytes
        case "crtr", "type", "ptcl": return .code
        case "port", "ctyp", "cenc", "crtp", "crnc", "scrp": return .number
        case "invi", "nega", "cusi": return .flag
        case "cdat", "mdat": return .date
        case "atyp": return .authentication
        default: return .text
        }
    }

    /// A tag's four characters.
    static func name(_ tag: UInt32) -> String {
        String([tag >> 24, tag >> 16, tag >> 8, tag].map { Character(Unicode.Scalar(UInt8($0 & 0xff))) })
    }

    /// A four-character code's value, as 'htps' is.
    static func code(_ text: String) -> UInt32 {
        var value: UInt32 = 0
        var count = 0
        for scalar in text.unicodeScalars.prefix(4) {
            value = value << 8 | (scalar.value & 0xff)
            count += 1
        }
        return count == 0 ? 0 : value << (8 * UInt32(4 - count))
    }

    /// A 32-bit integer's bytes, in this machine's order, as Darwin's are.
    static func word(_ value: UInt32) -> [UInt8] { withUnsafeBytes(of: value) { Array($0) } }

    /// An integer of 1, 2, 4 or 8 bytes in this machine's order.
    static func integer(_ bytes: [UInt8]) -> Int64? {
        switch bytes.count {
        case 1: return Int64(bytes[0])
        case 2: return Int64(bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) })
        case 4: return Int64(bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        case 8: return bytes.withUnsafeBytes { $0.loadUnaligned(as: Int64.self) }
        default: return nil
        }
    }

    /// Seconds since 2001 as Zulu time, "YYYYMMDDhhmmSSZ".
    static func zulu(_ interval: Double) -> String {
        var seconds = time_t(interval + 978_307_200)
        var parts = tm()
        gmtime_r(&seconds, &parts)
        func digits(_ value: Int32, _ width: Int) -> String {
            let text = String(value)
            return String(repeating: "0", count: max(0, width - text.count)) + text
        }
        return digits(parts.tm_year + 1900, 4) + digits(parts.tm_mon + 1, 2) + digits(parts.tm_mday, 2)
            + digits(parts.tm_hour, 2) + digits(parts.tm_min, 2) + digits(parts.tm_sec, 2) + "Z"
    }

    /// The bytes Darwin has for an item's value of an attribute.
    static func bytes(_ value: Value, tag: String) -> [UInt8]? {
        switch layout(tag) {
        case .text, .bytes:
            switch value {
            case .string(let text): return Array(text.utf8)
            case .data(let data): return Array(data)
            case .number(let number): return Array(String(number).utf8)
            default: return nil
            }
        case .code:
            switch value {
            case .string(let text): return word(code(text))
            case .number(let number): return word(UInt32(truncatingIfNeeded: number))
            default: return nil
            }
        case .number:
            switch value {
            case .number(let number): return word(UInt32(truncatingIfNeeded: number))
            case .double(let number): return word(UInt32(truncatingIfNeeded: Int64(number)))
            case .bool(let flag): return word(flag ? 1 : 0)
            case .string(let text): return UInt32(text).map { word($0) }
            default: return nil
            }
        case .flag:
            return word(value.truth ? 1 : 0)
        case .date:
            guard case .date(let interval) = value else { return nil }
            return Array(zulu(interval).utf8) + [0]
        case .authentication:
            // SecAuthenticationType's values are stored byte-swapped on
            // little-endian Darwin, so their bytes read as the four
            // characters ("dflt") there, as SecItem's strings are.
            guard case .string(let text) = value else { return nil }
            let characters = Array(text.utf8.prefix(4))
            return characters + [UInt8](repeating: 0x20, count: 4 - characters.count)
        }
    }

    /// A value from an attribute's bytes, as SecItem keeps it.
    static func value(_ bytes: [UInt8], tag: String) -> Value? {
        switch layout(tag) {
        case .text: return .string(String(decoding: trimmed(bytes), as: UTF8.self))
        case .bytes: return .data(Data(bytes))
        case .code:
            guard let number = integer(bytes) else { return nil }
            // SecItem's protocols are their four characters.
            return tag == "ptcl" ? .string(name(UInt32(truncatingIfNeeded: number))) : .number(number)
        case .number: return integer(bytes).map { .number($0) }
        case .flag: return integer(bytes).map { .bool($0 != 0) }
        case .date: return nil
        case .authentication: return .string(String(decoding: bytes.prefix(4), as: UTF8.self))
        }
    }

    /// Text without the NULs C strings end with.
    static func trimmed(_ bytes: [UInt8]) -> [UInt8] {
        var end = bytes.count
        while end > 0 && bytes[end - 1] == 0 { end -= 1 }
        return Array(bytes[..<end])
    }

    /// Whether an item has a search attribute's value.
    static func matches(_ item: Item, tag: UInt32, bytes: [UInt8]) -> Bool {
        let key = LegacyAttributes.name(tag)
        let kind = LegacyAttributes.layout(key)
        // kSecProtocolTypeAny and kSecAuthenticationTypeAny are 0.
        if key == "ptcl" || kind == .authentication, bytes.count == 4, bytes.allSatisfy({ $0 == 0 }) { return true }
        guard let value = item.attributes[key], let present = LegacyAttributes.bytes(value, tag: key) else { return false }
        switch kind {
        case .text, .bytes:
            return trimmed(present) == trimmed(bytes)
        case .code, .number, .flag:
            return integer(present) == integer(bytes)
        case .authentication:
            return present == Array(bytes.prefix(4))
        case .date:
            // Zulu time, or seconds since 1904 as a UInt32 or SInt64.
            if bytes.count == 4 || bytes.count == 8, let seconds = integer(bytes) {
                return present.prefix(15) == Array(zulu(Double(seconds) - 3_061_152_000).utf8).prefix(15)
            }
            return present.prefix(15) == bytes.prefix(15)
        }
    }
}

/// A SecKeychainAttributeList, read and filled in place: its count, then
/// its array of { tag, length, data } (tag and length 32 bits each, data a
/// pointer).
enum AttributeLists {
    static let pointer = MemoryLayout<UnsafeRawPointer>.size
    static let entrySize = 8 + pointer

    struct Entry {
        let slot: UnsafeMutableRawPointer
        var tag: UInt32 { slot.load(as: UInt32.self) }
        var length: Int { Int(slot.load(fromByteOffset: 4, as: UInt32.self)) }
        var data: UnsafeMutableRawPointer? { slot.load(fromByteOffset: 8, as: UnsafeMutableRawPointer?.self) }

        var bytes: [UInt8] {
            guard let data, length > 0 else { return [] }
            return Array(UnsafeRawBufferPointer(start: data, count: length))
        }

        func store(_ bytes: [UInt8]?) {
            var buffer: UnsafeMutableRawPointer?
            if let bytes {
                buffer = malloc(max(bytes.count, 1))
                if let buffer, !bytes.isEmpty { bytes.withUnsafeBytes { buffer.copyMemory(from: $0.baseAddress!, byteCount: $0.count) } }
            }
            slot.storeBytes(of: UInt32(buffer == nil ? 0 : bytes?.count ?? 0), toByteOffset: 4, as: UInt32.self)
            slot.storeBytes(of: buffer, toByteOffset: 8, as: UnsafeMutableRawPointer?.self)
        }
    }

    static func entries(_ list: UnsafeRawPointer) -> [Entry] {
        let count = Int(list.load(as: UInt32.self))
        guard count > 0, let base = list.load(fromByteOffset: pointer, as: UnsafeMutableRawPointer?.self) else { return [] }
        return (0..<count).map { Entry(slot: base + $0 * entrySize) }
    }
}

// MARK: - Items

/// A password item a search found: its place in the store.
final class LegacyItemState {
    let id: Int

    init(id: Int) { self.id = id }
}

@ObjCClass("__SecKeychainItem")
final class SecKeychainItemObject: NSObject {
    static let states = StateTable<LegacyItemState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        SecKeychainItemObject.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SecKeychainItemObject.objCClass.pointer)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { TypeIDs.keychainItem }
}

enum LegacyItems {
    /// The object a search gives for an item (+1): a SecKeychainItem for a
    /// password, a SecCertificate or a SecKey; nil for data that doesn't
    /// read as its class.
    static func object(_ item: Item) -> UnsafeMutableRawPointer? {
        switch item.itemClass {
        case ItemKeys.kSecClassCertificate:
            return item.data.flatMap { CertificateState(der: $0) }.map(Certificates.object)
        case ItemKeys.kSecClassKey:
            guard let data = item.data, case .string(let type)? = item.attributes[ItemKeys.kSecAttrKeyType],
                  let state = try? KeyState.make(type: type, isPrivate: LegacyClasses.code(item) == LegacyClasses.privateKey, data: data)
            else { return nil }
            if case .string(let label)? = item.attributes[ItemKeys.kSecAttrLabel] { state.label = label }
            if case .data(let tag)? = item.attributes[ItemKeys.kSecAttrApplicationTag] { state.tag = tag }
            return Keys.object(state)
        default:
            let object = SecKeychainItemObject.objCClass.ownedInstance()
            SecKeychainItemObject.states.set(object, LegacyItemState(id: item.id))
            return object
        }
    }

    /// An item reference's item as it is now, and whether its data may be
    /// read (a private key's may not); nil when it is gone or isn't one.
    static func content(_ reference: UnsafeMutableRawPointer?) -> (item: Item, readable: Bool)? {
        if let state = SecKeychainItemObject.states[reference] {
            return Keychain.shared.withStore { store in store.items.first { $0.id == state.id } }.map { ($0, true) }
        }
        if let certificate = Certificates.state(reference) {
            return (Item(id: 0, itemClass: ItemKeys.kSecClassCertificate, attributes: Keychain.certificateAttributes(certificate),
                         data: certificate.der), true)
        }
        if let key = Keys.state(reference) {
            return (Item(id: 0, itemClass: ItemKeys.kSecClassKey, attributes: Keychain.keyAttributes(key),
                         data: key.isPrivate ? nil : key.external), !key.isPrivate)
        }
        return nil
    }

    /// SecKeychainItemDelete: a password item by its place, a certificate
    /// or key by its data. Nil when the reference isn't an item.
    static func delete(_ reference: UnsafeMutableRawPointer?) -> Int32? {
        let matches: (Item) -> Bool
        if let state = SecKeychainItemObject.states[reference] {
            matches = { $0.id == state.id }
        } else if let certificate = Certificates.state(reference) {
            matches = { $0.itemClass == ItemKeys.kSecClassCertificate && $0.data == certificate.der }
        } else if let key = Keys.state(reference) {
            let data = key.external
            matches = { $0.itemClass == ItemKeys.kSecClassKey && $0.data == data }
        } else {
            return nil
        }
        return Keychain.shared.withStore { store in
            let before = store.items.count
            store.items.removeAll(where: matches)
            return store.items.count == before ? Status.itemNotFound : Status.success
        }
    }

    /// SecKeychainItemModifyAttributesAndData on a password item: the
    /// attributes listed (the dates are read-only) and the data, when given.
    /// Nil when the reference isn't a password item.
    static func modify(_ reference: UnsafeMutableRawPointer?, _ attributes: UnsafeRawPointer?, _ length: UInt32,
                       _ data: UnsafeRawPointer?) -> Int32? {
        guard let state = SecKeychainItemObject.states[reference] else { return nil }
        let changes = (attributes.map(AttributeLists.entries) ?? []).compactMap { entry -> (String, Value)? in
            let name = LegacyAttributes.name(entry.tag)
            return LegacyAttributes.value(entry.bytes, tag: name).map { (name, $0) }
        }
        let newData = data.map { Data(bytes: $0, count: Int(length)) }
        return Keychain.shared.withStore { store in
            guard let index = store.items.firstIndex(where: { $0.id == state.id }) else { return invalidItemRef }
            for (name, value) in changes { store.items[index].attributes[name] = value }
            if let newData { store.items[index].data = newData }
            store.items[index].attributes[ItemKeys.kSecAttrModificationDate] = .date(Date().timeIntervalSinceReferenceDate)
            return Status.success
        }
    }
}

@c(_SecKeychainItemGetTypeID) public func SecKeychainItemGetTypeID() -> UInt { TypeIDs.keychainItem }

/// OSStatus SecKeychainItemCopyContent(SecKeychainItemRef, SecItemClass *,
/// SecKeychainAttributeList *, UInt32 *length, void **outData): the item's
/// class, the attributes the list asks for (each a new buffer, or none
/// with length 0 when the item hasn't it) and a copy of its data, which
/// SecKeychainItemFreeContent frees.
@c(_SecKeychainItemCopyContent)
public func SecKeychainItemCopyContent(_ reference: UnsafeMutableRawPointer?, _ itemClass: UnsafeMutablePointer<UInt32>?,
                                       _ attributes: UnsafeMutableRawPointer?, _ length: UnsafeMutablePointer<UInt32>?,
                                       _ data: SecOut?) -> Int32 {
    guard let content = LegacyItems.content(reference) else { return invalidItemRef }
    let (item, readable) = content
    if data != nil && !readable { return dataNotAvailable }
    itemClass?.pointee = LegacyClasses.code(item)
    if let attributes {
        for entry in AttributeLists.entries(attributes) {
            let name = LegacyAttributes.name(entry.tag)
            entry.store(item.attributes[name].flatMap { LegacyAttributes.bytes($0, tag: name) })
        }
    }
    let bytes = item.data ?? Data()
    if let data {
        let buffer = malloc(max(bytes.count, 1))
        if let buffer { bytes.withUnsafeBytes { if let base = $0.baseAddress { buffer.copyMemory(from: base, byteCount: $0.count) } } }
        data.pointee = buffer
    }
    if data != nil || length != nil { length?.pointee = UInt32(bytes.count) }
    return Status.success
}

// MARK: - Searches

final class LegacySearchState {
    let found: [Item]
    var next = 0

    init(found: [Item]) { self.found = found }
}

@ObjCClass("__SecKeychainSearch")
final class SecKeychainSearchObject: NSObject {
    static let states = StateTable<LegacySearchState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        SecKeychainSearchObject.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SecKeychainSearchObject.objCClass.pointer)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { TypeIDs.keychainSearch }
}

@c(_SecKeychainSearchGetTypeID) public func SecKeychainSearchGetTypeID() -> UInt { TypeIDs.keychainSearch }

/// OSStatus SecKeychainSearchCreateFromAttributes(CFTypeRef keychainOrArray,
/// SecItemClass, const SecKeychainAttributeList *, SecKeychainSearchRef *):
/// the items of the class with every attribute listed, found now, in the
/// order they were added.
@c(_SecKeychainSearchCreateFromAttributes)
public func SecKeychainSearchCreateFromAttributes(_ keychainOrArray: UnsafeMutableRawPointer?, _ itemClass: UInt32,
                                                  _ attributes: UnsafeRawPointer?, _ search: SecOut?) -> Int32 {
    guard let search else { return Status.param }
    search.pointee = nil
    guard let kind = LegacyClasses.itemClass(itemClass) else { return noSuchClass }
    let wanted = (attributes.map(AttributeLists.entries) ?? []).map { (tag: $0.tag, bytes: $0.bytes) }
    let found = Keychain.shared.withStore { store in
        store.items.filter { item in
            guard item.itemClass == kind.itemClass, !(item.attributes[ItemKeys.kSecAttrSynchronizable]?.truth ?? false) else { return false }
            if kind.keyClass != nil && LegacyClasses.code(item) != itemClass { return false }
            return wanted.allSatisfy { LegacyAttributes.matches(item, tag: $0.tag, bytes: $0.bytes) }
        }
    }
    let object = SecKeychainSearchObject.objCClass.ownedInstance()
    SecKeychainSearchObject.states.set(object, LegacySearchState(found: found))
    search.pointee = object
    return Status.success
}

/// The next item found (+1), or errSecItemNotFound when there are no more.
@c(_SecKeychainSearchCopyNext)
public func SecKeychainSearchCopyNext(_ search: UnsafeMutableRawPointer?, _ item: SecOut?) -> Int32 {
    item?.pointee = nil
    guard let state = SecKeychainSearchObject.states[search] else { return invalidSearchRef }
    guard let item else { return Status.param }
    while state.next < state.found.count {
        let found = state.found[state.next]
        state.next += 1
        if let object = LegacyItems.object(found) {
            item.pointee = object
            return Status.success
        }
    }
    return Status.itemNotFound
}

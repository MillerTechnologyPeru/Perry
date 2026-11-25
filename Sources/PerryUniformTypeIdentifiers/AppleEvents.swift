import Glibc
import PerryObjCInterop

// 64-bit Mac apps' alone: 32-bit ones bind the Apple Event Manager to the
// Carbon provider, whose handlers they share, and armv7 runs only iOS apps.
#if arch(x86_64) || arch(arm64)
// The Apple Event Manager, which 64-bit Mac apps bind to CoreServices (its
// AE subframework): descriptors, lists, records and Apple events, their
// coercions, the application's handlers, and events it sends itself, which
// go straight to those handlers. No other process sends or receives them
// here, so events for another application fail as one that isn't running
// would. An AEDesc is { DescType, handle } packed to 2 bytes, so its handle
// is at offset 4; the handle is an AEStorage of this file's, reached only
// through these functions.

/// A descriptor's data: its bytes, or for a list, record or Apple event
/// its items (a record's and an event's keyed) and an event's attributes.
struct AEValue {
    var bytes: [UInt8] = []
    var items: [AEItem] = []
    var attributes: [AEItem] = []
    /// A record or an Apple event, whose items are found by keyword.
    var keyed = false
}

struct AEItem {
    var keyword: UInt32
    var type: UInt32
    var value: AEValue
}

/// What an AEDesc's handle points to.
final class AEStorage {
    var value: AEValue
    init(_ value: AEValue) { self.value = value }
}

enum AE {
    static func code(_ text: String) -> UInt32 { text.utf8.reduce(0) { $0 << 8 | UInt32($1) } }

    static let typeNull = code("null"), typeWildCard = code("****"), typeAEList = code("list"), typeAERecord = code("reco")
    static let typeAppleEvent = code("aevt"), typeType = code("type"), typeEnumerated = code("enum"), typeKeyword = code("keyw")
    static let typeProperty = code("prop"), typeBoolean = code("bool"), typeTrue = code("true"), typeFalse = code("fals")
    static let typeSInt16 = code("shor"), typeSInt32 = code("long"), typeSInt64 = code("comp"), typeUInt32 = code("magn")
    static let typeFloat = code("sing"), typeDouble = code("doub")
    static let typeChar = code("TEXT"), typeUTF8Text = code("utf8"), typeUnicodeText = code("utxt")
    static let typeProcessSerialNumber = code("psn "), typeKernelProcessID = code("kpid")
    static let typeObjectSpecifier = code("obj "), typeRangeDescriptor = code("rang")
    static let keyEventClassAttr = code("evcl"), keyEventIDAttr = code("evid"), keyAddressAttr = code("addr")
    static let keyReturnIDAttr = code("rtid"), keyTransactionIDAttr = code("tran"), keyErrorNumber = code("errn")
    static let kCoreEventClass = code("aevt"), kAEAnswer = code("ansr")

    static let noErr: Int16 = 0, paramErr: Int16 = -50, procNotFound: Int16 = -600
    static let coercionFail: Int16 = -1700, descNotFound: Int16 = -1701, wrongDataType: Int16 = -1703
    static let notAEDesc: Int16 = -1704, badListItem: Int16 = -1705, notAppleEvent: Int16 = -1707
    static let eventNotHandled: Int16 = -1708, handlerNotFound: Int16 = -1717, illegalIndex: Int16 = -1719
    static let accessorNotFound: Int16 = -1723

    // MARK: Descriptors in memory

    static func type(_ desc: UnsafeRawPointer) -> UInt32 { desc.loadUnaligned(as: UInt32.self) }

    static func storage(_ desc: UnsafeRawPointer) -> AEStorage? {
        let bits = desc.loadUnaligned(fromByteOffset: 4, as: UInt.self)
        return UnsafeMutableRawPointer(bitPattern: bits).map { Unmanaged<AEStorage>.fromOpaque($0).takeUnretainedValue() }
    }

    static func value(_ desc: UnsafeRawPointer) -> AEValue { storage(desc)?.value ?? AEValue() }

    /// Makes `desc` a new descriptor: typeNull has no data.
    static func set(_ desc: UnsafeMutableRawPointer, _ type: UInt32, _ value: AEValue) {
        desc.storeBytes(of: type, as: UInt32.self)
        let handle = type == typeNull ? 0 : UInt(bitPattern: Unmanaged.passRetained(AEStorage(value)).toOpaque())
        desc.storeBytes(of: handle, toByteOffset: 4, as: UInt.self)
    }

    static func dispose(_ desc: UnsafeMutableRawPointer) {
        let bits = desc.loadUnaligned(fromByteOffset: 4, as: UInt.self)
        if let handle = UnsafeMutableRawPointer(bitPattern: bits) { Unmanaged<AEStorage>.fromOpaque(handle).release() }
        set(desc, typeNull, AEValue())
    }

    static func item(_ desc: UnsafeRawPointer) -> AEItem { AEItem(keyword: 0, type: type(desc), value: value(desc)) }

    static func bytes(_ pointer: UnsafeRawPointer?, _ size: Int) -> [UInt8] {
        guard let pointer, size > 0 else { return [] }
        return Array(UnsafeRawBufferPointer(start: pointer, count: size))
    }

    /// Copies a descriptor's bytes out, as much as fits.
    static func copy(_ bytes: [UInt8], to buffer: UnsafeMutableRawPointer?, maximum: Int) {
        guard let buffer, maximum > 0, !bytes.isEmpty else { return }
        bytes.withUnsafeBytes { buffer.copyMemory(from: $0.baseAddress!, byteCount: min(maximum, $0.count)) }
    }

    // MARK: Coercion

    static func number<T: FixedWidthInteger>(_ value: T) -> [UInt8] { withUnsafeBytes(of: value) { Array($0) } }
    static func number(_ value: Double) -> [UInt8] { withUnsafeBytes(of: value) { Array($0) } }
    static func number(_ value: Float) -> [UInt8] { withUnsafeBytes(of: value) { Array($0) } }

    static func load<T>(_ bytes: [UInt8], as type: T.Type) -> T? {
        guard bytes.count == MemoryLayout<T>.size else { return nil }
        return bytes.withUnsafeBytes { $0.loadUnaligned(as: T.self) }
    }

    static let textTypes: Set<UInt32> = [typeChar, typeUTF8Text, typeUnicodeText]
    static let codeTypes: Set<UInt32> = [typeType, typeEnumerated, typeKeyword, typeProperty]

    static func text(_ type: UInt32, _ bytes: [UInt8]) -> String? {
        switch type {
        case typeUTF8Text: return String(validating: bytes, as: UTF8.self)
        case typeUnicodeText:
            // Native byte order, after a byte order mark if there is one.
            var units = stride(from: 0, to: bytes.count - 1, by: 2).map { UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8 }
            if units.first == 0xFEFF { units.removeFirst() }
            return String(validating: units, as: UTF16.self)
        case typeChar: return bytes.withUnsafeBytes { TextEncodings.decode($0, 0) }   // Mac OS Roman
        default: return nil
        }
    }

    static func textBytes(_ text: String, as type: UInt32) -> [UInt8]? {
        switch type {
        case typeUTF8Text: return Array(text.utf8)
        case typeUnicodeText: return text.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
        case typeChar: return TextEncodings.encode(text[...], 0, lossByte: UInt8(ascii: "?"))
        default: return nil
        }
    }

    /// A number's value, from a numeric, boolean or text descriptor.
    static func double(_ type: UInt32, _ bytes: [UInt8]) -> Double? {
        switch type {
        case typeSInt16: return load(bytes, as: Int16.self).map(Double.init)
        case typeSInt32: return load(bytes, as: Int32.self).map(Double.init)
        case typeSInt64: return load(bytes, as: Int64.self).map(Double.init)
        case typeUInt32: return load(bytes, as: UInt32.self).map(Double.init)
        case typeFloat: return load(bytes, as: Float.self).map(Double.init)
        case typeDouble: return load(bytes, as: Double.self)
        case typeBoolean: return bytes.first.map { $0 == 0 ? 0 : 1 }
        case typeTrue: return 1
        case typeFalse: return 0
        default: return text(type, bytes).flatMap { Double($0.trimmingCharacters(in: " \t\r\n")) }
        }
    }

    static func numberBytes(_ value: Double, as type: UInt32) -> [UInt8]? {
        func integer<T: FixedWidthInteger>(_: T.Type) -> [UInt8]? {
            guard value.rounded() == value, let exact = T(exactly: value) else { return nil }
            return number(exact)
        }
        switch type {
        case typeSInt16: return integer(Int16.self)
        case typeSInt32: return integer(Int32.self)
        case typeSInt64: return integer(Int64.self)
        case typeUInt32: return integer(UInt32.self)
        case typeFloat: return number(Float(value))
        case typeDouble: return number(value)
        case typeBoolean: return value == 0 || value == 1 ? [UInt8(value)] : nil
        default: return nil
        }
    }

    static let numericTypes: Set<UInt32> = [typeSInt16, typeSInt32, typeSInt64, typeUInt32, typeFloat, typeDouble, typeBoolean, typeTrue, typeFalse]

    /// The item as `to`: itself for the same type or typeWildCard, else the
    /// standard coercions between text, numbers, four-character codes and
    /// lists.
    static func coerce(_ item: AEItem, to: UInt32) -> AEItem? {
        if to == typeWildCard || to == item.type { return item }
        var result = AEItem(keyword: item.keyword, type: to, value: AEValue())
        if to == typeAEList {
            if item.type == typeAERecord || item.value.keyed { return nil }
            result.value.items = [AEItem(keyword: 0, type: item.type, value: item.value)]
            return result
        }
        if to == typeAERecord, item.value.keyed {
            result.value = item.value
            return result
        }
        if codeTypes.contains(to), codeTypes.contains(item.type), item.value.bytes.count == 4 {
            result.value.bytes = item.value.bytes
            return result
        }
        if textTypes.contains(to) {
            if let text = text(item.type, item.value.bytes), let bytes = textBytes(text, as: to) {
                result.value.bytes = bytes
                return result
            }
            if numericTypes.contains(item.type), let value = double(item.type, item.value.bytes),
               let bytes = textBytes(value.rounded() == value && abs(value) < 1e15 ? String(Int64(value)) : String(value), as: to) {
                result.value.bytes = bytes
                return result
            }
            if codeTypes.contains(item.type), let value = load(item.value.bytes, as: UInt32.self),
               let bytes = textBytes(fourCharacters(value), as: to) {
                result.value.bytes = bytes
                return result
            }
            return nil
        }
        if numericTypes.contains(to), let value = double(item.type, item.value.bytes) {
            if to == typeTrue || to == typeFalse { return (value != 0) == (to == typeTrue) ? result : nil }
            guard let bytes = numberBytes(value, as: to) else { return nil }
            result.value.bytes = bytes
            return result
        }
        return nil
    }

    // MARK: Handlers

    typealias EventHandler = @convention(c) (UnsafeRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Int16

    struct Handler {
        var eventClass: UInt32, eventID: UInt32
        var procedure: UnsafeMutableRawPointer?
        var refCon: UnsafeMutableRawPointer?
    }

    static let lock = Lock()
    nonisolated(unsafe) static var handlers: [Handler] = []
    nonisolated(unsafe) static var systemHandlers: [Handler] = []
    nonisolated(unsafe) static var accessors: [Handler] = []
    nonisolated(unsafe) static var nextReturnID: Int16 = 1

    static func handler(_ eventClass: UInt32, _ eventID: UInt32) -> Handler? {
        lock.withLock {
            let all = handlers + systemHandlers
            return all.first { $0.eventClass == eventClass && $0.eventID == eventID }
                ?? all.first { ($0.eventClass == eventClass || $0.eventClass == typeWildCard) && ($0.eventID == eventID || $0.eventID == typeWildCard) }
        }
    }

    static func attribute(_ event: AEValue, _ keyword: UInt32) -> AEItem? { event.attributes.first { $0.keyword == keyword } }

    static func code(of item: AEItem?) -> UInt32 { item.flatMap { load($0.value.bytes, as: UInt32.self) } ?? 0 }

    /// Whether an address names this process: kCurrentProcess, this pid, or
    /// no address at all.
    static func isSelf(_ address: AEItem?) -> Bool {
        guard let address, address.type != typeNull else { return true }
        if address.type == typeProcessSerialNumber, let psn = load(address.value.bytes, as: (UInt32, UInt32).self) {
            return psn.0 == 0 && psn.1 == 2   // { 0, kCurrentProcess }
        }
        if address.type == typeKernelProcessID, let pid = load(address.value.bytes, as: Int32.self) { return pid == getpid() }
        return false
    }

    /// Hands an event to the application's handler for it, with a reply
    /// event the handler fills in.
    static func dispatch(_ event: UnsafeRawPointer, _ reply: UnsafeMutableRawPointer?) -> Int16 {
        let value = value(event)
        let eventClass = code(of: attribute(value, keyEventClassAttr)), eventID = code(of: attribute(value, keyEventIDAttr))
        guard let handler = handler(eventClass, eventID), let procedure = handler.procedure else { return eventNotHandled }
        let function = unsafeBitCast(procedure, to: EventHandler.self)
        if let reply { return function(event, reply, handler.refCon) }
        var unused = (UInt32(0), UInt16(0), UInt16(0), UInt16(0), UInt16(0))   // a 12-byte typeNull AEDesc
        return withUnsafeMutableBytes(of: &unused) { buffer in
            set(buffer.baseAddress!, typeNull, AEValue())
            defer { dispose(buffer.baseAddress!) }
            return function(event, buffer.baseAddress, handler.refCon)
        }
    }

    /// AESend's and AESendMessage's work: an event for this process goes to
    /// its handler at once; one for another fails as for a process that
    /// isn't running.
    static func send(_ event: UnsafeRawPointer?, _ reply: UnsafeMutableRawPointer?, mode: Int32) -> Int16 {
        guard let event else { return paramErr }
        guard type(event) == typeAppleEvent else { return notAppleEvent }
        let wantsReply = mode & 3 == 3   // kAEWaitReply
        if let reply {
            var answer = AEValue(keyed: true)
            answer.attributes = [AEItem(keyword: keyEventClassAttr, type: typeType, value: AEValue(bytes: number(kCoreEventClass))),
                                 AEItem(keyword: keyEventIDAttr, type: typeType, value: AEValue(bytes: number(kAEAnswer)))]
            set(reply, wantsReply ? typeAppleEvent : typeNull, answer)
        }
        guard isSelf(attribute(value(event), keyAddressAttr)) else { return procNotFound }
        let error = dispatch(event, wantsReply ? reply : nil)
        if error != noErr, wantsReply, let reply, let storage = storage(reply), !storage.value.items.contains(where: { $0.keyword == keyErrorNumber }) {
            storage.value.items.append(AEItem(keyword: keyErrorNumber, type: typeSInt32, value: AEValue(bytes: number(Int32(error)))))
        }
        return wantsReply && error == eventNotHandled ? eventNotHandled : noErr
    }

    /// A four-character code's characters.
    static func fourCharacters(_ value: UInt32) -> String {
        String(decoding: [UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)], as: UTF8.self)
    }

    /// A descriptor's text, as AEPrintDescToHandle shows it.
    static func describe(_ item: AEItem) -> String {
        func code(_ value: UInt32) -> String { fourCharacters(value) }
        func items(_ list: [AEItem], keyed: Bool) -> String {
            list.map { keyed ? "\(code($0.keyword)):\(describe($0))" : describe($0) }.joined(separator: ", ")
        }
        if item.type == typeAppleEvent {
            let event = item.value
            return "'\(code(AE.code(of: attribute(event, keyEventClassAttr))))'\\'\(code(AE.code(of: attribute(event, keyEventIDAttr))))'{ \(items(event.items, keyed: true)) }"
        }
        if item.type == typeAEList { return "[\(items(item.value.items, keyed: false))]" }
        if item.value.keyed { return (item.type == typeAERecord ? "" : "'\(code(item.type))'") + "{ \(items(item.value.items, keyed: true)) }" }
        if let text = text(item.type, item.value.bytes) { return "'\(code(item.type))'(\"\(text)\")" }
        if numericTypes.contains(item.type), let value = double(item.type, item.value.bytes) { return "\(value)" }
        if codeTypes.contains(item.type), item.value.bytes.count == 4 { return "'\(code(load(item.value.bytes, as: UInt32.self)!))'" }
        return "'\(code(item.type))'(\(item.value.bytes.map { String($0, radix: 16) }.joined()))"
    }
}

private extension String {
    func trimmingCharacters(in set: String) -> String {
        var view = Substring(self)
        while let first = view.first, set.contains(first) { view.removeFirst() }
        while let last = view.last, set.contains(last) { view.removeLast() }
        return String(view)
    }
}

// MARK: - Descriptors

/// OSErr AECreateDesc(DescType, const void *, Size, AEDesc *).
@c(_AECreateDesc)
public func AECreateDesc(_ type: UInt32, _ data: UnsafeRawPointer?, _ size: Int, _ result: UnsafeMutableRawPointer?) -> Int16 {
    guard let result, size >= 0 else { return AE.paramErr }
    AE.set(result, type, AEValue(bytes: AE.bytes(data, size)))
    return AE.noErr
}

@c(_AEInitializeDesc)
public func AEInitializeDesc(_ desc: UnsafeMutableRawPointer?) {
    guard let desc else { return }
    desc.storeBytes(of: AE.typeNull, as: UInt32.self)
    desc.storeBytes(of: UInt(0), toByteOffset: 4, as: UInt.self)
}

@c(_AEDisposeDesc)
public func AEDisposeDesc(_ desc: UnsafeMutableRawPointer?) -> Int16 {
    if let desc { AE.dispose(desc) }
    return AE.noErr
}

@c(_AEDuplicateDesc)
public func AEDuplicateDesc(_ desc: UnsafeRawPointer?, _ result: UnsafeMutableRawPointer?) -> Int16 {
    guard let desc, let result else { return AE.paramErr }
    AE.set(result, AE.type(desc), AE.value(desc))
    return AE.noErr
}

@c(_AEGetDescDataSize)
public func AEGetDescDataSize(_ desc: UnsafeRawPointer?) -> Int { desc.map { AE.value($0).bytes.count } ?? 0 }

@c(_AEGetDescData)
public func AEGetDescData(_ desc: UnsafeRawPointer?, _ buffer: UnsafeMutableRawPointer?, _ maximum: Int) -> Int16 {
    guard let desc else { return AE.paramErr }
    AE.copy(AE.value(desc).bytes, to: buffer, maximum: maximum)
    return AE.noErr
}

/// OSErr AEReplaceDescData(DescType, const void *, Size, AEDesc *).
@c(_AEReplaceDescData)
public func AEReplaceDescData(_ type: UInt32, _ data: UnsafeRawPointer?, _ size: Int, _ desc: UnsafeMutableRawPointer?) -> Int16 {
    guard let desc, size >= 0 else { return AE.paramErr }
    AE.dispose(desc)
    AE.set(desc, type, AEValue(bytes: AE.bytes(data, size)))
    return AE.noErr
}

@c(_AECheckIsRecord)
public func AECheckIsRecord(_ desc: UnsafeRawPointer?) -> UInt8 {
    guard let desc else { return 0 }
    return AE.type(desc) != AE.typeAppleEvent && AE.value(desc).keyed ? 1 : 0
}

/// OSErr AECoercePtr(DescType, const void *, Size, DescType toType, AEDesc *).
@c(_AECoercePtr)
public func AECoercePtr(_ type: UInt32, _ data: UnsafeRawPointer?, _ size: Int, _ toType: UInt32, _ result: UnsafeMutableRawPointer?) -> Int16 {
    guard let result, size >= 0 else { return AE.paramErr }
    guard let coerced = AE.coerce(AEItem(keyword: 0, type: type, value: AEValue(bytes: AE.bytes(data, size))), to: toType) else {
        AE.set(result, AE.typeNull, AEValue())
        return AE.coercionFail
    }
    AE.set(result, coerced.type, coerced.value)
    return AE.noErr
}

@c(_AECoerceDesc)
public func AECoerceDesc(_ desc: UnsafeRawPointer?, _ toType: UInt32, _ result: UnsafeMutableRawPointer?) -> Int16 {
    guard let desc, let result else { return AE.paramErr }
    guard let coerced = AE.coerce(AE.item(desc), to: toType) else {
        AE.set(result, AE.typeNull, AEValue())
        return AE.coercionFail
    }
    AE.set(result, coerced.type, coerced.value)
    return AE.noErr
}

// MARK: - Lists and records

/// OSErr AECreateList(const void *factoringPtr, Size, Boolean isRecord, AEDescList *).
@c(_AECreateList)
public func AECreateList(_ factoring: UnsafeRawPointer?, _ size: Int, _ isRecord: UInt8, _ result: UnsafeMutableRawPointer?) -> Int16 {
    guard let result else { return AE.paramErr }
    AE.set(result, isRecord != 0 ? AE.typeAERecord : AE.typeAEList, AEValue(keyed: isRecord != 0))
    return AE.noErr
}

@c(_AECountItems)
public func AECountItems(_ list: UnsafeRawPointer?, _ count: UnsafeMutablePointer<Int>?) -> Int16 {
    guard let list, let count else { return AE.paramErr }
    count.pointee = AE.value(list).items.count
    return AE.noErr
}

/// The item at a 1-based index.
private func nthItem(_ list: UnsafeRawPointer?, _ index: Int) -> (AEItem?, Int16) {
    guard let list else { return (nil, AE.paramErr) }
    let items = AE.value(list).items
    guard index >= 1, index <= items.count else { return (nil, AE.illegalIndex) }
    return (items[index - 1], AE.noErr)
}

/// OSErr AEGetNthPtr(const AEDescList *, long index, DescType desired,
/// AEKeyword *, DescType *, void *, Size maximum, Size *actual).
@c(_AEGetNthPtr)
public func AEGetNthPtr(_ list: UnsafeRawPointer?, _ index: Int, _ desired: UInt32, _ keyword: UnsafeMutablePointer<UInt32>?,
                        _ type: UnsafeMutablePointer<UInt32>?, _ buffer: UnsafeMutableRawPointer?, _ maximum: Int,
                        _ actual: UnsafeMutablePointer<Int>?) -> Int16 {
    let (found, error) = nthItem(list, index)
    guard let found else { return error }
    guard let item = AE.coerce(found, to: desired) else { return AE.coercionFail }
    keyword?.pointee = found.keyword
    type?.pointee = item.type
    actual?.pointee = item.value.bytes.count
    AE.copy(item.value.bytes, to: buffer, maximum: maximum)
    return AE.noErr
}

@c(_AEGetNthDesc)
public func AEGetNthDesc(_ list: UnsafeRawPointer?, _ index: Int, _ desired: UInt32, _ keyword: UnsafeMutablePointer<UInt32>?,
                         _ result: UnsafeMutableRawPointer?) -> Int16 {
    guard let result else { return AE.paramErr }
    let (found, error) = nthItem(list, index)
    guard let found else {
        AE.set(result, AE.typeNull, AEValue())
        return error
    }
    guard let item = AE.coerce(found, to: desired) else {
        AE.set(result, AE.typeNull, AEValue())
        return AE.coercionFail
    }
    keyword?.pointee = found.keyword
    AE.set(result, item.type, item.value)
    return AE.noErr
}

/// OSErr AESizeOfNthItem(const AEDescList *, long index, DescType *, Size *).
@c(_AESizeOfNthItem)
public func AESizeOfNthItem(_ list: UnsafeRawPointer?, _ index: Int, _ type: UnsafeMutablePointer<UInt32>?, _ size: UnsafeMutablePointer<Int>?) -> Int16 {
    let (found, error) = nthItem(list, index)
    guard let found else { return error }
    type?.pointee = found.type
    size?.pointee = found.value.bytes.count
    return AE.noErr
}

/// Puts an item at a 1-based index, replacing the one there; 0 or one past
/// the end appends.
private func putItem(_ list: UnsafeMutableRawPointer?, _ index: Int, _ item: AEItem) -> Int16 {
    guard let list, let storage = AE.storage(list) else { return AE.paramErr }
    if index >= 1, index <= storage.value.items.count {
        var replacement = item
        replacement.keyword = storage.value.items[index - 1].keyword
        storage.value.items[index - 1] = replacement
    } else if index == 0 || index == storage.value.items.count + 1 {
        storage.value.items.append(item)
    } else {
        return AE.illegalIndex
    }
    return AE.noErr
}

/// OSErr AEPutPtr(AEDescList *, long index, DescType, const void *, Size).
@c(_AEPutPtr)
public func AEPutPtr(_ list: UnsafeMutableRawPointer?, _ index: Int, _ type: UInt32, _ data: UnsafeRawPointer?, _ size: Int) -> Int16 {
    putItem(list, index, AEItem(keyword: 0, type: type, value: AEValue(bytes: AE.bytes(data, size))))
}

@c(_AEPutDesc)
public func AEPutDesc(_ list: UnsafeMutableRawPointer?, _ index: Int, _ desc: UnsafeRawPointer?) -> Int16 {
    guard let desc else { return AE.paramErr }
    return putItem(list, index, AE.item(desc))
}

/// Sets a keyword's item in a record or event's parameters or attributes.
private func putKeyed(_ desc: UnsafeMutableRawPointer?, _ keyword: UInt32, _ item: AEItem, attribute: Bool) -> Int16 {
    guard let desc, let storage = AE.storage(desc) else { return AE.paramErr }
    var keyed = item
    keyed.keyword = keyword
    if attribute {
        storage.value.attributes.removeAll { $0.keyword == keyword }
        storage.value.attributes.append(keyed)
    } else if let at = storage.value.items.firstIndex(where: { $0.keyword == keyword }) {
        storage.value.items[at] = keyed
    } else {
        storage.value.items.append(keyed)
    }
    return AE.noErr
}

private func keyedItem(_ desc: UnsafeRawPointer?, _ keyword: UInt32, attribute: Bool) -> AEItem? {
    guard let desc else { return nil }
    let value = AE.value(desc)
    if attribute {
        // The address, class and ID are an event's own.
        return value.attributes.first { $0.keyword == keyword }
    }
    return value.items.first { $0.keyword == keyword }
}

/// OSErr AEPutParamPtr(AppleEvent *, AEKeyword, DescType, const void *, Size):
/// also AEPutKeyPtr, for records.
@c(_AEPutParamPtr)
public func AEPutParamPtr(_ event: UnsafeMutableRawPointer?, _ keyword: UInt32, _ type: UInt32, _ data: UnsafeRawPointer?, _ size: Int) -> Int16 {
    guard size >= 0 else { return AE.paramErr }
    return putKeyed(event, keyword, AEItem(keyword: keyword, type: type, value: AEValue(bytes: AE.bytes(data, size))), attribute: false)
}

@c(_AEPutParamDesc)
public func AEPutParamDesc(_ event: UnsafeMutableRawPointer?, _ keyword: UInt32, _ desc: UnsafeRawPointer?) -> Int16 {
    guard let desc else { return AE.paramErr }
    return putKeyed(event, keyword, AE.item(desc), attribute: false)
}

@c(_AEPutAttributePtr)
public func AEPutAttributePtr(_ event: UnsafeMutableRawPointer?, _ keyword: UInt32, _ type: UInt32, _ data: UnsafeRawPointer?, _ size: Int) -> Int16 {
    guard size >= 0 else { return AE.paramErr }
    return putKeyed(event, keyword, AEItem(keyword: keyword, type: type, value: AEValue(bytes: AE.bytes(data, size))), attribute: true)
}

@c(_AEPutAttributeDesc)
public func AEPutAttributeDesc(_ event: UnsafeMutableRawPointer?, _ keyword: UInt32, _ desc: UnsafeRawPointer?) -> Int16 {
    guard let desc else { return AE.paramErr }
    return putKeyed(event, keyword, AE.item(desc), attribute: true)
}

private func getKeyedPtr(_ desc: UnsafeRawPointer?, _ keyword: UInt32, _ desired: UInt32, _ type: UnsafeMutablePointer<UInt32>?,
                         _ buffer: UnsafeMutableRawPointer?, _ maximum: Int, _ actual: UnsafeMutablePointer<Int>?, attribute: Bool) -> Int16 {
    guard desc != nil else { return AE.paramErr }
    guard let found = keyedItem(desc, keyword, attribute: attribute) else { return AE.descNotFound }
    guard let item = AE.coerce(found, to: desired) else { return AE.coercionFail }
    type?.pointee = item.type
    actual?.pointee = item.value.bytes.count
    AE.copy(item.value.bytes, to: buffer, maximum: maximum)
    return AE.noErr
}

private func getKeyedDesc(_ desc: UnsafeRawPointer?, _ keyword: UInt32, _ desired: UInt32, _ result: UnsafeMutableRawPointer?,
                          attribute: Bool) -> Int16 {
    guard desc != nil, let result else { return AE.paramErr }
    AE.set(result, AE.typeNull, AEValue())
    guard let found = keyedItem(desc, keyword, attribute: attribute) else { return AE.descNotFound }
    guard let item = AE.coerce(found, to: desired) else { return AE.coercionFail }
    AE.set(result, item.type, item.value)
    return AE.noErr
}

/// OSErr AEGetParamPtr(const AppleEvent *, AEKeyword, DescType desired,
/// DescType *, void *, Size maximum, Size *actual): also AEGetKeyPtr.
@c(_AEGetParamPtr)
public func AEGetParamPtr(_ event: UnsafeRawPointer?, _ keyword: UInt32, _ desired: UInt32, _ type: UnsafeMutablePointer<UInt32>?,
                          _ buffer: UnsafeMutableRawPointer?, _ maximum: Int, _ actual: UnsafeMutablePointer<Int>?) -> Int16 {
    getKeyedPtr(event, keyword, desired, type, buffer, maximum, actual, attribute: false)
}

@c(_AEGetParamDesc)
public func AEGetParamDesc(_ event: UnsafeRawPointer?, _ keyword: UInt32, _ desired: UInt32, _ result: UnsafeMutableRawPointer?) -> Int16 {
    getKeyedDesc(event, keyword, desired, result, attribute: false)
}

@c(_AEGetAttributePtr)
public func AEGetAttributePtr(_ event: UnsafeRawPointer?, _ keyword: UInt32, _ desired: UInt32, _ type: UnsafeMutablePointer<UInt32>?,
                              _ buffer: UnsafeMutableRawPointer?, _ maximum: Int, _ actual: UnsafeMutablePointer<Int>?) -> Int16 {
    getKeyedPtr(event, keyword, desired, type, buffer, maximum, actual, attribute: true)
}

@c(_AEGetAttributeDesc)
public func AEGetAttributeDesc(_ event: UnsafeRawPointer?, _ keyword: UInt32, _ desired: UInt32, _ result: UnsafeMutableRawPointer?) -> Int16 {
    getKeyedDesc(event, keyword, desired, result, attribute: true)
}

/// OSErr AESizeOfParam(const AppleEvent *, AEKeyword, DescType *, Size *).
@c(_AESizeOfParam)
public func AESizeOfParam(_ event: UnsafeRawPointer?, _ keyword: UInt32, _ type: UnsafeMutablePointer<UInt32>?, _ size: UnsafeMutablePointer<Int>?) -> Int16 {
    guard event != nil else { return AE.paramErr }
    guard let found = keyedItem(event, keyword, attribute: false) else { return AE.descNotFound }
    type?.pointee = found.type
    size?.pointee = found.value.bytes.count
    return AE.noErr
}

@c(_AEDeleteParam)
public func AEDeleteParam(_ event: UnsafeMutableRawPointer?, _ keyword: UInt32) -> Int16 {
    guard let event, let storage = AE.storage(event) else { return AE.paramErr }
    guard let at = storage.value.items.firstIndex(where: { $0.keyword == keyword }) else { return AE.descNotFound }
    storage.value.items.remove(at: at)
    return AE.noErr
}

// MARK: - Apple events

/// OSErr AECreateAppleEvent(AEEventClass, AEEventID, const AEAddressDesc *,
/// AEReturnID, AETransactionID, AppleEvent *).
@c(_AECreateAppleEvent)
public func AECreateAppleEvent(_ eventClass: UInt32, _ eventID: UInt32, _ target: UnsafeRawPointer?, _ returnID: Int16,
                               _ transactionID: Int32, _ result: UnsafeMutableRawPointer?) -> Int16 {
    guard let result else { return AE.paramErr }
    var id = returnID
    if id == -1 {   // kAutoGenerateReturnID
        id = AE.lock.withLock {
            defer { AE.nextReturnID = AE.nextReturnID == Int16.max ? 1 : AE.nextReturnID + 1 }
            return AE.nextReturnID
        }
    }
    var event = AEValue(keyed: true)
    event.attributes = [AEItem(keyword: AE.keyEventClassAttr, type: AE.typeType, value: AEValue(bytes: AE.number(eventClass))),
                        AEItem(keyword: AE.keyEventIDAttr, type: AE.typeType, value: AEValue(bytes: AE.number(eventID))),
                        AEItem(keyword: AE.keyReturnIDAttr, type: AE.typeSInt16, value: AEValue(bytes: AE.number(id))),
                        AEItem(keyword: AE.keyTransactionIDAttr, type: AE.typeSInt32, value: AEValue(bytes: AE.number(transactionID)))]
    if let target { event.attributes.append(AEItem(keyword: AE.keyAddressAttr, type: AE.type(target), value: AE.value(target))) }
    AE.set(result, AE.typeAppleEvent, event)
    return AE.noErr
}

/// OSErr AESend(const AppleEvent *, AppleEvent *reply, AESendMode,
/// AESendPriority, long timeOutInTicks, AEIdleUPP, AEFilterUPP).
@c(_AESend)
public func AESend(_ event: UnsafeRawPointer?, _ reply: UnsafeMutableRawPointer?, _ mode: Int32, _ priority: Int16, _ timeout: Int,
                   _ idle: UnsafeRawPointer?, _ filter: UnsafeRawPointer?) -> Int16 {
    AE.send(event, reply, mode: mode)
}

/// OSStatus AESendMessage(const AppleEvent *, AppleEvent *reply, AESendMode, long timeOutInTicks).
@c(_AESendMessage)
public func AESendMessage(_ event: UnsafeRawPointer?, _ reply: UnsafeMutableRawPointer?, _ mode: Int32, _ timeout: Int) -> Int32 {
    Int32(AE.send(event, reply, mode: mode))
}

/// OSStatus AEDeterminePermissionToAutomateTarget(const AEAddressDesc *,
/// AEEventClass, AEEventID, Boolean askUserIfNeeded): this process may
/// send itself anything; no other is running to send to.
@c(_AEDeterminePermissionToAutomateTarget)
public func AEDeterminePermissionToAutomateTarget(_ target: UnsafeRawPointer?, _ eventClass: UInt32, _ eventID: UInt32, _ ask: UInt8) -> Int32 {
    guard let target else { return Int32(AE.paramErr) }
    return AE.isSelf(AE.item(target)) ? 0 : Int32(AE.procNotFound)
}

/// Suspending an event changes nothing: its handler's reply is already
/// the sender's, as the sender is this process.
@c(_AESuspendTheCurrentEvent)
public func AESuspendTheCurrentEvent(_ event: UnsafeRawPointer?) -> Int16 { event == nil ? AE.paramErr : AE.noErr }

/// OSErr AEResumeTheCurrentEvent(const AppleEvent *, const AppleEvent *reply,
/// AEEventHandlerUPP dispatcher, SRefCon): kAENoDispatch (0) does nothing,
/// kAEUseStandardDispatch (-1) hands the event to its handler, another
/// procedure is called.
@c(_AEResumeTheCurrentEvent)
public func AEResumeTheCurrentEvent(_ event: UnsafeRawPointer?, _ reply: UnsafeMutableRawPointer?, _ dispatcher: UnsafeMutableRawPointer?,
                                    _ refCon: UnsafeMutableRawPointer?) -> Int16 {
    guard let event else { return AE.paramErr }
    guard let dispatcher else { return AE.noErr }
    if UInt(bitPattern: dispatcher) == UInt.max { return AE.dispatch(event, reply) }
    return unsafeBitCast(dispatcher, to: AE.EventHandler.self)(event, reply, refCon)
}

/// OSStatus AEPrintDescToHandle(const AEDesc *, Handle *): the descriptor
/// as text, NUL-terminated.
@c(_AEPrintDescToHandle)
public func AEPrintDescToHandle(_ desc: UnsafeRawPointer?, _ result: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let desc, let result else { return Int32(AE.paramErr) }
    let text = Array(AE.describe(AE.item(desc)).utf8) + [0]
    guard let handle = NewHandle(text.count) else { return -108 }   // memFullErr
    let block = handle.load(as: UnsafeMutableRawPointer.self)
    text.withUnsafeBytes { block.copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
    result.pointee = handle
    return 0
}

// MARK: - Handlers

/// OSErr AEInstallEventHandler(AEEventClass, AEEventID, AEEventHandlerUPP,
/// SRefCon, Boolean isSysHandler).
@c(_AEInstallEventHandler)
public func AEInstallEventHandler(_ eventClass: UInt32, _ eventID: UInt32, _ procedure: UnsafeMutableRawPointer?,
                                  _ refCon: UnsafeMutableRawPointer?, _ system: UInt8) -> Int16 {
    let handler = AE.Handler(eventClass: eventClass, eventID: eventID, procedure: procedure, refCon: refCon)
    AE.lock.withLock {
        if system != 0 {
            AE.systemHandlers.removeAll { $0.eventClass == eventClass && $0.eventID == eventID }
            AE.systemHandlers.append(handler)
        } else {
            AE.handlers.removeAll { $0.eventClass == eventClass && $0.eventID == eventID }
            AE.handlers.append(handler)
        }
    }
    return AE.noErr
}

@c(_AERemoveEventHandler)
public func AERemoveEventHandler(_ eventClass: UInt32, _ eventID: UInt32, _ procedure: UnsafeMutableRawPointer?, _ system: UInt8) -> Int16 {
    AE.lock.withLock {
        let matches: (AE.Handler) -> Bool = { $0.eventClass == eventClass && $0.eventID == eventID }
        let before = AE.handlers.count + AE.systemHandlers.count
        if system != 0 { AE.systemHandlers.removeAll(where: matches) } else { AE.handlers.removeAll(where: matches) }
        return AE.handlers.count + AE.systemHandlers.count < before ? AE.noErr : AE.handlerNotFound
    }
}

/// OSErr AEGetEventHandler(AEEventClass, AEEventID, AEEventHandlerUPP *,
/// SRefCon *, Boolean isSysHandler).
@c(_AEGetEventHandler)
public func AEGetEventHandler(_ eventClass: UInt32, _ eventID: UInt32, _ procedure: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
                              _ refCon: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, _ system: UInt8) -> Int16 {
    let found = AE.lock.withLock {
        (system != 0 ? AE.systemHandlers : AE.handlers).first { $0.eventClass == eventClass && $0.eventID == eventID }
    }
    guard let found else { return AE.handlerNotFound }
    procedure?.pointee = found.procedure
    refCon?.pointee = found.refCon
    return AE.noErr
}

/// Coercion handlers are kept by no one: the coercions there are are the
/// standard ones.
@c(_AEInstallCoercionHandler)
public func AEInstallCoercionHandler(_ fromType: UInt32, _ toType: UInt32, _ handler: UnsafeRawPointer?, _ refCon: UnsafeRawPointer?,
                                     _ fromTypeIsDesc: UInt8, _ system: UInt8) -> Int16 { AE.noErr }

/// Special handlers (the object callbacks' and pre-dispatch) aren't kept.
@c(_AEGetSpecialHandler)
public func AEGetSpecialHandler(_ functionClass: UInt32, _ handler: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, _ system: UInt8) -> Int16 {
    handler?.pointee = nil
    return AE.handlerNotFound
}

@c(_AERemoveSpecialHandler)
public func AERemoveSpecialHandler(_ functionClass: UInt32, _ handler: UnsafeRawPointer?, _ system: UInt8) -> Int16 { AE.noErr }

// MARK: - The object model

/// The Object Support Library is ready at once: AEResolve uses the
/// accessors installed, and the object callbacks aren't needed by it.
@c(_AEObjectInit) public func AEObjectInit() -> Int16 { AE.noErr }

/// OSErr AESetObjectCallbacks(OSLCompareUPP, OSLCountUPP, OSLDisposeTokenUPP,
/// OSLGetMarkTokenUPP, OSLMarkUPP, OSLAdjustMarksUPP, OSLGetErrDescUPP).
@c(_AESetObjectCallbacks)
public func AESetObjectCallbacks(_ compare: UnsafeRawPointer?, _ count: UnsafeRawPointer?, _ disposeToken: UnsafeRawPointer?,
                                 _ getMarkToken: UnsafeRawPointer?, _ mark: UnsafeRawPointer?, _ adjustMarks: UnsafeRawPointer?,
                                 _ getErrDesc: UnsafeRawPointer?) -> Int16 { AE.noErr }

/// OSErr AEInstallObjectAccessor(DescType desiredClass, DescType containerType,
/// OSLAccessorUPP, SRefCon, Boolean isSysHandler).
@c(_AEInstallObjectAccessor)
public func AEInstallObjectAccessor(_ desiredClass: UInt32, _ containerType: UInt32, _ accessor: UnsafeMutableRawPointer?,
                                    _ refCon: UnsafeMutableRawPointer?, _ system: UInt8) -> Int16 {
    AE.lock.withLock {
        AE.accessors.removeAll { $0.eventClass == desiredClass && $0.eventID == containerType }
        AE.accessors.append(AE.Handler(eventClass: desiredClass, eventID: containerType, procedure: accessor, refCon: refCon))
    }
    return AE.noErr
}

@c(_AEGetObjectAccessor)
public func AEGetObjectAccessor(_ desiredClass: UInt32, _ containerType: UInt32, _ accessor: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
                                _ refCon: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, _ system: UInt8) -> Int16 {
    let found = AE.lock.withLock { AE.accessors.first { $0.eventClass == desiredClass && $0.eventID == containerType } }
    guard let found else { return AE.accessorNotFound }
    accessor?.pointee = found.procedure
    refCon?.pointee = found.refCon
    return AE.noErr
}

/// OSErr AEResolve(const AEDesc *objectSpecifier, short callbackFlags, AEDesc *token):
/// resolves the specifier's container first (the application, a null
/// descriptor, at the top), then asks the application's accessor for the
/// desired class in a container of the token's type, falling back to
/// wildcard accessors as the Object Support Library does. Whose clauses
/// and marking callbacks aren't evaluated here: an accessor gets the
/// selection data as it is.
@c(_AEResolve)
public func AEResolve(_ specifier: UnsafeRawPointer?, _ flags: Int16, _ token: UnsafeMutableRawPointer?) -> Int16 {
    guard let specifier, let token else { return AE.paramErr }
    AE.set(token, AE.typeNull, AEValue())
    return AE.resolve(AE.item(specifier), into: token)
}

extension AE {
    typealias Accessor = @convention(c) (UInt32, UnsafeRawPointer?, UInt32, UInt32, UnsafeRawPointer?, UnsafeMutableRawPointer?,
                                         UnsafeMutableRawPointer?) -> Int16

    /// Runs `body` with a 12-byte AEDesc holding `item`, disposed after.
    static func withDesc<T>(_ item: AEItem, _ body: (UnsafeMutableRawPointer) -> T) -> T {
        var storage = (UInt32(0), UInt16(0), UInt16(0), UInt16(0), UInt16(0))
        return withUnsafeMutableBytes(of: &storage) { buffer in
            set(buffer.baseAddress!, item.type, item.value)
            defer { dispose(buffer.baseAddress!) }
            return body(buffer.baseAddress!)
        }
    }

    static func resolve(_ specifier: AEItem, into token: UnsafeMutableRawPointer) -> Int16 {
        if specifier.type == typeNull { return noErr }   // the application
        guard specifier.type == typeObjectSpecifier, specifier.value.keyed else { return -1727 }   // errAENotAnObjSpec
        func key(_ name: String) -> AEItem? { specifier.value.items.first { $0.keyword == code(name) } }
        let desiredClass = code(of: key("want")), form = code(of: key("form"))
        let container = key("from") ?? AEItem(keyword: 0, type: typeNull, value: AEValue())
        let selection = key("seld") ?? AEItem(keyword: 0, type: typeNull, value: AEValue())
        return withDesc(AEItem(keyword: 0, type: typeNull, value: AEValue())) { containerToken in
            let error = resolve(container, into: containerToken)
            guard error == noErr else { return error }
            let containerClass = type(containerToken)
            let accessor = lock.withLock {
                [(desiredClass, containerClass), (desiredClass, typeWildCard), (typeWildCard, containerClass), (typeWildCard, typeWildCard)]
                    .lazy.compactMap { pair in accessors.first { $0.eventClass == pair.0 && $0.eventID == pair.1 } }.first
            }
            guard let accessor, let procedure = accessor.procedure else { return accessorNotFound }
            return withDesc(selection) { selectionData in
                unsafeBitCast(procedure, to: Accessor.self)(desiredClass, containerToken, containerClass, form, selectionData, token,
                                                            accessor.refCon)
            }
        }
    }
}

/// OSErr CreateObjSpecifier(DescType desiredClass, AEDesc *container,
/// DescType keyForm, AEDesc *keyData, Boolean disposeInputs, AEDesc *):
/// a record of type 'obj ' with the four keys.
@c(_CreateObjSpecifier)
public func CreateObjSpecifier(_ desiredClass: UInt32, _ container: UnsafeMutableRawPointer?, _ keyForm: UInt32,
                               _ keyData: UnsafeMutableRawPointer?, _ disposeInputs: UInt8, _ result: UnsafeMutableRawPointer?) -> Int16 {
    guard let container, let keyData, let result else { return AE.paramErr }
    var specifier = AEValue(keyed: true)
    specifier.items = [AEItem(keyword: AE.code("want"), type: AE.typeType, value: AEValue(bytes: AE.number(desiredClass))),
                       AEItem(keyword: AE.code("from"), type: AE.type(container), value: AE.value(container)),
                       AEItem(keyword: AE.code("form"), type: AE.typeEnumerated, value: AEValue(bytes: AE.number(keyForm))),
                       AEItem(keyword: AE.code("seld"), type: AE.type(keyData), value: AE.value(keyData))]
    if disposeInputs != 0 {
        AE.dispose(container)
        AE.dispose(keyData)
    }
    AE.set(result, AE.typeObjectSpecifier, specifier)
    return AE.noErr
}

/// OSErr CreateRangeDescriptor(AEDesc *start, AEDesc *stop, Boolean disposeInputs, AEDesc *).
@c(_CreateRangeDescriptor)
public func CreateRangeDescriptor(_ start: UnsafeMutableRawPointer?, _ stop: UnsafeMutableRawPointer?, _ disposeInputs: UInt8,
                                  _ result: UnsafeMutableRawPointer?) -> Int16 {
    guard let start, let stop, let result else { return AE.paramErr }
    var range = AEValue(keyed: true)
    range.items = [AEItem(keyword: AE.code("star"), type: AE.type(start), value: AE.value(start)),
                   AEItem(keyword: AE.code("stop"), type: AE.type(stop), value: AE.value(stop))]
    if disposeInputs != 0 {
        AE.dispose(start)
        AE.dispose(stop)
    }
    AE.set(result, AE.typeRangeDescriptor, range)
    return AE.noErr
}
#endif

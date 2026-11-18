import CPerryFoundation
import FoundationEssentials
import Glibc
import PerryObjCInterop

// NSArchiver and NSUnarchiver: NeXTSTEP's typedstream, the archives before
// keyed ones. A stream is a header ("streamtyped", little-endian, and the
// system version), then groups of values, each led by its type encoding.
// An object is written once, as its class chain (each class with its
// version, leaf first) and the groups its -encodeWithCoder: wrote, then an
// end marker; after that by number. Objects, classes and C strings share
// one numbering; type encodings, class names and selectors are shared
// strings with their own. Property lists' classes are written and read
// here, in the layouts Foundation gives them (strings as UTF-8 bytes,
// arrays as a count and their objects, numbers as their type and value);
// other objects code themselves, through -encodeWithCoder: and
// -initWithCoder: with the archiver or unarchiver as the coder.

private enum Tag {
    static let integer2: UInt8 = 0x81, integer4: UInt8 = 0x82, floating: UInt8 = 0x83
    static let new: UInt8 = 0x84, null: UInt8 = 0x85, endOfObject: UInt8 = 0x86
    /// References are numbered from here (-110), just above the tags.
    static let firstReference = -110
}

/// Splitting type encodings: "@i{CGPoint=dd}" is "@", "i" and the
/// structure.
enum ArchiveTypes {
    static func end(_ text: [UInt8], _ start: Int) -> Int {
        guard start < text.count else { return start }
        switch text[start] {
        case UInt8(ascii: "["):
            var index = start + 1
            while index < text.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(text[index]) { index += 1 }
            index = end(text, index)
            return min(index + 1, text.count)
        case UInt8(ascii: "{"), UInt8(ascii: "("):
            var depth = 0, index = start
            while index < text.count {
                if text[index] == UInt8(ascii: "{") || text[index] == UInt8(ascii: "(") { depth += 1 }
                if text[index] == UInt8(ascii: "}") || text[index] == UInt8(ascii: ")") {
                    depth -= 1
                    if depth == 0 { return index + 1 }
                }
                index += 1
            }
            return index
        case UInt8(ascii: "^"):
            return end(text, start + 1)
        case UInt8(ascii: "r"), UInt8(ascii: "n"), UInt8(ascii: "N"), UInt8(ascii: "o"), UInt8(ascii: "O"), UInt8(ascii: "R"), UInt8(ascii: "V"):
            return end(text, start + 1)
        default:
            return start + 1
        }
    }

    static func split(_ text: [UInt8]) -> [[UInt8]] {
        var types: [[UInt8]] = [], index = 0
        while index < text.count {
            let next = end(text, index)
            guard next > index else { break }
            types.append(Array(text[index..<next]))
            index = next
        }
        return types
    }

    /// The type without its qualifiers ("r*" is "*").
    static func bare(_ type: [UInt8]) -> [UInt8] {
        Array(type.drop { "rnNoORV".utf8.contains($0) })
    }

    static func layout(_ type: [UInt8]) -> (size: Int, alignment: Int) {
        var parser = TypeEncoding.Parser(bytes: type)
        return parser.type().map { ($0.0, max($0.1, 1)) } ?? (0, 1)
    }

    /// An array type's count and element: "[36c]" is 36 and "c".
    static func array(_ type: [UInt8]) -> (Int, [UInt8]) {
        let body = Array(type.dropFirst().dropLast())
        let digits = body.prefix { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }
        return (Int(String(decoding: digits, as: UTF8.self)) ?? 0, Array(body.dropFirst(digits.count)))
    }

    /// A structure's fields: "{CGPoint=dd}" has "d" and "d".
    static func fields(_ type: [UInt8]) -> [[UInt8]] {
        var body = Array(type.dropFirst().dropLast())
        if let equals = body.firstIndex(of: UInt8(ascii: "=")) { body = Array(body[(equals + 1)...]) }
        return split(body)
    }

    static func align(_ value: Int, _ alignment: Int) -> Int { (value + alignment - 1) / alignment * alignment }
}

/// The property list classes, as they are archived.
private enum ArchivedClasses {
    static func chain(_ names: [(String, Int)]) -> [(String, Int)] { names + [("NSObject", 0)] }
    static let string = chain([("NSString", 1)])
    static let mutableString = chain([("NSMutableString", 1), ("NSString", 1)])
    static let array = chain([("NSArray", 0)])
    static let mutableArray = chain([("NSMutableArray", 0), ("NSArray", 0)])
    static let dictionary = chain([("NSDictionary", 0)])
    static let mutableDictionary = chain([("NSMutableDictionary", 0), ("NSDictionary", 0)])
    static let set = chain([("NSSet", 0)])
    static let mutableSet = chain([("NSMutableSet", 0), ("NSSet", 0)])
    static let number = chain([("NSNumber", 0), ("NSValue", 0)])
    static let data = chain([("NSData", 0)])
    static let mutableData = chain([("NSMutableData", 0), ("NSData", 0)])
    static let date = chain([("NSDate", 0)])
    static let null = chain([("NSNull", 0)])
}

// MARK: - Writing

final class ArchiverState {
    var bytes: [UInt8] = [4, 11] + Array("streamtyped".utf8)
    var strings: [[UInt8]: Int] = [:]
    var shared = 0
    var objects: [UInt: Int] = [:]
    var classes: [String: Int] = [:]
    var classNames: [String: String] = [:]

    init() { integer(1000) }

    func byte(_ value: UInt8) { bytes.append(value) }

    func integer(_ value: Int64) {
        if value >= -110 && value <= 127 {
            bytes.append(UInt8(bitPattern: Int8(value)))
        } else if value >= Int64(Int16.min) && value <= Int64(Int16.max) {
            bytes.append(Tag.integer2)
            withUnsafeBytes(of: Int16(value).littleEndian) { bytes += $0 }
        } else {
            bytes.append(Tag.integer4)
            withUnsafeBytes(of: Int32(truncatingIfNeeded: value).littleEndian) { bytes += $0 }
        }
    }

    func reference(_ number: Int) { integer(Int64(number + Tag.firstReference)) }

    func unshared(_ text: [UInt8]) {
        integer(Int64(text.count))
        bytes += text
    }

    func sharedString(_ text: [UInt8]) {
        if let index = strings[text] { return reference(index) }
        strings[text] = strings.count
        byte(Tag.new)
        unshared(text)
    }

    func real(_ value: Double, double: Bool) {
        byte(Tag.floating)
        if double {
            withUnsafeBytes(of: value.bitPattern.littleEndian) { bytes += $0 }
        } else {
            withUnsafeBytes(of: Float(value).bitPattern.littleEndian) { bytes += $0 }
        }
    }

    /// A class chain, leaf first: classes written before by number.
    func classChain(_ chain: [(String, Int)]) {
        var literal: [String] = []
        for (name, version) in chain {
            if let number = classes[name] {
                reference(number)
                for name in literal { classes[name] = shared; shared += 1 }
                return
            }
            byte(Tag.new)
            sharedString(Array(name.utf8))
            integer(Int64(version))
            literal.append(name)
        }
        byte(Tag.null)
        for name in literal { classes[name] = shared; shared += 1 }
    }

    func group(_ type: String, _ body: () -> Void) {
        sharedString(Array(type.utf8))
        body()
    }

    /// An object: nil, by number, or written out.
    func object(_ object: id?, coder: id) {
        guard let object else { return byte(Tag.null) }
        if let number = objects[UInt(bitPattern: object)] { return reference(number) }
        objects[UInt(bitPattern: object)] = shared
        shared += 1
        byte(Tag.new)
        writeContents(object, coder: coder)
        byte(Tag.endOfObject)
    }

    private func writeContents(_ object: id, coder: id) {
        func kind(_ classes: [Class?]) -> Bool { classes.contains { $0.map { ObjC.isKind(object, of: $0) } ?? false } }
        if kind([MutableStrings.mutableClass]) || kind([Strings.stringClass, Strings.constantClass]) {
            classChain(kind([MutableStrings.mutableClass]) ? ArchivedClasses.mutableString : ArchivedClasses.string)
            group("+") { unshared(Array((Strings.value(of: object) ?? "").utf8)) }
        } else if kind([Arrays.arrayClass, Arrays.constantClass]) {
            let elements = Arrays.elements(object)
            classChain(kind([Arrays.mutableClass]) ? ArchivedClasses.mutableArray : ArchivedClasses.array)
            group("i") { integer(Int64(elements.count)) }
            for element in elements { group("@") { self.object(element, coder: coder) } }
        } else if kind([Dictionaries.dictionaryClass, Dictionaries.constantClass]) {
            let keys = Arrays.elements(ObjC.send(object, ObjC.selector("allKeys")))
            classChain(kind([Dictionaries.mutableClass]) ? ArchivedClasses.mutableDictionary : ArchivedClasses.dictionary)
            group("i") { integer(Int64(keys.count)) }
            for key in keys {
                group("@") { self.object(key, coder: coder) }
                group("@") { self.object(Dictionaries.value(object, for: key), coder: coder) }
            }
        } else if kind([Sets.setClass]) {
            let members = Sets.elements(object)
            classChain(kind([Sets.mutableClass]) ? ArchivedClasses.mutableSet : ArchivedClasses.set)
            group("I") { integer(Int64(members.count)) }
            for member in members { group("@") { self.object(member, coder: coder) } }
        } else if kind([Numbers.numberClass, Numbers.constantIntegerClass, Numbers.constantDoubleClass, Numbers.constantFloatClass,
                        Numbers.booleanClass, Numbers.keptClass]) {
            classChain(ArchivedClasses.number)
            let type: String, write: () -> Void
            switch Numbers.storage(object).value {
            case .signed(let value): (type, write) = ("q", { self.integer(value) })
            case .unsigned(let value): (type, write) = ("Q", { self.integer(Int64(bitPattern: value)) })
            case .double(let value): (type, write) = ("d", { self.real(value, double: true) })
            case .bool(let flag): (type, write) = ("c", { self.byte(flag ? 1 : 0) })
            }
            group("*") { cString(Array(type.utf8)) }
            group(type, write)
        } else if kind([DataObjects.dataClass]) {
            let data = DataObjects.data(object)
            classChain(kind([DataObjects.mutableClass]) ? ArchivedClasses.mutableData : ArchivedClasses.data)
            group("i") { integer(Int64(data.count)) }
            group("[\(data.count)c]") { bytes += data }
        } else if kind([Dates.dateClass]) {
            classChain(ArchivedClasses.date)
            group("d") { real(Dates.interval(object), double: true) }
        } else if kind([Nulls.nullClass]) {
            classChain(ArchivedClasses.null)
        } else {
            // Any other object codes itself, as its class for archiving
            // has it.
            let cls = ObjC.send(object, ObjC.selector("classForArchiver")) ?? ObjC.objectGetClass(object).map { UnsafeMutableRawPointer($0) }
            var chain: [(String, Int)] = []
            var current = cls?.assumingMemoryBound(to: perry_class_storage.self)
            while let c = current {
                let name = ObjC.className(UnsafeMutableRawPointer(c))
                let version = ObjC.sendUInt(UnsafeMutableRawPointer(c), ObjC.selector("version"))
                chain.append((classNames[name] ?? name, Int(version)))
                current = c.pointee.superclass
            }
            classChain(chain)
            _ = ObjC.send(object, ObjC.selector("encodeWithCoder:"), coder)
        }
    }

    func cString(_ text: [UInt8]?) {
        guard let text else { return byte(Tag.null) }
        byte(Tag.new)
        sharedString(text)
        shared += 1
    }

    /// A value of `type` at `pointer`, as -encodeValueOfObjCType:at: writes
    /// it.
    func value(_ type: [UInt8], at pointer: UnsafeRawPointer, coder: id) {
        let type = ArchiveTypes.bare(type)
        guard let first = type.first else { return }
        switch Character(UnicodeScalar(first)) {
        case "c", "B", "C": byte(pointer.load(as: UInt8.self))
        case "s": integer(Int64(pointer.loadUnaligned(as: Int16.self)))
        case "S": integer(Int64(pointer.loadUnaligned(as: UInt16.self)))
        case "i", "l": integer(Int64(pointer.loadUnaligned(as: Int32.self)))
        case "I", "L": integer(Int64(pointer.loadUnaligned(as: UInt32.self)))
        case "q": integer(pointer.loadUnaligned(as: Int64.self))
        case "Q": integer(Int64(bitPattern: pointer.loadUnaligned(as: UInt64.self)))
        case "f": real(Double(pointer.loadUnaligned(as: Float.self)), double: false)
        case "d": real(pointer.loadUnaligned(as: Double.self), double: true)
        case "*":
            let string = pointer.loadUnaligned(as: UnsafePointer<CChar>?.self)
            cString(string.map { Array(UnsafeRawBufferPointer(start: $0, count: strlen($0))) })
        case "@": object(pointer.loadUnaligned(as: id?.self), coder: coder)
        case "#":
            if let cls = pointer.loadUnaligned(as: id?.self) {
                var chain: [(String, Int)] = []
                var current: Class? = cls.assumingMemoryBound(to: perry_class_storage.self)
                while let c = current {
                    chain.append((ObjC.className(UnsafeMutableRawPointer(c)), Int(ObjC.sendUInt(UnsafeMutableRawPointer(c), ObjC.selector("version")))))
                    current = c.pointee.superclass
                }
                classChain(chain)
            } else {
                byte(Tag.null)
            }
        case ":":
            if let selector = pointer.loadUnaligned(as: UnsafePointer<CChar>?.self) {
                sharedString(Array(UnsafeRawBufferPointer(start: selector, count: strlen(selector))))
            } else {
                byte(Tag.null)
            }
        case "[":
            let (count, element) = ArchiveTypes.array(type)
            if element == [UInt8(ascii: "c")] || element == [UInt8(ascii: "C")] {
                bytes += UnsafeRawBufferPointer(start: pointer, count: count)
            } else {
                let size = ArchiveTypes.layout(element).size
                for index in 0..<count { value(element, at: pointer + index * size, coder: coder) }
            }
        case "{":
            var offset = 0
            for field in ArchiveTypes.fields(type) {
                let (size, alignment) = ArchiveTypes.layout(field)
                offset = ArchiveTypes.align(offset, alignment)
                value(field, at: pointer + offset, coder: coder)
                offset += size
            }
        default:
            break
        }
    }
}

enum LegacyArchivers {
    nonisolated(unsafe) static var archiverClass: Class!
    static func state(_ object: id?) -> ArchiverState? { Storage.get(object, as: ArchiverState.self) }

    static func archive(_ root: id?) -> Data {
        let state = ArchiverState()
        guard let archiver = Storage.allocate(UnsafeMutableRawPointer(archiverClass)) else { return Data() }
        Storage.set(archiver, state)
        state.group("@") { state.object(root, coder: archiver) }
        ObjC.release(archiver)
        return Data(state.bytes)
    }
}

@ObjCClass("NSArchiver")
public final class NSArchiver: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        LegacyArchivers.archiverClass = cls.storage
    }

    private var state: ArchiverState? { LegacyArchivers.state(objcObject) }
    /// The data being written to, when the archiver was made for one.
    private var target: id? { Storage.get(objcObject, as: ArchiverTarget.self)?.data }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: LegacyArchivers.archiverClass)
    }

    @ObjCClassMethod("archivedDataWithRootObject:")
    static func archivedData(rootObject: ObjCObject?) -> ObjCObject? {
        DataObjects.autoreleased(LegacyArchivers.archive(rootObject?.id)).map(ObjCObject.init)
    }

    @ObjCClassMethod("archiveRootObject:toFile:")
    static func archiveRootObject(_ root: ObjCObject?, toFile path: String) -> Bool {
        (try? LegacyArchivers.archive(root?.id).write(to: URL(fileURLWithPath: path))) != nil
    }

    @ObjCMethod("initForWritingWithMutableData:")
    func initialize(forWritingWith data: ObjCObject?) -> UnsafeMutableRawPointer? {
        Storage.set(objcObject, ArchiverTarget(state: ArchiverState(), data: data?.id))
        return objcObject
    }

    /// The archive so far.
    @ObjCMethod("archiverData")
    func archiverData() -> ObjCObject? {
        guard let state = state ?? Storage.get(objcObject, as: ArchiverTarget.self)?.state else { return nil }
        return DataObjects.autoreleased(Data(state.bytes)).map(ObjCObject.init)
    }

    private var writing: ArchiverState? { state ?? Storage.get(objcObject, as: ArchiverTarget.self)?.state }

    /// Writes the new bytes into the data the archiver was made for.
    private func flush() {
        guard let holder = Storage.get(objcObject, as: ArchiverTarget.self), let data = holder.data else { return }
        let bytes = holder.state.bytes
        bytes.withUnsafeBytes { buffer in
            typealias Length = @convention(c) (id?, SEL, UInt) -> Void
            typealias Append = @convention(c) (id?, SEL, UnsafeRawPointer?, UInt) -> Void
            unsafeBitCast(ObjC.msgSend!, to: Length.self)(data, ObjC.selector("setLength:"), 0)
            unsafeBitCast(ObjC.msgSend!, to: Append.self)(data, ObjC.selector("appendBytes:length:"), buffer.baseAddress, UInt(buffer.count))
        }
    }

    @ObjCMethod("encodeRootObject:")
    func encodeRootObject(_ object: ObjCObject?) { encodeObject(object) }

    @ObjCMethod("encodeObject:")
    func encodeObject(_ object: ObjCObject?) {
        guard let state = writing else { return }
        state.group("@") { state.object(object?.id, coder: objcObject) }
        flush()
    }

    @ObjCMethod("encodeConditionalObject:") func encodeConditionalObject(_ object: ObjCObject?) { encodeObject(object) }
    @ObjCMethod("encodeBycopyObject:") func encodeBycopyObject(_ object: ObjCObject?) { encodeObject(object) }
    @ObjCMethod("encodeByrefObject:") func encodeByrefObject(_ object: ObjCObject?) { encodeObject(object) }

    @ObjCMethod("encodeValueOfObjCType:at:")
    func encodeValue(ofObjCType type: UnsafePointer<CChar>?, at address: UnsafeRawPointer?) {
        guard let state = writing, let type, let address else { return }
        let text = Array(UnsafeRawBufferPointer(start: type, count: strlen(type)))
        state.group(String(decoding: text, as: UTF8.self)) { state.value(text, at: address, coder: objcObject) }
        flush()
    }

    @ObjCMethod("encodeArrayOfObjCType:count:at:")
    func encodeArray(ofObjCType type: UnsafePointer<CChar>?, count: UInt, at address: UnsafeRawPointer?) {
        guard let type else { return }
        let arrayType = "[\(count)\(String(cString: type))]"
        arrayType.withCString { encodeValue(ofObjCType: $0, at: address) }
    }

    /// Bytes: their count, then the bytes, as an array of chars.
    @ObjCMethod("encodeBytes:length:")
    func encodeBytes(_ address: UnsafeRawPointer?, length: UInt) {
        var count = Int32(truncatingIfNeeded: length)
        "i".withCString { encodeValue(ofObjCType: $0, at: &count) }
        if let address { "c".withCString { encodeArray(ofObjCType: $0, count: length, at: address) } }
    }

    @ObjCMethod("encodeDataObject:")
    func encodeDataObject(_ data: ObjCObject?) {
        let bytes = DataObjects.data(data?.id)
        bytes.withUnsafeBytes { encodeBytes($0.baseAddress, length: UInt($0.count)) }
    }




    @ObjCMethod("encodeClassName:intoClassName:")
    func encodeClassName(_ trueName: String, into name: String) { writing?.classNames[trueName] = name }
    @ObjCMethod("classNameEncodedForTrueClassName:")
    func classNameEncoded(forTrueClassName name: String) -> String? { writing?.classNames[name] }
    @ObjCMethod("replaceObject:withObject:") func replaceObject(_ object: ObjCObject?, with replacement: ObjCObject?) {}
    @ObjCMethod("allowsKeyedCoding") func allowsKeyedCoding() -> Bool { false }
    @ObjCMethod("systemVersion") func systemVersion() -> UInt32 { 1000 }
    @ObjCMethod("versionForClassName:")
    func version(forClassName name: String) -> Int {
        Int(ObjC.sendUInt(name.withCString { ObjC.getClass($0) }.map { UnsafeMutableRawPointer($0) }, ObjC.selector("version")))
    }
}

final class ArchiverTarget {
    let state: ArchiverState
    let data: id?
    init(state: ArchiverState, data: id?) {
        self.state = state
        self.data = data.map { ObjC.retain($0)! }
    }
    deinit { if let data { ObjC.release(data) } }
}

// MARK: - Reading

final class UnarchiverState {
    enum Shared {
        case object(id?)
        case classChain([(String, Int)])
        case cString(UnsafeMutablePointer<CChar>)
    }

    let bytes: [UInt8]
    var position = 0
    var bigEndian = false
    var systemVersion: UInt32 = 0
    var strings: [[UInt8]] = []
    var shared: [Shared] = []
    /// The types left in the group being read.
    var pending: [[UInt8]] = []
    var versions: [String: Int] = [:]
    var classNames: [String: String] = [:]
    var failed = false

    init?(_ bytes: [UInt8]) {
        guard bytes.count > 13, bytes[0] == 4, bytes[1] == 11 else { return nil }
        let signature = String(decoding: bytes[2..<13], as: UTF8.self)
        guard signature == "typedstream" || signature == "streamtyped" else { return nil }
        self.bytes = bytes
        bigEndian = signature == "typedstream"
        position = 13
        guard let head = head(), let version = integer(head, signed: false) else { return nil }
        systemVersion = UInt32(truncatingIfNeeded: version)
    }

    deinit {
        for entry in shared {
            switch entry {
            case .object(let object): if let object { ObjC.release(object) }
            case .cString(let text): free(text)
            case .classChain: break
            }
        }
    }

    var isAtEnd: Bool { pending.isEmpty && position >= bytes.count }

    func fail(_ reason: String) -> Never {
        Exceptions.raise(name: "NSArchiverArchiveInconsistencyException", reason: "*** -[NSUnarchiver]: \(reason)")
    }

    func take(_ count: Int) -> ArraySlice<UInt8> {
        guard count >= 0, position + count <= bytes.count else { fail("archive is cut short") }
        defer { position += count }
        return bytes[position..<position + count]
    }

    func head() -> Int8? {
        guard position < bytes.count else { return nil }
        defer { position += 1 }
        return Int8(bitPattern: bytes[position])
    }

    func peek() -> UInt8? { position < bytes.count ? bytes[position] : nil }

    func word(_ count: Int) -> UInt64 {
        let raw = take(count)
        let ordered = bigEndian ? Array(raw) : raw.reversed()
        return ordered.reduce(0) { $0 << 8 | UInt64($1) }
    }

    func integer(_ head: Int8, signed: Bool) -> Int64? {
        switch UInt8(bitPattern: head) {
        case Tag.integer2:
            let raw = word(2)
            return signed ? Int64(Int16(truncatingIfNeeded: raw)) : Int64(raw)
        case Tag.integer4:
            let raw = word(4)
            return signed ? Int64(Int32(truncatingIfNeeded: raw)) : Int64(raw)
        case 0x80...0x91:
            return nil
        default:
            return signed ? Int64(head) : Int64(UInt8(bitPattern: head))
        }
    }

    func integer(signed: Bool) -> Int64 {
        guard let head = head(), let value = integer(head, signed: signed) else { fail("an integer was expected") }
        return value
    }

    func real(double: Bool) -> Double {
        guard let head = head() else { fail("a number was expected") }
        guard UInt8(bitPattern: head) == Tag.floating else { return Double(integer(head, signed: true) ?? 0) }
        let raw = word(double ? 8 : 4)
        return double ? Double(bitPattern: raw) : Double(Float(bitPattern: UInt32(raw)))
    }

    func unshared(_ head: Int8) -> [UInt8]? {
        if UInt8(bitPattern: head) == Tag.null { return nil }
        guard let count = integer(head, signed: false) else { fail("a string was expected") }
        return Array(take(Int(count)))
    }

    func sharedString(_ head: Int8) -> [UInt8]? {
        switch UInt8(bitPattern: head) {
        case Tag.null:
            return nil
        case Tag.new:
            guard let next = self.head(), let string = unshared(next) else { fail("a shared string was expected") }
            strings.append(string)
            return string
        default:
            guard let number = integer(head, signed: true) else { fail("a shared string was expected") }
            let index = Int(number) - Tag.firstReference
            guard strings.indices.contains(index) else { fail("shared string \(index) is not in the archive") }
            return strings[index]
        }
    }

    func reference(_ head: Int8) -> Shared {
        guard let number = integer(head, signed: true) else { fail("a reference was expected") }
        let index = Int(number) - Tag.firstReference
        guard shared.indices.contains(index) else { fail("object \(index) is not in the archive") }
        return shared[index]
    }

    func classChain(_ first: Int8) -> [(String, Int)]? {
        var head = first
        var literal: [(String, Int)] = []
        while UInt8(bitPattern: head) == Tag.new {
            guard let nameHead = self.head(), let name = sharedString(nameHead), let next = self.head() else { fail("a class was expected") }
            let version = Int(integer(next, signed: true) ?? 0)
            let className = String(decoding: name, as: UTF8.self)
            literal.append((className, version))
            versions[className] = version
            guard let following = self.head() else { fail("a class was expected") }
            head = following
        }
        var rest: [(String, Int)] = []
        if UInt8(bitPattern: head) != Tag.null {
            guard case .classChain(let chain) = reference(head) else { fail("a class was expected") }
            rest = chain
        }
        let full = literal + rest
        for index in literal.indices { shared.append(.classChain(Array(full[index...]))) }
        return full.isEmpty ? nil : full
    }

    // MARK: Groups

    /// The next type of the group being read, reading the next group's
    /// encoding when it is done.
    func nextType() -> [UInt8] {
        if pending.isEmpty {
            guard let head = head(), let encoding = sharedString(head), !encoding.isEmpty else { fail("a type was expected") }
            pending = ArchiveTypes.split(encoding)
        }
        return pending.removeFirst()
    }

    /// Reads a value of the next type into `pointer`, `expected` being the
    /// type the reader asks for. Objects come back retained.
    func value(expected: [UInt8], into pointer: UnsafeMutableRawPointer, coder: id) {
        let type = nextType()
        guard ArchiveTypes.bare(type) == ArchiveTypes.bare(expected) else {
            fail("expected '\(String(decoding: expected, as: UTF8.self))' and got '\(String(decoding: type, as: UTF8.self))'")
        }
        read(type, into: pointer, coder: coder)
    }

    func read(_ type: [UInt8], into pointer: UnsafeMutableRawPointer, coder: id) {
        let type = ArchiveTypes.bare(type)
        guard let first = type.first else { return }
        switch Character(UnicodeScalar(first)) {
        case "c", "B", "C": pointer.storeBytes(of: take(1).first!, as: UInt8.self)
        case "s": pointer.storeBytes(of: Int16(truncatingIfNeeded: integer(signed: true)), as: Int16.self)
        case "S": pointer.storeBytes(of: UInt16(truncatingIfNeeded: integer(signed: false)), as: UInt16.self)
        case "i", "l": pointer.storeBytes(of: Int32(truncatingIfNeeded: integer(signed: true)), as: Int32.self)
        case "I", "L": pointer.storeBytes(of: UInt32(truncatingIfNeeded: integer(signed: false)), as: UInt32.self)
        case "q": pointer.storeBytes(of: integer(signed: true), as: Int64.self)
        case "Q": pointer.storeBytes(of: UInt64(bitPattern: integer(signed: false)), as: UInt64.self)
        case "f": pointer.storeBytes(of: Float(real(double: false)), as: Float.self)
        case "d": pointer.storeBytes(of: real(double: true), as: Double.self)
        case "*": pointer.storeBytes(of: cString(), as: UnsafeMutablePointer<CChar>?.self)
        case "@":
            let object = self.object(coder: coder)
            pointer.storeBytes(of: object.flatMap { ObjC.retain($0) }, as: id?.self)
        case "#":
            guard let head = head() else { fail("a class was expected") }
            var cls: id?
            if UInt8(bitPattern: head) != Tag.null {
                let chain: [(String, Int)]?
                if UInt8(bitPattern: head) == Tag.new {
                    chain = classChain(head)
                } else if case .classChain(let known) = reference(head) {
                    chain = known
                } else {
                    chain = nil
                }
                cls = chain?.first.flatMap { lookUp($0.0) }
            }
            pointer.storeBytes(of: cls, as: id?.self)
        case ":":
            guard let head = head() else { fail("a selector was expected") }
            let name = sharedString(head)
            pointer.storeBytes(of: name.map { name in String(decoding: name, as: UTF8.self).withCString { ObjC.registerName($0) } },
                               as: UnsafePointer<CChar>?.self)
        case "+":
            guard let head = head() else { fail("bytes were expected") }
            _ = unshared(head)
        case "[":
            let (count, element) = ArchiveTypes.array(type)
            if element == [UInt8(ascii: "c")] || element == [UInt8(ascii: "C")] {
                take(count).withUnsafeBytes { pointer.copyMemory(from: $0.baseAddress!, byteCount: count) }
            } else {
                let size = ArchiveTypes.layout(element).size
                for index in 0..<count { read(element, into: pointer + index * size, coder: coder) }
            }
        case "{":
            var offset = 0
            for field in ArchiveTypes.fields(type) {
                let (size, alignment) = ArchiveTypes.layout(field)
                offset = ArchiveTypes.align(offset, alignment)
                read(field, into: pointer + offset, coder: coder)
                offset += size
            }
        default:
            fail("type '\(String(decoding: type, as: UTF8.self))' isn't known")
        }
    }

    /// A C string, which the unarchiver keeps.
    func cString() -> UnsafeMutablePointer<CChar>? {
        guard let head = head() else { fail("a C string was expected") }
        switch UInt8(bitPattern: head) {
        case Tag.null:
            return nil
        case Tag.new:
            guard let next = self.head(), let raw = sharedString(next) else { fail("a C string was expected") }
            let copy = strdup(String(decoding: raw, as: UTF8.self))!
            shared.append(.cString(copy))
            return copy
        default:
            guard case .cString(let text) = reference(head) else { fail("a C string was expected") }
            return text
        }
    }

    func lookUp(_ name: String) -> id? {
        let mapped = classNames[name] ?? Unarchivers.legacyClassNames[name] ?? name
        return mapped.withCString { ObjC.getClass($0) }.map { UnsafeMutableRawPointer($0) }
    }

    // MARK: Objects

    /// The next object, not retained for the caller: nil, one read before,
    /// or read now (and kept by the unarchiver).
    func object(coder: id) -> id? {
        guard let head = head() else { fail("an object was expected") }
        switch UInt8(bitPattern: head) {
        case Tag.null:
            return nil
        case Tag.new:
            let index = shared.count
            shared.append(.object(nil))
            guard let classHead = self.head(), let chain = classChain(classHead) else { fail("an object's class was expected") }
            let object = contents(chain, coder: coder)
            if let object { shared[index] = .object(object) }
            // Whatever the object's coding left unread.
            let saved = pending
            pending = []
            while let next = peek(), next != Tag.endOfObject {
                let type = nextType()
                skip(type, coder: coder)
                while !pending.isEmpty { skip(nextType(), coder: coder) }
            }
            pending = saved
            _ = self.head()
            return object
        default:
            guard case .object(let object) = reference(head) else { fail("an object was expected") }
            return object
        }
    }

    func skip(_ type: [UInt8], coder: id) {
        let (size, alignment) = ArchiveTypes.layout(ArchiveTypes.bare(type))
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: max(size, 16), alignment: max(alignment, 16))
        defer { buffer.deallocate() }
        read(type, into: buffer, coder: coder)
        if ArchiveTypes.bare(type).first == UInt8(ascii: "@"), let object = buffer.load(as: id?.self) { ObjC.release(object) }
    }

    /// An object's contents, retained: a property list's read here, any
    /// other's by its class's -initWithCoder:.
    private func contents(_ chain: [(String, Int)], coder: id) -> id? {
        let name = chain[0].0
        func readInteger() -> Int {
            let type = nextType()
            var value: Int64 = 0
            let bare = ArchiveTypes.bare(type)
            withUnsafeMutableBytes(of: &value) { read(bare, into: $0.baseAddress!, coder: coder) }
            switch bare.first {
            case UInt8(ascii: "i"), UInt8(ascii: "l"): return Int(Int32(truncatingIfNeeded: value))
            case UInt8(ascii: "I"), UInt8(ascii: "L"): return Int(UInt32(truncatingIfNeeded: value))
            default: return Int(value)
            }
        }
        func readObject() -> id? {
            let type = nextType()
            guard ArchiveTypes.bare(type) == [UInt8(ascii: "@")] else { fail("an object was expected") }
            return object(coder: coder)
        }
        switch name {
        case "NSString", "NSMutableString":
            guard ArchiveTypes.bare(nextType()) == [UInt8(ascii: "+")], let head = head() else { fail("a string was expected") }
            let text = String(decoding: unshared(head) ?? [], as: UTF8.self)
            return name == "NSString" ? Strings.make(text) : ObjC.retain(Strings.autoreleased(text, of: UnsafeMutableRawPointer(MutableStrings.mutableClass)))
        case "NSArray", "NSMutableArray":
            let count = readInteger()
            let elements = (0..<max(count, 0)).compactMap { _ in readObject() }
            return Arrays.make(elements, cls: name == "NSMutableArray" ? UnsafeMutableRawPointer(Arrays.mutableClass) : nil)
        case "NSDictionary", "NSMutableDictionary":
            let count = readInteger()
            var entries: [(key: id, value: id)] = []
            for _ in 0..<max(count, 0) {
                let key = readObject(), value = readObject()
                if let key, let value { entries.append((key, value)) }
            }
            return Dictionaries.make(entries, cls: name == "NSMutableDictionary" ? UnsafeMutableRawPointer(Dictionaries.mutableClass) : nil)
        case "NSSet", "NSMutableSet":
            let count = readInteger()
            let members = (0..<max(count, 0)).compactMap { _ in readObject() }
            return Sets.make(members, cls: name == "NSMutableSet" ? UnsafeMutableRawPointer(Sets.mutableClass) : nil)
        case "NSNumber":
            guard ArchiveTypes.bare(nextType()) == [UInt8(ascii: "*")], let type = cString() else { fail("a number's type was expected") }
            let encoding = Array(UnsafeRawBufferPointer(start: type, count: strlen(type)))
            let valueType = nextType()
            var raw = [UInt8](repeating: 0, count: 16)
            raw.withUnsafeMutableBytes { read(valueType, into: $0.baseAddress!, coder: coder) }
            let value: NumberStorage.Value
            switch encoding.first.map({ Character(UnicodeScalar($0)) }) {
            case "f": value = .double(Double(raw.withUnsafeBytes { $0.load(as: Float.self) }))
            case "d": value = .double(raw.withUnsafeBytes { $0.load(as: Double.self) })
            case "c", "B": value = .bool(raw[0] != 0)
            case "C": value = .signed(Int64(raw[0]))
            case "s": value = .signed(Int64(raw.withUnsafeBytes { $0.load(as: Int16.self) }))
            case "S": value = .signed(Int64(raw.withUnsafeBytes { $0.load(as: UInt16.self) }))
            case "i", "l": value = .signed(Int64(raw.withUnsafeBytes { $0.load(as: Int32.self) }))
            case "I", "L": value = .signed(Int64(raw.withUnsafeBytes { $0.load(as: UInt32.self) }))
            case "Q": value = .unsigned(raw.withUnsafeBytes { $0.load(as: UInt64.self) })
            default: value = .signed(raw.withUnsafeBytes { $0.load(as: Int64.self) })
            }
            return Numbers.make(nil, value).flatMap { ObjC.retain($0) }
        case "NSData", "NSMutableData":
            let count = readInteger()
            let type = nextType()
            var data = Data(count: max(count, 0))
            if count > 0 { data.withUnsafeMutableBytes { read(type, into: $0.baseAddress!, coder: coder) } } else { skip(type, coder: coder) }
            return DataObjects.make(DataStorage(data), cls: name == "NSMutableData" ? UnsafeMutableRawPointer(DataObjects.mutableClass) : nil)
        case "NSDate":
            var interval = 0.0
            withUnsafeMutableBytes(of: &interval) { read(ArchiveTypes.bare(nextType()), into: $0.baseAddress!, coder: coder) }
            return Dates.autoreleased(interval).flatMap { ObjC.retain($0) }
        case "NSNull":
            return ObjC.retain(Nulls.null)
        default:
            guard let cls = lookUp(name) ?? chain.dropFirst().lazy.compactMap({ self.lookUp($0.0) }).first else {
                fail("cannot decode object of class (\(name))")
            }
            guard let allocated = ObjC.send(cls, ObjC.selector("alloc")) else { return nil }
            let made = ObjC.send(allocated, ObjC.selector("initWithCoder:"), coder)
            if let made, KeyValueCoding.responds(made, ObjC.selector("awakeAfterUsingCoder:")),
               let replaced = ObjC.send(made, ObjC.selector("awakeAfterUsingCoder:"), coder), replaced != made {
                ObjC.retain(replaced)
                ObjC.release(made)
                return replaced
            }
            return made
        }
    }
}

extension Unarchivers {
    /// Classes archived under names they've since lost.
    nonisolated(unsafe) static var legacyClassNames: [String: String] = [:]
    nonisolated(unsafe) static var legacyUnarchiverClass: Class!
}

@ObjCClass("NSUnarchiver")
public final class NSUnarchiver: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Unarchivers.legacyUnarchiverClass = cls.storage
    }

    private var state: UnarchiverState? { Storage.get(objcObject, as: UnarchiverState.self) }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Unarchivers.legacyUnarchiverClass)
    }

    static func root(_ bytes: [UInt8]) -> ObjCObject? {
        guard let state = UnarchiverState(bytes),
              let unarchiver = Storage.allocate(UnsafeMutableRawPointer(Unarchivers.legacyUnarchiverClass)) else { return nil }
        Storage.set(unarchiver, state)
        defer { ObjC.release(unarchiver) }
        guard ArchiveTypes.bare(state.nextType()) == [UInt8(ascii: "@")] else { return nil }
        let root = state.object(coder: unarchiver)
        return root.flatMap { ObjC.autorelease(ObjC.retain($0)) }.map(ObjCObject.init)
    }

    @ObjCClassMethod("unarchiveObjectWithData:")
    static func unarchiveObject(withData data: ObjCObject?) -> ObjCObject? {
        root(Array(DataObjects.data(data?.id)))
    }

    @ObjCClassMethod("unarchiveObjectWithFile:")
    static func unarchiveObject(withFile path: String) -> ObjCObject? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return root(Array(data))
    }

    @ObjCClassMethod("decodeClassName:asClassName:")
    static func decodeClassName(_ archived: String, asClassName name: String) { Unarchivers.legacyClassNames[archived] = name }
    @ObjCClassMethod("classNameDecodedForArchiveClassName:")
    static func classNameDecoded(forArchiveClassName name: String) -> String { Unarchivers.legacyClassNames[name] ?? name }

    @ObjCMethod("initForReadingWithData:")
    func initialize(forReadingWith data: ObjCObject?) -> UnsafeMutableRawPointer? {
        guard let state = UnarchiverState(Array(DataObjects.data(data?.id))) else {
            ObjC.release(objcObject)
            return nil
        }
        Storage.set(objcObject, state)
        return objcObject
    }

    @ObjCMethod("decodeObject")
    func decodeObject() -> UnsafeMutableRawPointer? {
        guard let state else { return nil }
        let type = state.nextType()
        guard ArchiveTypes.bare(type) == [UInt8(ascii: "@")] else {
            state.fail("expected '@' and got '\(String(decoding: type, as: UTF8.self))'")
        }
        return state.object(coder: objcObject).flatMap { ObjC.autorelease(ObjC.retain($0)) }
    }

    @ObjCMethod("decodeValueOfObjCType:at:")
    func decodeValue(ofObjCType type: UnsafePointer<CChar>?, at address: UnsafeMutableRawPointer?) {
        guard let state, let type, let address else { return }
        // One type a call: a group of several (from -encodeValuesOfObjCTypes:)
        // answers as many calls.
        let expected = Array(UnsafeRawBufferPointer(start: type, count: strlen(type)))
        state.value(expected: expected, into: address, coder: objcObject)
    }

    @ObjCMethod("decodeValueOfObjCType:at:size:")
    func decodeValue(ofObjCType type: UnsafePointer<CChar>?, at address: UnsafeMutableRawPointer?, size: UInt) {
        decodeValue(ofObjCType: type, at: address)
    }

    @ObjCMethod("decodeArrayOfObjCType:count:at:")
    func decodeArray(ofObjCType type: UnsafePointer<CChar>?, count: UInt, at address: UnsafeMutableRawPointer?) {
        guard let type else { return }
        "[\(count)\(String(cString: type))]".withCString { decodeValue(ofObjCType: $0, at: address) }
    }

    /// Bytes as -encodeBytes:length: wrote them, kept by the unarchiver.
    @ObjCMethod("decodeBytesWithReturnedLength:")
    func decodeBytes(returnedLength length: UnsafeMutablePointer<UInt>?) -> UnsafeMutableRawPointer? {
        var count: Int32 = 0
        "i".withCString { decodeValue(ofObjCType: $0, at: &count) }
        length?.pointee = UInt(max(count, 0))
        guard count > 0, let data = DataObjects.autoreleased(Data(count: Int(count))),
              let bytes = ObjC.sendPointer(data, ObjC.selector("mutableBytes")) else { return nil }
        "c".withCString { decodeArray(ofObjCType: $0, count: UInt(count), at: UnsafeMutableRawPointer(mutating: bytes)) }
        return UnsafeMutableRawPointer(mutating: bytes)
    }

    @ObjCMethod("decodeDataObject")
    func decodeDataObject() -> UnsafeMutableRawPointer? {
        var length: UInt = 0
        let bytes = decodeBytes(returnedLength: &length)
        let data = Data(bytes: bytes ?? UnsafeMutableRawPointer(bitPattern: 1)!, count: Int(length))
        return DataObjects.autoreleased(data)
    }




    @ObjCMethod("isAtEnd") func isAtEnd() -> Bool { state?.isAtEnd ?? true }
    @ObjCMethod("systemVersion") func systemVersion() -> UInt32 { state?.systemVersion ?? 0 }
    @ObjCMethod("allowsKeyedCoding") func allowsKeyedCoding() -> Bool { false }
    @ObjCMethod("versionForClassName:")
    func version(forClassName name: String) -> Int { state?.versions[name] ?? Int.max }
    @ObjCMethod("decodeClassName:asClassName:")
    func decodeClassName(_ archived: String, asClassName name: String) { state?.classNames[archived] = name }
    @ObjCMethod("classNameDecodedForArchiveClassName:")
    func classNameDecoded(forArchiveClassName name: String) -> String { state?.classNames[name] ?? name }
    @ObjCMethod("replaceObject:withObject:") func replaceObject(_ object: ObjCObject?, with replacement: ObjCObject?) {}
    @ObjCMethod("setObjectZone:") func setObjectZone(_ zone: UnsafeMutableRawPointer?) {}
    @ObjCMethod("objectZone") func objectZone() -> UnsafeMutableRawPointer? { nil }
}

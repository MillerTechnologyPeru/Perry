import CPerryGeometry
import Glibc
import PerryObjCInterop

// Nibs: Interface Builder's compiled interfaces, in Apple's NIBArchive
// format. A nib is a list of objects, each a class and keyed values: numbers,
// Booleans, data and references to other objects. Instantiating one decodes
// every object through -initWithCoder: with a UINibDecoder, makes the
// connections (outlets and actions), sends -awakeFromNib, and returns the
// top-level objects. Placeholders (UIProxyObject) stand for the owner and
// for objects passed in from outside.

/// A NIBArchive file, parsed.
struct NibArchive {
    enum Value {
        case integer(Int64)
        case bool(Bool)
        case double(Double)
        case data([UInt8])
        case null
        case object(Int)
    }

    struct Object {
        let className: String
        let fallbacks: [String]
        let values: ArraySlice<(key: String, value: Value)>
    }

    let objects: [Object]

    init?(_ bytes: [UInt8]) {
        guard bytes.count >= 50, Array(bytes[0..<10]) == Array("NIBArchive".utf8) else { return nil }
        func u32(_ at: Int) -> Int {
            Int(bytes[at]) | Int(bytes[at + 1]) << 8 | Int(bytes[at + 2]) << 16 | Int(bytes[at + 3]) << 24
        }
        // Variable-length integers, seven bits a byte, the last with the
        // high bit set.
        func varint(_ position: inout Int) -> Int {
            var result = 0, shift = 0
            while position < bytes.count {
                let byte = bytes[position]
                position += 1
                result |= Int(byte & 0x7f) << shift
                if byte & 0x80 != 0 { break }
                shift += 7
            }
            return result
        }
        let (objectCount, objectsAt, keyCount, keysAt) = (u32(18), u32(22), u32(26), u32(30))
        let (valueCount, valuesAt, classCount, classesAt) = (u32(34), u32(38), u32(42), u32(46))

        var classes: [(name: String, fallbacks: [Int])] = []
        var position = classesAt
        for _ in 0..<classCount {
            let length = varint(&position), extra = varint(&position)
            var fallbacks: [Int] = []
            for _ in 0..<extra {
                fallbacks.append(u32(position))
                position += 4
            }
            let name = String(decoding: bytes[position..<position + length].prefix { $0 != 0 }, as: UTF8.self)
            classes.append((name, fallbacks))
            position += length
        }
        var keys: [String] = []
        position = keysAt
        for _ in 0..<keyCount {
            let length = varint(&position)
            keys.append(String(decoding: bytes[position..<position + length], as: UTF8.self))
            position += length
        }
        var values: [(key: String, value: Value)] = []
        values.reserveCapacity(valueCount)
        position = valuesAt
        func load<T: FixedWidthInteger>(_ type: T.Type) -> T {
            var value: T = 0
            for index in 0..<MemoryLayout<T>.size { value |= T(truncatingIfNeeded: bytes[position + index]) << (8 * index) }
            position += MemoryLayout<T>.size
            return value
        }
        for _ in 0..<valueCount {
            let key = keys[varint(&position)]
            let kind = bytes[position]
            position += 1
            let value: Value
            switch kind {
            case 0: value = .integer(Int64(Int8(bitPattern: load(UInt8.self))))
            case 1: value = .integer(Int64(load(Int16.self)))
            case 2: value = .integer(Int64(load(Int32.self)))
            case 3: value = .integer(load(Int64.self))
            case 4: value = .bool(false)
            case 5: value = .bool(true)
            case 6: value = .double(Double(Float(bitPattern: load(UInt32.self))))
            case 7: value = .double(Double(bitPattern: load(UInt64.self)))
            case 8:
                let length = varint(&position)
                value = .data(Array(bytes[position..<position + length]))
                position += length
            case 9: value = .null
            case 10: value = .object(Int(load(UInt32.self)))
            default: return nil
            }
            values.append((key, value))
        }
        var objects: [Object] = []
        position = objectsAt
        for _ in 0..<objectCount {
            let cls = varint(&position), first = varint(&position), count = varint(&position)
            let entry = classes[cls]
            objects.append(Object(className: entry.name, fallbacks: entry.fallbacks.compactMap { classes.indices.contains($0) ? classes[$0].name : nil },
                                  values: values[first..<first + count]))
        }
        self.objects = objects
    }
}

/// One instantiation of a nib: the objects decoded so far, and what the
/// placeholders stand for.
final class NibUnarchiving {
    let archive: NibArchive
    let owner: NSObject?
    let external: [String: NSObject]
    /// The directory the nib came from, for nibs it refers to.
    let bundlePath: String?
    var decoded: [Int: NSObject] = [:]
    var stack: [Int] = []

    init(archive: NibArchive, owner: NSObject?, external: [String: NSObject], bundlePath: String?) {
        (self.archive, self.owner, self.external, self.bundlePath) = (archive, owner, external, bundlePath)
    }

    var currentValues: ArraySlice<(key: String, value: NibArchive.Value)> {
        stack.last.map { archive.objects[$0].values } ?? []
    }

    func value(_ key: String) -> NibArchive.Value? { currentValues.first { $0.key == key }?.value }

    /// The current object's unkeyed elements, as arrays and dictionaries
    /// store them.
    var elements: [NibArchive.Value] { currentValues.filter { $0.key == "UINibEncoderEmptyKey" }.map(\.value) }

    func object(_ value: NibArchive.Value?, decoder: NSObject) -> NSObject? {
        switch value {
        case .object(let index): return object(at: index, decoder: decoder)
        case .data(let bytes): return Nibs.data(bytes)
        default: return nil
        }
    }

    /// The object at `index`, decoded once.
    func object(at index: Int, decoder: NSObject) -> NSObject? {
        if let object = decoded[index] { return object }
        let entry = archive.objects[index]
        stack.append(index)
        defer { stack.removeLast() }
        func data(_ key: String) -> [UInt8]? {
            if case .data(let bytes) = value(key) { return bytes }
            return nil
        }
        switch entry.className {
        case "NSString", "NSMutableString", "NSLocalizableString":
            let text = String(decoding: data("NS.bytes") ?? [], as: UTF8.self)
            let string = NSObject.nibString(text, mutable: entry.className == "NSMutableString")
            decoded[index] = string
            return string
        case "NSArray", "NSMutableArray", "NSSet", "NSMutableSet", "NSOrderedSet", "NSMutableOrderedSet":
            let isSet = entry.className.hasSuffix("Set") && !entry.className.contains("Ordered")
            let collection: NSObject = isSet ? NSMutableSet.empty() : NSMutableArray.empty()
            decoded[index] = collection
            for element in elements {
                guard let item = object(element, decoder: decoder) else { continue }
                if isSet { collection.unsafeCast(to: NSMutableSet.self).add(item) } else {
                    collection.unsafeCast(to: NSMutableArray.self).add(item)
                }
            }
            return collection
        case "NSDictionary", "NSMutableDictionary":
            let dictionary = NSMutableDictionary.empty()
            decoded[index] = dictionary
            let items = elements
            for pair in stride(from: 0, to: items.count - 1, by: 2) {
                guard let key = object(items[pair], decoder: decoder), let item = object(items[pair + 1], decoder: decoder) else { continue }
                dictionary.setObject(item, forKeyObject: key)
            }
            return dictionary
        case "NSNumber":
            let number: NSObject
            switch value("NS.intval") ?? value("NS.dblval") ?? value("NS.boolval") {
            case .integer(let integer): number = NSNumber.make(integer: Int(integer))
            case .double(let double): number = NSNumber.make(double: double)
            case .bool(let bool): number = NSNumber.make(bool: bool)
            default: number = NSNumber.make(integer: 0)
            }
            decoded[index] = number
            return number
        case "NSData", "NSMutableData":
            let object = Nibs.data(data("NS.bytes") ?? [])
            decoded[index] = object
            return object
        case "NSNull":
            let null = NSNull.null()
            decoded[index] = null
            return null
        case "UIProxyObject":
            guard case .object(let identifierIndex)? = value("UIProxiedObjectIdentifier"),
                  let identifier = object(at: identifierIndex, decoder: decoder)?.stringValue else { return nil }
            let proxied = identifier == "IBFilesOwner" ? owner : external[identifier]
            if let proxied { decoded[index] = proxied }
            return proxied
        case "UIClassSwapper":
            guard case .object(let nameIndex)? = value("UIClassName"), let name = object(at: nameIndex, decoder: decoder)?.stringValue else {
                return nil
            }
            var original: String?
            if case .object(let originalIndex)? = value("UIOriginalClassName") { original = object(at: originalIndex, decoder: decoder)?.stringValue }
            guard let cls = Classes.named(name) ?? original.flatMap(Classes.named) else {
                uikitWarning("nib: no class \(name)")
                return nil
            }
            return instantiate(cls, at: index, decoder: decoder)
        default:
            guard let cls = Classes.named(entry.className) ?? entry.fallbacks.lazy.compactMap(Classes.named).first else {
                uikitWarning("nib: no class \(entry.className)")
                return nil
            }
            return instantiate(cls, at: index, decoder: decoder)
        }
    }

    /// Allocates the object, so references back to it while it decodes
    /// find it, then initializes it from the coder; an object that cannot
    /// be decoded, such as an app delegate, is initialized plainly.
    private func instantiate(_ cls: ObjCClass, at index: Int, decoder: NSObject) -> NSObject? {
        let allocated = cls.object.allocated()
        decoded[index] = allocated
        let object = allocated.responds(to: "initWithCoder:") ? allocated.sendInitWithCoder(decoder) : allocated.initialized()
        decoded[index] = object
        return object
    }
}

enum Nibs {
    static func data(_ bytes: [UInt8]) -> NSObject {
        bytes.withUnsafeBytes { NSData.make(bytes: $0.baseAddress, length: UInt($0.count)) }
    }

    /// Instantiates a nib's objects; returns the top-level objects that
    /// are not placeholders.
    static func instantiate(_ archive: NibArchive, owner: NSObject?, external: [String: NSObject], bundlePath: String?) -> [NSObject] {
        let unarchiving = NibUnarchiving(archive: archive, owner: owner, external: external, bundlePath: bundlePath)
        let decoder = UINibDecoder.objCClass.object.allocated().unsafeCast(to: UINibDecoder.self)
        decoder.state.unarchiving = unarchiving
        defer { decoder.state.unarchiving = nil }
        // The root object lists every object, the top-level ones, and the
        // connections.
        unarchiving.stack.append(0)
        let all = list(unarchiving.value("UINibObjectsKey"), unarchiving, decoder)
        let topLevel = list(unarchiving.value("UINibTopLevelObjectsKey"), unarchiving, decoder)
        let connections = list(unarchiving.value("UINibConnectionsKey"), unarchiving, decoder)
        unarchiving.stack.removeLast()
        for connection in connections where connection.responds(to: "connect") { connection.sendConnect() }
        let placeholders = Set([owner?.objcObject].compactMap { $0 } + external.values.map(\.objcObject))
        for object in all where !placeholders.contains(object.objcObject) && !object.isProxyClass && object.responds(to: "awakeFromNib") {
            object.sendAwakeFromNib()
        }
        return topLevel.filter { !placeholders.contains($0.objcObject) && !$0.isProxyClass }
    }

    private static func list(_ value: NibArchive.Value?, _ unarchiving: NibUnarchiving, _ decoder: UINibDecoder) -> [NSObject] {
        guard let collection = unarchiving.object(value, decoder: decoder.unsafeCast(to: NSObject.self))?.as(NSArray.self) else { return [] }
        return collection.elements
    }

    /// A nib file's archive: `name.nib`, or `runtime.nib` in a nib
    /// directory, in `directory`.
    static func load(named name: String, in directory: String) -> NibArchive? {
        let base = name.hasSuffix(".nib") ? String(name.dropLast(4)) : name
        for path in ["\(directory)/\(base).nib/runtime.nib", "\(directory)/\(base).nib", "\(directory)/\(base)~iphone.nib",
                     "\(directory)/\(base).nib/objects-13.0+.nib", "\(directory)/\(base).nib/objects.nib"] {
            if let bytes = Files.read(path), let archive = NibArchive(bytes) { return archive }
        }
        return nil
    }
}

enum Files {
    /// A file's bytes; nil for directories and missing files.
    static func read(_ path: String) -> [UInt8]? {
        var info = stat()
        guard stat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, let file = fopen(path, "rb") else { return nil }
        defer { fclose(file) }
        var bytes = [UInt8](repeating: 0, count: Int(info.st_size))
        let count = bytes.withUnsafeMutableBytes { fread($0.baseAddress, 1, $0.count, file) }
        return count == bytes.count ? bytes : nil
    }
}

extension NSObject {
    /// Placeholder classes a nib decodes to themselves, which take no part
    /// in awakening.
    var isProxyClass: Bool { self.is(UIProxyObject.self) }

    static func nibString(_ text: String, mutable: Bool) -> NSObject {
        let string = NSObject(objCReturnValue: text.objCReturnValue())
        return mutable ? string.mutableCopied() : string
    }

    @ObjCMethod("initWithCoder:") func sendInitWithCoder(_ coder: NSObject) -> NSObject
    @ObjCMethod("init") func initialized() -> NSObject
    @ObjCMethod("awakeFromNib") func sendAwakeFromNib()
    @ObjCMethod("connect") func sendConnect()
    @ObjCMethod("mutableCopy") func mutableCopied() -> NSObject
    @ObjCMethod("setValue:forKey:") func sendSetValue(_ value: NSObject?, forKey key: String)
}

/// What every object a nib makes can be sent, as UIKit adds it to NSObject:
/// subclasses call super's.
@ObjCCategory("UINibAwaking")
extension NSObject {
    @ObjCMethod("awakeFromNib") func nibAwakeFromNib() {}
    @ObjCMethod("prepareForInterfaceBuilder") func nibPrepareForInterfaceBuilder() {}
}

// MARK: - UINibDecoder

final class NibDecoderState: ObjectState {
    var unarchiving: NibUnarchiving?
}

/// The coder nib objects decode from, with NSCoder's keyed messages.
@ObjCClass("UINibDecoder")
open class UINibDecoder: NSObject {
    static let states = StateTable<NibDecoderState>()
    var state: NibDecoderState { UINibDecoder.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        UINibDecoder.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UINibDecoder.objCClass.pointer)
    }

    private var unarchiving: NibUnarchiving? { state.unarchiving }

    @ObjCMethod("allowsKeyedCoding") func allowsKeyedCoding() -> Bool { true }
    @ObjCMethod("requiresSecureCoding") func requiresSecureCoding() -> Bool { false }
    @ObjCMethod("systemVersion") func systemVersion() -> UInt32 { 2000 }

    @ObjCMethod("containsValueForKey:")
    func containsValue(forKey key: String) -> Bool { unarchiving?.value(key) != nil }

    @ObjCMethod("decodeObjectForKey:")
    func decodeObject(forKey key: String) -> NSObject? {
        guard let unarchiving else { return nil }
        return unarchiving.object(unarchiving.value(key), decoder: self)
    }

    @ObjCMethod("decodeObjectOfClass:forKey:")
    func decodeObject(ofClass cls: ObjCClass?, forKey key: String) -> NSObject? { decodeObject(forKey: key) }

    @ObjCMethod("decodeObjectOfClasses:forKey:")
    func decodeObject(ofClasses classes: NSObject?, forKey key: String) -> NSObject? { decodeObject(forKey: key) }

    @ObjCMethod("decodeArrayOfObjectsOfClass:forKey:")
    func decodeArray(ofClass cls: ObjCClass?, forKey key: String) -> NSObject? { decodeObject(forKey: key) }

    @ObjCMethod("decodeTopLevelObjectForKey:error:")
    func decodeTopLevelObject(forKey key: String, error: UnsafeMutableRawPointer?) -> NSObject? { decodeObject(forKey: key) }

    private func number(_ key: String) -> (Int64, Double)? {
        switch unarchiving?.value(key) {
        case .integer(let value): return (value, Double(value))
        case .double(let value): return (Int64(value), value)
        case .bool(let value): return (value ? 1 : 0, value ? 1 : 0)
        default: return nil
        }
    }

    @ObjCMethod("decodeBoolForKey:") func decodeBool(forKey key: String) -> Bool { (number(key)?.0 ?? 0) != 0 }
    @ObjCMethod("decodeIntegerForKey:") func decodeInteger(forKey key: String) -> Int { Int(number(key)?.0 ?? 0) }
    @ObjCMethod("decodeIntForKey:") func decodeInt(forKey key: String) -> Int32 { Int32(truncatingIfNeeded: number(key)?.0 ?? 0) }
    @ObjCMethod("decodeInt32ForKey:") func decodeInt32(forKey key: String) -> Int32 { Int32(truncatingIfNeeded: number(key)?.0 ?? 0) }
    @ObjCMethod("decodeInt64ForKey:") func decodeInt64(forKey key: String) -> Int64 { number(key)?.0 ?? 0 }
    @ObjCMethod("decodeFloatForKey:") func decodeFloat(forKey key: String) -> Float { Float(number(key)?.1 ?? 0) }
    @ObjCMethod("decodeDoubleForKey:") func decodeDouble(forKey key: String) -> Double { number(key)?.1 ?? 0 }

    /// Geometry is data: a byte giving the element type (6: floats, 7:
    /// doubles), then the elements.
    func doubles(_ key: String) -> [Double] {
        guard case .data(let bytes)? = unarchiving?.value(key), let kind = bytes.first else { return [] }
        let size = kind == 6 ? 4 : 8
        return stride(from: 1, to: bytes.count - size + 1, by: size).map { offset in
            var raw: UInt64 = 0
            for index in 0..<size { raw |= UInt64(bytes[offset + index]) << (8 * index) }
            return size == 4 ? Double(Float(bitPattern: UInt32(raw))) : Double(bitPattern: raw)
        }
    }

    @ObjCMethod("decodeCGPointForKey:")
    func decodeCGPoint(forKey key: String) -> CGPoint {
        let v = doubles(key).map { CGFloat($0) }
        return v.count >= 2 ? CGPoint(x: v[0], y: v[1]) : .zero
    }

    @ObjCMethod("decodeCGSizeForKey:")
    func decodeCGSize(forKey key: String) -> CGSize {
        let v = doubles(key).map { CGFloat($0) }
        return v.count >= 2 ? CGSize(width: v[0], height: v[1]) : .zero
    }

    @ObjCMethod("decodeCGRectForKey:")
    func decodeCGRect(forKey key: String) -> CGRect {
        let v = doubles(key).map { CGFloat($0) }
        return v.count >= 4 ? CGRect(x: v[0], y: v[1], width: v[2], height: v[3]) : .zero
    }

    @ObjCMethod("decodeUIEdgeInsetsForKey:")
    func decodeUIEdgeInsets(forKey key: String) -> UIEdgeInsets {
        let v = doubles(key).map { CGFloat($0) }
        return v.count >= 4 ? UIEdgeInsets(top: v[0], left: v[1], bottom: v[2], right: v[3]) : .zero
    }

    @ObjCMethod("decodeCGAffineTransformForKey:")
    func decodeCGAffineTransform(forKey key: String) -> CGAffineTransform {
        let v = doubles(key).map { CGFloat($0) }
        return v.count >= 6 ? CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5]) : .identity
    }

    @ObjCMethod("decodeBytesForKey:returnedLength:")
    func decodeBytes(forKey key: String, returnedLength length: UnsafeMutablePointer<UInt>?) -> UnsafeRawPointer? {
        guard case .data(let bytes)? = unarchiving?.value(key) else {
            length?.pointee = 0
            return nil
        }
        length?.pointee = UInt(bytes.count)
        // Valid for as long as the decoder's autorelease pool: kept in data.
        let data = Nibs.data(bytes)
        _ = ObjCRuntime.autorelease(ObjCRuntime.retain(data.objcObject))
        return data.sendBytes()
    }

    /// The object being decoded's own values, for UIKit's classes.
    var nib: NibUnarchiving? { unarchiving }
}

extension NSObject {
    @ObjCMethod("bytes") func sendBytes() -> UnsafeRawPointer?
    @ObjCMethod("containsValueForKey:") func sendContainsValue(forKey key: String) -> Bool
    @ObjCMethod("decodeObjectForKey:") func sendDecodeObject(forKey key: String) -> NSObject?
    @ObjCMethod("decodeBoolForKey:") func sendDecodeBool(forKey key: String) -> Bool
    @ObjCMethod("decodeIntegerForKey:") func sendDecodeInteger(forKey key: String) -> Int
    @ObjCMethod("decodeDoubleForKey:") func sendDecodeDouble(forKey key: String) -> Double
    @ObjCMethod("decodeFloatForKey:") func sendDecodeFloat(forKey key: String) -> Float
    @ObjCMethod("decodeCGRectForKey:") func sendDecodeCGRect(forKey key: String) -> CGRect
    @ObjCMethod("decodeCGPointForKey:") func sendDecodeCGPoint(forKey key: String) -> CGPoint
    @ObjCMethod("decodeCGSizeForKey:") func sendDecodeCGSize(forKey key: String) -> CGSize
    @ObjCMethod("decodeUIEdgeInsetsForKey:") func sendDecodeUIEdgeInsets(forKey key: String) -> UIEdgeInsets
}

/// Keyed decoding from any coder, for UIKit's -initWithCoder:.
struct Coder {
    let coder: NSObject

    func has(_ key: String) -> Bool { coder.sendContainsValue(forKey: key) }
    func object(_ key: String) -> NSObject? { has(key) ? coder.sendDecodeObject(forKey: key) : nil }
    func string(_ key: String) -> String? { object(key)?.stringValue }
    func bool(_ key: String) -> Bool { coder.sendDecodeBool(forKey: key) }
    func integer(_ key: String) -> Int { coder.sendDecodeInteger(forKey: key) }
    func double(_ key: String) -> Double { coder.sendDecodeDouble(forKey: key) }
    /// The same, as a CGFloat or another floating-point type where one is wanted.
    func double<T: BinaryFloatingPoint>(_ key: String) -> T { T(double(key)) }
    func rect(_ key: String) -> CGRect { coder.sendDecodeCGRect(forKey: key) }
    func point(_ key: String) -> CGPoint { coder.sendDecodeCGPoint(forKey: key) }
    func size(_ key: String) -> CGSize { coder.sendDecodeCGSize(forKey: key) }
    func insets(_ key: String) -> UIEdgeInsets { coder.sendDecodeUIEdgeInsets(forKey: key) }

    func array(_ key: String) -> [NSObject] { object(key)?.as(NSArray.self)?.elements ?? [] }

    /// A dictionary of strings to objects.
    func dictionary(_ key: String) -> [String: NSObject] {
        guard let dictionary = object(key)?.as(NSDictionary.self) else { return [:] }
        var result: [String: NSObject] = [:]
        for key in dictionary.allKeys().elements {
            if let value = dictionary.object(forKeyObject: key) { result[key.stringValue] = value }
        }
        return result
    }
}

// MARK: - UINib

final class NibState: ObjectState {
    var archive: NibArchive?
    var bundlePath: String?
}

@ObjCClass("UINib")
open class UINib: NSObject {
    static let states = StateTable<NibState>()
    var state: NibState { UINib.states[objcObject] }

    static func make(_ archive: NibArchive, bundlePath: String?) -> UINib {
        let nib = objCClass.object.allocated().unsafeCast(to: UINib.self)
        nib.state.archive = archive
        nib.state.bundlePath = bundlePath
        return nib
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        UINib.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UINib.objCClass.pointer)
    }

    @ObjCClassMethod("nibWithNibName:bundle:")
    static func nib(named name: String, bundle: NSObject?) -> UINib? {
        let directory = (bundle?.as(NSBundle.self) ?? NSBundle.main()).bundlePath()
        for candidate in [directory, directory + "/Base.lproj", directory + "/en.lproj"] {
            if let archive = Nibs.load(named: name, in: candidate) { return make(archive, bundlePath: candidate) }
        }
        return nil
    }

    @ObjCClassMethod("nibWithData:bundle:")
    static func nib(data: NSObject, bundle: NSObject?) -> UINib? {
        guard let archive = NibArchive(data.as(NSData.self)?.byteArray ?? []) else { return nil }
        return make(archive, bundlePath: (bundle?.as(NSBundle.self) ?? NSBundle.main()).bundlePath())
    }

    /// A nib inside another, as prototype cells are kept.
    @ObjCMethod("initWithCoder:")
    func initialize(coder: NSObject) -> Self {
        let decoded = Coder(coder: coder)
        if let data = decoded.object("archiveData")?.as(NSData.self) { state.archive = NibArchive(data.byteArray) }
        state.bundlePath = coder.as(UINibDecoder.self)?.nib?.bundlePath
        return self
    }

    @ObjCMethod("instantiateWithOwner:options:")
    func instantiate(owner: NSObject?, options: NSObject?) -> NSObject {
        let external = options?.as(NSDictionary.self)?.object(forKey: "UINibExternalObjects")
        return NSMutableArray.of(instantiate(owner: owner, external: Nibs.strings(external)))
    }

    func instantiate(owner: NSObject?, external: [String: NSObject]) -> [NSObject] {
        guard let archive = state.archive else { return [] }
        return Nibs.instantiate(archive, owner: owner, external: external, bundlePath: state.bundlePath)
    }
}

extension Nibs {
    /// An NSDictionary of strings to objects.
    static func strings(_ dictionary: NSObject?) -> [String: NSObject] {
        guard let dictionary = dictionary?.as(NSDictionary.self) else { return [:] }
        var result: [String: NSObject] = [:]
        for key in dictionary.allKeys().elements {
            if let value = dictionary.object(forKeyObject: key) { result[key.stringValue] = value }
        }
        return result
    }
}

/// -[NSBundle loadNibNamed:owner:options:], UIKit's addition.
@ObjCCategory("UINibLoadingAdditions")
extension NSBundle {
    @ObjCMethod("loadNibNamed:owner:options:")
    func loadNib(named name: String, owner: NSObject?, options: NSObject?) -> NSObject? {
        guard let nib = UINib.nib(named: name, bundle: self) else { return nil }
        return nib.instantiate(owner: owner, options: options)
    }
}

// MARK: - Placeholders and connections

@ObjCClass("UIProxyObject")
open class UIProxyObject: NSObject {}

final class ConnectionState: ObjectState {
    var label: String?
    var source: NSObject?
    var destination: NSObject?
    var eventMask: UInt = 0
}

/// A connection a nib makes once its objects exist.
@ObjCClass("UIRuntimeConnection")
open class UIRuntimeConnection: NSObject {
    static let states = StateTable<ConnectionState>()
    var state: ConnectionState { UIRuntimeConnection.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        UIRuntimeConnection.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIRuntimeConnection.objCClass.pointer)
    }

    @ObjCMethod("initWithCoder:")
    func initialize(coder: NSObject) -> Self {
        let decoded = Coder(coder: coder)
        state.label = decoded.string("UILabel")
        state.source = decoded.object("UISource")
        state.destination = decoded.object("UIDestination")
        state.eventMask = UInt(bitPattern: decoded.integer("UIEventMask"))
        return self
    }

    @ObjCMethod("label") func label() -> String? { state.label }
    @ObjCMethod("source") func source() -> NSObject? { state.source }
    @ObjCMethod("destination") func destination() -> NSObject? { state.destination }
    @ObjCMethod("connect") func connect() {}
}

/// An outlet: the source's property set to the destination.
@ObjCClass("UIRuntimeOutletConnection")
open class UIRuntimeOutletConnection: UIRuntimeConnection {
    @ObjCMethod("connect")
    override func connect() {
        guard let source = state.source, let label = state.label else { return }
        Outlets.set(source, label, state.destination)
    }
}

/// An outlet collection: the source's array of destinations.
@ObjCClass("UIRuntimeOutletCollectionConnection")
open class UIRuntimeOutletCollectionConnection: UIRuntimeConnection {
    @ObjCMethod("connect")
    override func connect() {
        guard let source = state.source, let label = state.label else { return }
        Outlets.set(source, label, state.destination)
    }
}

/// An action: the destination as the source's target for the selector.
@ObjCClass("UIRuntimeEventConnection")
open class UIRuntimeEventConnection: UIRuntimeConnection {
    @ObjCMethod("connect")
    override func connect() {
        guard let source = state.source, let label = state.label else { return }
        let action = ObjCSelector(label)
        if let item = source.as(UIBarButtonItem.self) {
            item.state.target = state.destination?.objcObject
            item.state.action = action.pointer
        } else if let control = source.as(UIControl.self) {
            control.addTarget(state.destination, action: action, for: state.eventMask == 0 ? 1 << 6 : state.eventMask)
        }
    }
}

enum Outlets {
    /// Sets `key` through its setter when the object has one, else through
    /// key-value coding.
    static func set(_ object: NSObject, _ key: String, _ value: NSObject?) {
        guard let first = key.first else { return }
        let setter = "set" + first.uppercased() + key.dropFirst() + ":"
        if object.responds(to: setter) {
            typealias Send = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Void
            unsafeBitCast(ObjCRuntime.msgSend, to: Send.self)(object.objcObject, ObjCRuntime.selector(setter), value?.objcObject)
        } else {
            object.sendSetValue(value, forKey: key)
        }
    }
}

extension NSData {
    @ObjCClassMethod("dataWithBytes:length:") static func make(bytes: UnsafeRawPointer?, length: UInt) -> NSData
    @ObjCMethod("length") func length() -> UInt
    @ObjCMethod("bytes") func bytes() -> UnsafeRawPointer?

    var byteArray: [UInt8] {
        let count = Int(length())
        guard count > 0, let bytes = bytes() else { return [] }
        return Array(UnsafeRawBufferPointer(start: bytes, count: count))
    }
}

extension NSBundle {
    @ObjCMethod("bundlePath") func bundlePath() -> String
}

extension NSDictionary {
    @ObjCMethod("allKeys") func allKeys() -> NSArray
    @ObjCMethod("objectForKey:") func object(forKeyObject key: NSObject) -> NSObject?
}

extension NSMutableDictionary {
    @ObjCMethod("setObject:forKey:") func setObject(_ object: NSObject, forKeyObject key: NSObject)
}

extension NSNumber {
    @ObjCClassMethod("numberWithInteger:") static func make(integer: Int) -> NSNumber
    @ObjCClassMethod("numberWithBool:") static func make(bool: Bool) -> NSNumber
}

@ObjCWrapper("NSNull")
class NSNull: NSObject {
    @ObjCClassMethod("null") static func null() -> NSNull
}

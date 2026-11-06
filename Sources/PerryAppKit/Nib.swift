import CPerryGeometry
import Glibc
import PerryObjCInterop

// Nibs: Interface Builder's compiled interfaces, in Apple's NIBArchive
// format (or, from Xcode before 10.13's, an NSKeyedArchiver archive). A
// nib is a list of objects, each a class and keyed values. Instantiating
// one decodes its objects through -initWithCoder: with an NSNibDecoder, as
// AppKit's nib loading does: views, cells, windows (from their
// NSWindowTemplate), menus, controllers and the app's own classes, those
// Interface Builder swapped in by name (NSClassSwapper) included. Then the
// connections are made (outlets, actions, double-click actions, runtime
// attributes), every object hears -awakeFromNib, and the windows marked
// visible at launch are shown. Placeholders stand for File's Owner, the
// application, the first responder and objects passed in from outside, as
// a storyboard passes itself and its controllers.

/// A NIBArchive file, parsed.
struct NibArchive {
    enum Value {
        case integer(Int64)
        case bool(Bool)
        case double(Double)
        case data([UInt8])
        case null
        case object(Int)

        var integer: Int64? {
            switch self {
            case .integer(let value): value
            case .bool(let value): value ? 1 : 0
            case .double(let value): Int64(value)
            default: nil
            }
        }
    }

    struct Object {
        let className: String
        let fallbacks: [String]
        let values: ArraySlice<(key: String, value: Value)>

        func value(_ key: String) -> Value? { values.first { $0.key == key }?.value }
        func reference(_ key: String) -> Int? {
            if case .object(let index)? = value(key) { return index }
            return nil
        }
        /// The references a collection lists.
        var elements: [Int] {
            values.compactMap { field in
                guard field.key == "UINibEncoderEmptyKey", case .object(let index) = field.value else { return nil }
                return index
            }
        }
    }

    let objects: [Object]

    init?(_ bytes: [UInt8]) {
        // An older nib is a keyed archive, a binary property list.
        if bytes.starts(with: Array("bplist00".utf8)) {
            guard let objects = KeyedNib.objects(bytes) else { return nil }
            self.objects = objects
            return
        }
        guard bytes.count >= 50, Array(bytes[0..<10]) == Array("NIBArchive".utf8) else { return nil }
        func u32(_ at: Int) -> Int {
            Int(bytes[at]) | Int(bytes[at + 1]) << 8 | Int(bytes[at + 2]) << 16 | Int(bytes[at + 3]) << 24
        }
        var failed = false
        // Variable-length integers, seven bits a byte, the last with the
        // high bit set.
        func varint(_ position: inout Int) -> Int {
            var result = 0, shift = 0
            while position < bytes.count {
                let byte = bytes[position]
                position += 1
                result |= Int(byte & 0x7f) << shift
                if byte & 0x80 != 0 { return result }
                shift += 7
            }
            failed = true
            return result
        }
        let (objectCount, objectsAt, keyCount, keysAt) = (u32(18), u32(22), u32(26), u32(30))
        let (valueCount, valuesAt, classCount, classesAt) = (u32(34), u32(38), u32(42), u32(46))
        guard [objectsAt, keysAt, valuesAt, classesAt].allSatisfy({ $0 < bytes.count }) else { return nil }

        var classes: [(name: String, fallbacks: [Int])] = []
        var position = classesAt
        for _ in 0..<classCount {
            let length = varint(&position), extra = varint(&position)
            var fallbacks: [Int] = []
            for _ in 0..<extra {
                guard position + 4 <= bytes.count else { return nil }
                fallbacks.append(u32(position))
                position += 4
            }
            guard position + length <= bytes.count else { return nil }
            classes.append((String(decoding: bytes[position..<position + length].prefix { $0 != 0 }, as: UTF8.self), fallbacks))
            position += length
        }
        var keys: [String] = []
        position = keysAt
        for _ in 0..<keyCount {
            let length = varint(&position)
            guard position + length <= bytes.count else { return nil }
            keys.append(String(decoding: bytes[position..<position + length], as: UTF8.self))
            position += length
        }
        var values: [(key: String, value: Value)] = []
        values.reserveCapacity(valueCount)
        position = valuesAt
        func load<T: FixedWidthInteger>(_ type: T.Type) -> T {
            guard position + MemoryLayout<T>.size <= bytes.count else {
                failed = true
                return 0
            }
            var value: T = 0
            for index in 0..<MemoryLayout<T>.size { value |= T(truncatingIfNeeded: bytes[position + index]) << (8 * index) }
            position += MemoryLayout<T>.size
            return value
        }
        for _ in 0..<valueCount {
            let keyIndex = varint(&position)
            guard keys.indices.contains(keyIndex), position < bytes.count else { return nil }
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
                guard position + length <= bytes.count else { return nil }
                value = .data(Array(bytes[position..<position + length]))
                position += length
            case 9: value = .null
            case 10: value = .object(Int(load(UInt32.self)))
            default: return nil
            }
            values.append((keys[keyIndex], value))
        }
        var objects: [Object] = []
        position = objectsAt
        for _ in 0..<objectCount {
            let cls = varint(&position), first = varint(&position), count = varint(&position)
            guard classes.indices.contains(cls), first + count <= values.count else { return nil }
            let entry = classes[cls]
            objects.append(Object(className: entry.name, fallbacks: entry.fallbacks.compactMap { classes.indices.contains($0) ? classes[$0].name : nil },
                                  values: values[first..<first + count]))
        }
        guard !failed else { return nil }
        self.objects = objects
    }
}

/// Nibs as Xcode made them before NIBArchive: an NSKeyedArchiver archive,
/// a binary property list whose "$objects" are the objects, each a
/// dictionary of its keys with its class under "$class", referring to one
/// another by index, and whose "$top" has the nib's own keys. They are read
/// into the objects a NIBArchive gives: the first is the root, in place of
/// "$null"; strings, numbers and data are NSString, NSNumber and NSData
/// with a NIBArchive's keys; a collection's "NS.objects" (and "NS.keys")
/// are its unkeyed elements.
enum KeyedNib {
    indirect enum Plist {
        case null, bool(Bool), integer(Int64), real(Double), data([UInt8]), string(String), uid(Int)
        case array([Plist]), dictionary([String: Plist])
    }

    /// A binary property list's top object.
    static func parse(_ bytes: [UInt8]) -> Plist? {
        guard bytes.count >= 40 else { return nil }
        func big(_ at: Int, _ size: Int) -> Int? {
            guard at >= 0, size > 0, at + size <= bytes.count else { return nil }
            return bytes[at..<at + size].reduce(0) { $0 << 8 | Int($1) }
        }
        let trailer = bytes.count - 32
        let offsetSize = Int(bytes[trailer + 6]), referenceSize = Int(bytes[trailer + 7])
        guard let count = big(trailer + 8, 8), let top = big(trailer + 16, 8), let table = big(trailer + 24, 8),
              offsetSize > 0, referenceSize > 0 else { return nil }
        var parsed: [Int: Plist] = [:]
        func object(_ index: Int, depth: Int) -> Plist? {
            if let known = parsed[index] { return known }
            guard depth < 64, index < count, let offset = big(table + index * offsetSize, offsetSize), offset < trailer else { return nil }
            let marker = bytes[offset], kind = marker >> 4, low = Int(marker & 0xf)
            var position = offset + 1
            func length() -> Int? {
                guard low == 0xf else { return low }
                guard position < trailer else { return nil }
                let size = 1 << Int(bytes[position] & 0xf)
                defer { position += 1 + size }
                return big(position + 1, size)
            }
            func references(_ number: Int) -> [Plist]? {
                var items: [Plist] = []
                for _ in 0..<number {
                    guard let reference = big(position, referenceSize), let item = object(reference, depth: depth + 1) else { return nil }
                    items.append(item)
                    position += referenceSize
                }
                return items
            }
            let value: Plist
            switch kind {
            case 0x0: value = marker == 0x08 ? .bool(false) : marker == 0x09 ? .bool(true) : .null
            case 0x1:
                guard let raw = big(position, 1 << low) else { return nil }
                value = .integer(Int64(truncatingIfNeeded: raw))
            case 0x2, 0x3:
                guard let raw = big(position, 1 << low) else { return nil }
                value = .real(low == 2 ? Double(Float(bitPattern: UInt32(truncatingIfNeeded: raw))) : Double(bitPattern: UInt64(bitPattern: Int64(raw))))
            case 0x4:
                guard let size = length(), position + size <= trailer else { return nil }
                value = .data(Array(bytes[position..<position + size]))
            case 0x5:
                guard let size = length(), position + size <= trailer else { return nil }
                value = .string(String(decoding: bytes[position..<position + size], as: UTF8.self))
            case 0x6:
                guard let size = length(), position + size * 2 <= trailer else { return nil }
                let units = (0..<size).map { UInt16(bytes[position + $0 * 2]) << 8 | UInt16(bytes[position + $0 * 2 + 1]) }
                value = .string(String(decoding: units, as: UTF16.self))
            case 0x8:
                guard let raw = big(position, low + 1) else { return nil }
                value = .uid(raw)
            case 0xa, 0xc:
                guard let size = length(), let items = references(size) else { return nil }
                value = .array(items)
            case 0xd:
                guard let size = length(), let keys = references(size), let values = references(size) else { return nil }
                var dictionary: [String: Plist] = [:]
                for (key, item) in zip(keys, values) {
                    if case .string(let name) = key { dictionary[name] = item }
                }
                value = .dictionary(dictionary)
            default: return nil
            }
            parsed[index] = value
            return value
        }
        return object(top, depth: 0)
    }

    /// The archive's objects as a nib's; nil if it is not a keyed archive.
    static func objects(_ bytes: [UInt8]) -> [NibArchive.Object]? {
        guard case .dictionary(let root)? = parse(bytes), case .array(let archived)? = root["$objects"],
              case .dictionary(let top)? = root["$top"] else { return nil }
        typealias Entry = (key: String, value: NibArchive.Value)
        var values: [Entry] = []
        var described: [(className: String, fallbacks: [String], range: Range<Int>)] = []
        func value(_ plist: Plist) -> NibArchive.Value? {
            switch plist {
            case .uid(let index): return index == 0 ? .null : .object(index)
            case .integer(let number): return .integer(number)
            case .real(let number): return .double(number)
            case .bool(let flag): return .bool(flag)
            case .data(let data): return .data(data)
            case .string(let text): return .data(Array(text.utf8))
            case .null: return .null
            case .array, .dictionary: return nil
            }
        }
        func add(_ className: String, _ fallbacks: [String] = [], _ entries: [Entry]) {
            described.append((className, fallbacks, values.count..<values.count + entries.count))
            values += entries
        }
        func text(_ plist: Plist?) -> String? {
            switch plist {
            case .string(let text)?: return text
            case .uid(let index)? where archived.indices.contains(index): if case .string(let text) = archived[index] { return text }
            default: break
            }
            return nil
        }
        add("NSObject", [], top.compactMap { key, item in value(item).map { (key, $0) } })
        for object in archived.dropFirst() {
            switch object {
            case .string(let string): add("NSString", [], [("NS.bytes", .data(Array(string.utf8)))])
            case .integer(let number): add("NSNumber", [], [("NS.intval", .integer(number))])
            case .real(let number): add("NSNumber", [], [("NS.dblval", .double(number))])
            case .bool(let flag): add("NSNumber", [], [("NS.boolval", .bool(flag))])
            case .data(let data): add("NSData", [], [("NS.bytes", .data(data))])
            case .dictionary(let fields):
                guard case .uid(let classIndex)? = fields["$class"], archived.indices.contains(classIndex),
                      case .dictionary(let cls) = archived[classIndex], case .string(let className)? = cls["$classname"] else {
                    add("$class", [], [])
                    continue
                }
                var fallbacks: [String] = []
                if case .array(let names)? = cls["$classes"] {
                    fallbacks = names.dropFirst().compactMap { if case .string(let name) = $0 { return name } else { return nil } }
                }
                var entries: [Entry] = []
                var elements: [Plist] = [], keys: [Plist]?
                for (key, item) in fields where key != "$class" {
                    switch (key, item) {
                    case ("NS.objects", .array(let items)): elements = items
                    case ("NS.keys", .array(let items)): keys = items
                    case ("NS.string", _):
                        if let string = text(item) { entries.append(("NS.bytes", .data(Array(string.utf8)))) }
                    default:
                        if let converted = value(item) { entries.append((key, converted)) }
                    }
                }
                if let keys {
                    for (key, item) in zip(keys, elements) {
                        guard let first = value(key), let second = value(item) else { continue }
                        entries.append(("UINibEncoderEmptyKey", first))
                        entries.append(("UINibEncoderEmptyKey", second))
                    }
                } else {
                    entries += elements.compactMap { value($0).map { ("UINibEncoderEmptyKey", $0) } }
                }
                add(className, fallbacks, entries)
            default: add("NSNull", [], [])
            }
        }
        return described.map { NibArchive.Object(className: $0.className, fallbacks: $0.fallbacks, values: values[$0.range]) }
    }
}

/// One instantiation of a nib: the objects decoded so far, and what the
/// placeholders stand for.
final class NibUnarchiving {
    let archive: NibArchive
    let owner: NSObject?
    let external: [String: NSObject]
    /// The directory the nib came from, for nibs and images it refers to.
    let bundlePath: String?
    var decoded: [Int: NSObject] = [:]
    /// Placeholders that stand for no object: the first responder.
    var empty: Set<Int> = []
    var stack: [Int] = []
    /// The objects that hear -awakeFromNib, in the order they were made.
    var made: [NSObject] = []
    var root: Int?

    init(archive: NibArchive, owner: NSObject?, external: [String: NSObject], bundlePath: String?) {
        (self.archive, self.owner, self.external, self.bundlePath) = (archive, owner, external, bundlePath)
    }

    var current: NibArchive.Object? { stack.last.map { archive.objects[$0] } }
    var currentValues: ArraySlice<(key: String, value: NibArchive.Value)> { current?.values ?? [] }
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

    func string(at index: Int) -> String? {
        guard archive.objects.indices.contains(index) else { return nil }
        let entry = archive.objects[index]
        guard entry.className.hasSuffix("String"), case .data(let bytes)? = entry.value("NS.bytes") else { return nil }
        return String(decoding: bytes, as: UTF8.self)
    }

    func string(_ key: String, of entry: NibArchive.Object) -> String? { entry.reference(key).flatMap(string(at:)) }

    /// The object at `index`, decoded once.
    func object(at index: Int, decoder: NSObject) -> NSObject? {
        guard archive.objects.indices.contains(index), !empty.contains(index) else { return nil }
        if let object = decoded[index] { return object }
        if index == root, let owner { return owner }
        let entry = archive.objects[index]
        stack.append(index)
        defer { stack.removeLast() }
        func data(_ key: String) -> [UInt8]? {
            if case .data(let bytes) = value(key) { return bytes }
            return nil
        }
        func keep(_ object: NSObject?) -> NSObject? {
            if let object { decoded[index] = object }
            return object
        }
        switch entry.className {
        case "NSString", "NSMutableString", "NSLocalizableString":
            let text = String(decoding: data("NS.bytes") ?? [], as: UTF8.self)
            return keep(NSObject.nibString(text, mutable: entry.className == "NSMutableString"))
        case "NSArray", "NSMutableArray", "NSSet", "NSMutableSet", "NSOrderedSet", "NSMutableOrderedSet":
            let isSet = entry.className.hasSuffix("Set") && !entry.className.contains("Ordered")
            let collection: NSObject = isSet ? NSMutableSet.empty() : NSMutableArray.empty()
            decoded[index] = collection
            for element in elements {
                guard let item = object(element, decoder: decoder) else { continue }
                if isSet { collection.unsafeCast(to: NSMutableSet.self).add(item) } else { collection.unsafeCast(to: NSMutableArray.self).add(item) }
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
            switch value("NS.intval") ?? value("NS.dblval") ?? value("NS.boolval") {
            case .integer(let integer): return keep(NSNumber.make(integer: Int(integer)))
            case .double(let double): return keep(NSNumber.make(double: double))
            case .bool(let bool): return keep(NSNumber.make(bool: bool))
            default: return keep(NSNumber.make(integer: 0))
            }
        case "NSData", "NSMutableData":
            return keep(Nibs.data(data("NS.bytes") ?? []))
        case "NSNull":
            return keep(NSNull.null())
        case "NSCustomObject":
            return keep(customObject(entry, decoder: decoder, index: index))
        case "NSNibExternalObjectPlaceholder":
            guard let identifier = string("NSExternalObjectPlaceholderIdentifier", of: entry) else { return nil }
            guard let object = external[identifier] else {
                if identifier != "NSStoryboardPlaceholder" { appKitWarning("nib: nothing passed in for \(identifier)") }
                empty.insert(index)
                return nil
            }
            return keep(object)
        case "NSCustomResource":
            // An image (or a color) of the app's, by name.
            guard let name = string("NSResourceName", of: entry) else { return nil }
            if string("NSClassName", of: entry) == "NSColor" { return keep(NSColor.color(named: name) ?? NSColor.blackColor()) }
            return keep(NSImage.image(named: name))
        case "NSClassSwapper":
            // An object of a class the app names, decoded as the class it
            // stands in for.
            let name = string("NSClassName", of: entry) ?? ""
            let original = string("NSOriginalClassName", of: entry)
            guard let cls = Classes.named(name) ?? original.flatMap(Classes.named) else {
                Nibs.missing(name)
                empty.insert(index)
                return nil
            }
            if value("NSInitializeWithInit")?.integer == 1 {
                let object = cls.object.allocated().initialized()
                made.append(object)
                return keep(object)
            }
            return instantiate(cls, at: index, decoder: decoder)
        case "NSWindowTemplate":
            return keep(NSWindow.instantiate(template: Coder(coder: decoder), unarchiving: self))
        case "NSCustomView":
            // A view of a class the app names, made with -initWithFrame:.
            let name = string("NSClassName", of: entry) ?? "NSView"
            guard let cls = Classes.named(name) ?? Classes.named("NSView") else { return nil }
            let allocated = cls.object.allocated()
            decoded[index] = allocated
            let view = NSObject(Send.initWithFrame(allocated.objcObject, NSView.frame(from: Coder(coder: decoder))) ?? allocated.objcObject)
            decoded[index] = view
            NSView.objCInstance(view.objcObject, ownership: .retain).decodeContents(Coder(coder: decoder))
            made.append(view)
            return view
        case "IBClassReference":
            return nil
        default:
            if let cls = Classes.named(entry.className) ?? entry.fallbacks.lazy.compactMap(Classes.named).first {
                return instantiate(cls, at: index, decoder: decoder)
            }
            // A view of a class this AppKit doesn't have is a plain view,
            // so that what it holds still shows.
            if value("NSvFlags") != nil || value("NSFrame") != nil || value("NSFrameSize") != nil, let cls = Classes.named("NSView") {
                Nibs.missing(entry.className)
                return instantiate(cls, at: index, decoder: decoder)
            }
            Nibs.missing(entry.className)
            return nil
        }
    }

    /// An object Interface Builder only names: File's Owner (the root), the
    /// application, the first responder, or an object of a class made with
    /// -init, as an app delegate is.
    private func customObject(_ entry: NibArchive.Object, decoder: NSObject, index: Int) -> NSObject? {
        guard let name = string("NSClassName", of: entry) else { return nil }
        if name == "FirstResponder" || name == "NSFirstResponder" {
            empty.insert(index)
            return nil
        }
        guard let cls = Classes.named(name) else {
            Nibs.missing(name)
            empty.insert(index)
            return nil
        }
        if cls.isSubclass(of: NSApplication.objCClass) {
            return Send.object(cls.pointer, "sharedApplication").map(NSObject.init)
        }
        let object = cls.object.allocated().initialized()
        made.append(object)
        return object
    }

    /// Allocates the object, so references back to it while it decodes
    /// find it, then initializes it from the coder.
    private func instantiate(_ cls: ObjCClass, at index: Int, decoder: NSObject) -> NSObject? {
        let allocated = cls.object.allocated()
        decoded[index] = allocated
        let object = allocated.responds(to: "initWithCoder:") ? allocated.sendInitWithCoder(decoder) : allocated.initialized()
        decoded[index] = object
        made.append(object)
        return object
    }
}

enum Nibs {
    /// What nibs made that nothing else keeps: the main nib's objects, as
    /// AppKit keeps them for the life of the app.
    nonisolated(unsafe) static var kept: [NSObject] = []
    nonisolated(unsafe) private static var reported: Set<String> = []

    static func missing(_ name: String) {
        guard !reported.contains(name) else { return }
        reported.insert(name)
        appKitWarning("nib: no class \(name)")
    }

    static func data(_ bytes: [UInt8]) -> NSObject {
        bytes.withUnsafeBytes { NSData.make(bytes: $0.baseAddress, length: UInt($0.count)) }
    }

    /// Instantiates a nib's objects; returns the top-level objects that
    /// are not placeholders.
    @discardableResult
    static func instantiate(_ archive: NibArchive, owner: NSObject?, external: [String: NSObject] = [:], bundlePath: String?) -> [NSObject] {
        let unarchiving = NibUnarchiving(archive: archive, owner: owner, external: external, bundlePath: bundlePath)
        let decoder = NSNibDecoder()
        decoder.unarchiving = unarchiving
        defer { decoder.unarchiving = nil }
        guard let first = archive.objects.first, let dataIndex = first.reference("IB.objectdata"),
              archive.objects.indices.contains(dataIndex) else {
            appKitWarning("nib: no object data")
            return []
        }
        let data = archive.objects[dataIndex]
        unarchiving.root = data.reference("NSRoot")
        unarchiving.stack.append(dataIndex)
        let objects = list(data.reference("NSObjectsKeys"), unarchiving, decoder)
        let parents = list(data.reference("NSObjectsValues"), unarchiving, decoder)
        let visible = list(data.reference("NSVisibleWindows"), unarchiving, decoder)
        unarchiving.stack.removeLast()
        // The connections, made once every object exists.
        if let connections = data.reference("NSConnections") {
            for index in archive.objects[connections].elements { connect(archive.objects[index], unarchiving, decoder) }
        }
        let placeholders = Set(([owner?.objcObject] + external.values.map(\.objcObject) + [App.shared?.objcObject]).compactMap { $0 })
        var awoken = Set<UnsafeMutableRawPointer>()
        for object in unarchiving.made where !placeholders.contains(object.objcObject) && !awoken.contains(object.objcObject) {
            awoken.insert(object.objcObject)
            if object.responds(to: "awakeFromNib") { Send.void(object.objcObject, "awakeFromNib") }
        }
        Trace.log("nib: \(archive.objects.count) entries, \(unarchiving.made.count) objects")
        for window in visible { Send.void(window.objcObject, "makeKeyAndOrderFront:", nil) }
        // The top level: the objects whose parent is File's Owner.
        let rootObject = unarchiving.root.flatMap { unarchiving.decoded[$0] } ?? owner
        var top: [NSObject] = []
        for (object, parent) in zip(objects, parents) where parent.objcObject == rootObject?.objcObject {
            if !placeholders.contains(object.objcObject) { top.append(object) }
        }
        return top
    }

    private static func list(_ index: Int?, _ unarchiving: NibUnarchiving, _ decoder: NSNibDecoder) -> [NSObject] {
        guard let index, unarchiving.archive.objects.indices.contains(index) else { return [] }
        // Elements one by one: a placeholder for nothing keeps its place.
        return unarchiving.archive.objects[index].elements.map { unarchiving.object(at: $0, decoder: decoder) ?? NSNull.null() }
    }

    /// An outlet, an action, a double-click action or runtime attributes.
    private static func connect(_ connector: NibArchive.Object, _ unarchiving: NibUnarchiving, _ decoder: NSNibDecoder) {
        func object(_ key: String) -> NSObject? {
            guard let index = connector.reference(key) else { return nil }
            let found = unarchiving.object(at: index, decoder: decoder)
            return found.flatMap { $0.is(NSNull.self) ? nil : $0 }
        }
        let label = unarchiving.string("NSLabel", of: connector)
        switch connector.className {
        case "NSNibOutletConnector":
            guard let label, let source = object("NSSource") else {
                Trace.log("nib: outlet \(label ?? "?") has no source")
                return
            }
            let destination = object("NSDestination")
            Trace.log("nib: outlet \(label) of \(source.describedByObject() ?? "?") to \(destination?.describedByObject() ?? "nil")")
            Outlets.set(source, label, destination)
        case "NSNibControlConnector":
            guard let label, let source = object("NSSource") else { return }
            Send.void(source.objcObject, "setAction:", UnsafeMutableRawPointer(mutating: ObjCRuntime.selector(label)))
            Send.void(source.objcObject, "setTarget:", object("NSDestination")?.objcObject)
        case "NSNibAuxiliaryActionConnector":
            // A second action: "doubleAction" for a table's double click.
            guard let label, let source = object("NSSource"), let trigger = unarchiving.string("NSTrigger", of: connector),
                  let first = trigger.first else { return }
            let setter = "set" + first.uppercased() + trigger.dropFirst() + ":"
            if source.responds(to: setter) { Send.void(source.objcObject, setter, UnsafeMutableRawPointer(mutating: ObjCRuntime.selector(label))) }
            Send.void(source.objcObject, "setTarget:", object("NSDestination")?.objcObject)
        case "NSIBUserDefinedRuntimeAttributesConnector":
            guard let target = object("NSObject"), let paths = connector.reference("NSKeyPaths"), let values = connector.reference("NSValues") else { return }
            let keys = unarchiving.archive.objects[paths].elements.compactMap { unarchiving.string(at: $0) }
            let items = unarchiving.archive.objects[values].elements.map { unarchiving.object(at: $0, decoder: decoder) }
            for (key, item) in zip(keys, items) { target.sendSetValue(item, forKeyPath: key) }
        case "NSNibBindingConnector":
            Bindings.connect(source: object("NSSource"), destination: object("NSDestination"), connector: connector, unarchiving: unarchiving)
        default:
            break
        }
    }

    /// A nib file's archive: `name.nib`, a NIBArchive or keyed archive, or
    /// a nib directory's keyedobjects, in `directory`.
    static func load(named name: String, in directory: String) -> NibArchive? {
        let base = name.hasSuffix(".nib") ? String(name.dropLast(4)) : name
        for path in ["\(directory)/\(base).nib", "\(directory)/\(base).nib/keyedobjects-110000.nib",
                     "\(directory)/\(base).nib/keyedobjects-101300.nib", "\(directory)/\(base).nib/keyedobjects.nib",
                     "\(directory)/\(base).nib/runtime.nib"] {
            if let bytes = Files.read(path), let archive = NibArchive(bytes) { return archive }
        }
        return nil
    }

    /// The directories a bundle's nib can be in: its resources, then their
    /// Base and English localizations.
    static func directories(_ bundle: NSObject?) -> [String] {
        let path = bundle.flatMap { Send.object($0.objcObject, "resourcePath") }.map { String(objCArgument: $0) }
            ?? NSBundle.main().bundlePath() + "/Contents/Resources"
        return [path, path + "/Base.lproj", path + "/en.lproj", path + "/English.lproj"]
    }

    /// A nib by name in a bundle, and the directory it was found in.
    static func find(_ name: String, bundle: NSObject?) -> (archive: NibArchive, directory: String)? {
        for directory in directories(bundle) {
            if let archive = load(named: name, in: directory) { return (archive, directory) }
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

enum Outlets {
    /// Sets `key` through its setter when the object has one, else through
    /// key-value coding.
    static func set(_ object: NSObject, _ key: String, _ value: NSObject?) {
        guard let first = key.first else { return }
        let setter = "set" + first.uppercased() + key.dropFirst() + ":"
        if object.responds(to: setter) {
            Send.void(object.objcObject, setter, value?.objcObject)
        } else if hasInstanceVariable(object, key) || hasInstanceVariable(object, "_" + key) {
            object.sendSetValue(value, forKey: key)
        } else {
            // An outlet of a class the app has and this one stands in for.
            appKitWarning("nib: \(object.describedByObject() ?? "an object") has no \(key) outlet")
        }
    }

    typealias GetInstanceVariable = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> UnsafeMutableRawPointer?
    nonisolated(unsafe) static let getInstanceVariable = Symbols.symbol("/usr/lib/libobjc.A.dylib", "_class_getInstanceVariable")
        .map { unsafeBitCast($0, to: GetInstanceVariable.self) }

    static func hasInstanceVariable(_ object: NSObject, _ name: String) -> Bool {
        guard let getInstanceVariable else { return true }
        return name.withCString { getInstanceVariable(ObjCRuntime.objectClass(object.objcObject), $0) } != nil
    }
}

/// Cocoa bindings a nib makes: kept as the binding's key path, for the
/// views that read their value once; bound objects don't observe changes.
enum Bindings {
    static func connect(source: NSObject?, destination: NSObject?, connector: NibArchive.Object, unarchiving: NibUnarchiving) {
        guard let source, let destination, let binding = unarchiving.string("NSBinding", of: connector),
              let keyPath = unarchiving.string("NSKeyPath", of: connector) else { return }
        Trace.log("nib: binding \(binding) to \(keyPath)")
        guard binding == "value" || binding == "hidden" || binding == "enabled" else { return }
        guard let value = destination.sendValue(forKeyPath: keyPath) else { return }
        switch binding {
        case "hidden": Send.void(source.objcObject, "setHidden:", bool: Send.bool(value.objcObject, "boolValue"))
        case "enabled": Send.void(source.objcObject, "setEnabled:", bool: Send.bool(value.objcObject, "boolValue"))
        default: Send.void(source.objcObject, "setObjectValue:", value.objcObject)
        }
    }
}

extension NSObject {
    static func nibString(_ text: String, mutable: Bool) -> NSObject {
        let string = NSObject(objCReturnValue: text.objCReturnValue())
        return mutable ? string.mutableCopied() : string
    }

    @ObjCMethod("initWithCoder:") func sendInitWithCoder(_ coder: NSObject) -> NSObject
    @ObjCMethod("mutableCopy") func mutableCopied() -> NSObject
    @ObjCMethod("setValue:forKey:") func sendSetValue(_ value: NSObject?, forKey key: String)
    @ObjCMethod("setValue:forKeyPath:") func sendSetValue(_ value: NSObject?, forKeyPath key: String)
    @ObjCMethod("valueForKeyPath:") func sendValue(forKeyPath key: String) -> NSObject?
    @ObjCMethod("bytes") func sendBytes() -> UnsafeRawPointer?
    @ObjCMethod("containsValueForKey:") func sendContainsValue(forKey key: String) -> Bool
    @ObjCMethod("decodeObjectForKey:") func sendDecodeObject(forKey key: String) -> NSObject?
    @ObjCMethod("decodeBoolForKey:") func sendDecodeBool(forKey key: String) -> Bool
    @ObjCMethod("decodeIntegerForKey:") func sendDecodeInteger(forKey key: String) -> Int
    @ObjCMethod("decodeDoubleForKey:") func sendDecodeDouble(forKey key: String) -> Double
    @ObjCMethod("decodeRectForKey:") func sendDecodeRect(forKey key: String) -> CGRect
    @ObjCMethod("decodePointForKey:") func sendDecodePoint(forKey key: String) -> CGPoint
    @ObjCMethod("decodeSizeForKey:") func sendDecodeSize(forKey key: String) -> CGSize
    @ObjCMethod("decodeBytesForKey:returnedLength:")
    func sendDecodeBytes(forKey key: String, returnedLength: UnsafeMutablePointer<UInt>?) -> UnsafeRawPointer?
}

/// What every object a nib makes can be sent, as AppKit adds it to NSObject:
/// subclasses call super's.
@ObjCCategory("NSNibAwaking")
extension NSObject {
    @ObjCMethod("awakeFromNib") func nibAwakeFromNib() {}
    @ObjCMethod("prepareForInterfaceBuilder") func nibPrepareForInterfaceBuilder() {}
}

// MARK: - NSNibDecoder

/// The coder nib objects decode from, with NSCoder's keyed messages.
@ObjCClass("NSNibDecoder")
open class NSNibDecoder: NSObject {
    var unarchiving: NibUnarchiving?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("allowsKeyedCoding") func allowsKeyedCoding() -> Bool { true }
    @ObjCMethod("requiresSecureCoding") func requiresSecureCoding() -> Bool { false }
    @ObjCMethod("systemVersion") func systemVersion() -> UInt32 { 2000 }
    @ObjCMethod("error") func error() -> NSObject? { nil }
    @ObjCMethod("decodingFailurePolicy") func decodingFailurePolicy() -> Int { 0 }

    @ObjCMethod("containsValueForKey:")
    func containsValue(forKey key: String) -> Bool {
        guard let value = unarchiving?.value(key) else { return false }
        if case .null = value { return false }
        return true
    }

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
    @ObjCMethod("decodeArrayOfObjectsOfClasses:forKey:")
    func decodeArray(ofClasses classes: NSObject?, forKey key: String) -> NSObject? { decodeObject(forKey: key) }
    @ObjCMethod("decodeDictionaryWithKeysOfClass:objectsOfClass:forKey:")
    func decodeDictionary(keysOfClass keys: ObjCClass?, objectsOfClass objects: ObjCClass?, forKey key: String) -> NSObject? { decodeObject(forKey: key) }
    @ObjCMethod("decodeTopLevelObjectForKey:error:")
    func decodeTopLevelObject(forKey key: String, error: UnsafeMutableRawPointer?) -> NSObject? { decodeObject(forKey: key) }
    @ObjCMethod("decodeTopLevelObjectOfClass:forKey:error:")
    func decodeTopLevelObject(ofClass cls: ObjCClass?, forKey key: String, error: UnsafeMutableRawPointer?) -> NSObject? { decodeObject(forKey: key) }

    private func number(_ key: String) -> (Int64, Double)? {
        switch unarchiving?.value(key) {
        case .integer(let value): return (value, Double(value))
        case .double(let value): return (Int64(value), value)
        case .bool(let value): return (value ? 1 : 0, value ? 1 : 0)
        case .object(let index):
            // A number archived as an object.
            guard let entry = unarchiving?.archive.objects[index], entry.className == "NSNumber" else { return nil }
            switch entry.value("NS.intval") ?? entry.value("NS.dblval") ?? entry.value("NS.boolval") {
            case .integer(let value): return (value, Double(value))
            case .double(let value): return (Int64(value), value)
            case .bool(let value): return (value ? 1 : 0, value ? 1 : 0)
            default: return nil
            }
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

    /// Geometry: a string, "{{0, 0}, {320, 480}}", or data whose first byte
    /// gives the element type (6: floats, 7: doubles).
    func doubles(_ key: String) -> [Double] {
        guard let unarchiving else { return [] }
        if case .object(let index)? = unarchiving.value(key), let text = unarchiving.string(at: index) {
            let separators: Set<Character> = ["{", "}", ",", " "]
            return text.split(whereSeparator: { separators.contains($0) }).compactMap { Double(String($0)) }
        }
        guard case .data(let bytes)? = unarchiving.value(key), let kind = bytes.first else { return [] }
        let size = kind == 6 ? 4 : 8
        return stride(from: 1, to: bytes.count - size + 1, by: size).map { offset in
            var raw: UInt64 = 0
            for index in 0..<size { raw |= UInt64(bytes[offset + index]) << (8 * index) }
            return size == 4 ? Double(Float(bitPattern: UInt32(raw))) : Double(bitPattern: raw)
        }
    }

    @ObjCMethod("decodePointForKey:")
    func decodePoint(forKey key: String) -> CGPoint {
        let v = doubles(key)
        return v.count >= 2 ? CGPoint(x: v[0], y: v[1]) : .zero
    }
    @ObjCMethod("decodeSizeForKey:")
    func decodeSize(forKey key: String) -> CGSize {
        let v = doubles(key)
        return v.count >= 2 ? CGSize(width: v[0], height: v[1]) : .zero
    }
    @ObjCMethod("decodeRectForKey:")
    func decodeRect(forKey key: String) -> CGRect {
        let v = doubles(key)
        return v.count >= 4 ? CGRect(x: v[0], y: v[1], width: v[2], height: v[3]) : .zero
    }
    @ObjCMethod("decodeCGPointForKey:") func decodeCGPoint(forKey key: String) -> CGPoint { decodePoint(forKey: key) }
    @ObjCMethod("decodeCGSizeForKey:") func decodeCGSize(forKey key: String) -> CGSize { decodeSize(forKey: key) }
    @ObjCMethod("decodeCGRectForKey:") func decodeCGRect(forKey key: String) -> CGRect { decodeRect(forKey: key) }

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

    /// The nib being instantiated, for AppKit's own classes.
    var nib: NibUnarchiving? { unarchiving }
}

/// Keyed decoding from any coder, for AppKit's -initWithCoder:.
struct Coder {
    let coder: NSObject

    var nib: NibUnarchiving? { coder.as(NSNibDecoder.self)?.nib }

    func has(_ key: String) -> Bool { coder.sendContainsValue(forKey: key) }
    func object(_ key: String) -> NSObject? {
        guard has(key), let object = coder.sendDecodeObject(forKey: key) else { return nil }
        return object.is(NSNull.self) ? nil : object
    }
    func string(_ key: String) -> String? { object(key).flatMap { $0.responds(to: "UTF8String") ? $0.stringValue : nil } }
    func bool(_ key: String) -> Bool { coder.sendDecodeBool(forKey: key) }
    func integer(_ key: String) -> Int { coder.sendDecodeInteger(forKey: key) }
    func double<T: BinaryFloatingPoint>(_ key: String) -> T { T(coder.sendDecodeDouble(forKey: key)) }
    func rect(_ key: String) -> CGRect { has(key) ? coder.sendDecodeRect(forKey: key) : .zero }
    func point(_ key: String) -> CGPoint { has(key) ? coder.sendDecodePoint(forKey: key) : .zero }
    func size(_ key: String) -> CGSize { has(key) ? coder.sendDecodeSize(forKey: key) : .zero }
    func array(_ key: String) -> [NSObject] { object(key)?.as(NSArray.self)?.elements ?? [] }
    func selector(_ key: String) -> ObjCSelector? { string(key).map { ObjCSelector($0) } }

    func bytes(_ key: String) -> [UInt8]? {
        guard has(key) else { return nil }
        var length: UInt = 0
        guard let bytes = coder.sendDecodeBytes(forKey: key, returnedLength: &length), length > 0 else { return nil }
        return Array(UnsafeRawBufferPointer(start: bytes, count: Int(length)))
    }

    /// A dictionary of strings to objects.
    func dictionary(_ key: String) -> [String: NSObject] { Nibs.strings(object(key)) }
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

// MARK: - NSNib

@ObjCClass("NSNib")
open class NSNib: NSObject {
    var archive: NibArchive?
    var directory: String?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithNibNamed:bundle:")
    public required init(nibNamed name: String?, bundle: NSObject?) {
        super.init()
        guard let name, let found = Nibs.find(name, bundle: bundle) else {
            appKitWarning("NSNib: no nib \(name ?? "")")
            return
        }
        (archive, directory) = (found.archive, found.directory)
    }

    @ObjCMethod("initWithNibData:bundle:")
    public required init(nibData data: NSObject?, bundle: NSObject?) {
        super.init()
        archive = NibArchive(data?.as(NSData.self)?.byteArray ?? [])
        directory = Nibs.directories(bundle).first
    }

    /// A nib inside another, as a table's cell views are kept.
    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init()
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        if let data = decoded.object("NSNibFileData")?.as(NSData.self) { archive = NibArchive(data.byteArray) }
        directory = decoded.nib?.bundlePath ?? Nibs.directories(nil).first
    }

    func instantiate(owner: NSObject?, external: [String: NSObject] = [:]) -> [NSObject] {
        guard let archive else { return [] }
        return Nibs.instantiate(archive, owner: owner, external: external, bundlePath: directory)
    }

    @ObjCMethod("instantiateWithOwner:topLevelObjects:")
    func instantiate(owner: NSObject?, topLevelObjects: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        guard archive != nil else { return false }
        let objects = instantiate(owner: owner)
        if let topLevelObjects {
            topLevelObjects.pointee = ObjCRuntime.autorelease(ObjCRuntime.retain(NSMutableArray.of(objects).objcObject))
        } else {
            Nibs.kept += objects
        }
        return true
    }

    @ObjCMethod("instantiateNibWithOwner:topLevelObjects:")
    func instantiateNib(owner: NSObject?, topLevelObjects: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        instantiate(owner: owner, topLevelObjects: topLevelObjects)
    }
}

/// -[NSBundle loadNibNamed:owner:topLevelObjects:], AppKit's addition.
@ObjCCategory("NSNibLoading")
extension NSBundle {
    @ObjCMethod("loadNibNamed:owner:topLevelObjects:")
    func loadNib(named name: String?, owner: NSObject?, topLevelObjects: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        NSNib(nibNamed: name, bundle: self).instantiate(owner: owner, topLevelObjects: topLevelObjects)
    }

    @ObjCClassMethod("loadNibNamed:owner:")
    static func loadNib(named name: String?, owner: NSObject?) -> Bool {
        NSNib(nibNamed: name, bundle: nil).instantiate(owner: owner, topLevelObjects: nil)
    }

    @ObjCClassMethod("loadNibFile:externalNameTable:withZone:")
    static func loadNibFile(_ path: String?, externalNameTable table: NSObject?, withZone zone: UnsafeMutableRawPointer?) -> Bool {
        guard let path, let bytes = Files.read(path) ?? Files.read(path + "/keyedobjects.nib"), let archive = NibArchive(bytes) else { return false }
        let owner = table?.as(NSDictionary.self)?.object(forKey: "NSOwner")
        let directory = "/" + path.split(separator: "/").dropLast().joined(separator: "/")
        Nibs.kept += Nibs.instantiate(archive, owner: owner, bundlePath: directory)
        return true
    }
}

/// The main nib, as NSApplicationMain loads it with the application as its
/// owner.
enum NibLoader {
    static func loadMainNib(named name: String, owner: NSObject) {
        guard let found = Nibs.find(name, bundle: nil) else {
            appKitWarning("no main nib \(name)")
            return
        }
        Nibs.kept += Nibs.instantiate(found.archive, owner: owner, bundlePath: found.directory)
    }
}

extension ObjCClass {
    /// Whether the class is `other` or inherits from it.
    func isSubclass(of other: ObjCClass) -> Bool {
        var current: ObjCClass? = self
        while let cls = current {
            if cls.pointer == other.pointer { return true }
            current = cls.superclass
        }
        return false
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

@ObjCWrapper("NSData")
class NSData: NSObject {}

@ObjCWrapper("NSMutableSet")
class NSMutableSet: NSObject {
    @ObjCClassMethod("set") static func empty() -> NSMutableSet
    @ObjCMethod("addObject:") func add(_ object: NSObject)
}

@ObjCWrapper("NSNull")
class NSNull: NSObject {
    @ObjCClassMethod("null") static func null() -> NSNull
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
}

extension Send {
    /// -initWithFrame: on an allocated view.
    static func initWithFrame(_ receiver: Object, _ frame: CGRect) -> Object? {
        typealias F = @convention(c) (Object, Selector, CGRect) -> Object?
        return unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector("initWithFrame:"), frame)
    }
}

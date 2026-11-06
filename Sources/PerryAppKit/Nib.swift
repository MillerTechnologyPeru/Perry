import Glibc
import PerryObjCInterop

// The main nib, as NSApplicationMain loads it: Interface Builder's
// compiled NIBArchive, a list of objects each with a class and keyed
// values. Its NSIBObjectData holds the objects, the root (File's Owner,
// the application) and the connections. Custom objects are made from
// their classes, except that one of an NSApplication subclass is the
// shared application, as AppKit's NSCustomObject decodes it; menus become
// NSMenus; outlets are set with their setters and actions given to their
// controls; then the objects hear -awakeFromNib. Views and windows in a
// nib aren't decoded here.

final class NibArchive {
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
        let fields: [(key: String, value: Value)]

        func value(_ key: String) -> Value? { fields.first { $0.key == key }?.value }
        func reference(_ key: String) -> Int? {
            if case .object(let index)? = value(key) { return index }
            return nil
        }
        /// The references a collection lists.
        var elements: [Int] {
            fields.compactMap { field in
                guard field.key == "UINibEncoderEmptyKey", case .object(let index) = field.value else { return nil }
                return index
            }
        }
    }

    let objects: [Object]

    init?(_ bytes: [UInt8]) {
        guard bytes.count >= 50, Array(bytes[0..<10]) == Array("NIBArchive".utf8) else { return nil }
        func u32(_ offset: Int) -> Int {
            Int(UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24)
        }
        // After the magic: the format and coder versions, then the count and
        // offset of the objects, keys, values and class names.
        let (objectCount, objectOffset) = (u32(18), u32(22))
        let (keyCount, keyOffset) = (u32(26), u32(30))
        let (valueCount, valueOffset) = (u32(34), u32(38))
        let (classCount, classOffset) = (u32(42), u32(46))
        var position = 0
        var failed = false
        // Variable-length integers: seven bits a byte, the last byte's high bit set.
        func varint() -> Int {
            var result = 0, shift = 0
            while position < bytes.count {
                let byte = Int(bytes[position])
                position += 1
                result |= (byte & 0x7f) << shift
                shift += 7
                if byte & 0x80 != 0 { return result }
            }
            failed = true
            return 0
        }
        func take(_ count: Int) -> ArraySlice<UInt8> {
            guard count >= 0, position + count <= bytes.count else {
                failed = true
                return []
            }
            defer { position += count }
            return bytes[position..<position + count]
        }
        func little<T: FixedWidthInteger>(_ type: T.Type) -> T {
            take(MemoryLayout<T>.size).reversed().reduce(T.zero) { $0 << 8 | T(truncatingIfNeeded: $1) }
        }

        position = keyOffset
        var keys: [String] = []
        for _ in 0..<keyCount { keys.append(String(decoding: take(varint()), as: UTF8.self)) }

        position = classOffset
        var classes: [String] = []
        for _ in 0..<classCount {
            let length = varint()
            let extras = varint()
            _ = take(extras * 4)
            classes.append(String(decoding: take(length).prefix { $0 != 0 }, as: UTF8.self))
        }

        position = valueOffset
        var values: [(key: String, value: Value)] = []
        for _ in 0..<valueCount {
            let key = varint()
            let type = take(1).first ?? 0
            let value: Value
            switch type {
            case 0: value = .integer(Int64(Int8(truncatingIfNeeded: little(UInt8.self))))
            case 1: value = .integer(Int64(Int16(truncatingIfNeeded: little(UInt16.self))))
            case 2: value = .integer(Int64(Int32(truncatingIfNeeded: little(UInt32.self))))
            case 3: value = .integer(Int64(truncatingIfNeeded: little(UInt64.self)))
            case 4: value = .bool(false)
            case 5: value = .bool(true)
            case 6: value = .double(Double(Float(bitPattern: little(UInt32.self))))
            case 7: value = .double(Double(bitPattern: little(UInt64.self)))
            case 8: value = .data(Array(take(varint())))
            case 9: value = .null
            case 10: value = .object(Int(little(UInt32.self)))
            default: return nil
            }
            values.append((keys.indices.contains(key) ? keys[key] : "", value))
        }

        position = objectOffset
        var objects: [Object] = []
        for _ in 0..<objectCount {
            let cls = varint(), start = varint(), count = varint()
            guard classes.indices.contains(cls), start + count <= values.count else { return nil }
            objects.append(Object(className: classes[cls], fields: Array(values[start..<start + count])))
        }
        guard !failed else { return nil }
        self.objects = objects
    }
}

/// Instantiates a main nib with the application as its owner.
final class NibLoader {
    let archive: NibArchive
    let owner: NSObject
    private var made: [Int: NSObject] = [:]
    private var awakening: [NSObject] = []
    private var root: Int?

    init(_ archive: NibArchive, owner: NSObject) {
        self.archive = archive
        self.owner = owner
    }

    static func loadMainNib(named name: String, owner: NSObject) {
        let path = NSBundle.main().bundlePath() + "/Contents/Resources/\(name).nib"
        guard let file = fopen(path, "rb") else {
            appKitWarning("no main nib at \(path)")
            return
        }
        defer { fclose(file) }
        var bytes: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = fread(&buffer, 1, buffer.count, file)
            if count <= 0 { break }
            bytes += buffer[0..<count]
        }
        guard let archive = NibArchive(bytes) else {
            appKitWarning("the main nib \(name) isn't a NIBArchive this AppKit reads")
            return
        }
        NibLoader(archive, owner: owner).instantiate()
    }

    func instantiate() {
        // The first object's IB.objectdata is the NSIBObjectData.
        guard let first = archive.objects.first, let dataIndex = first.reference("IB.objectdata"),
              archive.objects.indices.contains(dataIndex) else { return }
        let data = archive.objects[dataIndex]
        root = data.reference("NSRoot")
        // Every object the nib lists, made.
        if let keys = data.reference("NSObjectsKeys") {
            for index in archive.objects[keys].elements { _ = object(index) }
        }
        if let connections = data.reference("NSConnections") {
            for index in archive.objects[connections].elements { connect(archive.objects[index]) }
        }
        for object in awakening where object.responds(to: "awakeFromNib") { Send.void(object.objcObject, "awakeFromNib") }
        Trace.log("main nib: \(made.count) objects, \(awakening.count) awoken")
    }

    private func string(_ index: Int?) -> String? {
        guard let index, archive.objects.indices.contains(index) else { return nil }
        let object = archive.objects[index]
        guard object.className.hasSuffix("String"), case .data(let bytes)? = object.value("NS.bytes") else { return nil }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// The object at `index`, made once.
    private func object(_ index: Int?) -> NSObject? {
        guard let index, archive.objects.indices.contains(index) else { return nil }
        if index == root { return owner }
        if let object = made[index] { return object }
        let entry = archive.objects[index]
        let result: NSObject?
        switch entry.className {
        case "NSString", "NSMutableString":
            result = string(index).flatMap { $0.objCArgument() }.map { NSObject($0) }
        case "NSArray", "NSMutableArray", "NSSet", "NSMutableSet":
            result = NSMutableArray.of(entry.elements.compactMap { object($0) })
        case "NSNumber":
            if case .double(let value)? = entry.value("NS.dblval") { result = NSNumber.make(double: value) }
            else { result = NSNumber.make(double: Double(entry.value("NS.intval")?.integer ?? 0)) }
        case "NSCustomObject":
            result = customObject(entry)
        case "NSMenu":
            result = menu(index, entry)
        case "NSMenuItem":
            result = menuItem(index, entry)
        default:
            result = nil
        }
        if let result { made[index] = result }
        return result
    }

    private func customObject(_ entry: NibArchive.Object) -> NSObject? {
        guard let name = string(entry.reference("NSClassName")) else { return nil }
        guard let cls = Classes.named(name) else {
            appKitWarning("main nib: no class \(name)")
            return nil
        }
        if cls.isSubclass(of: NSApplication.objCClass) {
            return Send.object(cls.pointer, "sharedApplication").map(NSObject.init)
        }
        let object = cls.object.allocated().initialized()
        awakening.append(object)
        return object
    }

    private func menu(_ index: Int, _ entry: NibArchive.Object) -> NSObject {
        let menu = NSMenu(title: string(entry.reference("NSTitle")))
        made[index] = menu
        if let items = entry.reference("NSMenuItems") {
            for item in archive.objects[items].elements {
                if let item = object(item)?.as(NSMenuItem.self) { menu.addItem(item) }
            }
        }
        // The main menu, and the menus AppKit keeps by name.
        switch string(entry.reference("NSName")) {
        case "_NSMainMenu": App.shared?.mainMenu = menu
        case "_NSServicesMenu": App.shared?.servicesMenu = menu
        case "_NSHelpMenu": App.shared?.helpMenu = menu
        case "_NSWindowsMenu": App.shared?.windowsMenu = menu
        default: break
        }
        return menu
    }

    private func menuItem(_ index: Int, _ entry: NibArchive.Object) -> NSObject {
        let separator = entry.value("NSIsSeparator").flatMap(\.integer) == 1
        let item = separator ? NSMenuItem.separatorItem()
            : NSMenuItem(title: string(entry.reference("NSTitle")), action: nil, keyEquivalent: string(entry.reference("NSKeyEquiv")))
        made[index] = item
        if let mask = entry.value("NSKeyEquivModMask")?.integer { item.keyEquivalentModifierMask = UInt(mask) }
        if entry.value("NSIsDisabled")?.integer == 1 { item.enabled = false }
        if entry.value("NSIsHidden")?.integer == 1 { item.hidden = true }
        if let tag = entry.value("NSTag")?.integer { item.tag = Int(tag) }
        if let action = string(entry.reference("NSAction")) { item.action = ObjCSelector(action) }
        if let submenu = object(entry.reference("NSSubmenu"))?.as(NSMenu.self) { item.setSubmenu(submenu) }
        return item
    }

    /// An outlet, set through its setter; or an action, given to its control.
    private func connect(_ connector: NibArchive.Object) {
        guard let label = string(connector.reference("NSLabel")), let source = object(connector.reference("NSSource")) else { return }
        let destination = object(connector.reference("NSDestination"))
        switch connector.className {
        case "NSNibOutletConnector":
            guard let first = label.first else { return }
            let setter = "set" + first.uppercased() + label.dropFirst() + ":"
            if source.responds(to: setter) {
                Send.void(source.objcObject, setter, destination?.objcObject)
            } else {
                appKitWarning("main nib: \(label) outlet has no setter")
            }
        case "NSNibControlConnector":
            Send.void(source.objcObject, "setAction:", UnsafeMutableRawPointer(mutating: ObjCRuntime.selector(label)))
            Send.void(source.objcObject, "setTarget:", destination?.objcObject)
        default:
            break
        }
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

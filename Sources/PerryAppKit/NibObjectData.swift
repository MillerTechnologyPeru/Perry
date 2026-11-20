import CPerryGeometry
import Glibc
import PerryObjCInterop

// NSIBObjectData, a nib's root object, and the connectors it lists, for
// the programs that make nibs: Interface Builder's compiler fills them and
// archives them. They code the keys loading a nib reads (Nib.swift reads
// the archive itself, without these classes): the root object, each
// object's parent, name, ID and custom class, the connections, the windows
// shown when the nib loads, and the next free ID.

/// Foundation's C map tables, which Interface Builder fills with
/// NSMapInsert: objects to their parents, names and custom classes, and to
/// their integer IDs.
enum MapTables {
    typealias Table = UnsafeMutableRawPointer
    nonisolated(unsafe) private static let foundation = dlopen("libPerryFoundation.so", RTLD_NOW | RTLD_NOLOAD)
    private static func function<T>(_ name: String, _ type: T.Type) -> T? {
        dlsym(foundation, name).map { unsafeBitCast($0, to: T.self) }
    }
    private static let create = function("perry_create_map_table",
                                         (@convention(c) (UnsafeRawPointer?, UnsafeRawPointer?, UInt) -> Table?).self)
    private static let allKeys = function("_NSAllMapTableKeys", (@convention(c) (Table?) -> UnsafeMutableRawPointer?).self)
    private static let get = function("_NSMapGet", (@convention(c) (Table?, UnsafeRawPointer?) -> UnsafeMutableRawPointer?).self)
    private static let insert = function("_NSMapInsert", (@convention(c) (Table?, UnsafeRawPointer?, UnsafeRawPointer?) -> Void).self)

    /// Object keys, and object or integer values.
    static func make(integerValues: Bool) -> Table? {
        create?(dlsym(foundation, "_NSObjectMapKeyCallBacks"),
                dlsym(foundation, integerValues ? "_NSIntegerMapValueCallBacks" : "_NSObjectMapValueCallBacks"), 0)
    }

    /// The keys, and the value for each (an integer as an NSNumber).
    static func entries(_ table: Table?, integerValues: Bool) -> [(key: NSObject, value: NSObject)] {
        guard let table, let keys = allKeys?(table) else { return [] }
        return (NSObject(keys).as(NSArray.self)?.elements ?? []).compactMap { key in
            let value = get?(table, key.objcObject)
            if integerValues { return (key, NSNumber.make(integer: Int(bitPattern: value))) }
            return value.map { (key, NSObject($0)) }
        }
    }

    static func set(_ table: Table?, _ key: NSObject, _ value: NSObject, integerValues: Bool) {
        let stored = integerValues ? UnsafeRawPointer(bitPattern: Send.integer(value.objcObject, "integerValue")) : UnsafeRawPointer(value.objcObject)
        insert?(table, key.objcObject, stored)
    }
}

@ObjCClass("NSIBObjectData")
open class NSIBObjectData: NSObject {
    var rootObject: NSObject?
    var firstResponder: NSObject?
    var fontManager: NSObject?
    let objectTable = MapTables.make(integerValues: false)
    let nameTable = MapTables.make(integerValues: false)
    let oidTable = MapTables.make(integerValues: true)
    let classTable = MapTables.make(integerValues: false)
    var connections = NSMutableArray.of([])
    var visibleWindows = NSObject(Send.object(Classes.named("NSMutableSet")?.pointer, "set")!)
    var nextObjectID = 1
    var targetFramework: String?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init()
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        rootObject = decoded.object("NSRoot")
        firstResponder = decoded.object("NSFirstResponder")
        fontManager = decoded.object("NSFontManager")
        func fill(_ table: MapTables.Table?, _ keys: String, _ values: String, integerValues: Bool = false) {
            for (key, value) in zip(decoded.array(keys), decoded.array(values)) {
                MapTables.set(table, key, value, integerValues: integerValues)
            }
        }
        fill(objectTable, "NSObjectsKeys", "NSObjectsValues")
        fill(nameTable, "NSNamesKeys", "NSNamesValues")
        fill(oidTable, "NSOidsKeys", "NSOidsValues", integerValues: true)
        fill(classTable, "NSClassesKeys", "NSClassesValues")
        connections = NSMutableArray.of(decoded.array("NSConnections"))
        if let windows = decoded.object("NSVisibleWindows") { Send.void(visibleWindows.objcObject, "unionSet:", windows.objcObject) }
        nextObjectID = max(1, decoded.integer("NSNextOid"))
        targetFramework = decoded.string("NSFramework")
    }

    @ObjCMethod("encodeWithCoder:")
    func encode(with coder: NSObject?) {
        guard let coder else { return }
        let encoder = Encoder(coder: coder)
        func table(_ table: MapTables.Table?, _ keys: String, _ values: String, integerValues: Bool = false) {
            let pairs = MapTables.entries(table, integerValues: integerValues)
            encoder.object(NSMutableArray.of(pairs.map(\.key)), keys)
            encoder.object(NSMutableArray.of(pairs.map(\.value)), values)
        }
        encoder.object(rootObject, "NSRoot")
        table(objectTable, "NSObjectsKeys", "NSObjectsValues")
        table(nameTable, "NSNamesKeys", "NSNamesValues")
        table(oidTable, "NSOidsKeys", "NSOidsValues", integerValues: true)
        table(classTable, "NSClassesKeys", "NSClassesValues")
        encoder.object(connections, "NSConnections")
        encoder.object(visibleWindows, "NSVisibleWindows")
        encoder.object(firstResponder, "NSFirstResponder")
        encoder.object(fontManager, "NSFontManager")
        encoder.string(targetFramework, "NSFramework")
        encoder.integer(nextObjectID, "NSNextOid")
        encoder.object(NSMutableArray.of([]), "NSAccessibilityConnectors")
        encoder.object(NSMutableArray.of([]), "NSAccessibilityOidsKeys")
        encoder.object(NSMutableArray.of([]), "NSAccessibilityOidsValues")
    }

    @ObjCMethod("rootObject") func dataRootObject() -> NSObject? { rootObject }
    @ObjCMethod("setRootObject:") func setRootObject(_ value: NSObject?) { rootObject = value }
    @ObjCMethod("firstResponder") func dataFirstResponder() -> NSObject? { firstResponder }
    @ObjCMethod("setFirstResponder:") func setFirstResponder(_ value: NSObject?) { firstResponder = value }
    @ObjCMethod("fontManager") func dataFontManager() -> NSObject? { fontManager }
    @ObjCMethod("setFontManager:") func setFontManager(_ value: NSObject?) { fontManager = value }
    /// The C map tables, as AppKit's are.
    @ObjCMethod("objectTable") func dataObjectTable() -> UnsafeMutableRawPointer? { objectTable }
    @ObjCMethod("nameTable") func dataNameTable() -> UnsafeMutableRawPointer? { nameTable }
    @ObjCMethod("oidTable") func dataOidTable() -> UnsafeMutableRawPointer? { oidTable }
    @ObjCMethod("classTable") func dataClassTable() -> UnsafeMutableRawPointer? { classTable }
    @ObjCMethod("connections") func dataConnections() -> NSObject { connections }
    @ObjCMethod("setConnections:")
    func setConnections(_ value: NSObject?) { connections = NSMutableArray.of(value?.as(NSArray.self)?.elements ?? []) }
    @ObjCMethod("visibleWindows") func dataVisibleWindows() -> NSObject { visibleWindows }
    @ObjCMethod("setVisibleWindows:")
    func setVisibleWindows(_ value: NSObject?) {
        visibleWindows = NSObject(Send.object(Classes.named("NSMutableSet")?.pointer, "set")!)
        if let value { Send.void(visibleWindows.objcObject, "unionSet:", value.objcObject) }
    }
    @ObjCMethod("nextObjectID") func dataNextObjectID() -> Int { nextObjectID }
    @ObjCMethod("setNextObjectID:") func setNextObjectID(_ value: Int) { nextObjectID = value }
    @ObjCMethod("targetFramework") func dataTargetFramework() -> String? { targetFramework }
    @ObjCMethod("setTargetFramework:") func setTargetFramework(_ value: String?) { targetFramework = value }
}

/// A connection between two of a nib's objects: "NSSource",
/// "NSDestination" and "NSLabel" (an outlet's name or an action's).
@ObjCClass("NSNibConnector")
open class NSNibConnector: NSObject {
    var source: NSObject?
    var destination: NSObject?
    var label: String?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init()
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        source = decoded.object("NSSource")
        destination = decoded.object("NSDestination")
        label = decoded.string("NSLabel")
    }

    @ObjCMethod("encodeWithCoder:")
    func encode(with coder: NSObject?) {
        guard let coder else { return }
        let encoder = Encoder(coder: coder)
        encoder.object(source, "NSSource")
        encoder.object(destination, "NSDestination")
        encoder.string(label, "NSLabel")
    }

    @ObjCMethod("source") func connectorSource() -> NSObject? { source }
    @ObjCMethod("setSource:") func setSource(_ value: NSObject?) { source = value }
    @ObjCMethod("destination") func connectorDestination() -> NSObject? { destination }
    @ObjCMethod("setDestination:") func setDestination(_ value: NSObject?) { destination = value }
    @ObjCMethod("label") func connectorLabel() -> String? { label }
    @ObjCMethod("setLabel:") func setLabel(_ value: String?) { label = value }
    @ObjCMethod("replaceObject:withObject:")
    func replaceObject(_ old: NSObject?, with new: NSObject?) {
        if source?.objcObject == old?.objcObject { source = new }
        if destination?.objcObject == old?.objcObject { destination = new }
    }
    @ObjCMethod("establishConnection") func establishConnection() {}
}

/// An outlet: the source's outlet named by the label is the destination.
@ObjCClass("NSNibOutletConnector")
open class NSNibOutletConnector: NSNibConnector {
    @ObjCMethod("establishConnection")
    override func establishConnection() {
        guard let source, let label else { return }
        Send.void(source.objcObject, "setValue:forKey:", destination?.objcObject, NSObject(objCReturnValue: label.objCReturnValue()).objcObject)
    }
}

/// An action: the source (a control or menu item) sends the label's
/// action to the destination.
@ObjCClass("NSNibControlConnector")
open class NSNibControlConnector: NSNibConnector {
    @ObjCMethod("establishConnection")
    override func establishConnection() {
        guard let source else { return }
        Send.void(source.objcObject, "setTarget:", destination?.objcObject)
        if let label { Send.void(source.objcObject, "setAction:", UnsafeMutableRawPointer(mutating: ObjCRuntime.selector(label))) }
    }
}

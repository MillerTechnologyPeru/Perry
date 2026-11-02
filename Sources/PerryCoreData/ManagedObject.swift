import Glibc
import CoreModel
import FoundationEssentials
import PerryObjCInterop

// Managed objects: their values as CoreModel attribute and relationship
// values, the typed accessors Core Data generates for @dynamic properties,
// key-value coding, and change tracking.

final class ManagedObjectState: ObjectState {
    var entity: NSEntityDescription?
    /// The context; not retained (the context retains its objects).
    var context: UnsafeMutableRawPointer?
    var store: NSPersistentStore?
    var id = ObjectID(rawValue: "")
    var objectID: NSManagedObjectID?
    var attributes: [String: AttributeValue] = [:]
    var relationships: [String: RelationshipValue] = [:]
    var inserted = false
    var updated = false
    var deleted = false
    /// The values last saved or fetched, for rollback and changedValues.
    var committed: ModelData?

    var entityName: String { entity?.state.name ?? "" }

    var modelData: ModelData {
        ModelData(entity: EntityName(rawValue: entityName), id: id,
                  attributes: Dictionary(uniqueKeysWithValues: attributes.map { (PropertyKey(rawValue: $0.key), $0.value) }),
                  relationships: Dictionary(uniqueKeysWithValues: relationships.map { (PropertyKey(rawValue: $0.key), $0.value) }))
    }

    func load(_ data: ModelData) {
        attributes = Dictionary(uniqueKeysWithValues: data.attributes.map { ($0.key.rawValue, $0.value) })
        relationships = Dictionary(uniqueKeysWithValues: data.relationships.map { ($0.key.rawValue, $0.value) })
        committed = data
    }
}

enum ManagedObjects {
    static let states = StateTable<ManagedObjectState>()
    nonisolated(unsafe) static var entitiesByClass: [String: NSEntityDescription] = [:]
    nonisolated(unsafe) static var installed: Set<String> = []
    static let lock = Lock()

    /// The class an entity's objects are instances of.
    static func objectClass(_ entity: NSEntityDescription) -> ObjCClass {
        Classes.named(entity.state.className) ?? NSManagedObject.objCClass
    }

    // MARK: Values as objects

    static func object(_ value: AttributeValue) -> NSObject? {
        switch value {
        case .null: return nil
        case .string(let text): return NSObject(text.objCArgument()!)
        case .int16(let number): return NSNumber.make(int64: Int64(number))
        case .int32(let number): return NSNumber.make(int64: Int64(number))
        case .int64(let number): return NSNumber.make(int64: number)
        case .float(let number): return NSNumber.make(float: number)
        case .double(let number): return NSNumber.make(double: number)
        case .bool(let flag): return NSNumber.make(bool: flag)
        case .date(let date): return NSDate.make(sinceReferenceDate: date.timeIntervalSinceReferenceDate)
        case .data(let data): return data.withUnsafeBytes { NSData.make(bytes: $0.baseAddress, length: UInt($0.count)) }
        case .uuid(let uuid): return NSUUID.objCClass.object.allocated().initializeUUID(string: uuid.uuidString)
        case .url(let url): return NSURL.make(string: url.absoluteString)
        case .decimal(let decimal): return NSNumber.make(double: Double("\(decimal)") ?? 0)
        case .composite: return nil
        }
    }

    static func value(_ object: NSObject?, kind: UInt) -> AttributeValue {
        guard let object, !object.isKind(of: ObjCClass(named: "NSNull")) else { return .null }
        switch kind {
        case AttributeKind.int16: return .int16(Int16(truncatingIfNeeded: object.unsafeCast(to: NSNumber.self).int64Value()))
        case AttributeKind.int32: return .int32(Int32(truncatingIfNeeded: object.unsafeCast(to: NSNumber.self).int64Value()))
        case AttributeKind.int64: return .int64(object.unsafeCast(to: NSNumber.self).int64Value())
        case AttributeKind.double: return .double(object.unsafeCast(to: NSNumber.self).doubleValue())
        case AttributeKind.float: return .float(Float(object.unsafeCast(to: NSNumber.self).doubleValue()))
        case AttributeKind.boolean: return .bool(object.unsafeCast(to: NSNumber.self).boolValue())
        case AttributeKind.decimal: return .decimal(Decimal(object.unsafeCast(to: NSNumber.self).doubleValue()))
        case AttributeKind.date:
            return .date(Date(timeIntervalSinceReferenceDate: object.unsafeCast(to: NSDate.self).timeIntervalSinceReferenceDate()))
        case AttributeKind.binary, AttributeKind.transformable:
            let data = object.unsafeCast(to: NSData.self)
            return .data(Data(bytes: data.bytes() ?? UnsafeRawPointer(bitPattern: 1)!, count: Int(data.length())))
        case AttributeKind.uuid:
            return UUID(uuidString: object.unsafeCast(to: NSUUID.self).uuidString()).map(AttributeValue.uuid) ?? .null
        case AttributeKind.uri:
            return URL(string: object.unsafeCast(to: NSURL.self).absoluteString() ?? "").map(AttributeValue.url) ?? .null
        default:
            return .string(object.stringValue)
        }
    }

    // MARK: Reading and writing properties

    static func context(_ state: ManagedObjectState) -> NSManagedObjectContext? {
        state.context.map { NSManagedObjectContext(objcObject: $0, ownership: .retain) }
    }

    /// A property's value as an object: an attribute's value, a to-one
    /// relationship's object, or a to-many relationship's set.
    static func value(_ object: NSManagedObject, _ key: String) -> NSObject? {
        let state = object.state
        guard let property = state.entity?.property(named: key) else {
            coreDataFatal("[<\(state.entityName)> valueForUndefinedKey:]: the entity \(state.entityName) is not key value coding-compliant for the key \"\(key)\".")
        }
        if let relationship = property.as(NSRelationshipDescription.self) {
            let targets = related(object, relationship)
            return relationship.isToMany ? NSMutableSet.of(targets) : targets.first
        }
        return self.object(state.attributes[key] ?? .null)
    }

    static func setValue(_ object: NSManagedObject, _ key: String, _ value: NSObject?) {
        let state = object.state
        guard let property = state.entity?.property(named: key) else {
            coreDataFatal("[<\(state.entityName)> setValue:forUndefinedKey:]: the entity \(state.entityName) is not key value coding-compliant for the key \"\(key)\".")
        }
        if let relationship = property.as(NSRelationshipDescription.self) {
            if relationship.isToMany {
                let wanted = value?.unsafeCast(to: NSSet.self).allObjects().elements.map { $0.unsafeCast(to: NSManagedObject.self) } ?? []
                let current = related(object, relationship)
                for old in current where !wanted.contains(where: { $0.objcObject == old.objcObject }) {
                    unlink(object, relationship, old)
                }
                for new in wanted where !current.contains(where: { $0.objcObject == new.objcObject }) {
                    link(object, relationship, new)
                }
            } else {
                for old in related(object, relationship) { unlink(object, relationship, old) }
                if let target = value?.unsafeCast(to: NSManagedObject.self) { link(object, relationship, target) }
            }
            return
        }
        let kind = property.state.attributeType
        let newValue = self.value(value, kind: kind)
        if state.attributes[key] != newValue {
            state.attributes[key] = newValue
            changed(object)
        }
    }

    /// The objects a relationship holds.
    static func related(_ object: NSManagedObject, _ relationship: NSRelationshipDescription) -> [NSManagedObject] {
        let state = object.state
        guard let context = context(state), let destination = relationship.destination else { return [] }
        let ids: [ObjectID]
        switch state.relationships[relationship.state.name] ?? .null {
        case .null: ids = []
        case .toOne(let id): ids = [id]
        case .toMany(let many): ids = many
        }
        return ids.compactMap { context.object(entity: destination, id: $0) }
    }

    private static func add(_ id: ObjectID, to object: NSManagedObject, _ key: String, toMany: Bool) {
        let state = object.state
        if toMany {
            var ids: [ObjectID] = []
            if case .toMany(let existing)? = state.relationships[key] { ids = existing }
            guard !ids.contains(id) else { return }
            state.relationships[key] = .toMany(ids + [id])
        } else {
            state.relationships[key] = .toOne(id)
        }
        changed(object)
    }

    private static func remove(_ id: ObjectID, from object: NSManagedObject, _ key: String) {
        let state = object.state
        switch state.relationships[key] {
        case .toOne(let current)? where current == id:
            state.relationships[key] = .null
        case .toMany(let ids)? where ids.contains(id):
            state.relationships[key] = .toMany(ids.filter { $0 != id })
        default:
            return
        }
        changed(object)
    }

    /// Connects two objects through a relationship and its inverse; a
    /// to-one inverse first leaves its previous object.
    static func link(_ object: NSManagedObject, _ relationship: NSRelationshipDescription, _ target: NSManagedObject) {
        if !relationship.isToMany {
            for old in related(object, relationship) where old.objcObject != target.objcObject {
                unlink(object, relationship, old)
            }
        }
        add(target.state.id, to: object, relationship.state.name, toMany: relationship.isToMany)
        guard let inverse = relationship.inverse else { return }
        if !inverse.isToMany {
            for previous in related(target, inverse) where previous.objcObject != object.objcObject {
                unlink(target, inverse, previous)
            }
        }
        add(object.state.id, to: target, inverse.state.name, toMany: inverse.isToMany)
    }

    static func unlink(_ object: NSManagedObject, _ relationship: NSRelationshipDescription, _ target: NSManagedObject) {
        remove(target.state.id, from: object, relationship.state.name)
        if let inverse = relationship.inverse {
            remove(object.state.id, from: target, inverse.state.name)
        }
    }

    /// Marks a saved object changed in its context.
    static func changed(_ object: NSManagedObject) {
        let state = object.state
        guard !state.inserted, !state.deleted, !state.updated, let context = context(state) else { return }
        state.updated = true
        context.state.updated.append(object)
    }

    // MARK: Accessors for @dynamic properties

    /// Generates accessors for a model's entity classes: a getter and a
    /// setter per property, typed as the class declares the property, and
    /// for to-many relationships add<Key>Object:, remove<Key>Object:,
    /// add<Key>: and remove<Key>:. Methods a class implements are kept.
    static func install(_ model: NSManagedObjectModel) {
        lock.withLock {
            for entity in model.entityList {
                let className = entity.state.className
                entitiesByClass[className] = entity
                guard className != "NSManagedObject", !installed.contains(className),
                      let cls = Classes.named(className) else { continue }
                installed.insert(className)
                for property in entity.state.properties {
                    let name = property.state.name
                    let capitalized = name.prefix(1).uppercased() + name.dropFirst()
                    let relationship = property.as(NSRelationshipDescription.self)
                    let declared = Runtime.propertyType(cls, name) ?? "@"
                    let code = declared.first.map(String.init) ?? "@"
                    let accessors = Accessors.pair(code)
                    add(cls, name, accessors.getterTypes, accessors.getter)
                    add(cls, "set\(capitalized):", accessors.setterTypes, accessors.setter)
                    if relationship?.isToMany == true {
                        add(cls, "add\(capitalized)Object:", "v24@0:8@16", Accessors.addObject)
                        add(cls, "remove\(capitalized)Object:", "v24@0:8@16", Accessors.removeObject)
                        add(cls, "add\(capitalized):", "v24@0:8@16", Accessors.addObjects)
                        add(cls, "remove\(capitalized):", "v24@0:8@16", Accessors.removeObjects)
                    }
                }
            }
        }
    }

    private static func add(_ cls: ObjCClass, _ selector: String, _ types: String, _ implementation: UnsafeRawPointer) {
        let encoding = UnsafePointer(strdup(types)!)
        _ = ObjCRuntime.functions.addMethod(cls.pointer, ObjCRuntime.selector(selector), implementation, encoding)
    }

    /// The property a setter or mutator names: "setURL:" and "setUrl:"
    /// name whichever the entity has.
    static func key(_ object: NSManagedObject, selector: UnsafeRawPointer?, prefix: String, suffix: String) -> String {
        let name = selector.map { String(cString: $0.assumingMemoryBound(to: CChar.self)) } ?? ""
        let middle = String(name.dropFirst(prefix.count).dropLast(suffix.count))
        let properties = object.state.entity?.state.properties.map(\.state.name) ?? []
        return properties.first { $0 == middle }
            ?? properties.first { $0.prefix(1).uppercased() + $0.dropFirst() == middle }
            ?? middle.prefix(1).lowercased() + middle.dropFirst()
    }
}

/// Accessor implementations, one per declared type; each finds its key from
/// its selector.
enum Accessors {
    typealias Object = UnsafeMutableRawPointer?
    typealias Selector = UnsafeRawPointer?

    static func wrap(_ object: Object) -> NSManagedObject { NSManagedObject(objcObject: object!, ownership: .retain) }
    static func getterKey(_ selector: Selector) -> String {
        selector.map { String(cString: $0.assumingMemoryBound(to: CChar.self)) } ?? ""
    }

    static func get(_ object: Object, _ selector: Selector) -> NSObject? {
        let managed = wrap(object)
        return ManagedObjects.value(managed, getterKey(selector))
    }

    static func set(_ object: Object, _ selector: Selector, _ value: NSObject?) {
        let managed = wrap(object)
        ManagedObjects.setValue(managed, ManagedObjects.key(managed, selector: selector, prefix: "set", suffix: ":"), value)
    }

    static func number(_ object: Object, _ selector: Selector) -> NSNumber? {
        get(object, selector)?.unsafeCast(to: NSNumber.self)
    }

    static func implementation<F>(_ function: F) -> UnsafeRawPointer { unsafeBitCast(function, to: UnsafeRawPointer.self) }

    struct Pair {
        let getter: UnsafeRawPointer
        let setter: UnsafeRawPointer
        let getterTypes: String
        let setterTypes: String
    }

    /// The getter and setter for a type encoding's first character.
    static func pair(_ code: String) -> Pair {
        switch code {
        case "q", "Q", "l", "L":
            return Pair(getter: implementation({ (o: Object, s: Selector) -> Int64 in Accessors.number(o, s)?.int64Value() ?? 0 } as @convention(c) (Object, Selector) -> Int64),
                        setter: implementation({ (o: Object, s: Selector, v: Int64) in Accessors.set(o, s, NSNumber.make(int64: v)) } as @convention(c) (Object, Selector, Int64) -> Void),
                        getterTypes: "\(code)16@0:8", setterTypes: "v24@0:8\(code)16")
        case "i", "I":
            return Pair(getter: implementation({ (o: Object, s: Selector) -> Int32 in Int32(truncatingIfNeeded: Accessors.number(o, s)?.int64Value() ?? 0) } as @convention(c) (Object, Selector) -> Int32),
                        setter: implementation({ (o: Object, s: Selector, v: Int32) in Accessors.set(o, s, NSNumber.make(int64: Int64(v))) } as @convention(c) (Object, Selector, Int32) -> Void),
                        getterTypes: "\(code)16@0:8", setterTypes: "v20@0:8\(code)16")
        case "s", "S":
            return Pair(getter: implementation({ (o: Object, s: Selector) -> Int16 in Int16(truncatingIfNeeded: Accessors.number(o, s)?.int64Value() ?? 0) } as @convention(c) (Object, Selector) -> Int16),
                        setter: implementation({ (o: Object, s: Selector, v: Int16) in Accessors.set(o, s, NSNumber.make(int64: Int64(v))) } as @convention(c) (Object, Selector, Int16) -> Void),
                        getterTypes: "\(code)16@0:8", setterTypes: "v20@0:8\(code)16")
        case "B", "c", "C":
            return Pair(getter: implementation({ (o: Object, s: Selector) -> Bool in Accessors.number(o, s)?.boolValue() ?? false } as @convention(c) (Object, Selector) -> Bool),
                        setter: implementation({ (o: Object, s: Selector, v: Bool) in Accessors.set(o, s, NSNumber.make(bool: v)) } as @convention(c) (Object, Selector, Bool) -> Void),
                        getterTypes: "\(code)16@0:8", setterTypes: "v20@0:8\(code)16")
        case "d":
            return Pair(getter: implementation({ (o: Object, s: Selector) -> Double in Accessors.number(o, s)?.doubleValue() ?? 0 } as @convention(c) (Object, Selector) -> Double),
                        setter: implementation({ (o: Object, s: Selector, v: Double) in Accessors.set(o, s, NSNumber.make(double: v)) } as @convention(c) (Object, Selector, Double) -> Void),
                        getterTypes: "d16@0:8", setterTypes: "v24@0:8d16")
        case "f":
            return Pair(getter: implementation({ (o: Object, s: Selector) -> Float in Float(Accessors.number(o, s)?.doubleValue() ?? 0) } as @convention(c) (Object, Selector) -> Float),
                        setter: implementation({ (o: Object, s: Selector, v: Float) in Accessors.set(o, s, NSNumber.make(float: v)) } as @convention(c) (Object, Selector, Float) -> Void),
                        getterTypes: "f16@0:8", setterTypes: "v20@0:8f16")
        default:
            return Pair(getter: implementation({ (o: Object, s: Selector) -> Object in Accessors.get(o, s)?.objCReturnValue() ?? nil } as @convention(c) (Object, Selector) -> Object),
                        setter: implementation({ (o: Object, s: Selector, v: Object) in Accessors.set(o, s, v.map(NSObject.init)) } as @convention(c) (Object, Selector, Object) -> Void),
                        getterTypes: "@16@0:8", setterTypes: "v24@0:8@16")
        }
    }

    static func mutate(_ object: Object, _ selector: Selector, prefix: String, suffix: String, _ values: [NSManagedObject], adding: Bool) {
        let managed = wrap(object)
        let key = ManagedObjects.key(managed, selector: selector, prefix: prefix, suffix: suffix)
        guard let relationship = managed.state.entity?.property(named: key)?.as(NSRelationshipDescription.self) else { return }
        for value in values {
            if adding { ManagedObjects.link(managed, relationship, value) } else { ManagedObjects.unlink(managed, relationship, value) }
        }
    }

    static func members(_ set: Object) -> [NSManagedObject] {
        set.map { NSObject($0).unsafeCast(to: NSSet.self).allObjects().elements.map { $0.unsafeCast(to: NSManagedObject.self) } } ?? []
    }

    nonisolated(unsafe) static let addObject = implementation({ (o: Object, s: Selector, v: Object) in
        Accessors.mutate(o, s, prefix: "add", suffix: "Object:", v.map { [Accessors.wrap($0)] } ?? [], adding: true)
    } as @convention(c) (Object, Selector, Object) -> Void)
    nonisolated(unsafe) static let removeObject = implementation({ (o: Object, s: Selector, v: Object) in
        Accessors.mutate(o, s, prefix: "remove", suffix: "Object:", v.map { [Accessors.wrap($0)] } ?? [], adding: false)
    } as @convention(c) (Object, Selector, Object) -> Void)
    nonisolated(unsafe) static let addObjects = implementation({ (o: Object, s: Selector, v: Object) in
        Accessors.mutate(o, s, prefix: "add", suffix: ":", Accessors.members(v), adding: true)
    } as @convention(c) (Object, Selector, Object) -> Void)
    nonisolated(unsafe) static let removeObjects = implementation({ (o: Object, s: Selector, v: Object) in
        Accessors.mutate(o, s, prefix: "remove", suffix: ":", Accessors.members(v), adding: false)
    } as @convention(c) (Object, Selector, Object) -> Void)
}

// MARK: - NSManagedObject

@ObjCClass("NSManagedObject")
open class NSManagedObject: NSObject {
    var state: ManagedObjectState { ManagedObjects.states[objcObject] }

    var context: NSManagedObjectContext? { ManagedObjects.context(state) }

    @ObjCMethod("initWithEntity:insertIntoManagedObjectContext:")
    func initialize(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?) -> Self {
        state.entity = entity
        context?.insert(self)
        return self
    }

    /// The entity whose class is the receiver's class.
    @ObjCMethod("initWithContext:")
    func initialize(context: NSManagedObjectContext) -> Self {
        let className = Runtime.name(objCClass)
        guard let entity = context.coordinator?.model?.entityList.first(where: { $0.state.className == className })
                ?? ManagedObjects.entitiesByClass[className] else {
            coreDataFatal("An NSManagedObject of class '\(className)' must have a valid NSEntityDescription.")
        }
        return initialize(entity: entity, insertInto: context)
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        ManagedObjects.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSManagedObject.objCClass.pointer)
    }

    /// The entity of the receiving class, from the models in use.
    @ObjCClassMethod("entity")
    static func entityOfClass(_ cls: ObjCClass) -> NSEntityDescription? {
        ManagedObjects.lock.withLock { ManagedObjects.entitiesByClass[Runtime.name(cls)] }
    }

    @ObjCClassMethod("fetchRequest")
    static func fetchRequest(_ cls: ObjCClass) -> NSFetchRequest {
        let request = NSFetchRequest.objCClass.object.newInstance().unsafeCast(to: NSFetchRequest.self)
        let entity = entityOfClass(cls)
        request.state.entityName = entity?.state.name ?? Runtime.name(cls)
        request.state.entity = entity
        return request
    }

    @ObjCMethod("entity") func entity() -> NSEntityDescription? { state.entity }
    @ObjCMethod("managedObjectContext") func managedObjectContext() -> NSManagedObjectContext? { context }
    @ObjCMethod("objectID") func objectID() -> NSManagedObjectID? { state.objectID }
    @ObjCMethod("isInserted") func isInserted() -> Bool { state.inserted }
    @ObjCMethod("isUpdated") func isUpdated() -> Bool { state.updated }
    @ObjCMethod("isDeleted") func isDeleted() -> Bool { state.deleted }
    @ObjCMethod("isFault") func isFault() -> Bool { false }
    @ObjCMethod("hasChanges") func hasChanges() -> Bool { state.inserted || state.updated || state.deleted }
    @ObjCMethod("hasPersistentChangedValues") func hasPersistentChangedValues() -> Bool { hasChanges() }

    @ObjCMethod("valueForKey:")
    func value(forKey key: String) -> NSObject? { ManagedObjects.value(self, key) }

    @ObjCMethod("setValue:forKey:")
    func setValue(_ value: NSObject?, forKey key: String) { ManagedObjects.setValue(self, key, value) }

    @ObjCMethod("primitiveValueForKey:")
    func primitiveValue(forKey key: String) -> NSObject? { ManagedObjects.value(self, key) }

    @ObjCMethod("setPrimitiveValue:forKey:")
    func setPrimitiveValue(_ value: NSObject?, forKey key: String) { ManagedObjects.setValue(self, key, value) }

    /// A key path through relationships.
    @ObjCMethod("valueForKeyPath:")
    func value(forKeyPath path: String) -> NSObject? {
        var current: NSObject? = self
        for key in path.split(separator: ".") {
            guard let object = current?.as(NSManagedObject.self) else { return nil }
            current = ManagedObjects.value(object, String(key))
        }
        return current
    }

    /// The relationship's objects, as a set; changing the set does not
    /// change the relationship.
    @ObjCMethod("mutableSetValueForKey:")
    func mutableSetValue(forKey key: String) -> NSObject? { ManagedObjects.value(self, key) }

    /// The values changed since the last save or fetch.
    @ObjCMethod("changedValues")
    func changedValues() -> NSObject {
        let committed = state.committed
        var entries: [(String, NSObject)] = []
        for (key, value) in state.attributes.sorted(by: { $0.key < $1.key })
        where committed?.attributes[PropertyKey(rawValue: key)] != value {
            entries.append((key, ManagedObjects.object(value) ?? NSObject(ObjCClass(named: "NSNull").object.newInstance().objcObject)))
        }
        for (key, value) in state.relationships.sorted(by: { $0.key < $1.key })
        where committed?.relationships[PropertyKey(rawValue: key)] != value {
            if let object = ManagedObjects.value(self, key) { entries.append((key, object)) }
        }
        return NSMutableDictionary.of(entries)
    }

    @ObjCMethod("willChangeValueForKey:") func willChangeValue(forKey key: String?) {}
    @ObjCMethod("didChangeValueForKey:") func didChangeValue(forKey key: String?) {}
    @ObjCMethod("willAccessValueForKey:") func willAccessValue(forKey key: String?) {}
    @ObjCMethod("didAccessValueForKey:") func didAccessValue(forKey key: String?) {}

    // Lifecycle hooks, for subclasses.
    @ObjCMethod("awakeFromInsert") func awakeFromInsert() {}
    @ObjCMethod("awakeFromFetch") func awakeFromFetch() {}
    @ObjCMethod("willSave") func willSave() {}
    @ObjCMethod("didSave") func didSave() {}
    @ObjCMethod("prepareForDeletion") func prepareForDeletion() {}
    @ObjCMethod("willTurnIntoFault") func willTurnIntoFault() {}
    @ObjCMethod("didTurnIntoFault") func didTurnIntoFault() {}

    @ObjCMethod("description")
    func description() -> String {
        let pointer = String(UInt(bitPattern: objcObject), radix: 16)
        return "<\(Runtime.name(objCClass)): 0x\(pointer)> (entity: \(state.entityName); id: \(state.objectID?.uri ?? "nil"))"
    }
}

/// Messages to managed objects, sent so subclasses' overrides run.
extension NSObject {
    @ObjCMethod("initWithEntity:insertIntoManagedObjectContext:")
    func initializeManagedObject(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?) -> NSObject
    @ObjCMethod("awakeFromInsert") func sendAwakeFromInsert()
    @ObjCMethod("awakeFromFetch") func sendAwakeFromFetch()
    @ObjCMethod("willSave") func sendWillSave()
    @ObjCMethod("didSave") func sendDidSave()
    @ObjCMethod("prepareForDeletion") func sendPrepareForDeletion()
}

// MARK: - NSManagedObjectID

final class ObjectIDState: ObjectState {
    var entity: NSEntityDescription?
    var store: NSPersistentStore?
    var id = ObjectID(rawValue: "")
    var temporary = false
    /// A temporary ID's token, which its URI uses until it is saved.
    var token = ""
}

@ObjCClass("NSManagedObjectID")
open class NSManagedObjectID: NSObject {
    static let states = StateTable<ObjectIDState>()
    var state: ObjectIDState { NSManagedObjectID.states[objcObject] }

    static func make(entity: NSEntityDescription?, store: NSPersistentStore?, id: ObjectID, temporary: Bool) -> NSManagedObjectID {
        let objectID = NSManagedObjectID.objCClass.object.newInstance().unsafeCast(to: NSManagedObjectID.self)
        objectID.state.entity = entity
        objectID.state.store = store
        objectID.state.id = id
        objectID.state.temporary = temporary
        if temporary { objectID.state.token = "t" + NSUUID.make().uuidString() }
        return objectID
    }

    /// x-coredata://store/Entity/p1, or x-coredata:///Entity/tUUID while
    /// temporary.
    var uri: String {
        let entity = state.entity?.state.name ?? ""
        if state.temporary { return "x-coredata:///\(entity)/\(state.token)" }
        let row = state.id.rawValue.split(separator: "/").last.map(String.init) ?? state.id.rawValue
        return "x-coredata://\(state.store?.state.identifier ?? "")/\(entity)/\(row)"
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        NSManagedObjectID.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSManagedObjectID.objCClass.pointer)
    }

    @ObjCMethod("entity") func entity() -> NSEntityDescription? { state.entity }
    @ObjCMethod("persistentStore") func persistentStore() -> NSPersistentStore? { state.store }
    @ObjCMethod("isTemporaryID") func isTemporaryID() -> Bool { state.temporary }
    @ObjCMethod("URIRepresentation") func uriRepresentation() -> NSURL? { NSURL.make(string: uri) }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: NSObject?) -> Bool {
        guard let other = other?.as(NSManagedObjectID.self) else { return false }
        return other.uri == uri
    }

    @ObjCMethod("hash") func hash() -> UInt { UInt(bitPattern: uri.hashValue) }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> NSManagedObjectID { self }
    @ObjCMethod("description") func description() -> String {
        "0x\(String(UInt(bitPattern: objcObject), radix: 16)) <\(uri)>"
    }
}

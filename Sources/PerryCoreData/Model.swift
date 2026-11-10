import CoreModel
import PerryObjCInterop

// The managed object model: entities and their attributes and
// relationships, built in code or decoded from a compiled .mom (a keyed
// archive momc writes) through -initWithCoder:, and converted to a
// CoreModel model for the stores.

/// NSAttributeType.
enum AttributeKind {
    static let undefined: UInt = 0, int16: UInt = 100, int32: UInt = 200, int64: UInt = 300, decimal: UInt = 400
    static let double: UInt = 500, float: UInt = 600, string: UInt = 700, boolean: UInt = 800, date: UInt = 900
    static let binary: UInt = 1000, uuid: UInt = 1100, uri: UInt = 1200, transformable: UInt = 1800, objectID: UInt = 2000

    static func coreModelType(_ kind: UInt) -> AttributeType {
        switch kind {
        case int16: return .int16
        case int32: return .int32
        case int64: return .int64
        case decimal: return .decimal
        case double: return .double
        case float: return .float
        case boolean: return .bool
        case date: return .date
        case binary, transformable: return .data
        case uuid: return .uuid
        case uri: return .url
        default: return .string
        }
    }

    /// The class of an attribute's values.
    static func className(_ kind: UInt) -> String? {
        switch kind {
        case int16, int32, int64, double, float, boolean: return "NSNumber"
        case decimal: return "NSDecimalNumber"
        case string: return "NSString"
        case date: return "NSDate"
        case binary: return "NSData"
        case uuid: return "NSUUID"
        case uri: return "NSURL"
        default: return nil
        }
    }
}

/// NSDeleteRule.
enum DeleteRule {
    static let noAction: UInt = 0, nullify: UInt = 1, cascade: UInt = 2, deny: UInt = 3
}

// MARK: - State

final class ModelState: ObjectState {
    var entities: [NSEntityDescription] = []
}

final class EntityState: ObjectState {
    var name = ""
    var className = "NSManagedObject"
    var properties: [NSPropertyDescription] = []
    var abstract = false
    /// The model; not retained.
    var model: UnsafeMutableRawPointer?
}

final class PropertyState: ObjectState {
    var name = ""
    var optional = true
    var transient = false
    /// Whether the store should index it, and whether Spotlight should:
    /// kept and given back, as stores here index nothing by them.
    var indexed = false
    var indexedBySpotlight = false
    /// The entity; not retained.
    var entity: UnsafeMutableRawPointer?
    // Attributes.
    var attributeType = AttributeKind.undefined
    var defaultValue: NSObject?
    /// The class a program names for the attribute's values, the name of
    /// a transformable attribute's transformer, and the dictionary of its
    /// own a program gives a property: kept and given back.
    var valueClassName: String?
    var valueTransformerName: String?
    var userInfo: NSObject?
    // Relationships: the entities they connect, not retained.
    var destination: UnsafeMutableRawPointer?
    var inverse: UnsafeMutableRawPointer?
    var maxCount: UInt = 0
    var minCount: UInt = 0
    var deleteRule = DeleteRule.nullify
}

enum Descriptions {
    static let models = StateTable<ModelState>()
    static let entities = StateTable<EntityState>()
    static let properties = StateTable<PropertyState>()
}

/// An NSKeyedUnarchiver, as -initWithCoder: receives it.
extension NSObject {
    @ObjCMethod("decodeObjectForKey:") func coderObject(forKey key: String) -> NSObject?
    @ObjCMethod("decodeIntegerForKey:") func coderInteger(forKey key: String) -> Int
    @ObjCMethod("decodeBoolForKey:") func coderBool(forKey key: String) -> Bool
    @ObjCMethod("containsValueForKey:") func coderContains(_ key: String) -> Bool
}

// MARK: - NSManagedObjectModel

@ObjCClass("NSManagedObjectModel")
open class NSManagedObjectModel: NSObject {
    var state: ModelState { Descriptions.models[objcObject] }

    var entityList: [NSEntityDescription] { state.entities }

    func entity(named name: String) -> NSEntityDescription? {
        state.entities.first { $0.state.name == name }
    }

    @ObjCMethod("init")
    func initialize() -> Self { self }

    /// A compiled model: a .momd directory (its current version) or a .mom
    /// file, which is a keyed archive of the model.
    @ObjCMethod("initWithContentsOfURL:")
    func initialize(contentsOf url: NSURL?) -> NSObject? {
        guard let path = url?.path(), let file = ModelFiles.momFile(path),
              let data = NSData.make(contentsOf: NSURL.make(fileURLWithPath: file)),
              let model = NSKeyedUnarchiver.unarchive(data), model.is(NSManagedObjectModel.self) else { return nil }
        return model
    }

    @ObjCClassMethod("mergedModelFromBundles:")
    static func mergedModel(from bundles: NSArray?) -> NSManagedObjectModel? {
        let merged = NSManagedObjectModel.objCClass.object.newInstance().unsafeCast(to: NSManagedObjectModel.self)
        for file in ModelFiles.bundleModels() {
            guard let data = NSData.make(contentsOf: NSURL.make(fileURLWithPath: file)),
                  let model = NSKeyedUnarchiver.unarchive(data)?.as(NSManagedObjectModel.self) else { continue }
            merged.setEntities(NSMutableArray.of(merged.state.entities + model.state.entities))
        }
        return merged
    }

    @ObjCMethod("initWithCoder:")
    func initialize(coder: NSObject) -> Self {
        let entities = coder.coderObject(forKey: "NSEntities")?.as(NSDictionary.self)
        let values = entities.map { dictionary in
            dictionary.allKeys().elements.compactMap { dictionary.object(forKey: $0)?.unsafeCast(to: NSEntityDescription.self) }
        } ?? []
        setEntities(NSMutableArray.of(values))
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Descriptions.models.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSManagedObjectModel.objCClass.pointer)
    }

    @ObjCMethod("entities") func entities() -> NSObject { NSMutableArray.of(state.entities) }

    @ObjCMethod("setEntities:")
    func setEntities(_ entities: NSObject?) {
        let list = entities?.unsafeCast(to: NSArray.self).elements.map { $0.unsafeCast(to: NSEntityDescription.self) } ?? []
        for entity in list { entity.state.model = objcObject }
        state.entities = list
    }

    @ObjCMethod("entitiesByName")
    func entitiesByName() -> NSObject { NSMutableDictionary.of(state.entities.map { ($0.state.name, $0) }) }

    @ObjCMethod("fetchRequestTemplateForName:") func fetchRequestTemplate(forName name: String?) -> NSObject? { nil }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> NSManagedObjectModel { self }

    /// The model for CoreModel's stores.
    var coreModel: Model {
        var entities = state.entities.map(\.coreModelEntity)
        // CoreModel's stores keep a relationship in the table of the side
        // that is to-one, or in a join table, and need the other side to say
        // which: a relationship with no inverse gets one made for it, to many,
        // that no property of the entity's objects names.
        for index in entities.indices {
            for position in entities[index].relationships.indices {
                var relationship = entities[index].relationships[position]
                guard let destination = entities.firstIndex(where: { $0.id == relationship.destinationEntity }),
                      !entities[destination].relationships.contains(where: { $0.id == relationship.inverseRelationship })
                else { continue }
                let synthetic = PropertyKey(rawValue: PropertyKey.inversePrefix + entities[index].id.rawValue + "_" + relationship.id.rawValue)
                entities[destination].relationships.append(
                    Relationship(id: synthetic, type: .toMany, destinationEntity: entities[index].id, inverseRelationship: relationship.id))
                relationship.inverseRelationship = synthetic
                entities[index].relationships[position] = relationship
            }
        }
        return Model(entities: entities)
    }
}

enum ModelFiles {
    /// The .mom file a URL names: itself, or a .momd's current version.
    static func momFile(_ path: String) -> String? {
        guard path.hasSuffix(".momd") else { return path.hasSuffix(".mom") ? path : nil }
        let manager = NSFileManager.defaultManager()
        let files = manager.contents(atPath: path, error: nil)?.elements.map(\.stringValue).filter { $0.hasSuffix(".mom") } ?? []
        // VersionInfo.plist names the current version; a single model needs
        // none, and is named as the directory is.
        if let current = NSDictionary.make(contentsOfFile: path + "/VersionInfo.plist")?
            .object(forKey: "NSManagedObjectModel_CurrentVersionName")?.stringValue,
           files.contains(current + ".mom") {
            return path + "/" + current + ".mom"
        }
        let name = String(path.split(separator: "/").last ?? "").replacingSuffix(".momd", with: ".mom")
        if files.contains(name) { return path + "/" + name }
        return files.sorted().last.map { path + "/" + $0 }
    }

    /// Every model in the main bundle's resources.
    static func bundleModels() -> [String] {
        guard let resources = NSBundle.main().resourcePath() else { return [] }
        let manager = NSFileManager.defaultManager()
        let names = manager.contents(atPath: resources, error: nil)?.elements.map(\.stringValue) ?? []
        return names.sorted().compactMap { name in
            if name.hasSuffix(".momd") { return momFile(resources + "/" + name) }
            return name.hasSuffix(".mom") ? resources + "/" + name : nil
        }
    }
}

extension String {
    func replacingSuffix(_ suffix: String, with replacement: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) + replacement : self
    }
}

// MARK: - NSEntityDescription

@ObjCClass("NSEntityDescription")
open class NSEntityDescription: NSObject {
    var state: EntityState { Descriptions.entities[objcObject] }

    var model: NSManagedObjectModel? { state.model.map { NSManagedObjectModel(objcObject: $0, ownership: .retain) } }

    var attributes: [NSAttributeDescription] {
        state.properties.compactMap { $0.as(NSAttributeDescription.self) }
    }

    var relationships: [NSRelationshipDescription] {
        state.properties.compactMap { $0.as(NSRelationshipDescription.self) }
    }

    func property(named name: String) -> NSPropertyDescription? {
        state.properties.first { $0.state.name == name }
    }

    @ObjCMethod("init") func initialize() -> Self { self }

    @ObjCMethod("initWithCoder:")
    func initialize(coder: NSObject) -> Self {
        state.name = coder.coderObject(forKey: "NSEntityName")?.stringValue ?? ""
        state.className = coder.coderObject(forKey: "NSClassNameForEntity")?.stringValue ?? "NSManagedObject"
        state.abstract = coder.coderBool(forKey: "NSIsAbstract")
        if let properties = coder.coderObject(forKey: "NSProperties")?.as(NSDictionary.self) {
            let list = properties.allKeys().elements.compactMap {
                properties.object(forKey: $0)?.unsafeCast(to: NSPropertyDescription.self)
            }
            setProperties(NSMutableArray.of(list))
        }
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Descriptions.entities.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSEntityDescription.objCClass.pointer)
    }

    @ObjCClassMethod("entityForName:inManagedObjectContext:")
    static func entity(forName name: String, in context: NSManagedObjectContext?) -> NSEntityDescription? {
        context?.coordinator?.model?.entity(named: name)
    }

    @ObjCClassMethod("insertNewObjectForEntityForName:inManagedObjectContext:")
    static func insertNewObject(forEntityName name: String, into context: NSManagedObjectContext?) -> NSObject? {
        guard let context, let entity = entity(forName: name, in: context) else {
            coreDataFatal("+entityForName: could not locate an entity named '\(name)' in this model.")
        }
        let cls = ManagedObjects.objectClass(entity)
        return cls.object.allocated().initializeManagedObject(entity: entity, insertInto: context)
    }

    @ObjCMethod("name") func name() -> String? { state.name }
    @ObjCMethod("setName:") func setName(_ name: String?) { state.name = name ?? "" }
    @ObjCMethod("managedObjectClassName") func managedObjectClassName() -> String { state.className }
    @ObjCMethod("setManagedObjectClassName:") func setManagedObjectClassName(_ name: String?) {
        state.className = name ?? "NSManagedObject"
    }
    @ObjCMethod("isAbstract") func isAbstract() -> Bool { state.abstract }
    @ObjCMethod("setAbstract:") func setAbstract(_ value: Bool) { state.abstract = value }
    @ObjCMethod("managedObjectModel") func managedObjectModel() -> NSManagedObjectModel? { model }
    @ObjCMethod("superentity") func superentity() -> NSEntityDescription? { nil }

    @ObjCMethod("properties") func properties() -> NSObject { NSMutableArray.of(state.properties) }

    @ObjCMethod("setProperties:")
    func setProperties(_ properties: NSObject?) {
        let list = properties?.unsafeCast(to: NSArray.self).elements.map { $0.unsafeCast(to: NSPropertyDescription.self) } ?? []
        for property in list { property.state.entity = objcObject }
        state.properties = list
    }

    @ObjCMethod("propertiesByName")
    func propertiesByName() -> NSObject { NSMutableDictionary.of(state.properties.map { ($0.state.name, $0) }) }
    @ObjCMethod("attributesByName")
    func attributesByName() -> NSObject { NSMutableDictionary.of(attributes.map { ($0.state.name, $0) }) }
    @ObjCMethod("relationshipsByName")
    func relationshipsByName() -> NSObject { NSMutableDictionary.of(relationships.map { ($0.state.name, $0) }) }

    @ObjCMethod("isKindOfEntity:")
    func isKind(ofEntity entity: NSEntityDescription?) -> Bool { entity?.state.name == state.name }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> NSEntityDescription { self }

    @ObjCMethod("description")
    func description() -> String { "(\(state.className)) \(state.name)" }

    /// The entity for CoreModel's stores; transient properties are not stored.
    var coreModelEntity: EntityDescription {
        EntityDescription(
            id: EntityName(rawValue: state.name),
            attributes: attributes.filter { !$0.state.transient }.map {
                Attribute(id: PropertyKey(stored: $0.state.name), type: AttributeKind.coreModelType($0.state.attributeType))
            },
            relationships: relationships.filter { !$0.state.transient }.map { relationship in
                let destination = relationship.state.destination.map { Descriptions.entities[$0].name } ?? ""
                let inverse = relationship.state.inverse.map { Descriptions.properties[$0].name } ?? ""
                return Relationship(id: PropertyKey(stored: relationship.state.name),
                                    type: relationship.state.maxCount == 1 ? .toOne : .toMany,
                                    destinationEntity: EntityName(rawValue: destination),
                                    inverseRelationship: PropertyKey(stored: inverse))
            })
    }
}

// MARK: - Properties

@ObjCClass("NSPropertyDescription")
open class NSPropertyDescription: NSObject {
    var state: PropertyState { Descriptions.properties[objcObject] }

    var entity: NSEntityDescription? { state.entity.map { NSEntityDescription(objcObject: $0, ownership: .retain) } }

    @ObjCMethod("init") func initialize() -> Self { self }

    @ObjCMethod("initWithCoder:")
    func initialize(coder: NSObject) -> Self {
        state.name = coder.coderObject(forKey: "NSPropertyName")?.stringValue ?? ""
        state.optional = coder.coderBool(forKey: "NSIsOptional")
        state.transient = coder.coderBool(forKey: "NSIsTransient")
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Descriptions.properties.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSPropertyDescription.objCClass.pointer)
    }

    @ObjCMethod("name") func name() -> String? { state.name }
    @ObjCMethod("setName:") func setName(_ name: String?) { state.name = name ?? "" }
    @ObjCMethod("entity") func entityDescription() -> NSEntityDescription? { entity }
    @ObjCMethod("isOptional") func isOptional() -> Bool { state.optional }
    @ObjCMethod("setOptional:") func setOptional(_ value: Bool) { state.optional = value }
    @ObjCMethod("isTransient") func isTransient() -> Bool { state.transient }
    @ObjCMethod("setTransient:") func setTransient(_ value: Bool) { state.transient = value }
    @ObjCMethod("isIndexed") func isIndexed() -> Bool { state.indexed }
    @ObjCMethod("setIndexed:") func setIndexed(_ value: Bool) { state.indexed = value }
    @ObjCMethod("isIndexedBySpotlight") func isIndexedBySpotlight() -> Bool { state.indexedBySpotlight }
    @ObjCMethod("setIndexedBySpotlight:") func setIndexedBySpotlight(_ value: Bool) { state.indexedBySpotlight = value }
    @ObjCMethod("userInfo") func userInfo() -> NSObject? { state.userInfo }
    @ObjCMethod("setUserInfo:") func setUserInfo(_ info: NSObject?) { state.userInfo = info }
    @ObjCMethod("versionHashModifier") func versionHashModifier() -> String? { nil }
    @ObjCMethod("setVersionHashModifier:") func setVersionHashModifier(_ modifier: String?) {}
    @ObjCMethod("renamingIdentifier") func renamingIdentifier() -> String? { state.name }
    @ObjCMethod("setRenamingIdentifier:") func setRenamingIdentifier(_ identifier: String?) {}
    @ObjCMethod("isStoredInExternalRecord") func isStoredInExternalRecord() -> Bool { false }
    @ObjCMethod("setStoredInExternalRecord:") func setStoredInExternalRecord(_ value: Bool) {}
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> NSPropertyDescription { self }
}

@ObjCClass("NSAttributeDescription")
open class NSAttributeDescription: NSPropertyDescription {
    @ObjCMethod("initWithCoder:")
    override func initialize(coder: NSObject) -> Self {
        _ = super.initialize(coder: coder)
        state.attributeType = UInt(coder.coderInteger(forKey: "NSAttributeType"))
        state.defaultValue = coder.coderObject(forKey: "NSDefaultValue")
        return self
    }

    @ObjCMethod("attributeType") func attributeType() -> UInt { state.attributeType }
    @ObjCMethod("setAttributeType:") func setAttributeType(_ type: UInt) { state.attributeType = type }
    @ObjCMethod("defaultValue") func defaultValue() -> NSObject? { state.defaultValue }
    @ObjCMethod("setDefaultValue:") func setDefaultValue(_ value: NSObject?) { state.defaultValue = value }
    @ObjCMethod("attributeValueClassName") func attributeValueClassName() -> String? {
        state.valueClassName ?? AttributeKind.className(state.attributeType)
    }
    @ObjCMethod("setAttributeValueClassName:") func setAttributeValueClassName(_ name: String?) { state.valueClassName = name }
    @ObjCMethod("valueTransformerName") func valueTransformerName() -> String? { state.valueTransformerName }
    @ObjCMethod("setValueTransformerName:") func setValueTransformerName(_ name: String?) { state.valueTransformerName = name }
    @ObjCMethod("allowsExternalBinaryDataStorage") func allowsExternalBinaryDataStorage() -> Bool { false }
    @ObjCMethod("setAllowsExternalBinaryDataStorage:") func setAllowsExternalBinaryDataStorage(_ allows: Bool) {}
}

@ObjCClass("NSRelationshipDescription")
open class NSRelationshipDescription: NSPropertyDescription {
    var isToMany: Bool { state.maxCount != 1 }

    var destination: NSEntityDescription? { state.destination.map { NSEntityDescription(objcObject: $0, ownership: .retain) } }
    var inverse: NSRelationshipDescription? { state.inverse.map { NSRelationshipDescription(objcObject: $0, ownership: .retain) } }

    @ObjCMethod("initWithCoder:")
    override func initialize(coder: NSObject) -> Self {
        _ = super.initialize(coder: coder)
        state.destination = coder.coderObject(forKey: "NSDestinationEntity")?.objcObject
        state.inverse = coder.coderObject(forKey: "NSInverseRelationship")?.objcObject
        state.deleteRule = UInt(coder.coderInteger(forKey: "NSDeleteRule"))
        state.maxCount = UInt(coder.coderInteger(forKey: "NSMaxCount"))
        state.minCount = UInt(coder.coderInteger(forKey: "NSMinCount"))
        return self
    }

    @ObjCMethod("destinationEntity") func destinationEntity() -> NSEntityDescription? { destination }
    @ObjCMethod("setDestinationEntity:") func setDestinationEntity(_ entity: NSEntityDescription?) {
        state.destination = entity?.objcObject
    }
    @ObjCMethod("inverseRelationship") func inverseRelationship() -> NSRelationshipDescription? { inverse }
    @ObjCMethod("setInverseRelationship:") func setInverseRelationship(_ relationship: NSRelationshipDescription?) {
        state.inverse = relationship?.objcObject
    }
    @ObjCMethod("maxCount") func maxCount() -> UInt { state.maxCount }
    @ObjCMethod("setMaxCount:") func setMaxCount(_ count: UInt) { state.maxCount = count }
    @ObjCMethod("minCount") func minCount() -> UInt { state.minCount }
    @ObjCMethod("setMinCount:") func setMinCount(_ count: UInt) { state.minCount = count }
    @ObjCMethod("deleteRule") func deleteRule() -> UInt { state.deleteRule }
    @ObjCMethod("setDeleteRule:") func setDeleteRule(_ rule: UInt) { state.deleteRule = rule }
    @ObjCMethod("isToMany") func toMany() -> Bool { isToMany }
}

// MARK: - Stored names

/// A property's key in CoreModel's stores. CoreModel-SQLite names each
/// table's primary key column "id", and SQLite's column names do not tell
/// "id" from "ID" or "Id", so a property of any such name is stored under
/// another, and named back when read.
extension PropertyKey {
    static let prefix = "_perry_"
    /// The start of the name of an inverse made for a relationship that has none.
    static let inversePrefix = "_perry_inverse_"

    /// Whether SQLite would take `name` for the primary key's column.
    static func isReserved(_ name: String) -> Bool { name.lowercased() == "id" }

    init(stored name: String) {
        self.init(rawValue: PropertyKey.isReserved(name) ? PropertyKey.prefix + name : name)
    }

    /// The property this key stores.
    var propertyName: String {
        rawValue.hasPrefix(PropertyKey.prefix) && PropertyKey.isReserved(String(rawValue.dropFirst(PropertyKey.prefix.count)))
            ? String(rawValue.dropFirst(PropertyKey.prefix.count)) : rawValue
    }

    /// A predicate's key path in stored names, component by component.
    static func storedKeyPath(_ keyPath: String) -> String {
        keyPath.split(separator: ".", omittingEmptySubsequences: false)
            .map { isReserved(String($0)) ? prefix + $0 : String($0) }.joined(separator: ".")
    }
}

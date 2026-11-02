import CoreModel
import FoundationEssentials
import PerryObjCInterop

// Fetch requests, and fetching: the request's NSPredicate and sort
// descriptors become CoreModel's, the store evaluates them, and the
// context's unsaved changes are merged into the results.

/// NSFetchRequestResultType.
enum ResultType {
    static let managedObject: UInt = 0, managedObjectID: UInt = 1, dictionary: UInt = 2, count: UInt = 4
}

final class FetchRequestState: ObjectState {
    var entityName = ""
    var entity: NSEntityDescription?
    var predicate: NSObject?
    var sortDescriptors: NSObject?
    var fetchLimit: UInt = 0
    var fetchOffset: UInt = 0
    var fetchBatchSize: UInt = 0
    var resultType = ResultType.managedObject
    var includesPendingChanges = true
    var returnsObjectsAsFaults = true
    var propertiesToFetch: NSObject?
}

@ObjCClass("NSPersistentStoreRequest")
open class NSPersistentStoreRequest: NSObject {}

@ObjCClass("NSFetchRequest")
open class NSFetchRequest: NSPersistentStoreRequest {
    static let states = StateTable<FetchRequestState>()
    var state: FetchRequestState { NSFetchRequest.states[objcObject] }

    @ObjCClassMethod("fetchRequestWithEntityName:")
    static func fetchRequest(_ cls: ObjCClass, entityName: String) -> NSFetchRequest {
        let request = cls.object.newInstance().unsafeCast(to: NSFetchRequest.self)
        request.state.entityName = entityName
        return request
    }

    @ObjCMethod("init") func initialize() -> Self { self }

    @ObjCMethod("initWithEntityName:")
    func initialize(entityName: String) -> Self {
        state.entityName = entityName
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        NSFetchRequest.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSFetchRequest.objCClass.pointer)
    }

    @ObjCMethod("entityName") func entityName() -> String? { state.entity?.state.name ?? state.entityName }
    @ObjCMethod("entity") func entity() -> NSEntityDescription? { state.entity }
    @ObjCMethod("setEntity:") func setEntity(_ entity: NSEntityDescription?) {
        state.entity = entity
        state.entityName = entity?.state.name ?? ""
    }
    @ObjCMethod("predicate") func predicate() -> NSObject? { state.predicate }
    @ObjCMethod("setPredicate:") func setPredicate(_ predicate: NSObject?) { state.predicate = predicate }
    @ObjCMethod("sortDescriptors") func sortDescriptors() -> NSObject? { state.sortDescriptors }
    @ObjCMethod("setSortDescriptors:") func setSortDescriptors(_ descriptors: NSObject?) { state.sortDescriptors = descriptors }
    @ObjCMethod("fetchLimit") func fetchLimit() -> UInt { state.fetchLimit }
    @ObjCMethod("setFetchLimit:") func setFetchLimit(_ limit: UInt) { state.fetchLimit = limit }
    @ObjCMethod("fetchOffset") func fetchOffset() -> UInt { state.fetchOffset }
    @ObjCMethod("setFetchOffset:") func setFetchOffset(_ offset: UInt) { state.fetchOffset = offset }
    @ObjCMethod("fetchBatchSize") func fetchBatchSize() -> UInt { state.fetchBatchSize }
    @ObjCMethod("setFetchBatchSize:") func setFetchBatchSize(_ size: UInt) { state.fetchBatchSize = size }
    @ObjCMethod("resultType") func resultType() -> UInt { state.resultType }
    @ObjCMethod("setResultType:") func setResultType(_ type: UInt) { state.resultType = type }
    @ObjCMethod("includesPendingChanges") func includesPendingChanges() -> Bool { state.includesPendingChanges }
    @ObjCMethod("setIncludesPendingChanges:") func setIncludesPendingChanges(_ value: Bool) { state.includesPendingChanges = value }
    @ObjCMethod("returnsObjectsAsFaults") func returnsObjectsAsFaults() -> Bool { state.returnsObjectsAsFaults }
    @ObjCMethod("setReturnsObjectsAsFaults:") func setReturnsObjectsAsFaults(_ value: Bool) { state.returnsObjectsAsFaults = value }
    @ObjCMethod("propertiesToFetch") func propertiesToFetch() -> NSObject? { state.propertiesToFetch }
    @ObjCMethod("setPropertiesToFetch:") func setPropertiesToFetch(_ value: NSObject?) { state.propertiesToFetch = value }
    @ObjCMethod("setRelationshipKeyPathsForPrefetching:") func setRelationshipKeyPathsForPrefetching(_ value: NSObject?) {}
    @ObjCMethod("setIncludesSubentities:") func setIncludesSubentities(_ value: Bool) {}
    @ObjCMethod("setReturnsDistinctResults:") func setReturnsDistinctResults(_ value: Bool) {}

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> NSFetchRequest {
        let copy = NSFetchRequest.objCClass.object.newInstance().unsafeCast(to: NSFetchRequest.self)
        let source = state, target = copy.state
        target.entityName = source.entityName
        target.entity = source.entity
        target.predicate = source.predicate
        target.sortDescriptors = source.sortDescriptors
        target.fetchLimit = source.fetchLimit
        target.fetchOffset = source.fetchOffset
        target.resultType = source.resultType
        target.includesPendingChanges = source.includesPendingChanges
        target.propertiesToFetch = source.propertiesToFetch
        return copy
    }
}

enum Fetching {
    private static func error(_ code: Int, _ description: String) -> CoreDataError {
        CoreDataError(error: StoreErrors.make(code, description))
    }

    /// The managed objects a request matches, in order, unsaved changes
    /// included.
    static func matches(_ request: NSFetchRequest, in context: NSManagedObjectContext) throws -> [NSManagedObject] {
        let requestState = request.state
        guard let entity = requestState.entity ?? context.coordinator?.model?.entity(named: requestState.entityName) else {
            coreDataFatal("executeFetchRequest:error: A fetch request must have an entity.")
        }
        guard let backend = context.store?.state.backend else {
            throw error(134060, "This NSPersistentStoreCoordinator has no persistent stores.")
        }
        let entityName = EntityName(rawValue: entity.state.name)
        let predicate = try Predicates.convert(requestState.predicate, entity)
        let sorts = (requestState.sortDescriptors?.unsafeCast(to: NSArray.self).elements ?? []).compactMap { descriptor in
            descriptor.unsafeCast(to: NSSortDescriptor.self).key().map {
                FetchRequest.SortDescriptor(property: PropertyKey(rawValue: $0),
                                            ascending: descriptor.unsafeCast(to: NSSortDescriptor.self).ascending())
            }
        }
        let limit = Int(requestState.fetchLimit), offset = Int(requestState.fetchOffset)
        let contextState = context.state
        let pending = requestState.includesPendingChanges
            ? (contextState.inserted + contextState.updated + contextState.deleted).filter { $0.state.entityName == entity.state.name }
            : []
        let storeRequest = FetchRequest(entity: entityName, sortDescriptors: sorts, predicate: predicate,
                                        fetchLimit: pending.isEmpty ? limit : 0, fetchOffset: pending.isEmpty ? offset : 0)
        var results: [ModelData]
        do {
            results = try backend.fetch(storeRequest)
        } catch let failure {
            throw error(134060, "The fetch failed: \(failure)")
        }
        if !pending.isEmpty {
            // Deleted objects drop out; changed and new ones are judged by
            // their unsaved values.
            let changed = Set(pending.map(\.state.id))
            results = results.filter { !changed.contains($0.id) }
            let candidates = pending.filter { !$0.state.deleted }.map(\.state.modelData)
            results += predicate.map { candidates.filtered(by: $0) } ?? candidates
            results = FetchRequest(entity: entityName, sortDescriptors: sorts, predicate: nil,
                                   fetchLimit: limit, fetchOffset: offset).evaluate(results)
        }
        return results.map { context.materialize(entity, $0) }
    }

    static func execute(_ request: NSFetchRequest, in context: NSManagedObjectContext) throws -> NSObject {
        let objects = try matches(request, in: context)
        switch request.state.resultType {
        case ResultType.count:
            return NSMutableArray.of([NSNumber.make(int64: Int64(objects.count))])
        case ResultType.managedObjectID:
            return NSMutableArray.of(objects.compactMap(\.state.objectID))
        case ResultType.dictionary:
            let wanted = (request.state.propertiesToFetch?.unsafeCast(to: NSArray.self).elements ?? []).map { property in
                property.is(NSPropertyDescription.self) ? property.unsafeCast(to: NSPropertyDescription.self).state.name : property.stringValue
            }
            return NSMutableArray.of(objects.map { object in
                let keys = wanted.isEmpty ? object.state.entity?.attributes.map(\.state.name) ?? [] : wanted
                return NSMutableDictionary.of(keys.compactMap { key in ManagedObjects.value(object, key).map { (key, $0) } })
            })
        default:
            return NSMutableArray.of(objects)
        }
    }
}

/// NSPredicate trees, read through their public API, as CoreModel
/// predicates.
enum Predicates {
    static func convert(_ predicate: NSObject?, _ entity: NSEntityDescription) throws -> FetchRequest.Predicate? {
        guard let predicate else { return nil }
        if predicate.is(NSComparisonPredicate.self) {
            return try comparison(predicate.unsafeCast(to: NSComparisonPredicate.self), entity)
        }
        if predicate.is(NSCompoundPredicate.self) {
            let compound = predicate.unsafeCast(to: NSCompoundPredicate.self)
            let parts = try compound.subpredicates().elements.compactMap { try convert($0, entity) }
            switch compound.compoundPredicateType() {
            case 0: return .compound(.not(parts.first ?? .value(true)))
            case 1: return .compound(.and(parts))
            default: return .compound(.or(parts))
            }
        }
        let format = predicate.unsafeCast(to: NSPredicate.self).predicateFormat()
        return .value(format != "FALSEPREDICATE")
    }

    private static let operators: [UInt: FetchRequest.Predicate.Comparison.Operator] = [
        0: .lessThan, 1: .lessThanOrEqualTo, 2: .greaterThan, 3: .greaterThanOrEqualTo, 4: .equalTo, 5: .notEqualTo,
        6: .matches, 7: .like, 8: .beginsWith, 9: .endsWith, 10: .in, 99: .contains, 100: .between,
    ]

    private static func comparison(_ predicate: NSComparisonPredicate, _ entity: NSEntityDescription) throws -> FetchRequest.Predicate {
        let leftExpression = predicate.leftExpression()
        let rightExpression = predicate.rightExpression()
        let kind = leftExpression.expressionType() == 3
            ? entity.property(named: leftExpression.keyPath())?.as(NSAttributeDescription.self)?.state.attributeType
            : nil
        var options: Set<FetchRequest.Predicate.Comparison.Option> = []
        let flags = predicate.options()
        if flags & 1 != 0 { options.insert(.caseInsensitive) }
        if flags & 2 != 0 { options.insert(.diacriticInsensitive) }
        if flags & 4 != 0 { options.insert(.normalized) }
        let modifier: FetchRequest.Predicate.Comparison.Modifier? =
            predicate.comparisonPredicateModifier() == 1 ? .all : predicate.comparisonPredicateModifier() == 2 ? .any : nil
        let left = try expression(leftExpression, kind: kind)
        let operation = predicate.predicateOperatorType()
        func compare(_ type: FetchRequest.Predicate.Comparison.Operator, _ right: FetchRequest.Predicate.Expression) -> FetchRequest.Predicate {
            .comparison(.init(left: left, right: right, type: type, modifier: modifier, options: options))
        }
        // IN a constant collection: equal to any member. BETWEEN: both bounds.
        let members = try collection(rightExpression, kind: kind)
        if operation == 10, let members {
            return .compound(.or(members.map { compare(.equalTo, $0) }))
        }
        if operation == 100, let members, members.count == 2 {
            return .compound(.and([compare(.greaterThanOrEqualTo, members[0]), compare(.lessThanOrEqualTo, members[1])]))
        }
        guard let type = operators[operation] else {
            throw CoreDataError(error: StoreErrors.make(134060, "Unsupported predicate \(predicate.predicateFormat())"))
        }
        return compare(type, try expression(rightExpression, kind: kind))
    }

    /// An aggregate's or a constant collection's members.
    private static func collection(_ expression: NSExpression, kind: UInt?) throws -> [FetchRequest.Predicate.Expression]? {
        if expression.expressionType() == 14, let items = expression.collection()?.as(NSArray.self) {
            return try items.elements.map { try self.expression($0.unsafeCast(to: NSExpression.self), kind: kind) }
        }
        guard expression.expressionType() == 0, let value = expression.constantValue() else { return nil }
        let items: [NSObject]
        if value.is(NSArray.self) { items = value.unsafeCast(to: NSArray.self).elements }
        else if value.is(NSSet.self) { items = value.unsafeCast(to: NSSet.self).allObjects().elements }
        else { return nil }
        return items.map { constant($0, kind: kind) }
    }

    private static func expression(_ expression: NSExpression, kind: UInt?) throws -> FetchRequest.Predicate.Expression {
        switch expression.expressionType() {
        case 3: return .keyPath(PredicateKeyPath(rawValue: expression.keyPath()))
        case 0: return constant(expression.constantValue(), kind: kind)
        default:
            throw CoreDataError(error: StoreErrors.make(134060, "Unsupported expression type \(expression.expressionType())"))
        }
    }

    /// A constant, typed as the attribute it is compared with; managed
    /// objects and object IDs as relationship values.
    static func constant(_ value: NSObject?, kind: UInt?) -> FetchRequest.Predicate.Expression {
        guard let value else { return .attribute(.null) }
        if value.is(NSManagedObject.self) {
            return .relationship(.toOne(value.unsafeCast(to: NSManagedObject.self).state.id))
        }
        if value.is(NSManagedObjectID.self) {
            return .relationship(.toOne(value.unsafeCast(to: NSManagedObjectID.self).state.id))
        }
        if let kind { return .attribute(ManagedObjects.value(value, kind: kind)) }
        if value.is(NSNumber.self) {
            let number = value.unsafeCast(to: NSNumber.self)
            let double = number.doubleValue()
            return .attribute(double == Double(number.int64Value()) ? .int64(number.int64Value()) : .double(double))
        }
        if value.is(NSDate.self) { return .attribute(ManagedObjects.value(value, kind: AttributeKind.date)) }
        return .attribute(.string(value.stringValue))
    }
}

import PerryObjCInterop

// Requests a context executes besides fetches: batch updates, which change
// what a predicate matches without the caller fetching it, and history
// requests. A batch update or delete here is the same changes made to the
// objects the context finds and saved, since its store is the context's own; there
// is no history to fetch (the store keeps none), so history requests find
// nothing and deleting it succeeds.

/// NSPersistentStoreResult's kinds, each carrying what the request gave.
final class RequestResultState: ObjectState {
    var result: NSObject?
    var resultType: UInt = 0
}

@ObjCClass("NSPersistentStoreResult")
open class NSPersistentStoreResult: NSObject {}

@ObjCClass("NSBatchUpdateResult")
open class NSBatchUpdateResult: NSPersistentStoreResult {
    static let states = StateTable<RequestResultState>()
    var state: RequestResultState { NSBatchUpdateResult.states[objcObject] }

    static func make(_ result: NSObject?, type: UInt) -> NSBatchUpdateResult {
        let object = NSBatchUpdateResult.objCClass.object.newInstance().unsafeCast(to: NSBatchUpdateResult.self)
        object.state.result = result
        object.state.resultType = type
        return object
    }

    @ObjCMethod("result") func result() -> NSObject? { state.result }
    @ObjCMethod("resultType") func resultType() -> UInt { state.resultType }

    @ObjCMethod("dealloc")
    func dealloc() {
        NSBatchUpdateResult.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSBatchUpdateResult.objCClass.pointer)
    }
}

@ObjCClass("NSBatchDeleteResult")
open class NSBatchDeleteResult: NSPersistentStoreResult {
    static let states = StateTable<RequestResultState>()
    var state: RequestResultState { NSBatchDeleteResult.states[objcObject] }

    static func make(_ result: NSObject?, type: UInt) -> NSBatchDeleteResult {
        let object = NSBatchDeleteResult.objCClass.object.newInstance().unsafeCast(to: NSBatchDeleteResult.self)
        object.state.result = result
        object.state.resultType = type
        return object
    }

    @ObjCMethod("result") func result() -> NSObject? { state.result }
    @ObjCMethod("resultType") func resultType() -> UInt { state.resultType }

    @ObjCMethod("dealloc")
    func dealloc() {
        NSBatchDeleteResult.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSBatchDeleteResult.objCClass.pointer)
    }
}

@ObjCClass("NSPersistentHistoryResult")
open class NSPersistentHistoryResult: NSPersistentStoreResult {
    static let states = StateTable<RequestResultState>()
    var state: RequestResultState { NSPersistentHistoryResult.states[objcObject] }

    static func make(_ result: NSObject?, type: UInt) -> NSPersistentHistoryResult {
        let object = NSPersistentHistoryResult.objCClass.object.newInstance().unsafeCast(to: NSPersistentHistoryResult.self)
        object.state.result = result
        object.state.resultType = type
        return object
    }

    @ObjCMethod("result") func result() -> NSObject? { state.result }
    @ObjCMethod("resultType") func resultType() -> UInt { state.resultType }

    @ObjCMethod("dealloc")
    func dealloc() {
        NSPersistentHistoryResult.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSPersistentHistoryResult.objCClass.pointer)
    }
}

// MARK: - Batch update

final class BatchUpdateState: ObjectState {
    var entityName = ""
    var entity: NSEntityDescription?
    var predicate: NSObject?
    var propertiesToUpdate: NSObject?
    /// NSBatchUpdateRequestResultType: status only 0, updated object IDs 1,
    /// updated objects count 2.
    var resultType: UInt = 0
}

@ObjCClass("NSBatchUpdateRequest")
open class NSBatchUpdateRequest: NSPersistentStoreRequest {
    static let states = StateTable<BatchUpdateState>()
    var state: BatchUpdateState { NSBatchUpdateRequest.states[objcObject] }

    @ObjCClassMethod("batchUpdateRequestWithEntityName:")
    static func request(_ cls: ObjCClass, entityName: String) -> NSBatchUpdateRequest {
        let request = cls.object.newInstance().unsafeCast(to: NSBatchUpdateRequest.self)
        request.state.entityName = entityName
        return request
    }

    @ObjCMethod("init") func initialize() -> Self { self }

    @ObjCMethod("initWithEntityName:")
    func initialize(entityName: String) -> Self {
        state.entityName = entityName
        return self
    }

    @ObjCMethod("initWithEntity:")
    func initialize(entity: NSEntityDescription) -> Self {
        state.entity = entity
        state.entityName = entity.state.name
        return self
    }

    @ObjCMethod("entityName") func entityName() -> String { state.entityName }
    @ObjCMethod("entity") func entity() -> NSEntityDescription? { state.entity }
    @ObjCMethod("predicate") func predicate() -> NSObject? { state.predicate }
    @ObjCMethod("setPredicate:") func setPredicate(_ predicate: NSObject?) { state.predicate = predicate }
    @ObjCMethod("propertiesToUpdate") func propertiesToUpdate() -> NSObject? { state.propertiesToUpdate }
    @ObjCMethod("setPropertiesToUpdate:") func setPropertiesToUpdate(_ value: NSObject?) { state.propertiesToUpdate = value }
    @ObjCMethod("resultType") func resultType() -> UInt { state.resultType }
    @ObjCMethod("setResultType:") func setResultType(_ type: UInt) { state.resultType = type }
    @ObjCMethod("includesSubentities") func includesSubentities() -> Bool { true }
    @ObjCMethod("setIncludesSubentities:") func setIncludesSubentities(_ value: Bool) {}
    @ObjCMethod("affectedStores") func affectedStores() -> NSObject? { nil }
    @ObjCMethod("setAffectedStores:") func setAffectedStores(_ stores: NSObject?) {}

    @ObjCMethod("dealloc")
    func dealloc() {
        NSBatchUpdateRequest.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSBatchUpdateRequest.objCClass.pointer)
    }
}

// MARK: - Batch delete

final class BatchDeleteState: ObjectState {
    var fetchRequest: NSFetchRequest?
    var objectIDs: [NSObject] = []
    /// NSBatchDeleteRequestResultType: status only 0, deleted object IDs 1,
    /// deleted objects count 2.
    var resultType: UInt = 0
}

@ObjCClass("NSBatchDeleteRequest")
open class NSBatchDeleteRequest: NSPersistentStoreRequest {
    static let states = StateTable<BatchDeleteState>()
    var state: BatchDeleteState { NSBatchDeleteRequest.states[objcObject] }

    @ObjCMethod("initWithFetchRequest:")
    func initialize(fetchRequest: NSFetchRequest) -> Self {
        state.fetchRequest = fetchRequest
        return self
    }

    @ObjCMethod("initWithObjectIDs:")
    func initialize(objectIDs: NSArray) -> Self {
        state.objectIDs = objectIDs.elements
        return self
    }

    @ObjCMethod("fetchRequest") func fetchRequest() -> NSFetchRequest? { state.fetchRequest }
    @ObjCMethod("resultType") func resultType() -> UInt { state.resultType }
    @ObjCMethod("setResultType:") func setResultType(_ type: UInt) { state.resultType = type }

    @ObjCMethod("dealloc")
    func dealloc() {
        NSBatchDeleteRequest.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSBatchDeleteRequest.objCClass.pointer)
    }
}

// MARK: - History

final class HistoryRequestState: ObjectState {
    /// NSPersistentHistoryResultType: status only 0, object IDs 1, count 2,
    /// transactions only 3, changes only 4, transactions and changes 5.
    var resultType: UInt = 5
    var deletes = false
}

@ObjCClass("NSPersistentHistoryChangeRequest")
open class NSPersistentHistoryChangeRequest: NSPersistentStoreRequest {
    static let states = StateTable<HistoryRequestState>()
    var state: HistoryRequestState { NSPersistentHistoryChangeRequest.states[objcObject] }

    private static func make(_ cls: ObjCClass, deletes: Bool) -> NSPersistentHistoryChangeRequest {
        let request = cls.object.newInstance().unsafeCast(to: NSPersistentHistoryChangeRequest.self)
        request.state.deletes = deletes
        if deletes { request.state.resultType = 0 }
        return request
    }

    @ObjCClassMethod("deleteHistoryBeforeDate:")
    static func deleteHistory(_ cls: ObjCClass, beforeDate date: NSObject?) -> NSPersistentHistoryChangeRequest { make(cls, deletes: true) }
    @ObjCClassMethod("deleteHistoryBeforeToken:")
    static func deleteHistory(_ cls: ObjCClass, beforeToken token: NSObject?) -> NSPersistentHistoryChangeRequest { make(cls, deletes: true) }
    @ObjCClassMethod("deleteHistoryBeforeTransaction:")
    static func deleteHistory(_ cls: ObjCClass, beforeTransaction transaction: NSObject?) -> NSPersistentHistoryChangeRequest { make(cls, deletes: true) }
    @ObjCClassMethod("fetchHistoryAfterDate:")
    static func fetchHistory(_ cls: ObjCClass, afterDate date: NSObject?) -> NSPersistentHistoryChangeRequest { make(cls, deletes: false) }
    @ObjCClassMethod("fetchHistoryAfterToken:")
    static func fetchHistory(_ cls: ObjCClass, afterToken token: NSObject?) -> NSPersistentHistoryChangeRequest { make(cls, deletes: false) }
    @ObjCClassMethod("fetchHistoryAfterTransaction:")
    static func fetchHistory(_ cls: ObjCClass, afterTransaction transaction: NSObject?) -> NSPersistentHistoryChangeRequest { make(cls, deletes: false) }
    @ObjCClassMethod("fetchHistoryWithFetchRequest:")
    static func fetchHistory(_ cls: ObjCClass, withFetchRequest request: NSObject?) -> NSPersistentHistoryChangeRequest { make(cls, deletes: false) }

    @ObjCMethod("resultType") func resultType() -> UInt { state.resultType }
    @ObjCMethod("setResultType:") func setResultType(_ type: UInt) { state.resultType = type }
    @ObjCMethod("token") func token() -> NSObject? { nil }
    @ObjCMethod("fetchRequest") func fetchRequest() -> NSObject? { nil }
    @ObjCMethod("setFetchRequest:") func setFetchRequest(_ request: NSObject?) {}

    @ObjCMethod("dealloc")
    func dealloc() {
        NSPersistentHistoryChangeRequest.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSPersistentHistoryChangeRequest.objCClass.pointer)
    }
}

// MARK: - Executing

enum Requests {
    /// NSPersistentStoreUnsupportedRequestTypeError.
    private static var unsupported: CoreDataError {
        CoreDataError(error: StoreErrors.make(134091, "The store does not support this kind of request."))
    }

    static func execute(_ request: NSPersistentStoreRequest, in context: NSManagedObjectContext) throws -> NSObject {
        let object = request.unsafeCast(to: NSObject.self)
        if object.isKind(of: NSBatchUpdateRequest.objCClass) {
            return try batchUpdate(request.unsafeCast(to: NSBatchUpdateRequest.self), in: context)
        }
        if object.isKind(of: NSBatchDeleteRequest.objCClass) {
            return try batchDelete(request.unsafeCast(to: NSBatchDeleteRequest.self), in: context)
        }
        if object.isKind(of: NSPersistentHistoryChangeRequest.objCClass) {
            let history = request.unsafeCast(to: NSPersistentHistoryChangeRequest.self).state
            let result: NSObject? = history.resultType == 0 ? NSNumber.make(bool: true) : NSMutableArray.empty()
            return NSPersistentHistoryResult.make(result, type: history.resultType)
        }
        throw unsupported
    }

    private static func batchUpdate(_ request: NSBatchUpdateRequest, in context: NSManagedObjectContext) throws -> NSObject {
        context.processPendingChanges()
        let requestState = request.state
        let fetch = NSFetchRequest.objCClass.object.newInstance().unsafeCast(to: NSFetchRequest.self)
        fetch.state.entityName = requestState.entityName
        fetch.state.entity = requestState.entity
        fetch.state.predicate = requestState.predicate
        let matches = try Fetching.matches(fetch, in: context)
        if let updates = requestState.propertiesToUpdate?.unsafeCast(to: NSDictionary.self) {
            for key in updates.allKeys().elements {
                guard let value = updates.object(forKey: key) else { continue }
                for object in matches { ManagedObjects.setValue(object, key.stringValue, value) }
            }
        }
        var failure: UnsafeMutableRawPointer?
        if !matches.isEmpty, !context.save(&failure) {
            throw CoreDataError(error: failure.map { NSObject(objcObject: $0, ownership: .retain).unsafeCast(to: NSError.self) }
                ?? StoreErrors.make(134030, "The batch update could not be saved."))
        }
        let result: NSObject? = switch requestState.resultType {
        case 1: NSMutableArray.of(matches.compactMap { $0.objectID().map { NSObject($0.objcObject) } })
        case 2: NSNumber.make(int64: Int64(matches.count))
        default: NSNumber.make(bool: true)
        }
        return NSBatchUpdateResult.make(result, type: requestState.resultType)
    }

    private static func batchDelete(_ request: NSBatchDeleteRequest, in context: NSManagedObjectContext) throws -> NSObject {
        context.processPendingChanges()
        let requestState = request.state
        var matches: [NSManagedObject] = []
        if let fetch = requestState.fetchRequest {
            matches = try Fetching.matches(fetch, in: context)
        } else {
            matches = requestState.objectIDs.compactMap {
                context.object(with: $0.unsafeCast(to: NSManagedObjectID.self))
            }
        }
        let ids = matches.compactMap { $0.objectID().map { NSObject($0.objcObject) } }
        for object in matches { context.delete(object) }
        var failure: UnsafeMutableRawPointer?
        if !matches.isEmpty, !context.save(&failure) {
            throw CoreDataError(error: failure.map { NSObject(objcObject: $0, ownership: .retain).unsafeCast(to: NSError.self) }
                ?? StoreErrors.make(134030, "The batch delete could not be saved."))
        }
        let result: NSObject? = switch requestState.resultType {
        case 1: NSMutableArray.of(ids)
        case 2: NSNumber.make(int64: Int64(matches.count))
        default: NSNumber.make(bool: true)
        }
        return NSBatchDeleteResult.make(result, type: requestState.resultType)
    }
}

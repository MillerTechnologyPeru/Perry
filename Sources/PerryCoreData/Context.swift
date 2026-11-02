import CoreModel
import PerryObjCInterop

// The managed object context: the objects it has registered (one per ID),
// their unsaved changes, saving them to the store with validation, and
// fetching, where results include the unsaved changes.

/// NSManagedObjectContextConcurrencyType.
enum ConcurrencyType {
    static let confinement: UInt = 0, privateQueue: UInt = 1, mainQueue: UInt = 2
}

final class ContextState: ObjectState {
    var coordinator: NSPersistentStoreCoordinator?
    var concurrencyType = ConcurrencyType.confinement
    var name: String?
    var registered: [String: NSManagedObject] = [:]
    var inserted: [NSManagedObject] = []
    var updated: [NSManagedObject] = []
    var deleted: [NSManagedObject] = []
    /// Objects whose deny delete rule stops the save.
    var denied: [(NSManagedObject, String)] = []
    /// Deleted objects whose delete rules processPendingChanges applies.
    var pendingDeletions: [NSManagedObject] = []
    var mergePolicy: NSObject?
    var automaticallyMerges = false
    var queue: SerialQueue?
}

/// NSValidation and store error codes.
enum CoreDataErrors {
    static let missingMandatoryProperty = 1570
    static let multipleErrors = 1560
    static let relationshipDeniedDelete = 1550
    static let referentialIntegrity = 133000
    static let saveFailed = 134030
}

@ObjCClass("NSManagedObjectContext")
open class NSManagedObjectContext: NSObject {
    static let states = StateTable<ContextState>()
    var state: ContextState { NSManagedObjectContext.states[objcObject] }

    var coordinator: NSPersistentStoreCoordinator? { state.coordinator }

    private static func key(_ entity: String, _ id: ObjectID) -> String { entity + "/" + id.rawValue }

    @ObjCMethod("init") func initialize() -> Self { self }

    @ObjCMethod("initWithConcurrencyType:")
    func initialize(concurrencyType: UInt) -> Self {
        state.concurrencyType = concurrencyType
        if concurrencyType == ConcurrencyType.privateQueue { state.queue = SerialQueue() }
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        for object in state.registered.values { object.state.context = nil }
        NSManagedObjectContext.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSManagedObjectContext.objCClass.pointer)
    }

    @ObjCMethod("persistentStoreCoordinator") func persistentStoreCoordinator() -> NSPersistentStoreCoordinator? { coordinator }
    @ObjCMethod("setPersistentStoreCoordinator:")
    func setPersistentStoreCoordinator(_ coordinator: NSPersistentStoreCoordinator?) { state.coordinator = coordinator }
    @ObjCMethod("concurrencyType") func concurrencyType() -> UInt { state.concurrencyType }
    @ObjCMethod("name") func name() -> String? { state.name }
    @ObjCMethod("setName:") func setName(_ name: String?) { state.name = name }
    @ObjCMethod("parentContext") func parentContext() -> NSManagedObjectContext? { nil }
    @ObjCMethod("undoManager") func undoManager() -> NSObject? { nil }
    @ObjCMethod("setUndoManager:") func setUndoManager(_ manager: NSObject?) {}
    @ObjCMethod("mergePolicy") func mergePolicy() -> NSObject? { state.mergePolicy }
    @ObjCMethod("setMergePolicy:") func setMergePolicy(_ policy: NSObject?) { state.mergePolicy = policy }
    @ObjCMethod("automaticallyMergesChangesFromParent") func automaticallyMergesChangesFromParent() -> Bool {
        state.automaticallyMerges
    }
    @ObjCMethod("setAutomaticallyMergesChangesFromParent:") func setAutomaticallyMergesChangesFromParent(_ value: Bool) {
        state.automaticallyMerges = value
    }
    /// Applies the delete rules of objects deleted since the last call, as
    /// fetching and saving do first.
    @ObjCMethod("processPendingChanges")
    func processPendingChanges() {
        while !state.pendingDeletions.isEmpty {
            let object = state.pendingDeletions.removeFirst()
            propagateDeletion(object)
        }
    }

    @ObjCMethod("hasChanges")
    func hasChanges() -> Bool { !state.inserted.isEmpty || !state.updated.isEmpty || !state.deleted.isEmpty }

    @ObjCMethod("insertedObjects") func insertedObjects() -> NSObject { NSMutableSet.of(state.inserted) }
    @ObjCMethod("updatedObjects") func updatedObjects() -> NSObject { NSMutableSet.of(state.updated) }
    @ObjCMethod("deletedObjects") func deletedObjects() -> NSObject { NSMutableSet.of(state.deleted) }
    @ObjCMethod("registeredObjects") func registeredObjects() -> NSObject { NSMutableSet.of(Array(state.registered.values)) }

    // MARK: Objects

    var store: NSPersistentStore? { coordinator?.state.stores.first }

    /// Registers a new object with a permanent ID in the store, shown as a
    /// temporary ID until it is saved, and the entity's default values.
    @ObjCMethod("insertObject:")
    func insert(_ object: NSManagedObject) {
        let objectState = object.state
        guard objectState.context == nil, let entity = objectState.entity else { return }
        guard let store, let backend = store.state.backend, let id = try? backend.newID(entity.state.name) else {
            coreDataFatal("This NSPersistentStoreCoordinator has no persistent stores. It cannot perform a save operation.")
        }
        objectState.context = objcObject
        objectState.store = store
        objectState.id = id
        objectState.objectID = NSManagedObjectID.make(entity: entity, store: store, id: id, temporary: true)
        objectState.inserted = true
        for attribute in entity.attributes {
            objectState.attributes[attribute.state.name] =
                ManagedObjects.value(attribute.state.defaultValue, kind: attribute.state.attributeType)
        }
        for relationship in entity.relationships {
            objectState.relationships[relationship.state.name] = relationship.isToMany ? .toMany([]) : .null
        }
        state.registered[Self.key(entity.state.name, id)] = object
        state.inserted.append(object)
        object.sendAwakeFromInsert()
    }

    /// The registered object for an ID, or the store's, registered now.
    func object(entity: NSEntityDescription, id: ObjectID) -> NSManagedObject? {
        if let registered = state.registered[Self.key(entity.state.name, id)] { return registered }
        guard let backend = store?.state.backend,
              let data = try? backend.fetch(EntityName(rawValue: entity.state.name), id) else { return nil }
        return materialize(entity, data)
    }

    /// A registered object for fetched values: the one already registered,
    /// refreshed unless it has changes, or a new one.
    func materialize(_ entity: NSEntityDescription, _ data: ModelData) -> NSManagedObject {
        let key = Self.key(entity.state.name, data.id)
        if let registered = state.registered[key] {
            let objectState = registered.state
            if !objectState.inserted && !objectState.updated && !objectState.deleted { objectState.load(data) }
            return registered
        }
        let object = ManagedObjects.objectClass(entity).object.allocated().unsafeCast(to: NSManagedObject.self)
        let objectState = object.state
        objectState.entity = entity
        objectState.context = objcObject
        objectState.store = store
        objectState.id = data.id
        objectState.objectID = NSManagedObjectID.make(entity: entity, store: store, id: data.id, temporary: false)
        objectState.load(data)
        state.registered[key] = object
        object.sendAwakeFromFetch()
        return object
    }

    private func unregister(_ object: NSManagedObject) {
        let objectState = object.state
        state.registered[Self.key(objectState.entityName, objectState.id)] = nil
        objectState.context = nil
    }

    private func removeChange(_ object: NSManagedObject) {
        state.inserted.removeAll { $0.objcObject == object.objcObject }
        state.updated.removeAll { $0.objcObject == object.objcObject }
        state.deleted.removeAll { $0.objcObject == object.objcObject }
    }

    /// Deletes an object. Its relationships' delete rules apply when
    /// pending changes are processed (at once for an unsaved object):
    /// nullify removes it from the other side, cascade deletes the related
    /// objects, deny stops the save while related objects remain.
    @ObjCMethod("deleteObject:")
    func delete(_ object: NSManagedObject) {
        let objectState = object.state
        guard !objectState.deleted, objectState.context == objcObject else { return }
        object.sendPrepareForDeletion()
        let wasInserted = objectState.inserted
        removeChange(object)
        objectState.inserted = false
        objectState.updated = false
        objectState.deleted = true
        if wasInserted {
            propagateDeletion(object)
            unregister(object)
        } else {
            state.deleted.append(object)
            state.pendingDeletions.append(object)
        }
    }

    private func propagateDeletion(_ object: NSManagedObject) {
        guard let entity = object.state.entity else { return }
        for relationship in entity.relationships {
            let targets = ManagedObjects.related(object, relationship)
            switch relationship.state.deleteRule {
            case DeleteRule.cascade:
                for target in targets {
                    ManagedObjects.unlink(object, relationship, target)
                    delete(target)
                }
            case DeleteRule.deny:
                if !targets.isEmpty { state.denied.append((object, relationship.state.name)) }
            case DeleteRule.noAction:
                break
            default:
                for target in targets { ManagedObjects.unlink(object, relationship, target) }
            }
        }
    }

    @ObjCMethod("objectRegisteredForID:")
    func objectRegistered(for objectID: NSManagedObjectID?) -> NSManagedObject? {
        guard let objectID else { return nil }
        return state.registered[Self.key(objectID.state.entity?.state.name ?? "", objectID.state.id)]
    }

    @ObjCMethod("objectWithID:")
    func object(with objectID: NSManagedObjectID) -> NSManagedObject? {
        guard let entity = objectID.state.entity else { return nil }
        return object(entity: entity, id: objectID.state.id)
    }

    @ObjCMethod("existingObjectWithID:error:")
    func existingObject(with objectID: NSManagedObjectID,
                        error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> NSManagedObject? {
        if let object = object(with: objectID), !object.state.deleted { return object }
        error?.pointee = StoreErrors.make(CoreDataErrors.referentialIntegrity,
                                          "The operation couldn’t be completed. (Cocoa error \(CoreDataErrors.referentialIntegrity).)")
            .objCReturnValue()
        return nil
    }

    @ObjCMethod("obtainPermanentIDsForObjects:error:")
    func obtainPermanentIDs(for objects: NSArray?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        for object in objects?.elements ?? [] {
            let objectState = object.unsafeCast(to: NSManagedObject.self).state
            objectState.objectID = NSManagedObjectID.make(entity: objectState.entity, store: objectState.store,
                                                          id: objectState.id, temporary: false)
        }
        return true
    }

    // MARK: Saving

    private func validationError(_ object: NSManagedObject, _ key: String, code: Int, _ description: String) -> NSError {
        StoreErrors.make(code, description, [("NSValidationErrorKey", NSObject(key.objCArgument()!)),
                                              ("NSValidationErrorObject", object)])
    }

    /// Mandatory attributes and to-one relationships must have values.
    private func validate() -> [NSError] {
        var errors: [NSError] = []
        for object in state.inserted + state.updated {
            guard let entity = object.state.entity else { continue }
            for property in entity.state.properties where !property.state.optional && !property.state.transient {
                let name = property.state.name
                let missing: Bool
                if let relationship = property.as(NSRelationshipDescription.self) {
                    missing = !relationship.isToMany && (object.state.relationships[name] ?? .null) == .null
                } else {
                    missing = (object.state.attributes[name] ?? .null) == .null
                }
                if missing {
                    errors.append(validationError(object, name, code: CoreDataErrors.missingMandatoryProperty,
                                                  "\(name) is a required value."))
                }
            }
        }
        for (object, name) in state.denied where object.state.deleted {
            errors.append(validationError(object, name, code: CoreDataErrors.relationshipDeniedDelete,
                                          "\(name) is not valid."))
        }
        return errors
    }

    @ObjCMethod("save:")
    func save(_ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        processPendingChanges()
        guard hasChanges() else { return true }
        let inserted = state.inserted, updated = state.updated, deleted = state.deleted
        for object in inserted + updated + deleted { object.sendWillSave() }
        let errors = validate()
        if errors.count == 1 {
            error?.pointee = errors[0].objCReturnValue()
            return false
        }
        if errors.count > 1 {
            error?.pointee = StoreErrors.make(CoreDataErrors.multipleErrors, [("NSDetailedErrors", NSMutableArray.of(errors))]).objCReturnValue()
            return false
        }
        guard let backend = store?.state.backend else {
            error?.pointee = StoreErrors.make(134060, "This NSPersistentStoreCoordinator has no persistent stores.").objCReturnValue()
            return false
        }
        do {
            try backend.save(inserting: (inserted + updated).map(\.state.modelData),
                             deleting: deleted.map { (EntityName(rawValue: $0.state.entityName), $0.state.id) })
        } catch let failure {
            error?.pointee = StoreErrors.make(CoreDataErrors.saveFailed, "The store couldn’t be saved: \(failure)").objCReturnValue()
            return false
        }
        for object in inserted + updated {
            let objectState = object.state
            if objectState.inserted {
                objectState.objectID = NSManagedObjectID.make(entity: objectState.entity, store: objectState.store,
                                                              id: objectState.id, temporary: false)
            }
            objectState.inserted = false
            objectState.updated = false
            objectState.committed = objectState.modelData
        }
        for object in deleted { unregister(object) }
        state.inserted = []
        state.updated = []
        state.deleted = []
        state.denied = []
        for object in inserted + updated + deleted { object.sendDidSave() }
        NSNotificationCenter.defaultCenter().post(
            name: Notifications.NSManagedObjectContextDidSaveNotification, object: self,
            userInfo: NSMutableDictionary.of([(Notifications.NSInsertedObjectsKey, NSMutableSet.of(inserted)),
                                              (Notifications.NSUpdatedObjectsKey, NSMutableSet.of(updated)),
                                              (Notifications.NSDeletedObjectsKey, NSMutableSet.of(deleted))]))
        return true
    }

    /// Discards unsaved changes: new objects go, changed and deleted ones
    /// return to their saved values.
    @ObjCMethod("rollback")
    func rollback() {
        for object in state.inserted {
            object.state.inserted = false
            unregister(object)
        }
        for object in state.updated + state.deleted {
            let objectState = object.state
            objectState.updated = false
            objectState.deleted = false
            if let committed = objectState.committed { objectState.load(committed) }
            state.registered[Self.key(objectState.entityName, objectState.id)] = object
            objectState.context = objcObject
        }
        state.inserted = []
        state.updated = []
        state.deleted = []
        state.denied = []
        state.pendingDeletions = []
    }

    @ObjCMethod("reset")
    func reset() {
        for object in state.registered.values { object.state.context = nil }
        state.registered = [:]
        state.inserted = []
        state.updated = []
        state.deleted = []
        state.denied = []
    }

    /// Reloads an object from the store, keeping its changes when merging.
    @ObjCMethod("refreshObject:mergeChanges:")
    func refresh(_ object: NSManagedObject, mergeChanges: Bool) {
        let objectState = object.state
        guard !objectState.inserted, !(mergeChanges && objectState.updated),
              let entity = objectState.entity, let backend = objectState.store?.state.backend,
              let data = try? backend.fetch(EntityName(rawValue: entity.state.name), objectState.id) else { return }
        objectState.load(data)
        if objectState.updated {
            objectState.updated = false
            state.updated.removeAll { $0.objcObject == object.objcObject }
        }
    }

    @ObjCMethod("refreshAllObjects")
    func refreshAllObjects() {
        for object in state.registered.values { refresh(object, mergeChanges: true) }
    }

    /// Another context's saved changes: objects it deleted go, objects it
    /// updated are reloaded unless they have changes here.
    @ObjCMethod("mergeChangesFromContextDidSaveNotification:")
    func mergeChanges(fromContextDidSave notification: NSObject) {
        guard let userInfo = notification.notificationUserInfo()?.as(NSDictionary.self) else { return }
        func objects(_ key: String) -> [NSManagedObject] {
            userInfo.object(forKey: NSObject(key.objCArgument()!))?.unsafeCast(to: NSSet.self).allObjects().elements
                .map { $0.unsafeCast(to: NSManagedObject.self) } ?? []
        }
        for other in objects(Notifications.NSDeletedObjectsKey) {
            if let object = state.registered[Self.key(other.state.entityName, other.state.id)] { unregister(object) }
        }
        for other in objects(Notifications.NSUpdatedObjectsKey) {
            if let object = state.registered[Self.key(other.state.entityName, other.state.id)] {
                refresh(object, mergeChanges: true)
            }
        }
    }

    // MARK: Fetching

    @ObjCMethod("executeFetchRequest:error:")
    func execute(_ request: NSFetchRequest, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> NSObject? {
        processPendingChanges()
        do {
            return try Fetching.execute(request, in: self)
        } catch let failure as CoreDataError {
            error?.pointee = failure.error.objCReturnValue()
            return nil
        } catch {
            return nil
        }
    }

    /// NSNotFound when the request fails.
    @ObjCMethod("countForFetchRequest:error:")
    func count(for request: NSFetchRequest, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int {
        processPendingChanges()
        do {
            return try Fetching.matches(request, in: self).count
        } catch let failure as CoreDataError {
            error?.pointee = failure.error.objCReturnValue()
            return Int.max
        } catch {
            return Int.max
        }
    }

    // MARK: Queues

    /// Runs the block on the context's queue: the main thread's run loop for
    /// a main-queue context, the context's own thread for a private one.
    @ObjCMethod("performBlock:")
    func perform(_ block: ObjCBlock) {
        if let queue = state.queue {
            queue.async { Blocks.call(block) }
        } else {
            let runner = BlockRunner.make(block)
            runner.performOnMainThread(ObjCSelector("run"), with: nil, waitUntilDone: false)
        }
    }

    /// Runs the block now, on the calling thread.
    @ObjCMethod("performBlockAndWait:")
    func performAndWait(_ block: ObjCBlock) {
        ObjCRuntime.autoreleasepool { Blocks.call(block) }
    }
}

/// A Core Data failure, carrying the NSError to report.
struct CoreDataError: Error, @unchecked Sendable {
    let error: NSError
}

extension NSObject {
    @ObjCMethod("userInfo") func notificationUserInfo() -> NSObject?
}

/// Holds a block for -performSelectorOnMainThread:.
@ObjCClass("PFBlockRunner")
final class BlockRunner: NSObject {
    static let blocks = StateTable<BlockState>()

    final class BlockState: ObjectState {
        var block: ObjCBlock?
    }

    static func make(_ block: ObjCBlock) -> BlockRunner {
        let runner = BlockRunner.objCClass.object.newInstance().unsafeCast(to: BlockRunner.self)
        blocks[runner.objcObject].block = block
        return runner
    }

    @ObjCMethod("run")
    func run() {
        if let block = BlockRunner.blocks[objcObject].block { Blocks.call(block) }
        BlockRunner.blocks.remove(objcObject)
    }
}

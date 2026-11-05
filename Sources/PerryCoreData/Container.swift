import Glibc
import PerryObjCInterop

// NSPersistentContainer and NSPersistentStoreDescription: a model found by
// name in the main bundle, its coordinator, the stores the descriptions
// name, and contexts for the main queue and the background.

final class StoreDescriptionState: ObjectState {
    var type = StoreTypes.NSSQLiteStoreType
    var url: NSURL?
    var configuration: String?
    var options: [(String, NSObject)] = []
    var readOnly = false
    var addsAsynchronously = false
    var migratesAutomatically = true
    var infersMappingModel = true
    var cloudKitContainerOptions: NSObject?
}

@ObjCClass("NSPersistentStoreDescription")
open class NSPersistentStoreDescription: NSObject {
    static let states = StateTable<StoreDescriptionState>()
    var state: StoreDescriptionState { NSPersistentStoreDescription.states[objcObject] }

    @ObjCClassMethod("persistentStoreDescriptionWithURL:")
    static func description(_ cls: ObjCClass, url: NSURL?) -> NSPersistentStoreDescription {
        let description = cls.object.newInstance().unsafeCast(to: NSPersistentStoreDescription.self)
        description.state.url = url
        return description
    }

    @ObjCMethod("init") func initialize() -> Self { self }

    @ObjCMethod("initWithURL:")
    func initialize(url: NSURL?) -> Self {
        state.url = url
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        NSPersistentStoreDescription.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSPersistentStoreDescription.objCClass.pointer)
    }

    /// Kept; the store does not sync through CloudKit.
    @ObjCMethod("cloudKitContainerOptions") func cloudKitContainerOptions() -> NSObject? { state.cloudKitContainerOptions }
    @ObjCMethod("setCloudKitContainerOptions:") func setCloudKitContainerOptions(_ options: NSObject?) {
        state.cloudKitContainerOptions = options
    }

    @ObjCMethod("type") func type() -> String { state.type }
    @ObjCMethod("setType:") func setType(_ type: String) { state.type = type }
    @ObjCMethod("URL") func url() -> NSURL? { state.url }
    @ObjCMethod("setURL:") func setURL(_ url: NSURL?) { state.url = url }
    @ObjCMethod("configuration") func configuration() -> String? { state.configuration }
    @ObjCMethod("setConfiguration:") func setConfiguration(_ name: String?) { state.configuration = name }
    @ObjCMethod("isReadOnly") func isReadOnly() -> Bool { state.readOnly }
    @ObjCMethod("setReadOnly:") func setReadOnly(_ value: Bool) { state.readOnly = value }
    @ObjCMethod("shouldAddStoreAsynchronously") func shouldAddStoreAsynchronously() -> Bool { state.addsAsynchronously }
    @ObjCMethod("setShouldAddStoreAsynchronously:") func setShouldAddStoreAsynchronously(_ value: Bool) {
        state.addsAsynchronously = value
    }
    @ObjCMethod("shouldMigrateStoreAutomatically") func shouldMigrateStoreAutomatically() -> Bool { state.migratesAutomatically }
    @ObjCMethod("setShouldMigrateStoreAutomatically:") func setShouldMigrateStoreAutomatically(_ value: Bool) {
        state.migratesAutomatically = value
    }
    @ObjCMethod("shouldInferMappingModelAutomatically") func shouldInferMappingModelAutomatically() -> Bool {
        state.infersMappingModel
    }
    @ObjCMethod("setShouldInferMappingModelAutomatically:") func setShouldInferMappingModelAutomatically(_ value: Bool) {
        state.infersMappingModel = value
    }
    @ObjCMethod("setOption:forKey:")
    func setOption(_ option: NSObject?, forKey key: String) {
        state.options.removeAll { $0.0 == key }
        if let option { state.options.append((key, option)) }
    }
    @ObjCMethod("options") func options() -> NSObject { NSMutableDictionary.of(state.options) }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> NSPersistentStoreDescription {
        let copy = NSPersistentStoreDescription.objCClass.object.newInstance().unsafeCast(to: NSPersistentStoreDescription.self)
        let source = state, target = copy.state
        target.type = source.type
        target.url = source.url
        target.configuration = source.configuration
        target.options = source.options
        target.readOnly = source.readOnly
        target.addsAsynchronously = source.addsAsynchronously
        return copy
    }
}

final class ContainerState: ObjectState {
    var name = ""
    var model: NSManagedObjectModel?
    var coordinator: NSPersistentStoreCoordinator?
    var descriptions: [NSPersistentStoreDescription] = []
    var viewContext: NSManagedObjectContext?
}

@ObjCClass("NSPersistentContainer")
open class NSPersistentContainer: NSObject {
    static let states = StateTable<ContainerState>()
    var state: ContainerState { NSPersistentContainer.states[objcObject] }

    @ObjCClassMethod("persistentContainerWithName:")
    static func container(_ cls: ObjCClass, name: String) -> NSObject? {
        cls.object.allocated().initializeContainer(name: name)
    }

    @ObjCClassMethod("persistentContainerWithName:managedObjectModel:")
    static func container(_ cls: ObjCClass, name: String, model: NSManagedObjectModel) -> NSObject? {
        cls.object.allocated().initializeContainer(name: name, model: model)
    }

    /// The application's directory for stores: Library/Application Support.
    @ObjCClassMethod("defaultDirectoryURL")
    static func defaultDirectoryURL() -> NSURL {
        let home = String(cString: getenv("HOME") ?? strdup("/tmp")!)
        let path = home + "/Library/Application Support"
        _ = NSFileManager.defaultManager().createDirectory(atPath: path, intermediates: true, attributes: nil, error: nil)
        return NSURL.make(fileURLWithPath: path)
    }

    /// The model named `name` in the main bundle, or every model there.
    @ObjCMethod("initWithName:")
    func initialize(name: String) -> NSObject? {
        let model: NSManagedObjectModel?
        if let url = NSBundle.main().url(forResource: name, withExtension: "momd") ?? NSBundle.main().url(forResource: name, withExtension: "mom") {
            model = NSManagedObjectModel.objCClass.object.allocated().initializeModel(contentsOf: url)?.unsafeCast(to: NSManagedObjectModel.self)
        } else {
            model = NSManagedObjectModel.mergedModel(from: nil)
        }
        guard let model else { coreDataFatal("Failed to load model named \(name)") }
        return initialize(name: name, model: model)
    }

    @ObjCMethod("initWithName:managedObjectModel:")
    func initialize(name: String, model: NSManagedObjectModel) -> NSObject? {
        state.name = name
        state.model = model
        state.coordinator = NSPersistentStoreCoordinator.objCClass.object.allocated()
            .initializeCoordinator(model: model)?.unsafeCast(to: NSPersistentStoreCoordinator.self)
        let url = NSPersistentContainer.defaultDirectoryURL().appending(name + ".sqlite")
        state.descriptions = [NSPersistentStoreDescription.description(NSPersistentStoreDescription.objCClass, url: url)]
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        NSPersistentContainer.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSPersistentContainer.objCClass.pointer)
    }

    @ObjCMethod("name") func name() -> String { state.name }
    @ObjCMethod("managedObjectModel") func managedObjectModel() -> NSManagedObjectModel? { state.model }
    @ObjCMethod("persistentStoreCoordinator") func persistentStoreCoordinator() -> NSPersistentStoreCoordinator? {
        state.coordinator
    }
    @ObjCMethod("persistentStoreDescriptions") func persistentStoreDescriptions() -> NSObject {
        NSMutableArray.of(state.descriptions)
    }
    @ObjCMethod("setPersistentStoreDescriptions:")
    func setPersistentStoreDescriptions(_ descriptions: NSObject?) {
        state.descriptions = descriptions?.unsafeCast(to: NSArray.self).elements
            .map { $0.unsafeCast(to: NSPersistentStoreDescription.self) } ?? []
    }

    /// Adds each description's store, calling the handler for each, on this
    /// thread before returning.
    @ObjCMethod("loadPersistentStoresWithCompletionHandler:")
    func loadPersistentStores(completionHandler: ObjCBlock) {
        guard let coordinator = state.coordinator else { return }
        for description in state.descriptions {
            var error: UnsafeMutableRawPointer?
            let descriptionState = description.state
            _ = coordinator.addPersistentStore(type: descriptionState.type, configuration: descriptionState.configuration,
                                               url: descriptionState.url, options: NSMutableDictionary.of(descriptionState.options),
                                               error: &error)
            Blocks.call(completionHandler, description, error.map(NSObject.init))
        }
    }

    @ObjCMethod("viewContext")
    func viewContext() -> NSManagedObjectContext {
        if let context = state.viewContext { return context }
        let context = newContext(ConcurrencyType.mainQueue)
        state.viewContext = context
        return context
    }

    private func newContext(_ type: UInt) -> NSManagedObjectContext {
        let context = NSManagedObjectContext.objCClass.object.allocated().initializeContext(concurrencyType: type)
            .unsafeCast(to: NSManagedObjectContext.self)
        context.state.coordinator = state.coordinator
        return context
    }

    @ObjCMethod("newBackgroundContext")
    func newBackgroundContext() -> NSManagedObjectContext {
        let context = newContext(ConcurrencyType.privateQueue)
        return NSManagedObjectContext(objcObject: context.objCOwnedReturnValue()!, ownership: .adopt)
    }

    /// Runs the block with a new private-queue context, on that context's queue.
    @ObjCMethod("performBackgroundTask:")
    func performBackgroundTask(_ block: ObjCBlock) {
        let context = newContext(ConcurrencyType.privateQueue)
        context.state.queue?.async { Blocks.call(block, context) }
    }
}

extension NSObject {
    @ObjCMethod("initWithName:") func initializeContainer(name: String) -> NSObject?
    @ObjCMethod("initWithName:managedObjectModel:")
    func initializeContainer(name: String, model: NSManagedObjectModel) -> NSObject?
    @ObjCMethod("initWithContentsOfURL:") func initializeModel(contentsOf url: NSURL) -> NSObject?
    @ObjCMethod("initWithManagedObjectModel:") func initializeCoordinator(model: NSManagedObjectModel) -> NSObject?
    @ObjCMethod("initWithConcurrencyType:") func initializeContext(concurrencyType: UInt) -> NSObject
}

/// Notification names and their user info keys.
@ObjCConstants
enum Notifications {
    static let NSManagedObjectContextDidSaveNotification = "NSManagingContextDidSaveChangesNotification"
    static let NSManagedObjectContextWillSaveNotification = "NSManagingContextWillSaveChangesNotification"
    static let NSManagedObjectContextObjectsDidChangeNotification = "NSObjectsChangedInManagingContextNotification"
    static let NSInsertedObjectsKey = "inserted"
    static let NSUpdatedObjectsKey = "updated"
    static let NSDeletedObjectsKey = "deleted"
    static let NSRefreshedObjectsKey = "refreshed"
    static let NSInvalidatedObjectsKey = "invalidated"
    static let NSInvalidatedAllObjectsKey = "invalidatedAll"
}

/// Store options and error keys.
@ObjCConstants
enum Keys {
    static let NSAffectedStoresErrorKey = "NSAffectedStoresErrorKey"
    static let NSPersistentStoreSaveConflictsErrorKey = "NSPersistentStoreSaveConflictsErrorKey"
    static let NSValidationPredicateErrorKey = "NSValidationErrorPredicate"
    static let NSMigratePersistentStoresAutomaticallyOption = "NSMigratePersistentStoresAutomaticallyOption"
    static let NSInferMappingModelAutomaticallyOption = "NSInferMappingModelAutomaticallyOption"
    static let NSReadOnlyPersistentStoreOption = "NSReadOnlyPersistentStoreOption"
    static let NSPersistentStoreFileProtectionKey = "NSPersistentStoreFileProtectionKey"
    static let NSSQLitePragmasOption = "NSSQLitePragmasOption"
    static let NSValidationKeyErrorKey = "NSValidationErrorKey"
    static let NSValidationObjectErrorKey = "NSValidationErrorObject"
    static let NSValidationValueErrorKey = "NSValidationErrorValue"
    static let NSDetailedErrorsKey = "NSDetailedErrors"
    static let NSAffectedObjectsErrorKey = "NSAffectedObjectsErrorKey"
    static let NSPersistentStoreUbiquitousContentNameKey = "NSPersistentStoreUbiquitousContentNameKey"
    static let NSPersistentStoreUbiquitousContentURLKey = "NSPersistentStoreUbiquitousContentURLKey"
    static let NSPersistentStoreRemoveUbiquitousMetadataOption = "NSPersistentStoreRemoveUbiquitousMetadataOption"
    static let NSPersistentHistoryTrackingKey = "NSPersistentHistoryTrackingKey"
    static let NSPersistentStoreRemoteChangeNotificationPostOptionKey = "NSPersistentStoreRemoteChangeNotificationOptionKey"
    static let NSPersistentStoreRemoteChangeNotification = "NSPersistentStoreRemoteChangeNotification"
}

/// The coordinator's store-change notifications, which a store that does not
/// sync through iCloud never posts.
@ObjCConstants
enum StoreNotifications {
    static let NSPersistentStoreCoordinatorStoresDidChangeNotification = "NSPersistentStoreCoordinatorStoresDidChangeNotification"
    static let NSPersistentStoreCoordinatorStoresWillChangeNotification = "NSPersistentStoreCoordinatorStoresWillChangeNotification"
    static let NSPersistentStoreCoordinatorWillRemoveStoreNotification = "NSPersistentStoreCoordinatorWillRemoveStoreNotification"
    static let NSPersistentStoreDidImportUbiquitousContentChangesNotification = "com.apple.coredata.ubiquity.importer.didfinishimport"
    static let NSAddedPersistentStoresKey = "added"
    static let NSRemovedPersistentStoresKey = "removed"
    static let NSUUIDChangedPersistentStoresKey = "UUIDChangedPersistentStores"
}

// MARK: - CloudKit

/// A container whose stores would sync through CloudKit. With no iCloud
/// account here, it is a local container: its stores never sync.
@ObjCClass("NSPersistentCloudKitContainer")
open class NSPersistentCloudKitContainer: NSPersistentContainer {
    @ObjCMethod("initializeCloudKitSchemaWithOptions:error:")
    func initializeCloudKitSchema(options: UInt, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool { true }

    @ObjCMethod("canUpdateRecordForManagedObjectWithID:") func canUpdateRecord(forManagedObjectWithID id: NSObject?) -> Bool { true }
    @ObjCMethod("canDeleteRecordForManagedObjectWithID:") func canDeleteRecord(forManagedObjectWithID id: NSObject?) -> Bool { true }
    @ObjCMethod("canModifyManagedObjectsInStore:") func canModifyManagedObjects(in store: NSObject?) -> Bool { true }
}

final class CloudKitOptionsState: ObjectState {
    var containerIdentifier: String?
    /// CKDatabaseScope: private 2.
    var databaseScope = 2
}

@ObjCClass("NSPersistentCloudKitContainerOptions")
open class NSPersistentCloudKitContainerOptions: NSObject {
    static let states = StateTable<CloudKitOptionsState>()
    var state: CloudKitOptionsState { NSPersistentCloudKitContainerOptions.states[objcObject] }

    @ObjCMethod("initWithContainerIdentifier:")
    func initialize(containerIdentifier: String?) -> Self {
        state.containerIdentifier = containerIdentifier
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        NSPersistentCloudKitContainerOptions.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSPersistentCloudKitContainerOptions.objCClass.pointer)
    }

    @ObjCMethod("containerIdentifier") func containerIdentifier() -> String? { state.containerIdentifier }
    @ObjCMethod("databaseScope") func databaseScope() -> Int { state.databaseScope }
    @ObjCMethod("setDatabaseScope:") func setDatabaseScope(_ scope: Int) { state.databaseScope = scope }
}

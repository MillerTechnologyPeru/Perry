import CoreModel
import CoreModelSQLite
import PerryObjCInterop

// Persistent stores and the coordinator. SQLite stores are CoreModel-SQLite
// databases; every other type (in-memory, binary, XML, iCloud's and custom
// ones) is CoreModel's in-memory storage, keeping the type it was added as.

/// A store's CoreModel storage, used synchronously.
final class StoreBackend: @unchecked Sendable {
    let storage: any ModelStorage
    let model: Model
    private let lock = Lock()
    private var lastNumbers: [String: Int] = [:]

    init(storage: any ModelStorage, model: Model) {
        self.storage = storage
        self.model = model
    }

    func fetch(_ request: FetchRequest) throws -> [ModelData] {
        let storage = storage
        return try waitFor { try await storage.fetch(request) }
    }

    func fetch(_ entity: EntityName, _ id: ObjectID) throws -> ModelData? {
        let storage = storage
        return try waitFor { try await storage.fetch(entity, for: id) }
    }

    func save(inserting values: [ModelData], deleting removals: [(EntityName, ObjectID)]) throws {
        let storage = storage
        try waitFor {
            for (entity, id) in removals { try await storage.delete(entity, for: id) }
            if !values.isEmpty { try await storage.insert(values) }
        }
    }

    /// A new permanent ID: p1 and up for each entity, as Core Data numbers
    /// rows, kept as "Entity/p1" so IDs are unique across entities, as
    /// CoreModel's evaluation needs.
    func newID(_ entity: String) throws -> ObjectID {
        try lock.withLock {
            if lastNumbers[entity] == nil {
                let storage = storage
                let name = EntityName(rawValue: entity)
                let ids = try waitFor { try await storage.fetchID(FetchRequest(entity: name)) }
                lastNumbers[entity] = ids.compactMap { Int($0.rawValue.split(separator: "/").last?.dropFirst() ?? "") }.max() ?? 0
            }
            let number = lastNumbers[entity]! + 1
            lastNumbers[entity] = number
            return ObjectID(rawValue: "\(entity)/p\(number)")
        }
    }
}

final class StoreState: ObjectState {
    var type = ""
    var url: NSURL?
    var options: NSObject?
    var configuration: String?
    var identifier = ""
    var backend: StoreBackend?
    /// The coordinator; not retained.
    var coordinator: UnsafeMutableRawPointer?
}

@ObjCClass("NSPersistentStore")
open class NSPersistentStore: NSObject {
    static let states = StateTable<StoreState>()
    var state: StoreState { NSPersistentStore.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        NSPersistentStore.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSPersistentStore.objCClass.pointer)
    }

    @ObjCMethod("type") func type() -> String { state.type }
    @ObjCMethod("URL") func url() -> NSURL? { state.url }
    @ObjCMethod("setURL:") func setURL(_ url: NSURL?) { state.url = url }
    @ObjCMethod("identifier") func identifier() -> String { state.identifier }
    @ObjCMethod("options") func options() -> NSObject? { state.options }
    @ObjCMethod("configurationName") func configurationName() -> String { state.configuration ?? "PF_DEFAULT_CONFIGURATION_NAME" }
    @ObjCMethod("isReadOnly") func isReadOnly() -> Bool { false }
    @ObjCMethod("persistentStoreCoordinator")
    func persistentStoreCoordinator() -> NSPersistentStoreCoordinator? {
        state.coordinator.map { NSPersistentStoreCoordinator(objcObject: $0, ownership: .retain) }
    }
}

final class CoordinatorState: ObjectState {
    var model: NSManagedObjectModel?
    var stores: [NSPersistentStore] = []
    var name: String?
}

enum StoreErrors {
    /// NSCocoaErrorDomain errors, with a description.
    static func make(_ code: Int, _ description: String, _ extra: [(String, NSObject)] = []) -> NSError {
        NSError.make(domain: "NSCocoaErrorDomain", code: code,
                     userInfo: NSMutableDictionary.of([("NSLocalizedDescription", NSObject(description.objCArgument()!))] + extra))
    }

    /// An error whose description comes from Core Data's user info value
    /// provider rather than its dictionary, as Apple's multiple-error one.
    static func make(_ code: Int, _ extra: [(String, NSObject)]) -> NSError {
        NSError.make(domain: "NSCocoaErrorDomain", code: code, userInfo: NSMutableDictionary.of(extra))
    }

    /// Descriptions the provider supplies, by code.
    static let descriptions = [CoreDataErrors.multipleErrors: "Multiple validation errors occurred."]

    /// Registers the provider, a global block, for NSCocoaErrorDomain.
    static func registerProvider(globalBlockClass: UnsafeMutableRawPointer) {
        typealias Provide = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?)
            -> UnsafeMutableRawPointer?
        let provide: Provide = { _, error, key in
            guard let error, let key, String(objCArgument: key) == "NSLocalizedDescription",
                  NSError(objcObject: error, ownership: .retain).domain() == "NSCocoaErrorDomain",
                  let description = StoreErrors.descriptions[NSError(objcObject: error, ownership: .retain).code()]
            else { return nil }
            return description.objCArgument()
        }
        // Block_descriptor_1: reserved, size. Block_layout: isa, flags,
        // reserved, invoke, descriptor. BLOCK_IS_GLOBAL is 1 << 28.
        let descriptor = UnsafeMutablePointer<UInt>.allocate(capacity: 2)
        descriptor.initialize(from: [0, UInt(3 * MemoryLayout<UnsafeRawPointer>.size + 8)], count: 2)
        let block = UnsafeMutableRawPointer.allocate(byteCount: 3 * MemoryLayout<UnsafeRawPointer>.size + 8, alignment: 8)
        block.storeBytes(of: globalBlockClass, as: UnsafeMutableRawPointer.self)
        block.storeBytes(of: Int32(1 << 28), toByteOffset: MemoryLayout<UnsafeRawPointer>.size, as: Int32.self)
        block.storeBytes(of: Int32(0), toByteOffset: MemoryLayout<UnsafeRawPointer>.size + 4, as: Int32.self)
        block.storeBytes(of: unsafeBitCast(provide, to: UnsafeRawPointer.self), toByteOffset: MemoryLayout<UnsafeRawPointer>.size + 8, as: UnsafeRawPointer.self)
        block.storeBytes(of: UnsafeRawPointer(descriptor), toByteOffset: 2 * MemoryLayout<UnsafeRawPointer>.size + 8, as: UnsafeRawPointer.self)
        NSError.setUserInfoValueProvider(forDomain: "NSCocoaErrorDomain", provider: NSObject(objcObject: block, ownership: .borrow))
    }
}

@ObjCClass("NSPersistentStoreCoordinator")
open class NSPersistentStoreCoordinator: NSObject {
    static let states = StateTable<CoordinatorState>()
    var state: CoordinatorState { NSPersistentStoreCoordinator.states[objcObject] }

    var model: NSManagedObjectModel? { state.model }

    @ObjCMethod("initWithManagedObjectModel:")
    func initialize(model: NSManagedObjectModel) -> Self {
        state.model = model
        ManagedObjects.install(model)
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        NSPersistentStoreCoordinator.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSPersistentStoreCoordinator.objCClass.pointer)
    }

    @ObjCMethod("managedObjectModel") func managedObjectModel() -> NSManagedObjectModel? { state.model }
    @ObjCMethod("persistentStores") func persistentStores() -> NSObject { NSMutableArray.of(state.stores) }
    @ObjCMethod("name") func name() -> String? { state.name }
    @ObjCMethod("setName:") func setName(_ name: String?) { state.name = name }

    /// Adds a store: SQLite at the URL's path, any other type in memory.
    @ObjCMethod("addPersistentStoreWithType:configuration:URL:options:error:")
    func addPersistentStore(type: String, configuration: String?, url: NSURL?, options: NSObject?,
                            error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> NSPersistentStore? {
        guard let model = state.model?.coreModel else { return nil }
        let storage: any ModelStorage
        if type == StoreTypes.NSSQLiteStoreType {
            guard let path = url?.path(), url?.isFileURL() == true else {
                error?.pointee = StoreErrors.make(134080, "The store URL must be a file URL.").objCReturnValue()
                return nil
            }
            do {
                storage = try SQLiteDatabase(path: path, model: model)
            } catch let failure {
                error?.pointee = StoreErrors.make(134080, "The store couldn’t be opened: \(failure)").objCReturnValue()
                return nil
            }
        } else {
            storage = InMemoryModelStorage(model: model)
        }
        let store = NSPersistentStore.objCClass.object.newInstance().unsafeCast(to: NSPersistentStore.self)
        store.state.type = type
        store.state.url = url
        store.state.options = options
        store.state.configuration = configuration
        store.state.identifier = NSUUID.make().uuidString()
        store.state.backend = StoreBackend(storage: storage, model: model)
        store.state.coordinator = objcObject
        state.stores.append(store)
        return store
    }

    @ObjCMethod("removePersistentStore:error:")
    func removePersistentStore(_ store: NSPersistentStore, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        state.stores.removeAll { $0.objcObject == store.objcObject }
        return true
    }

    @ObjCMethod("persistentStoreForURL:")
    func persistentStore(for url: NSURL?) -> NSPersistentStore? {
        state.stores.first { $0.state.url?.absoluteString() == url?.absoluteString() }
    }

    @ObjCMethod("URLForPersistentStore:") func url(for store: NSPersistentStore) -> NSURL? { store.state.url }

    /// Deletes an SQLite store's files; other types have none.
    @ObjCMethod("destroyPersistentStoreAtURL:withType:options:error:")
    func destroyPersistentStore(at url: NSURL?, type: String, options: NSObject?,
                                error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        guard type == StoreTypes.NSSQLiteStoreType, let path = url?.path() else { return true }
        let manager = NSFileManager.defaultManager()
        for file in [path, path + "-wal", path + "-shm"] where manager.fileExists(atPath: file) {
            _ = manager.removeItem(atPath: file, error: nil)
        }
        return true
    }

    @ObjCMethod("managedObjectIDForURIRepresentation:")
    func managedObjectID(forURI url: NSURL?) -> NSManagedObjectID? {
        guard let parts = url?.absoluteString()?.dropFirst("x-coredata://".count).split(separator: "/"), parts.count == 3,
              let store = state.stores.first(where: { $0.state.identifier == parts[0] }),
              let entity = state.model?.entity(named: String(parts[1])) else { return nil }
        return NSManagedObjectID.make(entity: entity, store: store, id: ObjectID(rawValue: "\(parts[1])/\(parts[2])"),
                                      temporary: false)
    }
}

/// Store types and the constants that name them.
@ObjCConstants
enum StoreTypes {
    static let NSSQLiteStoreType = "SQLite"
    static let NSInMemoryStoreType = "InMemory"
    static let NSBinaryStoreType = "Binary"
    static let NSXMLStoreType = "XML"
}

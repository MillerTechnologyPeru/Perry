import CPerryFoundation
import FoundationEssentials
import Glibc
import PerryObjCInterop

// Spotlight and iCloud metadata queries. On iOS a query searches the app's
// iCloud containers; there is neither iCloud nor a metadata index here, so
// a query with a predicate starts, gathers and finishes as one with no
// matches does: NSMetadataQueryDidStartGatheringNotification as it starts,
// then NSMetadataQueryDidFinishGatheringNotification from the run loop (or
// the operation queue, if it has one), with no results, and no updates
// after. NSMetadataItem's -initWithURL: (macOS's) describes a file from
// the file system.

private func metadataClass(_ name: String) -> id? {
    name.withCString { ObjC.getClass($0) }.map { UnsafeMutableRawPointer($0) }
}

/// A copy of an object (+1), for copy properties.
private func copied(_ object: UnsafeMutableRawPointer?) -> ObjCObject? {
    object.flatMap { ObjC.send($0, Selectors.copyWithZone, nil) }.map { ObjCObject(objCOwned: $0) }
}

private func emptyArray() -> ObjCObject { ObjCObject(objCOwned: Arrays.make([])) }

private func raiseOutOfBounds(_ method: String, _ index: UInt) -> Never {
    Exceptions.raise(name: "NSInvalidArgumentException", reason: "*** -[NSMetadataQuery \(method)]: index (\(index)) out of bounds (0)")
}

// MARK: - Queries

final class MetadataQueryStorage {
    /// Unretained, as the property is assign.
    var delegate: id?
    var predicate: ObjCObject?
    var sortDescriptors: ObjCObject? = emptyArray()
    var valueListAttributes: ObjCObject? = emptyArray()
    var groupingAttributes: ObjCObject? = emptyArray()
    var notificationBatchingInterval: Double = 1
    var searchScopes: ObjCObject? = emptyArray()
    var searchItems: ObjCObject?
    var operationQueue: ObjCObject?
    var started = false
    var gathering = false
    var stopped = false
    var disabledUpdates = 0
}

@ObjCClass("NSMetadataQuery")
public class NSMetadataQuery: NSObject {
    nonisolated(unsafe) static var queryClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        queryClass = cls.storage
    }

    var storage: MetadataQueryStorage {
        if let storage = Storage.get(objcObject, as: MetadataQueryStorage.self) { return storage }
        let storage = MetadataQueryStorage()
        Storage.set(objcObject, storage)
        return storage
    }

    @ObjCMethod("init")
    func initialize() -> Self {
        _ = storage
        return self
    }

    @ObjCMethod("delegate") func delegate() -> UnsafeMutableRawPointer? { storage.delegate }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: UnsafeMutableRawPointer?) { storage.delegate = delegate }

    @ObjCMethod("predicate") func predicate() -> UnsafeMutableRawPointer? { storage.predicate?.id }
    @ObjCMethod("setPredicate:") func setPredicate(_ predicate: UnsafeMutableRawPointer?) { storage.predicate = copied(predicate) }

    @ObjCMethod("sortDescriptors") func sortDescriptors() -> UnsafeMutableRawPointer? { storage.sortDescriptors?.id }
    @ObjCMethod("setSortDescriptors:")
    func setSortDescriptors(_ descriptors: UnsafeMutableRawPointer?) { storage.sortDescriptors = copied(descriptors) }

    @ObjCMethod("valueListAttributes") func valueListAttributes() -> UnsafeMutableRawPointer? { storage.valueListAttributes?.id }
    @ObjCMethod("setValueListAttributes:")
    func setValueListAttributes(_ attributes: UnsafeMutableRawPointer?) { storage.valueListAttributes = copied(attributes) }

    @ObjCMethod("groupingAttributes") func groupingAttributes() -> UnsafeMutableRawPointer? { storage.groupingAttributes?.id }
    @ObjCMethod("setGroupingAttributes:")
    func setGroupingAttributes(_ attributes: UnsafeMutableRawPointer?) { storage.groupingAttributes = copied(attributes) }

    @ObjCMethod("notificationBatchingInterval") func notificationBatchingInterval() -> Double { storage.notificationBatchingInterval }
    @ObjCMethod("setNotificationBatchingInterval:")
    func setNotificationBatchingInterval(_ interval: Double) { storage.notificationBatchingInterval = interval }

    @ObjCMethod("searchScopes") func searchScopes() -> UnsafeMutableRawPointer? { storage.searchScopes?.id }
    @ObjCMethod("setSearchScopes:") func setSearchScopes(_ scopes: UnsafeMutableRawPointer?) { storage.searchScopes = copied(scopes) }

    @ObjCMethod("searchItems") func searchItems() -> UnsafeMutableRawPointer? { storage.searchItems?.id }
    @ObjCMethod("setSearchItems:") func setSearchItems(_ items: UnsafeMutableRawPointer?) { storage.searchItems = copied(items) }

    @ObjCMethod("operationQueue") func operationQueue() -> UnsafeMutableRawPointer? { storage.operationQueue?.id }
    @ObjCMethod("setOperationQueue:")
    func setOperationQueue(_ queue: UnsafeMutableRawPointer?) { storage.operationQueue = queue.map { ObjCObject($0) } }

    @ObjCMethod("isStarted") func isStarted() -> Bool { storage.started }
    @ObjCMethod("isGathering") func isGathering() -> Bool { storage.gathering }
    @ObjCMethod("isStopped") func isStopped() -> Bool { storage.stopped }

    private func post(_ name: String) {
        guard let center = ObjC.send(metadataClass("NSNotificationCenter"), ObjC.selector("defaultCenter")) else { return }
        _ = ObjC.send(center, ObjC.selector("postNotificationName:object:"), Strings.autoreleased(name), objcObject)
    }

    /// Starts gathering, as Darwin does once it has a predicate: the start
    /// is told at once (the query not yet started meanwhile), the end later.
    /// NO without a predicate, or while the query runs.
    @ObjCMethod("startQuery")
    func startQuery() -> Bool {
        let storage = self.storage
        guard storage.predicate != nil, !(storage.started && !storage.stopped) else { return false }
        storage.stopped = false
        storage.gathering = true
        post("NSMetadataQueryDidStartGatheringNotification")
        storage.started = true
        let finish = ObjC.selector("_perryFinishGathering")
        if let queue = storage.operationQueue?.id,
           let operation = ObjC.send(metadataClass("NSInvocationOperation"), ObjC.selector("alloc")) {
            typealias Make = @convention(c) (id?, SEL, id?, SEL, id?) -> id?
            let made = unsafeBitCast(ObjC.msgSend, to: Make.self)(operation, ObjC.selector("initWithTarget:selector:object:"),
                                                                  objcObject, finish, nil)
            _ = ObjC.send(queue, ObjC.selector("addOperation:"), made)
            ObjC.release(made)
        } else {
            typealias Perform = @convention(c) (id?, SEL, SEL, id?, Double) -> Void
            unsafeBitCast(ObjC.msgSend, to: Perform.self)(objcObject, ObjC.selector("performSelector:withObject:afterDelay:"),
                                                          finish, nil, 0)
        }
        return true
    }

    /// Gathering's end: no results were found.
    @ObjCMethod("_perryFinishGathering")
    func finishGathering() {
        let storage = self.storage
        guard storage.gathering, !storage.stopped else { return }
        storage.gathering = false
        post("NSMetadataQueryDidFinishGatheringNotification")
    }

    @ObjCMethod("stopQuery")
    func stopQuery() {
        let storage = self.storage
        guard storage.started else { return }
        storage.gathering = false
        storage.stopped = true
    }

    /// Updates would be held back meanwhile; none come.
    @ObjCMethod("disableUpdates") func disableUpdates() { storage.disabledUpdates += 1 }
    @ObjCMethod("enableUpdates") func enableUpdates() { storage.disabledUpdates = max(0, storage.disabledUpdates - 1) }

    @ObjCMethod("resultCount") func resultCount() -> UInt { 0 }

    @ObjCMethod("resultAtIndex:")
    func result(at index: UInt) -> UnsafeMutableRawPointer? { raiseOutOfBounds("resultAtIndex:", index) }

    @ObjCMethod("results") func results() -> UnsafeMutableRawPointer? { Arrays.autoreleased([]) }

    @ObjCMethod("enumerateResultsUsingBlock:")
    func enumerateResults(block: UnsafeMutableRawPointer?) {}

    @ObjCMethod("enumerateResultsWithOptions:usingBlock:")
    func enumerateResults(options: UInt, block: UnsafeMutableRawPointer?) {}

    /// NSNotFound: no result is one of the query's.
    @ObjCMethod("indexOfResult:") func index(ofResult result: UnsafeMutableRawPointer?) -> UInt { UInt(Int.max) }

    @ObjCMethod("valueLists") func valueLists() -> UnsafeMutableRawPointer? { Dictionaries.autoreleased([]) }
    @ObjCMethod("groupedResults") func groupedResults() -> UnsafeMutableRawPointer? { Arrays.autoreleased([]) }

    @ObjCMethod("valueOfAttribute:forResultAtIndex:")
    func value(ofAttribute attribute: UnsafeMutableRawPointer?, forResultAt index: UInt) -> UnsafeMutableRawPointer? {
        raiseOutOfBounds("valueOfAttribute:forResultAtIndex:", index)
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NSMetadataQuery.queryClass)
    }
}

// MARK: - Items

/// An item's attributes, by Spotlight's names (kMDItemFSName…).
final class MetadataItemStorage {
    var names: [String] = []
    var values: [String: ObjCObject] = [:]
}

@ObjCClass("NSMetadataItem")
public class NSMetadataItem: NSObject {
    nonisolated(unsafe) static var itemClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        itemClass = cls.storage
    }

    var storage: MetadataItemStorage {
        if let storage = Storage.get(objcObject, as: MetadataItemStorage.self) { return storage }
        let storage = MetadataItemStorage()
        Storage.set(objcObject, storage)
        return storage
    }

    @ObjCMethod("init")
    func initialize() -> Self {
        _ = storage
        return self
    }

    /// The file's attributes, as Spotlight has them for it: nil if there is
    /// no file. `attributes` lists the file system's own, as Darwin's does;
    /// the display name, path, URL and content type are answered too.
    @ObjCMethod("initWithURL:")
    func initialize(url: UnsafeMutableRawPointer?) -> Self? {
        guard let fileURL = URLs.url(url), fileURL.isFileURL else { return nil }
        let path = fileURL.path
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        let storage = MetadataItemStorage()
        func add(_ name: String, _ value: id?, listed: Bool) {
            guard let value else { return }
            storage.values[name] = ObjCObject(value)
            if listed { storage.names.append(name) }
        }
        let name = path.split(separator: "/").last.map(String.init) ?? path
        let isRegular = info.st_mode & S_IFMT == S_IFREG
        let manager = ObjC.send(metadataClass("NSFileManager"), ObjC.selector("defaultManager"))
        let attributes = ObjC.send(manager, ObjC.selector("attributesOfItemAtPath:error:"), Strings.autoreleased(path), nil)
        func attribute(_ key: String) -> id? { Dictionaries.value(attributes, for: Strings.autoreleased(key)) }

        add("kMDItemFSName", Strings.autoreleased(name), listed: true)
        if isRegular { add("kMDItemFSSize", Numbers.make(nil, .signed(Int64(info.st_size))), listed: true) }
        add("kMDItemFSCreationDate", attribute("NSFileCreationDate"), listed: true)
        add("kMDItemFSContentChangeDate", attribute("NSFileModificationDate"), listed: true)
        add("kMDItemFSOwnerUserID", Numbers.make(nil, .signed(Int64(info.st_uid))), listed: true)
        add("kMDItemFSOwnerGroupID", Numbers.make(nil, .signed(Int64(info.st_gid))), listed: true)
        add("kMDItemFSInvisible", Numbers.make(nil, .bool(name.hasPrefix("."))), listed: true)
        add("kMDItemDisplayName", Strings.autoreleased(name), listed: false)
        var resolved = path
        if let real = realpath(path, nil) {
            resolved = String(cString: real)
            free(real)
        }
        add("kMDItemPath", Strings.autoreleased(resolved), listed: false)
        add("kMDItemURL", URLs.autoreleased(URLs.fileURL(resolved, isDirectory: !isRegular && info.st_mode & S_IFMT == S_IFDIR)),
            listed: false)
        let ext = name.lastIndex(of: ".").map { String(name[name.index(after: $0)...]) } ?? ""
        if isRegular, let type = ItemProviderTypes.type(forExtension: ext) {
            add("kMDItemContentType", Strings.autoreleased(type), listed: false)
        }
        Storage.set(objcObject, storage)
        return self
    }

    @ObjCMethod("valueForAttribute:")
    func value(forAttribute attribute: String?) -> UnsafeMutableRawPointer? {
        attribute.flatMap { storage.values[$0]?.id }
    }

    /// The attributes the item has a value for, by name.
    @ObjCMethod("valuesForAttributes:")
    func values(forAttributes attributes: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        var entries: [(key: id, value: id)] = []
        for name in Arrays.elements(attributes) {
            guard let key = Strings.value(of: name), let value = storage.values[key] else { continue }
            entries.append((key: name, value: value.id))
        }
        return Dictionaries.autoreleased(entries)
    }

    @ObjCMethod("attributes")
    func attributes() -> UnsafeMutableRawPointer? { Arrays.autoreleased(storage.names.map { Strings.autoreleased($0) }) }

    /// Key-value coding reads attributes, as on Darwin.
    @ObjCMethod("valueForKey:")
    func value(forKey key: String?) -> UnsafeMutableRawPointer? { value(forAttribute: key) }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NSMetadataItem.itemClass)
    }
}

// MARK: - Value lists and groups

/// A value of a value-list attribute and how many results have it. Only a
/// query's results make them, and a query has none here.
final class MetadataTupleStorage {
    var attribute: String = ""
    var value: ObjCObject?
    var count: UInt = 0
}

@ObjCClass("NSMetadataQueryAttributeValueTuple")
public class NSMetadataQueryAttributeValueTuple: NSObject {
    nonisolated(unsafe) static var tupleClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        tupleClass = cls.storage
    }

    private var storage: MetadataTupleStorage? { Storage.get(objcObject, as: MetadataTupleStorage.self) }

    @ObjCMethod("attribute") func attribute() -> String { storage?.attribute ?? "" }
    @ObjCMethod("value") func value() -> UnsafeMutableRawPointer? { storage?.value?.id }
    @ObjCMethod("count") func count() -> UInt { storage?.count ?? 0 }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NSMetadataQueryAttributeValueTuple.tupleClass)
    }
}

/// The results sharing a value of a grouping attribute. Only a query's
/// results make them, and a query has none here.
final class MetadataGroupStorage {
    var attribute: String = ""
    var value: ObjCObject?
    var subgroups: ObjCObject?
    var results: [ObjCObject] = []
}

@ObjCClass("NSMetadataQueryResultGroup")
public class NSMetadataQueryResultGroup: NSObject {
    nonisolated(unsafe) static var groupClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        groupClass = cls.storage
    }

    private var storage: MetadataGroupStorage? { Storage.get(objcObject, as: MetadataGroupStorage.self) }

    @ObjCMethod("attribute") func attribute() -> String { storage?.attribute ?? "" }
    @ObjCMethod("value") func value() -> UnsafeMutableRawPointer? { storage?.value?.id }
    @ObjCMethod("subgroups") func subgroups() -> UnsafeMutableRawPointer? { storage?.subgroups?.id }
    @ObjCMethod("resultCount") func resultCount() -> UInt { UInt(storage?.results.count ?? 0) }

    @ObjCMethod("resultAtIndex:")
    func result(at index: UInt) -> UnsafeMutableRawPointer? {
        let results = storage?.results ?? []
        guard index < UInt(results.count) else {
            Exceptions.raise(name: "NSInvalidArgumentException",
                             reason: "*** -[NSMetadataQueryResultGroup resultAtIndex:]: index (\(index)) out of bounds (\(results.count))")
        }
        return results[Int(index)].id
    }

    @ObjCMethod("results")
    func results() -> UnsafeMutableRawPointer? { Arrays.autoreleased((storage?.results ?? []).map { $0.id }) }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NSMetadataQueryResultGroup.groupClass)
    }
}

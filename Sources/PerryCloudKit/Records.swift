import Glibc
import PerryObjCInterop

// CloudKit's records, queries and operations, without iCloud: records and
// queries keep what a program puts in them, and an operation added to a
// database finishes at once with the error of an account that is not
// signed in, which is how a program that reads its saves from iCloud at
// launch learns there are none.

/// What each of these objects keeps.
final class CloudState {
    var name: String?
    var type: String?
    var recordID: NSObject?
    var predicate: NSObject?
    var url: NSObject?
    var values: [String: NSObject] = [:]
    var query: NSObject?
    var desiredKeys: NSObject?
    var resultsLimit: UInt = 0
    var recordFetched: ObjCBlock?
    var queryCompletion: ObjCBlock?
    var modifyCompletion: ObjCBlock?
    var perRecordCompletion: ObjCBlock?
    var fetchCompletion: ObjCBlock?
    var completion: ObjCBlock?
    var savePolicy = 0
    var qualityOfService = -1
}

enum Cloud {
    static let states = StateTable<CloudState>()

    static func state(_ object: UnsafeMutableRawPointer) -> CloudState {
        if let state = states[object] { return state }
        let state = CloudState()
        states.set(object, state)
        return state
    }
}

@ObjCClass("CKRecordID")
open class CKRecordID: NSObject {
    var cloud: CloudState { Cloud.state(objcObject) }

    @ObjCMethod("dealloc")
    func dealloc() {
        Cloud.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CKRecordID.objCClass.pointer)
    }

    @ObjCMethod("initWithRecordName:")
    func initialize(recordName: String?) -> Self {
        cloud.name = recordName
        return self
    }

    @ObjCMethod("initWithRecordName:zoneID:")
    func initialize(recordName: String?, zoneID: NSObject?) -> Self { initialize(recordName: recordName) }

    @ObjCMethod("recordName") func recordName() -> String? { cloud.name }
    @ObjCMethod("zoneID") func zoneID() -> NSObject? { nil }
}

@ObjCClass("CKRecord")
open class CKRecord: NSObject {
    var cloud: CloudState { Cloud.state(objcObject) }

    @ObjCMethod("dealloc")
    func dealloc() {
        Cloud.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CKRecord.objCClass.pointer)
    }

    @ObjCMethod("initWithRecordType:")
    func initialize(recordType: String?) -> Self {
        cloud.type = recordType
        return self
    }

    @ObjCMethod("initWithRecordType:recordID:")
    func initialize(recordType: String?, recordID: NSObject?) -> Self {
        (cloud.type, cloud.recordID) = (recordType, recordID)
        return self
    }

    @ObjCMethod("recordType") func recordType() -> String? { cloud.type }
    @ObjCMethod("recordID") func recordID() -> NSObject? { cloud.recordID }
    @ObjCMethod("objectForKey:") func object(forKey key: String?) -> NSObject? { key.flatMap { cloud.values[$0] } }
    @ObjCMethod("objectForKeyedSubscript:") func object(forKeyedSubscript key: String?) -> NSObject? { object(forKey: key) }

    @ObjCMethod("setObject:forKey:")
    func set(object: NSObject?, forKey key: String?) {
        if let key { cloud.values[key] = object }
    }

    @ObjCMethod("setObject:forKeyedSubscript:") func set(object: NSObject?, forKeyedSubscript key: String?) { set(object: object, forKey: key) }
    @ObjCMethod("creationDate") func creationDate() -> NSObject? { nil }
    @ObjCMethod("modificationDate") func modificationDate() -> NSObject? { nil }
    @ObjCMethod("recordChangeTag") func recordChangeTag() -> String? { nil }
}

@ObjCClass("CKAsset")
open class CKAsset: NSObject {
    var cloud: CloudState { Cloud.state(objcObject) }

    @ObjCMethod("dealloc")
    func dealloc() {
        Cloud.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CKAsset.objCClass.pointer)
    }

    @ObjCMethod("initWithFileURL:")
    func initialize(fileURL: NSObject?) -> Self {
        cloud.url = fileURL
        return self
    }

    @ObjCMethod("fileURL") func fileURL() -> NSObject? { cloud.url }
}

@ObjCClass("CKQuery")
open class CKQuery: NSObject {
    var cloud: CloudState { Cloud.state(objcObject) }

    @ObjCMethod("dealloc")
    func dealloc() {
        Cloud.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CKQuery.objCClass.pointer)
    }

    @ObjCMethod("initWithRecordType:predicate:")
    func initialize(recordType: String?, predicate: NSObject?) -> Self {
        (cloud.type, cloud.predicate) = (recordType, predicate)
        return self
    }

    @ObjCMethod("recordType") func recordType() -> String? { cloud.type }
    @ObjCMethod("predicate") func predicate() -> NSObject? { cloud.predicate }
    @ObjCMethod("sortDescriptors") func sortDescriptors() -> NSObject? { nil }
    @ObjCMethod("setSortDescriptors:") func setSortDescriptors(_ descriptors: NSObject?) {}
}

// MARK: - Operations

@ObjCClass("CKOperation")
open class CKOperation: NSObject {
    var cloud: CloudState { Cloud.state(objcObject) }

    @ObjCMethod("dealloc")
    func dealloc() {
        Cloud.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CKOperation.objCClass.pointer)
    }

    /// Ends the operation, on a database without an account: its
    /// completion blocks are called with CKErrorNotAuthenticated.
    func finishWithoutAccount() {
        if let block = cloud.completion {
            typealias Invoke = @convention(c) (UnsafeMutableRawPointer) -> Void
            block.function(as: Invoke.self)(block.object)
        }
    }

    @ObjCMethod("start") func start() { finishWithoutAccount() }
    @ObjCMethod("cancel") func cancel() {}
    @ObjCMethod("isFinished") func isFinished() -> Bool { true }
    @ObjCMethod("isExecuting") func isExecuting() -> Bool { false }
    @ObjCMethod("isCancelled") func isCancelled() -> Bool { false }
    @ObjCMethod("database") func database() -> NSObject? { CKDatabase.shared }
    @ObjCMethod("setDatabase:") func setDatabase(_ database: NSObject?) {}
    @ObjCMethod("container") func container() -> NSObject? { nil }
    @ObjCMethod("setContainer:") func setContainer(_ container: NSObject?) {}
    @ObjCMethod("qualityOfService") func qualityOfService() -> Int { cloud.qualityOfService }
    @ObjCMethod("setQualityOfService:") func setQualityOfService(_ quality: Int) { cloud.qualityOfService = quality }
    @ObjCMethod("completionBlock") func completionBlock() -> ObjCBlock? { cloud.completion }
    @ObjCMethod("setCompletionBlock:") func setCompletionBlock(_ block: ObjCBlock?) { cloud.completion = block }
    @ObjCMethod("setAllowsCellularAccess:") func setAllowsCellularAccess(_ allows: Bool) {}
    @ObjCMethod("setZoneID:") func setZoneID(_ zone: NSObject?) {}
}

@ObjCClass("CKDatabaseOperation")
open class CKDatabaseOperation: CKOperation {
}

@ObjCClass("CKQueryOperation")
open class CKQueryOperation: CKDatabaseOperation {
    @ObjCMethod("initWithQuery:")
    func initialize(query: NSObject?) -> Self {
        cloud.query = query
        return self
    }

    @ObjCMethod("initWithCursor:") func initialize(cursor: NSObject?) -> Self { self }
    @ObjCMethod("query") func query() -> NSObject? { cloud.query }
    @ObjCMethod("setQuery:") func setQuery(_ query: NSObject?) { cloud.query = query }
    @ObjCMethod("desiredKeys") func desiredKeys() -> NSObject? { cloud.desiredKeys }
    @ObjCMethod("setDesiredKeys:") func setDesiredKeys(_ keys: NSObject?) { cloud.desiredKeys = keys }
    @ObjCMethod("resultsLimit") func resultsLimit() -> UInt { cloud.resultsLimit }
    @ObjCMethod("setResultsLimit:") func setResultsLimit(_ limit: UInt) { cloud.resultsLimit = limit }
    @ObjCMethod("recordFetchedBlock") func recordFetchedBlock() -> ObjCBlock? { cloud.recordFetched }
    @ObjCMethod("setRecordFetchedBlock:") func setRecordFetchedBlock(_ block: ObjCBlock?) { cloud.recordFetched = block }
    @ObjCMethod("queryCompletionBlock") func queryCompletionBlock() -> ObjCBlock? { cloud.queryCompletion }
    @ObjCMethod("setQueryCompletionBlock:") func setQueryCompletionBlock(_ block: ObjCBlock?) { cloud.queryCompletion = block }

    /// No records, no cursor, and the error.
    override func finishWithoutAccount() {
        if let block = cloud.queryCompletion {
            typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
            block.function(as: Invoke.self)(block.object, nil, CKDatabase.notAuthenticated().objcObject)
        }
        super.finishWithoutAccount()
    }
}

@ObjCClass("CKModifyRecordsOperation")
open class CKModifyRecordsOperation: CKDatabaseOperation {
    @ObjCMethod("initWithRecordsToSave:recordIDsToDelete:")
    func initialize(recordsToSave: NSObject?, recordIDsToDelete: NSObject?) -> Self { self }

    @ObjCMethod("setRecordsToSave:") func setRecordsToSave(_ records: NSObject?) {}
    @ObjCMethod("setRecordIDsToDelete:") func setRecordIDsToDelete(_ ids: NSObject?) {}
    @ObjCMethod("savePolicy") func savePolicy() -> Int { cloud.savePolicy }
    @ObjCMethod("setSavePolicy:") func setSavePolicy(_ policy: Int) { cloud.savePolicy = policy }
    @ObjCMethod("setAtomic:") func setAtomic(_ atomic: Bool) {}
    @ObjCMethod("setPerRecordProgressBlock:") func setPerRecordProgressBlock(_ block: ObjCBlock?) {}
    @ObjCMethod("perRecordCompletionBlock") func perRecordCompletionBlock() -> ObjCBlock? { cloud.perRecordCompletion }
    @ObjCMethod("setPerRecordCompletionBlock:") func setPerRecordCompletionBlock(_ block: ObjCBlock?) { cloud.perRecordCompletion = block }
    @ObjCMethod("modifyRecordsCompletionBlock") func modifyRecordsCompletionBlock() -> ObjCBlock? { cloud.modifyCompletion }
    @ObjCMethod("setModifyRecordsCompletionBlock:") func setModifyRecordsCompletionBlock(_ block: ObjCBlock?) { cloud.modifyCompletion = block }

    /// Nothing saved, nothing deleted, and the error.
    override func finishWithoutAccount() {
        if let block = cloud.modifyCompletion {
            typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?,
                                               UnsafeMutableRawPointer?) -> Void
            block.function(as: Invoke.self)(block.object, nil, nil, CKDatabase.notAuthenticated().objcObject)
        }
        super.finishWithoutAccount()
    }
}

@ObjCClass("CKFetchRecordsOperation")
open class CKFetchRecordsOperation: CKDatabaseOperation {
    @ObjCMethod("initWithRecordIDs:") func initialize(recordIDs: NSObject?) -> Self { self }
    @ObjCMethod("setRecordIDs:") func setRecordIDs(_ ids: NSObject?) {}
    @ObjCMethod("setDesiredKeys:") func setDesiredKeys(_ keys: NSObject?) { cloud.desiredKeys = keys }
    @ObjCMethod("setPerRecordProgressBlock:") func setPerRecordProgressBlock(_ block: ObjCBlock?) {}
    @ObjCMethod("setPerRecordCompletionBlock:") func setPerRecordCompletionBlock(_ block: ObjCBlock?) { cloud.perRecordCompletion = block }
    @ObjCMethod("fetchRecordsCompletionBlock") func fetchRecordsCompletionBlock() -> ObjCBlock? { cloud.fetchCompletion }
    @ObjCMethod("setFetchRecordsCompletionBlock:") func setFetchRecordsCompletionBlock(_ block: ObjCBlock?) { cloud.fetchCompletion = block }

    /// No records, and the error.
    override func finishWithoutAccount() {
        if let block = cloud.fetchCompletion {
            typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
            block.function(as: Invoke.self)(block.object, nil, CKDatabase.notAuthenticated().objcObject)
        }
        super.finishWithoutAccount()
    }
}

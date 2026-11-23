// CKDatabase's Swift API: async and Result-based fetches and changes of
// records, zones and subscriptions, made of CloudKit's operations, and
// databases and containers configured for a body's operations.

import Foundation

// MARK: - Configured operations

/// The configuration and group a configured database or container gives
/// the operations it makes, for the body running.
struct OperationSettings: Sendable {
    var configuration: CKOperation.Configuration?
    var group: CKOperationGroup?

    @TaskLocal static var current = OperationSettings()

    /// The settings of the synchronous body running on this thread.
    static var threadCurrent: OperationSettings? {
        get { Thread.current.threadDictionary[threadKey] as? OperationSettings }
        set { Thread.current.threadDictionary[threadKey] = newValue }
    }

    private static let threadKey = "com.apple.cloudkit.operation-settings"

    /// The settings in effect: the thread's, else the task's.
    static var effective: OperationSettings {
        threadCurrent ?? current
    }

    func apply(to operation: CKOperation) {
        if let configuration { operation.configuration = configuration }
        if let group { operation.group = group }
    }
}

/// Runs a synchronous body with operation settings.
func withSettings<R>(_ settings: OperationSettings, _ body: () throws -> R) rethrows -> R {
    let previous = OperationSettings.threadCurrent
    OperationSettings.threadCurrent = settings
    defer { OperationSettings.threadCurrent = previous }
    return try body()
}

extension CKDatabase {
    /// Adds an operation with the settings in effect.
    func run(_ operation: CKDatabaseOperation) {
        OperationSettings.effective.apply(to: operation)
        add(operation)
    }
}

extension CKContainer {
    /// Adds an operation with the settings in effect.
    func run(_ operation: CKOperation) {
        OperationSettings.effective.apply(to: operation)
        add(operation)
    }
}

/// Answers an async call with what a completion handler gave.
func awaitResult<T: Sendable>(_ start: (@escaping @Sendable (Result<T, any Error>) -> Void) -> Void) async throws -> T {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, any Error>) in
        start { continuation.resume(with: $0) }
    }
}

/// A box of results that operation blocks fill from CloudKit's queues.
final class ResultsBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    func update(_ change: (inout Value) -> Void) {
        lock.withLock { change(&storage) }
    }

    var value: Value { lock.withLock { storage } }
}

@available(macOS 10.10, macCatalyst 13.1, iOS 8.0, tvOS 9.0, watchOS 3.0, *)
extension CKDatabase {
    @available(macOS, introduced: 12.0, deprecated: 12.0, message: "renamed to records(matching:inZoneWith:desiredKeys:resultsLimit:)")
    @available(macCatalyst, introduced: 15.0, deprecated: 15.0, message: "renamed to records(matching:inZoneWith:desiredKeys:resultsLimit:)")
    @available(iOS, introduced: 15.0, deprecated: 15.0, message: "renamed to records(matching:inZoneWith:desiredKeys:resultsLimit:)")
    @available(tvOS, introduced: 15.0, deprecated: 15.0, message: "renamed to records(matching:inZoneWith:desiredKeys:resultsLimit:)")
    @available(watchOS, introduced: 8.0, deprecated: 8.0, message: "renamed to records(matching:inZoneWith:desiredKeys:resultsLimit:)")
    @_disfavoredOverload
    public func records(matching query: CKQuery, inZoneWith zoneID: CKRecordZone.ID?) async throws -> [CKRecord] {
        var cursor: CKQueryOperation.Cursor?
        var found: [CKRecord] = []
        repeat {
            let page: (matchResults: [(CKRecord.ID, Result<CKRecord, any Error>)], queryCursor: CKQueryOperation.Cursor?)
            if let cursor {
                page = try await self.records(continuingMatchFrom: cursor)
            } else {
                page = try await self.records(matching: query, inZoneWith: zoneID, desiredKeys: nil)
            }
            found += try page.matchResults.map { try $0.1.get() }
            cursor = page.queryCursor
        } while cursor != nil
        return found
    }
}

@available(macOS 10.10, macCatalyst 13.1, iOS 8.0, tvOS 9.0, watchOS 6.0, *)
extension CKDatabase {
    @available(macOS 12.0, macCatalyst 15.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    @usableFromInline
    internal func _allSubscriptions() async throws -> [CKSubscription] {
        try await awaitResult { done in fetchAllSubscriptions { done(result($0, $1)) } }
    }

    @preconcurrency
    public func fetch(withSubscriptionID subscriptionID: CKSubscription.ID, completionHandler: @escaping @Sendable (CKSubscription?, (any Error)?) -> Void) {
        __fetch(withSubscriptionID: subscriptionID, completionHandler: completionHandler)
    }

    @available(macOS 12.0, macCatalyst 15.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    public func subscription(for subscriptionID: CKSubscription.ID) async throws -> CKSubscription {
        try await awaitResult { done in __fetch(withSubscriptionID: subscriptionID) { done(result($0, $1)) } }
    }

    @available(macOS 12.0, macCatalyst 15.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    @usableFromInline
    internal func _save(_ subscription: CKSubscription) async throws -> CKSubscription {
        try await awaitResult { done in save(subscription) { done(result($0, $1)) } }
    }

    @preconcurrency
    public func delete(withSubscriptionID subscriptionID: CKSubscription.ID, completionHandler: @escaping @Sendable (String?, (any Error)?) -> Void) {
        __delete(withSubscriptionID: subscriptionID, completionHandler: completionHandler)
    }

    @available(macOS 12.0, macCatalyst 15.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    @discardableResult
    public func deleteSubscription(withID subscriptionID: CKSubscription.ID) async throws -> CKSubscription.ID {
        try await awaitResult { done in __delete(withSubscriptionID: subscriptionID) { done(result($0, $1)) } }
    }
}

@available(macOS 12.0, macCatalyst 15.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension CKDatabase {
    /// Runs the body with the database, its operations given the
    /// configuration and group.
    @discardableResult
    public func configuredWith<R>(configuration: CKOperation.Configuration? = nil, group: CKOperationGroup? = nil, body: (_ configuredDatabase: CKDatabase) throws -> R) rethrows -> R {
        try withSettings(OperationSettings(configuration: configuration, group: group)) { try body(self) }
    }

    @discardableResult
    @preconcurrency
    public func configuredWith<R>(configuration: CKOperation.Configuration? = nil, group: CKOperationGroup? = nil, body: @Sendable (_ configuredDatabase: CKDatabase) async throws -> R) async rethrows -> R {
        try await OperationSettings.$current.withValue(OperationSettings(configuration: configuration, group: group)) {
            try await body(self)
        }
    }

    @usableFromInline
    internal func _record(for recordID: CKRecord.ID) async throws -> CKRecord {
        try await awaitResult { done in fetch(withRecordID: recordID) { done(result($0, $1)) } }
    }

    @preconcurrency
    public func fetch(withRecordIDs recordIDs: [CKRecord.ID], desiredKeys: [CKRecord.FieldKey]? = nil, completionHandler: @escaping @Sendable (Result<[CKRecord.ID: Result<CKRecord, any Error>], any Error>) -> Void) {
        let operation = CKFetchRecordsOperation(recordIDs: recordIDs)
        operation.desiredKeys = desiredKeys
        let results = ResultsBox([CKRecord.ID: Result<CKRecord, any Error>]())
        operation.perRecordResultBlock = { id, outcome in results.update { $0[id] = outcome } }
        operation.fetchRecordsResultBlock = { outcome in
            completionHandler(outcome.map { results.value })
        }
        run(operation)
    }

    public func records(for ids: [CKRecord.ID], desiredKeys: [CKRecord.FieldKey]? = nil) async throws -> [CKRecord.ID: Result<CKRecord, any Error>] {
        try await awaitResult { done in fetch(withRecordIDs: ids, desiredKeys: desiredKeys, completionHandler: done) }
    }

    @usableFromInline
    internal func _save(_ record: CKRecord) async throws -> CKRecord {
        try await awaitResult { done in save(record) { done(result($0, $1)) } }
    }

    @usableFromInline
    internal func _deleteRecord(withID recordID: CKRecord.ID) async throws -> CKRecord.ID {
        try await awaitResult { done in delete(withRecordID: recordID) { done(result($0, $1)) } }
    }

    @preconcurrency
    public func modifyRecords(saving recordsToSave: [CKRecord], deleting recordIDsToDelete: [CKRecord.ID], savePolicy: CKModifyRecordsOperation.RecordSavePolicy = .ifServerRecordUnchanged, atomically: Bool = true, completionHandler: @escaping @Sendable (Result<(saveResults: [CKRecord.ID: Result<CKRecord, any Error>], deleteResults: [CKRecord.ID: Result<Void, any Error>]), any Error>) -> Void) {
        let operation = CKModifyRecordsOperation(recordsToSave: recordsToSave, recordIDsToDelete: recordIDsToDelete)
        operation.savePolicy = savePolicy
        operation.isAtomic = atomically
        let saves = ResultsBox([CKRecord.ID: Result<CKRecord, any Error>]())
        let deletes = ResultsBox([CKRecord.ID: Result<Void, any Error>]())
        operation.perRecordSaveBlock = { id, outcome in saves.update { $0[id] = outcome } }
        operation.perRecordDeleteBlock = { id, outcome in deletes.update { $0[id] = outcome } }
        operation.modifyRecordsResultBlock = { outcome in
            completionHandler(outcome.map { (saveResults: saves.value, deleteResults: deletes.value) })
        }
        run(operation)
    }

    public func modifyRecords(saving recordsToSave: [CKRecord], deleting recordIDsToDelete: [CKRecord.ID], savePolicy: CKModifyRecordsOperation.RecordSavePolicy = .ifServerRecordUnchanged, atomically: Bool = true) async throws -> (saveResults: [CKRecord.ID: Result<CKRecord, any Error>], deleteResults: [CKRecord.ID: Result<Void, any Error>]) {
        try await awaitResult { done in
            modifyRecords(saving: recordsToSave, deleting: recordIDsToDelete, savePolicy: savePolicy, atomically: atomically) { outcome in
                done(outcome.map { $0 })
            }
        }
    }

    /// Runs a query operation and answers its matches and cursor.
    private func runQuery(_ operation: CKQueryOperation, desiredKeys: [CKRecord.FieldKey]?, resultsLimit: Int, completionHandler: @escaping @Sendable (Result<(matchResults: [(CKRecord.ID, Result<CKRecord, any Error>)], queryCursor: CKQueryOperation.Cursor?), any Error>) -> Void) {
        operation.desiredKeys = desiredKeys
        operation.resultsLimit = resultsLimit
        let matches = ResultsBox([(CKRecord.ID, Result<CKRecord, any Error>)]())
        operation.recordMatchedBlock = { id, outcome in matches.update { $0.append((id, outcome)) } }
        operation.queryResultBlock = { outcome in
            completionHandler(outcome.map { (matchResults: matches.value, queryCursor: $0) })
        }
        run(operation)
    }

    @preconcurrency
    public func fetch(withQuery query: CKQuery, inZoneWith zoneID: CKRecordZone.ID? = nil, desiredKeys: [CKRecord.FieldKey]? = nil, resultsLimit: Int = CKQueryOperation.maximumResults, completionHandler: @escaping @Sendable (Result<(matchResults: [(CKRecord.ID, Result<CKRecord, any Error>)], queryCursor: CKQueryOperation.Cursor?), any Error>) -> Void) {
        let operation = CKQueryOperation(query: query)
        operation.zoneID = zoneID
        runQuery(operation, desiredKeys: desiredKeys, resultsLimit: resultsLimit, completionHandler: completionHandler)
    }

    @preconcurrency
    public func fetch(withCursor queryCursor: CKQueryOperation.Cursor, desiredKeys: [CKRecord.FieldKey]? = nil, resultsLimit: Int = CKQueryOperation.maximumResults, completionHandler: @escaping @Sendable (Result<(matchResults: [(CKRecord.ID, Result<CKRecord, any Error>)], queryCursor: CKQueryOperation.Cursor?), any Error>) -> Void) {
        runQuery(CKQueryOperation(cursor: queryCursor), desiredKeys: desiredKeys, resultsLimit: resultsLimit, completionHandler: completionHandler)
    }

    public func records(matching query: CKQuery, inZoneWith zoneID: CKRecordZone.ID? = nil, desiredKeys: [CKRecord.FieldKey]? = nil, resultsLimit: Int = CKQueryOperation.maximumResults) async throws -> (matchResults: [(CKRecord.ID, Result<CKRecord, any Error>)], queryCursor: CKQueryOperation.Cursor?) {
        try await awaitResult { done in
            fetch(withQuery: query, inZoneWith: zoneID, desiredKeys: desiredKeys, resultsLimit: resultsLimit) { done($0.map { $0 }) }
        }
    }

    public func records(continuingMatchFrom queryCursor: CKQueryOperation.Cursor, desiredKeys: [CKRecord.FieldKey]? = nil, resultsLimit: Int = CKQueryOperation.maximumResults) async throws -> (matchResults: [(CKRecord.ID, Result<CKRecord, any Error>)], queryCursor: CKQueryOperation.Cursor?) {
        try await awaitResult { done in
            fetch(withCursor: queryCursor, desiredKeys: desiredKeys, resultsLimit: resultsLimit) { done($0.map { $0 }) }
        }
    }

    @usableFromInline
    internal func _allRecordZones() async throws -> [CKRecordZone] {
        try await awaitResult { done in fetchAllRecordZones { done(result($0, $1)) } }
    }

    @usableFromInline
    internal func _recordZone(for zoneID: CKRecordZone.ID) async throws -> CKRecordZone {
        try await awaitResult { done in fetch(withRecordZoneID: zoneID) { done(result($0, $1)) } }
    }

    @preconcurrency
    public func fetch(withRecordZoneIDs zoneIDs: [CKRecordZone.ID], completionHandler: @escaping @Sendable (Result<[CKRecordZone.ID: Result<CKRecordZone, any Error>], any Error>) -> Void) {
        let operation = CKFetchRecordZonesOperation(recordZoneIDs: zoneIDs)
        let results = ResultsBox([CKRecordZone.ID: Result<CKRecordZone, any Error>]())
        operation.perRecordZoneResultBlock = { id, outcome in results.update { $0[id] = outcome } }
        operation.fetchRecordZonesResultBlock = { outcome in completionHandler(outcome.map { results.value }) }
        run(operation)
    }

    public func recordZones(for ids: [CKRecordZone.ID]) async throws -> [CKRecordZone.ID: Result<CKRecordZone, any Error>] {
        try await awaitResult { done in fetch(withRecordZoneIDs: ids, completionHandler: done) }
    }

    @usableFromInline
    internal func _save(_ zone: CKRecordZone) async throws -> CKRecordZone {
        try await awaitResult { done in save(zone) { done(result($0, $1)) } }
    }

    @usableFromInline
    internal func _deleteRecordZone(withID zoneID: CKRecordZone.ID) async throws -> CKRecordZone.ID {
        try await awaitResult { done in delete(withRecordZoneID: zoneID) { done(result($0, $1)) } }
    }

    @preconcurrency
    public func modifyRecordZones(saving recordZonesToSave: [CKRecordZone], deleting recordZoneIDsToDelete: [CKRecordZone.ID], completionHandler: @escaping @Sendable (Result<(saveResults: [CKRecordZone.ID: Result<CKRecordZone, any Error>], deleteResults: [CKRecordZone.ID: Result<Void, any Error>]), any Error>) -> Void) {
        let operation = CKModifyRecordZonesOperation(recordZonesToSave: recordZonesToSave, recordZoneIDsToDelete: recordZoneIDsToDelete)
        let saves = ResultsBox([CKRecordZone.ID: Result<CKRecordZone, any Error>]())
        let deletes = ResultsBox([CKRecordZone.ID: Result<Void, any Error>]())
        operation.perRecordZoneSaveBlock = { id, outcome in saves.update { $0[id] = outcome } }
        operation.perRecordZoneDeleteBlock = { id, outcome in deletes.update { $0[id] = outcome } }
        operation.modifyRecordZonesResultBlock = { outcome in
            completionHandler(outcome.map { (saveResults: saves.value, deleteResults: deletes.value) })
        }
        run(operation)
    }

    public func modifyRecordZones(saving recordZonesToSave: [CKRecordZone], deleting recordZoneIDsToDelete: [CKRecordZone.ID]) async throws -> (saveResults: [CKRecordZone.ID: Result<CKRecordZone, any Error>], deleteResults: [CKRecordZone.ID: Result<Void, any Error>]) {
        try await awaitResult { done in
            modifyRecordZones(saving: recordZonesToSave, deleting: recordZoneIDsToDelete) { done($0.map { $0 }) }
        }
    }

    @preconcurrency
    public func fetch(withSubscriptionIDs subscriptionIDs: [CKSubscription.ID], completionHandler: @escaping @Sendable (Result<[CKSubscription.ID: Result<CKSubscription, any Error>], any Error>) -> Void) {
        let operation = CKFetchSubscriptionsOperation(subscriptionIDs: subscriptionIDs)
        let results = ResultsBox([CKSubscription.ID: Result<CKSubscription, any Error>]())
        operation.perSubscriptionResultBlock = { id, outcome in results.update { $0[id] = outcome } }
        operation.fetchSubscriptionsResultBlock = { outcome in completionHandler(outcome.map { results.value }) }
        run(operation)
    }

    public func subscriptions(for ids: [CKSubscription.ID]) async throws -> [CKSubscription.ID: Result<CKSubscription, any Error>] {
        try await awaitResult { done in fetch(withSubscriptionIDs: ids, completionHandler: done) }
    }

    @preconcurrency
    public func modifySubscriptions(saving subscriptionsToSave: [CKSubscription], deleting subscriptionIDsToDelete: [CKSubscription.ID], completionHandler: @escaping @Sendable (Result<(saveResults: [CKSubscription.ID: Result<CKSubscription, any Error>], deleteResults: [CKSubscription.ID: Result<Void, any Error>]), any Error>) -> Void) {
        let operation = CKModifySubscriptionsOperation(subscriptionsToSave: subscriptionsToSave, subscriptionIDsToDelete: subscriptionIDsToDelete)
        let saves = ResultsBox([CKSubscription.ID: Result<CKSubscription, any Error>]())
        let deletes = ResultsBox([CKSubscription.ID: Result<Void, any Error>]())
        operation.perSubscriptionSaveBlock = { id, outcome in saves.update { $0[id] = outcome } }
        operation.perSubscriptionDeleteBlock = { id, outcome in deletes.update { $0[id] = outcome } }
        operation.modifySubscriptionsResultBlock = { outcome in
            completionHandler(outcome.map { (saveResults: saves.value, deleteResults: deletes.value) })
        }
        run(operation)
    }

    public func modifySubscriptions(saving subscriptionsToSave: [CKSubscription], deleting subscriptionIDsToDelete: [CKSubscription.ID]) async throws -> (saveResults: [CKSubscription.ID: Result<CKSubscription, any Error>], deleteResults: [CKSubscription.ID: Result<Void, any Error>]) {
        try await awaitResult { done in
            modifySubscriptions(saving: subscriptionsToSave, deleting: subscriptionIDsToDelete) { done($0.map { $0 }) }
        }
    }

    // MARK: Database changes

    public enum DatabaseChange {
        public struct Modification: Sendable {
            public var zoneID: CKRecordZone.ID { storedZoneID }
            let storedZoneID: CKRecordZone.ID
        }

        public struct Deletion: Sendable {
            public var zoneID: CKRecordZone.ID { storedZoneID }
            public var reason: Reason { storedReason }
            let storedZoneID: CKRecordZone.ID
            let storedReason: Reason

            public enum Reason: Sendable, Equatable {
                case deleted
                case purged
                case encryptedDataReset
            }

            public var purged: Bool { storedReason == .purged }
        }
    }

    @preconcurrency
    public func fetchDatabaseChanges(since changeToken: CKServerChangeToken?, resultsLimit: Int? = nil, completionHandler: @escaping @Sendable (Result<(modifications: [DatabaseChange.Modification], deletions: [DatabaseChange.Deletion], changeToken: CKServerChangeToken, moreComing: Bool), any Error>) -> Void) {
        let operation = CKFetchDatabaseChangesOperation(previousServerChangeToken: changeToken)
        if let resultsLimit { operation.resultsLimit = resultsLimit }
        let modifications = ResultsBox([DatabaseChange.Modification]())
        let deletions = ResultsBox([DatabaseChange.Deletion]())
        operation.recordZoneWithIDChangedBlock = { id in modifications.update { $0.append(.init(storedZoneID: id)) } }
        operation.recordZoneWithIDWasDeletedBlock = { id in deletions.update { $0.append(.init(storedZoneID: id, storedReason: .deleted)) } }
        operation.recordZoneWithIDWasPurgedBlock = { id in deletions.update { $0.append(.init(storedZoneID: id, storedReason: .purged)) } }
        if #available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *) {
            operation.recordZoneWithIDWasDeletedDueToUserEncryptedDataResetBlock = { id in
                deletions.update { $0.append(.init(storedZoneID: id, storedReason: .encryptedDataReset)) }
            }
        }
        operation.fetchDatabaseChangesResultBlock = { outcome in
            completionHandler(outcome.map { (modifications: modifications.value, deletions: deletions.value, changeToken: $0.serverChangeToken, moreComing: $0.moreComing) })
        }
        run(operation)
    }

    public func databaseChanges(since changeToken: CKServerChangeToken?, resultsLimit: Int? = nil) async throws -> (modifications: [DatabaseChange.Modification], deletions: [DatabaseChange.Deletion], changeToken: CKServerChangeToken, moreComing: Bool) {
        try await awaitResult { done in fetchDatabaseChanges(since: changeToken, resultsLimit: resultsLimit) { done($0.map { $0 }) } }
    }

    public enum RecordZoneChange {
        public struct Modification: Sendable {
            public var record: CKRecord { storedRecord }
            let storedRecord: CKRecord
        }

        public struct Deletion: Sendable {
            public var recordID: CKRecord.ID { storedRecordID }
            public var recordType: CKRecord.RecordType { storedRecordType }
            let storedRecordID: CKRecord.ID
            let storedRecordType: CKRecord.RecordType
        }
    }

    @preconcurrency
    public func fetchRecordZoneChanges(inZoneWith zoneID: CKRecordZone.ID, since changeToken: CKServerChangeToken?, desiredKeys: [CKRecord.FieldKey]? = nil, resultsLimit: Int? = nil, completionHandler: @escaping @Sendable (Result<(modificationResultsByID: [CKRecord.ID: Result<RecordZoneChange.Modification, any Error>], deletions: [RecordZoneChange.Deletion], changeToken: CKServerChangeToken, moreComing: Bool), any Error>) -> Void) {
        let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration(previousServerChangeToken: changeToken, resultsLimit: resultsLimit, desiredKeys: desiredKeys)
        let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: [zoneID], configurationsByRecordZoneID: [zoneID: configuration])
        let modifications = ResultsBox([CKRecord.ID: Result<RecordZoneChange.Modification, any Error>]())
        let deletions = ResultsBox([RecordZoneChange.Deletion]())
        let zoneResult = ResultsBox(Result<(serverChangeToken: CKServerChangeToken, clientChangeTokenData: Data?, moreComing: Bool), any Error>?.none)
        operation.recordWasChangedBlock = { id, outcome in
            modifications.update { $0[id] = outcome.map { RecordZoneChange.Modification(storedRecord: $0) } }
        }
        operation.recordWithIDWasDeletedBlock = { id, type in
            deletions.update { $0.append(.init(storedRecordID: id, storedRecordType: type)) }
        }
        operation.recordZoneFetchResultBlock = { _, outcome in zoneResult.update { $0 = outcome } }
        operation.fetchRecordZoneChangesResultBlock = { outcome in
            switch outcome {
            case .failure(let error):
                completionHandler(.failure(error))
            case .success:
                switch zoneResult.value {
                case .success(let zone)?:
                    completionHandler(.success((modificationResultsByID: modifications.value, deletions: deletions.value, changeToken: zone.serverChangeToken, moreComing: zone.moreComing)))
                case .failure(let error)?:
                    completionHandler(.failure(error))
                case nil:
                    completionHandler(.failure(CKError(.internalError)))
                }
            }
        }
        run(operation)
    }

    public func recordZoneChanges(inZoneWith zoneID: CKRecordZone.ID, since changeToken: CKServerChangeToken?, desiredKeys: [CKRecord.FieldKey]? = nil, resultsLimit: Int? = nil) async throws -> (modificationResultsByID: [CKRecord.ID: Result<RecordZoneChange.Modification, any Error>], deletions: [RecordZoneChange.Deletion], changeToken: CKServerChangeToken, moreComing: Bool) {
        try await awaitResult { done in
            fetchRecordZoneChanges(inZoneWith: zoneID, since: changeToken, desiredKeys: desiredKeys, resultsLimit: resultsLimit) { done($0.map { $0 }) }
        }
    }
}

@available(macOS 12.0, macCatalyst 15.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension CKDatabase.DatabaseChange: Sendable {}

@available(macOS 12.0, macCatalyst 15.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension CKDatabase.RecordZoneChange: Sendable {}

@available(macOS 12.0, macCatalyst 15.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension CKDatabase.DatabaseChange.Modification: Equatable, Hashable {
    public static func == (a: CKDatabase.DatabaseChange.Modification, b: CKDatabase.DatabaseChange.Modification) -> Bool {
        a.storedZoneID == b.storedZoneID
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(storedZoneID)
    }
}

@available(macOS 12.0, macCatalyst 15.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension CKDatabase.DatabaseChange.Deletion: Equatable, Hashable {
    public static func == (a: CKDatabase.DatabaseChange.Deletion, b: CKDatabase.DatabaseChange.Deletion) -> Bool {
        a.storedZoneID == b.storedZoneID && a.storedReason == b.storedReason
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(storedZoneID)
        hasher.combine(storedReason)
    }
}

@available(macOS 12.0, macCatalyst 15.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension CKDatabase.RecordZoneChange.Modification: Equatable, Hashable {
    public static func == (a: CKDatabase.RecordZoneChange.Modification, b: CKDatabase.RecordZoneChange.Modification) -> Bool {
        a.storedRecord == b.storedRecord
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(storedRecord)
    }
}

@available(macOS 12.0, macCatalyst 15.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension CKDatabase.RecordZoneChange.Deletion: Equatable, Hashable {
    public static func == (a: CKDatabase.RecordZoneChange.Deletion, b: CKDatabase.RecordZoneChange.Deletion) -> Bool {
        a.storedRecordID == b.storedRecordID && a.storedRecordType == b.storedRecordType
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(storedRecordID)
        hasher.combine(storedRecordType)
    }
}

@available(macOS 12.0, macCatalyst 15.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension CKDatabase.DatabaseChange.Deletion.Reason: Hashable {}

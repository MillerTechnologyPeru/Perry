// CKSyncEngine: Swift's sync engine over CloudKit's Objective-C one (the
// headers keep its classes for Swift as __CKSyncEngine and so on), its
// events, state and options as Swift values, and a delegate whose async
// methods the Objective-C delegate's synchronous ones wait for.

import Foundation

@_hasMissingDesignatedInitializers
@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
final public class CKSyncEngine: Sendable {
    nonisolated(unsafe) let engine: __CKSyncEngine
    private let bridge: SyncEngineDelegateBridge

    public init(_ configuration: Configuration) {
        let bridge = SyncEngineDelegateBridge(delegate: configuration.delegate)
        let objcConfiguration = __CKSyncEngineConfiguration(database: configuration.database,
                                                           stateSerialization: configuration.stateSerialization?.serialization,
                                                           delegate: bridge)
        objcConfiguration.automaticallySync = configuration.automaticallySync
        objcConfiguration.subscriptionID = configuration.subscriptionID
        self.bridge = bridge
        engine = __CKSyncEngine(objcConfiguration)
        bridge.engine = self
    }

    final public var database: CKDatabase { engine.database }

    final public var state: State { State(engine.state) }

    deinit {}
}

/// The Objective-C delegate of a Swift sync engine: each call waits for
/// the Swift delegate's async method (CloudKit calls it on a queue of its
/// own).
@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
private final class SyncEngineDelegateBridge: NSObject, __CKSyncEngineDelegate, @unchecked Sendable {
    weak var delegate: (any CKSyncEngineDelegate)?
    weak var engine: CKSyncEngine?

    init(delegate: any CKSyncEngineDelegate) {
        self.delegate = delegate
    }

    /// Runs an async body and waits for its answer.
    private func wait<T>(_ fallback: T, _ body: @escaping @Sendable (any CKSyncEngineDelegate, CKSyncEngine) async -> T) -> T {
        guard let delegate, let engine else { return fallback }
        let box = ResultsBox(fallback)
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) let unsafeBody = body
        Task {
            let value = await unsafeBody(delegate, engine)
            box.update { $0 = value }
            done.signal()
        }
        done.wait()
        return box.value
    }

    func syncEngine(_ syncEngine: __CKSyncEngine, handleEvent event: __CKSyncEngineEvent) {
        guard let swiftEvent = CKSyncEngine.Event(event) else { return }
        _ = wait(()) { delegate, engine in await delegate.handleEvent(swiftEvent, syncEngine: engine) }
    }

    func syncEngine(_ syncEngine: __CKSyncEngine, nextRecordZoneChangeBatch context: __CKSyncEngineSendChangesContext) -> __CKSyncEngineRecordZoneChangeBatch? {
        let swiftContext = CKSyncEngine.SendChangesContext(context)
        let batch = wait(nil as CKSyncEngine.RecordZoneChangeBatch?) { delegate, engine in
            await delegate.nextRecordZoneChangeBatch(swiftContext, syncEngine: engine)
        }
        return batch.map { batch in
            let objc = __CKSyncEngineRecordZoneChangeBatch(recordsToSave: batch.recordsToSave, recordIDsToDelete: batch.recordIDsToDelete, atomicByZone: batch.atomicByZone)
            return objc
        }
    }

    func syncEngine(_ syncEngine: __CKSyncEngine, fetchChangesOptions context: __CKSyncEngineFetchChangesContext) -> __CKSyncEngineFetchChangesOptions {
        let swiftContext = CKSyncEngine.FetchChangesContext(context)
        return wait(swiftContext.options) { delegate, engine in
            await delegate.nextFetchChangesOptions(swiftContext, syncEngine: engine)
        }.objc
    }
}

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine {
    final public func fetchChanges(_ options: FetchChangesOptions = .init()) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            engine.fetchChanges(options.objc) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    final public func sendChanges(_ options: SendChangesOptions = .init()) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            engine.sendChanges(options.objc) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    final public func cancelOperations() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            engine.cancelOperations { continuation.resume() }
        }
    }
}

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine: CustomStringConvertible {
    final public var description: String {
        "<CKSyncEngine database=\(database.databaseScope.rawValue) state=\(state.description)>"
    }
}

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine {
    public struct Configuration: Sendable {
        public var database: CKDatabase
        public var stateSerialization: State.Serialization?
        public var delegate: any CKSyncEngineDelegate
        public var automaticallySync: Bool
        public var subscriptionID: CKSubscription.ID?

        public init(database: CKDatabase, stateSerialization: State.Serialization?, delegate: any CKSyncEngineDelegate) {
            self.database = database
            self.stateSerialization = stateSerialization
            self.delegate = delegate
            automaticallySync = true
            subscriptionID = nil
        }
    }
}

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine.Configuration: CustomStringConvertible {
    public var description: String {
        "<Configuration database=\(database.databaseScope.rawValue) automaticallySync=\(automaticallySync) subscriptionID=\(subscriptionID ?? "nil")>"
    }
}

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
public protocol CKSyncEngineDelegate: AnyObject, Sendable {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async
    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch?
    func nextFetchChangesOptions(_ context: CKSyncEngine.FetchChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.FetchChangesOptions
}

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngineDelegate {
    public func nextFetchChangesOptions(_ context: CKSyncEngine.FetchChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.FetchChangesOptions {
        context.options
    }
}

// MARK: - Events

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine {
    public enum Event: Sendable {
        case stateUpdate(StateUpdate)
        case accountChange(AccountChange)
        case fetchedDatabaseChanges(FetchedDatabaseChanges)
        case fetchedRecordZoneChanges(FetchedRecordZoneChanges)
        case sentDatabaseChanges(SentDatabaseChanges)
        case sentRecordZoneChanges(SentRecordZoneChanges)
        case willFetchChanges(WillFetchChanges)
        case willFetchRecordZoneChanges(WillFetchRecordZoneChanges)
        case didFetchRecordZoneChanges(DidFetchRecordZoneChanges)
        case didFetchChanges(DidFetchChanges)
        case willSendChanges(WillSendChanges)
        case didSendChanges(DidSendChanges)
    }
}

/// The CKError of an NSError.
private func ckError(_ error: any Error) -> CKError {
    error as? CKError ?? CKError(_nsError: error as NSError)
}

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine.Event {
    public struct StateUpdate: Sendable {
        public let stateSerialization: CKSyncEngine.State.Serialization
    }

    public struct AccountChange: Sendable {
        public let changeType: ChangeType

        public enum ChangeType: Sendable {
            case signIn(currentUser: CKRecord.ID)
            case signOut(previousUser: CKRecord.ID)
            case switchAccounts(previousUser: CKRecord.ID, currentUser: CKRecord.ID)
        }
    }

    public struct FetchedDatabaseChanges: Sendable {
        public let modifications: [CKDatabase.DatabaseChange.Modification]
        public let deletions: [CKDatabase.DatabaseChange.Deletion]
    }

    public struct FetchedRecordZoneChanges: Sendable {
        public let modifications: [CKDatabase.RecordZoneChange.Modification]
        public let deletions: [CKDatabase.RecordZoneChange.Deletion]
    }

    public struct SentDatabaseChanges: Sendable {
        public let savedZones: [CKRecordZone]
        public let failedZoneSaves: [FailedZoneSave]
        public let deletedZoneIDs: [CKRecordZone.ID]
        public let failedZoneDeletes: [CKRecordZone.ID: CKError]

        public struct FailedZoneSave: Sendable {
            public let zone: CKRecordZone
            public let error: CKError
        }
    }

    public struct SentRecordZoneChanges: Sendable {
        public let savedRecords: [CKRecord]
        public let failedRecordSaves: [FailedRecordSave]
        public let deletedRecordIDs: [CKRecord.ID]
        public let failedRecordDeletes: [CKRecord.ID: CKError]

        public struct FailedRecordSave: Sendable {
            public let record: CKRecord
            public let error: CKError
        }
    }

    public struct WillFetchChanges: Sendable {
        public let context: CKSyncEngine.FetchChangesContext
    }

    public struct WillFetchRecordZoneChanges: Sendable {
        public let zoneID: CKRecordZone.ID
    }

    public struct DidFetchRecordZoneChanges: Sendable {
        public let zoneID: CKRecordZone.ID
        public let error: CKError?
    }

    public struct DidFetchChanges: Sendable {
        public let context: CKSyncEngine.FetchChangesContext
    }

    public struct WillSendChanges: Sendable {
        public let context: CKSyncEngine.SendChangesContext
    }

    public struct DidSendChanges: Sendable {
        public let context: CKSyncEngine.SendChangesContext
    }

    /// The event of an Objective-C one, nil for a kind not known.
    init?(_ event: __CKSyncEngineEvent) {
        switch event {
        case let event as __CKSyncEngineStateUpdateEvent:
            self = .stateUpdate(StateUpdate(stateSerialization: CKSyncEngine.State.Serialization(event.stateSerialization)))
        case let event as __CKSyncEngineAccountChangeEvent:
            switch (event.previousUser, event.currentUser) {
            case let (previous?, current?): self = .accountChange(AccountChange(changeType: .switchAccounts(previousUser: previous, currentUser: current)))
            case let (nil, current?): self = .accountChange(AccountChange(changeType: .signIn(currentUser: current)))
            case let (previous?, nil): self = .accountChange(AccountChange(changeType: .signOut(previousUser: previous)))
            default: return nil
            }
        case let event as __CKSyncEngineFetchedDatabaseChangesEvent:
            self = .fetchedDatabaseChanges(FetchedDatabaseChanges(
                modifications: event.modifications.map { .init(storedZoneID: $0.zoneID) },
                deletions: event.deletions.map { deletion in
                    let reason: CKDatabase.DatabaseChange.Deletion.Reason
                    switch deletion.reason.rawValue {
                    case 1: reason = .purged
                    case 2: reason = .encryptedDataReset
                    default: reason = .deleted
                    }
                    return .init(storedZoneID: deletion.zoneID, storedReason: reason)
                }))
        case let event as __CKSyncEngineFetchedRecordZoneChangesEvent:
            self = .fetchedRecordZoneChanges(FetchedRecordZoneChanges(
                modifications: event.modifications.map { .init(storedRecord: $0) },
                deletions: event.deletions.map { .init(storedRecordID: $0.recordID, storedRecordType: $0.recordType) }))
        case let event as __CKSyncEngineSentDatabaseChangesEvent:
            self = .sentDatabaseChanges(SentDatabaseChanges(
                savedZones: event.savedZones,
                failedZoneSaves: event.failedZoneSaves.map { .init(zone: $0.recordZone, error: ckError($0.error)) },
                deletedZoneIDs: event.deletedZoneIDs,
                failedZoneDeletes: event.failedZoneDeletes.mapValues(ckError)))
        case let event as __CKSyncEngineSentRecordZoneChangesEvent:
            self = .sentRecordZoneChanges(SentRecordZoneChanges(
                savedRecords: event.savedRecords,
                failedRecordSaves: event.failedRecordSaves.map { .init(record: $0.record, error: ckError($0.error)) },
                deletedRecordIDs: event.deletedRecordIDs,
                failedRecordDeletes: event.failedRecordDeletes.mapValues(ckError)))
        case let event as __CKSyncEngineWillFetchChangesEvent:
            self = .willFetchChanges(WillFetchChanges(context: CKSyncEngine.FetchChangesContext(event.context)))
        case let event as __CKSyncEngineWillFetchRecordZoneChangesEvent:
            self = .willFetchRecordZoneChanges(WillFetchRecordZoneChanges(zoneID: event.zoneID))
        case let event as __CKSyncEngineDidFetchRecordZoneChangesEvent:
            self = .didFetchRecordZoneChanges(DidFetchRecordZoneChanges(zoneID: event.zoneID, error: event.error.map(ckError)))
        case let event as __CKSyncEngineDidFetchChangesEvent:
            self = .didFetchChanges(DidFetchChanges(context: CKSyncEngine.FetchChangesContext(event.context)))
        case let event as __CKSyncEngineWillSendChangesEvent:
            self = .willSendChanges(WillSendChanges(context: CKSyncEngine.SendChangesContext(event.context)))
        case let event as __CKSyncEngineDidSendChangesEvent:
            self = .didSendChanges(DidSendChanges(context: CKSyncEngine.SendChangesContext(event.context)))
        default:
            return nil
        }
    }
}

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine.Event: CustomStringConvertible {
    public var description: String {
        switch self {
        case .stateUpdate(let event): return event.description
        case .accountChange(let event): return event.description
        case .fetchedDatabaseChanges(let event): return event.description
        case .fetchedRecordZoneChanges(let event): return event.description
        case .sentDatabaseChanges(let event): return event.description
        case .sentRecordZoneChanges(let event): return event.description
        case .willFetchChanges(let event): return event.description
        case .willFetchRecordZoneChanges(let event): return event.description
        case .didFetchRecordZoneChanges(let event): return event.description
        case .didFetchChanges(let event): return event.description
        case .willSendChanges(let event): return event.description
        case .didSendChanges(let event): return event.description
        }
    }
}

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine.Event.StateUpdate: CustomStringConvertible {
    public var description: String { "StateUpdate" }
}

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine.Event.AccountChange: CustomStringConvertible {
    public var description: String {
        switch changeType {
        case .signIn(let user): return "AccountChange(signIn: \(user.recordName))"
        case .signOut(let user): return "AccountChange(signOut: \(user.recordName))"
        case .switchAccounts(let previous, let current): return "AccountChange(switchAccounts: \(previous.recordName) -> \(current.recordName))"
        }
    }
}

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine.Event.AccountChange.ChangeType: Equatable {
    public static func == (a: Self, b: Self) -> Bool {
        switch (a, b) {
        case let (.signIn(x), .signIn(y)), let (.signOut(x), .signOut(y)): return x == y
        case let (.switchAccounts(p1, c1), .switchAccounts(p2, c2)): return p1 == p2 && c1 == c2
        default: return false
        }
    }
}

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine.Event.FetchedDatabaseChanges: CustomStringConvertible {
    public var description: String { "FetchedDatabaseChanges(modifications: \(modifications.count), deletions: \(deletions.count))" }
}

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine.Event.FetchedRecordZoneChanges: CustomStringConvertible {
    public var description: String { "FetchedRecordZoneChanges(modifications: \(modifications.count), deletions: \(deletions.count))" }
}

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine.Event.SentDatabaseChanges: CustomStringConvertible {
    public var description: String { "SentDatabaseChanges(saved: \(savedZones.count), failedSaves: \(failedZoneSaves.count), deleted: \(deletedZoneIDs.count), failedDeletes: \(failedZoneDeletes.count))" }
}

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine.Event.SentDatabaseChanges.FailedZoneSave: CustomStringConvertible {
    public var description: String { "FailedZoneSave(\(zone.zoneID.zoneName): \(error.code.rawValue))" }
}

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine.Event.SentRecordZoneChanges: CustomStringConvertible {
    public var description: String { "SentRecordZoneChanges(saved: \(savedRecords.count), failedSaves: \(failedRecordSaves.count), deleted: \(deletedRecordIDs.count), failedDeletes: \(failedRecordDeletes.count))" }
}

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave: CustomStringConvertible {
    public var description: String { "FailedRecordSave(\(record.recordID.recordName): \(error.code.rawValue))" }
}

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine.Event.WillFetchChanges: CustomStringConvertible {
    public var description: String { "WillFetchChanges(\(context))" }
}

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine.Event.WillFetchRecordZoneChanges: CustomStringConvertible {
    public var description: String { "WillFetchRecordZoneChanges(\(zoneID.zoneName))" }
}

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine.Event.DidFetchRecordZoneChanges: CustomStringConvertible {
    public var description: String { "DidFetchRecordZoneChanges(\(zoneID.zoneName)\(error.map { ", error: \($0.code.rawValue)" } ?? ""))" }
}

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine.Event.DidFetchChanges: CustomStringConvertible {
    public var description: String { "DidFetchChanges(\(context))" }
}

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine.Event.WillSendChanges: CustomStringConvertible {
    public var description: String { "WillSendChanges(\(context))" }
}

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine.Event.DidSendChanges: CustomStringConvertible {
    public var description: String { "DidSendChanges(\(context))" }
}

// MARK: - Batches

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine {
    public struct RecordZoneChangeBatch: Sendable {
        public var recordsToSave: [CKRecord]
        public var recordIDsToDelete: [CKRecord.ID]
        public var atomicByZone: Bool

        /// A batch of the pending changes, the records to save from the
        /// provider (changes it has no record for are left out); nil if
        /// nothing is left to send.
        public init?(pendingChanges: [PendingRecordZoneChange], recordProvider: @Sendable (CKRecord.ID) async -> CKRecord?) async {
            var saves: [CKRecord] = []
            var deletes: [CKRecord.ID] = []
            for change in pendingChanges {
                switch change {
                case .saveRecord(let id):
                    if let record = await recordProvider(id) { saves.append(record) }
                case .deleteRecord(let id):
                    deletes.append(id)
                }
            }
            guard !saves.isEmpty || !deletes.isEmpty else { return nil }
            self.init(recordsToSave: saves, recordIDsToDelete: deletes)
        }

        public init(recordsToSave: [CKRecord] = [], recordIDsToDelete: [CKRecord.ID] = [], atomicByZone: Bool = false) {
            self.recordsToSave = recordsToSave
            self.recordIDsToDelete = recordIDsToDelete
            self.atomicByZone = atomicByZone
        }
    }
}

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine.RecordZoneChangeBatch: CustomStringConvertible {
    public var description: String {
        "RecordZoneChangeBatch(save: \(recordsToSave.count), delete: \(recordIDsToDelete.count), atomicByZone: \(atomicByZone))"
    }
}

// MARK: - State

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine {
    @_hasMissingDesignatedInitializers
    final public class State: Sendable {
        nonisolated(unsafe) let state: __CKSyncEngineState

        init(_ state: __CKSyncEngineState) {
            self.state = state
        }

        final public var pendingRecordZoneChanges: [PendingRecordZoneChange] {
            state.pendingRecordZoneChanges.map(PendingRecordZoneChange.init)
        }

        final public var pendingDatabaseChanges: [PendingDatabaseChange] {
            state.pendingDatabaseChanges.compactMap(PendingDatabaseChange.init)
        }

        final public var hasPendingUntrackedChanges: Bool {
            get { state.hasPendingUntrackedChanges }
            set { state.hasPendingUntrackedChanges = newValue }
        }

        final public var zoneIDsWithUnfetchedServerChanges: [CKRecordZone.ID] {
            state.zoneIDsWithUnfetchedServerChanges
        }

        final public func add(pendingRecordZoneChanges: [PendingRecordZoneChange]) {
            state.add(pendingRecordZoneChanges: pendingRecordZoneChanges.map(\.objc))
        }

        final public func remove(pendingRecordZoneChanges: [PendingRecordZoneChange]) {
            state.remove(pendingRecordZoneChanges: pendingRecordZoneChanges.map(\.objc))
        }

        final public func add(pendingDatabaseChanges: [PendingDatabaseChange]) {
            state.add(pendingDatabaseChanges: pendingDatabaseChanges.map(\.objc))
        }

        final public func remove(pendingDatabaseChanges: [PendingDatabaseChange]) {
            state.remove(pendingDatabaseChanges: pendingDatabaseChanges.map(\.objc))
        }

        /// The state, to keep and give a later engine: its archive.
        public struct Serialization: Codable, Sendable {
            nonisolated(unsafe) let serialization: __CKSyncEngineStateSerialization

            init(_ serialization: __CKSyncEngineStateSerialization) {
                self.serialization = serialization
            }

            public func encode(to encoder: any Encoder) throws {
                let data = try NSKeyedArchiver.archivedData(withRootObject: serialization, requiringSecureCoding: true)
                var container = encoder.singleValueContainer()
                try container.encode(data)
            }

            public init(from decoder: any Decoder) throws {
                let data = try decoder.singleValueContainer().decode(Data.self)
                guard let serialization = try NSKeyedUnarchiver.unarchivedObject(ofClass: __CKSyncEngineStateSerialization.self, from: data) else {
                    throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a sync engine state"))
                }
                self.serialization = serialization
            }
        }

        var description: String {
            "pendingRecordZoneChanges=\(state.pendingRecordZoneChanges.count) pendingDatabaseChanges=\(state.pendingDatabaseChanges.count)"
        }

        deinit {}
    }

    public enum PendingRecordZoneChange: Sendable {
        case saveRecord(CKRecord.ID)
        case deleteRecord(CKRecord.ID)
    }

    public enum PendingDatabaseChange: Sendable {
        case saveZone(CKRecordZone)
        case deleteZone(CKRecordZone.ID)
    }
}

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine.PendingRecordZoneChange {
    init(_ change: __CKSyncEnginePendingRecordZoneChange) {
        self = change.type == .deleteRecord ? .deleteRecord(change.recordID) : .saveRecord(change.recordID)
    }

    var objc: __CKSyncEnginePendingRecordZoneChange {
        switch self {
        case .saveRecord(let id): return __CKSyncEnginePendingRecordZoneChange(id, type: .saveRecord)
        case .deleteRecord(let id): return __CKSyncEnginePendingRecordZoneChange(id, type: .deleteRecord)
        }
    }

    var recordID: CKRecord.ID {
        switch self {
        case .saveRecord(let id), .deleteRecord(let id): return id
        }
    }
}

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine.PendingDatabaseChange {
    init?(_ change: __CKSyncEnginePendingDatabaseChange) {
        switch change {
        case let save as __CKSyncEnginePendingZoneSave: self = .saveZone(save.zone())
        default: self = .deleteZone(change.zoneID)
        }
    }

    var objc: __CKSyncEnginePendingDatabaseChange {
        switch self {
        case .saveZone(let zone): return __CKSyncEnginePendingZoneSave(zone)
        case .deleteZone(let id): return __CKSyncEnginePendingZoneDelete(id)
        }
    }
}

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine.PendingRecordZoneChange: Hashable, CustomStringConvertible {
    public var description: String {
        switch self {
        case .saveRecord(let id): return "saveRecord(\(id.recordName))"
        case .deleteRecord(let id): return "deleteRecord(\(id.recordName))"
        }
    }

    public static func == (a: Self, b: Self) -> Bool {
        switch (a, b) {
        case let (.saveRecord(x), .saveRecord(y)), let (.deleteRecord(x), .deleteRecord(y)): return x == y
        default: return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .saveRecord(let id):
            hasher.combine(0)
            hasher.combine(id)
        case .deleteRecord(let id):
            hasher.combine(1)
            hasher.combine(id)
        }
    }
}

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine.PendingDatabaseChange: Hashable, CustomStringConvertible {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.saveZone(x), .saveZone(y)): return x.zoneID == y.zoneID
        case let (.deleteZone(x), .deleteZone(y)): return x == y
        default: return false
        }
    }

    public var description: String {
        switch self {
        case .saveZone(let zone): return "saveZone(\(zone.zoneID.zoneName))"
        case .deleteZone(let id): return "deleteZone(\(id.zoneName))"
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .saveZone(let zone):
            hasher.combine(0)
            hasher.combine(zone.zoneID)
        case .deleteZone(let id):
            hasher.combine(1)
            hasher.combine(id)
        }
    }
}

// MARK: - Options and contexts

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine {
    public struct FetchChangesOptions: Sendable {
        public var scope: Scope {
            get { storedScope }
            set { storedScope = newValue }
        }

        public var operationGroup: CKOperationGroup {
            get { storedGroup }
            set { storedGroup = newValue }
        }

        public var prioritizedZoneIDs: [CKRecordZone.ID]

        private var storedScope: Scope
        private var storedGroup: CKOperationGroup

        public enum Scope: Sendable {
            case all
            case allExcluding([CKRecordZone.ID])
            case zoneIDs([CKRecordZone.ID])

            public func contains(_ zoneID: CKRecordZone.ID) -> Bool {
                switch self {
                case .all: return true
                case .allExcluding(let excluded): return !excluded.contains(zoneID)
                case .zoneIDs(let included): return included.contains(zoneID)
                }
            }

            var objc: __CKSyncEngineFetchChangesScope {
                switch self {
                case .all: return __CKSyncEngineFetchChangesScope(zoneIDs: nil)
                case .allExcluding(let ids): return __CKSyncEngineFetchChangesScope(excludedZoneIDs: Set(ids))
                case .zoneIDs(let ids): return __CKSyncEngineFetchChangesScope(zoneIDs: Set(ids))
                }
            }

            init(_ scope: __CKSyncEngineFetchChangesScope) {
                if let ids = scope.zoneIDs {
                    self = .zoneIDs(Array(ids))
                } else if !scope.excludedZoneIDs.isEmpty {
                    self = .allExcluding(Array(scope.excludedZoneIDs))
                } else {
                    self = .all
                }
            }
        }

        public init(scope: Scope = .all, operationGroup: CKOperationGroup? = nil) {
            storedScope = scope
            storedGroup = operationGroup ?? CKOperationGroup()
            prioritizedZoneIDs = []
        }

        init(_ options: __CKSyncEngineFetchChangesOptions) {
            storedScope = Scope(options.scope)
            storedGroup = options.operationGroup
            prioritizedZoneIDs = options.prioritizedZoneIDs
        }

        var objc: __CKSyncEngineFetchChangesOptions {
            let options = __CKSyncEngineFetchChangesOptions(scope: storedScope.objc)
            options.operationGroup = storedGroup
            options.prioritizedZoneIDs = prioritizedZoneIDs
            return options
        }
    }

    public struct FetchChangesContext: Sendable {
        public let reason: SyncReason
        public let options: FetchChangesOptions

        init(_ context: __CKSyncEngineFetchChangesContext) {
            reason = context.reason == .manual ? .manual : .scheduled
            options = FetchChangesOptions(context.options)
        }
    }

    public struct SendChangesOptions: Sendable {
        public var scope: Scope {
            get { storedScope }
            set { storedScope = newValue }
        }

        public var operationGroup: CKOperationGroup {
            get { storedGroup }
            set { storedGroup = newValue }
        }

        private var storedScope: Scope
        private var storedGroup: CKOperationGroup

        public enum Scope: Sendable {
            case all
            case allExcluding([CKRecordZone.ID])
            case zoneIDs([CKRecordZone.ID])
            case recordIDs([CKRecord.ID])

            public func contains(_ recordID: CKRecord.ID) -> Bool {
                switch self {
                case .all: return true
                case .allExcluding(let excluded): return !excluded.contains(recordID.zoneID)
                case .zoneIDs(let included): return included.contains(recordID.zoneID)
                case .recordIDs(let included): return included.contains(recordID)
                }
            }

            public func contains(_ pendingChange: PendingRecordZoneChange) -> Bool {
                contains(pendingChange.recordID)
            }

            var objc: __CKSyncEngineSendChangesScope {
                switch self {
                case .all: return __CKSyncEngineSendChangesScope(zoneIDs: nil)
                case .allExcluding(let ids): return __CKSyncEngineSendChangesScope(excludedZoneIDs: Set(ids))
                case .zoneIDs(let ids): return __CKSyncEngineSendChangesScope(zoneIDs: Set(ids))
                case .recordIDs(let ids): return __CKSyncEngineSendChangesScope(recordIDs: Set(ids))
                }
            }

            init(_ scope: __CKSyncEngineSendChangesScope) {
                if let ids = scope.recordIDs {
                    self = .recordIDs(Array(ids))
                } else if let ids = scope.zoneIDs {
                    self = .zoneIDs(Array(ids))
                } else if !scope.excludedZoneIDs.isEmpty {
                    self = .allExcluding(Array(scope.excludedZoneIDs))
                } else {
                    self = .all
                }
            }
        }

        public init(scope: Scope = .all, operationGroup: CKOperationGroup? = nil) {
            storedScope = scope
            storedGroup = operationGroup ?? CKOperationGroup()
        }

        init(_ options: __CKSyncEngineSendChangesOptions) {
            storedScope = Scope(options.scope)
            storedGroup = options.operationGroup
        }

        var objc: __CKSyncEngineSendChangesOptions {
            let options = __CKSyncEngineSendChangesOptions(scope: storedScope.objc)
            options.operationGroup = storedGroup
            return options
        }
    }

    public struct SendChangesContext: Sendable {
        public let reason: SyncReason
        public let options: SendChangesOptions

        init(_ context: __CKSyncEngineSendChangesContext) {
            reason = context.reason == .manual ? .manual : .scheduled
            options = SendChangesOptions(context.options)
        }
    }

    public enum SyncReason: Sendable {
        case scheduled
        case manual
    }
}

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine.FetchChangesOptions: CustomStringConvertible {
    public var description: String { "FetchChangesOptions(scope: \(scope), prioritizedZoneIDs: \(prioritizedZoneIDs.map(\.zoneName)))" }
}

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine.FetchChangesOptions.Scope: Equatable {
    public static func == (a: Self, b: Self) -> Bool {
        switch (a, b) {
        case (.all, .all): return true
        case let (.allExcluding(x), .allExcluding(y)), let (.zoneIDs(x), .zoneIDs(y)): return Set(x) == Set(y)
        default: return false
        }
    }
}

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine.SendChangesOptions: CustomStringConvertible {
    public var description: String { "SendChangesOptions(scope: \(scope))" }
}

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine.SendChangesOptions.Scope: Equatable {
    public static func == (a: Self, b: Self) -> Bool {
        switch (a, b) {
        case (.all, .all): return true
        case let (.allExcluding(x), .allExcluding(y)), let (.zoneIDs(x), .zoneIDs(y)): return Set(x) == Set(y)
        case let (.recordIDs(x), .recordIDs(y)): return Set(x) == Set(y)
        default: return false
        }
    }
}

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine.SendChangesContext: CustomStringConvertible {
    public var description: String { "SendChangesContext(reason: \(reason), options: \(options))" }
}

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine.FetchChangesContext: CustomStringConvertible {
    public var description: String { "FetchChangesContext(reason: \(reason), options: \(options))" }
}

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine.SyncReason: CustomStringConvertible {
    public var description: String {
        switch self {
        case .scheduled: return "scheduled"
        case .manual: return "manual"
        }
    }
}

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine.SendChangesOptions.Scope: CustomStringConvertible {
    public var description: String {
        switch self {
        case .all: return "all"
        case .allExcluding(let ids): return "allExcluding(\(ids.map(\.zoneName)))"
        case .zoneIDs(let ids): return "zoneIDs(\(ids.map(\.zoneName)))"
        case .recordIDs(let ids): return "recordIDs(\(ids.map(\.recordName)))"
        }
    }
}

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine.FetchChangesOptions.Scope: CustomStringConvertible {
    public var description: String {
        switch self {
        case .all: return "all"
        case .allExcluding(let ids): return "allExcluding(\(ids.map(\.zoneName)))"
        case .zoneIDs(let ids): return "zoneIDs(\(ids.map(\.zoneName)))"
        }
    }
}

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine.SyncReason: Equatable {}

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKSyncEngine.SyncReason: Hashable {}

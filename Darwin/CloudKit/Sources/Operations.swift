// CloudKit's operations with Swift types: desired keys and identifiers as
// arrays, and per-item and operation results as Result values over the
// Objective-C blocks of (value, error) pairs. A getter answers a closure
// that calls the block set, so a block set either way can be read either.

import Foundation

/// A Result of what an Objective-C block gave: the value, else the error
/// (an unknown one if neither was given).
func result<T>(_ value: T?, _ error: (any Error)?) -> Result<T, any Error> {
    if let error { return .failure(error) }
    if let value { return .success(value) }
    return .failure(CKError(.internalError))
}

/// A Result with no value: success without an error.
func result(_ error: (any Error)?) -> Result<Void, any Error> {
    error.map { .failure($0) } ?? .success(())
}

/// The value and error of a Result, for an Objective-C block.
func parts<T>(_ result: Result<T, any Error>) -> (T?, (any Error)?) {
    switch result {
    case .success(let value): return (value, nil)
    case .failure(let error): return (nil, error)
    }
}

extension CKQueryOperation {
    public var desiredKeys: [CKRecord.FieldKey]? {
        get { __desiredKeys }
        set { __desiredKeys = newValue }
    }

    public var recordMatchedBlock: ((_ recordID: CKRecord.ID, _ recordResult: Result<CKRecord, any Error>) -> Void)? {
        get { __recordMatchedBlock.map { block in { id, result in let (r, e) = parts(result); block(id, r, e) } } }
        set { __recordMatchedBlock = newValue.map { block in { id, record, error in block(id, result(record, error)) } } }
    }

    public var queryResultBlock: ((_ operationResult: Result<CKQueryOperation.Cursor?, any Error>) -> Void)? {
        get {
            queryCompletionBlock.map { block in { result in
                switch result {
                case .success(let cursor): block(cursor, nil)
                case .failure(let error): block(nil, error)
                }
            } }
        }
        set {
            queryCompletionBlock = newValue.map { block in { cursor, error in
                block(error.map { .failure($0) } ?? .success(cursor))
            } }
        }
    }
}

extension CKFetchRecordsOperation {
    public var desiredKeys: [CKRecord.FieldKey]? {
        get { __desiredKeys }
        set { __desiredKeys = newValue }
    }

    public var perRecordResultBlock: ((_ recordID: CKRecord.ID, _ recordResult: Result<CKRecord, any Error>) -> Void)? {
        get { perRecordCompletionBlock.map { block in { id, result in let (r, e) = parts(result); block(r, id, e) } } }
        set {
            perRecordCompletionBlock = newValue.map { block in { record, id, error in
                guard let id = id ?? record?.recordID else { return }
                block(id, result(record, error))
            } }
        }
    }

    public var fetchRecordsResultBlock: ((_ operationResult: Result<Void, any Error>) -> Void)? {
        get { fetchRecordsCompletionBlock.map { block in { result in block(nil, parts(result).1) } } }
        set { fetchRecordsCompletionBlock = newValue.map { block in { _, error in block(result(error)) } } }
    }
}

extension CKFetchRecordZoneChangesOperation {
    /// An operation fetching the changes of the zones given, with each
    /// zone's configuration.
    convenience public init(recordZoneIDs: [CKRecordZone.ID]? = nil, configurationsByRecordZoneID: [CKRecordZone.ID: CKFetchRecordZoneChangesOperation.ZoneConfiguration]? = nil) {
        self.init()
        self.recordZoneIDs = recordZoneIDs
        self.configurationsByRecordZoneID = configurationsByRecordZoneID
    }

    public var recordWithIDWasDeletedBlock: ((_ recordID: CKRecord.ID, _ recordType: CKRecord.RecordType) -> Void)? {
        get { __recordWithIDWasDeletedBlock }
        set { __recordWithIDWasDeletedBlock = newValue }
    }

    public var recordWasChangedBlock: ((_ recordID: CKRecord.ID, _ recordResult: Result<CKRecord, any Error>) -> Void)? {
        get { __recordWasChangedBlock.map { block in { id, result in let (r, e) = parts(result); block(id, r, e) } } }
        set { __recordWasChangedBlock = newValue.map { block in { id, record, error in block(id, result(record, error)) } } }
    }

    public var recordZoneFetchResultBlock: ((_ recordZoneID: CKRecordZone.ID, _ fetchChangesResult: Result<(serverChangeToken: CKServerChangeToken, clientChangeTokenData: Data?, moreComing: Bool), any Error>) -> Void)? {
        get {
            recordZoneFetchCompletionBlock.map { block in { zoneID, result in
                switch result {
                case .success(let value): block(zoneID, value.serverChangeToken, value.clientChangeTokenData, value.moreComing, nil)
                case .failure(let error): block(zoneID, nil, nil, false, error)
                }
            } }
        }
        set {
            recordZoneFetchCompletionBlock = newValue.map { block in { zoneID, token, data, moreComing, error in
                if let error {
                    block(zoneID, .failure(error))
                } else if let token {
                    block(zoneID, .success((serverChangeToken: token, clientChangeTokenData: data, moreComing: moreComing)))
                } else {
                    block(zoneID, .failure(CKError(.internalError)))
                }
            } }
        }
    }

    public var fetchRecordZoneChangesResultBlock: ((_ operationResult: Result<Void, any Error>) -> Void)? {
        get { fetchRecordZoneChangesCompletionBlock.map { block in { result in block(parts(result).1) } } }
        set { fetchRecordZoneChangesCompletionBlock = newValue.map { block in { error in block(result(error)) } } }
    }
}

extension CKFetchRecordZoneChangesOperation.ZoneConfiguration {
    public var desiredKeys: [CKRecord.FieldKey]? {
        get { __desiredKeys }
        set { __desiredKeys = newValue }
    }

    convenience public init(previousServerChangeToken: CKServerChangeToken? = nil, resultsLimit: Int? = nil, desiredKeys: [CKRecord.FieldKey]? = nil) {
        self.init()
        self.previousServerChangeToken = previousServerChangeToken
        if let resultsLimit { self.resultsLimit = resultsLimit }
        self.desiredKeys = desiredKeys
    }
}

extension CKFetchRecordZoneChangesOperation.ZoneConfiguration: @unchecked Sendable {}

extension CKModifyRecordsOperation {
    convenience public init(recordsToSave: [CKRecord]? = nil, recordIDsToDelete: [CKRecord.ID]? = nil) {
        self.init()
        self.recordsToSave = recordsToSave
        self.recordIDsToDelete = recordIDsToDelete
    }

    public var perRecordSaveBlock: ((_ recordID: CKRecord.ID, _ saveResult: Result<CKRecord, any Error>) -> Void)? {
        get { __perRecordSaveBlock.map { block in { id, result in let (r, e) = parts(result); block(id, r, e) } } }
        set { __perRecordSaveBlock = newValue.map { block in { id, record, error in block(id, result(record, error)) } } }
    }

    public var perRecordDeleteBlock: ((_ recordID: CKRecord.ID, _ deleteResult: Result<Void, any Error>) -> Void)? {
        get { __perRecordDeleteBlock.map { block in { id, result in block(id, parts(result).1) } } }
        set { __perRecordDeleteBlock = newValue.map { block in { id, error in block(id, result(error)) } } }
    }

    public var modifyRecordsResultBlock: ((_ operationResult: Result<Void, any Error>) -> Void)? {
        get { modifyRecordsCompletionBlock.map { block in { result in block(nil, nil, parts(result).1) } } }
        set { modifyRecordsCompletionBlock = newValue.map { block in { _, _, error in block(result(error)) } } }
    }
}

extension CKAcceptSharesOperation {
    public var perShareResultBlock: ((_ metadata: CKShare.Metadata, _ metadataResult: Result<CKShare, any Error>) -> Void)? {
        get { perShareCompletionBlock.map { block in { metadata, result in let (s, e) = parts(result); block(metadata, s, e) } } }
        set { perShareCompletionBlock = newValue.map { block in { metadata, share, error in block(metadata, result(share, error)) } } }
    }

    public var acceptSharesResultBlock: ((_ operationResult: Result<Void, any Error>) -> Void)? {
        get { acceptSharesCompletionBlock.map { block in { result in block(parts(result).1) } } }
        set { acceptSharesCompletionBlock = newValue.map { block in { error in block(result(error)) } } }
    }
}

extension CKFetchShareMetadataOperation {
    public var rootRecordDesiredKeys: [CKRecord.FieldKey]? {
        get { __rootRecordDesiredKeys }
        set { __rootRecordDesiredKeys = newValue }
    }

    public var perShareMetadataResultBlock: ((_ shareURL: URL, _ shareMetadataResult: Result<CKShare.Metadata, any Error>) -> Void)? {
        get { perShareMetadataBlock.map { block in { url, result in let (m, e) = parts(result); block(url, m, e) } } }
        set { perShareMetadataBlock = newValue.map { block in { url, metadata, error in block(url, result(metadata, error)) } } }
    }

    public var fetchShareMetadataResultBlock: ((_ operationResult: Result<Void, any Error>) -> Void)? {
        get { fetchShareMetadataCompletionBlock.map { block in { result in block(parts(result).1) } } }
        set { fetchShareMetadataCompletionBlock = newValue.map { block in { error in block(result(error)) } } }
    }
}

@available(macOS 26.0, macCatalyst 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension CKShareRequestAccessOperation {
    public var perShareAccessRequestResultBlock: ((URL, Result<Void, any Error>) -> Void)? {
        get { __perShareAccessRequestCompletionBlock.map { block in { url, result in block(url, parts(result).1) } } }
        set { __perShareAccessRequestCompletionBlock = newValue.map { block in { url, error in block(url, result(error)) } } }
    }

    public var shareAccessRequestResultBlock: ((Result<Void, any Error>) -> Void)? {
        get { __shareRequestAccessCompletionBlock.map { block in { result in block(parts(result).1) } } }
        set { __shareRequestAccessCompletionBlock = newValue.map { block in { error in block(result(error)) } } }
    }
}

extension CKFetchSubscriptionsOperation {
    convenience public init(subscriptionIDs: [CKSubscription.ID]) {
        self.init()
        self.subscriptionIDs = subscriptionIDs
    }

    public var subscriptionIDs: [CKSubscription.ID]? {
        get { __subscriptionIDs }
        set { __subscriptionIDs = newValue }
    }

    public var perSubscriptionResultBlock: ((_ subscriptionID: CKSubscription.ID, _ subscriptionResult: Result<CKSubscription, any Error>) -> Void)? {
        get { __perSubscriptionCompletionBlock.map { block in { id, result in let (s, e) = parts(result); block(id, s, e) } } }
        set { __perSubscriptionCompletionBlock = newValue.map { block in { id, subscription, error in block(id, result(subscription, error)) } } }
    }

    public var fetchSubscriptionCompletionBlock: ((_ subscriptionsBySubscriptionID: [CKSubscription.ID: CKSubscription]?, _ operationError: (any Error)?) -> Void)? {
        get { __fetchSubscriptionCompletionBlock }
        set { __fetchSubscriptionCompletionBlock = newValue }
    }

    public var fetchSubscriptionsResultBlock: ((_ operationResult: Result<Void, any Error>) -> Void)? {
        get { __fetchSubscriptionCompletionBlock.map { block in { result in block(nil, parts(result).1) } } }
        set { __fetchSubscriptionCompletionBlock = newValue.map { block in { _, error in block(result(error)) } } }
    }
}

extension CKModifySubscriptionsOperation {
    convenience public init(subscriptionsToSave: [CKSubscription]? = nil, subscriptionIDsToDelete: [CKSubscription.ID]? = nil) {
        self.init()
        self.subscriptionsToSave = subscriptionsToSave
        self.subscriptionIDsToDelete = subscriptionIDsToDelete
    }

    public var subscriptionIDsToDelete: [CKSubscription.ID]? {
        get { __subscriptionIDsToDelete }
        set { __subscriptionIDsToDelete = newValue }
    }

    public var perSubscriptionSaveBlock: ((_ subscriptionID: CKSubscription.ID, _ saveResult: Result<CKSubscription, any Error>) -> Void)? {
        get { __perSubscriptionSaveBlock.map { block in { id, result in let (s, e) = parts(result); block(id, s, e) } } }
        set { __perSubscriptionSaveBlock = newValue.map { block in { id, subscription, error in block(id, result(subscription, error)) } } }
    }

    public var perSubscriptionDeleteBlock: ((_ subscriptionID: CKSubscription.ID, _ deleteResult: Result<Void, any Error>) -> Void)? {
        get { __perSubscriptionDeleteBlock.map { block in { id, result in block(id, parts(result).1) } } }
        set { __perSubscriptionDeleteBlock = newValue.map { block in { id, error in block(id, result(error)) } } }
    }

    public var modifySubscriptionsCompletionBlock: ((_ savedSubscriptions: [CKSubscription]?, _ deletedSubscriptionIDs: [CKSubscription.ID]?, _ operationError: (any Error)?) -> Void)? {
        get { __modifySubscriptionsCompletionBlock }
        set { __modifySubscriptionsCompletionBlock = newValue }
    }

    public var modifySubscriptionsResultBlock: ((_ operationResult: Result<Void, any Error>) -> Void)? {
        get { __modifySubscriptionsCompletionBlock.map { block in { result in block(nil, nil, parts(result).1) } } }
        set { __modifySubscriptionsCompletionBlock = newValue.map { block in { _, _, error in block(result(error)) } } }
    }
}

extension CKFetchDatabaseChangesOperation {
    public var fetchDatabaseChangesResultBlock: ((_ operationResult: Result<(serverChangeToken: CKServerChangeToken, moreComing: Bool), any Error>) -> Void)? {
        get {
            fetchDatabaseChangesCompletionBlock.map { block in { result in
                switch result {
                case .success(let value): block(value.serverChangeToken, value.moreComing, nil)
                case .failure(let error): block(nil, false, error)
                }
            } }
        }
        set {
            fetchDatabaseChangesCompletionBlock = newValue.map { block in { token, moreComing, error in
                if let error {
                    block(.failure(error))
                } else if let token {
                    block(.success((serverChangeToken: token, moreComing: moreComing)))
                } else {
                    block(.failure(CKError(.internalError)))
                }
            } }
        }
    }
}

extension CKFetchRecordZonesOperation {
    public var perRecordZoneResultBlock: ((_ recordZoneID: CKRecordZone.ID, _ recordZoneResult: Result<CKRecordZone, any Error>) -> Void)? {
        get { __perRecordZoneCompletionBlock.map { block in { id, result in let (z, e) = parts(result); block(id, z, e) } } }
        set { __perRecordZoneCompletionBlock = newValue.map { block in { id, zone, error in block(id, result(zone, error)) } } }
    }

    public var fetchRecordZonesResultBlock: ((_ operationResult: Result<Void, any Error>) -> Void)? {
        get { fetchRecordZonesCompletionBlock.map { block in { result in block(nil, parts(result).1) } } }
        set { fetchRecordZonesCompletionBlock = newValue.map { block in { _, error in block(result(error)) } } }
    }
}

extension CKModifyRecordZonesOperation {
    convenience public init(recordZonesToSave: [CKRecordZone]? = nil, recordZoneIDsToDelete: [CKRecordZone.ID]? = nil) {
        self.init()
        self.recordZonesToSave = recordZonesToSave
        self.recordZoneIDsToDelete = recordZoneIDsToDelete
    }

    public var perRecordZoneSaveBlock: ((_ recordZoneID: CKRecordZone.ID, _ saveResult: Result<CKRecordZone, any Error>) -> Void)? {
        get { __perRecordZoneSaveBlock.map { block in { id, result in let (z, e) = parts(result); block(id, z, e) } } }
        set { __perRecordZoneSaveBlock = newValue.map { block in { id, zone, error in block(id, result(zone, error)) } } }
    }

    public var perRecordZoneDeleteBlock: ((_ recordZoneID: CKRecordZone.ID, _ deleteResult: Result<Void, any Error>) -> Void)? {
        get { __perRecordZoneDeleteBlock.map { block in { id, result in block(id, parts(result).1) } } }
        set { __perRecordZoneDeleteBlock = newValue.map { block in { id, error in block(id, result(error)) } } }
    }

    public var modifyRecordZonesResultBlock: ((_ operationResult: Result<Void, any Error>) -> Void)? {
        get { modifyRecordZonesCompletionBlock.map { block in { result in block(nil, nil, parts(result).1) } } }
        set { modifyRecordZonesCompletionBlock = newValue.map { block in { _, _, error in block(result(error)) } } }
    }
}

extension CKFetchWebAuthTokenOperation {
    public var fetchWebAuthTokenResultBlock: ((_ operationResult: Result<String, any Error>) -> Void)? {
        get { fetchWebAuthTokenCompletionBlock.map { block in { result in let (t, e) = parts(result); block(t, e) } } }
        set { fetchWebAuthTokenCompletionBlock = newValue.map { block in { token, error in block(result(token, error)) } } }
    }
}

extension CKDiscoverAllUserIdentitiesOperation {
    public var discoverAllUserIdentitiesResultBlock: ((_ operationResult: Result<Void, any Error>) -> Void)? {
        get { discoverAllUserIdentitiesCompletionBlock.map { block in { result in block(parts(result).1) } } }
        set { discoverAllUserIdentitiesCompletionBlock = newValue.map { block in { error in block(result(error)) } } }
    }
}

extension CKDiscoverUserIdentitiesOperation {
    public var discoverUserIdentitiesResultBlock: ((_ operationResult: Result<Void, any Error>) -> Void)? {
        get { discoverUserIdentitiesCompletionBlock.map { block in { result in block(parts(result).1) } } }
        set { discoverUserIdentitiesCompletionBlock = newValue.map { block in { error in block(result(error)) } } }
    }
}

extension CKFetchShareParticipantsOperation {
    public var perShareParticipantResultBlock: ((_ lookupInfo: CKUserIdentity.LookupInfo, _ shareParticipantResult: Result<CKShare.Participant, any Error>) -> Void)? {
        get { __perShareParticipantCompletionBlock.map { block in { info, result in let (p, e) = parts(result); block(info, p, e) } } }
        set { __perShareParticipantCompletionBlock = newValue.map { block in { info, participant, error in block(info, result(participant, error)) } } }
    }

    public var fetchShareParticipantsResultBlock: ((_ operationResult: Result<Void, any Error>) -> Void)? {
        get { fetchShareParticipantsCompletionBlock.map { block in { result in block(parts(result).1) } } }
        set { fetchShareParticipantsCompletionBlock = newValue.map { block in { error in block(result(error)) } } }
    }
}

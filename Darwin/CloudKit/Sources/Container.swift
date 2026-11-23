// CKContainer's Swift API: long-lived operations, user identities, share
// participants and metadata with Results and async, over CloudKit's
// Objective-C methods and operations.

import Foundation

@available(macOS 10.12, macCatalyst 13.1, iOS 9.3, tvOS 9.2, watchOS 3.0, *)
extension CKContainer {
    @preconcurrency
    public func fetchAllLongLivedOperationIDs(completionHandler: @escaping @Sendable ([CKOperation.ID]?, (any Error)?) -> Void) {
        __fetchAllLongLivedOperationIDs(completionHandler: completionHandler)
    }

    @available(macOS 12.0, macCatalyst 15.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    public func allLongLivedOperationIDs() async throws -> [CKOperation.ID] {
        try await awaitResult { done in __fetchAllLongLivedOperationIDs { done(result($0, $1)) } }
    }

    @preconcurrency
    public func fetchLongLivedOperation(withID operationID: CKOperation.ID, completionHandler: @escaping @Sendable (CKOperation?, (any Error)?) -> Void) {
        __fetchLongLivedOperation(withID: operationID, completionHandler: completionHandler)
    }

    @available(macOS 12.0, macCatalyst 15.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    public func longLivedOperation(for operationID: CKOperation.ID) async throws -> CKOperation? {
        nonisolated(unsafe) var found: CKOperation?
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            __fetchLongLivedOperation(withID: operationID) { operation, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    found = operation
                    continuation.resume()
                }
            }
        }
        return found
    }
}

/// Runs a discovery or participant operation for lookup infos, with each
/// one's result.
@available(macOS 12.0, macCatalyst 15.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
private func participants(_ container: CKContainer, _ infos: [CKUserIdentity.LookupInfo], completion: @escaping @Sendable (Result<[CKUserIdentity.LookupInfo: Result<CKShare.Participant, any Error>], any Error>) -> Void) {
    let operation = CKFetchShareParticipantsOperation(userIdentityLookupInfos: infos)
    let results = ResultsBox([CKUserIdentity.LookupInfo: Result<CKShare.Participant, any Error>]())
    operation.perShareParticipantResultBlock = { info, outcome in results.update { $0[info] = outcome } }
    operation.fetchShareParticipantsResultBlock = { outcome in completion(outcome.map { results.value }) }
    container.run(operation)
}

@available(macOS 12.0, macCatalyst 15.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
private func identities(_ container: CKContainer, _ infos: [CKUserIdentity.LookupInfo], completion: @escaping @Sendable (Result<[CKUserIdentity.LookupInfo: CKUserIdentity], any Error>) -> Void) {
    let operation = CKDiscoverUserIdentitiesOperation(userIdentityLookupInfos: infos)
    let results = ResultsBox([CKUserIdentity.LookupInfo: CKUserIdentity]())
    operation.userIdentityDiscoveredBlock = { identity, info in results.update { $0[info] = identity } }
    operation.discoverUserIdentitiesResultBlock = { outcome in completion(outcome.map { results.value }) }
    container.run(operation)
}

/// The results by key of results by lookup info.
@available(macOS 12.0, macCatalyst 15.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
private func byKey<Key: Hashable, Value>(_ keys: [Key], _ info: (Key) -> CKUserIdentity.LookupInfo, _ results: [CKUserIdentity.LookupInfo: Value]) -> [Key: Value] {
    var answer: [Key: Value] = [:]
    for key in keys {
        if let value = results[info(key)] { answer[key] = value }
    }
    return answer
}

@available(macOS 12.0, macCatalyst 15.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension CKContainer {
    /// Runs the body with the container, its operations given the
    /// configuration and group.
    @discardableResult
    public func configuredWith<R>(configuration: CKOperation.Configuration? = nil, group: CKOperationGroup? = nil, body: (_ configuredContainer: CKContainer) throws -> R) rethrows -> R {
        try withSettings(OperationSettings(configuration: configuration, group: group)) { try body(self) }
    }

    @discardableResult
    @preconcurrency
    public func configuredWith<R>(configuration: CKOperation.Configuration? = nil, group: CKOperationGroup? = nil, body: @Sendable (_ configuredContainer: CKContainer) async throws -> R) async rethrows -> R {
        try await OperationSettings.$current.withValue(OperationSettings(configuration: configuration, group: group)) {
            try await body(self)
        }
    }

    @available(tvOS, unavailable)
    @usableFromInline
    internal func _allUserIdentitiesFromContacts() async throws -> [CKUserIdentity] {
        try await awaitResult { done in discoverAllIdentities { done(result($0, $1)) } }
    }

    @preconcurrency
    public func discoverUserIdentities(forEmailAddresses emails: [String], completionHandler: @escaping @Sendable (Result<[String: CKUserIdentity], any Error>) -> Void) {
        let infos = CKUserIdentity.LookupInfo.lookupInfos(withEmails: emails)
        identities(self, infos) { outcome in
            completionHandler(outcome.map { byKey(emails, { CKUserIdentity.LookupInfo(emailAddress: $0) }, $0) })
        }
    }

    @usableFromInline
    internal func _userIdentity(forEmailAddress email: String) async throws -> CKUserIdentity? {
        try await userIdentities(forEmailAddresses: [email])[email]
    }

    public func userIdentities(forEmailAddresses emails: [String]) async throws -> [String: CKUserIdentity] {
        try await awaitResult { done in discoverUserIdentities(forEmailAddresses: emails, completionHandler: done) }
    }

    @usableFromInline
    internal func _userIdentity(forPhoneNumber phoneNumber: String) async throws -> CKUserIdentity? {
        try await userIdentities(forPhoneNumbers: [phoneNumber])[phoneNumber]
    }

    @preconcurrency
    public func discoverUserIdentities(forPhoneNumbers phoneNumbers: [String], completionHandler: @escaping @Sendable (Result<[String: CKUserIdentity], any Error>) -> Void) {
        let infos = CKUserIdentity.LookupInfo.lookupInfos(withPhoneNumbers: phoneNumbers)
        identities(self, infos) { outcome in
            completionHandler(outcome.map { byKey(phoneNumbers, { CKUserIdentity.LookupInfo(phoneNumber: $0) }, $0) })
        }
    }

    public func userIdentities(forPhoneNumbers phoneNumbers: [String]) async throws -> [String: CKUserIdentity] {
        try await awaitResult { done in discoverUserIdentities(forPhoneNumbers: phoneNumbers, completionHandler: done) }
    }

    @usableFromInline
    internal func _userIdentity(forUserRecordID userRecordID: CKRecord.ID) async throws -> CKUserIdentity? {
        try await userIdentities(forUserRecordIDs: [userRecordID])[userRecordID]
    }

    @preconcurrency
    public func discoverUserIdentities(forUserRecordIDs userRecordIDs: [CKRecord.ID], completionHandler: @escaping @Sendable (Result<[CKRecord.ID: CKUserIdentity], any Error>) -> Void) {
        let infos = CKUserIdentity.LookupInfo.lookupInfos(with: userRecordIDs)
        identities(self, infos) { outcome in
            completionHandler(outcome.map { byKey(userRecordIDs, { CKUserIdentity.LookupInfo(userRecordID: $0) }, $0) })
        }
    }

    public func userIdentities(forUserRecordIDs userRecordIDs: [CKRecord.ID]) async throws -> [CKRecord.ID: CKUserIdentity] {
        try await awaitResult { done in discoverUserIdentities(forUserRecordIDs: userRecordIDs, completionHandler: done) }
    }

    @available(macOS 27.0, macCatalyst 27.0, iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
    @usableFromInline
    internal func _shareParticipant(forEmailAddress email: String) async throws -> CKShare.Participant {
        try await awaitResult { done in fetchShareParticipant(withEmailAddress: email) { done(result($0, $1)) } }
    }

    @preconcurrency
    public func fetchShareParticipants(forEmailAddresses emails: [String], completionHandler: @escaping @Sendable (Result<[String: Result<CKShare.Participant, any Error>], any Error>) -> Void) {
        participants(self, CKUserIdentity.LookupInfo.lookupInfos(withEmails: emails)) { outcome in
            completionHandler(outcome.map { byKey(emails, { CKUserIdentity.LookupInfo(emailAddress: $0) }, $0) })
        }
    }

    public func shareParticipants(forEmailAddresses emails: [String]) async throws -> [String: Result<CKShare.Participant, any Error>] {
        try await awaitResult { done in fetchShareParticipants(forEmailAddresses: emails, completionHandler: done) }
    }

    @available(macOS 27.0, macCatalyst 27.0, iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
    @usableFromInline
    internal func _shareParticipant(forPhoneNumber phoneNumber: String) async throws -> CKShare.Participant {
        try await awaitResult { done in fetchShareParticipant(withPhoneNumber: phoneNumber) { done(result($0, $1)) } }
    }

    @preconcurrency
    public func fetchShareParticipants(forPhoneNumbers phoneNumbers: [String], completionHandler: @escaping @Sendable (Result<[String: Result<CKShare.Participant, any Error>], any Error>) -> Void) {
        participants(self, CKUserIdentity.LookupInfo.lookupInfos(withPhoneNumbers: phoneNumbers)) { outcome in
            completionHandler(outcome.map { byKey(phoneNumbers, { CKUserIdentity.LookupInfo(phoneNumber: $0) }, $0) })
        }
    }

    public func shareParticipants(forPhoneNumbers phoneNumbers: [String]) async throws -> [String: Result<CKShare.Participant, any Error>] {
        try await awaitResult { done in fetchShareParticipants(forPhoneNumbers: phoneNumbers, completionHandler: done) }
    }

    @available(macOS 27.0, macCatalyst 27.0, iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
    @usableFromInline
    internal func _shareParticipant(forUserRecordID userRecordID: CKRecord.ID) async throws -> CKShare.Participant {
        try await awaitResult { done in fetchShareParticipant(withUserRecordID: userRecordID) { done(result($0, $1)) } }
    }

    @preconcurrency
    public func fetchShareParticipants(forUserRecordIDs userRecordIDs: [CKRecord.ID], completionHandler: @escaping @Sendable (Result<[CKRecord.ID: Result<CKShare.Participant, any Error>], any Error>) -> Void) {
        participants(self, CKUserIdentity.LookupInfo.lookupInfos(with: userRecordIDs)) { outcome in
            completionHandler(outcome.map { byKey(userRecordIDs, { CKUserIdentity.LookupInfo(userRecordID: $0) }, $0) })
        }
    }

    public func shareParticipants(forUserRecordIDs userRecordIDs: [CKRecord.ID]) async throws -> [CKRecord.ID: Result<CKShare.Participant, any Error>] {
        try await awaitResult { done in fetchShareParticipants(forUserRecordIDs: userRecordIDs, completionHandler: done) }
    }

    @available(macOS 26.0, macCatalyst 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public func shareParticipants(for lookupInfos: [CKUserIdentity.LookupInfo]) async throws -> [CKUserIdentity.LookupInfo: Result<CKShare.Participant, any Error>] {
        try await awaitResult { done in participants(self, lookupInfos) { done($0) } }
    }

    @available(macOS 27.0, macCatalyst 27.0, iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
    @usableFromInline
    internal func _shareMetadata(for url: URL) async throws -> CKShare.Metadata {
        try await awaitResult { done in fetchShareMetadata(with: url) { done(result($0, $1)) } }
    }

    @preconcurrency
    public func fetchShareMetadatas(for urls: [URL], completionHandler: @escaping @Sendable (Result<[URL: Result<CKShare.Metadata, any Error>], any Error>) -> Void) {
        let operation = CKFetchShareMetadataOperation(shareURLs: urls)
        let results = ResultsBox([URL: Result<CKShare.Metadata, any Error>]())
        operation.perShareMetadataResultBlock = { url, outcome in results.update { $0[url] = outcome } }
        operation.fetchShareMetadataResultBlock = { outcome in completionHandler(outcome.map { results.value }) }
        run(operation)
    }

    public func shareMetadatas(for urls: [URL]) async throws -> [URL: Result<CKShare.Metadata, any Error>] {
        try await awaitResult { done in fetchShareMetadatas(for: urls, completionHandler: done) }
    }

    @available(macOS 27.0, macCatalyst 27.0, iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
    @usableFromInline
    internal func _accept(_ metadata: CKShare.Metadata) async throws -> CKShare {
        try await awaitResult { done in accept(metadata) { done(result($0, $1)) } }
    }

    @preconcurrency
    public func accept(_ metadatas: [CKShare.Metadata], completionHandler: @escaping @Sendable (Result<[CKShare.Metadata: Result<CKShare, any Error>], any Error>) -> Void) {
        let operation = CKAcceptSharesOperation(shareMetadatas: metadatas)
        let results = ResultsBox([CKShare.Metadata: Result<CKShare, any Error>]())
        operation.perShareResultBlock = { metadata, outcome in results.update { $0[metadata] = outcome } }
        operation.acceptSharesResultBlock = { outcome in completionHandler(outcome.map { results.value }) }
        run(operation)
    }

    public func accept(_ metadatas: [CKShare.Metadata]) async throws -> [CKShare.Metadata: Result<CKShare, any Error>] {
        try await awaitResult { done in accept(metadatas, completionHandler: done) }
    }

    @available(macOS 26.0, macCatalyst 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public func requestShareAccess(for urls: [URL]) async throws -> [URL: Result<Void, any Error>] {
        try await awaitResult { done in
            let operation = CKShareRequestAccessOperation(shareURLs: urls)
            let results = ResultsBox([URL: Result<Void, any Error>]())
            operation.perShareAccessRequestResultBlock = { url, outcome in results.update { $0[url] = outcome } }
            operation.shareAccessRequestResultBlock = { outcome in done(outcome.map { results.value }) }
            run(operation)
        }
    }
}

@available(macOS 10.10, macCatalyst 13.1, iOS 8.0, tvOS 9.0, watchOS 3.0, *)
extension CKContainer {
    /// The names of the application permission types before Swift 4.2.
    public enum Application {
        @available(*, deprecated, message: "renamed to CKContainer.ApplicationPermissions")
        public typealias Permissions = CKContainer.ApplicationPermissions
        @available(*, deprecated, message: "renamed to CKContainer.ApplicationPermissionStatus")
        public typealias PermissionStatus = CKContainer.ApplicationPermissionStatus
        @available(*, deprecated, message: "renamed to CKContainer.ApplicationPermissionBlock")
        public typealias PermissionBlock = CKContainer.ApplicationPermissionBlock
    }
}

@available(*, unavailable)
extension CKContainer.Application: Sendable {}

@available(*, deprecated, message: "renamed to CKContainer.ApplicationPermissions")
public typealias CKContainer_Application_Permissions = CKContainer.ApplicationPermissions
@available(*, deprecated, message: "renamed to CKContainer.ApplicationPermissionStatus")
public typealias CKContainer_Application_PermissionStatus = CKContainer.ApplicationPermissionStatus
@available(*, deprecated, message: "renamed to CKContainer.ApplicationPermissionBlock")
public typealias CKContainer_Application_PermissionBlock = CKContainer.ApplicationPermissionBlock

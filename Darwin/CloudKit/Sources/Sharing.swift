// CloudKit's Swift API for subscriptions, notification info and shares:
// their identifiers and keys as Swift types, the share observer's blocks
// as Results, and sharing through Transferable and NSItemProvider.

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

// MARK: - Subscriptions

extension CKSubscription {
    public typealias ID = String

    public var subscriptionID: CKSubscription.ID {
        __subscriptionID
    }
}

extension CKSubscription: @unchecked Sendable {}

extension CKDatabaseSubscription {
    convenience public init(subscriptionID: CKSubscription.ID) {
        self.init(__subscriptionID: subscriptionID)
    }

    public var recordType: CKRecord.RecordType? {
        get { __recordType }
        set { __recordType = newValue }
    }
}

extension CKDatabaseSubscription: @unchecked Sendable {}

extension CKQuerySubscription {
    convenience public init(recordType: CKRecord.RecordType, predicate: NSPredicate, subscriptionID: CKSubscription.ID, options querySubscriptionOptions: CKQuerySubscription.Options = [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]) {
        self.init(__recordType: recordType, predicate: predicate, subscriptionID: subscriptionID, options: querySubscriptionOptions)
    }

    public var recordType: CKRecord.RecordType? {
        __recordType
    }
}

extension CKQuerySubscription: @unchecked Sendable {}

extension CKRecordZoneSubscription {
    convenience public init(zoneID: CKRecordZone.ID, subscriptionID: CKSubscription.ID) {
        self.init(__zoneID: zoneID, subscriptionID: subscriptionID)
    }

    public var recordType: CKRecord.RecordType? {
        get { __recordType }
        set { __recordType = newValue }
    }
}

extension CKRecordZoneSubscription: @unchecked Sendable {}

extension CKSubscription.NotificationInfo {
    public var alertLocalizationArgs: [CKRecord.FieldKey]? {
        get { __alertLocalizationArgs }
        set { __alertLocalizationArgs = newValue }
    }

    public var titleLocalizationArgs: [CKRecord.FieldKey]? {
        get { __titleLocalizationArgs }
        set { __titleLocalizationArgs = newValue }
    }

    public var subtitleLocalizationArgs: [CKRecord.FieldKey]? {
        get { __subtitleLocalizationArgs }
        set { __subtitleLocalizationArgs = newValue }
    }

    public var desiredKeys: [CKRecord.FieldKey]? {
        get { __desiredKeys }
        set { __desiredKeys = newValue }
    }

    convenience public init(alertBody: String? = nil, alertLocalizationKey: String? = nil, alertLocalizationArgs: [CKRecord.FieldKey] = [], title: String? = nil, titleLocalizationKey: String? = nil, titleLocalizationArgs: [CKRecord.FieldKey] = [], subtitle: String? = nil, subtitleLocalizationKey: String? = nil, subtitleLocalizationArgs: [CKRecord.FieldKey] = [], alertActionLocalizationKey: String? = nil, alertLaunchImage: String? = nil, soundName: String? = nil, desiredKeys: [CKRecord.FieldKey] = [], shouldBadge: Bool = false, shouldSendContentAvailable: Bool = false, shouldSendMutableContent: Bool = false, category: String? = nil, collapseIDKey: String? = nil) {
        self.init()
        self.alertBody = alertBody
        self.alertLocalizationKey = alertLocalizationKey
        self.alertLocalizationArgs = alertLocalizationArgs
        self.title = title
        self.titleLocalizationKey = titleLocalizationKey
        self.titleLocalizationArgs = titleLocalizationArgs
        self.subtitle = subtitle
        self.subtitleLocalizationKey = subtitleLocalizationKey
        self.subtitleLocalizationArgs = subtitleLocalizationArgs
        self.alertActionLocalizationKey = alertActionLocalizationKey
        self.alertLaunchImage = alertLaunchImage
        self.soundName = soundName
        self.desiredKeys = desiredKeys
        self.shouldBadge = shouldBadge
        self.shouldSendContentAvailable = shouldSendContentAvailable
        self.shouldSendMutableContent = shouldSendMutableContent
        self.category = category
        self.collapseIDKey = collapseIDKey
    }
}

extension CKSubscription.NotificationInfo: @unchecked Sendable {}

// MARK: - Shares

extension CKShare {
    public enum SystemFieldKey {
        public static let title: CKRecord.FieldKey = CKShareTitleKey
        public static let thumbnailImageData: CKRecord.FieldKey = CKShareThumbnailImageDataKey
        public static let shareType: CKRecord.FieldKey = CKShareTypeKey
    }
}

extension CKShare.SystemFieldKey: Sendable {}

extension CKShare: @unchecked Sendable {}

public let CKRecordTypeShare: String = __CKRecordTypeShare
public let CKShareTitleKey: String = __CKShareTitleKey
public let CKShareThumbnailImageDataKey: String = __CKShareThumbnailImageDataKey
public let CKShareTypeKey: String = __CKShareTypeKey

extension CKShare {
    @available(macOS 15.0, macCatalyst 18.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    public func oneTimeURL(for participantID: CKShare.Participant.ID) -> URL? {
        __oneTimeURL(forParticipantID: participantID)
    }
}

extension CKShare.Metadata: @unchecked Sendable {}

extension CKShare.Participant {
    public typealias AcceptanceStatus = CKShare.ParticipantAcceptanceStatus
    public typealias Permission = CKShare.ParticipantPermission
    public typealias Role = CKShare.ParticipantRole
    public typealias ParticipantType = CKShare.ParticipantType
}

extension CKShare.Participant {
    public typealias ID = String
}

extension CKShare.Participant {
    @available(macOS 12.0, macCatalyst 15.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    final public var participantID: CKShare.Participant.ID {
        __participantID
    }
}

extension CKShare.Participant: @unchecked Sendable {}

public typealias CKShare_Participant_AcceptanceStatus = CKShare.ParticipantAcceptanceStatus
public typealias CKShare_Participant_Permission = CKShare.ParticipantPermission
public typealias CKShare_Participant_Role = CKShare.ParticipantRole
public typealias CKShare_Participant_ParticipantType = CKShare.ParticipantType

/// The data a share is handed over as: its URL's text.
@available(macOS 13.0, iOS 16.0, *)
private func shareData(_ share: CKShare) throws -> Data {
    guard let url = share.url else { throw CKError(.internalError) }
    return Data(url.absoluteString.utf8)
}

/// Shares an item through CloudKit when it is transferred (dragged or
/// shared): the share is made, or the existing one given, and handed over
/// as its URL.
@available(macOS 13.0, iOS 16.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
public struct CKShareTransferRepresentation<Item>: TransferRepresentation where Item: Transferable {
    private let exporter: @Sendable (Item) throws -> ExportedShare

    public init(exporter: @escaping @Sendable (Item) throws -> ExportedShare) {
        self.exporter = exporter
    }

    public var body: some TransferRepresentation {
        let exporter = self.exporter
        return DataRepresentation<Item>(exportedContentType: .url) { item in
            try await exporter(item).share()
        }
    }

    /// The share an item is transferred as.
    public struct ExportedShare: Transferable, Sendable {
        private let make: @Sendable () async throws -> CKShare
        let container: CKContainer
        let allowedSharingOptions: CKAllowedSharingOptions

        private init(container: CKContainer, allowedSharingOptions: CKAllowedSharingOptions, make: @escaping @Sendable () async throws -> CKShare) {
            self.container = container
            self.allowedSharingOptions = allowedSharingOptions
            self.make = make
        }

        func share() async throws -> Data {
            try shareData(await make())
        }

        public static func prepareShare(container: CKContainer, allowedSharingOptions: CKAllowedSharingOptions = CKAllowedSharingOptions.standard, preparationHandler: @escaping @Sendable () async throws -> CKShare) -> ExportedShare {
            ExportedShare(container: container, allowedSharingOptions: allowedSharingOptions, make: preparationHandler)
        }

        public static func existing(_ share: CKShare, container: CKContainer, allowedSharingOptions: CKAllowedSharingOptions = CKAllowedSharingOptions.standard) -> ExportedShare {
            ExportedShare(container: container, allowedSharingOptions: allowedSharingOptions, make: { share })
        }

        public static var transferRepresentation: some TransferRepresentation {
            DataRepresentation<ExportedShare>(exportedContentType: .url) { exported in
                try await exported.share()
            }
        }
    }
}

@available(macOS 13.0, iOS 16.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
extension NSItemProvider {
    /// Offers a share the handler makes when it is asked for. The
    /// Objective-C methods have these methods' Swift names, so they are
    /// called through their implementations.
    public func registerCKShare(container: CKContainer, allowedSharingOptions: CKAllowedSharingOptions = CKAllowedSharingOptions.standard, preparationHandler: @escaping @Sendable () async throws -> CKShare) {
        let handler: @convention(block) (@escaping @convention(block) (CKShare?, NSError?) -> Void) -> Void = { completion in
            nonisolated(unsafe) let completion = completion
            Task {
                do {
                    completion(try await preparationHandler(), nil)
                } catch {
                    completion(nil, error as NSError)
                }
            }
        }
        let selector = NSSelectorFromString("registerCKShareWithContainer:allowedSharingOptions:preparationHandler:")
        typealias Method = @convention(c) (NSItemProvider, Selector, CKContainer, CKAllowedSharingOptions, @convention(block) (@escaping @convention(block) (CKShare?, NSError?) -> Void) -> Void) -> Void
        unsafeBitCast(method(for: selector), to: Method.self)(self, selector, container, allowedSharingOptions, handler)
    }

    public func registerCKShare(_ share: CKShare, container: CKContainer, allowedSharingOptions: CKAllowedSharingOptions = CKAllowedSharingOptions.standard) {
        let selector = NSSelectorFromString("registerCKShare:container:allowedSharingOptions:")
        typealias Method = @convention(c) (NSItemProvider, Selector, CKShare, CKContainer, CKAllowedSharingOptions) -> Void
        unsafeBitCast(method(for: selector), to: Method.self)(self, selector, share, container, allowedSharingOptions)
    }
}

// MARK: - The system sharing observer

@available(macOS 13.0, macCatalyst 16.0, iOS 16.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
extension CKSystemSharingUIObserver {
    @preconcurrency public var systemSharingUIDidSaveShareBlock: (@Sendable (_ recordID: CKRecord.ID, _ saveResult: Result<CKShare, any Error>) -> Void)? {
        get { __systemSharingUIDidSaveShareBlock.map { block in { id, result in let (s, e) = parts(result); block(id, s, e) } } }
        set { __systemSharingUIDidSaveShareBlock = newValue.map { block in { id, share, error in block(id, result(share, error)) } } }
    }

    @preconcurrency public var systemSharingUIDidStopSharingBlock: (@Sendable (_ recordID: CKRecord.ID, _ deleteResult: Result<Void, any Error>) -> Void)? {
        get { __systemSharingUIDidStopSharingBlock.map { block in { id, result in block(id, parts(result).1) } } }
        set { __systemSharingUIDidStopSharingBlock = newValue.map { block in { id, error in block(id, result(error)) } } }
    }
}

@available(macOS 13.0, macCatalyst 16.0, iOS 16.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
extension CKSystemSharingUIObserver: @unchecked Sendable {}

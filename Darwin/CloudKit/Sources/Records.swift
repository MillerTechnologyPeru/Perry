// CloudKit's Swift API for records: record types and field keys as
// strings, record values as Swift values, records as sequences of their
// fields, and the identifiers' Swift initializers, over the Objective-C
// API the headers keep for Swift (the __ names).

import CoreLocation
import Foundation

// MARK: - Assets

@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension CKAsset: @unchecked Sendable {}

extension CKAsset {
    /// The identifier of an asset another service (iCloud Photos) stores
    /// in CloudKit, to make an asset of without copying its data. No such
    /// service exists here, so one can only be decoded.
    @available(macOS 27.0, macCatalyst 27.0, iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
    public struct ExportedAssetID: Codable, Sendable {
        let identifier: String

        public init(from decoder: any Decoder) throws {
            identifier = try decoder.singleValueContainer().decode(String.self)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(identifier)
        }
    }

    /// An asset of an exported one. Its data can't be reached here, so the
    /// asset is of an empty file named by the identifier.
    @available(macOS 27.0, macCatalyst 27.0, iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
    convenience public init(importing exportedAssetID: ExportedAssetID) {
        let name = exportedAssetID.identifier.map { $0.isLetter || $0.isNumber ? $0 : "_" }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CKAsset-" + String(name))
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: Data())
        }
        self.init(fileURL: url)
    }
}

@available(macOS 13.3, macCatalyst 16.4, iOS 16.4, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
extension CKAllowedSharingOptions: @unchecked Sendable {}

// MARK: - Records

/// Iterates a record's keys and values.
public struct CKRecordKeyValueIterator: IteratorProtocol {
    private let record: CKRecord
    private var keys: IndexingIterator<[CKRecord.FieldKey]>

    init(_ record: CKRecord) {
        self.record = record
        keys = record.allKeys().makeIterator()
    }

    public mutating func next() -> (CKRecord.FieldKey, any CKRecordValueProtocol)? {
        while let key = keys.next() {
            if let value = record[key] as? any CKRecordValueProtocol {
                return (key, value)
            }
        }
        return nil
    }

    public typealias Element = (CKRecord.FieldKey, any CKRecordValueProtocol)
}

extension CKRecord: @unchecked Sendable {}

extension CKRecordKeyValueIterator: @unchecked Sendable {}

extension CKRecord: Sequence {
    public func makeIterator() -> CKRecordKeyValueIterator {
        CKRecordKeyValueIterator(self)
    }

    public typealias Element = (CKRecord.FieldKey, any CKRecordValueProtocol)
    public typealias Iterator = CKRecordKeyValueIterator
}

extension CKRecord {
    public typealias RecordType = String
    public typealias FieldKey = String

    public enum SystemType {
        public static let userRecord: CKRecord.RecordType = CKRecordTypeUserRecord
        public static let share: CKRecord.RecordType = CKRecordTypeShare
    }

    public enum SystemFieldKey {
        public static var recordID: CKRecord.FieldKey { __CKRecordRecordIDKey as CKRecord.FieldKey }
        public static var creatorUserRecordID: CKRecord.FieldKey { __CKRecordCreatorUserRecordIDKey as CKRecord.FieldKey }
        public static var creationDate: CKRecord.FieldKey { __CKRecordCreationDateKey as CKRecord.FieldKey }
        public static var lastModifiedUserRecordID: CKRecord.FieldKey { __CKRecordLastModifiedUserRecordIDKey as CKRecord.FieldKey }
        public static var modificationDate: CKRecord.FieldKey { __CKRecordModificationDateKey as CKRecord.FieldKey }
        public static let parent: CKRecord.FieldKey = CKRecordParentKey
        public static let share: CKRecord.FieldKey = CKRecordShareKey
    }

    convenience public init(recordType: CKRecord.RecordType, zoneID: CKRecordZone.ID) {
        self.init(__recordType: recordType, recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zoneID))
    }

    convenience public init(recordType: CKRecord.RecordType, recordID: CKRecord.ID = CKRecord.ID()) {
        self.init(__recordType: recordType, recordID: recordID)
    }

    public var recordType: CKRecord.RecordType {
        __recordType
    }

    public func object(forKey key: CKRecord.FieldKey) -> (any __CKRecordObjCValue)? {
        __object(forKey: key)
    }

    public func setObject(_ object: (any __CKRecordObjCValue)?, forKey key: CKRecord.FieldKey) {
        __setObject(object, forKey: key)
    }

    public subscript(key: CKRecord.FieldKey) -> (any __CKRecordObjCValue)? {
        get { __object(forKey: key) }
        set { __setObject(newValue, forKey: key) }
    }

    public func allKeys() -> [CKRecord.FieldKey] {
        __allKeys()
    }

    public func changedKeys() -> [CKRecord.FieldKey] {
        __changedKeys()
    }
}

extension CKRecord.SystemType: Sendable {}

extension CKRecord.SystemFieldKey: Sendable {}

public let CKRecordTypeUserRecord: String = __CKRecordTypeUserRecord
public let CKRecordParentKey: String = __CKRecordParentKey
public let CKRecordShareKey: String = __CKRecordShareKey

extension CKRecord.ID {
    convenience public init(recordName: String = UUID().uuidString, zoneID: CKRecordZone.ID = CKRecordZone.ID.default) {
        self.init(__recordName: recordName, zoneID: zoneID)
    }
}

extension CKRecord.Reference {
    public typealias Action = CKRecord.ReferenceAction
}

public typealias CKRecord_Reference_Action = CKRecord.ReferenceAction

// MARK: - Record values

/// A value a record's field can hold.
public protocol CKRecordValueProtocol {}

public typealias CKRecordValue = __CKRecordObjCValue

/// The Objective-C value of a Swift record value.
private func objectValue(_ value: (any CKRecordValueProtocol)?) -> (any __CKRecordObjCValue)? {
    guard let value else { return nil }
    return (value as AnyObject) as? any __CKRecordObjCValue
}

extension CKRecordKeyValueSetting {
    public subscript<T>(key: CKRecord.FieldKey) -> T? where T: CKRecordValueProtocol {
        get { object(forKey: key).flatMap { $0 as? T } }
        set { setObject(objectValue(newValue), forKey: key) }
    }

    public subscript(key: CKRecord.FieldKey) -> (any CKRecordValueProtocol)? {
        get { object(forKey: key).flatMap { $0 as? any CKRecordValueProtocol } }
        set { setObject(objectValue(newValue), forKey: key) }
    }
}

extension String: CKRecordValueProtocol {}
extension Date: CKRecordValueProtocol {}
extension Data: CKRecordValueProtocol {}
extension Bool: CKRecordValueProtocol {}
extension Double: CKRecordValueProtocol {}
extension Int: CKRecordValueProtocol {}
extension UInt: CKRecordValueProtocol {}
extension Int8: CKRecordValueProtocol {}
extension UInt8: CKRecordValueProtocol {}
extension Int16: CKRecordValueProtocol {}
extension UInt16: CKRecordValueProtocol {}
extension Int32: CKRecordValueProtocol {}
extension UInt32: CKRecordValueProtocol {}
extension Int64: CKRecordValueProtocol {}
extension UInt64: CKRecordValueProtocol {}
extension Float: CKRecordValueProtocol {}
extension Array: CKRecordValueProtocol where Element: CKRecordValueProtocol {}
extension NSString: CKRecordValueProtocol {}
extension NSDate: CKRecordValueProtocol {}
extension NSData: CKRecordValueProtocol {}
extension NSNumber: CKRecordValueProtocol {}
extension NSArray: CKRecordValueProtocol {}
extension CKRecord.Reference: CKRecordValueProtocol {}
extension CKAsset: CKRecordValueProtocol {}
extension CLLocation: CKRecordValueProtocol {}

// MARK: - Zones

extension CKRecordZone: @unchecked Sendable {}

extension CKRecordZone.ID {
    convenience public init(zoneName: String = CKRecordZone.ID.defaultZoneName, ownerName: String = CKCurrentUserDefaultName) {
        self.init(__zoneName: zoneName, ownerName: ownerName)
    }

    public static let `default` = CKRecordZone.ID(zoneName: CKRecordZone.ID.defaultZoneName, ownerName: CKCurrentUserDefaultName)
    public static let defaultZoneName: String = CKRecordZoneDefaultName
}

extension CKRecordZone.ID: @unchecked Sendable {}

public let CKRecordZoneDefaultName: String = __CKRecordZoneDefaultName

// MARK: - Queries

extension CKQuery {
    convenience public init(recordType: CKRecord.RecordType, predicate: NSPredicate) {
        self.init(__recordType: recordType, predicate: predicate)
    }

    public var recordType: CKRecord.RecordType {
        __recordType
    }
}

extension CKQuery: @unchecked Sendable {}

extension CKQueryOperation.Cursor: @unchecked Sendable {}

// MARK: - Errors

extension CKError {
    public var partialErrorsByItemID: [AnyHashable: any Error]? {
        (userInfo[CKPartialErrorsByItemIDKey] as? NSDictionary).map { dictionary in
            var errors: [AnyHashable: any Error] = [:]
            for (key, value) in dictionary {
                if let key = key as? AnyHashable, let error = value as? any Error {
                    errors[key] = error
                }
            }
            return errors
        }
    }

    public var ancestorRecord: CKRecord? {
        userInfo[CKRecordChangedErrorAncestorRecordKey] as? CKRecord
    }

    public var serverRecord: CKRecord? {
        userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord
    }

    public var clientRecord: CKRecord? {
        userInfo[CKRecordChangedErrorClientRecordKey] as? CKRecord
    }

    public var retryAfterSeconds: Double? {
        (userInfo[CKErrorRetryAfterKey] as? NSNumber)?.doubleValue
    }
}

// MARK: - Operations

extension CKOperation {
    public typealias ID = String

    public var operationID: CKOperation.ID {
        __operationID
    }
}

extension CKOperation.Configuration: @unchecked Sendable {}

extension CKOperationGroup: @unchecked Sendable {}

extension CKNotification {
    public var subscriptionID: CKSubscription.ID? {
        __subscriptionID
    }
}

extension CKNotification.ID: @unchecked Sendable {}

extension CKUserIdentity: @unchecked Sendable {}

extension CKUserIdentity.LookupInfo: @unchecked Sendable {}

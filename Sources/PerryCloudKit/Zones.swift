import PerryObjCInterop

// CloudKit's record zones and subscriptions, without iCloud as the rest is:
// zones, their IDs, subscriptions and the options given to them keep what a
// program puts in them, and the operations on them finish at once with the
// error of an account that is not signed in.

/// What each of these objects keeps.
final class ZoneState {
    var name: String?
    var owner: String?
    var zoneID: NSObject?
    var completion: ObjCBlock?
    var zoneFetchCompletion: ObjCBlock?
    /// The zone IDs an operation is for, retained.
    var zoneIDs: NSObject?
}

enum Zones {
    static let states = StateTable<ZoneState>()

    static func state(_ object: UnsafeMutableRawPointer) -> ZoneState {
        if let state = states[object] { return state }
        let state = ZoneState()
        states.set(object, state)
        return state
    }
}

@ObjCClass("CKRecordZoneID")
open class CKRecordZoneID: NSObject {
    var zone: ZoneState { Zones.state(objcObject) }

    @ObjCMethod("dealloc")
    func dealloc() {
        Zones.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CKRecordZoneID.objCClass.pointer)
    }

    @ObjCMethod("initWithZoneName:ownerName:")
    func initialize(zoneName: String?, ownerName: String?) -> Self {
        (zone.name, zone.owner) = (zoneName, ownerName)
        return self
    }

    @ObjCMethod("zoneName") func zoneName() -> String? { zone.name }
    @ObjCMethod("ownerName") func ownerName() -> String? { zone.owner ?? CloudKitConstants.CKCurrentUserDefaultName }
}

@ObjCClass("CKRecordZone")
open class CKRecordZone: NSObject {
    var zone: ZoneState { Zones.state(objcObject) }

    @ObjCMethod("dealloc")
    func dealloc() {
        Zones.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CKRecordZone.objCClass.pointer)
    }

    @ObjCMethod("initWithZoneName:")
    func initialize(zoneName: String?) -> Self {
        zone.name = zoneName
        return self
    }

    @ObjCMethod("initWithZoneID:")
    func initialize(zoneID: NSObject?) -> Self {
        zone.zoneID = zoneID
        return self
    }

    @ObjCMethod("zoneID") func zoneID() -> NSObject? { zone.zoneID }
    /// CKRecordZoneCapabilities: none, as no zone is stored.
    @ObjCMethod("capabilities") func capabilities() -> UInt { 0 }
}

@ObjCClass("CKSubscription")
open class CKSubscription: NSObject {
    var zone: ZoneState { Zones.state(objcObject) }

    @ObjCMethod("dealloc")
    func dealloc() {
        Zones.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CKSubscription.objCClass.pointer)
    }

    @ObjCMethod("subscriptionID") func subscriptionID() -> String? { zone.name }
    @ObjCMethod("notificationInfo") func notificationInfo() -> NSObject? { zone.zoneID }
    @ObjCMethod("setNotificationInfo:") func setNotificationInfo(_ info: NSObject?) { zone.zoneID = info }
}

@ObjCClass("CKQuerySubscription")
open class CKQuerySubscription: CKSubscription {
    @ObjCMethod("initWithRecordType:predicate:options:")
    func initialize(recordType: String?, predicate: NSObject?, options: UInt) -> Self { self }

    @ObjCMethod("initWithRecordType:predicate:subscriptionID:options:")
    func initialize(recordType: String?, predicate: NSObject?, subscriptionID: String?, options: UInt) -> Self {
        zone.name = subscriptionID
        return self
    }
}

@ObjCClass("CKNotificationInfo")
open class CKNotificationInfo: NSObject {
    @ObjCMethod("setShouldSendContentAvailable:") func setShouldSendContentAvailable(_ value: Bool) {}
    @ObjCMethod("setShouldSendMutableContent:") func setShouldSendMutableContent(_ value: Bool) {}
    @ObjCMethod("setShouldBadge:") func setShouldBadge(_ value: Bool) {}
    @ObjCMethod("setAlertBody:") func setAlertBody(_ value: NSObject?) {}
    @ObjCMethod("setSoundName:") func setSoundName(_ value: NSObject?) {}
    @ObjCMethod("setDesiredKeys:") func setDesiredKeys(_ value: NSObject?) {}
    @ObjCMethod("setCategory:") func setCategory(_ value: NSObject?) {}
}

@ObjCClass("CKFetchRecordZoneChangesConfiguration")
open class CKFetchRecordZoneChangesConfiguration: NSObject {
    @ObjCMethod("setPreviousServerChangeToken:") func setPreviousServerChangeToken(_ token: NSObject?) {}
    @ObjCMethod("previousServerChangeToken") func previousServerChangeToken() -> NSObject? { nil }
    @ObjCMethod("setResultsLimit:") func setResultsLimit(_ limit: UInt) {}
    @ObjCMethod("setDesiredKeys:") func setDesiredKeys(_ keys: NSObject?) {}
}

// MARK: - Operations

@ObjCClass("CKModifyRecordZonesOperation")
open class CKModifyRecordZonesOperation: CKDatabaseOperation {
    var zone: ZoneState { Zones.state(objcObject) }

    @ObjCMethod("dealloc")
    func deallocZone() {
        Zones.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CKModifyRecordZonesOperation.objCClass.pointer)
    }

    @ObjCMethod("initWithRecordZonesToSave:recordZoneIDsToDelete:")
    func initialize(recordZonesToSave: NSObject?, recordZoneIDsToDelete: NSObject?) -> Self { self }

    @ObjCMethod("setRecordZonesToSave:") func setRecordZonesToSave(_ zones: NSObject?) {}
    @ObjCMethod("setRecordZoneIDsToDelete:") func setRecordZoneIDsToDelete(_ ids: NSObject?) {}
    @ObjCMethod("modifyRecordZonesCompletionBlock") func modifyRecordZonesCompletionBlock() -> ObjCBlock? { zone.completion }
    @ObjCMethod("setModifyRecordZonesCompletionBlock:") func setModifyRecordZonesCompletionBlock(_ block: ObjCBlock?) { zone.completion = block }

    /// Nothing saved, nothing deleted, and the error.
    override func finishWithoutAccount() {
        if let block = zone.completion {
            typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?,
                                               UnsafeMutableRawPointer?) -> Void
            block.function(as: Invoke.self)(block.object, nil, nil, CKDatabase.notAuthenticated().objcObject)
        }
        super.finishWithoutAccount()
    }
}

@ObjCClass("CKModifySubscriptionsOperation")
open class CKModifySubscriptionsOperation: CKDatabaseOperation {
    var zone: ZoneState { Zones.state(objcObject) }

    @ObjCMethod("dealloc")
    func deallocZone() {
        Zones.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CKModifySubscriptionsOperation.objCClass.pointer)
    }

    @ObjCMethod("initWithSubscriptionsToSave:subscriptionIDsToDelete:")
    func initialize(subscriptionsToSave: NSObject?, subscriptionIDsToDelete: NSObject?) -> Self { self }

    @ObjCMethod("setSubscriptionsToSave:") func setSubscriptionsToSave(_ subscriptions: NSObject?) {}
    @ObjCMethod("setSubscriptionIDsToDelete:") func setSubscriptionIDsToDelete(_ ids: NSObject?) {}
    @ObjCMethod("modifySubscriptionsCompletionBlock") func modifySubscriptionsCompletionBlock() -> ObjCBlock? { zone.completion }
    @ObjCMethod("setModifySubscriptionsCompletionBlock:") func setModifySubscriptionsCompletionBlock(_ block: ObjCBlock?) { zone.completion = block }

    /// Nothing saved, nothing deleted, and the error.
    override func finishWithoutAccount() {
        if let block = zone.completion {
            typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?,
                                               UnsafeMutableRawPointer?) -> Void
            block.function(as: Invoke.self)(block.object, nil, nil, CKDatabase.notAuthenticated().objcObject)
        }
        super.finishWithoutAccount()
    }
}

@ObjCClass("CKFetchRecordZoneChangesOperation")
open class CKFetchRecordZoneChangesOperation: CKDatabaseOperation {
    var zone: ZoneState { Zones.state(objcObject) }

    @ObjCMethod("dealloc")
    func deallocZone() {
        Zones.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CKFetchRecordZoneChangesOperation.objCClass.pointer)
    }

    @ObjCMethod("initWithRecordZoneIDs:configurationsByRecordZoneID:")
    func initialize(recordZoneIDs: NSObject?, configurationsByRecordZoneID: NSObject?) -> Self {
        setRecordZoneIDs(recordZoneIDs)
        return self
    }

    @ObjCMethod("initWithRecordZoneIDs:optionsByRecordZoneID:")
    func initialize(recordZoneIDs: NSObject?, optionsByRecordZoneID: NSObject?) -> Self {
        setRecordZoneIDs(recordZoneIDs)
        return self
    }

    @ObjCMethod("recordZoneIDs") func recordZoneIDs() -> NSObject? { zone.zoneIDs }
    @ObjCMethod("setRecordZoneIDs:") func setRecordZoneIDs(_ ids: NSObject?) { zone.zoneIDs = ids?.sendCopy() }
    @ObjCMethod("setConfigurationsByRecordZoneID:") func setConfigurationsByRecordZoneID(_ configurations: NSObject?) {}
    @ObjCMethod("setFetchAllChanges:") func setFetchAllChanges(_ all: Bool) {}
    @ObjCMethod("setRecordChangedBlock:") func setRecordChangedBlock(_ block: ObjCBlock?) {}
    @ObjCMethod("setRecordWasChangedBlock:") func setRecordWasChangedBlock(_ block: ObjCBlock?) {}
    @ObjCMethod("setRecordWithIDWasDeletedBlock:") func setRecordWithIDWasDeletedBlock(_ block: ObjCBlock?) {}
    @ObjCMethod("setRecordZoneChangeTokensUpdatedBlock:") func setRecordZoneChangeTokensUpdatedBlock(_ block: ObjCBlock?) {}
    @ObjCMethod("setRecordZoneFetchCompletionBlock:") func setRecordZoneFetchCompletionBlock(_ block: ObjCBlock?) { zone.zoneFetchCompletion = block }
    @ObjCMethod("fetchRecordZoneChangesCompletionBlock") func fetchRecordZoneChangesCompletionBlock() -> ObjCBlock? { zone.completion }
    @ObjCMethod("setFetchRecordZoneChangesCompletionBlock:") func setFetchRecordZoneChangesCompletionBlock(_ block: ObjCBlock?) { zone.completion = block }

    /// No changes: each zone's fetch completes with the error, then the
    /// operation does.
    override func finishWithoutAccount() {
        if let block = zone.zoneFetchCompletion, let ids = zone.zoneIDs {
            // ^(CKRecordZoneID *zoneID, CKServerChangeToken *token, NSData
            // *clientChangeTokenData, BOOL moreComing, NSError *error)
            typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?,
                                               UnsafeMutableRawPointer?, Bool, UnsafeMutableRawPointer?) -> Void
            for index in 0..<ids.sendCount() {
                block.function(as: Invoke.self)(block.object, ids.sendObject(at: index).objcObject, nil, nil, false,
                                                CKDatabase.notAuthenticated().objcObject)
            }
        }
        if let block = zone.completion {
            typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?) -> Void
            block.function(as: Invoke.self)(block.object, CKDatabase.notAuthenticated().objcObject)
        }
        super.finishWithoutAccount()
    }
}

extension NSObject {
    @ObjCMethod("copy") func sendCopy() -> NSObject
    @ObjCMethod("count") func sendCount() -> Int
    @ObjCMethod("objectAtIndex:") func sendObject(at index: Int) -> NSObject
}

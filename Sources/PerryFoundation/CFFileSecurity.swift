import CPerryFoundation
import FoundationEssentials
import PerryObjCInterop

// CFFileSecurity (NSFileSecurity): a file's owner, group, mode and access
// control list, each set or not. Owner, group and mode are POSIX's. There
// are no ACLs here, so a file security never has one: copying it gives
// NULL and setting one fails, though removing it (NULL, or
// kCFFileSecurityRemoveACL) succeeds, as there's none to remove.
//
// The owner and group UUIDs are their own properties, as on Darwin: setting
// an owner or group gives no UUID, and a UUID no ID.
//
// A CFFileSecurityRef is an __NSFileSecurity, the concrete subclass of
// NSFileSecurity (NSFileSecurity.swift), so either API takes either.

final class FileSecurityStorage {
    var owner: UInt32?
    var group: UInt32?
    var mode: UInt16?
    var ownerUUID: UUID?
    var groupUUID: UUID?

    init() {}

    init(copying other: FileSecurityStorage) {
        (owner, group, mode, ownerUUID, groupUUID) = (other.owner, other.group, other.mode, other.ownerUUID, other.groupUUID)
    }

    var effectiveOwnerUUID: UUID? { ownerUUID }
    var effectiveGroupUUID: UUID? { groupUUID }
    var effectiveOwner: UInt32? { owner }
    var effectiveGroup: UInt32? { group }

    func isEqual(to other: FileSecurityStorage) -> Bool {
        effectiveOwner == other.effectiveOwner && effectiveGroup == other.effectiveGroup && mode == other.mode
            && effectiveOwnerUUID == other.effectiveOwnerUUID && effectiveGroupUUID == other.effectiveGroupUUID
    }
}

enum FileSecurities {
    nonisolated(unsafe) static var securityClass: Class!

    static let typeID: UInt = 64

    /// kCFFileSecurityClearOwner, Group, Mode, OwnerUUID, GroupUUID and
    /// AccessControlList.
    static let clearOwner: UInt = 1 << 0, clearGroup: UInt = 1 << 1, clearMode: UInt = 1 << 2
    static let clearOwnerUUID: UInt = 1 << 3, clearGroupUUID: UInt = 1 << 4, clearAccessControlList: UInt = 1 << 5

    /// _FILESEC_REMOVE_ACL, which kCFFileSecurityRemoveACL is.
    nonisolated(unsafe) static let removeACL = UnsafeMutableRawPointer(bitPattern: 1)

    static func storage(_ object: id?) -> FileSecurityStorage? { Storage.get(object, as: FileSecurityStorage.self) }

    /// A new file security (+1).
    static func make(_ storage: FileSecurityStorage) -> id? {
        guard let object = Storage.allocate(UnsafeMutableRawPointer(securityClass)) else { return nil }
        Storage.set(object, storage)
        return object
    }
}

@ObjCClass("__NSFileSecurity")
final class NSCFFileSecurity: NSFileSecurity {
    override class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        FileSecurities.securityClass = cls.storage
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: FileSecurities.securityClass)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { FileSecurities.typeID }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: UnsafeMutableRawPointer?) -> Bool {
        guard let other, other != objcObject else { return other == objcObject }
        guard let mine = FileSecurities.storage(objcObject), let theirs = FileSecurities.storage(other) else { return false }
        return mine.isEqual(to: theirs)
    }

    @ObjCMethod("hash")
    func hash() -> UInt {
        guard let storage = FileSecurities.storage(objcObject) else { return 0 }
        return UInt(storage.effectiveOwner ?? 0) &* 31 &+ UInt(storage.effectiveGroup ?? 0) &* 7 &+ UInt(storage.mode ?? 0)
    }

    /// A new file security (+1) of the same properties.
    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        guard let storage = FileSecurities.storage(objcObject) else { return nil }
        return FileSecurities.make(FileSecurityStorage(copying: storage))
    }

    /// Darwin's: each filesec property, set or (null); the mode in decimal.
    @ObjCMethod("description")
    func description() -> String {
        let address = "0x" + String(UInt(bitPattern: objcObject), radix: 16)
        let storage = FileSecurities.storage(objcObject) ?? FileSecurityStorage()
        func shown<T>(_ value: T?) -> String { value.map { "\($0)" } ?? "(null)" }
        let fields = ["FILESEC_OWNER = \(shown(storage.effectiveOwner))", "FILESEC_GROUP = \(shown(storage.effectiveGroup))",
                      "FILESEC_MODE = \(shown(storage.mode))", "FILESEC_UUID = \(shown(storage.effectiveOwnerUUID?.uuidString))",
                      "FILESEC_GRPUUID = \(shown(storage.effectiveGroupUUID?.uuidString))", "FILESEC_ACL = (null)"]
        return "<FileSecurity \(address)> [\(address)] {\(fields.joined(separator: ", "))}"
    }
}

@c(_CFFileSecurityGetTypeID) public func CFFileSecurityGetTypeID() -> UInt { FileSecurities.typeID }

/// A file security (+1) with no properties set.
@c(_CFFileSecurityCreate)
public func CFFileSecurityCreate(_ allocator: UnsafeRawPointer?) -> id? { FileSecurities.make(FileSecurityStorage()) }

@c(_CFFileSecurityCreateCopy)
public func CFFileSecurityCreateCopy(_ allocator: UnsafeRawPointer?, _ fileSecurity: id?) -> id? {
    guard let storage = FileSecurities.storage(fileSecurity) else { return nil }
    return FileSecurities.make(FileSecurityStorage(copying: storage))
}

/// False, with *owner untouched, when no owner is set.
@c(_CFFileSecurityGetOwner)
public func CFFileSecurityGetOwner(_ fileSecurity: id?, _ owner: UnsafeMutablePointer<UInt32>?) -> Bool {
    guard let value = FileSecurities.storage(fileSecurity)?.effectiveOwner else { return false }
    owner?.pointee = value
    return true
}

@c(_CFFileSecuritySetOwner)
public func CFFileSecuritySetOwner(_ fileSecurity: id?, _ owner: UInt32) -> Bool {
    guard let storage = FileSecurities.storage(fileSecurity) else { return false }
    storage.owner = owner
    return true
}

@c(_CFFileSecurityGetGroup)
public func CFFileSecurityGetGroup(_ fileSecurity: id?, _ group: UnsafeMutablePointer<UInt32>?) -> Bool {
    guard let value = FileSecurities.storage(fileSecurity)?.effectiveGroup else { return false }
    group?.pointee = value
    return true
}

@c(_CFFileSecuritySetGroup)
public func CFFileSecuritySetGroup(_ fileSecurity: id?, _ group: UInt32) -> Bool {
    guard let storage = FileSecurities.storage(fileSecurity) else { return false }
    storage.group = group
    return true
}

/// The mode's permission bits and file type, as mode_t: Darwin's is 16 bits.
@c(_CFFileSecurityGetMode)
public func CFFileSecurityGetMode(_ fileSecurity: id?, _ mode: UnsafeMutablePointer<UInt16>?) -> Bool {
    guard let value = FileSecurities.storage(fileSecurity)?.mode else { return false }
    mode?.pointee = value
    return true
}

@c(_CFFileSecuritySetMode)
public func CFFileSecuritySetMode(_ fileSecurity: id?, _ mode: UInt16) -> Bool {
    guard let storage = FileSecurities.storage(fileSecurity) else { return false }
    storage.mode = mode
    return true
}

/// The owner's UUID (+1), when one is set.
@c(_CFFileSecurityCopyOwnerUUID)
public func CFFileSecurityCopyOwnerUUID(_ fileSecurity: id?, _ ownerUUID: UnsafeMutablePointer<id?>?) -> Bool {
    guard let uuid = FileSecurities.storage(fileSecurity)?.effectiveOwnerUUID else { return false }
    if let ownerUUID { ownerUUID.pointee = NSCFUUID.make(uuid) }
    return true
}

/// NULL unsets the owner's UUID.
@c(_CFFileSecuritySetOwnerUUID)
public func CFFileSecuritySetOwnerUUID(_ fileSecurity: id?, _ ownerUUID: id?) -> Bool {
    guard let storage = FileSecurities.storage(fileSecurity) else { return false }
    guard let ownerUUID else {
        storage.ownerUUID = nil
        return true
    }
    guard let uuid = NSCFUUID.uuid(ownerUUID) else { return false }
    storage.ownerUUID = uuid
    return true
}

/// The group's UUID (+1), when one is set.
@c(_CFFileSecurityCopyGroupUUID)
public func CFFileSecurityCopyGroupUUID(_ fileSecurity: id?, _ groupUUID: UnsafeMutablePointer<id?>?) -> Bool {
    guard let uuid = FileSecurities.storage(fileSecurity)?.effectiveGroupUUID else { return false }
    if let groupUUID { groupUUID.pointee = NSCFUUID.make(uuid) }
    return true
}

/// NULL unsets the group's UUID.
@c(_CFFileSecuritySetGroupUUID)
public func CFFileSecuritySetGroupUUID(_ fileSecurity: id?, _ groupUUID: id?) -> Bool {
    guard let storage = FileSecurities.storage(fileSecurity) else { return false }
    guard let groupUUID else {
        storage.groupUUID = nil
        return true
    }
    guard let uuid = NSCFUUID.uuid(groupUUID) else { return false }
    storage.groupUUID = uuid
    return true
}

/// There are no ACLs here: *accessControlList is NULL, and the answer false,
/// as on Darwin for a file security with none.
@c(_CFFileSecurityCopyAccessControlList)
public func CFFileSecurityCopyAccessControlList(_ fileSecurity: id?, _ accessControlList: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
    accessControlList?.pointee = nil
    return false
}

/// Only removing the ACL (NULL or kCFFileSecurityRemoveACL) succeeds, as
/// there's never one; an ACL can't be set here.
@c(_CFFileSecuritySetAccessControlList)
public func CFFileSecuritySetAccessControlList(_ fileSecurity: id?, _ accessControlList: UnsafeMutableRawPointer?) -> Bool {
    guard FileSecurities.storage(fileSecurity) != nil else { return false }
    return accessControlList == nil || accessControlList == FileSecurities.removeACL
}

/// Unsets the properties of kCFFileSecurityClearOwner (1), Group (2),
/// Mode (4), OwnerUUID (8), GroupUUID (16) and AccessControlList (32).
@c(_CFFileSecurityClearProperties)
public func CFFileSecurityClearProperties(_ fileSecurity: id?, _ clearPropertyMask: UInt) -> Bool {
    guard let storage = FileSecurities.storage(fileSecurity) else { return false }
    if clearPropertyMask & FileSecurities.clearOwner != 0 { storage.owner = nil }
    if clearPropertyMask & FileSecurities.clearGroup != 0 { storage.group = nil }
    if clearPropertyMask & FileSecurities.clearMode != 0 { storage.mode = nil }
    if clearPropertyMask & FileSecurities.clearOwnerUUID != 0 { storage.ownerUUID = nil }
    if clearPropertyMask & FileSecurities.clearGroupUUID != 0 { storage.groupUUID = nil }
    return true
}

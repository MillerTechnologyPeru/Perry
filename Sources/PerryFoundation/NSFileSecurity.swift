import CPerryFoundation
import FoundationEssentials
import PerryObjCInterop

// NSFileSecurity, the class CFFileSecurity is toll-free bridged with: an
// abstract class whose instances are __NSFileSecurity's, as on Darwin, so
// [[NSFileSecurity alloc] init] makes one with nothing set and a
// CFFileSecurityRef is an NSFileSecurity. It copies, and archives under
// NS.filesec as Darwin's does: 72 bytes of the set properties' flags (owner
// 1, group 2, owner UUID 4, group UUID 8, mode 16), the owner, group and mode
// in eight bytes each, the two UUIDs, and eight for an ACL, which there
// never is here.

@ObjCClass("NSFileSecurity")
public class NSFileSecurity: NSObject {
    nonisolated(unsafe) static var fileSecurityClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        fileSecurityClass = cls.storage
    }

    /// The class to make an instance of: the concrete one for this one.
    private static func concrete(_ cls: ObjCClass) -> id? {
        cls.storage == fileSecurityClass ? UnsafeMutableRawPointer(FileSecurities.securityClass) : cls.pointer
    }

    @ObjCClassMethod("alloc")
    static func allocate(_ cls: ObjCClass) -> UnsafeMutableRawPointer? { Storage.allocate(concrete(cls)) }

    @ObjCClassMethod("allocWithZone:")
    static func allocate(_ cls: ObjCClass, zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        Storage.allocate(concrete(cls))
    }

    /// No property set.
    @ObjCMethod("init")
    func initialize() -> Self {
        if FileSecurities.storage(objcObject) == nil { Storage.set(objcObject, FileSecurityStorage()) }
        return self
    }

    // MARK: Coding

    @ObjCClassMethod("supportsSecureCoding") static func supportsSecureCoding() -> Bool { true }

    @ObjCMethod("initWithCoder:")
    func initialize(coder: ObjCObject) -> Self? {
        let data = ObjC.send(coder.id, ObjC.selector("decodeObjectForKey:"), Strings.autoreleased("NS.filesec"))
        guard let data, let storage = FileSecurities.decode([UInt8](DataObjects.data(data))) else { return nil }
        Storage.set(objcObject, storage)
        return self
    }

    @ObjCMethod("encodeWithCoder:")
    func encode(coder: ObjCObject) {
        let bytes = FileSecurities.encode(FileSecurities.storage(objcObject) ?? FileSecurityStorage())
        typealias EncodeObject = @convention(c) (id, SEL, id?, id?) -> Void
        unsafeBitCast(ObjC.msgSend, to: EncodeObject.self)(coder.id, ObjC.selector("encodeObject:forKey:"),
                                                            DataObjects.autoreleased(Data(bytes)), Strings.autoreleased("NS.filesec"))
    }
}

extension FileSecurities {
    /// The flags of NS.filesec's properties.
    static let archivedOwner: UInt64 = 1, archivedGroup: UInt64 = 2, archivedOwnerUUID: UInt64 = 4
    static let archivedGroupUUID: UInt64 = 8, archivedMode: UInt64 = 16

    /// A file security's NS.filesec bytes.
    static func encode(_ storage: FileSecurityStorage) -> [UInt8] {
        var flags: UInt64 = 0
        if storage.owner != nil { flags |= archivedOwner }
        if storage.group != nil { flags |= archivedGroup }
        if storage.ownerUUID != nil { flags |= archivedOwnerUUID }
        if storage.groupUUID != nil { flags |= archivedGroupUUID }
        if storage.mode != nil { flags |= archivedMode }
        var bytes: [UInt8] = []
        func word(_ value: UInt64) { withUnsafeBytes(of: value.littleEndian) { bytes += $0 } }
        func uuid(_ value: UUID?) {
            guard let value else { return bytes += [UInt8](repeating: 0, count: 16) }
            withUnsafeBytes(of: value.uuid) { bytes += $0 }
        }
        word(flags)
        word(UInt64(storage.owner ?? 0))
        word(UInt64(storage.group ?? 0))
        word(UInt64(storage.mode ?? 0))
        uuid(storage.ownerUUID)
        uuid(storage.groupUUID)
        word(0)
        return bytes
    }

    /// The file security NS.filesec's bytes describe; nil for too few.
    static func decode(_ bytes: [UInt8]) -> FileSecurityStorage? {
        guard bytes.count >= 64 else { return nil }
        func word(_ offset: Int) -> UInt64 {
            (0..<8).reduce(UInt64(0)) { $0 | UInt64(bytes[offset + $1]) << (8 * UInt64($1)) }
        }
        func uuid(_ offset: Int) -> UUID {
            let b = Array(bytes[offset..<offset + 16])
            return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
        }
        let flags = word(0)
        let storage = FileSecurityStorage()
        if flags & archivedOwner != 0 { storage.owner = UInt32(truncatingIfNeeded: word(8)) }
        if flags & archivedGroup != 0 { storage.group = UInt32(truncatingIfNeeded: word(16)) }
        if flags & archivedMode != 0 { storage.mode = UInt16(truncatingIfNeeded: word(24)) }
        if flags & archivedOwnerUUID != 0 { storage.ownerUUID = uuid(32) }
        if flags & archivedGroupUUID != 0 { storage.groupUUID = uuid(48) }
        return storage
    }

    /// A file's owner, group and mode (its type's bits too), as
    /// NSURLFileSecurityKey gives them; autoreleased.
    static func autoreleased(owner: UInt32, group: UInt32, mode: UInt16) -> id? {
        let storage = FileSecurityStorage()
        (storage.owner, storage.group, storage.mode) = (owner, group, mode)
        return ObjC.autorelease(make(storage))
    }
}

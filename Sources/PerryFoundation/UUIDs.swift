import CPerryFoundation
import FoundationEssentials
import PerryObjCInterop

/// An NSUUID's value: swift-foundation's UUID.
final class UUIDStorage {
    let uuid: UUID

    init(_ uuid: UUID) {
        self.uuid = uuid
    }
}

enum UUIDs {
    nonisolated(unsafe) static var uuidClass: Class!

    static func uuid(_ object: id?) -> UUID? {
        Storage.get(object, as: UUIDStorage.self)?.uuid
    }

    static func initialize(_ object: id?, _ uuid: UUID?) -> id? {
        guard let object else { return nil }
        guard let uuid else {
            ObjC.release(object)
            return nil
        }
        Storage.set(object, UUIDStorage(uuid))
        return object
    }

    static func install(superclass: Class) {
        uuidClass = NSUUID.defineObjCClass(StorageAllocated.registerObjCMethods).storage
    }
}

/// NSUUID.
@ObjCClass("NSUUID")
public final class NSUUID: NSObject {
    var uuid: UUID? { UUIDs.uuid(objcObject) }

    private func setUUID(_ uuid: UUID?) -> Self? {
        guard let uuid else { return nil }
        Storage.set(objcObject, UUIDStorage(uuid))
        return self
    }

    @ObjCClassMethod("UUID")
    static func make(_ cls: ObjCClass) -> NSUUID? {
        Storage.allocate(cls.pointer).flatMap { NSUUID(objCOwned: $0).setUUID(UUID()) }
    }

    @ObjCMethod("init") func initialize() -> Self? { setUUID(UUID()) }

    @ObjCMethod("initWithUUIDString:")
    func initialize(string: String) -> Self? { setUUID(UUID(uuidString: string)) }

    /// uuid_t, 16 bytes.
    @ObjCMethod("initWithUUIDBytes:")
    func initialize(bytes: UnsafePointer<UInt8>) -> Self? {
        let b = (0..<16).map { bytes[$0] }
        return setUUID(UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                                   b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15])))
    }

    @ObjCMethod("getUUIDBytes:")
    func getBytes(_ bytes: UnsafeMutablePointer<UInt8>) {
        guard let uuid else { return }
        withUnsafeBytes(of: uuid.uuid) { raw in
            for index in 0..<16 { bytes[index] = raw[index] }
        }
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: UUIDs.uuidClass)
    }

    @ObjCMethod("UUIDString") func string() -> String { uuid?.uuidString ?? "" }

    @ObjCMethod("description")
    func description() -> String { "<__NSConcreteUUID \(objcObject)> \(uuid?.uuidString ?? "")" }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: ObjCObject?) -> Bool {
        guard let other, other.is(NSUUID.self) else { return false }
        return other.unsafeCast(to: NSUUID.self).uuid == uuid
    }

    @ObjCMethod("hash") func hash() -> UInt { UInt(bitPattern: uuid?.hashValue ?? 0) }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> NSUUID { self }
}

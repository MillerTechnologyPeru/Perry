import PerryObjCInterop

// CBUUID: a Bluetooth UUID, 16, 32 or 128 bits. The short forms stand for
// UUIDs of the Bluetooth base UUID, 0000xxxx-0000-1000-8000-00805F9B34FB,
// and a 128-bit UUID of that form is shortened, as Darwin does, so that
// both spellings are the same UUID and print alike.

/// A UUID's 16 bytes, and how many of them its short form keeps (2, 4, 16).
struct BluetoothUUID: Hashable, Sendable {
    static let base: [UInt8] = [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x00, 0x80, 0x00, 0x00, 0x80, 0x5F, 0x9B, 0x34, 0xFB]

    let bytes: [UInt8]
    let length: Int

    init(bytes: [UInt8]) {
        switch bytes.count {
        case 2:
            self.bytes = [0, 0] + bytes + Array(Self.base[4...])
            self.length = 2
        case 4:
            self.bytes = bytes + Array(Self.base[4...])
            self.length = bytes[0] == 0 && bytes[1] == 0 ? 2 : 4
        default:
            let full = bytes.count == 16 ? bytes : Array(repeating: 0, count: 16)
            self.bytes = full
            if Array(full[4...]) == Array(Self.base[4...]) {
                self.length = full[0] == 0 && full[1] == 0 ? 2 : 4
            } else {
                self.length = 16
            }
        }
    }

    /// "180D", "0000180D", or "0000180D-0000-1000-8000-00805F9B34FB",
    /// in either case, with or without hyphens.
    init?(string: String) {
        let hex = string.filter { $0 != "-" }
        guard [4, 8, 32].contains(hex.count), hex.allSatisfy(\.isHexDigit) else { return nil }
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        self.init(bytes: bytes)
    }

    /// The short form's bytes.
    var data: [UInt8] {
        switch length {
        case 2: Array(bytes[2..<4])
        case 4: Array(bytes[0..<4])
        default: bytes
        }
    }

    /// The short form, in capitals: "180D", or a hyphenated 128-bit UUID.
    var string: String {
        let hex = data.map { ($0 < 16 ? "0" : "") + String($0, radix: 16, uppercase: true) }.joined()
        guard length == 16 else { return hex }
        let chars = Array(hex)
        return [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { String(chars[$0]) }.joined(separator: "-")
    }

    /// The 128-bit form BlueZ uses, in lower case.
    var bluezString: String {
        let hex = bytes.map { ($0 < 16 ? "0" : "") + String($0, radix: 16) }.joined()
        let chars = Array(hex)
        return [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { String(chars[$0]) }.joined(separator: "-")
    }
}

final class UUIDState: ObjectState {
    var uuid = BluetoothUUID(bytes: [0, 0])
}

@ObjCClass("CBUUID")
open class CBUUID: NSObject {
    static let states = StateTable<UUIDState>()
    var uuid: BluetoothUUID {
        get { CBUUID.states[objcObject].uuid }
        set { CBUUID.states[objcObject].uuid = newValue }
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        CBUUID.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CBUUID.objCClass.pointer)
    }

    static func make(_ uuid: BluetoothUUID) -> CBUUID {
        let object = CBUUID.objCClass.object.newInstance().unsafeCast(to: CBUUID.self)
        object.uuid = uuid
        return object
    }

    /// A string that is not a UUID ends the app, as Darwin's
    /// NSInternalInconsistencyException does.
    @ObjCClassMethod("UUIDWithString:")
    static func make(string: String) -> CBUUID {
        guard let uuid = BluetoothUUID(string: string) else {
            bluetoothFatal("Terminating app due to uncaught exception 'NSInternalInconsistencyException', reason: 'String \(string) does not represent a valid UUID'")
        }
        return make(uuid)
    }

    @ObjCClassMethod("UUIDWithData:")
    static func make(data: NSData) -> CBUUID { make(BluetoothUUID(bytes: data.byteArray)) }

    @ObjCClassMethod("UUIDWithNSUUID:")
    static func make(nsuuid: NSUUID) -> CBUUID { make(BluetoothUUID(string: nsuuid.uuidString()) ?? BluetoothUUID(bytes: [0, 0])) }

    @ObjCMethod("UUIDString") func uuidString() -> String { uuid.string }
    @ObjCMethod("description") func description() -> String { uuid.string }
    @ObjCMethod("data") func data() -> NSData { NSData.of(uuid.data) }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: NSObject?) -> Bool {
        guard let other, other.is(CBUUID.self) else { return false }
        return other.unsafeCast(to: CBUUID.self).uuid.bytes == uuid.bytes
    }

    @ObjCMethod("hash") func hash() -> UInt { UInt(bitPattern: uuid.bytes.hashValue) }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { ObjCRuntime.retain(objcObject) }
}

import DBUS
import PerryObjCInterop

// GATT's attributes: a peripheral's services, their characteristics, and
// the characteristics' descriptors, each standing for a BlueZ object (its
// path). They are made as a peripheral discovers them, and the registry
// finds them again by path when BlueZ reports a new value.

/// The Objective-C objects standing for BlueZ's, by central manager and
/// path: as on Darwin, each manager has peripherals (and their attributes)
/// of its own, so one manager's connection is never another's.
enum Registry {
    static let lock = Lock()
    nonisolated(unsafe) static var peripherals: [String: CBPeripheral] = [:]
    nonisolated(unsafe) static var characteristics: [String: CBCharacteristic] = [:]
    nonisolated(unsafe) static var descriptors: [String: CBDescriptor] = [:]

    static func key(_ manager: UnsafeMutableRawPointer?, _ path: String) -> String {
        "\(UInt(bitPattern: manager))|\(path)"
    }

    /// A manager's peripheral for a device, made the first time it sees it.
    static func peripheral(path: String, manager: UnsafeMutableRawPointer) -> CBPeripheral {
        lock.withLock {
            let key = key(manager, path)
            if let peripheral = peripherals[key] { return peripheral }
            let peripheral = CBPeripheral.objCClass.object.newInstance().unsafeCast(to: CBPeripheral.self)
            peripheral.peripheral.path = path
            peripheral.peripheral.manager = manager
            peripherals[key] = peripheral
            return peripheral
        }
    }

    /// The manager of the peripheral an attribute belongs to.
    static func manager(of peripheral: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        peripheral.flatMap { CBPeer.peerStates[$0].manager }
    }
}

/// A device's stable identifier, from its address: the same peripheral is
/// the same NSUUID from one launch to the next, as on Darwin.
enum Identifiers {
    static func identifier(path: String, address: String?) -> String {
        let hex = (address ?? String(path.split(separator: "/").last ?? "").replacingOccurrences(of: "dev_", with: ""))
            .filter(\.isHexDigit).uppercased()
        let padded = String(repeating: "0", count: max(0, 12 - hex.count)) + hex.suffix(12)
        return "B1E7D0D0-0000-4000-8000-\(padded)"
    }
}

final class AttributeState: ObjectState {
    var path = ""
    var uuid = BluetoothUUID(bytes: [0, 0])
    // A service's.
    var isPrimary = true
    var characteristics: [CBCharacteristic]?
    /// Unretained: a service belongs to its peripheral.
    var peripheral: UnsafeMutableRawPointer?
    // A characteristic's.
    var properties: UInt = 0
    var value: NSData?
    var isNotifying = false
    var descriptors: [CBDescriptor]?
    /// Unretained, as Darwin's are weak.
    var service: UnsafeMutableRawPointer?
    // A descriptor's.
    var characteristic: UnsafeMutableRawPointer?
}

@ObjCClass("CBAttribute")
open class CBAttribute: NSObject {
    static let states = StateTable<AttributeState>()
    var attribute: AttributeState { CBAttribute.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        CBAttribute.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CBAttribute.objCClass.pointer)
    }

    @ObjCMethod("UUID") func uuid() -> CBUUID { CBUUID.make(attribute.uuid) }
}

@ObjCClass("CBService")
open class CBService: CBAttribute {
    static func make(path: String, properties: [String: DBusValue], peripheral: CBPeripheral) -> CBService {
        let service = CBService.objCClass.object.newInstance().unsafeCast(to: CBService.self)
        let state = service.attribute
        state.path = path
        state.uuid = properties["UUID"]?.stringValue.flatMap(BluetoothUUID.init(string:)) ?? state.uuid
        state.isPrimary = properties["Primary"]?.boolValue ?? true
        state.peripheral = peripheral.objcObject
        return service
    }

    @ObjCMethod("isPrimary") func isPrimary() -> Bool { attribute.isPrimary }
    @ObjCMethod("peripheral") func peripheral() -> CBPeripheral? { attribute.peripheral.map { CBPeripheral(objcObject: $0, ownership: .retain) } }
    @ObjCMethod("characteristics") func characteristics() -> NSMutableArray? { attribute.characteristics.map { NSMutableArray.of($0) } }
    @ObjCMethod("includedServices") func includedServices() -> NSMutableArray? { nil }
    @ObjCMethod("description") func description() -> String {
        "<CBService: \(objcObject), isPrimary = \(attribute.isPrimary ? "YES" : "NO"), UUID = \(attribute.uuid.string)>"
    }
}

/// CBCharacteristicProperties.
enum CharacteristicProperties {
    static let flags: [(String, UInt)] = [
        ("broadcast", 0x01), ("read", 0x02), ("write-without-response", 0x04), ("write", 0x08),
        ("notify", 0x10), ("indicate", 0x20), ("authenticated-signed-writes", 0x40), ("extended-properties", 0x80),
        ("encrypt-notify", 0x100), ("encrypt-indicate", 0x200),
    ]

    static func properties(_ flags: [String]) -> UInt {
        Self.flags.reduce(0) { flags.contains($1.0) ? $0 | $1.1 : $0 }
    }
}

@ObjCClass("CBCharacteristic")
open class CBCharacteristic: CBAttribute {
    static func make(path: String, properties: [String: DBusValue], service: CBService) -> CBCharacteristic {
        let characteristic = CBCharacteristic.objCClass.object.newInstance().unsafeCast(to: CBCharacteristic.self)
        let state = characteristic.attribute
        state.path = path
        state.uuid = properties["UUID"]?.stringValue.flatMap(BluetoothUUID.init(string:)) ?? state.uuid
        state.properties = CharacteristicProperties.properties(properties["Flags"]?.stringArray ?? [])
        state.isNotifying = properties["Notifying"]?.boolValue ?? false
        state.value = properties["Value"]?.bytes.map(NSData.of)
        state.service = service.objcObject
        let manager = Registry.manager(of: service.attribute.peripheral)
        Registry.lock.withLock { Registry.characteristics[Registry.key(manager, path)] = characteristic }
        return characteristic
    }

    @ObjCMethod("service") func service() -> CBService? { attribute.service.map { CBService(objcObject: $0, ownership: .retain) } }
    @ObjCMethod("properties") func properties() -> UInt { attribute.properties }
    @ObjCMethod("value") func value() -> NSData? { attribute.value }
    @ObjCMethod("descriptors") func descriptors() -> NSMutableArray? { attribute.descriptors.map { NSMutableArray.of($0) } }
    @ObjCMethod("isNotifying") func isNotifying() -> Bool { attribute.isNotifying }
    @ObjCMethod("isBroadcasted") func isBroadcasted() -> Bool { false }
    @ObjCMethod("description") func description() -> String {
        "<CBCharacteristic: \(objcObject), UUID = \(attribute.uuid.string), properties = 0x\(String(attribute.properties, radix: 16, uppercase: true)), notifying = \(attribute.isNotifying ? "YES" : "NO")>"
    }

    /// The peripheral it belongs to.
    var owner: CBPeripheral? { service()?.peripheral() }
}

@ObjCClass("CBDescriptor")
open class CBDescriptor: CBAttribute {
    static func make(path: String, properties: [String: DBusValue], characteristic: CBCharacteristic) -> CBDescriptor {
        let descriptor = CBDescriptor.objCClass.object.newInstance().unsafeCast(to: CBDescriptor.self)
        let state = descriptor.attribute
        state.path = path
        state.uuid = properties["UUID"]?.stringValue.flatMap(BluetoothUUID.init(string:)) ?? state.uuid
        state.value = properties["Value"]?.bytes.map(NSData.of)
        state.characteristic = characteristic.objcObject
        let manager = characteristic.service().flatMap { Registry.manager(of: $0.attribute.peripheral) }
        Registry.lock.withLock { Registry.descriptors[Registry.key(manager, path)] = descriptor }
        return descriptor
    }

    @ObjCMethod("characteristic") func characteristic() -> CBCharacteristic? {
        attribute.characteristic.map { CBCharacteristic(objcObject: $0, ownership: .retain) }
    }

    @ObjCMethod("value") func value() -> NSObject? { attribute.value }

    /// The peripheral it belongs to.
    var owner: CBPeripheral? { characteristic()?.owner }
}

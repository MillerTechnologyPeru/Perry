import DBUS
import PerryObjCInterop

// CBPeripheral: a BlueZ device (org.bluez.Device1) and its GATT database,
// which BlueZ resolves on connecting. Discovering, reading, writing and
// notifying are BlueZ's methods, each answered on the queue of the
// peripheral's central manager, to its delegate. A nil attribute does
// nothing, as on Darwin.

/// CBPeripheralState.
enum PeripheralState {
    static let disconnected = 0, connecting = 1, connected = 2, disconnecting = 3
}

final class PeerState: ObjectState {
    var path = ""
    var address: String?
    var name: String?
    var rssi: Int?
    var state = PeripheralState.disconnected
    var services: [CBService]?
    /// Unretained, as Darwin's is weak.
    var delegate: UnsafeMutableRawPointer?
    /// The central manager that last found or connected it; unretained.
    var manager: UnsafeMutableRawPointer?
    /// Disconnecting was asked for, so it is no error.
    var cancelling = false
    /// Characteristics being read, whose new value the read reports, not a
    /// notification.
    var reading: Set<String> = []
    /// The connection's ATT MTU, if BlueZ gives it.
    var mtu: Int?
}

@ObjCClass("CBPeer")
open class CBPeer: NSObject {
    static let peerStates = StateTable<PeerState>()
    var peripheral: PeerState { CBPeer.peerStates[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        CBPeer.peerStates.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CBPeer.objCClass.pointer)
    }

    var identifierString: String { Identifiers.identifier(path: peripheral.path, address: peripheral.address) }

    @ObjCMethod("identifier") func identifier() -> NSUUID? { NSUUID.make(identifierString) }
}

@ObjCClass("CBPeripheral")
open class CBPeripheral: CBPeer {
    /// The queue its delegate hears on: its manager's.
    var queue: UnsafeMutableRawPointer? {
        peripheral.manager.map { CBCentralManager(objcObject: $0, ownership: .retain) }?.central.queue
    }

    func delegateObject() -> NSObject? { peripheral.delegate.map { NSObject($0) } }

    /// Runs `body` with the delegate, on the queue, if it answers `selector`.
    func tell(_ selector: String, _ body: @escaping (NSObject) -> Void) {
        let owner = Unchecked(self)
        Dispatch.on(queue) {
            guard let delegate = owner.value.delegateObject(), delegate.responds(to: selector) else { return }
            body(delegate)
        }
    }

    // MARK: Properties

    @ObjCMethod("name") func name() -> String? { peripheral.name }
    @ObjCMethod("state") func state() -> Int { peripheral.state }
    @ObjCMethod("services") func services() -> NSMutableArray? { peripheral.services.map { NSMutableArray.of($0) } }
    @ObjCMethod("delegate") func delegate() -> NSObject? { delegateObject() }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { peripheral.delegate = delegate?.objcObject }
    @ObjCMethod("RSSI") func rssi() -> NSNumber? { peripheral.rssi.map { NSNumber.make(integer: $0) } }
    @ObjCMethod("isConnected") func isConnected() -> Bool { peripheral.state == PeripheralState.connected }
    @ObjCMethod("canSendWriteWithoutResponse") func canSendWriteWithoutResponse() -> Bool { true }
    @ObjCMethod("ancsAuthorized") func ancsAuthorized() -> Bool { false }
    /// iOS 5's CFUUIDRef identifier, which no peripheral has before it
    /// connects.
    @ObjCMethod("UUID") func cfUUID() -> UnsafeMutableRawPointer? { nil }

    /// CBCharacteristicWriteType: with response 0, without 1.
    @ObjCMethod("maximumWriteValueLengthForType:")
    func maximumWriteValueLength(for type: Int) -> UInt { type == 1 ? UInt(max(20, (peripheral.mtu ?? 23) - 3)) : 512 }

    @ObjCMethod("description") func description() -> String {
        let states = ["disconnected", "connecting", "connected", "disconnecting"]
        return "<CBPeripheral: \(objcObject), identifier = \(identifierString), name = \(peripheral.name ?? "(null)"), mtu = \(peripheral.mtu ?? 23), state = \(states[peripheral.state])>"
    }

    // MARK: Discovery

    @ObjCMethod("discoverServices:")
    func discoverServices(_ uuids: NSObject?) {
        let wanted = uuids?.uuids
        let owner = Unchecked(self), path = peripheral.path
        Task {
            let objects = await BlueZ.shared.objects(under: path)
            Dispatch.on(owner.value.queue) {
                let peripheral = owner.value
                var services = peripheral.peripheral.services ?? []
                for (servicePath, interfaces) in objects.sorted(by: { $0.key < $1.key }) {
                    guard let properties = interfaces[BlueZInterface.service] else { continue }
                    let uuid = properties["UUID"]?.stringValue.flatMap(BluetoothUUID.init(string:))
                    guard wanted == nil || wanted!.isEmpty || uuid.map(wanted!.contains) == true,
                          !services.contains(where: { $0.attribute.path == servicePath }) else { continue }
                    services.append(CBService.make(path: servicePath, properties: properties, peripheral: peripheral))
                }
                peripheral.peripheral.services = services
                guard let delegate = peripheral.delegateObject(), delegate.responds(to: "peripheral:didDiscoverServices:") else { return }
                delegate.sendPeripheral(peripheral, didDiscoverServices: nil)
            }
        }
    }

    /// BlueZ does not expose included services.
    @ObjCMethod("discoverIncludedServices:forService:")
    func discoverIncludedServices(_ uuids: NSObject?, for service: CBService?) {
        guard let service else { return }
        let owner = Unchecked(self), target = Unchecked(service)
        tell("peripheral:didDiscoverIncludedServicesForService:error:") {
            $0.sendPeripheral(owner.value, didDiscoverIncludedServicesFor: target.value, error: nil)
        }
    }

    @ObjCMethod("discoverCharacteristics:forService:")
    func discoverCharacteristics(_ uuids: NSObject?, for service: CBService?) {
        guard let service else { return }
        let wanted = uuids?.uuids
        let owner = Unchecked(self), target = Unchecked(service), path = peripheral.path, servicePath = service.attribute.path
        Task {
            let objects = await BlueZ.shared.objects(under: path)
            Dispatch.on(owner.value.queue) {
                let service = target.value
                var characteristics = service.attribute.characteristics ?? []
                for (characteristicPath, interfaces) in objects.sorted(by: { $0.key < $1.key }) {
                    guard let properties = interfaces[BlueZInterface.characteristic],
                          properties["Service"]?.pathValue == servicePath else { continue }
                    let uuid = properties["UUID"]?.stringValue.flatMap(BluetoothUUID.init(string:))
                    guard wanted == nil || wanted!.isEmpty || uuid.map(wanted!.contains) == true,
                          !characteristics.contains(where: { $0.attribute.path == characteristicPath }) else { continue }
                    if let mtu = properties["MTU"]?.intValue { owner.value.peripheral.mtu = mtu }
                    characteristics.append(CBCharacteristic.make(path: characteristicPath, properties: properties, service: service))
                }
                service.attribute.characteristics = characteristics
                guard let delegate = owner.value.delegateObject(),
                      delegate.responds(to: "peripheral:didDiscoverCharacteristicsForService:error:") else { return }
                delegate.sendPeripheral(owner.value, didDiscoverCharacteristicsFor: service, error: nil)
            }
        }
    }

    @ObjCMethod("discoverDescriptorsForCharacteristic:")
    func discoverDescriptors(for characteristic: CBCharacteristic?) {
        guard let characteristic else { return }
        let owner = Unchecked(self), target = Unchecked(characteristic), path = peripheral.path
        let characteristicPath = characteristic.attribute.path
        Task {
            let objects = await BlueZ.shared.objects(under: path)
            Dispatch.on(owner.value.queue) {
                let characteristic = target.value
                var descriptors = characteristic.attribute.descriptors ?? []
                for (descriptorPath, interfaces) in objects.sorted(by: { $0.key < $1.key }) {
                    guard let properties = interfaces[BlueZInterface.descriptor],
                          properties["Characteristic"]?.pathValue == characteristicPath,
                          !descriptors.contains(where: { $0.attribute.path == descriptorPath }) else { continue }
                    descriptors.append(CBDescriptor.make(path: descriptorPath, properties: properties, characteristic: characteristic))
                }
                characteristic.attribute.descriptors = descriptors
                guard let delegate = owner.value.delegateObject(),
                      delegate.responds(to: "peripheral:didDiscoverDescriptorsForCharacteristic:error:") else { return }
                delegate.sendPeripheral(owner.value, didDiscoverDescriptorsFor: characteristic, error: nil)
            }
        }
    }

    // MARK: Values

    @ObjCMethod("readValueForCharacteristic:")
    func readValue(for characteristic: CBCharacteristic?) {
        guard let characteristic else { return }
        let owner = Unchecked(self), target = Unchecked(characteristic), path = characteristic.attribute.path
        peripheral.reading.insert(path)
        Task {
            let result = await Result { try await BlueZ.shared.call(path, BlueZInterface.characteristic, "ReadValue",
                                                                    [.dictionary([:])], signature: "a{sv}") }
            Dispatch.on(owner.value.queue) {
                let characteristic = target.value
                owner.value.peripheral.reading.remove(path)
                var error: NSError?
                switch result {
                case .success(let values): characteristic.attribute.value = NSData.of(values.first?.bytes ?? [])
                case .failure(let failure): error = BluetoothErrors.error(failure, reading: true)
                }
                guard let delegate = owner.value.delegateObject(),
                      delegate.responds(to: "peripheral:didUpdateValueForCharacteristic:error:") else { return }
                delegate.sendPeripheral(owner.value, didUpdateValueFor: characteristic, error: error)
            }
        }
    }

    /// With response (type 0) the delegate hears when it is written;
    /// without, nothing.
    @ObjCMethod("writeValue:forCharacteristic:type:")
    func writeValue(_ data: NSData?, for characteristic: CBCharacteristic?, type: Int) {
        guard let data, let characteristic else { return }
        let owner = Unchecked(self), target = Unchecked(characteristic), path = characteristic.attribute.path
        let bytes = data.byteArray
        let options: DBusValue = .dictionary([.string("type"): .variant(DBusVariant(.string(type == 1 ? "command" : "request")))])
        Task {
            let result = await Result { try await BlueZ.shared.call(path, BlueZInterface.characteristic, "WriteValue",
                                                                    [.byteArray(bytes), options], signature: "aya{sv}") }
            guard type != 1 else { return }
            Dispatch.on(owner.value.queue) {
                var error: NSError?
                if case .failure(let failure) = result { error = BluetoothErrors.error(failure, reading: false) }
                guard let delegate = owner.value.delegateObject(),
                      delegate.responds(to: "peripheral:didWriteValueForCharacteristic:error:") else { return }
                delegate.sendPeripheral(owner.value, didWriteValueFor: target.value, error: error)
            }
        }
    }

    @ObjCMethod("setNotifyValue:forCharacteristic:")
    func setNotifyValue(_ enabled: Bool, for characteristic: CBCharacteristic?) {
        guard let characteristic else { return }
        let owner = Unchecked(self), target = Unchecked(characteristic), path = characteristic.attribute.path
        Task {
            let result = await Result { try await BlueZ.shared.call(path, BlueZInterface.characteristic,
                                                                    enabled ? "StartNotify" : "StopNotify") }
            Dispatch.on(owner.value.queue) {
                var error: NSError?
                switch result {
                case .success: target.value.attribute.isNotifying = enabled
                case .failure(let failure): error = BluetoothErrors.error(failure, reading: true)
                }
                guard let delegate = owner.value.delegateObject(),
                      delegate.responds(to: "peripheral:didUpdateNotificationStateForCharacteristic:error:") else { return }
                delegate.sendPeripheral(owner.value, didUpdateNotificationStateFor: target.value, error: error)
            }
        }
    }

    @ObjCMethod("readValueForDescriptor:")
    func readValue(for descriptor: CBDescriptor?) {
        guard let descriptor else { return }
        let owner = Unchecked(self), target = Unchecked(descriptor), path = descriptor.attribute.path
        Task {
            let result = await Result { try await BlueZ.shared.call(path, BlueZInterface.descriptor, "ReadValue",
                                                                    [.dictionary([:])], signature: "a{sv}") }
            Dispatch.on(owner.value.queue) {
                var error: NSError?
                switch result {
                case .success(let values): target.value.attribute.value = NSData.of(values.first?.bytes ?? [])
                case .failure(let failure): error = BluetoothErrors.error(failure, reading: true)
                }
                guard let delegate = owner.value.delegateObject(),
                      delegate.responds(to: "peripheral:didUpdateValueForDescriptor:error:") else { return }
                delegate.sendPeripheral(owner.value, didUpdateValueFor: target.value, error: error)
            }
        }
    }

    @ObjCMethod("writeValue:forDescriptor:")
    func writeValue(_ data: NSData?, for descriptor: CBDescriptor?) {
        guard let data, let descriptor else { return }
        let owner = Unchecked(self), target = Unchecked(descriptor), path = descriptor.attribute.path
        let bytes = data.byteArray
        Task {
            let result = await Result { try await BlueZ.shared.call(path, BlueZInterface.descriptor, "WriteValue",
                                                                    [.byteArray(bytes), .dictionary([:])], signature: "aya{sv}") }
            Dispatch.on(owner.value.queue) {
                var error: NSError?
                if case .failure(let failure) = result { error = BluetoothErrors.error(failure, reading: false) }
                guard let delegate = owner.value.delegateObject(),
                      delegate.responds(to: "peripheral:didWriteValueForDescriptor:error:") else { return }
                delegate.sendPeripheral(owner.value, didWriteValueFor: target.value, error: error)
            }
        }
    }

    /// The last RSSI BlueZ heard, which it reports while discovering.
    @ObjCMethod("readRSSI")
    func readRSSI() {
        let owner = Unchecked(self), path = peripheral.path
        Task {
            let rssi = await BlueZ.shared.properties(path, BlueZInterface.device)?["RSSI"]?.intValue
            Dispatch.on(owner.value.queue) {
                let peripheral = owner.value
                if let rssi { peripheral.peripheral.rssi = rssi }
                let value = NSNumber.make(integer: peripheral.peripheral.rssi ?? 127)
                guard let delegate = peripheral.delegateObject() else { return }
                if delegate.responds(to: "peripheral:didReadRSSI:error:") {
                    delegate.sendPeripheral(peripheral, didReadRSSI: value, error: nil)
                } else if delegate.responds(to: "peripheralDidUpdateRSSI:error:") {
                    delegate.sendPeripheralDidUpdateRSSI(peripheral, error: nil)
                }
            }
        }
    }

    // MARK: BlueZ's reports

    /// A characteristic's new value, notified or indicated.
    func valueChanged(_ characteristic: CBCharacteristic, bytes: [UInt8]) {
        guard !peripheral.reading.contains(characteristic.attribute.path) else { return }
        characteristic.attribute.value = NSData.of(bytes)
        guard characteristic.attribute.isNotifying, let delegate = delegateObject(),
              delegate.responds(to: "peripheral:didUpdateValueForCharacteristic:error:") else { return }
        delegate.sendPeripheral(self, didUpdateValueFor: characteristic, error: nil)
    }

    func nameChanged(_ name: String) {
        peripheral.name = name
        guard let delegate = delegateObject(), delegate.responds(to: "peripheralDidUpdateName:") else { return }
        delegate.sendPeripheralDidUpdateName(self)
    }

    /// Forgets the GATT database, which BlueZ resolves anew on connecting.
    func disconnected() {
        let state = peripheral
        state.state = PeripheralState.disconnected
        state.services = nil
        state.reading = []
        Registry.lock.withLock {
            Registry.characteristics = Registry.characteristics.filter { !$0.key.hasPrefix(state.path + "/") }
            Registry.descriptors = Registry.descriptors.filter { !$0.key.hasPrefix(state.path + "/") }
        }
    }
}

extension Result where Failure == Error {
    init(catching body: () async throws -> Success) async {
        do { self = .success(try await body()) } catch { self = .failure(error) }
    }
}

/// CoreBluetooth's errors for BlueZ's.
enum BluetoothErrors {
    // CBError.
    static let unknown = 0, invalidParameters = 1, invalidHandle = 2, notConnected = 3, operationCancelled = 5
    static let connectionTimeout = 6, peripheralDisconnected = 7, connectionFailed = 10
    // CBATTError.
    static let readNotPermitted = 2, writeNotPermitted = 3, requestNotSupported = 6
    static let insufficientAuthorization = 8, invalidAttributeValueLength = 13, insufficientEncryption = 15

    /// An error, described by BlueZ's error when one caused it.
    static func cb(_ code: Int, _ cause: Error? = nil) -> NSError { make(Constants.CBErrorDomain, code, cause) }
    static func att(_ code: Int, _ cause: Error? = nil) -> NSError { make(Constants.CBATTErrorDomain, code, cause) }

    private static func make(_ domain: String, _ code: Int, _ cause: Error?) -> NSError {
        guard let cause = cause as? BlueZError else { return NSError.make(domain: domain, code: code, userInfo: nil) }
        let userInfo = NSMutableDictionary.empty()
        userInfo.set(string: cause.message.isEmpty ? cause.name : "\(cause.name): \(cause.message)", forKey: "NSLocalizedDescription")
        return NSError.make(domain: domain, code: code, userInfo: userInfo)
    }

    static func error(_ error: Error, reading: Bool) -> NSError {
        guard let cause = error as? BlueZError else { return cb(unknown) }
        switch cause.name {
        case "org.bluez.Error.NotPermitted": return att(reading ? readNotPermitted : writeNotPermitted, cause)
        case "org.bluez.Error.NotAuthorized": return att(insufficientAuthorization, cause)
        case "org.bluez.Error.NotSupported": return att(requestNotSupported, cause)
        case "org.bluez.Error.InvalidValueLength": return att(invalidAttributeValueLength, cause)
        case "org.bluez.Error.InvalidOffset": return att(7, cause)
        case "org.bluez.Error.NotConnected": return cb(notConnected, cause)
        default: return cb(unknown, cause)
        }
    }
}

/// CBPeripheralDelegate's messages.
extension NSObject {
    @ObjCMethod("peripheral:didDiscoverServices:")
    func sendPeripheral(_ peripheral: CBPeripheral, didDiscoverServices error: NSError?)

    @ObjCMethod("peripheral:didDiscoverIncludedServicesForService:error:")
    func sendPeripheral(_ peripheral: CBPeripheral, didDiscoverIncludedServicesFor service: CBService, error: NSError?)

    @ObjCMethod("peripheral:didDiscoverCharacteristicsForService:error:")
    func sendPeripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: NSError?)

    @ObjCMethod("peripheral:didDiscoverDescriptorsForCharacteristic:error:")
    func sendPeripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: NSError?)

    @ObjCMethod("peripheral:didUpdateValueForCharacteristic:error:")
    func sendPeripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: NSError?)

    @ObjCMethod("peripheral:didWriteValueForCharacteristic:error:")
    func sendPeripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: NSError?)

    @ObjCMethod("peripheral:didUpdateNotificationStateForCharacteristic:error:")
    func sendPeripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: NSError?)

    @ObjCMethod("peripheral:didUpdateValueForDescriptor:error:")
    func sendPeripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: NSError?)

    @ObjCMethod("peripheral:didWriteValueForDescriptor:error:")
    func sendPeripheral(_ peripheral: CBPeripheral, didWriteValueFor descriptor: CBDescriptor, error: NSError?)

    @ObjCMethod("peripheral:didReadRSSI:error:")
    func sendPeripheral(_ peripheral: CBPeripheral, didReadRSSI rssi: NSNumber, error: NSError?)

    @ObjCMethod("peripheralDidUpdateRSSI:error:")
    func sendPeripheralDidUpdateRSSI(_ peripheral: CBPeripheral, error: NSError?)

    @ObjCMethod("peripheralDidUpdateName:")
    func sendPeripheralDidUpdateName(_ peripheral: CBPeripheral)
}

import DBUS
import Glibc
import PerryObjCInterop

// The managers. A central manager uses BlueZ's first adapter: powered on
// or off as BlueZ says, and unsupported with no adapter or no BlueZ. It
// scans with BlueZ's LE discovery, reporting each device BlueZ hears
// advertise (once per scan unless duplicates are allowed), and connects
// with BlueZ's Connect, reporting the connection once BlueZ has resolved
// the device's services. A peripheral manager is unsupported: Perry does
// not advertise.

/// CBManagerState.
enum ManagerState {
    static let unknown = 0, resetting = 1, unsupported = 2, unauthorized = 3, poweredOff = 4, poweredOn = 5
}

final class CentralState: ObjectState {
    /// Unretained, as Darwin's is weak.
    var delegate: UnsafeMutableRawPointer?
    /// The delegate's queue, retained; nil for the main queue.
    var queue: UnsafeMutableRawPointer?
    var state = ManagerState.unknown
    var adapter: String?
    var scanning = false
    var allowDuplicates = false
    var scanServices: [BluetoothUUID] = []
    /// Devices reported in this scan.
    var reported: Set<String> = []
    /// The latest of each device's repeat sightings since they were last
    /// reported, and whether reporting them is scheduled.
    var repeats: [String: [String: DBusValue]] = [:]
    var repeatsScheduled = false
    var observer: Int?
    /// The last command sent to BlueZ: each waits for the one before, as
    /// BlueZ aborts a connection that starts while discovery is stopping.
    var last: Task<Void, Never>?

    /// Runs `body` after the commands before it.
    func command(_ body: @escaping @Sendable () async -> Void) {
        let previous = last
        last = Task {
            await previous?.value
            await body()
        }
    }
}

@ObjCClass("CBManager")
open class CBManager: NSObject {
    /// CBManagerAuthorization: allowed always 3.
    @ObjCClassMethod("authorization") static func classAuthorization() -> Int { 3 }
    @ObjCMethod("authorization") func authorization() -> Int { 3 }
}

@ObjCClass("CBCentralManager")
open class CBCentralManager: CBManager {
    static let states = StateTable<CentralState>()
    var central: CentralState { CBCentralManager.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        let state = central
        Centrals.remove(objcObject)
        if let observer = state.observer { Task { await BlueZ.shared.removeObserver(observer) } }
        if let queue = state.queue { Dispatch.release(queue) }
        CBCentralManager.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CBCentralManager.objCClass.pointer)
    }

    @ObjCMethod("init") func initialize() -> Self { initialize(delegate: nil, queue: nil, options: nil) }

    @ObjCMethod("initWithDelegate:queue:")
    func initialize(delegate: NSObject?, queue: UnsafeMutableRawPointer?) -> Self { initialize(delegate: delegate, queue: queue, options: nil) }

    @ObjCMethod("initWithDelegate:queue:options:")
    func initialize(delegate: NSObject?, queue: UnsafeMutableRawPointer?, options: NSObject?) -> Self {
        let state = central
        state.delegate = delegate?.objcObject
        if let queue {
            Dispatch.retain(queue)
            state.queue = queue
        }
        // The manager learns BlueZ's state, then hears of every change.
        let owner = Unchecked(objcObject)
        Task {
            let token = await BlueZ.shared.observe { event, current in
                let event = Unchecked(event), current = Unchecked(current)
                guard let manager = Centrals.alive(owner.value) else { return }
                Dispatch.on(manager.central.queue) { manager.handle(event.value, current: current.value) }
            }
            let adapter = await BlueZ.shared.adapter()
            guard let manager = Centrals.alive(owner.value) else {
                await BlueZ.shared.removeObserver(token)
                return
            }
            let path = adapter?.path, powered = adapter?.properties["Powered"]?.boolValue
            Dispatch.on(manager.central.queue) {
                manager.central.observer = token
                manager.central.adapter = path
                manager.update(path == nil ? ManagerState.unsupported : powered == true ? ManagerState.poweredOn : ManagerState.poweredOff)
            }
        }
        Centrals.add(self)
        return self
    }

    // MARK: State

    @ObjCMethod("state") func state() -> Int { central.state }
    @ObjCMethod("isScanning") func isScanning() -> Bool { central.scanning }
    @ObjCMethod("delegate") func delegate() -> NSObject? { central.delegate.map { NSObject($0) } }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { central.delegate = delegate?.objcObject }

    private func update(_ state: Int) {
        guard state != central.state else { return }
        central.state = state
        if state != ManagerState.poweredOn {
            central.scanning = false
            for peripheral in Registry.lock.withLock({ Array(Registry.peripherals.values) })
            where peripheral.peripheral.manager == objcObject && peripheral.peripheral.state != PeripheralState.disconnected {
                peripheral.disconnected()
            }
        }
        guard let delegate = delegate(), delegate.responds(to: "centralManagerDidUpdateState:") else { return }
        delegate.sendCentralManagerDidUpdateState(self)
    }

    /// Commands need the adapter powered on, as on Darwin, which logs the
    /// misuse and ignores them.
    private func poweredOn(_ command: String) -> Bool {
        guard central.state == ManagerState.poweredOn else {
            let line = "perry: CoreBluetooth: API MISUSE: <CBCentralManager: \(objcObject)> can only accept this command while in the powered on state (\(command))\n"
            line.withCString { _ = write(2, $0, strlen($0)) }
            return false
        }
        return true
    }

    // MARK: Scanning

    @ObjCMethod("scanForPeripheralsWithServices:options:")
    func scanForPeripherals(withServices services: NSObject?, options: NSObject?) {
        guard poweredOn("scanForPeripheralsWithServices:options:"), let adapter = central.adapter else { return }
        let state = central
        state.scanning = true
        state.reported = []
        state.repeats = [:]
        state.allowDuplicates = options?.option(Constants.CBCentralManagerScanOptionAllowDuplicatesKey)?
            .unsafeCast(to: NSNumber.self).boolValue() ?? false
        state.scanServices = services?.uuids ?? []
        var filter: [DBusValue: DBusValue] = [
            .string("Transport"): .variant(DBusVariant(.string("le"))),
            .string("DuplicateData"): .variant(DBusVariant(.boolean(state.allowDuplicates))),
        ]
        if !state.scanServices.isEmpty {
            filter[.string("UUIDs")] = .variant(DBusVariant(signature: "as", value: .array(state.scanServices.map { .string($0.bluezString) })))
        }
        let body: [DBusValue] = [.dictionary(filter)]
        state.command {
            _ = try? await BlueZ.shared.call(adapter, BlueZInterface.adapter, "SetDiscoveryFilter", body, signature: "a{sv}")
            _ = try? await BlueZ.shared.call(adapter, BlueZInterface.adapter, "StartDiscovery")
        }
    }

    @ObjCMethod("scanForPeripheralsWithServices:")
    func scanForPeripherals(withServices services: NSObject?) { scanForPeripherals(withServices: services, options: nil) }

    @ObjCMethod("stopScan")
    func stopScan() {
        guard central.scanning, let adapter = central.adapter else { return }
        central.scanning = false
        central.command { _ = try? await BlueZ.shared.call(adapter, BlueZInterface.adapter, "StopDiscovery") }
    }

    /// Reports a device BlueZ has heard advertise, if this scan wants it.
    private func discovered(_ path: String, _ device: [String: DBusValue]) {
        let state = central
        guard state.scanning, let rssi = device["RSSI"]?.intValue,
              state.allowDuplicates || !state.reported.contains(path) else { return }
        let services = device["UUIDs"]?.stringArray.compactMap(BluetoothUUID.init(string:)) ?? []
        guard state.scanServices.isEmpty || services.contains(where: state.scanServices.contains) else { return }
        guard state.reported.insert(path).inserted else { return scheduleRepeat(path, device) }
        report(path, device, rssi: rssi, services: services)
    }

    /// Keeps a device's repeat sighting to report with the others, together
    /// once a second: BlueZ passes on each advertisement it hears, dozens a
    /// second with many devices nearby, and each report may redraw the app.
    private func scheduleRepeat(_ path: String, _ device: [String: DBusValue]) {
        let state = central
        state.repeats[path] = device
        guard !state.repeatsScheduled else { return }
        state.repeatsScheduled = true
        let owner = Unchecked(objcObject)
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let manager = Centrals.alive(owner.value) else { return }
            Dispatch.on(manager.central.queue) { manager.reportRepeats() }
        }
    }

    private func reportRepeats() {
        let state = central
        state.repeatsScheduled = false
        let repeats = state.repeats
        state.repeats = [:]
        guard state.scanning else { return }
        for (path, device) in repeats {
            guard let rssi = device["RSSI"]?.intValue else { continue }
            report(path, device, rssi: rssi, services: device["UUIDs"]?.stringArray.compactMap(BluetoothUUID.init(string:)) ?? [])
        }
    }

    private func report(_ path: String, _ device: [String: DBusValue], rssi: Int, services: [BluetoothUUID]) {
        let peripheral = Registry.peripheral(path: path, manager: objcObject)
        let peer = peripheral.peripheral
        peer.address = device["Address"]?.stringValue
        peer.name = device["Name"]?.stringValue ?? peer.name
        peer.rssi = rssi
        guard let delegate = delegate(), delegate.responds(to: "centralManager:didDiscoverPeripheral:advertisementData:RSSI:") else { return }
        delegate.sendCentralManager(self, didDiscover: peripheral, advertisementData: Advertisement.data(device, services: services),
                                    rssi: NSNumber.make(integer: rssi))
    }

    // MARK: Connections

    @ObjCMethod("connectPeripheral:options:")
    func connect(_ peripheral: CBPeripheral?, options: NSObject?) {
        guard let peripheral, poweredOn("connectPeripheral:options:") else { return }
        let peer = peripheral.peripheral
        guard peer.state == PeripheralState.disconnected else { return }
        peer.state = PeripheralState.connecting
        peer.cancelling = false
        bluetoothTrace("connect \(peer.path)")
        let owner = Unchecked(self), target = Unchecked(peripheral), path = peer.path
        central.command {
            let result = await Self.connect(path, cancelled: { owner.value.isCancelled(target.value) })
            Dispatch.on(owner.value.central.queue) {
                let manager = owner.value, peripheral = target.value
                guard peripheral.peripheral.state == PeripheralState.connecting else { return }
                switch result {
                case .success:
                    // As on Darwin, the link being up is the connection;
                    // discovering services waits for BlueZ to resolve them.
                    manager.connected(peripheral)
                case .failure(let failure):
                    bluetoothTrace("connect \(path) failed: \(failure)")
                    peripheral.disconnected()
                    guard !peripheral.peripheral.cancelling else { return manager.disconnected(peripheral) }
                    let timedOut = (failure as? BlueZError)?.message.contains("timed out") == true
                    let error = BluetoothErrors.cb(timedOut ? BluetoothErrors.connectionTimeout : BluetoothErrors.connectionFailed, failure)
                    guard let delegate = manager.delegate(),
                          delegate.responds(to: "centralManager:didFailToConnectPeripheral:error:") else { return }
                    delegate.sendCentralManager(manager, didFailToConnect: peripheral, error: error)
                }
            }
        }
    }

    @ObjCMethod("connectPeripheral:") func connect(_ peripheral: CBPeripheral?) { connect(peripheral, options: nil) }

    /// BlueZ's Connect, tried again while it fails in ways that pass: an
    /// LE connection aborted by the controller, which a weak signal or a
    /// discovery just stopped brings about. Darwin keeps trying until the
    /// app cancels; this gives up after ten tries.
    private static func connect(_ path: String, cancelled: @escaping @Sendable () -> Bool) async -> Result<[DBusValue], Error> {
        let transient = ["le-connection-abort-by-local", "Software caused connection abort", "In Progress"]
        var result: Result<[DBusValue], Error> = .success([])
        for attempt in 0..<10 {
            if attempt > 0 { try? await Task.sleep(nanoseconds: 500_000_000) }
            if cancelled() { break }
            result = await Result { try await BlueZ.shared.call(path, BlueZInterface.device, "Connect") }
            guard case .failure(let failure) = result, let error = failure as? BlueZError,
                  transient.contains(where: { error.message.contains($0) || error.name.hasSuffix($0) }) else { break }
        }
        return result
    }

    /// Whether the app cancelled the peripheral's connection.
    func isCancelled(_ peripheral: CBPeripheral) -> Bool {
        let peer = peripheral.peripheral
        return peer.cancelling || peer.state != PeripheralState.connecting
    }

    @ObjCMethod("cancelPeripheralConnection:")
    func cancelConnection(_ peripheral: CBPeripheral?) {
        guard let peripheral else { return }
        let peer = peripheral.peripheral
        guard peer.state != PeripheralState.disconnected else { return }
        peer.cancelling = true
        peer.state = PeripheralState.disconnecting
        bluetoothTrace("disconnect \(peer.path)")
        let owner = Unchecked(self), target = Unchecked(peripheral), path = peer.path
        central.command {
            _ = try? await BlueZ.shared.call(path, BlueZInterface.device, "Disconnect")
            let connected = await BlueZ.shared.properties(path, BlueZInterface.device)?["Connected"]?.boolValue ?? false
            guard !connected else { return }
            // Never connected, so BlueZ reports no change: disconnected now.
            Dispatch.on(owner.value.central.queue) { owner.value.disconnected(target.value) }
        }
    }

    private func connected(_ peripheral: CBPeripheral) {
        guard peripheral.peripheral.state == PeripheralState.connecting else { return }
        bluetoothTrace("didConnect \(peripheral.peripheral.path)")
        peripheral.peripheral.state = PeripheralState.connected
        guard let delegate = delegate(), delegate.responds(to: "centralManager:didConnectPeripheral:") else { return }
        delegate.sendCentralManager(self, didConnect: peripheral)
    }

    private func disconnected(_ peripheral: CBPeripheral) {
        let peer = peripheral.peripheral
        guard peer.state != PeripheralState.disconnected || peer.cancelling else { return }
        let error = peer.cancelling ? nil : BluetoothErrors.cb(BluetoothErrors.peripheralDisconnected)
        let wasConnecting = peer.state == PeripheralState.connecting
        bluetoothTrace("disconnected \(peer.path), \(error == nil ? "asked for" : "lost")")
        peer.cancelling = false
        peripheral.disconnected()
        guard let delegate = delegate() else { return }
        if wasConnecting && error != nil {
            guard delegate.responds(to: "centralManager:didFailToConnectPeripheral:error:") else { return }
            delegate.sendCentralManager(self, didFailToConnect: peripheral, error: BluetoothErrors.cb(BluetoothErrors.connectionFailed))
        } else if delegate.responds(to: "centralManager:didDisconnectPeripheral:error:") {
            delegate.sendCentralManager(self, didDisconnect: peripheral, error: error)
        }
    }

    // MARK: Retrieving

    @ObjCMethod("retrievePeripheralsWithIdentifiers:")
    func retrievePeripherals(withIdentifiers identifiers: NSObject?) -> NSMutableArray {
        let wanted = identifiers.map { $0.is(NSArray.self) ? $0.unsafeCast(to: NSArray.self).elements : [] } ?? []
        let strings = wanted.map { $0.unsafeCast(to: NSUUID.self).uuidString().uppercased() }
        let devices = Blocking.wait { await BlueZ.shared.objects(with: BlueZInterface.device) }
        var found: [NSObject] = []
        for string in strings {
            guard let device = devices.first(where: {
                Identifiers.identifier(path: $0.path, address: $0.properties["Address"]?.stringValue) == string
            }) else { continue }
            found.append(peripheral(device.path, device.properties))
        }
        return NSMutableArray.of(found)
    }

    @ObjCMethod("retrieveConnectedPeripheralsWithServices:")
    func retrieveConnectedPeripherals(withServices services: NSObject?) -> NSMutableArray {
        let wanted = services?.uuids ?? []
        let devices = Blocking.wait { await BlueZ.shared.objects(with: BlueZInterface.device) }
        let found = devices.filter { device in
            guard device.properties["Connected"]?.boolValue == true else { return false }
            let uuids = device.properties["UUIDs"]?.stringArray.compactMap(BluetoothUUID.init(string:)) ?? []
            return wanted.isEmpty || uuids.contains(where: wanted.contains)
        }
        return NSMutableArray.of(found.map { peripheral($0.path, $0.properties) })
    }

    private func peripheral(_ path: String, _ device: [String: DBusValue]) -> CBPeripheral {
        let peripheral = Registry.peripheral(path: path, manager: objcObject)
        let peer = peripheral.peripheral
        peer.address = device["Address"]?.stringValue
        peer.name = device["Name"]?.stringValue ?? peer.name
        return peripheral
    }

    // MARK: BlueZ's reports

    func handle(_ event: BlueZEvent, current: Interfaces) {
        switch event {
        case .added(let path, let interfaces):
            if interfaces[BlueZInterface.adapter] != nil, central.adapter == nil {
                central.adapter = path
                update(interfaces[BlueZInterface.adapter]?["Powered"]?.boolValue == true ? ManagerState.poweredOn : ManagerState.poweredOff)
            }
            if let device = current[BlueZInterface.device] { discovered(path, device) }
        case .removed(let path, let interfaces):
            if path == central.adapter, interfaces.contains(BlueZInterface.adapter) {
                central.adapter = nil
                update(ManagerState.unsupported)
            }
        case .changed(let path, let interface, let changed):
            switch interface {
            case BlueZInterface.adapter where path == central.adapter:
                if let powered = changed["Powered"]?.boolValue { update(powered ? ManagerState.poweredOn : ManagerState.poweredOff) }
                if changed["Discovering"]?.boolValue == false, central.scanning, let adapter = central.adapter {
                    // BlueZ stopped discovering on its own; Darwin scans on.
                    Task { _ = try? await BlueZ.shared.call(adapter, BlueZInterface.adapter, "StartDiscovery") }
                }
            case BlueZInterface.device:
                guard let device = current[BlueZInterface.device] else { return }
                if ["RSSI", "ManufacturerData", "ServiceData", "TxPower"].contains(where: { changed[$0] != nil }) {
                    discovered(path, device)
                }
                let peripheral = Registry.lock.withLock { Registry.peripherals[Registry.key(objcObject, path)] }
                guard let peripheral else { return }
                if let name = changed["Name"]?.stringValue { peripheral.nameChanged(name) }
                if changed["ServicesResolved"]?.boolValue == true { connected(peripheral) }
                // While connecting, Connect's answer decides: BlueZ may drop
                // a connection it is about to try again.
                if changed["Connected"]?.boolValue == false, peripheral.peripheral.state != PeripheralState.connecting {
                    disconnected(peripheral)
                }
            case BlueZInterface.characteristic:
                guard let bytes = changed["Value"]?.bytes,
                      let characteristic = Registry.lock.withLock({ Registry.characteristics[Registry.key(objcObject, path)] }),
                      let peripheral = characteristic.owner else { return }
                if let mtu = changed["MTU"]?.intValue { peripheral.peripheral.mtu = mtu }
                peripheral.valueChanged(characteristic, bytes: bytes)
            default:
                break
            }
        }
    }
}

/// The central managers alive, which BlueZ's reports go to.
enum Centrals {
    private static let lock = Lock()
    nonisolated(unsafe) private static var managers: Set<UnsafeMutableRawPointer> = []

    static func add(_ manager: CBCentralManager) { _ = lock.withLock { managers.insert(manager.objcObject) } }

    static func remove(_ manager: UnsafeMutableRawPointer) { _ = lock.withLock { managers.remove(manager) } }

    /// The manager, if it has not been deallocated.
    static func alive(_ manager: UnsafeMutableRawPointer) -> CBCentralManager? {
        lock.withLock { managers.contains(manager) ? CBCentralManager(objcObject: manager, ownership: .retain) : nil }
    }
}

/// An advertisement as CoreBluetooth gives it: the device's name,
/// manufacturer data (its company's identifier first, little-endian),
/// service UUIDs and data, and transmit power.
enum Advertisement {
    static func data(_ device: [String: DBusValue], services: [BluetoothUUID]) -> NSMutableDictionary {
        let data = NSMutableDictionary.empty()
        if let name = device["Name"]?.stringValue {
            data.set(string: name, forKey: Constants.CBAdvertisementDataLocalNameKey)
        }
        if case .dictionary(let manufacturers)? = device["ManufacturerData"],
           let (company, value) = manufacturers.first, let identifier = company.intValue, let bytes = value.bytes {
            data.set(NSData.of([UInt8(identifier & 0xff), UInt8(identifier >> 8)] + bytes), forKey: Constants.CBAdvertisementDataManufacturerDataKey)
        }
        if !services.isEmpty {
            data.set(NSMutableArray.of(services.map(CBUUID.make)), forKey: Constants.CBAdvertisementDataServiceUUIDsKey)
        }
        if case .dictionary(let entries)? = device["ServiceData"], !entries.isEmpty {
            let serviceData = NSMutableDictionary.empty()
            for (uuid, value) in entries {
                guard let uuid = uuid.stringValue.flatMap(BluetoothUUID.init(string:)), let bytes = value.bytes else { continue }
                serviceData.set(NSData.of(bytes), forObjectKey: CBUUID.make(uuid))
            }
            data.set(serviceData, forKey: Constants.CBAdvertisementDataServiceDataKey)
        }
        if let power = device["TxPower"]?.intValue {
            data.set(NSNumber.make(integer: power), forKey: Constants.CBAdvertisementDataTxPowerLevelKey)
        }
        data.set(NSNumber.make(bool: true), forKey: Constants.CBAdvertisementDataIsConnectable)
        return data
    }
}

/// Waits on the calling thread for work on BlueZ's actor, for the methods
/// CoreBluetooth answers synchronously.
enum Blocking {
    private final class Box<T>: @unchecked Sendable { var value: T? }

    static func wait<T: Sendable>(_ body: @escaping @Sendable () async -> T) -> T {
        let box = Box<T>()
        let semaphore = UnsafeMutablePointer<sem_t>.allocate(capacity: 1)
        sem_init(semaphore, 0, 0)
        let signal = Unchecked(semaphore)
        Task {
            box.value = await body()
            sem_post(signal.value)
        }
        while sem_wait(semaphore) != 0 {}
        sem_destroy(semaphore)
        semaphore.deallocate()
        return box.value!
    }
}

/// A peripheral manager: unsupported, as Perry does not advertise.
@ObjCClass("CBPeripheralManager")
open class CBPeripheralManager: CBManager {
    static let delegates = StateTable<CentralState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        let state = CBPeripheralManager.delegates[objcObject]
        if let queue = state.queue { Dispatch.release(queue) }
        CBPeripheralManager.delegates.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CBPeripheralManager.objCClass.pointer)
    }

    /// CBPeripheralManagerAuthorizationStatus: authorized 3.
    @ObjCClassMethod("authorizationStatus") static func authorizationStatus() -> Int { 3 }

    @ObjCMethod("init") func initialize() -> Self { initialize(delegate: nil, queue: nil, options: nil) }

    @ObjCMethod("initWithDelegate:queue:")
    func initialize(delegate: NSObject?, queue: UnsafeMutableRawPointer?) -> Self { initialize(delegate: delegate, queue: queue, options: nil) }

    @ObjCMethod("initWithDelegate:queue:options:")
    func initialize(delegate: NSObject?, queue: UnsafeMutableRawPointer?, options: NSObject?) -> Self {
        let state = CBPeripheralManager.delegates[objcObject]
        state.delegate = delegate?.objcObject
        if let queue {
            Dispatch.retain(queue)
            state.queue = queue
        }
        state.state = ManagerState.unsupported
        let owner = Unchecked(self)
        Dispatch.on(queue) {
            let manager = owner.value
            guard let delegate = manager.delegate(), delegate.responds(to: "peripheralManagerDidUpdateState:") else { return }
            delegate.sendPeripheralManagerDidUpdateState(manager)
        }
        return self
    }

    @ObjCMethod("state") func state() -> Int { ManagerState.unsupported }
    @ObjCMethod("isAdvertising") func isAdvertising() -> Bool { false }
    @ObjCMethod("delegate") func delegate() -> NSObject? { CBPeripheralManager.delegates[objcObject].delegate.map { NSObject($0) } }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { CBPeripheralManager.delegates[objcObject].delegate = delegate?.objcObject }
    @ObjCMethod("startAdvertising:") func startAdvertising(_ data: NSObject?) {}
    @ObjCMethod("stopAdvertising") func stopAdvertising() {}
    @ObjCMethod("addService:") func add(_ service: NSObject?) {}
    @ObjCMethod("removeService:") func remove(_ service: NSObject?) {}
    @ObjCMethod("removeAllServices") func removeAllServices() {}
}

/// CBCentralManagerDelegate's and CBPeripheralManagerDelegate's messages.
extension NSObject {
    @ObjCMethod("centralManagerDidUpdateState:")
    func sendCentralManagerDidUpdateState(_ manager: CBCentralManager)

    @ObjCMethod("centralManager:didDiscoverPeripheral:advertisementData:RSSI:")
    func sendCentralManager(_ manager: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: NSMutableDictionary, rssi: NSNumber)

    @ObjCMethod("centralManager:didConnectPeripheral:")
    func sendCentralManager(_ manager: CBCentralManager, didConnect peripheral: CBPeripheral)

    @ObjCMethod("centralManager:didFailToConnectPeripheral:error:")
    func sendCentralManager(_ manager: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: NSError?)

    @ObjCMethod("centralManager:didDisconnectPeripheral:error:")
    func sendCentralManager(_ manager: CBCentralManager, didDisconnect peripheral: CBPeripheral, error: NSError?)

    @ObjCMethod("peripheralManagerDidUpdateState:")
    func sendPeripheralManagerDidUpdateState(_ manager: CBPeripheralManager)
}

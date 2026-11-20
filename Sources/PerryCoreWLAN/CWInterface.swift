import PerryObjCInterop

// CWInterface: a Wi-Fi interface. On the old API it is also the entry point
// (+interface, +interfaceWithName:, +interfaceNames); on the modern one
// CWWiFiClient is, and hands out CWInterfaces. An interface keeps only its
// name and reads everything else live from NetworkManager, so its answers
// stay current as on Darwin.

final class InterfaceState: ObjectState {
    var name = ""
}

@ObjCClass("CWInterface")
open class CWInterface: NSObject {
    static let states = StateTable<InterfaceState>()
    var name: String {
        get { CWInterface.states[objcObject].name }
        set { CWInterface.states[objcObject].name = newValue }
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        CWInterface.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CWInterface.objCClass.pointer)
    }

    static func make(name: String) -> CWInterface {
        let object = CWInterface.objCClass.object.newInstance().unsafeCast(to: CWInterface.self)
        object.name = name
        return object
    }

    /// The device this interface names, now; nil when it is gone or the name
    /// matches nothing.
    private func device() -> NMDevice? {
        let name = Unchecked(self.name)
        return Blocking.wait { await NetworkManager.shared.wifiDevice(named: name.value) }
    }

    // MARK: Entry point (old API)

    @ObjCClassMethod("interface")
    static func defaultInterface() -> CWInterface? {
        guard let device = Blocking.wait({ await NetworkManager.shared.wifiDevice(named: nil) }) else { return nil }
        return make(name: device.interface)
    }

    @ObjCClassMethod("interfaceWithName:")
    static func interface(name: String?) -> CWInterface? {
        guard let device = Blocking.wait({ await NetworkManager.shared.wifiDevice(named: name) }) else { return nil }
        return make(name: device.interface)
    }

    /// -init / -initWithInterfaceName:: a bare interface, or the named one.
    @ObjCMethod("init") func initialize() -> CWInterface {
        if name.isEmpty, let device = device() ?? Blocking.wait({ await NetworkManager.shared.wifiDevice(named: nil) }) {
            name = device.interface
        }
        return self
    }

    @ObjCMethod("initWithInterfaceName:")
    func initialize(name: String?) -> CWInterface {
        if let name { self.name = name }
        return self
    }

    /// +interfaceNames (old) / the names, as strings.
    @ObjCClassMethod("interfaceNames")
    static func interfaceNames() -> NSMutableArray {
        let names = Blocking.wait { await NetworkManager.shared.wifiDevices() }.map(\.interface)
        return NSMutableArray.of(names.map { $0.objCObject })
    }

    @ObjCClassMethod("supportedInterfaces")
    static func supportedInterfaces() -> NSMutableArray { interfaceNames() }

    // MARK: Identity

    @ObjCMethod("interfaceName") func interfaceName() -> String { device()?.interface ?? name }
    @ObjCMethod("name") func nameAccessor() -> String { interfaceName() }
    @ObjCMethod("macAddress") func macAddress() -> String { device()?.hardwareAddress ?? "" }
    @ObjCMethod("hardwareAddress") func hardwareAddress() -> String { macAddress() }

    // MARK: Power

    @ObjCMethod("powerOn") func powerOn() -> Bool {
        device() != nil && Blocking.wait { await NetworkManager.shared.wirelessEnabled }
    }

    @ObjCMethod("setPower:error:")
    func setPower(_ on: Bool, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        let value = Unchecked(on)
        let ok = Blocking.wait { await NetworkManager.shared.setWirelessEnabled(value.value) }
        if !ok { error?.pointee = Self.error() }
        return ok
    }

    /// Whether the interface is on and has hardware — the app's "hardware
    /// attached" column.
    @ObjCMethod("serviceActive") func serviceActive() -> Bool { device() != nil }
    @ObjCMethod("deviceAttached") func deviceAttached() -> Bool { device() != nil }

    // MARK: Current association

    private func active() -> NMAccessPoint? {
        guard let path = device()?.path else { return nil }
        let devicePath = Unchecked(path)
        return Blocking.wait { await NetworkManager.shared.activeAccessPoint(ofDevice: devicePath.value) }
    }

    @ObjCMethod("ssid") func ssid() -> String? { active().map { WiFi.ssidString($0.ssid) } }
    @ObjCMethod("SSID") func ssidUppercase() -> String? { ssid() }
    @ObjCMethod("bssid") func bssid() -> String? { active()?.bssid }
    @ObjCMethod("BSSID") func bssidUppercase() -> String? { active()?.bssid }
    @ObjCMethod("rssiValue") func rssiValue() -> Int { active().map { WiFi.rssi(strength: $0.strength) } ?? 0 }
    @ObjCMethod("rssi") func rssi() -> Int { rssiValue() }
    @ObjCMethod("noiseMeasurement") func noiseMeasurement() -> Int { 0 }
    @ObjCMethod("channel") func channel() -> NSNumber { NSNumber.make(integer: active().map { WiFi.channel(frequency: $0.frequency) } ?? 0) }
    @ObjCMethod("wlanChannel") func wlanChannel() -> CWChannel? {
        active().map { CWChannel.make(number: WiFi.channel(frequency: $0.frequency), band: WiFi.band(frequency: $0.frequency)) }
    }
    @ObjCMethod("interfaceMode") func interfaceMode() -> Int {
        guard let mode = active()?.mode else { return CWInterfaceMode.none.rawValue }
        // NM80211Mode: 2 = infrastructure (station), 1 = adhoc, 3 = AP.
        return switch mode { case 2: CWInterfaceMode.station.rawValue; case 1: CWInterfaceMode.ibss.rawValue
                             case 3: CWInterfaceMode.hostAP.rawValue; default: CWInterfaceMode.none.rawValue }
    }

    // MARK: Scanning

    private func scan(ssidFilter: [UInt8]?) -> [NMAccessPoint] {
        guard let path = device()?.path else { return [] }
        let devicePath = Unchecked(path)
        let found = Blocking.wait { await NetworkManager.shared.scan(deviceAt: devicePath.value) }
        guard let ssidFilter, !ssidFilter.isEmpty else { return found }
        return found.filter { $0.ssid == ssidFilter }
    }

    /// Old API: an NSArray of CWNetwork, filtered by SSID string when given.
    @ObjCMethod("scanForNetworksWithName:error:")
    func scanForNetworks(name: String?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> NSMutableArray {
        error?.pointee = nil
        wlanTrace("scanForNetworksWithName:\(name ?? "nil") on \(self.name)")
        let networks = scan(ssidFilter: name.map { Array($0.utf8) }).map { CWNetwork.make($0) as NSObject }
        return NSMutableArray.of(networks)
    }

    /// 10.6 API: scanForNetworksWithParameters: took an options dictionary,
    /// which we ignore (NetworkManager scans all channels), returning an array.
    @ObjCMethod("scanForNetworksWithParameters:error:")
    func scanForNetworks(parameters: NSObject?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> NSMutableArray {
        scanForNetworks(name: nil, error: error)
    }

    /// Modern API: an NSSet of CWNetwork, filtered by an SSID given as NSData.
    @ObjCMethod("scanForNetworksWithSSID:error:")
    func scanForNetworks(ssid: NSObject?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> NSMutableSet {
        error?.pointee = nil
        let filter = ssid.flatMap { $0.is(NSData.self) ? $0.unsafeCast(to: NSData.self).byteArray : nil }
        let networks = scan(ssidFilter: filter).map { CWNetwork.make($0) as NSObject }
        return NSMutableSet.of(networks)
    }

    /// Disassociation needs privileges CoreWLAN's simple API doesn't broker on
    /// Linux; a no-op, as on a Mac without the right.
    @ObjCMethod("disassociate") func disassociate() {}

    private static func error() -> UnsafeMutableRawPointer? {
        NSError.make(domain: CWError.domain, code: CWError.operationNotPermitted, userInfo: nil).objcObject
    }
}

// CWWiFiClient: the modern entry point (10.10+). It hands out CWInterfaces,
// which carry the whole API above.

@ObjCClass("CWWiFiClient")
open class CWWiFiClient: NSObject {
    nonisolated(unsafe) static var shared: CWWiFiClient?
    private static let lock = Lock()

    @ObjCClassMethod("sharedWiFiClient")
    static func sharedClient() -> CWWiFiClient {
        lock.withLock {
            if let shared { return shared }
            let client = CWWiFiClient.objCClass.object.newInstance().unsafeCast(to: CWWiFiClient.self)
            shared = client
            return client
        }
    }

    @ObjCMethod("init") func initialize() -> CWWiFiClient { self }

    @ObjCMethod("interface") func interface() -> CWInterface? { CWInterface.defaultInterface() }
    @ObjCMethod("interfaceWithName:") func interface(name: String?) -> CWInterface? { CWInterface.interface(name: name) }

    @ObjCMethod("interfaceNames") func interfaceNames() -> NSMutableArray { CWInterface.interfaceNames() }
    @ObjCClassMethod("interfaceNames") static func interfaceNamesClass() -> NSMutableArray { CWInterface.interfaceNames() }

    @ObjCMethod("interfaces") func interfaces() -> NSMutableArray {
        let devices = Blocking.wait { await NetworkManager.shared.wifiDevices() }
        return NSMutableArray.of(devices.map { CWInterface.make(name: $0.interface) as NSObject })
    }
}

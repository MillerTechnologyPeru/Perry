import PerryObjCInterop

// CWNetwork: one scanned Wi-Fi network, backed by a NetworkManager access
// point. The accessors cover both CoreWLAN generations — the old uppercase
// -SSID/-BSSID and -channel (an NSNumber), and the modern -ssid/-bssid and
// -wlanChannel (a CWChannel).

final class NetworkState: ObjectState {
    var ap = NMAccessPoint(path: "", ssid: [], bssid: "", frequency: 0, strength: 0, flags: 0, wpaFlags: 0, rsnFlags: 0, mode: 0)
}

@ObjCClass("CWNetwork")
open class CWNetwork: NSObject {
    static let states = StateTable<NetworkState>()
    var ap: NMAccessPoint {
        get { CWNetwork.states[objcObject].ap }
        set { CWNetwork.states[objcObject].ap = newValue }
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        CWNetwork.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CWNetwork.objCClass.pointer)
    }

    static func make(_ ap: NMAccessPoint) -> CWNetwork {
        let object = CWNetwork.objCClass.object.newInstance().unsafeCast(to: CWNetwork.self)
        object.ap = ap
        return object
    }

    // MARK: Identity

    @ObjCMethod("ssid") func ssid() -> String { WiFi.ssidString(ap.ssid) }
    @ObjCMethod("SSID") func ssidUppercase() -> String { ssid() }
    @ObjCMethod("ssidData") func ssidData() -> NSData { NSData.of(ap.ssid) }

    @ObjCMethod("bssid") func bssid() -> String { ap.bssid }
    @ObjCMethod("BSSID") func bssidUppercase() -> String { ap.bssid }

    // MARK: Signal

    @ObjCMethod("rssiValue") func rssiValue() -> Int { WiFi.rssi(strength: ap.strength) }
    @ObjCMethod("rssi") func rssi() -> Int { rssiValue() }
    // NetworkManager reports no noise floor; CoreWLAN returns 0 when unknown.
    @ObjCMethod("noiseMeasurement") func noiseMeasurement() -> Int { 0 }
    // NetworkManager's 0–100 signal quality, for apps that read a percentage.
    @ObjCMethod("strength") func strength() -> Int { ap.strength }

    // MARK: Channel

    /// The old API: an NSNumber for the channel.
    @ObjCMethod("channel") func channel() -> NSNumber { NSNumber.make(integer: WiFi.channel(frequency: ap.frequency)) }
    @ObjCMethod("channelNumber") func channelNumber() -> Int { WiFi.channel(frequency: ap.frequency) }
    /// The modern API: a CWChannel object.
    @ObjCMethod("wlanChannel") func wlanChannel() -> CWChannel {
        CWChannel.make(number: WiFi.channel(frequency: ap.frequency), band: WiFi.band(frequency: ap.frequency))
    }

    // MARK: Security

    @ObjCMethod("securityMode") func securityMode() -> Int {
        WiFi.security(flags: ap.flags, wpaFlags: ap.wpaFlags, rsnFlags: ap.rsnFlags).rawValue
    }
    @ObjCMethod("supportsSecurity:") func supports(security: Int) -> Bool {
        WiFi.security(flags: ap.flags, wpaFlags: ap.wpaFlags, rsnFlags: ap.rsnFlags).rawValue == security
    }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: NSObject?) -> Bool {
        guard let other, other.is(CWNetwork.self) else { return false }
        return other.unsafeCast(to: CWNetwork.self).ap.bssid == ap.bssid
    }

    @ObjCMethod("hash") func hash() -> UInt { UInt(bitPattern: ap.bssid.hashValue) }
    @ObjCMethod("description") func description() -> String { "\(WiFi.ssidString(ap.ssid)) (\(ap.bssid))" }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { ObjCRuntime.retain(objcObject) }
}

// CWChannel: the modern channel object.

final class ChannelState: ObjectState {
    var number = 0
    var band = CWChannelBand.unknown
    var width = CWChannelWidth.width20MHz
}

@ObjCClass("CWChannel")
open class CWChannel: NSObject {
    static let states = StateTable<ChannelState>()
    var state: ChannelState { CWChannel.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        CWChannel.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CWChannel.objCClass.pointer)
    }

    static func make(number: Int, band: CWChannelBand) -> CWChannel {
        let object = CWChannel.objCClass.object.newInstance().unsafeCast(to: CWChannel.self)
        object.state.number = number
        object.state.band = band
        return object
    }

    @ObjCMethod("channelNumber") func channelNumber() -> Int { state.number }
    @ObjCMethod("channelBand") func channelBand() -> Int { state.band.rawValue }
    @ObjCMethod("channelWidth") func channelWidth() -> Int { state.width.rawValue }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: NSObject?) -> Bool {
        guard let other, other.is(CWChannel.self) else { return false }
        return other.unsafeCast(to: CWChannel.self).state.number == state.number
    }

    @ObjCMethod("hash") func hash() -> UInt { UInt(bitPattern: state.number) }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { ObjCRuntime.retain(objcObject) }
}

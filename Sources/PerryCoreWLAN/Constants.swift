import PerryObjCInterop

// CoreWLAN's domain, enumerations and the conversions between NetworkManager's
// units and CoreWLAN's.

enum CWError {
    static let domain = "com.apple.coreWLAN.error"
    // CWErr / CWErrorCode: 0 is success; the generic failure Darwin returns.
    static let operationNotPermitted = -1
}

/// CWSecurity (modern) and the overlapping CWSecurityMode (old): the cases the
/// app layer uses line up at the low values.
enum CWSecurity: Int {
    case none = 0
    case wep = 1
    case wpaPersonal = 2
    case wpaPersonalMixed = 3
    case wpa2Personal = 4
    case wpaEnterprise = 7
    case wpa2Enterprise = 9
    case unknown = 11
}

/// CWPHYMode.
enum CWPHYMode: Int {
    case none = 0, a = 1, b = 2, g = 3, n = 4, ac = 5
}

/// CWInterfaceMode / CWOpMode.
enum CWInterfaceMode: Int {
    case none = 0, station = 1, ibss = 2, hostAP = 3
}

/// CWChannelBand.
enum CWChannelBand: Int {
    case unknown = 0, band2GHz = 1, band5GHz = 2, band6GHz = 3
}

/// CWChannelWidth.
enum CWChannelWidth: Int {
    case unknown = 0, width20MHz = 1, width40MHz = 2, width80MHz = 3, width160MHz = 4
}

enum WiFi {
    /// The channel number of a frequency in MHz, as CWChannel reports it.
    static func channel(frequency: Int) -> Int {
        switch frequency {
        case 2412...2472: (frequency - 2407) / 5   // 2.4 GHz: channels 1–13
        case 2484: 14
        case 5000...5895: (frequency - 5000) / 5   // 5 GHz
        case 5955...7115: (frequency - 5950) / 5   // 6 GHz
        default: 0
        }
    }

    static func band(frequency: Int) -> CWChannelBand {
        switch frequency {
        case ..<2500: .band2GHz
        case 2500..<5925: .band5GHz
        case 5925...: .band6GHz
        default: .unknown
        }
    }

    /// A received-signal level in dBm from NetworkManager's 0–100 strength.
    /// CoreWLAN reports rssiValue in dBm; NetworkManager gives a percentage,
    /// so this is the common linear inverse, −100 dBm (0) to −50 dBm (100).
    static func rssi(strength: Int) -> Int { strength / 2 - 100 }

    /// An SSID's text, as CWNetwork's -ssid gives it. Non-UTF-8 SSIDs, which
    /// the API also allows, come back as their bytes' Latin-1 reading.
    static func ssidString(_ bytes: [UInt8]) -> String {
        if let text = String(bytes: bytes, encoding: .utf8) { return text }
        return String(bytes.map { Character(UnicodeScalar($0)) })
    }

    // NetworkManager 802.11 access-point security flags (NM80211ApSecurityFlags).
    private static let keyMgmtPSK = 0x100
    private static let keyMgmt8021X = 0x200
    private static let apFlagPrivacy = 0x1

    /// The best security CoreWLAN would report for an access point.
    static func security(flags: Int, wpaFlags: Int, rsnFlags: Int) -> CWSecurity {
        if rsnFlags != 0 {
            return rsnFlags & keyMgmt8021X != 0 ? .wpa2Enterprise : .wpa2Personal
        }
        if wpaFlags != 0 {
            return wpaFlags & keyMgmt8021X != 0 ? .wpaEnterprise : .wpaPersonal
        }
        return flags & apFlagPrivacy != 0 ? .wep : .none
    }
}

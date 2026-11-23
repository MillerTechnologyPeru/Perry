// NWInterface: a network interface, from the C API's nw_interface_t, or
// by name and index for one named in an address ("fe80::1%en0").

import Darwin

@available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
public struct NWInterface: Hashable, CustomDebugStringConvertible, Sendable {
    public var debugDescription: String { name }

    public enum InterfaceType: Sendable {
        case other
        case wifi
        case cellular
        case wiredEthernet
        case loopback
    }

    public let type: InterfaceType
    public let name: String
    public let index: Int

    /// The C API's interface, when the interface came from it.
    nonisolated(unsafe) let nw: nw_interface_t?

    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    public enum RadioType: Sendable {
        public enum WiFi: Sendable {
            case b
            case a
            case g
            case n
            case ac
            case ax
        }

        public enum Cellular: Sendable {
            public enum NewRadio5GVariant: Sendable {
                case sub6GHz
                case mmWave
            }

            case lte
            case dualConnectivity5G(NewRadio5GVariant)
            case standalone5G(NewRadio5GVariant)
            case wcdma
            case gsm
            case cdma
            case evdo
        }

        case wifi(WiFi)
        case cell(Cellular)
    }

    init(_ nw: nw_interface_t) {
        self.nw = nw
        name = String(cString: nw_interface_get_name(nw))
        index = Int(nw_interface_get_index(nw))
        type = InterfaceType(nw_interface_get_type(nw))
    }

    /// The interface of the index given, nil for none.
    init?(index: Int) {
        guard index > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE) + 1)
        guard if_indextoname(UInt32(index), &buffer) != nil else { return nil }
        self.init(name: String(cString: buffer), index: index)
    }

    /// The interface of the name given, nil if there is no such interface.
    init?(name: String) {
        let index = Int(if_nametoindex(name))
        guard index > 0 else { return nil }
        self.init(name: name, index: index)
    }

    private init(name: String, index: Int) {
        self.name = name
        self.index = index
        nw = nil
        type = name.hasPrefix("lo") ? .loopback : .other
    }

    public static func == (a: NWInterface, b: NWInterface) -> Bool {
        a.name == b.name && a.index == b.index
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(index)
    }
}

extension NWInterface.InterfaceType {
    init(_ type: nw_interface_type_t) {
        switch type {
        case nw_interface_type_wifi: self = .wifi
        case nw_interface_type_cellular: self = .cellular
        case nw_interface_type_wired: self = .wiredEthernet
        case nw_interface_type_loopback: self = .loopback
        default: self = .other
        }
    }

    var nw: nw_interface_type_t {
        switch self {
        case .other: return nw_interface_type_other
        case .wifi: return nw_interface_type_wifi
        case .cellular: return nw_interface_type_cellular
        case .wiredEthernet: return nw_interface_type_wired
        case .loopback: return nw_interface_type_loopback
        }
    }
}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
extension NWInterface.RadioType {
    /// The radio type of the C API's, nil for an unknown one.
    init?(_ type: nw_interface_radio_type_t) {
        switch type {
        case nw_interface_radio_type_wifi_b: self = .wifi(.b)
        case nw_interface_radio_type_wifi_a: self = .wifi(.a)
        case nw_interface_radio_type_wifi_g: self = .wifi(.g)
        case nw_interface_radio_type_wifi_n: self = .wifi(.n)
        case nw_interface_radio_type_wifi_ac: self = .wifi(.ac)
        case nw_interface_radio_type_wifi_ax: self = .wifi(.ax)
        case nw_interface_radio_type_cell_lte: self = .cell(.lte)
        case nw_interface_radio_type_cell_endc_sub6: self = .cell(.dualConnectivity5G(.sub6GHz))
        case nw_interface_radio_type_cell_endc_mmw: self = .cell(.dualConnectivity5G(.mmWave))
        case nw_interface_radio_type_cell_nr_sa_sub6: self = .cell(.standalone5G(.sub6GHz))
        case nw_interface_radio_type_cell_nr_sa_mmw: self = .cell(.standalone5G(.mmWave))
        case nw_interface_radio_type_cell_wcdma: self = .cell(.wcdma)
        case nw_interface_radio_type_cell_gsm: self = .cell(.gsm)
        case nw_interface_radio_type_cell_cdma: self = .cell(.cdma)
        case nw_interface_radio_type_cell_evdo: self = .cell(.evdo)
        default: return nil
        }
    }
}

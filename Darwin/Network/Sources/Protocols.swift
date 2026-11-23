// The protocol classes: definitions, options and metadata over the C
// API's nw_protocol_definition_t, nw_protocol_options_t and
// nw_protocol_metadata_t, and those of IP, TCP, UDP and TLS. The C API
// sets most options without reading them back, so an options object
// keeps the values it set.

import Foundation
import Security

@_hasMissingDesignatedInitializers
@available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
@_objcRuntimeName(_TtC7Network21_NWProtocolDefinition)
public class NWProtocolDefinition: Equatable, CustomDebugStringConvertible, @unchecked Sendable {
    let nw: nw_protocol_definition_t
    final public let name: String

    init(_ nw: nw_protocol_definition_t, _ name: String) {
        self.nw = nw
        self.name = name
    }

    public static func == (lhs: NWProtocolDefinition, rhs: NWProtocolDefinition) -> Bool {
        lhs === rhs || nw_protocol_definition_is_equal(lhs.nw, rhs.nw)
    }

    public var debugDescription: String { name }

    deinit {}
}

@_hasMissingDesignatedInitializers
@available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
@_objcRuntimeName(_TtC7Network18_NWProtocolOptions)
public class NWProtocolOptions: @unchecked Sendable {
    let nw: nw_protocol_options_t

    init(_ nw: nw_protocol_options_t) {
        self.nw = nw
    }

    deinit {}
}

@_hasMissingDesignatedInitializers
@available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
@_objcRuntimeName(_TtC7Network19_NWProtocolMetadata)
public class NWProtocolMetadata: @unchecked Sendable {
    let nw: nw_protocol_metadata_t

    init(_ nw: nw_protocol_metadata_t) {
        self.nw = nw
    }

    deinit {}
}

@_hasMissingDesignatedInitializers
@available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
@_objcRuntimeName(_TtC7Network11_NWProtocol)
public class NWProtocol: @unchecked Sendable {
    init() {}

    deinit {}
}

// MARK: - Wrapping the C API's objects

@available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
extension NWProtocolOptions {
    /// The options object of a C API one, of its protocol's class.
    static func wrap(_ nw: nw_protocol_options_t) -> NWProtocolOptions {
        let definition = nw_protocol_options_copy_definition(nw)
        if nw_protocol_definition_is_equal(definition, nw_protocol_copy_tcp_definition()) {
            return NWProtocolTCP.Options(nw)
        }
        if nw_protocol_definition_is_equal(definition, nw_protocol_copy_udp_definition()) {
            return NWProtocolUDP.Options(nw)
        }
        if nw_protocol_definition_is_equal(definition, nw_protocol_copy_ip_definition()) {
            return NWProtocolIP.Options(nw)
        }
        if nw_protocol_definition_is_equal(definition, nw_protocol_copy_tls_definition()) {
            return NWProtocolTLS.Options(nw)
        }
        if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *), nw_protocol_options_is_quic(nw) {
            return NWProtocolQUIC.Options(nw)
        }
        if #available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *),
           nw_protocol_definition_is_equal(definition, nw_protocol_copy_ws_definition()) {
            return NWProtocolWebSocket.Options(nw)
        }
        return NWProtocolOptions(nw)
    }
}

@available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
extension NWProtocolMetadata {
    /// The metadata object of a C API one, of its protocol's class.
    static func wrap(_ nw: nw_protocol_metadata_t) -> NWProtocolMetadata {
        if nw_protocol_metadata_is_tcp(nw) { return NWProtocolTCP.Metadata(nw) }
        if nw_protocol_metadata_is_udp(nw) { return NWProtocolUDP.Metadata(nw) }
        if nw_protocol_metadata_is_ip(nw) { return NWProtocolIP.Metadata(nw) }
        if nw_protocol_metadata_is_tls(nw) { return NWProtocolTLS.Metadata(nw) }
        if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *), nw_protocol_metadata_is_quic(nw) {
            return NWProtocolQUIC.Metadata(nw)
        }
        if #available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *) {
            if nw_protocol_metadata_is_ws(nw) { return NWProtocolWebSocket.Metadata(nw) }
            if nw_protocol_metadata_is_framer_message(nw) { return NWProtocolFramer.Message(nw) }
        }
        return NWProtocolMetadata(nw)
    }
}

// MARK: - IP

@_inheritsConvenienceInitializers
@_hasMissingDesignatedInitializers
@available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
@_objcRuntimeName(_TtC7Network13_NWProtocolIP)
public class NWProtocolIP: NWProtocol {
    public static let definition = NWProtocolDefinition(nw_protocol_copy_ip_definition(), "ip")

    @_inheritsConvenienceInitializers
    @_hasMissingDesignatedInitializers
    @_objcRuntimeName(_TtCC7Network13_NWProtocolIP7Options)
    public class Options: NWProtocolOptions {
        public enum Version {
            case any
            case v4
            case v6
        }

        public var version: Version = .any {
            didSet {
                switch version {
                case .any: nw_ip_options_set_version(nw, nw_ip_version_any)
                case .v4: nw_ip_options_set_version(nw, nw_ip_version_4)
                case .v6: nw_ip_options_set_version(nw, nw_ip_version_6)
                }
            }
        }

        public var hopLimit: UInt8 = 0 {
            didSet { nw_ip_options_set_hop_limit(nw, hopLimit) }
        }

        public var useMinimumMTU = false {
            didSet { nw_ip_options_set_use_minimum_mtu(nw, useMinimumMTU) }
        }

        public var disableFragmentation = false {
            didSet { nw_ip_options_set_disable_fragmentation(nw, disableFragmentation) }
        }

        public var shouldCalculateReceiveTime = false {
            didSet { nw_ip_options_set_calculate_receive_time(nw, shouldCalculateReceiveTime) }
        }

        @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
        public enum AddressPreference {
            case `default`
            case temporary
            case stable
        }

        private var storedPreference = nw_ip_local_address_preference_default

        @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
        public var localAddressPreference: AddressPreference {
            get {
                switch storedPreference {
                case nw_ip_local_address_preference_temporary: return .temporary
                case nw_ip_local_address_preference_stable: return .stable
                default: return .default
                }
            }
            set {
                switch newValue {
                case .default: storedPreference = nw_ip_local_address_preference_default
                case .temporary: storedPreference = nw_ip_local_address_preference_temporary
                case .stable: storedPreference = nw_ip_local_address_preference_stable
                }
                nw_ip_options_set_local_address_preference(nw, storedPreference)
            }
        }

        private var storedMulticastLoopback = false

        @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
        public var disableMulticastLoopback: Bool {
            get { storedMulticastLoopback }
            set {
                storedMulticastLoopback = newValue
                nw_ip_options_set_disable_multicast_loopback(nw, newValue)
            }
        }

        deinit {}
    }

    public enum ECN {
        case nonECT
        case ect0
        case ect1
        case ce
    }

    @_inheritsConvenienceInitializers
    @_hasMissingDesignatedInitializers
    @_objcRuntimeName(_TtCC7Network13_NWProtocolIP8Metadata)
    public class Metadata: NWProtocolMetadata {
        public var ecn: ECN {
            get {
                switch nw_ip_metadata_get_ecn_flag(nw) {
                case nw_ip_ecn_flag_ect_0: return .ect0
                case nw_ip_ecn_flag_ect_1: return .ect1
                case nw_ip_ecn_flag_ce: return .ce
                default: return .nonECT
                }
            }
            set {
                switch newValue {
                case .nonECT: nw_ip_metadata_set_ecn_flag(nw, nw_ip_ecn_flag_non_ect)
                case .ect0: nw_ip_metadata_set_ecn_flag(nw, nw_ip_ecn_flag_ect_0)
                case .ect1: nw_ip_metadata_set_ecn_flag(nw, nw_ip_ecn_flag_ect_1)
                case .ce: nw_ip_metadata_set_ecn_flag(nw, nw_ip_ecn_flag_ce)
                }
            }
        }

        public var serviceClass: NWParameters.ServiceClass {
            get { NWParameters.ServiceClass(nw_ip_metadata_get_service_class(nw)) }
            set { nw_ip_metadata_set_service_class(nw, newValue.nw) }
        }

        public var receiveTime: UInt64 {
            nw_ip_metadata_get_receive_time(nw)
        }

        public init() {
            super.init(nw_ip_create_metadata())
        }

        override init(_ nw: nw_protocol_metadata_t) {
            super.init(nw)
        }

        deinit {}
    }

    deinit {}
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension NWProtocolIP.Metadata {
    /// Sets the ECN flag and answers the metadata.
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func ecn(_ ecn: NWProtocolIP.ECN) -> Self {
        self.ecn = ecn
        return self
    }

    /// Sets the service class and answers the metadata.
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func serviceClass(_ serviceClass: NWParameters.ServiceClass) -> Self {
        self.serviceClass = serviceClass
        return self
    }
}

// MARK: - TCP

@_inheritsConvenienceInitializers
@_hasMissingDesignatedInitializers
@available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
@_objcRuntimeName(_TtC7Network14_NWProtocolTCP)
public class NWProtocolTCP: NWProtocol {
    public static let definition = NWProtocolDefinition(nw_protocol_copy_tcp_definition(), "tcp")

    @_inheritsConvenienceInitializers
    @_hasMissingDesignatedInitializers
    @_objcRuntimeName(_TtCC7Network14_NWProtocolTCP7Options)
    public class Options: NWProtocolOptions {
        public var noDelay = false {
            didSet { nw_tcp_options_set_no_delay(nw, noDelay) }
        }

        public var noPush = false {
            didSet { nw_tcp_options_set_no_push(nw, noPush) }
        }

        public var noOptions = false {
            didSet { nw_tcp_options_set_no_options(nw, noOptions) }
        }

        public var enableKeepalive = false {
            didSet { nw_tcp_options_set_enable_keepalive(nw, enableKeepalive) }
        }

        public var keepaliveCount = 0 {
            didSet { nw_tcp_options_set_keepalive_count(nw, UInt32(clamping: keepaliveCount)) }
        }

        public var keepaliveIdle = 0 {
            didSet { nw_tcp_options_set_keepalive_idle_time(nw, UInt32(clamping: keepaliveIdle)) }
        }

        public var keepaliveInterval = 0 {
            didSet { nw_tcp_options_set_keepalive_interval(nw, UInt32(clamping: keepaliveInterval)) }
        }

        public var maximumSegmentSize = 0 {
            didSet { nw_tcp_options_set_maximum_segment_size(nw, UInt32(clamping: maximumSegmentSize)) }
        }

        public var connectionTimeout = 0 {
            didSet { nw_tcp_options_set_connection_timeout(nw, UInt32(clamping: connectionTimeout)) }
        }

        public var persistTimeout = 0 {
            didSet { nw_tcp_options_set_persist_timeout(nw, UInt32(clamping: persistTimeout)) }
        }

        public var connectionDropTime = 0 {
            didSet { nw_tcp_options_set_retransmit_connection_drop_time(nw, UInt32(clamping: connectionDropTime)) }
        }

        public var retransmitFinDrop = false {
            didSet { nw_tcp_options_set_retransmit_fin_drop(nw, retransmitFinDrop) }
        }

        public var disableAckStretching = false {
            didSet { nw_tcp_options_set_disable_ack_stretching(nw, disableAckStretching) }
        }

        public var enableFastOpen = false {
            didSet { nw_tcp_options_set_enable_fast_open(nw, enableFastOpen) }
        }

        public var disableECN = false {
            didSet { nw_tcp_options_set_disable_ecn(nw, disableECN) }
        }

        public init() {
            super.init(nw_tcp_create_options())
        }

        override init(_ nw: nw_protocol_options_t) {
            super.init(nw)
        }

        deinit {}
    }

    @_inheritsConvenienceInitializers
    @_hasMissingDesignatedInitializers
    @_objcRuntimeName(_TtCC7Network14_NWProtocolTCP8Metadata)
    public class Metadata: NWProtocolMetadata {
        public var availableReceiveBuffer: UInt32 {
            nw_tcp_get_available_receive_buffer(nw)
        }

        public var availableSendBuffer: UInt32 {
            nw_tcp_get_available_send_buffer(nw)
        }

        /// Limits how fast the connection sends; nil for no limit.
        @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
        public func setMaximumPacingRateBytesPerSecond(_ maximumPacingRateBytesPerSecond: UInt64?) {
            nw_tcp_set_max_pacing_rate(nw, maximumPacingRateBytesPerSecond ?? 0)
        }

        deinit {}
    }

    deinit {}
}

// MARK: - UDP

@_inheritsConvenienceInitializers
@_hasMissingDesignatedInitializers
@available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
@_objcRuntimeName(_TtC7Network14_NWProtocolUDP)
public class NWProtocolUDP: NWProtocol {
    public static let definition = NWProtocolDefinition(nw_protocol_copy_udp_definition(), "udp")

    @_inheritsConvenienceInitializers
    @_hasMissingDesignatedInitializers
    @_objcRuntimeName(_TtCC7Network14_NWProtocolUDP7Options)
    public class Options: NWProtocolOptions {
        public var preferNoChecksum = false {
            didSet { nw_udp_options_set_prefer_no_checksum(nw, preferNoChecksum) }
        }

        public init() {
            super.init(nw_udp_create_options())
        }

        override init(_ nw: nw_protocol_options_t) {
            super.init(nw)
        }

        deinit {}
    }

    @_inheritsConvenienceInitializers
    @_hasMissingDesignatedInitializers
    @_objcRuntimeName(_TtCC7Network14_NWProtocolUDP8Metadata)
    public class Metadata: NWProtocolMetadata {
        public init() {
            super.init(nw_udp_create_metadata())
        }

        override init(_ nw: nw_protocol_metadata_t) {
            super.init(nw)
        }

        deinit {}
    }

    deinit {}
}

// MARK: - TLS

@_inheritsConvenienceInitializers
@_hasMissingDesignatedInitializers
@available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
@_objcRuntimeName(_TtC7Network14_NWProtocolTLS)
public class NWProtocolTLS: NWProtocol {
    public static let definition = NWProtocolDefinition(nw_protocol_copy_tls_definition(), "tls")

    @_inheritsConvenienceInitializers
    @_hasMissingDesignatedInitializers
    @_objcRuntimeName(_TtCC7Network14_NWProtocolTLS7Options)
    public class Options: NWProtocolOptions {
        public var securityProtocolOptions: sec_protocol_options_t {
            nw_tls_copy_sec_protocol_options(nw)
        }

        public init() {
            super.init(nw_tls_create_options())
        }

        override init(_ nw: nw_protocol_options_t) {
            super.init(nw)
        }

        deinit {}
    }

    @_inheritsConvenienceInitializers
    @_hasMissingDesignatedInitializers
    @_objcRuntimeName(_TtCC7Network14_NWProtocolTLS8Metadata)
    public class Metadata: NWProtocolMetadata {
        public var securityProtocolMetadata: sec_protocol_metadata_t {
            nw_tls_copy_sec_protocol_metadata(nw)
        }

        deinit {}
    }

    deinit {}
}

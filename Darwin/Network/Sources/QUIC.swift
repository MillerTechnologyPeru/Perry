// NWProtocolQUIC: QUIC options and connection or stream metadata over the
// C API's nw_quic_* functions.

import Foundation
import Security

@_inheritsConvenienceInitializers
@_hasMissingDesignatedInitializers
@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public class NWProtocolQUIC: NWProtocol {
    public static let definition = NWProtocolDefinition(nw_protocol_copy_quic_definition(), "quic")

    @_inheritsConvenienceInitializers
    @_hasMissingDesignatedInitializers
    public class Options: NWProtocolOptions {
        public init() {
            super.init(nw_quic_create_options())
        }

        override init(_ nw: nw_protocol_options_t) {
            super.init(nw)
        }

        public convenience init(alpn: [String]) {
            self.init()
            self.alpn = alpn
        }

        /// The application protocols TLS offers. The C API only adds them,
        /// so protocols set again are not offered twice and ones taken
        /// out stay offered.
        public var alpn: [String] = [] {
            didSet {
                for name in alpn where !oldValue.contains(name) {
                    nw_quic_add_tls_application_protocol(nw, name)
                }
            }
        }

        public enum Direction: Sendable {
            case bidirectional
            case unidirectional
        }

        public var direction: Direction {
            get { nw_quic_get_stream_is_unidirectional(nw) ? .unidirectional : .bidirectional }
            set { nw_quic_set_stream_is_unidirectional(nw, newValue == .unidirectional) }
        }

        @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
        public var isDatagram: Bool {
            get { nw_quic_get_stream_is_datagram(nw) }
            set { nw_quic_set_stream_is_datagram(nw, newValue) }
        }

        public var securityProtocolOptions: sec_protocol_options_t {
            nw_quic_copy_sec_protocol_options(nw)
        }

        public var idleTimeout: Int {
            get { Int(nw_quic_get_idle_timeout(nw)) }
            set { nw_quic_set_idle_timeout(nw, UInt32(clamping: newValue)) }
        }

        public var maxUDPPayloadSize: Int {
            get { Int(nw_quic_get_max_udp_payload_size(nw)) }
            set { nw_quic_set_max_udp_payload_size(nw, UInt16(clamping: newValue)) }
        }

        public var initialMaxData: Int {
            get { Int(clamping: nw_quic_get_initial_max_data(nw)) }
            set { nw_quic_set_initial_max_data(nw, UInt64(clamping: newValue)) }
        }

        public var initialMaxStreamDataBidirectionalRemote: Int {
            get { Int(clamping: nw_quic_get_initial_max_stream_data_bidirectional_remote(nw)) }
            set { nw_quic_set_initial_max_stream_data_bidirectional_remote(nw, UInt64(clamping: newValue)) }
        }

        public var initialMaxStreamDataBidirectionalLocal: Int {
            get { Int(clamping: nw_quic_get_initial_max_stream_data_bidirectional_local(nw)) }
            set { nw_quic_set_initial_max_stream_data_bidirectional_local(nw, UInt64(clamping: newValue)) }
        }

        public var initialMaxStreamDataUnidirectional: Int {
            get { Int(clamping: nw_quic_get_initial_max_stream_data_unidirectional(nw)) }
            set { nw_quic_set_initial_max_stream_data_unidirectional(nw, UInt64(clamping: newValue)) }
        }

        public var initialMaxStreamsBidirectional: Int {
            get { Int(clamping: nw_quic_get_initial_max_streams_bidirectional(nw)) }
            set { nw_quic_set_initial_max_streams_bidirectional(nw, UInt64(clamping: newValue)) }
        }

        public var initialMaxStreamsUnidirectional: Int {
            get { Int(clamping: nw_quic_get_initial_max_streams_unidirectional(nw)) }
            set { nw_quic_set_initial_max_streams_unidirectional(nw, UInt64(clamping: newValue)) }
        }

        @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
        public var maxDatagramFrameSize: Int {
            get { Int(nw_quic_get_max_datagram_frame_size(nw)) }
            set { nw_quic_set_max_datagram_frame_size(nw, UInt16(clamping: newValue)) }
        }

        deinit {}
    }

    /// The code and reason a QUIC connection or stream was closed with.
    public struct ApplicationError: ExpressibleByIntegerLiteral, Sendable {
        public let code: UInt64
        public let reason: String?

        public init(integerLiteral code: UInt64) {
            self.init(code: code)
        }

        public init(code: UInt64, reason: String? = nil) {
            self.code = code
            self.reason = reason
        }

        @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
        public typealias IntegerLiteralType = UInt64
    }

    @_inheritsConvenienceInitializers
    @_hasMissingDesignatedInitializers
    public class Metadata: NWProtocolMetadata {
        public var securityProtocolMetadata: sec_protocol_metadata_t {
            nw_quic_copy_sec_protocol_metadata(nw)
        }

        public var negotiatedALPN: String? {
            sec_protocol_metadata_get_negotiated_protocol(securityProtocolMetadata).map { String(cString: $0) }
        }

        public var streamIdentifier: UInt64 {
            nw_quic_get_stream_id(nw)
        }

        public var remoteIdleTimeout: Int {
            Int(clamping: nw_quic_get_remote_idle_timeout(nw))
        }

        public var applicationError: ApplicationError {
            get {
                ApplicationError(code: nw_quic_get_application_error(nw),
                                 reason: nw_quic_get_application_error_reason(nw).map { String(cString: $0) })
            }
            set {
                nw_quic_set_application_error(nw, newValue.code, newValue.reason)
            }
        }

        public var streamApplicationErrorCode: UInt64 {
            get { nw_quic_get_stream_application_error(nw) }
            set { nw_quic_set_stream_application_error(nw, newValue) }
        }

        public var localMaxStreamsUnidirectional: Int {
            get { Int(clamping: nw_quic_get_local_max_streams_unidirectional(nw)) }
            set { nw_quic_set_local_max_streams_unidirectional(nw, UInt64(clamping: newValue)) }
        }

        public var remoteMaxStreamsUnidirectional: Int {
            Int(clamping: nw_quic_get_remote_max_streams_unidirectional(nw))
        }

        public var localMaxStreamsBidirectional: Int {
            get { Int(clamping: nw_quic_get_local_max_streams_bidirectional(nw)) }
            set { nw_quic_set_local_max_streams_bidirectional(nw, UInt64(clamping: newValue)) }
        }

        public var remoteMaxStreamsBidirectional: Int {
            Int(clamping: nw_quic_get_remote_max_streams_bidirectional(nw))
        }

        @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
        public var usableDatagramFrameSize: Int {
            Int(nw_quic_get_stream_usable_datagram_frame_size(nw))
        }

        public enum KeepAliveBehavior: Sendable {
            case on
            case off
            case seconds(Int)
        }

        /// Keep-alives: the C API's interval, 0 for none and UINT16_MAX
        /// for its default one.
        public var keepAlive: KeepAliveBehavior {
            get {
                switch nw_quic_get_keepalive_interval(nw) {
                case 0: return .off
                case UInt16.max: return .on
                case let seconds: return .seconds(Int(seconds))
                }
            }
            set {
                switch newValue {
                case .on: nw_quic_set_keepalive_interval(nw, UInt16.max)
                case .off: nw_quic_set_keepalive_interval(nw, 0)
                case .seconds(let seconds): nw_quic_set_keepalive_interval(nw, UInt16(clamping: seconds))
                }
            }
        }

        deinit {}
    }

    deinit {}
}

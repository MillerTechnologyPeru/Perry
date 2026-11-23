import Glibc
import PerryObjCInterop

// Protocol definitions, options and metadata. Options keep the values their
// setters were given, which the connection reads when it builds its
// stack; metadata is what a message or a connection's protocol reports.
// TLS options hold a sec_protocol_options_t, which Security's provider
// makes and keeps.

enum ProtocolKind: Equatable {
    case ip, tcp, udp, tls, quic, webSocket, framer

    var identifier: String {
        switch self {
        case .ip: return "ip"
        case .tcp: return "tcp"
        case .udp: return "udp"
        case .tls: return "tls"
        case .quic: return "quic"
        case .webSocket: return "websocket"
        case .framer: return "framer"
        }
    }
}

// MARK: - Definitions

/// A framer's definition: its name, flags and start handler.
final class FramerDefinition {
    let identifier: String
    let flags: UInt32
    let startHandler: ObjCBlock

    init(identifier: String, flags: UInt32, startHandler: ObjCBlock) {
        self.identifier = identifier
        self.flags = flags
        self.startHandler = startHandler
    }
}

final class DefinitionState: NWState {
    let kind: ProtocolKind
    let identifier: HeldCString
    let framer: FramerDefinition?

    init(kind: ProtocolKind, framer: FramerDefinition? = nil) {
        self.kind = kind
        self.framer = framer
        identifier = HeldCString(framer?.identifier ?? kind.identifier)
    }
}

@ObjCClass("OS_nw_protocol_definition")
open class NWProtocolDefinitionObject: NWObject {}

enum Definitions {
    private static let lock = Lock()
    nonisolated(unsafe) private static var builtIn: [String: UnsafeMutableRawPointer] = [:]

    /// The one definition of a built-in protocol, which lives as long as
    /// the process (+0).
    static func shared(_ kind: ProtocolKind) -> UnsafeMutableRawPointer {
        lock.withLock {
            if let existing = builtIn[kind.identifier] { return existing }
            let made = NWObjects.make(NWProtocolDefinitionObject.objCClass, DefinitionState(kind: kind))
            builtIn[kind.identifier] = made
            return made
        }
    }

    static func state(_ definition: UnsafeMutableRawPointer?) -> DefinitionState? { NWObjects.state(definition, DefinitionState.self) }

    static func kind(_ definition: UnsafeMutableRawPointer?) -> ProtocolKind? { state(definition)?.kind }
}

@c(_nw_protocol_copy_ip_definition)
public func nw_protocol_copy_ip_definition() -> UnsafeMutableRawPointer? { ObjCRuntime.retain(Definitions.shared(.ip)) }

@c(_nw_protocol_copy_tcp_definition)
public func nw_protocol_copy_tcp_definition() -> UnsafeMutableRawPointer? { ObjCRuntime.retain(Definitions.shared(.tcp)) }

@c(_nw_protocol_copy_udp_definition)
public func nw_protocol_copy_udp_definition() -> UnsafeMutableRawPointer? { ObjCRuntime.retain(Definitions.shared(.udp)) }

@c(_nw_protocol_copy_tls_definition)
public func nw_protocol_copy_tls_definition() -> UnsafeMutableRawPointer? { ObjCRuntime.retain(Definitions.shared(.tls)) }

@c(_nw_protocol_copy_quic_definition)
public func nw_protocol_copy_quic_definition() -> UnsafeMutableRawPointer? { ObjCRuntime.retain(Definitions.shared(.quic)) }

@c(_nw_protocol_copy_ws_definition)
public func nw_protocol_copy_ws_definition() -> UnsafeMutableRawPointer? { ObjCRuntime.retain(Definitions.shared(.webSocket)) }

/// The same built-in protocol, or the same framer definition.
@c(_nw_protocol_definition_is_equal)
public func nw_protocol_definition_is_equal(_ first: UnsafeMutableRawPointer?, _ second: UnsafeMutableRawPointer?) -> Bool {
    if first == second { return true }
    guard let a = Definitions.state(first), let b = Definitions.state(second), a.kind == b.kind else { return false }
    if a.kind == .framer { return a.framer === b.framer }
    return true
}

// MARK: - Options

/// QUIC's transport parameters, which options keep; QUIC itself isn't
/// carried here.
struct QUICSettings {
    var idleTimeout: UInt32 = 30_000
    var initialMaxData: UInt64 = 0
    var initialMaxStreamDataBidirectionalLocal: UInt64 = 0
    var initialMaxStreamDataBidirectionalRemote: UInt64 = 0
    var initialMaxStreamDataUnidirectional: UInt64 = 0
    var initialMaxStreamsBidirectional: UInt64 = 0
    var initialMaxStreamsUnidirectional: UInt64 = 0
    var maxDatagramFrameSize: UInt16 = 0
    var maxUDPPayloadSize: UInt16 = 1452
    var streamIsDatagram = false
    var streamIsUnidirectional = false
}

final class OptionsState: NWState {
    let kind: ProtocolKind
    /// The definition (+1).
    let definition: UnsafeMutableRawPointer

    // IP
    var ipVersion: Int32 = 0
    var hopLimit: UInt8 = 0
    var useMinimumMTU = false
    var disableFragmentation = false
    var calculateReceiveTime = false
    var localAddressPreference: Int32 = 0
    var disableMulticastLoopback = false

    // TCP
    var noDelay = false
    var noPush = false
    var noOptions = false
    var enableKeepalive = false
    var keepaliveCount: UInt32 = 0
    var keepaliveIdleTime: UInt32 = 0
    var keepaliveInterval: UInt32 = 0
    var maximumSegmentSize: UInt32 = 0
    var connectionTimeout: UInt32 = 0
    var persistTimeout: UInt32 = 0
    var retransmitConnectionDropTime: UInt32 = 0
    var retransmitFinDrop = false
    var disableAckStretching = false
    var enableFastOpen = false
    var disableECN = false

    // UDP
    var preferNoChecksum = false

    // TLS and QUIC
    var secOptions: UnsafeMutableRawPointer?
    var quic = QUICSettings()

    // WebSocket
    var webSocketVersion: Int32 = 1
    var autoReplyPing = false
    var maximumMessageSize = 0
    var skipHandshake = false
    var subprotocols: [String] = []
    var additionalHeaders: [(String, String)] = []
    var clientRequestHandler: ObjCBlock?
    var clientRequestQueue: UnsafeMutableRawPointer?

    // Framer
    var objectValues: [String: UnsafeMutableRawPointer] = [:]

    init(kind: ProtocolKind, definition: UnsafeMutableRawPointer) {
        self.kind = kind
        self.definition = ObjCRuntime.retain(definition)!
    }

    deinit {
        ObjCRuntime.release(definition)
        ObjCRuntime.release(secOptions)
        ObjCRuntime.release(clientRequestQueue)
        objectValues.values.forEach { ObjCRuntime.release($0) }
    }

    /// The same values in new options; TLS's sec_protocol_options_t and
    /// framer values are shared.
    func copy() -> OptionsState {
        let copy = OptionsState(kind: kind, definition: definition)
        copy.ipVersion = ipVersion
        copy.hopLimit = hopLimit
        copy.useMinimumMTU = useMinimumMTU
        copy.disableFragmentation = disableFragmentation
        copy.calculateReceiveTime = calculateReceiveTime
        copy.localAddressPreference = localAddressPreference
        copy.disableMulticastLoopback = disableMulticastLoopback
        copy.noDelay = noDelay
        copy.noPush = noPush
        copy.noOptions = noOptions
        copy.enableKeepalive = enableKeepalive
        copy.keepaliveCount = keepaliveCount
        copy.keepaliveIdleTime = keepaliveIdleTime
        copy.keepaliveInterval = keepaliveInterval
        copy.maximumSegmentSize = maximumSegmentSize
        copy.connectionTimeout = connectionTimeout
        copy.persistTimeout = persistTimeout
        copy.retransmitConnectionDropTime = retransmitConnectionDropTime
        copy.retransmitFinDrop = retransmitFinDrop
        copy.disableAckStretching = disableAckStretching
        copy.enableFastOpen = enableFastOpen
        copy.disableECN = disableECN
        copy.preferNoChecksum = preferNoChecksum
        copy.secOptions = ObjCRuntime.retain(secOptions)
        copy.quic = quic
        copy.webSocketVersion = webSocketVersion
        copy.autoReplyPing = autoReplyPing
        copy.maximumMessageSize = maximumMessageSize
        copy.skipHandshake = skipHandshake
        copy.subprotocols = subprotocols
        copy.additionalHeaders = additionalHeaders
        copy.clientRequestHandler = clientRequestHandler
        copy.clientRequestQueue = ObjCRuntime.retain(clientRequestQueue)
        copy.objectValues = objectValues.mapValues { ObjCRuntime.retain($0)! }
        return copy
    }

    var framer: FramerDefinition? { Definitions.state(definition)?.framer }
}

@ObjCClass("OS_nw_protocol_options")
open class NWProtocolOptionsObject: NWObject {}

enum Options {
    static func state(_ options: UnsafeMutableRawPointer?) -> OptionsState? { NWObjects.state(options, OptionsState.self) }

    static func state(_ options: UnsafeMutableRawPointer?, _ kind: ProtocolKind) -> OptionsState? {
        guard let state = state(options), state.kind == kind else { return nil }
        return state
    }

    /// New options (+1).
    static func make(_ kind: ProtocolKind) -> UnsafeMutableRawPointer {
        let state = OptionsState(kind: kind, definition: Definitions.shared(kind))
        if kind == .tls || kind == .quic { state.secOptions = SecurityBridge.makeOptions() }
        return NWObjects.make(NWProtocolOptionsObject.objCClass, state)
    }

    static func make(_ state: OptionsState) -> UnsafeMutableRawPointer { NWObjects.make(NWProtocolOptionsObject.objCClass, state) }

    /// A copy of the options (+1).
    static func copy(_ options: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer {
        guard let state = state(options) else { return ObjCRuntime.retain(options)! }
        return make(state.copy())
    }
}

@c(_nw_protocol_options_copy_definition)
public func nw_protocol_options_copy_definition(_ options: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    ObjCRuntime.retain(Options.state(options)?.definition)
}

@c(_nw_protocol_options_is_quic)
public func nw_protocol_options_is_quic(_ options: UnsafeMutableRawPointer?) -> Bool { Options.state(options)?.kind == .quic }

@c(_nw_protocol_options_is_tcp)
public func nw_protocol_options_is_tcp(_ options: UnsafeMutableRawPointer?) -> Bool { Options.state(options)?.kind == .tcp }

@c(_nw_protocol_options_is_udp)
public func nw_protocol_options_is_udp(_ options: UnsafeMutableRawPointer?) -> Bool { Options.state(options)?.kind == .udp }

@c(_nw_protocol_options_is_tls)
public func nw_protocol_options_is_tls(_ options: UnsafeMutableRawPointer?) -> Bool { Options.state(options)?.kind == .tls }

@c(_nw_protocol_options_is_ip)
public func nw_protocol_options_is_ip(_ options: UnsafeMutableRawPointer?) -> Bool { Options.state(options)?.kind == .ip }

@c(_nw_tcp_create_options)
public func nw_tcp_create_options() -> UnsafeMutableRawPointer? { Options.make(.tcp) }

@c(_nw_udp_create_options)
public func nw_udp_create_options() -> UnsafeMutableRawPointer? { Options.make(.udp) }

@c(_nw_tls_create_options)
public func nw_tls_create_options() -> UnsafeMutableRawPointer? { Options.make(.tls) }

@c(_nw_tls_copy_sec_protocol_options)
public func nw_tls_copy_sec_protocol_options(_ options: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    ObjCRuntime.retain(Options.state(options, .tls)?.secOptions)
}

// IP options

@c(_nw_ip_options_set_version)
public func nw_ip_options_set_version(_ options: UnsafeMutableRawPointer?, _ version: Int32) { Options.state(options, .ip)?.ipVersion = version }

@c(_nw_ip_options_set_hop_limit)
public func nw_ip_options_set_hop_limit(_ options: UnsafeMutableRawPointer?, _ limit: UInt8) { Options.state(options, .ip)?.hopLimit = limit }

@c(_nw_ip_options_set_use_minimum_mtu)
public func nw_ip_options_set_use_minimum_mtu(_ options: UnsafeMutableRawPointer?, _ value: Bool) { Options.state(options, .ip)?.useMinimumMTU = value }

@c(_nw_ip_options_set_disable_fragmentation)
public func nw_ip_options_set_disable_fragmentation(_ options: UnsafeMutableRawPointer?, _ value: Bool) {
    Options.state(options, .ip)?.disableFragmentation = value
}

@c(_nw_ip_options_set_calculate_receive_time)
public func nw_ip_options_set_calculate_receive_time(_ options: UnsafeMutableRawPointer?, _ value: Bool) {
    Options.state(options, .ip)?.calculateReceiveTime = value
}

@c(_nw_ip_options_set_local_address_preference)
public func nw_ip_options_set_local_address_preference(_ options: UnsafeMutableRawPointer?, _ value: Int32) {
    Options.state(options, .ip)?.localAddressPreference = value
}

@c(_nw_ip_options_set_disable_multicast_loopback)
public func nw_ip_options_set_disable_multicast_loopback(_ options: UnsafeMutableRawPointer?, _ value: Bool) {
    Options.state(options, .ip)?.disableMulticastLoopback = value
}

// TCP options

@c(_nw_tcp_options_set_no_delay)
public func nw_tcp_options_set_no_delay(_ options: UnsafeMutableRawPointer?, _ value: Bool) { Options.state(options, .tcp)?.noDelay = value }

@c(_nw_tcp_options_set_no_push)
public func nw_tcp_options_set_no_push(_ options: UnsafeMutableRawPointer?, _ value: Bool) { Options.state(options, .tcp)?.noPush = value }

@c(_nw_tcp_options_set_no_options)
public func nw_tcp_options_set_no_options(_ options: UnsafeMutableRawPointer?, _ value: Bool) { Options.state(options, .tcp)?.noOptions = value }

@c(_nw_tcp_options_set_enable_keepalive)
public func nw_tcp_options_set_enable_keepalive(_ options: UnsafeMutableRawPointer?, _ value: Bool) {
    Options.state(options, .tcp)?.enableKeepalive = value
}

@c(_nw_tcp_options_set_keepalive_count)
public func nw_tcp_options_set_keepalive_count(_ options: UnsafeMutableRawPointer?, _ value: UInt32) {
    Options.state(options, .tcp)?.keepaliveCount = value
}

@c(_nw_tcp_options_set_keepalive_idle_time)
public func nw_tcp_options_set_keepalive_idle_time(_ options: UnsafeMutableRawPointer?, _ value: UInt32) {
    Options.state(options, .tcp)?.keepaliveIdleTime = value
}

@c(_nw_tcp_options_set_keepalive_interval)
public func nw_tcp_options_set_keepalive_interval(_ options: UnsafeMutableRawPointer?, _ value: UInt32) {
    Options.state(options, .tcp)?.keepaliveInterval = value
}

@c(_nw_tcp_options_set_maximum_segment_size)
public func nw_tcp_options_set_maximum_segment_size(_ options: UnsafeMutableRawPointer?, _ value: UInt32) {
    Options.state(options, .tcp)?.maximumSegmentSize = value
}

@c(_nw_tcp_options_set_connection_timeout)
public func nw_tcp_options_set_connection_timeout(_ options: UnsafeMutableRawPointer?, _ value: UInt32) {
    Options.state(options, .tcp)?.connectionTimeout = value
}

@c(_nw_tcp_options_set_persist_timeout)
public func nw_tcp_options_set_persist_timeout(_ options: UnsafeMutableRawPointer?, _ value: UInt32) {
    Options.state(options, .tcp)?.persistTimeout = value
}

@c(_nw_tcp_options_set_retransmit_connection_drop_time)
public func nw_tcp_options_set_retransmit_connection_drop_time(_ options: UnsafeMutableRawPointer?, _ value: UInt32) {
    Options.state(options, .tcp)?.retransmitConnectionDropTime = value
}

@c(_nw_tcp_options_set_retransmit_fin_drop)
public func nw_tcp_options_set_retransmit_fin_drop(_ options: UnsafeMutableRawPointer?, _ value: Bool) {
    Options.state(options, .tcp)?.retransmitFinDrop = value
}

@c(_nw_tcp_options_set_disable_ack_stretching)
public func nw_tcp_options_set_disable_ack_stretching(_ options: UnsafeMutableRawPointer?, _ value: Bool) {
    Options.state(options, .tcp)?.disableAckStretching = value
}

@c(_nw_tcp_options_set_enable_fast_open)
public func nw_tcp_options_set_enable_fast_open(_ options: UnsafeMutableRawPointer?, _ value: Bool) {
    Options.state(options, .tcp)?.enableFastOpen = value
}

@c(_nw_tcp_options_set_disable_ecn)
public func nw_tcp_options_set_disable_ecn(_ options: UnsafeMutableRawPointer?, _ value: Bool) { Options.state(options, .tcp)?.disableECN = value }

// UDP options

@c(_nw_udp_options_set_prefer_no_checksum)
public func nw_udp_options_set_prefer_no_checksum(_ options: UnsafeMutableRawPointer?, _ value: Bool) {
    Options.state(options, .udp)?.preferNoChecksum = value
}

// MARK: - Metadata

final class MetadataState: NWState {
    let kind: ProtocolKind
    /// The definition (+1).
    let definition: UnsafeMutableRawPointer

    // IP
    var ecnFlag: Int32 = 0
    var serviceClass: Int32 = 0
    var receiveTime: UInt64 = 0

    // TCP: the connection's socket, for its buffers.
    var socket: Int32 = -1

    // TLS and QUIC: the sec_protocol_metadata_t (+1).
    var secMetadata: UnsafeMutableRawPointer?

    // QUIC
    var applicationError: UInt64 = 0
    var applicationErrorReason = HeldCString(nil)
    var keepaliveInterval: UInt16 = 0
    var localMaxStreamsBidirectional: UInt64 = 0
    var localMaxStreamsUnidirectional: UInt64 = 0

    // WebSocket
    var opcode: Int32 = -1
    var closeCode: Int32 = 1000
    var pongHandler: ObjCBlock?
    var pongQueue: UnsafeMutableRawPointer?
    var serverResponse: UnsafeMutableRawPointer?

    // Framer messages: values by key, objects (+1) and C values with their
    // dispose blocks.
    var objectValues: [String: UnsafeMutableRawPointer] = [:]
    var values: [String: (UnsafeMutableRawPointer?, ObjCBlock?)] = [:]

    init(kind: ProtocolKind, definition: UnsafeMutableRawPointer) {
        self.kind = kind
        self.definition = ObjCRuntime.retain(definition)!
    }

    deinit {
        ObjCRuntime.release(definition)
        ObjCRuntime.release(secMetadata)
        ObjCRuntime.release(pongQueue)
        ObjCRuntime.release(serverResponse)
        objectValues.values.forEach { ObjCRuntime.release($0) }
        for (value, dispose) in values.values { dispose?.call(value) }
    }
}

@ObjCClass("OS_nw_protocol_metadata")
open class NWProtocolMetadataObject: NWObject {}

enum Metadata {
    static func state(_ metadata: UnsafeMutableRawPointer?) -> MetadataState? { NWObjects.state(metadata, MetadataState.self) }

    static func state(_ metadata: UnsafeMutableRawPointer?, _ kind: ProtocolKind) -> MetadataState? {
        guard let state = state(metadata), state.kind == kind else { return nil }
        return state
    }

    /// New metadata (+1).
    static func make(_ kind: ProtocolKind, definition: UnsafeMutableRawPointer? = nil) -> (UnsafeMutableRawPointer, MetadataState) {
        let state = MetadataState(kind: kind, definition: definition ?? Definitions.shared(kind))
        return (NWObjects.make(NWProtocolMetadataObject.objCClass, state), state)
    }
}

@c(_nw_protocol_metadata_copy_definition)
public func nw_protocol_metadata_copy_definition(_ metadata: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    ObjCRuntime.retain(Metadata.state(metadata)?.definition)
}

@c(_nw_protocol_metadata_is_ip)
public func nw_protocol_metadata_is_ip(_ metadata: UnsafeMutableRawPointer?) -> Bool { Metadata.state(metadata)?.kind == .ip }

@c(_nw_protocol_metadata_is_tcp)
public func nw_protocol_metadata_is_tcp(_ metadata: UnsafeMutableRawPointer?) -> Bool { Metadata.state(metadata)?.kind == .tcp }

@c(_nw_protocol_metadata_is_udp)
public func nw_protocol_metadata_is_udp(_ metadata: UnsafeMutableRawPointer?) -> Bool { Metadata.state(metadata)?.kind == .udp }

@c(_nw_protocol_metadata_is_tls)
public func nw_protocol_metadata_is_tls(_ metadata: UnsafeMutableRawPointer?) -> Bool { Metadata.state(metadata)?.kind == .tls }

@c(_nw_protocol_metadata_is_quic)
public func nw_protocol_metadata_is_quic(_ metadata: UnsafeMutableRawPointer?) -> Bool { Metadata.state(metadata)?.kind == .quic }

@c(_nw_protocol_metadata_is_ws)
public func nw_protocol_metadata_is_ws(_ metadata: UnsafeMutableRawPointer?) -> Bool { Metadata.state(metadata)?.kind == .webSocket }

@c(_nw_protocol_metadata_is_framer_message)
public func nw_protocol_metadata_is_framer_message(_ metadata: UnsafeMutableRawPointer?) -> Bool {
    Metadata.state(metadata)?.kind == .framer
}

@c(_nw_ip_create_metadata)
public func nw_ip_create_metadata() -> UnsafeMutableRawPointer? { Metadata.make(.ip).0 }

@c(_nw_udp_create_metadata)
public func nw_udp_create_metadata() -> UnsafeMutableRawPointer? { Metadata.make(.udp).0 }

@c(_nw_ip_metadata_set_ecn_flag)
public func nw_ip_metadata_set_ecn_flag(_ metadata: UnsafeMutableRawPointer?, _ flag: Int32) { Metadata.state(metadata, .ip)?.ecnFlag = flag }

@c(_nw_ip_metadata_get_ecn_flag)
public func nw_ip_metadata_get_ecn_flag(_ metadata: UnsafeMutableRawPointer?) -> Int32 { Metadata.state(metadata, .ip)?.ecnFlag ?? 0 }

@c(_nw_ip_metadata_set_service_class)
public func nw_ip_metadata_set_service_class(_ metadata: UnsafeMutableRawPointer?, _ value: Int32) {
    Metadata.state(metadata, .ip)?.serviceClass = value
}

@c(_nw_ip_metadata_get_service_class)
public func nw_ip_metadata_get_service_class(_ metadata: UnsafeMutableRawPointer?) -> Int32 { Metadata.state(metadata, .ip)?.serviceClass ?? 0 }

/// When the packet arrived, in mach_continuous_time nanoseconds; 0 when not asked for.
@c(_nw_ip_metadata_get_receive_time)
public func nw_ip_metadata_get_receive_time(_ metadata: UnsafeMutableRawPointer?) -> UInt64 { Metadata.state(metadata, .ip)?.receiveTime ?? 0 }

/// The bytes waiting to be read on the connection's socket.
@c(_nw_tcp_get_available_receive_buffer)
public func nw_tcp_get_available_receive_buffer(_ metadata: UnsafeMutableRawPointer?) -> UInt32 {
    guard let socket = Metadata.state(metadata, .tcp)?.socket, socket >= 0 else { return 0 }
    var count: Int32 = 0
    let status = withUnsafeMutablePointer(to: &count) { ioctl(socket, UInt(FIONREAD), $0) }
    return status == 0 ? UInt32(max(0, count)) : 0
}

/// Room left in the socket's send buffer.
@c(_nw_tcp_get_available_send_buffer)
public func nw_tcp_get_available_send_buffer(_ metadata: UnsafeMutableRawPointer?) -> UInt32 {
    guard let socket = Metadata.state(metadata, .tcp)?.socket, socket >= 0 else { return 0 }
    var queued: Int32 = 0
    var size: Int32 = 0
    var length = socklen_t(MemoryLayout<Int32>.size)
    let status = withUnsafeMutablePointer(to: &queued) { ioctl(socket, UInt(TIOCOUTQ), $0) }
    guard status == 0, getsockopt(socket, SOL_SOCKET, SO_SNDBUF, &size, &length) == 0 else { return 0 }
    return UInt32(max(0, size - queued))
}

/// SO_MAX_PACING_RATE; 0 on success, an errno otherwise.
@c(_nw_tcp_set_max_pacing_rate)
public func nw_tcp_set_max_pacing_rate(_ metadata: UnsafeMutableRawPointer?, _ rate: UInt64) -> Int32 {
    guard let socket = Metadata.state(metadata, .tcp)?.socket, socket >= 0 else { return 22 }
    var value = rate
    return setsockopt(socket, SOL_SOCKET, SO_MAX_PACING_RATE, &value, socklen_t(MemoryLayout<UInt64>.size)) == 0
        ? 0 : DarwinErrno.from(linux: errno)
}

@c(_nw_tls_copy_sec_protocol_metadata)
public func nw_tls_copy_sec_protocol_metadata(_ metadata: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    ObjCRuntime.retain(Metadata.state(metadata, .tls)?.secMetadata)
}

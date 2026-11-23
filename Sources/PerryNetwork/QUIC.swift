import Glibc
import PerryObjCInterop

// QUIC's options and metadata. Options keep their transport parameters and
// TLS settings, so programs that build QUIC parameters run; a connection,
// listener or group that would carry QUIC fails with EPROTONOSUPPORT, as
// QUIC itself isn't implemented here.

@c(_nw_quic_create_options)
public func nw_quic_create_options() -> UnsafeMutableRawPointer? { Options.make(.quic) }

@c(_nw_quic_copy_sec_protocol_options)
public func nw_quic_copy_sec_protocol_options(_ options: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    ObjCRuntime.retain(Options.state(options, .quic)?.secOptions)
}

@c(_nw_quic_copy_sec_protocol_metadata)
public func nw_quic_copy_sec_protocol_metadata(_ metadata: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    ObjCRuntime.retain(Metadata.state(metadata, .quic)?.secMetadata)
}

/// ALPN, which QUIC needs, on the options' TLS settings.
@c(_nw_quic_add_tls_application_protocol)
public func nw_quic_add_tls_application_protocol(_ options: UnsafeMutableRawPointer?, _ name: UnsafePointer<CChar>?) {
    guard let secOptions = Options.state(options, .quic)?.secOptions,
          let add = lookupSymbol(securityFramework, "_sec_protocol_options_add_tls_application_protocol") else { return }
    typealias Add = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> Void
    unsafeBitCast(add, to: Add.self)(secOptions, name)
}

private func quic(_ options: UnsafeMutableRawPointer?) -> OptionsState? { Options.state(options, .quic) }
private func quicMetadata(_ metadata: UnsafeMutableRawPointer?) -> MetadataState? { Metadata.state(metadata, .quic) }

@c(_nw_quic_get_stream_is_unidirectional)
public func nw_quic_get_stream_is_unidirectional(_ options: UnsafeMutableRawPointer?) -> Bool { quic(options)?.quic.streamIsUnidirectional ?? false }

@c(_nw_quic_set_stream_is_unidirectional)
public func nw_quic_set_stream_is_unidirectional(_ options: UnsafeMutableRawPointer?, _ value: Bool) {
    quic(options)?.quic.streamIsUnidirectional = value
}

@c(_nw_quic_get_stream_is_datagram)
public func nw_quic_get_stream_is_datagram(_ options: UnsafeMutableRawPointer?) -> Bool { quic(options)?.quic.streamIsDatagram ?? false }

@c(_nw_quic_set_stream_is_datagram)
public func nw_quic_set_stream_is_datagram(_ options: UnsafeMutableRawPointer?, _ value: Bool) { quic(options)?.quic.streamIsDatagram = value }

@c(_nw_quic_get_idle_timeout)
public func nw_quic_get_idle_timeout(_ options: UnsafeMutableRawPointer?) -> UInt32 { quic(options)?.quic.idleTimeout ?? 0 }

@c(_nw_quic_set_idle_timeout)
public func nw_quic_set_idle_timeout(_ options: UnsafeMutableRawPointer?, _ value: UInt32) { quic(options)?.quic.idleTimeout = value }

@c(_nw_quic_get_max_udp_payload_size)
public func nw_quic_get_max_udp_payload_size(_ options: UnsafeMutableRawPointer?) -> UInt16 { quic(options)?.quic.maxUDPPayloadSize ?? 0 }

@c(_nw_quic_set_max_udp_payload_size)
public func nw_quic_set_max_udp_payload_size(_ options: UnsafeMutableRawPointer?, _ value: UInt16) { quic(options)?.quic.maxUDPPayloadSize = value }

@c(_nw_quic_get_initial_max_data)
public func nw_quic_get_initial_max_data(_ options: UnsafeMutableRawPointer?) -> UInt64 { quic(options)?.quic.initialMaxData ?? 0 }

@c(_nw_quic_set_initial_max_data)
public func nw_quic_set_initial_max_data(_ options: UnsafeMutableRawPointer?, _ value: UInt64) { quic(options)?.quic.initialMaxData = value }

@c(_nw_quic_get_initial_max_stream_data_bidirectional_local)
public func nw_quic_get_initial_max_stream_data_bidirectional_local(_ options: UnsafeMutableRawPointer?) -> UInt64 {
    quic(options)?.quic.initialMaxStreamDataBidirectionalLocal ?? 0
}

@c(_nw_quic_set_initial_max_stream_data_bidirectional_local)
public func nw_quic_set_initial_max_stream_data_bidirectional_local(_ options: UnsafeMutableRawPointer?, _ value: UInt64) {
    quic(options)?.quic.initialMaxStreamDataBidirectionalLocal = value
}

@c(_nw_quic_get_initial_max_stream_data_bidirectional_remote)
public func nw_quic_get_initial_max_stream_data_bidirectional_remote(_ options: UnsafeMutableRawPointer?) -> UInt64 {
    quic(options)?.quic.initialMaxStreamDataBidirectionalRemote ?? 0
}

@c(_nw_quic_set_initial_max_stream_data_bidirectional_remote)
public func nw_quic_set_initial_max_stream_data_bidirectional_remote(_ options: UnsafeMutableRawPointer?, _ value: UInt64) {
    quic(options)?.quic.initialMaxStreamDataBidirectionalRemote = value
}

@c(_nw_quic_get_initial_max_stream_data_unidirectional)
public func nw_quic_get_initial_max_stream_data_unidirectional(_ options: UnsafeMutableRawPointer?) -> UInt64 {
    quic(options)?.quic.initialMaxStreamDataUnidirectional ?? 0
}

@c(_nw_quic_set_initial_max_stream_data_unidirectional)
public func nw_quic_set_initial_max_stream_data_unidirectional(_ options: UnsafeMutableRawPointer?, _ value: UInt64) {
    quic(options)?.quic.initialMaxStreamDataUnidirectional = value
}

@c(_nw_quic_get_initial_max_streams_bidirectional)
public func nw_quic_get_initial_max_streams_bidirectional(_ options: UnsafeMutableRawPointer?) -> UInt64 {
    quic(options)?.quic.initialMaxStreamsBidirectional ?? 0
}

@c(_nw_quic_set_initial_max_streams_bidirectional)
public func nw_quic_set_initial_max_streams_bidirectional(_ options: UnsafeMutableRawPointer?, _ value: UInt64) {
    quic(options)?.quic.initialMaxStreamsBidirectional = value
}

@c(_nw_quic_get_initial_max_streams_unidirectional)
public func nw_quic_get_initial_max_streams_unidirectional(_ options: UnsafeMutableRawPointer?) -> UInt64 {
    quic(options)?.quic.initialMaxStreamsUnidirectional ?? 0
}

@c(_nw_quic_set_initial_max_streams_unidirectional)
public func nw_quic_set_initial_max_streams_unidirectional(_ options: UnsafeMutableRawPointer?, _ value: UInt64) {
    quic(options)?.quic.initialMaxStreamsUnidirectional = value
}

@c(_nw_quic_get_max_datagram_frame_size)
public func nw_quic_get_max_datagram_frame_size(_ options: UnsafeMutableRawPointer?) -> UInt16 { quic(options)?.quic.maxDatagramFrameSize ?? 0 }

@c(_nw_quic_set_max_datagram_frame_size)
public func nw_quic_set_max_datagram_frame_size(_ options: UnsafeMutableRawPointer?, _ value: UInt16) {
    quic(options)?.quic.maxDatagramFrameSize = value
}

// Metadata, which no QUIC connection makes here: answers for metadata the
// program made itself.

@c(_nw_quic_get_stream_id)
public func nw_quic_get_stream_id(_ metadata: UnsafeMutableRawPointer?) -> UInt64 { 0 }

@c(_nw_quic_get_stream_usable_datagram_frame_size)
public func nw_quic_get_stream_usable_datagram_frame_size(_ metadata: UnsafeMutableRawPointer?) -> UInt16 { 0 }

@c(_nw_quic_get_stream_application_error)
public func nw_quic_get_stream_application_error(_ metadata: UnsafeMutableRawPointer?) -> UInt64 {
    quicMetadata(metadata)?.applicationError ?? UInt64.max
}

@c(_nw_quic_set_stream_application_error)
public func nw_quic_set_stream_application_error(_ metadata: UnsafeMutableRawPointer?, _ value: UInt64) {
    quicMetadata(metadata)?.applicationError = value
}

@c(_nw_quic_get_application_error)
public func nw_quic_get_application_error(_ metadata: UnsafeMutableRawPointer?) -> UInt64 { quicMetadata(metadata)?.applicationError ?? UInt64.max }

@c(_nw_quic_get_application_error_reason)
public func nw_quic_get_application_error_reason(_ metadata: UnsafeMutableRawPointer?) -> UnsafePointer<CChar>? {
    quicMetadata(metadata)?.applicationErrorReason.value
}

@c(_nw_quic_set_application_error)
public func nw_quic_set_application_error(_ metadata: UnsafeMutableRawPointer?, _ value: UInt64, _ reason: UnsafePointer<CChar>?) {
    guard let state = quicMetadata(metadata) else { return }
    state.applicationError = value
    state.applicationErrorReason = HeldCString(reason.map { String(cString: $0) })
}

@c(_nw_quic_get_keepalive_interval)
public func nw_quic_get_keepalive_interval(_ metadata: UnsafeMutableRawPointer?) -> UInt16 { quicMetadata(metadata)?.keepaliveInterval ?? 0 }

@c(_nw_quic_set_keepalive_interval)
public func nw_quic_set_keepalive_interval(_ metadata: UnsafeMutableRawPointer?, _ value: UInt16) {
    quicMetadata(metadata)?.keepaliveInterval = value
}

@c(_nw_quic_get_remote_idle_timeout)
public func nw_quic_get_remote_idle_timeout(_ metadata: UnsafeMutableRawPointer?) -> UInt64 { 0 }

@c(_nw_quic_get_local_max_streams_bidirectional)
public func nw_quic_get_local_max_streams_bidirectional(_ metadata: UnsafeMutableRawPointer?) -> UInt64 {
    quicMetadata(metadata)?.localMaxStreamsBidirectional ?? 0
}

@c(_nw_quic_set_local_max_streams_bidirectional)
public func nw_quic_set_local_max_streams_bidirectional(_ metadata: UnsafeMutableRawPointer?, _ value: UInt64) {
    quicMetadata(metadata)?.localMaxStreamsBidirectional = value
}

@c(_nw_quic_get_local_max_streams_unidirectional)
public func nw_quic_get_local_max_streams_unidirectional(_ metadata: UnsafeMutableRawPointer?) -> UInt64 {
    quicMetadata(metadata)?.localMaxStreamsUnidirectional ?? 0
}

@c(_nw_quic_set_local_max_streams_unidirectional)
public func nw_quic_set_local_max_streams_unidirectional(_ metadata: UnsafeMutableRawPointer?, _ value: UInt64) {
    quicMetadata(metadata)?.localMaxStreamsUnidirectional = value
}

@c(_nw_quic_get_remote_max_streams_bidirectional)
public func nw_quic_get_remote_max_streams_bidirectional(_ metadata: UnsafeMutableRawPointer?) -> UInt64 { 0 }

@c(_nw_quic_get_remote_max_streams_unidirectional)
public func nw_quic_get_remote_max_streams_unidirectional(_ metadata: UnsafeMutableRawPointer?) -> UInt64 { 0 }

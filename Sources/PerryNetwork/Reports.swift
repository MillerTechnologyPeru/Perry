import Glibc
import PerryObjCInterop

// Establishment reports (how long the connection took to set up, its name
// lookup and each protocol's handshake) and data transfer reports (bytes
// and packets between a report's creation and its collection, and TCP's
// round-trip times, from TCP_INFO). Connections have one path, with no
// proxy.

final class ResolutionReportState: NWState {
    let source: Int32
    let milliseconds: UInt64
    let endpointCount: UInt32
    let successful: UnsafeMutableRawPointer?
    let preferred: UnsafeMutableRawPointer?

    init(source: Int32, milliseconds: UInt64, endpointCount: UInt32, successful: UnsafeMutableRawPointer?, preferred: UnsafeMutableRawPointer?) {
        self.source = source
        self.milliseconds = milliseconds
        self.endpointCount = endpointCount
        self.successful = ObjCRuntime.retain(successful)
        self.preferred = ObjCRuntime.retain(preferred)
    }

    deinit {
        ObjCRuntime.release(successful)
        ObjCRuntime.release(preferred)
    }
}

@ObjCClass("OS_nw_resolution_report")
open class NWResolutionReportObject: NWObject {}

final class EstablishmentReportState: NWState {
    var duration: UInt64 = 0
    var previousAttempts: UInt32 = 0
    var resolutions: [UnsafeMutableRawPointer] = []
    var protocols: [(UnsafeMutableRawPointer, UInt64, UInt64)] = []

    deinit { resolutions.forEach { ObjCRuntime.release($0) } }
}

@ObjCClass("OS_nw_establishment_report")
open class NWEstablishmentReportObject: NWObject {}

private func establishment(_ report: UnsafeMutableRawPointer?) -> EstablishmentReportState? {
    NWObjects.state(report, EstablishmentReportState.self)
}

private func resolution(_ report: UnsafeMutableRawPointer?) -> ResolutionReportState? { NWObjects.state(report, ResolutionReportState.self) }

/// The report of a ready connection (+1), from its connection's queue.
private func makeEstablishmentReport(_ connection: ConnectionState) -> UnsafeMutableRawPointer? {
    guard connection.readyTime != 0, let transport = connection.transport else { return nil }
    let state = EstablishmentReportState()
    state.duration = connection.readyTime - connection.startTime
    state.previousAttempts = UInt32(max(0, transport.attempts - 1))
    if connection.resolvedFromQuery {
        let successful = transport.remoteAddress.map { Endpoints.make(address: $0) }
        let report = NWObjects.make(NWResolutionReportObject.objCClass,
                                    ResolutionReportState(source: 1, milliseconds: connection.resolutionMilliseconds,
                                                          endpointCount: UInt32(connection.resolvedCount), successful: successful,
                                                          preferred: successful))
        ObjCRuntime.release(successful)
        state.resolutions.append(report)
    }
    let roundTrip = transport.roundTrip.smoothed
    let others = connection.handshakeTimes.reduce(0) { $0 + $1.1 }
    let resolving = connection.resolvedFromQuery ? connection.resolutionMilliseconds : 0
    let transportTime = state.duration > others + resolving ? state.duration - others - resolving : 0
    state.protocols.append((Definitions.shared(transport.isStream ? .tcp : .udp), transportTime, roundTrip))
    for (kind, time) in connection.handshakeTimes where kind != .framer {
        state.protocols.append((Definitions.shared(kind), time, roundTrip))
    }
    return NWObjects.make(NWEstablishmentReportObject.objCClass, state)
}

@c(_nw_connection_access_establishment_report)
public func nw_connection_access_establishment_report(_ connection: UnsafeMutableRawPointer?, _ queue: UnsafeMutableRawPointer?,
                                                      _ block: UnsafeMutableRawPointer?) {
    guard let state = Connections.state(connection), let block = ObjCBlock.from(block) else { return }
    let held = ObjCRuntime.retain(queue)
    Dispatch.on(state.queue) {
        let report = makeEstablishmentReport(state)
        Dispatch.on(held) {
            block.call(report)
            ObjCRuntime.release(report)
            ObjCRuntime.release(held)
        }
    }
}

@c(_nw_establishment_report_get_duration_milliseconds)
public func nw_establishment_report_get_duration_milliseconds(_ report: UnsafeMutableRawPointer?) -> UInt64 { establishment(report)?.duration ?? 0 }

@c(_nw_establishment_report_get_attempt_started_after_milliseconds)
public func nw_establishment_report_get_attempt_started_after_milliseconds(_ report: UnsafeMutableRawPointer?) -> UInt64 { 0 }

@c(_nw_establishment_report_get_previous_attempt_count)
public func nw_establishment_report_get_previous_attempt_count(_ report: UnsafeMutableRawPointer?) -> UInt32 {
    establishment(report)?.previousAttempts ?? 0
}

@c(_nw_establishment_report_get_used_proxy)
public func nw_establishment_report_get_used_proxy(_ report: UnsafeMutableRawPointer?) -> Bool { false }

@c(_nw_establishment_report_get_proxy_configured)
public func nw_establishment_report_get_proxy_configured(_ report: UnsafeMutableRawPointer?) -> Bool { false }

@c(_nw_establishment_report_copy_proxy_endpoint)
public func nw_establishment_report_copy_proxy_endpoint(_ report: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { nil }

/// Each protocol with its handshake's milliseconds and round trip.
@c(_nw_establishment_report_enumerate_protocols)
public func nw_establishment_report_enumerate_protocols(_ report: UnsafeMutableRawPointer?, _ block: UnsafeMutableRawPointer?) {
    guard let state = establishment(report), let block = ObjCBlock.from(block) else { return }
    typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UInt64, UInt64) -> Bool
    for (definition, time, roundTrip) in state.protocols where !block.function(as: Invoke.self)(block.object, definition, time, roundTrip) { break }
}

@c(_nw_establishment_report_enumerate_resolution_reports)
public func nw_establishment_report_enumerate_resolution_reports(_ report: UnsafeMutableRawPointer?, _ block: UnsafeMutableRawPointer?) {
    guard let state = establishment(report), let block = ObjCBlock.from(block) else { return }
    for resolution in state.resolutions where !block.test(resolution) { break }
}

/// The older form: source, milliseconds, endpoint count, successful and
/// preferred endpoint.
@c(_nw_establishment_report_enumerate_resolutions)
public func nw_establishment_report_enumerate_resolutions(_ report: UnsafeMutableRawPointer?, _ block: UnsafeMutableRawPointer?) {
    guard let state = establishment(report), let block = ObjCBlock.from(block) else { return }
    typealias Invoke = @convention(c) (UnsafeMutableRawPointer, Int32, UInt64, UInt32, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Bool
    for object in state.resolutions {
        guard let entry = resolution(object) else { continue }
        if !block.function(as: Invoke.self)(block.object, entry.source, entry.milliseconds, entry.endpointCount, entry.successful, entry.preferred) {
            break
        }
    }
}

@c(_nw_resolution_report_get_source)
public func nw_resolution_report_get_source(_ report: UnsafeMutableRawPointer?) -> Int32 { resolution(report)?.source ?? 1 }

@c(_nw_resolution_report_get_milliseconds)
public func nw_resolution_report_get_milliseconds(_ report: UnsafeMutableRawPointer?) -> UInt64 { resolution(report)?.milliseconds ?? 0 }

@c(_nw_resolution_report_get_endpoint_count)
public func nw_resolution_report_get_endpoint_count(_ report: UnsafeMutableRawPointer?) -> UInt32 { resolution(report)?.endpointCount ?? 0 }

@c(_nw_resolution_report_copy_successful_endpoint)
public func nw_resolution_report_copy_successful_endpoint(_ report: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    ObjCRuntime.retain(resolution(report)?.successful)
}

@c(_nw_resolution_report_copy_preferred_endpoint)
public func nw_resolution_report_copy_preferred_endpoint(_ report: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    ObjCRuntime.retain(resolution(report)?.preferred)
}

/// nw_report_resolution_protocol_t: the system resolver asks over UDP.
@c(_nw_resolution_report_get_protocol)
public func nw_resolution_report_get_protocol(_ report: UnsafeMutableRawPointer?) -> Int32 { 1 }

// MARK: - Data transfer reports

private struct TransferCounters {
    var time: UInt64 = 0
    var applicationSent: UInt64 = 0
    var applicationReceived: UInt64 = 0
    var transportSent: UInt64 = 0
    var transportReceived: UInt64 = 0
    var packetsSent: UInt64 = 0
    var packetsReceived: UInt64 = 0
    var retransmitted: UInt64 = 0

    init() {}

    init(_ connection: ConnectionState) {
        time = monotonicMilliseconds()
        applicationSent = connection.applicationBytesSent
        applicationReceived = connection.applicationBytesReceived
        if let transport = connection.transport {
            transportSent = transport.bytesSent
            transportReceived = transport.bytesReceived
            packetsSent = transport.packetsSent
            packetsReceived = transport.packetsReceived
            retransmitted = transport.roundTrip.retransmitted
        }
    }
}

final class DataTransferReportState: NWState {
    weak var connection: ConnectionState?
    fileprivate var start = TransferCounters()
    fileprivate var end = TransferCounters()
    var collected = false
    var roundTrip: (smoothed: UInt64, variance: UInt64, retransmitted: UInt64) = (0, 0, 0)
    var interface: InterfaceInfo?
}

@ObjCClass("OS_nw_data_transfer_report")
open class NWDataTransferReportObject: NWObject {}

private func transfer(_ report: UnsafeMutableRawPointer?) -> DataTransferReportState? {
    NWObjects.state(report, DataTransferReportState.self)
}

@c(_nw_connection_create_new_data_transfer_report)
public func nw_connection_create_new_data_transfer_report(_ connection: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let state = Connections.state(connection) else { return nil }
    let report = DataTransferReportState()
    report.connection = state
    report.start = TransferCounters(state)
    return NWObjects.make(NWDataTransferReportObject.objCClass, report)
}

@c(_nw_data_transfer_report_collect)
public func nw_data_transfer_report_collect(_ object: UnsafeMutableRawPointer?, _ queue: UnsafeMutableRawPointer?, _ block: UnsafeMutableRawPointer?) {
    guard let report = transfer(object), let object, let block = ObjCBlock.from(block) else { return }
    _ = ObjCRuntime.retain(object)
    let held = ObjCRuntime.retain(queue)
    let finish = {
        if !report.collected, let connection = report.connection {
            report.end = TransferCounters(connection)
            report.roundTrip = connection.transport?.roundTrip ?? (0, 0, 0)
            report.interface = Interfaces.with(address: connection.transport?.localAddress)
        } else if !report.collected {
            report.end = report.start
        }
        report.collected = true
        Dispatch.on(held) {
            block.call(object)
            ObjCRuntime.release(object)
            ObjCRuntime.release(held)
        }
    }
    if let connection = report.connection { Dispatch.on(connection.queue, finish) } else { finish() }
}

/// nw_data_transfer_report_state_t: collecting 1, collected 2.
@c(_nw_data_transfer_report_get_state)
public func nw_data_transfer_report_get_state(_ object: UnsafeMutableRawPointer?) -> Int32 { transfer(object)?.collected == true ? 2 : 1 }

@c(_nw_data_transfer_report_get_duration_milliseconds)
public func nw_data_transfer_report_get_duration_milliseconds(_ object: UnsafeMutableRawPointer?) -> UInt64 {
    guard let report = transfer(object), report.collected else { return 0 }
    return report.end.time - report.start.time
}

@c(_nw_data_transfer_report_get_path_count)
public func nw_data_transfer_report_get_path_count(_ object: UnsafeMutableRawPointer?) -> UInt32 { transfer(object)?.collected == true ? 1 : 0 }

private func difference(_ object: UnsafeMutableRawPointer?, _ path: UInt32, _ value: (TransferCounters) -> UInt64) -> UInt64 {
    guard let report = transfer(object), report.collected, path == 0 || path == UInt32.max else { return 0 }
    let (end, start) = (value(report.end), value(report.start))
    return end > start ? end - start : 0
}

@c(_nw_data_transfer_report_get_received_application_byte_count)
public func nw_data_transfer_report_get_received_application_byte_count(_ object: UnsafeMutableRawPointer?, _ path: UInt32) -> UInt64 {
    difference(object, path) { $0.applicationReceived }
}

@c(_nw_data_transfer_report_get_sent_application_byte_count)
public func nw_data_transfer_report_get_sent_application_byte_count(_ object: UnsafeMutableRawPointer?, _ path: UInt32) -> UInt64 {
    difference(object, path) { $0.applicationSent }
}

@c(_nw_data_transfer_report_get_received_transport_byte_count)
public func nw_data_transfer_report_get_received_transport_byte_count(_ object: UnsafeMutableRawPointer?, _ path: UInt32) -> UInt64 {
    difference(object, path) { $0.transportReceived }
}

@c(_nw_data_transfer_report_get_sent_transport_byte_count)
public func nw_data_transfer_report_get_sent_transport_byte_count(_ object: UnsafeMutableRawPointer?, _ path: UInt32) -> UInt64 {
    difference(object, path) { $0.transportSent }
}

@c(_nw_data_transfer_report_get_received_ip_packet_count)
public func nw_data_transfer_report_get_received_ip_packet_count(_ object: UnsafeMutableRawPointer?, _ path: UInt32) -> UInt64 {
    difference(object, path) { $0.packetsReceived }
}

@c(_nw_data_transfer_report_get_sent_ip_packet_count)
public func nw_data_transfer_report_get_sent_ip_packet_count(_ object: UnsafeMutableRawPointer?, _ path: UInt32) -> UInt64 {
    difference(object, path) { $0.packetsSent }
}

@c(_nw_data_transfer_report_get_received_transport_duplicate_byte_count)
public func nw_data_transfer_report_get_received_transport_duplicate_byte_count(_ object: UnsafeMutableRawPointer?, _ path: UInt32) -> UInt64 { 0 }

@c(_nw_data_transfer_report_get_received_transport_out_of_order_byte_count)
public func nw_data_transfer_report_get_received_transport_out_of_order_byte_count(_ object: UnsafeMutableRawPointer?, _ path: UInt32) -> UInt64 { 0 }

@c(_nw_data_transfer_report_get_sent_transport_retransmitted_byte_count)
public func nw_data_transfer_report_get_sent_transport_retransmitted_byte_count(_ object: UnsafeMutableRawPointer?, _ path: UInt32) -> UInt64 {
    difference(object, path) { $0.retransmitted }
}

@c(_nw_data_transfer_report_get_transport_smoothed_rtt_milliseconds)
public func nw_data_transfer_report_get_transport_smoothed_rtt_milliseconds(_ object: UnsafeMutableRawPointer?, _ path: UInt32) -> UInt64 {
    transfer(object)?.roundTrip.smoothed ?? 0
}

/// TCP_INFO has no minimum; the smoothed time stands for it.
@c(_nw_data_transfer_report_get_transport_minimum_rtt_milliseconds)
public func nw_data_transfer_report_get_transport_minimum_rtt_milliseconds(_ object: UnsafeMutableRawPointer?, _ path: UInt32) -> UInt64 {
    transfer(object)?.roundTrip.smoothed ?? 0
}

@c(_nw_data_transfer_report_get_transport_rtt_variance)
public func nw_data_transfer_report_get_transport_rtt_variance(_ object: UnsafeMutableRawPointer?, _ path: UInt32) -> UInt64 {
    transfer(object)?.roundTrip.variance ?? 0
}

/// nw_interface_radio_type_t: unknown, or Wi-Fi's 802.11ac for a Wi-Fi link.
@c(_nw_data_transfer_report_get_path_radio_type)
public func nw_data_transfer_report_get_path_radio_type(_ object: UnsafeMutableRawPointer?, _ path: UInt32) -> Int32 {
    transfer(object)?.interface?.type == InterfaceType.wifi ? 5 : 0
}

@c(_nw_data_transfer_report_copy_path_interface)
public func nw_data_transfer_report_copy_path_interface(_ object: UnsafeMutableRawPointer?, _ path: UInt32) -> UnsafeMutableRawPointer? {
    transfer(object)?.interface?.object()
}

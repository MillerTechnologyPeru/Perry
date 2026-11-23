// NWConnection over the C API's nw_connection_t: its states and events,
// sending and receiving with content contexts, and its establishment and
// data transfer reports.

import Dispatch
import Foundation

/// nw_connection_send, declared with its completion as a block so the
/// idempotent-content block constant is passed as it is (the C API knows
/// it by its address) instead of wrapped in a new block.
@_silgen_name("nw_connection_send")
private func nwConnectionSend(_ connection: nw_connection_t, _ content: __DispatchData?, _ context: nw_content_context_t, _ isComplete: Bool, _ completion: @convention(block) (nw_error_t?) -> Void)

@_hasMissingDesignatedInitializers
@available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
@_objcRuntimeName(_TtC7Network13_NWConnection)
final public class NWConnection: CustomDebugStringConvertible {
    let nw: nw_connection_t
    private let lock = NSLock()
    private var storedState: State = .setup
    private var storedQueue: DispatchQueue?
    private var storedStateHandler: (@Sendable (State) -> Void)?
    private var storedPathHandler: (@Sendable (NWPath) -> Void)?
    private var storedViabilityHandler: (@Sendable (Bool) -> Void)?
    private var storedBetterPathHandler: (@Sendable (Bool) -> Void)?
    private var started = false

    final public var debugDescription: String {
        String(cString: nw_connection_copy_description(nw))
    }

    public enum State: Equatable, Sendable {
        case setup
        case waiting(NWError)
        case preparing
        case ready
        case failed(NWError)
        case cancelled

        public static func == (a: State, b: State) -> Bool {
            switch (a, b) {
            case (.setup, .setup), (.preparing, .preparing), (.ready, .ready), (.cancelled, .cancelled): return true
            case let (.waiting(x), .waiting(y)), let (.failed(x), .failed(y)): return x == y
            default: return false
            }
        }

        init(_ state: nw_connection_state_t, _ error: nw_error_t?) {
            let error = NWError(error) ?? .posix(.ECONNABORTED)
            switch state {
            case nw_connection_state_waiting: self = .waiting(error)
            case nw_connection_state_preparing: self = .preparing
            case nw_connection_state_ready: self = .ready
            case nw_connection_state_failed: self = .failed(error)
            case nw_connection_state_cancelled: self = .cancelled
            default: self = .setup
            }
        }
    }

    final public var state: State {
        lock.withLock { storedState }
    }

    @preconcurrency final public var stateUpdateHandler: (@Sendable (_ state: State) -> Void)? {
        get { lock.withLock { storedStateHandler } }
        set { lock.withLock { storedStateHandler = newValue } }
    }

    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    final public var maximumDatagramSize: Int {
        Int(nw_connection_get_maximum_datagram_size(nw))
    }

    final public var currentPath: NWPath? {
        nw_connection_copy_current_path(nw).map(NWPath.init)
    }

    @preconcurrency final public var pathUpdateHandler: (@Sendable (_ newPath: NWPath) -> Void)? {
        get { lock.withLock { storedPathHandler } }
        set { lock.withLock { storedPathHandler = newValue } }
    }

    @preconcurrency final public var viabilityUpdateHandler: (@Sendable (_ newIsViable: Bool) -> Void)? {
        get { lock.withLock { storedViabilityHandler } }
        set { lock.withLock { storedViabilityHandler = newValue } }
    }

    @preconcurrency final public var betterPathUpdateHandler: (@Sendable (_ newHasBetterPath: Bool) -> Void)? {
        get { lock.withLock { storedBetterPathHandler } }
        set { lock.withLock { storedBetterPathHandler = newValue } }
    }

    final public let endpoint: NWEndpoint
    final public let parameters: NWParameters

    public init(to: NWEndpoint, using: NWParameters) {
        endpoint = to
        parameters = using
        nw = nw_connection_create(to.nw, using.nw)
    }

    /// A connection of the C API's, one a listener or group made.
    init(_ connection: nw_connection_t) {
        nw = connection
        endpoint = NWEndpoint(nw_connection_copy_endpoint(connection))
        parameters = NWParameters(nw_connection_copy_parameters(connection))
    }

    public convenience init(host: NWEndpoint.Host, port: NWEndpoint.Port, using: NWParameters) {
        self.init(to: .hostPort(host: host, port: port), using: using)
    }

    /// Starts the connection on the queue its handlers are called on. The
    /// C API's handlers hold the connection until it is cancelled or fails.
    final public func start(queue: DispatchQueue) {
        let first = lock.withLock { () -> Bool in
            storedQueue = queue
            defer { started = true }
            return !started
        }
        guard first else { return }
        nw_connection_set_queue(nw, queue)
        nw_connection_set_state_changed_handler(nw) { state, error in
            self.update(State(state, error))
        }
        nw_connection_set_path_changed_handler(nw) { path in
            self.pathUpdateHandler?(NWPath(path))
        }
        nw_connection_set_viability_changed_handler(nw) { viable in
            self.viabilityUpdateHandler?(viable)
        }
        nw_connection_set_better_path_available_handler(nw) { better in
            self.betterPathUpdateHandler?(better)
        }
        nw_connection_start(nw)
    }

    private func update(_ state: State) {
        let handler = lock.withLock { () -> (@Sendable (State) -> Void)? in
            storedState = state
            return storedStateHandler
        }
        handler?(state)
        if state == .cancelled {
            // Lets the connection go: the handlers hold it.
            nw_connection_set_state_changed_handler(nw, nil)
            nw_connection_set_path_changed_handler(nw, nil)
            nw_connection_set_viability_changed_handler(nw, nil)
            nw_connection_set_better_path_available_handler(nw, nil)
        }
    }

    final public var queue: DispatchQueue? {
        lock.withLock { storedQueue }
    }

    final public func cancel() {
        nw_connection_cancel(nw)
    }

    final public func forceCancel() {
        nw_connection_force_cancel(nw)
    }

    final public func cancelCurrentEndpoint() {
        nw_connection_cancel_current_endpoint(nw)
    }

    final public func restart() {
        nw_connection_restart(nw)
    }

    /// What is sent or received together: a message, or the stream.
    @_hasMissingDesignatedInitializers
    @_objcRuntimeName(_TtCC7Network13_NWConnection14ContentContext)
    public class ContentContext: @unchecked Sendable {
        let nw: nw_content_context_t
        final public let identifier: String
        final public let expirationMilliseconds: UInt64
        final public let relativePriority: Double
        final public let antecedent: ContentContext?
        final public let isFinal: Bool

        /// A context the C API gave, as it is.
        init(_ context: nw_content_context_t) {
            nw = context
            identifier = String(cString: nw_content_context_get_identifier(context))
            expirationMilliseconds = nw_content_context_get_expiration_milliseconds(context)
            relativePriority = nw_content_context_get_relative_priority(context)
            antecedent = nw_content_context_copy_antecedent(context).map(ContentContext.init)
            isFinal = nw_content_context_get_is_final(context)
        }

        public var protocolMetadata: [NWProtocolMetadata] {
            var metadata: [NWProtocolMetadata] = []
            nw_content_context_foreach_protocol_metadata(nw) { _, value in
                metadata.append(NWProtocolMetadata.wrap(value))
            }
            return metadata
        }

        public func protocolMetadata(definition: NWProtocolDefinition) -> NWProtocolMetadata? {
            nw_content_context_copy_protocol_metadata(nw, definition.nw).map(NWProtocolMetadata.wrap)
        }

        public init(identifier: String, expiration: UInt64 = 0, priority: Double = 0.5, isFinal: Bool = false, antecedent: ContentContext? = nil, metadata: [NWProtocolMetadata]? = []) {
            nw = nw_content_context_create(identifier)
            self.identifier = identifier
            expirationMilliseconds = expiration
            relativePriority = priority
            self.isFinal = isFinal
            self.antecedent = antecedent
            nw_content_context_set_expiration_milliseconds(nw, expiration)
            nw_content_context_set_relative_priority(nw, priority)
            nw_content_context_set_is_final(nw, isFinal)
            nw_content_context_set_antecedent(nw, antecedent?.nw)
            for item in metadata ?? [] {
                nw_content_context_set_metadata_for_protocol(nw, item.nw)
            }
        }

        /// A message on its own: the C API's default message context.
        public static let defaultMessage = ContentContext(_nw_content_context_default_message)
        /// The last message: after it the connection is done sending.
        public static let finalMessage = ContentContext(_nw_content_context_final_send)
        /// The connection's one stream, final once complete.
        public static let defaultStream = ContentContext(_nw_content_context_default_stream)

        deinit {}
    }

    @preconcurrency
    final public func receive(minimumIncompleteLength: Int, maximumLength: Int, completion: @escaping @Sendable (_ content: Data?, _ contentContext: ContentContext?, _ isComplete: Bool, _ error: NWError?) -> Void) {
        nw_connection_receive(nw, UInt32(clamping: minimumIncompleteLength), UInt32(clamping: maximumLength)) { content, context, isComplete, error in
            completion(data(of: content), context.map(ContentContext.init), isComplete, NWError(error))
        }
    }

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
    @preconcurrency
    final public func receiveDiscontiguous(minimumIncompleteLength: Int, maximumLength: Int, completion: @escaping @Sendable (_ content: DispatchData?, _ contentContext: ContentContext?, _ isComplete: Bool, _ error: NWError?) -> Void) {
        nw_connection_receive(nw, UInt32(clamping: minimumIncompleteLength), UInt32(clamping: maximumLength)) { content, context, isComplete, error in
            completion(dispatchData(of: content), context.map(ContentContext.init), isComplete, NWError(error))
        }
    }

    @preconcurrency
    final public func receiveMessage(completion: @escaping @Sendable (_ content: Data?, _ contentContext: ContentContext?, _ isComplete: Bool, _ error: NWError?) -> Void) {
        nw_connection_receive_message(nw) { content, context, isComplete, error in
            completion(data(of: content), context.map(ContentContext.init), isComplete, NWError(error))
        }
    }

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
    @preconcurrency
    final public func receiveMessageDiscontiguous(completion: @escaping @Sendable (_ content: DispatchData?, _ contentContext: ContentContext?, _ isComplete: Bool, _ error: NWError?) -> Void) {
        nw_connection_receive_message(nw) { content, context, isComplete, error in
            completion(dispatchData(of: content), context.map(ContentContext.init), isComplete, NWError(error))
        }
    }

    public enum SendCompletion {
        /// Called once the content was sent, or with why it wasn't.
        @preconcurrency case contentProcessed(@Sendable (_ error: NWError?) -> Void)
        /// The content may be sent more than once (with TCP Fast Open's
        /// data, say), and nothing is called.
        case idempotent

        var block: @convention(block) (nw_error_t?) -> Void {
            switch self {
            case .contentProcessed(let handler):
                return { error in handler(NWError(error)) }
            case .idempotent:
                return _nw_connection_send_idempotent_content
            }
        }
    }

    @preconcurrency
    final public func send(content: Data?, contentContext: ContentContext = .defaultMessage, isComplete: Bool = true, completion: SendCompletion) {
        let data = content.map { bytes in
            bytes.withUnsafeBytes { DispatchData(bytes: $0) }._bridgeToObjectiveC()
        }
        nwConnectionSend(nw, data, contentContext.nw, isComplete, completion.block)
    }

    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    @usableFromInline
    @preconcurrency
    final internal func send(discontiguousContent: DispatchData, contentContext: ContentContext = .defaultMessage, isComplete: Bool = true, completion: SendCompletion) {
        nwConnectionSend(nw, discontiguousContent._bridgeToObjectiveC(), contentContext.nw, isComplete, completion.block)
    }

    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    @preconcurrency
    @inlinable
    final public func send<Content>(content: Content?, contentContext: ContentContext = .defaultMessage, isComplete: Bool = true, completion: SendCompletion) where Content: DataProtocol {
        guard let content else {
            send(content: nil as Data?, contentContext: contentContext, isComplete: isComplete, completion: completion)
            return
        }
        if let pieces = content as? DispatchData {
            send(discontiguousContent: pieces, contentContext: contentContext, isComplete: isComplete, completion: completion)
        } else {
            send(content: content as? Data ?? Data(content), contentContext: contentContext, isComplete: isComplete, completion: completion)
        }
    }

    /// Runs the block with the connection's sends and receives batched.
    final public func batch(_ block: () -> Void) {
        withoutActuallyEscaping(block) { block in
            nw_connection_batch(nw, block)
        }
    }

    final public func metadata(definition: NWProtocolDefinition) -> NWProtocolMetadata? {
        nw_connection_copy_protocol_metadata(nw, definition.nw).map(NWProtocolMetadata.wrap)
    }

    /// How the connection was established: name resolution, protocol
    /// handshakes and attempts.
    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    public struct EstablishmentReport: CustomDebugStringConvertible, Sendable {
        public var debugDescription: String {
            var lines = ["Establishment report: \(duration)s, attempt started after \(attemptStartedAfterInterval)s, \(previousAttemptCount) previous attempts"]
            if usedProxy, let proxyEndpoint { lines.append("Proxy: \(proxyEndpoint.debugDescription)") }
            for resolution in resolutions {
                lines.append("Resolution: \(resolution.source) \(resolution.duration)s, \(resolution.endpointCount) endpoints, \(resolution.successfulEndpoint.debugDescription)")
            }
            for handshake in handshakes {
                lines.append("Handshake: \(handshake.definition.name) \(handshake.handshakeDuration)s, RTT \(handshake.handshakeRTT)s")
            }
            return lines.joined(separator: "\n")
        }

        public let duration: TimeInterval
        public let attemptStartedAfterInterval: TimeInterval
        public let previousAttemptCount: Int
        public let usedProxy: Bool
        public let proxyConfigured: Bool
        public let proxyEndpoint: NWEndpoint?

        public struct Resolution: Sendable {
            public enum Source: Sendable {
                case query
                case cache
                case expiredCache
            }

            public let source: Source
            public let duration: TimeInterval
            public let endpointCount: Int
            public let successfulEndpoint: NWEndpoint
            public let preferredEndpoint: NWEndpoint

            @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
            public enum DNSProtocol: Sendable {
                case unknown
                case udp
                case tcp
                case tls
                case https
            }

            private let storedProtocol: nw_report_resolution_protocol_t

            @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
            public var dnsProtocol: DNSProtocol {
                switch storedProtocol {
                case nw_report_resolution_protocol_udp: return .udp
                case nw_report_resolution_protocol_tcp: return .tcp
                case nw_report_resolution_protocol_tls: return .tls
                case nw_report_resolution_protocol_https: return .https
                default: return .unknown
                }
            }

            init(_ report: nw_resolution_report_t) {
                switch nw_resolution_report_get_source(report) {
                case nw_report_resolution_source_cache: source = .cache
                case nw_report_resolution_source_expired_cache: source = .expiredCache
                default: source = .query
                }
                duration = TimeInterval(nw_resolution_report_get_milliseconds(report)) / 1000
                endpointCount = Int(nw_resolution_report_get_endpoint_count(report))
                successfulEndpoint = NWEndpoint(nw_resolution_report_copy_successful_endpoint(report))
                preferredEndpoint = NWEndpoint(nw_resolution_report_copy_preferred_endpoint(report))
                storedProtocol = nw_resolution_report_get_protocol(report)
            }
        }

        public let resolutions: [Resolution]

        public struct Handshake: Sendable {
            public let definition: NWProtocolDefinition
            public let handshakeDuration: TimeInterval
            public let handshakeRTT: TimeInterval
        }

        public let handshakes: [Handshake]

        init(_ report: nw_establishment_report_t) {
            duration = TimeInterval(nw_establishment_report_get_duration_milliseconds(report)) / 1000
            attemptStartedAfterInterval = TimeInterval(nw_establishment_report_get_attempt_started_after_milliseconds(report)) / 1000
            previousAttemptCount = Int(nw_establishment_report_get_previous_attempt_count(report))
            usedProxy = nw_establishment_report_get_used_proxy(report)
            proxyConfigured = nw_establishment_report_get_proxy_configured(report)
            proxyEndpoint = nw_establishment_report_copy_proxy_endpoint(report).map(NWEndpoint.init)
            var resolutions: [Resolution] = []
            nw_establishment_report_enumerate_resolution_reports(report) { resolution in
                resolutions.append(Resolution(resolution))
                return true
            }
            self.resolutions = resolutions
            var handshakes: [Handshake] = []
            nw_establishment_report_enumerate_protocols(report) { definition, milliseconds, rtt in
                handshakes.append(Handshake(definition: knownDefinition(definition),
                                            handshakeDuration: TimeInterval(milliseconds) / 1000,
                                            handshakeRTT: TimeInterval(rtt) / 1000))
                return true
            }
            self.handshakes = handshakes
        }
    }

    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    @preconcurrency
    final public func requestEstablishmentReport(queue: DispatchQueue, completion: @escaping @Sendable (_ report: EstablishmentReport?) -> Void) {
        nw_connection_access_establishment_report(nw, queue) { report in
            completion(report.map(EstablishmentReport.init))
        }
    }

    /// The data a connection sent and received while a report ran, in all
    /// and on each path.
    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    public struct DataTransferReport: CustomDebugStringConvertible, Sendable {
        public var debugDescription: String {
            let total = aggregatePathReport
            return "Data transfer report: \(duration)s, sent \(total.sentApplicationByteCount) bytes, received \(total.receivedApplicationByteCount) bytes over \(pathReports.count) paths"
        }

        public let duration: TimeInterval

        public struct PathReport: Sendable {
            public let interface: NWInterface
            private let storedRadio: nw_interface_radio_type_t

            @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
            public var radioType: NWInterface.RadioType? {
                NWInterface.RadioType(storedRadio)
            }

            public let receivedIPPacketCount: UInt64
            public let sentIPPacketCount: UInt64
            public let receivedTransportByteCount: UInt64
            public let receivedTransportDuplicateByteCount: UInt64
            public let receivedTransportOutOfOrderByteCount: UInt64
            public let sentTransportByteCount: UInt64
            public let retransmittedTransportByteCount: UInt64
            public let transportSmoothedRTT: TimeInterval
            public let transportMinimumRTT: TimeInterval
            public let transportRTTVariance: TimeInterval
            public let receivedApplicationByteCount: UInt64
            public let sentApplicationByteCount: UInt64

            init(_ report: nw_data_transfer_report_t, path: UInt32, interface: NWInterface) {
                self.interface = interface
                storedRadio = path == UInt32.max ? nw_interface_radio_type_unknown : nw_data_transfer_report_get_path_radio_type(report, path)
                receivedIPPacketCount = nw_data_transfer_report_get_received_ip_packet_count(report, path)
                sentIPPacketCount = nw_data_transfer_report_get_sent_ip_packet_count(report, path)
                receivedTransportByteCount = nw_data_transfer_report_get_received_transport_byte_count(report, path)
                receivedTransportDuplicateByteCount = nw_data_transfer_report_get_received_transport_duplicate_byte_count(report, path)
                receivedTransportOutOfOrderByteCount = nw_data_transfer_report_get_received_transport_out_of_order_byte_count(report, path)
                sentTransportByteCount = nw_data_transfer_report_get_sent_transport_byte_count(report, path)
                retransmittedTransportByteCount = nw_data_transfer_report_get_sent_transport_retransmitted_byte_count(report, path)
                let rttPath = path == UInt32.max ? 0 : path
                transportSmoothedRTT = TimeInterval(nw_data_transfer_report_get_transport_smoothed_rtt_milliseconds(report, rttPath)) / 1000
                transportMinimumRTT = TimeInterval(nw_data_transfer_report_get_transport_minimum_rtt_milliseconds(report, rttPath)) / 1000
                transportRTTVariance = TimeInterval(nw_data_transfer_report_get_transport_rtt_variance(report, rttPath)) / 1000
                receivedApplicationByteCount = nw_data_transfer_report_get_received_application_byte_count(report, path)
                sentApplicationByteCount = nw_data_transfer_report_get_sent_application_byte_count(report, path)
            }
        }

        public let aggregatePathReport: PathReport
        public let pathReports: [PathReport]

        init(_ report: nw_data_transfer_report_t) {
            duration = TimeInterval(nw_data_transfer_report_get_duration_milliseconds(report)) / 1000
            let count = nw_data_transfer_report_get_path_count(report)
            var paths: [PathReport] = []
            for path in 0..<count {
                let interface = NWInterface(nw_data_transfer_report_copy_path_interface(report, path))
                paths.append(PathReport(report, path: path, interface: interface))
            }
            pathReports = paths
            // NW_ALL_PATHS is UINT32_MAX: the paths summed.
            aggregatePathReport = PathReport(report, path: UInt32.max, interface: paths.first?.interface ?? NWInterface(index: 1) ?? loopbackInterface)
        }
    }

    /// A data transfer report running until it is collected.
    @_hasMissingDesignatedInitializers
    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    public class PendingDataTransferReport: @unchecked Sendable {
        let nw: nw_data_transfer_report_t

        init(_ report: nw_data_transfer_report_t) {
            nw = report
        }

        @preconcurrency
        public func collect(queue: DispatchQueue, completion: @escaping @Sendable (_ report: DataTransferReport) -> Void) {
            nw_data_transfer_report_collect(nw, queue) { report in
                completion(DataTransferReport(report))
            }
        }

        deinit {}
    }

    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    final public func startDataTransferReport() -> PendingDataTransferReport {
        PendingDataTransferReport(nw_connection_create_new_data_transfer_report(nw))
    }

    deinit {}
}

/// The Swift value of a C API's dispatch data.
func dispatchData(of data: __DispatchData?) -> DispatchData? {
    data.map { DispatchData._unconditionallyBridgeFromObjectiveC($0) }
}

/// The bytes of a C API's dispatch data.
func data(of data: __DispatchData?) -> Data? {
    guard let pieces = dispatchData(of: data) else { return nil }
    // Region by region through Dispatch's own API (Foundation's `regions`
    // isn't in every Foundation a runtime directory has).
    var bytes = Data(capacity: pieces.count)
    pieces.enumerateBytes { buffer, _, _ in
        bytes.append(buffer)
    }
    return bytes
}

/// An interface for a report without one: the loopback interface, by name.
private let loopbackInterface = NWInterface(name: "lo0") ?? NWInterface(index: 1)!

/// The definition object of a C API definition: the shared one of a known
/// protocol, else one named by the protocol.
@available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
func knownDefinition(_ definition: nw_protocol_definition_t) -> NWProtocolDefinition {
    var known: [NWProtocolDefinition] = [NWProtocolTCP.definition, NWProtocolUDP.definition, NWProtocolIP.definition, NWProtocolTLS.definition]
    if #available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *) {
        known.append(NWProtocolWebSocket.definition)
    }
    if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
        known.append(NWProtocolQUIC.definition)
    }
    for candidate in known where nw_protocol_definition_is_equal(candidate.nw, definition) {
        return candidate
    }
    return NWProtocolDefinition(definition, definition.description)
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
extension NWConnection: @unchecked Sendable {}

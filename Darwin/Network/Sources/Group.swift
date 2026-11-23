// NWConnectionGroup over the C API's nw_connection_group_t: multicast
// groups and multiplexed (QUIC) connections, with their messages.

import Dispatch
import Foundation

@available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
public protocol NWGroupDescriptor: AnyObject, Sendable {
    var members: [NWEndpoint] { get }
}

@available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
private func members(of descriptor: nw_group_descriptor_t) -> [NWEndpoint] {
    var members: [NWEndpoint] = []
    nw_group_descriptor_enumerate_endpoints(descriptor) { endpoint in
        members.append(NWEndpoint(endpoint))
        return true
    }
    return members
}

/// The C API's descriptor of a group.
@available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
private func nwDescriptor(of descriptor: any NWGroupDescriptor) -> nw_group_descriptor_t {
    if let multicast = descriptor as? NWMulticastGroup { return multicast.nw }
    if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *), let multiplex = descriptor as? NWMultiplexGroup {
        return multiplex.nw
    }
    // A descriptor of the app's own: a multicast group of its members.
    let members = descriptor.members
    let group = nw_group_descriptor_create_multicast(members.first?.nw ?? NWEndpoint.hostPort(host: .ipv4(.any), port: .any).nw)
    for member in members.dropFirst() {
        _ = nw_group_descriptor_add_endpoint(group, member.nw)
    }
    return group
}

/// A group of multicast addresses to join, optionally from one source.
@_hasMissingDesignatedInitializers
@available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
public class NWMulticastGroup: NWGroupDescriptor, @unchecked Sendable {
    let nw: nw_group_descriptor_t

    public var members: [NWEndpoint] {
        Network.members(of: nw)
    }

    final public let sourceFilter: NWEndpoint?
    final public let isUnicastDisabled: Bool

    public init(for groupAddresses: [NWEndpoint], from: NWEndpoint? = nil, disableUnicast: Bool = false) throws {
        guard let first = groupAddresses.first else { throw NWError.posix(.EINVAL) }
        nw = nw_group_descriptor_create_multicast(first.nw)
        for address in groupAddresses.dropFirst() {
            guard nw_group_descriptor_add_endpoint(nw, address.nw) else { throw NWError.posix(.EINVAL) }
        }
        if let from {
            nw_multicast_group_descriptor_set_specific_source(nw, from.nw)
        }
        nw_multicast_group_descriptor_set_disable_unicast_traffic(nw, disableUnicast)
        sourceFilter = from
        isUnicastDisabled = disableUnicast
    }

    deinit {}
}

/// The streams of a multiplexed connection (QUIC) to one endpoint.
@_hasMissingDesignatedInitializers
@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public class NWMultiplexGroup: NWGroupDescriptor, @unchecked Sendable {
    let nw: nw_group_descriptor_t

    public var members: [NWEndpoint] {
        Network.members(of: nw)
    }

    public init(to: NWEndpoint) {
        nw = nw_group_descriptor_create_multiplex(to.nw)
    }

    init(_ descriptor: nw_group_descriptor_t) {
        nw = descriptor
    }

    deinit {}
}

@_hasMissingDesignatedInitializers
@available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
final public class NWConnectionGroup: CustomDebugStringConvertible {
    let nw: nw_connection_group_t
    private let lock = NSLock()
    private var storedState: State = .setup
    private var storedQueue: DispatchQueue?
    private var storedStateHandler: (@Sendable (State) -> Void)?
    private var storedConnectionHandler: (@Sendable (NWConnection) -> Void)?
    private var started = false

    final public var debugDescription: String {
        "NWConnectionGroup \(descriptor.members.map(\.debugDescription))"
    }

    public enum State: Equatable, Sendable {
        case setup
        case waiting(NWError)
        case ready
        case failed(NWError)
        case cancelled

        public static func == (a: State, b: State) -> Bool {
            switch (a, b) {
            case (.setup, .setup), (.ready, .ready), (.cancelled, .cancelled): return true
            case let (.waiting(x), .waiting(y)), let (.failed(x), .failed(y)): return x == y
            default: return false
            }
        }

        init(_ state: nw_connection_group_state_t, _ error: nw_error_t?) {
            let error = NWError(error) ?? .posix(.ECONNABORTED)
            switch state {
            case nw_connection_group_state_waiting: self = .waiting(error)
            case nw_connection_group_state_ready: self = .ready
            case nw_connection_group_state_failed: self = .failed(error)
            case nw_connection_group_state_cancelled: self = .cancelled
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

    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    final public func metadata(definition: NWProtocolDefinition) -> NWProtocolMetadata? {
        nw_connection_group_copy_protocol_metadata(nw, definition.nw).map(NWProtocolMetadata.wrap)
    }

    /// A message the group received, or one to send.
    @_inheritsConvenienceInitializers
    @_hasMissingDesignatedInitializers
    public class Message: NWConnection.ContentContext {
        /// The group the message came to, for those received.
        private var group: nw_connection_group_t?

        public static let `default` = Message(nw: _nw_content_context_default_message)

        public var remoteEndpoint: NWEndpoint? {
            group.flatMap { nw_connection_group_copy_remote_endpoint_for_message($0, nw) }.map(NWEndpoint.init)
        }

        public var localEndpoint: NWEndpoint? {
            group.flatMap { nw_connection_group_copy_local_endpoint_for_message($0, nw) }.map(NWEndpoint.init)
        }

        @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
        public func metadata(definition: NWProtocolDefinition) -> NWProtocolMetadata? {
            group.flatMap { nw_connection_group_copy_protocol_metadata_for_message($0, nw, definition.nw) }.map(NWProtocolMetadata.wrap)
        }

        public var path: NWPath? {
            group.flatMap { nw_connection_group_copy_path_for_message($0, nw) }.map(NWPath.init)
        }

        /// Answers the sender of a received message.
        public func reply(content: Data?, message: Message = .default) {
            guard let group else { return }
            let data = content.map { bytes in bytes.withUnsafeBytes { DispatchData(bytes: $0) }._bridgeToObjectiveC() }
            nw_connection_group_reply(group, nw, message.nw, data)
        }

        /// A connection to the sender of a received message.
        public func extractConnection() -> NWConnection? {
            guard let group, let connection = nw_connection_group_extract_connection_for_message(group, nw) else { return nil }
            return NWConnection(connection)
        }

        override public init(identifier: String, expiration: UInt64 = 0, priority: Double = 0.5, isFinal: Bool = false, antecedent: NWConnection.ContentContext? = nil, metadata: [NWProtocolMetadata]? = []) {
            super.init(identifier: identifier, expiration: expiration, priority: priority, isFinal: isFinal, antecedent: antecedent, metadata: metadata)
        }

        @available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
        public init(nw: nw_content_context_t) {
            super.init(nw)
        }

        init(_ context: nw_content_context_t, group: nw_connection_group_t) {
            self.group = group
            super.init(context)
        }

        override init(_ context: nw_content_context_t) {
            super.init(context)
        }

        deinit {}
    }

    @preconcurrency
    final public func setReceiveHandler(maximumMessageSize: Int = Int.max, rejectOversizedMessages: Bool = true, handler: (@Sendable (_ message: Message, _ content: Data?, _ isComplete: Bool) -> Void)?) {
        guard let handler else {
            nw_connection_group_set_receive_handler(nw, UInt32(clamping: maximumMessageSize), rejectOversizedMessages, nil)
            return
        }
        let group = nw
        nw_connection_group_set_receive_handler(nw, UInt32(clamping: maximumMessageSize), rejectOversizedMessages) { content, context, isComplete in
            handler(Message(context, group: group), data(of: content), isComplete)
        }
    }

    @preconcurrency
    final public func send(content: Data?, to: NWEndpoint? = nil, message: Message = .default, completion: @escaping (_ error: NWError?) -> Void) {
        let data = content.map { bytes in bytes.withUnsafeBytes { DispatchData(bytes: $0) }._bridgeToObjectiveC() }
        nw_connection_group_send_message(nw, data, to?.nw, message.nw) { error in
            completion(NWError(error))
        }
    }

    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    @preconcurrency final public var newConnectionHandler: (@Sendable (_ connection: NWConnection) -> Void)? {
        get { lock.withLock { storedConnectionHandler } }
        set {
            lock.withLock { storedConnectionHandler = newValue }
            if newValue == nil {
                nw_connection_group_set_new_connection_handler(nw, nil)
            } else {
                nw_connection_group_set_new_connection_handler(nw) { [weak self] connection in
                    self?.newConnectionHandler?(NWConnection(connection))
                }
            }
        }
    }

    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    final public func extract(connectionTo: NWEndpoint? = nil, using: NWProtocolOptions? = nil) -> NWConnection? {
        nw_connection_group_extract_connection(nw, connectionTo?.nw, using?.nw).map(NWConnection.init)
    }

    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    final public func reinsert(connection: NWConnection) -> Bool {
        nw_connection_group_reinsert_extracted_connection(nw, connection.nw)
    }

    final public let descriptor: any NWGroupDescriptor
    final public let parameters: NWParameters

    public init(with: any NWGroupDescriptor, using: NWParameters) {
        descriptor = with
        parameters = using
        nw = nw_connection_group_create(nwDescriptor(of: with), using.nw)
    }

    /// A group of the C API's, one a listener made.
    init(_ group: nw_connection_group_t) {
        nw = group
        if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
            descriptor = NWMultiplexGroup(nw_connection_group_copy_descriptor(group))
        } else {
            descriptor = (try? NWMulticastGroup(for: Network.members(of: nw_connection_group_copy_descriptor(group))))
                ?? (try! NWMulticastGroup(for: [.hostPort(host: .ipv4(.any), port: .any)]))
        }
        parameters = NWParameters(nw_connection_group_copy_parameters(group))
    }

    /// Starts the group. The C API's handlers hold it until it is cancelled.
    final public func start(queue: DispatchQueue) {
        let first = lock.withLock { () -> Bool in
            storedQueue = queue
            defer { started = true }
            return !started
        }
        guard first else { return }
        nw_connection_group_set_queue(nw, queue)
        nw_connection_group_set_state_changed_handler(nw) { state, error in
            self.update(State(state, error))
        }
        nw_connection_group_start(nw)
    }

    private func update(_ state: State) {
        let handler = lock.withLock { () -> (@Sendable (State) -> Void)? in
            storedState = state
            return storedStateHandler
        }
        handler?(state)
        if state == .cancelled {
            nw_connection_group_set_state_changed_handler(nw, nil)
        }
    }

    final public var queue: DispatchQueue? {
        lock.withLock { storedQueue }
    }

    final public func cancel() {
        nw_connection_group_cancel(nw)
    }

    deinit {}
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
extension NWConnectionGroup: @unchecked Sendable {}

@available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
extension NWConnection {
    /// A connection to the sender of a message a group received.
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    public convenience init?(message: NWConnectionGroup.Message) {
        guard let connection = message.extractConnection() else { return nil }
        self.init(connection.nw)
    }

    /// A connection taken from a group: a new stream of a multiplexed one.
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    public convenience init?(from: NWConnectionGroup, to: NWEndpoint? = nil, using: NWProtocolOptions? = nil) {
        guard let connection = nw_connection_group_extract_connection(from.nw, to?.nw, using?.nw) else { return nil }
        self.init(connection)
    }
}

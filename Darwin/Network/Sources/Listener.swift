// NWListener over the C API's nw_listener_t: listening on a port, with a
// Bonjour service or application service advertised.

import Dispatch
import Foundation

@_hasMissingDesignatedInitializers
@available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
@_objcRuntimeName(_TtC7Network11_NWListener)
final public class NWListener: CustomDebugStringConvertible {
    let nw: nw_listener_t
    private let lock = NSLock()
    private var storedState: State = .setup
    private var storedQueue: DispatchQueue?
    private var storedService: Service?
    private var storedConnectionHandler: (@Sendable (NWConnection) -> Void)?
    private var storedGroupHandler: (@Sendable (NWConnectionGroup) -> Void)?
    private var storedStateHandler: (@Sendable (State) -> Void)?
    private var storedRegistrationHandler: (@Sendable (ServiceRegistrationChange) -> Void)?
    private var started = false

    final public var debugDescription: String {
        if let port { return "NWListener on port \(port.rawValue)" }
        return "NWListener"
    }

    /// A Bonjour service, or an application service, to advertise.
    public struct Service: Equatable, CustomDebugStringConvertible, Sendable {
        public static func == (lhs: Service, rhs: Service) -> Bool {
            lhs.name == rhs.name && lhs.type == rhs.type && lhs.domain == rhs.domain
                && lhs.txtRecord == rhs.txtRecord && lhs.storedTXTRecord == rhs.storedTXTRecord
                && lhs.noAutoRename == rhs.noAutoRename && lhs.applicationService == rhs.applicationService
        }

        public var debugDescription: String {
            if let applicationService { return "Application service \(applicationService)" }
            return [name, type, domain].compactMap { $0 }.joined(separator: ".")
        }

        public let name: String?
        public let type: String
        public let domain: String?
        private var storedTXTRecord: NWTXTRecord?
        /// The application service's name, for one.
        let applicationService: String?

        @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
        public var txtRecordObject: NWTXTRecord? {
            get { storedTXTRecord ?? txtRecord.map { NWTXTRecord(wireFormat: $0) } }
            set { storedTXTRecord = newValue }
        }

        public let txtRecord: Data?

        @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
        public var noAutoRename = false

        public init(name: String? = nil, type: String, domain: String? = nil, txtRecord: Data? = nil) {
            self.name = name
            self.type = type
            self.domain = domain
            self.txtRecord = txtRecord
            storedTXTRecord = nil
            applicationService = nil
        }

        @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
        public init(name: String? = nil, type: String, domain: String? = nil, txtRecord: NWTXTRecord) {
            self.name = name
            self.type = type
            self.domain = domain
            self.txtRecord = txtRecord.wireFormat
            storedTXTRecord = txtRecord
            applicationService = nil
        }

        @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
        public init(applicationService: String) {
            name = applicationService
            type = ""
            domain = nil
            txtRecord = nil
            storedTXTRecord = nil
            self.applicationService = applicationService
        }

        /// The C API's descriptor of the service.
        var nw: nw_advertise_descriptor_t? {
            if let applicationService {
                guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else { return nil }
                return nw_advertise_descriptor_create_application_service(applicationService)
            }
            guard let descriptor = nw_advertise_descriptor_create_bonjour_service(name, type, domain) else { return nil }
            if let record = storedTXTRecord {
                nw_advertise_descriptor_set_txt_record_object(descriptor, record.nw)
            } else if let txtRecord {
                txtRecord.withUnsafeBytes { nw_advertise_descriptor_set_txt_record(descriptor, $0.baseAddress, $0.count) }
            }
            nw_advertise_descriptor_set_no_auto_rename(descriptor, noAutoRename)
            return descriptor
        }
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

        init(_ state: nw_listener_state_t, _ error: nw_error_t?) {
            let error = NWError(error) ?? .posix(.ECONNABORTED)
            switch state {
            case nw_listener_state_waiting: self = .waiting(error)
            case nw_listener_state_ready: self = .ready
            case nw_listener_state_failed: self = .failed(error)
            case nw_listener_state_cancelled: self = .cancelled
            default: self = .setup
            }
        }
    }

    @preconcurrency final public var newConnectionHandler: (@Sendable (_ connection: NWConnection) -> Void)? {
        get { lock.withLock { storedConnectionHandler } }
        set { lock.withLock { storedConnectionHandler = newValue } }
    }

    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    @preconcurrency final public var newConnectionGroupHandler: (@Sendable (_ group: NWConnectionGroup) -> Void)? {
        get { lock.withLock { storedGroupHandler } }
        set { lock.withLock { storedGroupHandler = newValue } }
    }

    final public var state: State {
        lock.withLock { storedState }
    }

    @preconcurrency final public var stateUpdateHandler: (@Sendable (_ newState: State) -> Void)? {
        get { lock.withLock { storedStateHandler } }
        set { lock.withLock { storedStateHandler = newValue } }
    }

    final public let parameters: NWParameters

    final public var service: Service? {
        get { lock.withLock { storedService } }
        set {
            lock.withLock { storedService = newValue }
            nw_listener_set_advertise_descriptor(nw, newValue?.nw)
        }
    }

    /// No limit on new connections: NW_LISTENER_INFINITE_CONNECTION_LIMIT.
    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    public static let InfiniteConnectionLimit = Int(UInt32.max)

    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    final public var newConnectionLimit: Int {
        get { Int(nw_listener_get_new_connection_limit(nw)) }
        set { nw_listener_set_new_connection_limit(nw, UInt32(clamping: newValue)) }
    }

    final public var port: NWEndpoint.Port? {
        let port = nw_listener_get_port(nw)
        return port == 0 ? nil : NWEndpoint.Port(integerLiteral: port)
    }

    public enum ServiceRegistrationChange: Sendable {
        case add(NWEndpoint)
        case remove(NWEndpoint)
    }

    @preconcurrency final public var serviceRegistrationUpdateHandler: (@Sendable (_ change: ServiceRegistrationChange) -> Void)? {
        get { lock.withLock { storedRegistrationHandler } }
        set { lock.withLock { storedRegistrationHandler = newValue } }
    }

    /// A listener on the port given (any port for .any), or the error
    /// the C API gives none for.
    public init(using: NWParameters, on: NWEndpoint.Port = .any) throws {
        let listener = on == .any ? nw_listener_create(using.nw) : nw_listener_create_with_port(String(on.rawValue), using.nw)
        guard let listener else { throw NWError.posix(.EINVAL) }
        nw = listener
        parameters = using
    }

    init(_ listener: nw_listener_t, parameters: NWParameters) {
        nw = listener
        self.parameters = parameters
    }

    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    public convenience init(applicationService name: String, using parameters: NWParameters = .applicationService) throws {
        try self.init(using: parameters)
        service = Service(applicationService: name)
    }

    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    public convenience init(service: Service, using parameters: NWParameters) throws {
        try self.init(using: parameters)
        self.service = service
    }

    /// A listener on the socket launchd opened for the key of the job's
    /// Sockets dictionary.
    @available(macOS, introduced: 13.0, deprecated: 15.0, message: "Use init(launchdSocketKey:parameters:)")
    @available(iOS, unavailable)
    @available(watchOS, unavailable)
    @available(tvOS, unavailable)
    public convenience init?(launchd key: String, using parameters: NWParameters) {
        self.init(nw_listener_create_with_launchd_key(parameters.nw, key), parameters: parameters)
    }

    /// The same, for a key launchd has a socket for.
    @available(macOS 13.0, *)
    @available(iOS, unavailable)
    @available(watchOS, unavailable)
    @available(tvOS, unavailable)
    public convenience init(launchdSocketKey: String, parameters: NWParameters) {
        self.init(nw_listener_create_with_launchd_key(parameters.nw, launchdSocketKey), parameters: parameters)
    }

    /// Starts listening. The C API's handlers hold the listener until it
    /// is cancelled.
    final public func start(queue: DispatchQueue) {
        let first = lock.withLock { () -> Bool in
            storedQueue = queue
            defer { started = true }
            return !started
        }
        guard first else { return }
        nw_listener_set_queue(nw, queue)
        nw_listener_set_state_changed_handler(nw) { state, error in
            self.update(State(state, error))
        }
        nw_listener_set_new_connection_handler(nw) { connection in
            let handler = self.newConnectionHandler
            if let handler {
                handler(NWConnection(connection))
            } else {
                nw_connection_cancel(connection)
            }
        }
        if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *), lock.withLock({ storedGroupHandler != nil }) {
            nw_listener_set_new_connection_group_handler(nw) { group in
                self.newConnectionGroupHandler?(NWConnectionGroup(group))
            }
        }
        nw_listener_set_advertised_endpoint_changed_handler(nw) { endpoint, added in
            let change: ServiceRegistrationChange = added ? .add(NWEndpoint(endpoint)) : .remove(NWEndpoint(endpoint))
            self.serviceRegistrationUpdateHandler?(change)
        }
        nw_listener_start(nw)
    }

    private func update(_ state: State) {
        let handler = lock.withLock { () -> (@Sendable (State) -> Void)? in
            storedState = state
            return storedStateHandler
        }
        handler?(state)
        if state == .cancelled {
            nw_listener_set_state_changed_handler(nw, nil)
            nw_listener_set_new_connection_handler(nw, nil)
            if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
                nw_listener_set_new_connection_group_handler(nw, nil)
            }
            nw_listener_set_advertised_endpoint_changed_handler(nw, nil)
        }
    }

    final public var queue: DispatchQueue? {
        lock.withLock { storedQueue }
    }

    final public func cancel() {
        nw_listener_cancel(nw)
    }

    deinit {}
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
extension NWListener: @unchecked Sendable {}

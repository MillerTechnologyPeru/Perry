// NetworkListener and NetworkBrowser, macOS and iOS 26's listener and
// browser run as async loops, over NWListener and NWBrowser; Bonjour's
// browser and listener providers.

import Dispatch
import Foundation

// MARK: - Listener

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public protocol ListenerProvider {
    var service: NWListener.Service { get }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public struct BonjourListenerProvider: ListenerProvider {
    public let service: NWListener.Service

    public init(name: String? = nil, type: String, domain: String? = nil, txtRecord: NWTXTRecord? = nil) {
        if let txtRecord {
            service = NWListener.Service(name: name, type: type, domain: domain, txtRecord: txtRecord)
        } else {
            service = NWListener.Service(name: name, type: type, domain: domain)
        }
    }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension ListenerProvider where Self == BonjourListenerProvider {
    public static func bonjour(name: String? = nil, type: String, domain: String? = nil, txtRecord: NWTXTRecord? = nil) -> BonjourListenerProvider {
        BonjourListenerProvider(name: name, type: type, domain: domain, txtRecord: txtRecord)
    }
}

@_hasMissingDesignatedInitializers
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
final public class NetworkListener<ApplicationProtocol>: @unchecked Sendable, CustomDebugStringConvertible where ApplicationProtocol: NetworkProtocolOptions {
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

        init(_ state: NWListener.State) {
            switch state {
            case .setup: self = .setup
            case .waiting(let error): self = .waiting(error)
            case .ready: self = .ready
            case .failed(let error): self = .failed(error)
            case .cancelled: self = .cancelled
            }
        }
    }

    public enum ServiceRegistrationChange: Sendable {
        case add(NWEndpoint)
        case remove(NWEndpoint)
    }

    public typealias StateUpdateHandler = @isolated(any) @Sendable (_ listener: NetworkListener<ApplicationProtocol>, _ state: State) -> Void
    public typealias ServiceRegistrationUpdateHandler = @isolated(any) @Sendable (_ listener: NetworkListener<ApplicationProtocol>, _ change: ServiceRegistrationChange) -> Void

    let listener: NWListener
    let stack: StackDescription
    private let queue = DispatchQueue(label: "com.apple.network.listener")

    init(listener: NWListener, stack: StackDescription) {
        self.listener = listener
        self.stack = stack
    }

    deinit {
        listener.cancel()
    }

    final public var debugDescription: String { listener.debugDescription }

    public convenience init(for provider: (any ListenerProvider)? = nil, @ProtocolStackBuilder<ApplicationProtocol> using builder: () -> ApplicationProtocol) throws {
        let stack = describeStack([builder()])
        try self.init(provider: provider, stack: stack, parameters: stack.makeParameters())
    }

    public convenience init(for provider: (any ListenerProvider)? = nil, using builder: NWParametersBuilder<ApplicationProtocol>) throws {
        try self.init(provider: provider, stack: builder.stack, parameters: builder.parameters)
    }

    private convenience init(provider: (any ListenerProvider)?, stack: StackDescription, parameters: NWParameters) throws {
        let listener = try NWListener(using: parameters)
        listener.service = provider?.service
        self.init(listener: listener, stack: stack)
    }

    @discardableResult
    final public func onStateUpdate(@_inheritActorContext _ handler: @escaping @isolated(any) @Sendable (_ listener: NetworkListener<ApplicationProtocol>, _ state: State) -> Void) -> Self {
        let deliver = deliverToListener(handler)
        listener.stateUpdateHandler = { state in deliver(State(state)) }
        return self
    }

    @discardableResult
    final public func onServiceRegistrationUpdate(@_inheritActorContext _ handler: @escaping @isolated(any) @Sendable (_ listener: NetworkListener<ApplicationProtocol>, _ change: ServiceRegistrationChange) -> Void) -> Self {
        let deliver = deliverToListener(handler)
        listener.serviceRegistrationUpdateHandler = { change in
            switch change {
            case .add(let endpoint): deliver(.add(endpoint))
            case .remove(let endpoint): deliver(.remove(endpoint))
            }
        }
        return self
    }

    private func deliverToListener<Value>(_ handler: @escaping @isolated(any) @Sendable (NetworkListener<ApplicationProtocol>, Value) -> Void) -> @Sendable (Value) -> Void {
        nonisolated(unsafe) unowned let listener = self
        return { value in Task { await handler(listener, value) } }
    }

    final public func newConnectionLimit(_ limit: Int) -> Self {
        newConnectionLimit = limit
        return self
    }

    final public var newConnectionLimit: Int {
        get { listener.newConnectionLimit }
        set { listener.newConnectionLimit = newValue }
    }

    final public var service: NWListener.Service? {
        get { listener.service }
        set { listener.service = newValue }
    }

    final public var port: NWEndpoint.Port? { listener.port }

    /// Runs the listener until it fails, is cancelled or the task is:
    /// each connection is handed to the handler in a task of its own.
    func runListener<Item>(accept: (@escaping @Sendable (Item) -> Void) -> Void, handle: @escaping @Sendable (Item) async throws -> Void) async throws {
        let (items, continuation) = AsyncStream<Item>.makeStream()
        accept { continuation.yield($0) }
        let previous = listener.stateUpdateHandler
        let failure = FailureBox()
        listener.stateUpdateHandler = { state in
            previous?(state)
            switch state {
            case .failed(let error):
                failure.error = error
                continuation.finish()
            case .cancelled:
                continuation.finish()
            default:
                break
            }
        }
        listener.start(queue: queue)
        try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: Void.self) { tasks in
                for await item in items {
                    tasks.addTask { try await handle(item) }
                }
                try await tasks.waitForAll()
            }
        } onCancel: {
            listener.cancel()
        }
        if let error = failure.error { throw error }
    }
}

/// The error a listener or browser failed with.
private final class FailureBox: @unchecked Sendable {
    var error: NWError?
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension NetworkListener where ApplicationProtocol: OneToOneProtocol {
    final public func run(@_inheritActorContext _ handler: @escaping @isolated(any) @Sendable (NetworkConnection<ApplicationProtocol>) async throws -> Void) async throws {
        let stack = self.stack
        let listener = self.listener
        try await runListener(accept: { accept in
            listener.newConnectionHandler = { accept($0) }
        }, handle: { (connection: NWConnection) in
            try await handler(NetworkConnection<ApplicationProtocol>(transport: .connection(connection), stack: stack))
        })
    }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension NetworkListener where ApplicationProtocol: MultiplexProtocol {
    final public func run(@_inheritActorContext _ handler: @escaping @isolated(any) @Sendable (NetworkConnection<ApplicationProtocol>) async throws -> Void) async throws {
        let stack = self.stack
        let listener = self.listener
        try await runListener(accept: { accept in
            listener.newConnectionGroupHandler = { accept($0) }
        }, handle: { (group: NWConnectionGroup) in
            try await handler(NetworkConnection<ApplicationProtocol>(transport: .group(group), stack: stack))
        })
    }
}

// MARK: - Browser

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public protocol BrowserProvider: Sendable {
    associatedtype Endpoint: Connectable
}

/// A provider whose endpoints come from an NWBrowser's results.
protocol BrowsingProvider {
    var browseDescriptor: NWBrowser.Descriptor { get }
    func endpoints(of results: Set<NWBrowser.Result>) -> [Any]
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public struct Bonjour: BrowserProvider, BrowsingProvider {
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public struct Endpoint: Equatable, Identifiable, Sendable, Connectable, CustomStringConvertible, EndpointProviding {
        public let result: NWBrowser.Result
        public let txtRecord: NWTXTRecord
        public let name: String
        public let type: String
        public let domain: String

        public static func == (lhs: Endpoint, rhs: Endpoint) -> Bool {
            lhs.result == rhs.result && lhs.txtRecord == rhs.txtRecord
        }

        public var id: String { "\(name).\(type).\(domain)" }

        public var nwEndpoint: NWEndpoint { result.endpoint }

        public var description: String { "\(name) (\(type)\(domain))" }

        var connectionEndpoint: NWEndpoint { nwEndpoint }

        @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
        public typealias ID = String

        init(_ result: NWBrowser.Result) {
            self.result = result
            if case .bonjour(let record) = result.metadata {
                txtRecord = record
            } else {
                txtRecord = NWTXTRecord()
            }
            switch result.endpoint.resolvedOpaque {
            case .service(let name, let type, let domain, _):
                self.name = name
                self.type = type
                self.domain = domain
            default:
                name = result.endpoint.debugDescription
                type = ""
                domain = ""
            }
        }
    }

    let type: String
    let domain: String?
    let includeTxtRecord: Bool

    var browseDescriptor: NWBrowser.Descriptor {
        includeTxtRecord ? .bonjourWithTXTRecord(type: type, domain: domain) : .bonjour(type: type, domain: domain)
    }

    func endpoints(of results: Set<NWBrowser.Result>) -> [Any] {
        results.map(Endpoint.init).sorted { $0.id < $1.id }
    }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension BrowserProvider where Self == Bonjour {
    public static func bonjour(_ type: String, domain: String? = nil, includeTxtRecord: Bool = false) -> Bonjour {
        Bonjour(type: type, domain: domain, includeTxtRecord: includeTxtRecord)
    }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
final public class NetworkBrowser<Provider>: Sendable, CustomDebugStringConvertible where Provider: BrowserProvider {
    public enum State: Equatable, Sendable {
        case setup
        case ready
        case failed(NWError)
        case cancelled
        case waiting(NWError)

        public static func == (a: State, b: State) -> Bool {
            switch (a, b) {
            case (.setup, .setup), (.ready, .ready), (.cancelled, .cancelled): return true
            case let (.failed(x), .failed(y)), let (.waiting(x), .waiting(y)): return x == y
            default: return false
            }
        }

        init(_ state: NWBrowser.State) {
            switch state {
            case .setup: self = .setup
            case .ready: self = .ready
            case .failed(let error): self = .failed(error)
            case .cancelled: self = .cancelled
            case .waiting(let error): self = .waiting(error)
            }
        }
    }

    public typealias StateUpdateHandler = @isolated(any) @Sendable (NetworkBrowser<Provider>, State) -> Void

    public enum RunResult<T> {
        case finish(T)
        case `continue`
    }

    private let provider: Provider
    private let parameters: NWParameters
    nonisolated(unsafe) private var stateHandler: (@Sendable (State) -> Void)?

    final public var debugDescription: String { "NetworkBrowser for \(provider)" }

    public init(for provider: Provider, using parameters: NWParameters? = nil) {
        self.provider = provider
        self.parameters = parameters ?? NWParameters()
    }

    @discardableResult
    final public func onStateUpdate(@_inheritActorContext _ handler: @escaping @isolated(any) @Sendable (NetworkBrowser<Provider>, State) -> Void) -> Self {
        setStateHandler(handler)
        return self
    }

    private func setStateHandler(_ handler: @escaping @isolated(any) @Sendable (NetworkBrowser<Provider>, State) -> Void) {
        nonisolated(unsafe) unowned let browser = self
        stateHandler = { state in Task { await handler(browser, state) } }
    }

    /// Browses until the handler finishes, calling it with the endpoints
    /// each time they change.
    private func browse<Return>(_ handler: @escaping @Sendable ([Provider.Endpoint]) async throws -> RunResult<Return>) async throws -> Return {
        guard let browsing = provider as? any BrowsingProvider else { throw NWError.posix(.EPROTONOSUPPORT) }
        let browser = NWBrowser(for: browsing.descriptor, using: parameters)
        let (updates, continuation) = AsyncStream<Set<NWBrowser.Result>>.makeStream()
        let failure = FailureBox()
        let stateHandler = self.stateHandler
        browser.stateUpdateHandler = { state in
            stateHandler?(State(state))
            switch state {
            case .failed(let error):
                failure.error = error
                continuation.finish()
            case .cancelled:
                continuation.finish()
            default:
                break
            }
        }
        browser.browseResultsChangedHandler = { results, _ in continuation.yield(results) }
        browser.start(queue: DispatchQueue(label: "com.apple.network.browser"))
        defer { browser.cancel() }
        return try await withTaskCancellationHandler {
            for await results in updates {
                let endpoints = browsing.endpoints(of: results).compactMap { $0 as? Provider.Endpoint }
                if case .finish(let value) = try await handler(endpoints) {
                    return value
                }
            }
            if let error = failure.error { throw error }
            throw CancellationError()
        } onCancel: {
            browser.cancel()
        }
    }

    final public func run(@_inheritActorContext _ handler: @escaping @isolated(any) @Sendable ([Provider.Endpoint]) async throws -> Void) async throws {
        let _: Void = try await browse { endpoints -> RunResult<Void> in
            try await handler(endpoints)
            return .continue
        }
    }

    final public func run<Return>(@_inheritActorContext _ handler: @escaping @isolated(any) @Sendable ([Provider.Endpoint]) async throws -> RunResult<Return>) async throws -> Return {
        try await browse { try await handler($0) }
    }

    deinit {}
}

extension BrowsingProvider {
    var descriptor: NWBrowser.Descriptor { browseDescriptor }
}

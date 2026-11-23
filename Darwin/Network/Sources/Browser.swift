// NWBrowser over the C API's nw_browser_t: browsing for Bonjour and
// application services, with the results and their changes.

import Dispatch
import Foundation

/// nw_browser_set_browse_results_changed_handler, declared with the
/// results optional: the C API passes no old result for an added service
/// and no new one for a removed one.
@_silgen_name("nw_browser_set_browse_results_changed_handler")
private func nwBrowserSetResultsChangedHandler(_ browser: nw_browser_t, _ handler: (@convention(block) (nw_browse_result_t?, nw_browse_result_t?, Bool) -> Void)?)

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
final public class NWBrowser: CustomDebugStringConvertible {
    let nw: nw_browser_t
    private let lock = NSLock()
    private var storedState: State = .setup
    private var storedResults: Set<Result> = []
    private var pendingChanges: Set<Result.Change> = []
    private var storedQueue: DispatchQueue?
    private var storedStateHandler: (@Sendable (State) -> Void)?
    private var storedResultsHandler: (@Sendable (Set<Result>, Set<Result.Change>) -> Void)?
    private var started = false

    final public var debugDescription: String {
        "NWBrowser \(descriptor)"
    }

    /// What to browse for.
    public enum Descriptor: Sendable {
        case bonjour(type: String, domain: String?)
        case bonjourWithTXTRecord(type: String, domain: String?)
        @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
        case applicationService(name: String)

        var nw: nw_browse_descriptor_t {
            switch self {
            case .bonjour(let type, let domain):
                return nw_browse_descriptor_create_bonjour_service(type, domain)
            case .bonjourWithTXTRecord(let type, let domain):
                let descriptor = nw_browse_descriptor_create_bonjour_service(type, domain)
                nw_browse_descriptor_set_include_txt_record(descriptor, true)
                return descriptor
            case .applicationService(let name):
                return nw_browse_descriptor_create_application_service(name)
            }
        }
    }

    /// A service found: its endpoint, the interfaces it is on and its
    /// TXT record. Results are the same service when their endpoints are.
    public struct Result: Hashable, Sendable {
        public let endpoint: NWEndpoint
        public let interfaces: [NWInterface]
        public let metadata: Metadata

        public enum Metadata: Equatable, CustomDebugStringConvertible, Sendable {
            case none
            case bonjour(_: NWTXTRecord)

            public static func == (lhs: Metadata, rhs: Metadata) -> Bool {
                switch (lhs, rhs) {
                case (.none, .none): return true
                case let (.bonjour(a), .bonjour(b)): return a == b
                default: return false
                }
            }

            public var debugDescription: String {
                switch self {
                case .none: return "none"
                case .bonjour(let record): return "bonjour(\(record.debugDescription))"
                }
            }
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(endpoint)
        }

        public static func == (lhs: Result, rhs: Result) -> Bool {
            lhs.endpoint == rhs.endpoint
        }

        /// How a service's result changed.
        public enum Change: Hashable, Sendable {
            case identical
            case added(Result)
            case removed(Result)
            case changed(old: Result, new: Result, flags: Flags)

            public static func == (lhs: Change, rhs: Change) -> Bool {
                switch (lhs, rhs) {
                case (.identical, .identical): return true
                case let (.added(a), .added(b)), let (.removed(a), .removed(b)): return a == b
                case let (.changed(o1, n1, f1), .changed(o2, n2, f2)): return o1 == o2 && n1 == n2 && f1 == f2
                default: return false
                }
            }

            public struct Flags: OptionSet, Hashable, Sendable {
                public let rawValue: UInt8

                public init(rawValue: UInt8) {
                    self.rawValue = rawValue
                }

                public static let identical = Flags(rawValue: 0x01)
                public static let interfaceAdded = Flags(rawValue: 0x08)
                public static let interfaceRemoved = Flags(rawValue: 0x10)
                public static let metadataChanged = Flags(rawValue: 0x20)

                @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
                public typealias ArrayLiteralElement = Flags
                @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
                public typealias Element = Flags
                @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
                public typealias RawValue = UInt8
            }

            public init(between old: Result?, _ new: Result?) {
                switch (old, new) {
                case (nil, nil):
                    self = .identical
                case (nil, let new?):
                    self = .added(new)
                case (let old?, nil):
                    self = .removed(old)
                case (let old?, let new?):
                    var flags: Flags = []
                    if new.interfaces.contains(where: { !old.interfaces.contains($0) }) { flags.insert(.interfaceAdded) }
                    if old.interfaces.contains(where: { !new.interfaces.contains($0) }) { flags.insert(.interfaceRemoved) }
                    if old.metadata != new.metadata { flags.insert(.metadataChanged) }
                    self = flags.isEmpty && old.endpoint == new.endpoint ? .identical : .changed(old: old, new: new, flags: flags.isEmpty ? .identical : flags)
                }
            }

            public func hash(into hasher: inout Hasher) {
                switch self {
                case .identical: hasher.combine(0)
                case .added(let result):
                    hasher.combine(1)
                    hasher.combine(result)
                case .removed(let result):
                    hasher.combine(2)
                    hasher.combine(result)
                case .changed(let old, let new, let flags):
                    hasher.combine(3)
                    hasher.combine(old)
                    hasher.combine(new)
                    hasher.combine(flags)
                }
            }
        }

        init(_ result: nw_browse_result_t) {
            endpoint = NWEndpoint(nw_browse_result_copy_endpoint(result))
            var interfaces: [NWInterface] = []
            nw_browse_result_enumerate_interfaces(result) { interface in
                interfaces.append(NWInterface(interface))
                return true
            }
            self.interfaces = interfaces
            metadata = nw_browse_result_copy_txt_record_object(result).map { .bonjour(NWTXTRecord($0)) } ?? .none
        }
    }

    public enum State: Equatable, Sendable {
        case setup
        case ready
        case failed(NWError)
        case cancelled
        @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
        case waiting(NWError)

        public static func == (a: State, b: State) -> Bool {
            switch (a, b) {
            case (.setup, .setup), (.ready, .ready), (.cancelled, .cancelled): return true
            case let (.failed(x), .failed(y)), let (.waiting(x), .waiting(y)): return x == y
            default: return false
            }
        }

        init(_ state: nw_browser_state_t, _ error: nw_error_t?) {
            let error = NWError(error) ?? .posix(.ECONNABORTED)
            switch state {
            case nw_browser_state_ready: self = .ready
            case nw_browser_state_failed: self = .failed(error)
            case nw_browser_state_cancelled: self = .cancelled
            case nw_browser_state_waiting: self = .waiting(error)
            default: self = .setup
            }
        }
    }

    final public let descriptor: Descriptor
    final public let parameters: NWParameters

    final public var state: State {
        lock.withLock { storedState }
    }

    final public var browseResults: Set<Result> {
        lock.withLock { storedResults }
    }

    final public var queue: DispatchQueue? {
        lock.withLock { storedQueue }
    }

    @preconcurrency final public var stateUpdateHandler: (@Sendable (_ newState: State) -> Void)? {
        get { lock.withLock { storedStateHandler } }
        set { lock.withLock { storedStateHandler = newValue } }
    }

    @preconcurrency final public var browseResultsChangedHandler: (@Sendable (_ newResults: Set<Result>, _ changes: Set<Result.Change>) -> Void)? {
        get { lock.withLock { storedResultsHandler } }
        set { lock.withLock { storedResultsHandler = newValue } }
    }

    public init(for descriptor: Descriptor, using parameters: NWParameters) {
        self.descriptor = descriptor
        self.parameters = parameters
        nw = nw_browser_create(descriptor.nw, parameters.nw)
    }

    /// Starts browsing. The C API's handlers hold the browser until it is
    /// cancelled.
    final public func start(queue: DispatchQueue) {
        let first = lock.withLock { () -> Bool in
            storedQueue = queue
            defer { started = true }
            return !started
        }
        guard first else { return }
        nw_browser_set_queue(nw, queue)
        nw_browser_set_state_changed_handler(nw) { state, error in
            self.update(State(state, error))
        }
        nwBrowserSetResultsChangedHandler(nw) { old, new, batchComplete in
            self.change(old: old.map(Result.init), new: new.map(Result.init), batchComplete: batchComplete)
        }
        nw_browser_start(nw)
    }

    private func change(old: Result?, new: Result?, batchComplete: Bool) {
        let delivery = lock.withLock { () -> (Set<Result>, Set<Result.Change>, (@Sendable (Set<Result>, Set<Result.Change>) -> Void)?)? in
            if let old { storedResults.remove(old) }
            if let new { storedResults.update(with: new) }
            let change = Result.Change(between: old, new)
            if change != .identical { pendingChanges.insert(change) }
            guard batchComplete else { return nil }
            defer { pendingChanges = [] }
            return (storedResults, pendingChanges, storedResultsHandler)
        }
        if let (results, changes, handler) = delivery {
            handler?(results, changes)
        }
    }

    private func update(_ state: State) {
        let handler = lock.withLock { () -> (@Sendable (State) -> Void)? in
            storedState = state
            return storedStateHandler
        }
        handler?(state)
        if state == .cancelled {
            nw_browser_set_state_changed_handler(nw, nil)
            nwBrowserSetResultsChangedHandler(nw, nil)
        }
    }

    final public func cancel() {
        nw_browser_cancel(nw)
    }

    deinit {}
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
extension NWBrowser: @unchecked Sendable {}

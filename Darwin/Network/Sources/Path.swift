// NWPath, a snapshot of the C API's nw_path_t, and NWPathMonitor over
// nw_path_monitor_t, also an AsyncSequence of the paths it sees.

import Dispatch
import Foundation

@available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
public struct NWPath: Equatable, CustomDebugStringConvertible, Sendable {
    public var debugDescription: String {
        var parts: [String] = []
        switch status {
        case .satisfied: parts.append("satisfied")
        case .unsatisfied: parts.append("unsatisfied (\(unsatisfiedReasonText))")
        case .requiresConnection: parts.append("requires connection")
        }
        if !availableInterfaces.isEmpty {
            parts.append("interface: " + availableInterfaces.map(\.name).joined(separator: ", "))
        }
        if supportsIPv4 { parts.append("ipv4") }
        if supportsIPv6 { parts.append("ipv6") }
        if supportsDNS { parts.append("dns") }
        if isExpensive { parts.append("expensive") }
        if storedConstrained { parts.append("constrained") }
        return parts.joined(separator: ", ")
    }

    private var unsatisfiedReasonText: String {
        switch storedReason {
        case nw_path_unsatisfied_reason_cellular_denied: return "Cellular access denied"
        case nw_path_unsatisfied_reason_wifi_denied: return "Wi-Fi access denied"
        case nw_path_unsatisfied_reason_local_network_denied: return "Local network access denied"
        case nw_path_unsatisfied_reason_vpn_inactive: return "VPN inactive"
        default: return "No network route"
        }
    }

    public enum Status: Sendable {
        case satisfied
        case unsatisfied
        case requiresConnection
    }

    public let status: Status

    @available(macOS 11.0, iOS 14.2, watchOS 7.1, tvOS 14.2, *)
    public enum UnsatisfiedReason: Sendable {
        case notAvailable
        case cellularDenied
        case wifiDenied
        case localNetworkDenied
        @available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
        case vpnInactive
    }

    @available(macOS 11.0, iOS 14.2, watchOS 7.1, tvOS 14.2, *)
    public var unsatisfiedReason: UnsatisfiedReason {
        switch storedReason {
        case nw_path_unsatisfied_reason_cellular_denied: return .cellularDenied
        case nw_path_unsatisfied_reason_wifi_denied: return .wifiDenied
        case nw_path_unsatisfied_reason_local_network_denied: return .localNetworkDenied
        case nw_path_unsatisfied_reason_vpn_inactive:
            if #available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *) { return .vpnInactive }
            return .notAvailable
        default: return .notAvailable
        }
    }

    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public enum LinkQuality: Sendable {
        case unknown
        case minimal
        case moderate
        case good
    }

    public let availableInterfaces: [NWInterface]
    public let isExpensive: Bool

    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    public var isConstrained: Bool { storedConstrained }

    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public var isUltraConstrained: Bool { storedUltraConstrained }

    public let supportsIPv4: Bool
    public let supportsIPv6: Bool
    public let supportsDNS: Bool

    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    public var gateways: [NWEndpoint] { storedGateways }

    public let localEndpoint: NWEndpoint?
    public let remoteEndpoint: NWEndpoint?

    public func usesInterfaceType(_ type: NWInterface.InterfaceType) -> Bool {
        if let nw {
            return nw_path_uses_interface_type(nw, type.nw)
        }
        return availableInterfaces.contains { $0.type == type }
    }

    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public var linkQuality: LinkQuality {
        switch storedLinkQuality {
        case nw_link_quality_minimal: return .minimal
        case nw_link_quality_moderate: return .moderate
        case nw_link_quality_good: return .good
        default: return .unknown
        }
    }

    public static func == (lhs: NWPath, rhs: NWPath) -> Bool {
        if let left = lhs.nw, let right = rhs.nw {
            return nw_path_is_equal(left, right)
        }
        return lhs.status == rhs.status && lhs.availableInterfaces == rhs.availableInterfaces
            && lhs.isExpensive == rhs.isExpensive && lhs.storedConstrained == rhs.storedConstrained
            && lhs.supportsIPv4 == rhs.supportsIPv4 && lhs.supportsIPv6 == rhs.supportsIPv6
            && lhs.supportsDNS == rhs.supportsDNS && lhs.localEndpoint == rhs.localEndpoint
            && lhs.remoteEndpoint == rhs.remoteEndpoint
    }

    private let storedReason: nw_path_unsatisfied_reason_t
    private let storedConstrained: Bool
    private let storedUltraConstrained: Bool
    private let storedGateways: [NWEndpoint]
    private let storedLinkQuality: nw_link_quality_t
    /// The C API's path this is a snapshot of.
    nonisolated(unsafe) let nw: nw_path_t?

    init(_ path: nw_path_t) {
        nw = path
        switch nw_path_get_status(path) {
        case nw_path_status_satisfied: status = .satisfied
        case nw_path_status_satisfiable: status = .requiresConnection
        default: status = .unsatisfied
        }
        storedReason = nw_path_get_unsatisfied_reason(path)
        var interfaces: [NWInterface] = []
        nw_path_enumerate_interfaces(path) { interface in
            interfaces.append(NWInterface(interface))
            return true
        }
        availableInterfaces = interfaces
        isExpensive = nw_path_is_expensive(path)
        storedConstrained = nw_path_is_constrained(path)
        if #available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *) {
            storedUltraConstrained = nw_path_is_ultra_constrained(path)
            storedLinkQuality = nw_path_get_link_quality(path)
        } else {
            storedUltraConstrained = false
            storedLinkQuality = nw_link_quality_unknown
        }
        supportsIPv4 = nw_path_has_ipv4(path)
        supportsIPv6 = nw_path_has_ipv6(path)
        supportsDNS = nw_path_has_dns(path)
        var gateways: [NWEndpoint] = []
        nw_path_enumerate_gateways(path) { gateway in
            gateways.append(NWEndpoint(gateway))
            return true
        }
        storedGateways = gateways
        localEndpoint = nw_path_copy_effective_local_endpoint(path).map(NWEndpoint.init)
        remoteEndpoint = nw_path_copy_effective_remote_endpoint(path).map(NWEndpoint.init)
    }

    /// The path before a monitor has seen one: unsatisfied, with nothing.
    init() {
        nw = nil
        status = .unsatisfied
        storedReason = nw_path_unsatisfied_reason_not_available
        availableInterfaces = []
        isExpensive = false
        storedConstrained = false
        storedUltraConstrained = false
        storedLinkQuality = nw_link_quality_unknown
        supportsIPv4 = false
        supportsIPv6 = false
        supportsDNS = false
        storedGateways = []
        localEndpoint = nil
        remoteEndpoint = nil
    }
}

@available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
@_objcRuntimeName(_TtC7Network14_NWPathMonitor)
final public class NWPathMonitor {
    private let monitor: nw_path_monitor_t
    private let lock = NSLock()
    private var storedPath = NWPath()
    private var storedHandler: (@Sendable (_ newPath: NWPath) -> Void)?
    private var storedQueue: DispatchQueue?
    private var started = false
    /// The continuations of the async iterators, by their number.
    private var observers: [Int: AsyncStream<NWPath>.Continuation] = [:]
    private var nextObserver = 0

    final public var currentPath: NWPath {
        get { lock.withLock { storedPath } }
        @available(macOS, introduced: 10.14, deprecated: 14.0, message: "setting currentPath not supported")
        @available(iOS, introduced: 12.0, deprecated: 17.0, message: "setting currentPath not supported")
        @available(watchOS, introduced: 5.0, deprecated: 9.0, message: "setting currentPath not supported")
        @available(tvOS, introduced: 12.0, deprecated: 17.0, message: "setting currentPath not supported")
        set { lock.withLock { storedPath = newValue } }
    }

    @preconcurrency final public var pathUpdateHandler: (@Sendable (_ newPath: NWPath) -> Void)? {
        get { lock.withLock { storedHandler } }
        set { lock.withLock { storedHandler = newValue } }
    }

    final public func start(queue: DispatchQueue) {
        let first = lock.withLock { () -> Bool in
            storedQueue = queue
            defer { started = true }
            return !started
        }
        guard first else { return }
        nw_path_monitor_set_queue(monitor, queue)
        nw_path_monitor_set_update_handler(monitor) { [weak self] path in
            self?.update(NWPath(path))
        }
        nw_path_monitor_set_cancel_handler(monitor) { [weak self] in
            self?.finishObservers()
        }
        nw_path_monitor_start(monitor)
    }

    private func update(_ path: NWPath) {
        let (handler, observers) = lock.withLock { () -> ((@Sendable (NWPath) -> Void)?, [AsyncStream<NWPath>.Continuation]) in
            storedPath = path
            return (storedHandler, Array(self.observers.values))
        }
        handler?(path)
        for observer in observers {
            observer.yield(path)
        }
    }

    private func finishObservers() {
        let observers = lock.withLock { () -> [AsyncStream<NWPath>.Continuation] in
            defer { self.observers.removeAll() }
            return Array(self.observers.values)
        }
        for observer in observers {
            observer.finish()
        }
    }

    final public func cancel() {
        nw_path_monitor_cancel(monitor)
    }

    final public var queue: DispatchQueue? {
        lock.withLock { storedQueue }
    }

    private init(monitor: nw_path_monitor_t) {
        self.monitor = monitor
    }

    public init() {
        monitor = nw_path_monitor_create()
    }

    deinit {
        if lock.withLock({ started }) {
            nw_path_monitor_cancel(monitor)
        }
    }

    /// A monitor of the paths Ethernet channels can use.
    @available(macOS 13.0, *)
    @available(iOS, unavailable)
    @available(watchOS, unavailable)
    @available(tvOS, unavailable)
    public static var ethernetChannel: NWPathMonitor {
        NWPathMonitor(monitor: nw_path_monitor_create_for_ethernet_channel())
    }

    public init(requiredInterfaceType: NWInterface.InterfaceType) {
        monitor = nw_path_monitor_create_with_type(requiredInterfaceType.nw)
    }

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
    public init(prohibitedInterfaceTypes: [NWInterface.InterfaceType]) {
        monitor = nw_path_monitor_create()
        for type in prohibitedInterfaceTypes {
            nw_path_monitor_prohibit_interface_type(monitor, type.nw)
        }
    }

    /// A stream of the monitor's paths, from the next one; the monitor is
    /// started on a queue of its own if it wasn't.
    fileprivate func makeStream() -> AsyncStream<NWPath> {
        AsyncStream { continuation in
            let (number, needsStart) = lock.withLock { () -> (Int, Bool) in
                let number = nextObserver
                nextObserver += 1
                observers[number] = continuation
                return (number, !started)
            }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                _ = self.lock.withLock { self.observers.removeValue(forKey: number) }
            }
            if needsStart {
                start(queue: DispatchQueue(label: "com.apple.network.path-monitor"))
            } else if lock.withLock({ storedPath.nw != nil }) {
                continuation.yield(currentPath)
            }
        }
    }
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
extension NWPathMonitor: @unchecked Sendable, CustomDebugStringConvertible, AsyncSequence {
    public typealias Element = NWPath
    public typealias AsyncIterator = NWPathMonitor.Iterator

    @available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
    final public var debugDescription: String {
        "NWPathMonitor (\(currentPath.debugDescription))"
    }

    @available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
    public struct Iterator: AsyncIteratorProtocol {
        private var base: AsyncStream<NWPath>.Iterator

        fileprivate init(_ stream: AsyncStream<NWPath>) {
            base = stream.makeAsyncIterator()
        }

        public mutating func next() async -> NWPathMonitor.Element? {
            await base.next()
        }

        @available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
        public typealias Element = NWPathMonitor.Element
    }

    @available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
    final public __consuming func makeAsyncIterator() -> NWPathMonitor.Iterator {
        Iterator(makeStream())
    }
}

@available(*, unavailable)
extension NWPathMonitor.Iterator: Sendable {}

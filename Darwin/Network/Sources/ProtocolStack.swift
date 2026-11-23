// The protocol stacks of macOS and iOS 26's NetworkConnection API: the
// protocol values (TLS, TCP, UDP, IP, QUIC, DTLS, WebSocket, Framer, TLV,
// Coder), their result builders, and NWParametersBuilder, which turns a
// stack into NWParameters.
//
// Each protocol value keeps its settings as closures run on fresh C API
// options when parameters are made, so values stay values. TLV and Coder
// frame messages in Swift over the protocol below them.

import Dispatch
import Foundation
import Security

// MARK: - Stack descriptions

/// The kind of a layer of a stack, which says how a channel sends and
/// receives on it.
enum StackLayerKind {
    case stream
    case datagram
    case quic
    case webSocket
    case framer
    case tlv
    case coder
}

/// How a TLV or Coder protocol frames its messages.
enum StackFraming {
    /// A TLV: the type's and length's sizes in bytes, big-endian.
    case tlv(typeSize: Int, lengthSize: Int)
    /// Coded values: a 4-byte big-endian length before each on a stream.
    case coder(encode: @Sendable (Any) throws -> Data, decode: @Sendable (Data) throws -> Any)
}

/// What a stack of protocols makes: the C API's protocols and the framing
/// done in Swift above them.
struct StackDescription {
    /// The application protocols, top first.
    var application: [() -> NWProtocolOptions] = []
    var transport: (() -> NWProtocolOptions)?
    var ipSettings: [(NWProtocolIP.Options) -> Void] = []
    /// The layers, top first.
    var layers: [StackLayerKind] = []
    var framing: StackFraming?

    /// The kind of the stack's top layer.
    var top: StackLayerKind { layers.first ?? .stream }

    /// Whether the first layer below Swift's framing keeps message
    /// boundaries (so each message is one TLV or one coded value).
    var framingOverMessages: Bool {
        guard let below = layers.dropFirst().first else { return false }
        switch below {
        case .datagram, .webSocket, .framer: return true
        default: return false
        }
    }

    /// Parameters of the stack: a copy of those given with its protocols.
    func makeParameters(from initial: NWParameters? = nil) -> NWParameters {
        let parameters = initial?.copy() ?? NWParameters()
        let stack = parameters.defaultProtocolStack
        let transport = self.transport?() ?? (layers.contains(.datagram) ? NWProtocolUDP.Options() : NWProtocolTCP.Options())
        stack.transportProtocol = transport
        stack.applicationProtocols = application.map { $0() }
        if let ip = stack.internetProtocol as? NWProtocolIP.Options {
            for setting in ipSettings {
                setting(ip)
            }
        }
        return parameters
    }
}

/// A protocol value that can be part of a stack.
protocol StackLayer {
    func describe(into stack: inout StackDescription)
}

/// The description of a stack given as protocol values, top first.
func describeStack(_ protocols: [Any]) -> StackDescription {
    var stack = StackDescription()
    for item in protocols {
        (item as? any StackLayer)?.describe(into: &stack)
    }
    return stack
}

/// A queue for TLS verification blocks.
private let verifyQueue = DispatchQueue(label: "com.apple.network.verify", attributes: .concurrent)

/// Sets whether TLS asks the peer for a certificate: required, optional
/// (macOS has no optional request: there it isn't required) or neither.
private func setPeerAuthentication(_ options: sec_protocol_options_t, required: Bool, optional: Bool) {
    #if os(macOS)
    sec_protocol_options_set_peer_authentication_required(options, required)
    #else
    if optional {
        sec_protocol_options_set_peer_authentication_optional(options, true)
    } else {
        sec_protocol_options_set_peer_authentication_required(options, required)
    }
    #endif
}

/// Has TLS options call an async validator for each peer's trust.
private func setValidator(_ options: sec_protocol_options_t, _ handler: @escaping @isolated(any) @Sendable (sec_protocol_metadata_t, sec_trust_t) async -> Bool) {
    sec_protocol_options_set_verify_block(options, { metadata, trust, complete in
        nonisolated(unsafe) let complete = complete
        nonisolated(unsafe) let metadata = metadata
        nonisolated(unsafe) let trust = trust
        Task {
            complete(await handler(metadata, trust))
        }
    }, verifyQueue)
}

// MARK: - Protocols

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public protocol Connectable {}

/// The error of an endpoint a connection can't use.
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public struct UnexpectedEndpointType: Error {
    public let endpoint: NWEndpoint

    public init(endpoint: NWEndpoint) {
        self.endpoint = endpoint
    }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public protocol NetworkFixedWidthInteger: FixedWidthInteger {
    init(bigEndian: Self)
    var bigEndian: Self { get }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension UInt8: NetworkFixedWidthInteger {}
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension UInt16: NetworkFixedWidthInteger {}
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension UInt32: NetworkFixedWidthInteger {}
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension UInt64: NetworkFixedWidthInteger {}
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension Int8: NetworkFixedWidthInteger {}
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension Int16: NetworkFixedWidthInteger {}
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension Int32: NetworkFixedWidthInteger {}
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension Int64: NetworkFixedWidthInteger {}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public protocol NetworkMetadataProtocol {}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public protocol NetworkProtocolOptions {
    associatedtype BelowProtocol
    associatedtype ProtocolStorage: ConnectionStorage = DefaultProtocolStorage
    associatedtype Metadata: NetworkMetadataProtocol
    typealias Message<T> = (content: T, metadata: Self.Metadata)
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public protocol ConnectionStorage {
    init()
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public struct DefaultProtocolStorage: ConnectionStorage, Sendable {
    public init() {}
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public protocol OneToOneProtocol: NetworkProtocolOptions {}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public protocol MultiplexProtocol: NetworkProtocolOptions {}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public protocol StreamProtocol: OneToOneProtocol {}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public protocol MessageProtocol: OneToOneProtocol {
    associatedtype ContentType
    associatedtype LegacyMessage
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public protocol DatagramProtocol: MessageProtocol {}

/// Builds a stack: the application protocol, then any below it.
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
@resultBuilder
public struct ProtocolStackBuilder<ApplicationProtocol, each P> where ApplicationProtocol: NetworkProtocolOptions, repeat each P: NetworkProtocolOptions {
    public static func buildBlock(_ applicationProtocol: ApplicationProtocol, _ belowProtocols: repeat each P) -> (ApplicationProtocol, repeat each P) {
        (applicationProtocol, repeat each belowProtocols)
    }
}

/// Builds the protocol metadata to send with content.
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
@resultBuilder
public struct ProtocolMetadataBuilder {
    public static func buildBlock(_ metadata: NWProtocolMetadata...) -> [NWProtocolMetadata] {
        metadata
    }
}

// MARK: - Parameters providers

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public protocol NWParametersProvider {
    var parameters: NWParameters { get }
    func requiredInterface(_ interface: NWInterface) -> Self
    func requiredInterfaceType(_ type: NWInterface.InterfaceType) -> Self
    func prohibitedInterfaces(_ interfaces: [NWInterface]) -> Self
    func prohibitedInterfaceTypes(_ types: [NWInterface.InterfaceType]) -> Self
    func expensivePathsProhibited(_ prohibited: Bool) -> Self
    func constrainedPathsProhibited(_ prohibited: Bool) -> Self
    func noProxiesPreferred(_ preferred: Bool) -> Self
    func localEndpoint(_ endpoint: NWEndpoint?) -> Self
    func localPort(_ port: NWEndpoint.Port) -> Self
    func localEndpointReuseAllowed(_ allowed: Bool) -> Self
    func localOnly(_ local: Bool) -> Self
    func peerToPeerIncluded(_ included: Bool) -> Self
    func dnssecValidationRequired(_ required: Bool) -> Self
    func serviceClass(_ serviceClass: NWParameters.ServiceClass) -> Self
    func multipathServiceType(_ type: NWParameters.MultipathServiceType) -> Self
    func fastOpenAllowed(_ allowed: Bool) -> Self
    func expiredDNSBehavior(_ behavior: NWParameters.ExpiredDNSBehavior) -> Self
    func ultraConstrainedPathsAllowed(_ allowed: Bool) -> Self
}

/// Each setter changes the provider's parameters and answers the provider.
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension NWParametersProvider {
    private func with(_ change: (NWParameters) -> Void) -> Self {
        change(parameters)
        return self
    }

    public func requiredInterface(_ interface: NWInterface) -> Self {
        with { $0.requiredInterface = interface }
    }

    public func requiredInterfaceType(_ type: NWInterface.InterfaceType) -> Self {
        with { $0.requiredInterfaceType = type }
    }

    public func prohibitedInterfaces(_ interfaces: [NWInterface]) -> Self {
        with { $0.prohibitedInterfaces = interfaces }
    }

    public func prohibitedInterfaceTypes(_ types: [NWInterface.InterfaceType]) -> Self {
        with { $0.prohibitedInterfaceTypes = types }
    }

    public func expensivePathsProhibited(_ prohibited: Bool) -> Self {
        with { $0.prohibitExpensivePaths = prohibited }
    }

    public func constrainedPathsProhibited(_ prohibited: Bool) -> Self {
        with { $0.prohibitConstrainedPaths = prohibited }
    }

    public func noProxiesPreferred(_ noProxies: Bool) -> Self {
        with { $0.preferNoProxies = noProxies }
    }

    public func localEndpoint(_ endpoint: NWEndpoint?) -> Self {
        with { $0.requiredLocalEndpoint = endpoint }
    }

    public func localPort(_ port: NWEndpoint.Port) -> Self {
        with { $0.requiredLocalEndpoint = .hostPort(host: .ipv6(.any), port: port) }
    }

    public func localEndpointReuseAllowed(_ allowed: Bool) -> Self {
        with { $0.allowLocalEndpointReuse = allowed }
    }

    public func localOnly(_ local: Bool) -> Self {
        with { $0.acceptLocalOnly = local }
    }

    public func peerToPeerIncluded(_ included: Bool) -> Self {
        with { $0.includePeerToPeer = included }
    }

    public func dnssecValidationRequired(_ required: Bool) -> Self {
        with { $0.requiresDNSSECValidation = required }
    }

    public func serviceClass(_ serviceClass: NWParameters.ServiceClass) -> Self {
        with { $0.serviceClass = serviceClass }
    }

    public func multipathServiceType(_ type: NWParameters.MultipathServiceType) -> Self {
        with { $0.multipathServiceType = type }
    }

    public func fastOpenAllowed(_ allowed: Bool) -> Self {
        with { $0.allowFastOpen = allowed }
    }

    public func expiredDNSBehavior(_ behavior: NWParameters.ExpiredDNSBehavior) -> Self {
        with { $0.expiredDNSBehavior = behavior }
    }

    public func ultraConstrainedPathsAllowed(_ val: Bool) -> Self {
        with { $0.allowUltraConstrainedPaths = val }
    }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension NWParameters: NWParametersProvider {
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    final public var parameters: NWParameters { self }
}

/// Parameters of a protocol stack, with the stack's description for the
/// connections made with them.
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public struct NWParametersBuilder<Top, each P>: NWParametersProvider where Top: NetworkProtocolOptions, repeat each P: NetworkProtocolOptions {
    public var parameters: NWParameters
    let stack: StackDescription

    private init(stack: StackDescription, initial: NWParameters?) {
        self.stack = stack
        parameters = stack.makeParameters(from: initial)
    }

    /// The stack of the builder's tuple (the top protocol and those below),
    /// taken as Any: its elements are read with a mirror.
    private static func describe(_ protocols: Any) -> StackDescription {
        describeStack(Mirror(reflecting: protocols).children.map(\.value))
    }

    public static func parameters(@ProtocolStackBuilder<Top, repeat each P> _ builder: () -> (Top, repeat each P)) -> NWParametersBuilder<Top, repeat each P> {
        NWParametersBuilder(stack: describe(builder()), initial: nil)
    }

    public static func parameters(initialParameters: NWParameters, @ProtocolStackBuilder<Top, repeat each P> _ builder: () -> (Top, repeat each P)) -> NWParametersBuilder<Top, repeat each P> {
        NWParametersBuilder(stack: describe(builder()), initial: initialParameters)
    }

    public init(auto: () -> (Top, repeat each P)) {
        self.init(stack: Self.describe(auto()), initial: nil)
    }

    public init(@ProtocolStackBuilder<Top, repeat each P> _ builder: () -> (Top, repeat each P)) {
        self.init(stack: Self.describe(builder()), initial: nil)
    }
}

// MARK: - Metadata of the stacks' protocols

/// Metadata made from what a receive gave.
protocol ReceivedMetadata {
    static func make(endOfStream: Bool, isComplete: Bool, context: NWConnection.ContentContext?) -> Self
}

private func otherMetadata(_ context: NWConnection.ContentContext?) -> [NWProtocolMetadata] {
    context?.protocolMetadata ?? []
}

// MARK: - IP

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public struct IP: NetworkProtocolOptions, StackLayer {
    public struct Metadata: NetworkMetadataProtocol, ReceivedMetadata {
        public let other: [NWProtocolMetadata]

        static func make(endOfStream: Bool, isComplete: Bool, context: NWConnection.ContentContext?) -> Metadata {
            Metadata(other: otherMetadata(context))
        }
    }

    private var settings: [(NWProtocolIP.Options) -> Void] = []

    public init() {}

    private func with(_ setting: @escaping (NWProtocolIP.Options) -> Void) -> IP {
        var copy = self
        copy.settings.append(setting)
        return copy
    }

    public func version(_ version: NWProtocolIP.Options.Version) -> IP { with { $0.version = version } }
    public func hopLimit(_ limit: UInt8) -> IP { with { $0.hopLimit = limit } }
    public func minimumMTU(_ useMinimumMTU: Bool) -> IP { with { $0.useMinimumMTU = useMinimumMTU } }
    public func fragmentationDisabled(_ dontFragment: Bool) -> IP { with { $0.disableFragmentation = dontFragment } }
    public func receiveTimeCalculated(_ calculateReceiveTime: Bool) -> IP { with { $0.shouldCalculateReceiveTime = calculateReceiveTime } }
    public func localAddressPreference(_ preference: NWProtocolIP.Options.AddressPreference) -> IP { with { $0.localAddressPreference = preference } }
    public func multicastLoopbackDisabled(_ disableMulticastLoopback: Bool) -> IP { with { $0.disableMulticastLoopback = disableMulticastLoopback } }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public typealias BelowProtocol = Void
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public typealias ProtocolStorage = DefaultProtocolStorage

    func describe(into stack: inout StackDescription) {
        stack.ipSettings.append(contentsOf: settings)
    }
}

// MARK: - TCP

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public struct TCP: StreamProtocol, StackLayer {
    public struct Metadata: NetworkMetadataProtocol, ReceivedMetadata {
        public let endOfStream: Bool
        public let other: [NWProtocolMetadata]

        static func make(endOfStream: Bool, isComplete: Bool, context: NWConnection.ContentContext?) -> Metadata {
            Metadata(endOfStream: endOfStream, other: otherMetadata(context))
        }
    }

    private var settings: [(NWProtocolTCP.Options) -> Void] = []
    private var below = IP()

    public init() {}

    public init(@ProtocolStackBuilder<IP> _ builder: () -> IP) {
        below = builder()
    }

    private func with(_ setting: @escaping (NWProtocolTCP.Options) -> Void) -> TCP {
        var copy = self
        copy.settings.append(setting)
        return copy
    }

    public func noDelay(_ noDelay: Bool) -> TCP { with { $0.noDelay = noDelay } }
    public func noPush(_ noPush: Bool) -> TCP { with { $0.noPush = noPush } }
    public func noOptions(_ noOptions: Bool) -> TCP { with { $0.noOptions = noOptions } }

    public func keepalive(idleTimeInSeconds: UInt32, count: UInt32, intervalInSeconds: UInt32) -> TCP {
        with {
            $0.enableKeepalive = true
            $0.keepaliveIdle = Int(idleTimeInSeconds)
            $0.keepaliveCount = Int(count)
            $0.keepaliveInterval = Int(intervalInSeconds)
        }
    }

    public func maximumSegmentSize(_ bytes: UInt32) -> TCP { with { $0.maximumSegmentSize = Int(bytes) } }
    public func connectionTimeout(_ timeout: UInt32) -> TCP { with { $0.connectionTimeout = Int(timeout) } }
    public func persistTimeout(_ timeout: UInt32) -> TCP { with { $0.persistTimeout = Int(timeout) } }
    public func retransmitConnectionDropTime(_ timeout: UInt32) -> TCP { with { $0.connectionDropTime = Int(timeout) } }
    public func retransmitFinDrop(_ drop: Bool) -> TCP { with { $0.retransmitFinDrop = drop } }
    public func ackStretchingDisabled(_ disableAckStretching: Bool) -> TCP { with { $0.disableAckStretching = disableAckStretching } }
    public func ecnDisabled(_ disableECN: Bool) -> TCP { with { $0.disableECN = disableECN } }
    public func fastOpenAllowed(_ allowed: Bool) -> TCP { with { $0.enableFastOpen = allowed } }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public typealias BelowProtocol = IP
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public typealias ProtocolStorage = DefaultProtocolStorage

    func describe(into stack: inout StackDescription) {
        let settings = self.settings
        stack.layers.append(.stream)
        stack.transport = {
            let options = NWProtocolTCP.Options()
            settings.forEach { $0(options) }
            return options
        }
        below.describe(into: &stack)
    }
}

// MARK: - UDP

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public struct UDP: DatagramProtocol, StackLayer {
    public struct Metadata: NetworkMetadataProtocol, ReceivedMetadata {
        public let other: [NWProtocolMetadata]

        static func make(endOfStream: Bool, isComplete: Bool, context: NWConnection.ContentContext?) -> Metadata {
            Metadata(other: otherMetadata(context))
        }
    }

    public typealias ContentType = Data

    private var settings: [(NWProtocolUDP.Options) -> Void] = []
    private var below = IP()

    public init() {}

    public init(@ProtocolStackBuilder<IP> _ builder: () -> IP) {
        below = builder()
    }

    public func noChecksumPreferred(_ noChecksum: Bool) -> UDP {
        var copy = self
        copy.settings.append { $0.preferNoChecksum = noChecksum }
        return copy
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public typealias BelowProtocol = IP
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public typealias LegacyMessage = (content: Data, metadata: [NWProtocolMetadata]?)
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public typealias ProtocolStorage = DefaultProtocolStorage

    func describe(into stack: inout StackDescription) {
        let settings = self.settings
        stack.layers.append(.datagram)
        stack.transport = {
            let options = NWProtocolUDP.Options()
            settings.forEach { $0(options) }
            return options
        }
        below.describe(into: &stack)
    }
}

// MARK: - TLS

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public struct TLS: StreamProtocol, StackLayer {
    public struct Metadata: NetworkMetadataProtocol, ReceivedMetadata {
        public let endOfStream: Bool
        public let other: [NWProtocolMetadata]

        static func make(endOfStream: Bool, isComplete: Bool, context: NWConnection.ContentContext?) -> Metadata {
            Metadata(endOfStream: endOfStream, other: otherMetadata(context))
        }
    }

    private var settings: [(sec_protocol_options_t) -> Void] = []
    private var below = TCP()

    public init() {}

    public init(@ProtocolStackBuilder<TCP> _ builder: () -> TCP) {
        below = builder()
    }

    private func with(_ setting: @escaping (sec_protocol_options_t) -> Void) -> TLS {
        var copy = self
        copy.settings.append(setting)
        return copy
    }

    public func localIdentity(_ identity: sec_identity_t) -> TLS {
        with { sec_protocol_options_set_local_identity($0, identity) }
    }

    public func certificateValidator(@_inheritActorContext _ handler: @escaping @isolated(any) @Sendable (sec_protocol_metadata_t, sec_trust_t) async -> Bool) -> TLS {
        with { setValidator($0, handler) }
    }

    public enum PeerAuthentication {
        case none
        case optional
        case required
    }

    public func peerAuthentication(_ preference: PeerAuthentication) -> TLS {
        with { setPeerAuthentication($0, required: preference == .required, optional: preference == .optional) }
    }

    public func applicationProtocols(_ protocols: [String]) -> TLS {
        with { options in protocols.forEach { sec_protocol_options_add_tls_application_protocol(options, $0) } }
    }

    public func cipherSuites(_ suites: [tls_ciphersuite_t]) -> TLS {
        with { options in suites.forEach { sec_protocol_options_append_tls_ciphersuite(options, $0) } }
    }

    public func cipherSuiteGroups(_ groups: [tls_ciphersuite_group_t]) -> TLS {
        with { options in groups.forEach { sec_protocol_options_append_tls_ciphersuite_group(options, $0) } }
    }

    /// TLS 1.3 early data; the C API has no switch for it, so this asks
    /// for it with the session tickets it needs.
    public func earlyDataEnabled(_ enabled: Bool) -> TLS {
        with { sec_protocol_options_set_tls_tickets_enabled($0, enabled) }
    }

    public func ticketsEnabled(_ enabled: Bool) -> TLS {
        with { sec_protocol_options_set_tls_tickets_enabled($0, enabled) }
    }

    public func version(min: tls_protocol_version_t? = nil, max: tls_protocol_version_t? = nil) -> TLS {
        with { options in
            if let min { sec_protocol_options_set_min_tls_protocol_version(options, min) }
            if let max { sec_protocol_options_set_max_tls_protocol_version(options, max) }
        }
    }

    @available(*, unavailable, message: "Pass a minimum or maximum version")
    public func version() -> TLS { self }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public typealias BelowProtocol = TCP
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public typealias ProtocolStorage = DefaultProtocolStorage

    func describe(into stack: inout StackDescription) {
        let settings = self.settings
        stack.layers.append(.stream)
        stack.application.append {
            let options = NWProtocolTLS.Options()
            settings.forEach { $0(options.securityProtocolOptions) }
            return options
        }
        below.describe(into: &stack)
    }
}

// MARK: - DTLS

@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
public struct DTLS: DatagramProtocol, StackLayer {
    public struct Metadata: NetworkMetadataProtocol, ReceivedMetadata {
        public let other: [NWProtocolMetadata]

        static func make(endOfStream: Bool, isComplete: Bool, context: NWConnection.ContentContext?) -> Metadata {
            Metadata(other: otherMetadata(context))
        }
    }

    private var settings: [(sec_protocol_options_t) -> Void] = []
    private var below = UDP()

    public init() {}

    public init(@ProtocolStackBuilder<UDP> _ builder: () -> UDP) {
        below = builder()
    }

    private func with(_ setting: @escaping (sec_protocol_options_t) -> Void) -> DTLS {
        var copy = self
        copy.settings.append(setting)
        return copy
    }

    public func localIdentity(_ identity: sec_identity_t) -> DTLS {
        with { sec_protocol_options_set_local_identity($0, identity) }
    }

    public func certificateValidator(@_inheritActorContext _ handler: @escaping @isolated(any) @Sendable (sec_protocol_metadata_t, sec_trust_t) async -> Bool) -> DTLS {
        with { setValidator($0, handler) }
    }

    public enum PeerAuthentication {
        case none
        case optional
        case required
    }

    public func peerAuthentication(_ preference: PeerAuthentication) -> DTLS {
        with { setPeerAuthentication($0, required: preference == .required, optional: preference == .optional) }
    }

    public func applicationProtocols(_ protocols: [String]) -> DTLS {
        with { options in protocols.forEach { sec_protocol_options_add_tls_application_protocol(options, $0) } }
    }

    public func cipherSuites(_ suites: [tls_ciphersuite_t]) -> DTLS {
        with { options in suites.forEach { sec_protocol_options_append_tls_ciphersuite(options, $0) } }
    }

    public func cipherSuiteGroups(_ groups: [tls_ciphersuite_group_t]) -> DTLS {
        with { options in groups.forEach { sec_protocol_options_append_tls_ciphersuite_group(options, $0) } }
    }

    public func earlyDataEnabled(_ enabled: Bool) -> DTLS {
        with { sec_protocol_options_set_tls_tickets_enabled($0, enabled) }
    }

    public func ticketsEnabled(_ enabled: Bool) -> DTLS {
        with { sec_protocol_options_set_tls_tickets_enabled($0, enabled) }
    }

    public func version(min: tls_protocol_version_t? = nil, max: tls_protocol_version_t? = nil) -> DTLS {
        with { options in
            if let min { sec_protocol_options_set_min_tls_protocol_version(options, min) }
            if let max { sec_protocol_options_set_max_tls_protocol_version(options, max) }
        }
    }

    @available(*, unavailable, message: "Pass a minimum or maximum version")
    public func version() -> DTLS { self }

    @available(macOS 27.0, iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
    public typealias BelowProtocol = UDP
    @available(macOS 27.0, iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
    public typealias ContentType = Data
    @available(macOS 27.0, iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
    public typealias LegacyMessage = (content: Data, metadata: [NWProtocolMetadata]?)
    @available(macOS 27.0, iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
    public typealias ProtocolStorage = DefaultProtocolStorage

    func describe(into stack: inout StackDescription) {
        let settings = self.settings
        stack.layers.append(.datagram)
        stack.application.append {
            let options = NWProtocolTLS.Options()
            settings.forEach { $0(options.securityProtocolOptions) }
            return options
        }
        below.describe(into: &stack)
    }
}

// MARK: - QUIC

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public struct QUIC: MultiplexProtocol, StackLayer {
    public struct Metadata: NetworkMetadataProtocol {}

    private let alpn: [String]
    fileprivate var settings: [(NWProtocolQUIC.Options) -> Void] = []

    public init(alpn: [String]) {
        self.alpn = alpn
    }

    /// QUIC on the UDP given; its options are QUIC's own here.
    public init(alpn: [String], @ProtocolStackBuilder<UDP> _ builder: () -> UDP) {
        self.alpn = alpn
        _ = builder()
    }

    public struct ProtocolStorage: ConnectionStorage {
        public init() {}
    }

    fileprivate func with(_ setting: @escaping (NWProtocolQUIC.Options) -> Void) -> QUIC {
        var copy = self
        copy.settings.append(setting)
        return copy
    }

    public func idleTimeout(_ timeout: Int) -> QUIC { with { $0.idleTimeout = timeout } }
    public func maxUDPPayloadSize(_ size: Int) -> QUIC { with { $0.maxUDPPayloadSize = size } }
    public func initialMaxData(_ initialMaxData: Int) -> QUIC { with { $0.initialMaxData = initialMaxData } }
    public func initialMaxStreamDataBidirectionalRemote(_ initialMaxStreamDataBidiRemote: Int) -> QUIC { with { $0.initialMaxStreamDataBidirectionalRemote = initialMaxStreamDataBidiRemote } }
    public func initialMaxStreamDataBidirectionalLocal(_ initialMaxStreamDataBidiLocal: Int) -> QUIC { with { $0.initialMaxStreamDataBidirectionalLocal = initialMaxStreamDataBidiLocal } }
    public func initialMaxStreamDataUnidirectional(_ initialMaxStreamDataUni: Int) -> QUIC { with { $0.initialMaxStreamDataUnidirectional = initialMaxStreamDataUni } }
    public func initialMaxBidirectionalStreams(_ initialMaxStreamsBidi: Int) -> QUIC { with { $0.initialMaxStreamsBidirectional = initialMaxStreamsBidi } }
    public func initialMaxUnidirectionalStreams(_ initialMaxStreamDataUni: Int) -> QUIC { with { $0.initialMaxStreamsUnidirectional = initialMaxStreamDataUni } }
    public func maxDatagramFrameSize(_ size: Int) -> QUIC { with { $0.maxDatagramFrameSize = size } }

    public var tls: TLS { TLS(quic: self) }

    /// QUIC's TLS settings.
    public struct TLS {
        fileprivate let quic: QUIC

        private func with(_ setting: @escaping (sec_protocol_options_t) -> Void) -> QUIC {
            quic.with { setting($0.securityProtocolOptions) }
        }

        public func localIdentity(_ identity: sec_identity_t) -> QUIC {
            with { sec_protocol_options_set_local_identity($0, identity) }
        }

        public func certificateValidator(@_inheritActorContext _ handler: @escaping @isolated(any) @Sendable (sec_protocol_metadata_t, sec_trust_t) async -> Bool) -> QUIC {
            with { setValidator($0, handler) }
        }

        public func peerAuthentication(_ preference: Network.TLS.PeerAuthentication) -> QUIC {
            with { setPeerAuthentication($0, required: preference == .required, optional: preference == .optional) }
        }

        public func cipherSuites(_ suites: [tls_ciphersuite_t]) -> QUIC {
            with { options in suites.forEach { sec_protocol_options_append_tls_ciphersuite(options, $0) } }
        }

        public func ciphersuiteGroups(_ groups: [tls_ciphersuite_group_t]) -> QUIC {
            with { options in groups.forEach { sec_protocol_options_append_tls_ciphersuite_group(options, $0) } }
        }
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public typealias BelowProtocol = UDP

    /// The QUIC options of the connection.
    func makeOptions() -> NWProtocolQUIC.Options {
        let options = NWProtocolQUIC.Options(alpn: alpn)
        settings.forEach { $0(options) }
        return options
    }

    func describe(into stack: inout StackDescription) {
        stack.layers.append(.quic)
        stack.transport = { self.makeOptions() }
    }
}

/// A stream of a QUIC connection.
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public struct QUICStream: StreamProtocol, StackLayer {
    public struct Metadata: NetworkMetadataProtocol, ReceivedMetadata {
        public let endOfStream: Bool
        public let other: [NWProtocolMetadata]

        static func make(endOfStream: Bool, isComplete: Bool, context: NWConnection.ContentContext?) -> Metadata {
            Metadata(endOfStream: endOfStream, other: otherMetadata(context))
        }
    }

    public enum Directionality: Equatable {
        case unidirectional
        case bidirectional
    }

    public enum Initiator: Equatable {
        case client
        case server
    }

    let directionality: Directionality

    init(directionality: Directionality = .bidirectional) {
        self.directionality = directionality
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public typealias BelowProtocol = Void
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public typealias ProtocolStorage = DefaultProtocolStorage

    func describe(into stack: inout StackDescription) {
        stack.layers.append(.stream)
    }
}

/// The datagrams of a QUIC connection.
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public struct QUICDatagram: DatagramProtocol, StackLayer {
    public struct Metadata: NetworkMetadataProtocol, ReceivedMetadata {
        public let other: [NWProtocolMetadata]

        static func make(endOfStream: Bool, isComplete: Bool, context: NWConnection.ContentContext?) -> Metadata {
            Metadata(other: otherMetadata(context))
        }
    }

    public typealias ContentType = Data

    init() {}

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public typealias BelowProtocol = Void
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public typealias LegacyMessage = (content: Data, metadata: [NWProtocolMetadata]?)
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public typealias ProtocolStorage = DefaultProtocolStorage

    func describe(into stack: inout StackDescription) {
        stack.layers.append(.datagram)
    }
}

// MARK: - TLV

/// Messages of a type and a length before their value, framed in Swift.
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public struct TLV: MessageProtocol, StackLayer {
    public struct Metadata: NetworkMetadataProtocol {
        public let type: Int
        public let length: Int
        public let isComplete: Bool
        public let lastMessage: Bool
        public let other: [NWProtocolMetadata]
    }

    private let typeSize: Int
    private let lengthSize: Int
    private let below: Any

    public init<BelowProtocol>(@ProtocolStackBuilder<BelowProtocol> _ builder: () -> BelowProtocol) where BelowProtocol: StreamProtocol {
        self.init(typeSize: 4, lengthSize: 4, below: builder())
    }

    public init<BelowProtocol>(@ProtocolStackBuilder<BelowProtocol> _ builder: () -> BelowProtocol) where BelowProtocol: MessageProtocol {
        self.init(typeSize: 4, lengthSize: 4, below: builder())
    }

    public init<T, L, BelowProtocol>(type: T.Type, length: L.Type, @ProtocolStackBuilder<BelowProtocol> _ builder: () -> BelowProtocol) where T: Sendable, T: UnsignedInteger, L: Sendable, L: UnsignedInteger, BelowProtocol: StreamProtocol {
        self.init(typeSize: MemoryLayout<T>.size, lengthSize: MemoryLayout<L>.size, below: builder())
    }

    public init<T, L, BelowProtocol>(type: T.Type, length: L.Type, @ProtocolStackBuilder<BelowProtocol> _ builder: () -> BelowProtocol) where T: Sendable, T: UnsignedInteger, L: Sendable, L: UnsignedInteger, BelowProtocol: MessageProtocol {
        self.init(typeSize: MemoryLayout<T>.size, lengthSize: MemoryLayout<L>.size, below: builder())
    }

    private init(typeSize: Int, lengthSize: Int, below: Any) {
        self.typeSize = Swift.min(Swift.max(typeSize, 1), 8)
        self.lengthSize = Swift.min(Swift.max(lengthSize, 1), 8)
        self.below = below
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public typealias BelowProtocol = any NetworkProtocolOptions
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public typealias ContentType = Data
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public typealias LegacyMessage = (type: Int, content: Data, metadata: [NWProtocolMetadata]?, isFinal: Bool)
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public typealias ProtocolStorage = DefaultProtocolStorage

    func describe(into stack: inout StackDescription) {
        stack.layers.append(.tlv)
        stack.framing = .tlv(typeSize: typeSize, lengthSize: lengthSize)
        (below as? any StackLayer)?.describe(into: &stack)
    }
}

// MARK: - Coder

/// Codable values sent as messages, encoded and decoded with a coder.
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public struct Coder<Sending, Receiving, CoderType>: MessageProtocol, StackLayer where Sending: Encodable, Receiving: Decodable, CoderType: NetworkCoder {
    public struct Metadata: NetworkMetadataProtocol {
        public let isComplete: Bool
        public let lastMessage: Bool
        public let other: [NWProtocolMetadata]
    }

    public typealias ContentType = Receiving

    private let coder: CoderType
    private let below: Any

    private init(coder: CoderType, below: Any) {
        self.coder = coder
        self.below = below
    }

    public init<BelowProtocol>(sending: Sending.Type, receiving: Receiving.Type, using: CoderType, @ProtocolStackBuilder<BelowProtocol> _ builder: () -> BelowProtocol) where BelowProtocol: StreamProtocol {
        self.init(coder: using, below: builder())
    }

    public init<BelowProtocol>(sending: Sending.Type, receiving: Receiving.Type, using: CoderType, @ProtocolStackBuilder<BelowProtocol> _ builder: () -> BelowProtocol) where BelowProtocol: DatagramProtocol {
        self.init(coder: using, below: builder())
    }

    public init<BelowProtocol>(receiving: Receiving.Type, sending: Sending.Type, using: CoderType, @ProtocolStackBuilder<BelowProtocol> _ builder: () -> BelowProtocol) where BelowProtocol: StreamProtocol {
        self.init(coder: using, below: builder())
    }

    public init<BelowProtocol>(receiving: Receiving.Type, sending: Sending.Type, using: CoderType, @ProtocolStackBuilder<BelowProtocol> _ builder: () -> BelowProtocol) where BelowProtocol: DatagramProtocol {
        self.init(coder: using, below: builder())
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public typealias BelowProtocol = any NetworkProtocolOptions
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public typealias LegacyMessage = (content: ContentType, metadata: [NWProtocolMetadata]?, isFinal: Bool)
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public typealias ProtocolStorage = DefaultProtocolStorage

    func describe(into stack: inout StackDescription) {
        let coder = self.coder
        stack.layers.append(.coder)
        stack.framing = .coder(
            encode: { value in
                guard let value = value as? Sending else { throw NWError.posix(.EINVAL) }
                return try coder.makeEncoder().encode(value)
            },
            decode: { data in try coder.makeDecoder().decode(Receiving.self, from: data) }
        )
        (below as? any StackLayer)?.describe(into: &stack)
    }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension Coder where Sending: Decodable, Sending == Receiving {
    public init<BelowProtocol>(_ type: Sending.Type, using: CoderType, @ProtocolStackBuilder<BelowProtocol> _ builder: () -> BelowProtocol) where BelowProtocol: StreamProtocol {
        self.init(sending: type, receiving: type, using: using, builder)
    }

    public init<BelowProtocol>(_ type: Sending.Type, using: CoderType, @ProtocolStackBuilder<BelowProtocol> _ builder: () -> BelowProtocol) where BelowProtocol: DatagramProtocol {
        self.init(sending: type, receiving: type, using: using, builder)
    }
}

// MARK: - WebSocket

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public struct WebSocket: MessageProtocol, StackLayer {
    public struct Metadata: NetworkMetadataProtocol {
        public let opcode: NWProtocolWebSocket.Opcode
        public let closeCode: NWProtocolWebSocket.CloseCode?
        public let isComplete: Bool
        public let lastMessage: Bool
        public let other: [NWProtocolMetadata]
    }

    private var settings: [(NWProtocolWebSocket.Options) -> Void] = []
    private let below: Any

    public init<BelowProtocol>(@ProtocolStackBuilder<BelowProtocol> _ builder: () -> BelowProtocol) where BelowProtocol: StreamProtocol {
        below = builder()
    }

    public init<BelowProtocol>(@ProtocolStackBuilder<BelowProtocol> _ builder: () -> BelowProtocol) where BelowProtocol: MessageProtocol {
        below = builder()
    }

    private func with(_ setting: @escaping (NWProtocolWebSocket.Options) -> Void) -> WebSocket {
        var copy = self
        copy.settings.append(setting)
        return copy
    }

    public func additionalHeaders(_ headers: [(name: String, value: String)]) -> WebSocket { with { $0.setAdditionalHeaders(headers) } }
    public func subprotocols(_ subprotocols: [String]) -> WebSocket { with { $0.setSubprotocols(subprotocols) } }
    public func autoReplyPing(_ reply: Bool) -> WebSocket { with { $0.autoReplyPing = reply } }
    public func skipHandshake(_ skip: Bool) -> WebSocket { with { $0.skipHandshake = skip } }
    public func maximumMessageSize(_ size: Int) -> WebSocket { with { $0.maximumMessageSize = size } }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public typealias BelowProtocol = any NetworkProtocolOptions
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public typealias ContentType = Data
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public typealias LegacyMessage = (type: NWProtocolWebSocket.Opcode, content: Data, metadata: [NWProtocolMetadata]?, isFinal: Bool)
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public typealias ProtocolStorage = DefaultProtocolStorage

    func describe(into stack: inout StackDescription) {
        let settings = self.settings
        stack.layers.append(.webSocket)
        stack.application.append {
            let options = NWProtocolWebSocket.Options()
            settings.forEach { $0(options) }
            return options
        }
        (below as? any StackLayer)?.describe(into: &stack)
    }
}

// MARK: - Framer

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public protocol FramerProtocol {
    static var definition: NWProtocolFramer.Definition { get }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public struct Framer<T>: MessageProtocol, StackLayer where T: FramerProtocol {
    public struct Metadata: NetworkMetadataProtocol {
        public let framer: NWProtocolFramer.Message
        public let isComplete: Bool
        public let lastMessage: Bool
        public let other: [NWProtocolMetadata]

        public init(framer: NWProtocolFramer.Message, isComplete: Bool, lastMessage: Bool, other: [NWProtocolMetadata]?) {
            self.framer = framer
            self.isComplete = isComplete
            self.lastMessage = lastMessage
            self.other = other ?? []
        }
    }

    public typealias ContentType = Data

    public var options: NWProtocolFramer.Options
    private let below: Any

    public init<BelowProtocol>(@ProtocolStackBuilder<BelowProtocol> _ builder: () -> BelowProtocol) where BelowProtocol: StreamProtocol {
        options = NWProtocolFramer.Options(definition: T.definition)
        below = builder()
    }

    public init<BelowProtocol>(@ProtocolStackBuilder<BelowProtocol> _ builder: () -> BelowProtocol) where BelowProtocol: MessageProtocol {
        options = NWProtocolFramer.Options(definition: T.definition)
        below = builder()
    }

    public init<BelowProtocol>(using framer: T.Type, @ProtocolStackBuilder<BelowProtocol> _ builder: () -> BelowProtocol) where BelowProtocol: StreamProtocol {
        options = NWProtocolFramer.Options(definition: framer.definition)
        below = builder()
    }

    public init<BelowProtocol>(using framer: T.Type, @ProtocolStackBuilder<BelowProtocol> _ builder: () -> BelowProtocol) where BelowProtocol: MessageProtocol {
        options = NWProtocolFramer.Options(definition: framer.definition)
        below = builder()
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public typealias BelowProtocol = any NetworkProtocolOptions
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public typealias LegacyMessage = (Data, Framer<T>.Metadata)
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public typealias ProtocolStorage = DefaultProtocolStorage

    func describe(into stack: inout StackDescription) {
        let options = self.options
        stack.layers.append(.framer)
        stack.application.append { options }
        (below as? any StackLayer)?.describe(into: &stack)
    }
}

// MARK: - Coders

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public protocol NetworkEncoder {
    func encode<T>(_ value: T) throws -> Data where T: Encodable
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension JSONEncoder: NetworkEncoder {}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension PropertyListEncoder: NetworkEncoder {}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public protocol NetworkDecoder {
    func decode<T>(_ type: T.Type, from data: Data) throws -> T where T: Decodable
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension JSONDecoder: NetworkDecoder {}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension PropertyListDecoder: NetworkDecoder {}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public protocol NetworkCoder: Sendable {
    associatedtype Encoder: NetworkEncoder
    associatedtype Decoder: NetworkDecoder
    init()
    func makeEncoder() -> Encoder
    func makeDecoder() -> Decoder
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension NetworkCoder where Self == NetworkJSONCoder {
    public static var json: NetworkJSONCoder { NetworkJSONCoder() }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension NetworkCoder where Self == NetworkPropertyListCoder {
    public static var propertyList: NetworkPropertyListCoder { NetworkPropertyListCoder() }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public struct NetworkJSONCoder: NetworkCoder {
    public init() {}
    public func makeEncoder() -> JSONEncoder { JSONEncoder() }
    public func makeDecoder() -> JSONDecoder { JSONDecoder() }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public typealias Decoder = JSONDecoder
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public typealias Encoder = JSONEncoder
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public struct NetworkPropertyListCoder: NetworkCoder {
    public init() {}

    public func makeEncoder() -> PropertyListEncoder {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return encoder
    }

    public func makeDecoder() -> PropertyListDecoder { PropertyListDecoder() }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public typealias Decoder = PropertyListDecoder
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public typealias Encoder = PropertyListEncoder
}

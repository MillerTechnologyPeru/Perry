// NWParameters over the C API's nw_parameters_t: its protocol stack,
// privacy contexts and proxy configurations.

import Foundation
import Network.FoundationExtension
import Security

@_hasMissingDesignatedInitializers
@available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
@_objcRuntimeName(_TtC7Network13_NWParameters)
final public class NWParameters: CustomDebugStringConvertible {
    let nw: nw_parameters_t
    /// The interfaces set, kept for the getters of those the C API can't
    /// take (ones not from it).
    private var storedRequiredInterface: NWInterface?
    private var storedProhibitedInterfaces: [NWInterface]?
    private var storedPrivacyContext: PrivacyContext?

    init(_ nw: nw_parameters_t) {
        self.nw = nw
    }

    final public var debugDescription: String {
        nw.description
    }

    /// Parameters with a stack of the protocols given, from the top one.
    private convenience init(transport: NWProtocolOptions, application: NWProtocolOptions?) {
        self.init(nw_parameters_create())
        let stack = nw_parameters_copy_default_protocol_stack(nw)
        nw_protocol_stack_set_transport_protocol(stack, transport.nw)
        if let application {
            nw_protocol_stack_prepend_application_protocol(stack, application.nw)
        }
    }

    public convenience init(tls: NWProtocolTLS.Options?, tcp: NWProtocolTCP.Options = NWProtocolTCP.Options()) {
        self.init(transport: tcp, application: tls)
    }

    public convenience init(dtls: NWProtocolTLS.Options?, udp: NWProtocolUDP.Options = NWProtocolUDP.Options()) {
        self.init(transport: udp, application: dtls)
    }

    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    public convenience init(quic: NWProtocolQUIC.Options) {
        self.init(transport: quic, application: nil)
    }

    /// Parameters of raw IP with the protocol number given.
    @available(macOS 10.15, *)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    public init(customIPProtocolNumber: UInt8) {
        nw = nw_parameters_create_custom_ip(customIPProtocolNumber) { _ in }
    }

    public init() {
        nw = nw_parameters_create()
    }

    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    final public class var applicationService: NWParameters {
        NWParameters(nw_parameters_create_application_service())
    }

    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    final public class func quic(alpn: [String]) -> NWParameters {
        NWParameters(quic: NWProtocolQUIC.Options(alpn: alpn))
    }

    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    final public class func quicDatagram(alpn: [String]) -> NWParameters {
        let options = NWProtocolQUIC.Options(alpn: alpn)
        options.isDatagram = true
        return NWParameters(quic: options)
    }

    final public class var tls: NWParameters {
        NWParameters(tls: NWProtocolTLS.Options())
    }

    final public class var dtls: NWParameters {
        NWParameters(dtls: NWProtocolTLS.Options())
    }

    final public class var tcp: NWParameters {
        NWParameters(tls: nil)
    }

    final public class var udp: NWParameters {
        NWParameters(dtls: nil)
    }

    final public var requiredInterface: NWInterface? {
        get {
            nw_parameters_copy_required_interface(nw).map(NWInterface.init) ?? storedRequiredInterface
        }
        set {
            storedRequiredInterface = newValue
            nw_parameters_require_interface(nw, newValue?.nw)
        }
    }

    final public var requiredInterfaceType: NWInterface.InterfaceType {
        get { NWInterface.InterfaceType(nw_parameters_get_required_interface_type(nw)) }
        set { nw_parameters_set_required_interface_type(nw, newValue.nw) }
    }

    final public var prohibitedInterfaces: [NWInterface]? {
        get {
            var interfaces: [NWInterface] = []
            nw_parameters_iterate_prohibited_interfaces(nw) { interface in
                interfaces.append(NWInterface(interface))
                return true
            }
            if interfaces.isEmpty { return storedProhibitedInterfaces }
            return interfaces
        }
        set {
            storedProhibitedInterfaces = newValue
            nw_parameters_clear_prohibited_interfaces(nw)
            for interface in newValue ?? [] {
                if let nwInterface = interface.nw {
                    nw_parameters_prohibit_interface(nw, nwInterface)
                }
            }
        }
    }

    final public var prohibitedInterfaceTypes: [NWInterface.InterfaceType]? {
        get {
            var types: [NWInterface.InterfaceType] = []
            nw_parameters_iterate_prohibited_interface_types(nw) { type in
                types.append(NWInterface.InterfaceType(type))
                return true
            }
            return types.isEmpty ? nil : types
        }
        set {
            nw_parameters_clear_prohibited_interface_types(nw)
            for type in newValue ?? [] {
                nw_parameters_prohibit_interface_type(nw, type.nw)
            }
        }
    }

    final public var prohibitExpensivePaths: Bool {
        get { nw_parameters_get_prohibit_expensive(nw) }
        set { nw_parameters_set_prohibit_expensive(nw, newValue) }
    }

    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    final public var prohibitConstrainedPaths: Bool {
        get { nw_parameters_get_prohibit_constrained(nw) }
        set { nw_parameters_set_prohibit_constrained(nw, newValue) }
    }

    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    final public var allowUltraConstrainedPaths: Bool {
        get { nw_parameters_get_allow_ultra_constrained(nw) }
        set { nw_parameters_set_allow_ultra_constrained(nw, newValue) }
    }

    final public var preferNoProxies: Bool {
        get { nw_parameters_get_prefer_no_proxy(nw) }
        set { nw_parameters_set_prefer_no_proxy(nw, newValue) }
    }

    final public var requiredLocalEndpoint: NWEndpoint? {
        get { nw_parameters_copy_local_endpoint(nw).map(NWEndpoint.init) }
        set { nw_parameters_set_local_endpoint(nw, newValue?.nw) }
    }

    final public var allowLocalEndpointReuse: Bool {
        get { nw_parameters_get_reuse_local_address(nw) }
        set { nw_parameters_set_reuse_local_address(nw, newValue) }
    }

    final public var acceptLocalOnly: Bool {
        get { nw_parameters_get_local_only(nw) }
        set { nw_parameters_set_local_only(nw, newValue) }
    }

    final public var includePeerToPeer: Bool {
        get { nw_parameters_get_include_peer_to_peer(nw) }
        set { nw_parameters_set_include_peer_to_peer(nw, newValue) }
    }

    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    final public var requiresDNSSECValidation: Bool {
        get { nw_parameters_requires_dnssec_validation(nw) }
        set { nw_parameters_set_requires_dnssec_validation(nw, newValue) }
    }

    public enum ServiceClass: Sendable {
        case bestEffort
        case background
        case interactiveVideo
        case interactiveVoice
        case responsiveData
        case signaling
    }

    final public var serviceClass: ServiceClass {
        get { ServiceClass(nw_parameters_get_service_class(nw)) }
        set { nw_parameters_set_service_class(nw, newValue.nw) }
    }

    public enum MultipathServiceType: Sendable {
        case disabled
        case handover
        case interactive
        case aggregate
    }

    final public var multipathServiceType: MultipathServiceType {
        get {
            switch nw_parameters_get_multipath_service(nw) {
            case nw_multipath_service_handover: return .handover
            case nw_multipath_service_interactive: return .interactive
            case nw_multipath_service_aggregate: return .aggregate
            default: return .disabled
            }
        }
        set {
            switch newValue {
            case .disabled: nw_parameters_set_multipath_service(nw, nw_multipath_service_disabled)
            case .handover: nw_parameters_set_multipath_service(nw, nw_multipath_service_handover)
            case .interactive: nw_parameters_set_multipath_service(nw, nw_multipath_service_interactive)
            case .aggregate: nw_parameters_set_multipath_service(nw, nw_multipath_service_aggregate)
            }
        }
    }

    final public var allowFastOpen: Bool {
        get { nw_parameters_get_fast_open_enabled(nw) }
        set { nw_parameters_set_fast_open_enabled(nw, newValue) }
    }

    public enum ExpiredDNSBehavior: Sendable {
        case systemDefault
        case allow
        case prohibit
        @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
        case persistent
    }

    final public var expiredDNSBehavior: ExpiredDNSBehavior {
        get {
            switch nw_parameters_get_expired_dns_behavior(nw) {
            case nw_parameters_expired_dns_behavior_allow: return .allow
            case nw_parameters_expired_dns_behavior_prohibit: return .prohibit
            case nw_parameters_expired_dns_behavior_persistent: return .persistent
            default: return .systemDefault
            }
        }
        set {
            switch newValue {
            case .systemDefault: nw_parameters_set_expired_dns_behavior(nw, nw_parameters_expired_dns_behavior_default)
            case .allow: nw_parameters_set_expired_dns_behavior(nw, nw_parameters_expired_dns_behavior_allow)
            case .prohibit: nw_parameters_set_expired_dns_behavior(nw, nw_parameters_expired_dns_behavior_prohibit)
            case .persistent: nw_parameters_set_expired_dns_behavior(nw, nw_parameters_expired_dns_behavior_persistent)
            }
        }
    }

    /// The protocols of the parameters, from the application's down.
    @_hasMissingDesignatedInitializers
    @_objcRuntimeName(_TtCC7Network13_NWParameters13ProtocolStack)
    public class ProtocolStack {
        let nw: nw_protocol_stack_t

        init(_ nw: nw_protocol_stack_t) {
            self.nw = nw
        }

        /// The protocols above the transport one, the top one first.
        public var applicationProtocols: [NWProtocolOptions] {
            get {
                var protocols: [NWProtocolOptions] = []
                nw_protocol_stack_iterate_application_protocols(nw) { options in
                    protocols.append(NWProtocolOptions.wrap(options))
                }
                return protocols
            }
            set {
                nw_protocol_stack_clear_application_protocols(nw)
                for options in newValue.reversed() {
                    nw_protocol_stack_prepend_application_protocol(nw, options.nw)
                }
            }
        }

        public var transportProtocol: NWProtocolOptions? {
            get { nw_protocol_stack_copy_transport_protocol(nw).map(NWProtocolOptions.wrap) }
            set {
                if let newValue {
                    nw_protocol_stack_set_transport_protocol(nw, newValue.nw)
                }
            }
        }

        /// The IP options of the stack. The C API has no way to replace
        /// them, so setting other options does nothing: change these.
        public var internetProtocol: NWProtocolOptions? {
            get { nw_protocol_stack_copy_internet_protocol(nw).map(NWProtocolOptions.wrap) }
            set {}
        }

        deinit {}
    }

    final public var defaultProtocolStack: ProtocolStack {
        ProtocolStack(nw_parameters_copy_default_protocol_stack(nw))
    }

    /// Settings of name resolution, caching, logging and proxies a set of
    /// connections share.
    @_hasMissingDesignatedInitializers
    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
    public class PrivacyContext: CustomDebugStringConvertible, @unchecked Sendable {
        let nw: nw_privacy_context_t
        private let name: String
        private var storedProxies: [ProxyConfiguration] = []

        init(_ nw: nw_privacy_context_t, name: String) {
            self.nw = nw
            self.name = name
        }

        public var debugDescription: String { name }

        /// The process's default privacy context.
        public static let `default` = PrivacyContext(_nw_privacy_context_default_context, name: "default")

        public init(description: String) {
            nw = nw_privacy_context_create(description)
            name = description
        }

        public func flushCache() {
            nw_privacy_context_flush_cache(nw)
        }

        public func disableLogging() {
            nw_privacy_context_disable_logging(nw)
        }

        public enum ResolverConfiguration: CustomDebugStringConvertible, Sendable {
            public var debugDescription: String {
                switch self {
                case .tls(let endpoint, let servers):
                    return "DNS over TLS to \(endpoint.debugDescription) \(servers.map(\.debugDescription))"
                case .https(let url, let servers):
                    return "DNS over HTTPS to \(url.absoluteString) \(servers.map(\.debugDescription))"
                }
            }

            case tls(_: NWEndpoint, serverAddresses: [NWEndpoint])
            case https(_: URL, serverAddresses: [NWEndpoint])

            var nw: nw_resolver_config_t {
                switch self {
                case .tls(let endpoint, let servers):
                    let config = nw_resolver_config_create_tls(endpoint.nw)
                    for server in servers {
                        nw_resolver_config_add_server_address(config, server.nw)
                    }
                    return config
                case .https(let url, let servers):
                    let config = nw_resolver_config_create_https(nw_endpoint_create_url(url.absoluteString))
                    for server in servers {
                        nw_resolver_config_add_server_address(config, server.nw)
                    }
                    return config
                }
            }
        }

        public func requireEncryptedNameResolution(_ requireEncryption: Bool, fallbackResolver: ResolverConfiguration?) {
            nw_privacy_context_require_encrypted_name_resolution(nw, requireEncryption, fallbackResolver?.nw)
        }

        @available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
        public var proxyConfigurations: [ProxyConfiguration] {
            get { storedProxies }
            set {
                storedProxies = newValue
                nw_privacy_context_clear_proxies(nw)
                for proxy in newValue {
                    nw_privacy_context_add_proxy(nw, proxy._nw)
                }
            }
        }

        deinit {}
    }

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
    final public func setPrivacyContext(_ privacyContext: PrivacyContext) {
        storedPrivacyContext = privacyContext
        nw_parameters_set_privacy_context(nw, privacyContext.nw)
    }

    final public func copy() -> NWParameters {
        let copy = NWParameters(nw_parameters_copy(nw))
        copy.storedRequiredInterface = storedRequiredInterface
        copy.storedProhibitedInterfaces = storedProhibitedInterfaces
        copy.storedPrivacyContext = storedPrivacyContext
        return copy
    }

    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    public enum Attribution: Equatable, Sendable {
        case developer
        case user
    }

    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    final public var attribution: Attribution {
        get { nw_parameters_get_attribution(nw) == .user ? .user : .developer }
        set { nw_parameters_set_attribution(nw, newValue == .user ? .user : .developer) }
    }

    deinit {}
}

extension NWParameters.ServiceClass {
    init(_ serviceClass: nw_service_class_t) {
        switch serviceClass {
        case nw_service_class_background: self = .background
        case nw_service_class_interactive_video: self = .interactiveVideo
        case nw_service_class_interactive_voice: self = .interactiveVoice
        case nw_service_class_responsive_data: self = .responsiveData
        case nw_service_class_signaling: self = .signaling
        default: self = .bestEffort
        }
    }

    var nw: nw_service_class_t {
        switch self {
        case .bestEffort: return nw_service_class_best_effort
        case .background: return nw_service_class_background
        case .interactiveVideo: return nw_service_class_interactive_video
        case .interactiveVoice: return nw_service_class_interactive_voice
        case .responsiveData: return nw_service_class_responsive_data
        case .signaling: return nw_service_class_signaling
        }
    }
}

// MARK: - Proxies

/// A proxy connections go through: SOCKS, HTTP CONNECT, a chain of
/// MASQUE relays or an Oblivious HTTP relay, over the C API's
/// nw_proxy_config_t.
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
public struct ProxyConfiguration: CustomDebugStringConvertible, @unchecked Sendable {
    public var debugDescription: String { _nw.description }

    @available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
    public init(_nw: nw_proxy_config_t) {
        self._nw = _nw
    }

    @available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
    public let _nw: nw_proxy_config_t

    public var allowFailover: Bool {
        get { nw_proxy_config_get_failover_allowed(_nw) }
        set { nw_proxy_config_set_failover_allowed(_nw, newValue) }
    }

    public var matchDomains: [String] {
        get {
            var domains: [String] = []
            nw_proxy_config_enumerate_match_domains(_nw) { domains.append(String(cString: $0)) }
            return domains
        }
        set {
            nw_proxy_config_clear_match_domains(_nw)
            for domain in newValue {
                nw_proxy_config_add_match_domain(_nw, domain)
            }
        }
    }

    public var excludedDomains: [String] {
        get {
            var domains: [String] = []
            nw_proxy_config_enumerate_excluded_domains(_nw) { domains.append(String(cString: $0)) }
            return domains
        }
        set {
            nw_proxy_config_clear_excluded_domains(_nw)
            for domain in newValue {
                nw_proxy_config_add_excluded_domain(_nw, domain)
            }
        }
    }

    public func applyCredential(username: String, password: String) {
        nw_proxy_config_set_username_and_password(_nw, username, password)
    }

    public init(socksv5Proxy: NWEndpoint) {
        _nw = nw_proxy_config_create_socksv5(socksv5Proxy.nw)
    }

    public init(httpCONNECTProxy: NWEndpoint, tlsOptions: NWProtocolTLS.Options? = nil) {
        _nw = nw_proxy_config_create_http_connect(httpCONNECTProxy.nw, tlsOptions?.nw)
    }

    /// A relay of a chain: HTTP/3 (falling back to HTTP/2) or HTTP/2.
    public struct RelayHop: CustomDebugStringConvertible, @unchecked Sendable {
        let nw: nw_relay_hop_t

        public var debugDescription: String { nw.description }

        public init(http3RelayEndpoint: NWEndpoint, http2RelayEndpoint: NWEndpoint? = nil, tlsOptions: NWProtocolTLS.Options = .init(), additionalHTTPHeaderFields: [String: String] = [:]) {
            nw = nw_relay_hop_create(http3RelayEndpoint.nw, http2RelayEndpoint?.nw, tlsOptions.nw)
            for (name, value) in additionalHTTPHeaderFields.sorted(by: { $0.key < $1.key }) {
                nw_relay_hop_add_additional_http_header_field(nw, name, value)
            }
        }

        public init(http2RelayEndpoint: NWEndpoint, tlsOptions: NWProtocolTLS.Options = .init(), additionalHTTPHeaderFields: [String: String] = [:]) {
            nw = nw_relay_hop_create(nil, http2RelayEndpoint.nw, tlsOptions.nw)
            for (name, value) in additionalHTTPHeaderFields.sorted(by: { $0.key < $1.key }) {
                nw_relay_hop_add_additional_http_header_field(nw, name, value)
            }
        }
    }

    /// A chain of one or two relays (the C API takes two at most).
    public init(relayHops: [RelayHop]) {
        precondition(!relayHops.isEmpty, "A relay proxy needs a relay")
        _nw = nw_proxy_config_create_relay(relayHops[0].nw, relayHops.count > 1 ? relayHops[1].nw : nil)
    }

    public init(obliviousHTTPRelay: RelayHop, relayResourcePath: String, gatewayKeyConfig: Data, matchDomains: [String]) {
        let bytes = [UInt8](gatewayKeyConfig)
        _nw = bytes.withUnsafeBufferPointer { buffer in
            nw_proxy_config_create_oblivious_http(obliviousHTTPRelay.nw, relayResourcePath, buffer.baseAddress ?? UnsafePointer(bitPattern: 1)!, buffer.count)
        }
        for domain in matchDomains {
            nw_proxy_config_add_match_domain(_nw, domain)
        }
    }
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
extension NWParameters: @unchecked Sendable {}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
extension NWParameters.ProtocolStack: @unchecked Sendable {}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
extension URLSessionConfiguration {
    @available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
    public var proxyConfigurations: [ProxyConfiguration] {
        get { __proxyConfigurations.map { ProxyConfiguration(_nw: $0) } }
        set { __proxyConfigurations = newValue.map(\._nw) }
    }
}

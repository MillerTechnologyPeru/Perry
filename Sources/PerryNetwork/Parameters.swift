import Glibc
import PerryObjCInterop

// Parameters and their protocol stack, and the privacy contexts, proxy
// configurations, relay hops and resolver configurations parameters can
// carry. Proxies and encrypted resolvers are kept and reported but not
// used: connections go direct and resolve with the system resolver.

final class ProtocolStackState: NWState {
    /// Application protocols, top first (+1 each).
    var applicationProtocols: [UnsafeMutableRawPointer] = []
    var transport: UnsafeMutableRawPointer?
    var internet: UnsafeMutableRawPointer

    init(internet: UnsafeMutableRawPointer) { self.internet = internet }

    deinit {
        applicationProtocols.forEach { ObjCRuntime.release($0) }
        ObjCRuntime.release(transport)
        ObjCRuntime.release(internet)
    }

    func copy() -> ProtocolStackState {
        let copy = ProtocolStackState(internet: Options.copy(internet))
        copy.applicationProtocols = applicationProtocols.map(Options.copy)
        copy.transport = transport.map(Options.copy)
        return copy
    }

    var transportKind: ProtocolKind { Options.state(transport)?.kind ?? .tcp }
    var ipOptions: OptionsState? { Options.state(internet) }
    var transportOptions: OptionsState? { Options.state(transport) }

    /// Application protocols bottom first, as a connection stacks them.
    var applicationBottomUp: [OptionsState] { applicationProtocols.reversed().compactMap { Options.state($0) } }
}

@ObjCClass("OS_nw_protocol_stack")
open class NWProtocolStackObject: NWObject {}

final class ParametersState: NWState {
    /// The protocol stack (+1).
    var stack: UnsafeMutableRawPointer
    var requiredInterface: UnsafeMutableRawPointer?
    var requiredInterfaceType: Int32 = 0
    var prohibitedInterfaces: [UnsafeMutableRawPointer] = []
    var prohibitedInterfaceTypes: [Int32] = []
    var prohibitExpensive = false
    var prohibitConstrained = false
    var allowUltraConstrained = false
    var reuseLocalAddress = false
    var localEndpoint: UnsafeMutableRawPointer?
    var includePeerToPeer = false
    var fastOpenEnabled = false
    var serviceClass: Int32 = 0
    var multipathService: Int32 = 0
    var expiredDNSBehavior: Int32 = 0
    var localOnly = false
    var preferNoProxy = false
    var attribution: Int32 = 1
    var requiresDNSSECValidation = false
    var privacyContext: UnsafeMutableRawPointer?
    /// The IP protocol number of parameters made for a custom IP protocol.
    var customIPProtocol: UInt8?

    init(stack: ProtocolStackState) {
        self.stack = NWObjects.make(NWProtocolStackObject.objCClass, stack)
    }

    deinit {
        ObjCRuntime.release(stack)
        ObjCRuntime.release(requiredInterface)
        prohibitedInterfaces.forEach { ObjCRuntime.release($0) }
        ObjCRuntime.release(localEndpoint)
        ObjCRuntime.release(privacyContext)
    }

    var stackState: ProtocolStackState { NWObjects.state(stack, ProtocolStackState.self)! }

    func copy() -> ParametersState {
        let copy = ParametersState(stack: stackState.copy())
        copy.requiredInterface = ObjCRuntime.retain(requiredInterface)
        copy.requiredInterfaceType = requiredInterfaceType
        copy.prohibitedInterfaces = prohibitedInterfaces.map { ObjCRuntime.retain($0)! }
        copy.prohibitedInterfaceTypes = prohibitedInterfaceTypes
        copy.prohibitExpensive = prohibitExpensive
        copy.prohibitConstrained = prohibitConstrained
        copy.allowUltraConstrained = allowUltraConstrained
        copy.reuseLocalAddress = reuseLocalAddress
        copy.localEndpoint = ObjCRuntime.retain(localEndpoint)
        copy.includePeerToPeer = includePeerToPeer
        copy.fastOpenEnabled = fastOpenEnabled
        copy.serviceClass = serviceClass
        copy.multipathService = multipathService
        copy.expiredDNSBehavior = expiredDNSBehavior
        copy.localOnly = localOnly
        copy.preferNoProxy = preferNoProxy
        copy.attribution = attribution
        copy.requiresDNSSECValidation = requiresDNSSECValidation
        copy.privacyContext = ObjCRuntime.retain(privacyContext)
        copy.customIPProtocol = customIPProtocol
        return copy
    }

    /// Whether an interface may carry the connection.
    func allows(_ interface: InterfaceInfo) -> Bool {
        if requiredInterfaceType != 0, interface.type != requiredInterfaceType { return false }
        if prohibitedInterfaceTypes.contains(interface.type) { return false }
        if let required = Interfaces.state(requiredInterface), required.nameText != interface.name { return false }
        if prohibitedInterfaces.contains(where: { Interfaces.state($0)?.nameText == interface.name }) { return false }
        return true
    }
}

@ObjCClass("OS_nw_parameters")
open class NWParametersObject: NWObject {}

enum Parameters {
    static func state(_ parameters: UnsafeMutableRawPointer?) -> ParametersState? { NWObjects.state(parameters, ParametersState.self) }

    static func make(_ state: ParametersState) -> UnsafeMutableRawPointer { NWObjects.make(NWParametersObject.objCClass, state) }

    /// Parameters with an IP layer and the transport given, if any (+1).
    static func make(transport: ProtocolKind?) -> UnsafeMutableRawPointer {
        let stack = ProtocolStackState(internet: Options.make(.ip))
        if let transport { stack.transport = Options.make(transport) }
        return make(ParametersState(stack: stack))
    }
}

/// Parameters with no transport yet; connections take TCP until one is set.
@c(_nw_parameters_create)
public func nw_parameters_create() -> UnsafeMutableRawPointer? { Parameters.make(transport: nil) }

@c(_nw_parameters_create_application_service)
public func nw_parameters_create_application_service() -> UnsafeMutableRawPointer? { Parameters.make(transport: .tcp) }

@c(_nw_parameters_create_custom_ip)
public func nw_parameters_create_custom_ip(_ protocolNumber: UInt8, _ configure: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    let parameters = Parameters.make(transport: nil)
    let state = Parameters.state(parameters)!
    state.customIPProtocol = protocolNumber
    if let block = ObjCBlock.from(configure), configure != ConfigurationBlocks.disableObject,
       configure != ConfigurationBlocks.defaultObject {
        block.call(state.stackState.internet)
    }
    return parameters
}

/// TLS (unless disabled) over TCP, each configured by its block or left
/// at its defaults.
@c(_nw_parameters_create_secure_tcp)
public func nw_parameters_create_secure_tcp(_ configureTLS: UnsafeMutableRawPointer?, _ configureTCP: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    secureParameters(transport: .tcp, configureTLS, configureTCP)
}

/// DTLS (unless disabled) over UDP.
@c(_nw_parameters_create_secure_udp)
public func nw_parameters_create_secure_udp(_ configureDTLS: UnsafeMutableRawPointer?, _ configureUDP: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    secureParameters(transport: .udp, configureDTLS, configureUDP)
}

private func secureParameters(transport: ProtocolKind, _ configureSecurity: UnsafeMutableRawPointer?,
                              _ configureTransport: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
    let parameters = Parameters.make(transport: transport)
    let stack = Parameters.state(parameters)!.stackState
    if configureTransport != ConfigurationBlocks.defaultObject, let block = ObjCBlock.from(configureTransport),
       configureTransport != ConfigurationBlocks.disableObject {
        block.call(stack.transport)
    }
    if configureSecurity != ConfigurationBlocks.disableObject {
        let tls = Options.make(.tls)
        if configureSecurity != ConfigurationBlocks.defaultObject, let block = ObjCBlock.from(configureSecurity) { block.call(tls) }
        stack.applicationProtocols.append(tls)
    }
    return parameters
}

/// NW_PARAMETERS_DISABLE_PROTOCOL and NW_PARAMETERS_DEFAULT_CONFIGURATION:
/// blocks that are told apart by their address.
@ObjCConstants
enum ConfigurationBlocks {
    nonisolated(unsafe) static let _nw_parameters_configure_protocol_disable = BlocksRuntime.block(invoke: unsafeBitCast(ignoreOptions, to: UnsafeRawPointer.self))
    nonisolated(unsafe) static let _nw_parameters_configure_protocol_default_configuration =
        BlocksRuntime.block(invoke: unsafeBitCast(ignoreOptions, to: UnsafeRawPointer.self))

    static var disableObject: UnsafeMutableRawPointer { _nw_parameters_configure_protocol_disable }
    static var defaultObject: UnsafeMutableRawPointer { _nw_parameters_configure_protocol_default_configuration }
}

private let ignoreOptions: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void = { _, _ in }

@c(_nw_parameters_copy)
public func nw_parameters_copy(_ parameters: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let state = Parameters.state(parameters) else { return nil }
    return Parameters.make(state.copy())
}

@c(_nw_parameters_copy_default_protocol_stack)
public func nw_parameters_copy_default_protocol_stack(_ parameters: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    ObjCRuntime.retain(Parameters.state(parameters)?.stack)
}

@c(_nw_parameters_require_interface)
public func nw_parameters_require_interface(_ parameters: UnsafeMutableRawPointer?, _ interface: UnsafeMutableRawPointer?) {
    guard let state = Parameters.state(parameters) else { return }
    let held = ObjCRuntime.retain(interface)
    ObjCRuntime.release(state.requiredInterface)
    state.requiredInterface = held
}

@c(_nw_parameters_copy_required_interface)
public func nw_parameters_copy_required_interface(_ parameters: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    ObjCRuntime.retain(Parameters.state(parameters)?.requiredInterface)
}

@c(_nw_parameters_set_required_interface_type)
public func nw_parameters_set_required_interface_type(_ parameters: UnsafeMutableRawPointer?, _ type: Int32) {
    Parameters.state(parameters)?.requiredInterfaceType = type
}

@c(_nw_parameters_get_required_interface_type)
public func nw_parameters_get_required_interface_type(_ parameters: UnsafeMutableRawPointer?) -> Int32 {
    Parameters.state(parameters)?.requiredInterfaceType ?? 0
}

@c(_nw_parameters_prohibit_interface)
public func nw_parameters_prohibit_interface(_ parameters: UnsafeMutableRawPointer?, _ interface: UnsafeMutableRawPointer?) {
    guard let state = Parameters.state(parameters), let interface else { return }
    state.prohibitedInterfaces.append(ObjCRuntime.retain(interface)!)
}

@c(_nw_parameters_clear_prohibited_interfaces)
public func nw_parameters_clear_prohibited_interfaces(_ parameters: UnsafeMutableRawPointer?) {
    guard let state = Parameters.state(parameters) else { return }
    state.prohibitedInterfaces.forEach { ObjCRuntime.release($0) }
    state.prohibitedInterfaces = []
}

@c(_nw_parameters_iterate_prohibited_interfaces)
public func nw_parameters_iterate_prohibited_interfaces(_ parameters: UnsafeMutableRawPointer?, _ block: UnsafeMutableRawPointer?) {
    guard let state = Parameters.state(parameters), let block = ObjCBlock.from(block) else { return }
    for interface in state.prohibitedInterfaces where !block.test(interface) { break }
}

@c(_nw_parameters_prohibit_interface_type)
public func nw_parameters_prohibit_interface_type(_ parameters: UnsafeMutableRawPointer?, _ type: Int32) {
    Parameters.state(parameters)?.prohibitedInterfaceTypes.append(type)
}

@c(_nw_parameters_clear_prohibited_interface_types)
public func nw_parameters_clear_prohibited_interface_types(_ parameters: UnsafeMutableRawPointer?) {
    Parameters.state(parameters)?.prohibitedInterfaceTypes = []
}

@c(_nw_parameters_iterate_prohibited_interface_types)
public func nw_parameters_iterate_prohibited_interface_types(_ parameters: UnsafeMutableRawPointer?, _ block: UnsafeMutableRawPointer?) {
    guard let state = Parameters.state(parameters), let block = ObjCBlock.from(block) else { return }
    typealias Invoke = @convention(c) (UnsafeMutableRawPointer, Int32) -> Bool
    for type in state.prohibitedInterfaceTypes where !block.function(as: Invoke.self)(block.object, type) { break }
}

@c(_nw_parameters_set_prohibit_expensive)
public func nw_parameters_set_prohibit_expensive(_ parameters: UnsafeMutableRawPointer?, _ value: Bool) {
    Parameters.state(parameters)?.prohibitExpensive = value
}

@c(_nw_parameters_get_prohibit_expensive)
public func nw_parameters_get_prohibit_expensive(_ parameters: UnsafeMutableRawPointer?) -> Bool { Parameters.state(parameters)?.prohibitExpensive ?? false }

@c(_nw_parameters_set_prohibit_constrained)
public func nw_parameters_set_prohibit_constrained(_ parameters: UnsafeMutableRawPointer?, _ value: Bool) {
    Parameters.state(parameters)?.prohibitConstrained = value
}

@c(_nw_parameters_get_prohibit_constrained)
public func nw_parameters_get_prohibit_constrained(_ parameters: UnsafeMutableRawPointer?) -> Bool {
    Parameters.state(parameters)?.prohibitConstrained ?? false
}

@c(_nw_parameters_set_allow_ultra_constrained)
public func nw_parameters_set_allow_ultra_constrained(_ parameters: UnsafeMutableRawPointer?, _ value: Bool) {
    Parameters.state(parameters)?.allowUltraConstrained = value
}

@c(_nw_parameters_get_allow_ultra_constrained)
public func nw_parameters_get_allow_ultra_constrained(_ parameters: UnsafeMutableRawPointer?) -> Bool {
    Parameters.state(parameters)?.allowUltraConstrained ?? false
}

@c(_nw_parameters_set_reuse_local_address)
public func nw_parameters_set_reuse_local_address(_ parameters: UnsafeMutableRawPointer?, _ value: Bool) {
    Parameters.state(parameters)?.reuseLocalAddress = value
}

@c(_nw_parameters_get_reuse_local_address)
public func nw_parameters_get_reuse_local_address(_ parameters: UnsafeMutableRawPointer?) -> Bool {
    Parameters.state(parameters)?.reuseLocalAddress ?? false
}

@c(_nw_parameters_set_local_endpoint)
public func nw_parameters_set_local_endpoint(_ parameters: UnsafeMutableRawPointer?, _ endpoint: UnsafeMutableRawPointer?) {
    guard let state = Parameters.state(parameters) else { return }
    let held = ObjCRuntime.retain(endpoint)
    ObjCRuntime.release(state.localEndpoint)
    state.localEndpoint = held
}

@c(_nw_parameters_copy_local_endpoint)
public func nw_parameters_copy_local_endpoint(_ parameters: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    ObjCRuntime.retain(Parameters.state(parameters)?.localEndpoint)
}

@c(_nw_parameters_set_include_peer_to_peer)
public func nw_parameters_set_include_peer_to_peer(_ parameters: UnsafeMutableRawPointer?, _ value: Bool) {
    Parameters.state(parameters)?.includePeerToPeer = value
}

@c(_nw_parameters_get_include_peer_to_peer)
public func nw_parameters_get_include_peer_to_peer(_ parameters: UnsafeMutableRawPointer?) -> Bool {
    Parameters.state(parameters)?.includePeerToPeer ?? false
}

@c(_nw_parameters_set_fast_open_enabled)
public func nw_parameters_set_fast_open_enabled(_ parameters: UnsafeMutableRawPointer?, _ value: Bool) {
    Parameters.state(parameters)?.fastOpenEnabled = value
}

@c(_nw_parameters_get_fast_open_enabled)
public func nw_parameters_get_fast_open_enabled(_ parameters: UnsafeMutableRawPointer?) -> Bool { Parameters.state(parameters)?.fastOpenEnabled ?? false }

@c(_nw_parameters_set_service_class)
public func nw_parameters_set_service_class(_ parameters: UnsafeMutableRawPointer?, _ value: Int32) {
    Parameters.state(parameters)?.serviceClass = value
}

@c(_nw_parameters_get_service_class)
public func nw_parameters_get_service_class(_ parameters: UnsafeMutableRawPointer?) -> Int32 { Parameters.state(parameters)?.serviceClass ?? 0 }

@c(_nw_parameters_set_multipath_service)
public func nw_parameters_set_multipath_service(_ parameters: UnsafeMutableRawPointer?, _ value: Int32) {
    Parameters.state(parameters)?.multipathService = value
}

@c(_nw_parameters_get_multipath_service)
public func nw_parameters_get_multipath_service(_ parameters: UnsafeMutableRawPointer?) -> Int32 { Parameters.state(parameters)?.multipathService ?? 0 }

@c(_nw_parameters_set_expired_dns_behavior)
public func nw_parameters_set_expired_dns_behavior(_ parameters: UnsafeMutableRawPointer?, _ value: Int32) {
    Parameters.state(parameters)?.expiredDNSBehavior = value
}

@c(_nw_parameters_get_expired_dns_behavior)
public func nw_parameters_get_expired_dns_behavior(_ parameters: UnsafeMutableRawPointer?) -> Int32 {
    Parameters.state(parameters)?.expiredDNSBehavior ?? 0
}

@c(_nw_parameters_set_local_only)
public func nw_parameters_set_local_only(_ parameters: UnsafeMutableRawPointer?, _ value: Bool) { Parameters.state(parameters)?.localOnly = value }

@c(_nw_parameters_get_local_only)
public func nw_parameters_get_local_only(_ parameters: UnsafeMutableRawPointer?) -> Bool { Parameters.state(parameters)?.localOnly ?? false }

@c(_nw_parameters_set_prefer_no_proxy)
public func nw_parameters_set_prefer_no_proxy(_ parameters: UnsafeMutableRawPointer?, _ value: Bool) {
    Parameters.state(parameters)?.preferNoProxy = value
}

@c(_nw_parameters_get_prefer_no_proxy)
public func nw_parameters_get_prefer_no_proxy(_ parameters: UnsafeMutableRawPointer?) -> Bool { Parameters.state(parameters)?.preferNoProxy ?? false }

@c(_nw_parameters_set_attribution)
public func nw_parameters_set_attribution(_ parameters: UnsafeMutableRawPointer?, _ value: Int32) {
    Parameters.state(parameters)?.attribution = value
}

@c(_nw_parameters_get_attribution)
public func nw_parameters_get_attribution(_ parameters: UnsafeMutableRawPointer?) -> Int32 { Parameters.state(parameters)?.attribution ?? 1 }

@c(_nw_parameters_set_requires_dnssec_validation)
public func nw_parameters_set_requires_dnssec_validation(_ parameters: UnsafeMutableRawPointer?, _ value: Bool) {
    Parameters.state(parameters)?.requiresDNSSECValidation = value
}

@c(_nw_parameters_requires_dnssec_validation)
public func nw_parameters_requires_dnssec_validation(_ parameters: UnsafeMutableRawPointer?) -> Bool {
    Parameters.state(parameters)?.requiresDNSSECValidation ?? false
}

@c(_nw_parameters_set_privacy_context)
public func nw_parameters_set_privacy_context(_ parameters: UnsafeMutableRawPointer?, _ context: UnsafeMutableRawPointer?) {
    guard let state = Parameters.state(parameters) else { return }
    let held = ObjCRuntime.retain(context)
    ObjCRuntime.release(state.privacyContext)
    state.privacyContext = held
}

// MARK: - Protocol stack

private func stack(_ stack: UnsafeMutableRawPointer?) -> ProtocolStackState? { NWObjects.state(stack, ProtocolStackState.self) }

@c(_nw_protocol_stack_prepend_application_protocol)
public func nw_protocol_stack_prepend_application_protocol(_ protocolStack: UnsafeMutableRawPointer?, _ options: UnsafeMutableRawPointer?) {
    guard let state = stack(protocolStack), let options else { return }
    state.applicationProtocols.insert(ObjCRuntime.retain(options)!, at: 0)
}

@c(_nw_protocol_stack_clear_application_protocols)
public func nw_protocol_stack_clear_application_protocols(_ protocolStack: UnsafeMutableRawPointer?) {
    guard let state = stack(protocolStack) else { return }
    state.applicationProtocols.forEach { ObjCRuntime.release($0) }
    state.applicationProtocols = []
}

/// The application protocols, top first.
@c(_nw_protocol_stack_iterate_application_protocols)
public func nw_protocol_stack_iterate_application_protocols(_ protocolStack: UnsafeMutableRawPointer?, _ block: UnsafeMutableRawPointer?) {
    guard let state = stack(protocolStack), let block = ObjCBlock.from(block) else { return }
    for options in state.applicationProtocols { block.call(options) }
}

@c(_nw_protocol_stack_copy_transport_protocol)
public func nw_protocol_stack_copy_transport_protocol(_ protocolStack: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    ObjCRuntime.retain(stack(protocolStack)?.transport)
}

@c(_nw_protocol_stack_set_transport_protocol)
public func nw_protocol_stack_set_transport_protocol(_ protocolStack: UnsafeMutableRawPointer?, _ options: UnsafeMutableRawPointer?) {
    guard let state = stack(protocolStack) else { return }
    let held = ObjCRuntime.retain(options)
    ObjCRuntime.release(state.transport)
    state.transport = held
}

@c(_nw_protocol_stack_copy_internet_protocol)
public func nw_protocol_stack_copy_internet_protocol(_ protocolStack: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    ObjCRuntime.retain(stack(protocolStack)?.internet)
}

// MARK: - Privacy contexts

final class PrivacyContextState: NWState {
    let description: String
    var loggingDisabled = false
    var requireEncryptedNameResolution = false
    var fallbackResolver: UnsafeMutableRawPointer?
    var proxies: [UnsafeMutableRawPointer] = []

    init(description: String) { self.description = description }

    deinit {
        ObjCRuntime.release(fallbackResolver)
        proxies.forEach { ObjCRuntime.release($0) }
    }
}

@ObjCClass("OS_nw_privacy_context")
open class NWPrivacyContextObject: NWObject {}

@ObjCConstants
enum PrivacyContexts {
    nonisolated(unsafe) static let _nw_privacy_context_default_context = NWObjects.make(NWPrivacyContextObject.objCClass, PrivacyContextState(description: "default"))
}

private func privacy(_ context: UnsafeMutableRawPointer?) -> PrivacyContextState? { NWObjects.state(context, PrivacyContextState.self) }

@c(_nw_privacy_context_create)
public func nw_privacy_context_create(_ description: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    NWObjects.make(NWPrivacyContextObject.objCClass, PrivacyContextState(description: description.map { String(cString: $0) } ?? ""))
}

/// There is no resolver cache of Network's own to flush.
@c(_nw_privacy_context_flush_cache)
public func nw_privacy_context_flush_cache(_ context: UnsafeMutableRawPointer?) {}

@c(_nw_privacy_context_disable_logging)
public func nw_privacy_context_disable_logging(_ context: UnsafeMutableRawPointer?) { privacy(context)?.loggingDisabled = true }

@c(_nw_privacy_context_require_encrypted_name_resolution)
public func nw_privacy_context_require_encrypted_name_resolution(_ context: UnsafeMutableRawPointer?, _ require: Bool,
                                                                 _ fallback: UnsafeMutableRawPointer?) {
    guard let state = privacy(context) else { return }
    state.requireEncryptedNameResolution = require
    let held = ObjCRuntime.retain(fallback)
    ObjCRuntime.release(state.fallbackResolver)
    state.fallbackResolver = held
}

@c(_nw_privacy_context_add_proxy)
public func nw_privacy_context_add_proxy(_ context: UnsafeMutableRawPointer?, _ proxy: UnsafeMutableRawPointer?) {
    guard let state = privacy(context), let proxy else { return }
    state.proxies.append(ObjCRuntime.retain(proxy)!)
}

@c(_nw_privacy_context_clear_proxies)
public func nw_privacy_context_clear_proxies(_ context: UnsafeMutableRawPointer?) {
    guard let state = privacy(context) else { return }
    state.proxies.forEach { ObjCRuntime.release($0) }
    state.proxies = []
}

// MARK: - Proxy configurations and relay hops

final class ProxyConfigState: NWState {
    enum Kind { case httpConnect, socksV5, relay, obliviousHTTP }
    let kind: Kind
    var endpoints: [UnsafeMutableRawPointer] = []
    var username: String?
    var password: String?
    var failoverAllowed = false
    var matchDomains: [String] = []
    var excludedDomains: [String] = []

    init(kind: Kind) { self.kind = kind }

    deinit { endpoints.forEach { ObjCRuntime.release($0) } }
}

@ObjCClass("OS_nw_proxy_config")
open class NWProxyConfigObject: NWObject {}

final class RelayHopState: NWState {
    let http3Endpoint: UnsafeMutableRawPointer?
    let http2Endpoint: UnsafeMutableRawPointer?
    let tlsOptions: UnsafeMutableRawPointer?
    var headers: [(String, String)] = []

    init(http3: UnsafeMutableRawPointer?, http2: UnsafeMutableRawPointer?, tls: UnsafeMutableRawPointer?) {
        http3Endpoint = ObjCRuntime.retain(http3)
        http2Endpoint = ObjCRuntime.retain(http2)
        tlsOptions = ObjCRuntime.retain(tls)
    }

    deinit {
        ObjCRuntime.release(http3Endpoint)
        ObjCRuntime.release(http2Endpoint)
        ObjCRuntime.release(tlsOptions)
    }
}

@ObjCClass("OS_nw_relay_hop")
open class NWRelayHopObject: NWObject {}

private func proxy(_ config: UnsafeMutableRawPointer?) -> ProxyConfigState? { NWObjects.state(config, ProxyConfigState.self) }

private func makeProxy(_ kind: ProxyConfigState.Kind, _ endpoints: [UnsafeMutableRawPointer?]) -> UnsafeMutableRawPointer {
    let state = ProxyConfigState(kind: kind)
    state.endpoints = endpoints.compactMap { ObjCRuntime.retain($0) }
    return NWObjects.make(NWProxyConfigObject.objCClass, state)
}

@c(_nw_relay_hop_create)
public func nw_relay_hop_create(_ http3: UnsafeMutableRawPointer?, _ http2: UnsafeMutableRawPointer?,
                                _ tls: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    NWObjects.make(NWRelayHopObject.objCClass, RelayHopState(http3: http3, http2: http2, tls: tls))
}

@c(_nw_relay_hop_add_additional_http_header_field)
public func nw_relay_hop_add_additional_http_header_field(_ hop: UnsafeMutableRawPointer?, _ name: UnsafePointer<CChar>?,
                                                          _ value: UnsafePointer<CChar>?) {
    guard let state = NWObjects.state(hop, RelayHopState.self), let name, let value else { return }
    state.headers.append((String(cString: name), String(cString: value)))
}

@c(_nw_proxy_config_create_relay)
public func nw_proxy_config_create_relay(_ first: UnsafeMutableRawPointer?, _ second: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    makeProxy(.relay, [first, second])
}

@c(_nw_proxy_config_create_oblivious_http)
public func nw_proxy_config_create_oblivious_http(_ relay: UnsafeMutableRawPointer?, _ path: UnsafePointer<CChar>?,
                                                  _ key: UnsafePointer<UInt8>?, _ keyLength: Int) -> UnsafeMutableRawPointer? {
    makeProxy(.obliviousHTTP, [relay])
}

@c(_nw_proxy_config_create_http_connect)
public func nw_proxy_config_create_http_connect(_ endpoint: UnsafeMutableRawPointer?, _ tls: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    makeProxy(.httpConnect, [endpoint, tls])
}

@c(_nw_proxy_config_create_socksv5)
public func nw_proxy_config_create_socksv5(_ endpoint: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    makeProxy(.socksV5, [endpoint])
}

@c(_nw_proxy_config_set_username_and_password)
public func nw_proxy_config_set_username_and_password(_ config: UnsafeMutableRawPointer?, _ username: UnsafePointer<CChar>?,
                                                      _ password: UnsafePointer<CChar>?) {
    guard let state = proxy(config) else { return }
    state.username = username.map { String(cString: $0) }
    state.password = password.map { String(cString: $0) }
}

@c(_nw_proxy_config_set_failover_allowed)
public func nw_proxy_config_set_failover_allowed(_ config: UnsafeMutableRawPointer?, _ allowed: Bool) { proxy(config)?.failoverAllowed = allowed }

@c(_nw_proxy_config_get_failover_allowed)
public func nw_proxy_config_get_failover_allowed(_ config: UnsafeMutableRawPointer?) -> Bool { proxy(config)?.failoverAllowed ?? false }

@c(_nw_proxy_config_add_match_domain)
public func nw_proxy_config_add_match_domain(_ config: UnsafeMutableRawPointer?, _ domain: UnsafePointer<CChar>?) {
    guard let domain else { return }
    proxy(config)?.matchDomains.append(String(cString: domain))
}

@c(_nw_proxy_config_clear_match_domains)
public func nw_proxy_config_clear_match_domains(_ config: UnsafeMutableRawPointer?) { proxy(config)?.matchDomains = [] }

@c(_nw_proxy_config_add_excluded_domain)
public func nw_proxy_config_add_excluded_domain(_ config: UnsafeMutableRawPointer?, _ domain: UnsafePointer<CChar>?) {
    guard let domain else { return }
    proxy(config)?.excludedDomains.append(String(cString: domain))
}

@c(_nw_proxy_config_clear_excluded_domains)
public func nw_proxy_config_clear_excluded_domains(_ config: UnsafeMutableRawPointer?) { proxy(config)?.excludedDomains = [] }

private func enumerate(_ domains: [String], _ block: UnsafeMutableRawPointer?) {
    guard let block = ObjCBlock.from(block) else { return }
    typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafePointer<CChar>?) -> Void
    for domain in domains { domain.withCString { block.function(as: Invoke.self)(block.object, $0) } }
}

@c(_nw_proxy_config_enumerate_match_domains)
public func nw_proxy_config_enumerate_match_domains(_ config: UnsafeMutableRawPointer?, _ block: UnsafeMutableRawPointer?) {
    enumerate(proxy(config)?.matchDomains ?? [], block)
}

@c(_nw_proxy_config_enumerate_excluded_domains)
public func nw_proxy_config_enumerate_excluded_domains(_ config: UnsafeMutableRawPointer?, _ block: UnsafeMutableRawPointer?) {
    enumerate(proxy(config)?.excludedDomains ?? [], block)
}

// MARK: - Resolver configurations

final class ResolverConfigState: NWState {
    let endpoint: UnsafeMutableRawPointer?
    var servers: [UnsafeMutableRawPointer] = []

    init(endpoint: UnsafeMutableRawPointer?) { self.endpoint = ObjCRuntime.retain(endpoint) }

    deinit {
        ObjCRuntime.release(endpoint)
        servers.forEach { ObjCRuntime.release($0) }
    }
}

@ObjCClass("OS_nw_resolver_config")
open class NWResolverConfigObject: NWObject {}

@c(_nw_resolver_config_create_https)
public func nw_resolver_config_create_https(_ url: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    NWObjects.make(NWResolverConfigObject.objCClass, ResolverConfigState(endpoint: url))
}

@c(_nw_resolver_config_create_tls)
public func nw_resolver_config_create_tls(_ server: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    NWObjects.make(NWResolverConfigObject.objCClass, ResolverConfigState(endpoint: server))
}

@c(_nw_resolver_config_add_server_address)
public func nw_resolver_config_add_server_address(_ config: UnsafeMutableRawPointer?, _ address: UnsafeMutableRawPointer?) {
    guard let state = NWObjects.state(config, ResolverConfigState.self), let address else { return }
    state.servers.append(ObjCRuntime.retain(address)!)
}

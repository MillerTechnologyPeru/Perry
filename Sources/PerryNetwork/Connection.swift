import Glibc
import PerryObjCInterop

// nw_connection_t: a protocol stack (Stack.swift) to one endpoint, run on
// a serial queue of its own; its handlers and completions go to the queue
// the program set. As on Darwin, a started connection keeps itself until it
// is cancelled; one that can't connect waits (with the error) until it is
// restarted or cancelled, and one whose protocols fail after that fails.

/// nw_connection_state_t.
enum ConnectionStatus {
    static let invalid: Int32 = 0
    static let waiting: Int32 = 1
    static let preparing: Int32 = 2
    static let ready: Int32 = 3
    static let failed: Int32 = 4
    static let cancelled: Int32 = 5
}

private struct PendingReceive {
    let minimum: Int
    let maximum: Int
    let wholeMessage: Bool
    let completion: ObjCBlock
}

private struct PendingSend {
    let data: [UInt8]
    /// The context (+1).
    let context: UnsafeMutableRawPointer
    let isComplete: Bool
    let completion: ObjCBlock?
}

/// A received message waiting for a receive, with its context (+1).
private struct ReceivedMessage {
    var data: [UInt8]
    let context: UnsafeMutableRawPointer
    let isComplete: Bool
}

final class ConnectionState: NWState {
    private static let counterLock = Lock()
    nonisolated(unsafe) private static var counter = 0

    let identifier: Int
    /// The object this is the state of; valid while it lives, which a
    /// started connection makes sure of until it is cancelled.
    var object: UnsafeMutableRawPointer?
    let endpoint: UnsafeMutableRawPointer
    let parametersObject: UnsafeMutableRawPointer
    let parameters: ParametersState
    /// The stack's queue (+1).
    let queue: UnsafeMutableRawPointer
    let isInbound: Bool

    private let lock = Lock()
    private var userQueue: UnsafeMutableRawPointer?
    private var stateHandler: ObjCBlock?
    private var viabilityHandler: ObjCBlock?
    private var betterPathHandler: ObjCBlock?
    private var pathHandler: ObjCBlock?
    private var status = ConnectionStatus.invalid
    private var started = false
    private var holdsItself = false
    private var layers: [Layer] = []
    private var inboundTransport: SocketTransport?

    private var streamBuffer: [UInt8] = []
    private var streamEnded = false
    private var messages: [ReceivedMessage] = []
    private var receives: [PendingReceive] = []
    private var sends: [PendingSend] = []
    private var failure: NetworkError?

    // For reports.
    var startTime: UInt64 = 0
    var readyTime: UInt64 = 0
    var resolutionMilliseconds: UInt64 = 0
    var resolvedCount = 0
    var resolvedFromQuery = false
    var applicationBytesSent: UInt64 = 0
    var applicationBytesReceived: UInt64 = 0
    var handshakeTimes: [(ProtocolKind, UInt64)] = []

    init(endpoint: UnsafeMutableRawPointer, parameters: UnsafeMutableRawPointer, inbound transport: SocketTransport? = nil) {
        identifier = ConnectionState.counterLock.withLock { () -> Int in
            ConnectionState.counter += 1
            return ConnectionState.counter
        }
        self.endpoint = ObjCRuntime.retain(endpoint)!
        // The connection keeps a copy, so later changes to the program's
        // parameters don't reach it.
        let copy = nw_parameters_copy(parameters) ?? ObjCRuntime.retain(parameters)!
        parametersObject = copy
        self.parameters = Parameters.state(copy)!
        queue = Dispatch.serialQueue("com.apple.network.connection")
        isInbound = transport != nil
        inboundTransport = transport
        super.init()
        if transport != nil { _ = buildStack() }
    }

    deinit {
        ObjCRuntime.release(endpoint)
        ObjCRuntime.release(parametersObject)
        ObjCRuntime.release(userQueue)
        ObjCRuntime.release(queue)
        messages.forEach { ObjCRuntime.release($0.context) }
        sends.forEach { ObjCRuntime.release($0.context) }
    }

    override func objectDeallocated() {
        object = nil
        let stack = lock.withLock { layers }
        if !stack.isEmpty { Dispatch.on(queue) { stack.reversed().forEach { $0.stop() } } }
    }

    var endpointState: EndpointState? { Endpoints.state(endpoint) }
    var transport: SocketTransport? { lock.withLock { layers.first as? SocketTransport } }
    var currentLayers: [Layer] { lock.withLock { layers } }
    var currentStatus: Int32 { lock.withLock { status } }

    // MARK: Program-facing

    func setQueue(_ queue: UnsafeMutableRawPointer?) {
        let held = ObjCRuntime.retain(queue)
        let old = lock.withLock { () -> UnsafeMutableRawPointer? in
            let old = userQueue
            userQueue = held
            return old
        }
        ObjCRuntime.release(old)
    }

    func setStateHandler(_ block: ObjCBlock?) { lock.withLock { stateHandler = block } }
    func setViabilityHandler(_ block: ObjCBlock?) { lock.withLock { viabilityHandler = block } }
    func setBetterPathHandler(_ block: ObjCBlock?) { lock.withLock { betterPathHandler = block } }
    func setPathHandler(_ block: ObjCBlock?) { lock.withLock { pathHandler = block } }

    /// Runs `body` on the program's queue.
    func onUserQueue(_ body: @escaping () -> Void) {
        let queue = lock.withLock { userQueue }
        Dispatch.on(queue, body)
    }

    func start() {
        let first = lock.withLock { () -> Bool in
            guard !started, status != ConnectionStatus.cancelled else { return false }
            started = true
            return true
        }
        guard first, let object else { return }
        // Started, the connection keeps itself until it is cancelled.
        _ = ObjCRuntime.retain(object)
        lock.withLock { holdsItself = true }
        Dispatch.on(queue) { self.begin() }
    }

    private func begin() {
        startTime = monotonicMilliseconds()
        setStatus(ConnectionStatus.preparing, nil)
        if !isInbound {
            guard buildStack() else { return }
        }
        guard let bottom = lock.withLock({ layers.first }) else { return }
        bottom.start()
    }

    /// Builds the stack from the parameters: false (and failed) when it has
    /// a protocol this can't carry.
    private func buildStack() -> Bool {
        let stack = parameters.stackState
        var built: [Layer] = []
        if let transport = inboundTransport {
            built.append(transport)
        } else {
            switch stack.transportKind {
            case .tcp: built.append(SocketTransport(isStream: true))
            case .udp: built.append(SocketTransport(isStream: false))
            default:
                unsupported("QUIC")
                return false
            }
        }
        let host: String? = {
            guard let endpoint = endpointState else { return nil }
            if endpoint.type == EndpointType.host || endpoint.type == EndpointType.url { return endpoint.hostname.value.map { String(cString: $0) } }
            return nil
        }()
        for options in stack.applicationBottomUp {
            switch options.kind {
            case .tls:
                guard built.last?.deliversMessages == false else {
                    unsupported("DTLS")
                    return false
                }
                built.append(TLSLayer(options: options, serverName: host, isServer: isInbound))
            case .webSocket:
                built.append(WebSocketLayer(options: options, isServer: isInbound))
            case .framer:
                built.append(FramerLayer(options: options, isServer: isInbound))
            case .quic:
                unsupported("QUIC")
                return false
            default:
                break
            }
        }
        for (index, layer) in built.enumerated() {
            layer.connection = self
            layer.lower = index > 0 ? built[index - 1] : nil
            layer.upper = index + 1 < built.count ? built[index + 1] : nil
        }
        lock.withLock { layers = built }
        return true
    }

    private func unsupported(_ name: String) {
        networkWarning("\(name) connections aren't supported")
        fail(.protocolNotSupported)
    }

    func restart() {
        Dispatch.on(queue) {
            guard self.currentStatus == ConnectionStatus.waiting else { return }
            let old = self.lock.withLock { () -> [Layer] in
                let old = self.layers
                self.layers = []
                return old
            }
            old.reversed().forEach { $0.stop() }
            self.failure = nil
            self.begin()
        }
    }

    func cancel() {
        Dispatch.on(queue) { self.finishCancel() }
    }

    private func finishCancel() {
        let already = lock.withLock { () -> Bool in
            if status == ConnectionStatus.cancelled { return true }
            return false
        }
        guard !already else { return }
        currentLayers.reversed().forEach { $0.stop() }
        failure = failure ?? .cancelled
        failPending(.cancelled)
        setStatus(ConnectionStatus.cancelled, nil)
        // The connection lets go of itself once its handler has run.
        let release = lock.withLock { () -> Bool in
            let held = holdsItself
            holdsItself = false
            return held
        }
        if release, let object {
            onUserQueue { ObjCRuntime.release(object) }
        }
    }

    func send(_ data: [UInt8], context: UnsafeMutableRawPointer?, isComplete: Bool, completion: ObjCBlock?) {
        let pending = PendingSend(data: data, context: ObjCRuntime.retain(context ?? Contexts.defaultMessage)!, isComplete: isComplete,
                                  completion: completion)
        Dispatch.on(queue) {
            switch self.currentStatus {
            case ConnectionStatus.ready:
                self.perform(pending)
            case ConnectionStatus.failed, ConnectionStatus.cancelled:
                self.complete(pending.completion, self.failure ?? .cancelled)
                ObjCRuntime.release(pending.context)
            default:
                self.sends.append(pending)
            }
        }
    }

    private func perform(_ pending: PendingSend) {
        applicationBytesSent += UInt64(pending.data.count)
        let completion = pending.completion
        let top = lock.withLock { layers.last }
        top?.send(pending.data, context: pending.context, isComplete: pending.isComplete) { [weak self] error in
            self?.complete(completion, error)
        }
        if pending.isComplete, Contexts.state(pending.context)?.isFinal == true { top?.finish() }
        ObjCRuntime.release(pending.context)
    }

    private func complete(_ completion: ObjCBlock?, _ error: NetworkError?) {
        guard let completion else { return }
        onUserQueue {
            let object = error?.object()
            completion.call(object)
            ObjCRuntime.release(object)
        }
    }

    func receive(minimum: Int, maximum: Int, wholeMessage: Bool, completion: ObjCBlock) {
        Dispatch.on(queue) {
            self.receives.append(PendingReceive(minimum: minimum, maximum: max(maximum, 1), wholeMessage: wholeMessage, completion: completion))
            self.serviceReceives()
        }
    }

    // MARK: Stack events

    /// The stack couldn't reach the endpoint: the connection waits, as
    /// Darwin's does, until it is restarted.
    func couldNotConnect(_ error: NetworkError) {
        guard currentStatus != ConnectionStatus.cancelled, currentStatus != ConnectionStatus.failed else { return }
        failure = error
        setStatus(ConnectionStatus.waiting, error)
    }

    func stackReady() {
        guard currentStatus == ConnectionStatus.preparing || currentStatus == ConnectionStatus.waiting else { return }
        readyTime = monotonicMilliseconds()
        failure = nil
        setStatus(ConnectionStatus.ready, nil)
        let (viability, pathChanged) = lock.withLock { (viabilityHandler, pathHandler) }
        if let viability { onUserQueue { viability.call(true) } }
        if let pathChanged {
            let path = copyCurrentPath()
            onUserQueue {
                pathChanged.call(path)
                ObjCRuntime.release(path)
            }
        }
        let queued = sends
        sends = []
        for pending in queued { perform(pending) }
        serviceReceives()
    }

    func stackFailed(_ error: NetworkError) {
        let status = currentStatus
        guard status != ConnectionStatus.cancelled, status != ConnectionStatus.failed else { return }
        // Before it is ready, as on Darwin, a connection whose protocols
        // fail (a refused TLS handshake among them) waits.
        if status == ConnectionStatus.preparing || status == ConnectionStatus.waiting {
            currentLayers.reversed().forEach { $0.stop() }
            couldNotConnect(error)
            return
        }
        fail(error)
    }

    private func fail(_ error: NetworkError) {
        failure = error
        currentLayers.reversed().forEach { $0.stop() }
        setStatus(ConnectionStatus.failed, error)
        failPending(error)
    }

    private func failPending(_ error: NetworkError) {
        let pendingSends = sends
        sends = []
        for pending in pendingSends {
            complete(pending.completion, error)
            ObjCRuntime.release(pending.context)
        }
        serviceReceives()
    }

    func received(_ data: [UInt8], context: UnsafeMutableRawPointer?, isComplete: Bool) {
        applicationBytesReceived += UInt64(data.count)
        let top = lock.withLock { layers.last }
        if top?.deliversMessages == true, let context {
            messages.append(ReceivedMessage(data: data, context: ObjCRuntime.retain(context)!, isComplete: isComplete))
        } else {
            streamBuffer += data
            if isComplete { streamEnded = true }
        }
        serviceReceives()
    }

    private func serviceReceives() {
        while let request = receives.first {
            if let message = messages.first {
                if request.wholeMessage {
                    // A whole message: its pieces up to the complete one.
                    guard let end = messages.firstIndex(where: { $0.isComplete }) else {
                        if failure == nil { return }
                        deliver(request, Array(messages.flatMap(\.data)), context: messages[0].context, isComplete: false, error: nil)
                        messages.forEach { ObjCRuntime.release($0.context) }
                        messages = []
                        receives.removeFirst()
                        continue
                    }
                    let parts = messages[0...end]
                    deliver(request, Array(parts.flatMap(\.data)), context: messages[end].context, isComplete: true, error: nil)
                    parts.forEach { ObjCRuntime.release($0.context) }
                    messages.removeFirst(end + 1)
                } else if message.data.count > request.maximum {
                    deliver(request, Array(message.data.prefix(request.maximum)), context: message.context, isComplete: false, error: nil)
                    messages[0].data.removeFirst(request.maximum)
                } else {
                    deliver(request, message.data, context: message.context, isComplete: message.isComplete, error: nil)
                    ObjCRuntime.release(message.context)
                    messages.removeFirst()
                }
                receives.removeFirst()
                continue
            }
            if request.wholeMessage {
                guard streamEnded || failure != nil else { return }
                if streamEnded {
                    let data = streamBuffer
                    streamBuffer = []
                    deliver(request, data, context: Contexts.finalSend, isComplete: true, error: nil)
                } else {
                    deliver(request, [], context: nil, isComplete: false, error: failure)
                }
                receives.removeFirst()
                continue
            }
            let needed = max(request.minimum, 1)
            if streamBuffer.count >= needed || (streamEnded && !streamBuffer.isEmpty) {
                let count = min(streamBuffer.count, request.maximum)
                let data = Array(streamBuffer.prefix(count))
                streamBuffer.removeFirst(count)
                let last = streamEnded && streamBuffer.isEmpty
                deliver(request, data, context: last ? Contexts.finalSend : Contexts.defaultMessage, isComplete: last, error: nil)
            } else if streamEnded {
                deliver(request, [], context: Contexts.finalSend, isComplete: true, error: nil)
            } else if let failure {
                deliver(request, [], context: nil, isComplete: false, error: failure)
            } else {
                return
            }
            receives.removeFirst()
        }
    }

    private func deliver(_ request: PendingReceive, _ data: [UInt8], context: UnsafeMutableRawPointer?, isComplete: Bool, error: NetworkError?) {
        let content = data.isEmpty ? nil : Dispatch.data(data)
        let heldContext = ObjCRuntime.retain(context)
        let completion = request.completion
        onUserQueue {
            let errorObject = error?.object()
            typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Bool,
                                               UnsafeMutableRawPointer?) -> Void
            completion.function(as: Invoke.self)(completion.object, content, heldContext, isComplete, errorObject)
            ObjCRuntime.release(errorObject)
            ObjCRuntime.release(heldContext)
            ObjCRuntime.release(content)
        }
    }

    private func setStatus(_ new: Int32, _ error: NetworkError?) {
        let handler = lock.withLock { () -> ObjCBlock? in
            status = new
            return stateHandler
        }
        guard let handler else { return }
        onUserQueue {
            let object = error?.object()
            handler.call(state: new, object)
            ObjCRuntime.release(object)
        }
    }

    // MARK: Lookups

    /// The endpoint's addresses, for the transport.
    func resolveRemote(_ completion: @escaping ([SocketAddress], NetworkError?) -> Void) {
        guard let endpoint = endpointState else {
            completion([], .posix(darwin: 22))
            return
        }
        if let address = endpoint.address {
            resolvedCount = 1
            completion([address], nil)
            return
        }
        guard endpoint.type == EndpointType.host || endpoint.type == EndpointType.url, let host = endpoint.hostname.value else {
            completion([], .noSuchRecord)
            return
        }
        let stack = parameters.stackState
        let type = stack.transportKind == .udp ? Int32(SOCK_DGRAM.rawValue) : Int32(SOCK_STREAM.rawValue)
        let family: Int32
        switch stack.ipOptions?.ipVersion ?? 0 {
        case 4: family = AF_INET
        case 6: family = AF_INET6
        default: family = AF_UNSPEC
        }
        Resolver.resolve(String(cString: host), port: endpoint.port, type: type, family: family, queue: queue) { [weak self] result in
            self?.resolutionMilliseconds = result.milliseconds
            self?.resolvedCount = result.addresses.count
            self?.resolvedFromQuery = true
            completion(result.addresses, result.error)
        }
    }

    /// The connection's path (+1).
    func copyCurrentPath() -> UnsafeMutableRawPointer {
        let transport = self.transport
        let ready = currentStatus == ConnectionStatus.ready
        var interfaces: [InterfaceInfo] = []
        if let interface = Interfaces.with(address: transport?.localAddress) { interfaces = [interface] }
        let info = PathInfo(status: ready ? PathStatus.satisfied : PathStatus.unsatisfied, interfaces: interfaces,
                            local: transport?.localAddress, remote: transport?.remoteAddress)
        return info.object()
    }

    var descriptionText: String {
        let kinds = currentLayers.reversed().map { $0.kind.identifier }.joined(separator: ", ")
        let names = ["invalid", "waiting", "preparing", "ready", "failed", "cancelled"]
        let state = Int(currentStatus)
        return "[C\(identifier) \(endpointState?.description ?? "?") \(kinds.isEmpty ? parameters.stackState.transportKind.identifier : kinds), \(state < names.count ? names[state] : "?")]"
    }
}

@ObjCClass("OS_nw_connection")
open class NWConnectionObject: NWObject {}

enum Connections {
    static func state(_ connection: UnsafeMutableRawPointer?) -> ConnectionState? { NWObjects.state(connection, ConnectionState.self) }

    /// A new connection object (+1) for `state`.
    static func make(_ state: ConnectionState) -> UnsafeMutableRawPointer {
        let object = NWObjects.make(NWConnectionObject.objCClass, state)
        state.object = object
        return object
    }
}

@c(_nw_connection_create)
public func nw_connection_create(_ endpoint: UnsafeMutableRawPointer?, _ parameters: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let endpoint, let parameters, Parameters.state(parameters) != nil else { return nil }
    return Connections.make(ConnectionState(endpoint: endpoint, parameters: parameters))
}

@c(_nw_connection_copy_endpoint)
public func nw_connection_copy_endpoint(_ connection: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    ObjCRuntime.retain(Connections.state(connection)?.endpoint)
}

@c(_nw_connection_copy_parameters)
public func nw_connection_copy_parameters(_ connection: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    ObjCRuntime.retain(Connections.state(connection)?.parametersObject)
}

@c(_nw_connection_set_queue)
public func nw_connection_set_queue(_ connection: UnsafeMutableRawPointer?, _ queue: UnsafeMutableRawPointer?) {
    Connections.state(connection)?.setQueue(queue)
}

@c(_nw_connection_set_state_changed_handler)
public func nw_connection_set_state_changed_handler(_ connection: UnsafeMutableRawPointer?, _ handler: UnsafeMutableRawPointer?) {
    Connections.state(connection)?.setStateHandler(ObjCBlock.from(handler))
}

@c(_nw_connection_set_viability_changed_handler)
public func nw_connection_set_viability_changed_handler(_ connection: UnsafeMutableRawPointer?, _ handler: UnsafeMutableRawPointer?) {
    Connections.state(connection)?.setViabilityHandler(ObjCBlock.from(handler))
}

/// Connections have one path here: no better one turns up.
@c(_nw_connection_set_better_path_available_handler)
public func nw_connection_set_better_path_available_handler(_ connection: UnsafeMutableRawPointer?, _ handler: UnsafeMutableRawPointer?) {
    Connections.state(connection)?.setBetterPathHandler(ObjCBlock.from(handler))
}

@c(_nw_connection_set_path_changed_handler)
public func nw_connection_set_path_changed_handler(_ connection: UnsafeMutableRawPointer?, _ handler: UnsafeMutableRawPointer?) {
    Connections.state(connection)?.setPathHandler(ObjCBlock.from(handler))
}

@c(_nw_connection_start)
public func nw_connection_start(_ connection: UnsafeMutableRawPointer?) { Connections.state(connection)?.start() }

@c(_nw_connection_restart)
public func nw_connection_restart(_ connection: UnsafeMutableRawPointer?) { Connections.state(connection)?.restart() }

@c(_nw_connection_cancel)
public func nw_connection_cancel(_ connection: UnsafeMutableRawPointer?) { Connections.state(connection)?.cancel() }

@c(_nw_connection_force_cancel)
public func nw_connection_force_cancel(_ connection: UnsafeMutableRawPointer?) { Connections.state(connection)?.cancel() }

/// There is one attempt at a time; it goes on.
@c(_nw_connection_cancel_current_endpoint)
public func nw_connection_cancel_current_endpoint(_ connection: UnsafeMutableRawPointer?) {}

/// The block runs now: sends and receives it makes are queued in order anyway.
@c(_nw_connection_batch)
public func nw_connection_batch(_ connection: UnsafeMutableRawPointer?, _ block: UnsafeMutableRawPointer?) {
    ObjCBlock.from(block)?.call()
}

@c(_nw_connection_send)
public func nw_connection_send(_ connection: UnsafeMutableRawPointer?, _ content: UnsafeMutableRawPointer?, _ context: UnsafeMutableRawPointer?,
                               _ isComplete: Bool, _ completion: UnsafeMutableRawPointer?) {
    guard let state = Connections.state(connection) else { return }
    let block = completion == SharedContexts._nw_connection_send_idempotent_content ? nil : ObjCBlock.from(completion)
    state.send(Dispatch.bytes(content), context: context, isComplete: isComplete, completion: block)
}

@c(_nw_connection_receive)
public func nw_connection_receive(_ connection: UnsafeMutableRawPointer?, _ minimum: UInt32, _ maximum: UInt32,
                                  _ completion: UnsafeMutableRawPointer?) {
    guard let state = Connections.state(connection), let block = ObjCBlock.from(completion) else { return }
    state.receive(minimum: Int(minimum), maximum: Int(maximum), wholeMessage: false, completion: block)
}

@c(_nw_connection_receive_message)
public func nw_connection_receive_message(_ connection: UnsafeMutableRawPointer?, _ completion: UnsafeMutableRawPointer?) {
    guard let state = Connections.state(connection), let block = ObjCBlock.from(completion) else { return }
    state.receive(minimum: 1, maximum: Int(UInt32.max), wholeMessage: true, completion: block)
}

@c(_nw_connection_copy_current_path)
public func nw_connection_copy_current_path(_ connection: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let state = Connections.state(connection), state.currentStatus == ConnectionStatus.ready else { return nil }
    return state.copyCurrentPath()
}

/// The metadata of the stack's protocol with that definition (+1).
@c(_nw_connection_copy_protocol_metadata)
public func nw_connection_copy_protocol_metadata(_ connection: UnsafeMutableRawPointer?,
                                                 _ definition: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let state = Connections.state(connection), let wanted = Definitions.state(definition) else { return nil }
    if wanted.kind == .ip { return Metadata.make(.ip).0 }
    for layer in state.currentLayers.reversed() where layer.kind == wanted.kind {
        if wanted.kind == .framer, let framer = layer as? FramerLayer, framer.definition !== wanted.framer { continue }
        return layer.copyMetadata()
    }
    return nil
}

/// UDP's largest datagram; 0 for a stream.
@c(_nw_connection_get_maximum_datagram_size)
public func nw_connection_get_maximum_datagram_size(_ connection: UnsafeMutableRawPointer?) -> UInt32 {
    guard let state = Connections.state(connection) else { return 0 }
    guard state.parameters.stackState.transportKind == .udp else { return 0 }
    return state.transport?.remoteAddress?.family == AF_INET6 ? 65527 : 65507
}

@c(_nw_connection_copy_description)
public func nw_connection_copy_description(_ connection: UnsafeMutableRawPointer?) -> UnsafeMutablePointer<CChar>? {
    guard let state = Connections.state(connection) else { return nil }
    return copiedCString(state.descriptionText)
}

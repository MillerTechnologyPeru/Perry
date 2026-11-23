// NetworkConnection and NetworkChannel, macOS and iOS 26's connections of
// protocol stacks with async sends and receives, over NWConnection (one
// to one) and NWConnectionGroup (QUIC's streams); QUIC streams and
// datagrams; and withNetworkConnection.

import Dispatch
import Foundation
import Security

/// What a channel sends and receives on.
enum ChannelTransport {
    case connection(NWConnection)
    case group(NWConnectionGroup)
    /// A connection that could not be made, and why.
    case failed(any Error)
}

/// The bytes a framed channel received and hasn't read yet.
private final class ReceiveBuffer: @unchecked Sendable {
    let lock = NSLock()
    var bytes = Data()
    var ended = false
}

@_hasMissingDesignatedInitializers
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public class NetworkChannel<ApplicationProtocol>: CustomDebugStringConvertible, @unchecked Sendable where ApplicationProtocol: NetworkProtocolOptions {
    public enum State: Equatable, Sendable {
        case setup
        case waiting(NWError)
        case preparing
        case ready
        case failed(NWError)
        case cancelled

        public static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.setup, .setup), (.preparing, .preparing), (.ready, .ready), (.cancelled, .cancelled): return true
            case let (.waiting(x), .waiting(y)), let (.failed(x), .failed(y)): return x == y
            default: return false
            }
        }
    }

    let transport: ChannelTransport
    let stack: StackDescription
    let queue: DispatchQueue
    let lock = NSLock()
    private let identifier = UUID().uuidString
    private var started = false
    private var storedState: State = .setup
    private var stateHandler: (@Sendable (State) -> Void)?
    private var pendingReport: NWConnection.PendingDataTransferReport?
    private let buffer = ReceiveBuffer()

    init(transport: ChannelTransport, stack: StackDescription) {
        self.transport = transport
        self.stack = stack
        queue = DispatchQueue(label: "com.apple.network.connection")
    }

    deinit {
        switch transport {
        case .connection(let connection): connection.cancel()
        case .group(let group): group.cancel()
        case .failed: break
        }
    }

    public static func == (lhs: NetworkChannel, rhs: NetworkChannel) -> Bool {
        lhs === rhs
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    public var id: String { identifier }

    public var debugDescription: String {
        switch transport {
        case .connection(let connection): return connection.debugDescription
        case .group(let group): return group.debugDescription
        case .failed(let error): return "Failed connection: \(error)"
        }
    }

    public var state: State {
        lock.withLock { storedState }
    }

    /// Has a state handler called as the state changes.
    func setStateHandler(_ handler: @escaping @Sendable (State) -> Void) {
        lock.withLock { stateHandler = handler }
    }

    func update(_ state: State) {
        let handler = lock.withLock { () -> (@Sendable (State) -> Void)? in
            storedState = state
            return stateHandler
        }
        handler?(state)
    }

    /// Starts the connection the first time it is used.
    func startIfNeeded() {
        let first = lock.withLock { () -> Bool in
            defer { started = true }
            return !started
        }
        guard first else { return }
        switch transport {
        case .connection(let connection):
            connection.stateUpdateHandler = { [weak self] state in
                self?.update(State(state))
            }
            pendingReport = connection.startDataTransferReport()
            connection.start(queue: queue)
        case .group(let group):
            group.stateUpdateHandler = { [weak self] state in
                self?.update(State(state))
            }
            group.start(queue: queue)
        case .failed(let error):
            update(.failed(error as? NWError ?? .posix(.EINVAL)))
        }
    }

    /// The connection of a one-to-one channel, started.
    func connection() throws -> NWConnection {
        startIfNeeded()
        switch transport {
        case .connection(let connection): return connection
        case .group: throw NWError.posix(.EOPNOTSUPP)
        case .failed(let error): throw error
        }
    }

    public var maximumDatagramSize: Int {
        if case .connection(let connection) = transport { return connection.maximumDatagramSize }
        return 0
    }

    public var parameters: NWParameters {
        switch transport {
        case .connection(let connection): return connection.parameters
        case .group(let group): return group.parameters
        case .failed: return stack.makeParameters()
        }
    }

    public func metadata(definition: NWProtocolDefinition) -> NWProtocolMetadata? {
        switch transport {
        case .connection(let connection): return connection.metadata(definition: definition)
        case .group(let group): return group.metadata(definition: definition)
        case .failed: return nil
        }
    }

    public func establishmentReport() async throws -> NWConnection.EstablishmentReport {
        let connection = try connection()
        let report = await withCheckedContinuation { continuation in
            connection.requestEstablishmentReport(queue: queue) { continuation.resume(returning: $0) }
        }
        guard let report else { throw NWError.posix(.ENOTCONN) }
        return report
    }

    /// The data transferred since the channel started or the last report.
    public func dataTransferReport() async throws -> NWConnection.DataTransferReport {
        let connection = try connection()
        let pending = lock.withLock { () -> NWConnection.PendingDataTransferReport in
            let pending = pendingReport ?? connection.startDataTransferReport()
            pendingReport = connection.startDataTransferReport()
            return pending
        }
        return await withCheckedContinuation { continuation in
            pending.collect(queue: queue) { continuation.resume(returning: $0) }
        }
    }

    // MARK: Sending and receiving

    /// Sends content with a context and waits until it is processed.
    func sendContent(_ content: Data?, context: NWConnection.ContentContext, isComplete: Bool) async throws {
        let connection = try connection()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(content: content, contentContext: context, isComplete: isComplete, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    func sendIdempotentContent(_ content: Data?, context: NWConnection.ContentContext, isComplete: Bool) {
        guard let connection = try? connection() else { return }
        connection.send(content: content, contentContext: context, isComplete: isComplete, completion: .idempotent)
    }

    /// A context for content with metadata, final at the end of a stream.
    func context(metadata: [NWProtocolMetadata], isFinal: Bool) -> NWConnection.ContentContext {
        if metadata.isEmpty {
            return isFinal ? .finalMessage : .defaultMessage
        }
        return NWConnection.ContentContext(identifier: "send", isFinal: isFinal, metadata: metadata)
    }

    /// Receives bytes of a stream: nil content at its end.
    func receiveBytes(atLeast: Int, atMost: Int) async throws -> (Data?, NWConnection.ContentContext?, Bool) {
        let connection = try connection()
        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: atLeast, maximumLength: atMost) { content, context, isComplete, error in
                if let error, content == nil {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (content, context, isComplete))
                }
            }
        }
    }

    /// Receives one message.
    func receiveOneMessage() async throws -> (Data, NWConnection.ContentContext?, Bool) {
        let connection = try connection()
        return try await withCheckedThrowingContinuation { continuation in
            connection.receiveMessage { content, context, isComplete, error in
                if let error, content == nil {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (content ?? Data(), context, isComplete))
                }
            }
        }
    }

    /// Exactly the count of bytes from the stream, reading past what is
    /// buffered; fewer only at the stream's end.
    func readFramed(_ count: Int) async throws -> Data {
        while true {
            let ready = buffer.lock.withLock { () -> Data? in
                if buffer.bytes.count >= count || buffer.ended {
                    let taken = buffer.bytes.prefix(count)
                    buffer.bytes.removeFirst(taken.count)
                    return Data(taken)
                }
                return nil
            }
            if let ready {
                if ready.count < count { throw NWError.posix(.ENODATA) }
                return ready
            }
            let (content, _, isComplete) = try await receiveBytes(atLeast: 1, atMost: 65536)
            buffer.lock.withLock {
                if let content { buffer.bytes.append(content) }
                if isComplete && content == nil { buffer.ended = true }
            }
        }
    }

    /// The bytes of one message of Swift's framing: a message of the
    /// protocol below, or a length-prefixed piece of the stream.
    func receiveFramedMessage(lengthSize: Int) async throws -> (Data, NWConnection.ContentContext?) {
        if stack.framingOverMessages {
            let (content, context, _) = try await receiveOneMessage()
            return (content, context)
        }
        let length = try await bigEndianValue(readFramed(lengthSize))
        return (try await readFramed(Int(length)), nil)
    }

    /// Sends one message of Swift's framing.
    func sendFramed(_ payload: Data, context: NWConnection.ContentContext) async throws {
        try await sendContent(payload, context: context, isComplete: true)
    }

    // MARK: Swift's framing

    /// A TLV message of the type and value.
    func tlvBytes(type: Int, value: Data) throws -> Data {
        guard case .tlv(let typeSize, let lengthSize) = stack.framing else { throw NWError.posix(.EINVAL) }
        var bytes = bigEndianBytes(UInt64(truncatingIfNeeded: type), size: typeSize)
        bytes.append(bigEndianBytes(UInt64(value.count), size: lengthSize))
        bytes.append(value)
        return bytes
    }

    /// The next TLV message: its type and value.
    func receiveTLV() async throws -> (type: Int, value: Data, context: NWConnection.ContentContext?) {
        guard case .tlv(let typeSize, let lengthSize) = stack.framing else { throw NWError.posix(.EINVAL) }
        if stack.framingOverMessages {
            let (content, context, _) = try await receiveOneMessage()
            guard content.count >= typeSize + lengthSize else { throw NWError.posix(.EBADMSG) }
            let type = bigEndianValue(content.prefix(typeSize))
            return (Int(truncatingIfNeeded: type), Data(content.dropFirst(typeSize + lengthSize)), context)
        }
        let type = try bigEndianValue(await readFramed(typeSize))
        let length = try bigEndianValue(await readFramed(lengthSize))
        return (Int(truncatingIfNeeded: type), try await readFramed(Int(length)), nil)
    }

    /// A coded value's message: on a stream a 4-byte length before it.
    func coderBytes(_ value: Any) throws -> Data {
        guard case .coder(let encode, _) = stack.framing else { throw NWError.posix(.EINVAL) }
        let payload = try encode(value)
        if stack.framingOverMessages { return payload }
        var bytes = bigEndianBytes(UInt64(payload.count), size: 4)
        bytes.append(payload)
        return bytes
    }

    func receiveCoded() async throws -> (Any, NWConnection.ContentContext?) {
        guard case .coder(_, let decode) = stack.framing else { throw NWError.posix(.EINVAL) }
        let (payload, context) = try await receiveFramedMessage(lengthSize: 4)
        return (try decode(payload), context)
    }

    /// The next message of a message protocol's channel, as its content
    /// and metadata (of the protocol's types).
    func receiveAnyMessage() async throws -> (Any, Any) {
        switch stack.top {
        case .tlv:
            let (type, value, context) = try await receiveTLV()
            return (value, TLV.Metadata(type: type, length: value.count, isComplete: true, lastMessage: false, other: context?.protocolMetadata ?? []))
        case .coder:
            let (value, context) = try await receiveCoded()
            return (value, codedMetadata(context))
        case .webSocket:
            let (content, context, isComplete) = try await receiveOneMessage()
            return (content, webSocketMetadata(context, isComplete: isComplete))
        case .framer:
            let (content, context, isComplete) = try await receiveOneMessage()
            return (content, framerMetadata(context, isComplete: isComplete))
        default:
            let (content, context, isComplete) = try await receiveOneMessage()
            return (content, try receivedMetadata(endOfStream: false, isComplete: isComplete, context: context))
        }
    }

    /// The Coder metadata of a received value: Coder's generic Metadata,
    /// made through the application protocol's type.
    func codedMetadata(_ context: NWConnection.ContentContext?) -> Any {
        CodedMetadataBox(isComplete: true, lastMessage: context?.isFinal ?? false, other: context?.protocolMetadata ?? [])
    }

    func webSocketMetadata(_ context: NWConnection.ContentContext?, isComplete: Bool) -> WebSocket.Metadata {
        let ws = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
        let closeCode: NWProtocolWebSocket.CloseCode? = ws?.opcode == .close ? ws?.closeCode : nil
        return WebSocket.Metadata(opcode: ws?.opcode ?? .binary, closeCode: closeCode, isComplete: isComplete,
                                  lastMessage: context?.isFinal ?? false, other: context?.protocolMetadata ?? [])
    }

    func framerMetadata(_ context: NWConnection.ContentContext?, isComplete: Bool) -> Any {
        let message = context?.protocolMetadata.compactMap { $0 as? NWProtocolFramer.Message }.first
        return FramerMetadataBox(framer: message, isComplete: isComplete, lastMessage: context?.isFinal ?? false, other: context?.protocolMetadata ?? [])
    }

    /// The application protocol's metadata of a receive, for the protocols
    /// whose metadata a receive makes.
    func receivedMetadata(endOfStream: Bool, isComplete: Bool, context: NWConnection.ContentContext?) throws -> ApplicationProtocol.Metadata {
        guard let type = ApplicationProtocol.Metadata.self as? any ReceivedMetadata.Type,
              let metadata = type.make(endOfStream: endOfStream, isComplete: isComplete, context: context) as? ApplicationProtocol.Metadata else {
            throw NWError.posix(.EPROTONOSUPPORT)
        }
        return metadata
    }

    /// A message of the application protocol of content and metadata.
    func message<Content>(_ content: Any, _ metadata: Any) throws -> ApplicationProtocol.Message<Content> {
        guard let content = content as? Content else { throw NWError.posix(.EBADMSG) }
        if let metadata = metadata as? ApplicationProtocol.Metadata {
            return (content: content, metadata: metadata)
        }
        if let box = metadata as? MetadataBox, let metadata = box.metadata(as: ApplicationProtocol.Metadata.self) {
            return (content: content, metadata: metadata)
        }
        throw NWError.posix(.EPROTONOSUPPORT)
    }
}

/// Metadata of a generic protocol's (Coder's or Framer's), made once the
/// generic type is known.
protocol MetadataBox {
    func metadata<M>(as type: M.Type) -> M?
}

private protocol CodedMetadataMaking {
    static func make(isComplete: Bool, lastMessage: Bool, other: [NWProtocolMetadata]) -> Self
}

private protocol FramerMetadataMaking {
    static func make(framer: NWProtocolFramer.Message?, isComplete: Bool, lastMessage: Bool, other: [NWProtocolMetadata]) -> Self?
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension Coder.Metadata: CodedMetadataMaking {
    static func make(isComplete: Bool, lastMessage: Bool, other: [NWProtocolMetadata]) -> Self {
        Self(isComplete: isComplete, lastMessage: lastMessage, other: other)
    }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension Framer.Metadata: FramerMetadataMaking {
    static func make(framer: NWProtocolFramer.Message?, isComplete: Bool, lastMessage: Bool, other: [NWProtocolMetadata]) -> Self? {
        guard let framer else { return nil }
        return Self(framer: framer, isComplete: isComplete, lastMessage: lastMessage, other: other)
    }
}

private struct CodedMetadataBox: MetadataBox {
    let isComplete: Bool
    let lastMessage: Bool
    let other: [NWProtocolMetadata]

    func metadata<M>(as type: M.Type) -> M? {
        (type as? any CodedMetadataMaking.Type)?.make(isComplete: isComplete, lastMessage: lastMessage, other: other) as? M
    }
}

private struct FramerMetadataBox: MetadataBox {
    let framer: NWProtocolFramer.Message?
    let isComplete: Bool
    let lastMessage: Bool
    let other: [NWProtocolMetadata]

    func metadata<M>(as type: M.Type) -> M? {
        (type as? any FramerMetadataMaking.Type)?.make(framer: framer, isComplete: isComplete, lastMessage: lastMessage, other: other) as? M
    }
}

/// The bytes of a value, big-endian, in the size given.
func bigEndianBytes(_ value: UInt64, size: Int) -> Data {
    Data((0..<size).reversed().map { UInt8(truncatingIfNeeded: value >> (UInt64($0) * 8)) })
}

/// The value of big-endian bytes.
func bigEndianValue(_ bytes: Data) -> UInt64 {
    bytes.reduce(0) { $0 << 8 | UInt64($1) }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension NetworkChannel.State {
    init(_ state: NWConnection.State) {
        switch state {
        case .setup: self = .setup
        case .waiting(let error): self = .waiting(error)
        case .preparing: self = .preparing
        case .ready: self = .ready
        case .failed(let error): self = .failed(error)
        case .cancelled: self = .cancelled
        }
    }

    init(_ state: NWConnectionGroup.State) {
        switch state {
        case .setup: self = .setup
        case .waiting(let error): self = .waiting(error)
        case .ready: self = .ready
        case .failed(let error): self = .failed(error)
        case .cancelled: self = .cancelled
        }
    }
}

@available(macOS 26.1, iOS 26.1, watchOS 26.1, tvOS 26.1, visionOS 26.1, *)
extension NetworkChannel: Identifiable, Hashable {
    @available(macOS 26.1, iOS 26.1, tvOS 26.1, watchOS 26.1, visionOS 26.1, *)
    public typealias ID = String
}

// MARK: - Connections

@_inheritsConvenienceInitializers
@_hasMissingDesignatedInitializers
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
final public class NetworkConnection<ApplicationProtocol>: NetworkChannel<ApplicationProtocol>, @unchecked Sendable where ApplicationProtocol: NetworkProtocolOptions {
    final public var currentPath: NWPath? {
        if case .connection(let connection) = transport { return connection.currentPath }
        return nil
    }

    final public var localEndpoint: NWEndpoint? {
        currentPath?.localEndpoint
    }

    final public var remoteEndpoint: NWEndpoint? {
        switch transport {
        case .connection(let connection): return currentPath?.remoteEndpoint ?? connection.endpoint
        case .group(let group): return group.descriptor.members.first
        case .failed: return nil
        }
    }

    final public func tryNextEndpoint() {
        if case .connection(let connection) = transport { connection.cancelCurrentEndpoint() }
    }

    @discardableResult
    final public func onStateUpdate(@_inheritActorContext _ handler: @escaping @isolated(any) @Sendable (_ connection: NetworkConnection<ApplicationProtocol>, _ state: NetworkChannel<ApplicationProtocol>.State) -> Void) -> Self {
        unowned let connection: NetworkConnection<ApplicationProtocol> = self
        setStateHandler { state in
            Task { await handler(connection, state) }
        }
        return self
    }

    /// A connection to an endpoint, or one failing for an endpoint the
    /// Connectable doesn't give.
    static func transport(to provider: any Connectable, stack: StackDescription, parameters: NWParameters) -> ChannelTransport {
        guard let endpoint = (provider as? any EndpointProviding)?.connectionEndpoint else {
            return .failed(NWError.posix(.EAFNOSUPPORT))
        }
        return transport(to: endpoint, stack: stack, parameters: parameters)
    }

    static func transport(to endpoint: NWEndpoint, stack: StackDescription, parameters: NWParameters) -> ChannelTransport {
        if stack.top == .quic {
            return .group(NWConnectionGroup(with: NWMultiplexGroup(to: endpoint), using: parameters))
        }
        return .connection(NWConnection(to: endpoint, using: parameters))
    }

    /// Path, viability and better path handlers of the connection.
    func setPathHandlers(path: (@Sendable (NWPath) -> Void)?, viability: (@Sendable (Bool) -> Void)?, betterPath: (@Sendable (Bool) -> Void)?) {
        guard case .connection(let connection) = transport else { return }
        if let path { connection.pathUpdateHandler = path }
        if let viability { connection.viabilityUpdateHandler = viability }
        if let betterPath { connection.betterPathUpdateHandler = betterPath }
    }
}

/// A Connectable that gives an endpoint to connect to.
protocol EndpointProviding {
    var connectionEndpoint: NWEndpoint { get }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension NetworkConnection where ApplicationProtocol: OneToOneProtocol {
    public convenience init(to endpoint: NWEndpoint, @ProtocolStackBuilder<ApplicationProtocol> using builder: () -> ApplicationProtocol) {
        let stack = describeStack([builder()])
        self.init(transport: Self.transport(to: endpoint, stack: stack, parameters: stack.makeParameters()), stack: stack)
    }

    public convenience init(to provider: any Connectable, @ProtocolStackBuilder<ApplicationProtocol> using builder: () -> ApplicationProtocol) {
        let stack = describeStack([builder()])
        self.init(transport: Self.transport(to: provider, stack: stack, parameters: stack.makeParameters()), stack: stack)
    }

    public convenience init(to endpoint: NWEndpoint, using builder: NWParametersBuilder<ApplicationProtocol>) {
        self.init(transport: Self.transport(to: endpoint, stack: builder.stack, parameters: builder.parameters), stack: builder.stack)
    }

    public convenience init(to provider: any Connectable, using builder: NWParametersBuilder<ApplicationProtocol>) {
        self.init(transport: Self.transport(to: provider, stack: builder.stack, parameters: builder.parameters), stack: builder.stack)
    }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension NetworkConnection where ApplicationProtocol: MultiplexProtocol {
    public convenience init(to endpoint: NWEndpoint, @ProtocolStackBuilder<ApplicationProtocol> using builder: () -> ApplicationProtocol) {
        let stack = describeStack([builder()])
        self.init(transport: Self.transport(to: endpoint, stack: stack, parameters: stack.makeParameters()), stack: stack)
    }

    public convenience init(to provider: any Connectable, @ProtocolStackBuilder<ApplicationProtocol> using builder: () -> ApplicationProtocol) {
        let stack = describeStack([builder()])
        self.init(transport: Self.transport(to: provider, stack: stack, parameters: stack.makeParameters()), stack: stack)
    }

    public convenience init(to endpoint: NWEndpoint, using builder: NWParametersBuilder<ApplicationProtocol>) {
        self.init(transport: Self.transport(to: endpoint, stack: builder.stack, parameters: builder.parameters), stack: builder.stack)
    }

    public convenience init(to provider: any Connectable, using builder: NWParametersBuilder<ApplicationProtocol>) {
        self.init(transport: Self.transport(to: provider, stack: builder.stack, parameters: builder.parameters), stack: builder.stack)
    }

    /// Starts the connection now, rather than at its first stream.
    final public func start() -> Self {
        startIfNeeded()
        return self
    }
}

@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
extension NetworkConnection where ApplicationProtocol: MultiplexProtocol {
    @discardableResult
    final public func onPathUpdate(@_inheritActorContext _ handler: @escaping @isolated(any) @Sendable (_ connection: NetworkConnection<ApplicationProtocol>, _ newPath: NWPath) -> Void) -> Self {
        unowned let connection: NetworkConnection<ApplicationProtocol> = self
        setPathHandlers(path: { path in Task { await handler(connection, path) } }, viability: nil, betterPath: nil)
        return self
    }

    @discardableResult
    final public func onViabilityUpdate(@_inheritActorContext _ handler: @escaping @isolated(any) @Sendable (_ connection: NetworkConnection<ApplicationProtocol>, _ newViable: Bool) -> Void) -> Self {
        unowned let connection: NetworkConnection<ApplicationProtocol> = self
        setPathHandlers(path: nil, viability: { viable in Task { await handler(connection, viable) } }, betterPath: nil)
        return self
    }

    @discardableResult
    final public func onBetterPathUpdate(@_inheritActorContext _ handler: @escaping @isolated(any) @Sendable (_ connection: NetworkConnection<ApplicationProtocol>, _ newValue: Bool) -> Void) -> Self {
        unowned let connection: NetworkConnection<ApplicationProtocol> = self
        setPathHandlers(path: nil, viability: nil, betterPath: { better in Task { await handler(connection, better) } })
        return self
    }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension NetworkConnection where ApplicationProtocol: OneToOneProtocol {
    @discardableResult
    final public func onPathUpdate(@_inheritActorContext _ handler: @escaping @isolated(any) @Sendable (_ connection: NetworkConnection<ApplicationProtocol>, _ newPath: NWPath) -> Void) -> Self {
        unowned let connection: NetworkConnection<ApplicationProtocol> = self
        setPathHandlers(path: { path in Task { await handler(connection, path) } }, viability: nil, betterPath: nil)
        return self
    }

    @discardableResult
    final public func onViabilityUpdate(@_inheritActorContext _ handler: @escaping @isolated(any) @Sendable (_ connection: NetworkConnection<ApplicationProtocol>, _ newViable: Bool) -> Void) -> Self {
        unowned let connection: NetworkConnection<ApplicationProtocol> = self
        setPathHandlers(path: nil, viability: { viable in Task { await handler(connection, viable) } }, betterPath: nil)
        return self
    }

    @discardableResult
    final public func onBetterPathUpdate(@_inheritActorContext _ handler: @escaping @isolated(any) @Sendable (_ connection: NetworkConnection<ApplicationProtocol>, _ newValue: Bool) -> Void) -> Self {
        unowned let connection: NetworkConnection<ApplicationProtocol> = self
        setPathHandlers(path: nil, viability: nil, betterPath: { better in Task { await handler(connection, better) } })
        return self
    }
}

// MARK: - QUIC streams and datagrams

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension QUIC {
    /// A stream of a QUIC connection.
    @_hasMissingDesignatedInitializers
    final public class Stream<ApplicationProtocol>: NetworkChannel<ApplicationProtocol>, @unchecked Sendable where ApplicationProtocol: NetworkProtocolOptions {
        final public let parent: NetworkConnection<QUIC>

        init(parent: NetworkConnection<QUIC>, connection: NWConnection, stack: StackDescription) {
            self.parent = parent
            super.init(transport: .connection(connection), stack: stack)
        }

        private var quicMetadata: NWProtocolQUIC.Metadata? {
            metadata(definition: NWProtocolQUIC.definition) as? NWProtocolQUIC.Metadata
        }

        final public var streamID: UInt64 {
            quicMetadata?.streamIdentifier ?? 0
        }

        /// QUIC's stream identifiers say the direction in bit 1.
        final public var directionality: QUICStream.Directionality {
            streamID & 0x2 == 0 ? .bidirectional : .unidirectional
        }

        /// QUIC's stream identifiers say the initiator in bit 0.
        final public var initiator: QUICStream.Initiator {
            streamID & 0x1 == 0 ? .client : .server
        }

        final public var streamApplicationErrorCode: UInt64 {
            get { quicMetadata?.streamApplicationErrorCode ?? 0 }
            set { quicMetadata?.streamApplicationErrorCode = newValue }
        }

        deinit {}
    }

    /// The datagrams of a QUIC connection.
    @_hasMissingDesignatedInitializers
    final public class Datagrams<ApplicationProtocol>: NetworkChannel<ApplicationProtocol>, @unchecked Sendable where ApplicationProtocol: NetworkProtocolOptions {
        final public let parent: NetworkConnection<QUIC>

        init(parent: NetworkConnection<QUIC>, connection: NWConnection) {
            self.parent = parent
            super.init(transport: .connection(connection), stack: describeStack([QUICDatagram()]))
        }

        deinit {}
    }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension NetworkConnection where ApplicationProtocol == QUIC {
    private var group: NWConnectionGroup? {
        startIfNeeded()
        if case .group(let group) = transport { return group }
        return nil
    }

    private var quicMetadata: NWProtocolQUIC.Metadata? {
        group?.metadata(definition: NWProtocolQUIC.definition) as? NWProtocolQUIC.Metadata
    }

    /// The TLS metadata of the connection, once it is established (it
    /// can't be had before).
    final public var securityProtocolMetadata: sec_protocol_metadata_t {
        guard let metadata = quicMetadata else {
            preconditionFailure("The QUIC connection is not established")
        }
        return metadata.securityProtocolMetadata
    }

    final public var negotiatedALPN: String? { quicMetadata?.negotiatedALPN }

    final public var remoteIdleTimeout: Int { quicMetadata?.remoteIdleTimeout ?? 0 }

    final public var applicationError: NWProtocolQUIC.ApplicationError {
        get { quicMetadata?.applicationError ?? NWProtocolQUIC.ApplicationError(code: 0) }
        set { quicMetadata?.applicationError = newValue }
    }

    final public var remoteMaxStreamsUnidirectional: Int { quicMetadata?.remoteMaxStreamsUnidirectional ?? 0 }

    final public var remoteMaxStreamsBidirectional: Int { quicMetadata?.remoteMaxStreamsBidirectional ?? 0 }

    final public var usableDatagramFrameSize: Int { quicMetadata?.usableDatagramFrameSize ?? 0 }

    final public var keepalive: NWProtocolQUIC.Metadata.KeepAliveBehavior {
        get { quicMetadata?.keepAlive ?? .off }
        set { quicMetadata?.keepAlive = newValue }
    }

    /// A new stream, taken from the group with its own QUIC options.
    private func newStream(directionality: QUICStream.Directionality, datagram: Bool = false) throws -> NWConnection {
        guard let group else { throw NWError.posix(.ENOTCONN) }
        let options = NWProtocolQUIC.Options()
        options.direction = directionality == .unidirectional ? .unidirectional : .bidirectional
        options.isDatagram = datagram
        guard let connection = group.extract(connectionTo: nil, using: options) else { throw NWError.posix(.ENOTCONN) }
        return connection
    }

    final public func openStream(directionality: QUICStream.Directionality = .bidirectional) async throws -> QUIC.Stream<QUICStream> {
        QUIC.Stream(parent: self, connection: try newStream(directionality: directionality), stack: describeStack([QUICStream(directionality: directionality)]))
    }

    /// A stream with protocols above it. Swift's framing (TLV, Coder) is
    /// done on it; protocols of the C API's (WebSocket, a framer) can't be
    /// added to a stream taken from a group, so they are left out.
    final public func openStream<NewApplicationProtocol>(directionality: QUICStream.Directionality = .bidirectional, @ProtocolStackBuilder<NewApplicationProtocol> _ prepending: (QUICStream) -> NewApplicationProtocol) async throws -> QUIC.Stream<NewApplicationProtocol> where NewApplicationProtocol: OneToOneProtocol {
        let stack = describeStack([prepending(QUICStream(directionality: directionality))])
        return QUIC.Stream(parent: self, connection: try newStream(directionality: directionality), stack: stack)
    }

    final public var datagrams: QUIC.Datagrams<QUICDatagram> {
        get async throws {
            QUIC.Datagrams(parent: self, connection: try newStream(directionality: .bidirectional, datagram: true))
        }
    }

    final public func inboundStreams(@_inheritActorContext _ handler: @escaping @isolated(any) @Sendable (QUIC.Stream<QUICStream>) async throws -> Void) async throws {
        try await inboundStreams(prepending: { $0 }, handler)
    }

    final public func inboundStreams<NewApplicationProtocol>(@ProtocolStackBuilder<NewApplicationProtocol> prepending: @escaping (QUICStream) -> NewApplicationProtocol, @_inheritActorContext _ handler: @escaping @isolated(any) @Sendable (QUIC.Stream<NewApplicationProtocol>) async throws -> Void) async throws where NewApplicationProtocol: OneToOneProtocol {
        guard let group else { throw NWError.posix(.ENOTCONN) }
        let stack = describeStack([prepending(QUICStream())])
        let (connections, continuation) = AsyncStream<NWConnection>.makeStream()
        group.newConnectionHandler = { continuation.yield($0) }
        let previous = group.stateUpdateHandler
        group.stateUpdateHandler = { [weak self] state in
            previous?(state)
            self?.update(NetworkChannel<QUIC>.State(state))
            switch state {
            case .failed, .cancelled: continuation.finish()
            default: break
            }
        }
        try await withThrowingTaskGroup(of: Void.self) { tasks in
            for await connection in connections {
                let stream = QUIC.Stream<NewApplicationProtocol>(parent: self, connection: connection, stack: stack)
                tasks.addTask { try await handler(stream) }
            }
            try await tasks.waitForAll()
        }
        if case .failed(let error) = state { throw error }
    }
}

// MARK: - Sending and receiving

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension NetworkChannel where ApplicationProtocol: StreamProtocol {
    public func send<Content>(_ content: Content, endOfStream: Bool = false, @ProtocolMetadataBuilder metadata builder: () -> [NWProtocolMetadata] = { [] }) async throws where Content: DataProtocol {
        try await sendContent(Data(content), context: context(metadata: builder(), isFinal: endOfStream), isComplete: endOfStream)
    }

    public func send<Value>(_ value: Value, endOfStream: Bool = false, @ProtocolMetadataBuilder metadata builder: () -> [NWProtocolMetadata] = { [] }) async throws where Value: NetworkFixedWidthInteger {
        try await send(withUnsafeBytes(of: value.bigEndian) { Data($0) }, endOfStream: endOfStream, metadata: builder)
    }

    public func sendIdempotent<Content>(_ content: Content, endOfStream: Bool = false, @ProtocolMetadataBuilder metadata builder: () -> [NWProtocolMetadata] = { [] }) where Content: DataProtocol {
        sendIdempotentContent(Data(content), context: context(metadata: builder(), isFinal: endOfStream), isComplete: endOfStream)
    }

    public func sendIdempotent<Value>(_ value: Value, endOfStream: Bool = false, @ProtocolMetadataBuilder metadata builder: () -> [NWProtocolMetadata] = { [] }) where Value: NetworkFixedWidthInteger {
        sendIdempotent(withUnsafeBytes(of: value.bigEndian) { Data($0) }, endOfStream: endOfStream, metadata: builder)
    }

    public func receive(atLeast: Int = 1, atMost: Int) async throws -> ApplicationProtocol.Message<Data> {
        let (content, context, isComplete) = try await receiveBytes(atLeast: atLeast, atMost: atMost)
        let endOfStream = isComplete && (context?.isFinal ?? true)
        return (content: content ?? Data(), metadata: try receivedMetadata(endOfStream: endOfStream, isComplete: isComplete, context: context))
    }

    public func receive(exactly: Int) async throws -> ApplicationProtocol.Message<Data> {
        try await receive(atLeast: exactly, atMost: exactly)
    }

    public func receive<Value>(as type: Value.Type) async throws -> ApplicationProtocol.Message<Value> where Value: NetworkFixedWidthInteger {
        let message = try await receive(exactly: MemoryLayout<Value>.size)
        guard message.content.count == MemoryLayout<Value>.size else { throw NWError.posix(.ENODATA) }
        var value = Value.zero
        withUnsafeMutableBytes(of: &value) { _ = message.content.copyBytes(to: $0) }
        return (content: Value(bigEndian: value), metadata: message.metadata)
    }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension NetworkChannel where ApplicationProtocol: DatagramProtocol {
    public func send<Content>(_ content: Content, @ProtocolMetadataBuilder metadata builder: () -> [NWProtocolMetadata] = { [] }) async throws where Content: DataProtocol {
        try await sendContent(Data(content), context: context(metadata: builder(), isFinal: false), isComplete: true)
    }

    public func receive() async throws -> ApplicationProtocol.Message<Data> {
        let (content, context, isComplete) = try await receiveOneMessage()
        return (content: content, metadata: try receivedMetadata(endOfStream: false, isComplete: isComplete, context: context))
    }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension NetworkChannel where ApplicationProtocol == WebSocket {
    private func webSocketContext(_ opcode: NWProtocolWebSocket.Opcode, _ metadata: [NWProtocolMetadata], configure: (NWProtocolWebSocket.Metadata) -> Void = { _ in }) -> NWConnection.ContentContext {
        let ws = NWProtocolWebSocket.Metadata(opcode: opcode)
        configure(ws)
        return NWConnection.ContentContext(identifier: "websocket", metadata: [ws] + metadata)
    }

    public func send(_ content: String, @ProtocolMetadataBuilder metadata builder: () -> [NWProtocolMetadata] = { [] }) async throws {
        try await sendContent(Data(content.utf8), context: webSocketContext(.text, builder()), isComplete: true)
    }

    public func sendIdempotent(_ content: String, @ProtocolMetadataBuilder metadata builder: () -> [NWProtocolMetadata] = { [] }) {
        sendIdempotentContent(Data(content.utf8), context: webSocketContext(.text, builder()), isComplete: true)
    }

    public func send<Content>(_ content: Content, @ProtocolMetadataBuilder metadata builder: () -> [NWProtocolMetadata] = { [] }) async throws where Content: DataProtocol {
        try await sendContent(Data(content), context: webSocketContext(.binary, builder()), isComplete: true)
    }

    public func sendIdempotent<Content>(_ content: Content, @ProtocolMetadataBuilder metadata builder: () -> [NWProtocolMetadata] = { [] }) where Content: DataProtocol {
        sendIdempotentContent(Data(content), context: webSocketContext(.binary, builder()), isComplete: true)
    }

    /// Sends a text message in parts: the first, then those the handler sends.
    public func startSend(_ content: String, @ProtocolMetadataBuilder metadata builder: () -> [NWProtocolMetadata] = { [] }, handler: (_ send: (_ content: String, _ isComplete: Bool) async throws -> Void) async throws -> Void) async throws {
        let context = webSocketContext(.text, builder())
        try await sendContent(Data(content.utf8), context: context, isComplete: false)
        try await handler { part, isComplete in
            try await self.sendContent(Data(part.utf8), context: context, isComplete: isComplete)
        }
    }

    public func startSend<Content>(_ content: Content, @ProtocolMetadataBuilder metadata builder: () -> [NWProtocolMetadata] = { [] }, handler: (_ send: (_ content: Content, _ isComplete: Bool) async throws -> Void) async throws -> Void) async throws where Content: DataProtocol {
        let context = webSocketContext(.binary, builder())
        try await sendContent(Data(content), context: context, isComplete: false)
        try await handler { part, isComplete in
            try await self.sendContent(Data(part), context: context, isComplete: isComplete)
        }
    }

    public func ping<Content>(_ content: Content? = nil, @ProtocolMetadataBuilder metadata builder: () -> [NWProtocolMetadata] = { [] }) async throws where Content: DataProtocol {
        try await sendContent(content.map { Data($0) } ?? Data(), context: webSocketContext(.ping, builder()), isComplete: true)
    }

    public func pong<Content>(_ content: Content? = nil, @ProtocolMetadataBuilder metadata builder: () -> [NWProtocolMetadata] = { [] }) async throws where Content: DataProtocol {
        try await sendContent(content.map { Data($0) } ?? Data(), context: webSocketContext(.pong, builder()), isComplete: true)
    }

    public func close(code: NWProtocolWebSocket.CloseCode = .protocolCode(.normalClosure), reason: String? = nil, @ProtocolMetadataBuilder metadata builder: () -> [NWProtocolMetadata] = { [] }) async throws {
        let context = webSocketContext(.close, builder()) { $0.closeCode = code }
        try await sendContent(reason.map { Data($0.utf8) } ?? Data(), context: context, isComplete: true)
    }

    public func receive() async throws -> ApplicationProtocol.Message<Data> {
        let (content, context, isComplete) = try await receiveOneMessage()
        return (content: content, metadata: webSocketMetadata(context, isComplete: isComplete))
    }

    /// Receives a message in parts, as the handler asks for them.
    public func startReceive(_ handler: (_ receive: (_ atLeast: Int, _ atMost: Int) async throws -> ApplicationProtocol.Message<Data>) async throws -> Void) async throws {
        try await handler { atLeast, atMost in
            let (content, context, isComplete) = try await self.receiveBytes(atLeast: atLeast, atMost: atMost)
            return (content: content ?? Data(), metadata: self.webSocketMetadata(context, isComplete: isComplete))
        }
    }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension NetworkChannel where ApplicationProtocol == TLV {
    public func send<Content>(_ content: Content, type: Int, lastMessage: Bool = false, @ProtocolMetadataBuilder metadata builder: () -> [NWProtocolMetadata] = { [] }) async throws where Content: DataProtocol {
        try await sendFramed(tlvBytes(type: type, value: Data(content)), context: context(metadata: builder(), isFinal: lastMessage))
    }

    public func sendIdempotent<Content>(_ content: Content, type: Int, lastMessage: Bool = false, @ProtocolMetadataBuilder metadata builder: () -> [NWProtocolMetadata] = { [] }) where Content: DataProtocol {
        guard let bytes = try? tlvBytes(type: type, value: Data(content)) else { return }
        sendIdempotentContent(bytes, context: context(metadata: builder(), isFinal: lastMessage), isComplete: true)
    }

    public func receive() async throws -> ApplicationProtocol.Message<Data> {
        let (type, value, context) = try await receiveTLV()
        return (content: value, metadata: TLV.Metadata(type: type, length: value.count, isComplete: true, lastMessage: context?.isFinal ?? false, other: context?.protocolMetadata ?? []))
    }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension NetworkChannel {
    public func send<Sending, Receiving, CoderType>(_ content: Sending, @ProtocolMetadataBuilder metadata builder: () -> [NWProtocolMetadata] = { [] }) async throws where ApplicationProtocol == Coder<Sending, Receiving, CoderType>, Sending: Encodable, Receiving: Decodable, CoderType: NetworkCoder {
        try await sendFramed(coderBytes(content), context: context(metadata: builder(), isFinal: false))
    }

    public func receive<Sending, Receiving, CoderType>() async throws -> ApplicationProtocol.Message<Receiving> where ApplicationProtocol == Coder<Sending, Receiving, CoderType>, Sending: Encodable, Receiving: Decodable, CoderType: NetworkCoder {
        let (value, context) = try await receiveCoded()
        guard let value = value as? Receiving else { throw NWError.posix(.EBADMSG) }
        return (content: value, metadata: Coder<Sending, Receiving, CoderType>.Metadata(isComplete: true, lastMessage: context?.isFinal ?? false, other: context?.protocolMetadata ?? []))
    }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension NetworkChannel {
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func send<T>(_ content: Data, lastMessage: Bool = false, metadata: NWProtocolFramer.Message? = nil, @ProtocolMetadataBuilder other builder: () -> [NWProtocolMetadata] = { [] }) async throws where ApplicationProtocol == Framer<T>, T: FramerProtocol {
        let items = (metadata.map { [$0] } ?? []) + builder()
        try await sendContent(content, context: NWConnection.ContentContext(identifier: "framer", isFinal: lastMessage, metadata: items), isComplete: true)
    }

    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func receive<T>() async throws -> ApplicationProtocol.Message<Data> where ApplicationProtocol == Framer<T>, T: FramerProtocol {
        let (content, context, isComplete) = try await receiveOneMessage()
        let message = context?.protocolMetadata.compactMap { $0 as? NWProtocolFramer.Message }.first ?? NWProtocolFramer.Message(definition: T.definition)
        return (content: content, metadata: Framer<T>.Metadata(framer: message, isComplete: isComplete, lastMessage: context?.isFinal ?? false, other: context?.protocolMetadata))
    }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension NetworkChannel where ApplicationProtocol: MessageProtocol {
    /// The channel's messages as they come, until it ends or fails.
    public var messages: AsyncThrowingStream<ApplicationProtocol.Message<ApplicationProtocol.ContentType>, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    while !Task.isCancelled {
                        let (content, metadata) = try await self.receiveAnyMessage()
                        let message: ApplicationProtocol.Message<ApplicationProtocol.ContentType> = try self.message(content, metadata)
                        continuation.yield(message)
                    }
                    continuation.finish()
                } catch NWError.posix(.ENODATA) {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
extension NetworkChannel where ApplicationProtocol == QUICStream {
    private func setHandlers(path: (@Sendable (NWPath) -> Void)?, viability: (@Sendable (Bool) -> Void)?, betterPath: (@Sendable (Bool) -> Void)?) {
        guard case .connection(let connection) = transport else { return }
        if let path { connection.pathUpdateHandler = path }
        if let viability { connection.viabilityUpdateHandler = viability }
        if let betterPath { connection.betterPathUpdateHandler = betterPath }
    }

    @discardableResult
    public func onPathUpdate(@_inheritActorContext _ handler: @escaping @isolated(any) @Sendable (_ connection: Self, _ newPath: NWPath) -> Void) -> Self {
        setHandlers(path: deliver(handler, to: self), viability: nil, betterPath: nil)
        return self
    }

    @discardableResult
    public func onViabilityUpdate(@_inheritActorContext _ handler: @escaping @isolated(any) @Sendable (_ connection: Self, _ newViable: Bool) -> Void) -> Self {
        setHandlers(path: nil, viability: deliver(handler, to: self), betterPath: nil)
        return self
    }

    @discardableResult
    public func onBetterPathUpdate(@_inheritActorContext _ handler: @escaping @isolated(any) @Sendable (_ connection: Self, _ newValue: Bool) -> Void) -> Self {
        setHandlers(path: nil, viability: nil, betterPath: deliver(handler, to: self))
        return self
    }
}

/// A handler of an object's events: calls the app's handler with the
/// object (held unowned) and the event, in a task.
private func deliver<Object: AnyObject, Value>(_ handler: @escaping @isolated(any) @Sendable (Object, Value) -> Void, to object: Object) -> @Sendable (Value) -> Void {
    nonisolated(unsafe) unowned let object = object
    return { value in
        Task { await handler(object, value) }
    }
}

// MARK: - withNetworkConnection

/// Runs the handler with a connection, cancelled once the handler is done.
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
nonisolated(nonsending) public func withNetworkConnection<ApplicationProtocol>(to endpoint: NWEndpoint, @ProtocolStackBuilder<ApplicationProtocol> using builder: () -> ApplicationProtocol, _ handler: (NetworkConnection<ApplicationProtocol>) async throws -> Void) async throws where ApplicationProtocol: OneToOneProtocol {
    let connection = NetworkConnection(to: endpoint, using: builder)
    defer { _ = try? connection.connection().cancel() }
    try await handler(connection)
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
nonisolated(nonsending) public func withNetworkConnection<ApplicationProtocol>(to endpoint: NWEndpoint, using builder: NWParametersBuilder<ApplicationProtocol>, _ handler: (NetworkConnection<ApplicationProtocol>) async throws -> Void) async throws where ApplicationProtocol: OneToOneProtocol {
    let connection = NetworkConnection(to: endpoint, using: builder)
    defer { _ = try? connection.connection().cancel() }
    try await handler(connection)
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
nonisolated(nonsending) public func withNetworkConnection<ApplicationProtocol>(to endpoint: NWEndpoint, @ProtocolStackBuilder<ApplicationProtocol> using builder: () -> ApplicationProtocol, _ handler: (NetworkConnection<ApplicationProtocol>) async throws -> Void) async throws where ApplicationProtocol: MultiplexProtocol {
    let connection = NetworkConnection(to: endpoint, using: builder)
    defer { if case .group(let group) = connection.transport { group.cancel() } }
    try await handler(connection)
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
nonisolated(nonsending) public func withNetworkConnection<ApplicationProtocol>(to endpoint: NWEndpoint, using builder: NWParametersBuilder<ApplicationProtocol>, _ handler: (NetworkConnection<ApplicationProtocol>) async throws -> Void) async throws where ApplicationProtocol: MultiplexProtocol {
    let connection = NetworkConnection(to: endpoint, using: builder)
    defer { if case .group(let group) = connection.transport { group.cancel() } }
    try await handler(connection)
}

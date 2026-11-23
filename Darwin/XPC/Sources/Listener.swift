import Dispatch

// XPCListener: a service's listener, which hands each peer that connects
// to the program as a request to accept (with the handlers of the session
// it becomes) or reject.

@available(macOS 14.0, macCatalyst 17.0, *)
public class XPCListener {
    public struct InitializationOptions: OptionSet, Sendable {
        public let rawValue: UInt64

        public init(rawValue: UInt64) {
            self.rawValue = rawValue
        }

        public static let none = InitializationOptions([])
        public static let inactive = InitializationOptions(rawValue: 1 << 0)
    }

    /// A peer asking to connect.
    public class IncomingSessionRequest {
        /// What the request's handler answers: the peer was accepted or
        /// rejected.
        public struct Decision {
            internal let accepted: Bool
        }

        /// The peer's session, not yet active.
        internal let peer: xpc_object_t

        internal init(peer: xpc_object_t) {
            self.peer = peer
        }

        /// The session the peer becomes, with its handlers set.
        private func session(_ configure: (XPCSession) -> Void) -> XPCSession {
            let session = XPCSession(session: peer)
            configure(session)
            return session
        }

        @preconcurrency
        public func accept(incomingMessageHandler: @escaping @Sendable (XPCDictionary) -> XPCDictionary?,
                           cancellationHandler: (@Sendable (XPCRichError) -> Void)? = nil) -> Decision {
            accept(incomingMessageHandler: incomingMessageHandler, cancellationHandler: cancellationHandler).0
        }

        @preconcurrency
        public func accept<Message: Decodable>(incomingMessageHandler: @escaping @Sendable (Message) -> (any Encodable)?,
                                               cancellationHandler: (@Sendable (XPCRichError) -> Void)? = nil) -> Decision {
            accept(incomingMessageHandler: incomingMessageHandler, cancellationHandler: cancellationHandler).0
        }

        @preconcurrency
        public func accept(incomingMessageHandler: @escaping @Sendable (XPCReceivedMessage) -> (any Encodable)?,
                           cancellationHandler: (@Sendable (XPCRichError) -> Void)? = nil) -> Decision {
            accept(incomingMessageHandler: incomingMessageHandler, cancellationHandler: cancellationHandler).0
        }

        @preconcurrency
        public func accept(incomingMessageHandler: @escaping @Sendable (XPCDictionary) -> XPCDictionary?,
                           cancellationHandler: (@Sendable (XPCRichError) -> Void)? = nil) -> (Decision, XPCSession) {
            (Decision(accepted: true), session {
                $0.setIncomingMessageHandler(incomingMessageHandler)
                if let cancellationHandler { $0.setCancellationHandler(cancellationHandler) }
            })
        }

        @preconcurrency
        public func accept<Message: Decodable>(incomingMessageHandler: @escaping @Sendable (Message) -> (any Encodable)?,
                                               cancellationHandler: (@Sendable (XPCRichError) -> Void)? = nil) -> (Decision, XPCSession) {
            (Decision(accepted: true), session {
                $0.setIncomingMessageHandler(incomingMessageHandler)
                if let cancellationHandler { $0.setCancellationHandler(cancellationHandler) }
            })
        }

        @preconcurrency
        public func accept(incomingMessageHandler: @escaping @Sendable (XPCReceivedMessage) -> (any Encodable)?,
                           cancellationHandler: (@Sendable (XPCRichError) -> Void)? = nil) -> (Decision, XPCSession) {
            (Decision(accepted: true), session {
                $0.setIncomingMessageHandler(incomingMessageHandler)
                if let cancellationHandler { $0.setCancellationHandler(cancellationHandler) }
            })
        }

        public func accept<Handler: XPCPeerHandler>(_ inactiveSessionHandler: (XPCSession) -> Handler) -> Decision
        where Handler.Input == XPCDictionary, Handler.Output == XPCDictionary {
            let session = XPCSession(session: peer)
            let handler = inactiveSessionHandler(session)
            session.setIncomingMessageHandler { handler.handleIncomingRequest($0) }
            session.setCancellationHandler { handler.handleCancellation(error: $0) }
            return Decision(accepted: true)
        }

        public func accept<Handler: XPCPeerHandler>(_ inactiveSessionHandler: (XPCSession) -> Handler) -> Decision
        where Handler.Input: Decodable, Handler.Output == any Encodable {
            let session = XPCSession(session: peer)
            let handler = inactiveSessionHandler(session)
            session.setIncomingMessageHandler { (message: Handler.Input) in handler.handleIncomingRequest(message) }
            session.setCancellationHandler { handler.handleCancellation(error: $0) }
            return Decision(accepted: true)
        }

        public func accept<Handler: XPCPeerHandler>(_ inactiveSessionHandler: (XPCSession) -> Handler) -> Decision
        where Handler.Input == XPCReceivedMessage, Handler.Output == any Encodable {
            let session = XPCSession(session: peer)
            let handler = inactiveSessionHandler(session)
            session.setIncomingMessageHandler { (message: XPCReceivedMessage) in handler.handleIncomingRequest(message) }
            session.setCancellationHandler { handler.handleCancellation(error: $0) }
            return Decision(accepted: true)
        }

        public func reject(reason: String) -> Decision {
            xpc_listener_reject_peer(peer, reason)
            return Decision(accepted: false)
        }
    }

    /// The C listener.
    internal let listener: AnyObject
    /// The queue its handlers run on.
    internal let queue: DispatchQueue?

    /// The C block that turns each peer into a request for the handler.
    private static func sessionHandler(_ handler: @escaping @Sendable (IncomingSessionRequest) -> IncomingSessionRequest.Decision)
        -> C.SessionHandler {
        { peer in _ = handler(IncomingSessionRequest(peer: peer)) }
    }

    @preconcurrency
    public init(service: String, targetQueue: DispatchQueue? = nil, options: InitializationOptions = .none,
                incomingSessionHandler: @escaping @Sendable (IncomingSessionRequest) -> IncomingSessionRequest.Decision) throws {
        guard let create = C.listenerCreate else { throw XPCRichError.failed(nil, "Listening as \(service)") }
        let handler = XPCListener.sessionHandler(incomingSessionHandler)
        let (made, error) = withErrorOut { error in
            service.withCString { create($0, targetQueue, InitializationOptions.inactive.rawValue, handler, error) }
        }
        guard let made else { throw XPCRichError.failed(error, "Listening as \(service)") }
        listener = made
        queue = targetQueue
        if !options.contains(.inactive) { try activate() }
    }

    /// A listener without a service, which peers reach through its
    /// endpoint. Where the runtime can't make one, it is a listener no
    /// peer reaches.
    @preconcurrency
    public init(targetQueue: DispatchQueue? = nil, options: InitializationOptions = .none,
                incomingSessionHandler: @escaping @Sendable (IncomingSessionRequest) -> IncomingSessionRequest.Decision) {
        let handler = XPCListener.sessionHandler(incomingSessionHandler)
        let made = C.listenerCreateAnonymous.flatMap { create in
            withErrorOut { create(targetQueue, InitializationOptions.inactive.rawValue, handler, $0) }.0
        }
        listener = made ?? xpc_null_create()
        queue = targetQueue
        if !options.contains(.inactive) { try? activate() }
    }

    public func activate() throws {
        guard let activate = C.listenerActivate else { throw XPCRichError.failed(nil, "Activating a listener") }
        let (activated, error) = withErrorOut { activate(listener, $0) }
        if !activated { throw XPCRichError.failed(error, "Activating a listener") }
    }

    public func cancel() {
        C.listenerCancel?(listener)
    }

    deinit {}
}

extension XPCListener {
    public var targetQueue: DispatchQueue? {
        queue
    }

    public func setPeerRequirement(_ requirement: XPCPeerRequirement) {
        if let object = requirement.object() { C.listenerSetPeerRequirement?(listener, object) }
    }
}

extension XPCListener {
    /// The endpoint peers connect to the listener through.
    public var endpoint: XPCEndpoint {
        XPCEndpoint(C.listenerCreateEndpoint?(listener) ?? xpc_null_create())
    }
}

/// What handles the messages of a session a listener accepted.
@available(macOS 14.0, macCatalyst 17.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
@preconcurrency
public protocol XPCPeerHandler: Sendable {
    associatedtype Input
    associatedtype Output

    func handleIncomingRequest(_: Input) -> Output?

    func handleCancellation(error: XPCRichError)
}

extension XPCPeerHandler {
    public func handleCancellation(error: XPCRichError) {}
}

extension XPCListener: CustomDebugStringConvertible {
    public var debugDescription: String {
        guard let description = C.listenerCopyDescription?(listener) else { return "<XPCListener>" }
        defer { free(description) }
        return String(cString: description)
    }
}

extension XPCListener {
    @preconcurrency
    public convenience init(service: String, targetQueue: DispatchQueue? = nil, options: InitializationOptions = .none,
                            requirement: XPCPeerRequirement,
                            incomingSessionHandler: @escaping @Sendable (IncomingSessionRequest) -> IncomingSessionRequest.Decision) throws {
        try self.init(service: service, targetQueue: targetQueue, options: options.union(.inactive),
                      incomingSessionHandler: incomingSessionHandler)
        setPeerRequirement(requirement)
        if !options.contains(.inactive) { try activate() }
    }
}

extension XPCListener: @unchecked Sendable {}

import Dispatch

// XPCSession and what goes with it: rich errors, received messages and
// peer requirements. A session wraps the C library's xpc_session_t; a
// Codable message travels as a dictionary holding its encoded object
// under one key. Where the runtime has no sessions, making one throws.

/// The key of a Codable message's contents in its dictionary.
internal let contentsKey = "contents"

// MARK: Errors

@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
public struct XPCRichError: Error, Sendable {
    private let description: String
    private let retry: Bool

    /// The error a rich error object describes.
    internal init(_ error: xpc_rich_error_t) {
        let text = xpc_rich_error_copy_description(error)
        description = text.map { String(cString: $0) } ?? "XPC error"
        free(text)
        retry = xpc_rich_error_can_retry(error)
    }

    internal init(description: String, canRetry: Bool = false) {
        self.description = description
        retry = canRetry
    }

    /// The error of an operation that failed without saying why, or of a
    /// runtime without XPC services.
    internal static func failed(_ error: xpc_rich_error_t?, _ operation: String) -> XPCRichError {
        error.map(XPCRichError.init) ?? XPCRichError(description: "\(operation) failed: XPC services are not available")
    }

    public var canRetry: Bool {
        retry
    }
}

extension XPCRichError: CustomDebugStringConvertible {
    public var debugDescription: String {
        description
    }
}

// MARK: Peer requirements

/// What a peer must be to talk to a session or listener.
public struct XPCPeerRequirement {
    private enum Kind {
        case entitlement(String)
        case entitlementValue(String, xpc_object_t)
        case team(String?)
        case platform(String?)
        case lightweight(XPCDictionary)
    }

    private let kind: Kind

    private init(_ kind: Kind) {
        self.kind = kind
    }

    /// The C library's requirement object, or nil if it makes none.
    internal func object() -> xpc_object_t? {
        func made(_ result: Unmanaged<AnyObject>?) -> xpc_object_t? {
            result.map { retainedObject($0) }
        }
        switch kind {
        case .entitlement(let name):
            return C.requirementEntitlementExists.flatMap { create in name.withCString { made(create($0, nil)) } }
        case .entitlementValue(let name, let value):
            return C.requirementEntitlementMatches.flatMap { create in name.withCString { made(create($0, value, nil)) } }
        case .team(let identifier):
            return C.requirementTeamIdentity.flatMap { create in withOptionalCString(identifier) { made(create($0, nil)) } }
        case .platform(let identifier):
            return C.requirementPlatformIdentity.flatMap { create in withOptionalCString(identifier) { made(create($0, nil)) } }
        case .lightweight(let dictionary):
            return C.requirementLWCR.flatMap { made($0(dictionary.object, nil)) }
        }
    }
}

/// Calls `body` with a string's C string, or nil.
internal func withOptionalCString<R>(_ string: String?, _ body: (UnsafePointer<CChar>?) -> R) -> R {
    guard let string else { return body(nil) }
    return string.withCString(body)
}

extension XPCPeerRequirement {
    public static func hasEntitlement(_ entitlement: String) -> XPCPeerRequirement {
        XPCPeerRequirement(.entitlement(entitlement))
    }

    public static func entitlement(_ entitlement: String, matches value: Bool) -> XPCPeerRequirement {
        XPCPeerRequirement(.entitlementValue(entitlement, xpc_bool_create(value)))
    }

    public static func entitlement(_ entitlement: String, matches value: String) -> XPCPeerRequirement {
        XPCPeerRequirement(.entitlementValue(entitlement, xpc_string_create(value)))
    }

    public static func entitlement(_ entitlement: String, matches value: Int) -> XPCPeerRequirement {
        XPCPeerRequirement(.entitlementValue(entitlement, xpc_int64_create(Int64(value))))
    }

    public static func isFromSameTeam(andMatchesSigningIdentifier: String? = nil) -> XPCPeerRequirement {
        XPCPeerRequirement(.team(andMatchesSigningIdentifier))
    }

    public static func isPlatformCode(andMatchesSigningIdentifier: String? = nil) -> XPCPeerRequirement {
        XPCPeerRequirement(.platform(andMatchesSigningIdentifier))
    }

    public init(lightweightCodeRequirements dictionary: XPCDictionary) {
        self.init(.lightweight(dictionary))
    }
}

extension XPCPeerRequirement: @unchecked Sendable {}

// MARK: Received messages

/// A message a session received: its dictionary, which may hold a Codable
/// value, and the session to reply through.
public struct XPCReceivedMessage {
    internal let dictionary: XPCDictionary
    internal let session: xpc_object_t?

    internal init(_ dictionary: XPCDictionary, session: xpc_object_t?) {
        self.dictionary = dictionary
        self.session = session
    }

    /// The Codable value the message holds, or the message itself.
    internal var contents: xpc_object_t {
        dictionary[contentsKey] ?? dictionary.object
    }

    public func decode<T: Decodable>(as type: T.Type = T.self) throws -> T {
        try decodeObject(type, from: contents)
    }

    public func reply<Message: Encodable>(_ object: Message) {
        guard let reply = try? replyDictionary(object) else { return }
        send(reply)
    }

    /// Replies later: runs `continuation` on the queue, which replies with
    /// reply(_:), and returns what tells the session not to reply now.
    @preconcurrency
    public func handoffReply(to queue: DispatchQueue, _ continuation: @escaping @Sendable () -> Void) -> (any Encodable)? {
        queue.async(execute: continuation)
        return HandedOffReply()
    }

    public var expectsReply: Bool {
        C.dictionaryExpectsReply?(dictionary.object) ?? (xpc_dictionary_get_remote_connection(dictionary.object) != nil)
    }

    /// Whether the sender waits for the reply. The C library says so only
    /// to its own callers: this is false.
    public var isSync: Bool {
        false
    }

    /// A reply made for the message, holding a value.
    internal func replyDictionary<Message: Encodable>(_ value: Message) throws -> XPCDictionary? {
        guard let made = xpc_dictionary_create_reply(dictionary.object) else { return nil }
        var reply = XPCDictionary(made)
        reply[contentsKey] = try encodeObject(value)
        return reply
    }

    /// Sends a reply through the session, or the message's connection.
    internal func send(_ reply: XPCDictionary) {
        if let session {
            _ = xpc_session_send_message(session, reply.object)
        } else if let connection = xpc_dictionary_get_remote_connection(dictionary.object) {
            xpc_connection_send_message(connection, reply.object)
        }
    }
}

extension XPCReceivedMessage {
    public func senderSatisfies(_ requirement: XPCPeerRequirement) -> Bool {
        guard let match = C.requirementMatchReceivedMessage, let object = requirement.object() else { return false }
        return match(object, dictionary.object, nil)
    }
}

/// What handoffReply returns: no reply now.
private struct HandedOffReply: Encodable {}

// MARK: Sessions

@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
public class XPCSession {
    public struct InitializationOptions: OptionSet, Sendable {
        public let rawValue: UInt64

        public init(rawValue: UInt64) {
            self.rawValue = rawValue
        }

        public static let none = InitializationOptions([])
        public static let inactive = InitializationOptions(rawValue: 1 << 0)
        public static let privileged = InitializationOptions(rawValue: 1 << 1)
    }

    /// The C session.
    internal let session: xpc_object_t

    internal init(session: xpc_object_t) {
        self.session = session
    }

    /// A session made by a C function, or the error it gave.
    private static func make(_ operation: String, _ create: (ErrorOut) -> xpc_object_t?) throws -> xpc_object_t {
        let (session, error) = withErrorOut(create)
        guard let session else { throw XPCRichError.failed(error, operation) }
        return session
    }

    /// Activates the session unless it was made inactive.
    private func start(_ options: InitializationOptions) throws {
        if !options.contains(.inactive) { try activate() }
    }

    // Each initializer makes the C session, sets its handlers, and
    // activates it unless asked not to.

    private convenience init(service name: String, mach: Bool, targetQueue: DispatchQueue?, options: InitializationOptions,
                             requirement: XPCPeerRequirement?, configure: (XPCSession) -> Void) throws {
        let create = mach ? C.sessionCreateMachService : C.sessionCreateXPCService
        guard let create else { throw XPCRichError.failed(nil, "Connecting to \(name)") }
        let flags = options.subtracting(.inactive).rawValue | XPCSession.InitializationOptions.inactive.rawValue
        let session = try XPCSession.make("Connecting to \(name)") { error in
            name.withCString { create($0, targetQueue, flags, error) }
        }
        self.init(session: session)
        if let requirement { setPeerRequirement(requirement) }
        configure(self)
        try start(options)
    }

    @preconcurrency
    public convenience init(xpcService: String, targetQueue: DispatchQueue? = nil, options: InitializationOptions = .none,
                            cancellationHandler: (@Sendable (XPCRichError) -> Void)? = nil) throws {
        try self.init(service: xpcService, mach: false, targetQueue: targetQueue, options: options, requirement: nil) {
            $0.configure(cancellationHandler)
        }
    }

    @preconcurrency
    public convenience init(xpcService: String, targetQueue: DispatchQueue? = nil, options: InitializationOptions = .none,
                            incomingMessageHandler: (@Sendable (XPCDictionary) -> XPCDictionary?)? = nil,
                            cancellationHandler: (@Sendable (XPCRichError) -> Void)? = nil) throws {
        try self.init(service: xpcService, mach: false, targetQueue: targetQueue, options: options, requirement: nil) {
            $0.configure(cancellationHandler)
            if let incomingMessageHandler { $0.setIncomingMessageHandler(incomingMessageHandler) }
        }
    }

    @preconcurrency
    public convenience init<Message: Decodable>(xpcService: String, targetQueue: DispatchQueue? = nil, options: InitializationOptions = .none,
                                                incomingMessageHandler: (@Sendable (Message) -> (any Encodable)?)? = nil,
                                                cancellationHandler: (@Sendable (XPCRichError) -> Void)? = nil) throws {
        try self.init(service: xpcService, mach: false, targetQueue: targetQueue, options: options, requirement: nil) {
            $0.configure(cancellationHandler)
            if let incomingMessageHandler { $0.setIncomingMessageHandler(incomingMessageHandler) }
        }
    }

    @preconcurrency
    public convenience init(xpcService: String, targetQueue: DispatchQueue? = nil, options: InitializationOptions = .none,
                            incomingMessageHandler: (@Sendable (XPCReceivedMessage) -> (any Encodable)?)? = nil,
                            cancellationHandler: (@Sendable (XPCRichError) -> Void)? = nil) throws {
        try self.init(service: xpcService, mach: false, targetQueue: targetQueue, options: options, requirement: nil) {
            $0.configure(cancellationHandler)
            if let incomingMessageHandler { $0.setIncomingMessageHandler(incomingMessageHandler) }
        }
    }

    @preconcurrency
    public convenience init(machService: String, targetQueue: DispatchQueue? = nil, options: InitializationOptions = .none,
                            cancellationHandler: (@Sendable (XPCRichError) -> Void)? = nil) throws {
        try self.init(service: machService, mach: true, targetQueue: targetQueue, options: options, requirement: nil) {
            $0.configure(cancellationHandler)
        }
    }

    @preconcurrency
    public convenience init(machService: String, targetQueue: DispatchQueue? = nil, options: InitializationOptions = .none,
                            incomingMessageHandler: (@Sendable (XPCDictionary) -> XPCDictionary?)? = nil,
                            cancellationHandler: (@Sendable (XPCRichError) -> Void)? = nil) throws {
        try self.init(service: machService, mach: true, targetQueue: targetQueue, options: options, requirement: nil) {
            $0.configure(cancellationHandler)
            if let incomingMessageHandler { $0.setIncomingMessageHandler(incomingMessageHandler) }
        }
    }

    @preconcurrency
    public convenience init<Message: Decodable>(machService: String, targetQueue: DispatchQueue? = nil, options: InitializationOptions = .none,
                                                incomingMessageHandler: (@Sendable (Message) -> (any Encodable)?)? = nil,
                                                cancellationHandler: (@Sendable (XPCRichError) -> Void)? = nil) throws {
        try self.init(service: machService, mach: true, targetQueue: targetQueue, options: options, requirement: nil) {
            $0.configure(cancellationHandler)
            if let incomingMessageHandler { $0.setIncomingMessageHandler(incomingMessageHandler) }
        }
    }

    @preconcurrency
    public convenience init(machService: String, targetQueue: DispatchQueue? = nil, options: InitializationOptions = .none,
                            incomingMessageHandler: (@Sendable (XPCReceivedMessage) -> (any Encodable)?)? = nil,
                            cancellationHandler: (@Sendable (XPCRichError) -> Void)? = nil) throws {
        try self.init(service: machService, mach: true, targetQueue: targetQueue, options: options, requirement: nil) {
            $0.configure(cancellationHandler)
            if let incomingMessageHandler { $0.setIncomingMessageHandler(incomingMessageHandler) }
        }
    }

    /// Sets the cancellation handler, if there is one.
    private func configure(_ cancellationHandler: (@Sendable (XPCRichError) -> Void)?) {
        if let cancellationHandler { setCancellationHandler(cancellationHandler) }
    }

    // MARK: Handlers

    @preconcurrency
    public func setIncomingMessageHandler(_ incomingMessageHandler: @escaping @Sendable (XPCDictionary) -> XPCDictionary?) {
        let session = self.session
        xpc_session_set_incoming_message_handler(session) { message in
            let received = XPCReceivedMessage(XPCDictionary(message), session: session)
            guard let reply = incomingMessageHandler(received.dictionary), let made = xpc_dictionary_create_reply(message) else { return }
            reply.copy(into: XPCDictionary(made))
            received.send(XPCDictionary(made))
        }
    }

    @preconcurrency
    public func setIncomingMessageHandler<Message: Decodable>(_ incomingMessageHandler: @escaping @Sendable (Message) -> (any Encodable)?) {
        setIncomingMessageHandler { (received: XPCReceivedMessage) -> (any Encodable)? in
            guard let message = try? received.decode(as: Message.self) else { return nil }
            return incomingMessageHandler(message)
        }
    }

    @preconcurrency
    public func setIncomingMessageHandler(_ incomingMessageHandler: @escaping @Sendable (XPCReceivedMessage) -> (any Encodable)?) {
        let session = self.session
        xpc_session_set_incoming_message_handler(session) { message in
            let received = XPCReceivedMessage(XPCDictionary(message), session: session)
            guard let reply = incomingMessageHandler(received), !(reply is HandedOffReply), received.expectsReply else { return }
            if let dictionary = try? received.replyDictionary(reply) { received.send(dictionary) }
        }
    }

    @preconcurrency
    public func setCancellationHandler(_ cancellationHandler: @escaping @Sendable (XPCRichError) -> Void) {
        xpc_session_set_cancel_handler(session) { error in
            cancellationHandler(XPCRichError(error))
        }
    }

    public func setTargetQueue(_ targetQueue: DispatchQueue) {
        xpc_session_set_target_queue(session, targetQueue)
    }

    // MARK: Life

    public func activate() throws {
        guard let activate = C.sessionActivate else { throw XPCRichError.failed(nil, "Activating a session") }
        let (activated, error) = withErrorOut { activate(session, $0) }
        if !activated { throw XPCRichError.failed(error, "Activating a session") }
    }

    /// Cancels the session. The reason is for the caller's own logs: the
    /// C library takes none.
    public func cancel(reason: String) {
        xpc_session_cancel(session)
    }

    // MARK: Sending

    /// A message holding a Codable value.
    private func message<Message: Encodable>(_ value: Message) throws -> XPCDictionary {
        var message = XPCDictionary()
        message[contentsKey] = try encodeObject(value)
        return message
    }

    public func send(message: XPCDictionary) throws {
        guard let send = C.sessionSendMessage else { throw XPCRichError.failed(nil, "Sending a message") }
        if let error = send(session, message.object) {
            throw XPCRichError(retainedObject(error))
        }
    }

    public func send<Message: Encodable>(_ message: Message) throws {
        try send(message: self.message(message))
    }

    public func sendSync(message: XPCDictionary) throws -> XPCDictionary {
        guard let send = C.sessionSendMessageWithReplySync else { throw XPCRichError.failed(nil, "Sending a message") }
        let (reply, error) = withErrorOut { send(session, message.object, $0) }
        guard let reply else { throw XPCRichError.failed(error, "Sending a message") }
        return XPCDictionary(retainedObject(reply))
    }

    public func sendSync<Message: Encodable, Reply: Decodable>(_ message: Message) throws -> Reply {
        try sendSync(message).decode(as: Reply.self)
    }

    public func sendSync<Message: Encodable>(_ message: Message) throws -> XPCReceivedMessage {
        XPCReceivedMessage(try sendSync(message: self.message(message)), session: session)
    }

    @preconcurrency
    public func send(message: XPCDictionary, replyHandler: @escaping @Sendable (Result<XPCDictionary, XPCRichError>) -> Void) {
        guard let send = C.sessionSendMessageWithReplyAsync else {
            replyHandler(.failure(.failed(nil, "Sending a message")))
            return
        }
        send(session, message.object) { reply, error in
            if let reply {
                replyHandler(.success(XPCDictionary(reply)))
            } else {
                replyHandler(.failure(.failed(error, "Sending a message")))
            }
        }
    }

    @preconcurrency
    public func send<Message: Encodable, Reply: Decodable>(_ message: Message,
                                                            replyHandler: @escaping @Sendable (Result<Reply, any Error>) -> Void) throws {
        send(message: try self.message(message)) { [session] result in
            replyHandler(Result {
                try XPCReceivedMessage(result.get(), session: session).decode(as: Reply.self)
            })
        }
    }

    @preconcurrency
    public func send<Message: Encodable>(_ message: Message,
                                         replyHandler: @escaping @Sendable (Result<XPCReceivedMessage, XPCRichError>) -> Void) throws {
        send(message: try self.message(message)) { [session] result in
            replyHandler(result.map { XPCReceivedMessage($0, session: session) })
        }
    }

    deinit {}
}

extension XPCSession {
    /// A session to the listener an endpoint names.
    private convenience init(endpoint: XPCEndpoint, targetQueue: DispatchQueue?, options: InitializationOptions,
                             configure: (XPCSession) -> Void) throws {
        guard let create = C.sessionCreateEndpoint else { throw XPCRichError.failed(nil, "Connecting to an endpoint") }
        let flags = options.rawValue | InitializationOptions.inactive.rawValue
        let session = try XPCSession.make("Connecting to an endpoint") { create(endpoint._endpoint, targetQueue, flags, $0) }
        self.init(session: session)
        configure(self)
        try start(options)
    }

    @preconcurrency
    public convenience init(endpoint: XPCEndpoint, targetQueue: DispatchQueue? = nil, options: InitializationOptions = .none,
                            cancellationHandler: (@Sendable (XPCRichError) -> Void)? = nil) throws {
        try self.init(endpoint: endpoint, targetQueue: targetQueue, options: options) { $0.configure(cancellationHandler) }
    }

    @preconcurrency
    public convenience init(endpoint: XPCEndpoint, targetQueue: DispatchQueue? = nil, options: InitializationOptions = .none,
                            incomingMessageHandler: (@Sendable (XPCDictionary) -> XPCDictionary?)? = nil,
                            cancellationHandler: (@Sendable (XPCRichError) -> Void)? = nil) throws {
        try self.init(endpoint: endpoint, targetQueue: targetQueue, options: options) {
            $0.configure(cancellationHandler)
            if let incomingMessageHandler { $0.setIncomingMessageHandler(incomingMessageHandler) }
        }
    }

    @preconcurrency
    public convenience init<Message: Decodable>(endpoint: XPCEndpoint, targetQueue: DispatchQueue? = nil, options: InitializationOptions = .none,
                                                incomingMessageHandler: (@Sendable (Message) -> (any Encodable)?)? = nil,
                                                cancellationHandler: (@Sendable (XPCRichError) -> Void)? = nil) throws {
        try self.init(endpoint: endpoint, targetQueue: targetQueue, options: options) {
            $0.configure(cancellationHandler)
            if let incomingMessageHandler { $0.setIncomingMessageHandler(incomingMessageHandler) }
        }
    }

    @preconcurrency
    public convenience init(endpoint: XPCEndpoint, targetQueue: DispatchQueue? = nil, options: InitializationOptions = .none,
                            incomingMessageHandler: (@Sendable (XPCReceivedMessage) -> (any Encodable)?)? = nil,
                            cancellationHandler: (@Sendable (XPCRichError) -> Void)? = nil) throws {
        try self.init(endpoint: endpoint, targetQueue: targetQueue, options: options) {
            $0.configure(cancellationHandler)
            if let incomingMessageHandler { $0.setIncomingMessageHandler(incomingMessageHandler) }
        }
    }
}

extension XPCSession {
    public func setPeerRequirement(_ requirement: XPCPeerRequirement) {
        if let object = requirement.object() { C.sessionSetPeerRequirement?(session, object) }
    }
}

extension XPCSession: CustomDebugStringConvertible {
    public var debugDescription: String {
        guard let description = xpc_session_copy_description(session) else { return "<XPCSession>" }
        defer { free(description) }
        return String(cString: description)
    }
}

extension XPCSession {
    @preconcurrency
    public convenience init(xpcService: String, targetQueue: DispatchQueue? = nil, options: InitializationOptions = .none,
                            requirement: XPCPeerRequirement, cancellationHandler: (@Sendable (XPCRichError) -> Void)? = nil) throws {
        try self.init(service: xpcService, mach: false, targetQueue: targetQueue, options: options, requirement: requirement) {
            $0.configure(cancellationHandler)
        }
    }

    @preconcurrency
    public convenience init(xpcService: String, targetQueue: DispatchQueue? = nil, options: InitializationOptions = .none,
                            requirement: XPCPeerRequirement,
                            incomingMessageHandler: (@Sendable (XPCDictionary) -> XPCDictionary?)? = nil,
                            cancellationHandler: (@Sendable (XPCRichError) -> Void)? = nil) throws {
        try self.init(service: xpcService, mach: false, targetQueue: targetQueue, options: options, requirement: requirement) {
            $0.configure(cancellationHandler)
            if let incomingMessageHandler { $0.setIncomingMessageHandler(incomingMessageHandler) }
        }
    }

    @preconcurrency
    public convenience init<Message: Decodable>(xpcService: String, targetQueue: DispatchQueue? = nil, options: InitializationOptions = .none,
                                                requirement: XPCPeerRequirement,
                                                incomingMessageHandler: (@Sendable (Message) -> (any Encodable)?)? = nil,
                                                cancellationHandler: (@Sendable (XPCRichError) -> Void)? = nil) throws {
        try self.init(service: xpcService, mach: false, targetQueue: targetQueue, options: options, requirement: requirement) {
            $0.configure(cancellationHandler)
            if let incomingMessageHandler { $0.setIncomingMessageHandler(incomingMessageHandler) }
        }
    }

    @preconcurrency
    public convenience init(xpcService: String, targetQueue: DispatchQueue? = nil, options: InitializationOptions = .none,
                            requirement: XPCPeerRequirement,
                            incomingMessageHandler: (@Sendable (XPCReceivedMessage) -> (any Encodable)?)? = nil,
                            cancellationHandler: (@Sendable (XPCRichError) -> Void)? = nil) throws {
        try self.init(service: xpcService, mach: false, targetQueue: targetQueue, options: options, requirement: requirement) {
            $0.configure(cancellationHandler)
            if let incomingMessageHandler { $0.setIncomingMessageHandler(incomingMessageHandler) }
        }
    }

    @preconcurrency
    public convenience init(machService: String, targetQueue: DispatchQueue? = nil, options: InitializationOptions = .none,
                            requirement: XPCPeerRequirement, cancellationHandler: (@Sendable (XPCRichError) -> Void)? = nil) throws {
        try self.init(service: machService, mach: true, targetQueue: targetQueue, options: options, requirement: requirement) {
            $0.configure(cancellationHandler)
        }
    }

    @preconcurrency
    public convenience init(machService: String, targetQueue: DispatchQueue? = nil, options: InitializationOptions = .none,
                            requirement: XPCPeerRequirement,
                            incomingMessageHandler: (@Sendable (XPCDictionary) -> XPCDictionary?)? = nil,
                            cancellationHandler: (@Sendable (XPCRichError) -> Void)? = nil) throws {
        try self.init(service: machService, mach: true, targetQueue: targetQueue, options: options, requirement: requirement) {
            $0.configure(cancellationHandler)
            if let incomingMessageHandler { $0.setIncomingMessageHandler(incomingMessageHandler) }
        }
    }

    @preconcurrency
    public convenience init<Message: Decodable>(machService: String, targetQueue: DispatchQueue? = nil, options: InitializationOptions = .none,
                                                requirement: XPCPeerRequirement,
                                                incomingMessageHandler: (@Sendable (Message) -> (any Encodable)?)? = nil,
                                                cancellationHandler: (@Sendable (XPCRichError) -> Void)? = nil) throws {
        try self.init(service: machService, mach: true, targetQueue: targetQueue, options: options, requirement: requirement) {
            $0.configure(cancellationHandler)
            if let incomingMessageHandler { $0.setIncomingMessageHandler(incomingMessageHandler) }
        }
    }

    @preconcurrency
    public convenience init(machService: String, targetQueue: DispatchQueue? = nil, options: InitializationOptions = .none,
                            requirement: XPCPeerRequirement,
                            incomingMessageHandler: (@Sendable (XPCReceivedMessage) -> (any Encodable)?)? = nil,
                            cancellationHandler: (@Sendable (XPCRichError) -> Void)? = nil) throws {
        try self.init(service: machService, mach: true, targetQueue: targetQueue, options: options, requirement: requirement) {
            $0.configure(cancellationHandler)
            if let incomingMessageHandler { $0.setIncomingMessageHandler(incomingMessageHandler) }
        }
    }
}

extension XPCSession: @unchecked Sendable {}

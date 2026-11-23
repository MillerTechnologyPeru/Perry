import Darwin
import Dispatch

// The C functions of sessions, listeners, peer requirements and replies,
// looked up when first used: a runtime without XPC services (Perry's
// keeps XPC objects in the process and has no connections) lacks them,
// and the Swift API reports that as an error instead of calling nothing.
// The Swift wrappers of these functions the SDK declares are here too.

/// A function of the process's libraries, by name.
private func lookup<F>(_ name: String, as type: F.Type) -> F? {
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
    return unsafeBitCast(symbol, to: F.self)
}

/// Where a C function hands back a rich error it made (+1).
internal typealias ErrorOut = UnsafeMutablePointer<Unmanaged<AnyObject>?>

/// Calls `body` with room for an error, returning the error it left.
internal func withErrorOut<R>(_ body: (ErrorOut) -> R) -> (R, xpc_rich_error_t?) {
    var error: Unmanaged<AnyObject>?
    let result = body(&error)
    return (result, error.map { retainedObject($0) })
}

internal enum C {
    typealias Object = xpc_object_t
    typealias MessageHandler = @convention(block) (Object) -> Void
    typealias ErrorHandler = @convention(block) (Object) -> Void
    typealias ReplyHandler = @convention(block) (Object?, Object?) -> Void
    typealias SessionHandler = @convention(block) (Object) -> Void

    static let sessionCreateXPCService = lookup("xpc_session_create_xpc_service",
        as: (@convention(c) (UnsafePointer<CChar>, DispatchQueue?, UInt64, ErrorOut?) -> Object?).self)
    static let sessionCreateMachService = lookup("xpc_session_create_mach_service",
        as: (@convention(c) (UnsafePointer<CChar>, DispatchQueue?, UInt64, ErrorOut?) -> Object?).self)
    static let sessionCreateEndpoint = lookup("xpc_session_create_xpc_endpoint",
        as: (@convention(c) (Object, DispatchQueue?, UInt64, ErrorOut?) -> Object?).self)
    static let sessionSetIncomingMessageHandler = lookup("xpc_session_set_incoming_message_handler",
        as: (@convention(c) (Object, MessageHandler) -> Void).self)
    static let sessionSetCancelHandler = lookup("xpc_session_set_cancel_handler",
        as: (@convention(c) (Object, ErrorHandler) -> Void).self)
    static let sessionSetTargetQueue = lookup("xpc_session_set_target_queue",
        as: (@convention(c) (Object, DispatchQueue?) -> Void).self)
    static let sessionActivate = lookup("xpc_session_activate",
        as: (@convention(c) (Object, ErrorOut?) -> Bool).self)
    static let sessionCancel = lookup("xpc_session_cancel",
        as: (@convention(c) (Object) -> Void).self)
    static let sessionSendMessage = lookup("xpc_session_send_message",
        as: (@convention(c) (Object, Object) -> Unmanaged<AnyObject>?).self)
    static let sessionSendMessageWithReplySync = lookup("xpc_session_send_message_with_reply_sync",
        as: (@convention(c) (Object, Object, ErrorOut?) -> Unmanaged<AnyObject>?).self)
    static let sessionSendMessageWithReplyAsync = lookup("xpc_session_send_message_with_reply_async",
        as: (@convention(c) (Object, Object, ReplyHandler) -> Void).self)
    static let sessionCopyDescription = lookup("xpc_session_copy_description",
        as: (@convention(c) (Object) -> UnsafeMutablePointer<CChar>?).self)
    static let sessionSetPeerRequirement = lookup("xpc_session_set_peer_requirement",
        as: (@convention(c) (Object, Object) -> Void).self)

    static let listenerCreate = lookup("xpc_listener_create",
        as: (@convention(c) (UnsafePointer<CChar>, DispatchQueue?, UInt64, SessionHandler, ErrorOut?) -> AnyObject?).self)
    static let listenerCreateAnonymous = lookup("xpc_listener_create_anonymous",
        as: (@convention(c) (DispatchQueue?, UInt64, SessionHandler, ErrorOut?) -> AnyObject?).self)
    static let listenerCreateEndpoint = lookup("xpc_listener_create_endpoint",
        as: (@convention(c) (AnyObject) -> Object?).self)
    static let listenerActivate = lookup("xpc_listener_activate",
        as: (@convention(c) (AnyObject, ErrorOut?) -> Bool).self)
    static let listenerCancel = lookup("xpc_listener_cancel",
        as: (@convention(c) (AnyObject) -> Void).self)
    static let listenerRejectPeer = lookup("xpc_listener_reject_peer",
        as: (@convention(c) (Object, UnsafePointer<CChar>) -> Void).self)
    static let listenerCopyDescription = lookup("xpc_listener_copy_description",
        as: (@convention(c) (AnyObject) -> UnsafeMutablePointer<CChar>?).self)
    static let listenerSetPeerRequirement = lookup("xpc_listener_set_peer_requirement",
        as: (@convention(c) (AnyObject, Object) -> Void).self)

    static let requirementEntitlementExists = lookup("xpc_peer_requirement_create_entitlement_exists",
        as: (@convention(c) (UnsafePointer<CChar>, ErrorOut?) -> Unmanaged<AnyObject>?).self)
    static let requirementEntitlementMatches = lookup("xpc_peer_requirement_create_entitlement_matches_value",
        as: (@convention(c) (UnsafePointer<CChar>, Object, ErrorOut?) -> Unmanaged<AnyObject>?).self)
    static let requirementTeamIdentity = lookup("xpc_peer_requirement_create_team_identity",
        as: (@convention(c) (UnsafePointer<CChar>?, ErrorOut?) -> Unmanaged<AnyObject>?).self)
    static let requirementPlatformIdentity = lookup("xpc_peer_requirement_create_platform_identity",
        as: (@convention(c) (UnsafePointer<CChar>?, ErrorOut?) -> Unmanaged<AnyObject>?).self)
    static let requirementLWCR = lookup("xpc_peer_requirement_create_lwcr",
        as: (@convention(c) (Object, ErrorOut?) -> Unmanaged<AnyObject>?).self)
    static let requirementMatchReceivedMessage = lookup("xpc_peer_requirement_match_received_message",
        as: (@convention(c) (Object, Object, ErrorOut?) -> Bool).self)

    static let dictionaryExpectsReply = lookup("xpc_dictionary_expects_reply",
        as: (@convention(c) (Object) -> Bool).self)
}

// MARK: The SDK's Swift wrappers

/// The session flags of xpc_session_create_xpc_service and
/// xpc_session_create_mach_service.
public struct xpc_session_create_flags_t: OptionSet, @unchecked Sendable {
    private let value: UInt64

    public var rawValue: UInt64 { value }

    public init(rawValue: UInt64) {
        value = rawValue
    }

    public static let none = xpc_session_create_flags_t(rawValue: 0)
    public static let privileged = xpc_session_create_flags_t(rawValue: 1 << 1)
    public static let inactive = xpc_session_create_flags_t(rawValue: 1 << 0)
}

public typealias xpc_session_t = OS_xpc_object
public typealias xpc_session_cancel_handler_t = (xpc_rich_error_t) -> Void
public typealias xpc_session_incoming_message_handler_t = (xpc_object_t) -> Void
public typealias xpc_session_reply_handler_t = (xpc_object_t?, xpc_rich_error_t?) -> Void

/// Stores a C function's error where the Swift caller asked for it.
private func hand(_ error: xpc_rich_error_t?, to errorOut: AutoreleasingUnsafeMutablePointer<xpc_rich_error_t?>?) {
    if let error, let errorOut { errorOut.pointee = error }
}

public func xpc_session_copy_description(_ session: any OS_xpc_object) -> UnsafeMutablePointer<CChar>? {
    C.sessionCopyDescription?(session)
}

public func xpc_session_create_xpc_service(_ name: UnsafePointer<CChar>, _ target_queue: dispatch_queue_t?,
                                           _ flags: xpc_session_create_flags_t,
                                           _ error_out: AutoreleasingUnsafeMutablePointer<xpc_rich_error_t?>?) -> (any OS_xpc_object)? {
    guard let create = C.sessionCreateXPCService else { return nil }
    let (session, error) = withErrorOut { create(name, target_queue, flags.rawValue, $0) }
    hand(error, to: error_out)
    return session
}

public func xpc_session_create_mach_service(_ mach_service: UnsafePointer<CChar>, _ target_queue: dispatch_queue_t?,
                                            _ flags: xpc_session_create_flags_t,
                                            _ error_out: AutoreleasingUnsafeMutablePointer<xpc_rich_error_t?>?) -> (any OS_xpc_object)? {
    guard let create = C.sessionCreateMachService else { return nil }
    let (session, error) = withErrorOut { create(mach_service, target_queue, flags.rawValue, $0) }
    hand(error, to: error_out)
    return session
}

public func xpc_session_set_incoming_message_handler(_ session: any OS_xpc_object,
                                                     _ handler: @escaping xpc_session_incoming_message_handler_t) {
    C.sessionSetIncomingMessageHandler?(session, handler)
}

public func xpc_session_set_cancel_handler(_ session: any OS_xpc_object, _ cancel_handler: @escaping xpc_session_cancel_handler_t) {
    C.sessionSetCancelHandler?(session, cancel_handler)
}

public func xpc_session_set_target_queue(_ session: any OS_xpc_object, _ target_queue: dispatch_queue_t?) {
    C.sessionSetTargetQueue?(session, target_queue)
}

public func xpc_session_activate(_ session: any OS_xpc_object,
                                 _ error_out: AutoreleasingUnsafeMutablePointer<xpc_rich_error_t?>?) -> Bool {
    guard let activate = C.sessionActivate else { return false }
    let (activated, error) = withErrorOut { activate(session, $0) }
    hand(error, to: error_out)
    return activated
}

public func xpc_session_cancel(_ session: any OS_xpc_object) {
    C.sessionCancel?(session)
}

public func xpc_session_send_message(_ session: any OS_xpc_object, _ message: xpc_object_t) -> xpc_rich_error_t? {
    guard let send = C.sessionSendMessage else { return nil }
    return send(session, message).map { retainedObject($0) }
}

public func xpc_session_send_message_with_reply_sync(_ session: any OS_xpc_object, _ message: xpc_object_t,
                                                     _ error_out: AutoreleasingUnsafeMutablePointer<xpc_rich_error_t?>?) -> xpc_object_t? {
    guard let send = C.sessionSendMessageWithReplySync else { return nil }
    let (reply, error) = withErrorOut { send(session, message, $0) }
    hand(error, to: error_out)
    return reply.map { retainedObject($0) }
}

public func xpc_session_send_message_with_reply_async(_ session: any OS_xpc_object, _ message: xpc_object_t,
                                                      _ reply_handler: @escaping xpc_session_reply_handler_t) {
    C.sessionSendMessageWithReplyAsync?(session, message, reply_handler)
}

public typealias xpc_listener_t = OS_xpc_listener

/// The flags of xpc_listener_create, which the Swift API takes as
/// XPCListener.InitializationOptions.
public struct xpc_listener_create_flags_t {}

public typealias xpc_listener_incoming_session_handler_t = (any OS_xpc_object) -> Void

public func xpc_listener_copy_description(_ listener: xpc_listener_t) -> UnsafeMutablePointer<CChar>? {
    C.listenerCopyDescription?(listener)
}

public func xpc_listener_create(_ service: UnsafePointer<CChar>, _ target_queue: dispatch_queue_t?,
                                _ flags: xpc_listener_create_flags_t,
                                _ incoming_session_handler: @escaping xpc_listener_incoming_session_handler_t,
                                _ error_out: AutoreleasingUnsafeMutablePointer<xpc_rich_error_t?>?) -> xpc_listener_t? {
    guard let create = C.listenerCreate else { return nil }
    let (listener, error) = withErrorOut { create(service, target_queue, 0, incoming_session_handler, $0) }
    hand(error, to: error_out)
    return listener.map { unsafeBitCast($0, to: xpc_listener_t.self) }
}

public func xpc_listener_activate(_ listener: xpc_listener_t,
                                  _ error_out: AutoreleasingUnsafeMutablePointer<xpc_rich_error_t?>?) -> Bool {
    guard let activate = C.listenerActivate else { return false }
    let (activated, error) = withErrorOut { activate(listener, $0) }
    hand(error, to: error_out)
    return activated
}

public func xpc_listener_cancel(_ listener: xpc_listener_t) {
    C.listenerCancel?(listener)
}

public func xpc_listener_reject_peer(_ peer: any OS_xpc_object, _ reason: UnsafePointer<CChar>) {
    C.listenerRejectPeer?(peer, reason)
}

/// The object a C function returned retained. An XPC object's existential
/// is its pointer alone, so no conformance check is needed.
internal func retainedObject(_ object: Unmanaged<AnyObject>) -> xpc_object_t {
    unsafeBitCast(object.takeRetainedValue(), to: xpc_object_t.self)
}

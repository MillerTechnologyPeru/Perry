import Glibc
import PerryObjCInterop

// Content contexts: what a send or a receive carries besides its bytes (an
// identifier, whether it is the last message, protocol metadata). The
// default message, final send and default stream contexts are data
// symbols, and so is the completion that marks a send idempotent.

final class ContextState: NWState {
    let identifier: HeldCString
    let isShared: Bool
    var expirationMilliseconds: UInt64 = 0
    var relativePriority = 0.5
    var isFinal = false
    var antecedent: UnsafeMutableRawPointer?
    /// Metadata (+1 each), one per protocol definition.
    var metadata: [UnsafeMutableRawPointer] = []
    /// For a group's received messages: who sent it and where to, and
    /// which socket it came on, for replies.
    var remoteAddress: SocketAddress?
    var localAddress: SocketAddress?
    weak var group: GroupState?

    init(identifier: String, isShared: Bool = false, isFinal: Bool = false) {
        self.identifier = HeldCString(identifier)
        self.isShared = isShared
        self.isFinal = isFinal
    }

    deinit {
        ObjCRuntime.release(antecedent)
        metadata.forEach { ObjCRuntime.release($0) }
    }

    /// The metadata for a definition (+0).
    func metadata(for definition: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        metadata.first { nw_protocol_definition_is_equal(Metadata.state($0)?.definition, definition) }
    }

    func metadata(of kind: ProtocolKind) -> MetadataState? {
        metadata.lazy.compactMap { Metadata.state($0) }.first { $0.kind == kind }
    }

    func setMetadata(_ object: UnsafeMutableRawPointer) {
        guard let definition = Metadata.state(object)?.definition else { return }
        let held = ObjCRuntime.retain(object)!
        if let index = metadata.firstIndex(where: { nw_protocol_definition_is_equal(Metadata.state($0)?.definition, definition) }) {
            ObjCRuntime.release(metadata[index])
            metadata[index] = held
        } else {
            metadata.append(held)
        }
    }
}

@ObjCClass("OS_nw_content_context")
open class NWContentContextObject: NWObject {}

enum Contexts {
    static func state(_ context: UnsafeMutableRawPointer?) -> ContextState? { NWObjects.state(context, ContextState.self) }

    /// A new context (+1).
    static func make(_ state: ContextState) -> UnsafeMutableRawPointer { NWObjects.make(NWContentContextObject.objCClass, state) }

    /// A received message's context (+1), with its metadata.
    static func message(_ identifier: String, metadata: [UnsafeMutableRawPointer] = [], isFinal: Bool = false) -> UnsafeMutableRawPointer {
        let state = ContextState(identifier: identifier, isFinal: isFinal)
        for object in metadata { state.setMetadata(object) }
        return make(state)
    }

    static var defaultMessage: UnsafeMutableRawPointer { SharedContexts._nw_content_context_default_message }
    static var finalSend: UnsafeMutableRawPointer { SharedContexts._nw_content_context_final_send }
    static var defaultStream: UnsafeMutableRawPointer { SharedContexts._nw_content_context_default_stream }
}

@ObjCConstants
enum SharedContexts {
    nonisolated(unsafe) static let _nw_content_context_default_message = Contexts.make(ContextState(identifier: "default_message", isShared: true))
    nonisolated(unsafe) static let _nw_content_context_final_send = Contexts.make(ContextState(identifier: "final_send", isShared: true, isFinal: true))
    nonisolated(unsafe) static let _nw_content_context_default_stream = Contexts.make(ContextState(identifier: "default_stream", isShared: true))
    /// NW_CONNECTION_SEND_IDEMPOTENT_CONTENT: a completion that is never
    /// called, told apart by its address.
    nonisolated(unsafe) static let _nw_connection_send_idempotent_content = BlocksRuntime.block(invoke: unsafeBitCast(ignoreError, to: UnsafeRawPointer.self))
}

private let ignoreError: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void = { _, _ in }

@c(_nw_content_context_create)
public func nw_content_context_create(_ identifier: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    Contexts.make(ContextState(identifier: identifier.map { String(cString: $0) } ?? ""))
}

@c(_nw_content_context_get_identifier)
public func nw_content_context_get_identifier(_ context: UnsafeMutableRawPointer?) -> UnsafePointer<CChar>? {
    Contexts.state(context)?.identifier.value
}

@c(_nw_content_context_get_is_final)
public func nw_content_context_get_is_final(_ context: UnsafeMutableRawPointer?) -> Bool { Contexts.state(context)?.isFinal ?? false }

/// The shared contexts don't change.
@c(_nw_content_context_set_is_final)
public func nw_content_context_set_is_final(_ context: UnsafeMutableRawPointer?, _ isFinal: Bool) {
    guard let state = Contexts.state(context), !state.isShared else { return }
    state.isFinal = isFinal
}

@c(_nw_content_context_get_expiration_milliseconds)
public func nw_content_context_get_expiration_milliseconds(_ context: UnsafeMutableRawPointer?) -> UInt64 {
    Contexts.state(context)?.expirationMilliseconds ?? 0
}

@c(_nw_content_context_set_expiration_milliseconds)
public func nw_content_context_set_expiration_milliseconds(_ context: UnsafeMutableRawPointer?, _ value: UInt64) {
    guard let state = Contexts.state(context), !state.isShared else { return }
    state.expirationMilliseconds = value
}

@c(_nw_content_context_get_relative_priority)
public func nw_content_context_get_relative_priority(_ context: UnsafeMutableRawPointer?) -> Double {
    Contexts.state(context)?.relativePriority ?? 0.5
}

@c(_nw_content_context_set_relative_priority)
public func nw_content_context_set_relative_priority(_ context: UnsafeMutableRawPointer?, _ value: Double) {
    guard let state = Contexts.state(context), !state.isShared else { return }
    state.relativePriority = value
}

@c(_nw_content_context_copy_antecedent)
public func nw_content_context_copy_antecedent(_ context: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    ObjCRuntime.retain(Contexts.state(context)?.antecedent)
}

@c(_nw_content_context_set_antecedent)
public func nw_content_context_set_antecedent(_ context: UnsafeMutableRawPointer?, _ antecedent: UnsafeMutableRawPointer?) {
    guard let state = Contexts.state(context), !state.isShared else { return }
    let held = ObjCRuntime.retain(antecedent)
    ObjCRuntime.release(state.antecedent)
    state.antecedent = held
}

@c(_nw_content_context_set_metadata_for_protocol)
public func nw_content_context_set_metadata_for_protocol(_ context: UnsafeMutableRawPointer?, _ metadata: UnsafeMutableRawPointer?) {
    guard let state = Contexts.state(context), !state.isShared, let metadata else { return }
    state.setMetadata(metadata)
}

@c(_nw_content_context_copy_protocol_metadata)
public func nw_content_context_copy_protocol_metadata(_ context: UnsafeMutableRawPointer?,
                                                      _ definition: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    ObjCRuntime.retain(Contexts.state(context)?.metadata(for: definition))
}

@c(_nw_content_context_foreach_protocol_metadata)
public func nw_content_context_foreach_protocol_metadata(_ context: UnsafeMutableRawPointer?, _ block: UnsafeMutableRawPointer?) {
    guard let state = Contexts.state(context), let block = ObjCBlock.from(block) else { return }
    for metadata in state.metadata { block.call(Metadata.state(metadata)?.definition, metadata) }
}

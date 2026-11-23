import Glibc
import PerryObjCInterop

// Framers: protocols the program writes, with a start handler (from the
// definition) and the input, output, wakeup, stop and cleanup handlers it
// sets on each connection's nw_framer_t. Handlers run on the connection's
// queue; inside them the program parses what the layer below delivered and
// delivers messages up, or parses what the program sent and writes it
// down. A framer's messages carry framer-message metadata.

/// nw_framer_start_result_t.
private enum StartResult {
    static let ready: Int32 = 1
    static let willMarkReady: Int32 = 2
}

final class FramerInstanceState: NWState {
    weak var layer: FramerLayer?
    var inputHandler: ObjCBlock?
    var outputHandler: ObjCBlock?
    var wakeupHandler: ObjCBlock?
    var stopHandler: ObjCBlock?
    var cleanupHandler: ObjCBlock?
}

@ObjCClass("OS_nw_framer")
open class NWFramerObject: NWObject {}

final class FramerLayer: Layer {
    let options: OptionsState
    let definition: FramerDefinition
    let isServer: Bool
    private let instance = FramerInstanceState()
    private var framer: UnsafeMutableRawPointer?
    private var started = false
    private var ready = false
    private var stopped = false
    private var input: [UInt8] = []
    private var inputEnded = false
    private var wanted = 0
    private var inInput = false
    private var passThroughInput = false
    private var passThroughOutput = false
    private var pendingNoCopy: (length: Int, message: UnsafeMutableRawPointer?, isComplete: Bool)?
    private var output: (data: [UInt8], offset: Int, isComplete: Bool)?
    private var wakeupGeneration = 0
    private var startTime: UInt64 = 0

    override var kind: ProtocolKind { .framer }
    override var deliversMessages: Bool { passThroughInput ? (lower?.deliversMessages ?? false) : true }

    init(options: OptionsState, isServer: Bool) {
        self.options = options
        definition = options.framer!
        self.isServer = isServer
    }

    deinit {
        ObjCRuntime.release(framer)
        ObjCRuntime.release(pendingNoCopy?.message)
    }

    override func lowerReady() {
        startTime = monotonicMilliseconds()
        instance.layer = self
        framer = NWObjects.make(NWFramerObject.objCClass, instance)
        started = true
        typealias Start = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?) -> Int32
        let result = definition.startHandler.function(as: Start.self)(definition.startHandler.object, framer)
        if result == StartResult.ready { markReady() }
        runInput()
    }

    func markReady() {
        guard !ready, !stopped else { return }
        ready = true
        connection.handshakeTimes.append((.framer, monotonicMilliseconds() - startTime))
        // After the handler that marked it returns.
        Dispatch.on(connection.queue) { [weak self] in
            guard let self, !self.stopped else { return }
            self.readyUp()
        }
    }

    func markFailed(_ code: Int32) {
        Dispatch.on(connection.queue) { [weak self] in
            guard let self, !self.stopped else { return }
            self.failUp(.posix(darwin: code == 0 ? 57 : code))
        }
    }

    // MARK: Input

    override func lowerReceived(_ data: [UInt8], context: UnsafeMutableRawPointer?, isComplete: Bool) {
        guard !stopped else { return }
        if passThroughInput {
            deliverUp(data, context: context, isComplete: isComplete)
            return
        }
        input += data
        let streamEnded = isComplete && data.isEmpty && lower?.deliversMessages == false
        if streamEnded { inputEnded = true }
        runInput()
        if streamEnded, !stopped { endUp() }
    }

    private func runInput() {
        guard started, !inInput, !stopped else { return }
        inInput = true
        defer { inInput = false }
        var calls = 0
        while !stopped {
            if let pending = pendingNoCopy {
                guard input.count >= pending.length else { return }
                pendingNoCopy = nil
                deliver(Array(input.prefix(pending.length)), message: pending.message, isComplete: pending.isComplete)
                input.removeFirst(pending.length)
                ObjCRuntime.release(pending.message)
            }
            if passThroughInput {
                if !input.isEmpty {
                    let rest = input
                    input = []
                    deliverUp(rest, context: nil, isComplete: false)
                }
                return
            }
            guard let handler = instance.inputHandler, !input.isEmpty, input.count >= max(wanted, 1) else { return }
            let before = input.count
            typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?) -> Int
            wanted = handler.function(as: Invoke.self)(handler.object, framer)
            calls += 1
            // Called again while it takes bytes, and isn't waiting for more.
            if input.count == before || calls > 10_000 { return }
        }
    }

    func parseInput(minimum: Int, maximum: Int, parse: ObjCBlock) -> Bool {
        let available = input.count
        guard available > 0, available >= minimum else { return false }
        let count = min(available, max(maximum, 0))
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt8>?, Int, Bool) -> Int
        // A copy, so the block may call the framer while it reads.
        var bytes = Array(input.prefix(count))
        let ended = inputEnded
        let consumed = bytes.withUnsafeMutableBufferPointer { buffer in
            parse.function(as: Invoke.self)(parse.object, buffer.baseAddress, count, ended)
        }
        input.removeFirst(min(max(consumed, 0), count))
        return true
    }

    func deliverInput(_ bytes: [UInt8], message: UnsafeMutableRawPointer?, isComplete: Bool) {
        deliver(bytes, message: message, isComplete: isComplete)
    }

    func deliverInputNoCopy(length: Int, message: UnsafeMutableRawPointer?, isComplete: Bool) -> Bool {
        if input.count >= length {
            let bytes = Array(input.prefix(length))
            input.removeFirst(length)
            deliver(bytes, message: message, isComplete: isComplete)
            return true
        }
        ObjCRuntime.release(pendingNoCopy?.message)
        pendingNoCopy = (length, ObjCRuntime.retain(message), isComplete)
        return false
    }

    func passInputThrough() {
        passThroughInput = true
        if !inInput { runInput() }
    }

    private func deliver(_ bytes: [UInt8], message: UnsafeMutableRawPointer?, isComplete: Bool) {
        let made = message == nil ? makeMessage() : nil
        let context = Contexts.message(definition.identifier, metadata: [message ?? made!])
        ObjCRuntime.release(made)
        deliverUp(bytes, context: context, isComplete: isComplete)
        ObjCRuntime.release(context)
    }

    /// A message of this framer (+1).
    func makeMessage() -> UnsafeMutableRawPointer { Metadata.make(.framer, definition: options.definition).0 }

    // MARK: Output

    override func send(_ data: [UInt8], context: UnsafeMutableRawPointer?, isComplete: Bool, completion: SendCompletion?) {
        guard !stopped else {
            completion?(.cancelled)
            return
        }
        if passThroughOutput {
            lower?.send(data, context: context, isComplete: isComplete, completion: completion)
            return
        }
        guard let handler = instance.outputHandler else {
            lower?.send(data, context: nil, isComplete: isComplete, completion: completion)
            return
        }
        var message = Contexts.state(context)?.metadata(for: options.definition)
        let made = message == nil ? makeMessage() : nil
        message = message ?? made
        output = (data, 0, isComplete)
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int, Bool) -> Void
        handler.function(as: Invoke.self)(handler.object, framer, message, data.count, isComplete)
        output = nil
        ObjCRuntime.release(made)
        // A message below ends with the program's.
        if lower?.deliversMessages == true {
            lower?.send([], context: nil, isComplete: isComplete, completion: completion)
        } else {
            completion?(nil)
        }
    }

    func writeOutput(_ bytes: [UInt8]) {
        guard !stopped, !bytes.isEmpty else { return }
        lower?.send(bytes, context: nil, isComplete: false, completion: nil)
    }

    func writeOutputNoCopy(length: Int) -> Bool {
        guard let current = output, current.data.count - current.offset >= length else { return false }
        writeOutput(Array(current.data[current.offset..<current.offset + length]))
        output?.offset += length
        return true
    }

    func parseOutput(minimum: Int, maximum: Int, parse: ObjCBlock) -> Bool {
        guard var current = output else { return false }
        let available = current.data.count - current.offset
        guard available >= minimum else { return false }
        let count = min(available, max(maximum, 0))
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt8>?, Int, Bool) -> Int
        let isComplete = current.isComplete && count == available
        let consumed = current.data.withUnsafeMutableBufferPointer { buffer in
            parse.function(as: Invoke.self)(parse.object, count > 0 ? buffer.baseAddress! + current.offset : nil, count, isComplete)
        }
        current.offset += min(max(consumed, 0), count)
        output = current
        return true
    }

    func passOutputThrough() { passThroughOutput = true }

    // MARK: Time and teardown

    func scheduleWakeup(milliseconds: UInt64) {
        wakeupGeneration += 1
        guard milliseconds != UInt64.max else { return }
        let generation = wakeupGeneration
        Dispatch.after(Double(milliseconds) / 1000, on: connection.queue) { [weak self] in
            guard let self, !self.stopped, self.wakeupGeneration == generation, let handler = self.instance.wakeupHandler else { return }
            handler.call(self.framer)
        }
    }

    override func stop() {
        guard !stopped else { return }
        stopped = true
        wakeupGeneration += 1
        if started, let framer {
            _ = instance.stopHandler?.test(framer)
            instance.cleanupHandler?.call(framer)
        }
        instance.inputHandler = nil
        instance.outputHandler = nil
        instance.wakeupHandler = nil
        instance.stopHandler = nil
        instance.cleanupHandler = nil
    }

    override func copyMetadata() -> UnsafeMutableRawPointer? { makeMessage() }
}

private func instance(_ framer: UnsafeMutableRawPointer?) -> FramerInstanceState? { NWObjects.state(framer, FramerInstanceState.self) }
private func layer(_ framer: UnsafeMutableRawPointer?) -> FramerLayer? { instance(framer)?.layer }

@c(_nw_framer_create_definition)
public func nw_framer_create_definition(_ identifier: UnsafePointer<CChar>?, _ flags: UInt32, _ start: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let start = ObjCBlock.from(start) else { return nil }
    let definition = FramerDefinition(identifier: identifier.map { String(cString: $0) } ?? "framer", flags: flags, startHandler: start)
    return NWObjects.make(NWProtocolDefinitionObject.objCClass, DefinitionState(kind: .framer, framer: definition))
}

@c(_nw_framer_create_options)
public func nw_framer_create_options(_ definition: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let definition, Definitions.state(definition)?.framer != nil else { return nil }
    return Options.make(OptionsState(kind: .framer, definition: definition))
}

@c(_nw_framer_options_set_object_value)
public func nw_framer_options_set_object_value(_ options: UnsafeMutableRawPointer?, _ key: UnsafePointer<CChar>?, _ value: UnsafeMutableRawPointer?) {
    guard let state = Options.state(options, .framer), let key else { return }
    let name = String(cString: key)
    let held = ObjCRuntime.retain(value)
    if let old = state.objectValues[name] { ObjCRuntime.release(old) }
    state.objectValues[name] = held
}

@c(_nw_framer_options_copy_object_value)
public func nw_framer_options_copy_object_value(_ options: UnsafeMutableRawPointer?, _ key: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    guard let state = Options.state(options, .framer), let key else { return nil }
    return ObjCRuntime.retain(state.objectValues[String(cString: key)])
}

@c(_nw_framer_message_create)
public func nw_framer_message_create(_ framer: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { layer(framer)?.makeMessage() }

@c(_nw_framer_protocol_create_message)
public func nw_framer_protocol_create_message(_ definition: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let definition, Definitions.state(definition)?.framer != nil else { return nil }
    return Metadata.make(.framer, definition: definition).0
}

@c(_nw_framer_message_set_object_value)
public func nw_framer_message_set_object_value(_ message: UnsafeMutableRawPointer?, _ key: UnsafePointer<CChar>?, _ value: UnsafeMutableRawPointer?) {
    guard let state = Metadata.state(message, .framer), let key else { return }
    let name = String(cString: key)
    let held = ObjCRuntime.retain(value)
    if let old = state.objectValues[name] { ObjCRuntime.release(old) }
    state.objectValues[name] = held
}

@c(_nw_framer_message_copy_object_value)
public func nw_framer_message_copy_object_value(_ message: UnsafeMutableRawPointer?, _ key: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    guard let state = Metadata.state(message, .framer), let key else { return nil }
    return ObjCRuntime.retain(state.objectValues[String(cString: key)])
}

/// A C value with the block that disposes of it when it is replaced or
/// the message goes away.
@c(_nw_framer_message_set_value)
public func nw_framer_message_set_value(_ message: UnsafeMutableRawPointer?, _ key: UnsafePointer<CChar>?, _ value: UnsafeMutableRawPointer?,
                                        _ dispose: UnsafeMutableRawPointer?) {
    guard let state = Metadata.state(message, .framer), let key else { return }
    let name = String(cString: key)
    if let (old, disposeOld) = state.values[name] { disposeOld?.call(old) }
    state.values[name] = (value, ObjCBlock.from(dispose))
}

@c(_nw_framer_message_access_value)
public func nw_framer_message_access_value(_ message: UnsafeMutableRawPointer?, _ key: UnsafePointer<CChar>?, _ block: UnsafeMutableRawPointer?) -> Bool {
    guard let state = Metadata.state(message, .framer), let key, let block = ObjCBlock.from(block) else { return false }
    typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?) -> Bool
    return block.function(as: Invoke.self)(block.object, state.values[String(cString: key)]?.0)
}

@c(_nw_framer_set_input_handler)
public func nw_framer_set_input_handler(_ framer: UnsafeMutableRawPointer?, _ handler: UnsafeMutableRawPointer?) {
    instance(framer)?.inputHandler = ObjCBlock.from(handler)
}

@c(_nw_framer_set_output_handler)
public func nw_framer_set_output_handler(_ framer: UnsafeMutableRawPointer?, _ handler: UnsafeMutableRawPointer?) {
    instance(framer)?.outputHandler = ObjCBlock.from(handler)
}

@c(_nw_framer_set_wakeup_handler)
public func nw_framer_set_wakeup_handler(_ framer: UnsafeMutableRawPointer?, _ handler: UnsafeMutableRawPointer?) {
    instance(framer)?.wakeupHandler = ObjCBlock.from(handler)
}

@c(_nw_framer_set_stop_handler)
public func nw_framer_set_stop_handler(_ framer: UnsafeMutableRawPointer?, _ handler: UnsafeMutableRawPointer?) {
    instance(framer)?.stopHandler = ObjCBlock.from(handler)
}

@c(_nw_framer_set_cleanup_handler)
public func nw_framer_set_cleanup_handler(_ framer: UnsafeMutableRawPointer?, _ handler: UnsafeMutableRawPointer?) {
    instance(framer)?.cleanupHandler = ObjCBlock.from(handler)
}

@c(_nw_framer_mark_ready)
public func nw_framer_mark_ready(_ framer: UnsafeMutableRawPointer?) { layer(framer)?.markReady() }

@c(_nw_framer_mark_failed_with_error)
public func nw_framer_mark_failed_with_error(_ framer: UnsafeMutableRawPointer?, _ code: Int32) { layer(framer)?.markFailed(code) }

/// Protocols can't be added above a running framer here.
@c(_nw_framer_prepend_application_protocol)
public func nw_framer_prepend_application_protocol(_ framer: UnsafeMutableRawPointer?, _ options: UnsafeMutableRawPointer?) -> Bool { false }

@c(_nw_framer_parse_input)
public func nw_framer_parse_input(_ framer: UnsafeMutableRawPointer?, _ minimum: Int, _ maximum: Int, _ buffer: UnsafeMutablePointer<UInt8>?,
                                  _ parse: UnsafeMutableRawPointer?) -> Bool {
    guard let layer = layer(framer), let parse = ObjCBlock.from(parse) else { return false }
    return layer.parseInput(minimum: minimum, maximum: maximum, parse: parse)
}

@c(_nw_framer_deliver_input)
public func nw_framer_deliver_input(_ framer: UnsafeMutableRawPointer?, _ bytes: UnsafePointer<UInt8>?, _ length: Int,
                                    _ message: UnsafeMutableRawPointer?, _ isComplete: Bool) {
    guard let layer = layer(framer) else { return }
    let data = bytes.map { Array(UnsafeBufferPointer(start: $0, count: length)) } ?? []
    layer.deliverInput(data, message: message, isComplete: isComplete)
}

@c(_nw_framer_deliver_input_no_copy)
public func nw_framer_deliver_input_no_copy(_ framer: UnsafeMutableRawPointer?, _ length: Int, _ message: UnsafeMutableRawPointer?,
                                            _ isComplete: Bool) -> Bool {
    layer(framer)?.deliverInputNoCopy(length: length, message: message, isComplete: isComplete) ?? false
}

@c(_nw_framer_pass_through_input)
public func nw_framer_pass_through_input(_ framer: UnsafeMutableRawPointer?) { layer(framer)?.passInputThrough() }

@c(_nw_framer_parse_output)
public func nw_framer_parse_output(_ framer: UnsafeMutableRawPointer?, _ minimum: Int, _ maximum: Int, _ buffer: UnsafeMutablePointer<UInt8>?,
                                   _ parse: UnsafeMutableRawPointer?) -> Bool {
    guard let layer = layer(framer), let parse = ObjCBlock.from(parse) else { return false }
    return layer.parseOutput(minimum: minimum, maximum: maximum, parse: parse)
}

@c(_nw_framer_write_output)
public func nw_framer_write_output(_ framer: UnsafeMutableRawPointer?, _ bytes: UnsafePointer<UInt8>?, _ length: Int) {
    guard let layer = layer(framer), let bytes else { return }
    layer.writeOutput(Array(UnsafeBufferPointer(start: bytes, count: length)))
}

@c(_nw_framer_write_output_data)
public func nw_framer_write_output_data(_ framer: UnsafeMutableRawPointer?, _ data: UnsafeMutableRawPointer?) {
    layer(framer)?.writeOutput(Dispatch.bytes(data))
}

@c(_nw_framer_write_output_no_copy)
public func nw_framer_write_output_no_copy(_ framer: UnsafeMutableRawPointer?, _ length: Int) -> Bool {
    layer(framer)?.writeOutputNoCopy(length: length) ?? false
}

@c(_nw_framer_pass_through_output)
public func nw_framer_pass_through_output(_ framer: UnsafeMutableRawPointer?) { layer(framer)?.passOutputThrough() }

@c(_nw_framer_schedule_wakeup)
public func nw_framer_schedule_wakeup(_ framer: UnsafeMutableRawPointer?, _ milliseconds: UInt64) {
    layer(framer)?.scheduleWakeup(milliseconds: milliseconds)
}

/// The block runs on the framer's connection's queue.
@c(_nw_framer_async)
public func nw_framer_async(_ framer: UnsafeMutableRawPointer?, _ block: UnsafeMutableRawPointer?) {
    guard let layer = layer(framer), let block = ObjCBlock.from(block) else { return }
    Dispatch.on(layer.connection.queue) { block.call() }
}

@c(_nw_framer_copy_remote_endpoint)
public func nw_framer_copy_remote_endpoint(_ framer: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let layer = layer(framer) else { return nil }
    if let remote = layer.connection.transport?.remoteAddress, layer.connection.isInbound { return Endpoints.make(address: remote) }
    return ObjCRuntime.retain(layer.connection.endpoint)
}

@c(_nw_framer_copy_local_endpoint)
public func nw_framer_copy_local_endpoint(_ framer: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let local = layer(framer)?.connection.transport?.localAddress else { return nil }
    return Endpoints.make(address: local)
}

@c(_nw_framer_copy_parameters)
public func nw_framer_copy_parameters(_ framer: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    ObjCRuntime.retain(layer(framer)?.connection.parametersObject)
}

/// The framer's options, with the values the program set on them.
@c(_nw_framer_copy_options)
public func nw_framer_copy_options(_ framer: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let layer = layer(framer) else { return nil }
    return Options.make(layer.options.copy())
}

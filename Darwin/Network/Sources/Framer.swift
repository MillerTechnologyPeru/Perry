// NWProtocolFramer: protocols an app writes, as an implementation type the
// C API's framer (nw_framer_t) calls through its handlers.

import Dispatch
import Foundation

@_inheritsConvenienceInitializers
@_hasMissingDesignatedInitializers
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public class NWProtocolFramer: NWProtocol {
    /// The definition of a framer protocol: each connection that uses it
    /// makes an instance of the implementation type.
    @_hasMissingDesignatedInitializers
    public class Definition: NWProtocolDefinition {
        public init(implementation: any NWProtocolFramerImplementation.Type) {
            let definition = nw_framer_create_definition(implementation.label, 0) { framer in
                Instance.start(framer, implementation: implementation)
            }
            super.init(definition, implementation.label)
        }

        override init(_ nw: nw_protocol_definition_t, _ name: String) {
            super.init(nw, name)
        }

        deinit {}
    }

    @_inheritsConvenienceInitializers
    @_hasMissingDesignatedInitializers
    public class Options: NWProtocolOptions {
        public init(definition: Definition) {
            super.init(nw_framer_create_options(definition.nw))
        }

        override init(_ nw: nw_protocol_options_t) {
            super.init(nw)
        }

        /// A value the framer's instances read from their options.
        @available(macOS 12.3, iOS 15.4, watchOS 8.4, tvOS 15.4, *)
        public subscript(key: String) -> Any? {
            get { nw_framer_options_copy_object_value(nw, key) }
            set(value) { nw_framer_options_set_object_value(nw, key, value) }
        }

        deinit {}
    }

    /// The metadata of a framer protocol's message, with values by key.
    @_inheritsConvenienceInitializers
    @_hasMissingDesignatedInitializers
    public class Message: NWProtocolMetadata {
        public init(definition: Definition) {
            super.init(nw_framer_protocol_create_message(definition.nw))
        }

        public init(instance: Instance) {
            super.init(nw_framer_message_create(instance.framer))
        }

        override init(_ nw: nw_protocol_metadata_t) {
            super.init(nw)
        }

        public subscript(key: String) -> Any? {
            get { nw_framer_message_copy_object_value(nw, key) }
            set(value) { nw_framer_message_set_object_value(nw, key, value) }
        }

        deinit {}
    }

    /// A framer protocol's instance on one connection.
    @_hasMissingDesignatedInitializers
    final public class Instance: CustomDebugStringConvertible, @unchecked Sendable {
        let framer: nw_framer_t
        /// The implementation, from start to clean-up.
        private var implementation: (any NWProtocolFramerImplementation)?

        private init(_ framer: nw_framer_t) {
            self.framer = framer
        }

        /// Starts an instance on a framer: makes the implementation and
        /// has the framer's handlers call it.
        static func start(_ framer: nw_framer_t, implementation type: any NWProtocolFramerImplementation.Type) -> nw_framer_start_result_t {
            let instance = Instance(framer)
            let implementation = type.init(framer: instance)
            instance.implementation = implementation
            nw_framer_set_input_handler(framer) { _ in
                instance.implementation.map { $0.handleInput(framer: instance) }.map { $0 < 0 ? 0 : $0 } ?? 0
            }
            nw_framer_set_output_handler(framer) { _, message, length, isComplete in
                instance.implementation?.handleOutput(framer: instance, message: Message(message), messageLength: length, isComplete: isComplete)
            }
            nw_framer_set_wakeup_handler(framer) { _ in
                instance.implementation?.wakeup(framer: instance)
            }
            nw_framer_set_stop_handler(framer) { _ in
                instance.implementation?.stop(framer: instance) ?? true
            }
            nw_framer_set_cleanup_handler(framer) { _ in
                instance.implementation?.cleanup(framer: instance)
                instance.implementation = nil
            }
            switch implementation.start(framer: instance) {
            case .ready: return nw_framer_start_result_ready
            case .willMarkReady: return nw_framer_start_result_will_mark_ready
            }
        }

        final public var debugDescription: String {
            framer.description
        }

        final public func markReady() {
            nw_framer_mark_ready(framer)
        }

        final public func markFailed(error: NWError?) {
            let code: Int32
            switch error {
            case .posix(let posix)?: code = posix.rawValue
            case nil: code = 0
            default: code = EPROTO
            }
            nw_framer_mark_failed_with_error(framer, code)
        }

        final public func parseInput(minimumIncompleteLength: Int, maximumLength: Int, parse: (_ buffer: UnsafeMutableRawBufferPointer?, _ isComplete: Bool) -> Int) -> Bool {
            withoutActuallyEscaping(parse) { parse in
                nw_framer_parse_input(framer, minimumIncompleteLength, maximumLength, nil) { buffer, length, isComplete in
                    let bytes = buffer.map { UnsafeMutableRawBufferPointer(start: $0, count: length) }
                    return max(0, parse(bytes, isComplete))
                }
            }
        }

        final public func deliverInput(data: Data, message: Message, isComplete: Bool) {
            data.withUnsafeBytes { raw in
                let bytes = raw.bindMemory(to: UInt8.self)
                nw_framer_deliver_input(framer, bytes.baseAddress ?? emptyBytes, bytes.count, message.nw, isComplete)
            }
        }

        final public func deliverInputNoCopy(length: Int, message: Message, isComplete: Bool) -> Bool {
            nw_framer_deliver_input_no_copy(framer, length, message.nw, isComplete)
        }

        final public func passThroughInput() {
            nw_framer_pass_through_input(framer)
        }

        final public func parseOutput(minimumIncompleteLength: Int, maximumLength: Int, parse: (_ buffer: UnsafeMutableRawBufferPointer?, _ isComplete: Bool) -> Int) -> Bool {
            withoutActuallyEscaping(parse) { parse in
                nw_framer_parse_output(framer, minimumIncompleteLength, maximumLength, nil) { buffer, length, isComplete in
                    let bytes = buffer.map { UnsafeMutableRawBufferPointer(start: $0, count: length) }
                    return max(0, parse(bytes, isComplete))
                }
            }
        }

        final public func writeOutput(data: Data) {
            data.withUnsafeBytes { raw in
                let bytes = raw.bindMemory(to: UInt8.self)
                nw_framer_write_output(framer, bytes.baseAddress ?? emptyBytes, bytes.count)
            }
        }

        @usableFromInline
        final internal func writeOutput(discontiguousData: DispatchData) {
            nw_framer_write_output_data(framer, discontiguousData._bridgeToObjectiveC())
        }

        @inlinable
        final public func writeOutput<Output>(data: Output) where Output: DataProtocol {
            if let dispatchData = data as? DispatchData {
                writeOutput(discontiguousData: dispatchData)
            } else if let data = data as? Data {
                writeOutput(data: data)
            } else {
                writeOutput(data: Data(data))
            }
        }

        final public func writeOutputNoCopy(length: Int) throws {
            guard nw_framer_write_output_no_copy(framer, length) else {
                throw NWError.posix(.EINVAL)
            }
        }

        final public func passThroughOutput() {
            nw_framer_pass_through_output(framer)
        }

        public enum WakeupTime {
            case milliseconds(UInt64)
            case forever
        }

        final public func scheduleWakeup(wakeupTime: WakeupTime) {
            switch wakeupTime {
            case .milliseconds(let milliseconds): nw_framer_schedule_wakeup(framer, milliseconds)
            case .forever: nw_framer_schedule_wakeup(framer, UInt64.max)
            }
        }

        final public func async(execute: @escaping () -> Void) {
            nw_framer_async(framer, execute)
        }

        final public var remote: NWEndpoint? {
            NWEndpoint(nw_framer_copy_remote_endpoint(framer))
        }

        final public var local: NWEndpoint? {
            NWEndpoint(nw_framer_copy_local_endpoint(framer))
        }

        final public var parameters: NWParameters? {
            NWParameters(nw_framer_copy_parameters(framer))
        }

        @available(macOS 12.3, iOS 15.4, watchOS 8.4, tvOS 15.4, *)
        final public var options: Options {
            Options(nw_framer_copy_options(framer))
        }

        final public func prependApplicationProtocol(options: NWProtocolOptions) throws {
            guard nw_framer_prepend_application_protocol(framer, options.nw) else {
                throw NWError.posix(.EINVAL)
            }
        }

        /// Prepends a protocol without waiting for it to be ready. The C
        /// API has one way to prepend, used here too.
        @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
        final public func prependApplicationProtocolIgnoringReady(options: NWProtocolOptions) throws {
            try prependApplicationProtocol(options: options)
        }

        deinit {}
    }

    public enum StartResult {
        case ready
        case willMarkReady
    }

    deinit {}
}

/// A pointer for C calls that take bytes when there are none.
private let emptyBytes = UnsafePointer<UInt8>(bitPattern: 1)!

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public protocol NWProtocolFramerImplementation: AnyObject {
    static var label: String { get }
    init(framer: NWProtocolFramer.Instance)
    func start(framer: NWProtocolFramer.Instance) -> NWProtocolFramer.StartResult
    func handleInput(framer: NWProtocolFramer.Instance) -> Int
    func handleOutput(framer: NWProtocolFramer.Instance, message: NWProtocolFramer.Message, messageLength: Int, isComplete: Bool)
    func wakeup(framer: NWProtocolFramer.Instance)
    func stop(framer: NWProtocolFramer.Instance) -> Bool
    func cleanup(framer: NWProtocolFramer.Instance)
}

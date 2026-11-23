// NWEthernetChannel over the C API's nw_ethernet_channel_t: Ethernet
// frames of one EtherType on an interface (macOS only).

import Dispatch
import Foundation

@available(macOS 10.15, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
final public class NWEthernetChannel: CustomDebugStringConvertible {
    /// The C API's channel; none for an interface the C API didn't give
    /// (one only named), which can't be opened.
    private let nw: nw_ethernet_channel_t?
    private let lock = NSLock()
    private var storedState: State = .setup
    private var storedQueue: DispatchQueue?
    private var storedStateHandler: (@Sendable (State) -> Void)?
    private var storedReceiveHandler: (@Sendable (Data, UInt16, EthernetAddress, EthernetAddress) -> Void)?
    private var started = false

    final public var debugDescription: String {
        "NWEthernetChannel on \(interface.name), EtherType 0x\(String(etherType, radix: 16))"
    }

    public enum State: Equatable, Sendable {
        case setup
        case waiting(NWError)
        case preparing
        case ready
        case failed(NWError)
        case cancelled

        public static func == (a: State, b: State) -> Bool {
            switch (a, b) {
            case (.setup, .setup), (.preparing, .preparing), (.ready, .ready), (.cancelled, .cancelled): return true
            case let (.waiting(x), .waiting(y)), let (.failed(x), .failed(y)): return x == y
            default: return false
            }
        }

        init(_ state: nw_ethernet_channel_state_t, _ error: nw_error_t?) {
            let error = NWError(error) ?? .posix(.ECONNABORTED)
            switch state {
            case nw_ethernet_channel_state_waiting: self = .waiting(error)
            case nw_ethernet_channel_state_preparing: self = .preparing
            case nw_ethernet_channel_state_ready: self = .ready
            case nw_ethernet_channel_state_failed: self = .failed(error)
            case nw_ethernet_channel_state_cancelled: self = .cancelled
            default: self = .setup
            }
        }
    }

    final public var state: State {
        lock.withLock { storedState }
    }

    @preconcurrency final public var stateUpdateHandler: (@Sendable (_ state: State) -> Void)? {
        get { lock.withLock { storedStateHandler } }
        set { lock.withLock { storedStateHandler = newValue } }
    }

    final public let etherType: UInt16
    final public let interface: NWInterface

    public init(on interface: NWInterface, etherType: UInt16) {
        self.interface = interface
        self.etherType = etherType
        nw = interface.nw.map { nw_ethernet_channel_create(etherType, $0) }
    }

    @available(macOS 13.0, *)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    public init(on interface: NWInterface, etherType: UInt16, parameters: NWParameters) {
        self.interface = interface
        self.etherType = etherType
        nw = interface.nw.map { nw_ethernet_channel_create_with_parameters(etherType, $0, parameters.nw) }
    }

    @available(macOS 13.0, *)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    final public var maximumPayloadSize: Int {
        nw.map { Int(nw_ethernet_channel_get_maximum_payload_size($0)) } ?? 0
    }

    final public func start(queue: DispatchQueue) {
        let first = lock.withLock { () -> Bool in
            storedQueue = queue
            defer { started = true }
            return !started
        }
        guard first else { return }
        guard let nw else {
            queue.async { self.update(.failed(.posix(.ENXIO))) }
            return
        }
        nw_ethernet_channel_set_queue(nw, queue)
        nw_ethernet_channel_set_state_changed_handler(nw) { state, error in
            self.update(State(state, error))
        }
        nw_ethernet_channel_set_receive_handler(nw) { content, vlan, local, remote in
            guard let handler = self.receiveHandler else { return }
            let localAddress = EthernetAddress(bytes: local)
            let remoteAddress = EthernetAddress(bytes: remote)
            handler(data(of: content) ?? Data(), vlan, localAddress, remoteAddress)
        }
        nw_ethernet_channel_start(nw)
    }

    private func update(_ state: State) {
        let handler = lock.withLock { () -> (@Sendable (State) -> Void)? in
            storedState = state
            return storedStateHandler
        }
        handler?(state)
        if state == .cancelled, let nw {
            nw_ethernet_channel_set_state_changed_handler(nw, nil)
            nw_ethernet_channel_set_receive_handler(nw, nil)
        }
    }

    final public var queue: DispatchQueue? {
        lock.withLock { storedQueue }
    }

    final public func cancel() {
        if let nw {
            nw_ethernet_channel_cancel(nw)
        } else {
            update(.cancelled)
        }
    }

    /// A MAC address.
    public struct EthernetAddress: Hashable, CustomDebugStringConvertible, Sendable {
        private let bytes: [UInt8]

        init(bytes pointer: UnsafeMutablePointer<UInt8>) {
            bytes = Array(UnsafeBufferPointer(start: pointer, count: 6))
        }

        public init?(_ rawValue: Data) {
            guard rawValue.count == 6 else { return nil }
            bytes = [UInt8](rawValue)
        }

        /// An address of six hexadecimal bytes separated by colons.
        public init?(_ string: String) {
            let parts = string.split(separator: ":")
            guard parts.count == 6 else { return nil }
            var bytes: [UInt8] = []
            for part in parts {
                guard part.count <= 2, let byte = UInt8(part, radix: 16) else { return nil }
                bytes.append(byte)
            }
            self.bytes = bytes
        }

        public var debugDescription: String {
            bytes.map { $0 < 16 ? "0" + String($0, radix: 16) : String($0, radix: 16) }.joined(separator: ":")
        }

        public var rawValue: Data { Data(bytes) }

        public static func == (a: EthernetAddress, b: EthernetAddress) -> Bool {
            a.bytes == b.bytes
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(bytes)
        }
    }

    @preconcurrency
    final public func send(content: Data, to remoteAddress: EthernetAddress, vlanTag: UInt16, completion: @escaping @Sendable (_ error: NWError?) -> Void) {
        guard let nw else {
            completion(.posix(.ENXIO))
            return
        }
        let data = content.withUnsafeBytes { DispatchData(bytes: $0) }._bridgeToObjectiveC()
        var address = [UInt8](remoteAddress.rawValue)
        address.withUnsafeMutableBufferPointer { buffer in
            nw_ethernet_channel_send(nw, data, vlanTag, buffer.baseAddress!) { error in
                completion(NWError(error))
            }
        }
    }

    @preconcurrency final public var receiveHandler: (@Sendable (_ content: Data, _ vlanTag: UInt16, _ localAddress: EthernetAddress, _ remoteAddress: EthernetAddress) -> Void)? {
        get { lock.withLock { storedReceiveHandler } }
        set { lock.withLock { storedReceiveHandler = newValue } }
    }

    deinit {}
}

@available(macOS 14.0, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
extension NWEthernetChannel: @unchecked Sendable {}

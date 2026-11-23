// NWProtocolWebSocket: WebSocket options and message metadata over the C
// API's nw_ws_* functions.

import Dispatch
import Foundation

@_inheritsConvenienceInitializers
@_hasMissingDesignatedInitializers
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public class NWProtocolWebSocket: NWProtocol {
    public static let definition = NWProtocolDefinition(nw_protocol_copy_ws_definition(), "websocket")

    public enum Version: Sendable {
        case version13
    }

    public enum Opcode: UInt8, Sendable {
        case cont = 0x0
        case text = 0x1
        case binary = 0x2
        case close = 0x8
        case ping = 0x9
        case pong = 0xA

        var nw: nw_ws_opcode_t {
            nw_ws_opcode_t(rawValue: Int32(rawValue))
        }
    }

    public enum CloseCode: Equatable, Sendable {
        public enum Defined: UInt16, Sendable {
            case normalClosure = 1000
            case goingAway = 1001
            case protocolError = 1002
            case unsupportedData = 1003
            case noStatusReceived = 1005
            case abnormalClosure = 1006
            case invalidFramePayloadData = 1007
            case policyViolation = 1008
            case messageTooBig = 1009
            case mandatoryExtension = 1010
            case internalServerError = 1011
            case tlsHandshake = 1015
        }

        case protocolCode(Defined)
        case applicationCode(UInt16)
        case privateCode(UInt16)

        /// A close code of RFC 6455's ranges: defined codes below 3000,
        /// codes of applications to 3999 and private ones to 4999.
        public init(rawValue: UInt16) throws {
            switch rawValue {
            case 1000..<3000:
                guard let defined = Defined(rawValue: rawValue) else { throw NWError.posix(.EINVAL) }
                self = .protocolCode(defined)
            case 3000..<4000:
                self = .applicationCode(rawValue)
            case 4000..<5000:
                self = .privateCode(rawValue)
            default:
                throw NWError.posix(.EINVAL)
            }
        }

        var rawValue: UInt16 {
            switch self {
            case .protocolCode(let defined): return defined.rawValue
            case .applicationCode(let code), .privateCode(let code): return code
            }
        }

        public static func == (a: CloseCode, b: CloseCode) -> Bool {
            a.rawValue == b.rawValue
        }
    }

    @_inheritsConvenienceInitializers
    @_hasMissingDesignatedInitializers
    public class Options: NWProtocolOptions {
        public var autoReplyPing = false {
            didSet { nw_ws_options_set_auto_reply_ping(nw, autoReplyPing) }
        }

        public var maximumMessageSize = 0 {
            didSet { nw_ws_options_set_maximum_message_size(nw, maximumMessageSize) }
        }

        public var skipHandshake = false {
            didSet { nw_ws_options_set_skip_handshake(nw, skipHandshake) }
        }

        public init(_ version: Version = .version13) {
            super.init(nw_ws_create_options(nw_ws_version_13))
        }

        override init(_ nw: nw_protocol_options_t) {
            super.init(nw)
        }

        public func setAdditionalHeaders(_ headers: [(name: String, value: String)]) {
            for header in headers {
                nw_ws_options_add_additional_header(nw, header.name, header.value)
            }
        }

        public func setSubprotocols(_ subprotocols: [String]) {
            for subprotocol in subprotocols {
                nw_ws_options_add_subprotocol(nw, subprotocol)
            }
        }

        /// Has a server answer each client's request to connect, given the
        /// subprotocols and headers the client sent.
        @preconcurrency
        public func setClientRequestHandler(_ queue: DispatchQueue, handler: @escaping @Sendable (_ subprotocols: [String], _ additionalHeaders: [(name: String, value: String)]) -> Response) {
            nw_ws_options_set_client_request_handler(nw, queue) { request in
                var subprotocols: [String] = []
                nw_ws_request_enumerate_subprotocols(request) { subprotocol in
                    subprotocols.append(String(cString: subprotocol))
                    return true
                }
                var headers: [(name: String, value: String)] = []
                nw_ws_request_enumerate_additional_headers(request) { name, value in
                    headers.append((String(cString: name), String(cString: value)))
                    return true
                }
                let answer = handler(subprotocols, headers)
                let response = nw_ws_response_create(answer.status == .accept ? nw_ws_response_status_accept : nw_ws_response_status_reject, answer.subprotocol)
                for header in answer.additionalHeaders ?? [] {
                    nw_ws_response_add_additional_header(response, header.name, header.value)
                }
                return response
            }
        }

        deinit {}
    }

    @_inheritsConvenienceInitializers
    @_hasMissingDesignatedInitializers
    public class Metadata: NWProtocolMetadata {
        final public let opcode: Opcode

        public init(opcode: Opcode) {
            self.opcode = opcode
            super.init(nw_ws_create_metadata(opcode.nw))
        }

        override init(_ nw: nw_protocol_metadata_t) {
            opcode = Opcode(rawValue: UInt8(truncatingIfNeeded: nw_ws_metadata_get_opcode(nw).rawValue)) ?? .binary
            super.init(nw)
        }

        public var closeCode: CloseCode {
            get {
                let code = UInt16(truncatingIfNeeded: nw_ws_metadata_get_close_code(nw).rawValue)
                return (try? CloseCode(rawValue: code)) ?? .protocolCode(.noStatusReceived)
            }
            set {
                nw_ws_metadata_set_close_code(nw, nw_ws_close_code_t(rawValue: UInt32(newValue.rawValue)))
            }
        }

        @preconcurrency
        public func setPongHandler(_ queue: DispatchQueue, handler: @escaping @Sendable (NWError?) -> Void) {
            nw_ws_metadata_set_pong_handler(nw, queue) { error in
                handler(NWError(error))
            }
        }

        public var selectedSubprotocol: String? {
            let response = nw_ws_metadata_copy_server_response(nw)
            guard nw_ws_response_get_status(response) != nw_ws_response_status_invalid,
                  let subprotocol = nw_ws_response_get_selected_subprotocol(response) else { return nil }
            return String(cString: subprotocol)
        }

        public var additionalServerHeaders: [(String, String)]? {
            let response = nw_ws_metadata_copy_server_response(nw)
            guard nw_ws_response_get_status(response) != nw_ws_response_status_invalid else { return nil }
            var headers: [(String, String)] = []
            nw_ws_response_enumerate_additional_headers(response) { name, value in
                headers.append((String(cString: name), String(cString: value)))
                return true
            }
            return headers
        }

        deinit {}
    }

    /// A server's answer to a client's request to connect.
    public struct Response: Sendable {
        public enum Status: Sendable {
            case accept
            case reject
        }

        public let status: Status
        public let subprotocol: String?
        public let additionalHeaders: [(name: String, value: String)]?

        public init(status: Status, subprotocol: String?, additionalHeaders: [(name: String, value: String)]? = nil) {
            self.status = status
            self.subprotocol = subprotocol
            self.additionalHeaders = additionalHeaders
        }
    }

    deinit {}
}

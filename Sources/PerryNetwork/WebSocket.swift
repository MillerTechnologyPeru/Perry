import Glibc
import PerryObjCInterop

// WebSocket (RFC 6455) over the stream below it: the HTTP upgrade (a client
// sends the request, a server answers it, asking the program's client
// request handler when it has one), then frames, each received message
// handed up whole with WebSocket metadata (its opcode, a close's code).
// Pings are answered when the options say so, and a sent ping's pong
// handler is called when its pong comes.

/// nw_ws_opcode_t.
enum WebSocketOpcode {
    static let continuation: Int32 = 0
    static let text: Int32 = 1
    static let binary: Int32 = 2
    static let close: Int32 = 8
    static let ping: Int32 = 9
    static let pong: Int32 = 10
}

// MARK: - Options, metadata, requests and responses

@c(_nw_ws_create_options)
public func nw_ws_create_options(_ version: Int32) -> UnsafeMutableRawPointer? {
    let options = Options.make(.webSocket)
    Options.state(options)?.webSocketVersion = version
    return options
}

@c(_nw_ws_options_add_additional_header)
public func nw_ws_options_add_additional_header(_ options: UnsafeMutableRawPointer?, _ name: UnsafePointer<CChar>?, _ value: UnsafePointer<CChar>?) {
    guard let name, let value else { return }
    Options.state(options, .webSocket)?.additionalHeaders.append((String(cString: name), String(cString: value)))
}

@c(_nw_ws_options_add_subprotocol)
public func nw_ws_options_add_subprotocol(_ options: UnsafeMutableRawPointer?, _ subprotocol: UnsafePointer<CChar>?) {
    guard let subprotocol else { return }
    Options.state(options, .webSocket)?.subprotocols.append(String(cString: subprotocol))
}

@c(_nw_ws_options_set_auto_reply_ping)
public func nw_ws_options_set_auto_reply_ping(_ options: UnsafeMutableRawPointer?, _ value: Bool) {
    Options.state(options, .webSocket)?.autoReplyPing = value
}

@c(_nw_ws_options_set_maximum_message_size)
public func nw_ws_options_set_maximum_message_size(_ options: UnsafeMutableRawPointer?, _ size: Int) {
    Options.state(options, .webSocket)?.maximumMessageSize = size
}

@c(_nw_ws_options_set_skip_handshake)
public func nw_ws_options_set_skip_handshake(_ options: UnsafeMutableRawPointer?, _ value: Bool) {
    Options.state(options, .webSocket)?.skipHandshake = value
}

@c(_nw_ws_options_set_client_request_handler)
public func nw_ws_options_set_client_request_handler(_ options: UnsafeMutableRawPointer?, _ queue: UnsafeMutableRawPointer?,
                                                     _ handler: UnsafeMutableRawPointer?) {
    guard let state = Options.state(options, .webSocket) else { return }
    state.clientRequestHandler = ObjCBlock.from(handler)
    let held = ObjCRuntime.retain(queue)
    ObjCRuntime.release(state.clientRequestQueue)
    state.clientRequestQueue = held
}

@c(_nw_ws_create_metadata)
public func nw_ws_create_metadata(_ opcode: Int32) -> UnsafeMutableRawPointer? {
    let (object, state) = Metadata.make(.webSocket)
    state.opcode = opcode
    return object
}

@c(_nw_ws_metadata_get_opcode)
public func nw_ws_metadata_get_opcode(_ metadata: UnsafeMutableRawPointer?) -> Int32 { Metadata.state(metadata, .webSocket)?.opcode ?? -1 }

@c(_nw_ws_metadata_set_close_code)
public func nw_ws_metadata_set_close_code(_ metadata: UnsafeMutableRawPointer?, _ code: Int32) {
    Metadata.state(metadata, .webSocket)?.closeCode = code
}

@c(_nw_ws_metadata_get_close_code)
public func nw_ws_metadata_get_close_code(_ metadata: UnsafeMutableRawPointer?) -> Int32 {
    Metadata.state(metadata, .webSocket)?.closeCode ?? 1000
}

@c(_nw_ws_metadata_set_pong_handler)
public func nw_ws_metadata_set_pong_handler(_ metadata: UnsafeMutableRawPointer?, _ queue: UnsafeMutableRawPointer?, _ handler: UnsafeMutableRawPointer?) {
    guard let state = Metadata.state(metadata, .webSocket) else { return }
    state.pongHandler = ObjCBlock.from(handler)
    let held = ObjCRuntime.retain(queue)
    ObjCRuntime.release(state.pongQueue)
    state.pongQueue = held
}

@c(_nw_ws_metadata_copy_server_response)
public func nw_ws_metadata_copy_server_response(_ metadata: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    ObjCRuntime.retain(Metadata.state(metadata, .webSocket)?.serverResponse)
}

final class WebSocketRequestState: NWState {
    let subprotocols: [String]
    let headers: [(String, String)]
    init(subprotocols: [String], headers: [(String, String)]) {
        self.subprotocols = subprotocols
        self.headers = headers
    }
}

@ObjCClass("OS_nw_ws_request")
open class NWWebSocketRequestObject: NWObject {}

final class WebSocketResponseState: NWState {
    let status: Int32
    let subprotocol: HeldCString
    var headers: [(String, String)] = []
    init(status: Int32, subprotocol: String?) {
        self.status = status
        self.subprotocol = HeldCString(subprotocol)
    }
}

@ObjCClass("OS_nw_ws_response")
open class NWWebSocketResponseObject: NWObject {}

private typealias HeaderEnumerator = @convention(c) (UnsafeMutableRawPointer, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Bool

private func enumerateHeaders(_ headers: [(String, String)], _ block: UnsafeMutableRawPointer?) -> Bool {
    guard let block = ObjCBlock.from(block) else { return false }
    for (name, value) in headers {
        let more = name.withCString { name in value.withCString { block.function(as: HeaderEnumerator.self)(block.object, name, $0) } }
        if !more { return false }
    }
    return true
}

@c(_nw_ws_request_enumerate_additional_headers)
public func nw_ws_request_enumerate_additional_headers(_ request: UnsafeMutableRawPointer?, _ block: UnsafeMutableRawPointer?) -> Bool {
    guard let state = NWObjects.state(request, WebSocketRequestState.self) else { return false }
    return enumerateHeaders(state.headers, block)
}

@c(_nw_ws_request_enumerate_subprotocols)
public func nw_ws_request_enumerate_subprotocols(_ request: UnsafeMutableRawPointer?, _ block: UnsafeMutableRawPointer?) -> Bool {
    guard let state = NWObjects.state(request, WebSocketRequestState.self), let block = ObjCBlock.from(block) else { return false }
    typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafePointer<CChar>?) -> Bool
    for name in state.subprotocols where !name.withCString({ block.function(as: Invoke.self)(block.object, $0) }) { return false }
    return true
}

@c(_nw_ws_response_create)
public func nw_ws_response_create(_ status: Int32, _ subprotocol: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    NWObjects.make(NWWebSocketResponseObject.objCClass, WebSocketResponseState(status: status, subprotocol: subprotocol.map { String(cString: $0) }))
}

@c(_nw_ws_response_get_status)
public func nw_ws_response_get_status(_ response: UnsafeMutableRawPointer?) -> Int32 {
    NWObjects.state(response, WebSocketResponseState.self)?.status ?? 0
}

@c(_nw_ws_response_get_selected_subprotocol)
public func nw_ws_response_get_selected_subprotocol(_ response: UnsafeMutableRawPointer?) -> UnsafePointer<CChar>? {
    NWObjects.state(response, WebSocketResponseState.self)?.subprotocol.value
}

@c(_nw_ws_response_add_additional_header)
public func nw_ws_response_add_additional_header(_ response: UnsafeMutableRawPointer?, _ name: UnsafePointer<CChar>?, _ value: UnsafePointer<CChar>?) {
    guard let name, let value else { return }
    NWObjects.state(response, WebSocketResponseState.self)?.headers.append((String(cString: name), String(cString: value)))
}

@c(_nw_ws_response_enumerate_additional_headers)
public func nw_ws_response_enumerate_additional_headers(_ response: UnsafeMutableRawPointer?, _ block: UnsafeMutableRawPointer?) -> Bool {
    guard let state = NWObjects.state(response, WebSocketResponseState.self) else { return false }
    return enumerateHeaders(state.headers, block)
}

// MARK: - The protocol

final class WebSocketLayer: Layer {
    private static let guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    /// nw_ws_response_status_t.
    private static let accept: Int32 = 1

    let options: OptionsState
    let isServer: Bool
    private var open = false
    private var stopped = false
    private var input: [UInt8] = []
    private var key = ""
    private var fragmentOpcode: Int32?
    private var fragment: [UInt8] = []
    private var sendingFragment = false
    private var closeSent = false
    private var closed = false
    private var serverResponse: UnsafeMutableRawPointer?
    private var pongHandlers: [(ObjCBlock, UnsafeMutableRawPointer?)] = []
    private var startTime: UInt64 = 0

    override var kind: ProtocolKind { .webSocket }
    override var deliversMessages: Bool { true }

    init(options: OptionsState, isServer: Bool) {
        self.options = options
        self.isServer = isServer
    }

    deinit {
        ObjCRuntime.release(serverResponse)
        pongHandlers.forEach { ObjCRuntime.release($0.1) }
    }

    override func lowerReady() {
        startTime = monotonicMilliseconds()
        if options.skipHandshake {
            becomeOpen()
            return
        }
        if !isServer { sendRequest() }
        // A server waits for the request.
        if !input.isEmpty { process() }
    }

    private func becomeOpen() {
        open = true
        connection.handshakeTimes.append((.webSocket, monotonicMilliseconds() - startTime))
        readyUp()
        if !input.isEmpty { process() }
    }

    private func sendRequest() {
        var random = SystemRandomNumberGenerator()
        key = Base64.encode((0..<16).map { _ in UInt8.random(in: 0...255, using: &random) })
        let endpoint = connection.endpointState
        let path = endpoint?.type == EndpointType.url ? endpoint!.urlPath : "/"
        var host = endpoint?.hostText ?? "localhost"
        if host.contains(":") { host = "[\(host)]" }
        let port = endpoint?.port ?? 0
        let secure = connection.currentLayers.contains { $0.kind == .tls }
        if port != 0, port != (secure ? 443 : 80) { host += ":\(port)" }
        var request = "GET \(path) HTTP/1.1\r\nHost: \(host)\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
        request += "Sec-WebSocket-Key: \(key)\r\nSec-WebSocket-Version: 13\r\n"
        if !options.subprotocols.isEmpty { request += "Sec-WebSocket-Protocol: \(options.subprotocols.joined(separator: ", "))\r\n" }
        for (name, value) in options.additionalHeaders { request += "\(name): \(value)\r\n" }
        request += "\r\n"
        lower?.send(Array(request.utf8), context: nil, isComplete: false, completion: nil)
    }

    override func lowerReceived(_ data: [UInt8], context: UnsafeMutableRawPointer?, isComplete: Bool) {
        guard !stopped else { return }
        input += data
        if isComplete && data.isEmpty {
            // The stream ended.
            if !open { failUp(.posix(darwin: 54)) } else if !closed { endUp() }
            closed = true
            return
        }
        process()
    }

    private func process() {
        if !open {
            guard let end = headerEnd() else { return }
            let head = String(decoding: input[0..<end], as: UTF8.self)
            input.removeFirst(end + 4)
            if isServer { answer(head) } else { finishClient(head) }
            return
        }
        while !stopped, !closed, let frame = nextFrame() { handle(frame) }
    }

    private func headerEnd() -> Int? {
        guard input.count >= 4 else { return nil }
        for index in 0...(input.count - 4) where input[index] == 13 && input[index + 1] == 10 && input[index + 2] == 13 && input[index + 3] == 10 {
            return index
        }
        return nil
    }

    private func parseHeaders(_ head: String) -> (first: String, headers: [(String, String)]) {
        var lines = head.components(separatedBy: "\r\n")
        let first = lines.isEmpty ? "" : lines.removeFirst()
        var headers: [(String, String)] = []
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: " \t")
            let value = line[line.index(after: colon)...].trimmingCharacters(in: " \t")
            headers.append((name, value))
        }
        return (first, headers)
    }

    private func value(_ name: String, in headers: [(String, String)]) -> String? {
        headers.first { $0.0.lowercased() == name.lowercased() }?.1
    }

    private func acceptKey(for key: String) -> String { Base64.encode(SHA1.hash(Array((key + WebSocketLayer.guid).utf8))) }

    private func finishClient(_ head: String) {
        let (status, headers) = parseHeaders(head)
        let parts = status.split(separator: " ")
        guard parts.count >= 2, parts[1] == "101", value("Sec-WebSocket-Accept", in: headers) == acceptKey(for: key) else {
            networkWarning("WebSocket upgrade refused: \(status)")
            failUp(.posix(darwin: 100))
            return
        }
        let response = WebSocketResponseState(status: WebSocketLayer.accept, subprotocol: value("Sec-WebSocket-Protocol", in: headers))
        response.headers = headers
        serverResponse = NWObjects.make(NWWebSocketResponseObject.objCClass, response)
        becomeOpen()
    }

    private func answer(_ head: String) {
        let (_, headers) = parseHeaders(head)
        guard let clientKey = value("Sec-WebSocket-Key", in: headers), value("Upgrade", in: headers)?.lowercased() == "websocket" else {
            lower?.send(Array("HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n".utf8), context: nil, isComplete: false, completion: nil)
            failUp(.posix(darwin: 100))
            return
        }
        let offered = value("Sec-WebSocket-Protocol", in: headers)?.split(separator: ",").map { $0.trimmingCharacters(in: " \t") } ?? []
        let finish: (UnsafeMutableRawPointer?) -> Void = { [weak self] response in
            guard let self, !self.stopped else { return }
            let state = NWObjects.state(response, WebSocketResponseState.self)
            if let state, state.status != WebSocketLayer.accept {
                self.lower?.send(Array("HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n".utf8), context: nil, isComplete: false, completion: nil)
                self.failUp(.posix(darwin: 61))
                return
            }
            var reply = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
            reply += "Sec-WebSocket-Accept: \(self.acceptKey(for: clientKey))\r\n"
            if let selected = state?.subprotocol.value {
                reply += "Sec-WebSocket-Protocol: \(String(cString: selected))\r\n"
            } else if let first = offered.first(where: { self.options.subprotocols.contains($0) }) {
                reply += "Sec-WebSocket-Protocol: \(first)\r\n"
            }
            for (name, value) in self.options.additionalHeaders + (state?.headers ?? []) { reply += "\(name): \(value)\r\n" }
            reply += "\r\n"
            self.lower?.send(Array(reply.utf8), context: nil, isComplete: false, completion: nil)
            self.becomeOpen()
        }
        guard let handler = options.clientRequestHandler else {
            finish(nil)
            return
        }
        let request = NWObjects.make(NWWebSocketRequestObject.objCClass, WebSocketRequestState(subprotocols: offered, headers: headers))
        let queue = connection.queue
        Dispatch.on(options.clientRequestQueue) {
            typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
            // The block returns its response autoreleased, as an ObjC block does.
            let response = ObjCRuntime.retain(handler.function(as: Invoke.self)(handler.object, request))
            ObjCRuntime.release(request)
            Dispatch.on(queue) {
                finish(response)
                ObjCRuntime.release(response)
            }
        }
    }

    private struct Frame {
        let final: Bool
        let opcode: Int32
        let payload: [UInt8]
    }

    private func nextFrame() -> Frame? {
        guard input.count >= 2 else { return nil }
        let final = input[0] & 0x80 != 0
        let opcode = Int32(input[0] & 0x0F)
        let masked = input[1] & 0x80 != 0
        var length = Int(input[1] & 0x7F)
        var offset = 2
        if length == 126 {
            guard input.count >= 4 else { return nil }
            length = Int(input[2]) << 8 | Int(input[3])
            offset = 4
        } else if length == 127 {
            guard input.count >= 10 else { return nil }
            length = 0
            for index in 2..<10 { length = length << 8 | Int(input[index]) }
            offset = 10
        }
        var mask: [UInt8] = []
        if masked {
            guard input.count >= offset + 4 else { return nil }
            mask = Array(input[offset..<offset + 4])
            offset += 4
        }
        if options.maximumMessageSize > 0, length + fragment.count > options.maximumMessageSize {
            sendClose(1009)
            failUp(.posix(darwin: 40))
            input = []
            return nil
        }
        guard input.count >= offset + length else { return nil }
        var payload = Array(input[offset..<offset + length])
        if masked { for index in payload.indices { payload[index] ^= mask[index & 3] } }
        input.removeFirst(offset + length)
        return Frame(final: final, opcode: opcode, payload: payload)
    }

    private func handle(_ frame: Frame) {
        switch frame.opcode {
        case WebSocketOpcode.continuation, WebSocketOpcode.text, WebSocketOpcode.binary:
            if frame.opcode != WebSocketOpcode.continuation { fragmentOpcode = frame.opcode; fragment = [] }
            fragment += frame.payload
            guard frame.final, let opcode = fragmentOpcode else { return }
            fragmentOpcode = nil
            let message = fragment
            fragment = []
            deliver(message, opcode: opcode)
        case WebSocketOpcode.ping:
            if options.autoReplyPing {
                sendFrame(opcode: WebSocketOpcode.pong, payload: frame.payload, final: true, completion: nil)
            } else {
                deliver(frame.payload, opcode: WebSocketOpcode.ping)
            }
        case WebSocketOpcode.pong:
            if !pongHandlers.isEmpty {
                let (handler, queue) = pongHandlers.removeFirst()
                Dispatch.on(queue) { handler.call(nil) }
                ObjCRuntime.release(queue)
            } else {
                deliver(frame.payload, opcode: WebSocketOpcode.pong)
            }
        case WebSocketOpcode.close:
            var code: Int32 = 1005
            var reason: [UInt8] = []
            if frame.payload.count >= 2 {
                code = Int32(frame.payload[0]) << 8 | Int32(frame.payload[1])
                reason = Array(frame.payload[2...])
            }
            deliver(reason, opcode: WebSocketOpcode.close, closeCode: code)
            if !closeSent { sendClose(code == 1005 ? 1000 : code) }
            closed = true
            lower?.finish()
            endUp()
        default:
            sendClose(1002)
            failUp(.posix(darwin: 100))
        }
    }

    private func deliver(_ payload: [UInt8], opcode: Int32, closeCode: Int32 = 1000) {
        let (metadata, state) = Metadata.make(.webSocket)
        state.opcode = opcode
        state.closeCode = closeCode
        let context = Contexts.message("websocket", metadata: [metadata])
        ObjCRuntime.release(metadata)
        deliverUp(payload, context: context, isComplete: true)
        ObjCRuntime.release(context)
    }

    override func send(_ data: [UInt8], context: UnsafeMutableRawPointer?, isComplete: Bool, completion: SendCompletion?) {
        guard open, !stopped, !closeSent else {
            completion?(.cancelled)
            return
        }
        let metadata = Contexts.state(context)?.metadata(of: .webSocket)
        let opcode = metadata?.opcode ?? WebSocketOpcode.binary
        switch opcode {
        case WebSocketOpcode.close:
            let code = UInt16(truncatingIfNeeded: metadata?.closeCode ?? 1000)
            closeSent = true
            sendFrame(opcode: WebSocketOpcode.close, payload: [UInt8(code >> 8), UInt8(code & 0xFF)] + data, final: true, completion: completion)
        case WebSocketOpcode.ping:
            if let handler = metadata?.pongHandler { pongHandlers.append((handler, ObjCRuntime.retain(metadata?.pongQueue))) }
            sendFrame(opcode: WebSocketOpcode.ping, payload: data, final: true, completion: completion)
        case WebSocketOpcode.pong:
            sendFrame(opcode: WebSocketOpcode.pong, payload: data, final: true, completion: completion)
        default:
            let frameOpcode = sendingFragment ? WebSocketOpcode.continuation : (opcode == WebSocketOpcode.text ? opcode : WebSocketOpcode.binary)
            sendingFragment = !isComplete
            sendFrame(opcode: frameOpcode, payload: data, final: isComplete, completion: completion)
        }
    }

    private func sendClose(_ code: Int32) {
        guard !closeSent else { return }
        closeSent = true
        let value = UInt16(truncatingIfNeeded: code)
        sendFrame(opcode: WebSocketOpcode.close, payload: [UInt8(value >> 8), UInt8(value & 0xFF)], final: true, completion: nil)
    }

    private func sendFrame(opcode: Int32, payload: [UInt8], final: Bool, completion: SendCompletion?) {
        var frame: [UInt8] = [(final ? 0x80 : 0) | UInt8(opcode & 0x0F)]
        let maskBit: UInt8 = isServer ? 0 : 0x80
        if payload.count < 126 {
            frame.append(maskBit | UInt8(payload.count))
        } else if payload.count <= 0xFFFF {
            frame += [maskBit | 126, UInt8(payload.count >> 8), UInt8(payload.count & 0xFF)]
        } else {
            frame.append(maskBit | 127)
            for shift in stride(from: 56, through: 0, by: -8) { frame.append(UInt8((UInt64(payload.count) >> UInt64(shift)) & 0xFF)) }
        }
        if isServer {
            frame += payload
        } else {
            var random = SystemRandomNumberGenerator()
            let mask = (0..<4).map { _ in UInt8.random(in: 0...255, using: &random) }
            frame += mask
            frame += payload.enumerated().map { $0.element ^ mask[$0.offset & 3] }
        }
        lower?.send(frame, context: nil, isComplete: false, completion: completion)
    }

    override func finish() {
        if open, !closeSent { sendClose(1000) }
        lower?.finish()
    }

    override func stop() {
        guard !stopped else { return }
        if open, !closeSent, !closed { sendClose(1001) }
        stopped = true
    }

    override func copyMetadata() -> UnsafeMutableRawPointer? {
        let (object, state) = Metadata.make(.webSocket)
        state.serverResponse = ObjCRuntime.retain(serverResponse)
        return object
    }
}

// MARK: - SHA-1 and Base64, for the upgrade's keys

enum SHA1 {
    static func hash(_ message: [UInt8]) -> [UInt8] {
        var h: [UInt32] = [0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0]
        var data = message
        let bitLength = UInt64(message.count) * 8
        data.append(0x80)
        while data.count % 64 != 56 { data.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) { data.append(UInt8((bitLength >> UInt64(shift)) & 0xFF)) }
        var w = [UInt32](repeating: 0, count: 80)
        for chunk in stride(from: 0, to: data.count, by: 64) {
            for index in 0..<16 {
                let base = chunk + index * 4
                w[index] = UInt32(data[base]) << 24 | UInt32(data[base + 1]) << 16 | UInt32(data[base + 2]) << 8 | UInt32(data[base + 3])
            }
            for index in 16..<80 {
                let value = w[index - 3] ^ w[index - 8] ^ w[index - 14] ^ w[index - 16]
                w[index] = value << 1 | value >> 31
            }
            var (a, b, c, d, e) = (h[0], h[1], h[2], h[3], h[4])
            for index in 0..<80 {
                let f: UInt32
                let k: UInt32
                switch index {
                case 0..<20: f = (b & c) | (~b & d); k = 0x5A827999
                case 20..<40: f = b ^ c ^ d; k = 0x6ED9EBA1
                case 40..<60: f = (b & c) | (b & d) | (c & d); k = 0x8F1BBCDC
                default: f = b ^ c ^ d; k = 0xCA62C1D6
                }
                let temp = (a << 5 | a >> 27) &+ f &+ e &+ k &+ w[index]
                e = d
                d = c
                c = b << 30 | b >> 2
                b = a
                a = temp
            }
            h[0] &+= a; h[1] &+= b; h[2] &+= c; h[3] &+= d; h[4] &+= e
        }
        return h.flatMap { value in [UInt8(value >> 24), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)] }
    }
}

enum Base64 {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)

    static func encode(_ bytes: [UInt8]) -> String {
        var output: [UInt8] = []
        for start in stride(from: 0, to: bytes.count, by: 3) {
            let chunk = Array(bytes[start..<min(start + 3, bytes.count)])
            let value = UInt32(chunk[0]) << 16 | UInt32(chunk.count > 1 ? chunk[1] : 0) << 8 | UInt32(chunk.count > 2 ? chunk[2] : 0)
            output.append(alphabet[Int(value >> 18 & 63)])
            output.append(alphabet[Int(value >> 12 & 63)])
            output.append(chunk.count > 1 ? alphabet[Int(value >> 6 & 63)] : UInt8(ascii: "="))
            output.append(chunk.count > 2 ? alphabet[Int(value & 63)] : UInt8(ascii: "="))
        }
        return String(decoding: output, as: UTF8.self)
    }
}

extension StringProtocol {
    /// The text without the given characters at either end.
    func trimmingCharacters(in set: String) -> String {
        let characters = Set(set)
        var slice = Substring(self)
        while let first = slice.first, characters.contains(first) { slice.removeFirst() }
        while let last = slice.last, characters.contains(last) { slice.removeLast() }
        return String(slice)
    }

    func components(separatedBy separator: String) -> [String] {
        var result: [String] = []
        var rest = Substring(self)
        while let range = rest.firstRange(of: separator) {
            result.append(String(rest[..<range.lowerBound]))
            rest = rest[range.upperBound...]
        }
        result.append(String(rest))
        return result
    }
}

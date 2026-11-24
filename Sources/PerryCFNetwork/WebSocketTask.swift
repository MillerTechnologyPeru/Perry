import FoundationEssentials
import Glibc
import PerryObjCInterop
import PerryURLLoading

// NSURLSessionWebSocketTask: an RFC 6455 client over TaskSocket, with TLS
// for wss. The upgrade is an HTTP/1.1 GET whose answer is checked
// (101, Sec-WebSocket-Accept); messages are framed and masked here, pings
// answered, fragments joined and closes exchanged. No extensions are
// offered (Darwin offers permessage-deflate), so frames are never
// compressed.

// MARK: - Messages

final class WebSocketMessageState {
    /// NSURLSessionWebSocketMessageType: data 0, string 1.
    let type: Int
    let data: Data?
    let string: String?

    init(data: Data) {
        type = 0
        self.data = data
        string = nil
    }

    init(string: String) {
        type = 1
        data = nil
        self.string = string
    }
}

enum WebSocketMessages {
    static let states = StateTable<WebSocketMessageState>()

    /// A message object (+0).
    static func object(_ state: WebSocketMessageState) -> NSObject {
        let object = NSURLSessionWebSocketMessage.objCClass.autoreleasedInstance()
        states.set(object.objcObject, state)
        return object
    }
}

/// NSURLSessionWebSocketMessage: data or a string.
@ObjCClass("NSURLSessionWebSocketMessage")
open class NSURLSessionWebSocketMessage: NSObject {
    var message: WebSocketMessageState? { WebSocketMessages.states.get(objcObject) }

    @ObjCMethod("dealloc")
    func dealloc() {
        WebSocketMessages.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSURLSessionWebSocketMessage.objCClass.pointer)
    }

    @ObjCMethod("initWithData:")
    func initialize(data: NSData?) -> Self {
        WebSocketMessages.states.set(objcObject, WebSocketMessageState(data: data?.data ?? Data()))
        return self
    }

    @ObjCMethod("initWithString:")
    func initialize(string: String?) -> Self {
        WebSocketMessages.states.set(objcObject, WebSocketMessageState(string: string ?? ""))
        return self
    }

    @ObjCMethod("type") func type() -> Int { message?.type ?? 0 }
    @ObjCMethod("data") func data() -> NSData? { message?.data.map(NSData.of) }
    @ObjCMethod("string") func string() -> String? { message?.string }
}

// MARK: - Framing

enum WebSocketFrames {
    static let continuation: UInt8 = 0, text: UInt8 = 1, binary: UInt8 = 2, close: UInt8 = 8, ping: UInt8 = 9, pong: UInt8 = 10
    static let guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    /// A client's frame: final, masked with a random key.
    static func frame(_ opcode: UInt8, _ payload: [UInt8]) -> [UInt8] {
        var frame: [UInt8] = [0x80 | opcode]
        let count = payload.count
        if count < 126 {
            frame.append(0x80 | UInt8(count))
        } else if count <= 0xFFFF {
            frame += [0x80 | 126, UInt8(count >> 8), UInt8(count & 0xFF)]
        } else {
            frame.append(0x80 | 127)
            for shift in stride(from: 56, through: 0, by: -8) { frame.append(UInt8((UInt64(count) >> UInt64(shift)) & 0xFF)) }
        }
        let mask = (0..<4).map { _ in UInt8.random(in: 0...255) }
        frame += mask
        frame += payload.enumerated().map { $0.element ^ mask[$0.offset & 3] }
        return frame
    }

    /// A close frame's payload: the code, then the reason. Codes that
    /// never go on the wire (none, 1005, 1006, 1015) make an empty one.
    static func closePayload(code: Int, reason: Data?) -> [UInt8] {
        guard code > 0, code != 1005, code != 1006, code != 1015 else { return [] }
        return [UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF)] + Array((reason ?? Data()).prefix(123))
    }

    /// Sec-WebSocket-Accept for a key.
    static func accept(_ key: String) -> String { Data(sha1(Array((key + guid).utf8))).base64EncodedString() }

    static func sha1(_ message: [UInt8]) -> [UInt8] {
        var hash: [UInt32] = [0x6745_2301, 0xEFCD_AB89, 0x98BA_DCFE, 0x1032_5476, 0xC3D2_E1F0]
        var bytes = message + [0x80]
        while bytes.count % 64 != 56 { bytes.append(0) }
        let bits = UInt64(message.count) * 8
        for shift in stride(from: 56, through: 0, by: -8) { bytes.append(UInt8((bits >> UInt64(shift)) & 0xFF)) }
        for chunk in stride(from: 0, to: bytes.count, by: 64) {
            var words = [UInt32](repeating: 0, count: 80)
            for index in 0..<16 {
                let at = chunk + index * 4
                words[index] = UInt32(bytes[at]) << 24 | UInt32(bytes[at + 1]) << 16 | UInt32(bytes[at + 2]) << 8 | UInt32(bytes[at + 3])
            }
            for index in 16..<80 {
                let value = words[index - 3] ^ words[index - 8] ^ words[index - 14] ^ words[index - 16]
                words[index] = value << 1 | value >> 31
            }
            var (a, b, c, d, e) = (hash[0], hash[1], hash[2], hash[3], hash[4])
            for index in 0..<80 {
                var f: UInt32 = 0, k: UInt32 = 0
                switch index {
                case 0..<20: (f, k) = ((b & c) | (~b & d), 0x5A82_7999)
                case 20..<40: (f, k) = (b ^ c ^ d, 0x6ED9_EBA1)
                case 40..<60: (f, k) = ((b & c) | (b & d) | (c & d), 0x8F1B_BCDC)
                default: (f, k) = (b ^ c ^ d, 0xCA62_C1D6)
                }
                let temp = (a << 5 | a >> 27) &+ f &+ e &+ k &+ words[index]
                (e, d, c, b, a) = (d, c, b << 30 | b >> 2, a, temp)
            }
            hash[0] = hash[0] &+ a
            hash[1] = hash[1] &+ b
            hash[2] = hash[2] &+ c
            hash[3] = hash[3] &+ d
            hash[4] = hash[4] &+ e
        }
        return hash.flatMap { word in [24, 16, 8, 0].map { UInt8((word >> UInt32($0)) & 0xFF) } }
    }
}

// MARK: - The task

final class WebSocketTaskState: SocketTaskState {
    /// The ws or wss URL.
    let url: URL
    let secure: Bool
    let protocols: [String]
    let key: String
    let socket: TaskSocket
    private let writes = SocketTaskQueue()
    private let opened = SocketTaskGate()

    private var maximumSize = 1 << 20
    private var code = 0
    private var reason: Data?
    /// Messages that came before anyone asked for them, and those who wait.
    private var messages: [WebSocketMessageState] = []
    private var receivers: [ObjCBlock] = []
    private var pongHandlers: [ObjCBlock] = []
    /// Why receives, sends and pings fail once the connection is over.
    private var terminal: NSError?
    /// A close frame was sent; the program asked for it (cancelWithCloseCode:reason:).
    private var sentClose = false
    private var closedByProgram = false
    private var cancelledByProgram = false
    /// The upgrade succeeded.
    private var isOpen = false

    init(session: UnsafeMutableRawPointer, url: URL, request: Request, protocols: [String], object: UnsafeMutableRawPointer) {
        let isSecure = url.scheme?.lowercased() == "wss"
        let made = Data((0..<16).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
        self.url = url
        secure = isSecure
        self.protocols = protocols
        key = made
        socket = TaskSocket(host: url.host ?? "", port: url.port ?? (isSecure ? 443 : 80))
        // The request as Darwin shows it: http or https, with the upgrade's
        // headers.
        if var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            parts.scheme = isSecure ? "https" : "http"
            request.url = parts.url
        }
        request.setHeader("Upgrade", for: "Connection")
        request.setHeader("websocket", for: "Upgrade")
        request.setHeader(made, for: "Sec-WebSocket-Key")
        request.setHeader("13", for: "Sec-WebSocket-Version")
        if !protocols.isEmpty { request.setHeader(protocols.joined(separator: ", "), for: "Sec-WebSocket-Protocol") }
        super.init(session: session, request: request, object: object)
    }

    var maximumMessageSize: Int {
        get { lock.withLock { maximumSize } }
        set { lock.withLock { maximumSize = newValue } }
    }

    var closeCode: Int { lock.withLock { code } }
    var closeReason: Data? { lock.withLock { reason } }

    // MARK: Opening

    override func start() {
        SocketTaskThreads.spawn { [self] in
            let deadline = TaskClock.now() + (originalRequest.timeout > 0 ? originalRequest.timeout : 60)
            var leftover: [UInt8] = []
            if let failure = open(deadline: deadline, leftover: &leftover) {
                fail(failure)
                return
            }
            lock.withLock { isOpen = true }
            opened.open(nil)
            receive(leftover)
        }
    }

    /// Connects and upgrades: nil once open, else the error.
    private func open(deadline: Double, leftover: inout [UInt8]) -> NSError? {
        if let failure = socket.connect(deadline: deadline) { return SocketTaskErrors.connectError(failure, url) }
        if secure, socket.startTLS(peerName: url.host ?? "", deadline: deadline) != nil {
            return socket.isClosed ? SocketTaskErrors.cancelledError(url) : SocketTaskErrors.secureConnectionFailed(url)
        }
        var path = url.path(percentEncoded: true)
        if path.isEmpty { path = "/" }
        if let query = url.query(percentEncoded: true) { path += "?" + query }
        var hostHeader = url.host ?? ""
        if hostHeader.contains(":") { hostHeader = "[" + hostHeader + "]" }
        if let port = url.port, port != (secure ? 443 : 80) { hostHeader += ":\(port)" }
        var request = "GET \(path) HTTP/1.1\r\nHost: \(hostHeader)\r\n"
        let order = ["Upgrade", "Connection", "Sec-WebSocket-Key", "Sec-WebSocket-Version", "Sec-WebSocket-Protocol"]
        let headers = originalRequest.headers ?? [:]
        for name in order { if let value = headers.first(where: { $0.key.lowercased() == name.lowercased() })?.value { request += "\(name): \(value)\r\n" } }
        for (name, value) in headers.sorted(by: { $0.key < $1.key })
        where !order.contains(where: { $0.lowercased() == name.lowercased() }) && name.lowercased() != "host" {
            request += "\(name): \(value)\r\n"
        }
        request += "\r\n"
        if let failure = socket.write(Array(request.utf8), deadline: deadline) {
            return failure == SocketTaskErrors.cancelled ? SocketTaskErrors.cancelledError(url)
                : SocketTaskErrors.urlError(-1005, "The network connection was lost.", url)
        }
        // The answer's head, up to the blank line.
        var head: [UInt8] = []
        while true {
            if let end = WebSocketTaskState.headEnd(head) {
                leftover = Array(head[end...])
                head = Array(head[..<end])
                break
            }
            guard head.count < 65536 else { return badResponse() }
            switch socket.read(limit: 4096, deadline: deadline) {
            case .data(let bytes): head += bytes
            case .end: return badResponse()
            case .failed(let code):
                if code == SocketTaskErrors.cancelled { return SocketTaskErrors.cancelledError(url) }
                return code == SocketTaskErrors.timedOut ? SocketTaskErrors.urlError(-1001, "The request timed out.", url) : badResponse()
            }
        }
        // "\r\n" is one Character.
        let lines = String(decoding: head, as: UTF8.self).split(separator: "\r\n").map(String.init)
        let status = lines.first?.split(separator: " ").dropFirst().first.flatMap { Int($0) } ?? 0
        var fields: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            fields[name] = fields[name].map { $0 + ", " + value } ?? value
        }
        func field(_ name: String) -> String? { fields.first { $0.key.lowercased() == name.lowercased() }?.value }
        if let response = Response(url: originalRequest.url ?? url, statusCode: status, httpVersion: "HTTP/1.1", headers: fields) {
            setResponse(response)
        }
        guard status == 101, field("Upgrade")?.lowercased() == "websocket", field("Sec-WebSocket-Accept") == WebSocketFrames.accept(key) else {
            return badResponse()
        }
        let chosen = field("Sec-WebSocket-Protocol")
        deliver { [self] in
            let selector = "URLSession:webSocketTask:didOpenWithProtocol:"
            guard let delegate = delegate(for: selector) else { return }
            let name = chosen.map { NSObject.string($0) }
            unsafeBitCast(ObjCRuntime.msgSend, to: (@convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeMutableRawPointer?,
                                                                    UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void).self)(
                delegate.objcObject, ObjCRuntime.selector(selector), session, object, name?.objcObject)
        }
        return nil
    }

    private static func headEnd(_ bytes: [UInt8]) -> Int? {
        guard bytes.count >= 4 else { return nil }
        for index in 0...(bytes.count - 4) where bytes[index] == 13 && bytes[index + 1] == 10 && bytes[index + 2] == 13 && bytes[index + 3] == 10 {
            return index + 4
        }
        return nil
    }

    private func badResponse() -> NSError { SocketTaskErrors.urlError(-1011, "There was a bad response from the server.", url) }

    // MARK: Receiving

    /// Reads frames until the connection ends.
    private func receive(_ leftover: [UInt8]) {
        var buffer = leftover
        var fragments: [UInt8] = []
        var fragmentType: UInt8?
        func need(_ count: Int) -> Bool {
            while buffer.count < count {
                switch socket.read(limit: max(65536, count - buffer.count), deadline: nil) {
                case .data(let bytes):
                    buffer += bytes
                    countReceived(bytes.count)
                case .end, .failed:
                    return false
                }
            }
            return true
        }
        while need(2) {
            let first = buffer[0], second = buffer[1]
            let opcode = first & 0x0F, isFinal = first & 0x80 != 0, masked = second & 0x80 != 0
            var length = Int(second & 0x7F), header = 2
            if length == 126 {
                guard need(4) else { break }
                length = Int(buffer[2]) << 8 | Int(buffer[3])
                header = 4
            } else if length == 127 {
                guard need(10) else { break }
                length = (2..<10).reduce(0) { $0 << 8 | Int(buffer[$1]) }
                header = 10
            }
            if masked { header += 4 }
            if opcode < 8, fragments.count + length > maximumMessageSize {
                return closeForError(1009, SocketTaskErrors.posix(SocketTaskErrors.messageTooLong))
            }
            guard length >= 0, need(header + length) else { break }
            var payload = Array(buffer[header..<(header + length)])
            if masked {
                let mask = Array(buffer[(header - 4)..<header])
                for index in payload.indices { payload[index] ^= mask[index & 3] }
            }
            buffer.removeFirst(header + length)
            switch opcode {
            case WebSocketFrames.continuation, WebSocketFrames.text, WebSocketFrames.binary:
                if opcode != WebSocketFrames.continuation {
                    fragmentType = opcode
                    fragments = []
                }
                guard let type = fragmentType else { return closeForError(1002, badResponse()) }
                fragments += payload
                guard isFinal else { continue }
                let message = type == WebSocketFrames.text ? WebSocketMessageState(string: String(decoding: fragments, as: UTF8.self))
                    : WebSocketMessageState(data: Data(fragments))
                (fragments, fragmentType) = ([], nil)
                arrived(message)
            case WebSocketFrames.ping:
                writeFrame(WebSocketFrames.pong, payload)
            case WebSocketFrames.pong:
                let handler: ObjCBlock? = lock.withLock { pongHandlers.isEmpty ? nil : pongHandlers.removeFirst() }
                call(handler, error: nil)
            case WebSocketFrames.close:
                let peerCode = payload.count >= 2 ? Int(payload[0]) << 8 | Int(payload[1]) : 1005
                let peerReason = payload.count > 2 ? Data(payload[2...]) : nil
                return peerClosed(code: peerCode, reason: peerReason)
            default:
                return closeForError(1002, badResponse())
            }
        }
        ended()
    }

    private func arrived(_ message: WebSocketMessageState) {
        let receiver: ObjCBlock? = lock.withLock {
            guard !receivers.isEmpty else {
                messages.append(message)
                return nil
            }
            return receivers.removeFirst()
        }
        if let receiver { hand(message, to: receiver) }
    }

    private func hand(_ message: WebSocketMessageState?, to handler: ObjCBlock, error: NSError? = nil) {
        nonisolated(unsafe) let block = handler
        deliver {
            let object = message.map(WebSocketMessages.object)
            block.function(as: (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void).self)(
                block.object, object?.objcObject, error?.objcObject)
        }
    }

    /// The server closed: its close is echoed (unless it answers ours),
    /// the delegate told, and the task completes without an error.
    private func peerClosed(code peerCode: Int, reason peerReason: Data?) {
        let answer: Bool = lock.withLock {
            code = peerCode
            reason = peerReason
            if terminal == nil {
                terminal = closedByProgram || cancelledByProgram ? SocketTaskErrors.cancelledError(url)
                    : SocketTaskErrors.posix(SocketTaskErrors.notConnected)
            }
            defer { sentClose = true }
            return !sentClose
        }
        if answer {
            writes.async { [self] in
                // The answer echoes the server's code and reason, as Darwin's does.
                _ = socket.write(WebSocketFrames.frame(WebSocketFrames.close, WebSocketFrames.closePayload(code: peerCode, reason: peerReason)),
                                 deadline: TaskClock.now() + 5)
                socket.close()
            }
        } else {
            socket.close()
        }
        deliver { [self] in
            let selector = "URLSession:webSocketTask:didCloseWithCode:reason:"
            guard let delegate = delegate(for: selector) else { return }
            let data = peerReason.map(NSData.of)
            unsafeBitCast(ObjCRuntime.msgSend, to: (@convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeMutableRawPointer?,
                                                                    UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?) -> Void).self)(
                delegate.objcObject, ObjCRuntime.selector(selector), session, object, peerCode, data?.objcObject)
        }
        finish(cancelledByProgram ? SocketTaskErrors.cancelledError(url) : nil)
    }

    /// The connection ended without a close frame.
    private func ended() {
        let (program, cancelled): (Bool, Bool) = lock.withLock {
            if terminal == nil { terminal = SocketTaskErrors.posix(SocketTaskErrors.notConnected) }
            return (closedByProgram, cancelledByProgram)
        }
        socket.close()
        if cancelled {
            finish(SocketTaskErrors.cancelledError(url))
        } else {
            finish(program ? nil : SocketTaskErrors.urlError(-1005, "The network connection was lost.", url))
        }
    }

    /// Closes with `closeCode` for a protocol error or an oversized
    /// message, failing what waits with `error`.
    private func closeForError(_ closeCode: Int, _ error: NSError) {
        lock.withLock {
            if terminal == nil { terminal = error }
            if code == 0 { code = closeCode }
            sentClose = true
        }
        writes.async { [self] in
            _ = socket.write(WebSocketFrames.frame(WebSocketFrames.close, WebSocketFrames.closePayload(code: closeCode, reason: nil)),
                             deadline: TaskClock.now() + 5)
            socket.close()
        }
        finish(error)
    }

    /// Fails before opening: what waits is given the error, as the task is.
    private func fail(_ error: NSError) {
        lock.withLock { if terminal == nil { terminal = error } }
        opened.open(error)
        socket.close()
        finish(error)
    }

    /// Gives what waits the terminal error, then completes.
    private func finish(_ error: NSError?) {
        let (waiting, pongs, failure): ([ObjCBlock], [ObjCBlock], NSError?) = lock.withLock {
            defer {
                receivers = []
                pongHandlers = []
            }
            return (receivers, pongHandlers, terminal)
        }
        opened.open(failure)
        for receiver in waiting { hand(nil, to: receiver, error: failure) }
        for handler in pongs { call(handler, error: failure) }
        complete(error)
    }

    // MARK: The program's calls

    private func writeFrame(_ opcode: UInt8, _ payload: [UInt8], then handler: ObjCBlock? = nil) {
        writes.async { [self] in
            var error = opened.wait()
            if error == nil, opcode != WebSocketFrames.close, opcode != WebSocketFrames.pong, let failure = lock.withLock({ terminal }) {
                error = failure
            }
            if error == nil, let code = socket.write(WebSocketFrames.frame(opcode, payload), deadline: nil) {
                error = lock.withLock { terminal } ?? SocketTaskErrors.posix(code == SocketTaskErrors.cancelled ? SocketTaskErrors.notConnected : code)
            } else if error == nil {
                countSent(payload.count)
            }
            call(handler, error: error)
        }
    }

    func send(_ message: WebSocketMessageState?, handler: ObjCBlock?) {
        guard let message else { return call(handler, error: SocketTaskErrors.posix(22)) }
        if let string = message.string {
            writeFrame(WebSocketFrames.text, Array(string.utf8), then: handler)
        } else {
            writeFrame(WebSocketFrames.binary, [UInt8](message.data ?? Data()), then: handler)
        }
    }

    func receive(handler: ObjCBlock?) {
        guard let handler else { return }
        let (message, failure): (WebSocketMessageState?, NSError?) = lock.withLock {
            if !messages.isEmpty { return (messages.removeFirst(), nil) }
            if let terminal { return (nil, terminal) }
            receivers.append(handler)
            return (nil, nil)
        }
        if message != nil || failure != nil { hand(message, to: handler, error: failure) }
    }

    func ping(handler: ObjCBlock?) {
        let failure: NSError? = lock.withLock {
            if let terminal { return terminal }
            if let handler { pongHandlers.append(handler) }
            return nil
        }
        if let failure { return call(handler, error: failure) }
        writes.async { [self] in
            guard opened.wait() == nil else { return }
            let payload = (0..<4).map { _ in UInt8.random(in: 0...255) }
            if socket.write(WebSocketFrames.frame(WebSocketFrames.ping, payload), deadline: nil) == nil { countSent(payload.count) }
        }
    }

    /// Sends a close with the code and reason and waits (a few seconds at
    /// most) for the server's; the task then completes without an error.
    func close(code closeCode: Int, reason closeReason: Data?) {
        let send: Bool = lock.withLock {
            guard !sentClose, terminal == nil else { return false }
            sentClose = true
            closedByProgram = true
            code = closeCode
            reason = closeReason
            terminal = SocketTaskErrors.cancelledError(url)
            return true
        }
        guard send else { return }
        guard hasStarted else {
            lock.withLock { cancelledByProgram = true }
            return fail(SocketTaskErrors.cancelledError(url))
        }
        writes.async { [self] in
            guard opened.wait() == nil else { return }
            _ = socket.write(WebSocketFrames.frame(WebSocketFrames.close, WebSocketFrames.closePayload(code: closeCode, reason: closeReason)),
                             deadline: TaskClock.now() + 5)
            let deadline = TaskClock.now() + 5
            SocketTaskThreads.spawn { [self] in
                while !isCompleted, TaskClock.now() < deadline { usleep(20000) }
                socket.close()
            }
        }
    }

    /// Going away (1001) when open, then NSURLErrorCancelled.
    override func cancel() {
        let first: Bool = lock.withLock {
            guard !cancelledByProgram else { return false }
            cancelledByProgram = true
            if terminal == nil { terminal = SocketTaskErrors.cancelledError(url) }
            return true
        }
        guard first, !isCompleted else { return }
        _ = beginCancelling()
        guard hasStarted else { return fail(SocketTaskErrors.cancelledError(url)) }
        let (isUp, alreadyClosing): (Bool, Bool) = lock.withLock {
            defer { sentClose = true }
            return (isOpen, sentClose)
        }
        // The reader then finds the connection gone and completes the task;
        // one still opening fails to.
        guard isUp, !alreadyClosing else { return socket.close() }
        writes.async { [self] in
            _ = socket.write(WebSocketFrames.frame(WebSocketFrames.close, WebSocketFrames.closePayload(code: 1001, reason: nil)),
                             deadline: TaskClock.now() + 1)
            socket.close()
        }
    }
}

enum WebSocketTasks {
    static func state(_ object: UnsafeMutableRawPointer) -> WebSocketTaskState? { SocketTasks.states.get(object) as? WebSocketTaskState }

    /// A task for a ws or wss request; another scheme raises
    /// NSGenericException, as on Darwin.
    static func make(session: UnsafeMutableRawPointer, request: Request, protocols: [String]) -> NSObject {
        guard let url = request.url, let scheme = url.scheme?.lowercased(), scheme == "ws" || scheme == "wss" else {
            NetworkExceptions.raise("NSGenericException", "WebSocket tasks can only be created with ws or wss schemes")
        }
        let object = NSURLSessionWebSocketTask.objCClass.autoreleasedInstance()
        let state = WebSocketTaskState(session: session, url: url, request: request, protocols: protocols, object: object.objcObject)
        SocketTasks.states.set(object.objcObject, state)
        return object
    }
}

@ObjCWrapper("NSException")
class NSException: NSObject {
    @ObjCClassMethod("exceptionWithName:reason:userInfo:") static func make(name: String, reason: String?, userInfo: NSDictionary?) -> NSException
    @ObjCMethod("raise") func raise()
}

enum NetworkExceptions {
    /// Raises an Objective-C exception, as CFNetwork does.
    static func raise(_ name: String, _ reason: String) -> Never {
        NSException.make(name: name, reason: reason, userInfo: nil).raise()
        networkFatal("\(name): \(reason)")
    }
}

/// NSURLSessionWebSocketTask.
@ObjCClass("NSURLSessionWebSocketTask")
open class NSURLSessionWebSocketTask: NSURLSessionTask {
    private var socketState: WebSocketTaskState? { WebSocketTasks.state(objcObject) }

    /// The handler: void (^)(NSError *error), once the message is written.
    @ObjCMethod("sendMessage:completionHandler:")
    func sendMessage(_ message: NSObject?, completionHandler: ObjCBlock?) {
        socketState?.send(message.flatMap { WebSocketMessages.states.get($0.objcObject) }, handler: completionHandler)
    }

    /// The handler: void (^)(NSURLSessionWebSocketMessage *, NSError *).
    @ObjCMethod("receiveMessageWithCompletionHandler:")
    func receiveMessage(completionHandler: ObjCBlock?) { socketState?.receive(handler: completionHandler) }

    /// The handler runs when the server's pong comes, or with an error.
    @ObjCMethod("sendPingWithPongReceiveHandler:")
    func sendPing(pongReceiveHandler: ObjCBlock?) { socketState?.ping(handler: pongReceiveHandler) }

    @ObjCMethod("cancelWithCloseCode:reason:")
    func cancel(closeCode: Int, reason: NSData?) { socketState?.close(code: closeCode, reason: reason?.data) }

    /// Larger messages close the connection (1009); 1 MiB at first.
    @ObjCMethod("maximumMessageSize") func maximumMessageSize() -> Int { socketState?.maximumMessageSize ?? 1 << 20 }
    @ObjCMethod("setMaximumMessageSize:") func setMaximumMessageSize(_ size: Int) { socketState?.maximumMessageSize = size }

    /// The close's code: the server's once it closed, else the one the
    /// program closed with; NSURLSessionWebSocketCloseCodeInvalid (0) before.
    @ObjCMethod("closeCode") func closeCode() -> Int { socketState?.closeCode ?? 0 }
    @ObjCMethod("closeReason") func closeReason() -> NSData? { socketState?.closeReason.map(NSData.of) }
}

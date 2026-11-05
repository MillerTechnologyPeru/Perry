import FoundationEssentials
import Glibc
import HTTPTypes
import PerryObjCInterop

// CFHTTPMessage: an HTTP/1 request or response, its head as swift-http-types'
// HTTPRequest or HTTPResponse, and its body. Messages are made whole, or
// parsed from bytes as they arrive (CFHTTPMessageAppendBytes, as a server
// reads a request), and serialized as HTTP/1.1.
//
// HTTP read streams (CFReadStreamCreateForHTTPRequest) aren't made yet:
// creating one fails, as it does without a network, and apps report the
// request as failed.

/// A message's state.
final class HTTPMessage {
    enum Head {
        case request(HTTPRequest)
        case response(HTTPResponse)
    }

    let isRequest: Bool
    /// Nil until an empty message has parsed its head.
    var head: Head?
    /// The request's URL as the app gave it, kept to return as given.
    var url: URL?
    var version: String
    var body = Data()
    /// Bytes appended before the head was complete.
    private var pending: [UInt8] = []
    private var failed = false

    init(isRequest: Bool, head: Head?, url: URL? = nil, version: String) {
        self.isRequest = isRequest
        self.head = head
        self.url = url
        self.version = version
    }

    var fields: HTTPFields {
        get {
            switch head {
            case .request(let request): return request.headerFields
            case .response(let response): return response.headerFields
            case nil: return HTTPFields()
            }
        }
        set {
            switch head {
            case .request(var request): request.headerFields = newValue; head = .request(request)
            case .response(var response): response.headerFields = newValue; head = .response(response)
            case nil: break
            }
        }
    }

    var isHeaderComplete: Bool { head != nil }

    // MARK: Parsing

    /// Appends bytes: the head's until it is complete, then the body's.
    /// False if the head is malformed.
    func append(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool {
        if failed { return false }
        if head != nil {
            body.append(contentsOf: bytes)
            return true
        }
        pending.append(contentsOf: bytes)
        guard let end = Self.headEnd(pending) else { return true }
        let text = String(decoding: pending[..<end.head], as: UTF8.self)
        let rest = pending[end.body...]
        pending = []
        guard parseHead(text) else {
            failed = true
            return false
        }
        body.append(contentsOf: rest)
        return true
    }

    /// Where the head's blank line is, and the body after it.
    private static func headEnd(_ bytes: [UInt8]) -> (head: Int, body: Int)? {
        var index = 0
        while index < bytes.count {
            if bytes[index] == 0x0A {
                // "\n\n" or "\r\n\r\n", the blank line ending the head.
                if index + 1 < bytes.count, bytes[index + 1] == 0x0A { return (index, index + 2) }
                if index + 2 < bytes.count, bytes[index + 1] == 0x0D, bytes[index + 2] == 0x0A { return (index, index + 3) }
            }
            index += 1
        }
        return nil
    }

    private func parseHead(_ text: String) -> Bool {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map {
            $0.hasSuffix("\r") ? String($0.dropLast()) : String($0)
        }
        while lines.first?.isEmpty == true { lines.removeFirst() }    // tolerated before a request line
        guard let start = lines.first else { return false }
        var fields = HTTPFields()
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":"), let name = HTTPField.Name(Self.trimmed(line[..<colon])) else { return false }
            fields.append(HTTPField(name: name, value: Self.trimmed(line[line.index(after: colon)...])))
        }
        let parts = start.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true).map(String.init)
        if isRequest {
            // METHOD target HTTP/1.x
            guard parts.count == 3, let method = HTTPRequest.Method(parts[0]) else { return false }
            version = parts[2]
            let target = parts[1]
            // HTTP/1's Host field, which HTTP/2 and 3 carry as the authority.
            let host = HTTPField.Name("Host").flatMap { fields[$0] }
            if target.hasPrefix("http://") || target.hasPrefix("https://"), let absolute = URL(string: target) {
                url = absolute
            } else {
                url = URL(string: "http://\(host ?? "localhost")\(target)")
            }
            var request = HTTPRequest(method: method, scheme: url?.scheme, authority: host ?? url.map(Self.authority), path: target)
            request.headerFields = fields
            head = .request(request)
        } else {
            // HTTP/1.x code reason
            guard parts.count >= 2, parts[0].hasPrefix("HTTP/"), let code = Int(parts[1]), (100...999).contains(code) else { return false }
            version = parts[0]
            head = .response(HTTPResponse(status: .init(code: code, reasonPhrase: parts.count > 2 ? parts[2] : ""), headerFields: fields))
        }
        return true
    }

    /// Without leading and trailing spaces and tabs.
    static func trimmed(_ text: Substring) -> String {
        String(text.drop { $0 == " " || $0 == "\t" }.reversed().drop { $0 == " " || $0 == "\t" }.reversed())
    }

    static func authority(_ url: URL) -> String {
        let host = url.host(percentEncoded: true) ?? ""
        return url.port.map { "\(host):\($0)" } ?? host
    }

    /// The path and query a request line names.
    static func target(_ url: URL) -> String {
        let path = url.path(percentEncoded: true)
        let query = url.query(percentEncoded: true).map { "?" + $0 } ?? ""
        return (path.isEmpty ? "/" : path) + query
    }

    // MARK: Serializing

    /// The message as HTTP/1.1 sends it; nil while an empty message has no
    /// head.
    func serialized() -> Data? {
        var text: String
        switch head {
        case .request(let request):
            text = "\(request.method.rawValue) \(request.path ?? "/") \(version)\r\n"
        case .response(let response):
            let reason = response.status.reasonPhrase
            text = "\(version) \(response.status.code)\(reason.isEmpty ? "" : " " + reason)\r\n"
        case nil:
            return nil
        }
        for field in fields { text += "\(field.name.rawName): \(field.value)\r\n" }
        text += "\r\n"
        var data = Data(text.utf8)
        data.append(body)
        return data
    }

    /// The header fields as a dictionary, the values of repeated fields
    /// joined with commas.
    var headerDictionary: [(String, String)] {
        var order: [String] = []
        var values: [String: (name: String, value: String)] = [:]
        for field in fields {
            let key = field.name.canonicalName
            if let existing = values[key] {
                values[key] = (existing.name, existing.value + ", " + field.value)
            } else {
                values[key] = (field.name.rawName, field.value)
                order.append(key)
            }
        }
        return order.compactMap { values[$0].map { ($0.name, $0.value) } }
    }
}

enum HTTPMessages {
    static let states = StateTable<HTTPMessage>()

    static func message(_ object: UnsafeMutableRawPointer?) -> HTTPMessage? { object.flatMap { states.get($0) } }

    /// A new message object, +1, as CF's Create functions return.
    static func make(_ message: HTTPMessage) -> UnsafeMutableRawPointer {
        let object = CFHTTPMessageObject.objCClass.autoreleasedInstance()
        states.set(object.objcObject, message)
        return ObjCRuntime.retain(object.objcObject)!
    }

    /// A string, +1.
    static func copy(_ string: String?) -> UnsafeMutableRawPointer? {
        string.flatMap { ObjCRuntime.retain(NSObject.string($0).objcObject) }
    }

    /// Said once for each function.
    nonisolated(unsafe) private static var said: Set<String> = []
    static func unsupported(_ function: String) {
        guard said.insert(function).inserted else { return }
        let line = "perry: CFNetwork: \(function) isn't supported; the request fails\n"
        _ = line.withCString { write(2, $0, strlen($0)) }
    }

    static func string(_ object: UnsafeMutableRawPointer?) -> String? {
        object.map { NSObject($0) }.flatMap { $0.isString ? $0.stringValue : nil }
    }
}

/// CFHTTPMessageRef's class.
@ObjCClass("__NSCFHTTPMessage")
final class CFHTTPMessageObject: NSObject {
    @ObjCMethod("dealloc")
    func dealloc() {
        HTTPMessages.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CFHTTPMessageObject.objCClass.pointer)
    }

    @ObjCMethod("description")
    func description() -> String {
        guard let message = HTTPMessages.message(objcObject) else { return "<CFHTTPMessage>" }
        switch message.head {
        case .request(let request): return "<CFHTTPMessage request \(request.method.rawValue) \(message.url?.absoluteString ?? "")>"
        case .response(let response): return "<CFHTTPMessage response \(response.status.code)>"
        case nil: return "<CFHTTPMessage \(message.isRequest ? "request" : "response"), head incomplete>"
        }
    }
}

// MARK: - Creating

@c(_CFHTTPMessageCreateRequest)
public func CFHTTPMessageCreateRequest(_ allocator: UnsafeRawPointer?, _ method: UnsafeMutableRawPointer?, _ url: UnsafeMutableRawPointer?,
                                       _ version: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let methodName = HTTPMessages.string(method), let parsedMethod = HTTPRequest.Method(methodName),
          let url, let text = NSObject(url).unsafeCast(to: NSURL.self).absoluteString(), let parsed = URL(string: text) else { return nil }
    let request = HTTPRequest(method: parsedMethod, scheme: parsed.scheme, authority: HTTPMessage.authority(parsed),
                              path: HTTPMessage.target(parsed))
    return HTTPMessages.make(HTTPMessage(isRequest: true, head: .request(request), url: parsed,
                                         version: HTTPMessages.string(version) ?? "HTTP/1.1"))
}

@c(_CFHTTPMessageCreateResponse)
public func CFHTTPMessageCreateResponse(_ allocator: UnsafeRawPointer?, _ status: Int, _ description: UnsafeMutableRawPointer?,
                                        _ version: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard (100...999).contains(status) else { return nil }
    let response = HTTPResponse(status: .init(code: status, reasonPhrase: HTTPMessages.string(description) ?? ""))
    return HTTPMessages.make(HTTPMessage(isRequest: false, head: .response(response), version: HTTPMessages.string(version) ?? "HTTP/1.1"))
}

@c(_CFHTTPMessageCreateEmpty)
public func CFHTTPMessageCreateEmpty(_ allocator: UnsafeRawPointer?, _ isRequest: UInt8) -> UnsafeMutableRawPointer? {
    HTTPMessages.make(HTTPMessage(isRequest: isRequest != 0, head: nil, version: "HTTP/1.1"))
}

@c(_CFHTTPMessageCreateCopy)
public func CFHTTPMessageCreateCopy(_ allocator: UnsafeRawPointer?, _ message: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let original = HTTPMessages.message(message) else { return nil }
    let copy = HTTPMessage(isRequest: original.isRequest, head: original.head, url: original.url, version: original.version)
    copy.body = original.body
    return HTTPMessages.make(copy)
}

// MARK: - Reading

@c(_CFHTTPMessageIsRequest)
public func CFHTTPMessageIsRequest(_ message: UnsafeMutableRawPointer?) -> UInt8 {
    HTTPMessages.message(message)?.isRequest == true ? 1 : 0
}

@c(_CFHTTPMessageIsHeaderComplete)
public func CFHTTPMessageIsHeaderComplete(_ message: UnsafeMutableRawPointer?) -> UInt8 {
    HTTPMessages.message(message)?.isHeaderComplete == true ? 1 : 0
}

@c(_CFHTTPMessageCopyVersion)
public func CFHTTPMessageCopyVersion(_ message: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    HTTPMessages.copy(HTTPMessages.message(message)?.version)
}

@c(_CFHTTPMessageCopyBody)
public func CFHTTPMessageCopyBody(_ message: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let message = HTTPMessages.message(message), message.isHeaderComplete else { return nil }
    return ObjCRuntime.retain(NSData.of(message.body).objcObject)
}

@c(_CFHTTPMessageCopyHeaderFieldValue)
public func CFHTTPMessageCopyHeaderFieldValue(_ message: UnsafeMutableRawPointer?, _ field: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let message = HTTPMessages.message(message), let text = HTTPMessages.string(field), let name = HTTPField.Name(text) else { return nil }
    let values = message.fields[values: name]
    return values.isEmpty ? nil : HTTPMessages.copy(values.joined(separator: ", "))
}

@c(_CFHTTPMessageCopyAllHeaderFields)
public func CFHTTPMessageCopyAllHeaderFields(_ message: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let message = HTTPMessages.message(message), message.isHeaderComplete else { return nil }
    let dictionary = NSMutableDictionary.of(message.headerDictionary.map { ($0.0, NSObject.string($0.1)) })
    return ObjCRuntime.retain(dictionary.objcObject)
}

@c(_CFHTTPMessageCopySerializedMessage)
public func CFHTTPMessageCopySerializedMessage(_ message: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let data = HTTPMessages.message(message)?.serialized() else { return nil }
    return ObjCRuntime.retain(NSData.of(data).objcObject)
}

@c(_CFHTTPMessageCopyRequestURL)
public func CFHTTPMessageCopyRequestURL(_ message: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let message = HTTPMessages.message(message), message.isRequest, let url = message.url,
          let object = NSURL.make(string: url.absoluteString) else { return nil }
    return ObjCRuntime.retain(object.objcObject)
}

@c(_CFHTTPMessageCopyRequestMethod)
public func CFHTTPMessageCopyRequestMethod(_ message: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard case .request(let request)? = HTTPMessages.message(message)?.head else { return nil }
    return HTTPMessages.copy(request.method.rawValue)
}

@c(_CFHTTPMessageGetResponseStatusCode)
public func CFHTTPMessageGetResponseStatusCode(_ message: UnsafeMutableRawPointer?) -> Int {
    guard case .response(let response)? = HTTPMessages.message(message)?.head else { return 0 }
    return response.status.code
}

@c(_CFHTTPMessageCopyResponseStatusLine)
public func CFHTTPMessageCopyResponseStatusLine(_ message: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let message = HTTPMessages.message(message), case .response(let response)? = message.head else { return nil }
    let reason = response.status.reasonPhrase
    return HTTPMessages.copy("\(message.version) \(response.status.code)\(reason.isEmpty ? "" : " " + reason)")
}

// MARK: - Changing

@c(_CFHTTPMessageSetBody)
public func CFHTTPMessageSetBody(_ message: UnsafeMutableRawPointer?, _ body: UnsafeMutableRawPointer?) {
    guard let message = HTTPMessages.message(message) else { return }
    message.body = body.map { NSObject($0).unsafeCast(to: NSData.self).data } ?? Data()
}

/// A nil value removes the field.
@c(_CFHTTPMessageSetHeaderFieldValue)
public func CFHTTPMessageSetHeaderFieldValue(_ message: UnsafeMutableRawPointer?, _ field: UnsafeMutableRawPointer?,
                                             _ value: UnsafeMutableRawPointer?) {
    guard let message = HTTPMessages.message(message), message.isHeaderComplete,
          let text = HTTPMessages.string(field), let name = HTTPField.Name(text) else { return }
    message.fields[name] = HTTPMessages.string(value)
}

@c(_CFHTTPMessageAppendBytes)
public func CFHTTPMessageAppendBytes(_ message: UnsafeMutableRawPointer?, _ bytes: UnsafePointer<UInt8>?, _ length: Int) -> UInt8 {
    guard let message = HTTPMessages.message(message) else { return 0 }
    guard let bytes, length > 0 else { return 1 }
    return message.append(UnsafeBufferPointer(start: bytes, count: length)) ? 1 : 0
}

/// Basic authentication, the scheme there is without a server's
/// challenge to answer: an Authorization field with the credentials.
@c(_CFHTTPMessageAddAuthentication)
public func CFHTTPMessageAddAuthentication(_ request: UnsafeMutableRawPointer?, _ failure: UnsafeMutableRawPointer?,
                                           _ username: UnsafeMutableRawPointer?, _ password: UnsafeMutableRawPointer?,
                                           _ scheme: UnsafeMutableRawPointer?, _ forProxy: UInt8) -> UInt8 {
    guard let message = HTTPMessages.message(request), message.isRequest, message.isHeaderComplete else { return 0 }
    let schemeName = HTTPMessages.string(scheme) ?? HTTPAuthenticationSchemes.kCFHTTPAuthenticationSchemeBasic
    guard schemeName.lowercased() == HTTPAuthenticationSchemes.kCFHTTPAuthenticationSchemeBasic.lowercased() else { return 0 }
    let credentials = Data("\(HTTPMessages.string(username) ?? ""):\(HTTPMessages.string(password) ?? "")".utf8).base64EncodedString()
    message.fields[forProxy != 0 ? .proxyAuthorization : .authorization] = "Basic " + credentials
    return 1
}

// MARK: - Streams

@c(_CFReadStreamCreateForHTTPRequest)
public func CFReadStreamCreateForHTTPRequest(_ allocator: UnsafeRawPointer?, _ request: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    HTTPMessages.unsupported("CFReadStreamCreateForHTTPRequest")
    return nil
}

@c(_CFReadStreamCreateForStreamedHTTPRequest)
public func CFReadStreamCreateForStreamedHTTPRequest(_ allocator: UnsafeRawPointer?, _ request: UnsafeMutableRawPointer?,
                                                     _ body: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    HTTPMessages.unsupported("CFReadStreamCreateForStreamedHTTPRequest")
    return nil
}

// MARK: - Constants

@ObjCConstants
enum HTTPAuthenticationSchemes {
    static let kCFHTTPAuthenticationSchemeBasic = "Basic"
    static let kCFHTTPAuthenticationSchemeDigest = "Digest"
    static let kCFHTTPAuthenticationSchemeNTLM = "NTLM"
    static let kCFHTTPAuthenticationSchemeKerberos = "Kerberos"
    static let kCFHTTPAuthenticationSchemeNegotiate = "Negotiate"
    static let kCFHTTPAuthenticationSchemeNegotiate2 = "Negotiate2"
    static let kCFHTTPAuthenticationSchemeXMobileMeAuthToken = "XMobileMeAuthToken"
}

@ObjCConstants
enum HTTPStreamProperties {
    static let kCFStreamPropertyHTTPResponseHeader = "kCFStreamPropertyHTTPResponseHeader"
    static let kCFStreamPropertyHTTPFinalURL = "kCFStreamPropertyHTTPFinalURL"
    static let kCFStreamPropertyHTTPFinalRequest = "kCFStreamPropertyHTTPFinalRequest"
    static let kCFStreamPropertyHTTPProxy = "kCFStreamPropertyHTTPProxy"
    static let kCFStreamPropertyHTTPShouldAutoredirect = "kCFStreamPropertyHTTPShouldAutoredirect"
    static let kCFStreamPropertyHTTPAttemptPersistentConnection = "kCFStreamPropertyHTTPAttemptPersistentConnection"
    static let kCFStreamPropertyHTTPRequestBytesWrittenCount = "kCFStreamPropertyHTTPRequestBytesWrittenCount"
    static let kCFStreamErrorDomainHTTP: Int32 = 4
    static let kCFStreamErrorDomainNetServices: Int32 = 10
    static let kCFStreamErrorDomainNetDB: Int32 = 12
}

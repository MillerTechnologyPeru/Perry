import Foundation
import FoundationNetworking

// URL loading over swift-corelibs-foundation's URLSession, libcurl's client
// in Swift, for CFNetwork's Objective-C classes. This module alone imports
// that Foundation; its API speaks in FoundationEssentials' URL, Data and
// Date and in its own reference types, so the provider never sees
// corelibs' Objective-C-named classes.

// MARK: - Requests

/// An input stream over a reader, for a body corelibs' session reads as it
/// sends. It has bytes until a read finds none: a body written while the
/// request goes out (a bound pair's) is read whole, waiting on the writer.
final class ReaderStream: InputStream, @unchecked Sendable {
    private let openReader: @Sendable () -> Void
    private let readBytes: @Sendable (UnsafeMutablePointer<UInt8>, Int) -> Int
    private let finish: @Sendable () -> Void
    private var status: Stream.Status = .notOpen

    init(open: @escaping @Sendable () -> Void, read: @escaping @Sendable (UnsafeMutablePointer<UInt8>, Int) -> Int,
         finish: @escaping @Sendable () -> Void) {
        openReader = open
        readBytes = read
        self.finish = finish
        super.init(data: Data())
    }

    deinit { finish() }

    override func open() {
        guard status == .notOpen else { return }
        openReader()
        status = .open
    }

    override func close() { status = .closed }
    override var streamStatus: Stream.Status { status }
    override var hasBytesAvailable: Bool { status == .open || status == .notOpen }

    override func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength length: Int) -> Int {
        if status == .notOpen { open() }
        guard status == .open else { return 0 }
        let count = readBytes(buffer, length)
        if count <= 0 { status = .atEnd }
        return max(count, 0)
    }

    override func getBuffer(_ buffer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>,
                            length: UnsafeMutablePointer<Int>) -> Bool { false }
}

/// A request, which NSURLRequest and NSMutableURLRequest hold.
public final class Request: @unchecked Sendable {
    var value: URLRequest

    init(_ value: URLRequest) {
        self.value = value
    }

    public init(url: URL?, cachePolicy: Int = 0, timeout: Double = 60) {
        value = URLRequest(url: url ?? URL(string: "about:blank")!,
                           cachePolicy: URLRequest.CachePolicy(rawValue: UInt(cachePolicy)) ?? .useProtocolCachePolicy,
                           timeoutInterval: timeout)
        if url == nil { value.url = nil }
    }

    public func copy() -> Request {
        let copy = Request(value)
        copy.properties = properties
        copy.protocolClasses = protocolClasses
        return copy
    }

    public var url: URL? {
        get { value.url }
        set { value.url = newValue }
    }

    public var method: String {
        get { value.httpMethod ?? "GET" }
        set { value.httpMethod = newValue }
    }

    public var headers: [String: String]? {
        get { value.allHTTPHeaderFields.flatMap { $0.isEmpty ? nil : $0 } }
        set { value.allHTTPHeaderFields = newValue }
    }

    public func header(_ name: String) -> String? { value.value(forHTTPHeaderField: name) }
    public func setHeader(_ value: String?, for name: String) { self.value.setValue(value, forHTTPHeaderField: name) }
    public func addHeader(_ value: String, for name: String) { self.value.addValue(value, forHTTPHeaderField: name) }

    public var body: Data? {
        get { value.httpBody }
        set { value.httpBody = newValue }
    }

    /// A body read from another stream as the request is sent, on the
    /// session's own thread: `read` fills a buffer and gives the count, 0
    /// at the end; `finish` runs once the stream is let go.
    public func setBodyReader(open: @escaping @Sendable () -> Void, read: @escaping @Sendable (UnsafeMutablePointer<UInt8>, Int) -> Int,
                              finish: @escaping @Sendable () -> Void) {
        value.httpBody = nil
        value.httpBodyStream = ReaderStream(open: open, read: read, finish: finish)
    }

    public var timeout: Double {
        get { value.timeoutInterval }
        set { value.timeoutInterval = newValue }
    }

    public var cachePolicy: Int {
        get { Int(value.cachePolicy.rawValue) }
        set { value.cachePolicy = URLRequest.CachePolicy(rawValue: UInt(newValue)) ?? .useProtocolCachePolicy }
    }

    public var handlesCookies: Bool {
        get { value.httpShouldHandleCookies }
        set { value.httpShouldHandleCookies = newValue }
    }

    public var usesPipelining: Bool {
        get { value.httpShouldUsePipelining }
        set { value.httpShouldUsePipelining = newValue }
    }

    public var mainDocumentURL: URL? {
        get { value.mainDocumentURL }
        set { value.mainDocumentURL = newValue }
    }

    public var allowsCellularAccess: Bool {
        get { value.allowsCellularAccess }
        set { value.allowsCellularAccess = newValue }
    }

    public var networkServiceType: Int {
        get { Int(value.networkServiceType.rawValue) }
        set { value.networkServiceType = URLRequest.NetworkServiceType(rawValue: UInt(newValue)) ?? .default }
    }

    /// Equal when everything a load depends on is: corelibs' == compares
    /// less than Darwin's -isEqual:.
    public func isEqual(to other: Request) -> Bool {
        value == other.value && value.timeoutInterval == other.value.timeoutInterval
            && value.cachePolicy == other.value.cachePolicy && value.allHTTPHeaderFields == other.value.allHTTPHeaderFields
            && value.httpBody == other.value.httpBody && value.httpMethod == other.value.httpMethod
            && value.httpShouldHandleCookies == other.value.httpShouldHandleCookies
            && value.mainDocumentURL == other.value.mainDocumentURL && sameProperties(as: other)
    }
    public var hash: Int { value.hashValue }

    /// NSURLProtocol's properties. corelibs' own protocol properties
    /// never survive into a URLRequest, so a request handed to corelibs
    /// carries a tag naming them instead (see RequestTags).
    public var properties: [String: AnyObject] = [:]
    /// The session configuration's Objective-C protocol classes.
    var protocolClasses: [UnsafeMutableRawPointer] = []

    public func property(forKey key: String) -> AnyObject? { properties[key] }
    public func setProperty(_ object: AnyObject?, forKey key: String) { properties[key] = object }

    /// Equal properties: the same keys holding the same objects.
    func sameProperties(as other: Request) -> Bool {
        properties.count == other.properties.count && properties.allSatisfy { key, value in other.properties[key] === value }
    }

    /// The request for corelibs, tagged when it has properties or classes;
    /// the tag lives as long as the caller keeps it.
    func forCorelibs() -> (URLRequest, RequestTag?) {
        guard !properties.isEmpty || !protocolClasses.isEmpty else { return (value, nil) }
        let tag = RequestTags.register(properties: properties, classes: protocolClasses)
        var tagged = value
        tagged.setValue(String(tag.id), forHTTPHeaderField: RequestTags.header)
        return (tagged, tag)
    }

    /// A request corelibs hands back, with its tag's properties and classes.
    init(fromCorelibs request: URLRequest) {
        var value = request
        if let id = value.value(forHTTPHeaderField: RequestTags.header) {
            value.setValue(nil, forHTTPHeaderField: RequestTags.header)
            if let tag = Int(id).flatMap(RequestTags.tag) {
                properties = tag.properties
                protocolClasses = tag.classes
            }
        }
        self.value = value
    }
}

/// What a tagged request carries, found by the id in its header.
final class RequestTag: @unchecked Sendable {
    let id: Int
    let properties: [String: AnyObject]
    let classes: [UnsafeMutableRawPointer]

    init(id: Int, properties: [String: AnyObject], classes: [UnsafeMutableRawPointer]) {
        self.id = id
        self.properties = properties
        self.classes = classes
    }
}

enum RequestTags {
    static let header = "X-Perry-Request-Tag"
    private final class Weak {
        weak var tag: RequestTag?
        init(_ tag: RequestTag) { self.tag = tag }
    }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var tags: [Int: Weak] = [:]
    nonisolated(unsafe) private static var next = 0

    static func register(properties: [String: AnyObject], classes: [UnsafeMutableRawPointer]) -> RequestTag {
        lock.lock()
        defer { lock.unlock() }
        next += 1
        let tag = RequestTag(id: next, properties: properties, classes: classes)
        tags = tags.filter { $0.value.tag != nil }
        tags[next] = Weak(tag)
        return tag
    }

    static func tag(_ id: Int) -> RequestTag? {
        lock.lock()
        defer { lock.unlock() }
        return tags[id]?.tag
    }
}

// MARK: - Responses

/// A response, which NSURLResponse and NSHTTPURLResponse hold.
public final class Response: @unchecked Sendable {
    let value: URLResponse

    init(_ value: URLResponse) {
        self.value = value
    }

    public init(url: URL, mimeType: String?, expectedLength: Int, textEncodingName: String?) {
        value = URLResponse(url: url, mimeType: mimeType, expectedContentLength: expectedLength,
                            textEncodingName: textEncodingName)
    }

    public init?(url: URL, statusCode: Int, httpVersion: String?, headers: [String: String]?) {
        guard let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: httpVersion,
                                             headerFields: headers) else { return nil }
        value = response
    }

    public var url: URL? { value.url }
    public var mimeType: String? { value.mimeType }
    public var expectedLength: Int64 { value.expectedContentLength }
    public var textEncodingName: String? { value.textEncodingName }
    /// Content-Disposition's filename, else the URL's last path component,
    /// else "Unknown", as Darwin chooses.
    public var suggestedFilename: String? {
        if let disposition = header("Content-Disposition"),
           let range = disposition.range(of: "filename=") {
            let name = disposition[range.upperBound...].split(separator: ";").first.map(String.init) ?? ""
            let trimmed = name.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
            if !trimmed.isEmpty { return trimmed }
        }
        if let component = value.url?.lastPathComponent, !component.isEmpty, component != "/" { return component }
        return "Unknown"
    }
    public var isHTTP: Bool { value is HTTPURLResponse }
    public var statusCode: Int { (value as? HTTPURLResponse)?.statusCode ?? 0 }

    /// The header fields as the server sent them.
    public var headers: [(name: String, value: String)] {
        guard let http = value as? HTTPURLResponse else { return [] }
        return http.allHeaderFields.compactMap { key, value in
            guard let name = key as? String, let value = value as? String else { return nil }
            return (name, value)
        }.sorted { $0.name < $1.name }
    }

    public func header(_ name: String) -> String? { (value as? HTTPURLResponse)?.value(forHTTPHeaderField: name) }

    /// CFNetwork's phrases, which are lowercase, and its fallbacks by class.
    public static func localizedString(forStatusCode code: Int) -> String {
        let phrases: [Int: String] = [
            100: "continue", 101: "switching protocols", 200: "no error", 201: "created", 202: "accepted",
            203: "non-authoritative information", 204: "no content", 205: "reset content", 206: "partial content",
            300: "multiple choices", 301: "moved permanently", 302: "found", 303: "see other", 304: "not modified",
            305: "use proxy", 307: "temporarily redirected", 400: "bad request", 401: "unauthorized",
            402: "payment required", 403: "forbidden", 404: "not found", 405: "method not allowed",
            406: "unacceptable", 407: "proxy authentication required", 408: "request timed out", 409: "conflict",
            410: "no longer exists", 411: "length required", 412: "precondition failed", 413: "request too large",
            414: "requested URL too long", 415: "unsupported media type", 416: "requested range not satisfiable",
            417: "expectation failed", 500: "internal server error", 501: "unimplemented", 502: "bad gateway",
            503: "service unavailable", 504: "gateway timed out", 505: "unsupported version",
        ]
        if let phrase = phrases[code] { return phrase }
        switch code {
        case 100..<200: return "informational"
        case 200..<300: return "success"
        case 300..<400: return "redirected"
        case 400..<500: return "client error"
        case 500..<600: return "server error"
        default: return "unknown"
        }
    }
}

// MARK: - Errors

/// A failed load, as NSError's parts in NSURLErrorDomain.
public struct Failure: Sendable {
    public let domain: String
    public let code: Int
    public let description: String
    public let failingURL: URL?

    /// NSURLErrorTimedOut, for a load given up on.
    public static func timedOut(url: URL?) -> Failure { Failure(URLError(.timedOut), url: url) }

    init(_ error: any Error, url: URL?) {
        if let error = error as? URLError {
            domain = "NSURLErrorDomain"
            code = error.errorCode
            description = error.localizedDescription
            failingURL = error.failingURL ?? url
        } else {
            let error = error as NSError
            domain = error.domain
            code = error.code
            description = error.localizedDescription
            failingURL = url
        }
    }
}

// MARK: - Configurations

/// A session configuration, which NSURLSessionConfiguration holds.
public final class Configuration: @unchecked Sendable {
    let value: URLSessionConfiguration

    /// The bridge to Objective-C protocols comes first, so it sees each
    /// request before corelibs' own protocols.
    init(_ value: URLSessionConfiguration) {
        self.value = value
        value.protocolClasses = [BridgedProtocol.self] + (value.protocolClasses ?? []).filter { $0 != BridgedProtocol.self }
    }

    /// The Objective-C protocol classes the program set, unretained classes.
    public var protocolClasses: [UnsafeMutableRawPointer]?

    public static func makeDefault() -> Configuration { Configuration(.default) }
    public static func makeEphemeral() -> Configuration { Configuration(.ephemeral) }

    public static func makeBackground(identifier: String) -> Configuration {
        // Linux has no background transfers: an ordinary configuration.
        let configuration = Configuration(.default)
        configuration.identifier = identifier
        return configuration
    }

    public var identifier: String?

    /// Settings corelibs doesn't use (the network service type, constrained
    /// and expensive access, discretionary transfers…), kept by name to be
    /// read back.
    public var settings: [String: Int] = [:]
    public var sharedContainerIdentifier: String?

    public func copy() -> Configuration {
        let copy = Configuration(value.copy() as! URLSessionConfiguration)
        copy.identifier = identifier
        copy.settings = settings
        copy.sharedContainerIdentifier = sharedContainerIdentifier
        copy.waitsForConnectivity = waitsForConnectivity
        copy.protocolClasses = protocolClasses
        return copy
    }

    public var timeoutForRequest: Double {
        get { value.timeoutIntervalForRequest }
        set { value.timeoutIntervalForRequest = newValue }
    }

    public var timeoutForResource: Double {
        get { value.timeoutIntervalForResource }
        set { value.timeoutIntervalForResource = newValue }
    }

    public var additionalHeaders: [String: String]? {
        get {
            value.httpAdditionalHeaders?.reduce(into: [String: String]()) { headers, entry in
                if let name = entry.key as? String, let text = entry.value as? String { headers[name] = text }
            }
        }
        set { value.httpAdditionalHeaders = newValue }
    }

    public var setsCookies: Bool {
        get { value.httpShouldSetCookies }
        set { value.httpShouldSetCookies = newValue }
    }

    public var cookieAcceptPolicy: Int {
        get { Int(value.httpCookieAcceptPolicy.rawValue) }
        set { value.httpCookieAcceptPolicy = HTTPCookie.AcceptPolicy(rawValue: UInt(newValue)) ?? .onlyFromMainDocumentDomain }
    }

    public var usesCookieStorage: Bool {
        get { value.httpCookieStorage != nil }
        set { value.httpCookieStorage = newValue ? .shared : nil }
    }

    public var hasURLCache: Bool { value.urlCache != nil }

    public var requestCachePolicy: Int {
        get { Int(value.requestCachePolicy.rawValue) }
        set { value.requestCachePolicy = URLRequest.CachePolicy(rawValue: UInt(newValue)) ?? .useProtocolCachePolicy }
    }

    public var maximumConnectionsPerHost: Int {
        get { value.httpMaximumConnectionsPerHost }
        set { value.httpMaximumConnectionsPerHost = newValue }
    }

    public var allowsCellularAccess: Bool {
        get { value.allowsCellularAccess }
        set { value.allowsCellularAccess = newValue }
    }

    /// Kept for the program; corelibs never waits for connectivity.
    public var waitsForConnectivity = false

    public var usesPipelining: Bool {
        get { value.httpShouldUsePipelining }
        set { value.httpShouldUsePipelining = newValue }
    }
}

// MARK: - Cookies

/// A cookie, which NSHTTPCookie holds.
public final class Cookie: @unchecked Sendable {
    let value: HTTPCookie

    init(_ value: HTTPCookie) {
        self.value = value
    }

    /// From NSHTTPCookie's property keys and string values.
    public init?(properties: [String: Any]) {
        var keyed: [HTTPCookiePropertyKey: Any] = [:]
        for (key, value) in properties { keyed[HTTPCookiePropertyKey(key)] = value }
        guard let cookie = HTTPCookie(properties: keyed) else { return nil }
        value = cookie
    }

    public var name: String { value.name }
    public var value_: String { value.value }
    public var domain: String { value.domain }
    public var path: String { value.path }
    public var expiresDate: Date? { value.expiresDate }
    /// Darwin keeps a cookie for the session when it has no expiry.
    public var isSessionOnly: Bool { value.expiresDate == nil }
    public var isSecure: Bool { value.isSecure }
    public var isHTTPOnly: Bool { value.isHTTPOnly }
    public var version: Int { value.version }
    public var comment: String? { value.comment }
    public var sameSitePolicy: String? { value.properties?[HTTPCookiePropertyKey("SameSite")] as? String }

    public var properties: [(String, String)] {
        (value.properties ?? [:]).compactMap { key, value in
            if let text = value as? String { return (key.rawValue, text) }
            if let date = value as? Date { return (key.rawValue, "\(date)") }
            return (key.rawValue, "\(value)")
        }.sorted { $0.0 < $1.0 }
    }

    public static func requestHeaders(_ cookies: [Cookie]) -> [String: String] {
        HTTPCookie.requestHeaderFields(with: cookies.map(\.value))
    }

    public static func parse(_ headers: [String: String], for url: URL) -> [Cookie] {
        HTTPCookie.cookies(withResponseHeaderFields: headers, for: url).map(Cookie.init)
    }

    public func isEqual(to other: Cookie) -> Bool { value == other.value }
}

/// The shared cookie storage.
public enum CookieStorage {
    public static var all: [Cookie] { (HTTPCookieStorage.shared.cookies ?? []).map(Cookie.init) }
    public static func cookies(for url: URL) -> [Cookie] { (HTTPCookieStorage.shared.cookies(for: url) ?? []).map(Cookie.init) }
    public static func set(_ cookie: Cookie) { HTTPCookieStorage.shared.setCookie(cookie.value) }
    public static func delete(_ cookie: Cookie) { HTTPCookieStorage.shared.deleteCookie(cookie.value) }
    public static func removeAll(since date: Date) { HTTPCookieStorage.shared.removeCookies(since: date) }

    public static func set(_ cookies: [Cookie], for url: URL?, mainDocumentURL: URL?) {
        HTTPCookieStorage.shared.setCookies(cookies.map(\.value), for: url, mainDocumentURL: mainDocumentURL)
    }

    public static var acceptPolicy: Int {
        get { Int(HTTPCookieStorage.shared.cookieAcceptPolicy.rawValue) }
        set { HTTPCookieStorage.shared.cookieAcceptPolicy = HTTPCookie.AcceptPolicy(rawValue: UInt(newValue)) ?? .always }
    }
}

// MARK: - Tasks

/// A task, which an NSURLSessionTask holds. `owner` is the Objective-C task.
public final class Task: @unchecked Sendable {
    /// The corelibs task first made, and the one running now: a retry
    /// with a credential replaces it.
    let first: URLSessionTask
    private var running: URLSessionTask
    var value: URLSessionTask {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    func replace(with task: URLSessionTask) {
        lock.lock()
        running = task
        lock.unlock()
    }

    // A 401 response and its body, held while its challenge is answered.
    private var held: (response: URLResponse, data: Data)?
    /// Answers given to challenges so far, and the last credential.
    var failures = 0
    var lastCredential: Credential?

    func hold(_ response: URLResponse) {
        lock.lock()
        held = (response, Data())
        lock.unlock()
    }

    /// Keeps data for a held response; false when none is held.
    func hold(_ data: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard held != nil else { return false }
        held?.data.append(data)
        return true
    }

    func takeHeld() -> (response: URLResponse, data: Data)? {
        lock.lock()
        defer {
            held = nil
            lock.unlock()
        }
        return held
    }
    public let kind: Kind
    /// The Objective-C object standing for the task, unretained.
    public var owner: UnsafeMutableRawPointer?

    public enum Kind: Sendable { case data, upload, download }

    /// The tags its requests carry, kept while it runs.
    var tags: [RequestTag] = []

    private let lock = NSLock()
    private var completed = false
    private var delivered: Int64 = 0

    /// corelibs reports a task's last event before it marks the task
    /// completed and counts the bytes a delegate was given; Darwin's state
    /// and counts are final by then.
    public func markCompleted() {
        lock.lock()
        completed = true
        lock.unlock()
    }

    func count(_ bytes: Int) {
        lock.lock()
        delivered += Int64(bytes)
        lock.unlock()
    }

    init(_ value: URLSessionTask, kind: Kind) {
        first = value
        running = value
        self.kind = kind
    }

    public var identifier: Int { first.taskIdentifier }
    /// NSURLSessionTaskState: running 0, suspended 1, canceling 2, completed 3.
    public var state: Int {
        lock.lock()
        defer { lock.unlock() }
        return completed ? URLSessionTask.State.completed.rawValue : running.state.rawValue
    }
    public var originalRequest: Request? { first.originalRequest.map { Request(fromCorelibs: $0) } }
    public var currentRequest: Request? { value.currentRequest.map { Request(fromCorelibs: $0) } }
    /// None when a challenge was cancelled: the 401 never reached the program.
    public var response: Response? { cancelledChallenge ? nil : value.response.map(Response.init) }
    var cancelledChallenge = false
    public var bytesReceived: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return max(running.countOfBytesReceived, delivered)
    }
    public var bytesSent: Int64 { value.countOfBytesSent }
    public var bytesExpectedToReceive: Int64 { value.countOfBytesExpectedToReceive }
    public var bytesExpectedToSend: Int64 { value.countOfBytesExpectedToSend }
    public var error: Failure? { value.error.map { Failure($0, url: value.originalRequest?.url) } }

    public var taskDescription: String? {
        get { value.taskDescription }
        set { value.taskDescription = newValue }
    }

    public var priority: Float {
        get { value.priority }
        set { value.priority = newValue }
    }

    public func resume() { value.resume() }
    public func suspend() { value.suspend() }
    public func cancel() { value.cancel() }
}

// MARK: - Sessions

/// What a session's Objective-C delegate is told; each call comes on the
/// corelibs session's own serial queue.
public protocol SessionEvents: AnyObject {
    /// Answers with NSURLSessionResponseDisposition: cancel 0, allow 1.
    func task(_ task: Task, didReceive response: Response, completion: @escaping @Sendable (Int) -> Void)
    func task(_ task: Task, didReceive data: Data)
    func task(_ task: Task, willRedirect response: Response, to request: Request,
              completion: @escaping @Sendable (Request?) -> Void)
    func task(_ task: Task, didSend bytes: Int64, total: Int64, expected: Int64)
    func task(_ task: Task, didWrite bytes: Int64, total: Int64, expected: Int64)
    func task(_ task: Task, didFinishDownloadingTo location: URL)
    func task(_ task: Task, didCompleteWith error: Failure?)
    func sessionDidBecomeInvalid(_ error: Failure?)
    /// Answers with NSURLSessionAuthChallengeDisposition and a credential.
    func task(_ task: Task, didReceive challenge: Challenge, completion: @escaping @Sendable (Int, Credential?) -> Void)
}

/// corelibs' delegate: forwards each event to the Objective-C side.
final class Forwarder: NSObject, URLSessionDataDelegate, URLSessionDownloadDelegate, @unchecked Sendable {
    weak var session: Session?
    var events: SessionEvents? { session?.events }

    func task(_ task: URLSessionTask) -> Task? { session?.task(for: task) }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let events, let task = task(dataTask) else { return completionHandler(.allow) }
        // A challenge comes first: the 401 waits for the delegate's answer.
        if task.kind == .data, let http = response as? HTTPURLResponse, Authentication.space(for: http) != nil {
            task.hold(response)
            return completionHandler(.allow)
        }
        nonisolated(unsafe) let handler = completionHandler
        events.task(task, didReceive: Response(response)) { disposition in
            handler(URLSession.ResponseDisposition(rawValue: disposition) ?? .allow)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let task = task(dataTask), !task.hold(data) else { return }
        task.count(data.count)
        events?.task(task, didReceive: data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let events, let wrapper = self.task(task) else { return completionHandler(request) }
        nonisolated(unsafe) let handler = completionHandler
        events.task(wrapper, willRedirect: Response(response), to: Request(fromCorelibs: request)) { handler($0?.value) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard let wrapper = self.task(task) else { return }
        events?.task(wrapper, didSend: bytesSent, total: totalBytesSent, expected: totalBytesExpectedToSend)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let wrapper = task(downloadTask) else { return }
        events?.task(wrapper, didWrite: bytesWritten, total: totalBytesWritten, expected: totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let wrapper = task(downloadTask) else { return }
        events?.task(wrapper, didFinishDownloadingTo: location)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let wrapper = self.task(task) else { return }
        if error == nil, let held = wrapper.takeHeld(), let events, let owner = self.session {
            return Authentication.challenge(wrapper, held, events: events, session: owner)
        }
        wrapper.markCompleted()
        URLTrace.completed(task.originalRequest?.url, task.response, nil, error)
        events?.task(wrapper, didCompleteWith: error.map { Failure($0, url: task.originalRequest?.url) })
        self.session?.forget(task)
    }

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: (any Error)?) {
        events?.sessionDidBecomeInvalid(error.map { Failure($0, url: nil) })
        self.session?.events = nil
    }
}

/// With PERRY_URL_TRACE set, each task's request, status and error as it
/// completes, on standard error.
enum URLTrace {
    static let on = getenv("PERRY_URL_TRACE") != nil

    static func completed(_ url: URL?, _ response: URLResponse?, _ bytes: Int?, _ error: (any Error)?) {
        guard on else { return }
        var line = "perry: URL: \(url?.absoluteString ?? "?")"
        if let http = response as? HTTPURLResponse { line += " status \(http.statusCode)" }
        else if response == nil { line += " no response" }
        if let bytes { line += " \(bytes) bytes" }
        if let error { line += " error \(error) (\(String(reflecting: error)))" }
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}

/// A session, which NSURLSession holds.
public final class Session: @unchecked Sendable {
    let value: URLSession
    private let forwarder: Forwarder?
    /// The Objective-C delegate's side; the session holds it until it is
    /// invalidated, as Darwin's holds its delegate.
    public fileprivate(set) var events: SessionEvents?
    public let configuration: Configuration
    private let lock = NSLock()
    private var tasks: [ObjectIdentifier: Task] = [:]

    public init(configuration: Configuration, events: SessionEvents?) {
        self.configuration = configuration.copy()
        self.events = events
        if events != nil {
            let forwarder = Forwarder()
            self.forwarder = forwarder
            value = URLSession(configuration: self.configuration.value, delegate: forwarder, delegateQueue: nil)
            forwarder.session = self
        } else {
            forwarder = nil
            value = URLSession(configuration: self.configuration.value)
        }
    }

    /// Sessions let go. corelibs' URLSession can't be freed safely: while
    /// its tasks run, or after, when a finished task holding the last
    /// reference goes, its deinit finds its curl multi handle still
    /// referenced and traps. Darwin's outlives both. A session let go
    /// finishes its tasks, invalidated, and is kept for good.
    nonisolated(unsafe) private static var orphans: [URLSession] = []
    private static let orphansLock = NSLock()

    deinit {
        value.finishTasksAndInvalidate()
        Self.orphansLock.lock()
        Self.orphans.append(value)
        Self.orphansLock.unlock()
    }

    fileprivate func task(for task: URLSessionTask) -> Task? {
        lock.lock()
        defer { lock.unlock() }
        return tasks[ObjectIdentifier(task)]
    }

    /// A retry made for a task, reporting as it.
    fileprivate func adopt(_ retry: URLSessionTask, for task: Task) {
        lock.lock()
        tasks[ObjectIdentifier(retry)] = task
        lock.unlock()
    }

    fileprivate func forget(_ task: URLSessionTask) {
        lock.lock()
        tasks[ObjectIdentifier(task)] = nil
        lock.unlock()
    }

    private func track(_ task: URLSessionTask, _ kind: Task.Kind) -> Task {
        let wrapper = Task(task, kind: kind)
        lock.lock()
        wrapper.tags = pendingTags
        pendingTags = []
        lock.unlock()
        lock.lock()
        tasks[ObjectIdentifier(task)] = wrapper
        lock.unlock()
        return wrapper
    }

    /// The request for corelibs, carrying the configuration's Objective-C
    /// protocol classes and its own properties for the bridge to find. The
    /// task keeps the tag.
    private func tagged(_ request: Request) -> URLRequest {
        let copy = request.copy()
        copy.protocolClasses = configuration.protocolClasses ?? []
        let (value, tag) = copy.forCorelibs()
        if let tag { pendingTags.append(tag) }
        return value
    }

    /// Tags for the task being made, which track() hands to it.
    private var pendingTags: [RequestTag] = []

    public typealias DataCompletion = @Sendable (Data?, Response?, Failure?) -> Void
    public typealias DownloadCompletion = @Sendable (URL?, Response?, Failure?) -> Void

    private static func dataHandler(_ completion: @escaping DataCompletion, _ url: URL?)
        -> @Sendable (Data?, URLResponse?, (any Error)?) -> Void {
        { data, response, error in
            URLTrace.completed(url, response, data?.count, error)
            completion(data, response.map(Response.init), error.map { Failure($0, url: url) })
        }
    }

    public func dataTask(_ request: Request, completion: DataCompletion? = nil) -> Task {
        guard let completion else { return track(value.dataTask(with: tagged(request)), .data) }
        return track(value.dataTask(with: tagged(request), completionHandler: Self.dataHandler(completion, request.url)), .data)
    }

    public func uploadTask(_ request: Request, data: Data, completion: DataCompletion? = nil) -> Task {
        guard let completion else { return track(value.uploadTask(with: tagged(request), from: data), .upload) }
        return track(value.uploadTask(with: tagged(request), from: data,
                                      completionHandler: Self.dataHandler(completion, request.url)), .upload)
    }

    public func uploadTask(_ request: Request, file: URL, completion: DataCompletion? = nil) -> Task {
        guard let completion else { return track(value.uploadTask(with: tagged(request), fromFile: file), .upload) }
        return track(value.uploadTask(with: tagged(request), fromFile: file,
                                      completionHandler: Self.dataHandler(completion, request.url)), .upload)
    }

    public func downloadTask(_ request: Request, completion: DownloadCompletion? = nil) -> Task {
        guard let completion else { return track(value.downloadTask(with: tagged(request)), .download) }
        let url = request.url
        return track(value.downloadTask(with: tagged(request)) { location, response, error in
            completion(location, response.map(Response.init), error.map { Failure($0, url: url) })
        }, .download)
    }

    public func finishTasksAndInvalidate() { value.finishTasksAndInvalidate() }
    public func invalidateAndCancel() { value.invalidateAndCancel() }

    public var sessionDescription: String? {
        get { value.sessionDescription }
        set { value.sessionDescription = newValue }
    }
}

// MARK: - Protocols

/// Loads by Objective-C NSURLProtocol subclasses, which CFNetwork provides.
public protocol ProtocolLoader: AnyObject, Sendable {
    /// The class that loads the request: the first of `classes`, then of the
    /// registered classes, that can.
    func protocolClass(for request: Request, classes: [UnsafeMutableRawPointer]) -> UnsafeMutableRawPointer?
    /// Starts a load, returning what stops it.
    func start(_ cls: UnsafeMutableRawPointer, request: Request, client: ProtocolClient) -> AnyObject
    func stop(_ load: AnyObject)
}

public enum Protocols {
    nonisolated(unsafe) public static var loader: ProtocolLoader?
}

/// corelibs' protocol for every Objective-C one.
final class BridgedProtocol: URLProtocol {
    private var load: AnyObject?

    static func objCClass(_ request: URLRequest) -> UnsafeMutableRawPointer? {
        let request = Request(fromCorelibs: request)
        return Protocols.loader?.protocolClass(for: request, classes: request.protocolClasses)
    }

    override class func canInit(with request: URLRequest) -> Bool { objCClass(request) != nil }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    /// Loads start and stop here, off corelibs' queue, as Darwin runs a
    /// protocol on a thread of its own: a protocol may start a task of the
    /// same session.
    private let queue = DispatchQueue(label: "org.perry.urlprotocol")

    override func startLoading() {
        let request = self.request
        nonisolated(unsafe) let owner = self
        queue.async { owner.load(request) }
    }

    override func stopLoading() {
        nonisolated(unsafe) let owner = self
        queue.async {
            if let load = owner.load { Protocols.loader?.stop(load) }
            owner.load = nil
            owner.forwarded?.cancel()
            owner.forwarded = nil
        }
    }

    private var forwarded: URLSessionDataTask?

    /// Loads by the Objective-C protocol that takes the request, or else as
    /// corelibs would without one: a redirect may lead anywhere.
    private func load(_ request: URLRequest) {
        if let loader = Protocols.loader, let cls = Self.objCClass(request) {
            load = loader.start(cls, request: Request(fromCorelibs: request), client: ProtocolClient(self))
            return
        }
        nonisolated(unsafe) let owner = self
        let task = Self.plainSession.dataTask(with: Request(fromCorelibs: request).value) { data, response, error in
            let `self` = owner
            if let error { return self.client?.urlProtocol(self, didFailWithError: error) ?? () }
            if let response { self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed) }
            if let data, !data.isEmpty { self.client?.urlProtocol(self, didLoad: data) }
            self.client?.urlProtocolDidFinishLoading(self)
        }
        forwarded = task
        task.resume()
    }

    /// Without the bridge, for loads it passes on.
    private static let plainSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = (configuration.protocolClasses ?? []).filter { $0 != BridgedProtocol.self }
        return URLSession(configuration: configuration)
    }()

    /// corelibs follows no redirect a protocol reports: the bridge loads the
    /// new request itself.
    func redirect(to request: URLRequest) {
        nonisolated(unsafe) let owner = self
        queue.async {
            if let load = owner.load { Protocols.loader?.stop(load) }
            owner.load = nil
            owner.load(request)
        }
    }
}

/// What an Objective-C protocol tells its client, passed to corelibs. Data
/// is passed on whole when the load finishes: corelibs gives a completion
/// handler only the last piece it was given.
public final class ProtocolClient: @unchecked Sendable {
    private let owner: BridgedProtocol
    private let lock = NSLock()
    private var data = Data()

    init(_ owner: BridgedProtocol) {
        self.owner = owner
    }

    /// NSURLCacheStoragePolicy: allowed 0, in memory only 1, not allowed 2.
    public func receive(_ response: Response, cachePolicy: Int) {
        owner.client?.urlProtocol(owner, didReceive: response.value,
                                  cacheStoragePolicy: URLCache.StoragePolicy(rawValue: UInt(cachePolicy)) ?? .notAllowed)
    }

    public func load(_ data: Data) {
        lock.lock()
        self.data.append(data)
        lock.unlock()
    }

    public func finish() {
        lock.lock()
        let data = self.data
        self.data = Data()
        lock.unlock()
        if !data.isEmpty { owner.client?.urlProtocol(owner, didLoad: data) }
        owner.client?.urlProtocolDidFinishLoading(owner)
    }

    public func fail(domain: String, code: Int, description: String?) {
        let info: [String: Any] = description.map { [NSLocalizedDescriptionKey: $0] } ?? [:]
        owner.client?.urlProtocol(owner, didFailWithError: NSError(domain: domain, code: code, userInfo: info))
    }

    public func redirect(to request: Request, response: Response) {
        let (value, tag) = request.forCorelibs()
        tags.append(contentsOf: tag.map { [$0] } ?? [])
        owner.redirect(to: value)
    }

    private var tags: [RequestTag] = []
}

// MARK: - Authentication

/// A protection space's parts.
public struct ProtectionSpace: Sendable, Hashable {
    public var host: String
    public var port: Int
    public var protocolName: String?
    public var realm: String?
    public var method: String
    public var proxyType: String?

    public init(host: String, port: Int, protocolName: String?, realm: String?, method: String?, proxyType: String? = nil) {
        self.host = host
        self.port = port
        self.protocolName = protocolName
        self.realm = realm
        self.method = method ?? "NSURLAuthenticationMethodDefault"
        self.proxyType = proxyType
    }

    init(_ space: URLProtectionSpace) {
        self.init(host: space.host, port: space.port, protocolName: space.protocol, realm: space.realm,
                  method: space.authenticationMethod, proxyType: space.proxyType)
    }
}

/// A credential's parts.
public struct Credential: Sendable {
    public var user: String?
    public var password: String?
    /// NSURLCredentialPersistence: none 0, for session 1, permanent 2, synchronizable 3.
    public var persistence: Int

    public init(user: String?, password: String?, persistence: Int) {
        self.user = user
        self.password = password
        self.persistence = persistence
    }

    init(_ credential: URLCredential) {
        self.init(user: credential.user, password: credential.password, persistence: Int(credential.persistence.rawValue))
    }

    var value: URLCredential {
        URLCredential(user: user ?? "", password: password ?? "",
                      persistence: URLCredential.Persistence(rawValue: UInt(persistence)) ?? .none)
    }
}

/// An authentication challenge's parts.
public struct Challenge: Sendable {
    public let space: ProtectionSpace
    public let proposed: Credential?
    public let previousFailureCount: Int
    public let failureResponse: Response?
    public let error: Failure?

    init(space: ProtectionSpace, proposed: Credential?, previousFailureCount: Int, failureResponse: Response?, error: Failure?) {
        self.space = space
        self.proposed = proposed
        self.previousFailureCount = previousFailureCount
        self.failureResponse = failureResponse
        self.error = error
    }
}

/// HTTP authentication as Darwin runs it: a 401's challenge goes to the
/// delegate before the response does; a credential retries the request
/// with it (Basic), a cancel fails the task, and anything else delivers
/// the 401 as it came. corelibs' own challenges stop after one attempt.
enum Authentication {
    /// The protection space a 401 names, for the methods Perry answers.
    static func space(for response: HTTPURLResponse) -> ProtectionSpace? {
        guard response.statusCode == 401, let url = response.url, let host = url.host,
              let header = response.value(forHTTPHeaderField: "WWW-Authenticate") else { return nil }
        let scheme = header.prefix { $0 != " " }.lowercased()
        guard scheme == "basic" else { return nil }
        var realm: String?
        if let range = header.range(of: "realm=") {
            let rest = header[range.upperBound...]
            realm = rest.hasPrefix("\"") ? String(rest.dropFirst().prefix { $0 != "\"" }) : String(rest.prefix { $0 != "," })
        }
        let scheme_ = url.scheme?.lowercased() ?? "http"
        return ProtectionSpace(host: host, port: url.port ?? (scheme_ == "https" ? 443 : 80), protocolName: scheme_, realm: realm,
                               method: "NSURLAuthenticationMethodHTTPBasic")
    }

    static func challenge(_ task: Task, _ held: (response: URLResponse, data: Data), events: SessionEvents, session: Session) {
        guard let http = held.response as? HTTPURLResponse, let space = space(for: http) else {
            return deliver(task, held, events: events, session: session)
        }
        let challenge = Challenge(space: space, proposed: task.lastCredential, previousFailureCount: task.failures,
                                  failureResponse: Response(held.response), error: nil)
        nonisolated(unsafe) let events = events
        events.task(task, didReceive: challenge) { disposition, credential in
            switch disposition {
            case 0 where credential != nil:
                task.failures += 1
                task.lastCredential = credential
                guard var request = task.first.originalRequest else { return deliver(task, held, events: events, session: session) }
                let pair = "\(credential?.user ?? ""):\(credential?.password ?? "")"
                request.setValue("Basic " + Data(pair.utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
                let old = task.value
                let retry = session.value.dataTask(with: request)
                session.adopt(retry, for: task)
                task.replace(with: retry)
                session.forget(old)
                retry.resume()
            case 2:
                task.cancelledChallenge = true
                task.markCompleted()
                events.task(task, didCompleteWith: Failure(URLError(.cancelled), url: task.first.originalRequest?.url))
                session.forget(task.value)
            default:
                deliver(task, held, events: events, session: session)
            }
        }
    }

    /// The 401 as the server sent it.
    static func deliver(_ task: Task, _ held: (response: URLResponse, data: Data), events: SessionEvents, session: Session) {
        events.task(task, didReceive: Response(held.response)) { _ in }
        if !held.data.isEmpty {
            task.count(held.data.count)
            events.task(task, didReceive: held.data)
        }
        task.markCompleted()
        events.task(task, didCompleteWith: nil)
        session.forget(task.value)
    }
}

import Foundation
import FoundationNetworking

// URL loading over swift-corelibs-foundation's URLSession, libcurl's client
// in Swift, for CFNetwork's Objective-C classes. This module alone imports
// that Foundation; its API speaks in FoundationEssentials' URL, Data and
// Date and in its own reference types, so the provider never sees
// corelibs' Objective-C-named classes.

// MARK: - Requests

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

    public func copy() -> Request { Request(value) }

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
            && value.mainDocumentURL == other.value.mainDocumentURL
    }
    public var hash: Int { value.hashValue }
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

    init(_ value: URLSessionConfiguration) {
        self.value = value
    }

    public static func makeDefault() -> Configuration { Configuration(.default) }
    public static func makeEphemeral() -> Configuration { Configuration(.ephemeral) }

    public static func makeBackground(identifier: String) -> Configuration {
        // Linux has no background transfers: an ordinary configuration.
        let configuration = Configuration(.default)
        configuration.identifier = identifier
        return configuration
    }

    public var identifier: String?

    public func copy() -> Configuration {
        let copy = Configuration(value.copy() as! URLSessionConfiguration)
        copy.identifier = identifier
        copy.waitsForConnectivity = waitsForConnectivity
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
    let value: URLSessionTask
    public let kind: Kind
    /// The Objective-C object standing for the task, unretained.
    public var owner: UnsafeMutableRawPointer?

    public enum Kind: Sendable { case data, upload, download }

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
        self.value = value
        self.kind = kind
    }

    public var identifier: Int { value.taskIdentifier }
    /// NSURLSessionTaskState: running 0, suspended 1, canceling 2, completed 3.
    public var state: Int {
        lock.lock()
        defer { lock.unlock() }
        return completed ? URLSessionTask.State.completed.rawValue : value.state.rawValue
    }
    public var originalRequest: Request? { value.originalRequest.map(Request.init) }
    public var currentRequest: Request? { value.currentRequest.map(Request.init) }
    public var response: Response? { value.response.map(Response.init) }
    public var bytesReceived: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return max(value.countOfBytesReceived, delivered)
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
}

/// corelibs' delegate: forwards each event to the Objective-C side.
final class Forwarder: NSObject, URLSessionDataDelegate, URLSessionDownloadDelegate, @unchecked Sendable {
    weak var session: Session?
    var events: SessionEvents? { session?.events }

    func task(_ task: URLSessionTask) -> Task? { session?.task(for: task) }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let events, let task = task(dataTask) else { return completionHandler(.allow) }
        nonisolated(unsafe) let handler = completionHandler
        events.task(task, didReceive: Response(response)) { disposition in
            handler(URLSession.ResponseDisposition(rawValue: disposition) ?? .allow)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let task = task(dataTask) else { return }
        task.count(data.count)
        events?.task(task, didReceive: data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let events, let wrapper = self.task(task) else { return completionHandler(request) }
        nonisolated(unsafe) let handler = completionHandler
        events.task(wrapper, willRedirect: Response(response), to: Request(request)) { handler($0?.value) }
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
        wrapper.markCompleted()
        events?.task(wrapper, didCompleteWith: error.map { Failure($0, url: task.originalRequest?.url) })
        self.session?.forget(task)
    }

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: (any Error)?) {
        events?.sessionDidBecomeInvalid(error.map { Failure($0, url: nil) })
        self.session?.events = nil
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

    fileprivate func task(for task: URLSessionTask) -> Task? {
        lock.lock()
        defer { lock.unlock() }
        return tasks[ObjectIdentifier(task)]
    }

    fileprivate func forget(_ task: URLSessionTask) {
        lock.lock()
        tasks[ObjectIdentifier(task)] = nil
        lock.unlock()
    }

    private func track(_ task: URLSessionTask, _ kind: Task.Kind) -> Task {
        let wrapper = Task(task, kind: kind)
        lock.lock()
        tasks[ObjectIdentifier(task)] = wrapper
        lock.unlock()
        return wrapper
    }

    public typealias DataCompletion = @Sendable (Data?, Response?, Failure?) -> Void
    public typealias DownloadCompletion = @Sendable (URL?, Response?, Failure?) -> Void

    private static func dataHandler(_ completion: @escaping DataCompletion, _ url: URL?)
        -> @Sendable (Data?, URLResponse?, (any Error)?) -> Void {
        { data, response, error in completion(data, response.map(Response.init), error.map { Failure($0, url: url) }) }
    }

    public func dataTask(_ request: Request, completion: DataCompletion? = nil) -> Task {
        guard let completion else { return track(value.dataTask(with: request.value), .data) }
        return track(value.dataTask(with: request.value, completionHandler: Self.dataHandler(completion, request.url)), .data)
    }

    public func uploadTask(_ request: Request, data: Data, completion: DataCompletion? = nil) -> Task {
        guard let completion else { return track(value.uploadTask(with: request.value, from: data), .upload) }
        return track(value.uploadTask(with: request.value, from: data,
                                      completionHandler: Self.dataHandler(completion, request.url)), .upload)
    }

    public func uploadTask(_ request: Request, file: URL, completion: DataCompletion? = nil) -> Task {
        guard let completion else { return track(value.uploadTask(with: request.value, fromFile: file), .upload) }
        return track(value.uploadTask(with: request.value, fromFile: file,
                                      completionHandler: Self.dataHandler(completion, request.url)), .upload)
    }

    public func downloadTask(_ request: Request, completion: DownloadCompletion? = nil) -> Task {
        guard let completion else { return track(value.downloadTask(with: request.value), .download) }
        let url = request.url
        return track(value.downloadTask(with: request.value) { location, response, error in
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

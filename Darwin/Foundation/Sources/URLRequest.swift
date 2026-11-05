// URLRequest, a value over the NSMutableURLRequest it bridges to: a
// request is copied before it changes when another value shares it.

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
public struct URLRequest: ReferenceConvertible, Equatable, Hashable, Sendable {
    public typealias ReferenceType = NSURLRequest
    public typealias CachePolicy = NSURLRequest.CachePolicy
    public typealias NetworkServiceType = NSURLRequest.NetworkServiceType
    public typealias Attribution = NSURLRequest.Attribution

    /// The request, which only this value holds when it changes.
    final class Storage: @unchecked Sendable {
        let request: NSMutableURLRequest

        init(_ request: NSMutableURLRequest) {
            self.request = request
        }
    }

    var storage: Storage

    init(_request request: NSURLRequest) {
        storage = Storage(request.mutableCopy() as! NSMutableURLRequest)
    }

    /// The request to read.
    var _request: NSMutableURLRequest { storage.request }

    /// The request to change, copied first when shared.
    var _mutableRequest: NSMutableURLRequest {
        mutating get {
            if !isKnownUniquelyReferenced(&storage) {
                storage = Storage(storage.request.mutableCopy() as! NSMutableURLRequest)
            }
            return storage.request
        }
    }

    /// Creates and initializes a URL request with the given URL, cache
    /// policy and timeout interval.
    public init(url: URL, cachePolicy: CachePolicy = .useProtocolCachePolicy, timeoutInterval: TimeInterval = 60.0) {
        storage = Storage(NSMutableURLRequest(url: url, cachePolicy: cachePolicy, timeoutInterval: timeoutInterval))
    }

    /// The URL of the receiver.
    public var url: URL? {
        get { _request.url }
        set { _mutableRequest.url = newValue }
    }

    /// The cache policy of the receiver.
    public var cachePolicy: CachePolicy {
        get { _request.cachePolicy }
        set { _mutableRequest.cachePolicy = newValue }
    }

    /// The timeout interval of the receiver.
    public var timeoutInterval: TimeInterval {
        get { _request.timeoutInterval }
        set { _mutableRequest.timeoutInterval = newValue }
    }

    /// The main document URL associated with this load.
    public var mainDocumentURL: URL? {
        get { _request.mainDocumentURL }
        set { _mutableRequest.mainDocumentURL = newValue }
    }

    /// The network service type of the request.
    public var networkServiceType: NetworkServiceType {
        get { _request.networkServiceType }
        set { _mutableRequest.networkServiceType = newValue }
    }

    /// Whether the connection may use the cellular radio.
    public var allowsCellularAccess: Bool {
        get { _request.allowsCellularAccess }
        set { _mutableRequest.allowsCellularAccess = newValue }
    }

    /// Whether the connection may use an expensive network.
    public var allowsExpensiveNetworkAccess: Bool {
        get { _request.allowsExpensiveNetworkAccess }
        set { _mutableRequest.allowsExpensiveNetworkAccess = newValue }
    }

    /// Whether the connection may use a constrained network.
    public var allowsConstrainedNetworkAccess: Bool {
        get { _request.allowsConstrainedNetworkAccess }
        set { _mutableRequest.allowsConstrainedNetworkAccess = newValue }
    }

    /// Whether the request is assumed to be to an HTTP/3 server.
    public var assumesHTTP3Capable: Bool {
        get { _request.assumesHTTP3Capable }
        set { _mutableRequest.assumesHTTP3Capable = newValue }
    }

    /// Who initiated the request.
    public var attribution: Attribution {
        get { _request.attribution }
        set { _mutableRequest.attribution = newValue }
    }

    /// Whether DNS lookups for the request are DNSSEC-validated.
    public var requiresDNSSECValidation: Bool {
        get { _request.requiresDNSSECValidation }
        set { _mutableRequest.requiresDNSSECValidation = newValue }
    }

    /// The HTTP request method.
    public var httpMethod: String? {
        get { _request.httpMethod }
        set { _mutableRequest.httpMethod = newValue ?? "GET" }
    }

    /// A dictionary containing all of the HTTP header fields for a request.
    public var allHTTPHeaderFields: [String: String]? {
        get { _request.allHTTPHeaderFields }
        set { _mutableRequest.allHTTPHeaderFields = newValue }
    }

    /// The value of the given header field, case-insensitively.
    public func value(forHTTPHeaderField field: String) -> String? {
        _request.value(forHTTPHeaderField: field)
    }

    /// Sets a value for a header field, replacing any it had.
    public mutating func setValue(_ value: String?, forHTTPHeaderField field: String) {
        _mutableRequest.setValue(value, forHTTPHeaderField: field)
    }

    /// Adds a value to a header field.
    public mutating func addValue(_ value: String, forHTTPHeaderField field: String) {
        _mutableRequest.addValue(value, forHTTPHeaderField: field)
    }

    /// The data sent as the message body of a request.
    public var httpBody: Data? {
        get { _request.httpBody }
        set { _mutableRequest.httpBody = newValue }
    }

    /// The stream used to deliver the HTTP body.
    public var httpBodyStream: InputStream? {
        get { _request.httpBodyStream }
        set { _mutableRequest.httpBodyStream = newValue }
    }

    /// Whether cookies will be sent with and set for this request.
    public var httpShouldHandleCookies: Bool {
        get { _request.httpShouldHandleCookies }
        set { _mutableRequest.httpShouldHandleCookies = newValue }
    }

    /// Whether the request may be pipelined.
    @available(iOS, introduced: 8.0, deprecated: 18.4, message: "Only supported in the classic loading mode, please adopt HTTP/2 and HTTP/3 instead")
    public var httpShouldUsePipelining: Bool {
        get { _request.httpShouldUsePipelining }
        set { _mutableRequest.httpShouldUsePipelining = newValue }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
        hasher.combine(httpMethod)
    }

    public static func == (lhs: URLRequest, rhs: URLRequest) -> Bool {
        lhs.storage === rhs.storage || lhs._request.isEqual(rhs._request)
    }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension URLRequest: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        url?.description ?? "url: nil"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(self, children: [
            "url": url as Any,
            "cachePolicy": cachePolicy.rawValue,
            "timeoutInterval": timeoutInterval,
            "httpMethod": httpMethod as Any,
            "allHTTPHeaderFields": allHTTPHeaderFields as Any,
            "httpBody": httpBody as Any,
        ], displayStyle: .struct)
    }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension URLRequest: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSURLRequest

    public static func _getObjectiveCType() -> Any.Type {
        NSURLRequest.self
    }

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSURLRequest {
        _request.copy() as! NSURLRequest
    }

    public static func _forceBridgeFromObjectiveC(_ input: NSURLRequest, result: inout URLRequest?) {
        result = URLRequest(_request: input)
    }

    public static func _conditionallyBridgeFromObjectiveC(_ input: NSURLRequest, result: inout URLRequest?) -> Bool {
        result = URLRequest(_request: input)
        return true
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSURLRequest?) -> URLRequest {
        URLRequest(_request: source!)
    }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension NSURLRequest: _HasCustomAnyHashableRepresentation {
    @nonobjc
    public func _toCustomAnyHashable() -> AnyHashable? {
        AnyHashable(URLRequest._unconditionallyBridgeFromObjectiveC(self))
    }
}

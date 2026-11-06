import FoundationEssentials
import PerryObjCInterop
import PerryURLLoading

// NSURLRequest and NSMutableURLRequest hold a PerryURLLoading request: a
// corelibs URLRequest.

enum Requests {
    static let states = StateTable<Request>()

    static func request(_ object: UnsafeMutableRawPointer) -> Request {
        if let request = states.get(object) { return request }
        let request = Request(url: nil)
        states.set(object, request)
        return request
    }

    /// A new request object of `cls` (+0) holding `request`.
    static func make(_ request: Request, cls: ObjCClass) -> NSObject {
        let object = cls.autoreleasedInstance()
        states.set(object.objcObject, request)
        return object
    }

    static func object(_ request: Request, mutable: Bool = false) -> NSObject {
        make(request, cls: mutable ? NSMutableURLRequest.objCClass : NSURLRequest.objCClass)
    }
}

/// NSURLRequest.
@ObjCClass("NSURLRequest")
open class NSURLRequest: NSObject {
    var request: Request { Requests.request(objcObject) }

    @ObjCMethod("dealloc")
    func dealloc() {
        Requests.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSURLRequest.objCClass.pointer)
    }

    @ObjCClassMethod("requestWithURL:")
    static func make(_ cls: ObjCClass, url: NSURL?) -> NSObject { Requests.make(Request(url: url?.url), cls: cls) }

    @ObjCClassMethod("requestWithURL:cachePolicy:timeoutInterval:")
    static func make(_ cls: ObjCClass, url: NSURL?, cachePolicy: UInt, timeoutInterval: Double) -> NSObject {
        Requests.make(Request(url: url?.url, cachePolicy: Int(cachePolicy), timeout: timeoutInterval), cls: cls)
    }

    @ObjCMethod("init")
    func initialize() -> Self {
        _ = request
        return self
    }

    @ObjCMethod("initWithURL:")
    func initialize(url: NSURL?) -> Self {
        Requests.states.set(objcObject, Request(url: url?.url))
        return self
    }

    @ObjCMethod("initWithURL:cachePolicy:timeoutInterval:")
    func initialize(url: NSURL?, cachePolicy: UInt, timeoutInterval: Double) -> Self {
        Requests.states.set(objcObject, Request(url: url?.url, cachePolicy: Int(cachePolicy), timeout: timeoutInterval))
        return self
    }

    @ObjCMethod("URL") func url() -> NSURL? { request.url.flatMap(NSURL.of) }
    @ObjCMethod("HTTPMethod") func httpMethod() -> String { request.method }

    @ObjCMethod("allHTTPHeaderFields")
    func allHTTPHeaderFields() -> NSDictionary? {
        request.headers.map { headers in
            NSMutableDictionary.of(headers.sorted { $0.key < $1.key }.map { ($0.key, NSObject.string($0.value)) })
        }
    }

    @ObjCMethod("valueForHTTPHeaderField:") func value(forHTTPHeaderField name: String) -> String? { request.header(name) }
    @ObjCMethod("HTTPBody") func httpBody() -> NSData? { request.body.map(NSData.of) }
    @ObjCMethod("HTTPBodyStream") func httpBodyStream() -> NSObject? { nil }
    @ObjCMethod("timeoutInterval") func timeoutInterval() -> Double { request.timeout }
    @ObjCMethod("cachePolicy") func cachePolicy() -> UInt { UInt(request.cachePolicy) }
    @ObjCMethod("HTTPShouldHandleCookies") func httpShouldHandleCookies() -> Bool { request.handlesCookies }
    @ObjCMethod("HTTPShouldUsePipelining") func httpShouldUsePipelining() -> Bool { request.usesPipelining }
    @ObjCMethod("mainDocumentURL") func mainDocumentURL() -> NSURL? { request.mainDocumentURL.flatMap(NSURL.of) }
    @ObjCMethod("allowsCellularAccess") func allowsCellularAccess() -> Bool { request.allowsCellularAccess }
    @ObjCMethod("allowsExpensiveNetworkAccess") func allowsExpensiveNetworkAccess() -> Bool { true }
    @ObjCMethod("allowsConstrainedNetworkAccess") func allowsConstrainedNetworkAccess() -> Bool { true }
    @ObjCMethod("networkServiceType") func networkServiceType() -> UInt { UInt(request.networkServiceType) }

    /// A copy is of the request's own class, as CFNetwork's is: a mutable
    /// request's copy is mutable, which Swift's URLRequest relies on.
    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
        ObjCRuntime.retain(Requests.object(request.copy(), mutable: isKind(of: NSMutableURLRequest.objCClass)).objcObject)!
    }

    // MARK: NSSecureCoding

    @ObjCClassMethod("supportsSecureCoding") static func supportsSecureCoding() -> Bool { true }

    /// The URL, method, headers, body and loading settings, by name.
    @ObjCMethod("encodeWithCoder:")
    func encode(with coder: NSObject) {
        coder.sendEncode(url(), forKey: "URL")
        coder.sendEncode(NSObject.string(request.method), forKey: "HTTPMethod")
        coder.sendEncode(allHTTPHeaderFields(), forKey: "allHTTPHeaderFields")
        coder.sendEncode(httpBody(), forKey: "HTTPBody")
        coder.sendEncode(double: request.timeout, forKey: "timeoutInterval")
        coder.sendEncode(integer: request.cachePolicy, forKey: "cachePolicy")
        coder.sendEncode(bool: request.handlesCookies, forKey: "HTTPShouldHandleCookies")
        coder.sendEncode(bool: request.allowsCellularAccess, forKey: "allowsCellularAccess")
    }

    @ObjCMethod("initWithCoder:")
    func initialize(coder: NSObject) -> Self {
        let decoded = Request(url: coder.sendDecodeObject(forKey: "URL")?.as(NSURL.self)?.url)
        if let method = coder.sendDecodeObject(forKey: "HTTPMethod") { decoded.method = method.stringValue }
        decoded.headers = coder.sendDecodeObject(forKey: "allHTTPHeaderFields")?.as(NSDictionary.self)?.strings
        decoded.body = coder.sendDecodeObject(forKey: "HTTPBody")?.as(NSData.self)?.data
        if coder.sendContainsValue(forKey: "timeoutInterval") { decoded.timeout = coder.sendDecodeDouble(forKey: "timeoutInterval") }
        decoded.cachePolicy = coder.sendDecodeInteger(forKey: "cachePolicy")
        if coder.sendContainsValue(forKey: "HTTPShouldHandleCookies") {
            decoded.handlesCookies = coder.sendDecodeBool(forKey: "HTTPShouldHandleCookies")
        }
        if coder.sendContainsValue(forKey: "allowsCellularAccess") {
            decoded.allowsCellularAccess = coder.sendDecodeBool(forKey: "allowsCellularAccess")
        }
        Requests.states.set(objcObject, decoded)
        return self
    }

    @ObjCMethod("mutableCopyWithZone:")
    func mutableCopy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
        ObjCRuntime.retain(Requests.object(request.copy(), mutable: true).objcObject)!
    }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: NSObject?) -> Bool {
        guard let other, let request = Requests.states.get(other.objcObject) else { return false }
        return request.isEqual(to: self.request)
    }

    @ObjCMethod("hash") func hash() -> UInt { UInt(bitPattern: request.hash) }

    @ObjCMethod("description")
    func description() -> String {
        let name = isKind(of: NSMutableURLRequest.objCClass) ? "NSMutableURLRequest" : "NSURLRequest"
        return "<\(name): \(objcObject)> { URL: \(request.url?.absoluteString ?? "(null)") }"
    }
}

/// NSMutableURLRequest.
@ObjCClass("NSMutableURLRequest")
open class NSMutableURLRequest: NSURLRequest {
    @ObjCMethod("setURL:") func setURL(_ url: NSURL?) { request.url = url?.url }
    @ObjCMethod("setHTTPMethod:") func setHTTPMethod(_ method: String?) { request.method = method ?? "GET" }

    @ObjCMethod("setAllHTTPHeaderFields:")
    func setAllHTTPHeaderFields(_ fields: NSDictionary?) { request.headers = fields?.strings }

    @ObjCMethod("setValue:forHTTPHeaderField:")
    func setValue(_ value: String?, forHTTPHeaderField name: String) { request.setHeader(value, for: name) }

    @ObjCMethod("addValue:forHTTPHeaderField:")
    func addValue(_ value: String, forHTTPHeaderField name: String) { request.addHeader(value, for: name) }

    @ObjCMethod("setHTTPBody:") func setHTTPBody(_ body: NSData?) { request.body = body?.data }
    @ObjCMethod("setTimeoutInterval:") func setTimeoutInterval(_ timeout: Double) { request.timeout = timeout }
    @ObjCMethod("setCachePolicy:") func setCachePolicy(_ policy: UInt) { request.cachePolicy = Int(policy) }
    @ObjCMethod("setHTTPShouldHandleCookies:") func setHTTPShouldHandleCookies(_ value: Bool) { request.handlesCookies = value }
    @ObjCMethod("setHTTPShouldUsePipelining:") func setHTTPShouldUsePipelining(_ value: Bool) { request.usesPipelining = value }
    @ObjCMethod("setMainDocumentURL:") func setMainDocumentURL(_ url: NSURL?) { request.mainDocumentURL = url?.url }
    @ObjCMethod("setAllowsCellularAccess:") func setAllowsCellularAccess(_ value: Bool) { request.allowsCellularAccess = value }
    @ObjCMethod("setNetworkServiceType:") func setNetworkServiceType(_ value: UInt) { request.networkServiceType = Int(value) }
}

/// NSCoder's keyed messages.
extension NSObject {
    @ObjCMethod("encodeObject:forKey:") func sendEncode(_ object: NSObject?, forKey key: String)
    @ObjCMethod("encodeDouble:forKey:") func sendEncode(double value: Double, forKey key: String)
    @ObjCMethod("encodeInteger:forKey:") func sendEncode(integer value: Int, forKey key: String)
    @ObjCMethod("encodeBool:forKey:") func sendEncode(bool value: Bool, forKey key: String)
    @ObjCMethod("decodeObjectForKey:") func sendDecodeObject(forKey key: String) -> NSObject?
    @ObjCMethod("decodeDoubleForKey:") func sendDecodeDouble(forKey key: String) -> Double
    @ObjCMethod("decodeIntegerForKey:") func sendDecodeInteger(forKey key: String) -> Int
    @ObjCMethod("decodeBoolForKey:") func sendDecodeBool(forKey key: String) -> Bool
    @ObjCMethod("containsValueForKey:") func sendContainsValue(forKey key: String) -> Bool
}

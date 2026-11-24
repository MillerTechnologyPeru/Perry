import FoundationEssentials
import PerryObjCInterop
import PerryURLLoading

// NSHTTPCookie holds a PerryURLLoading cookie; NSHTTPCookieStorage is the
// shared corelibs storage, which URLSession reads and fills.

/// NSHTTPCookie's property keys and the related constants.
@ObjCConstants
enum CookieKeys {
    static let NSHTTPCookieName = "Name"
    static let NSHTTPCookieValue = "Value"
    static let NSHTTPCookieOriginURL = "OriginURL"
    static let NSHTTPCookieVersion = "Version"
    static let NSHTTPCookieDomain = "Domain"
    static let NSHTTPCookiePath = "Path"
    static let NSHTTPCookieSecure = "Secure"
    static let NSHTTPCookieExpires = "Expires"
    static let NSHTTPCookieComment = "Comment"
    static let NSHTTPCookieCommentURL = "CommentURL"
    static let NSHTTPCookieDiscard = "Discard"
    static let NSHTTPCookieMaximumAge = "Max-Age"
    static let NSHTTPCookiePort = "Port"
    static let NSHTTPCookieSameSitePolicy = "SameSite"
    static let NSHTTPCookieSameSiteLax = "lax"
    static let NSHTTPCookieSameSiteStrict = "strict"
    static let NSHTTPCookieManagerAcceptPolicyChangedNotification = "NSHTTPCookieManagerAcceptPolicyChangedNotification"
    static let NSHTTPCookieManagerCookiesChangedNotification = "NSHTTPCookieManagerCookiesChangedNotification"
}

enum Cookies {
    static let states = StateTable<Cookie>()

    static func cookie(_ object: NSObject?) -> Cookie? { object.flatMap { states.get($0.objcObject) } }

    static func object(_ cookie: Cookie) -> NSObject {
        let object = NSHTTPCookie.objCClass.autoreleasedInstance()
        states.set(object.objcObject, cookie)
        return object
    }

    static func objects(_ cookies: [Cookie]) -> NSArray { NSMutableArray.of(cookies.map(object)) }

    /// A Port property's port, the first number in it, as Darwin reads it.
    static func ports(_ text: String) -> [UInt16] {
        let digits = text.drop { !$0.isNumber }.prefix { $0.isNumber }
        guard let first = UInt64(digits.prefix(18)) else { return [] }
        return [UInt16(truncatingIfNeeded: first)]
    }

    /// Whether a cookie may go to a URL's port: one limited to ports names it.
    static func allows(_ cookie: Cookie, port: Int) -> Bool {
        guard let text = cookie.properties.first(where: { $0.0 == CookieKeys.NSHTTPCookiePort })?.1 else { return true }
        let listed = ports(text)
        return listed.isEmpty || listed.contains(UInt16(truncatingIfNeeded: port))
    }

    /// Whether a cookie's domain covers a host.
    static func matches(_ cookie: Cookie, host: String) -> Bool {
        let host = host.lowercased()
        var domain = cookie.domain.lowercased()
        if domain.hasPrefix(".") { domain.removeFirst() }
        return host == domain || host.hasSuffix("." + domain)
    }

    /// The URL a task's cookies are for, and its main document's.
    static func urls(_ task: NSObject?) -> (url: URL?, mainDocument: URL?) {
        guard let task, let request = task.unsafeCast(to: NSURLSessionTask.self).currentRequest() else { return (nil, nil) }
        let value = Requests.request(request.objcObject)
        return (value.url, value.mainDocumentURL)
    }

    /// A properties dictionary's values as corelibs takes them: strings,
    /// dates and URLs.
    static func properties(_ dictionary: NSDictionary) -> [String: Any] {
        var properties: [String: Any] = [:]
        for key in dictionary.allKeys().elements where key.isString {
            guard let value = dictionary.object(forKey: key) else { continue }
            if value.isString {
                properties[key.stringValue] = value.stringValue
            } else if value.isKind(of: ObjCClass(named: "NSDate")) {
                properties[key.stringValue] = value.unsafeCast(to: NSDate.self).date
            } else if value.isKind(of: ObjCClass(named: "NSURL")) {
                properties[key.stringValue] = value.unsafeCast(to: NSURL.self).url
            } else {
                properties[key.stringValue] = value.describedByObject() ?? ""
            }
        }
        return properties
    }
}

/// NSHTTPCookie.
@ObjCClass("NSHTTPCookie")
open class NSHTTPCookie: NSObject {
    var cookie: Cookie? { Cookies.states.get(objcObject) }

    @ObjCMethod("dealloc")
    func dealloc() {
        Cookies.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSHTTPCookie.objCClass.pointer)
    }

    @ObjCClassMethod("cookieWithProperties:")
    static func make(properties: NSDictionary?) -> NSObject? {
        // No properties make no cookie, as on Darwin.
        guard let properties else { return nil }
        return Cookie(properties: Cookies.properties(properties)).map(Cookies.object)
    }

    @ObjCMethod("initWithProperties:")
    func initialize(properties: NSDictionary?) -> UnsafeMutableRawPointer? {
        guard let properties, let cookie = Cookie(properties: Cookies.properties(properties)) else { return nil }
        Cookies.states.set(objcObject, cookie)
        // The receiver's wrapper adopted its reference; the result is +1.
        return ObjCRuntime.retain(objcObject)
    }

    @ObjCClassMethod("cookiesWithResponseHeaderFields:forURL:")
    static func cookies(withResponseHeaderFields fields: NSDictionary?, for url: NSURL?) -> NSArray {
        guard let fields, let url = url?.url else { return NSMutableArray.of([]) }
        return Cookies.objects(Cookie.parse(fields.strings, for: url))
    }

    @ObjCClassMethod("requestHeaderFieldsWithCookies:")
    static func requestHeaderFields(withCookies cookies: NSArray?) -> NSDictionary {
        let headers = Cookie.requestHeaders((cookies?.elements ?? []).compactMap(Cookies.cookie))
        return NSMutableDictionary.of(headers.sorted { $0.key < $1.key }.map { ($0.key, NSObject.string($0.value)) })
    }

    @ObjCMethod("name") func name() -> String { cookie?.name ?? "" }
    @ObjCMethod("value") func value() -> String { cookie?.value_ ?? "" }
    @ObjCMethod("domain") func domain() -> String { cookie?.domain ?? "" }
    @ObjCMethod("path") func path() -> String { cookie?.path ?? "/" }
    @ObjCMethod("expiresDate") func expiresDate() -> NSDate? { cookie?.expiresDate.map(NSDate.of) }
    @ObjCMethod("isSessionOnly") func isSessionOnly() -> Bool { cookie?.isSessionOnly ?? true }
    @ObjCMethod("isSecure") func isSecure() -> Bool { cookie?.isSecure ?? false }
    @ObjCMethod("isHTTPOnly") func isHTTPOnly() -> Bool { cookie?.isHTTPOnly ?? false }
    @ObjCMethod("version") func version() -> UInt { UInt(cookie?.version ?? 0) }
    @ObjCMethod("comment") func comment() -> String? { cookie?.comment }

    /// A property's text, as the cookie was given it.
    private func property(_ name: String) -> String? { cookie?.properties.first { $0.0 == name }?.1 }

    @ObjCMethod("commentURL")
    func commentURL() -> NSURL? {
        guard let text = property(CookieKeys.NSHTTPCookieCommentURL), let url = URL(string: text) else { return nil }
        return NSURL.of(url)
    }

    /// The port the cookie is limited to, as NSNumbers; empty for any port.
    /// Darwin reads one port from the Port property, its first, as an
    /// unsigned 16-bit number.
    @ObjCMethod("portList")
    func portList() -> NSArray {
        guard let text = property(CookieKeys.NSHTTPCookiePort) else { return NSMutableArray.of([]) }
        return NSMutableArray.of(Cookies.ports(text).map { NSNumber.make(int64: Int64($0)) })
    }
    @ObjCMethod("sameSitePolicy") func sameSitePolicy() -> String? { cookie?.sameSitePolicy }

    @ObjCMethod("properties")
    func properties() -> NSDictionary {
        NSMutableDictionary.of((cookie?.properties ?? []).map { ($0.0, NSObject.string($0.1)) })
    }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: NSObject?) -> Bool {
        guard let cookie, let other = Cookies.cookie(other) else { return false }
        return cookie.isEqual(to: other)
    }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }

    @ObjCMethod("description")
    func description() -> String {
        "<NSHTTPCookie name:\(name()) value:\(value()) domain:\(domain()) path:\(path())>"
    }
}

extension NSArray {
    @ObjCMethod("sortedArrayUsingDescriptors:") func sorted(using descriptors: NSArray) -> NSArray
}

/// NSHTTPCookieStorage: the one shared storage.
@ObjCClass("NSHTTPCookieStorage")
open class NSHTTPCookieStorage: NSObject {
    nonisolated(unsafe) static var shared: NSObject?

    @ObjCClassMethod("sharedHTTPCookieStorage")
    static func sharedStorage() -> NSObject {
        if let shared { return shared }
        let storage = objCClass.object.newInstance()
        shared = storage
        return storage
    }

    @ObjCClassMethod("sharedCookieStorageForGroupContainerIdentifier:")
    static func sharedStorage(forGroupContainerIdentifier identifier: String) -> NSObject { sharedStorage() }

    @ObjCMethod("cookies") func cookies() -> NSArray { Cookies.objects(CookieStorage.all) }

    @ObjCMethod("cookiesForURL:")
    func cookies(for url: NSURL?) -> NSArray { Cookies.objects(url?.url.map(CookieStorage.cookies(for:)) ?? []) }

    // A nil cookie or date, which apps pass when they have none, changes nothing.
    @ObjCMethod("setCookie:") func setCookie(_ cookie: NSObject?) { Cookies.cookie(cookie).map(CookieStorage.set) }
    @ObjCMethod("deleteCookie:") func deleteCookie(_ cookie: NSObject?) { Cookies.cookie(cookie).map(CookieStorage.delete) }
    @ObjCMethod("removeCookiesSinceDate:") func removeCookies(since date: NSDate?) { date.map { CookieStorage.removeAll(since: $0.date) } }

    @ObjCMethod("setCookies:forURL:mainDocumentURL:")
    func setCookies(_ cookies: NSArray?, for url: NSURL?, mainDocumentURL: NSURL?) {
        CookieStorage.set((cookies?.elements ?? []).compactMap(Cookies.cookie), for: url?.url, mainDocumentURL: mainDocumentURL?.url)
    }

    /// The cookies, sorted as the descriptors say.
    @ObjCMethod("sortedCookiesUsingDescriptors:")
    func sortedCookies(using descriptors: NSArray?) -> NSArray {
        let all = cookies()
        guard let descriptors else { return all }
        return all.sorted(using: descriptors)
    }

    /// The cookies for the task's URL whose domain covers its host, as
    /// Darwin keeps only those.
    @ObjCMethod("storeCookies:forTask:")
    func storeCookies(_ cookies: NSArray?, for task: NSObject?) {
        let (url, mainDocument) = Cookies.urls(task)
        guard let url, let host = url.host else { return }
        let kept = (cookies?.elements ?? []).compactMap(Cookies.cookie).filter { Cookies.matches($0, host: host) }
        CookieStorage.set(kept, for: url, mainDocumentURL: mainDocument)
    }

    /// The cookies that would go with the task's request, given to the
    /// handler on another thread: void (^)(NSArray<NSHTTPCookie *> *).
    @ObjCMethod("getCookiesForTask:completionHandler:")
    func getCookies(for task: NSObject?, completionHandler: ObjCBlock?) {
        guard let completionHandler else { return }
        let url = Cookies.urls(task).url
        let port = url.map { $0.port ?? ($0.scheme?.lowercased() == "https" ? 443 : 80) } ?? 0
        let found = url.map(CookieStorage.cookies(for:))?.filter { Cookies.allows($0, port: port) } ?? []
        nonisolated(unsafe) let block = completionHandler
        SocketTaskThreads.spawn {
            block.function(as: (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void).self)(
                block.object, Cookies.objects(found).objcObject)
        }
    }

    @ObjCMethod("cookieAcceptPolicy") func cookieAcceptPolicy() -> UInt { UInt(CookieStorage.acceptPolicy) }
    @ObjCMethod("setCookieAcceptPolicy:") func setCookieAcceptPolicy(_ policy: UInt) { CookieStorage.acceptPolicy = Int(policy) }
}

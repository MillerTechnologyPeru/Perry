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
    static func make(properties: NSDictionary) -> NSObject? { Cookie(properties: Cookies.properties(properties)).map(Cookies.object) }

    @ObjCMethod("initWithProperties:")
    func initialize(properties: NSDictionary) -> UnsafeMutableRawPointer? {
        guard let cookie = Cookie(properties: Cookies.properties(properties)) else { return nil }
        Cookies.states.set(objcObject, cookie)
        // The receiver's wrapper adopted its reference; the result is +1.
        return ObjCRuntime.retain(objcObject)
    }

    @ObjCClassMethod("cookiesWithResponseHeaderFields:forURL:")
    static func cookies(withResponseHeaderFields fields: NSDictionary, for url: NSURL) -> NSArray {
        guard let url = url.url else { return NSMutableArray.of([]) }
        return Cookies.objects(Cookie.parse(fields.strings, for: url))
    }

    @ObjCClassMethod("requestHeaderFieldsWithCookies:")
    static func requestHeaderFields(withCookies cookies: NSArray) -> NSDictionary {
        let headers = Cookie.requestHeaders(cookies.elements.compactMap(Cookies.cookie))
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
    func cookies(for url: NSURL) -> NSArray { Cookies.objects(url.url.map(CookieStorage.cookies(for:)) ?? []) }

    @ObjCMethod("setCookie:") func setCookie(_ cookie: NSObject) { Cookies.cookie(cookie).map(CookieStorage.set) }
    @ObjCMethod("deleteCookie:") func deleteCookie(_ cookie: NSObject) { Cookies.cookie(cookie).map(CookieStorage.delete) }
    @ObjCMethod("removeCookiesSinceDate:") func removeCookies(since date: NSDate) { CookieStorage.removeAll(since: date.date) }

    @ObjCMethod("setCookies:forURL:mainDocumentURL:")
    func setCookies(_ cookies: NSArray, for url: NSURL?, mainDocumentURL: NSURL?) {
        CookieStorage.set(cookies.elements.compactMap(Cookies.cookie), for: url?.url, mainDocumentURL: mainDocumentURL?.url)
    }

    @ObjCMethod("cookieAcceptPolicy") func cookieAcceptPolicy() -> UInt { UInt(CookieStorage.acceptPolicy) }
    @ObjCMethod("setCookieAcceptPolicy:") func setCookieAcceptPolicy(_ policy: UInt) { CookieStorage.acceptPolicy = Int(policy) }
}

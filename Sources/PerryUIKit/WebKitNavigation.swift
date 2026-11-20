import PerryObjCInterop

// WebKit's navigations and the rest of its configuration. Without WPE
// there is no web engine, so loads end on the next pass as a page with
// nothing in it would (local content finishes; network requests fail,
// offline), scripts fail to run, and stores hold nothing.

@ObjCWrapper("NSError")
class NSErrorObject: NSObject {
    @ObjCClassMethod("errorWithDomain:code:userInfo:")
    static func make(domain: String, code: Int, userInfo: NSObject?) -> NSErrorObject
}

@ObjCWrapper("NSURLRequest")
class NSURLRequestObject: NSObject {
    @ObjCMethod("URL") func url() -> NSObject?
}

extension NSObject {
    @ObjCMethod("scheme") func sendScheme() -> String?
    @ObjCMethod("webView:didStartProvisionalNavigation:") func sendDidStartProvisionalNavigation(_ view: NSObject, _ navigation: NSObject)
    @ObjCMethod("webView:didCommitNavigation:") func sendDidCommitNavigation(_ view: NSObject, _ navigation: NSObject)
    @ObjCMethod("webView:didFinishNavigation:") func sendDidFinishNavigation(_ view: NSObject, _ navigation: NSObject)
    @ObjCMethod("webView:didFailProvisionalNavigation:withError:")
    func sendDidFailProvisionalNavigation(_ view: NSObject, _ navigation: NSObject, _ error: NSObject)
}

/// WebKit's error domain, which the WKError Swift makes of WebKit's header
/// reads.
@ObjCConstants
enum WebKitErrorConstants {
    static let WKErrorDomain = "WKErrorDomain"
}

/// The kinds of data a website data store holds, by WebKit's names.
@ObjCConstants
enum WebsiteDataTypeConstants {
    static let WKWebsiteDataTypeFetchCache = "WKWebsiteDataTypeFetchCache"
    static let WKWebsiteDataTypeDiskCache = "WKWebsiteDataTypeDiskCache"
    static let WKWebsiteDataTypeMemoryCache = "WKWebsiteDataTypeMemoryCache"
    static let WKWebsiteDataTypeOfflineWebApplicationCache = "WKWebsiteDataTypeOfflineWebApplicationCache"
    static let WKWebsiteDataTypeCookies = "WKWebsiteDataTypeCookies"
    static let WKWebsiteDataTypeSessionStorage = "WKWebsiteDataTypeSessionStorage"
    static let WKWebsiteDataTypeLocalStorage = "WKWebsiteDataTypeLocalStorage"
    static let WKWebsiteDataTypeWebSQLDatabases = "WKWebsiteDataTypeWebSQLDatabases"
    static let WKWebsiteDataTypeIndexedDBDatabases = "WKWebsiteDataTypeIndexedDBDatabases"
    static let WKWebsiteDataTypeServiceWorkerRegistrations = "WKWebsiteDataTypeServiceWorkerRegistrations"
    static let WKWebsiteDataTypeFileSystem = "WKWebsiteDataTypeFileSystem"
    static let WKWebsiteDataTypeSearchFieldRecentSearches = "WKWebsiteDataTypeSearchFieldRecentSearches"
    static let WKWebsiteDataTypeMediaKeys = "WKWebsiteDataTypeMediaKeys"
    static let WKWebsiteDataTypeHashSalt = "WKWebsiteDataTypeHashSalt"
    static let WKWebsiteDataTypeScreenTime = "WKWebsiteDataTypeScreenTime"
}

enum WebErrors {
    /// NSURLErrorNotConnectedToInternet, as without a network.
    static func offline() -> NSErrorObject { NSErrorObject.make(domain: "NSURLErrorDomain", code: -1009, userInfo: nil) }
    /// WKErrorJavaScriptExceptionOccurred: no script runs.
    static func noScript() -> NSErrorObject { NSErrorObject.make(domain: "WKErrorDomain", code: 4, userInfo: nil) }
    /// WKErrorJavaScriptExceptionOccurred, for a script that threw.
    static func exception() -> NSErrorObject { NSErrorObject.make(domain: "WKErrorDomain", code: 4, userInfo: nil) }
    /// WKErrorUnknown.
    static func unknown() -> NSErrorObject { NSErrorObject.make(domain: "WKErrorDomain", code: 1, userInfo: nil) }

    /// A failed load's error, from WPE's GError: as NSURLErrorDomain's
    /// codes where there is one.
    static func loading(domain: String, code: Int) -> NSErrorObject {
        let url: Int
        switch (domain, code) {
        case ("WebKitNetworkError", 302): url = -999                       // cancelled
        case ("WebKitNetworkError", 303): url = -1100                      // file does not exist
        case ("WebKitNetworkError", 301): url = -1002                      // unsupported URL
        case ("WebKitPolicyError", let code): return NSErrorObject.make(domain: "WebKitErrorDomain", code: code, userInfo: nil)
        case ("g-resolver-error-quark", _): url = -1003                    // cannot find host
        case ("g-io-error-quark", 39): url = -1004                         // cannot connect to host (refused)
        case ("g-io-error-quark", 24): url = -1001                         // timed out
        case ("g-tls-error-quark", _): url = -1200                         // secure connection failed
        default: url = -1                                                  // unknown
        }
        return NSErrorObject.make(domain: "NSURLErrorDomain", code: url, userInfo: nil)
    }
}

/// What a load returns, and its delegate calls name.
@ObjCClass("WKNavigation")
open class WKNavigation: NSObject {
    @ObjCMethod("init") public required override init() { super.init() }
}

enum WebNavigations {
    /// A new navigation whose outcome the web view's delegate hears after
    /// the pass: finished, or failed with `error`. The view is kept until
    /// then.
    static func start(_ view: NSObject, failing error: NSErrorObject?) -> NSObject {
        let navigation = WKNavigation()
        let object = ObjCRuntime.retain(view.objcObject)!
        Updates.afterPass {
            defer { ObjCRuntime.release(object) }
            let view = WKWebView(objcObject: object, ownership: .retain)
            guard let delegate = view.navigationDelegate() else { return }
            if delegate.responds(to: "webView:didStartProvisionalNavigation:") {
                delegate.sendDidStartProvisionalNavigation(view, navigation)
            }
            if let error {
                if delegate.responds(to: "webView:didFailProvisionalNavigation:withError:") {
                    delegate.sendDidFailProvisionalNavigation(view, navigation, error)
                }
                return
            }
            if delegate.responds(to: "webView:didCommitNavigation:") { delegate.sendDidCommitNavigation(view, navigation) }
            if delegate.responds(to: "webView:didFinishNavigation:") { delegate.sendDidFinishNavigation(view, navigation) }
        }
        return navigation
    }

    /// Loads from the network fail; others (files, data, about:) finish.
    static func isNetwork(_ url: NSObject?) -> Bool {
        guard let scheme = url?.sendScheme()?.lowercased() else { return false }
        return scheme == "http" || scheme == "https" || scheme == "ws" || scheme == "wss"
    }
}

/// A script the content controller keeps; no page runs it.
@ObjCClass("WKUserScript")
open class WKUserScript: NSObject {
    var source: String?
    /// WKUserScriptInjectionTime: at document start 0, at document end 1.
    var injectionTime = 0
    var forMainFrameOnly = true

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("initWithSource:injectionTime:forMainFrameOnly:")
    public required init(source: String?, injectionTime: Int, forMainFrameOnly: Bool) {
        super.init()
        (self.source, self.injectionTime, self.forMainFrameOnly) = (source, injectionTime, forMainFrameOnly)
    }

    @ObjCMethod("initWithSource:injectionTime:forMainFrameOnly:inContentWorld:")
    public required init(source: String?, injectionTime: Int, forMainFrameOnly: Bool, world: NSObject?) {
        super.init()
        (self.source, self.injectionTime, self.forMainFrameOnly) = (source, injectionTime, forMainFrameOnly)
    }

    @ObjCMethod("source") func sourceValue() -> String? { source }
    @ObjCMethod("injectionTime") func injectionTimeValue() -> Int { injectionTime }
    @ObjCMethod("isForMainFrameOnly") func isForMainFrameOnly() -> Bool { forMainFrameOnly }
}

/// Per-navigation preferences: JavaScript allowed, the recommended content
/// mode.
@ObjCClass("WKWebpagePreferences")
open class WKWebpagePreferences: NSObject {
    var allowsContentJavaScript = true
    /// WKContentMode: recommended 0, mobile 1, desktop 2.
    var preferredContentMode = 0

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("allowsContentJavaScript") func allowsContentJavaScriptValue() -> Bool { allowsContentJavaScript }
    @ObjCMethod("setAllowsContentJavaScript:") func setAllowsContentJavaScript(_ value: Bool) { allowsContentJavaScript = value }
    @ObjCMethod("preferredContentMode") func preferredContentModeValue() -> Int { preferredContentMode }
    @ObjCMethod("setPreferredContentMode:") func setPreferredContentMode(_ value: Int) { preferredContentMode = value }
}

/// The web views' cookies: there are none; changes are accepted and their
/// handlers run after the pass.
@ObjCClass("WKHTTPCookieStore")
open class WKHTTPCookieStore: NSObject {
    @ObjCMethod("init") public required override init() { super.init() }

    nonisolated(unsafe) static let shared = WKHTTPCookieStore()

    @ObjCMethod("getAllCookies:")
    func getAllCookies(_ handler: ObjCBlock?) {
        guard let handler else { return }
        Updates.afterPass {
            typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?) -> Void
            handler.function(as: Invoke.self)(handler.object, NSMutableArray.empty().objcObject)
        }
    }

    @ObjCMethod("setCookie:completionHandler:")
    func setCookie(_ cookie: NSObject?, completionHandler: ObjCBlock?) {
        guard let completionHandler else { return }
        Updates.afterPass { Blocks.call(completionHandler) }
    }

    @ObjCMethod("deleteCookie:completionHandler:")
    func deleteCookie(_ cookie: NSObject?, completionHandler: ObjCBlock?) {
        guard let completionHandler else { return }
        Updates.afterPass { Blocks.call(completionHandler) }
    }

    @ObjCMethod("addObserver:") func addObserver(_ observer: NSObject?) {}
    @ObjCMethod("removeObserver:") func removeObserver(_ observer: NSObject?) {}
}

/// Where scripts run. Pages have one world here, so every world is the
/// page's; worlds keep their names.
@ObjCClass("WKContentWorld")
open class WKContentWorld: NSObject {
    var worldName: String?

    @ObjCMethod("init") public required override init() { super.init() }

    nonisolated(unsafe) static let page = WKContentWorld()
    nonisolated(unsafe) static let defaultClient = WKContentWorld()

    @ObjCClassMethod("pageWorld") static func pageWorld() -> NSObject { page }
    @ObjCClassMethod("defaultClientWorld") static func defaultClientWorld() -> NSObject { defaultClient }
    @ObjCClassMethod("worldWithName:") static func world(name: String?) -> NSObject {
        let world = WKContentWorld()
        world.worldName = name
        return world
    }
    @ObjCMethod("name") func name() -> String? { worldName }
}

// MARK: - Navigation policy

/// Where a navigation comes from or goes: the main frame, always.
@ObjCClass("WKFrameInfo")
open class WKFrameInfo: NSObject {
    var frameRequest: NSObject?

    @ObjCMethod("init") public required override init() { super.init() }
    @ObjCMethod("isMainFrame") func isMainFrame() -> Bool { true }
    @ObjCMethod("request") func request() -> NSObject? { frameRequest }
}

/// A navigation the delegate is asked to allow.
@ObjCClass("WKNavigationAction")
open class WKNavigationAction: NSObject {
    var actionRequest: NSObject?
    var type = -1
    var frame: WKFrameInfo?

    @ObjCMethod("init") public required override init() { super.init() }
    @ObjCMethod("request") func request() -> NSObject? { actionRequest }
    @ObjCMethod("navigationType") func navigationType() -> Int { type }
    @ObjCMethod("sourceFrame") func sourceFrame() -> NSObject? { frame }
    @ObjCMethod("targetFrame") func targetFrame() -> NSObject? { frame }
    @ObjCMethod("shouldPerformDownload") func shouldPerformDownload() -> Bool { false }
    @ObjCMethod("modifierFlags") func modifierFlags() -> Int { 0 }
    @ObjCMethod("buttonNumber") func buttonNumber() -> Int { 0 }
}

extension NSObject {
    @ObjCMethod("webView:decidePolicyForNavigationAction:decisionHandler:")
    func sendDecidePolicy(_ view: NSObject, _ action: NSObject, _ handler: UnsafeMutableRawPointer?)
    @ObjCMethod("webView:decidePolicyForNavigationAction:preferences:decisionHandler:")
    func sendDecidePolicy(_ view: NSObject, _ action: NSObject, preferences: NSObject?, _ handler: UnsafeMutableRawPointer?)
}

/// The navigation delegate's say over a navigation, before it loads: an app
/// takes its sign-in page's last redirect, to a scheme of its own, from
/// here (Crunchyroll's crunchyroll://sso_auth) and cancels it.
enum WebNavigationPolicy {
    /// What the delegate's handler was called with, during the call.
    nonisolated(unsafe) static var answer: Int?

    /// decisionHandler(policy), and with preferences decisionHandler(policy,
    /// preferences): the policy is the first argument of both.
    nonisolated(unsafe) static let handler: UnsafeMutableRawPointer? = {
        guard let isa = Display.globalBlockClass else { return nil }
        let invoke: @convention(c) (UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?) -> Void = { _, policy, _ in
            WebNavigationPolicy.answer = policy
        }
        let word = MemoryLayout<UnsafeRawPointer>.size
        let descriptor = UnsafeMutableRawPointer.allocate(byteCount: 16, alignment: 8)
        descriptor.storeBytes(of: 0, as: UInt.self)
        descriptor.storeBytes(of: UInt(3 * word + 8), toByteOffset: word, as: UInt.self)
        let block = UnsafeMutableRawPointer.allocate(byteCount: 3 * word + 8, alignment: 8)
        block.storeBytes(of: isa, as: UnsafeMutableRawPointer.self)
        block.storeBytes(of: Int32(1 << 28), toByteOffset: word, as: Int32.self)   // BLOCK_IS_GLOBAL
        block.storeBytes(of: Int32(0), toByteOffset: word + 4, as: Int32.self)
        block.storeBytes(of: unsafeBitCast(invoke, to: UnsafeRawPointer.self), toByteOffset: word + 8, as: UnsafeRawPointer.self)
        block.storeBytes(of: UnsafeRawPointer(descriptor), toByteOffset: 2 * word + 8, as: UnsafeRawPointer.self)
        return block
    }()

    /// Whether the navigation to `uri` goes ahead. WebKit's navigation types
    /// are WKNavigationType's but for "other", its last. A delegate that
    /// answers later is taken to allow what a web engine can load and to
    /// cancel the rest, which it has seen and nothing could load.
    static func decide(_ object: UnsafeMutableRawPointer, uri: String, type: Int32) -> Bool {
        // The page outlives its view while a load winds down: a view the
        // app has let go (its sign-in sheet, once signed in) has no say.
        guard WebViews.live.contains(where: { $0.object == object }) else { return true }
        let view = WKWebView(objcObject: object, ownership: .retain)
        let scheme = uri.prefix { $0 != ":" }.lowercased()
        let configuration = view.web.configuration?.as(WKWebViewConfiguration.self)
        let loadable = ["http", "https", "about", "data", "blob", "file"].contains(scheme)
            || configuration?.schemeHandlers[scheme] != nil
        guard let delegate = view.navigationDelegate(), let handler, Classes.named("NSURLRequest") != nil,
              let request = NSURLObject.make(string: uri).map({ NSURLRequestFactory.make(url: $0) }) else { return true }
        let action = WKNavigationAction()
        let frame = WKFrameInfo()
        frame.frameRequest = request
        action.actionRequest = request
        action.type = (0...4).contains(type) ? Int(type) : -1
        action.frame = frame
        answer = nil
        if delegate.responds(to: "webView:decidePolicyForNavigationAction:preferences:decisionHandler:") {
            delegate.sendDecidePolicy(view, action, preferences: configuration?.defaultWebpagePreferencesObject(), handler)
        } else if delegate.responds(to: "webView:decidePolicyForNavigationAction:decisionHandler:") {
            delegate.sendDecidePolicy(view, action, handler)
        } else {
            return true
        }
        defer { answer = nil }
        // WKNavigationActionPolicyCancel is 0.
        return answer.map { $0 != 0 } ?? loadable
    }
}

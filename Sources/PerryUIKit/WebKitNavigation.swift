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
    func initialize(source: String?, injectionTime: Int, forMainFrameOnly: Bool) -> Self {
        (self.source, self.injectionTime, self.forMainFrameOnly) = (source, injectionTime, forMainFrameOnly)
        return self
    }

    @ObjCMethod("initWithSource:injectionTime:forMainFrameOnly:inContentWorld:")
    func initialize(source: String?, injectionTime: Int, forMainFrameOnly: Bool, world: NSObject?) -> Self {
        initialize(source: source, injectionTime: injectionTime, forMainFrameOnly: forMainFrameOnly)
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

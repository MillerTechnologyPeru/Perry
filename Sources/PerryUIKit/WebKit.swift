import PerryObjCInterop

// WebKit's configuration objects, which WKWebView keeps: they hold what an
// app sets on them, and loading nothing changes nothing.

/// What a web view is made with. A copy shares its objects, as WebKit's
/// shallow copy does.
@ObjCClass("WKWebViewConfiguration")
open class WKWebViewConfiguration: NSObject {
    var websiteDataStore: NSObject?
    var preferences: NSObject?
    var userContentController: NSObject?
    var processPool: NSObject?
    var applicationNameForUserAgent: String?
    var allowsInlineMediaPlayback = false
    var allowsAirPlayForMediaPlayback = true
    var allowsPictureInPictureMediaPlayback = true
    var mediaTypesRequiringUserActionForPlayback: UInt = 15    // WKAudiovisualMediaTypeAll
    var suppressesIncrementalRendering = false
    var dataDetectorTypes: UInt = 0
    var ignoresViewportScaleLimits = false
    var selectionGranularity = 0

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
        let copy = WKWebViewConfiguration()
        (copy.websiteDataStore, copy.preferences, copy.userContentController, copy.processPool) =
            (websiteDataStore, preferences, userContentController, processPool)
        copy.applicationNameForUserAgent = applicationNameForUserAgent
        (copy.allowsInlineMediaPlayback, copy.allowsAirPlayForMediaPlayback, copy.allowsPictureInPictureMediaPlayback) =
            (allowsInlineMediaPlayback, allowsAirPlayForMediaPlayback, allowsPictureInPictureMediaPlayback)
        (copy.mediaTypesRequiringUserActionForPlayback, copy.suppressesIncrementalRendering, copy.dataDetectorTypes) =
            (mediaTypesRequiringUserActionForPlayback, suppressesIncrementalRendering, dataDetectorTypes)
        (copy.ignoresViewportScaleLimits, copy.selectionGranularity) = (ignoresViewportScaleLimits, selectionGranularity)
        return ObjCRuntime.retain(copy.objcObject)!
    }

    /// The defaults are made when first asked for.
    @ObjCMethod("websiteDataStore")
    func websiteDataStoreObject() -> NSObject? {
        if websiteDataStore == nil { websiteDataStore = WKWebsiteDataStore.defaultStore }
        return websiteDataStore
    }
    @ObjCMethod("setWebsiteDataStore:") func setWebsiteDataStore(_ store: NSObject?) { websiteDataStore = store }

    @ObjCMethod("preferences")
    func preferencesObject() -> NSObject? {
        if preferences == nil { preferences = WKPreferences() }
        return preferences
    }
    @ObjCMethod("setPreferences:") func setPreferences(_ object: NSObject?) { preferences = object }

    @ObjCMethod("userContentController")
    func userContentControllerObject() -> NSObject? {
        if userContentController == nil { userContentController = WKUserContentController() }
        return userContentController
    }
    @ObjCMethod("setUserContentController:") func setUserContentController(_ object: NSObject?) { userContentController = object }

    @ObjCMethod("processPool")
    func processPoolObject() -> NSObject? {
        if processPool == nil { processPool = WKProcessPool() }
        return processPool
    }
    @ObjCMethod("setProcessPool:") func setProcessPool(_ object: NSObject?) { processPool = object }

    @ObjCMethod("applicationNameForUserAgent") func applicationNameForUserAgentValue() -> String? { applicationNameForUserAgent }
    @ObjCMethod("setApplicationNameForUserAgent:")
    func setApplicationNameForUserAgent(_ name: String?) { applicationNameForUserAgent = name }

    @ObjCMethod("allowsInlineMediaPlayback") func allowsInlineMediaPlaybackValue() -> Bool { allowsInlineMediaPlayback }
    @ObjCMethod("setAllowsInlineMediaPlayback:") func setAllowsInlineMediaPlayback(_ value: Bool) { allowsInlineMediaPlayback = value }
    @ObjCMethod("allowsAirPlayForMediaPlayback") func allowsAirPlayForMediaPlaybackValue() -> Bool { allowsAirPlayForMediaPlayback }
    @ObjCMethod("setAllowsAirPlayForMediaPlayback:")
    func setAllowsAirPlayForMediaPlayback(_ value: Bool) { allowsAirPlayForMediaPlayback = value }
    @ObjCMethod("allowsPictureInPictureMediaPlayback")
    func allowsPictureInPictureMediaPlaybackValue() -> Bool { allowsPictureInPictureMediaPlayback }
    @ObjCMethod("setAllowsPictureInPictureMediaPlayback:")
    func setAllowsPictureInPictureMediaPlayback(_ value: Bool) { allowsPictureInPictureMediaPlayback = value }
    @ObjCMethod("mediaTypesRequiringUserActionForPlayback")
    func mediaTypesRequiringUserActionForPlaybackValue() -> UInt { mediaTypesRequiringUserActionForPlayback }
    @ObjCMethod("setMediaTypesRequiringUserActionForPlayback:")
    func setMediaTypesRequiringUserActionForPlayback(_ value: UInt) { mediaTypesRequiringUserActionForPlayback = value }
    /// The older Boolean form: audio and video, or none.
    @ObjCMethod("requiresUserActionForMediaPlayback")
    func requiresUserActionForMediaPlayback() -> Bool { mediaTypesRequiringUserActionForPlayback != 0 }
    @ObjCMethod("setRequiresUserActionForMediaPlayback:")
    func setRequiresUserActionForMediaPlayback(_ value: Bool) { mediaTypesRequiringUserActionForPlayback = value ? 15 : 0 }
    @ObjCMethod("mediaPlaybackRequiresUserAction") func mediaPlaybackRequiresUserAction() -> Bool { requiresUserActionForMediaPlayback() }
    @ObjCMethod("setMediaPlaybackRequiresUserAction:")
    func setMediaPlaybackRequiresUserAction(_ value: Bool) { setRequiresUserActionForMediaPlayback(value) }
    @ObjCMethod("suppressesIncrementalRendering") func suppressesIncrementalRenderingValue() -> Bool { suppressesIncrementalRendering }
    @ObjCMethod("setSuppressesIncrementalRendering:")
    func setSuppressesIncrementalRendering(_ value: Bool) { suppressesIncrementalRendering = value }
    @ObjCMethod("dataDetectorTypes") func dataDetectorTypesValue() -> UInt { dataDetectorTypes }
    @ObjCMethod("setDataDetectorTypes:") func setDataDetectorTypes(_ value: UInt) { dataDetectorTypes = value }
    @ObjCMethod("ignoresViewportScaleLimits") func ignoresViewportScaleLimitsValue() -> Bool { ignoresViewportScaleLimits }
    @ObjCMethod("setIgnoresViewportScaleLimits:") func setIgnoresViewportScaleLimits(_ value: Bool) { ignoresViewportScaleLimits = value }
    @ObjCMethod("selectionGranularity") func selectionGranularityValue() -> Int { selectionGranularity }
    @ObjCMethod("setSelectionGranularity:") func setSelectionGranularity(_ value: Int) { selectionGranularity = value }
}

/// Where web views keep cookies and caches: nothing is stored.
@ObjCClass("WKWebsiteDataStore")
open class WKWebsiteDataStore: NSObject {
    var persistent = true

    @ObjCMethod("init") public required override init() { super.init() }

    nonisolated(unsafe) static let defaultStore = WKWebsiteDataStore()

    @ObjCClassMethod("defaultDataStore") static func defaultDataStore() -> WKWebsiteDataStore { defaultStore }

    @ObjCClassMethod("nonPersistentDataStore")
    static func nonPersistentDataStore() -> WKWebsiteDataStore {
        let store = WKWebsiteDataStore()
        store.persistent = false
        return store
    }

    @ObjCClassMethod("allWebsiteDataTypes")
    static func allWebsiteDataTypes() -> NSObject { NSMutableSet.empty() }

    @ObjCMethod("isPersistent") func isPersistent() -> Bool { persistent }

    /// There is no data to remove; the handler runs at once.
    @ObjCMethod("removeDataOfTypes:modifiedSince:completionHandler:")
    func removeData(ofTypes types: NSObject?, modifiedSince date: NSObject?, completionHandler: ObjCBlock?) {
        completionHandler.map(Blocks.call)
    }
}

@ObjCClass("WKPreferences")
open class WKPreferences: NSObject {
    var javaScriptEnabled = true
    var javaScriptCanOpenWindowsAutomatically = false
    var minimumFontSize: CGFloat = 0

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("javaScriptEnabled") func javaScriptEnabledValue() -> Bool { javaScriptEnabled }
    @ObjCMethod("setJavaScriptEnabled:") func setJavaScriptEnabled(_ value: Bool) { javaScriptEnabled = value }
    @ObjCMethod("javaScriptCanOpenWindowsAutomatically")
    func javaScriptCanOpenWindowsAutomaticallyValue() -> Bool { javaScriptCanOpenWindowsAutomatically }
    @ObjCMethod("setJavaScriptCanOpenWindowsAutomatically:")
    func setJavaScriptCanOpenWindowsAutomatically(_ value: Bool) { javaScriptCanOpenWindowsAutomatically = value }
    @ObjCMethod("minimumFontSize") func minimumFontSizeValue() -> CGFloat { minimumFontSize }
    @ObjCMethod("setMinimumFontSize:") func setMinimumFontSize(_ value: CGFloat) { minimumFontSize = value }
}

/// Scripts and message handlers, kept; no page runs them.
@ObjCClass("WKUserContentController")
open class WKUserContentController: NSObject {
    var userScripts: [NSObject] = []
    var handlers: [String: NSObject] = [:]

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("userScripts") func userScriptsObject() -> NSObject { NSMutableArray.of(userScripts) }
    @ObjCMethod("addUserScript:") func addUserScript(_ script: NSObject) { userScripts.append(script) }
    @ObjCMethod("removeAllUserScripts") func removeAllUserScripts() { userScripts.removeAll() }
    @ObjCMethod("addScriptMessageHandler:name:")
    func addScriptMessageHandler(_ handler: NSObject, name: String) { handlers[name] = handler }
    @ObjCMethod("removeScriptMessageHandlerForName:")
    func removeScriptMessageHandler(forName name: String) { handlers[name] = nil }
}

@ObjCClass("WKProcessPool")
open class WKProcessPool: NSObject {
    @ObjCMethod("init") public required override init() { super.init() }
}

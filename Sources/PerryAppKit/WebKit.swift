import CPerryGeometry
import Glibc
import PerryObjCInterop

// A Mac app's WebKit: WKWebView and the legacy WebView, both NSViews over a
// page of WPE WebKit's (WPE.swift), whose frames are the view's layer's
// contents. Clicks, wheel turns and keys go to the page. WKWebView's script
// message handlers hear window.webkit.messageHandlers[name].postMessage(),
// and its user scripts run on each load. The legacy WebView loads, draws
// and evaluates scripts, but its window script object's values aren't
// reachable from the page: JavaScript can't call Objective-C here. Without
// WPE the views take their loads and show nothing.

// MARK: - Messages

private enum Calls {
    typealias Object = UnsafeMutableRawPointer
    typealias Selector = UnsafeRawPointer

    static func object(_ receiver: Object?, _ selector: String, _ first: Object?, _ second: Object?, _ third: Object?) -> Object? {
        guard let receiver else { return nil }
        typealias F = @convention(c) (Object, Selector, Object?, Object?, Object?) -> Object?
        return unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector(selector), first, second, third)
    }

    static func object(_ receiver: Object?, _ selector: String, _ first: Object?, int second: Int, _ third: Object?) -> Object? {
        guard let receiver else { return nil }
        typealias F = @convention(c) (Object, Selector, Object?, Int, Object?) -> Object?
        return unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector(selector), first, second, third)
    }

    static func object(_ receiver: Object?, _ selector: String, uint argument: UInt) -> Object? {
        guard let receiver else { return nil }
        typealias F = @convention(c) (Object, Selector, UInt) -> Object?
        return unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector(selector), argument)
    }

    static func void(_ receiver: Object?, _ selector: String, _ first: Object?, _ second: Object?, _ third: Object?) {
        guard let receiver else { return }
        typealias F = @convention(c) (Object, Selector, Object?, Object?, Object?) -> Void
        unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector(selector), first, second, third)
    }

    static func string(_ object: Object?) -> String? { object.map { String(objCArgument: $0) } }

    /// An NSURL's absolute string.
    static func absoluteString(_ url: Object?) -> String? { string(Send.object(url, "absoluteString")) }

    /// An NSURL, +0.
    static func url(_ string: String?) -> Object? {
        guard let string else { return nil }
        return Send.object(ObjCRuntime.classObject("NSURL"), "URLWithString:", string.objCArgument())
    }

    /// An NSURLRequest for a URL, +0.
    static func request(_ url: Object?) -> Object? {
        guard let url else { return nil }
        return Send.object(ObjCRuntime.classObject("NSURLRequest"), "requestWithURL:", url)
    }

    /// Foundation's value for JSON (+0): strings, numbers, Booleans, arrays
    /// and dictionaries, and NSNull for null.
    static func object(json: String) -> Object? {
        guard let data = object(json.objCArgument(), "dataUsingEncoding:", uint: 4) else { return nil }   // NSUTF8StringEncoding
        // NSJSONReadingFragmentsAllowed.
        return object(ObjCRuntime.classObject("NSJSONSerialization"), "JSONObjectWithData:options:error:", data, int: 4, nil)
    }

    /// NSError, +0.
    static func error(domain: String, code: Int, description: String?) -> Object? {
        var info: Object?
        if let description {
            info = object(ObjCRuntime.classObject("NSDictionary"), "dictionaryWithObject:forKey:",
                          description.objCArgument(), "NSLocalizedDescription".objCArgument(), nil)
        }
        return object(ObjCRuntime.classObject("NSError"), "errorWithDomain:code:userInfo:", domain.objCArgument(), int: code, info)
    }
}

// MARK: - Drawing frames

/// CoreGraphics' bitmap images, bound the first time a frame is drawn.
private enum Bitmaps {
    typealias Ref = UnsafeMutableRawPointer
    private static let coreGraphics = "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"
    private static let coreFoundation = "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"

    struct Functions {
        let colorSpace: @convention(c) () -> Ref?
        let context: @convention(c) (Ref?, Int, Int, Int, Int, Ref?, UInt32) -> Ref?
        let data: @convention(c) (Ref?) -> Ref?
        let image: @convention(c) (Ref?) -> Ref?
        let release: @convention(c) (Ref?) -> Void
    }

    nonisolated(unsafe) static let functions: Functions? = {
        func bind<T>(_ library: String, _ name: String, _: T.Type) -> T? { Symbols.symbol(library, name).map { unsafeBitCast($0, to: T.self) } }
        guard let colorSpace = bind(coreGraphics, "_CGColorSpaceCreateDeviceRGB", (@convention(c) () -> Ref?).self),
              let context = bind(coreGraphics, "_CGBitmapContextCreate", (@convention(c) (Ref?, Int, Int, Int, Int, Ref?, UInt32) -> Ref?).self),
              let data = bind(coreGraphics, "_CGBitmapContextGetData", (@convention(c) (Ref?) -> Ref?).self),
              let image = bind(coreGraphics, "_CGBitmapContextCreateImage", (@convention(c) (Ref?) -> Ref?).self),
              let release = bind(coreFoundation, "_CFRelease", (@convention(c) (Ref?) -> Void).self) else {
            WPE.log("CoreGraphics' bitmap contexts are missing; web views show nothing")
            return nil
        }
        return Functions(colorSpace: colorSpace, context: context, data: data, image: image, release: release)
    }()

    /// A CGImage (+1) of a frame: Wayland's ARGB8888, premultiplied, first
    /// byte blue.
    static func image(_ bytes: UnsafeRawPointer, width: Int, height: Int, stride: Int) -> Ref? {
        guard let cg = functions, let space = cg.colorSpace() else { return nil }
        defer { cg.release(space) }
        guard let context = cg.context(nil, width, height, 8, width * 4, space, 2 | 0x2000) else { return nil }
        defer { cg.release(context) }
        guard let data = cg.data(context) else { return nil }
        for row in 0..<height {
            (data + row * width * 4).copyMemory(from: bytes + row * stride, byteCount: width * 4)
        }
        return cg.image(context)
    }

    static func release(_ object: Ref?) { if let object { functions?.release(object) } }
}

// MARK: - The page behind a view

/// What both web views keep: the page, made on the first load, and the
/// view's frames. Not retained by the page's callbacks, which name the
/// view by its object.
final class WebContent {
    unowned let view: NSView
    var page: WebPage?
    var customUserAgent: String?
    /// The last frame, +1.
    var frameImage: UnsafeMutableRawPointer?
    var loadFinished = false
    var buttons: UInt32 = 0
    private var lastFrameSize = (0, 0)
    /// Set up a new page, before its first load.
    var prepare: ((WebPage) -> Void)?
    var loadChanged: ((Int32) -> Void)?
    var loadFailed: ((Bool, String, Int, String) -> Void)?

    init(_ view: NSView) { self.view = view }

    /// A JavaScript evaluation still on its way keeps the page, whose
    /// callbacks name this content and its view, both gone by then.
    deinit {
        page?.detach()
        Bitmaps.release(frameImage)
    }

    /// The view's page; nil without WPE.
    func ensurePage() -> WebPage? {
        if let page { return page }
        let size = view.bounds.size
        let scale = view.backingScale
        guard let page = WebPage(width: UInt32(max(size.width, 1)), height: UInt32(max(size.height, 1)), scale: Float(scale)) else { return nil }
        self.page = page
        Trace.log("web view: a page of \(Int(size.width))x\(Int(size.height)) at \(scale)x")
        if let customUserAgent { page.setUserAgent(customUserAgent) }
        page.frame = { [unowned self] bytes, width, height, stride in self.show(bytes, width: width, height: height, stride: stride) }
        page.loadChanged = { [unowned self] event in
            Trace.log("web view: load event \(event) at \(self.page?.uri ?? "?")")
            if event == WPE.loadStarted { self.loadFinished = false }
            if event == WPE.loadFinished { self.loadFinished = true }
            self.loadChanged?(event)
        }
        page.loadFailed = { [unowned self] committed, domain, code, message in self.loadFailed?(committed, domain, code, message) }
        prepare?(page)
        return page
    }

    private func show(_ bytes: UnsafeRawPointer, width: Int, height: Int, stride: Int) {
        guard let image = Bitmaps.image(bytes, width: width, height: height, stride: stride) else { return }
        if (width, height) != lastFrameSize {
            lastFrameSize = (width, height)
            Trace.log("web view: frames of \(width)x\(height); layer \(view.layer == nil ? "none yet" : "there"), window \(view.windowObject == nil ? "none" : "there")")
        }
        Bitmaps.release(frameImage)
        frameImage = image
        view.ensureLayer()
        guard let layer = view.layer else { return }
        let wrapped = CALayer(objcObject: layer.objcObject, ownership: .retain)
        CATransaction.withoutActions {
            wrapped.setContents(NSObject(image))
            wrapped.setContentsScale(CGFloat(page?.scale ?? 1))
        }
        Windows.layersChanged()
    }

    /// The page follows the view's size.
    func resize() {
        let size = view.bounds.size
        page?.resize(width: UInt32(max(size.width, 1)), height: UInt32(max(size.height, 1)), scale: Float(view.backingScale))
    }

    func load(_ request: UnsafeMutableRawPointer?) -> Bool {
        guard let page = ensurePage(), let uri = Calls.absoluteString(Send.object(request, "URL")) else { return false }
        Trace.log("web view: loading \(uri)")
        page.loadURI(uri)
        return true
    }

    func loadHTML(_ html: String?, baseURL: UnsafeMutableRawPointer?) -> Bool {
        guard let page = ensurePage() else { return false }
        page.loadHTML(html ?? "", baseURI: Calls.absoluteString(baseURL) ?? "about:blank")
        return true
    }

    // MARK: Input

    /// A mouse event's point in the page: the view's, from the top left.
    private func point(_ event: NSEvent) -> (Int32, Int32) {
        var point = view.convert(event.locationInWindow, from: nil)
        if !view.flipped { point.y = view.bounds.height - point.y }
        return (Int32(point.x.rounded(.down)), Int32(point.y.rounded(.down)))
    }

    /// wpe_input_keyboard_modifier: control, shift, alt, meta; and the
    /// pointer's buttons held, from 1 << 20.
    private func modifiers(_ event: NSEvent) -> UInt32 {
        let flags = event.modifierFlags
        var modifiers: UInt32 = 0
        if flags & (1 << 18) != 0 { modifiers |= 1 << 0 }
        if flags & (1 << 17) != 0 { modifiers |= 1 << 1 }
        if flags & (1 << 19) != 0 { modifiers |= 1 << 2 }
        if flags & (1 << 20) != 0 { modifiers |= 1 << 3 }
        for button in 1...3 where buttons & (1 << (button - 1)) != 0 { modifiers |= 1 << (19 + UInt32(button)) }
        return modifiers
    }

    func mouse(_ event: NSEvent, button: UInt32?, pressed: Bool) {
        guard let page else { return }
        let (x, y) = point(event)
        guard let button else { return page.pointer(motion: true, x: x, y: y, button: 0, pressed: false, modifiers: modifiers(event)) }
        if pressed {
            page.pointer(motion: true, x: x, y: y, button: 0, pressed: false, modifiers: modifiers(event))
            buttons |= 1 << (button - 1)
        } else {
            buttons &= ~(1 << (button - 1))
        }
        page.pointer(motion: false, x: x, y: y, button: button, pressed: pressed, modifiers: modifiers(event))
    }

    func scroll(_ event: NSEvent) {
        guard let page else { return }
        let (x, y) = point(event)
        // Precise deltas are points; a wheel's are lines, of 40 points.
        let unit: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 40
        let dy = (event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY) * unit
        let dx = (event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.deltaX) * unit
        if dy != 0 { page.axis(x: x, y: y, horizontal: false, value: Int32(dy.rounded()), modifiers: modifiers(event)) }
        if dx != 0 { page.axis(x: x, y: y, horizontal: true, value: Int32(dx.rounded()), modifiers: modifiers(event)) }
    }

    /// Mac virtual key codes WebKit knows by X11 key symbols.
    private static let keySymbols: [UInt16: UInt32] = [
        0x24: 0xff0d, 0x4C: 0xff8d, 0x30: 0xff09, 0x33: 0xff08, 0x35: 0xff1b, 0x75: 0xffff,
        0x7B: 0xff51, 0x7C: 0xff53, 0x7D: 0xff54, 0x7E: 0xff52,
        0x73: 0xff50, 0x77: 0xff57, 0x74: 0xff55, 0x79: 0xff56,
        0x38: 0xffe1, 0x3C: 0xffe2, 0x3B: 0xffe3, 0x3E: 0xffe4, 0x3A: 0xffe9, 0x3D: 0xffea, 0x37: 0xffeb, 0x36: 0xffec,
    ]

    func key(_ event: NSEvent, pressed: Bool) {
        guard let page else { return }
        var symbol = WebContent.keySymbols[event.keyCode]
        if symbol == nil, let scalar = (pressed ? event.characters : event.charactersIgnoringModifiers).unicodeScalars.first
            ?? event.charactersIgnoringModifiers.unicodeScalars.first {
            // Latin-1's symbols are their code points; the rest are Unicode's, from 0x1000000.
            symbol = scalar.value < 0x100 ? scalar.value : 0x0100_0000 | scalar.value
        }
        guard let symbol else { return }
        // Evdev's code, as X11's: the Mac's key code isn't one.
        page.key(symbol: symbol, hardwareCode: UInt32(event.keyCode) + 8, pressed: pressed, modifiers: modifiers(event))
    }
}

// MARK: - WKWebView's configuration

@ObjCClass("WKPreferences")
open class WKPreferences: NSObject {
    var javaScriptEnabled = true
    var values: [String: NSObject] = [:]

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("javaScriptEnabled") func isJavaScriptEnabled() -> Bool { javaScriptEnabled }
    @ObjCMethod("setJavaScriptEnabled:") func setJavaScriptEnabled(_ enabled: Bool) { javaScriptEnabled = enabled }
    @ObjCMethod("javaScriptCanOpenWindowsAutomatically") func javaScriptCanOpenWindowsAutomatically() -> Bool { false }
    @ObjCMethod("setJavaScriptCanOpenWindowsAutomatically:") func setJavaScriptCanOpenWindowsAutomatically(_ value: Bool) {}
    @ObjCMethod("minimumFontSize") func minimumFontSize() -> CGFloat { 0 }
    @ObjCMethod("setMinimumFontSize:") func setMinimumFontSize(_ size: CGFloat) {}
    @ObjCMethod("isElementFullscreenEnabled") func isElementFullscreenEnabled() -> Bool { false }
    @ObjCMethod("setElementFullscreenEnabled:") func setElementFullscreenEnabled(_ value: Bool) {}

    /// Private preferences set by key (developerExtrasEnabled), kept.
    @ObjCMethod("setValue:forKey:") func setValue(_ value: NSObject?, forKey key: String?) { if let key { values[key] = value } }
    @ObjCMethod("valueForKey:") func value(forKey key: String?) -> NSObject? { key.flatMap { values[$0] } }
}

@ObjCClass("WKUserScript")
open class WKUserScript: NSObject {
    var source = ""
    var injectionTime = 0
    var mainFrameOnly = true

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithSource:injectionTime:forMainFrameOnly:")
    public required init(source: String?, injectionTime: Int, forMainFrameOnly mainFrameOnly: Bool) {
        super.init()
        self.source = source ?? ""
        self.injectionTime = injectionTime
        self.mainFrameOnly = mainFrameOnly
    }

    @ObjCMethod("source") func scriptSource() -> String { source }
    @ObjCMethod("injectionTime") func scriptInjectionTime() -> Int { injectionTime }
    @ObjCMethod("isForMainFrameOnly") func isForMainFrameOnly() -> Bool { mainFrameOnly }
}

/// A compiled set of content-blocking rules. Pages here don't apply them
/// (there is no rule compiler), but apps that compile and add lists at
/// launch get lists back.
@ObjCClass("WKContentRuleList")
open class WKContentRuleList: NSObject {
    var identifier = ""
    var encoded = ""

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("identifier") func ruleListIdentifier() -> String { identifier }
}

@ObjCClass("WKContentRuleListStore")
open class WKContentRuleListStore: NSObject {
    nonisolated(unsafe) private static let shared = WKContentRuleListStore()
    private var lists: [String: WKContentRuleList] = [:]

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCClassMethod("defaultStore") class func defaultStore() -> WKContentRuleListStore { shared }
    @ObjCClassMethod("storeWithURL:") class func store(url: NSObject?) -> WKContentRuleListStore { WKContentRuleListStore() }

    @ObjCMethod("compileContentRuleListForIdentifier:encodedContentRuleList:completionHandler:")
    func compile(identifier: String?, encoded: String?, completionHandler: ObjCBlock?) {
        let list = WKContentRuleList()
        list.identifier = identifier ?? ""
        list.encoded = encoded ?? ""
        lists[list.identifier] = list
        guard let completionHandler else { return }
        Dispatch.onMain { Blocks.call(completionHandler, list.objcObject, nil) }
    }

    @ObjCMethod("lookUpContentRuleListForIdentifier:completionHandler:")
    func lookUp(identifier: String?, completionHandler: ObjCBlock?) {
        let list = identifier.flatMap { lists[$0] }
        guard let completionHandler else { return }
        Dispatch.onMain {
            Blocks.call(completionHandler, list?.objcObject,
                        list == nil ? Calls.error(domain: "WKErrorDomain", code: 7, description: "No rule list with that identifier") : nil)
        }
    }

    @ObjCMethod("removeContentRuleListForIdentifier:completionHandler:")
    func remove(identifier: String?, completionHandler: ObjCBlock?) {
        if let identifier { lists[identifier] = nil }
        if let completionHandler { Dispatch.onMain { Blocks.call(completionHandler, nil) } }
    }

    @ObjCMethod("getAvailableContentRuleListIdentifiers:")
    func availableIdentifiers(completionHandler: ObjCBlock?) {
        let identifiers = NSMutableArray.of(lists.keys.sorted().compactMap { $0.objCArgument().map(NSObject.init) })
        if let completionHandler { Dispatch.onMain { Blocks.call(completionHandler, identifiers.objcObject) } }
    }
}

/// A page's view of a controller: weak, as the views own their pages.
private final class PageReference {
    weak var page: WebPage?
    init(_ page: WebPage) { self.page = page }
}

@ObjCClass("WKUserContentController")
open class WKUserContentController: NSObject {
    /// Retained, as WebKit's.
    var handlers: [(name: String, handler: NSObject)] = []
    var scripts: [WKUserScript] = []
    private var pages: [PageReference] = []

    @ObjCMethod("init")
    public required override init() { super.init() }

    /// Gives a new page the handlers and scripts there are, and those added later.
    func attach(_ page: WebPage) {
        pages.removeAll { $0.page == nil }
        pages.append(PageReference(page))
        for (name, _) in handlers { page.addMessageHandler(name) }
        for script in scripts { page.addUserScript(script.source, atStart: script.injectionTime == 0, mainFrameOnly: script.mainFrameOnly) }
    }

    private var livePages: [WebPage] { pages.compactMap(\.page) }

    func handler(named name: String) -> NSObject? { handlers.first { $0.name == name }?.handler }

    @ObjCMethod("addScriptMessageHandler:name:")
    func addScriptMessageHandler(_ handler: NSObject?, name: String?) {
        guard let handler, let name, self.handler(named: name) == nil else { return }
        handlers.append((name, handler))
        for page in livePages { page.addMessageHandler(name) }
    }

    @ObjCMethod("addScriptMessageHandler:contentWorld:name:")
    func addScriptMessageHandler(_ handler: NSObject?, contentWorld: NSObject?, name: String?) { addScriptMessageHandler(handler, name: name) }

    @ObjCMethod("removeScriptMessageHandlerForName:")
    func removeScriptMessageHandler(forName name: String?) {
        guard let name else { return }
        handlers.removeAll { $0.name == name }
        for page in livePages { page.removeMessageHandler(name) }
    }

    @ObjCMethod("removeAllScriptMessageHandlers")
    func removeAllScriptMessageHandlers() {
        for (name, _) in handlers { for page in livePages { page.removeMessageHandler(name) } }
        handlers = []
    }

    @ObjCMethod("addUserScript:")
    func addUserScript(_ script: WKUserScript?) {
        guard let script else { return }
        scripts.append(script)
        for page in livePages { page.addUserScript(script.source, atStart: script.injectionTime == 0, mainFrameOnly: script.mainFrameOnly) }
    }

    @ObjCMethod("removeAllUserScripts")
    func removeAllUserScripts() {
        scripts = []
        for page in livePages { page.removeAllUserScripts() }
    }

    @ObjCMethod("userScripts") func userScripts() -> NSObject { NSMutableArray.of(scripts) }

    var ruleLists: [WKContentRuleList] = []
    @ObjCMethod("addContentRuleList:")
    func addContentRuleList(_ list: WKContentRuleList?) { if let list, !ruleLists.contains(where: { $0 === list }) { ruleLists.append(list) } }
    @ObjCMethod("removeContentRuleList:")
    func removeContentRuleList(_ list: WKContentRuleList?) { ruleLists.removeAll { $0 === list } }
    @ObjCMethod("removeAllContentRuleLists") func removeAllContentRuleLists() { ruleLists = [] }
}

@ObjCClass("WKWebViewConfiguration")
open class WKWebViewConfiguration: NSObject {
    var userContentController = WKUserContentController()
    var preferences = WKPreferences()
    var schemeHandlers: [String: NSObject] = [:]
    var values: [String: NSObject] = [:]
    var applicationNameForUserAgent: String?
    var websiteDataStore: NSObject?
    var processPool: NSObject?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("userContentController") func configurationUserContentController() -> WKUserContentController { userContentController }
    @ObjCMethod("setUserContentController:")
    func setUserContentController(_ controller: WKUserContentController?) { userContentController = controller ?? WKUserContentController() }
    @ObjCMethod("preferences") func configurationPreferences() -> WKPreferences { preferences }
    @ObjCMethod("setPreferences:") func setPreferences(_ preferences: WKPreferences?) { self.preferences = preferences ?? WKPreferences() }
    @ObjCMethod("applicationNameForUserAgent") func configurationApplicationName() -> String? { applicationNameForUserAgent }
    @ObjCMethod("setApplicationNameForUserAgent:") func setApplicationNameForUserAgent(_ name: String?) { applicationNameForUserAgent = name }
    @ObjCMethod("websiteDataStore") func configurationWebsiteDataStore() -> NSObject? { websiteDataStore }
    @ObjCMethod("setWebsiteDataStore:") func setWebsiteDataStore(_ store: NSObject?) { websiteDataStore = store }
    @ObjCMethod("processPool") func configurationProcessPool() -> NSObject? { processPool }
    @ObjCMethod("setProcessPool:") func setProcessPool(_ pool: NSObject?) { processPool = pool }
    @ObjCMethod("setSuppressesIncrementalRendering:") func setSuppressesIncrementalRendering(_ value: Bool) {}
    @ObjCMethod("setAllowsAirPlayForMediaPlayback:") func setAllowsAirPlayForMediaPlayback(_ value: Bool) {}
    @ObjCMethod("setMediaTypesRequiringUserActionForPlayback:") func setMediaTypesRequiringUserActionForPlayback(_ types: UInt) {}
    @ObjCMethod("setLimitsNavigationsToAppBoundDomains:") func setLimitsNavigationsToAppBoundDomains(_ value: Bool) {}
    @ObjCMethod("defaultWebpagePreferences") func defaultWebpagePreferences() -> NSObject? { nil }

    /// Schemes an app serves itself. WPE asks no handler for them here, so
    /// their loads fail.
    @ObjCMethod("setURLSchemeHandler:forURLScheme:")
    func setURLSchemeHandler(_ handler: NSObject?, forURLScheme scheme: String?) {
        guard let scheme else { return }
        schemeHandlers[scheme] = handler
        WPE.log("no URL scheme handlers here: \(scheme): loads fail")
    }

    @ObjCMethod("urlSchemeHandlerForURLScheme:") func urlSchemeHandler(forURLScheme scheme: String?) -> NSObject? { scheme.flatMap { schemeHandlers[$0] } }

    /// Private settings set by key (allowFileAccessFromFileURLs), kept.
    @ObjCMethod("setValue:forKey:") func setValue(_ value: NSObject?, forKey key: String?) { if let key { values[key] = value } }
    @ObjCMethod("valueForKey:") func value(forKey key: String?) -> NSObject? { key.flatMap { values[$0] } }
}

@ObjCClass("WKSnapshotConfiguration")
open class WKSnapshotConfiguration: NSObject {
    var rect = CGRect(x: CGFloat.infinity, y: CGFloat.infinity, width: 0, height: 0)    // CGRectNull
    var snapshotWidth: NSObject?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("rect") func snapshotRect() -> CGRect { rect }
    @ObjCMethod("setRect:") func setRect(_ rect: CGRect) { self.rect = rect }
    @ObjCMethod("snapshotWidth") func configurationSnapshotWidth() -> NSObject? { snapshotWidth }
    @ObjCMethod("setSnapshotWidth:") func setSnapshotWidth(_ width: NSObject?) { snapshotWidth = width }
    @ObjCMethod("setAfterScreenUpdates:") func setAfterScreenUpdates(_ value: Bool) {}
}

@ObjCClass("WKScriptMessage")
open class WKScriptMessage: NSObject {
    var body: NSObject?
    var name = ""
    /// Not retained.
    var webViewObject: UnsafeMutableRawPointer?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("body") func messageBody() -> NSObject? { body }
    @ObjCMethod("name") func messageName() -> String { name }
    @ObjCMethod("webView") func messageWebView() -> NSObject? { webViewObject.map(NSObject.init) }
    @ObjCMethod("frameInfo") func frameInfo() -> NSObject? { WKFrameInfo() }
    @ObjCMethod("world") func world() -> NSObject? { nil }
}

/// The page's main frame, which every message and navigation is from.
@ObjCClass("WKFrameInfo")
open class WKFrameInfo: NSObject {
    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("isMainFrame") func isMainFrame() -> Bool { true }
    @ObjCMethod("request") func request() -> NSObject? { nil }
}

@ObjCClass("WKNavigation")
open class WKNavigation: NSObject {
    @ObjCMethod("init")
    public required override init() { super.init() }
}

// MARK: - WKWebView

@ObjCClass("WKWebView")
open class WKWebView: NSView {
    var configuration = WKWebViewConfiguration()
    /// Not retained, as WebKit's.
    var navigationDelegate: UnsafeMutableRawPointer?
    var uiDelegate: UnsafeMutableRawPointer?
    var navigation: WKNavigation?
    var navigationFailed = false
    var drawsBackground = true
    var values: [String: NSObject] = [:]
    lazy var content: WebContent = makeContent()

    @ObjCMethod("initWithFrame:configuration:")
    public required init(frame: CGRect, configuration: WKWebViewConfiguration?) {
        super.init(frame: frame)
        if let configuration { self.configuration = configuration }
    }

    @ObjCMethod("initWithFrame:")
    public required init(frame: CGRect) { super.init(frame: frame) }

    @ObjCMethod("init")
    public required init() { super.init() }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) { super.init(coder: coder) }

    private func makeContent() -> WebContent {
        let content = WebContent(self)
        let object = objcObject
        let configuration = configuration
        content.prepare = { [unowned content] page in
            if let name = configuration.applicationNameForUserAgent, content.customUserAgent == nil {
                page.setUserAgent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) \(name)")
            }
            page.scriptMessage = { name, json in WKWebView.deliver(object, name, json) }
            configuration.userContentController.attach(page)
        }
        content.loadChanged = { event in WKWebView.loadChanged(object, event) }
        content.loadFailed = { committed, domain, code, message in
            WKWebView.loadFailed(object, committed: committed, domain: domain, code: code, message: message)
        }
        return content
    }

    @ObjCMethod("isFlipped") override func isFlipped() -> Bool { true }
    @ObjCMethod("acceptsFirstResponder") override func acceptsFirstResponder() -> Bool { true }
    @ObjCMethod("acceptsFirstMouse:") override func acceptsFirstMouse(_ event: NSObject?) -> Bool { true }

    @ObjCMethod("setFrameSize:")
    override func setFrameSize(_ size: CGSize) {
        Trace.log("web view: size \(size)")
        super.setFrameSize(size)
        content.resize()
    }

    @ObjCMethod("viewDidMoveToWindow")
    override func viewDidMoveToWindow() {
        Trace.log("web view: in a window, frame \(frame), superview \(superview.map { "\($0.frame)" } ?? "none")")
    }

    @ObjCMethod("configuration") func webConfiguration() -> WKWebViewConfiguration { configuration }
    @ObjCMethod("navigationDelegate") func webNavigationDelegate() -> NSObject? { navigationDelegate.map(NSObject.init) }
    @ObjCMethod("setNavigationDelegate:") func setNavigationDelegate(_ delegate: NSObject?) { navigationDelegate = delegate?.objcObject }
    @ObjCMethod("UIDelegate") func webUIDelegate() -> NSObject? { uiDelegate.map(NSObject.init) }
    @ObjCMethod("setUIDelegate:") func setUIDelegate(_ delegate: NSObject?) { uiDelegate = delegate?.objcObject }

    private func begin() -> WKNavigation {
        let navigation = WKNavigation()
        self.navigation = navigation
        navigationFailed = false
        return navigation
    }

    /// A navigation that fails at once: without WPE, the page can't load.
    private func failing() -> WKNavigation {
        let navigation = begin()
        let object = objcObject
        Dispatch.onMain {
            WKWebView.loadFailed(object, committed: false, domain: "NSURLErrorDomain", code: -1009, message: "Web views can't load pages here")
        }
        return navigation
    }

    @ObjCMethod("loadRequest:")
    func loadRequest(_ request: NSObject?) -> WKNavigation {
        content.load(request?.objcObject) ? begin() : failing()
    }

    @ObjCMethod("loadFileURL:allowingReadAccessToURL:")
    func loadFileURL(_ url: NSObject?, allowingReadAccessTo directory: NSObject?) -> WKNavigation {
        content.load(Calls.request(url?.objcObject)) ? begin() : failing()
    }

    @ObjCMethod("loadHTMLString:baseURL:")
    func loadHTMLString(_ html: String?, baseURL: NSObject?) -> WKNavigation {
        content.loadHTML(html, baseURL: baseURL?.objcObject) ? begin() : failing()
    }

    @ObjCMethod("loadData:MIMEType:characterEncodingName:baseURL:")
    func loadData(_ data: NSObject?, mimeType: String?, encoding: String?, baseURL: NSObject?) -> WKNavigation {
        let html = Send.object(ObjCRuntime.classObject("NSString"), "alloc").flatMap {
            Calls.object($0, "initWithData:encoding:", data?.objcObject, int: 4, nil)
        }
        defer { ObjCRuntime.release(html) }
        return content.loadHTML(Calls.string(html), baseURL: baseURL?.objcObject) ? begin() : failing()
    }

    @ObjCMethod("customUserAgent") func webCustomUserAgent() -> String? { content.customUserAgent }
    @ObjCMethod("setCustomUserAgent:")
    func setCustomUserAgent(_ agent: String?) {
        content.customUserAgent = agent
        content.page?.setUserAgent(agent)
    }

    @ObjCMethod("URL") func url() -> NSObject? { Calls.url(content.page?.uri).map(NSObject.init) }
    @ObjCMethod("title") func title() -> String? { content.page?.title ?? "" }
    @ObjCMethod("isLoading") func isLoading() -> Bool { content.page?.isLoading ?? false }
    @ObjCMethod("estimatedProgress") func estimatedProgress() -> Double { content.page?.progress ?? 1 }
    @ObjCMethod("canGoBack") func canGoBack() -> Bool { content.page?.canGoBack ?? false }
    @ObjCMethod("canGoForward") func canGoForward() -> Bool { content.page?.canGoForward ?? false }
    @ObjCMethod("goBack")
    func goBack() -> WKNavigation? {
        guard let page = content.page, page.canGoBack else { return nil }
        page.goBack()
        return begin()
    }
    @ObjCMethod("goForward")
    func goForward() -> WKNavigation? {
        guard let page = content.page, page.canGoForward else { return nil }
        page.goForward()
        return begin()
    }
    @ObjCMethod("reload")
    func reload() -> WKNavigation? {
        guard let page = content.page else { return nil }
        page.reload()
        return begin()
    }
    @ObjCMethod("stopLoading") func stopLoading() { content.page?.stopLoading() }
    @ObjCMethod("allowsBackForwardNavigationGestures") func allowsBackForwardNavigationGestures() -> Bool { false }
    @ObjCMethod("setAllowsBackForwardNavigationGestures:") func setAllowsBackForwardNavigationGestures(_ allows: Bool) {}
    @ObjCMethod("allowsMagnification") func allowsMagnification() -> Bool { false }
    @ObjCMethod("setAllowsMagnification:") func setAllowsMagnification(_ allows: Bool) {}
    @ObjCMethod("allowsLinkPreview") func allowsLinkPreview() -> Bool { false }
    @ObjCMethod("setAllowsLinkPreview:") func setAllowsLinkPreview(_ allows: Bool) {}
    @ObjCMethod("isInspectable") func isInspectable() -> Bool { false }
    @ObjCMethod("setInspectable:") func setInspectable(_ inspectable: Bool) {}
    @ObjCMethod("setUnderPageBackgroundColor:") func setUnderPageBackgroundColor(_ color: NSObject?) {}
    @ObjCMethod("magnification") func magnification() -> CGFloat { 1 }
    @ObjCMethod("setMagnification:centeredAtPoint:") func setMagnification(_ magnification: CGFloat, centeredAt point: CGPoint) {}

    /// The page plays no media of its own to close, pause or suspend.
    @ObjCMethod("closeAllMediaPresentationsWithCompletionHandler:")
    func closeAllMediaPresentations(completionHandler: ObjCBlock?) { if let completionHandler { Dispatch.onMain { Blocks.call(completionHandler) } } }
    @ObjCMethod("closeAllMediaPresentations") func closeAllMediaPresentations() {}
    @ObjCMethod("pauseAllMediaPlaybackWithCompletionHandler:")
    func pauseAllMediaPlayback(completionHandler: ObjCBlock?) { if let completionHandler { Dispatch.onMain { Blocks.call(completionHandler) } } }
    @ObjCMethod("setAllMediaPlaybackSuspended:completionHandler:")
    func setAllMediaPlaybackSuspended(_ suspended: Bool, completionHandler: ObjCBlock?) {
        if let completionHandler { Dispatch.onMain { Blocks.call(completionHandler) } }
    }
    /// WKMediaPlaybackStateNone.
    @ObjCMethod("requestMediaPlaybackStateWithCompletionHandler:")
    func requestMediaPlaybackState(completionHandler: ObjCBlock?) { if let completionHandler { Dispatch.onMain { Blocks.call(completionHandler, 0) } } }
    @ObjCMethod("pageZoom") func pageZoom() -> CGFloat { 1 }
    @ObjCMethod("setPageZoom:") func setPageZoom(_ zoom: CGFloat) {}

    /// Private settings set by key: drawsBackground, kept.
    @ObjCMethod("setValue:forKey:")
    func setValue(_ value: NSObject?, forKey key: String?) {
        guard let key else { return }
        if key == "drawsBackground" { drawsBackground = Send.bool(value?.objcObject, "boolValue") }
        values[key] = value
    }
    @ObjCMethod("valueForKey:") func value(forKey key: String?) -> NSObject? { key.flatMap { values[$0] } }

    /// The script's value, as WebKit gives it: Foundation's for JSON's,
    /// nil for undefined.
    @ObjCMethod("evaluateJavaScript:completionHandler:")
    func evaluateJavaScript(_ script: String?, completionHandler: ObjCBlock?) {
        guard let page = content.ensurePage() else {
            guard let completionHandler else { return }
            Dispatch.onMain {
                Blocks.call(completionHandler, nil, Calls.error(domain: "WKErrorDomain", code: 1, description: "Web views can't run scripts here"))
            }
            return
        }
        page.evaluate(script ?? "") { result in
            guard let completionHandler else { return }
            switch result {
            case .success(let json):
                Blocks.call(completionHandler, json.flatMap(Calls.object(json:)), nil)
            case .failure(let error):
                // WKErrorJavaScriptExceptionOccurred.
                Blocks.call(completionHandler, nil, Calls.error(domain: "WKErrorDomain", code: 4, description: error.message))
            }
        }
    }

    @ObjCMethod("evaluateJavaScript:inFrame:inContentWorld:completionHandler:")
    func evaluateJavaScript(_ script: String?, frame: NSObject?, world: NSObject?, completionHandler: ObjCBlock?) {
        evaluateJavaScript(script, completionHandler: completionHandler)
    }

    /// The last frame, as an NSImage of the view's size.
    @ObjCMethod("takeSnapshotWithConfiguration:completionHandler:")
    func takeSnapshot(configuration: NSObject?, completionHandler: ObjCBlock?) {
        guard let completionHandler else { return }
        let image = content.frameImage.map { NSImage(cgImage: $0, size: bounds.size) }
        Dispatch.onMain {
            Blocks.call(completionHandler, image?.objcObject,
                        image == nil ? Calls.error(domain: "WKErrorDomain", code: 1, description: "The page has drawn nothing") : nil)
        }
    }

    // MARK: Input

    @ObjCMethod("mouseDown:") override func mouseDown(_ event: NSObject?) { if let event = event?.as(NSEvent.self) { content.mouse(event, button: 1, pressed: true) } }
    @ObjCMethod("mouseUp:") override func mouseUp(_ event: NSObject?) { if let event = event?.as(NSEvent.self) { content.mouse(event, button: 1, pressed: false) } }
    @ObjCMethod("rightMouseDown:") override func rightMouseDown(_ event: NSObject?) { if let event = event?.as(NSEvent.self) { content.mouse(event, button: 2, pressed: true) } }
    @ObjCMethod("rightMouseUp:") override func rightMouseUp(_ event: NSObject?) { if let event = event?.as(NSEvent.self) { content.mouse(event, button: 2, pressed: false) } }
    @ObjCMethod("mouseMoved:") override func mouseMoved(_ event: NSObject?) { if let event = event?.as(NSEvent.self) { content.mouse(event, button: nil, pressed: false) } }
    @ObjCMethod("mouseDragged:") override func mouseDragged(_ event: NSObject?) { if let event = event?.as(NSEvent.self) { content.mouse(event, button: nil, pressed: false) } }
    @ObjCMethod("scrollWheel:") override func scrollWheel(_ event: NSObject?) { if let event = event?.as(NSEvent.self) { content.scroll(event) } }
    @ObjCMethod("keyDown:") override func keyDown(_ event: NSObject?) { if let event = event?.as(NSEvent.self) { content.key(event, pressed: true) } }
    @ObjCMethod("keyUp:") override func keyUp(_ event: NSObject?) { if let event = event?.as(NSEvent.self) { content.key(event, pressed: false) } }

    // MARK: Callbacks from the page

    private static func view(_ object: UnsafeMutableRawPointer) -> WKWebView { WKWebView.objCInstance(object, ownership: .retain) }

    /// A script message, to its handler's -userContentController:didReceiveScriptMessage:.
    static func deliver(_ object: UnsafeMutableRawPointer, _ name: String, _ json: String?) {
        let view = view(object)
        let controller = view.configuration.userContentController
        Trace.log("web view: message to \(name): \(json?.prefix(200) ?? "undefined")")
        guard let handler = controller.handler(named: name) else { return }
        let message = WKScriptMessage()
        message.name = name
        message.body = json.flatMap(Calls.object(json:)).map(NSObject.init)
        message.webViewObject = object
        Send.void(handler.objcObject, "userContentController:didReceiveScriptMessage:", controller.objcObject, message.objcObject)
    }

    static func loadChanged(_ object: UnsafeMutableRawPointer, _ event: Int32) {
        let view = view(object)
        guard let delegate = view.navigationDelegate else { return }
        let navigation = (view.navigation ?? WKNavigation()).objcObject
        switch event {
        case WPE.loadStarted:
            if Send.responds(delegate, "webView:didStartProvisionalNavigation:") {
                Send.void(delegate, "webView:didStartProvisionalNavigation:", object, navigation)
            }
        case WPE.loadCommitted:
            if Send.responds(delegate, "webView:didCommitNavigation:") { Send.void(delegate, "webView:didCommitNavigation:", object, navigation) }
        case WPE.loadFinished:
            // WebKit finishes a failed load too; the delegate heard it fail.
            guard !view.navigationFailed else { return }
            if Send.responds(delegate, "webView:didFinishNavigation:") { Send.void(delegate, "webView:didFinishNavigation:", object, navigation) }
        default:
            break
        }
    }

    static func loadFailed(_ object: UnsafeMutableRawPointer, committed: Bool, domain: String, code: Int, message: String) {
        let view = view(object)
        view.navigationFailed = true
        WPE.log("a load failed: \(domain) \(code): \(message)")
        guard let delegate = view.navigationDelegate else { return }
        let navigation = (view.navigation ?? WKNavigation()).objcObject
        let error = Calls.error(domain: "NSURLErrorDomain", code: code == 0 ? -1 : -code, description: message)
        let selector = committed ? "webView:didFailNavigation:withError:" : "webView:didFailProvisionalNavigation:withError:"
        if Send.responds(delegate, selector) { Calls.void(delegate, selector, object, navigation, error) }
    }
}

// MARK: - The legacy WebView

/// WebUndefined: JavaScript's undefined, as the legacy bridge gives it.
@ObjCClass("WebUndefined")
open class WebUndefined: NSObject {
    nonisolated(unsafe) static var shared: WebUndefined?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCClassMethod("undefined")
    static func undefined() -> WebUndefined {
        if let shared { return shared }
        let made = WebUndefined()
        shared = made
        return made
    }
}

/// A web view's window object. Values set on it are kept, for the app to
/// read back; scripts it evaluates run in the page, and their string,
/// number and Boolean values come back as Foundation's.
@ObjCClass("WebScriptObject")
open class WebScriptObject: NSObject {
    /// Not retained.
    var viewObject: UnsafeMutableRawPointer?
    var values: [String: NSObject] = [:]
    nonisolated(unsafe) static var warned = false

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCClassMethod("throwException:") static func throwException(_ message: String?) -> Bool { false }

    private var page: WebPage? { viewObject.flatMap { WebView.objCInstance($0, ownership: .retain).content.page } }

    @ObjCMethod("setValue:forKey:")
    func setValue(_ value: NSObject?, forKey key: String?) {
        guard let key else { return }
        values[key] = value
        if !WebScriptObject.warned {
            WebScriptObject.warned = true
            WPE.log("the page can't call \(key) and other Objective-C objects a WebView's window script object is given")
        }
    }

    @ObjCMethod("valueForKey:")
    func value(forKey key: String?) -> NSObject? {
        guard let key else { return nil }
        if let value = values[key] { return value }
        return evaluate("window[\(WebScriptObject.quoted(key))]")
    }

    @ObjCMethod("removeWebScriptKey:") func removeWebScriptKey(_ key: String?) { if let key { values[key] = nil } }

    @ObjCMethod("evaluateWebScript:") func evaluateWebScript(_ script: String?) -> NSObject? { evaluate(script ?? "") }

    @ObjCMethod("callWebScriptMethod:withArguments:")
    func callWebScriptMethod(_ name: String?, withArguments arguments: NSObject?) -> NSObject? {
        guard let name else { return WebUndefined.undefined() }
        var json = "[]"
        if let arguments, let data = Calls.object(ObjCRuntime.classObject("NSJSONSerialization"), "dataWithJSONObject:options:error:",
                                                  arguments.objcObject, int: 0, nil),
           let text = Send.object(ObjCRuntime.classObject("NSString"), "alloc").flatMap({ Calls.object($0, "initWithData:encoding:", data, int: 4, nil) }) {
            json = String(objCArgument: text)
            ObjCRuntime.release(text)
        }
        return evaluate("window[\(WebScriptObject.quoted(name))].apply(window, \(json))")
    }

    @ObjCMethod("stringRepresentation") func stringRepresentation() -> String { "[object Window]" }

    private func evaluate(_ script: String) -> NSObject? {
        guard let page else { return WebUndefined.undefined() }
        // JSON's value, through a string, as the page's evaluation gives one.
        guard let json = page.evaluateString("(function(){ var v = (\(script)); return v === undefined ? undefined : JSON.stringify(v); })()"),
              let object = Calls.object(json: json) else { return WebUndefined.undefined() }
        return NSObject(object)
    }

    static func quoted(_ text: String) -> String {
        var quoted = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": quoted += "\\\""
            case "\\": quoted += "\\\\"
            case "\n": quoted += "\\n"
            default: quoted.unicodeScalars.append(scalar)
            }
        }
        return quoted + "\""
    }
}

@ObjCClass("WebFrame")
open class WebFrame: NSObject {
    /// Not retained.
    var viewObject: UnsafeMutableRawPointer?

    @ObjCMethod("init")
    public required override init() { super.init() }

    private var view: WebView? { viewObject.map { WebView.objCInstance($0, ownership: .retain) } }

    @ObjCMethod("webView") func webView() -> WebView? { view }
    @ObjCMethod("name") func name() -> String { "" }
    @ObjCMethod("parentFrame") func parentFrame() -> NSObject? { nil }
    @ObjCMethod("childFrames") func childFrames() -> NSObject { NSMutableArray.of([NSObject]()) }
    @ObjCMethod("loadRequest:") func loadRequest(_ request: NSObject?) { view?.load(request?.objcObject) }
    @ObjCMethod("loadHTMLString:baseURL:") func loadHTMLString(_ html: String?, baseURL: NSObject?) { view?.loadHTML(html, baseURL: baseURL?.objcObject) }
    @ObjCMethod("reload") func reload() { view?.content.page?.reload() }
    @ObjCMethod("stopLoading") func stopLoading() { view?.content.page?.stopLoading() }
    @ObjCMethod("windowObject") func windowObject() -> WebScriptObject? { view?.scriptObject }
    @ObjCMethod("globalContext") func globalContext() -> UnsafeMutableRawPointer? { nil }
    @ObjCMethod("DOMDocument") func domDocument() -> NSObject? { nil }
    @ObjCMethod("dataSource") func dataSource() -> NSObject? { nil }
    @ObjCMethod("provisionalDataSource") func provisionalDataSource() -> NSObject? { nil }
}

@ObjCClass("WebView")
open class WebView: NSView {
    /// Not retained, as WebKit's.
    var frameLoadDelegate: UnsafeMutableRawPointer?
    var policyDelegate: UnsafeMutableRawPointer?
    var uiDelegate: UnsafeMutableRawPointer?
    var resourceLoadDelegate: UnsafeMutableRawPointer?
    var downloadDelegate: UnsafeMutableRawPointer?
    var editingDelegate: UnsafeMutableRawPointer?
    var applicationName: String?
    var drawsBackground = true
    var preferences: NSObject?
    var groupName: String?
    lazy var mainFrame: WebFrame = makeFrame()
    lazy var scriptObject: WebScriptObject = makeScriptObject()
    lazy var content: WebContent = makeContent()

    @ObjCMethod("initWithFrame:frameName:groupName:")
    public required init(frame: CGRect, frameName: String?, groupName: String?) {
        super.init(frame: frame)
        self.groupName = groupName
    }

    @ObjCMethod("initWithFrame:")
    public required init(frame: CGRect) { super.init(frame: frame) }

    @ObjCMethod("init")
    public required init() { super.init() }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) { super.init(coder: coder) }

    private func makeFrame() -> WebFrame {
        let frame = WebFrame()
        frame.viewObject = objcObject
        return frame
    }

    private func makeScriptObject() -> WebScriptObject {
        let object = WebScriptObject()
        object.viewObject = objcObject
        return object
    }

    private func makeContent() -> WebContent {
        let content = WebContent(self)
        let object = objcObject
        content.prepare = { [unowned self, unowned content] page in
            if let name = self.applicationName, content.customUserAgent == nil {
                page.setUserAgent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) \(name)")
            }
        }
        content.loadChanged = { event in WebView.loadChanged(object, event) }
        content.loadFailed = { committed, domain, code, message in
            WebView.loadFailed(object, committed: committed, domain: domain, code: code, message: message)
        }
        return content
    }

    @ObjCMethod("isFlipped") override func isFlipped() -> Bool { true }
    @ObjCMethod("acceptsFirstResponder") override func acceptsFirstResponder() -> Bool { true }
    @ObjCMethod("acceptsFirstMouse:") override func acceptsFirstMouse(_ event: NSObject?) -> Bool { true }

    @ObjCMethod("setFrameSize:")
    override func setFrameSize(_ size: CGSize) {
        super.setFrameSize(size)
        content.resize()
    }

    func load(_ request: UnsafeMutableRawPointer?) {
        if !content.load(request) { WebView.failSoon(objcObject) }
    }

    func loadHTML(_ html: String?, baseURL: UnsafeMutableRawPointer?) {
        if !content.loadHTML(html, baseURL: baseURL) { WebView.failSoon(objcObject) }
    }

    private static func failSoon(_ object: UnsafeMutableRawPointer) {
        Dispatch.onMain {
            WebView.loadFailed(object, committed: false, domain: "NSURLErrorDomain", code: 1009, message: "Web views can't load pages here")
        }
    }

    @ObjCMethod("mainFrame") func webMainFrame() -> WebFrame { mainFrame }
    @ObjCMethod("windowScriptObject") func windowScriptObject() -> WebScriptObject { scriptObject }
    @ObjCMethod("mainFrameURL") func mainFrameURL() -> String? { content.page?.uri }
    @ObjCMethod("setMainFrameURL:") func setMainFrameURL(_ url: String?) { load(Calls.request(Calls.url(url))) }
    @ObjCMethod("mainFrameTitle") func mainFrameTitle() -> String { content.page?.title ?? "" }
    @ObjCMethod("isLoading") func isLoading() -> Bool { content.page?.isLoading ?? false }
    @ObjCMethod("estimatedProgress") func estimatedProgress() -> Double { content.page?.progress ?? 1 }
    @ObjCMethod("reload:") func reload(_ sender: NSObject?) { content.page?.reload() }
    @ObjCMethod("stopLoading:") func stopLoading(_ sender: NSObject?) { content.page?.stopLoading() }
    @ObjCMethod("goBack") func goBack() -> Bool {
        guard let page = content.page, page.canGoBack else { return false }
        page.goBack()
        return true
    }
    @ObjCMethod("goForward") func goForward() -> Bool {
        guard let page = content.page, page.canGoForward else { return false }
        page.goForward()
        return true
    }
    @ObjCMethod("close") func close() { content.page?.stopLoading() }

    @ObjCMethod("stringByEvaluatingJavaScriptFromString:")
    func stringByEvaluatingJavaScript(from script: String?) -> String {
        guard let page = content.ensurePage() else { return "" }
        return page.evaluateString(script ?? "") ?? ""
    }

    @ObjCMethod("frameLoadDelegate") func webFrameLoadDelegate() -> NSObject? { frameLoadDelegate.map(NSObject.init) }
    @ObjCMethod("setFrameLoadDelegate:") func setFrameLoadDelegate(_ delegate: NSObject?) { frameLoadDelegate = delegate?.objcObject }
    @ObjCMethod("policyDelegate") func webPolicyDelegate() -> NSObject? { policyDelegate.map(NSObject.init) }
    @ObjCMethod("setPolicyDelegate:") func setPolicyDelegate(_ delegate: NSObject?) { policyDelegate = delegate?.objcObject }
    @ObjCMethod("UIDelegate") func webUIDelegate() -> NSObject? { uiDelegate.map(NSObject.init) }
    @ObjCMethod("setUIDelegate:") func setUIDelegate(_ delegate: NSObject?) { uiDelegate = delegate?.objcObject }
    @ObjCMethod("resourceLoadDelegate") func webResourceLoadDelegate() -> NSObject? { resourceLoadDelegate.map(NSObject.init) }
    @ObjCMethod("setResourceLoadDelegate:") func setResourceLoadDelegate(_ delegate: NSObject?) { resourceLoadDelegate = delegate?.objcObject }
    @ObjCMethod("downloadDelegate") func webDownloadDelegate() -> NSObject? { downloadDelegate.map(NSObject.init) }
    @ObjCMethod("setDownloadDelegate:") func setDownloadDelegate(_ delegate: NSObject?) { downloadDelegate = delegate?.objcObject }
    @ObjCMethod("editingDelegate") func webEditingDelegate() -> NSObject? { editingDelegate.map(NSObject.init) }
    @ObjCMethod("setEditingDelegate:") func setEditingDelegate(_ delegate: NSObject?) { editingDelegate = delegate?.objcObject }

    @ObjCMethod("applicationNameForUserAgent") func applicationNameForUserAgent() -> String? { applicationName }
    @ObjCMethod("setApplicationNameForUserAgent:") func setApplicationNameForUserAgent(_ name: String?) { applicationName = name }
    @ObjCMethod("customUserAgent") func webCustomUserAgent() -> String? { content.customUserAgent }
    @ObjCMethod("setCustomUserAgent:")
    func setCustomUserAgent(_ agent: String?) {
        content.customUserAgent = agent
        content.page?.setUserAgent(agent)
    }
    @ObjCMethod("drawsBackground") func webDrawsBackground() -> Bool { drawsBackground }
    @ObjCMethod("setDrawsBackground:") func setDrawsBackground(_ draws: Bool) { drawsBackground = draws }
    @ObjCMethod("preferences") func webPreferences() -> NSObject? { preferences }
    @ObjCMethod("setPreferences:") func setPreferences(_ preferences: NSObject?) { self.preferences = preferences }
    @ObjCMethod("groupName") func webGroupName() -> String? { groupName }
    @ObjCMethod("setGroupName:") func setGroupName(_ name: String?) { groupName = name }
    @ObjCMethod("setMaintainsBackForwardList:") func setMaintainsBackForwardList(_ value: Bool) {}
    @ObjCMethod("setShouldCloseWithWindow:") func setShouldCloseWithWindow(_ value: Bool) {}
    @ObjCMethod("setShouldUpdateWhileOffscreen:") func setShouldUpdateWhileOffscreen(_ value: Bool) {}
    @ObjCMethod("setEditable:") func setEditable(_ value: Bool) {}
    @ObjCMethod("isEditable") func isEditable() -> Bool { false }
    @ObjCMethod("setMediaStyle:") func setMediaStyle(_ style: String?) {}
    @ObjCMethod("setHostWindow:") func setHostWindow(_ window: NSObject?) {}

    /// Private settings set by key, kept.
    @ObjCMethod("setValue:forKey:")
    func setValue(_ value: NSObject?, forKey key: String?) {
        if key == "drawsBackground" { drawsBackground = Send.bool(value?.objcObject, "boolValue") }
    }

    // MARK: Input

    @ObjCMethod("mouseDown:") override func mouseDown(_ event: NSObject?) { if let event = event?.as(NSEvent.self) { content.mouse(event, button: 1, pressed: true) } }
    @ObjCMethod("mouseUp:") override func mouseUp(_ event: NSObject?) { if let event = event?.as(NSEvent.self) { content.mouse(event, button: 1, pressed: false) } }
    @ObjCMethod("rightMouseDown:") override func rightMouseDown(_ event: NSObject?) { if let event = event?.as(NSEvent.self) { content.mouse(event, button: 2, pressed: true) } }
    @ObjCMethod("rightMouseUp:") override func rightMouseUp(_ event: NSObject?) { if let event = event?.as(NSEvent.self) { content.mouse(event, button: 2, pressed: false) } }
    @ObjCMethod("mouseMoved:") override func mouseMoved(_ event: NSObject?) { if let event = event?.as(NSEvent.self) { content.mouse(event, button: nil, pressed: false) } }
    @ObjCMethod("mouseDragged:") override func mouseDragged(_ event: NSObject?) { if let event = event?.as(NSEvent.self) { content.mouse(event, button: nil, pressed: false) } }
    @ObjCMethod("scrollWheel:") override func scrollWheel(_ event: NSObject?) { if let event = event?.as(NSEvent.self) { content.scroll(event) } }
    @ObjCMethod("keyDown:") override func keyDown(_ event: NSObject?) { if let event = event?.as(NSEvent.self) { content.key(event, pressed: true) } }
    @ObjCMethod("keyUp:") override func keyUp(_ event: NSObject?) { if let event = event?.as(NSEvent.self) { content.key(event, pressed: false) } }

    // MARK: Callbacks from the page: WebFrameLoadDelegate's

    static func loadChanged(_ object: UnsafeMutableRawPointer, _ event: Int32) {
        let view = WebView.objCInstance(object, ownership: .retain)
        guard let delegate = view.frameLoadDelegate else { return }
        let frame = view.mainFrame.objcObject
        func tell(_ selector: String) { if Send.responds(delegate, selector) { Send.void(delegate, selector, object, frame) } }
        switch event {
        case WPE.loadStarted:
            tell("webView:didStartProvisionalLoadForFrame:")
        case WPE.loadCommitted:
            tell("webView:didCommitLoadForFrame:")
            // The window object is new with each page.
            if Send.responds(delegate, "webView:didClearWindowObject:forFrame:") {
                Calls.void(delegate, "webView:didClearWindowObject:forFrame:", object, view.scriptObject.objcObject, frame)
            }
        case WPE.loadFinished:
            if let title = view.content.page?.title, Send.responds(delegate, "webView:didReceiveTitle:forFrame:") {
                Calls.void(delegate, "webView:didReceiveTitle:forFrame:", object, title.objCArgument(), frame)
            }
            tell("webView:didFinishLoadForFrame:")
        default:
            break
        }
    }

    static func loadFailed(_ object: UnsafeMutableRawPointer, committed: Bool, domain: String, code: Int, message: String) {
        let view = WebView.objCInstance(object, ownership: .retain)
        WPE.log("a load failed: \(domain) \(code): \(message)")
        guard let delegate = view.frameLoadDelegate else { return }
        let error = Calls.error(domain: "NSURLErrorDomain", code: code == 0 ? -1 : -abs(code), description: message)
        let selector = committed ? "webView:didFailLoadWithError:forFrame:" : "webView:didFailProvisionalLoadWithError:forFrame:"
        if Send.responds(delegate, selector) { Calls.void(delegate, selector, object, error, view.mainFrame.objcObject) }
    }
}

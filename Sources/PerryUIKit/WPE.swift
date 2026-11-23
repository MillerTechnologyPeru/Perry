import CacaoRender
import Foundation
import Glibc
import WPEWebKit

// WPE WebKit, WebKit's port for embedding, through the engine Cacao's web
// views share (PureSwift/WebKit's WPEWebKit), loaded when a web view first
// needs it. Each web view has a page of its own, which draws into frames of
// the view's size in shared memory; the view shows each as its layer's
// contents. The pages run in WPE's web and network processes, which are
// Linux programs; their replies come through GLib's main context, which
// runs on the main queue while there are pages. Without WPE web views load
// nothing.

/// WPE WebKit as Perry's web views use it: whether it's there, and the load
/// events they tell apart (WebKitLoadEvent's).
enum WPE {
    static var isAvailable: Bool { WPEEngine.isAvailable }

    static let loadStarted = WPELoadEvent.started.rawValue
    static let loadCommitted = WPELoadEvent.committed.rawValue
    static let loadFinished = WPELoadEvent.finished.rawValue

    static func log(_ message: String) {
        let line = "perry: WebKit: \(message)\n"
        line.withCString { _ = write(2, $0, strlen($0)) }
    }
}

/// One web view's page: a WPE page drawing into frames of the view's size,
/// which `frame` shows. Used on the main queue only, where GLib's context
/// runs and frames are published.
final class WebPage: @unchecked Sendable {
    let content: WPEWebContent
    /// Hears the page's state for this page, which it doesn't keep.
    private let reporter: Reporter
    private(set) var size: (width: UInt32, height: UInt32)
    private(set) var scale: Float

    /// A frame: BGRA pixels, premultiplied, top row first, with the width,
    /// height and bytes per row. They are good only during the call.
    var frame: ((UnsafeRawPointer, Int, Int, Int) -> Void)?
    /// WebKitLoadEvent: started, redirected, committed, finished.
    var loadChanged: ((Int32) -> Void)?
    /// A load failed: whether it had committed, then GError's domain, code
    /// and message.
    var loadFailed: ((Bool, String, Int, String) -> Void)?
    /// A property of the page's changed, by WebKit's name: title, uri,
    /// is-loading, estimated-load-progress.
    var propertyChanged: ((String) -> Void)?
    /// Whether a navigation to a URI goes ahead, with its
    /// WebKitNavigationType (UIWebViewNavigationType's values); nil lets
    /// every navigation go ahead. The view's own loads are asked about too,
    /// as UIWebView's delegate is about loadRequest:.
    var decideNavigation: ((String, Int32) -> Bool)?
    /// A script message: the handler's name and the message's body as JSON
    /// (nil for undefined).
    var scriptMessage: ((String, String?) -> Void)?

    /// What the page last said of itself.
    private(set) var title: String?
    private(set) var uri: String?
    private(set) var isLoading = false
    private(set) var progress: Double = 0
    private(set) var canGoBack = false
    private(set) var canGoForward = false

    nonisolated(unsafe) private static var scheduled = false

    init?(width: UInt32, height: UInt32, scale: Float) {
        let reporter = Reporter()
        guard let content = WPEWebContent(delegate: reporter) else { return nil }
        self.content = content
        self.reporter = reporter
        let size = (max(width, 1), max(height, 1))
        (self.size, self.scale) = (size, scale)
        reporter.page = self
        content.asksAboutOwnLoads = true
        content.attach(width: size.0, height: size.1, scale: scale)
        content.focus(true)
        content.onLoadEvent = { [unowned self] event in loadChanged?(event.rawValue) }
        content.onLoadError = { [unowned self] error, committed in
            loadFailed?(committed, error.domain, error.code, error.message)
        }
        content.onNavigation = { [unowned self] navigation, decision in
            // A new window has nowhere to go, as before: it goes ahead, to nothing.
            guard !navigation.opensNewWindow, let decideNavigation else { return decision.allow() }
            if decideNavigation(navigation.uri, navigation.kind.rawValue) { decision.allow() } else { decision.cancel() }
        }
        content.onScriptMessage = { [unowned self] name, json in scriptMessage?(name, json) }
        content.surface.onPublish = { [weak self] in
            // On the main queue, where GLib's context runs.
            self?.showNewFrame()
        }
        if getenv("PERRY_UIKIT_WEB_CONSOLE") != nil {
            WPE.log("PERRY_UIKIT_WEB_CONSOLE: the shared engine doesn't write a page's console")
        }
        WebPage.schedule()
    }

    /// The newest frame, to `frame`.
    private func showNewFrame() {
        guard let frame, let latest = content.surface.takeFrame(), latest.width > 0, latest.height > 0 else { return }
        latest.pixels.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            frame(base, latest.width, latest.height, latest.bytesPerRow)
        }
    }

    /// Makes window.webkit.messageHandlers[name] post to `scriptMessage`.
    func addMessageHandler(_ name: String) { content.addScriptMessageHandler(name) }

    /// A script the page runs on each load, at its start or end.
    func addUserScript(_ source: String, atStart: Bool, mainFrameOnly: Bool) {
        content.addUserScript(source, atDocumentStart: atStart, mainFrameOnly: mainFrameOnly)
    }

    func loadHTML(_ html: String, baseURI: String?) { content.loadHTML(html, baseURL: baseURI) }
    func loadURI(_ uri: String) { content.load(uri) }
    func goBack() { content.goBack() }
    func goForward() { content.goForward() }
    func reload() { content.reload() }
    func stopLoading() { content.stopLoading() }

    // MARK: Input

    /// With PERRY_UIKIT_WEB_TRACE set, input sent to pages is written to
    /// standard error.
    nonisolated(unsafe) static let tracing = getenv("PERRY_UIKIT_WEB_TRACE") != nil

    static func trace(_ message: @autoclosure () -> String) {
        guard tracing else { return }
        let line = "perry: UIKit: web: \(message())\n"
        line.withCString { _ = write(2, $0, strlen($0)) }
    }

    /// A click of the primary button at a point in the page's pixels: the
    /// pointer moves there, presses and releases.
    func click(x: Int32, y: Int32) {
        WebPage.trace("click at \(x), \(y) of \(size.width)x\(size.height) at scale \(scale)")
        let (x, y) = (Double(x), Double(y))
        content.pointerMoved(x: x, y: y)
        content.pointerButton(pressed: true, x: x, y: y, modifiers: .button1)
        content.pointerButton(pressed: false, x: x, y: y)
    }

    /// Scrolls what is under a point by a distance in pixels, as a
    /// touchpad's smooth scrolling does, passed to WPE as it is (the engine
    /// takes points toward the page's end, and turns them to pixels toward
    /// its start).
    func scroll(x: Int32, y: Int32, dx: Double, dy: Double) {
        let scale = Double(content.size?.scale ?? self.scale)
        content.scroll(x: Double(x), y: Double(y), dx: -dx / scale, dy: -dy / scale)
    }

    /// Presses and releases a key, by its XKB keysym.
    func press(keysym: UInt32) {
        content.key(keysym: keysym, pressed: true)
        content.key(keysym: keysym, pressed: false)
    }

    /// Types text, a key for each character; newlines press Return.
    func type(_ text: String) {
        WebPage.trace("type \(text.count) characters")
        content.type(text)
    }

    /// XKB's keysyms for Return and BackSpace.
    static let returnKey = WPEKeysym.return
    static let backspaceKey = WPEKeysym.backspace

    func setUserAgent(_ agent: String?) { content.setUserAgent(agent) }

    /// The view's size in points and its scale, which the next frames have.
    func resize(width: UInt32, height: UInt32, scale: Float) {
        let size = (max(width, 1), max(height, 1))
        guard size != self.size || scale != self.scale else { return }
        (self.size, self.scale) = (size, scale)
        content.attach(width: size.0, height: size.1, scale: scale)
        WebPage.trace("resized to \(size.0)x\(size.1) at scale \(scale)")
    }

    // MARK: Scripts

    struct EvaluationError: Error {
        let domain: String, code: Int, message: String
    }

    /// Runs `script` in the page; `completion` hears its value as JSON (nil
    /// for undefined) or a GError's domain, code and message.
    func evaluate(_ script: String, completion: @escaping (Result<String?, EvaluationError>) -> Void) {
        content.evaluateJavaScript(script) { completion(WebPage.result($0)) }
    }

    /// Runs `body` as an async function's body, awaiting what it returns;
    /// `completion` hears its value as `evaluate`'s does.
    func callAsync(_ body: String, completion: @escaping (Result<String?, EvaluationError>) -> Void) {
        content.callAsyncJavaScript(body) { completion(WebPage.result($0)) }
    }

    private static func result(_ result: Result<String?, WPEError>) -> Result<String?, EvaluationError> {
        result.mapError { EvaluationError(domain: $0.domain, code: $0.code, message: $0.message) }
    }

    /// Calls `body` once the page has drawn what it has now: after two of
    /// its animation frames, and a frame's time for that frame to arrive.
    func afterRendering(_ body: @escaping () -> Void) {
        callAsync("await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)))") { _ in
            guard let after = Display.dispatchAfter, let time = Display.dispatchTime else { return body() }
            let box = Unmanaged.passRetained(Rendering(body)).toOpaque()
            after(time(0, 50_000_000), Updates.mainQueue, box) { data in
                guard let data else { return }
                Unmanaged<Rendering>.fromOpaque(data).takeRetainedValue().body()
            }
        }
    }

    private final class Rendering {
        let body: () -> Void
        init(_ body: @escaping () -> Void) { self.body = body }
    }

    /// Runs `script` in the page and waits for it, running GLib's context
    /// meanwhile: a string, number or Boolean value as a string, as
    /// JavaScript's String() makes it; nil for other values and exceptions.
    func evaluateString(_ script: String) -> String? {
        var outcome: Result<String?, WPEError>?
        // The value's type comes with it, as UIWebView's scripts give only
        // strings, numbers and Booleans. Evaluated indirectly, the script's
        // declarations are the page's globals, as they were.
        let wrapped = "(() => { const v = (0, eval)(\(WebPage.quoted(script))); "
            + "return (typeof v === 'string' || typeof v === 'number' || typeof v === 'boolean') ? [String(v)] : [] })()"
        content.evaluateJavaScript(wrapped) { outcome = $0 }
        WPEEngine.dispatch(for: 60) { outcome != nil }
        guard case .success(let json)? = outcome, let json,
              let array = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String] else { return nil }
        return array.first
    }

    /// A string as a JavaScript string literal.
    private static func quoted(_ string: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [string]), let array = String(data: data, encoding: .utf8) else {
            return "''"
        }
        return String(array.dropFirst().dropLast())
    }

    // MARK: The loop

    /// Runs GLib's context on the main queue, a frame's time apart, while
    /// there are pages.
    private static func schedule() {
        guard !scheduled, let after = Display.dispatchAfter, let time = Display.dispatchTime else { return }
        scheduled = true
        after(time(0, 8_000_000), Updates.mainQueue, nil) { _ in
            WebPage.scheduled = false
            WPEEngine.dispatch()
            WebPage.tick?()
            if WPEEngine.pageCount > 0 { WebPage.schedule() }
        }
    }

    /// Run after each pass of GLib's context: web views follow their sizes.
    nonisolated(unsafe) static var tick: (() -> Void)?

    // MARK: The page's state

    /// The page's reports, kept on its page and passed on by WebKit's
    /// property names.
    private final class Reporter: WPEWebContentDelegate {
        weak var page: WebPage?

        func shouldNavigate(_ content: WPEWebContent, url: String, kind: Int32, isMainFrame: Bool) -> Bool {
            // onNavigation answers instead.
            true
        }

        func didChangeURL(_ content: WPEWebContent, url: String?) {
            page?.uri = url
            page?.propertyChanged?("uri")
        }

        func didChangeTitle(_ content: WPEWebContent, title: String) {
            page?.title = title
            page?.propertyChanged?("title")
        }

        func didChangeLoading(_ content: WPEWebContent, isLoading: Bool, progress: Double) {
            guard let page else { return }
            let changed = page.isLoading != isLoading
            (page.isLoading, page.progress) = (isLoading, progress)
            page.propertyChanged?("estimated-load-progress")
            if changed { page.propertyChanged?("is-loading") }
        }

        func didChangeHistory(_ content: WPEWebContent, canGoBack: Bool, canGoForward: Bool) {
            guard let page else { return }
            (page.canGoBack, page.canGoForward) = (canGoBack, canGoForward)
        }

        func didFinishNavigation(_ content: WPEWebContent) {}
        func didFailNavigation(_ content: WPEWebContent, error: Int32, message: String) {}
        func didEvaluateJavaScript(_ content: WPEWebContent, request: Int32, result: String?, error: String?) {}
    }
}

public import Foundation
public import Observation

// WebKit's WebPage: a page an app loads and reads, shown by SwiftUI's
// WebView. Here it is a WKWebView of the page's own, which Perry's UIKit
// runs on WPE WebKit: the page's properties are the view's, observed
// through key-value observing, its loads are the view's navigations, as
// sequences of their events, and its scripts run through
// callAsyncJavaScript. Declarations follow the SDK's interface, whose
// symbols apps bind.

@available(iOS 26.0, *)
@_Concurrency.MainActor final public class WebPage {
    /// The view showing the page, which SwiftUI's WebView hosts.
    @_spi(Perry) public let webView: WKWebView

    private let registrar = ObservationRegistrar()
    private var navigationDelegate: NavigationDelegate!
    private var propertyObserver: PropertyObserver!
    /// Each load's events, by its navigation, and every navigation's.
    private var loads: [ObjectIdentifier: AsyncThrowingStream<NavigationEvent, any Error>.Continuation] = [:]
    private var watchers: [UUID: AsyncThrowingStream<NavigationEvent, any Error>.Continuation] = [:]

    init(_configuration configuration: Configuration) {
        let made = WKWebViewConfiguration()
        made.websiteDataStore = configuration.websiteDataStore
        made.userContentController = configuration.userContentController
        made.applicationNameForUserAgent = configuration.applicationNameForUserAgent
        made.suppressesIncrementalRendering = configuration.suppressesIncrementalRendering
        made.allowsAirPlayForMediaPlayback = configuration.allowsAirPlayForMediaPlayback
        made.ignoresViewportScaleLimits = configuration.ignoresViewportScaleLimits
        webView = WKWebView(frame: .zero, configuration: made)
        navigationDelegate = NavigationDelegate(page: self)
        webView.navigationDelegate = navigationDelegate
        propertyObserver = PropertyObserver(page: self, webView: webView)
    }

    @_Concurrency.MainActor convenience public init(configuration: WebPage.Configuration = Configuration()) {
        self.init(_configuration: configuration)
    }

    isolated deinit {
        propertyObserver.stop()
        for continuation in loads.values { continuation.finish(throwing: NavigationError.pageClosed) }
        for continuation in watchers.values { continuation.finish() }
    }

    // MARK: Properties

    /// Every navigation's events from now on.
    @_Concurrency.MainActor final public var navigations: some _Concurrency.AsyncSequence<WebPage.NavigationEvent, any Swift.Error> {
        let id = UUID()
        return AsyncThrowingStream<NavigationEvent, any Error> { continuation in
            watchers[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.watchers[id] = nil }
            }
        }
    }

    @_Concurrency.MainActor final public var url: Foundation.URL? {
        registrar.access(self, keyPath: \.url)
        return webView.url
    }

    @_Concurrency.MainActor final public var title: Swift.String {
        registrar.access(self, keyPath: \.title)
        return webView.title ?? ""
    }

    @_Concurrency.MainActor final public var estimatedProgress: Swift.Double {
        registrar.access(self, keyPath: \.estimatedProgress)
        return webView.estimatedProgress
    }

    @_Concurrency.MainActor final public var isLoading: Swift.Bool {
        registrar.access(self, keyPath: \.isLoading)
        return webView.isLoading
    }

    @_Concurrency.MainActor final public var customUserAgent: Swift.String? {
        get {
            registrar.access(self, keyPath: \.customUserAgent)
            return webView.customUserAgent
        }
        set {
            registrar.withMutation(of: self, keyPath: \.customUserAgent) { webView.customUserAgent = newValue }
        }
    }

    @_Concurrency.MainActor final public var isInspectable: Swift.Bool {
        get {
            registrar.access(self, keyPath: \.isInspectable)
            return webView.isInspectable
        }
        set {
            registrar.withMutation(of: self, keyPath: \.isInspectable) { webView.isInspectable = newValue }
        }
    }

    // MARK: Loading

    @discardableResult
    @_Concurrency.MainActor final public func load(_ url: Foundation.URL?)
        -> some _Concurrency.AsyncSequence<WebPage.NavigationEvent, any Swift.Error> {
        guard let url else { return failed(NavigationError.invalidURL) }
        return track(webView.load(URLRequest(url: url)))
    }

    @discardableResult
    @_Concurrency.MainActor final public func load(_ request: Foundation.URLRequest)
        -> some _Concurrency.AsyncSequence<WebPage.NavigationEvent, any Swift.Error> {
        track(webView.load(request))
    }

    @discardableResult
    @_Concurrency.MainActor final public func load(html: Swift.String, baseURL: Foundation.URL = Foundation.URL(string: "about:blank")!)
        -> some _Concurrency.AsyncSequence<WebPage.NavigationEvent, any Swift.Error> {
        track(webView.loadHTMLString(html, baseURL: baseURL))
    }

    @discardableResult
    @_Concurrency.MainActor final public func reload(fromOrigin: Swift.Bool = false)
        -> some _Concurrency.AsyncSequence<WebPage.NavigationEvent, any Swift.Error> {
        track(webView.reload())
    }

    @_Concurrency.MainActor final public func stopLoading() { webView.stopLoading() }

    /// A load's events, until it finishes or fails.
    private func track(_ navigation: WKNavigation?) -> AsyncThrowingStream<NavigationEvent, any Error> {
        guard let navigation else { return failed(NavigationError.invalidURL) }
        let key = ObjectIdentifier(navigation)
        return AsyncThrowingStream { continuation in loads[key] = continuation }
    }

    private func failed(_ error: any Error) -> AsyncThrowingStream<NavigationEvent, any Error> {
        AsyncThrowingStream { $0.finish(throwing: error) }
    }

    /// A navigation's event, to its load's sequence and every watcher's.
    fileprivate func navigation(_ navigation: WKNavigation?, _ event: NavigationEvent) {
        if let navigation { loads[ObjectIdentifier(navigation)]?.yield(event) }
        for continuation in watchers.values { continuation.yield(event) }
        if event == .finished, let navigation { loads.removeValue(forKey: ObjectIdentifier(navigation))?.finish() }
    }

    fileprivate func navigation(_ navigation: WKNavigation?, failed error: any Error) {
        if let navigation { loads.removeValue(forKey: ObjectIdentifier(navigation))?.finish(throwing: error) }
    }

    /// The view's property changed: observers of the page's hear it.
    fileprivate func changed(_ key: String) {
        switch key {
        case "title": registrar.withMutation(of: self, keyPath: \.title) {}
        case "URL": registrar.withMutation(of: self, keyPath: \.url) {}
        case "loading": registrar.withMutation(of: self, keyPath: \.isLoading) {}
        case "estimatedProgress": registrar.withMutation(of: self, keyPath: \.estimatedProgress) {}
        default: break
        }
    }

    // MARK: Scripts

    /// `functionBody` as an async function's body, with `arguments` as its
    /// variables; what it returns, awaited, as Foundation's objects.
    @discardableResult
    @_Concurrency.MainActor final public func callJavaScript(_ functionBody: Swift.String, arguments: [Swift.String: Any] = [:],
                                                             in frame: WebPage.FrameInfo? = nil,
                                                             contentWorld: WKContentWorld? = nil) async throws -> sending Any? {
        let objects = arguments.mapValues(Self.object)
        let result: Result<UncheckedValue, any Error> = await withCheckedContinuation { continuation in
            webView.__callAsyncJavaScript(functionBody, arguments: objects, inFrame: nil, in: contentWorld ?? .page) { value, error in
                if let error { continuation.resume(returning: .failure(error)) } else {
                    continuation.resume(returning: .success(UncheckedValue(value: value)))
                }
            }
        }
        return Self.value(try result.get().value)
    }

    private struct UncheckedValue: @unchecked Sendable { let value: Any? }

    /// A Swift value as the Foundation object the script receives:
    /// numbers, Booleans, strings, arrays and dictionaries, made here rather
    /// than by the runtime's bridging.
    private static func object(_ value: Any) -> Any {
        switch value {
        case let value as NSObject: return value
        case let value as Bool: return NSNumber(value: value)
        case let value as Int: return NSNumber(value: value)
        case let value as Double: return NSNumber(value: value)
        case let value as Float: return NSNumber(value: value)
        case let value as String: return NSString(string: value)
        case let value as [Any]:
            let array = NSMutableArray()
            for element in value { array.add(object(element)) }
            return array
        case let value as [String: Any]:
            let dictionary = NSMutableDictionary()
            for (key, element) in value { dictionary.setObject(object(element), forKey: NSString(string: key)) }
            return dictionary
        default: return NSString(string: "\(value)")
        }
    }

    /// The script's value as Swift's: Booleans, integers and other numbers,
    /// strings, arrays and dictionaries of them; NSNull stays.
    private static func value(_ object: Any?) -> Any? {
        guard let object else { return nil }
        if let number = object as? NSNumber {
            switch String(cString: number.objCType) {
            case "c", "B": return number.boolValue
            case "d", "f":
                let double = number.doubleValue
                return double.rounded() == double && abs(double) < 9.0e15 ? Int(double) as Any : double as Any
            default: return number.intValue
            }
        }
        if let string = object as? NSString { return String(string) }
        if let array = object as? NSArray { return (0..<array.count).map { value(array.object(at: $0)) as Any } }
        if let dictionary = object as? NSDictionary {
            var values: [String: Any] = [:]
            for key in dictionary.allKeys {
                if let key = key as? NSString { values[String(key)] = value(dictionary.object(forKey: key)) as Any }
            }
            return values
        }
        return object
    }
}

@available(iOS 26.0, *)
extension WebPage: nonisolated Observation.Observable {}

// MARK: - Configuration and events

@available(iOS 26.0, *)
extension WebPage {
    @_Concurrency.MainActor public struct Configuration {
        @_Concurrency.MainActor public init() {}
        @_Concurrency.MainActor public var websiteDataStore: WKWebsiteDataStore = .default()
        @_Concurrency.MainActor public var userContentController = WKUserContentController()
        @_Concurrency.MainActor public var applicationNameForUserAgent: Swift.String?
        @_Concurrency.MainActor public var limitsNavigationsToAppBoundDomains = false
        @_Concurrency.MainActor public var upgradeKnownHostsToHTTPS = false
        @_Concurrency.MainActor public var suppressesIncrementalRendering = false
        @_Concurrency.MainActor public var allowsAirPlayForMediaPlayback = true
        @_Concurrency.MainActor public var loadsSubresources = true
        @_Concurrency.MainActor public var allowsInlinePredictions = false
        @_Concurrency.MainActor public var supportsAdaptiveImageGlyph = false
        @_Concurrency.MainActor public var ignoresViewportScaleLimits = false
    }

    public enum NavigationEvent: Swift.Hashable, Swift.Sendable {
        case startedProvisionalNavigation
        case receivedServerRedirect
        case committed
        case finished
    }

    public enum NavigationError: Swift.Error {
        case failedProvisionalNavigation(any Swift.Error)
        case pageClosed
        case webContentProcessTerminated
        case invalidURL
    }

    /// A frame of the page's: here, always its main frame.
    @_Concurrency.MainActor public struct FrameInfo {
        @_Concurrency.MainActor public var isMainFrame: Swift.Bool { true }
    }
}

// MARK: - The view's delegate and observer

@available(iOS 26.0, *)
@_Concurrency.MainActor
private final class NavigationDelegate: NSObject, WKNavigationDelegate {
    weak var page: WebPage?

    init(page: WebPage) { self.page = page }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        page?.navigation(navigation, .startedProvisionalNavigation)
    }

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        page?.navigation(navigation, .receivedServerRedirect)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        page?.navigation(navigation, .committed)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        page?.navigation(navigation, .finished)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        page?.navigation(navigation, failed: WebPage.NavigationError.failedProvisionalNavigation(error))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        page?.navigation(navigation, failed: error)
    }
}

/// The view's properties' changes, by key-value observing.
@available(iOS 26.0, *)
private final class PropertyObserver: NSObject {
    static let keys = ["title", "URL", "loading", "estimatedProgress"]
    weak var page: WebPage?
    let webView: WKWebView
    var observing = true

    @_Concurrency.MainActor init(page: WebPage, webView: WKWebView) {
        (self.page, self.webView) = (page, webView)
        super.init()
        for key in PropertyObserver.keys { webView.addObserver(self, forKeyPath: key, options: [], context: nil) }
    }

    @_Concurrency.MainActor func stop() {
        guard observing else { return }
        observing = false
        for key in PropertyObserver.keys { webView.removeObserver(self, forKeyPath: key) }
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?,
                               context: UnsafeMutableRawPointer?) {
        guard let keyPath else { return }
        MainActor.assumeIsolated { page?.changed(keyPath) }
    }
}

public import SwiftUI
@_exported public import WebKit
@_spi(Perry) import WebKit

// _WebKit_SwiftUI's WebView: SwiftUI's view of a WebPage, which hosts the
// page's WKWebView. A view made with a URL keeps a page of its own and loads
// the URL into it. Declarations follow the SDK's interface, whose symbols
// apps bind.

@available(iOS 26.0, *)
@_Concurrency.MainActor @preconcurrency public struct WebView: SwiftUI.View {
    private let page: WebPage?
    private let url: Foundation.URL?

    @_Concurrency.MainActor @preconcurrency public init(_ page: WebPage) {
        (self.page, self.url) = (page, nil)
    }

    @_Concurrency.MainActor @preconcurrency public init(url: Foundation.URL?) {
        (self.page, self.url) = (nil, url)
    }

    @_Concurrency.MainActor @preconcurrency public var body: some SwiftUI.View {
        PageView(page: page, url: url)
    }
}

@available(iOS 26.0, *)
extension WebView: Swift.Sendable {}

/// The page's view in SwiftUI's hierarchy.
@available(iOS 26.0, *)
private struct PageView: UIViewRepresentable {
    let page: WebPage?
    let url: URL?

    /// The page shown: the one given, or one of the view's own.
    final class Coordinator {
        let page: WebPage
        var loaded: URL?
        init(page: WebPage) { self.page = page }
    }

    func makeCoordinator() -> Coordinator { Coordinator(page: page ?? WebPage()) }

    func makeUIView(context: Context) -> WKWebView {
        load(context.coordinator)
        return context.coordinator.page.webView
    }

    func updateUIView(_ view: WKWebView, context: Context) { load(context.coordinator) }

    /// A view of its own page loads its URL, when it changes.
    private func load(_ coordinator: Coordinator) {
        guard page == nil, let url, url != coordinator.loaded else { return }
        coordinator.loaded = url
        coordinator.page.load(url)
    }
}

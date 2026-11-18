// SwiftUI's AuthenticationServices API: the web authentication session a
// view takes from its environment to sign in through a web page. Perry
// has no browser sheet to show the page in, so a session's sign-in ends
// at once as cancelled by the user, which apps handle as a sign-in the
// user chose not to finish.

public import Foundation
public import OpenSwiftUI
public import AuthenticationServices

/// Signs in through a web page shown in a browser session.
@available(iOS 16.4, *)
@MainActor
public struct WebAuthenticationSession {
    /// The browser session a sign-in page is shown in: one that shares
    /// cookies with the browser, or an ephemeral one that keeps none.
    public struct BrowserSession: Sendable {
        let ephemeralSession: Bool

        public static var ephemeral: WebAuthenticationSession.BrowserSession { BrowserSession(ephemeralSession: true) }
        public static var shared: WebAuthenticationSession.BrowserSession { BrowserSession(ephemeralSession: false) }
    }

    nonisolated init() {}

    /// The sign-in, cancelled: no page can be shown.
    @MainActor
    public func authenticate(using url: URL, callbackURLScheme: String,
                             preferredBrowserSession: WebAuthenticationSession.BrowserSession? = nil) async throws -> URL {
        throw URLError(.cancelled)
    }

    /// The sign-in, cancelled: no page can be shown.
    @available(iOS 17.4, *)
    @MainActor
    public func authenticate(using url: URL, callback: ASWebAuthenticationSession.Callback,
                             preferredBrowserSession: WebAuthenticationSession.BrowserSession? = nil,
                             additionalHeaderFields: [String: String]) async throws -> URL {
        throw URLError(.cancelled)
    }
}

@available(iOS 16.4, *)
extension WebAuthenticationSession: Sendable {}

@available(iOS 16.4, *)
extension EnvironmentValues {
    /// The session views sign in through web pages with.
    public var webAuthenticationSession: WebAuthenticationSession { WebAuthenticationSession() }
}

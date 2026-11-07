import PerryObjCInterop

// AuthenticationServices' web authentication session: OAuth and other web
// sign-ins, which on iOS run in a Safari sheet. Here the sheet is a
// navigation controller presented from the window the presentation context
// provider names (else the key window), its page a WKWebView (WPE) loading
// the session's URL, and a Cancel button on its bar. A navigation to the
// callback (the URL scheme given, or the callback object's match) ends the
// session: the sheet closes and the completion handler gets that URL.
// Cancel closes it with ASWebAuthenticationSessionErrorCodeCanceledLogin.
// Without WPE, the session cannot start. Pages share the web views' data
// store, so an ephemeral session's cookies are not kept apart.

/// The session's errors.
@ObjCConstants
enum AuthenticationServicesConstants {
    static let ASWebAuthenticationSessionErrorDomain = "com.apple.AuthenticationServices.WebAuthenticationSession"
}

final class WebAuthenticationState: ObjectState {
    var url: NSObject?
    var callbackScheme: String?
    /// An ASWebAuthenticationSessionCallback, which matches callback URLs.
    var callback: NSObject?
    var completion: ObjCBlock?
    /// Not retained, as Darwin's is weak.
    var provider: UnsafeMutableRawPointer?
    var ephemeral = false
    var headers: NSObject?
    var started = false
    var finished = false
    /// The sheet, while it shows.
    var sheet: UIViewController?
}

@ObjCClass("ASWebAuthenticationSession")
open class ASWebAuthenticationSession: NSObject {
    static let states = StateTable<WebAuthenticationState>()
    var session: WebAuthenticationState { ASWebAuthenticationSession.states[objcObject] }

    /// ASWebAuthenticationSessionErrorCodeCanceledLogin.
    static let canceledLogin = 1
    /// ASWebAuthenticationSessionErrorCodePresentationContextInvalid.
    static let presentationContextInvalid = 3

    @ObjCMethod("dealloc")
    func dealloc() {
        ASWebAuthenticationSession.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: ASWebAuthenticationSession.objCClass.pointer)
    }

    @ObjCMethod("initWithURL:callbackURLScheme:completionHandler:")
    func initialize(url: NSObject, callbackURLScheme scheme: String?, completionHandler: ObjCBlock) -> Self {
        (session.url, session.callbackScheme, session.completion) = (url, scheme, completionHandler)
        return self
    }

    /// iOS 17.4's, with an ASWebAuthenticationSessionCallback.
    @ObjCMethod("initWithURL:callback:completionHandler:")
    func initialize(url: NSObject, callback: NSObject, completionHandler: ObjCBlock) -> Self {
        (session.url, session.callback, session.completion) = (url, callback, completionHandler)
        return self
    }

    @ObjCMethod("presentationContextProvider") func presentationContextProvider() -> NSObject? { session.provider.map { NSObject($0) } }
    @ObjCMethod("setPresentationContextProvider:") func setPresentationContextProvider(_ provider: NSObject?) { session.provider = provider?.objcObject }
    @ObjCMethod("prefersEphemeralWebBrowserSession") func prefersEphemeralWebBrowserSession() -> Bool { session.ephemeral }
    @ObjCMethod("setPrefersEphemeralWebBrowserSession:") func setPrefersEphemeralWebBrowserSession(_ ephemeral: Bool) { session.ephemeral = ephemeral }
    @ObjCMethod("additionalHeaderFields") func additionalHeaderFields() -> NSObject? { session.headers }
    @ObjCMethod("setAdditionalHeaderFields:") func setAdditionalHeaderFields(_ headers: NSObject?) { session.headers = headers }

    /// Whether the session can start: there is a web engine.
    @ObjCMethod("canStart") func canStart() -> Bool { !session.started && WPE.shared != nil }

    /// Shows the sheet in the next update pass, as UIKit presents; false
    /// when the session has started or can't.
    @ObjCMethod("start")
    func start() -> Bool {
        guard !session.started, WPE.shared != nil, let url = session.url else { return false }
        session.started = true
        let object = ObjCRuntime.retain(objcObject)!
        Updates.afterPass {
            defer { ObjCRuntime.release(object) }
            ASWebAuthenticationSession(objcObject: object, ownership: .retain).present(url)
        }
        return true
    }

    /// Closes the sheet; the handler hears the login was canceled.
    @ObjCMethod("cancel") func cancel() { finish(url: nil, errorCode: ASWebAuthenticationSession.canceledLogin) }

    /// The Cancel button's action.
    @ObjCMethod("_perryCancel:") func cancelButton(_ sender: NSObject?) { cancel() }

    // MARK: The sheet

    private func present(_ url: NSObject) {
        guard !session.finished else { return }
        guard let presenter = presenter() else {
            return finish(url: nil, errorCode: ASWebAuthenticationSession.presentationContextInvalid)
        }
        // UIBarButtonSystemItemCancel.
        let cancel = UIBarButtonItem.objCClass.object.allocated().unsafeCast(to: UIBarButtonItem.self)
            .initialize(systemItem: 1, target: self, action: ObjCSelector("_perryCancel:"))
        // The callback ends the session instead of loading.
        let object = objcObject
        guard let page = WebSheets.page(url: url, button: cancel, decide: { uri in
            let session = ASWebAuthenticationSession(objcObject: object, ownership: .retain)
            guard session.isCallback(uri) else { return true }
            let callback = NSURLObject.make(string: uri)
            Updates.afterPass { session.finish(url: callback, errorCode: nil) }
            return false
        }) else {
            return finish(url: nil, errorCode: ASWebAuthenticationSession.presentationContextInvalid)
        }
        let sheet = UINavigationController.objCClass.object.allocated().unsafeCast(to: UINavigationController.self)
            .initialize(rootViewController: page).unsafeCast(to: UIViewController.self)
        session.sheet = sheet
        presenter.present(sheet, animated: true, completion: nil)
    }

    /// Whether a navigation is to the callback: the scheme given, or what
    /// the callback object matches.
    private func isCallback(_ uri: String) -> Bool {
        if let callback = session.callback, callback.responds(to: "matchesURL:"), let url = NSURLObject.make(string: uri) {
            return callback.sendMatchesURL(url)
        }
        guard let scheme = session.callbackScheme?.lowercased(), let colon = uri.firstIndex(of: ":") else { return false }
        return uri[..<colon].lowercased() == scheme
    }

    /// The topmost controller of the window the provider names, else the
    /// key window's.
    private func presenter() -> UIViewController? {
        var window: UIWindow?
        if let provider = presentationContextProvider(),
           provider.responds(to: "presentationAnchorForWebAuthenticationSession:") {
            window = provider.sendPresentationAnchor(for: self)?.as(UIWindow.self)
        }
        if window == nil { window = Windows.key.map { UIWindow(objcObject: $0, ownership: .retain) } ?? Windows.visible.last }
        guard var top = window?.windowState.rootViewController else { return nil }
        while let presented = top.state.presented { top = presented }
        return top
    }

    /// Closes the sheet and tells the handler, once.
    private func finish(url: NSObject?, errorCode: Int?) {
        let session = session
        guard !session.finished else { return }
        session.finished = true
        if let sheet = session.sheet {
            session.sheet = nil
            sheet.dismiss(animated: true, completion: nil)
        }
        guard let completion = session.completion else { return }
        session.completion = nil
        let error = errorCode.map {
            NSErrorObject.make(domain: AuthenticationServicesConstants.ASWebAuthenticationSessionErrorDomain, code: $0, userInfo: nil)
        }
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
        completion.function(as: Invoke.self)(completion.object, url?.objcObject, error?.objcObject)
    }
}

/// The session's provider's and callback's messages.
extension NSObject {
    @ObjCMethod("presentationAnchorForWebAuthenticationSession:")
    func sendPresentationAnchor(for session: ASWebAuthenticationSession) -> NSObject?
    @ObjCMethod("matchesURL:") func sendMatchesURL(_ url: NSObject) -> Bool
    @ObjCMethod("host") func sendHost() -> String?
}

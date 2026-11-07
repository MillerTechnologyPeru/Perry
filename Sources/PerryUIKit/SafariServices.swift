import CPerryGeometry
import Glibc
import PerryObjCInterop

// SafariServices' Safari view controller: a web page shown over the app,
// which on iOS is Safari's. Here it is a navigation controller (rather than
// a plain view controller) whose page is a WKWebView (WPE), dressed as
// iOS 17's (WebSheets.page), with a Done button that closes it and tells
// the delegate (-safariViewControllerDidFinish:). Links to schemes outside the web go to
// -[UIApplication openURL:], as Safari hands them on: the app's own scheme
// opens the app (IncomingURLs), so an OAuth sign-in's redirect reaches it.

/// The pages web sheets show: Safari view controllers' and web
/// authentication sessions'.
enum WebSheets {
    /// Schemes the page loads itself; any other leaves the web.
    static let webSchemes: Set<String> = ["http", "https", "about", "data", "blob", "file", "javascript"]

    /// A controller showing `url` as iOS 17's Safari sheets do: the page
    /// under a bar with `button` on its left, a lock and the page's host in
    /// its middle, and text size and reload on its right, over a toolbar of
    /// back, forward, share and Safari. Each navigation asks `decide`
    /// whether to go ahead. Nil without WPE.
    static func page(url: NSObject, button: UIBarButtonItem, decide: @escaping (String) -> Bool) -> UIViewController? {
        guard WPE.shared != nil else { return nil }
        let bounds = Screen.bounds
        let toolbarHeight: CGFloat = 44
        let container = UIView.objCClass.object.allocated().initializeView(frame: bounds).unsafeCast(to: UIView.self)
        container.setBackgroundColor(UIColor.white())
        let web = WKWebView.objCClass.object.allocated().unsafeCast(to: WKWebView.self)
            .initialize(frame: CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - toolbarHeight), configuration: nil)
            .unsafeCast(to: WKWebView.self)
        web.setAutoresizingMask(18)     // flexible width and height
        container.addSubview(web)
        let toolbar = UIToolbar.objCClass.object.allocated().initializeView(
            frame: CGRect(x: 0, y: bounds.height - toolbarHeight, width: bounds.width, height: toolbarHeight)).unsafeCast(to: UIToolbar.self)
        toolbar.setAutoresizingMask(10)  // flexible width and top margin
        container.addSubview(toolbar)

        let controls = WebSheetControls.objCClass.object.newInstance().unsafeCast(to: WebSheetControls.self)
        controls.setWebView(web)
        web.web.sheetControls = controls
        func item(_ symbol: String, _ action: String) -> UIBarButtonItem {
            UIBarButtonItem.objCClass.object.allocated().unsafeCast(to: UIBarButtonItem.self)
                .initialize(image: UIImage.systemImage(named: symbol), style: 0, target: controls, action: ObjCSelector(action))
        }
        func space() -> UIBarButtonItem {
            // UIBarButtonSystemItemFlexibleSpace.
            UIBarButtonItem.objCClass.object.allocated().unsafeCast(to: UIBarButtonItem.self)
                .initialize(systemItem: 5, target: nil, action: nil)
        }
        let back = item("chevron.backward", "goBack:"), forward = item("chevron.forward", "goForward:")
        toolbar.setItems(NSMutableArray.of([back, space(), forward, space(), space(), item("square.and.arrow.up", "share:"),
                                            space(), space(), item("safari", "openInSafari:")]))

        let page = UIViewController.objCClass.object.allocated().initializeViewController(nibName: nil, bundle: nil)
            .unsafeCast(to: UIViewController.self)
        page.setView(container)
        // The page below the bar, as Safari shows it: it doesn't scroll
        // under it.
        page.setEdgesForExtendedLayout(0)
        let navigationItem = page.navigationItem()
        navigationItem.setLeftBarButtonItem(button)
        navigationItem.setRightBarButtonItems(NSMutableArray.of([item("arrow.clockwise", "reload:"), item("textformat.size", "textSize:")]))
        // The bar follows the page: its host, and whether it can go back
        // and forward.
        let update: () -> Void = { [weak back, weak forward] in
            let host = (web.web.page?.uri).flatMap(NSURLObject.make(string:))?.sendHost() ?? url.sendHost() ?? ""
            navigationItem.setTitleView(WebSheets.titleView(host))
            back?.setEnabled(web.web.page?.canGoBack ?? false)
            forward?.setEnabled(web.web.page?.canGoForward ?? false)
            toolbar.setNeedsDisplay()
        }
        web.web.navigationChanged = update
        web.page()?.decideNavigation = { uri, _ in decide(uri) }
        update()
        _ = web.loadRequest(NSURLRequestFactory.make(url: url))
        return page
    }

    /// A lock and the host, as Safari's bar shows a secure page's.
    static func titleView(_ host: String) -> UIView {
        let font = UIFont.systemFont(size: 17, weight: 0.3)
        let width = ceil(Text.size(host, font: font).width)
        let lockWidth: CGFloat = 12, gap: CGFloat = 6
        let view = UIView.objCClass.object.allocated()
            .initializeView(frame: CGRect(x: 0, y: 0, width: lockWidth + gap + width, height: 22)).unsafeCast(to: UIView.self)
        if let lock = UIImage.systemImage(named: "lock.fill") {
            let image = UIImageView.objCClass.object.allocated().unsafeCast(to: UIImageView.self).initialize(image: lock)
                .unsafeCast(to: UIImageView.self)
            image.setFrame(CGRect(x: 0, y: 3, width: lockWidth, height: 15))
            image.setTintColor(UIColor.black())
            view.addSubview(image)
        }
        let label = UILabel.objCClass.object.allocated().initializeView(
            frame: CGRect(x: lockWidth + gap, y: 0, width: width, height: 22)).unsafeCast(to: UILabel.self)
        label.setFont(font)
        label.setText(host)
        view.addSubview(label)
        return view
    }

    /// Whether a URL is the web's, which the page loads itself.
    static func isWeb(_ uri: String) -> Bool {
        guard let colon = uri.firstIndex(of: ":") else { return true }
        return webSchemes.contains(uri[..<colon].lowercased())
    }
}

/// A web sheet's bar and toolbar buttons' target: its page's back,
/// forward and reload. Text size, share and Safari, which have nothing to
/// open here, do nothing.
@ObjCClass("_PerryWebSheetControls")
final class WebSheetControls: NSObject {
    nonisolated(unsafe) static var views: [UnsafeMutableRawPointer: UnsafeMutableRawPointer] = [:]

    @ObjCMethod("dealloc")
    func dealloc() {
        WebSheetControls.views[objcObject] = nil
        ObjCRuntime.superDealloc(objcObject, definedOn: WebSheetControls.objCClass.pointer)
    }

    /// Not retained: the web view holds these controls.
    func setWebView(_ view: WKWebView) { WebSheetControls.views[objcObject] = view.objcObject }
    private var webView: WKWebView? { WebSheetControls.views[objcObject].map { WKWebView(objcObject: $0, ownership: .retain) } }

    @ObjCMethod("goBack:") func goBack(_ sender: NSObject?) { _ = webView?.goBack() }
    @ObjCMethod("goForward:") func goForward(_ sender: NSObject?) { _ = webView?.goForward() }
    @ObjCMethod("reload:") func reload(_ sender: NSObject?) { _ = webView?.reload() }
    @ObjCMethod("textSize:") func textSize(_ sender: NSObject?) {}
    @ObjCMethod("share:") func share(_ sender: NSObject?) { uikitWarning("no share sheet for the page") }
    @ObjCMethod("openInSafari:") func openInSafari(_ sender: NSObject?) { uikitWarning("no Safari to open the page in") }
}

@ObjCClass("SFSafariViewControllerConfiguration")
open class SFSafariViewControllerConfiguration: NSObject {
    nonisolated(unsafe) static var reader: [UnsafeMutableRawPointer: Bool] = [:]
    nonisolated(unsafe) static var collapsing: [UnsafeMutableRawPointer: Bool] = [:]

    @ObjCMethod("dealloc")
    func dealloc() {
        SFSafariViewControllerConfiguration.reader[objcObject] = nil
        SFSafariViewControllerConfiguration.collapsing[objcObject] = nil
        ObjCRuntime.superDealloc(objcObject, definedOn: SFSafariViewControllerConfiguration.objCClass.pointer)
    }

    @ObjCMethod("entersReaderIfAvailable") func entersReaderIfAvailable() -> Bool { Self.reader[objcObject] ?? false }
    @ObjCMethod("setEntersReaderIfAvailable:") func setEntersReaderIfAvailable(_ enters: Bool) { Self.reader[objcObject] = enters }
    @ObjCMethod("barCollapsingEnabled") func barCollapsingEnabled() -> Bool { Self.collapsing[objcObject] ?? true }
    @ObjCMethod("setBarCollapsingEnabled:") func setBarCollapsingEnabled(_ enabled: Bool) { Self.collapsing[objcObject] = enabled }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }
}

final class SafariState: ObjectState {
    /// Not retained, as Darwin's is weak.
    var delegate: UnsafeMutableRawPointer?
    var configuration: NSObject?
    var barTintColor: NSObject?
    var controlTintColor: NSObject?
    var dismissButtonStyle = 0
}

@ObjCClass("SFSafariViewController")
open class SFSafariViewController: UINavigationController {
    static let safariStates = StateTable<SafariState>()
    var safari: SafariState { SFSafariViewController.safariStates[objcObject] }

    @ObjCMethod("dealloc")
    override func dealloc() {
        SFSafariViewController.safariStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCMethod("initWithURL:configuration:")
    func initialize(url: NSObject, configuration: NSObject?) -> NSObject {
        safari.configuration = configuration
        let object = objcObject
        // UIBarButtonSystemItemDone.
        let done = UIBarButtonItem.objCClass.object.allocated().unsafeCast(to: UIBarButtonItem.self)
            .initialize(systemItem: 0, target: self, action: ObjCSelector("_perryDone:"))
        guard let page = WebSheets.page(url: url, button: done, decide: { uri in
            guard !WebSheets.isWeb(uri) else { return true }
            let controller = SFSafariViewController(objcObject: object, ownership: .retain)
            controller.leaveWeb(uri)
            return false
        }) else {
            uikitWarning("SFSafariViewController can't show \(url.describedByObject()) without WPE")
            return initialize(nibName: nil, bundle: nil)
        }
        return initialize(rootViewController: page)
    }

    @ObjCMethod("initWithURL:") func initialize(url: NSObject) -> NSObject { initialize(url: url, configuration: nil) }

    @ObjCMethod("initWithURL:entersReaderIfAvailable:")
    func initialize(url: NSObject, entersReaderIfAvailable: Bool) -> NSObject { initialize(url: url, configuration: nil) }

    @ObjCMethod("delegate") override func delegate() -> NSObject? { safari.delegate.map { NSObject($0) } }
    @ObjCMethod("setDelegate:") override func setDelegate(_ delegate: NSObject?) { safari.delegate = delegate?.objcObject }
    @ObjCMethod("configuration") func configuration() -> NSObject? { safari.configuration }
    @ObjCMethod("preferredBarTintColor") func preferredBarTintColor() -> NSObject? { safari.barTintColor }
    @ObjCMethod("setPreferredBarTintColor:") func setPreferredBarTintColor(_ color: NSObject?) { safari.barTintColor = color }
    @ObjCMethod("preferredControlTintColor") func preferredControlTintColor() -> NSObject? { safari.controlTintColor }
    @ObjCMethod("setPreferredControlTintColor:") func setPreferredControlTintColor(_ color: NSObject?) { safari.controlTintColor = color }
    /// SFSafariViewControllerDismissButtonStyle: done 0, close 1, cancel 2.
    @ObjCMethod("dismissButtonStyle") func dismissButtonStyle() -> Int { safari.dismissButtonStyle }
    @ObjCMethod("setDismissButtonStyle:") func setDismissButtonStyle(_ style: Int) { safari.dismissButtonStyle = style }

    /// Done: the controller closes, and the delegate hears it finished.
    @ObjCMethod("_perryDone:")
    func done(_ sender: NSObject?) {
        dismiss(animated: true, completion: nil)
        guard let delegate = delegate(), delegate.responds(to: "safariViewControllerDidFinish:") else { return }
        delegate.sendSafariViewControllerDidFinish(self)
    }

    /// A link out of the web, which Safari hands on: the app's own opens
    /// the app.
    func leaveWeb(_ uri: String) {
        guard let url = NSURLObject.make(string: uri) else { return }
        Updates.afterPass {
            if IncomingURLs.isOwn(url) {
                IncomingURLs.open(url)
            } else {
                uikitWarning("no app to open \(uri)")
            }
        }
    }
}

extension NSObject {
    @ObjCMethod("safariViewControllerDidFinish:") func sendSafariViewControllerDidFinish(_ controller: SFSafariViewController)
}

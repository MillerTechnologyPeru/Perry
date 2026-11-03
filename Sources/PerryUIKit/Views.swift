import CPerryGeometry
import Glibc
import PerryObjCInterop

// More of UIKit's views and the objects nibs hold: layout guides and their
// constraints, image placeholders, toolbars, paragraph styles, and web
// views, which show nothing (there is no web engine) but take their loads.

/// The top and bottom layout guides storyboards give a view controller:
/// hidden views the constraints attach to.
@ObjCClass("_UILayoutGuide")
open class UILayoutGuideView: UIView {
    @ObjCMethod("length") func length() -> CGFloat { state.bounds.height }
}

@ObjCClass("_UILayoutSupportConstraint")
open class UILayoutSupportConstraint: NSLayoutConstraint {}

/// An image a nib names, loaded from the main bundle.
@ObjCClass("UIImageNibPlaceholder")
open class UIImageNibPlaceholder: UIImage {}

// MARK: - UIToolbar

final class ToolbarState: ObjectState {
    var items: [UIBarButtonItem] = []
    var barStyle = 0
    var translucent = true
    var barTintColor: UIColor?
    var delegate: UnsafeMutableRawPointer?
}

/// A bar of items along the bottom, their titles in the tint color.
@ObjCClass("UIToolbar")
open class UIToolbar: UIView {
    static let toolbarStates = StateTable<ToolbarState>()
    var toolbar: ToolbarState { UIToolbar.toolbarStates[objcObject] }

    @ObjCMethod("dealloc")
    override func dealloc() {
        UIToolbar.toolbarStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCMethod("initWithCoder:")
    override func initialize(coder: NSObject) -> Self {
        _ = super.initialize(coder: coder)
        let decoded = Coder(coder: coder)
        toolbar.items = decoded.array("UIItems").compactMap { $0.as(UIBarButtonItem.self) }
        toolbar.barStyle = decoded.integer("UIBarStyle")
        return self
    }

    @ObjCMethod("items") func items() -> NSObject? { toolbar.items.isEmpty ? nil : NSMutableArray.of(toolbar.items) }
    @ObjCMethod("setItems:") func setItems(_ items: NSArray?) { setItems(items, animated: false) }
    @ObjCMethod("setItems:animated:") func setItems(_ items: NSArray?, animated: Bool) {
        toolbar.items = items?.elements.compactMap { $0.as(UIBarButtonItem.self) } ?? []
        setNeedsDisplay()
    }
    @ObjCMethod("barStyle") func barStyle() -> Int { toolbar.barStyle }
    @ObjCMethod("setBarStyle:") func setBarStyle(_ style: Int) { toolbar.barStyle = style }
    @ObjCMethod("isTranslucent") func isTranslucent() -> Bool { toolbar.translucent }
    @ObjCMethod("setTranslucent:") func setTranslucent(_ translucent: Bool) { toolbar.translucent = translucent }
    @ObjCMethod("barTintColor") func barTintColor() -> UIColor? { toolbar.barTintColor }
    @ObjCMethod("setBarTintColor:") func setBarTintColor(_ color: UIColor?) { toolbar.barTintColor = color; setNeedsDisplay() }
    @ObjCMethod("delegate") func delegate() -> NSObject? { toolbar.delegate.map { NSObject($0) } }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { toolbar.delegate = delegate?.objcObject }

    @ObjCMethod("sizeThatFits:")
    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: 44) }

    @ObjCMethod("drawRect:")
    override func draw(_ rect: CGRect) {
        guard let context = Graphics.current else { return }
        let bounds = state.bounds
        let background = toolbar.barTintColor ?? UIColor.gray(0.97), separator = UIColor.separator()
        withExtendedLifetime((background, separator)) {
            CG.setFillColorWithColor(context, background.state.makeCGColor())
            CG.fillRect(context, bounds)
            CG.setFillColorWithColor(context, separator.state.makeCGColor())
            CG.fillRect(context, CGRect(x: 0, y: 0, width: bounds.width, height: 1 / Screen.scale))
        }
        let font = UIFont.systemFont(size: 17)
        var x: CGFloat = 16
        for item in toolbar.items where !item.displayTitle.isEmpty {
            let title = item.displayTitle
            Text.draw(title, at: CGPoint(x: x, y: bounds.midY - Text.size(title, font: font).height / 2), font: font, color: tintColor())
            x += Text.size(title, font: font).width + 20
        }
    }
}

// MARK: - Paragraph styles

final class ParagraphStyleState: ObjectState {
    var alignment = 4
    var lineBreakMode = 0
    var lineSpacing: CGFloat = 0
    var paragraphSpacing: CGFloat = 0
    var firstLineHeadIndent: CGFloat = 0
    var headIndent: CGFloat = 0
    var tailIndent: CGFloat = 0
    var minimumLineHeight: CGFloat = 0
    var maximumLineHeight: CGFloat = 0
    var lineHeightMultiple: CGFloat = 0
}

@ObjCClass("NSParagraphStyle")
open class NSParagraphStyle: NSObject {
    static let states = StateTable<ParagraphStyleState>()
    var state: ParagraphStyleState { NSParagraphStyle.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        NSParagraphStyle.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSParagraphStyle.objCClass.pointer)
    }

    @ObjCClassMethod("defaultParagraphStyle")
    static func defaultParagraphStyle(_ cls: ObjCClass) -> NSObject { cls.object.allocated().unsafeCast(to: NSObject.self) }

    @ObjCMethod("initWithCoder:")
    func initialize(coder: NSObject) -> Self {
        let decoded = Coder(coder: coder)
        if decoded.has("NSAlignment") { state.alignment = decoded.integer("NSAlignment") }
        state.lineBreakMode = decoded.integer("NSLineBreakMode")
        state.lineSpacing = decoded.double("NSLineSpacing")
        state.paragraphSpacing = decoded.double("NSParagraphSpacing")
        return self
    }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
        let copy = NSParagraphStyle.objCClass.object.allocated().unsafeCast(to: NSParagraphStyle.self)
        let (from, to) = (state, copy.state)
        (to.alignment, to.lineBreakMode, to.lineSpacing, to.paragraphSpacing) = (from.alignment, from.lineBreakMode, from.lineSpacing, from.paragraphSpacing)
        (to.firstLineHeadIndent, to.headIndent, to.tailIndent) = (from.firstLineHeadIndent, from.headIndent, from.tailIndent)
        (to.minimumLineHeight, to.maximumLineHeight, to.lineHeightMultiple) = (from.minimumLineHeight, from.maximumLineHeight, from.lineHeightMultiple)
        return ObjCRuntime.retain(copy.objcObject)!
    }

    @ObjCMethod("mutableCopyWithZone:")
    func mutableCopy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
        let copy = NSMutableParagraphStyle.objCClass.object.allocated().unsafeCast(to: NSParagraphStyle.self)
        let (from, to) = (state, copy.state)
        (to.alignment, to.lineBreakMode, to.lineSpacing, to.paragraphSpacing) = (from.alignment, from.lineBreakMode, from.lineSpacing, from.paragraphSpacing)
        return ObjCRuntime.retain(copy.objcObject)!
    }

    @ObjCMethod("alignment") func alignment() -> Int { state.alignment }
    @ObjCMethod("lineBreakMode") func lineBreakMode() -> Int { state.lineBreakMode }
    @ObjCMethod("lineSpacing") func lineSpacing() -> CGFloat { state.lineSpacing }
    @ObjCMethod("paragraphSpacing") func paragraphSpacing() -> CGFloat { state.paragraphSpacing }
    @ObjCMethod("firstLineHeadIndent") func firstLineHeadIndent() -> CGFloat { state.firstLineHeadIndent }
    @ObjCMethod("headIndent") func headIndent() -> CGFloat { state.headIndent }
    @ObjCMethod("tailIndent") func tailIndent() -> CGFloat { state.tailIndent }
    @ObjCMethod("minimumLineHeight") func minimumLineHeight() -> CGFloat { state.minimumLineHeight }
    @ObjCMethod("maximumLineHeight") func maximumLineHeight() -> CGFloat { state.maximumLineHeight }
    @ObjCMethod("lineHeightMultiple") func lineHeightMultiple() -> CGFloat { state.lineHeightMultiple }
}

@ObjCClass("NSMutableParagraphStyle")
open class NSMutableParagraphStyle: NSParagraphStyle {
    @ObjCMethod("setAlignment:") func setAlignment(_ alignment: Int) { state.alignment = alignment }
    @ObjCMethod("setLineBreakMode:") func setLineBreakMode(_ mode: Int) { state.lineBreakMode = mode }
    @ObjCMethod("setLineSpacing:") func setLineSpacing(_ spacing: CGFloat) { state.lineSpacing = spacing }
    @ObjCMethod("setParagraphSpacing:") func setParagraphSpacing(_ spacing: CGFloat) { state.paragraphSpacing = spacing }
    @ObjCMethod("setFirstLineHeadIndent:") func setFirstLineHeadIndent(_ indent: CGFloat) { state.firstLineHeadIndent = indent }
    @ObjCMethod("setHeadIndent:") func setHeadIndent(_ indent: CGFloat) { state.headIndent = indent }
    @ObjCMethod("setTailIndent:") func setTailIndent(_ indent: CGFloat) { state.tailIndent = indent }
    @ObjCMethod("setMinimumLineHeight:") func setMinimumLineHeight(_ height: CGFloat) { state.minimumLineHeight = height }
    @ObjCMethod("setMaximumLineHeight:") func setMaximumLineHeight(_ height: CGFloat) { state.maximumLineHeight = height }
    @ObjCMethod("setLineHeightMultiple:") func setLineHeightMultiple(_ multiple: CGFloat) { state.lineHeightMultiple = multiple }
}

// MARK: - Web views, which show nothing

final class WebViewState: ObjectState {
    var delegate: UnsafeMutableRawPointer?
    var navigationDelegate: UnsafeMutableRawPointer?
    var uiDelegate: UnsafeMutableRawPointer?
    var html: String?
    var request: NSObject?
    var scalesPageToFit = false
    var configuration: NSObject?
}

/// UIWebView: takes what it is asked to load and tells its delegate the
/// load finished; it draws only its background.
@ObjCClass("UIWebView")
open class UIWebView: UIView {
    static let webStates = StateTable<WebViewState>()
    var web: WebViewState { UIWebView.webStates[objcObject] }

    @ObjCMethod("dealloc")
    override func dealloc() {
        UIWebView.webStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCMethod("delegate") func delegate() -> NSObject? { web.delegate.map { NSObject($0) } }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { web.delegate = delegate?.objcObject }
    @ObjCMethod("scalesPageToFit") func scalesPageToFit() -> Bool { web.scalesPageToFit }
    @ObjCMethod("setScalesPageToFit:") func setScalesPageToFit(_ scales: Bool) { web.scalesPageToFit = scales }
    @ObjCMethod("request") func request() -> NSObject? { web.request }
    @ObjCMethod("isLoading") func isLoading() -> Bool { false }
    @ObjCMethod("canGoBack") func canGoBack() -> Bool { false }
    @ObjCMethod("canGoForward") func canGoForward() -> Bool { false }
    @ObjCMethod("goBack") func goBack() {}
    @ObjCMethod("goForward") func goForward() {}
    @ObjCMethod("reload") func reload() {}
    @ObjCMethod("stopLoading") func stopLoading() {}
    @ObjCMethod("scrollView") func scrollView() -> NSObject? { nil }

    @ObjCMethod("loadHTMLString:baseURL:")
    func loadHTMLString(_ html: String?, baseURL: NSObject?) {
        web.html = html
        finishLoad()
    }

    @ObjCMethod("loadRequest:")
    func loadRequest(_ request: NSObject?) {
        web.request = request
        finishLoad()
    }

    @ObjCMethod("stringByEvaluatingJavaScriptFromString:") func evaluate(_ script: String?) -> String? { "" }

    /// The delegate hears the load start and finish, on the next pass.
    private func finishLoad() {
        let object = objcObject
        Updates.afterPass {
            let view = UIWebView(objcObject: object, ownership: .retain)
            guard let delegate = view.delegate() else { return }
            if delegate.responds(to: "webViewDidStartLoad:") { delegate.sendWebViewDidStartLoad(view) }
            if delegate.responds(to: "webViewDidFinishLoad:") { delegate.sendWebViewDidFinishLoad(view) }
        }
    }
}

extension NSObject {
    @ObjCMethod("webViewDidStartLoad:") func sendWebViewDidStartLoad(_ view: UIView)
    @ObjCMethod("webViewDidFinishLoad:") func sendWebViewDidFinishLoad(_ view: UIView)
}

@ObjCClass("WKWebViewConfiguration")
open class WKWebViewConfiguration: NSObject {
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }
}

/// WKWebView: an empty view that takes its loads.
@ObjCClass("WKWebView")
open class WKWebView: UIView {
    static let webStates = StateTable<WebViewState>()
    var web: WebViewState { WKWebView.webStates[objcObject] }

    @ObjCMethod("dealloc")
    override func dealloc() {
        WKWebView.webStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCMethod("initWithFrame:configuration:")
    func initialize(frame: CGRect, configuration: NSObject?) -> NSObject {
        let view = initializeView(frame: frame).unsafeCast(to: WKWebView.self)
        view.web.configuration = configuration
        return view
    }

    @ObjCMethod("configuration") func configuration() -> NSObject? { web.configuration }
    @ObjCMethod("navigationDelegate") func navigationDelegate() -> NSObject? { web.navigationDelegate.map { NSObject($0) } }
    @ObjCMethod("setNavigationDelegate:") func setNavigationDelegate(_ delegate: NSObject?) { web.navigationDelegate = delegate?.objcObject }
    @ObjCMethod("UIDelegate") func uiDelegate() -> NSObject? { web.uiDelegate.map { NSObject($0) } }
    @ObjCMethod("setUIDelegate:") func setUIDelegate(_ delegate: NSObject?) { web.uiDelegate = delegate?.objcObject }
    @ObjCMethod("loadHTMLString:baseURL:") func loadHTMLString(_ html: String?, baseURL: NSObject?) -> NSObject? {
        web.html = html
        return nil
    }
    @ObjCMethod("loadRequest:") func loadRequest(_ request: NSObject?) -> NSObject? {
        web.request = request
        return nil
    }
    @ObjCMethod("URL") func url() -> NSObject? { nil }
    @ObjCMethod("title") func title() -> String? { nil }
    @ObjCMethod("isLoading") func isLoading() -> Bool { false }
    @ObjCMethod("estimatedProgress") func estimatedProgress() -> Double { 1 }
    @ObjCMethod("canGoBack") func canGoBack() -> Bool { false }
    @ObjCMethod("canGoForward") func canGoForward() -> Bool { false }
    @ObjCMethod("goBack") func goBack() -> NSObject? { nil }
    @ObjCMethod("goForward") func goForward() -> NSObject? { nil }
    @ObjCMethod("reload") func reload() -> NSObject? { nil }
    @ObjCMethod("stopLoading") func stopLoading() {}
    @ObjCMethod("scrollView") func scrollView() -> NSObject? { nil }
    @ObjCMethod("evaluateJavaScript:completionHandler:") func evaluateJavaScript(_ script: String?, completionHandler: ObjCBlock?) {}
}

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

/// A bar of items along the bottom, in the tint color: titles, or icons
/// for the system items that have them, spread by fixed and flexible
/// spaces. A tap on an item sends its action.
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

    nonisolated(unsafe) private static let font = UIFont.systemFont(size: 17)

    /// UIBarButtonSystemItem: flexible space 5, fixed space 6.
    private func isSpace(_ item: UIBarButtonItem) -> Bool { item.state.systemItem == 5 || item.state.systemItem == 6 }

    /// The width an item takes: its icon's, its title's, or a fixed space's.
    private func width(of item: UIBarButtonItem) -> CGFloat {
        if item.state.systemItem == 6 { return item.state.width }
        if item.state.systemItem == 5 { return 0 }
        if item.state.width > 0 { return item.state.width }
        if let view = item.state.customView { return view.state.bounds.width }
        if BarIcons.has(item.state.systemItem) { return 28 }
        return Text.size(item.displayTitle, font: UIToolbar.font).width
    }

    /// Each item's frame: 16 points in from the edges, 8 between items
    /// that are not spaces, flexible spaces sharing what is left.
    func itemFrames() -> [(item: UIBarButtonItem, frame: CGRect)] {
        let bounds = state.bounds, items = toolbar.items
        var fixed: CGFloat = 32
        var flexible = 0
        for (index, item) in items.enumerated() {
            fixed += width(of: item)
            if item.state.systemItem == 5 { flexible += 1 }
            if index > 0, !isSpace(item), !isSpace(items[index - 1]) { fixed += 8 }
        }
        let share = flexible > 0 ? max(0, bounds.width - fixed) / CGFloat(flexible) : 0
        var x: CGFloat = 16
        var frames: [(UIBarButtonItem, CGRect)] = []
        for (index, item) in items.enumerated() {
            if index > 0, !isSpace(item), !isSpace(items[index - 1]) { x += 8 }
            let width = item.state.systemItem == 5 ? share : width(of: item)
            frames.append((item, CGRect(x: x, y: 0, width: width, height: bounds.height)))
            x += width
        }
        return frames
    }

    @ObjCMethod("layoutSubviews")
    override func layoutSubviews() {
        for (item, frame) in itemFrames() {
            guard let view = item.state.customView else { continue }
            if view.state.superview != objcObject { addSubview(view) }
            let size = view.state.bounds.size
            view.sendSetFrame(CGRect(x: frame.minX, y: frame.midY - size.height / 2, width: size.width, height: size.height))
        }
    }

    @ObjCMethod("drawRect:")
    override func draw(_ rect: CGRect) {
        guard let context = Graphics.current else { return }
        let bounds = state.bounds
        let background = toolbar.barTintColor ?? UIColor.gray(0.97), separator = UIColor.separator()
        withExtendedLifetime((background, separator)) {
            CG.setFillColorWithColor(context, background.state.makeCGColor())
            CG.fillRect(context, bounds)
            CG.setFillColorWithColor(context, separator.state.makeCGColor())
            CG.fillRect(context, CGRect(x: 0, y: 0, width: bounds.width, height: Screen.pixel))
        }
        for (item, frame) in itemFrames() where !isSpace(item) && item.state.customView == nil {
            let color = item.state.tintColor ?? tintColor()
            if BarIcons.draw(item.state.systemItem, in: frame, color: color, context: context) { continue }
            let title = item.displayTitle
            Text.draw(title, at: CGPoint(x: frame.minX, y: frame.midY - Text.size(title, font: UIToolbar.font).height / 2),
                      font: UIToolbar.font, color: color)
        }
    }

    /// A tap sends the action of the item under it.
    func tap(at point: CGPoint) {
        for (item, frame) in itemFrames() where !isSpace(item) && item.state.enabled
            && point.x >= frame.minX - 8 && point.x <= frame.maxX + 8 {
            item.sendAction(startingAt: self)
            return
        }
    }
}

/// Icons for the system bar items that are drawn as icons, in place of
/// the SF Symbols iOS draws: lines in the item's tint color.
enum BarIcons {
    /// UIBarButtonSystemItem: add 4, compose 7, reply 8, action 9,
    /// search 12, refresh 13, stop 14, trash 16.
    static func has(_ item: Int) -> Bool { [4, 7, 8, 9, 12, 13, 14, 16].contains(item) }

    static func draw(_ item: Int, in frame: CGRect, color: UIColor, context: CGRef) -> Bool {
        guard has(item) else { return false }
        let path = CG.pathCreateMutable()
        defer { CG.release(path) }
        let cx = frame.midX, cy = frame.midY
        func line(_ points: [(CGFloat, CGFloat)]) {
            guard let first = points.first else { return }
            CG.pathMoveToPoint(path, nil, cx + first.0, cy + first.1)
            for point in points.dropFirst() { CG.pathAddLineToPoint(path, nil, cx + point.0, cy + point.1) }
        }
        switch item {
        case 4: // add: a plus
            line([(-9, 0), (9, 0)]); line([(0, -9), (0, 9)])
        case 7: // compose: a square and a pencil
            line([(2, -8), (-8, -8), (-8, 9), (9, 9), (9, -1)]); line([(9, -10), (-1, 0), (-2, 2), (0, 1), (10, -9)])
        case 8: // reply: a curved arrow
            line([(-4, -7), (-10, -1), (-4, 5)]); line([(-10, -1), (4, -1), (9, 3), (9, 8)])
        case 9: // action: a box open at the top, an arrow out of it
            line([(-4, -4), (-8, -4), (-8, 10), (8, 10), (8, -4), (4, -4)])
            line([(0, 3), (0, -12)]); line([(-4, -8), (0, -12), (4, -8)])
        case 12: // search: a magnifying glass
            CG.pathAddEllipseInRect(path, nil, CGRect(x: cx - 9, y: cy - 9, width: 13, height: 13)); line([(2.5, 2.5), (9, 9)])
        case 13: // refresh: an arc with an arrowhead
            CG.pathAddArc(path, nil, cx, cy + 1, 8, -0.5 * .pi, 1.6 * .pi, false); line([(-2, -11), (1, -7), (-3, -4)])
        case 14: // stop: a cross
            line([(-7, -7), (7, 7)]); line([(-7, 7), (7, -7)])
        default: // trash: a can and its lid
            line([(-9, -6), (9, -6)]); line([(-3, -6), (-3, -9), (3, -9), (3, -6)]); line([(-7, -6), (-6, 10), (6, 10), (7, -6)])
        }
        CG.saveGState(context)
        defer { CG.restoreGState(context) }
        withExtendedLifetime(color) {
            CG.setStrokeColorWithColor(context, color.state.makeCGColor())
            CG.setLineWidth(context, 1.8)
            CG.setLineCap(context, 1)
            CG.setLineJoin(context, 1)
            CG.addPath(context, path)
            CG.strokePath(context)
        }
        return true
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
    var paragraphSpacingBefore: CGFloat = 0
    var lineBreakStrategy: UInt = 0
    var hyphenationFactor: Float = 0
    /// NSWritingDirectionNatural.
    var baseWritingDirection = -1
    var allowsDefaultTighteningForTruncation = false
    // Private to UIKit, which SwiftUI sets.
    var secondaryLineBreakMode = 0
    var fullyJustified = false
    var spansAllLines = false

    func copy(from other: ParagraphStyleState) {
        (alignment, lineBreakMode, lineSpacing, paragraphSpacing) = (other.alignment, other.lineBreakMode, other.lineSpacing, other.paragraphSpacing)
        (firstLineHeadIndent, headIndent, tailIndent) = (other.firstLineHeadIndent, other.headIndent, other.tailIndent)
        (minimumLineHeight, maximumLineHeight, lineHeightMultiple) = (other.minimumLineHeight, other.maximumLineHeight, other.lineHeightMultiple)
        (paragraphSpacingBefore, lineBreakStrategy, hyphenationFactor) = (other.paragraphSpacingBefore, other.lineBreakStrategy, other.hyphenationFactor)
        (baseWritingDirection, allowsDefaultTighteningForTruncation) = (other.baseWritingDirection, other.allowsDefaultTighteningForTruncation)
        (secondaryLineBreakMode, fullyJustified, spansAllLines) = (other.secondaryLineBreakMode, other.fullyJustified, other.spansAllLines)
    }
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
        copy.state.copy(from: state)
        return ObjCRuntime.retain(copy.objcObject)!
    }

    @ObjCMethod("mutableCopyWithZone:")
    func mutableCopy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
        let copy = NSMutableParagraphStyle.objCClass.object.allocated().unsafeCast(to: NSParagraphStyle.self)
        copy.state.copy(from: state)
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
    @ObjCMethod("paragraphSpacingBefore") func paragraphSpacingBefore() -> CGFloat { state.paragraphSpacingBefore }
    @ObjCMethod("lineBreakStrategy") func lineBreakStrategy() -> UInt { state.lineBreakStrategy }
    @ObjCMethod("hyphenationFactor") func hyphenationFactor() -> Float { state.hyphenationFactor }
    @ObjCMethod("baseWritingDirection") func baseWritingDirection() -> Int { state.baseWritingDirection }
    @ObjCMethod("allowsDefaultTighteningForTruncation") func allowsDefaultTighteningForTruncation() -> Bool { state.allowsDefaultTighteningForTruncation }
    @ObjCMethod("secondaryLineBreakMode") func secondaryLineBreakMode() -> Int { state.secondaryLineBreakMode }
    @ObjCMethod("fullyJustified") func fullyJustified() -> Bool { state.fullyJustified }
    @ObjCMethod("spansAllLines") func spansAllLines() -> Bool { state.spansAllLines }
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
    @ObjCMethod("setParagraphSpacingBefore:") func setParagraphSpacingBefore(_ spacing: CGFloat) { state.paragraphSpacingBefore = spacing }
    @ObjCMethod("setLineBreakStrategy:") func setLineBreakStrategy(_ strategy: UInt) { state.lineBreakStrategy = strategy }
    @ObjCMethod("setHyphenationFactor:") func setHyphenationFactor(_ factor: Float) { state.hyphenationFactor = factor }
    @ObjCMethod("setBaseWritingDirection:") func setBaseWritingDirection(_ direction: Int) { state.baseWritingDirection = direction }
    @ObjCMethod("setAllowsDefaultTighteningForTruncation:")
    func setAllowsDefaultTighteningForTruncation(_ allows: Bool) { state.allowsDefaultTighteningForTruncation = allows }
    @ObjCMethod("setSecondaryLineBreakMode:") func setSecondaryLineBreakMode(_ mode: Int) { state.secondaryLineBreakMode = mode }
    @ObjCMethod("setFullyJustified:") func setFullyJustified(_ justified: Bool) { state.fullyJustified = justified }
    @ObjCMethod("setSpansAllLines:") func setSpansAllLines(_ spans: Bool) { state.spansAllLines = spans }
}

// MARK: - Web views, which show nothing

final class WebViewState: ObjectState {
    var delegate: UnsafeMutableRawPointer?
    var navigationDelegate: UnsafeMutableRawPointer?
    var uiDelegate: UnsafeMutableRawPointer?
    var html: String?
    var request: NSObject?
    var customUserAgent: String?
    var scalesPageToFit = false
    var configuration: NSObject?
    var allowsInlineMediaPlayback = false
    var mediaPlaybackRequiresUserAction = true
    var mediaPlaybackAllowsAirPlay = true
    var suppressesIncrementalRendering = false
    var keyboardDisplayRequiresUserAction = true
    var allowsLinkPreview = false
    var dataDetectorTypes: UInt = 0
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
    @ObjCMethod("allowsInlineMediaPlayback") func allowsInlineMediaPlayback() -> Bool { web.allowsInlineMediaPlayback }
    @ObjCMethod("setAllowsInlineMediaPlayback:") func setAllowsInlineMediaPlayback(_ value: Bool) { web.allowsInlineMediaPlayback = value }
    @ObjCMethod("mediaPlaybackRequiresUserAction") func mediaPlaybackRequiresUserAction() -> Bool { web.mediaPlaybackRequiresUserAction }
    @ObjCMethod("setMediaPlaybackRequiresUserAction:")
    func setMediaPlaybackRequiresUserAction(_ value: Bool) { web.mediaPlaybackRequiresUserAction = value }
    @ObjCMethod("mediaPlaybackAllowsAirPlay") func mediaPlaybackAllowsAirPlay() -> Bool { web.mediaPlaybackAllowsAirPlay }
    @ObjCMethod("setMediaPlaybackAllowsAirPlay:") func setMediaPlaybackAllowsAirPlay(_ value: Bool) { web.mediaPlaybackAllowsAirPlay = value }
    @ObjCMethod("suppressesIncrementalRendering") func suppressesIncrementalRendering() -> Bool { web.suppressesIncrementalRendering }
    @ObjCMethod("setSuppressesIncrementalRendering:")
    func setSuppressesIncrementalRendering(_ value: Bool) { web.suppressesIncrementalRendering = value }
    @ObjCMethod("keyboardDisplayRequiresUserAction")
    func keyboardDisplayRequiresUserAction() -> Bool { web.keyboardDisplayRequiresUserAction }
    @ObjCMethod("setKeyboardDisplayRequiresUserAction:")
    func setKeyboardDisplayRequiresUserAction(_ value: Bool) { web.keyboardDisplayRequiresUserAction = value }
    @ObjCMethod("allowsLinkPreview") func allowsLinkPreview() -> Bool { web.allowsLinkPreview }
    @ObjCMethod("setAllowsLinkPreview:") func setAllowsLinkPreview(_ value: Bool) { web.allowsLinkPreview = value }
    @ObjCMethod("dataDetectorTypes") func dataDetectorTypes() -> UInt { web.dataDetectorTypes }
    @ObjCMethod("setDataDetectorTypes:") func setDataDetectorTypes(_ value: UInt) { web.dataDetectorTypes = value }
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

    /// The delegate hears the load start and finish, on the next pass. The
    /// view is kept until then, as its controller may let it go first.
    private func finishLoad() {
        let object = ObjCRuntime.retain(objcObject)!
        Updates.afterPass {
            defer { ObjCRuntime.release(object) }
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
        return WebNavigations.start(self, failing: nil)
    }
    @ObjCMethod("loadRequest:") func loadRequest(_ request: NSObject?) -> NSObject? {
        web.request = request
        let url = request?.unsafeCast(to: NSURLRequestObject.self).url()
        return WebNavigations.start(self, failing: WebNavigations.isNetwork(url) ? WebErrors.offline() : nil)
    }
    @ObjCMethod("loadFileURL:allowingReadAccessToURL:")
    func loadFileURL(_ url: NSObject?, allowingReadAccessTo directory: NSObject?) -> NSObject? {
        WebNavigations.start(self, failing: nil)
    }
    @ObjCMethod("loadData:MIMEType:characterEncodingName:baseURL:")
    func loadData(_ data: NSObject?, mimeType: String?, encoding: String?, baseURL: NSObject?) -> NSObject? {
        WebNavigations.start(self, failing: nil)
    }
    @ObjCMethod("customUserAgent") func customUserAgent() -> String? { web.customUserAgent }
    @ObjCMethod("setCustomUserAgent:") func setCustomUserAgent(_ agent: String?) { web.customUserAgent = agent }
    @ObjCMethod("allowsBackForwardNavigationGestures") func allowsBackForwardNavigationGestures() -> Bool { false }
    @ObjCMethod("setAllowsBackForwardNavigationGestures:") func setAllowsBackForwardNavigationGestures(_ allows: Bool) {}
    @ObjCMethod("allowsLinkPreview") func allowsLinkPreview() -> Bool { false }
    @ObjCMethod("setAllowsLinkPreview:") func setAllowsLinkPreview(_ allows: Bool) {}
    @ObjCMethod("isInspectable") func isInspectable() -> Bool { false }
    @ObjCMethod("setInspectable:") func setInspectable(_ inspectable: Bool) {}
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
    /// No script runs: the handler hears an error after the pass.
    @ObjCMethod("evaluateJavaScript:completionHandler:") func evaluateJavaScript(_ script: String?, completionHandler: ObjCBlock?) {
        guard let completionHandler else { return }
        Updates.afterPass {
            typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
            completionHandler.function(as: Invoke.self)(completionHandler.object, nil, WebErrors.noScript().objcObject)
        }
    }
}

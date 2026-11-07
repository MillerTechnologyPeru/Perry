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
    /// Tab stops: the NSTextTabs set, and their locations; 0 for the
    /// default interval between the ones after them.
    var tabStops: NSObject?
    var tabLocations: [CGFloat] = []
    var defaultTabInterval: CGFloat = 0

    func copy(from other: ParagraphStyleState) {
        (alignment, lineBreakMode, lineSpacing, paragraphSpacing) = (other.alignment, other.lineBreakMode, other.lineSpacing, other.paragraphSpacing)
        (firstLineHeadIndent, headIndent, tailIndent) = (other.firstLineHeadIndent, other.headIndent, other.tailIndent)
        (minimumLineHeight, maximumLineHeight, lineHeightMultiple) = (other.minimumLineHeight, other.maximumLineHeight, other.lineHeightMultiple)
        (paragraphSpacingBefore, lineBreakStrategy, hyphenationFactor) = (other.paragraphSpacingBefore, other.lineBreakStrategy, other.hyphenationFactor)
        (baseWritingDirection, allowsDefaultTighteningForTruncation) = (other.baseWritingDirection, other.allowsDefaultTighteningForTruncation)
        (secondaryLineBreakMode, fullyJustified, spansAllLines) = (other.secondaryLineBreakMode, other.fullyJustified, other.spansAllLines)
        (tabStops, tabLocations, defaultTabInterval) = (other.tabStops, other.tabLocations, other.defaultTabInterval)
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
    /// NSTextHorizontalAlignment (natural 0, left 2, right 3, center 4),
    /// the visual alignment SwiftUI sets, as NSTextAlignment's.
    @ObjCMethod("horizontalAlignment")
    func horizontalAlignment() -> Int { [0: 2, 1: 4, 2: 3, 4: 0][state.alignment] ?? 0 }
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
    /// SwiftUI's text alignment: NSTextHorizontalAlignment, as
    /// NSTextAlignment (left 0, center 1, right 2, natural 4).
    @ObjCMethod("setHorizontalAlignment:")
    func setHorizontalAlignment(_ alignment: Int) { state.alignment = [2: 0, 3: 2, 4: 1][alignment] ?? 4 }
    @ObjCMethod("setFullyJustified:") func setFullyJustified(_ justified: Bool) { state.fullyJustified = justified }
    @ObjCMethod("setSpansAllLines:") func setSpansAllLines(_ spans: Bool) { state.spansAllLines = spans }
    @ObjCMethod("defaultTabInterval") func defaultTabInterval() -> CGFloat { state.defaultTabInterval }
    @ObjCMethod("setDefaultTabInterval:") func setDefaultTabInterval(_ interval: CGFloat) { state.defaultTabInterval = interval }
    @ObjCMethod("tabStops") func tabStops() -> NSObject? { state.tabStops }
    @ObjCMethod("setTabStops:")
    func setTabStops(_ stops: NSObject?) {
        state.tabStops = stops
        state.tabLocations = TabStops.locations(stops)
    }
}

/// The locations of an array of tab stops (NSTextTab or CTTextTab, which
/// are the same), in order.
enum TabStops {
    static func locations(_ stops: NSObject?) -> [CGFloat] {
        guard let stops else { return [] }
        typealias Count = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer) -> UInt
        typealias At = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, UInt) -> UnsafeMutableRawPointer?
        typealias Location = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer) -> CGFloat
        let count = unsafeBitCast(ObjCRuntime.msgSend, to: Count.self)(stops.objcObject, ObjCRuntime.selector("count"))
        var locations: [CGFloat] = []
        for index in 0..<count {
            guard let tab = unsafeBitCast(ObjCRuntime.msgSend, to: At.self)(stops.objcObject, ObjCRuntime.selector("objectAtIndex:"), index)
            else { continue }
            locations.append(unsafeBitCast(ObjCRuntime.msgSend, to: Location.self)(tab, ObjCRuntime.selector("location")))
        }
        return locations.sorted()
    }

    /// The tab stops of a paragraph style of any provider: its locations,
    /// and the default interval (28 points, Darwin's, when it gives none).
    static func of(_ style: NSObject?) -> (locations: [CGFloat], interval: CGFloat) {
        guard let style else { return ([], 28) }
        if let own = style.as(NSParagraphStyle.self) {
            return (own.state.tabLocations, own.state.defaultTabInterval > 0 ? own.state.defaultTabInterval : 28)
        }
        typealias Interval = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer) -> CGFloat
        typealias Object = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer) -> UnsafeMutableRawPointer?
        var interval: CGFloat = 0
        var stopLocations: [CGFloat] = []
        if style.responds(to: "defaultTabInterval") {
            interval = unsafeBitCast(ObjCRuntime.msgSend, to: Interval.self)(style.objcObject, ObjCRuntime.selector("defaultTabInterval"))
        }
        if style.responds(to: "tabStops"),
           let stops = unsafeBitCast(ObjCRuntime.msgSend, to: Object.self)(style.objcObject, ObjCRuntime.selector("tabStops")) {
            stopLocations = locations(NSObject(stops))
        }
        return (stopLocations, interval > 0 ? interval : 28)
    }
}

// MARK: - Web views

final class WebViewState: ObjectState {
    /// WKWebView's page, over WPE, and its last frame.
    var page: WebPage?
    var frameImage: Owned?
    /// The navigation the delegate's calls name, and whether it failed.
    var navigation: NSObject?
    var navigationFailed = false
    /// Whether the load finished, and a frame came after: snapshots wait
    /// for one.
    var loadFinished = false
    var frameCurrent = false
    var snapshotWaiters: [() -> Void] = []
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

/// UIWebView: a page of WPE WebKit's, as WKWebView's, with UIWebView's
/// delegate and its scripts run to completion before they return. Without
/// WPE it takes what it is asked to load and tells its delegate the load
/// finished, drawing only its background.
@ObjCClass("UIWebView")
open class UIWebView: UIView {
    static let webStates = StateTable<WebViewState>()
    var web: WebViewState { UIWebView.webStates[objcObject] }

    @ObjCMethod("dealloc")
    override func dealloc() {
        WebViews.live.removeAll { $0.object == objcObject }
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
    @ObjCMethod("isLoading") func isLoading() -> Bool { web.page?.isLoading ?? false }
    @ObjCMethod("canGoBack") func canGoBack() -> Bool { web.page?.canGoBack ?? false }
    @ObjCMethod("canGoForward") func canGoForward() -> Bool { web.page?.canGoForward ?? false }
    @ObjCMethod("goBack") func goBack() { web.page?.goBack() }
    @ObjCMethod("goForward") func goForward() { web.page?.goForward() }
    @ObjCMethod("reload") func reload() { web.page?.reload() }
    @ObjCMethod("stopLoading") func stopLoading() { web.page?.stopLoading() }
    @ObjCMethod("scrollView") func scrollView() -> NSObject? { nil }

    @ObjCMethod("loadHTMLString:baseURL:")
    func loadHTMLString(_ html: String?, baseURL: NSObject?) {
        web.html = html
        guard let page = page() else { return finishLoad() }
        page.loadHTML(html ?? "", baseURI: baseURL?.sendAbsoluteString() ?? "about:blank")
    }

    @ObjCMethod("loadRequest:")
    func loadRequest(_ request: NSObject?) {
        web.request = request
        guard let page = page(), let uri = request?.unsafeCast(to: NSURLRequestObject.self).url()?.sendAbsoluteString() else {
            return finishLoad()
        }
        page.loadURI(uri)
    }

    /// The script's value as a string, once it has run: strings, numbers
    /// and Booleans; empty for other values and exceptions.
    @ObjCMethod("stringByEvaluatingJavaScriptFromString:") func evaluate(_ script: String?) -> String? {
        guard let page = page() else { return "" }
        return page.evaluateString(script ?? "") ?? ""
    }

    /// The view's page, made on its first load; nil without WPE. Its
    /// navigations ask the delegate, which hears them start, finish and
    /// fail.
    func page() -> WebPage? {
        if let page = web.page { return page }
        guard let page = makeWebPage(web) else { return nil }
        let object = objcObject
        // The delegate is asked with an NSURLRequest, which CFNetwork has
        // when the program uses it; otherwise navigations go ahead.
        page.decideNavigation = { uri, type in
            let view = UIWebView(objcObject: object, ownership: .retain)
            guard Classes.named("NSURLRequest") != nil, let request = NSURLObject.make(string: uri).map({ NSURLRequestFactory.make(url: $0) }) else { return true }
            view.web.request = request
            guard let delegate = view.delegate(), delegate.responds(to: "webView:shouldStartLoadWithRequest:navigationType:") else {
                return true
            }
            return delegate.sendShouldStartLoad(view, request, Int(type))
        }
        page.loadChanged = { event in
            let view = UIWebView(objcObject: object, ownership: .retain)
            let web = view.web
            switch event {
            case WPE.loadStarted: web.navigationFailed = false
            case WPE.loadFinished: web.loadFinished = true
            default: break
            }
            guard let delegate = view.delegate() else { return }
            if event == WPE.loadStarted, delegate.responds(to: "webViewDidStartLoad:") { delegate.sendWebViewDidStartLoad(view) }
            // WebKit finishes a failed load too; the delegate heard it fail.
            if event == WPE.loadFinished, !web.navigationFailed, delegate.responds(to: "webViewDidFinishLoad:") {
                delegate.sendWebViewDidFinishLoad(view)
            }
        }
        page.loadFailed = { _, domain, code, _ in
            let view = UIWebView(objcObject: object, ownership: .retain)
            view.web.navigationFailed = true
            guard let delegate = view.delegate(), delegate.responds(to: "webView:didFailLoadWithError:") else { return }
            delegate.sendDidFailLoad(view, WebErrors.loading(domain: domain, code: code))
        }
        return page
    }

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
    @ObjCMethod("webView:didFailLoadWithError:") func sendDidFailLoad(_ view: UIView, _ error: NSObject)
    @ObjCMethod("webView:shouldStartLoadWithRequest:navigationType:")
    func sendShouldStartLoad(_ view: UIView, _ request: NSObject, _ type: Int) -> Bool
}

@ObjCWrapper("NSURLRequest")
class NSURLRequestFactory: NSObject {
    @ObjCClassMethod("requestWithURL:") static func make(url: NSObject) -> NSObject
}

/// WKWebView: a page of WPE WebKit's, shown as the view's layer's contents
/// and sized with it. Without WPE it takes its loads and shows nothing.
@ObjCClass("WKWebView")
open class WKWebView: UIView {
    static let webStates = StateTable<WebViewState>()
    var web: WebViewState { WKWebView.webStates[objcObject] }

    @ObjCMethod("dealloc")
    override func dealloc() {
        WebViews.live.removeAll { $0.object == objcObject }
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
        guard let page = page() else { return WebNavigations.start(self, failing: nil) }
        // WebKit's base for a page without one.
        page.loadHTML(html ?? "", baseURI: baseURL?.sendAbsoluteString() ?? "about:blank")
        return WebViews.begin(self)
    }
    @ObjCMethod("loadRequest:") func loadRequest(_ request: NSObject?) -> NSObject? {
        web.request = request
        let url = request?.unsafeCast(to: NSURLRequestObject.self).url()
        guard let page = page(), let uri = url?.sendAbsoluteString() else {
            return WebNavigations.start(self, failing: WebNavigations.isNetwork(url) ? WebErrors.offline() : nil)
        }
        page.loadURI(uri)
        return WebViews.begin(self)
    }
    @ObjCMethod("loadFileURL:allowingReadAccessToURL:")
    func loadFileURL(_ url: NSObject?, allowingReadAccessTo directory: NSObject?) -> NSObject? {
        guard let page = page(), let uri = url?.sendAbsoluteString() else { return WebNavigations.start(self, failing: nil) }
        page.loadURI(uri)
        return WebViews.begin(self)
    }
    @ObjCMethod("loadData:MIMEType:characterEncodingName:baseURL:")
    func loadData(_ data: NSObject?, mimeType: String?, encoding: String?, baseURL: NSObject?) -> NSObject? {
        WebNavigations.start(self, failing: nil)
    }
    @ObjCMethod("customUserAgent") func customUserAgent() -> String? { web.customUserAgent }
    @ObjCMethod("setCustomUserAgent:") func setCustomUserAgent(_ agent: String?) {
        web.customUserAgent = agent
        web.page?.setUserAgent(agent)
    }
    @ObjCMethod("allowsBackForwardNavigationGestures") func allowsBackForwardNavigationGestures() -> Bool { false }
    @ObjCMethod("setAllowsBackForwardNavigationGestures:") func setAllowsBackForwardNavigationGestures(_ allows: Bool) {}
    @ObjCMethod("allowsLinkPreview") func allowsLinkPreview() -> Bool { false }
    @ObjCMethod("setAllowsLinkPreview:") func setAllowsLinkPreview(_ allows: Bool) {}
    @ObjCMethod("isInspectable") func isInspectable() -> Bool { false }
    @ObjCMethod("setInspectable:") func setInspectable(_ inspectable: Bool) {}
    @ObjCMethod("URL") func url() -> NSObject? {
        guard let uri = web.page?.uri else { return nil }
        return NSURLObject.make(string: uri)
    }
    /// Empty until the page has one, as WebKit's.
    @ObjCMethod("title") func title() -> String? { web.page?.title ?? "" }
    @ObjCMethod("isLoading") func isLoading() -> Bool { web.page?.isLoading ?? false }
    @ObjCMethod("estimatedProgress") func estimatedProgress() -> Double { web.page?.progress ?? 1 }
    @ObjCMethod("canGoBack") func canGoBack() -> Bool { web.page?.canGoBack ?? false }
    @ObjCMethod("canGoForward") func canGoForward() -> Bool { web.page?.canGoForward ?? false }
    @ObjCMethod("goBack") func goBack() -> NSObject? {
        guard let page = web.page, page.canGoBack else { return nil }
        page.goBack()
        return WebViews.begin(self)
    }
    @ObjCMethod("goForward") func goForward() -> NSObject? {
        guard let page = web.page, page.canGoForward else { return nil }
        page.goForward()
        return WebViews.begin(self)
    }
    @ObjCMethod("reload") func reload() -> NSObject? {
        guard let page = web.page else { return nil }
        page.reload()
        return WebViews.begin(self)
    }
    @ObjCMethod("stopLoading") func stopLoading() { web.page?.stopLoading() }
    @ObjCMethod("scrollView") func scrollView() -> NSObject? { nil }

    /// The script's value, as WebKit gives it: strings, numbers, Booleans,
    /// arrays and dictionaries as Foundation's, NSNull for null and nil for
    /// undefined.
    @ObjCMethod("evaluateJavaScript:completionHandler:") func evaluateJavaScript(_ script: String?, completionHandler: ObjCBlock?) {
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
        guard let page = page() else {
            guard let completionHandler else { return }
            Updates.afterPass {
                completionHandler.function(as: Invoke.self)(completionHandler.object, nil, WebErrors.noScript().objcObject)
            }
            return
        }
        page.evaluate(script ?? "") { result in
            guard let completionHandler else { return }
            switch result {
            case .success(let json):
                let value = json.flatMap(WebViews.object(json:))
                completionHandler.function(as: Invoke.self)(completionHandler.object, value?.objcObject, nil)
            case .failure:
                completionHandler.function(as: Invoke.self)(completionHandler.object, nil, WebErrors.exception().objcObject)
            }
        }
    }

    /// The last frame, as an image of the view's size.
    @ObjCMethod("takeSnapshotWithConfiguration:completionHandler:")
    func takeSnapshot(configuration: NSObject?, completionHandler: ObjCBlock?) {
        guard let completionHandler else { return }
        let object = objcObject
        let deliver = {
            let view = WKWebView(objcObject: object, ownership: .retain)
            let image = view.web.frameImage.map {
                UIImageFactory.make(cgImage: $0.object, scale: CGFloat(view.web.page?.scale ?? 1), orientation: 0)
            }
            typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
            completionHandler.function(as: Invoke.self)(completionHandler.object, image?.objcObject,
                                                        image == nil ? WebErrors.unknown().objcObject : nil)
        }
        guard let page = web.page else { return Updates.afterPass(deliver) }
        // The page is snapshotted once it has drawn what it has now, and a
        // page still loading once it has drawn after the load.
        page.afterRendering {
            let view = WKWebView(objcObject: object, ownership: .retain)
            if view.web.frameCurrent { deliver() } else { view.web.snapshotWaiters.append(deliver) }
        }
    }

    /// The view's page, made on its first load; nil without WPE.
    func page() -> WebPage? {
        if let page = web.page { return page }
        guard let page = makeWebPage(web) else { return nil }
        let object = objcObject
        page.loadChanged = { event in WebViews.loadChanged(object, event) }
        page.loadFailed = { committed, domain, code, message in
            WebViews.loadFailed(object, committed: committed, domain: domain, code: code, message: message)
        }
        // Key-value observers hear the properties WebKit's change.
        page.propertyChanged = { property in
            let keys: [String] = switch property {
            case "title": ["title"]
            case "uri": ["URL"]
            case "is-loading": ["loading", "canGoBack", "canGoForward"]
            case "estimated-load-progress": ["estimatedProgress"]
            default: []
            }
            let view = NSObject(object)
            for key in keys { view.sendWillChangeValue(forKey: key) }
            for key in keys.reversed() { view.sendDidChangeValue(forKey: key) }
        }
        return page
    }

    /// `functionBody` as an async function's body, its arguments as its
    /// variables; the handler hears what it returns, awaited, as
    /// evaluateJavaScript's does. Frames and content worlds are the page's.
    @ObjCMethod("callAsyncJavaScript:arguments:inFrame:inContentWorld:completionHandler:")
    func callAsyncJavaScript(_ body: String?, arguments: NSObject?, frame: NSObject?, world: NSObject?, completionHandler: ObjCBlock?) {
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
        guard let page = page() else {
            guard let completionHandler else { return }
            Updates.afterPass {
                completionHandler.function(as: Invoke.self)(completionHandler.object, nil, WebErrors.noScript().objcObject)
            }
            return
        }
        page.callAsync(WebViews.declaring(arguments) + (body ?? "")) { result in
            guard let completionHandler else { return }
            switch result {
            case .success(let json):
                let value = json.flatMap(WebViews.object(json:))
                completionHandler.function(as: Invoke.self)(completionHandler.object, value?.objcObject, nil)
            case .failure:
                completionHandler.function(as: Invoke.self)(completionHandler.object, nil, WebErrors.exception().objcObject)
            }
        }
    }
}

extension UIView {
    /// A page for a web view whose state is `web`, of the view's size,
    /// showing its frames as the view's layer's contents; nil without WPE.
    func makeWebPage(_ web: WebViewState) -> WebPage? {
        let size = state.bounds.size
        guard let page = WebPage(width: UInt32(max(size.width, 1)), height: UInt32(max(size.height, 1)), scale: Float(Screen.scale))
        else { return nil }
        web.page = page
        if let agent = web.customUserAgent { page.setUserAgent(agent) }
        let object = objcObject
        WebViews.live.append((object, web))
        WebPage.tick = WebViews.tick
        page.frame = { [unowned web] bytes, width, height, stride in
            UIView(objcObject: object, ownership: .retain).showWebFrame(web, bytes, width: width, height: height, stride: stride)
        }
        return page
    }

    /// A frame of the page's, as the layer's contents.
    func showWebFrame(_ web: WebViewState, _ bytes: UnsafeRawPointer, width: Int, height: Int, stride: Int) {
        guard let space = CG.colorSpaceCreateDeviceRGB() else { return }
        defer { CG.release(space) }
        // Wayland's ARGB8888: premultiplied, first byte blue.
        guard let context = CG.bitmapContextCreate(nil, width, height, 8, width * 4, space, 2 | 0x2000) else { return }
        defer { CG.release(context) }
        guard let data = CG.bitmapContextGetData(context) else { return }
        for row in 0..<height {
            (data + row * width * 4).copyMemory(from: bytes + row * stride, byteCount: width * 4)
        }
        guard let image = CG.bitmapContextCreateImage(context).map(Owned.init) else { return }
        web.frameImage = image
        state.layer.setContents(NSObject(image.object))
        state.layer.setContentsScale(CGFloat(web.page?.scale ?? 1))
        Display.markDirty()
        if web.loadFinished {
            web.frameCurrent = true
            let waiters = web.snapshotWaiters
            web.snapshotWaiters = []
            for waiter in waiters { waiter() }
        }
    }
}

/// The web views with pages, and their navigations.
enum WebViews {
    /// The views with pages, and their states.
    nonisolated(unsafe) static var live: [(object: UnsafeMutableRawPointer, web: WebViewState)] = []

    /// A navigation for the load just started, which the delegate's calls
    /// name until the next.
    static func begin(_ view: WKWebView) -> NSObject {
        let navigation = WKNavigation()
        view.web.navigation = navigation
        view.web.navigationFailed = false
        view.web.loadFinished = false
        view.web.frameCurrent = false
        return navigation
    }

    /// Pages follow their views' sizes.
    static func tick() {
        for (object, web) in live {
            guard let page = web.page else { continue }
            let size = UIView(objcObject: object, ownership: .retain).state.bounds.size
            page.resize(width: UInt32(max(size.width, 1)), height: UInt32(max(size.height, 1)), scale: Float(Screen.scale))
        }
    }

    static func loadChanged(_ object: UnsafeMutableRawPointer, _ event: Int32) {
        let view = WKWebView(objcObject: object, ownership: .retain)
        let state = view.web
        if event == WPE.loadFinished { state.loadFinished = true }
        guard let delegate = view.navigationDelegate() else { return }
        let navigation = state.navigation ?? WKNavigation()
        switch event {
        case WPE.loadStarted:
            if delegate.responds(to: "webView:didStartProvisionalNavigation:") { delegate.sendDidStartProvisionalNavigation(view, navigation) }
        case WPE.loadCommitted:
            if delegate.responds(to: "webView:didCommitNavigation:") { delegate.sendDidCommitNavigation(view, navigation) }
        case WPE.loadFinished:
            // WebKit finishes a failed load too; the delegate heard it fail.
            guard !state.navigationFailed else { return }
            if delegate.responds(to: "webView:didFinishNavigation:") { delegate.sendDidFinishNavigation(view, navigation) }
        default: break
        }
    }

    static func loadFailed(_ object: UnsafeMutableRawPointer, committed: Bool, domain: String, code: Int, message: String) {
        let view = WKWebView(objcObject: object, ownership: .retain)
        view.web.navigationFailed = true
        guard let delegate = view.navigationDelegate() else { return }
        let navigation = view.web.navigation ?? WKNavigation()
        let error = WebErrors.loading(domain: domain, code: code)
        if committed {
            if delegate.responds(to: "webView:didFailNavigation:withError:") { delegate.sendDidFailNavigation(view, navigation, error) }
        } else if delegate.responds(to: "webView:didFailProvisionalNavigation:withError:") {
            delegate.sendDidFailProvisionalNavigation(view, navigation, error)
        }
    }

    /// Declarations of a dictionary's entries as constants, for a function
    /// body: each value as a JavaScript literal.
    static func declaring(_ arguments: NSObject?) -> String {
        guard let arguments, arguments.sendCount() > 0 else { return "" }
        let keys = arguments.sendAllKeys()
        var declarations: [String] = []
        for index in 0..<keys.sendCount() {
            let key = keys.sendObject(at: index)
            let name = String(objCArgument: key.objcObject)
            declarations.append("\(name) = \(literal(arguments.sendObject(forKey: key)))")
        }
        return "const \(declarations.joined(separator: ", "));\n"
    }

    /// Foundation's strings, numbers, Booleans, arrays, dictionaries and
    /// NSNull as JavaScript; other objects as their descriptions' strings.
    static func literal(_ object: NSObject?) -> String {
        guard let object else { return "undefined" }
        func kind(_ name: String) -> Bool { ObjCRuntime.isKind(object.objcObject, of: ObjCRuntime.classObject(name)) }
        if kind("NSNull") { return "null" }
        if kind("NSString") { return quoted(String(objCArgument: object.objcObject)) }
        if kind("NSNumber") {
            // NSNumber's Booleans are 'c' (BOOL) numbers of CFBoolean's.
            if kind("__NSCFBoolean") || object.sendObjCType().map({ String(cString: $0) }) == "c" {
                return object.sendBoolValue() ? "true" : "false"
            }
            return object.sendStringValue()
        }
        if kind("NSArray") {
            return "[" + (0..<object.sendCount()).map { literal(object.sendObject(at: $0)) }.joined(separator: ", ") + "]"
        }
        if kind("NSDictionary") {
            let keys = object.sendAllKeys()
            return "{" + (0..<keys.sendCount()).map { index -> String in
                let key = keys.sendObject(at: index)
                return quoted(String(objCArgument: key.sendDescription().objcObject)) + ": " + literal(object.sendObject(forKey: key))
            }.joined(separator: ", ") + "}"
        }
        return quoted(String(objCArgument: object.sendDescription().objcObject))
    }

    /// A JavaScript string literal.
    static func quoted(_ string: String) -> String {
        var out = "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\u{2028}": out += "\\u2028"
            case "\u{2029}": out += "\\u2029"
            default:
                if scalar.value < 0x20 {
                    let hex = String(scalar.value, radix: 16)
                    out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

    /// A script's value from its JSON, fragments allowed.
    static func object(json: String) -> NSObject? {
        var text = json
        return text.withUTF8 { bytes -> NSObject? in
            guard let base = bytes.baseAddress else { return nil }
            let data = NSDataFactory.make(bytes: UnsafeRawPointer(base), length: UInt(bytes.count))
            return JSONSerializationObject.object(data: data, options: 4, error: nil)
        }
    }
}

@ObjCWrapper("NSURL")
class NSURLObject: NSObject {
    @ObjCClassMethod("URLWithString:") static func make(string: String) -> NSObject?
    @ObjCClassMethod("fileURLWithPath:") static func make(fileURLWithPath path: String) -> NSObject?
}

@ObjCWrapper("NSData")
class NSDataFactory: NSObject {
    @ObjCClassMethod("dataWithBytes:length:") static func make(bytes: UnsafeRawPointer, length: UInt) -> NSObject
}

@ObjCWrapper("NSJSONSerialization")
class JSONSerializationObject: NSObject {
    @ObjCClassMethod("JSONObjectWithData:options:error:")
    static func object(data: NSObject, options: UInt, error: UnsafeMutableRawPointer?) -> NSObject?
    @ObjCClassMethod("dataWithJSONObject:options:error:")
    static func data(object: NSObject, options: UInt, error: UnsafeMutableRawPointer?) -> NSObject?
}

@ObjCWrapper("UIImage")
class UIImageFactory: NSObject {
    @ObjCClassMethod("imageWithCGImage:scale:orientation:")
    static func make(cgImage: UnsafeMutableRawPointer?, scale: CGFloat, orientation: Int) -> NSObject
}

extension NSObject {
    @ObjCMethod("absoluteString") func sendAbsoluteString() -> String?
    @ObjCMethod("willChangeValueForKey:") func sendWillChangeValue(forKey key: String)
    @ObjCMethod("didChangeValueForKey:") func sendDidChangeValue(forKey key: String)
    @ObjCMethod("count") func sendCount() -> UInt
    @ObjCMethod("allKeys") func sendAllKeys() -> NSObject
    @ObjCMethod("objectAtIndex:") func sendObject(at index: UInt) -> NSObject
    @ObjCMethod("objectForKey:") func sendObject(forKey key: NSObject) -> NSObject?
    @ObjCMethod("objCType") func sendObjCType() -> UnsafePointer<CChar>?
    @ObjCMethod("boolValue") func sendBoolValue() -> Bool
    @ObjCMethod("stringValue") func sendStringValue() -> String
    @ObjCMethod("description") func sendDescription() -> NSObject
    @ObjCMethod("length") func sendLength() -> UInt
    @ObjCMethod("webView:didFailNavigation:withError:")
    func sendDidFailNavigation(_ view: NSObject, _ navigation: NSObject, _ error: NSObject)
}

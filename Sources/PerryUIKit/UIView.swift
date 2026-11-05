import CPerryGeometry
import Glibc
import PerryObjCInterop

// UIView: geometry, the view hierarchy with UIKit's callbacks, coordinate
// conversion, layout, drawing and the responder chain. Each view has a
// layer, made with the view, whose delegate it is; the view's geometry,
// visibility and opacity are the layer's, and its subviews' layers are
// the layer's sublayers in the same order.

final class ViewState: ObjectState {
    /// The view's layer, and its properties.
    var layer: CALayer!
    var geometry: LayerGeometry!
    var tag = 0
    var userInteractionEnabled = true
    var backgroundColor: UIColor?
    var tintColor: UIColor?
    /// UIViewContentMode: scale to fill 0.
    var contentMode = 0
    /// UISemanticContentAttribute: unspecified 0.
    var semanticContentAttribute = 0
    var autoresizingMask: UInt = 0
    var autoresizesSubviews = true
    var multipleTouchEnabled = false
    var exclusiveTouch = false
    var gestureRecognizers: [UIGestureRecognizer] = []
    var motionEffects: [NSObject] = []
    var constraints: [NSObject] = []
    var translatesAutoresizingMaskIntoConstraints = true
    /// Content hugging and compression resistance, per axis.
    var contentHuggingPriority = (width: Float(250), height: Float(250))
    var compressionResistancePriority = (width: Float(750), height: Float(750))
    var accessibilityIdentifier: String?
    var needsLayout = true
    /// The superview, which retains this view; not retained.
    var superview: UnsafeMutableRawPointer?
    var subviews: [UIView] = []
    /// The view controller whose view this is; not retained.
    var viewController: UnsafeMutableRawPointer?

    var center: CGPoint {
        get { geometry.position }
        set { geometry.position = newValue }
    }

    var bounds: CGRect {
        get { geometry.bounds }
        set { geometry.bounds = newValue }
    }

    var frame: CGRect {
        get { geometry.frame }
        set { geometry.frame = newValue }
    }

    var hidden: Bool {
        get { geometry.hidden }
        set { geometry.hidden = newValue }
    }

    var alpha: CGFloat {
        get { CGFloat(geometry.opacity) }
        set { geometry.opacity = Float(newValue) }
    }
}

/// The default size of views a controller makes for itself, and of
/// windows: an iPhone's screen, in points, at three pixels a point, held
/// as the app's Info.plist allows: in portrait, unless it supports only
/// landscape orientations.
enum Screen {
    /// UIInterfaceOrientation: portrait 1, landscape right 3, landscape left 4.
    nonisolated(unsafe) static let orientation: Int = {
        let bundle = NSBundle.main()
        let names = (bundle.infoObject(forKey: "UISupportedInterfaceOrientations~iphone")
            ?? bundle.infoObject(forKey: "UISupportedInterfaceOrientations"))?.as(NSArray.self)?.elements.map { $0.stringValue } ?? []
        if names.isEmpty || names.contains("UIInterfaceOrientationPortrait") { return 1 }
        for name in names {
            if name == "UIInterfaceOrientationLandscapeRight" { return 3 }
            if name == "UIInterfaceOrientationLandscapeLeft" { return 4 }
        }
        return 1
    }()

    static var isLandscape: Bool { orientation == 3 || orientation == 4 }

    /// With a live view, the screen is the display's own: its usable area,
    /// in points at the desktop's scale (one pixel a point unless it scales
    /// its display). PERRY_UIKIT_SCREEN=iphone keeps an iPhone's instead, as
    /// without a display.
    nonisolated(unsafe) static let nativeSize: CGSize? = {
        if let setting = getenv("PERRY_UIKIT_SCREEN"), String(cString: setting) == "iphone" { return nil }
        guard Display.wanted, let pixels = SDL.usableDisplaySize() else { return nil }
        let scale = max(Display.scale, 1)
        return CGSize(width: (pixels.width / scale).rounded(.down), height: (pixels.height / scale).rounded(.down))
    }()

    /// The screen's points; a resizable app's change with its window.
    nonisolated(unsafe) static var bounds = nativeSize.map { CGRect(origin: .zero, size: $0) }
        ?? (isLandscape ? CGRect(x: 0, y: 0, width: 844, height: 390) : CGRect(x: 0, y: 0, width: 390, height: 844))

    /// Whether the app runs in a window of any size, as an iPad app that
    /// supports multitasking does: it supports the iPad, both portrait and
    /// landscape, and does not require the full screen; or the screen is the
    /// display's. PERRY_UIKIT_RESIZABLE set to 1 or 0 decides it instead.
    nonisolated(unsafe) static let isResizable: Bool = {
        if let setting = getenv("PERRY_UIKIT_RESIZABLE") { return String(cString: setting) != "0" }
        // The display's screen is a desktop window's.
        if nativeSize != nil { return true }
        let bundle = NSBundle.main()
        let families = bundle.infoObject(forKey: "UIDeviceFamily")?.as(NSArray.self)?.elements.map { $0.sendIntegerValue() } ?? []
        guard families.contains(2) else { return false }
        if let required = bundle.infoObject(forKey: "UIRequiresFullScreen"), required.sendIntegerValue() != 0 { return false }
        let names = (bundle.infoObject(forKey: "UISupportedInterfaceOrientations~ipad")
            ?? bundle.infoObject(forKey: "UISupportedInterfaceOrientations"))?.as(NSArray.self)?.elements.map { $0.stringValue } ?? []
        let portrait = names.isEmpty || names.contains { $0.hasPrefix("UIInterfaceOrientationPortrait") }
        let landscape = names.isEmpty || names.contains { $0.hasPrefix("UIInterfaceOrientationLandscape") }
        return portrait && landscape
    }()

    /// The screen takes a new size: windows that filled it fill it again,
    /// their view hierarchies following by autoresizing and layout, and
    /// root view controllers hear of it first.
    static func resize(to size: CGSize) {
        let old = bounds
        guard size.width > 0, size.height > 0, size != old.size else { return }
        bounds = CGRect(origin: .zero, size: size)
        for window in Windows.all.map({ UIWindow(objcObject: $0, ownership: .retain) }) where window.state.frame == old {
            if let root = window.windowState.rootViewController, root.responds(to: "viewWillTransitionToSize:withTransitionCoordinator:") {
                root.sendViewWillTransition(to: size, with: nil)
            }
            window.sendSetFrame(bounds)
            window.setNeedsLayout()
        }
        Display.markDirty()
        Updates.schedule()
    }
    /// Pixels per point: the display's when the screen is the display's,
    /// else the iPhone's. Apps size what they draw from it (a game its
    /// renderbuffer and its interface), so an iPhone's screen keeps three
    /// whatever the live view's scale.
    nonisolated(unsafe) static let scale: CGFloat = nativeSize != nil ? max(Display.scale, 1) : 3
    /// One pixel of what is drawn: of the live view at its scale, else of
    /// the screen. Hairlines are a pixel thick, and layout rounds to
    /// pixels, so lines are not lost between them.
    static var pixel: CGFloat { 1 / (Display.isLive ? max(Display.scale, 1) : scale) }
    /// Under the home indicator, and under a status bar when
    /// PERRY_UIKIT_STATUS_BAR_HEIGHT gives it a height (47 on this
    /// iPhone); none is drawn, so by default it has none.
    /// In landscape, beside the sensor housing and above the home indicator.
    nonisolated(unsafe) static let safeAreaInsets: UIEdgeInsets = {
        // A window on a desktop has no sensor housing or home indicator.
        if isResizable { return UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0) }
        if isLandscape { return UIEdgeInsets(top: 0, left: 47, bottom: 21, right: 47) }
        let statusBar = getenv("PERRY_UIKIT_STATUS_BAR_HEIGHT").flatMap { Double(String(cString: $0)) } ?? 0
        return UIEdgeInsets(top: CGFloat(max(statusBar, 0)), left: 0, bottom: 34, right: 0)
    }()
}

/// A coordinate space: one with bounds that converts to and from others.
@ObjCProtocol("UICoordinateSpace")
protocol UICoordinateSpace {
    @ObjCRequired("bounds")
    func bounds() -> CGRect

    @ObjCRequired("convertPoint:toCoordinateSpace:")
    func convert(_ point: CGPoint, toCoordinateSpace space: NSObject) -> CGPoint

    @ObjCRequired("convertPoint:fromCoordinateSpace:")
    func convert(_ point: CGPoint, fromCoordinateSpace space: NSObject) -> CGPoint

    @ObjCRequired("convertRect:toCoordinateSpace:")
    func convert(_ rect: CGRect, toCoordinateSpace space: NSObject) -> CGRect

    @ObjCRequired("convertRect:fromCoordinateSpace:")
    func convert(_ rect: CGRect, fromCoordinateSpace space: NSObject) -> CGRect
}

@ObjCClass("UIView")
open class UIView: UIResponder, UICoordinateSpace {
    static let states = StateTable<ViewState>()

    /// The view's state, with its layer, made on first use.
    var state: ViewState {
        let state = UIView.states[objcObject]
        if state.layer == nil { makeLayer(state) }
        return state
    }

    static func state(of view: UnsafeMutableRawPointer) -> ViewState { wrap(view).state }

    static func wrap(_ object: UnsafeMutableRawPointer) -> UIView { UIView(objcObject: object, ownership: .retain) }

    /// A layer of the class's +layerClass, with the view as its delegate.
    private func makeLayer(_ state: ViewState) {
        let cls = NSObject(ObjCRuntime.objectClass(objcObject)!).sendLayerClass()
        let layer = cls.object.allocated().initializeLayer().unsafeCast(to: CALayer.self)
        state.layer = layer
        state.geometry = LayerGeometry(layer)
        layer.setDelegate(self)
        layer.setContentsScale(Screen.scale)
    }

    @ObjCClassMethod("layerClass") static func layerClass() -> ObjCClass { CALayer.objCClass }
    @ObjCMethod("layer") func layer() -> CALayer { state.layer }

    // MARK: Creating

    /// -init is -initWithFrame: with an empty frame, sent so a subclass's
    /// initializer runs.
    @ObjCMethod("init")
    func initialize() -> NSObject { initializeView(frame: .zero) }

    @ObjCMethod("initWithFrame:")
    func initialize(frame: CGRect) -> Self {
        setFrame(frame)
        return self
    }

    /// A view backed by `layer`, which it becomes the delegate of, in place
    /// of one of its +layerClass; its frame is the layer's.
    @ObjCMethod("_initWithLayer:")
    func initialize(layer: CALayer) -> Self {
        let state = UIView.states[objcObject]
        state.layer = layer
        state.geometry = LayerGeometry(layer)
        layer.setDelegate(self)
        return self
    }

    /// From a nib: the geometry, appearance and behavior Interface Builder
    /// set, the constraints, then the subviews.
    @ObjCMethod("initWithCoder:")
    func initialize(coder: NSObject) -> Self {
        let decoded = Coder(coder: coder)
        let state = state
        state.bounds = decoded.rect("UIBounds")
        state.center = decoded.point("UICenter")
        state.needsLayout = true
        if decoded.has("UIAlpha") { state.alpha = decoded.double("UIAlpha") }
        state.hidden = decoded.bool("UIHidden")
        state.tag = decoded.integer("UITag")
        state.geometry.isOpaque = decoded.bool("UIOpaque")
        state.geometry.masksToBounds = decoded.bool("UIClipsToBounds")
        state.autoresizingMask = UInt(bitPattern: decoded.integer("UIAutoresizingMask"))
        state.autoresizesSubviews = decoded.has("UIAutoresizeSubviews") ? decoded.bool("UIAutoresizeSubviews") : true
        state.contentMode = decoded.integer("UIContentMode")
        state.userInteractionEnabled = !decoded.bool("UIUserInteractionDisabled")
        state.multipleTouchEnabled = decoded.bool("UIMultipleTouchEnabled")
        state.tintColor = decoded.object("UITintColor")?.as(UIColor.self)
        if let color = decoded.object("UIBackgroundColor")?.as(UIColor.self) { setBackgroundColor(color) }
        state.translatesAutoresizingMaskIntoConstraints = !decoded.bool("UIViewDoesNotTranslateAutoresizingMaskIntoConstraints")
        state.constraints = decoded.array("UIViewAutolayoutConstraints")
        if let hugging = UIView.priorities(decoded.string("UIViewContentHuggingPriority")) { state.contentHuggingPriority = hugging }
        if let compression = UIView.priorities(decoded.string("UIViewContentCompressionResistancePriority")) {
            state.compressionResistancePriority = compression
        }
        for subview in decoded.array("UISubviews") {
            if let view = subview.as(UIView.self) { addSubview(view) }
        }
        return self
    }

    @ObjCMethod("awakeFromNib") func awakeFromNib() {}

    // MARK: Constraints, kept for Auto Layout

    @ObjCMethod("constraints") func constraints() -> NSObject { NSMutableArray.of(state.constraints) }
    @ObjCMethod("addConstraint:") func addConstraint(_ constraint: NSObject) { state.constraints.append(constraint); setNeedsLayout() }
    @ObjCMethod("addConstraints:") func addConstraints(_ constraints: NSArray) { state.constraints += constraints.elements; setNeedsLayout() }
    @ObjCMethod("removeConstraint:") func removeConstraint(_ constraint: NSObject) {
        state.constraints.removeAll { $0.objcObject == constraint.objcObject }
    }
    @ObjCMethod("removeConstraints:") func removeConstraints(_ constraints: NSArray) {
        let removed = Set(constraints.elements.map(\.objcObject))
        state.constraints.removeAll { removed.contains($0.objcObject) }
    }
    @ObjCMethod("translatesAutoresizingMaskIntoConstraints") func translatesAutoresizingMaskIntoConstraints() -> Bool {
        state.translatesAutoresizingMaskIntoConstraints
    }
    @ObjCMethod("setTranslatesAutoresizingMaskIntoConstraints:") func setTranslatesAutoresizingMaskIntoConstraints(_ translates: Bool) {
        state.translatesAutoresizingMaskIntoConstraints = translates
    }
    @ObjCMethod("setNeedsUpdateConstraints") func setNeedsUpdateConstraints() {}
    @ObjCMethod("updateConstraintsIfNeeded") func updateConstraintsIfNeeded() {}
    @ObjCMethod("updateConstraints") func updateConstraints() {}
    @ObjCMethod("needsUpdateConstraints") func needsUpdateConstraints() -> Bool { false }
    /// Every property animates inside an animation block.
    @ObjCMethod("_shouldAnimatePropertyWithKey:") func shouldAnimateProperty(withKey key: String?) -> Bool { true }
    /// The subviews put in their layers' order, after the sublayers were
    /// reordered directly (as SwiftUI does, then calls this): UIKit's
    /// subviews follow the layer tree.
    @ObjCMethod("_invalidateSubviewCache")
    func invalidateSubviewCache() {
        let state = state
        guard state.subviews.count > 1, let sublayers = state.layer.sublayers()?.elements else { return }
        var order: [UnsafeMutableRawPointer: Int] = [:]
        for (index, sublayer) in sublayers.enumerated() { order[sublayer.objcObject] = index }
        state.subviews = state.subviews.enumerated().sorted { lhs, rhs in
            let left = lhs.element.state.layer.map { order[$0.objcObject] ?? Int.max } ?? Int.max
            let right = rhs.element.state.layer.map { order[$0.objcObject] ?? Int.max } ?? Int.max
            return (left, lhs.offset) < (right, rhs.offset)
        }.map(\.element)
    }
    @ObjCMethod("_wantsConstraintBasedLayout") func wantsConstraintBasedLayout() -> Bool { !state.constraints.isEmpty }
    /// Alignment rects are frames: views have no alignment insets.
    @ObjCMethod("alignmentRectInsets") func alignmentRectInsets() -> UIEdgeInsets { UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0) }
    @ObjCMethod("frameForAlignmentRect:") func frame(forAlignmentRect rect: CGRect) -> CGRect { rect }
    @ObjCMethod("alignmentRectForFrame:") func alignmentRect(forFrame frame: CGRect) -> CGRect { frame }
    @ObjCMethod("invalidateIntrinsicContentSize") func invalidateIntrinsicContentSize() { setNeedsLayout(); superviewNeedsLayout() }
    @ObjCMethod("intrinsicContentSize") func intrinsicContentSizeOfView() -> CGSize { CGSize(width: -1, height: -1) }

    /// The width given, and the least height the constraints allow there.
    @ObjCMethod("systemLayoutSizeFittingSize:")
    func systemLayoutSizeFitting(_ size: CGSize) -> CGSize {
        let width = size.width > 0 ? size.width : state.bounds.width
        return CGSize(width: width, height: AutoLayout.fittingHeight(self, width: width) ?? state.bounds.height)
    }

    @ObjCMethod("systemLayoutSizeFittingSize:withHorizontalFittingPriority:verticalFittingPriority:")
    func systemLayoutSizeFitting(_ size: CGSize, horizontalPriority: Float, verticalPriority: Float) -> CGSize {
        systemLayoutSizeFitting(size)
    }

    /// UILayoutConstraintAxis: horizontal 0, vertical 1.
    @ObjCMethod("setContentHuggingPriority:forAxis:")
    func setContentHuggingPriority(_ priority: Float, for axis: Int) {
        if axis == 0 { state.contentHuggingPriority.width = priority } else { state.contentHuggingPriority.height = priority }
        superviewNeedsLayout()
    }
    @ObjCMethod("contentHuggingPriorityForAxis:")
    func contentHuggingPriority(for axis: Int) -> Float { axis == 0 ? state.contentHuggingPriority.width : state.contentHuggingPriority.height }
    @ObjCMethod("setContentCompressionResistancePriority:forAxis:")
    func setContentCompressionResistancePriority(_ priority: Float, for axis: Int) {
        if axis == 0 { state.compressionResistancePriority.width = priority } else { state.compressionResistancePriority.height = priority }
        superviewNeedsLayout()
    }
    @ObjCMethod("contentCompressionResistancePriorityForAxis:")
    func contentCompressionResistancePriority(for axis: Int) -> Float {
        axis == 0 ? state.compressionResistancePriority.width : state.compressionResistancePriority.height
    }

    /// A nib's priorities, "{horizontal, vertical}".
    static func priorities(_ text: String?) -> (width: Float, height: Float)? {
        guard let text else { return nil }
        let values = text.split(whereSeparator: { "{}, ".contains($0) }).compactMap { Float($0) }
        return values.count == 2 ? (values[0], values[1]) : nil
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        for subview in state.subviews { subview.state.superview = nil }
        state.layer.setDelegate(nil)
        UIView.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIView.objCClass.pointer)
    }

    // MARK: Geometry

    @ObjCMethod("frame") func frame() -> CGRect { state.frame }

    @ObjCMethod("setFrame:")
    func setFrame(_ frame: CGRect) {
        let state = state
        let size = state.bounds.size
        state.frame = frame
        state.needsLayout = true
        Updates.schedule()
        if state.bounds.size != size { boundsSizeChanged(from: size) }
    }

    @ObjCMethod("bounds") func bounds() -> CGRect { state.bounds }

    /// Keeps the center, so the frame grows or shrinks around it.
    @ObjCMethod("setBounds:")
    func setBounds(_ bounds: CGRect) {
        let state = state
        let size = state.bounds.size
        state.bounds = bounds
        state.needsLayout = true
        if state.bounds.size != size { boundsSizeChanged(from: size) }
    }

    /// A view that draws redraws at its new size, as with the redraw
    /// content mode; its subviews resize by their autoresizing masks.
    private func boundsSizeChanged(from size: CGSize) {
        let state = state
        if state.contentMode == 3 { state.geometry.needsDisplay = true }
        guard state.autoresizesSubviews else { return }
        let delta = CGSize(width: state.bounds.width - size.width, height: state.bounds.height - size.height)
        for subview in state.subviews where subview.state.autoresizingMask != 0 {
            let mask = subview.state.autoresizingMask, frame = subview.state.frame
            let (x, width) = Autoresizing.resize(frame.minX, frame.width, size.width - frame.maxX, by: delta.width,
                                                 flexible: (mask & 1 != 0, mask & 2 != 0, mask & 4 != 0))
            let (y, height) = Autoresizing.resize(frame.minY, frame.height, size.height - frame.maxY, by: delta.height,
                                                  flexible: (mask & 8 != 0, mask & 16 != 0, mask & 32 != 0))
            let resized = CGRect(x: x, y: y, width: width, height: height)
            if resized != frame { subview.sendSetFrame(resized) }
        }
    }

    @ObjCMethod("transform") func transform() -> CGAffineTransform { state.geometry.transform }
    @ObjCMethod("setTransform:") func setTransform(_ transform: CGAffineTransform) { state.geometry.transform = transform }

    @ObjCMethod("center") func center() -> CGPoint { state.center }
    @ObjCMethod("setCenter:") func setCenter(_ center: CGPoint) { state.center = center }

    // MARK: Appearance

    /// The device's, for every view.
    @ObjCMethod("traitCollection") func traitCollection() -> UITraitCollection { UITraitCollection.device() }

    @ObjCMethod("isHidden") func isHidden() -> Bool { state.hidden }
    /// A stack view closes up around an arranged subview that hides. As
    /// with the other changes that show, the next update pass draws it.
    @ObjCMethod("setHidden:")
    func setHidden(_ hidden: Bool) {
        guard hidden != state.hidden else { return }
        state.hidden = hidden
        Updates.schedule()
        if let superview = state.superview, ObjCRuntime.isKind(superview, of: UIStackView.objCClass.pointer) {
            UIView.wrap(superview).unsafeCast(to: UIStackView.self).arrangementChanged()
        }
    }
    @ObjCMethod("alpha") func alpha() -> CGFloat { state.alpha }
    @ObjCMethod("setAlpha:")
    func setAlpha(_ alpha: CGFloat) {
        state.alpha = alpha
        Updates.schedule()
    }
    @ObjCMethod("backgroundColor") func backgroundColor() -> UIColor? { state.backgroundColor }

    @ObjCMethod("setBackgroundColor:")
    func setBackgroundColor(_ color: UIColor?) {
        let state = state
        state.backgroundColor = color
        state.geometry.backgroundColor = color?.sendCGColor()
    }

    /// Pixels per point of the layer's content.
    @ObjCMethod("contentScaleFactor") func contentScaleFactor() -> CGFloat { state.geometry.contentsScale }

    @ObjCMethod("setContentScaleFactor:")
    func setContentScaleFactor(_ scale: CGFloat) {
        state.geometry.contentsScale = scale
        state.geometry.needsDisplay = true
    }

    @ObjCMethod("clipsToBounds") func clipsToBounds() -> Bool { state.geometry.masksToBounds }
    @ObjCMethod("setClipsToBounds:") func setClipsToBounds(_ clips: Bool) { state.geometry.masksToBounds = clips }
    @ObjCMethod("isOpaque") func isOpaque() -> Bool { state.geometry.isOpaque }
    @ObjCMethod("setOpaque:") func setOpaque(_ opaque: Bool) { state.geometry.isOpaque = opaque }
    @ObjCMethod("contentMode") func contentMode() -> Int { state.contentMode }
    @ObjCMethod("setContentMode:") func setContentMode(_ mode: Int) { state.contentMode = mode }
    @ObjCMethod("semanticContentAttribute") func semanticContentAttribute() -> Int { state.semanticContentAttribute }
    @ObjCMethod("setSemanticContentAttribute:") func setSemanticContentAttribute(_ attribute: Int) { state.semanticContentAttribute = attribute }
    @ObjCMethod("effectiveUserInterfaceLayoutDirection") func effectiveUserInterfaceLayoutDirection() -> Int { state.semanticContentAttribute == 4 ? 1 : 0 }
    @ObjCMethod("autoresizingMask") func autoresizingMask() -> UInt { state.autoresizingMask }
    @ObjCMethod("setAutoresizingMask:") func setAutoresizingMask(_ mask: UInt) { state.autoresizingMask = mask }
    @ObjCMethod("autoresizesSubviews") func autoresizesSubviews() -> Bool { state.autoresizesSubviews }
    @ObjCMethod("setAutoresizesSubviews:") func setAutoresizesSubviews(_ autoresizes: Bool) { state.autoresizesSubviews = autoresizes }
    @ObjCMethod("isMultipleTouchEnabled") func isMultipleTouchEnabled() -> Bool { state.multipleTouchEnabled }
    @ObjCMethod("setMultipleTouchEnabled:") func setMultipleTouchEnabled(_ enabled: Bool) { state.multipleTouchEnabled = enabled }
    @ObjCMethod("isExclusiveTouch") func isExclusiveTouch() -> Bool { state.exclusiveTouch }
    @ObjCMethod("setExclusiveTouch:") func setExclusiveTouch(_ exclusive: Bool) { state.exclusiveTouch = exclusive }

    /// The view's tint color, else its superview's, else the system blue.
    @ObjCMethod("tintColor")
    func tintColor() -> UIColor {
        var current: UnsafeMutableRawPointer? = objcObject
        while let view = current {
            let state = UIView.states[view]
            if let tint = state.tintColor { return tint }
            current = state.superview
        }
        return UIColor.systemBlue()
    }

    /// The view and those under it that take its tint hear of the change.
    @ObjCMethod("setTintColor:")
    func setTintColor(_ color: UIColor?) {
        state.tintColor = color
        UIView.tintChanged(self)
    }

    private static func tintChanged(_ view: UIView) {
        view.sendTintColorDidChange()
        for subview in view.state.subviews where subview.state.tintColor == nil { tintChanged(subview) }
    }

    @ObjCMethod("tintColorDidChange") func tintColorDidChange() {}
    @ObjCMethod("tag") func tag() -> Int { state.tag }
    @ObjCMethod("setTag:") func setTag(_ tag: Int) { state.tag = tag }
    @ObjCMethod("isUserInteractionEnabled") func isUserInteractionEnabled() -> Bool { state.userInteractionEnabled }
    @ObjCMethod("setUserInteractionEnabled:") func setUserInteractionEnabled(_ enabled: Bool) {
        state.userInteractionEnabled = enabled
    }
    @ObjCMethod("accessibilityIdentifier") func accessibilityIdentifier() -> String? { state.accessibilityIdentifier }
    @ObjCMethod("setAccessibilityIdentifier:") func setAccessibilityIdentifier(_ identifier: String?) {
        state.accessibilityIdentifier = identifier
    }

    // MARK: Hierarchy

    @ObjCMethod("superview") func superview() -> UIView? { state.superview.map(UIView.wrap) }
    @ObjCMethod("subviews") func subviews() -> NSObject { NSMutableArray.of(state.subviews) }

    /// The window the view is in: the nearest UIWindow at or above it.
    @ObjCMethod("window")
    func window() -> UIView? { windowObject.map(UIView.wrap) }

    var windowObject: UnsafeMutableRawPointer? {
        var current: UnsafeMutableRawPointer? = objcObject
        while let view = current {
            if UIView.wrap(view).is(UIWindow.self) { return view }
            current = UIView.states[view].superview
        }
        return nil
    }

    @ObjCMethod("addSubview:")
    func addSubview(_ view: UIView) { insert(view, at: state.subviews.count) }

    @ObjCMethod("insertSubview:atIndex:")
    func insertSubview(_ view: UIView, at index: Int) { insert(view, at: index) }

    @ObjCMethod("insertSubview:belowSubview:")
    func insertSubview(_ view: UIView, below sibling: UIView?) {
        insert(view, at: sibling.flatMap(index(of:)) ?? 0)
    }

    @ObjCMethod("insertSubview:aboveSubview:")
    func insertSubview(_ view: UIView, above sibling: UIView?) {
        insert(view, at: sibling.flatMap(index(of:)).map { $0 + 1 } ?? state.subviews.count)
    }

    @ObjCMethod("bringSubviewToFront:")
    func bringSubviewToFront(_ view: UIView) {
        guard let index = index(of: view) else { return }
        state.subviews.append(state.subviews.remove(at: index))
        placeLayer(of: view)
    }

    @ObjCMethod("sendSubviewToBack:")
    func sendSubviewToBack(_ view: UIView) {
        guard let index = index(of: view) else { return }
        state.subviews.insert(state.subviews.remove(at: index), at: 0)
        placeLayer(of: view)
    }

    @ObjCMethod("exchangeSubviewAtIndex:withSubviewAtIndex:")
    func exchangeSubview(at first: Int, withSubviewAt second: Int) {
        let subviews = state.subviews
        guard subviews.indices.contains(first), subviews.indices.contains(second) else { return }
        state.subviews.swapAt(first, second)
        placeLayer(of: subviews[first])
        placeLayer(of: subviews[second])
    }

    /// Puts a subview's layer among the layer's sublayers where the
    /// subview is among the subviews: below the next subview's layer.
    private func placeLayer(of view: UIView) {
        let subviews = state.subviews
        guard let index = index(of: view) else { return }
        let layer = state.layer!, sublayer = view.state.layer!
        if index + 1 < subviews.count {
            layer.insertSublayer(sublayer, below: subviews[index + 1].state.layer)
        } else {
            layer.addSublayer(sublayer)
        }
    }

    @ObjCMethod("removeFromSuperview")
    func removeFromSuperview() {
        guard let superviewObject = state.superview else { return }
        let superview = UIView.wrap(superviewObject)
        let window = windowObject
        superview.sendWillRemoveSubview(self)
        sendWillMoveToSuperview(nil)
        if window != nil { UIView.willMove(self, toWindow: nil) }
        superview.state.subviews.removeAll { $0.objcObject == objcObject }
        state.superview = nil
        state.layer.removeFromSuperlayer()
        if window != nil { UIView.didMoveToWindow(self) }
        sendDidMoveToSuperview()
        Updates.schedule()
    }

    /// Adds or moves `view` here, with UIKit's callbacks: the superview
    /// move, then the window move down the subtree, then the superview
    /// notified.
    private func insert(_ view: UIView, at index: Int) {
        guard view.objcObject != objcObject else { return }
        if view.state.superview == objcObject {
            guard let current = self.index(of: view) else { return }
            let moved = state.subviews.remove(at: current)
            state.subviews.insert(moved, at: min(max(index, 0), state.subviews.count))
            placeLayer(of: moved)
            return
        }
        let oldSuperview = view.state.superview.map(UIView.wrap)
        let oldWindow = view.windowObject, newWindow = windowObject
        oldSuperview?.sendWillRemoveSubview(view)
        view.sendWillMoveToSuperview(self)
        if oldWindow != newWindow { UIView.willMove(view, toWindow: newWindow) }
        oldSuperview?.state.subviews.removeAll { $0.objcObject == view.objcObject }
        state.subviews.insert(view, at: min(max(index, 0), state.subviews.count))
        view.state.superview = objcObject
        placeLayer(of: view)
        if oldWindow != newWindow { UIView.didMoveToWindow(view) }
        view.sendDidMoveToSuperview()
        sendDidAddSubview(view)
        setNeedsLayout()
    }

    private func index(of view: UIView) -> Int? {
        state.subviews.firstIndex { $0.objcObject == view.objcObject }
    }

    /// -willMoveToWindow: to a subtree, each view before its subviews.
    static func willMove(_ view: UIView, toWindow window: UnsafeMutableRawPointer?) {
        if let controller = view.state.viewController { UIViewController.wrap(controller).viewWillMove(toWindow: window) }
        view.sendWillMoveToWindow(window.map(UIView.wrap))
        for subview in view.state.subviews { willMove(subview, toWindow: window) }
    }

    /// -didMoveToWindow to a subtree, each view after its subviews.
    static func didMoveToWindow(_ view: UIView) {
        for subview in view.state.subviews { didMoveToWindow(subview) }
        view.sendDidMoveToWindow()
    }

    @ObjCMethod("viewWithTag:")
    func viewWithTag(_ tag: Int) -> UIView? {
        if state.tag == tag { return self }
        for subview in state.subviews {
            if let found = subview.viewWithTag(tag) { return found }
        }
        return nil
    }

    @ObjCMethod("isDescendantOfView:")
    func isDescendant(of view: UIView?) -> Bool {
        guard let view else { return false }
        var current: UnsafeMutableRawPointer? = objcObject
        while let candidate = current {
            if candidate == view.objcObject { return true }
            current = UIView.states[candidate].superview
        }
        return false
    }

    // The hierarchy's callbacks, for subclasses.
    @ObjCMethod("willMoveToSuperview:") func willMoveToSuperview(_ superview: UIView?) {}
    @ObjCMethod("didMoveToSuperview") func didMoveToSuperview() {}
    @ObjCMethod("willMoveToWindow:") func willMoveToWindow(_ window: UIView?) {}
    @ObjCMethod("didMoveToWindow") func didMoveToWindow() {}
    @ObjCMethod("didAddSubview:") func didAddSubview(_ subview: UIView) {}
    @ObjCMethod("willRemoveSubview:") func willRemoveSubview(_ subview: UIView) {}

    // MARK: Coordinates

    /// A point in this view's bounds, in its window's base coordinates.
    private func toBase(_ point: CGPoint) -> CGPoint {
        var point = point
        var current: UnsafeMutableRawPointer? = objcObject
        while let view = current {
            let state = UIView.state(of: view)
            guard let superview = state.superview else { break }
            let frame = state.frame
            point = CGPoint(x: point.x - state.bounds.origin.x + frame.origin.x,
                            y: point.y - state.bounds.origin.y + frame.origin.y)
            current = superview
        }
        return point
    }

    private func fromBase(_ point: CGPoint) -> CGPoint {
        let origin = toBase(.zero)
        return CGPoint(x: point.x - origin.x, y: point.y - origin.y)
    }

    @ObjCMethod("convertPoint:toView:")
    func convert(_ point: CGPoint, to view: UIView?) -> CGPoint {
        let base = toBase(point)
        return view?.fromBase(base) ?? base
    }

    @ObjCMethod("convertPoint:fromView:")
    func convert(_ point: CGPoint, from view: UIView?) -> CGPoint {
        fromBase(view?.toBase(point) ?? point)
    }

    @ObjCMethod("convertRect:toView:")
    func convert(_ rect: CGRect, to view: UIView?) -> CGRect {
        CGRect(origin: convert(rect.origin, to: view), size: rect.size)
    }

    @ObjCMethod("convertRect:fromView:")
    func convert(_ rect: CGRect, from view: UIView?) -> CGRect {
        CGRect(origin: convert(rect.origin, from: view), size: rect.size)
    }

    // UICoordinateSpace: another view's space, or else the window's.

    private func view(of space: NSObject) -> UIView? { space.as(UIView.self) }

    @ObjCMethod("convertPoint:toCoordinateSpace:")
    func convert(_ point: CGPoint, toCoordinateSpace space: NSObject) -> CGPoint { convert(point, to: view(of: space)) }

    @ObjCMethod("convertPoint:fromCoordinateSpace:")
    func convert(_ point: CGPoint, fromCoordinateSpace space: NSObject) -> CGPoint { convert(point, from: view(of: space)) }

    @ObjCMethod("convertRect:toCoordinateSpace:")
    func convert(_ rect: CGRect, toCoordinateSpace space: NSObject) -> CGRect { convert(rect, to: view(of: space)) }

    @ObjCMethod("convertRect:fromCoordinateSpace:")
    func convert(_ rect: CGRect, fromCoordinateSpace space: NSObject) -> CGRect { convert(rect, from: view(of: space)) }

    // MARK: Layout

    /// Marks the view, and has the next update pass lay it out, as Core
    /// Animation commits at the end of the run loop's turn: changes made
    /// from a timer or a message performed on the main thread show too.
    @ObjCMethod("setNeedsLayout")
    func setNeedsLayout() {
        state.needsLayout = true
        Updates.schedule()
    }

    /// A change to the view's intrinsic size: its superview lays it out
    /// again, and so does each ancestor whose layout solves the view, up
    /// through those constraints lay out.
    func superviewNeedsLayout() {
        var view = self
        while let superview = view.state.superview {
            let next = UIView.wrap(superview)
            next.state.needsLayout = true
            guard !next.state.translatesAutoresizingMaskIntoConstraints else { break }
            view = next
        }
        Updates.schedule()
    }

    /// Lays out the subtree's views that need it, each before its subviews.
    /// A controller's view is laid out between its controller's
    /// -viewWillLayoutSubviews and -viewDidLayoutSubviews.
    @ObjCMethod("layoutIfNeeded")
    func layoutIfNeeded() {
        if state.needsLayout {
            state.needsLayout = false
            let controller = state.viewController.map { NSObject($0) }
            controller?.sendViewWillLayoutSubviews()
            sendLayoutSubviews()
            controller?.sendViewDidLayoutSubviews()
        }
        for subview in state.subviews { subview.layoutIfNeeded() }
    }

    // MARK: Gesture recognizers

    /// UIKit's private notice of ancestors' geometry changes, which
    /// SwiftUI's hosting view asks for: views here are laid out anew each
    /// pass, so there is nothing to register.
    @ObjCMethod("_registerForGeometryChanges") func registerForGeometryChanges() {}
    @ObjCMethod("_unregisterForGeometryChanges") func unregisterForGeometryChanges() {}

    @ObjCMethod("gestureRecognizers")
    func gestureRecognizers() -> NSObject? { state.gestureRecognizers.isEmpty ? nil : NSMutableArray.of(state.gestureRecognizers) }

    @ObjCMethod("addGestureRecognizer:")
    func addGestureRecognizer(_ recognizer: UIGestureRecognizer) {
        if let old = recognizer.state.view, old != objcObject { UIView.wrap(old).removeGestureRecognizer(recognizer) }
        guard !state.gestureRecognizers.contains(where: { $0.objcObject == recognizer.objcObject }) else { return }
        state.gestureRecognizers.append(recognizer)
        recognizer.state.view = objcObject
    }

    @ObjCMethod("removeGestureRecognizer:")
    func removeGestureRecognizer(_ recognizer: UIGestureRecognizer) {
        state.gestureRecognizers.removeAll { $0.objcObject == recognizer.objcObject }
        if recognizer.state.view == objcObject { recognizer.state.view = nil }
    }

    // MARK: Safe area and margins

    /// The parts of the view under its window's unsafe edges and under the
    /// bars of the navigation controller its controller is in, plus its
    /// controller's additional insets.
    @ObjCMethod("safeAreaInsets")
    func safeAreaInsets() -> UIEdgeInsets { safeAreaInsets(ignoringController: false) }

    func safeAreaInsets(ignoringController: Bool) -> UIEdgeInsets {
        if self.is(UIWindow.self) { return Screen.safeAreaInsets }
        let state = state
        guard let superviewObject = state.superview, windowObject != nil else { return .zero }
        let superview = UIView.wrap(superviewObject)
        let safe = superview.state.bounds.inset(by: superview.safeAreaInsets(ignoringController: false))
        let frame = convert(state.bounds, to: superview)
        var insets = UIEdgeInsets(top: max(0, safe.minY - frame.minY), left: max(0, safe.minX - frame.minX),
                                  bottom: max(0, frame.maxY - safe.maxY), right: max(0, frame.maxX - safe.maxX))
        if !ignoringController, let controllerObject = state.viewController {
            let controller = UIViewController.wrap(controllerObject)
            if let parent = controller.state.parent, ObjCRuntime.isKind(parent, of: UINavigationController.objCClass.pointer) {
                let navigation = UINavigationController(objcObject: parent, ownership: .retain)
                let bar = navigation.navigationBar()
                if !navigation.navigation.barHidden, !bar.state.hidden, bar.windowObject != nil {
                    insets.top = max(insets.top, bar.convert(bar.state.bounds, to: self).maxY - state.bounds.minY)
                }
            }
            let extra = controller.state.additionalSafeAreaInsets
            insets = UIEdgeInsets(top: insets.top + extra.top, left: insets.left + extra.left,
                                  bottom: insets.bottom + extra.bottom, right: insets.right + extra.right)
        }
        return insets
    }

    @ObjCMethod("layoutMargins")
    func layoutMargins() -> UIEdgeInsets {
        let safe = safeAreaInsets()
        let side: CGFloat = state.viewController != nil ? 16 : 8
        return UIEdgeInsets(top: safe.top + 8, left: max(safe.left, side), bottom: safe.bottom + 8, right: max(safe.right, side))
    }

    @ObjCMethod("setLayoutMargins:") func setLayoutMargins(_ margins: UIEdgeInsets) {}
    @ObjCMethod("insetsLayoutMarginsFromSafeArea") func insetsLayoutMarginsFromSafeArea() -> Bool { true }
    @ObjCMethod("setInsetsLayoutMarginsFromSafeArea:") func setInsetsLayoutMarginsFromSafeArea(_ insets: Bool) {}
    @ObjCMethod("preservesSuperviewLayoutMargins") func preservesSuperviewLayoutMargins() -> Bool { false }
    @ObjCMethod("setPreservesSuperviewLayoutMargins:") func setPreservesSuperviewLayoutMargins(_ preserves: Bool) {}
    @ObjCMethod("safeAreaInsetsDidChange") func safeAreaInsetsDidChange() {}
    @ObjCMethod("layoutMarginsDidChange") func layoutMarginsDidChange() {}

    /// Subviews laid out by constraints get their frames.
    @ObjCMethod("layoutSubviews") func layoutSubviews() { AutoLayout.layOut(self) }

    /// A plain view fits its current size.
    @ObjCMethod("sizeThatFits:") func sizeThatFits(_ size: CGSize) -> CGSize { state.bounds.size }

    @ObjCMethod("sizeToFit")
    func sizeToFit() {
        let size = sendSizeThatFits(state.bounds.size)
        let frame = state.frame
        setFrame(CGRect(origin: frame.origin, size: size))
    }

    // MARK: Drawing

    /// Draws nothing; a subclass that implements it draws its layer's
    /// content.
    @ObjCMethod("drawRect:") func draw(_ rect: CGRect) {}

    @ObjCMethod("setNeedsDisplay")
    func setNeedsDisplay() {
        state.geometry.needsDisplay = true
        Updates.schedule()
    }

    @ObjCMethod("setNeedsDisplayInRect:") func setNeedsDisplay(in rect: CGRect) { setNeedsDisplay() }

    /// Whether the view draws its layer's content: its class has -drawRect:.
    @ObjCMethod("_perryDrawsLayer:")
    func drawsLayer(_ layer: NSObject) -> Bool { Methods.overrides(objcObject, "drawRect:", of: UIView.objCClass.pointer) }

    /// The animation for a change to the layer inside an animation block;
    /// outside one, none, as a view's layer does not animate by itself.
    @ObjCMethod("actionForLayer:forKey:")
    func action(for layer: NSObject, forKey key: String) -> NSObject? {
        ViewAnimations.action(forKey: key) ?? NSNull.null()
    }

    /// The layer's content: -drawRect: with the layer's context current.
    @ObjCMethod("drawLayer:inContext:")
    func drawLayer(_ layer: CALayer, in context: UnsafeMutableRawPointer?) {
        guard let context else { return }
        let bounds = state.bounds
        Graphics.drawing(in: context) { sendDraw(bounds) }
    }

    /// Renders the view's hierarchy, laid out, into the current context,
    /// scaled to `rect`.
    @ObjCMethod("drawViewHierarchyInRect:afterScreenUpdates:")
    func drawHierarchy(in rect: CGRect, afterScreenUpdates: Bool) -> Bool {
        guard let context = Graphics.current else { return false }
        layoutIfNeeded()
        let bounds = state.bounds
        CG.saveGState(context)
        CG.translateCTM(context, rect.minX, rect.minY)
        if bounds.width > 0, bounds.height > 0 { CG.scaleCTM(context, rect.width / bounds.width, rect.height / bounds.height) }
        CG.translateCTM(context, -bounds.minX, -bounds.minY)
        state.layer.render(in: context)
        CG.restoreGState(context)
        return true
    }

    // MARK: Hit testing

    /// The deepest visible, interactive descendant containing `point`,
    /// front to back.
    @ObjCMethod("hitTest:withEvent:")
    func hitTest(_ point: CGPoint, with event: NSObject?) -> UIView? {
        let state = state
        guard !state.hidden, state.userInteractionEnabled, state.alpha > 0.01, sendPointInside(point, with: event) else { return nil }
        for subview in state.subviews.reversed() {
            let local = subview.convert(point, from: self)
            if let hit = subview.sendHitTest(local, with: event) { return hit }
        }
        return self
    }

    @ObjCMethod("pointInside:withEvent:")
    func pointInside(_ point: CGPoint, with event: NSObject?) -> Bool { state.bounds.contains(point) }

    // MARK: Responder chain

    /// The view's controller, if it is a controller's view; otherwise the
    /// superview.
    @ObjCMethod("nextResponder")
    override func nextResponder() -> NSObject? {
        if let controller = state.viewController { return NSObject(controller) }
        return state.superview.map(UIView.wrap)
    }
}

/// Views UIKit puts between a window and its root view controller's view.
@ObjCClass("UITransitionView")
open class UITransitionView: UIView {}

@ObjCClass("UIDropShadowView")
open class UIDropShadowView: UIView {}

/// UIView's messages, sent so subclasses' overrides run.
extension NSObject {
    @ObjCMethod("initWithFrame:")
    func initializeView(frame: CGRect) -> NSObject

    @ObjCMethod("willMoveToSuperview:") func sendWillMoveToSuperview(_ superview: UIView?)
    @ObjCMethod("didMoveToSuperview") func sendDidMoveToSuperview()
    @ObjCMethod("willMoveToWindow:") func sendWillMoveToWindow(_ window: UIView?)
    @ObjCMethod("didMoveToWindow") func sendDidMoveToWindow()
    @ObjCMethod("didAddSubview:") func sendDidAddSubview(_ subview: UIView)
    @ObjCMethod("willRemoveSubview:") func sendWillRemoveSubview(_ subview: UIView)
    @ObjCMethod("layoutSubviews") func sendLayoutSubviews()
    @ObjCMethod("tintColorDidChange") func sendTintColorDidChange()
    @ObjCMethod("sizeThatFits:") func sendSizeThatFits(_ size: CGSize) -> CGSize
    @ObjCMethod("layerClass") func sendLayerClass() -> ObjCClass
    @ObjCMethod("drawRect:") func sendDraw(_ rect: CGRect)
    @ObjCMethod("hitTest:withEvent:") func sendHitTest(_ point: CGPoint, with event: NSObject?) -> UIView?
    @ObjCMethod("pointInside:withEvent:") func sendPointInside(_ point: CGPoint, with event: NSObject?) -> Bool
}

/// UIViewAutoresizing: a superview's change in size is shared among a
/// subview's flexible leading margin, size and trailing margin, in
/// proportion to their current lengths, or evenly when those are all zero.
enum Autoresizing {
    static func resize(_ leading: CGFloat, _ length: CGFloat, _ trailing: CGFloat, by delta: CGFloat,
                       flexible: (leading: Bool, length: Bool, trailing: Bool)) -> (CGFloat, CGFloat) {
        guard delta != 0 else { return (leading, length) }
        let parts = [(flexible.leading, max(leading, 0)), (flexible.length, max(length, 0)), (flexible.trailing, max(trailing, 0))]
        let count = parts.filter(\.0).count
        guard count > 0 else { return (leading, length) }
        let total = parts.reduce(0) { $0 + ($1.0 ? $1.1 : 0) }
        func share(_ part: (Bool, CGFloat)) -> CGFloat {
            guard part.0 else { return 0 }
            return total > 0 ? delta * part.1 / total : delta / CGFloat(count)
        }
        return (leading + share(parts[0]), max(length + share(parts[1]), 0))
    }
}

extension NSObject {
    @ObjCMethod("viewWillTransitionToSize:withTransitionCoordinator:")
    func sendViewWillTransition(to size: CGSize, with coordinator: NSObject?)
}

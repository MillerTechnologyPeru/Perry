import CPerryGeometry
import PerryObjCInterop

// NSView: a rectangle in its superview, in AppKit's coordinates (origin at
// the bottom left, y up, unless the view is flipped). Every view in a
// window is backed by a layer, made by -makeBackingLayer (a Metal view's
// CAMetalLayer) when the view first needs one, and QuartzCore composites
// the window's content view's layer tree. A layer's frame is its view's,
// flipped into the superlayer's top-left coordinates for a superview that
// isn't flipped. Changing a view's frame moves and resizes its layer and,
// by their autoresizing masks, its subviews. Views don't draw with
// -drawRect: here; their layers show what is set on them.

@ObjCClass("NSView")
open class NSView: NSResponder {
    var frame = CGRect.zero
    var boundsOrigin = CGPoint.zero
    var subviews: [NSView] = []
    /// Not retained.
    var superviewObject: UnsafeMutableRawPointer?
    /// Not retained.
    var windowObject: UnsafeMutableRawPointer?
    var layer: NSObject?
    var wantsLayer = false
    var hidden = false
    var autoresizingMask: UInt = 0
    var autoresizesSubviews = true
    var needsDisplay = false
    var needsLayout = false
    var alphaValue: CGFloat = 1
    var tag = -1
    var trackingAreas: [NSTrackingArea] = []
    var postsFrameChangedNotifications = true
    var postsBoundsChangedNotifications = true
    var identifier: String?
    var toolTip: String?
    var appearance: NSObject?
    var nextKeyView: NSObject?

    @ObjCMethod("init")
    public required init() { super.init() }

    @ObjCMethod("initWithFrame:")
    public required init(frame: CGRect) {
        super.init()
        self.frame = frame
    }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) { super.init() }

    deinit {
        for subview in subviews { subview.superviewObject = nil }
    }

    static func wrap(_ object: UnsafeMutableRawPointer) -> NSView { NSView.objCInstance(object, ownership: .retain) }

    var superview: NSView? { superviewObject.map(NSView.wrap) }
    var window: NSWindow? { windowObject.map(NSWindow.wrap) }
    var bounds: CGRect { CGRect(origin: boundsOrigin, size: frame.size) }
    /// -isFlipped, as the view's class answers.
    var flipped: Bool { Send.bool(objcObject, "isFlipped") }

    // MARK: Geometry

    @ObjCMethod("frame") func viewFrame() -> CGRect { frame }
    @ObjCMethod("bounds") func viewBounds() -> CGRect { bounds }
    @ObjCMethod("isFlipped") func isFlipped() -> Bool { false }
    @ObjCMethod("frameRotation") func frameRotation() -> CGFloat { 0 }

    /// Moves and resizes through -setFrameOrigin: and -setFrameSize:, which
    /// subclasses override.
    @ObjCMethod("setFrame:")
    func setFrame(_ frame: CGRect) {
        Send.void(objcObject, "setFrameOrigin:", point: frame.origin)
        Send.void(objcObject, "setFrameSize:", size: frame.size)
    }

    @ObjCMethod("setFrameOrigin:")
    func setFrameOrigin(_ origin: CGPoint) {
        guard origin != frame.origin else { return }
        frame.origin = origin
        updateLayerGeometry()
        postFrameChanged()
    }

    @ObjCMethod("setFrameSize:")
    func setFrameSize(_ size: CGSize) {
        let old = frame.size
        guard size != old else { return }
        frame.size = size
        updateLayerGeometry()
        if autoresizesSubviews {
            typealias F = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, CGSize) -> Void
            unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(objcObject, ObjCRuntime.selector("resizeSubviewsWithOldSize:"), old)
        }
        // Subviews' layers sit from the top: a height change moves them.
        for subview in subviews { subview.updateLayerGeometry() }
        needsLayout = true
        postFrameChanged()
    }

    @ObjCMethod("setBounds:")
    func setBounds(_ bounds: CGRect) {
        boundsOrigin = bounds.origin
        if bounds.size != frame.size { Send.void(objcObject, "setFrameSize:", size: bounds.size) }
    }
    @ObjCMethod("setBoundsOrigin:") func setBoundsOrigin(_ origin: CGPoint) { boundsOrigin = origin }
    @ObjCMethod("setBoundsSize:") func setBoundsSize(_ size: CGSize) { Send.void(objcObject, "setFrameSize:", size: size) }

    private func postFrameChanged() {
        if postsFrameChangedNotifications { post(Constants.NSViewFrameDidChangeNotification, object: self) }
    }

    @ObjCMethod("resizeSubviewsWithOldSize:")
    func resizeSubviews(withOldSize old: CGSize) {
        for subview in subviews {
            typealias F = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, CGSize) -> Void
            unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(subview.objcObject, ObjCRuntime.selector("resizeWithOldSuperviewSize:"), old)
        }
    }

    /// NSAutoresizingMaskOptions: min-x margin 1, width 2, max-x margin 4,
    /// min-y margin 8, height 16, max-y margin 32. The superview's change
    /// is shared among the flexible parts.
    @ObjCMethod("resizeWithOldSuperviewSize:")
    func resize(withOldSuperviewSize old: CGSize) {
        guard let superview, autoresizingMask != 0 else { return }
        let new = superview.frame.size
        func share(_ delta: CGFloat, _ parts: [Bool]) -> [CGFloat] {
            let count = parts.filter { $0 }.count
            return parts.map { $0 && count > 0 ? delta / CGFloat(count) : 0 }
        }
        let mask = autoresizingMask
        var frame = self.frame
        let x = share(new.width - old.width, [mask & 1 != 0, mask & 2 != 0, mask & 4 != 0])
        frame.origin.x += x[0]
        frame.size.width = max(0, frame.size.width + x[1])
        let y = share(new.height - old.height, [mask & 8 != 0, mask & 16 != 0, mask & 32 != 0])
        frame.origin.y += y[0]
        frame.size.height = max(0, frame.size.height + y[1])
        if frame != self.frame { Send.void(objcObject, "setFrame:", rect: frame) }
    }

    @ObjCMethod("autoresizingMask") func viewAutoresizingMask() -> UInt { autoresizingMask }
    @ObjCMethod("setAutoresizingMask:") func setAutoresizingMask(_ mask: UInt) { autoresizingMask = mask }
    @ObjCMethod("autoresizesSubviews") func viewAutoresizesSubviews() -> Bool { autoresizesSubviews }
    @ObjCMethod("setAutoresizesSubviews:") func setAutoresizesSubviews(_ value: Bool) { autoresizesSubviews = value }
    @ObjCMethod("translatesAutoresizingMaskIntoConstraints") func translatesAutoresizingMaskIntoConstraints() -> Bool { true }
    @ObjCMethod("setTranslatesAutoresizingMaskIntoConstraints:") func setTranslatesAutoresizingMaskIntoConstraints(_ value: Bool) {}
    @ObjCMethod("postsFrameChangedNotifications") func viewPostsFrameChanged() -> Bool { postsFrameChangedNotifications }
    @ObjCMethod("setPostsFrameChangedNotifications:") func setPostsFrameChangedNotifications(_ value: Bool) { postsFrameChangedNotifications = value }
    @ObjCMethod("setPostsBoundsChangedNotifications:") func setPostsBoundsChangedNotifications(_ value: Bool) { postsBoundsChangedNotifications = value }

    @ObjCMethod("visibleRect") func visibleRect() -> CGRect { bounds }
    @ObjCMethod("isHidden") func isHidden() -> Bool { hidden }
    @ObjCMethod("isHiddenOrHasHiddenAncestor") func isHiddenOrHasHiddenAncestor() -> Bool { hidden || (superview?.isHiddenOrHasHiddenAncestor() ?? false) }

    @ObjCMethod("setHidden:")
    func setHidden(_ hidden: Bool) {
        self.hidden = hidden
        layer.map { CALayer(objcObject: $0.objcObject, ownership: .retain).setHidden(hidden) }
    }

    @ObjCMethod("alphaValue") func viewAlphaValue() -> CGFloat { alphaValue }
    @ObjCMethod("setAlphaValue:") func setAlphaValue(_ alpha: CGFloat) { alphaValue = alpha }
    @ObjCMethod("isOpaque") func isOpaque() -> Bool { false }
    @ObjCMethod("tag") func viewTag() -> Int { tag }
    @ObjCMethod("setTag:") func setTag(_ tag: Int) { self.tag = tag }
    @ObjCMethod("identifier") func viewIdentifier() -> String? { identifier }
    @ObjCMethod("setIdentifier:") func setIdentifier(_ identifier: String?) { self.identifier = identifier }
    @ObjCMethod("toolTip") func viewToolTip() -> String? { toolTip }
    @ObjCMethod("setToolTip:") func setToolTip(_ toolTip: String?) { self.toolTip = toolTip }
    @ObjCMethod("appearance") func viewAppearance() -> NSObject? { appearance }
    @ObjCMethod("setAppearance:") func setAppearance(_ appearance: NSObject?) { self.appearance = appearance }
    @ObjCMethod("effectiveAppearance") func effectiveAppearance() -> NSObject? { appearance ?? superview?.effectiveAppearance() }
    @ObjCMethod("nextKeyView") func viewNextKeyView() -> NSObject? { nextKeyView }
    @ObjCMethod("setNextKeyView:") func setNextKeyView(_ view: NSObject?) { nextKeyView = view }
    @ObjCMethod("inLiveResize") func inLiveResize() -> Bool { false }
    @ObjCMethod("mouseDownCanMoveWindow") func mouseDownCanMoveWindow() -> Bool { false }
    @ObjCMethod("acceptsFirstMouse:") func acceptsFirstMouse(_ event: NSObject?) -> Bool { false }
    @ObjCMethod("needsPanelToBecomeKey") func needsPanelToBecomeKey() -> Bool { false }
    @ObjCMethod("allowedTouchTypes") func allowedTouchTypes() -> UInt { 1 }
    @ObjCMethod("setAllowedTouchTypes:") func setAllowedTouchTypes(_ types: UInt) {}
    @ObjCMethod("setWantsRestingTouches:") func setWantsRestingTouches(_ wants: Bool) {}
    @ObjCMethod("setFocusRingType:") func setFocusRingType(_ type: UInt) {}
    @ObjCMethod("userInterfaceLayoutDirection") func userInterfaceLayoutDirection() -> Int { 0 }
    @ObjCMethod("enclosingScrollView") func enclosingScrollView() -> NSObject? { nil }

    // MARK: The view hierarchy

    @ObjCMethod("superview") func viewSuperview() -> NSView? { superview }
    @ObjCMethod("window") func viewWindow() -> NSWindow? { window }
    @ObjCMethod("subviews") func viewSubviews() -> NSObject { NSMutableArray.of(subviews) }

    @ObjCMethod("setSubviews:")
    func setSubviews(_ views: NSObject?) {
        for subview in subviews { Send.void(subview.objcObject, "removeFromSuperview") }
        for object in views?.as(NSArray.self)?.elements ?? [] { Send.void(objcObject, "addSubview:", object.objcObject) }
    }

    @ObjCMethod("addSubview:")
    func addSubview(_ view: NSView) { insert(view, at: subviews.count) }

    /// NSWindowOrderingMode: above 1, below -1.
    @ObjCMethod("addSubview:positioned:relativeTo:")
    func addSubview(_ view: NSView, positioned place: Int, relativeTo other: NSView?) {
        guard let other, let index = subviews.firstIndex(where: { $0 === other }) else {
            insert(view, at: place == -1 ? 0 : subviews.count)
            return
        }
        insert(view, at: place == -1 ? index : index + 1)
    }

    private func insert(_ view: NSView, at index: Int) {
        if view.superviewObject == objcObject, let current = subviews.firstIndex(where: { $0 === view }) {
            subviews.remove(at: current)
        } else {
            view.detachFromSuperview()
            Send.void(view.objcObject, "viewWillMoveToSuperview:", objcObject)
        }
        let moving = view.windowObject != windowObject
        if moving { Send.void(view.objcObject, "viewWillMoveToWindow:", windowObject) }
        subviews.insert(view, at: min(index, subviews.count))
        view.superviewObject = objcObject
        view.nextResponderObject = objcObject
        view.setWindowTree(windowObject)
        if windowObject != nil || layer != nil {
            ensureLayer()
            view.attachLayer(to: self)
        }
        Send.void(view.objcObject, "viewDidMoveToSuperview")
        if moving { view.didMoveToWindowTree() }
        Windows.layersChanged()
    }

    @ObjCMethod("removeFromSuperview")
    func removeFromSuperview() {
        guard superviewObject != nil else { return }
        Send.void(objcObject, "viewWillMoveToSuperview:", nil)
        let hadWindow = windowObject != nil
        if hadWindow { Send.void(objcObject, "viewWillMoveToWindow:", nil) }
        detachFromSuperview()
        setWindowTree(nil)
        Send.void(objcObject, "viewDidMoveToSuperview")
        if hadWindow { didMoveToWindowTree() }
        Windows.layersChanged()
    }

    /// Out of its superview's subviews and its layer out of the superview's.
    private func detachFromSuperview() {
        guard let superview else { return }
        withExtendedLifetime(self) {
            superview.subviews.removeAll { $0 === self }
            superviewObject = nil
            if nextResponderObject == superview.objcObject { nextResponderObject = nil }
            layer.map { CALayer(objcObject: $0.objcObject, ownership: .retain).removeFromSuperlayer() }
        }
    }

    /// The window of this view and its subviews.
    func setWindowTree(_ window: UnsafeMutableRawPointer?) {
        windowObject = window
        for subview in subviews { subview.setWindowTree(window) }
    }

    /// -viewDidMoveToWindow down the tree, after the layers are in place.
    func didMoveToWindowTree() {
        if let window { layer.map { CALayer(objcObject: $0.objcObject, ownership: .retain).setContentsScale(window.backingScaleFactor()) } }
        Send.void(objcObject, "viewDidMoveToWindow")
        for subview in subviews { subview.didMoveToWindowTree() }
    }

    @ObjCMethod("viewWillMoveToWindow:") func viewWillMove(toWindow window: NSObject?) {}
    @ObjCMethod("viewDidMoveToWindow") func viewDidMoveToWindow() {}
    @ObjCMethod("viewWillMoveToSuperview:") func viewWillMove(toSuperview view: NSObject?) {}
    @ObjCMethod("viewDidMoveToSuperview") func viewDidMoveToSuperview() {}
    @ObjCMethod("viewDidChangeBackingProperties") func viewDidChangeBackingProperties() {}
    @ObjCMethod("viewDidHide") func viewDidHide() {}
    @ObjCMethod("viewDidUnhide") func viewDidUnhide() {}
    @ObjCMethod("didAddSubview:") func didAddSubview(_ view: NSObject?) {}
    @ObjCMethod("willRemoveSubview:") func willRemoveSubview(_ view: NSObject?) {}

    @ObjCMethod("isDescendantOf:")
    func isDescendant(of view: NSView?) -> Bool {
        guard let view else { return false }
        var current: NSView? = self
        while let candidate = current {
            if candidate === view { return true }
            current = candidate.superview
        }
        return false
    }

    @ObjCMethod("viewWithTag:")
    func view(withTag tag: Int) -> NSView? {
        if self.tag == tag { return self }
        for subview in subviews { if let found = subview.view(withTag: tag) { return found } }
        return nil
    }

    // MARK: Layers

    @ObjCMethod("wantsLayer") func viewWantsLayer() -> Bool { wantsLayer || layer != nil }

    @ObjCMethod("setWantsLayer:")
    func setWantsLayer(_ wants: Bool) {
        wantsLayer = wants
        if wants { ensureLayer() }
    }

    @ObjCMethod("layer") func viewLayer() -> NSObject? { layer }

    /// A layer-hosting view: the app's layer is the view's.
    @ObjCMethod("setLayer:")
    func setLayer(_ newLayer: NSObject?) {
        if let old = layer { CALayer(objcObject: old.objcObject, ownership: .retain).removeFromSuperlayer() }
        layer = newLayer
        guard newLayer != nil else { return }
        updateLayerGeometry()
        if let superview { superview.ensureLayer(); attachLayer(to: superview) }
        for subview in subviews { subview.ensureLayer(); subview.attachLayer(to: self) }
        Windows.layersChanged()
    }

    @ObjCMethod("makeBackingLayer") func makeBackingLayer() -> NSObject { CALayer.make() }
    @ObjCMethod("wantsUpdateLayer") func wantsUpdateLayer() -> Bool { false }
    @ObjCMethod("updateLayer") func updateLayer() {}
    @ObjCMethod("layerContentsRedrawPolicy") func layerContentsRedrawPolicy() -> Int { 1 }
    @ObjCMethod("setLayerContentsRedrawPolicy:") func setLayerContentsRedrawPolicy(_ policy: Int) {}
    @ObjCMethod("setLayerContentsPlacement:") func setLayerContentsPlacement(_ placement: Int) {}
    @ObjCMethod("setCanDrawSubviewsIntoLayer:") func setCanDrawSubviewsIntoLayer(_ value: Bool) {}
    @ObjCMethod("setWantsBestResolutionOpenGLSurface:") func setWantsBestResolutionOpenGLSurface(_ value: Bool) {}
    @ObjCMethod("wantsBestResolutionOpenGLSurface") func wantsBestResolutionOpenGLSurface() -> Bool { true }
    @ObjCMethod("setWantsExtendedDynamicRangeOpenGLSurface:") func setWantsEDROpenGLSurface(_ value: Bool) {}
    @ObjCMethod("setLayerUsesCoreImageFilters:") func setLayerUsesCoreImageFilters(_ value: Bool) {}

    /// The view's layer, made by -makeBackingLayer the first time.
    func ensureLayer() {
        guard layer == nil else { return }
        guard let made = Send.object(objcObject, "makeBackingLayer") else { return }
        layer = NSObject(made)
        let wrapped = CALayer(objcObject: made, ownership: .retain)
        if let window { wrapped.setContentsScale(window.backingScaleFactor()) }
        if hidden { wrapped.setHidden(true) }
        updateLayerGeometry()
        for subview in subviews {
            subview.ensureLayer()
            subview.attachLayer(to: self)
        }
    }

    /// Puts the layer in the superview's, in subview order.
    func attachLayer(to superview: NSView) {
        guard let layer, let superlayer = superview.layer,
              let index = superview.subviews.firstIndex(where: { $0 === self }) else { return }
        CATransaction.withoutActions {
            CALayer(objcObject: superlayer.objcObject, ownership: .retain).insertSublayer(layer, at: UInt32(index))
        }
        updateLayerGeometry()
    }

    /// The layer's frame, in its superlayer's top-left coordinates: the
    /// window's content view's fills the window.
    func updateLayerGeometry() {
        guard let layer else { return }
        let wrapped = CALayer(objcObject: layer.objcObject, ownership: .retain)
        var rect = frame
        if let superview {
            if !superview.flipped { rect.origin.y = superview.frame.height - frame.maxY }
            rect.origin.x -= superview.boundsOrigin.x
            rect.origin.y -= superview.boundsOrigin.y
        } else if windowObject != nil {
            rect.origin = .zero
        }
        CATransaction.withoutActions { wrapped.setFrame(rect) }
        Windows.layersChanged()
    }

    // MARK: Display and layout

    @ObjCMethod("needsDisplay") func viewNeedsDisplay() -> Bool { needsDisplay }
    @ObjCMethod("setNeedsDisplay:")
    func setNeedsDisplay(_ needs: Bool) {
        needsDisplay = needs
        if needs { Windows.layersChanged() }
    }
    @ObjCMethod("setNeedsDisplayInRect:") func setNeedsDisplay(in rect: CGRect) { setNeedsDisplay(true) }
    @ObjCMethod("display") func display() { needsDisplay = false }
    @ObjCMethod("displayIfNeeded") func displayIfNeeded() { needsDisplay = false }
    @ObjCMethod("drawRect:") func draw(_ rect: CGRect) {}
    @ObjCMethod("lockFocus") func lockFocus() {}
    @ObjCMethod("unlockFocus") func unlockFocus() {}
    @ObjCMethod("lockFocusIfCanDraw") func lockFocusIfCanDraw() -> Bool { false }
    @ObjCMethod("needsLayout") func viewNeedsLayout() -> Bool { needsLayout }
    @ObjCMethod("setNeedsLayout:") func setNeedsLayout(_ needs: Bool) { needsLayout = needs }
    @ObjCMethod("layout") func layout() {}
    @ObjCMethod("layoutSubtreeIfNeeded")
    func layoutSubtreeIfNeeded() {
        if needsLayout {
            needsLayout = false
            Send.void(objcObject, "layout")
        }
        for subview in subviews { subview.layoutSubtreeIfNeeded() }
    }
    @ObjCMethod("updateConstraints") func updateConstraints() {}
    @ObjCMethod("fittingSize") func fittingSize() -> CGSize { frame.size }
    @ObjCMethod("intrinsicContentSize") func intrinsicContentSize() -> CGSize { CGSize(width: -1, height: -1) }

    // MARK: Hit testing and conversion

    /// The deepest visible view at `point`, in the superview's coordinates.
    @ObjCMethod("hitTest:")
    func hitTest(_ point: CGPoint) -> NSView? {
        guard !hidden, frame.contains(point) else { return nil }
        let local = fromSuperview(point)
        for subview in subviews.reversed() {
            if let hit = Send.hitTest(subview.objcObject, local) { return NSView.wrap(hit) }
        }
        return self
    }

    @ObjCMethod("mouse:inRect:") func mouse(_ point: CGPoint, in rect: CGRect) -> Bool { rect.contains(point) }

    /// A point in this view's coordinates, in its superview's (or the
    /// window's, for a view without one), and back.
    func toSuperview(_ point: CGPoint) -> CGPoint {
        let superFlipped = superview?.flipped ?? false
        let x = frame.minX + point.x - boundsOrigin.x
        let local = point.y - boundsOrigin.y
        let y = flipped != superFlipped ? frame.minY + frame.height - local : frame.minY + local
        return CGPoint(x: x, y: y)
    }

    func fromSuperview(_ point: CGPoint) -> CGPoint {
        let superFlipped = superview?.flipped ?? false
        let x = point.x - frame.minX + boundsOrigin.x
        let y = flipped != superFlipped ? frame.minY + frame.height - point.y : point.y - frame.minY
        return CGPoint(x: x, y: y + boundsOrigin.y)
    }

    /// In the window's base coordinates.
    func toWindow(_ point: CGPoint) -> CGPoint {
        var point = point, view: NSView? = self
        while let current = view {
            point = current.toSuperview(point)
            view = current.superview
        }
        return point
    }

    func fromWindow(_ point: CGPoint) -> CGPoint {
        var chain: [NSView] = [], view: NSView? = self
        while let current = view {
            chain.append(current)
            view = current.superview
        }
        return chain.reversed().reduce(point) { $1.fromSuperview($0) }
    }

    private func convert(_ rect: CGRect, _ convert: (CGPoint) -> CGPoint) -> CGRect {
        let a = convert(rect.origin), b = convert(CGPoint(x: rect.maxX, y: rect.maxY))
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    @ObjCMethod("convertPoint:fromView:")
    func convert(_ point: CGPoint, from view: NSView?) -> CGPoint { fromWindow(view.map { $0.toWindow(point) } ?? point) }
    @ObjCMethod("convertPoint:toView:")
    func convert(_ point: CGPoint, to view: NSView?) -> CGPoint {
        let base = toWindow(point)
        return view.map { $0.fromWindow(base) } ?? base
    }
    @ObjCMethod("convertRect:fromView:")
    func convert(_ rect: CGRect, from view: NSView?) -> CGRect { convert(rect) { self.convert($0, from: view) } }
    @ObjCMethod("convertRect:toView:")
    func convert(_ rect: CGRect, to view: NSView?) -> CGRect { convert(rect) { self.convert($0, to: view) } }
    @ObjCMethod("convertSize:fromView:") func convert(_ size: CGSize, from view: NSView?) -> CGSize { size }
    @ObjCMethod("convertSize:toView:") func convert(_ size: CGSize, to view: NSView?) -> CGSize { size }

    var backingScale: CGFloat { window?.backingScaleFactor() ?? Screens.display.density }
    @ObjCMethod("convertRectToBacking:") func convertRectToBacking(_ rect: CGRect) -> CGRect { Backing.scale(rect, by: backingScale) }
    @ObjCMethod("convertRectFromBacking:") func convertRectFromBacking(_ rect: CGRect) -> CGRect { Backing.scale(rect, by: 1 / backingScale) }
    @ObjCMethod("convertPointToBacking:") func convertPointToBacking(_ point: CGPoint) -> CGPoint { Backing.scale(point, by: backingScale) }
    @ObjCMethod("convertPointFromBacking:") func convertPointFromBacking(_ point: CGPoint) -> CGPoint { Backing.scale(point, by: 1 / backingScale) }
    @ObjCMethod("convertSizeToBacking:") func convertSizeToBacking(_ size: CGSize) -> CGSize { Backing.scale(size, by: backingScale) }
    @ObjCMethod("convertSizeFromBacking:") func convertSizeFromBacking(_ size: CGSize) -> CGSize { Backing.scale(size, by: 1 / backingScale) }
    @ObjCMethod("backingAlignedRect:options:")
    func backingAlignedRect(_ rect: CGRect, options: UInt64) -> CGRect { Backing.aligned(rect, scale: backingScale) }

    // MARK: Tracking areas and cursor rectangles

    @ObjCMethod("addTrackingArea:") func addTrackingArea(_ area: NSTrackingArea) { trackingAreas.append(area) }
    @ObjCMethod("removeTrackingArea:") func removeTrackingArea(_ area: NSTrackingArea) { trackingAreas.removeAll { $0 === area } }
    @ObjCMethod("trackingAreas") func viewTrackingAreas() -> NSObject { NSMutableArray.of(trackingAreas) }
    @ObjCMethod("updateTrackingAreas") func updateTrackingAreas() {}
    @ObjCMethod("addCursorRect:cursor:") func addCursorRect(_ rect: CGRect, cursor: NSObject?) {}
    @ObjCMethod("removeCursorRect:cursor:") func removeCursorRect(_ rect: CGRect, cursor: NSObject?) {}
    @ObjCMethod("discardCursorRects") func discardCursorRects() {}
    @ObjCMethod("resetCursorRects") func resetCursorRects() {}

    /// Every view in the tree, depth first.
    var allViews: [NSView] { [self] + subviews.flatMap(\.allViews) }
}

/// NSTrackingArea: a view's rectangle and what its owner hears of the
/// mouse in it. NSTrackingAreaOptions: entered and exited 0x01, moved 0x02,
/// cursor update 0x04, in the visible rectangle 0x200.
@ObjCClass("NSTrackingArea")
open class NSTrackingArea: NSObject {
    var rect = CGRect.zero
    var options: UInt = 0
    /// Not retained, as AppKit's.
    var owner: UnsafeMutableRawPointer?
    var userInfo: NSObject?
    /// Whether the mouse was in it at the last motion.
    var inside = false

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithRect:options:owner:userInfo:")
    public required init(rect: CGRect, options: UInt, owner: NSObject?, userInfo: NSObject?) {
        super.init()
        self.rect = rect
        self.options = options
        self.owner = owner?.objcObject
        self.userInfo = userInfo
    }

    @ObjCMethod("rect") func areaRect() -> CGRect { rect }
    @ObjCMethod("options") func areaOptions() -> UInt { options }
    @ObjCMethod("owner") func areaOwner() -> NSObject? { owner.map(NSObject.init) }
    @ObjCMethod("userInfo") func areaUserInfo() -> NSObject? { userInfo }
}

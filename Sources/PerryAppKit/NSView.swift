import CPerryGeometry
import PerryObjCInterop

// NSView: a rectangle in its superview, in AppKit's coordinates (origin at
// the bottom left, y up, unless the view is flipped). Every view in a
// window is backed by a layer, made by -makeBackingLayer (a Metal view's
// CAMetalLayer) when the view first needs one, and QuartzCore composites
// the window's content view's layer tree. A layer's frame is its view's,
// flipped into the superlayer's top-left coordinates for a superview that
// isn't flipped. Changing a view's frame moves and resizes its layer and,
// by their autoresizing masks, its subviews. A view whose class draws
// (overrides -drawRect:) is its layer's delegate, and draws into the
// layer's bitmap with an NSGraphicsContext current, in its own coordinates,
// when it needs display. Views from nibs decode their frame, flags,
// subviews and constraints; a view's constraints lay out its subviews when
// it lays out (Layout.swift).

@ObjCClass("NSView")
open class NSView: NSResponder {
    var frame = CGRect.zero
    var boundsOrigin = CGPoint.zero
    var draggedTypes: NSObject?
    var constraintsNeedUpdate = true
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
    var needsLayout = false {
        didSet { if needsLayout { Layout.generation &+= 1 } }
    }
    var alphaValue: CGFloat = 1
    var tag = -1
    var trackingAreas: [NSTrackingArea] = []
    var postsFrameChangedNotifications = true
    var postsBoundsChangedNotifications = true
    var identifier: String?
    var toolTip: String?
    var appearance: NSObject?
    var nextKeyView: NSObject?
    var constraints: [NSLayoutConstraint] = []
    var translatesAutoresizingMask = true
    var gestureRecognizers: [NSObject] = []
    var hugging: [Float] = [250, 250]
    var compressionResistance: [Float] = [750, 750]

    public required init() { super.init() }

    /// -init is -initWithFrame: with an empty frame, sent so a subclass's
    /// -initWithFrame: runs, as Darwin's NSView does.
    @ObjCMethod("init")
    func initialize() -> NSObject { initializeView(frame: .zero) }

    @ObjCMethod("initWithFrame:")
    public required init(frame: CGRect) {
        super.init()
        self.frame = frame
    }

    /// NSView's archive: its frame ("NSFrame", or "NSFrameSize" at the
    /// origin), "NSvFlags" (the autoresizing mask in the low six bits,
    /// hidden in the top bit), "NSSubviews" and "NSViewConstraints".
    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init()
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        frame = NSView.frame(from: decoded)
        decodeContents(decoded)
    }

    static func frame(from coder: Coder) -> CGRect {
        coder.has("NSFrame") ? coder.rect("NSFrame") : CGRect(origin: .zero, size: coder.size("NSFrameSize"))
    }

    /// What a view's archive holds besides its frame.
    func decodeContents(_ decoded: Coder) {
        let flags = UInt32(truncatingIfNeeded: decoded.integer("NSvFlags"))
        autoresizingMask = UInt(flags & 0x3f)
        autoresizesSubviews = flags & 0x100 != 0 || !decoded.has("NSvFlags")
        hidden = flags & 0x8000_0000 != 0
        translatesAutoresizingMask = !decoded.bool("NSDoNotTranslateAutoresizingMask")
        if decoded.bool("NSViewIsLayerTreeHost") || decoded.bool("NSViewWantsLayer") { wantsLayer = true }
        identifier = decoded.string("NSUserInterfaceItemIdentifier") ?? decoded.string("NSViewIdentifier")
        toolTip = decoded.string("NSToolTip")
        if decoded.has("NSHuggingPriority") {
            let v = decoded.string("NSHuggingPriority").map(NSView.pair) ?? []
            if v.count == 2 { hugging = v }
        }
        if decoded.has("NSAntiCompressionPriority") {
            let v = decoded.string("NSAntiCompressionPriority").map(NSView.pair) ?? []
            if v.count == 2 { compressionResistance = v }
        }
        for subview in decoded.array("NSSubviews") {
            guard let view = subview.as(NSView.self) else { continue }
            addSubview(view)
        }
        for constraint in decoded.array("NSViewConstraints") {
            if let constraint = constraint.as(NSLayoutConstraint.self) { constraints.append(constraint) }
        }
        if !constraints.isEmpty { needsLayout = true }
        gestureRecognizers = decoded.array("NSGestureRecognizers")
    }

    /// "{250, 750}"
    private static func pair(_ text: String) -> [Float] {
        text.split(whereSeparator: { "{}, ".contains($0) }).compactMap { Float(String($0)) }
    }

    deinit {
        for subview in subviews { subview.superviewObject = nil }
        InputContexts.contexts[objcObject] = nil
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
        Layout.generation &+= 1
        updateLayerGeometry()
        postFrameChanged()
    }

    @ObjCMethod("setFrameSize:")
    func setFrameSize(_ size: CGSize) {
        let old = frame.size
        guard size != old else { return }
        frame.size = size
        updateLayerGeometry()
        if draws { setNeedsDisplay(true) }
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
        setBoundsOrigin(bounds.origin)
        if bounds.size != frame.size { Send.void(objcObject, "setFrameSize:", size: bounds.size) }
    }
    @ObjCMethod("setBoundsOrigin:")
    func setBoundsOrigin(_ origin: CGPoint) {
        guard origin != boundsOrigin else { return }
        boundsOrigin = origin
        for subview in subviews { subview.updateLayerGeometry() }
        if draws { setNeedsDisplay(true) }
        if postsBoundsChangedNotifications { post(Constants.NSViewBoundsDidChangeNotification, object: self) }
    }
    @ObjCMethod("setBoundsSize:") func setBoundsSize(_ size: CGSize) { Send.void(objcObject, "setFrameSize:", size: size) }

    private func postFrameChanged() {
        if postsFrameChangedNotifications { post(Constants.NSViewFrameDidChangeNotification, object: self) }
        // A clip view keeps showing its document as the document changes.
        if let clip = superview?.as(NSClipView.self), clip.documentView === self { clip.documentFrameChanged() }
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
    @ObjCMethod("translatesAutoresizingMaskIntoConstraints") func translatesAutoresizingMaskIntoConstraints() -> Bool { translatesAutoresizingMask }
    @ObjCMethod("setTranslatesAutoresizingMaskIntoConstraints:")
    func setTranslatesAutoresizingMaskIntoConstraints(_ value: Bool) {
        translatesAutoresizingMask = value
        superview?.needsLayout = true
    }
    @ObjCMethod("postsFrameChangedNotifications") func viewPostsFrameChanged() -> Bool { postsFrameChangedNotifications }
    @ObjCMethod("setPostsFrameChangedNotifications:") func setPostsFrameChangedNotifications(_ value: Bool) { postsFrameChangedNotifications = value }
    @ObjCMethod("setPostsBoundsChangedNotifications:") func setPostsBoundsChangedNotifications(_ value: Bool) { postsBoundsChangedNotifications = value }

    /// The part of the bounds its superviews (clip views) show.
    @ObjCMethod("visibleRect")
    func visibleRect() -> CGRect {
        guard let superview else { return bounds }
        let shown = superview.visibleRect()
        let mine = convert(shown, from: superview)
        let x0 = max(bounds.minX, mine.minX), y0 = max(bounds.minY, mine.minY)
        let x1 = min(bounds.maxX, mine.maxX), y1 = min(bounds.maxY, mine.maxY)
        return x1 > x0 && y1 > y0 ? CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0) : .zero
    }
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
    @ObjCMethod("effectiveAppearance")
    func effectiveAppearance() -> NSObject? {
        appearance ?? superview?.effectiveAppearance() ?? window?.effectiveAppearance() ?? App.shared?.effectiveAppearance() ?? NSAppearance.system
    }
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
    @ObjCMethod("enclosingScrollView")
    func enclosingScrollView() -> NSView? {
        var view = superview
        while let current = view {
            if current.is(NSScrollView.self) { return current }
            view = current.superview
        }
        return nil
    }
    @ObjCMethod("gestureRecognizers") func viewGestureRecognizers() -> NSObject { NSMutableArray.of(gestureRecognizers) }
    @ObjCMethod("setGestureRecognizers:") func setGestureRecognizers(_ value: NSObject?) { gestureRecognizers = value?.as(NSArray.self)?.elements ?? [] }
    @ObjCMethod("addGestureRecognizer:") func addGestureRecognizer(_ recognizer: NSObject?) { recognizer.map { gestureRecognizers.append($0) } }
    @ObjCMethod("removeGestureRecognizer:") func removeGestureRecognizer(_ recognizer: NSObject?) { gestureRecognizers.removeAll { $0 === recognizer } }
    @ObjCMethod("wantsDefaultClipping") func wantsDefaultClipping() -> Bool { true }
    @ObjCMethod("clipsToBounds") func clipsToBounds() -> Bool { false }
    @ObjCMethod("setClipsToBounds:") func setClipsToBounds(_ value: Bool) { layer.map { CALayer(objcObject: $0.objcObject, ownership: .retain).setMasksToBounds(value) } }
    @ObjCMethod("isRotatedFromBase") func isRotatedFromBase() -> Bool { false }
    @ObjCMethod("isRotatedOrScaledFromBase") func isRotatedOrScaledFromBase() -> Bool { false }
    @ObjCMethod("canDraw") func canDraw() -> Bool { windowObject != nil }
    @ObjCMethod("canBecomeKeyView") func canBecomeKeyView() -> Bool { Send.bool(objcObject, "acceptsFirstResponder") && !hidden }
    @ObjCMethod("previousKeyView") func previousKeyView() -> NSObject? { nil }
    @ObjCMethod("nextValidKeyView") func nextValidKeyView() -> NSObject? { nextKeyView }
    @ObjCMethod("setKeyboardFocusRingNeedsDisplayInRect:") func setKeyboardFocusRingNeedsDisplay(in rect: CGRect) {}
    @ObjCMethod("focusRingType") func focusRingType() -> UInt { 0 }
    @ObjCMethod("scrollPoint:")
    func scroll(_ point: CGPoint) {
        guard let clip = superview?.as(NSClipView.self) else { return }
        clip.scroll(to: clip.constrainBoundsRect(CGRect(origin: convert(point, to: clip), size: clip.bounds.size)).origin)
    }
    @ObjCMethod("scrollRectToVisible:")
    func scrollRectToVisible(_ rect: CGRect) -> Bool {
        guard let clip = superview?.as(NSClipView.self) else { return false }
        let target = convert(rect, to: clip)
        var origin = clip.bounds.origin
        if target.minX < clip.bounds.minX { origin.x = target.minX } else if target.maxX > clip.bounds.maxX { origin.x = target.maxX - clip.bounds.width }
        if target.minY < clip.bounds.minY { origin.y = target.minY } else if target.maxY > clip.bounds.maxY { origin.y = target.maxY - clip.bounds.height }
        guard origin != clip.bounds.origin else { return false }
        clip.scroll(to: clip.constrainBoundsRect(CGRect(origin: origin, size: clip.bounds.size)).origin)
        return true
    }
    @ObjCMethod("autoscroll:") func autoscroll(_ event: NSObject?) -> Bool { false }
    @ObjCMethod("enclosingMenuItem") func enclosingMenuItem() -> NSObject? { nil }
    @ObjCMethod("ancestorSharedWithView:")
    func ancestorShared(with view: NSView?) -> NSView? {
        var current: NSView? = self
        while let candidate = current {
            if let view, view.isDescendant(of: candidate) { return candidate }
            current = candidate.superview
        }
        return nil
    }

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
            // A view built apart from a window gets its layers now, its
            // subviews' with it.
            view.ensureLayer()
            view.attachLayer(to: self)
        }
        Send.void(view.objcObject, "viewDidMoveToSuperview")
        Send.void(objcObject, "didAddSubview:", view.objcObject)
        if moving { view.didMoveToWindowTree() }
        needsLayout = true
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
    @ObjCMethod("makeBackingLayerIfNeeded") func makeBackingLayerIfNeeded() { ensureLayer() }
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
        // A view that draws draws its layer, as its delegate.
        if draws {
            wrapped.setDelegate(self)
            wrapped.setNeedsDisplay()
        }
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
            // Scrolled by the superview's bounds origin: up a flipped view,
            // down one whose y axis points up.
            rect.origin.x -= superview.boundsOrigin.x
            rect.origin.y += superview.flipped ? -superview.boundsOrigin.y : superview.boundsOrigin.y
        } else if windowObject != nil {
            rect.origin = .zero
        }
        CATransaction.withoutActions {
            wrapped.setFrame(rect)
            // A layer's bounds start at the view's bounds origin, which a
            // clip view moves to scroll.
        }
        Windows.layersChanged()
    }

    // MARK: Display and layout

    @ObjCMethod("needsDisplay") func viewNeedsDisplay() -> Bool { needsDisplay }
    /// The view's text input context, for a view that adopts
    /// NSTextInputClient.
    @ObjCMethod("inputContext") func inputContext() -> NSTextInputContext? { InputContexts.context(for: self) }

    // Dragging: nothing is dragged between views or apps here, so the types
    // are kept only to be read back.
    @ObjCMethod("registerForDraggedTypes:") func registerForDraggedTypes(_ types: NSObject?) { draggedTypes = types }
    @ObjCMethod("unregisterDraggedTypes") func unregisterDraggedTypes() { draggedTypes = nil }
    @ObjCMethod("registeredDraggedTypes") func registeredDraggedTypes() -> NSObject { draggedTypes ?? NSMutableArray.empty() }

    @ObjCMethod("setNeedsDisplay:")
    func setNeedsDisplay(_ needs: Bool) {
        needsDisplay = needs
        guard needs else { return }
        if draws, let layer { CALayer(objcObject: layer.objcObject, ownership: .retain).setNeedsDisplay() }
        Windows.layersChanged()
    }
    @ObjCMethod("setNeedsDisplayInRect:") func setNeedsDisplay(in rect: CGRect) { setNeedsDisplay(true) }
    @ObjCMethod("display") func display() { setNeedsDisplay(true) }
    @ObjCMethod("displayIfNeeded") func displayIfNeeded() {}
    @ObjCMethod("displayRect:") func display(_ rect: CGRect) { setNeedsDisplay(true) }
    @ObjCMethod("displayIfNeededIgnoringOpacity") func displayIfNeededIgnoringOpacity() {}
    @ObjCMethod("drawRect:") func draw(_ rect: CGRect) {}
    @ObjCMethod("viewWillDraw") func viewWillDraw() {}
    @ObjCMethod("lockFocus") func lockFocus() {}
    @ObjCMethod("unlockFocus") func unlockFocus() {}
    @ObjCMethod("lockFocusIfCanDraw") func lockFocusIfCanDraw() -> Bool { false }
    @ObjCMethod("getRectsBeingDrawn:count:")
    func getRectsBeingDrawn(_ rects: UnsafeMutablePointer<UnsafePointer<CGRect>?>?, count: UnsafeMutablePointer<Int>?) {
        rects?.pointee = nil
        count?.pointee = 0
    }
    @ObjCMethod("needsToDrawRect:") func needsToDraw(_ rect: CGRect) -> Bool { true }
    @ObjCMethod("needsLayout") func viewNeedsLayout() -> Bool { needsLayout }
    @ObjCMethod("setNeedsLayout:")
    func setNeedsLayout(_ needs: Bool) {
        needsLayout = needs
        if needs { Windows.layersChanged() }
    }
    /// Lays out the subviews that constraints place.
    @ObjCMethod("layout") func layout() { Layout.apply(self) }
    @ObjCMethod("layoutSubtreeIfNeeded")
    func layoutSubtreeIfNeeded() {
        if needsLayout {
            needsLayout = false
            Send.void(objcObject, "layout")
        }
        for subview in subviews { subview.layoutSubtreeIfNeeded() }
    }
    /// Where a view adds the constraints it makes itself; subclasses call
    /// super's.
    @ObjCMethod("updateConstraints") func updateConstraints() {}
    /// The update pass before layout: subviews first, then the view, each
    /// once it needs it (as every view does at first).
    @ObjCMethod("updateConstraintsForSubtreeIfNeeded")
    func updateConstraintsForSubtreeIfNeeded() {
        for subview in subviews { Send.void(subview.objcObject, "updateConstraintsForSubtreeIfNeeded") }
        if constraintsNeedUpdate {
            constraintsNeedUpdate = false
            Send.void(objcObject, "updateConstraints")
            needsLayout = true
        }
    }
    @ObjCMethod("needsUpdateConstraints") func needsUpdateConstraints() -> Bool { constraintsNeedUpdate }
    @ObjCMethod("setNeedsUpdateConstraints:")
    func setNeedsUpdateConstraints(_ needs: Bool) {
        constraintsNeedUpdate = needs
        if needs {
            needsLayout = true
            Windows.layersChanged()
        }
    }
    @ObjCMethod("fittingSize") func fittingSize() -> CGSize { Layout.fittingSize(self) }
    @ObjCMethod("intrinsicContentSize") func intrinsicContentSize() -> CGSize { CGSize(width: -1, height: -1) }
    @ObjCMethod("invalidateIntrinsicContentSize") func invalidateIntrinsicContentSize() { superview?.setNeedsLayout(true) }
    @ObjCMethod("alignmentRectInsets") func alignmentRectInsets() -> NSEdgeInsets { NSEdgeInsets() }
    @ObjCMethod("baselineOffsetFromBottom") func baselineOffsetFromBottom() -> CGFloat { 0 }
    @ObjCMethod("firstBaselineOffsetFromTop") func firstBaselineOffsetFromTop() -> CGFloat { 0 }
    @ObjCMethod("contentHuggingPriorityForOrientation:")
    func contentHuggingPriority(for orientation: Int) -> Float { hugging[orientation == 1 ? 1 : 0] }
    @ObjCMethod("setContentHuggingPriority:forOrientation:")
    func setContentHuggingPriority(_ priority: Float, for orientation: Int) { hugging[orientation == 1 ? 1 : 0] = priority }
    @ObjCMethod("contentCompressionResistancePriorityForOrientation:")
    func contentCompressionResistancePriority(for orientation: Int) -> Float { compressionResistance[orientation == 1 ? 1 : 0] }
    @ObjCMethod("setContentCompressionResistancePriority:forOrientation:")
    func setContentCompressionResistancePriority(_ priority: Float, for orientation: Int) { compressionResistance[orientation == 1 ? 1 : 0] = priority }

    // MARK: Constraints

    @ObjCMethod("constraints") func viewConstraints() -> NSObject { NSMutableArray.of(constraints) }
    @ObjCMethod("addConstraint:")
    func addConstraint(_ constraint: NSLayoutConstraint?) {
        guard let constraint, !constraints.contains(where: { $0 === constraint }) else { return }
        constraints.append(constraint)
        needsLayout = true
        Windows.layersChanged()
    }
    @ObjCMethod("addConstraints:")
    func addConstraints(_ list: NSObject?) {
        for item in list?.as(NSArray.self)?.elements ?? [] { addConstraint(item.as(NSLayoutConstraint.self)) }
    }
    @ObjCMethod("removeConstraint:")
    func removeConstraint(_ constraint: NSLayoutConstraint?) {
        constraints.removeAll { $0 === constraint }
        needsLayout = true
    }
    @ObjCMethod("removeConstraints:")
    func removeConstraints(_ list: NSObject?) {
        for item in list?.as(NSArray.self)?.elements ?? [] { removeConstraint(item.as(NSLayoutConstraint.self)) }
    }
    @ObjCMethod("leadingAnchor") func leadingAnchor() -> NSLayoutAnchor { NSLayoutAnchor.make(self, 5) }
    @ObjCMethod("trailingAnchor") func trailingAnchor() -> NSLayoutAnchor { NSLayoutAnchor.make(self, 6) }
    @ObjCMethod("leftAnchor") func leftAnchor() -> NSLayoutAnchor { NSLayoutAnchor.make(self, 1) }
    @ObjCMethod("rightAnchor") func rightAnchor() -> NSLayoutAnchor { NSLayoutAnchor.make(self, 2) }
    @ObjCMethod("topAnchor") func topAnchor() -> NSLayoutAnchor { NSLayoutAnchor.make(self, 3) }
    @ObjCMethod("bottomAnchor") func bottomAnchor() -> NSLayoutAnchor { NSLayoutAnchor.make(self, 4) }
    @ObjCMethod("widthAnchor") func widthAnchor() -> NSLayoutAnchor { NSLayoutAnchor.make(self, 7) }
    @ObjCMethod("heightAnchor") func heightAnchor() -> NSLayoutAnchor { NSLayoutAnchor.make(self, 8) }
    @ObjCMethod("centerXAnchor") func centerXAnchor() -> NSLayoutAnchor { NSLayoutAnchor.make(self, 9) }
    @ObjCMethod("centerYAnchor") func centerYAnchor() -> NSLayoutAnchor { NSLayoutAnchor.make(self, 10) }
    @ObjCMethod("firstBaselineAnchor") func firstBaselineAnchor() -> NSLayoutAnchor { NSLayoutAnchor.make(self, 12) }
    @ObjCMethod("lastBaselineAnchor") func lastBaselineAnchor() -> NSLayoutAnchor { NSLayoutAnchor.make(self, 11) }

    // MARK: Layout guides

    /// The guides the view owns. The safe area and the layout margins are
    /// the view's bounds here: no titlebar or edge covers them.
    var layoutGuides: [NSLayoutGuide] = []
    var safeAreaGuide: NSLayoutGuide?
    var marginsGuide: NSLayoutGuide?

    @ObjCMethod("safeAreaLayoutGuide")
    func safeAreaLayoutGuide() -> NSLayoutGuide {
        if let safeAreaGuide { return safeAreaGuide }
        let guide = NSLayoutGuide()
        guide.owningViewObject = objcObject
        safeAreaGuide = guide
        return guide
    }
    @ObjCMethod("layoutMarginsGuide")
    func layoutMarginsGuide() -> NSLayoutGuide {
        if let marginsGuide { return marginsGuide }
        let guide = NSLayoutGuide()
        guide.owningViewObject = objcObject
        marginsGuide = guide
        return guide
    }
    @ObjCMethod("safeAreaInsets") func safeAreaInsets() -> NSEdgeInsets { NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0) }
    @ObjCMethod("safeAreaRect") func safeAreaRect() -> CGRect { bounds }
    @ObjCMethod("additionalSafeAreaInsets") func additionalSafeAreaInsets() -> NSEdgeInsets { NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0) }
    @ObjCMethod("setAdditionalSafeAreaInsets:") func setAdditionalSafeAreaInsets(_ insets: NSEdgeInsets) {}
    @ObjCMethod("layoutGuides") func viewLayoutGuides() -> NSObject { NSMutableArray.of(layoutGuides) }
    @ObjCMethod("addLayoutGuide:")
    func addLayoutGuide(_ guide: NSLayoutGuide?) {
        guard let guide, !layoutGuides.contains(where: { $0 === guide }) else { return }
        guide.owningViewObject = objcObject
        layoutGuides.append(guide)
    }
    @ObjCMethod("removeLayoutGuide:")
    func removeLayoutGuide(_ guide: NSLayoutGuide?) {
        layoutGuides.removeAll { $0 === guide }
        if guide?.owningViewObject == objcObject { guide?.owningViewObject = nil }
    }

    // MARK: Drawing into the layer

    /// Whether the view's class draws: overrides -drawRect:.
    var draws: Bool { Methods.overrides(objcObject, "drawRect:", of: NSView.objCClass.pointer) }

    @ObjCMethod("_perryDrawsLayer:") func drawsLayer(_ layer: NSObject?) -> Bool { draws }

    /// Draws the view into its layer's context: in the view's bounds, y up
    /// unless the view is flipped.
    @ObjCMethod("drawLayer:inContext:")
    func draw(_ layer: NSObject?, in context: UnsafeMutableRawPointer?) {
        guard let context else { return }
        let flipped = self.flipped
        NSGraphicsContext.with(context, flipped: flipped) {
            // The layer's context has its origin at the top left.
            if !flipped {
                CG.translateCTM(context, 0, frame.height)
                CG.scaleCTM(context, 1, -1)
            }
            CG.translateCTM(context, -boundsOrigin.x, -boundsOrigin.y)
            Send.void(objcObject, "viewWillDraw")
            typealias F = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, CGRect) -> Void
            unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(objcObject, ObjCRuntime.selector("drawRect:"), bounds)
        }
        needsDisplay = false
    }

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

/// NSView's messages, sent so subclasses' overrides run.
extension NSObject {
    @ObjCMethod("initWithFrame:")
    func initializeView(frame: CGRect) -> NSObject
}

import CPerryGeometry
import Glibc
import PerryObjCInterop

// Scrolling: NSScrollView tiles a clip view (and a table's header clip
// view above it) inside its border, with overlay scrollers over the
// clip view's right and bottom edges. The clip view shows part of its
// document view by moving its bounds origin, which moves the document's
// layer; wheel turns and scroller drags move it, kept within the document.
// NSScrollView is flipped, as AppKit's is: its header sits at its top.

@ObjCClass("NSScrollView")
open class NSScrollView: NSView {
    var contentClip: NSClipView?
    var headerClip: NSClipView?
    var verticalScroller: NSScroller?
    var horizontalScroller: NSScroller?
    var cornerView: NSView?
    var hasVerticalScroller = false
    var hasHorizontalScroller = false
    var autohidesScrollers = true
    /// NSBorderType: none 0, line 1, bezel 2, groove 3.
    var borderType: UInt = 0
    var lineScroll: CGFloat = 10
    var pageScroll: CGFloat = 10
    var contentInsets = NSEdgeInsets()
    var automaticallyAdjustsContentInsets = true
    var magnification: CGFloat = 1
    var allowsMagnification = false
    var verticalScrollElasticity = 0
    var horizontalScrollElasticity = 0
    var usesPredominantAxisScrolling = true
    var findBarPosition = 1

    @ObjCMethod("init")
    public required init() {
        super.init()
        setUpClip()
    }

    @ObjCMethod("initWithFrame:")
    public required init(frame: CGRect) {
        super.init(frame: frame)
        setUpClip()
    }

    /// NSScrollView's archive: "NSContentView", "NSHeaderClipView", the
    /// scrollers, and "NSsFlags" (the border type in its low two bits,
    /// vertical 0x10 and horizontal 0x20 scrollers, autohiding 0x200).
    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init(coder: coder)
        guard let coder else {
            setUpClip()
            return
        }
        let decoded = Coder(coder: coder)
        let flags = decoded.integer("NSsFlags")
        borderType = UInt(flags & 3)
        hasVerticalScroller = flags & 0x10 != 0
        hasHorizontalScroller = flags & 0x20 != 0
        autohidesScrollers = flags & 0x200 != 0
        contentClip = decoded.object("NSContentView")?.as(NSClipView.self)
        headerClip = decoded.object("NSHeaderClipView")?.as(NSClipView.self)
        verticalScroller = decoded.object("NSVScroller")?.as(NSScroller.self)
        horizontalScroller = decoded.object("NSHScroller")?.as(NSScroller.self)
        cornerView = decoded.object("NSCornerView")?.as(NSView.self)
        if decoded.has("NSScrollAmts"), let amounts = decoded.bytes("NSScrollAmts"), amounts.count >= 16 {
            // Four big-endian floats: vertical line, vertical page, horizontal line, horizontal page.
            func float(_ at: Int) -> CGFloat {
                CGFloat(Float(bitPattern: UInt32(amounts[at]) << 24 | UInt32(amounts[at + 1]) << 16 | UInt32(amounts[at + 2]) << 8 | UInt32(amounts[at + 3])))
            }
            lineScroll = max(1, float(0))
        }
        if contentClip == nil { setUpClip() }
        for scroller in [verticalScroller, horizontalScroller].compactMap({ $0 }) {
            scroller.scrollView = objcObject
            if scroller.superview !== self { addSubview(scroller) }
        }
        if let headerClip, headerClip.superview !== self { addSubview(headerClip) }
        // An outline or table view's corner sits over the vertical scroller.
        cornerView?.removeFromSuperview()
        tile()
    }

    private func setUpClip() {
        let clip = NSClipView(frame: CGRect(origin: .zero, size: frame.size))
        contentClip = clip
        addSubview(clip)
        tile()
    }

    @ObjCMethod("isFlipped") override func isFlipped() -> Bool { true }

    @ObjCMethod("contentView") func contentView() -> NSClipView? { contentClip }
    @ObjCMethod("setContentView:")
    func setContentView(_ clip: NSClipView?) {
        contentClip?.removeFromSuperview()
        contentClip = clip
        if let clip { addSubview(clip, positioned: -1, relativeTo: nil) }
        tile()
    }
    @ObjCMethod("documentView") func documentView() -> NSView? { contentClip?.documentView }
    @ObjCMethod("setDocumentView:") func setDocumentView(_ view: NSView?) { contentClip?.setDocumentView(view); tile() }
    @ObjCMethod("documentVisibleRect") func documentVisibleRect() -> CGRect { contentClip?.documentVisibleRect() ?? .zero }
    @ObjCMethod("contentSize") func contentSize() -> CGSize { contentClip?.frame.size ?? .zero }
    @ObjCMethod("hasVerticalScroller") func scrollHasVerticalScroller() -> Bool { hasVerticalScroller }
    @ObjCMethod("setHasVerticalScroller:")
    func setHasVerticalScroller(_ value: Bool) {
        hasVerticalScroller = value
        if value, verticalScroller == nil { setVerticalScroller(NSScroller(frame: CGRect(x: 0, y: 0, width: 15, height: 100))) }
        tile()
    }
    @ObjCMethod("hasHorizontalScroller") func scrollHasHorizontalScroller() -> Bool { hasHorizontalScroller }
    @ObjCMethod("setHasHorizontalScroller:")
    func setHasHorizontalScroller(_ value: Bool) {
        hasHorizontalScroller = value
        if value, horizontalScroller == nil { setHorizontalScroller(NSScroller(frame: CGRect(x: 0, y: 0, width: 100, height: 15))) }
        tile()
    }
    @ObjCMethod("verticalScroller") func scrollVerticalScroller() -> NSScroller? { verticalScroller }
    @ObjCMethod("setVerticalScroller:")
    func setVerticalScroller(_ scroller: NSScroller?) {
        verticalScroller?.removeFromSuperview()
        verticalScroller = scroller
        if let scroller { scroller.scrollView = objcObject; addSubview(scroller) }
        tile()
    }
    @ObjCMethod("horizontalScroller") func scrollHorizontalScroller() -> NSScroller? { horizontalScroller }
    @ObjCMethod("setHorizontalScroller:")
    func setHorizontalScroller(_ scroller: NSScroller?) {
        horizontalScroller?.removeFromSuperview()
        horizontalScroller = scroller
        if let scroller { scroller.scrollView = objcObject; addSubview(scroller) }
        tile()
    }
    @ObjCMethod("autohidesScrollers") func scrollAutohidesScrollers() -> Bool { autohidesScrollers }
    @ObjCMethod("setAutohidesScrollers:") func setAutohidesScrollers(_ value: Bool) { autohidesScrollers = value; tile() }
    @ObjCMethod("hasVerticalRuler") func hasVerticalRuler() -> Bool { false }
    @ObjCMethod("setHasVerticalRuler:") func setHasVerticalRuler(_ value: Bool) {}
    @ObjCMethod("hasHorizontalRuler") func hasHorizontalRuler() -> Bool { false }
    @ObjCMethod("setHasHorizontalRuler:") func setHasHorizontalRuler(_ value: Bool) {}
    @ObjCMethod("setRulersVisible:") func setRulersVisible(_ value: Bool) {}
    @ObjCMethod("borderType") func scrollBorderType() -> UInt { borderType }
    @ObjCMethod("setBorderType:") func setBorderType(_ value: UInt) { borderType = value; tile(); setNeedsDisplay(true) }
    @ObjCMethod("drawsBackground") func drawsBackground() -> Bool { contentClip?.drawsBackground ?? false }
    @ObjCMethod("setDrawsBackground:") func setDrawsBackground(_ value: Bool) { contentClip?.setDrawsBackground(value) }
    @ObjCMethod("backgroundColor") func backgroundColor() -> NSColor? { contentClip?.backgroundColor }
    @ObjCMethod("setBackgroundColor:") func setBackgroundColor(_ color: NSColor?) { contentClip?.setBackgroundColor(color) }
    @ObjCMethod("lineScroll") func scrollLineScroll() -> CGFloat { lineScroll }
    @ObjCMethod("setLineScroll:") func setLineScroll(_ value: CGFloat) { lineScroll = value }
    @ObjCMethod("verticalLineScroll") func verticalLineScroll() -> CGFloat { lineScroll }
    @ObjCMethod("setVerticalLineScroll:") func setVerticalLineScroll(_ value: CGFloat) { lineScroll = value }
    @ObjCMethod("horizontalLineScroll") func horizontalLineScroll() -> CGFloat { lineScroll }
    @ObjCMethod("setHorizontalLineScroll:") func setHorizontalLineScroll(_ value: CGFloat) { lineScroll = value }
    @ObjCMethod("pageScroll") func scrollPageScroll() -> CGFloat { pageScroll }
    @ObjCMethod("setPageScroll:") func setPageScroll(_ value: CGFloat) { pageScroll = value }
    @ObjCMethod("setVerticalPageScroll:") func setVerticalPageScroll(_ value: CGFloat) { pageScroll = value }
    @ObjCMethod("setHorizontalPageScroll:") func setHorizontalPageScroll(_ value: CGFloat) { pageScroll = value }
    @ObjCMethod("scrollsDynamically") func scrollsDynamically() -> Bool { true }
    @ObjCMethod("setScrollsDynamically:") func setScrollsDynamically(_ value: Bool) {}
    @ObjCMethod("scrollerStyle") func scrollerStyle() -> Int { 1 }
    @ObjCMethod("setScrollerStyle:") func setScrollerStyle(_ value: Int) {}
    @ObjCMethod("scrollerKnobStyle") func scrollerKnobStyle() -> Int { 0 }
    @ObjCMethod("setScrollerKnobStyle:") func setScrollerKnobStyle(_ value: Int) {}
    @ObjCMethod("contentInsets") func scrollContentInsets() -> NSEdgeInsets { contentInsets }
    @ObjCMethod("setContentInsets:") func setContentInsets(_ value: NSEdgeInsets) { contentInsets = value; tile() }
    @ObjCMethod("scrollerInsets") func scrollerInsets() -> NSEdgeInsets { NSEdgeInsets() }
    @ObjCMethod("setScrollerInsets:") func setScrollerInsets(_ value: NSEdgeInsets) {}
    @ObjCMethod("automaticallyAdjustsContentInsets") func scrollAutomaticallyAdjustsContentInsets() -> Bool { automaticallyAdjustsContentInsets }
    @ObjCMethod("setAutomaticallyAdjustsContentInsets:") func setAutomaticallyAdjustsContentInsets(_ value: Bool) { automaticallyAdjustsContentInsets = value }
    @ObjCMethod("magnification") func scrollMagnification() -> CGFloat { magnification }
    @ObjCMethod("setMagnification:") func setMagnification(_ value: CGFloat) { magnification = value }
    @ObjCMethod("allowsMagnification") func scrollAllowsMagnification() -> Bool { allowsMagnification }
    @ObjCMethod("setAllowsMagnification:") func setAllowsMagnification(_ value: Bool) { allowsMagnification = value }
    @ObjCMethod("setMinMagnification:") func setMinMagnification(_ value: CGFloat) {}
    @ObjCMethod("setMaxMagnification:") func setMaxMagnification(_ value: CGFloat) {}
    @ObjCMethod("verticalScrollElasticity") func scrollVerticalScrollElasticity() -> Int { verticalScrollElasticity }
    @ObjCMethod("setVerticalScrollElasticity:") func setVerticalScrollElasticity(_ value: Int) { verticalScrollElasticity = value }
    @ObjCMethod("horizontalScrollElasticity") func scrollHorizontalScrollElasticity() -> Int { horizontalScrollElasticity }
    @ObjCMethod("setHorizontalScrollElasticity:") func setHorizontalScrollElasticity(_ value: Int) { horizontalScrollElasticity = value }
    @ObjCMethod("usesPredominantAxisScrolling") func scrollUsesPredominantAxisScrolling() -> Bool { usesPredominantAxisScrolling }
    @ObjCMethod("setUsesPredominantAxisScrolling:") func setUsesPredominantAxisScrolling(_ value: Bool) { usesPredominantAxisScrolling = value }
    @ObjCMethod("setFindBarPosition:") func setFindBarPosition(_ value: Int) { findBarPosition = value }
    @ObjCMethod("flashScrollers") func flashScrollers() {}
    @ObjCMethod("setDocumentCursor:") func setDocumentCursor(_ cursor: NSObject?) {}
    @ObjCMethod("addFloatingSubview:forAxis:") func addFloatingSubview(_ view: NSView?, forAxis axis: Int) { view.map(addSubview) }
    @ObjCClassMethod("contentSizeForFrameSize:horizontalScrollerClass:verticalScrollerClass:borderType:controlSize:scrollerStyle:")
    static func contentSize(forFrameSize size: CGSize, horizontalScrollerClass: ObjCClass?, verticalScrollerClass: ObjCClass?, borderType: UInt,
                            controlSize: UInt, scrollerStyle: Int) -> CGSize {
        let inset: CGFloat = borderType == 0 ? 0 : 2
        return CGSize(width: size.width - inset, height: size.height - inset)
    }
    @ObjCClassMethod("frameSizeForContentSize:horizontalScrollerClass:verticalScrollerClass:borderType:controlSize:scrollerStyle:")
    static func frameSize(forContentSize size: CGSize, horizontalScrollerClass: ObjCClass?, verticalScrollerClass: ObjCClass?, borderType: UInt,
                          controlSize: UInt, scrollerStyle: Int) -> CGSize {
        let inset: CGFloat = borderType == 0 ? 0 : 2
        return CGSize(width: size.width + inset, height: size.height + inset)
    }

    @ObjCMethod("setFrameSize:")
    override func setFrameSize(_ size: CGSize) {
        super.setFrameSize(size)
        tile()
    }

    /// The header clip view on top, the clip view under it, inside the
    /// border; the scrollers over the clip view's edges.
    @ObjCMethod("tile")
    func tile() {
        let inset: CGFloat = borderType == 0 ? 0 : 1
        var content = CGRect(x: inset, y: inset, width: max(0, frame.width - 2 * inset), height: max(0, frame.height - 2 * inset))
        if let headerClip, let header = headerClip.documentView {
            let height = header.frame.height > 0 ? header.frame.height : 23
            Send.void(headerClip.objcObject, "setFrame:", rect: CGRect(x: content.minX, y: content.minY, width: content.width, height: height))
            content.origin.y += height
            content.size.height = max(0, content.height - height)
        }
        if let contentClip, contentClip.frame != content { Send.void(contentClip.objcObject, "setFrame:", rect: content) }
        if let verticalScroller {
            verticalScroller.setFrame(CGRect(x: content.maxX - 15, y: content.minY, width: 15, height: content.height))
        }
        if let horizontalScroller {
            horizontalScroller.setFrame(CGRect(x: content.minX, y: content.maxY - 15, width: max(0, content.width - (hasVerticalScroller ? 15 : 0)), height: 15))
        }
        reflectScrolledClipView(contentClip)
        setNeedsDisplay(true)
    }

    /// The scrollers show what part of the document the clip view shows.
    @ObjCMethod("reflectScrolledClipView:")
    func reflectScrolledClipView(_ clip: NSClipView?) {
        guard let clip = contentClip, let document = clip.documentView else {
            verticalScroller?.setHidden(true)
            horizontalScroller?.setHidden(true)
            return
        }
        let visible = clip.bounds, whole = document.frame
        func update(_ scroller: NSScroller?, has: Bool, visible length: CGFloat, whole total: CGFloat, offset: CGFloat) {
            guard let scroller else { return }
            let scrollable = total > length + 0.5
            scroller.setHidden(!has || (!scrollable && autohidesScrollers) || !scrollable)
            scroller.knobProportion = total > 0 ? min(1, length / total) : 1
            scroller.value = scrollable ? max(0, min(1, offset / (total - length))) : 0
            scroller.setNeedsDisplay(true)
        }
        update(verticalScroller, has: hasVerticalScroller, visible: visible.height, whole: whole.height,
               offset: document.flipped ? visible.minY - whole.minY : whole.maxY - visible.maxY)
        update(horizontalScroller, has: hasHorizontalScroller, visible: visible.width, whole: whole.width, offset: visible.minX - whole.minX)
        // A table's header scrolls sideways with it.
        if let headerClip, headerClip.boundsOrigin.x != visible.minX { headerClip.setBoundsOrigin(CGPoint(x: visible.minX, y: headerClip.boundsOrigin.y)) }
    }

    /// Scrolls by a wheel turn: lines, or points for a trackpad's precise
    /// deltas.
    @ObjCMethod("scrollWheel:")
    override func scrollWheel(_ eventObject: NSObject?) {
        guard let event = eventObject?.as(NSEvent.self), let clip = contentClip, let document = clip.documentView else {
            return super.scrollWheel(eventObject)
        }
        let scale = event.hasPreciseScrollingDeltas ? 1 : lineScroll * 4
        var dx = -event.scrollingDeltaX * scale, dy = -event.scrollingDeltaY * scale
        if usesPredominantAxisScrolling { if abs(dx) > abs(dy) { dy = 0 } else { dx = 0 } }
        if !hasHorizontalScroller && document.frame.width <= clip.bounds.width + 0.5 { dx = 0 }
        if !document.flipped { dy = -dy }
        guard dx != 0 || dy != 0 else { return }
        let target = CGRect(origin: CGPoint(x: clip.bounds.minX + dx, y: clip.bounds.minY + dy), size: clip.bounds.size)
        let constrained = clip.constrainBoundsRect(target)
        guard constrained.origin != clip.bounds.origin else { return super.scrollWheel(eventObject) }
        clip.scroll(to: constrained.origin)
    }

    /// A scroller's knob moved to `value` (0 to 1).
    func scrollerMoved(_ scroller: NSScroller) {
        guard let clip = contentClip, let document = clip.documentView else { return }
        var origin = clip.bounds.origin
        let whole = document.frame
        if scroller === verticalScroller {
            let range = max(0, whole.height - clip.bounds.height)
            origin.y = document.flipped ? whole.minY + range * scroller.value : whole.minY + range * (1 - scroller.value)
        } else {
            origin.x = whole.minX + max(0, whole.width - clip.bounds.width) * scroller.value
        }
        clip.scroll(to: clip.constrainBoundsRect(CGRect(origin: origin, size: clip.bounds.size)).origin)
    }

    @ObjCMethod("drawRect:")
    override func draw(_ rect: CGRect) {
        guard borderType != 0, let context = NSGraphicsContext.currentCG else { return }
        CG.saveGState(context)
        CG.setFillColorWithColor(context, NSColor(white: 0.75, alpha: 1).cgColorRef)
        NSFrameRect(bounds)
        CG.restoreGState(context)
    }
}

@ObjCClass("NSClipView")
open class NSClipView: NSView {
    var documentView: NSView?
    var drawsBackground = true
    var backgroundColor: NSColor? = NSColor.controlBackgroundColor()
    var copiesOnScroll = true
    var contentInsets = NSEdgeInsets()
    var automaticallyAdjustsContentInsets = true

    @ObjCMethod("init")
    public required init() { super.init() }

    @ObjCMethod("initWithFrame:")
    public required init(frame: CGRect) { super.init(frame: frame) }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init(coder: coder)
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        documentView = decoded.object("NSDocView")?.as(NSView.self)
        backgroundColor = decoded.object("NSBGColor")?.as(NSColor.self) ?? backgroundColor
        // NScvFlags: draws the background 4.
        if decoded.has("NScvFlags") { drawsBackground = decoded.integer("NScvFlags") & 4 != 0 }
        if let documentView, documentView.superview !== self { addSubview(documentView) }
    }

    /// A clip view's coordinates are its document's.
    @ObjCMethod("isFlipped") override func isFlipped() -> Bool { documentView?.flipped ?? false }

    @ObjCMethod("documentView") func clipDocumentView() -> NSView? { documentView }
    @ObjCMethod("setDocumentView:")
    func setDocumentView(_ view: NSView?) {
        documentView?.removeFromSuperview()
        documentView = view
        if let view {
            addSubview(view)
            view.updateLayerGeometry()
        }
        Send.void(objcObject, "setBoundsOrigin:", point: view?.frame.origin ?? .zero)
        documentFrameChanged()
    }
    @ObjCMethod("drawsBackground") func clipDrawsBackground() -> Bool { drawsBackground }
    @ObjCMethod("setDrawsBackground:") func setDrawsBackground(_ value: Bool) { drawsBackground = value; setNeedsDisplay(true) }
    @ObjCMethod("backgroundColor") func clipBackgroundColor() -> NSColor? { backgroundColor }
    @ObjCMethod("setBackgroundColor:") func setBackgroundColor(_ color: NSColor?) { backgroundColor = color; setNeedsDisplay(true) }
    @ObjCMethod("copiesOnScroll") func clipCopiesOnScroll() -> Bool { copiesOnScroll }
    @ObjCMethod("setCopiesOnScroll:") func setCopiesOnScroll(_ value: Bool) { copiesOnScroll = value }
    @ObjCMethod("contentInsets") func clipContentInsets() -> NSEdgeInsets { contentInsets }
    @ObjCMethod("setContentInsets:") func setContentInsets(_ value: NSEdgeInsets) { contentInsets = value }
    @ObjCMethod("automaticallyAdjustsContentInsets") func clipAutomaticallyAdjustsContentInsets() -> Bool { automaticallyAdjustsContentInsets }
    @ObjCMethod("setAutomaticallyAdjustsContentInsets:") func setAutomaticallyAdjustsContentInsets(_ value: Bool) { automaticallyAdjustsContentInsets = value }
    @ObjCMethod("documentRect") func documentRect() -> CGRect { documentView?.frame ?? bounds }
    @ObjCMethod("documentVisibleRect")
    func documentVisibleRect() -> CGRect {
        guard let documentView else { return .zero }
        return documentView.convert(bounds, from: self)
    }
    @ObjCMethod("documentCursor") func documentCursor() -> NSObject? { nil }
    @ObjCMethod("setDocumentCursor:") func setDocumentCursor(_ cursor: NSObject?) {}

    /// The bounds kept within the document: no further than its far edges,
    /// and at its near edge when it is smaller.
    @ObjCMethod("constrainBoundsRect:")
    func constrainBoundsRect(_ rect: CGRect) -> CGRect {
        guard let documentView else { return rect }
        let document = documentView.frame
        var result = rect
        func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat { high < low ? low : min(max(value, low), high) }
        result.origin.x = clamp(rect.minX, document.minX, document.maxX - rect.width)
        if documentView.flipped {
            result.origin.y = clamp(rect.minY, document.minY, document.maxY - rect.height)
        } else {
            // A document shorter than the clip view sits at the top.
            result.origin.y = document.height < rect.height ? document.maxY - rect.height : clamp(rect.minY, document.minY, document.maxY - rect.height)
        }
        return result
    }

    @ObjCMethod("scrollToPoint:")
    func scroll(to point: CGPoint) {
        Send.void(objcObject, "setBoundsOrigin:", point: point)
        superview?.as(NSScrollView.self)?.reflectScrolledClipView(self)
        documentView?.as(NSTableView.self)?.visibleRectChanged()
    }

    @ObjCMethod("autoscroll:") override func autoscroll(_ event: NSObject?) -> Bool { false }
    @ObjCMethod("viewBoundsChanged:") func viewBoundsChanged(_ notification: NSObject?) {}
    @ObjCMethod("viewFrameChanged:") func viewFrameChanged(_ notification: NSObject?) { documentFrameChanged() }

    /// The document grew or shrank: the bounds stay within it, and the
    /// scrollers show its new size.
    func documentFrameChanged() {
        let constrained = constrainBoundsRect(bounds)
        if constrained.origin != boundsOrigin { Send.void(objcObject, "setBoundsOrigin:", point: constrained.origin) }
        superview?.as(NSScrollView.self)?.reflectScrolledClipView(self)
    }

    @ObjCMethod("setFrameSize:")
    override func setFrameSize(_ size: CGSize) {
        super.setFrameSize(size)
        // A view-based table's width follows its clip view's.
        if let table = documentView?.as(NSTableView.self) { table.clipResized() }
        documentFrameChanged()
    }

    @ObjCMethod("drawRect:")
    override func draw(_ rect: CGRect) {
        guard drawsBackground, let backgroundColor, let context = NSGraphicsContext.currentCG else { return }
        CG.saveGState(context)
        CG.setFillColorWithColor(context, backgroundColor.cgColorRef)
        CG.fillRect(context, bounds)
        CG.restoreGState(context)
    }

    override func ensureLayer() {
        super.ensureLayer()
        layer.map { CALayer(objcObject: $0.objcObject, ownership: .retain).setMasksToBounds(true) }
    }
}

/// NSScroller: an overlay knob, as proportionally long as the part of the
/// document shown, dragged to scroll.
@ObjCClass("NSScroller")
open class NSScroller: NSControl {
    var knobProportion: CGFloat = 1
    var value: CGFloat = 0
    /// Not retained.
    var scrollView: UnsafeMutableRawPointer?
    var dragStart: (point: CGFloat, value: CGFloat)?

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init(coder: coder)
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        value = decoded.double("NSCurValue")
        if decoded.has("NSPercent") { knobProportion = decoded.double("NSPercent") }
    }

    @ObjCMethod("init")
    public required init() { super.init() }

    @ObjCMethod("initWithFrame:")
    public required init(frame: CGRect) { super.init(frame: frame) }

    @ObjCClassMethod("cellClass") static func scrollerCellClass() -> ObjCClass? { nil }
    @ObjCClassMethod("scrollerWidth") static func scrollerWidth() -> CGFloat { 15 }
    @ObjCClassMethod("scrollerWidthForControlSize:") static func scrollerWidth(forControlSize size: UInt) -> CGFloat { size == 1 ? 11 : 15 }
    @ObjCClassMethod("scrollerWidthForControlSize:scrollerStyle:")
    static func scrollerWidth(forControlSize size: UInt, scrollerStyle: Int) -> CGFloat { size == 1 ? 11 : 15 }
    @ObjCClassMethod("preferredScrollerStyle") static func preferredScrollerStyle() -> Int { 1 }
    @ObjCClassMethod("isCompatibleWithOverlayScrollers") static func isCompatibleWithOverlayScrollers() -> Bool { true }

    var vertical: Bool { frame.height >= frame.width }

    @ObjCMethod("knobProportion") func scrollerKnobProportion() -> CGFloat { knobProportion }
    @ObjCMethod("setKnobProportion:") func setKnobProportion(_ value: CGFloat) { knobProportion = value; setNeedsDisplay(true) }
    @ObjCMethod("doubleValue") func scrollerDoubleValue() -> Double { value }
    @ObjCMethod("setDoubleValue:") func setScrollerDoubleValue(_ value: Double) { self.value = value; setNeedsDisplay(true) }
    @ObjCMethod("floatValue") func scrollerFloatValue() -> Float { Float(value) }
    @ObjCMethod("setFloatValue:knobProportion:")
    func setFloatValue(_ value: Float, knobProportion: CGFloat) {
        self.value = CGFloat(value)
        self.knobProportion = knobProportion
        setNeedsDisplay(true)
    }
    @ObjCMethod("scrollerStyle") func scrollerStyle() -> Int { 1 }
    @ObjCMethod("setScrollerStyle:") func setScrollerStyle(_ value: Int) {}
    @ObjCMethod("knobStyle") func knobStyle() -> Int { 0 }
    @ObjCMethod("setKnobStyle:") func setKnobStyle(_ value: Int) {}
    @ObjCMethod("hitPart") func hitPart() -> UInt { 2 }
    @ObjCMethod("usableParts") func usableParts() -> UInt { 2 }
    @ObjCMethod("isFlipped") override func isFlipped() -> Bool { true }

    /// The knob's rectangle in the scroller.
    var knobRect: CGRect {
        let length = vertical ? bounds.height : bounds.width
        let knob = max(20, length * knobProportion)
        let offset = (length - knob) * value
        return vertical ? CGRect(x: 4, y: offset + 2, width: max(0, bounds.width - 7), height: knob - 4)
            : CGRect(x: offset + 2, y: 4, width: knob - 4, height: max(0, bounds.height - 7))
    }

    @ObjCMethod("rectForPart:") func rect(forPart part: UInt) -> CGRect { part == 2 ? knobRect : bounds }

    @ObjCMethod("drawRect:")
    override func draw(_ rect: CGRect) {
        guard knobProportion < 1, let context = NSGraphicsContext.currentCG else { return }
        let knob = knobRect
        CG.fill(CG.roundedRect(knob, radius: min(knob.width, knob.height) / 2), NSColor(white: 0, alpha: 0.35), in: context)
    }

    @ObjCMethod("drawKnob") func drawKnob() {}
    @ObjCMethod("drawKnobSlotInRect:highlight:") func drawKnobSlot(in rect: CGRect, highlight: Bool) {}

    @ObjCMethod("mouseDown:")
    override func mouseDown(_ event: NSObject?) {
        guard let event = event?.as(NSEvent.self) else { return }
        let point = convert(event.locationInWindow, from: nil)
        if !knobRect.contains(point) {
            // A click in the slot moves the knob there.
            let length = vertical ? bounds.height : bounds.width
            let knob = max(20, length * knobProportion)
            let position = (vertical ? point.y : point.x) - knob / 2
            value = max(0, min(1, position / max(1, length - knob)))
            moved()
        }
        dragStart = (vertical ? point.y : point.x, value)
    }

    @ObjCMethod("mouseDragged:")
    override func mouseDragged(_ event: NSObject?) {
        guard let start = dragStart, let event = event?.as(NSEvent.self) else { return }
        let point = convert(event.locationInWindow, from: nil)
        let length = vertical ? bounds.height : bounds.width
        let knob = max(20, length * knobProportion)
        let delta = (vertical ? point.y : point.x) - start.point
        value = max(0, min(1, start.value + delta / max(1, length - knob)))
        moved()
    }

    @ObjCMethod("mouseUp:") override func mouseUp(_ event: NSObject?) { dragStart = nil }

    private func moved() {
        setNeedsDisplay(true)
        if let scrollView { NSScrollView.objCInstance(scrollView, ownership: .retain).scrollerMoved(self) }
        _ = sendAction(action, to: target.map(NSObject.init))
    }
}

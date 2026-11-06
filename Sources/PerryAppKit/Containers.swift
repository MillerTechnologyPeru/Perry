import CPerryGeometry
import PerryObjCInterop

// Views that hold others: NSBox (a titled, bordered or filled box, or a
// separator line), NSSplitView (panes side by side or one above another,
// between dividers that can be dragged) and NSStackView (views in a row or
// column, spaced evenly).

/// NSBoxType: primary 0, separator 2, custom 4. NSTitlePosition: none 0,
/// above top 1, at top 2.
@ObjCClass("NSBox")
open class NSBox: NSView {
    var boxType: UInt = 0
    var borderType: UInt = 3
    var titlePosition: UInt = 2
    var titleCell: NSCell?
    var contentViewMargins = CGSize(width: 5, height: 5)
    var fillColor: NSColor = NSColor.clearColor()
    var borderColor: NSColor = NSColor(white: 0, alpha: 0.15)
    var borderWidth: CGFloat = 1
    var cornerRadius: CGFloat = 5
    var transparent = false
    var contentView: NSView?

    public required init() { super.init() }

    @ObjCMethod("initWithFrame:")
    public required init(frame: CGRect) {
        super.init(frame: frame)
        let content = NSView(frame: CGRect(origin: .zero, size: frame.size))
        contentView = content
        addSubview(content)
    }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init(coder: coder)
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        boxType = UInt(decoded.integer("NSBoxType"))
        if decoded.has("NSBorderType") { borderType = UInt(decoded.integer("NSBorderType")) }
        if decoded.has("NSTitlePosition") { titlePosition = UInt(decoded.integer("NSTitlePosition")) }
        titleCell = decoded.object("NSTitleCell")?.as(NSCell.self)
        if decoded.has("NSOffsets") { contentViewMargins = decoded.size("NSOffsets") }
        fillColor = decoded.object("NSFillColor2")?.as(NSColor.self) ?? fillColor
        if let color = decoded.object("NSBorderColor2")?.as(NSColor.self) { borderColor = color }
        if decoded.has("NSBorderWidth2") { borderWidth = decoded.double("NSBorderWidth2") }
        if decoded.has("NSCornerRadius2") { cornerRadius = decoded.double("NSCornerRadius2") }
        transparent = decoded.bool("NSTransparent")
        contentView = decoded.object("NSContentView")?.as(NSView.self)
        if let contentView, contentView.superview !== self { addSubview(contentView) }
    }

    var title: String { titleCell?.cellString ?? "" }
    var showsTitle: Bool { titlePosition != 0 && !title.isEmpty && boxType == 0 }

    @ObjCMethod("isFlipped") override func isFlipped() -> Bool { true }
    @ObjCMethod("title") func boxTitle() -> String { title }
    @ObjCMethod("setTitle:")
    func setTitle(_ value: String?) {
        if titleCell == nil { titleCell = NSTextFieldCell(textCell: value) } else { titleCell?.setStringValue(value) }
        setNeedsDisplay(true)
    }
    @ObjCMethod("titleFont") func titleFont() -> NSFont? { titleCell?.font }
    @ObjCMethod("setTitleFont:") func setTitleFont(_ font: NSFont?) { titleCell?.font = font; setNeedsDisplay(true) }
    @ObjCMethod("titlePosition") func boxTitlePosition() -> UInt { titlePosition }
    @ObjCMethod("setTitlePosition:") func setTitlePosition(_ value: UInt) { titlePosition = value; setNeedsDisplay(true) }
    @ObjCMethod("boxType") func boxBoxType() -> UInt { boxType }
    @ObjCMethod("setBoxType:") func setBoxType(_ value: UInt) { boxType = value; setNeedsDisplay(true) }
    @ObjCMethod("borderType") func boxBorderType() -> UInt { borderType }
    @ObjCMethod("setBorderType:") func setBorderType(_ value: UInt) { borderType = value; setNeedsDisplay(true) }
    @ObjCMethod("fillColor") func boxFillColor() -> NSColor { fillColor }
    @ObjCMethod("setFillColor:") func setFillColor(_ color: NSColor?) { fillColor = color ?? NSColor.clearColor(); setNeedsDisplay(true) }
    @ObjCMethod("borderColor") func boxBorderColor() -> NSColor { borderColor }
    @ObjCMethod("setBorderColor:") func setBorderColor(_ color: NSColor?) { borderColor = color ?? borderColor; setNeedsDisplay(true) }
    @ObjCMethod("borderWidth") func boxBorderWidth() -> CGFloat { borderWidth }
    @ObjCMethod("setBorderWidth:") func setBorderWidth(_ value: CGFloat) { borderWidth = value; setNeedsDisplay(true) }
    @ObjCMethod("cornerRadius") func boxCornerRadius() -> CGFloat { cornerRadius }
    @ObjCMethod("setCornerRadius:") func setCornerRadius(_ value: CGFloat) { cornerRadius = value; setNeedsDisplay(true) }
    @ObjCMethod("isTransparent") func isTransparent() -> Bool { transparent }
    @ObjCMethod("setTransparent:") func setTransparent(_ value: Bool) { transparent = value; setNeedsDisplay(true) }
    @ObjCMethod("contentViewMargins") func boxContentViewMargins() -> CGSize { contentViewMargins }
    @ObjCMethod("setContentViewMargins:") func setContentViewMargins(_ value: CGSize) { contentViewMargins = value }
    @ObjCMethod("contentView") func boxContentView() -> NSView? { contentView }
    @ObjCMethod("setContentView:")
    func setContentView(_ view: NSView?) {
        contentView?.removeFromSuperview()
        contentView = view
        if let view { addSubview(view) }
    }
    @ObjCMethod("sizeToFit") func sizeToFit() {}
    @ObjCMethod("setFrameFromContentFrame:") func setFrame(fromContentFrame frame: CGRect) { Send.void(objcObject, "setFrame:", rect: frame) }

    @ObjCMethod("drawRect:")
    override func draw(_ rect: CGRect) {
        guard !transparent, let context = NSGraphicsContext.currentCG else { return }
        if boxType == 2 {
            // A separator: a line across its longer side.
            CG.saveGState(context)
            CG.setFill(context, NSColor.separatorColor())
            if bounds.width >= bounds.height {
                CG.fillRect(context, CGRect(x: 0, y: (bounds.height / 2).rounded(.down), width: bounds.width, height: 1))
            } else {
                CG.fillRect(context, CGRect(x: (bounds.width / 2).rounded(.down), y: 0, width: 1, height: bounds.height))
            }
            CG.restoreGState(context)
            return
        }
        let font = titleCell?.font ?? NSFont.system(size: 11)
        let titleHeight = showsTitle ? Text.lineHeight(font) : 0
        let frame = CGRect(x: 0.5, y: titleHeight + 0.5, width: bounds.width - 1, height: bounds.height - titleHeight - 1)
        if boxType == 4 {
            if fillColor.alpha > 0 { CG.fill(CG.roundedRect(frame, radius: cornerRadius), fillColor, in: context) }
            if borderWidth > 0 { CG.stroke(CG.roundedRect(frame, radius: cornerRadius), borderColor, width: borderWidth, in: context) }
        } else {
            CG.fill(CG.roundedRect(frame, radius: 5), NSColor(white: 0, alpha: 0.04), in: context)
            CG.stroke(CG.roundedRect(frame, radius: 5), NSColor(white: 0, alpha: 0.12), in: context)
        }
        if showsTitle {
            var style = TextStyle()
            style.maximumLines = 1
            Text.draw([TextRun(text: title, font: font, color: NSColor.labelColor())], in: CGRect(x: 6, y: 0, width: bounds.width - 12, height: titleHeight),
                      style: style)
        }
    }
}

/// NSSplitView: its arranged subviews side by side (vertical dividers) or
/// one above another, a thin divider between each.
@ObjCClass("NSSplitView")
open class NSSplitView: NSView {
    var vertical = false
    /// NSSplitViewDividerStyle: thick 1, thin 2, pane splitter 3.
    var dividerStyle = 2
    var autosaveName: String?
    var holdingPriorities: [Float] = []
    var arrangesAllSubviews = true
    var arranged: [NSView] = []
    /// Not retained.
    var delegateObject: UnsafeMutableRawPointer?
    var dragging: (index: Int, start: CGFloat, position: CGFloat)?
    /// The thinnest and thickest a pane may be (a split view controller's
    /// items say), where something limits it.
    var paneLimits: ((NSView) -> (minimum: CGFloat, maximum: CGFloat))?

    func limits(of pane: NSView) -> (minimum: CGFloat, maximum: CGFloat) {
        paneLimits?(pane) ?? (0, .greatestFiniteMagnitude)
    }

    public required init() { super.init() }

    @ObjCMethod("initWithFrame:")
    public required init(frame: CGRect) { super.init(frame: frame) }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init(coder: coder)
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        vertical = decoded.bool("NSIsVertical")
        if decoded.has("NSDividerStyle") { dividerStyle = decoded.integer("NSDividerStyle") }
        autosaveName = decoded.string("NSAutosaveName")
        arrangesAllSubviews = !decoded.bool("NSDoesNotArrangeAllSubviews")
        arranged = decoded.array("NSArrangedSubviews").compactMap { $0.as(NSView.self) }
        holdingPriorities = decoded.array("NSHoldingPriorities").map { Float(Send.double($0.objcObject, "doubleValue")) }
    }

    var panes: [NSView] { arrangesAllSubviews || arranged.isEmpty ? subviews : arranged }

    @ObjCMethod("isFlipped") override func isFlipped() -> Bool { true }
    @ObjCMethod("isVertical") func isVertical() -> Bool { vertical }
    @ObjCMethod("setVertical:") func setVertical(_ value: Bool) { vertical = value; adjustSubviews() }
    @ObjCMethod("dividerStyle") func splitDividerStyle() -> Int { dividerStyle }
    @ObjCMethod("setDividerStyle:") func setDividerStyle(_ value: Int) { dividerStyle = value; adjustSubviews() }
    @ObjCMethod("dividerThickness") func dividerThickness() -> CGFloat { dividerStyle == 1 ? 9 : dividerStyle == 3 ? 10 : 1 }
    @ObjCMethod("dividerColor") func dividerColor() -> NSColor { NSColor.separatorColor() }
    @ObjCMethod("autosaveName") func splitAutosaveName() -> String? { autosaveName }
    @ObjCMethod("setAutosaveName:") func setAutosaveName(_ name: String?) { autosaveName = name }
    @ObjCMethod("delegate") func splitDelegate() -> NSObject? { delegateObject.map(NSObject.init) }
    @ObjCMethod("setDelegate:") func setDelegate(_ value: NSObject?) { delegateObject = value?.objcObject }
    @ObjCMethod("arrangedSubviews") func arrangedSubviews() -> NSObject { NSMutableArray.of(panes) }
    @ObjCMethod("arrangesAllSubviews") func splitArrangesAllSubviews() -> Bool { arrangesAllSubviews }
    @ObjCMethod("setArrangesAllSubviews:") func setArrangesAllSubviews(_ value: Bool) { arrangesAllSubviews = value }
    @ObjCMethod("addArrangedSubview:")
    func addArrangedSubview(_ view: NSView?) {
        guard let view else { return }
        arranged.append(view)
        if view.superview !== self { addSubview(view) }
        adjustSubviews()
    }
    @ObjCMethod("removeArrangedSubview:") func removeArrangedSubview(_ view: NSView?) { arranged.removeAll { $0 === view }; adjustSubviews() }
    @ObjCMethod("holdingPriorityForSubviewAtIndex:")
    func holdingPriority(forSubviewAt index: Int) -> Float { holdingPriorities.indices.contains(index) ? holdingPriorities[index] : 250 }
    @ObjCMethod("setHoldingPriority:forSubviewAtIndex:")
    func setHoldingPriority(_ priority: Float, forSubviewAt index: Int) {
        while holdingPriorities.count <= index { holdingPriorities.append(250) }
        holdingPriorities[index] = priority
    }
    @ObjCMethod("isSubviewCollapsed:") func isSubviewCollapsed(_ view: NSView?) -> Bool { view?.hidden ?? false }
    @ObjCMethod("minPossiblePositionOfDividerAtIndex:") func minPossiblePosition(ofDividerAt index: Int) -> CGFloat { 0 }
    @ObjCMethod("maxPossiblePositionOfDividerAtIndex:") func maxPossiblePosition(ofDividerAt index: Int) -> CGFloat { vertical ? bounds.width : bounds.height }

    /// Each pane keeps its size along the split, but the panes fill it:
    /// the last pane, or the one holding least, takes what is left.
    @ObjCMethod("adjustSubviews")
    func adjustSubviews() {
        let panes = self.panes.filter { !$0.hidden }
        guard !panes.isEmpty else { return }
        let thickness = dividerThickness()
        let total = vertical ? bounds.width : bounds.height
        // Laid out once there is room: squeezed into nothing, the panes'
        // own subviews would lose their layout.
        guard total > 0 else { return }
        var sizes = panes.map { pane in
            let limits = limits(of: pane)
            return min(max(vertical ? pane.frame.width : pane.frame.height, limits.minimum), limits.maximum)
        }
        let available = total - thickness * CGFloat(panes.count - 1)
        let extra = available - sizes.reduce(0, +)
        // The pane with the lowest holding priority grows or shrinks: the
        // last of those, when several hold as little.
        let all = self.panes
        var flexible = panes.count - 1
        var lowest = Float.greatestFiniteMagnitude
        for (index, pane) in panes.enumerated() {
            let priority = holdingPriority(forSubviewAt: all.firstIndex(where: { $0 === pane }) ?? index)
            if priority <= lowest {
                lowest = priority
                flexible = index
            }
        }
        sizes[flexible] = max(limits(of: panes[flexible]).minimum, sizes[flexible] + extra)
        var offset: CGFloat = 0
        for (pane, size) in zip(panes, sizes) {
            let frame = vertical ? CGRect(x: offset, y: 0, width: size, height: bounds.height) : CGRect(x: 0, y: offset, width: bounds.width, height: size)
            if pane.frame != frame { Send.void(pane.objcObject, "setFrame:", rect: frame) }
            offset += size + thickness
        }
        setNeedsDisplay(true)
        dividersMoved()
    }

    /// Toolbar sections that track the dividers follow them.
    func dividersMoved() {
        if vertical { window?.toolbarView?.arrange() }
    }

    @ObjCMethod("setPosition:ofDividerAtIndex:")
    func setPosition(_ position: CGFloat, ofDividerAt index: Int) {
        let panes = self.panes.filter { !$0.hidden }
        guard index + 1 < panes.count else { return }
        let first = panes[index], second = panes[index + 1]
        let start = vertical ? first.frame.minX : first.frame.minY
        let end = vertical ? second.frame.maxX : second.frame.maxY
        let thickness = dividerThickness()
        let (firstLimits, secondLimits) = (limits(of: first), limits(of: second))
        let lowest = max(start + firstLimits.minimum, end - thickness - secondLimits.maximum)
        let highest = min(start + firstLimits.maximum, end - thickness - secondLimits.minimum)
        let clamped = max(start, min(end - thickness, max(lowest, min(highest, position))))
        if vertical {
            first.setFrame(CGRect(x: start, y: 0, width: clamped - start, height: bounds.height))
            second.setFrame(CGRect(x: clamped + thickness, y: 0, width: end - clamped - thickness, height: bounds.height))
        } else {
            first.setFrame(CGRect(x: 0, y: start, width: bounds.width, height: clamped - start))
            second.setFrame(CGRect(x: 0, y: clamped + thickness, width: bounds.width, height: end - clamped - thickness))
        }
        post("NSSplitViewDidResizeSubviewsNotification", object: self)
        setNeedsDisplay(true)
        dividersMoved()
    }

    @ObjCMethod("setFrameSize:")
    override func setFrameSize(_ size: CGSize) {
        let old = frame.size
        super.setFrameSize(size)
        if old != size { adjustSubviews() }
    }

    @ObjCMethod("resizeSubviewsWithOldSize:")
    override func resizeSubviews(withOldSize old: CGSize) { adjustSubviews() }

    /// The dividers' rectangles.
    var dividers: [CGRect] {
        let panes = self.panes.filter { !$0.hidden }
        let thickness = dividerThickness()
        return panes.dropLast().map { pane in
            vertical ? CGRect(x: pane.frame.maxX, y: 0, width: thickness, height: bounds.height)
                : CGRect(x: 0, y: pane.frame.maxY, width: bounds.width, height: thickness)
        }
    }

    @ObjCMethod("drawDividerInRect:")
    func drawDivider(in rect: CGRect) {
        guard let context = NSGraphicsContext.currentCG else { return }
        CG.saveGState(context)
        CG.setFill(context, NSColor.separatorColor())
        CG.fillRect(context, rect)
        CG.restoreGState(context)
    }

    @ObjCMethod("drawRect:")
    override func draw(_ rect: CGRect) {
        for divider in dividers { Send.void(objcObject, "drawDividerInRect:", rect: divider) }
    }

    /// The divider under a point, a few points either side of it.
    @ObjCMethod("hitTest:")
    override func hitTest(_ point: CGPoint) -> NSView? {
        guard !hidden, frame.contains(point) else { return nil }
        let local = fromSuperview(point)
        if dividers.contains(where: { $0.insetBy(dx: vertical ? -3 : 0, dy: vertical ? 0 : -3).contains(local) }) { return self }
        return super.hitTest(point)
    }

    @ObjCMethod("mouseDown:")
    override func mouseDown(_ event: NSObject?) {
        guard let event = event?.as(NSEvent.self) else { return }
        let point = convert(event.locationInWindow, from: nil)
        for (index, divider) in dividers.enumerated() where divider.insetBy(dx: vertical ? -3 : 0, dy: vertical ? 0 : -3).contains(point) {
            dragging = (index, vertical ? point.x : point.y, vertical ? divider.minX : divider.minY)
            return
        }
    }

    @ObjCMethod("mouseDragged:")
    override func mouseDragged(_ event: NSObject?) {
        guard let dragging, let event = event?.as(NSEvent.self) else { return }
        let point = convert(event.locationInWindow, from: nil)
        setPosition(dragging.position + (vertical ? point.x : point.y) - dragging.start, ofDividerAt: dragging.index)
    }

    @ObjCMethod("mouseUp:") override func mouseUp(_ event: NSObject?) { dragging = nil }
}

/// NSStackView: its views in a row (orientation 0) or column (1), with
/// spacing between, inside its edge insets.
@ObjCClass("NSStackView")
open class NSStackView: NSView {
    var orientation = 0
    var alignment = 0
    var spacing: CGFloat = 8
    var edgeInsets = NSEdgeInsets()
    var distribution = 0
    var detachesHiddenViews = true
    var views: [NSView] = []

    public required init() { super.init() }

    @ObjCMethod("initWithFrame:")
    public required init(frame: CGRect) { super.init(frame: frame) }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init(coder: coder)
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        orientation = decoded.integer("NSStackViewOrientation")
        alignment = decoded.integer("NSStackViewAlignment")
        if decoded.has("NSStackViewSpacing") { spacing = decoded.double("NSStackViewSpacing") }
        edgeInsets = NSEdgeInsets(top: decoded.double("NSStackViewEdgeInsets.top"), left: decoded.double("NSStackViewEdgeInsets.left"),
                                  bottom: decoded.double("NSStackViewEdgeInsets.bottom"), right: decoded.double("NSStackViewEdgeInsets.right"))
        distribution = decoded.integer("NSStackViewdistribution")
        detachesHiddenViews = decoded.bool("NSStackViewDetachesHiddenViews")
        // The views are in its containers: beginning, center, end.
        for key in ["NSStackViewBeginningContainer", "NSStackViewMiddleContainer", "NSStackViewEndContainer"] {
            guard let container = decoded.object(key)?.as(NSStackViewContainer.self) else { continue }
            views += container.views
            container.removeFromSuperview()
        }
        if views.isEmpty { views = subviews }
        for view in views where view.superview !== self { addSubview(view) }
        needsLayout = true
    }

    @ObjCClassMethod("stackViewWithViews:")
    static func stackView(views: NSObject?) -> NSStackView {
        let stack = NSStackView(frame: .zero)
        stack.setViews(views)
        return stack
    }

    @ObjCMethod("isFlipped") override func isFlipped() -> Bool { true }
    @ObjCMethod("orientation") func stackOrientation() -> Int { orientation }
    @ObjCMethod("setOrientation:") func setOrientation(_ value: Int) { orientation = value; needsLayout = true }
    @ObjCMethod("alignment") func stackAlignment() -> Int { alignment }
    @ObjCMethod("setAlignment:") func setAlignment(_ value: Int) { alignment = value; needsLayout = true }
    @ObjCMethod("spacing") func stackSpacing() -> CGFloat { spacing }
    @ObjCMethod("setSpacing:") func setSpacing(_ value: CGFloat) { spacing = value; needsLayout = true }
    @ObjCMethod("edgeInsets") func stackEdgeInsets() -> NSEdgeInsets { edgeInsets }
    @ObjCMethod("setEdgeInsets:") func setEdgeInsets(_ value: NSEdgeInsets) { edgeInsets = value; needsLayout = true }
    @ObjCMethod("distribution") func stackDistribution() -> Int { distribution }
    @ObjCMethod("setDistribution:") func setDistribution(_ value: Int) { distribution = value; needsLayout = true }
    @ObjCMethod("detachesHiddenViews") func stackDetachesHiddenViews() -> Bool { detachesHiddenViews }
    @ObjCMethod("setDetachesHiddenViews:") func setDetachesHiddenViews(_ value: Bool) { detachesHiddenViews = value }
    @ObjCMethod("arrangedSubviews") func arrangedSubviews() -> NSObject { NSMutableArray.of(views) }
    @ObjCMethod("views") func stackViews() -> NSObject { NSMutableArray.of(views) }
    @ObjCMethod("setViews:")
    func setViews(_ list: NSObject?) {
        for view in views { view.removeFromSuperview() }
        views = list?.as(NSArray.self)?.elements.compactMap { $0.as(NSView.self) } ?? []
        for view in views { addSubview(view) }
        needsLayout = true
    }
    @ObjCMethod("addArrangedSubview:") func addArrangedSubview(_ view: NSView?) { insertArrangedSubview(view, at: views.count) }
    @ObjCMethod("insertArrangedSubview:atIndex:")
    func insertArrangedSubview(_ view: NSView?, at index: Int) {
        guard let view else { return }
        views.removeAll { $0 === view }
        views.insert(view, at: max(0, min(index, views.count)))
        if view.superview !== self { addSubview(view) }
        needsLayout = true
    }
    @ObjCMethod("removeArrangedSubview:") func removeArrangedSubview(_ view: NSView?) { views.removeAll { $0 === view }; needsLayout = true }
    @ObjCMethod("addView:inGravity:") func addView(_ view: NSView?, inGravity gravity: Int) { addArrangedSubview(view) }
    @ObjCMethod("setCustomSpacing:afterView:") func setCustomSpacing(_ spacing: CGFloat, after view: NSView?) {}
    @ObjCMethod("setHuggingPriority:forOrientation:") func setHuggingPriority(_ priority: Float, for orientation: Int) {}
    @ObjCMethod("setClippingResistancePriority:forOrientation:") func setClippingResistancePriority(_ priority: Float, for orientation: Int) {}
    @ObjCMethod("setVisibilityPriority:forView:") func setVisibilityPriority(_ priority: Float, for view: NSView?) {}

    /// The views one after another along the orientation, at their
    /// intrinsic (or current) sizes; filling the stack across it.
    @ObjCMethod("layout")
    override func layout() {
        let shown = views.filter { !($0.hidden && detachesHiddenViews) }
        let horizontal = orientation == 0
        var offset = horizontal ? edgeInsets.left : edgeInsets.top
        let across = horizontal ? bounds.height - edgeInsets.top - edgeInsets.bottom : bounds.width - edgeInsets.left - edgeInsets.right
        let sizes = shown.map { view -> CGSize in
            let intrinsic = Send.size(view.objcObject, "intrinsicContentSize")
            return CGSize(width: intrinsic.width > 0 ? intrinsic.width : view.frame.width, height: intrinsic.height > 0 ? intrinsic.height : view.frame.height)
        }
        // Fill: the remaining length goes to the last view.
        let length = horizontal ? bounds.width - edgeInsets.left - edgeInsets.right : bounds.height - edgeInsets.top - edgeInsets.bottom
        let used = sizes.reduce(0) { $0 + (horizontal ? $1.width : $1.height) } + spacing * CGFloat(max(0, shown.count - 1))
        for (index, (view, size)) in zip(shown, sizes).enumerated() {
            var along = horizontal ? size.width : size.height
            if distribution == 0, index == shown.count - 1, used < length { along += length - used }
            let frame = horizontal ? CGRect(x: offset, y: edgeInsets.top, width: along, height: alignment == 0 ? across : min(size.height, across))
                : CGRect(x: edgeInsets.left, y: offset, width: alignment == 1 || across < size.width ? across : across, height: along)
            if view.frame != frame { Send.void(view.objcObject, "setFrame:", rect: frame) }
            offset += along + spacing
        }
        super.layout()
    }
}

/// One of a stack view's archived containers of views.
@ObjCClass("NSStackViewContainer")
open class NSStackViewContainer: NSView {
    var views: [NSView] = []

    public required init() { super.init() }

    @ObjCMethod("initWithFrame:")
    public required init(frame: CGRect) { super.init(frame: frame) }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init(coder: coder)
        guard let coder else { return }
        views = Coder(coder: coder).array("NSStackViewContainerNonDroppedViews").compactMap { $0.as(NSView.self) }
        if views.isEmpty { views = subviews }
    }
}

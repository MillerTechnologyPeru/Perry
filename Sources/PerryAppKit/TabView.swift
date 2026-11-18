import CPerryGeometry
import Glibc
import PerryObjCInterop

// NSTabView: one of its items' views at a time, chosen by a row of tabs
// across its top, which a click selects. Without tabs (the "no tabs" types)
// the program chooses, as a wizard's pages are. The delegate hears a
// selection change, and may refuse it. Nibs keep the items in
// "NSTabViewItems" and the one shown in "NSSelectedTabViewItem".

@ObjCClass("NSTabViewItem")
open class NSTabViewItem: NSObject {
    var identifier: NSObject?
    var label = ""
    var toolTip: String?
    var color: NSColor?
    var view: NSView?
    var initialFirstResponder: NSObject?
    /// Not retained.
    var tabViewObject: UnsafeMutableRawPointer?
    var image: NSObject?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithIdentifier:")
    public required init(identifier: NSObject?) {
        self.identifier = identifier
        super.init()
    }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init()
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        identifier = decoded.object("NSIdentifier")
        label = decoded.string("NSLabel") ?? ""
        toolTip = decoded.string("NSToolTip")
        color = decoded.object("NSColor")?.as(NSColor.self)
        view = decoded.object("NSView")?.as(NSView.self)
        initialFirstResponder = decoded.object("NSFirstResponder")
        tabViewObject = decoded.object("NSTabView")?.objcObject
    }

    var tabView: NSTabView? { tabViewObject.map { NSTabView.objCInstance($0, ownership: .retain) } }

    @ObjCMethod("identifier") func itemIdentifier() -> NSObject? { identifier }
    @ObjCMethod("setIdentifier:") func setIdentifier(_ value: NSObject?) { identifier = value }
    @ObjCMethod("label") func itemLabel() -> String { label }
    @ObjCMethod("setLabel:")
    func setLabel(_ value: String?) {
        label = value ?? ""
        tabView?.setNeedsDisplay(true)
    }
    @ObjCMethod("toolTip") func itemToolTip() -> String? { toolTip }
    @ObjCMethod("setToolTip:") func setToolTip(_ value: String?) { toolTip = value }
    @ObjCMethod("color") func itemColor() -> NSColor? { color }
    @ObjCMethod("setColor:") func setColor(_ value: NSColor?) { color = value }
    @ObjCMethod("image") func itemImage() -> NSObject? { image }
    @ObjCMethod("setImage:") func setImage(_ value: NSObject?) { image = value }
    @ObjCMethod("view") func itemView() -> NSView? { view }
    @ObjCMethod("setView:")
    func setView(_ value: NSView?) {
        let old = view
        view = value
        if let tabView = tabView, tabView.selected === self {
            old?.removeFromSuperview()
            tabView.showSelected()
        }
    }
    @ObjCMethod("initialFirstResponder") func itemInitialFirstResponder() -> NSObject? { initialFirstResponder }
    @ObjCMethod("setInitialFirstResponder:") func setInitialFirstResponder(_ value: NSObject?) { initialFirstResponder = value }
    @ObjCMethod("tabView") func itemTabView() -> NSTabView? { tabView }
    @ObjCMethod("_setTabView:") func setTabView(_ value: NSTabView?) { tabViewObject = value?.objcObject }
    @ObjCMethod("viewController") func viewController() -> NSObject? { nil }

    /// NSTabState: selected 0, background 1, pressed 2.
    @ObjCMethod("tabState")
    func tabState() -> UInt { tabView?.selected === self ? 0 : 1 }

    @ObjCMethod("sizeOfLabel:")
    func sizeOfLabel(_ shouldTruncate: Bool) -> CGSize {
        let font = tabView?.font ?? NSFont.system(size: 13)
        return CGSize(width: Text.width(label, font: font), height: Text.lineHeight(font))
    }

    @ObjCMethod("drawLabel:inRect:")
    func drawLabel(_ shouldTruncate: Bool, in rect: CGRect) {
        var style = TextStyle()
        style.alignment = 1
        style.maximumLines = 1
        style.lineBreakMode = shouldTruncate ? 4 : 2
        let font = tabView?.font ?? NSFont.system(size: 13)
        let color = tabView?.selected === self ? NSColor.alternateSelectedControlTextColor() : NSColor.controlTextColor()
        Text.draw([TextRun(text: label, font: font, color: color)], in: rect, style: style)
    }
}

@ObjCClass("NSTabView")
open class NSTabView: NSView {
    var items: [NSTabViewItem] = []
    var selected: NSTabViewItem?
    /// NSTabViewType: tabs on top 0, left 1, bottom 2, right 3; no tabs with
    /// a bezel 4, a line 5, or no border 6.
    var tabViewType: UInt = 0
    var font: NSFont = NSFont.system(size: 13)
    var allowsTruncatedLabels = true
    var drawsBackground = true
    var controlSize: UInt = 0
    /// Not retained.
    var delegateObject: UnsafeMutableRawPointer?

    static let tabHeight: CGFloat = 24

    public required init() { super.init() }

    @ObjCMethod("initWithFrame:")
    public required init(frame: CGRect) { super.init(frame: frame) }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init(coder: coder)
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        items = decoded.array("NSTabViewItems").compactMap { $0.as(NSTabViewItem.self) }
        for item in items { item.tabViewObject = objcObject }
        if let font = decoded.object("NSFont")?.as(NSFont.self) { self.font = font }
        if decoded.has("NSTvFlags") { tabViewType = UInt(decoded.integer("NSTvFlags") & 7) }
        if decoded.has("NSAllowTruncatedLabels") { allowsTruncatedLabels = decoded.bool("NSAllowTruncatedLabels") }
        if decoded.has("NSDrawsBackground") { drawsBackground = decoded.bool("NSDrawsBackground") }
        delegateObject = decoded.object("NSDelegate")?.objcObject
        // The views of the items not shown are not subviews.
        let chosen = decoded.object("NSSelectedTabViewItem")?.as(NSTabViewItem.self) ?? items.first
        for item in items where item !== chosen { item.view?.removeFromSuperview() }
        selected = chosen
        showSelected()
    }

    @ObjCMethod("isFlipped") override func isFlipped() -> Bool { true }

    var hasTabs: Bool { tabViewType < 4 }

    /// Where the selected item's view goes.
    @ObjCMethod("contentRect")
    func contentRect() -> CGRect {
        switch tabViewType {
        case 6: return bounds
        case 4, 5: return bounds.insetBy(dx: 1, dy: 1)
        default:
            let top = Self.tabHeight / 2
            return CGRect(x: 4, y: top + Self.tabHeight / 2 + 4, width: max(bounds.width - 8, 0),
                          height: max(bounds.height - top - Self.tabHeight / 2 - 8, 0))
        }
    }

    @ObjCMethod("minimumSize") func minimumSize() -> CGSize { CGSize(width: 0, height: hasTabs ? Self.tabHeight + 8 : 0) }

    /// The selected item's view, in the content rect.
    func showSelected() {
        guard let view = selected?.view else { return setNeedsDisplay(true) }
        if view.superviewObject != objcObject { addSubview(view) }
        view.setFrame(contentRect())
        view.autoresizingMask = 18      // width and height
        setNeedsDisplay(true)
    }

    @ObjCMethod("setFrameSize:")
    override func setFrameSize(_ size: CGSize) {
        super.setFrameSize(size)
        selected?.view?.setFrame(contentRect())
    }

    // MARK: Items

    @ObjCMethod("tabViewItems") func tabViewItems() -> NSObject { NSMutableArray.of(items) }
    @ObjCMethod("numberOfTabViewItems") func numberOfTabViewItems() -> Int { items.count }
    @ObjCMethod("tabViewItemAtIndex:") func tabViewItem(at index: Int) -> NSTabViewItem? { items.indices.contains(index) ? items[index] : nil }
    @ObjCMethod("indexOfTabViewItem:")
    func index(of item: NSTabViewItem?) -> Int { items.firstIndex { $0 === item } ?? Int.max }   // NSNotFound
    @ObjCMethod("indexOfTabViewItemWithIdentifier:")
    func index(ofIdentifier identifier: NSObject?) -> Int {
        items.firstIndex { item in
            guard let mine = item.identifier, let identifier else { return item.identifier == nil && identifier == nil }
            return mine.objcObject == identifier.objcObject || Send.bool(mine.objcObject, "isEqual:", identifier.objcObject)
        } ?? Int.max
    }
    @ObjCMethod("tabViewItemWithLabel:")
    func tabViewItem(withLabel label: String?) -> NSTabViewItem? { items.first { $0.label == label } }
    @ObjCMethod("selectedTabViewItem") func selectedTabViewItem() -> NSTabViewItem? { selected }

    @ObjCMethod("addTabViewItem:") func addTabViewItem(_ item: NSTabViewItem?) { insertTabViewItem(item, at: items.count) }

    @ObjCMethod("insertTabViewItem:atIndex:")
    func insertTabViewItem(_ item: NSTabViewItem?, at index: Int) {
        guard let item else { return }
        items.insert(item, at: min(max(index, 0), items.count))
        item.tabViewObject = objcObject
        if selected == nil { selectTabViewItem(item) }
        tell("tabViewDidChangeNumberOfTabViewItems:", nil)
        setNeedsDisplay(true)
    }

    @ObjCMethod("removeTabViewItem:")
    func removeTabViewItem(_ item: NSTabViewItem?) {
        guard let item, let index = items.firstIndex(where: { $0 === item }) else { return }
        items.remove(at: index)
        item.view?.removeFromSuperview()
        item.tabViewObject = nil
        if selected === item {
            selected = nil
            if !items.isEmpty { selectTabViewItem(items[min(index, items.count - 1)]) }
        }
        tell("tabViewDidChangeNumberOfTabViewItems:", nil)
        setNeedsDisplay(true)
    }

    // MARK: Selection

    func tell(_ selector: String, _ item: NSTabViewItem?) {
        guard Send.responds(delegateObject, selector) else { return }
        if selector.hasSuffix("Items:") {
            Send.void(delegateObject, selector, objcObject)
        } else {
            Send.void(delegateObject, selector, objcObject, item?.objcObject)
        }
    }

    @ObjCMethod("selectTabViewItem:")
    func selectTabViewItem(_ item: NSTabViewItem?) {
        guard let item, item !== selected, items.contains(where: { $0 === item }) else { return }
        if Send.responds(delegateObject, "tabView:shouldSelectTabViewItem:") {
            typealias Should = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer, UnsafeMutableRawPointer, UnsafeMutableRawPointer) -> Bool
            let should = unsafeBitCast(ObjCRuntime.msgSend, to: Should.self)
            if !should(delegateObject, ObjCRuntime.selector("tabView:shouldSelectTabViewItem:"), objcObject, item.objcObject) { return }
        }
        tell("tabView:willSelectTabViewItem:", item)
        selected?.view?.removeFromSuperview()
        selected = item
        showSelected()
        if let first = item.initialFirstResponder { _ = window?.makeFirstResponder(first) }
        tell("tabView:didSelectTabViewItem:", item)
    }

    @ObjCMethod("selectTabViewItemAtIndex:")
    func selectTabViewItem(at index: Int) {
        guard items.indices.contains(index) else { return }
        selectTabViewItem(items[index])
    }
    @ObjCMethod("selectTabViewItemWithIdentifier:")
    func selectTabViewItem(withIdentifier identifier: NSObject?) { selectTabViewItem(at: index(ofIdentifier: identifier)) }
    @ObjCMethod("selectFirstTabViewItem:") func selectFirstTabViewItem(_ sender: NSObject?) { selectTabViewItem(at: 0) }
    @ObjCMethod("selectLastTabViewItem:") func selectLastTabViewItem(_ sender: NSObject?) { selectTabViewItem(at: items.count - 1) }
    @ObjCMethod("selectNextTabViewItem:")
    func selectNextTabViewItem(_ sender: NSObject?) { selectTabViewItem(at: index(of: selected) == Int.max ? 0 : index(of: selected) + 1) }
    @ObjCMethod("selectPreviousTabViewItem:")
    func selectPreviousTabViewItem(_ sender: NSObject?) { selectTabViewItem(at: index(of: selected) - 1) }
    @ObjCMethod("takeSelectedTabViewItemFromSender:")
    func takeSelectedTabViewItem(fromSender sender: NSObject?) {
        guard let sender else { return }
        typealias Index = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer) -> Int
        selectTabViewItem(at: unsafeBitCast(ObjCRuntime.msgSend, to: Index.self)(sender.objcObject, ObjCRuntime.selector("indexOfSelectedItem")))
    }

    // MARK: Settings

    @ObjCMethod("tabViewType") func type() -> UInt { tabViewType }
    @ObjCMethod("setTabViewType:")
    func setTabViewType(_ value: UInt) {
        tabViewType = value
        showSelected()
    }
    @ObjCMethod("font") func tabFont() -> NSFont { font }
    @ObjCMethod("setFont:") func setFont(_ value: NSFont?) { font = value ?? font; setNeedsDisplay(true) }
    @ObjCMethod("allowsTruncatedLabels") func tabAllowsTruncatedLabels() -> Bool { allowsTruncatedLabels }
    @ObjCMethod("setAllowsTruncatedLabels:") func setAllowsTruncatedLabels(_ value: Bool) { allowsTruncatedLabels = value }
    @ObjCMethod("drawsBackground") func tabDrawsBackground() -> Bool { drawsBackground }
    @ObjCMethod("setDrawsBackground:") func setDrawsBackground(_ value: Bool) { drawsBackground = value; setNeedsDisplay(true) }
    @ObjCMethod("controlSize") func tabControlSize() -> UInt { controlSize }
    @ObjCMethod("setControlSize:") func setControlSize(_ value: UInt) { controlSize = value }
    @ObjCMethod("controlTint") func controlTint() -> UInt { 0 }
    @ObjCMethod("setControlTint:") func setControlTint(_ value: UInt) {}
    @ObjCMethod("delegate") func tabDelegate() -> NSObject? { delegateObject.map(NSObject.init) }
    @ObjCMethod("setDelegate:") func setDelegate(_ value: NSObject?) { delegateObject = value?.objcObject }

    // MARK: Tabs

    /// Each tab's rectangle, centered along the top.
    var tabRects: [CGRect] {
        guard hasTabs, !items.isEmpty else { return [] }
        let widths = items.map { Text.width($0.label, font: font) + 24 }
        var x = ((bounds.width - widths.reduce(0, +)) / 2).rounded(.down)
        return widths.map { width in
            defer { x += width }
            return CGRect(x: x, y: 0, width: width, height: Self.tabHeight)
        }
    }

    @ObjCMethod("tabViewItemAtPoint:")
    func tabViewItem(at point: CGPoint) -> NSTabViewItem? {
        let rects = tabRects
        return rects.firstIndex { $0.contains(point) }.map { items[$0] }
    }

    @ObjCMethod("mouseDown:")
    override func mouseDown(_ event: NSObject?) {
        guard let event = event?.as(NSEvent.self), let item = tabViewItem(at: convert(event.locationInWindow, from: nil)) else {
            return super.mouseDown(event)
        }
        selectTabViewItem(item)
    }

    @ObjCMethod("drawRect:")
    override func draw(_ rect: CGRect) {
        guard let context = NSGraphicsContext.currentCG else { return }
        switch tabViewType {
        case 6:
            return
        case 4, 5:
            CG.stroke(CG.roundedRect(bounds.insetBy(dx: 0.5, dy: 0.5), radius: tabViewType == 4 ? 4 : 0),
                      NSColor(white: 0, alpha: 0.18), in: context)
            return
        default:
            break
        }
        // The pane: a rounded box from the middle of the tabs down.
        let pane = CGRect(x: 0.5, y: Self.tabHeight / 2 + 0.5, width: bounds.width - 1, height: bounds.height - Self.tabHeight / 2 - 1)
        if drawsBackground { CG.fill(CG.roundedRect(pane, radius: 5), NSColor(white: 0, alpha: 0.04), in: context) }
        CG.stroke(CG.roundedRect(pane, radius: 5), NSColor(white: 0, alpha: 0.15), in: context)
        // The tabs: one segmented control, the selected tab filled.
        let rects = tabRects
        guard let first = rects.first, let last = rects.last else { return }
        let bar = CGRect(x: first.minX, y: 0, width: last.maxX - first.minX, height: Self.tabHeight)
        CG.fill(CG.roundedRect(bar, radius: 6), NSColor.controlColor(), in: context)
        CG.stroke(CG.roundedRect(bar.insetBy(dx: 0.5, dy: 0.5), radius: 6), NSColor(white: 0, alpha: 0.2), in: context)
        for (item, tab) in zip(items, rects) {
            if item === selected {
                CG.fill(CG.roundedRect(tab.insetBy(dx: 1, dy: 1), radius: 5), NSColor.controlAccentColor(), in: context)
            }
            let textHeight = Text.lineHeight(font)
            item.drawLabel(allowsTruncatedLabels, in: CGRect(x: tab.minX + 6, y: ((Self.tabHeight - textHeight) / 2).rounded(),
                                                             width: tab.width - 12, height: textHeight))
        }
    }
}

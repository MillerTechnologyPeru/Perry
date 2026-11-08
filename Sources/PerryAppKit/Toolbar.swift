import CPerryGeometry
import PerryObjCInterop

// NSToolbar and its items: a window's toolbar shows across the top of the
// window, above the content view, its items' views (or their images and
// labels) in order, with flexible spaces sharing what is left. A click on
// an item without a view sends its action.

@ObjCClass("NSToolbar")
open class NSToolbar: NSObject {
    var identifier = ""
    var items: [NSToolbarItem] = []
    var defaultIdentifiers: [String] = []
    var allowedIdentifiers: [String] = []
    var identifiedItems: [String: NSToolbarItem] = [:]
    /// Not retained.
    var delegateObject: UnsafeMutableRawPointer?
    var visible = true
    /// NSToolbarDisplayMode: default 0, icon and label 1, icon only 2, label only 3.
    var displayMode: UInt = 0
    var sizeMode: UInt = 0
    var allowsUserCustomization = false
    var autosavesConfiguration = false
    var selectedItemIdentifier: String?
    var centeredItemIdentifier: String?
    var showsBaselineSeparator = true
    /// Not retained.
    var windowObject: UnsafeMutableRawPointer?
    var loaded = false

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithIdentifier:")
    public required init(identifier: String?) {
        super.init()
        self.identifier = identifier ?? ""
    }

    /// A nib's toolbar: its items by identifier and the default ones.
    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init()
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        identifier = decoded.string("NSToolbarIdentifier") ?? ""
        displayMode = UInt(decoded.integer("NSToolbarDisplayMode"))
        sizeMode = UInt(decoded.integer("NSToolbarSizeMode"))
        allowsUserCustomization = decoded.bool("NSToolbarAllowsUserCustomization")
        autosavesConfiguration = decoded.bool("NSToolbarAutosavesConfiguration")
        visible = !decoded.has("NSToolbarPrefersToBeShown") || decoded.bool("NSToolbarPrefersToBeShown")
        centeredItemIdentifier = decoded.string("NSToolbarCenteredItemIdentifier")
        for (key, item) in decoded.dictionary("NSToolbarIBIdentifiedItems") {
            if let item = item.as(NSToolbarItem.self) { identifiedItems[key] = item }
        }
        let defaults = decoded.array("NSToolbarIBDefaultItems").compactMap { $0.as(NSToolbarItem.self) }
        items = defaults
        defaultIdentifiers = defaults.map(\.identifier)
        allowedIdentifiers = decoded.array("NSToolbarIBAllowedItems").compactMap { $0.as(NSToolbarItem.self)?.identifier }
        delegateObject = decoded.object("NSToolbarDelegate")?.objcObject
        loaded = true
        for item in items { item.toolbarObject = objcObject }
    }

    var window: NSWindow? { windowObject.map(NSWindow.wrap) }

    /// Items from the delegate, the first time they are needed.
    func loadItems() {
        guard !loaded else { return }
        loaded = true
        guard let delegateObject, Send.responds(delegateObject, "toolbarDefaultItemIdentifiers:") else { return }
        let identifiers = Send.object(delegateObject, "toolbarDefaultItemIdentifiers:", objcObject).map(NSObject.init)?.as(NSArray.self)?.elements ?? []
        for identifier in identifiers {
            if let item = makeItem(identifier.stringValue) { items.append(item) }
        }
    }

    private func makeItem(_ identifier: String) -> NSToolbarItem? {
        if let standard = NSToolbarItem.standard(identifier) { return standard }
        guard let delegateObject else { return identifiedItems[identifier] }
        typealias F = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, UnsafeMutableRawPointer, UnsafeMutableRawPointer?, Bool) -> UnsafeMutableRawPointer?
        let made = unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(delegateObject, ObjCRuntime.selector("toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:"),
                                                                 objcObject, identifier.objCArgument(), true)
        let item = made.map(NSObject.init)?.as(NSToolbarItem.self) ?? identifiedItems[identifier]
        item?.toolbarObject = objcObject
        return item
    }

    @ObjCMethod("identifier") func toolbarIdentifier() -> String { identifier }
    @ObjCMethod("items") func toolbarItems() -> NSObject { loadItems(); return NSMutableArray.of(items) }
    @ObjCMethod("visibleItems") func visibleItems() -> NSObject { loadItems(); return NSMutableArray.of(items.filter { $0.visible }) }
    @ObjCMethod("delegate") func toolbarDelegate() -> NSObject? { delegateObject.map(NSObject.init) }
    @ObjCMethod("setDelegate:")
    func setDelegate(_ value: NSObject?) {
        delegateObject = value?.objcObject
        if items.isEmpty { loaded = false }
        window?.toolbarChanged()
    }
    @ObjCMethod("isVisible") func isVisible() -> Bool { visible }
    @ObjCMethod("setVisible:") func setVisible(_ value: Bool) { visible = value; window?.toolbarChanged() }
    @ObjCMethod("displayMode") func toolbarDisplayMode() -> UInt { displayMode }
    @ObjCMethod("setDisplayMode:") func setDisplayMode(_ value: UInt) { displayMode = value; window?.toolbarChanged() }
    @ObjCMethod("sizeMode") func toolbarSizeMode() -> UInt { sizeMode }
    @ObjCMethod("setSizeMode:") func setSizeMode(_ value: UInt) { sizeMode = value }
    @ObjCMethod("allowsUserCustomization") func toolbarAllowsUserCustomization() -> Bool { allowsUserCustomization }
    @ObjCMethod("setAllowsUserCustomization:") func setAllowsUserCustomization(_ value: Bool) { allowsUserCustomization = value }
    @ObjCMethod("autosavesConfiguration") func toolbarAutosavesConfiguration() -> Bool { autosavesConfiguration }
    @ObjCMethod("setAutosavesConfiguration:") func setAutosavesConfiguration(_ value: Bool) { autosavesConfiguration = value }
    @ObjCMethod("selectedItemIdentifier") func toolbarSelectedItemIdentifier() -> String? { selectedItemIdentifier }
    @ObjCMethod("setSelectedItemIdentifier:") func setSelectedItemIdentifier(_ value: String?) { selectedItemIdentifier = value; window?.toolbarChanged() }
    @ObjCMethod("centeredItemIdentifier") func toolbarCenteredItemIdentifier() -> String? { centeredItemIdentifier }
    @ObjCMethod("setCenteredItemIdentifier:") func setCenteredItemIdentifier(_ value: String?) { centeredItemIdentifier = value }
    @ObjCMethod("showsBaselineSeparator") func toolbarShowsBaselineSeparator() -> Bool { showsBaselineSeparator }
    @ObjCMethod("setShowsBaselineSeparator:") func setShowsBaselineSeparator(_ value: Bool) { showsBaselineSeparator = value }
    @ObjCMethod("insertItemWithItemIdentifier:atIndex:")
    func insertItem(withItemIdentifier identifier: String?, at index: Int) {
        loadItems()
        guard let identifier, let item = makeItem(identifier) else { return }
        items.insert(item, at: max(0, min(index, items.count)))
        window?.toolbarChanged()
    }
    @ObjCMethod("removeItemAtIndex:")
    func removeItem(at index: Int) {
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
        window?.toolbarChanged()
    }
    @ObjCMethod("validateVisibleItems") func validateVisibleItems() {}
    @ObjCMethod("runCustomizationPalette:") func runCustomizationPalette(_ sender: NSObject?) {}
    @ObjCMethod("customizationPaletteIsRunning") func customizationPaletteIsRunning() -> Bool { false }
    @ObjCMethod("setConfigurationFromDictionary:") func setConfiguration(from dictionary: NSObject?) {}
    @ObjCMethod("configurationDictionary") func configurationDictionary() -> NSObject { NSMutableDictionary.empty() }
}

@ObjCClass("NSToolbarItem")
open class NSToolbarItem: NSObject {
    var identifier = ""
    var label = ""
    var paletteLabel = ""
    var toolTip: String?
    var image: NSImage?
    var view: NSView?
    var minSize = CGSize.zero
    var maxSize = CGSize.zero
    /// Not retained.
    var target: UnsafeMutableRawPointer?
    var action: ObjCSelector?
    var enabled = true
    var tag = 0
    var bordered = false
    var title = ""
    var autovalidates = true
    var visibilityPriority = 0
    var navigational = false
    var menuFormRepresentation: NSObject?
    var hidden = false
    /// Not retained.
    var toolbarObject: UnsafeMutableRawPointer?

    var visible: Bool { !hidden }

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithItemIdentifier:")
    public required init(itemIdentifier identifier: String?) {
        super.init()
        self.identifier = identifier ?? ""
    }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init()
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        identifier = decoded.string("NSToolbarItemIdentifier") ?? ""
        label = decoded.string("NSToolbarItemLabel") ?? ""
        paletteLabel = decoded.string("NSToolbarItemPaletteLabel") ?? ""
        toolTip = decoded.string("NSToolbarItemToolTip")
        image = decoded.object("NSToolbarItemImage")?.as(NSImage.self)
        view = decoded.object("NSToolbarItemView")?.as(NSView.self)
        minSize = decoded.size("NSToolbarItemMinSize")
        maxSize = decoded.size("NSToolbarItemMaxSize")
        target = decoded.object("NSToolbarItemTarget")?.objcObject
        action = decoded.selector("NSToolbarItemAction")
        enabled = !decoded.has("NSToolbarItemEnabled") || decoded.bool("NSToolbarItemEnabled")
        tag = decoded.integer("NSToolbarItemTag")
        bordered = decoded.bool("NSToolbarItemBordered")
        title = decoded.string("NSToolbarItemTitle") ?? ""
        autovalidates = decoded.bool("NSToolbarItemAutovalidates")
        visibilityPriority = decoded.integer("NSToolbarItemVisibilityPriority")
        navigational = decoded.bool("NSToolbarItemNavigational")
        menuFormRepresentation = decoded.object("NSToolbarItemMenuFormRepresentation")
    }

    /// The items AppKit provides by identifier: spaces, separators and the
    /// sidebar's button.
    static func standard(_ identifier: String) -> NSToolbarItem? {
        switch identifier {
        case "NSToolbarFlexibleSpaceItem": return NSToolbarFlexibleSpaceItem(itemIdentifier: identifier)
        case "NSToolbarSpaceItem", "NSToolbarSeparatorItem": return NSToolbarSpaceItem(itemIdentifier: identifier)
        case "NSToolbarSidebarTrackingSeparatorItemIdentifier":
            // The window's split view's first divider, found when laid out.
            return NSTrackingSeparatorToolbarItem(itemIdentifier: identifier)
        case "NSToolbarToggleSidebarItemIdentifier":
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = "Sidebar"
            item.image = NSImage.image(systemSymbolName: "sidebar.left", accessibilityDescription: nil)
            item.action = ObjCSelector("toggleSidebar:")
            return item
        default: return nil
        }
    }

    var isFlexibleSpace: Bool { false }
    var isSpace: Bool { false }
    /// Where a tracking separator's divider is, in the toolbar view.
    func trackedDividerX(in view: ToolbarView) -> CGFloat? { nil }

    @ObjCMethod("itemIdentifier") func itemIdentifier() -> String { identifier }
    @ObjCMethod("toolbar") func toolbar() -> NSToolbar? { toolbarObject.map { NSToolbar.objCInstance($0, ownership: .retain) } }
    @ObjCMethod("label") func itemLabel() -> String { label }
    @ObjCMethod("setLabel:") func setLabel(_ value: String?) { label = value ?? ""; changed() }
    @ObjCMethod("paletteLabel") func itemPaletteLabel() -> String { paletteLabel }
    @ObjCMethod("setPaletteLabel:") func setPaletteLabel(_ value: String?) { paletteLabel = value ?? "" }
    @ObjCMethod("toolTip") func itemToolTip() -> String? { toolTip }
    @ObjCMethod("setToolTip:") func setToolTip(_ value: String?) { toolTip = value }
    @ObjCMethod("image") func itemImage() -> NSImage? { image }
    @ObjCMethod("setImage:") func setImage(_ value: NSImage?) { image = value; changed() }
    @ObjCMethod("view") func itemView() -> NSView? { view }
    @ObjCMethod("setView:") func setView(_ value: NSView?) { view = value; changed() }
    @ObjCMethod("minSize") func itemMinSize() -> CGSize { minSize }
    @ObjCMethod("setMinSize:") func setMinSize(_ value: CGSize) { minSize = value; changed() }
    @ObjCMethod("maxSize") func itemMaxSize() -> CGSize { maxSize }
    @ObjCMethod("setMaxSize:") func setMaxSize(_ value: CGSize) { maxSize = value; changed() }
    @ObjCMethod("target") func itemTarget() -> NSObject? { target.map(NSObject.init) }
    @ObjCMethod("setTarget:") func setTarget(_ value: NSObject?) { target = value?.objcObject }
    @ObjCMethod("action") func itemAction() -> ObjCSelector? { action }
    @ObjCMethod("setAction:") func setAction(_ value: ObjCSelector?) { action = value }
    @ObjCMethod("isEnabled") func isEnabled() -> Bool { enabled }
    @ObjCMethod("setEnabled:") func setEnabled(_ value: Bool) { enabled = value; changed() }
    @ObjCMethod("tag") func itemTag() -> Int { tag }
    @ObjCMethod("setTag:") func setTag(_ value: Int) { tag = value }
    @ObjCMethod("isBordered") func isBordered() -> Bool { bordered }
    @ObjCMethod("setBordered:") func setBordered(_ value: Bool) { bordered = value; changed() }
    @ObjCMethod("title") func itemTitle() -> String { title }
    @ObjCMethod("setTitle:") func setTitle(_ value: String?) { title = value ?? ""; changed() }
    @ObjCMethod("autovalidates") func itemAutovalidates() -> Bool { autovalidates }
    @ObjCMethod("setAutovalidates:") func setAutovalidates(_ value: Bool) { autovalidates = value }
    @ObjCMethod("visibilityPriority") func itemVisibilityPriority() -> Int { visibilityPriority }
    @ObjCMethod("setVisibilityPriority:") func setVisibilityPriority(_ value: Int) { visibilityPriority = value }
    @ObjCMethod("isNavigational") func isNavigational() -> Bool { navigational }
    @ObjCMethod("setNavigational:") func setNavigational(_ value: Bool) { navigational = value }
    @ObjCMethod("menuFormRepresentation") func itemMenuFormRepresentation() -> NSObject? { menuFormRepresentation }
    @ObjCMethod("setMenuFormRepresentation:") func setMenuFormRepresentation(_ value: NSObject?) { menuFormRepresentation = value }
    @ObjCMethod("isVisible") func isVisible() -> Bool { visible }
    @ObjCMethod("isHidden") func isHidden() -> Bool { hidden }
    @ObjCMethod("setHidden:") func setHidden(_ value: Bool) { hidden = value; changed() }
    @ObjCMethod("validate") func validate() {}
    @ObjCMethod("allowsDuplicatesInToolbar") func allowsDuplicatesInToolbar() -> Bool { false }

    func changed() { toolbar()?.window?.toolbarChanged() }
}

@ObjCClass("NSToolbarFlexibleSpaceItem")
open class NSToolbarFlexibleSpaceItem: NSToolbarItem {
    override var isFlexibleSpace: Bool { true }
}

/// A group of items shown as one, such as a segmented control's segments:
/// the group's view is the control, and its subitems are the segments' items.
@ObjCClass("NSToolbarItemGroup")
open class NSToolbarItemGroup: NSToolbarItem {
    var subitems: [NSToolbarItem] = []
    var selectedIndex = -1
    var selectionMode = 0
    var controlRepresentation = 0

    @ObjCMethod("subitems") func groupSubitems() -> NSObject { NSMutableArray.of(subitems.map { NSObject($0.objcObject) }) }
    @ObjCMethod("setSubitems:") func setSubitems(_ items: NSObject?) {
        subitems = items?.as(NSArray.self)?.elements.compactMap { $0.as(NSToolbarItem.self) } ?? []
        changed()
    }
    @ObjCMethod("selectedIndex") func groupSelectedIndex() -> Int { selectedIndex }
    @ObjCMethod("setSelectedIndex:") func setSelectedIndex(_ index: Int) { selectedIndex = index }
    @ObjCMethod("setSelected:atIndex:") func setSelected(_ selected: Bool, at index: Int) { selectedIndex = selected ? index : -1 }
    @ObjCMethod("isSelectedAtIndex:") func isSelected(at index: Int) -> Bool { selectedIndex == index }
    @ObjCMethod("selectionMode") func groupSelectionMode() -> Int { selectionMode }
    @ObjCMethod("setSelectionMode:") func setSelectionMode(_ mode: Int) { selectionMode = mode }
    @ObjCMethod("controlRepresentation") func groupControlRepresentation() -> Int { controlRepresentation }
    @ObjCMethod("setControlRepresentation:") func setControlRepresentation(_ value: Int) { controlRepresentation = value }
}

@ObjCClass("NSToolbarSpaceItem")
open class NSToolbarSpaceItem: NSToolbarItem {
    override var isSpace: Bool { true }
}

/// Lines the items after it up with a split view's divider: the toolbar's
/// sections sit over the panes.
@ObjCClass("NSTrackingSeparatorToolbarItem")
open class NSTrackingSeparatorToolbarItem: NSToolbarItem {
    weak var splitView: NSSplitView?
    var dividerIndex = 0

    @ObjCClassMethod("trackingSeparatorToolbarItemWithIdentifier:splitView:dividerIndex:")
    class func item(identifier: String?, splitView: NSSplitView?, dividerIndex: Int) -> NSTrackingSeparatorToolbarItem {
        let item = NSTrackingSeparatorToolbarItem(itemIdentifier: identifier)
        item.splitView = splitView
        item.dividerIndex = dividerIndex
        return item
    }

    @ObjCMethod("splitView") func trackedSplitView() -> NSSplitView? { splitView }
    @ObjCMethod("setSplitView:") func setSplitView(_ value: NSSplitView?) { splitView = value; changed() }
    @ObjCMethod("dividerIndex") func trackedDividerIndex() -> Int { dividerIndex }
    @ObjCMethod("setDividerIndex:") func setDividerIndex(_ value: Int) { dividerIndex = value; changed() }

    override func trackedDividerX(in view: ToolbarView) -> CGFloat? {
        guard let splitView = splitView ?? view.window?.contentView.flatMap(Self.firstSplitView), splitView.vertical,
              splitView.window != nil else { return nil }
        let dividers = splitView.dividers
        guard dividers.indices.contains(dividerIndex) else { return nil }
        let divider = dividers[dividerIndex]
        return view.convert(splitView.convert(CGPoint(x: divider.maxX, y: divider.minY), to: nil), from: nil).x
    }

    private static func firstSplitView(_ view: NSView) -> NSSplitView? {
        if let split = view as? NSSplitView, split.vertical { return split }
        for subview in view.subviews { if let found = firstSplitView(subview) { return found } }
        return nil
    }
}

/// A search field in the toolbar.
@ObjCClass("NSSearchToolbarItem")
open class NSSearchToolbarItem: NSToolbarItem {
    var preferredWidth: CGFloat = 220
    var resignsFirstResponderWithCancel = true

    var field: NSSearchField {
        if let field = view?.as(NSSearchField.self) { return field }
        let field = NSSearchField(frame: CGRect(x: 0, y: 0, width: preferredWidth, height: 22))
        view = field
        minSize = CGSize(width: 140, height: 22)
        maxSize = CGSize(width: preferredWidth, height: 22)
        return field
    }

    @ObjCMethod("searchField") func searchField() -> NSSearchField { field }
    @ObjCMethod("setSearchField:")
    func setSearchField(_ value: NSSearchField?) {
        view = value
        changed()
    }
    @ObjCMethod("view") override func itemView() -> NSView? { field }
    @ObjCMethod("preferredWidthForSearchField") func preferredWidthForSearchField() -> CGFloat { preferredWidth }
    @ObjCMethod("setPreferredWidthForSearchField:")
    func setPreferredWidthForSearchField(_ value: CGFloat) {
        preferredWidth = value
        maxSize = CGSize(width: value, height: 22)
        changed()
    }
    @ObjCMethod("resignsFirstResponderWithCancel") func itemResignsFirstResponderWithCancel() -> Bool { resignsFirstResponderWithCancel }
    @ObjCMethod("setResignsFirstResponderWithCancel:") func setResignsFirstResponderWithCancel(_ value: Bool) { resignsFirstResponderWithCancel = value }
    @ObjCMethod("beginSearchInteraction") func beginSearchInteraction() { field.window?.makeFirstResponder(field) }
    @ObjCMethod("endSearchInteraction") func endSearchInteraction() {}
}

/// An image that shows a menu when pressed.
@ObjCClass("NSMenuToolbarItem")
open class NSMenuToolbarItem: NSToolbarItem {
    var menu: NSMenu?
    var showsIndicator = true

    @ObjCMethod("menu") func itemMenu() -> NSMenu? { menu }
    @ObjCMethod("setMenu:") func setMenu(_ value: NSMenu?) { menu = value }
    @ObjCMethod("showsIndicator") func itemShowsIndicator() -> Bool { showsIndicator }
    @ObjCMethod("setShowsIndicator:") func setShowsIndicator(_ value: Bool) { showsIndicator = value; changed() }
}

/// The strip across the top of a window that shows its toolbar's items.
@ObjCClass("_PerryToolbarView")
open class ToolbarView: NSView {
    /// Not retained.
    var toolbarObject: UnsafeMutableRawPointer?
    var buttons: [(item: NSToolbarItem, frame: CGRect)] = []

    static let height: CGFloat = 38

    var toolbar: NSToolbar? { toolbarObject.map { NSToolbar.objCInstance($0, ownership: .retain) } }

    @ObjCMethod("isFlipped") override func isFlipped() -> Bool { true }

    /// The items left to right: views at their size (within their min and
    /// max), images in a square, flexible spaces sharing what is left of
    /// their section. Tracking separators end a section at their split
    /// view's divider, so the next starts over the next pane.
    /// The width the items were last arranged for.
    var arrangedWidth: CGFloat = -1

    func arrange() {
        guard let toolbar else { return }
        arrangedWidth = bounds.width
        toolbar.loadItems()
        // Views stay where they are when still shown, so a search field
        // keeps its typing as dividers move.
        let shown = toolbar.items.filter(\.visible).compactMap { $0.itemView() }
        for view in subviews where !shown.contains(where: { $0 === view }) { view.removeFromSuperview() }
        buttons = []
        func width(_ item: NSToolbarItem) -> CGFloat {
            if item.isFlexibleSpace { return 0 }
            if item.isSpace { return 8 }
            if let view = item.itemView() {
                let intrinsic = Send.size(view.objcObject, "intrinsicContentSize").width
                var width = item.minSize.width > 0 ? item.minSize.width : intrinsic > 0 ? intrinsic : view.frame.width
                if item.maxSize.width > 0 { width = min(max(width, view.frame.width), item.maxSize.width) }
                return max(width, 20)
            }
            if item.image != nil { return item is NSMenuToolbarItem ? 44 : 32 }
            return max(32, Text.width(item.label, font: NSFont.system(size: 11)) + 8)
        }
        var sections: [(items: [NSToolbarItem], end: CGFloat)] = []
        var current: [NSToolbarItem] = []
        for item in toolbar.items where item.visible {
            if item is NSTrackingSeparatorToolbarItem {
                if let x = item.trackedDividerX(in: self) {
                    sections.append((current, x))
                    current = []
                }
            } else {
                current.append(item)
            }
        }
        sections.append((current, bounds.width))
        var start: CGFloat = 8
        for (items, end) in sections {
            var widths = items.map(width)
            // Too wide for its section: items that can (a search field down
            // to its min size) shrink, the last first.
            var overflow = widths.reduce(0, +) + CGFloat(max(0, items.count - 1)) * 8 - (end - 8 - start)
            for index in items.indices.reversed() where overflow > 0 && items[index].minSize.width > 0 {
                let give = min(overflow, max(0, widths[index] - items[index].minSize.width))
                widths[index] -= give
                overflow -= give
            }
            let fixed = widths.reduce(0, +) + CGFloat(max(0, items.count - 1)) * 8
            let flexible = items.filter(\.isFlexibleSpace)
            let extra = max(0, end - 8 - start - fixed)
            let share = flexible.isEmpty ? 0 : extra / CGFloat(flexible.count)
            var x = start
            for (index, item) in items.enumerated() {
                let w = item.isFlexibleSpace ? share : widths[index]
                if let view = item.itemView() {
                    let height = min(max(view.frame.height, 22), bounds.height - 8)
                    if view.superview !== self { addSubview(view) }
                    view.translatesAutoresizingMask = true
                    Send.void(view.objcObject, "setFrame:", rect: CGRect(x: x, y: ((bounds.height - height) / 2).rounded(), width: w, height: height))
                } else if !item.isFlexibleSpace && !item.isSpace {
                    buttons.append((item, CGRect(x: x, y: 5, width: w, height: bounds.height - 10)))
                }
                x += w + 8
            }
            start = max(x, end + 8)
        }
        setNeedsDisplay(true)
    }

    @ObjCMethod("setFrameSize:")
    override func setFrameSize(_ size: CGSize) {
        let old = frame.size
        super.setFrameSize(size)
        if old.width != size.width { arrange() }
    }

    @ObjCMethod("drawRect:")
    override func draw(_ rect: CGRect) {
        guard let context = NSGraphicsContext.currentCG else { return }
        // Resized without hearing of it (its window grew in one go).
        if arrangedWidth != bounds.width { arrange() }
        CG.saveGState(context)
        CG.setFill(context, NSColor.windowBackgroundColor())
        CG.fillRect(context, bounds)
        CG.setFill(context, NSColor.separatorColor())
        CG.fillRect(context, CGRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1))
        CG.restoreGState(context)
        let selected = toolbar?.selectedItemIdentifier
        for (item, frame) in buttons {
            if item.identifier == selected || item === pressed {
                CG.fill(CG.roundedRect(frame, radius: 6), NSColor.labelColor().withAlphaComponent(0.12), in: context)
            }
            if let image = item.image {
                // Icons alone, as unified toolbars show them; a menu's with
                // a small chevron after.
                let menu = (item as? NSMenuToolbarItem).map { $0.showsIndicator } ?? false
                let iconFrame = CGRect(x: frame.minX, y: frame.minY, width: frame.width - (menu ? 12 : 0), height: frame.height)
                let tint = item.enabled ? NSColor.secondaryLabelColor() : NSColor.tertiaryLabelColor()
                ImageDrawing.draw(image, fitting: iconFrame.insetBy(dx: 4, dy: 3), tint: tint)
                if menu {
                    let path = NSBezierPath()
                    path.move(to: CGPoint(x: frame.maxX - 13, y: frame.midY - 1.5))
                    path.line(to: CGPoint(x: frame.maxX - 10, y: frame.midY + 1.5))
                    path.line(to: CGPoint(x: frame.maxX - 7, y: frame.midY - 1.5))
                    tint.setStroke()
                    path.setLineWidth(1.2)
                    path.stroke()
                }
                continue
            }
            let font = NSFont.system(size: 10)
            let labelHeight = Text.lineHeight(font)
            if let image = item.image {
                ImageDrawing.draw(image, fitting: CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height - labelHeight))
            }
            var style = TextStyle()
            style.alignment = 1
            style.maximumLines = 1
            style.lineBreakMode = 4
            let color = item.enabled ? NSColor.labelColor() : NSColor.disabledControlTextColor()
            Text.draw([TextRun(text: item.label.isEmpty ? item.title : item.label, font: font, color: color)],
                      in: CGRect(x: frame.minX, y: frame.maxY - labelHeight, width: frame.width, height: labelHeight), style: style)
        }
    }

    /// The item being pressed, drawn darker.
    weak var pressed: NSToolbarItem?

    @ObjCMethod("mouseDown:")
    override func mouseDown(_ eventObject: NSObject?) {
        guard let event = eventObject?.as(NSEvent.self) else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let (item, frame) = buttons.first(where: { $0.frame.contains(point) }), item.enabled else { return }
        if let menu = (item as? NSMenuToolbarItem)?.menu {
            // Its menu, below it.
            _ = menu.popUp(positioning: nil, at: CGPoint(x: frame.minX, y: frame.maxY + 2), in: self)
            return
        }
        pressed = item
        setNeedsDisplay(true)
    }

    @ObjCMethod("mouseUp:")
    override func mouseUp(_ eventObject: NSObject?) {
        let wasPressed = pressed
        pressed = nil
        setNeedsDisplay(true)
        guard let event = eventObject?.as(NSEvent.self) else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let (item, _) = buttons.first(where: { $0.frame.contains(point) }), item === wasPressed, item.enabled,
              let action = item.action else { return }
        _ = App.shared?.sendAction(action, to: item.target.map(NSObject.init), from: item)
    }
}

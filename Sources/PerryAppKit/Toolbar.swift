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
    /// Not retained.
    var toolbarObject: UnsafeMutableRawPointer?

    var visible: Bool { true }

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

    /// The items AppKit provides by identifier: spaces and separators.
    static func standard(_ identifier: String) -> NSToolbarItem? {
        switch identifier {
        case "NSToolbarFlexibleSpaceItem": return NSToolbarFlexibleSpaceItem(itemIdentifier: identifier)
        case "NSToolbarSpaceItem": return NSToolbarSpaceItem(itemIdentifier: identifier)
        case "NSToolbarSeparatorItem", "NSToolbarSidebarTrackingSeparatorItemIdentifier": return NSToolbarSpaceItem(itemIdentifier: identifier)
        default: return nil
        }
    }

    var isFlexibleSpace: Bool { false }
    var isSpace: Bool { false }

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
    @ObjCMethod("validate") func validate() {}
    @ObjCMethod("allowsDuplicatesInToolbar") func allowsDuplicatesInToolbar() -> Bool { false }

    private func changed() { toolbar()?.window?.toolbarChanged() }
}

@ObjCClass("NSToolbarFlexibleSpaceItem")
open class NSToolbarFlexibleSpaceItem: NSToolbarItem {
    override var isFlexibleSpace: Bool { true }
}

@ObjCClass("NSToolbarSpaceItem")
open class NSToolbarSpaceItem: NSToolbarItem {
    override var isSpace: Bool { true }
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
    /// max), images and labels in a square, flexible spaces sharing what is
    /// left.
    func arrange() {
        guard let toolbar else { return }
        toolbar.loadItems()
        for view in subviews { view.removeFromSuperview() }
        buttons = []
        let items = toolbar.items
        func width(_ item: NSToolbarItem) -> CGFloat {
            if item.isFlexibleSpace { return 0 }
            if item.isSpace { return 8 }
            if let view = item.view {
                let intrinsic = Send.size(view.objcObject, "intrinsicContentSize").width
                var width = item.minSize.width > 0 ? item.minSize.width : intrinsic > 0 ? intrinsic : view.frame.width
                if item.maxSize.width > 0 { width = min(max(width, view.frame.width), item.maxSize.width) }
                return max(width, 20)
            }
            return max(32, Text.width(item.label, font: NSFont.system(size: 11)) + 8)
        }
        let fixed = items.reduce(0) { $0 + width($1) } + CGFloat(max(0, items.count - 1)) * 8
        let flexible = items.filter(\.isFlexibleSpace)
        // Without flexible spaces, a view whose max width allows it grows.
        let extra = max(0, bounds.width - 16 - fixed)
        let share = flexible.isEmpty ? 0 : extra / CGFloat(flexible.count)
        var x: CGFloat = 8
        for item in items {
            let w = item.isFlexibleSpace ? share : width(item)
            if let view = item.view {
                let height = min(max(view.frame.height, 22), bounds.height - 8)
                addSubview(view)
                view.translatesAutoresizingMask = true
                Send.void(view.objcObject, "setFrame:", rect: CGRect(x: x, y: ((bounds.height - height) / 2).rounded(), width: w, height: height))
            } else if !item.isFlexibleSpace && !item.isSpace {
                buttons.append((item, CGRect(x: x, y: 3, width: w, height: bounds.height - 6)))
            }
            x += w + 8
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
        CG.saveGState(context)
        CG.setFillColorWithColor(context, NSColor.windowBackgroundColor().cgColorRef)
        CG.fillRect(context, bounds)
        CG.setFillColorWithColor(context, NSColor.separatorColor().cgColorRef)
        CG.fillRect(context, CGRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1))
        CG.restoreGState(context)
        let selected = toolbar?.selectedItemIdentifier
        for (item, frame) in buttons {
            if item.identifier == selected { CG.fill(CG.roundedRect(frame, radius: 5), NSColor(white: 0, alpha: 0.08), in: context) }
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

    @ObjCMethod("mouseUp:")
    override func mouseUp(_ eventObject: NSObject?) {
        guard let event = eventObject?.as(NSEvent.self) else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let (item, _) = buttons.first(where: { $0.frame.contains(point) }), item.enabled, let action = item.action else { return }
        _ = App.shared?.sendAction(action, to: item.target.map(NSObject.init), from: item)
    }
}

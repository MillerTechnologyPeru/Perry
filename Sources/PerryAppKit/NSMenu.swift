import CPerryGeometry
import PerryObjCInterop

// NSMenu and NSMenuItem: menus are kept as apps build them, for apps that
// read them back, but not shown: there is no menu bar here. Key
// equivalents still reach the app as key events.

@ObjCClass("NSMenu")
open class NSMenu: NSObject {
    var title = ""
    var items: [NSMenuItem] = []
    /// Not retained.
    var supermenu: UnsafeMutableRawPointer?
    var delegate: UnsafeMutableRawPointer?
    var autoenablesItems = true
    var font: NSFont?
    var minimumWidth: CGFloat = 0

    @ObjCMethod("init")
    public required override init() { super.init() }

    /// The menu's items' font: the menu font unless one was set.
    @ObjCMethod("font") func menuFont() -> NSFont { font ?? NSFont.menuFont(ofSize: 0) }
    @ObjCMethod("setFont:") func setFont(_ value: NSFont?) { font = value }

    @ObjCMethod("initWithTitle:")
    public required init(title: String?) {
        super.init()
        self.title = title ?? ""
    }

    /// A nib's menu: "NSTitle", "NSMenuItems", and "NSName" for the menus
    /// AppKit keeps by name.
    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init()
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        title = decoded.string("NSTitle") ?? ""
        for item in decoded.array("NSMenuItems") {
            guard let item = item.as(NSMenuItem.self) else { continue }
            items.append(item)
            item.menu = objcObject
        }
        switch decoded.string("NSName") {
        case "_NSMainMenu": App.shared?.setMainMenu(self)
        case "_NSServicesMenu": App.shared?.servicesMenu = self
        case "_NSHelpMenu": App.shared?.helpMenu = self
        case "_NSWindowsMenu": App.shared?.windowsMenu = self
        default: break
        }
    }

    @ObjCMethod("title") func menuTitle() -> String { title }
    @ObjCMethod("setTitle:") func setTitle(_ title: String?) { self.title = title ?? "" }
    @ObjCMethod("supermenu") func menuSupermenu() -> NSMenu? { supermenu.map { NSMenu.objCInstance($0, ownership: .retain) } }
    @ObjCMethod("delegate") func menuDelegate() -> NSObject? { delegate.map(NSObject.init) }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { self.delegate = delegate?.objcObject }
    @ObjCMethod("autoenablesItems") func menuAutoenablesItems() -> Bool { autoenablesItems }
    @ObjCMethod("setAutoenablesItems:") func setAutoenablesItems(_ value: Bool) { autoenablesItems = value }
    @ObjCMethod("itemArray") func itemArray() -> NSObject { NSMutableArray.of(items) }
    @ObjCMethod("setItemArray:")
    func setItemArray(_ array: NSObject?) {
        items = array?.as(NSArray.self)?.elements.compactMap { $0.as(NSMenuItem.self) } ?? []
        for item in items { item.menu = objcObject }
    }
    @ObjCMethod("numberOfItems") func numberOfItems() -> Int { items.count }
    @ObjCMethod("itemAtIndex:") func item(at index: Int) -> NSMenuItem? { items.indices.contains(index) ? items[index] : nil }
    @ObjCMethod("itemWithTitle:") func item(withTitle title: String?) -> NSMenuItem? { items.first { $0.title == title } }
    @ObjCMethod("itemWithTag:") func item(withTag tag: Int) -> NSMenuItem? { items.first { $0.tag == tag } }
    @ObjCMethod("indexOfItem:") func index(of item: NSMenuItem?) -> Int { items.firstIndex { $0 === item } ?? -1 }
    @ObjCMethod("indexOfItemWithTitle:") func indexOfItem(withTitle title: String?) -> Int { items.firstIndex { $0.title == title } ?? -1 }
    @ObjCMethod("indexOfItemWithTag:") func indexOfItem(withTag tag: Int) -> Int { items.firstIndex { $0.tag == tag } ?? -1 }

    @ObjCMethod("addItem:") func addItem(_ item: NSMenuItem) { insertItem(item, at: items.count) }

    @ObjCMethod("insertItem:atIndex:")
    func insertItem(_ item: NSMenuItem, at index: Int) {
        items.insert(item, at: max(0, min(index, items.count)))
        item.menu = objcObject
    }

    @ObjCMethod("addItemWithTitle:action:keyEquivalent:")
    func addItem(title: String?, action: ObjCSelector?, keyEquivalent: String?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        addItem(item)
        return item
    }

    @ObjCMethod("insertItemWithTitle:action:keyEquivalent:atIndex:")
    func insertItem(title: String?, action: ObjCSelector?, keyEquivalent: String?, at index: Int) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        insertItem(item, at: index)
        return item
    }

    @ObjCMethod("removeItem:")
    func removeItem(_ item: NSMenuItem?) {
        items.removeAll { $0 === item }
        item?.menu = nil
    }
    @ObjCMethod("removeItemAtIndex:")
    func removeItem(at index: Int) { if items.indices.contains(index) { removeItem(items[index]) } }
    @ObjCMethod("removeAllItems") func removeAllItems() { items.forEach { $0.menu = nil }; items = [] }

    @ObjCMethod("setSubmenu:forItem:")
    func setSubmenu(_ menu: NSMenu?, for item: NSMenuItem?) { item?.setSubmenu(menu) }
    /// Items enable as their targets validate them, when the menu enables
    /// its items itself: an item with an action is enabled when its target
    /// (or what the action would reach without one) implements it and,
    /// asked with -validateMenuItem:, agrees.
    @ObjCMethod("update")
    func update() {
        guard autoenablesItems else { return }
        for item in items where !item.separator {
            guard let action = item.action else {
                item.enabled = item.submenu != nil
                continue
            }
            let name = action.name
            let receiver = item.target ?? App.shared?.receiver(forAction: name)
            guard let receiver, Send.responds(receiver, name) else {
                item.enabled = false
                continue
            }
            if Send.responds(receiver, "validateMenuItem:") {
                item.enabled = Send.bool(receiver, "validateMenuItem:", item.objcObject)
            } else if Send.responds(receiver, "validateUserInterfaceItem:") {
                item.enabled = Send.bool(receiver, "validateUserInterfaceItem:", item.objcObject)
            } else {
                item.enabled = true
            }
        }
    }
    @ObjCMethod("performKeyEquivalent:") func performKeyEquivalent(_ event: NSObject?) -> Bool { false }
    @ObjCMethod("popUpMenuPositioningItem:atLocation:inView:")
    func popUp(positioning item: NSMenuItem?, at location: CGPoint, in view: NSObject?) -> Bool {
        MenuTracking.popUp(self, positioning: item, at: location, in: view?.as(NSView.self)) != nil
    }

    /// A context menu at the event's place.
    @ObjCClassMethod("popUpContextMenu:withEvent:forView:")
    static func popUpContextMenu(_ menu: NSMenu?, with event: NSEvent?, for view: NSView?) {
        guard let menu, let event else { return }
        let point = view.map { $0.convert(event.locationInWindow, from: nil) } ?? event.locationInWindow
        MenuTracking.popUp(menu, positioning: nil, at: point, in: view)
    }
    @ObjCMethod("cancelTracking") func cancelTracking() {}
    @ObjCMethod("setShowsStateColumn:") func setShowsStateColumn(_ value: Bool) {}
    @ObjCMethod("setMinimumWidth:") func setMinimumWidth(_ width: Double) { minimumWidth = width }
    @ObjCMethod("minimumWidth") func menuMinimumWidth() -> Double { minimumWidth }
    @ObjCClassMethod("setMenuBarVisible:") static func setMenuBarVisible(_ visible: Bool) {}
    @ObjCClassMethod("menuBarVisible") static func menuBarVisible() -> Bool { false }
}

@ObjCClass("NSMenuItem")
open class NSMenuItem: NSObject {
    var title = ""
    var action: ObjCSelector?
    var keyEquivalent = ""
    var keyEquivalentModifierMask: UInt = ModifierFlags.command
    /// Not retained.
    var target: UnsafeMutableRawPointer?
    var submenu: NSMenu?
    /// Not retained.
    var menu: UnsafeMutableRawPointer?
    var tag = 0
    var state = 0
    var enabled = true
    var hidden = false
    var separator = false
    var representedObject: NSObject?
    var image: NSObject?
    var toolTip: String?
    var indentationLevel = 0

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithTitle:action:keyEquivalent:")
    public required init(title: String?, action: ObjCSelector?, keyEquivalent: String?) {
        super.init()
        self.title = title ?? ""
        self.action = action
        self.keyEquivalent = keyEquivalent ?? ""
    }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init()
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        separator = decoded.bool("NSIsSeparator")
        title = decoded.string("NSTitle") ?? ""
        keyEquivalent = decoded.string("NSKeyEquiv") ?? ""
        if decoded.has("NSKeyEquivModMask") { keyEquivalentModifierMask = UInt(bitPattern: decoded.integer("NSKeyEquivModMask")) }
        enabled = !decoded.bool("NSIsDisabled") && !separator
        hidden = decoded.bool("NSIsHidden")
        tag = decoded.integer("NSTag")
        state = decoded.integer("NSState")
        action = decoded.selector("NSAction")
        target = decoded.object("NSTarget")?.objcObject
        representedObject = decoded.object("NSRepObject")
        image = decoded.object("NSImage")
        toolTip = decoded.string("NSToolTip")
        indentationLevel = decoded.integer("NSIndent")
        if let submenu = decoded.object("NSSubmenu")?.as(NSMenu.self) { setSubmenu(submenu) }
    }

    @ObjCClassMethod("separatorItem")
    static func separatorItem() -> NSMenuItem {
        let item = NSMenuItem()
        item.separator = true
        item.enabled = false
        return item
    }

    @ObjCMethod("title") func itemTitle() -> String { title }
    @ObjCMethod("setTitle:") func setTitle(_ title: String?) { self.title = title ?? "" }
    @ObjCMethod("attributedTitle") func attributedTitle() -> NSObject? { nil }
    @ObjCMethod("setAttributedTitle:") func setAttributedTitle(_ title: NSObject?) {}
    @ObjCMethod("action") func itemAction() -> ObjCSelector? { action }
    @ObjCMethod("setAction:") func setAction(_ action: ObjCSelector?) { self.action = action }
    @ObjCMethod("target") func itemTarget() -> NSObject? { target.map(NSObject.init) }
    @ObjCMethod("setTarget:") func setTarget(_ target: NSObject?) { self.target = target?.objcObject }
    @ObjCMethod("keyEquivalent") func itemKeyEquivalent() -> String { keyEquivalent }
    @ObjCMethod("setKeyEquivalent:") func setKeyEquivalent(_ key: String?) { keyEquivalent = key ?? "" }
    @ObjCMethod("keyEquivalentModifierMask") func itemKeyEquivalentModifierMask() -> UInt { keyEquivalentModifierMask }
    @ObjCMethod("setKeyEquivalentModifierMask:") func setKeyEquivalentModifierMask(_ mask: UInt) { keyEquivalentModifierMask = mask }
    @ObjCMethod("submenu") func itemSubmenu() -> NSMenu? { submenu }
    @ObjCMethod("setSubmenu:")
    func setSubmenu(_ menu: NSMenu?) {
        submenu = menu
        menu?.supermenu = self.menu
    }
    @ObjCMethod("hasSubmenu") func hasSubmenu() -> Bool { submenu != nil }
    @ObjCMethod("menu") func itemMenu() -> NSMenu? { menu.map { NSMenu.objCInstance($0, ownership: .retain) } }
    @ObjCMethod("setMenu:") func setMenu(_ menu: NSMenu?) { self.menu = menu?.objcObject }
    @ObjCMethod("tag") func itemTag() -> Int { tag }
    @ObjCMethod("setTag:") func setTag(_ tag: Int) { self.tag = tag }
    @ObjCMethod("state") func itemState() -> Int { state }
    @ObjCMethod("setState:") func setState(_ state: Int) { self.state = state }
    @ObjCMethod("isEnabled") func isEnabled() -> Bool { enabled }
    @ObjCMethod("setEnabled:") func setEnabled(_ enabled: Bool) { self.enabled = enabled }
    @ObjCMethod("isHidden") func isHidden() -> Bool { hidden }
    @ObjCMethod("setHidden:") func setHidden(_ hidden: Bool) { self.hidden = hidden }
    @ObjCMethod("isSeparatorItem") func isSeparatorItem() -> Bool { separator }
    @ObjCMethod("representedObject") func itemRepresentedObject() -> NSObject? { representedObject }
    @ObjCMethod("setRepresentedObject:") func setRepresentedObject(_ object: NSObject?) { representedObject = object }
    @ObjCMethod("image") func itemImage() -> NSObject? { image }
    @ObjCMethod("setImage:") func setImage(_ image: NSObject?) { self.image = image }
    @ObjCMethod("setOnStateImage:") func setOnStateImage(_ image: NSObject?) {}
    @ObjCMethod("setOffStateImage:") func setOffStateImage(_ image: NSObject?) {}
    @ObjCMethod("toolTip") func itemToolTip() -> String? { toolTip }
    @ObjCMethod("setToolTip:") func setToolTip(_ toolTip: String?) { self.toolTip = toolTip }
    @ObjCMethod("indentationLevel") func itemIndentationLevel() -> Int { indentationLevel }
    @ObjCMethod("setIndentationLevel:") func setIndentationLevel(_ level: Int) { indentationLevel = level }
    @ObjCMethod("setAlternate:") func setAlternate(_ value: Bool) {}
    @ObjCMethod("isAlternate") func isAlternate() -> Bool { false }
    @ObjCMethod("setView:") func setView(_ view: NSObject?) {}
    @ObjCMethod("view") func view() -> NSObject? { nil }
    @ObjCMethod("isHighlighted") func isHighlighted() -> Bool { false }
}

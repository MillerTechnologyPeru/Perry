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

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithTitle:")
    public required init(title: String?) {
        super.init()
        self.title = title ?? ""
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
    @ObjCMethod("update") func update() {}
    @ObjCMethod("performKeyEquivalent:") func performKeyEquivalent(_ event: NSObject?) -> Bool { false }
    @ObjCMethod("popUpMenuPositioningItem:atLocation:inView:")
    func popUp(positioning item: NSMenuItem?, at location: CGPoint, in view: NSObject?) -> Bool { false }
    @ObjCMethod("cancelTracking") func cancelTracking() {}
    @ObjCMethod("setShowsStateColumn:") func setShowsStateColumn(_ value: Bool) {}
    @ObjCMethod("setMinimumWidth:") func setMinimumWidth(_ width: Double) {}
    @ObjCMethod("setFont:") func setFont(_ font: NSObject?) {}
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

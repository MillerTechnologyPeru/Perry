import CPerryGeometry
import CacaoDBusMenu
import Glibc
import PerryDesktopMenus
import PerryDesktopStatusItems
import PerryObjCInterop

// The system status bar's items on the desktop: each NSStatusItem is a
// StatusNotifierItem at the right of the desktop's menu bar, which Cacao's
// menu bar and other desktops' panels show. The item shows its button's
// title and tool tip, and its menu, which a click opens; an item with no
// menu sends its button's action when clicked, as on a Mac. Images aren't
// shown yet: an item with no title shows the app's name. An item that isn't
// visible is passive, which the bar hides.
//
// PERRY_APPKIT_STATUS_ITEMS=0 shows none.

enum StatusItems {
    static var enabled: Bool { getenv("PERRY_APPKIT_STATUS_ITEMS").map { String(cString: $0) != "0" } ?? true }

    /// How long the bar's AboutToShow waits for the main thread.
    static let validationWait = 1.0

    /// The item a key names, while it's in the status bar.
    static func item(_ key: UInt) -> NSStatusItem? {
        NSStatusBar.system.items.first { UInt(bitPattern: $0.objcObject) == key }
    }
}

@ObjCClass("NSStatusBar")
open class NSStatusBar: NSObject {
    /// The system status bar, the only one shown.
    nonisolated(unsafe) static let system = NSStatusBar()

    /// The items, from first made to last, until they're removed.
    var items: [NSStatusItem] = []

    public required override init() { super.init() }

    @ObjCClassMethod("systemStatusBar") static func systemStatusBar() -> NSObject { system }

    @ObjCMethod("statusItemWithLength:") func statusItem(withLength length: CGFloat) -> NSObject {
        let item = NSStatusItem()
        item.statusBar = self
        item.length = length
        items.append(item)
        item.show()
        return item
    }

    @ObjCMethod("removeStatusItem:") func removeStatusItem(_ object: NSObject?) {
        guard let object, let item = items.first(where: { $0.objcObject == object.objcObject }) else { return }
        items.removeAll { $0 === item }
        item.hide()
    }

    @ObjCMethod("thickness") func thickness() -> CGFloat { 22 }
    @ObjCMethod("isVertical") func isVertical() -> Bool { false }
}

@ObjCClass("NSStatusItem")
open class NSStatusItem: NSObject {
    weak var statusBar: NSStatusBar?
    var length: CGFloat = -1
    var visible = true
    var behavior: UInt = 0
    var autosaveName: String?
    var menu: NSMenu?
    /// A custom view, before 10.10: not shown.
    var customView: NSObject?
    var highlightMode = false
    var actionMask: UInt = 0

    /// The button the bar shows the item with.
    lazy var button: NSStatusBarButton = {
        let button = NSStatusBarButton(frame: CGRect(x: 0, y: 0, width: 22, height: 22))
        // Untitled, as on a Mac, rather than a new button's "Button".
        button.title = ""
        button.statusItem = self
        return button
    }()

    /// The item on the desktop, while it's shown.
    private var desktopItem: DesktopStatusItem?
    private var shownProperties: DesktopStatusItem.Properties?
    private var mapping = DesktopMenuMapping(commandKey: DesktopMenus.commandKey)
    /// The menu last served.
    private var served: DBusMenuItem?

    public required override init() { super.init() }

    @ObjCMethod("statusBar") func itemStatusBar() -> NSObject? { statusBar }
    @ObjCMethod("button") func itemButton() -> NSObject? { button }
    @ObjCMethod("menu") func itemMenu() -> NSObject? { menu }
    @ObjCMethod("setMenu:") func setMenu(_ menu: NSObject?) {
        self.menu = menu?.as(NSMenu.self)
        changed()
        publishMenu()
    }
    @ObjCMethod("length") func itemLength() -> CGFloat { length }
    @ObjCMethod("setLength:") func setLength(_ length: CGFloat) { self.length = length }
    @ObjCMethod("isVisible") func isVisible() -> Bool { visible }
    @ObjCMethod("setVisible:") func setVisible(_ visible: Bool) {
        self.visible = visible
        changed()
    }
    @ObjCMethod("behavior") func itemBehavior() -> UInt { behavior }
    @ObjCMethod("setBehavior:") func setBehavior(_ behavior: UInt) { self.behavior = behavior }
    @ObjCMethod("autosaveName") func itemAutosaveName() -> String? { autosaveName }
    @ObjCMethod("setAutosaveName:") func setAutosaveName(_ name: String?) { autosaveName = name }

    // Before 10.10, the item had these itself: they're the button's.
    @ObjCMethod("title") func itemTitle() -> String { button.title }
    @ObjCMethod("setTitle:") func setTitle(_ title: String?) { button.setTitle(title) }
    @ObjCMethod("image") func itemImage() -> NSObject? { button.image }
    @ObjCMethod("setImage:") func setImage(_ image: NSObject?) { button.setImage(image) }
    @ObjCMethod("toolTip") func itemToolTip() -> String? { button.toolTip }
    @ObjCMethod("setToolTip:") func setToolTip(_ toolTip: String?) { button.setToolTip(toolTip) }
    @ObjCMethod("target") func itemTarget() -> NSObject? { button.controlTarget() }
    @ObjCMethod("setTarget:") func setTarget(_ target: NSObject?) { button.setTarget(target) }
    @ObjCMethod("action") func itemAction() -> ObjCSelector? { button.controlAction() }
    @ObjCMethod("setAction:") func setAction(_ action: ObjCSelector?) { button.setAction(action) }
    @ObjCMethod("highlightMode") func itemHighlightMode() -> Bool { highlightMode }
    @ObjCMethod("setHighlightMode:") func setHighlightMode(_ mode: Bool) { highlightMode = mode }
    @ObjCMethod("view") func itemView() -> NSObject? { customView }
    @ObjCMethod("setView:") func setView(_ view: NSObject?) { customView = view }
    @ObjCMethod("sendActionOn:") func sendAction(on mask: UInt) -> Int { defer { actionMask = mask }; return Int(actionMask) }
    /// The bar opens the menu itself, when the item is clicked.
    @ObjCMethod("popUpStatusItemMenu:") func popUpMenu(_ menu: NSObject?) {}

    // MARK: On the desktop

    /// What the bar shows of the item.
    var properties: DesktopStatusItem.Properties {
        DesktopStatusItem.Properties(id: DesktopMenus.appName, title: button.title, toolTip: button.toolTip ?? "",
                                     status: visible ? .active : .passive, hasMenu: menu != nil)
    }

    /// Puts the item on the desktop's bar.
    func show() {
        guard StatusItems.enabled, desktopItem == nil else { return }
        let key = UInt(bitPattern: objcObject)
        let properties = properties
        shownProperties = properties
        desktopItem = DesktopStatusItem(properties) {
            Dispatch.onMain { StatusItems.item(key)?.activate() }
        } onMenuClick: { id in
            Dispatch.onMain { StatusItems.item(key)?.choose(id) }
        } onMenuAboutToShow: { id in
            _ = await DesktopMenuService.result(within: StatusItems.validationWait, scheduling: { work in Dispatch.onMain(work) }) {
                StatusItems.item(key)?.validate(id)
            }
        }
        publishMenu()
    }

    /// Takes the item off the desktop's bar.
    func hide() {
        desktopItem?.remove()
        desktopItem = nil
        shownProperties = nil
        served = nil
    }

    /// Shows what changed of the item.
    func changed() {
        let properties = properties
        guard let desktopItem, properties != shownProperties else { return }
        shownProperties = properties
        desktopItem.update(properties)
    }

    /// Reads the menu again and serves it if it changed.
    private func publishMenu() {
        guard let desktopItem else { return }
        let root = menu.map { mapping.menu(forItems: DesktopMenus.entries(of: $0)) } ?? .root([])
        guard root != served else { return }
        served = root
        desktopItem.publish(root)
    }

    /// The bar's click on an item without a menu: the button's action is
    /// sent, as a click on it does on a Mac.
    private func activate() {
        guard menu == nil else { return }
        button.clicked()
    }

    /// The bar's click on one of the menu's items: its action is sent, if
    /// it's still enabled once validated.
    private func choose(_ id: Int32) {
        guard let item = item(withID: id), item.submenu == nil, !item.separator else { return }
        if let owner = item.menu.map({ NSMenu.objCInstance($0, ownership: .retain) }) { MenuTracking.prepare(owner) }
        guard item.enabled else { return }
        MenuTracking.perform(item)
        publishMenu()
    }

    /// The menu, or one of its submenus, is about to open: its delegate
    /// fills it and its items are validated, as before it opens on a Mac.
    private func validate(_ id: Int32) {
        if id == DBusMenuItem.rootID {
            if let menu { MenuTracking.prepare(menu) }
        } else if let submenu = item(withID: id)?.submenu {
            MenuTracking.prepare(submenu)
        }
        publishMenu()
    }

    /// The menu's item an identifier was given to, if it's still there.
    private func item(withID id: Int32) -> NSMenuItem? {
        guard let key = mapping.key(for: id), let menu else { return nil }
        func find(_ menu: NSMenu, depth: Int) -> NSMenuItem? {
            guard depth < 16 else { return nil }
            for item in menu.items {
                if UInt(bitPattern: item.objcObject) == key { return item }
                if let submenu = item.submenu, let found = find(submenu, depth: depth + 1) { return found }
            }
            return nil
        }
        return find(menu, depth: 0)
    }
}

@ObjCClass("NSStatusBarButton")
open class NSStatusBarButton: NSButton {
    /// The item the button shows, which hears its changes.
    weak var statusItem: NSStatusItem?
    var appearsDisabled = false

    public required init() { super.init() }
    @ObjCMethod("initWithFrame:")
    public required init(frame: CGRect) { super.init(frame: frame) }
    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) { super.init(coder: coder) }

    @ObjCMethod("setTitle:") override func setTitle(_ title: String?) {
        super.setTitle(title)
        statusItem?.changed()
    }
    @ObjCMethod("setImage:") override func setImage(_ image: NSObject?) {
        super.setImage(image)
        statusItem?.changed()
    }
    @ObjCMethod("setToolTip:") override func setToolTip(_ toolTip: String?) {
        super.setToolTip(toolTip)
        statusItem?.changed()
    }
    @ObjCMethod("appearsDisabled") func buttonAppearsDisabled() -> Bool { appearsDisabled }
    @ObjCMethod("setAppearsDisabled:") func setAppearsDisabled(_ value: Bool) { appearsDisabled = value }
}

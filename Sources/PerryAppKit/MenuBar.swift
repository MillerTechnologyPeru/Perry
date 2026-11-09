import CPerryGeometry
import Glibc
import PerryObjCInterop

// The main menu on Linux. GNOME has no menu bar of its own to put it in (its
// top bar no longer shows an application's menus), so each document window
// carries the menu across its top, over the toolbar, as the desktops that
// kept menu bars do. The application menu, which exists for macOS's
// conventions, is folded into the menus Linux apps keep those items in: About
// at the end of Help, Preferences at the end of Edit, Quit at the end of File.
// The Window menu is left out (the window manager arranges windows), and so
// are the application menu's Hide and Services. Command's shortcuts are
// Control's, as on other Linux desktops: a Control key press that is a menu
// item's key equivalent with Command chooses it, before the focused view
// sees the key.
//
// PERRY_APPKIT_MENUBAR=off leaves the menu out.

enum MenuBar {
    static var enabled: Bool { getenv("PERRY_APPKIT_MENUBAR").map { String(cString: $0) != "off" } ?? true }

    /// The main menu, if the app has one.
    static var mainMenu: NSMenu? { App.shared?.mainMenu.map { NSMenu.objCInstance($0.objcObject, ownership: .retain) } }

    /// Whether a window shows the menu: the titled windows of an app that
    /// has one, not its panels.
    static func shows(in window: NSWindow) -> Bool {
        enabled && mainMenu != nil && window.styleMask & StyleMask.titled != 0 && !(window is NSPanel)
            && window.styleMask & StyleMask.fullScreen == 0
    }

    private static func title(of item: NSMenuItem) -> String {
        let title = item.title.isEmpty ? (item.submenu?.title ?? "") : item.title
        return String(title.filter { $0 != "&" })
    }

    nonisolated(unsafe) private static var adapted: UnsafeMutableRawPointer?
    nonisolated(unsafe) private static var appMenuShown = false

    /// The menus the bar shows, titled: the main menu's, past the
    /// application menu (shown only when its items had nowhere to go) and
    /// without the Window menu.
    static func entries() -> [(title: String, menu: NSMenu)] {
        guard let main = mainMenu else { return [] }
        adapt(main)
        let windows = App.shared?.windowsMenu?.objcObject
        return main.items.enumerated().compactMap { index, item in
            guard let submenu = item.submenu, !item.hidden else { return nil }
            if index == 0 && !appMenuShown { return nil }
            if submenu.objcObject == windows || title(of: item) == "Window" { return nil }
            return (title(of: item), submenu)
        }
    }

    /// Moves the application menu's About, Preferences and Quit into Help,
    /// Edit and File, once; those with no such menu to go to keep the
    /// application menu in the bar.
    private static func adapt(_ main: NSMenu) {
        guard adapted != main.objcObject else { return }
        adapted = main.objcObject
        guard let appMenu = main.items.first?.submenu else { return }
        func menu(named name: String) -> NSMenu? { main.items.dropFirst().first { title(of: $0) == name }?.submenu }
        let moves: [(prefixes: [String], to: String)] = [(["About "], "Help"), (["Preferences", "Settings"], "Edit"), (["Quit "], "File")]
        for (prefixes, name) in moves {
            guard let item = appMenu.items.first(where: { item in prefixes.contains { item.title.hasPrefix($0) } }) else { continue }
            guard let destination = menu(named: name) else { appMenuShown = true; continue }
            appMenu.removeItem(item)
            if let last = destination.items.last, !last.separator { destination.addItem(NSMenuItem.separatorItem()) }
            destination.addItem(item)
        }
        // The rest of the application menu isn't shown without a place for
        // its items (a menu with nothing to move stays out of the bar).
        if appMenuShown { return }
    }

    // MARK: Key equivalents

    private static let significant = ModifierFlags.shift | ModifierFlags.option | ModifierFlags.command | ModifierFlags.control

    /// Chooses the menu item whose key equivalent the key press is, with
    /// Control standing for Command; whether there was one.
    static func performKeyEquivalent(_ event: NSEvent) -> Bool {
        guard !MenuTracking.tracking, let main = mainMenu else { return false }
        adapt(main)
        var modifiers = event.modifierFlags & significant
        if modifiers & ModifierFlags.control != 0, modifiers & ModifierFlags.command == 0 {
            modifiers = (modifiers & ~ModifierFlags.control) | ModifierFlags.command
        }
        let key = event.charactersIgnoringModifiers.lowercased()
        guard !key.isEmpty else { return false }
        var found: NSMenuItem?
        func search(_ menu: NSMenu) {
            for item in menu.items where found == nil && !item.hidden && !item.separator {
                if let submenu = item.submenu { search(submenu); continue }
                guard !item.keyEquivalent.isEmpty, item.keyEquivalent.lowercased() == key else { continue }
                var wanted = item.keyEquivalentModifierMask & significant
                let letter = item.keyEquivalent
                // An uppercase letter is typed with shift.
                if letter.count == 1, letter.uppercased() == letter, letter.lowercased() != letter { wanted |= ModifierFlags.shift }
                if wanted == modifiers { found = item }
            }
        }
        search(main)
        guard let item = found, let owner = item.menu.map({ NSMenu.objCInstance($0, ownership: .retain) }) else { return false }
        MenuTracking.prepare(owner)
        guard item.enabled else { return false }
        MenuTracking.perform(item)
        return true
    }
}

/// The strip across the top of a window that shows its main menu's titles.
@ObjCClass("_PerryMenuBarView")
open class MenuBarView: NSView {
    static let height: CGFloat = 26

    /// The title being shown open.
    var open: Int?
    var titles: [(title: String, menu: NSMenu, frame: CGRect)] = []
    nonisolated(unsafe) private static let font = NSFont.system(size: 13)

    public required init() { super.init() }

    @ObjCMethod("initWithFrame:")
    public required init(frame: CGRect) { super.init(frame: frame) }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) { super.init(coder: coder) }

    @ObjCMethod("isFlipped") override func isFlipped() -> Bool { true }

    func arrange() {
        var x: CGFloat = 4
        func width(_ title: String) -> CGFloat { ceil(Text.width(title, font: MenuBarView.font)) + 20 }
        let entries = MenuBar.entries()
        let overflowWidth = width("»")
        let total = entries.reduce(CGFloat(4)) { $0 + width($1.title) }
        var shown = entries.count
        // Too wide: the titles that don't fit, with room for "»", go in its menu.
        if total > bounds.width {
            var used: CGFloat = 4 + overflowWidth
            shown = 0
            for entry in entries {
                used += width(entry.title)
                if used > bounds.width { break }
                shown += 1
            }
        }
        titles = entries.prefix(shown).map { entry in
            defer { x += width(entry.title) }
            return (entry.title, entry.menu, CGRect(x: x, y: 2, width: width(entry.title), height: bounds.height - 4))
        }
        overflow = entries.dropFirst(shown).map { $0 }
        overflowFrame = overflow.isEmpty ? .zero : CGRect(x: x, y: 2, width: overflowWidth, height: bounds.height - 4)
    }

    /// The menus that didn't fit, shown from a "»" at the end.
    var overflow: [(title: String, menu: NSMenu)] = []
    var overflowFrame = CGRect.zero

    /// A menu of the overflowing menus' titles, each opening its menu.
    private func overflowMenu() -> NSMenu {
        let menu = NSMenu(title: "")
        for entry in overflow {
            let item = NSMenuItem(title: entry.title, action: nil, keyEquivalent: "")
            item.setSubmenu(entry.menu)
            menu.addItem(item)
        }
        return menu
    }

    @ObjCMethod("drawRect:")
    override func draw(_ rect: CGRect) {
        guard let context = NSGraphicsContext.currentCG else { return }
        arrange()
        let dark = Appearances.currentIsDark
        CG.saveGState(context)
        CG.setFill(context, NSColor.windowBackgroundColor())
        CG.fillRect(context, bounds)
        CG.setFill(context, NSColor.separatorColor())
        CG.fillRect(context, CGRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1))
        CG.restoreGState(context)
        for (index, entry) in titles.enumerated() {
            if index == open {
                CG.fill(CG.roundedRect(entry.frame, radius: 5), NSColor.labelColor().withAlphaComponent(dark ? 0.18 : 0.12), in: context)
            }
            var style = TextStyle()
            style.alignment = 1
            style.maximumLines = 1
            let height = Text.lineHeight(MenuBarView.font)
            let area = CGRect(x: entry.frame.minX, y: entry.frame.midY - height / 2, width: entry.frame.width, height: height)
            Text.draw([TextRun(text: entry.title, font: MenuBarView.font, color: NSColor.labelColor())], in: area, style: style)
        }
        if !overflow.isEmpty {
            var style = TextStyle()
            style.alignment = 1
            style.maximumLines = 1
            let height = Text.lineHeight(MenuBarView.font)
            let area = CGRect(x: overflowFrame.minX, y: overflowFrame.midY - height / 2, width: overflowFrame.width, height: height)
            Text.draw([TextRun(text: "»", font: MenuBarView.font, color: NSColor.labelColor())], in: area, style: style)
        }
    }

    @ObjCMethod("mouseDown:")
    override func mouseDown(_ eventObject: NSObject?) {
        guard let event = eventObject?.as(NSEvent.self), !MenuTracking.tracking else { return }
        arrange()
        let point = convert(event.locationInWindow, from: nil)
        if !overflow.isEmpty, overflowFrame.contains(point) {
            MenuTracking.popUp(overflowMenu(), positioning: nil, at: CGPoint(x: overflowFrame.minX, y: bounds.height), in: self)
            return
        }
        guard let index = titles.firstIndex(where: { $0.frame.contains(point) }) else { return }
        open = index
        setNeedsDisplay(true)
        let entry = titles[index]
        // Its menu opens below the title.
        MenuTracking.popUp(entry.menu, positioning: nil, at: CGPoint(x: entry.frame.minX, y: bounds.height), in: self)
        open = nil
        setNeedsDisplay(true)
    }
}

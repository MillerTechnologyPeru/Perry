import CacaoDBusMenu
import PerryDesktopMenus
import Testing

/// A main menu as NSMenu's items read it.
private enum Keys {
    static let app: UInt = 0x100, about: UInt = 0x101, appSeparator: UInt = 0x102, quit: UInt = 0x103
    static let file: UInt = 0x200, new: UInt = 0x201, open: UInt = 0x202, recent: UInt = 0x203, recentItem: UInt = 0x204
    static let view: UInt = 0x300, sidebar: UInt = 0x301, mixed: UInt = 0x302, hidden: UInt = 0x303
    static let window: UInt = 0x400, minimize: UInt = 0x401
    static let loose: UInt = 0x500
}

private let command = DesktopMenuEntry.ModifierMask.command
private let shift = DesktopMenuEntry.ModifierMask.shift
private let option = DesktopMenuEntry.ModifierMask.option
private let control = DesktopMenuEntry.ModifierMask.control

private func mainMenu(extraFileItem: DesktopMenuEntry? = nil) -> [DesktopMenuEntry] {
    var fileItems = [
        DesktopMenuEntry(key: Keys.new, title: "New", keyEquivalent: "n"),
        DesktopMenuEntry(key: Keys.open, title: "Open…", keyEquivalent: "o"),
        DesktopMenuEntry(key: Keys.recent, title: "Open Recent", submenu: [
            DesktopMenuEntry(key: Keys.recentItem, title: "notes_2026.txt"),
        ], submenuTitle: "Open Recent"),
    ]
    if let extraFileItem { fileItems.insert(extraFileItem, at: 0) }
    return [
        DesktopMenuEntry(key: Keys.app, title: "Apple", submenu: [
            DesktopMenuEntry(key: Keys.about, title: "About Probe"),
            DesktopMenuEntry(key: Keys.appSeparator, isSeparator: true, isEnabled: false),
            DesktopMenuEntry(key: Keys.quit, title: "Quit Probe", keyEquivalent: "q"),
        ], submenuTitle: "Apple"),
        DesktopMenuEntry(key: Keys.file, title: "", submenu: fileItems, submenuTitle: "File"),
        DesktopMenuEntry(key: Keys.view, title: "View", submenu: [
            DesktopMenuEntry(key: Keys.sidebar, title: "Show Sidebar", state: 1, keyEquivalent: "S", keyEquivalentModifierMask: command | control),
            DesktopMenuEntry(key: Keys.mixed, title: "Mixed", isEnabled: false, state: -1),
            DesktopMenuEntry(key: Keys.hidden, title: "Hidden", isHidden: true),
        ], submenuTitle: "View"),
        // An item of the main menu with no submenu isn't a menu of the bar.
        DesktopMenuEntry(key: Keys.loose, title: "Loose"),
        DesktopMenuEntry(key: Keys.window, title: "Window", submenu: [
            DesktopMenuEntry(key: Keys.minimize, title: "Minimize", keyEquivalent: "m"),
        ], submenuTitle: "Window"),
    ]
}

@Suite("NSMenu to dbusmenu")
struct DesktopMenuMappingTests {
    @Test("The menus of the bar, as the app put them, the application menu titled with the app's name")
    func menus() throws {
        var mapping = DesktopMenuMapping(commandKey: .super)
        let root = mapping.menu(for: mainMenu(), appName: "Probe")
        #expect(root.id == DBusMenuItem.rootID)
        #expect(root.children.map(\.title) == ["Probe", "File", "View", "Window"])
        #expect(root.children.allSatisfy { $0.isSubmenu })
        let app = root.children[0]
        #expect(app.children.map(\.title) == ["About Probe", "", "Quit Probe"])
        #expect(app.children[1].type == .separator)
        #expect(app.children[0].type == .standard)
    }

    @Test("Identifiers: one per item, nonzero, and the same from one mapping to the next")
    func stableIdentifiers() throws {
        var mapping = DesktopMenuMapping(commandKey: .super)
        let first = mapping.menu(for: mainMenu(), appName: "Probe")
        var ids: [Int32] = []
        first.children.forEach { $0.forEach { ids.append($0.id) } }
        #expect(!ids.contains(0))
        #expect(Set(ids).count == ids.count)

        // An item comes in before the others: theirs stay.
        let second = mapping.menu(for: mainMenu(extraFileItem: DesktopMenuEntry(key: 0x2FF, title: "Inserted")), appName: "Probe")
        for id in ids {
            let before = try #require(first.item(withID: id))
            let after = try #require(second.item(withID: id))
            #expect(before.title == after.title)
        }
        let inserted = try #require(mapping.identifier(for: 0x2FF))
        #expect(!ids.contains(inserted))
        #expect(mapping.key(for: inserted) == 0x2FF)

        // It leaves again: its identifier goes, and the others stay.
        let third = mapping.menu(for: mainMenu(), appName: "Probe")
        #expect(mapping.identifier(for: 0x2FF) == nil)
        #expect(mapping.key(for: inserted) == nil)
        #expect(third == first)
    }

    @Test("Titles: an item with none takes its submenu's, and underscores aren't mnemonics")
    func titles() throws {
        var mapping = DesktopMenuMapping(commandKey: .super)
        let root = mapping.menu(for: mainMenu(), appName: "Probe")
        #expect(root.children[1].title == "File")
        let recent = try #require(root.children[1].children.last)
        #expect(recent.isSubmenu)
        #expect(recent.title == "Open Recent")
        #expect(recent.children[0].title == "notes_2026.txt")
        #expect(recent.children[0].label == "notes__2026.txt")
        #expect(recent.shortcut == nil)
    }

    @Test("States: on and mixed are checkmarks, off shows none; disabled and hidden items stay")
    func states() throws {
        var mapping = DesktopMenuMapping(commandKey: .super)
        let view = mapping.menu(for: mainMenu(), appName: "Probe").children[2]
        let sidebar = view.children[0], mixed = view.children[1], hidden = view.children[2]
        #expect(sidebar.toggleType == .checkmark)
        #expect(sidebar.toggleState == .on)
        #expect(mixed.toggleType == .checkmark)
        #expect(mixed.toggleState == .indeterminate)
        #expect(!mixed.isEnabled)
        #expect(hidden.toggleType == nil)
        #expect(!hidden.isVisible)
        #expect(sidebar.isVisible && sidebar.isEnabled)
    }

    @Test("Command is Super on Cacao's desktop, shown as ⌘")
    func superShortcuts() throws {
        var mapping = DesktopMenuMapping(commandKey: .super)
        let root = mapping.menu(for: mainMenu(), appName: "Probe")
        let quit = try #require(root.children[0].children[2].shortcut)
        #expect(quit.keys == ["Super", "q"])
        #expect(quit.glyphs == "⌘Q")
        // An uppercase letter is typed with Shift; Control stays Control.
        let sidebar = try #require(root.children[2].children[0].shortcut)
        #expect(sidebar.keys == ["Control", "Shift", "Super", "s"])
        #expect(sidebar.glyphs == "⌃⇧⌘S")
    }

    @Test("Command is Control on other desktops")
    func controlShortcuts() throws {
        var mapping = DesktopMenuMapping(commandKey: .control)
        let root = mapping.menu(for: mainMenu(), appName: "Probe")
        #expect(root.children[0].children[2].shortcut?.keys == ["Control", "q"])
        #expect(root.children[3].children[0].shortcut?.keys == ["Control", "m"])
    }

    @Test("The desktop's key for Command, from XDG_CURRENT_DESKTOP")
    func commandKey() {
        #expect(DesktopMenuMapping.commandKey(forDesktop: "Cacao") == .super)
        #expect(DesktopMenuMapping.commandKey(forDesktop: "sway:Cacao") == .super)
        #expect(DesktopMenuMapping.commandKey(forDesktop: "GNOME") == .control)
        #expect(DesktopMenuMapping.commandKey(forDesktop: "KDE") == .control)
        #expect(DesktopMenuMapping.commandKey(forDesktop: nil) == .control)
    }

    @Test("Keys AppKit writes as control or function-key characters")
    func namedKeys() {
        func keys(_ key: String, _ mask: UInt = command) -> [String]? {
            DesktopMenuMapping.shortcut(key, modifiers: mask, commandKey: .super)?.keys
        }
        #expect(keys("") == nil)
        #expect(keys("\r") == ["Super", "Return"])
        #expect(keys("\u{1B}", 0) == ["Escape"])
        #expect(keys("\u{7F}") == ["Super", "BackSpace"])
        #expect(keys("\u{8}") == ["Super", "BackSpace"])
        #expect(keys("\u{F728}") == ["Super", "Delete"])
        #expect(keys("\u{F700}", command | option) == ["Alt", "Super", "Up"])
        #expect(keys("\u{F703}") == ["Super", "Right"])
        #expect(keys("\u{F704}") == ["Super", "F1"])
        #expect(keys("\u{F70F}", 0) == ["F12"])
        #expect(keys("\u{F72C}") == ["Super", "Page_Up"])
        #expect(keys(",") == ["Super", "comma"])
        #expect(keys("?", command | shift) == ["Shift", "Super", "question"])
        #expect(keys("1") == ["Super", "1"])
        #expect(keys(" ", control) == ["Control", "space"])
        #expect(keys("\t", control) == ["Control", "Tab"])
        #expect(keys("\u{19}", control) == ["Control", "Shift", "Tab"])
        #expect(DesktopMenuMapping.shortcut("\u{F702}", modifiers: command, commandKey: .super)?.glyphs == "⌘←")
    }
}

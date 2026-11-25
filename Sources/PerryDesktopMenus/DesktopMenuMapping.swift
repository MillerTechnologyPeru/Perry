public import CacaoDBusMenu

/// A Mac app's main menu as the desktop's menu bar reads it over
/// `com.canonical.dbusmenu`: its menus as the app put them, the application
/// menu first, titled with the app's name, and the Window menu where it is.
///
/// Each item keeps its identifier while it stays in the menu, from one
/// mapping to the next, so a click the bar sends after an update still
/// finds it; an item that leaves and comes back gets a new one.
///
/// Key equivalents are written with the key the desktop gives Command: Super
/// on Cacao's desktop, whose menu bar shows Super as ⌘, and Control on
/// others, where Perry takes Control for Command.
public struct DesktopMenuMapping: Sendable {
    /// The key that stands for Command.
    public enum CommandKey: Sendable {
        case `super`
        case control
    }

    public var commandKey: CommandKey

    private var identifiers: [UInt: Int32] = [:]
    private var keys: [Int32: UInt] = [:]
    private var nextIdentifier: Int32 = 1

    public init(commandKey: CommandKey) {
        self.commandKey = commandKey
    }

    /// The key for Command on the desktop XDG_CURRENT_DESKTOP names (a
    /// list separated by colons): Super on Cacao's.
    public static func commandKey(forDesktop desktop: String?) -> CommandKey {
        let names = desktop?.split(separator: ":").map { $0.lowercased() } ?? []
        return names.contains("cacao") ? .super : .control
    }

    /// The menu: the root, whose children are the main menu's menus. Only
    /// the main menu's items with submenus are menus of the bar; the first
    /// is the application menu.
    public mutating func menu(for mainMenu: [DesktopMenuEntry], appName: String) -> DBusMenuItem {
        var seen: Set<UInt> = []
        var menus: [DBusMenuItem] = []
        for entry in mainMenu where entry.submenu != nil && !entry.isSeparator {
            var item = self.item(for: entry, seen: &seen)
            if menus.isEmpty { item.label = DBusMenuLabel(title: appName).rawValue }
            menus.append(item)
        }
        forgetItems(notIn: seen)
        return .root(menus)
    }

    /// A menu of its own, such as a status item's: the root, whose children
    /// are the menu's items, as it shows them when it opens.
    public mutating func menu(forItems items: [DesktopMenuEntry]) -> DBusMenuItem {
        var seen: Set<UInt> = []
        let children = items.map { item(for: $0, seen: &seen) }
        forgetItems(notIn: seen)
        return .root(children)
    }

    /// Items that left the menu let go of their identifiers.
    private mutating func forgetItems(notIn seen: Set<UInt>) {
        for (key, id) in identifiers where !seen.contains(key) {
            identifiers[key] = nil
            keys[id] = nil
        }
    }

    /// The key of the item an identifier was given to, while it is in the
    /// menu last mapped.
    public func key(for id: Int32) -> UInt? { keys[id] }

    /// The identifier an item was given, while it is in the menu last
    /// mapped.
    public func identifier(for key: UInt) -> Int32? { identifiers[key] }

    private mutating func identifier(_ key: UInt) -> Int32 {
        if let id = identifiers[key] { return id }
        var id = nextIdentifier
        // Past Int32's end, from 1 again, skipping identifiers in use.
        while id <= 0 || keys[id] != nil { id = id <= 0 ? 1 : id &+ 1 }
        nextIdentifier = id &+ 1
        identifiers[key] = id
        keys[id] = key
        return id
    }

    private mutating func item(for entry: DesktopMenuEntry, seen: inout Set<UInt>) -> DBusMenuItem {
        seen.insert(entry.key)
        let id = identifier(entry.key)
        if entry.isSeparator {
            var separator = DBusMenuItem.separator(id: id)
            separator.isVisible = !entry.isHidden
            return separator
        }
        let children = entry.submenu.map { $0.map { item(for: $0, seen: &seen) } } ?? []
        let title = entry.title.isEmpty ? entry.submenuTitle : entry.title
        let toggled = entry.state != 0 && entry.submenu == nil
        return DBusMenuItem(
            id: id,
            label: DBusMenuLabel(title: title).rawValue,
            isEnabled: entry.isEnabled,
            isVisible: !entry.isHidden,
            shortcut: entry.submenu == nil ? Self.shortcut(entry.keyEquivalent, modifiers: entry.keyEquivalentModifierMask, commandKey: commandKey) : nil,
            toggleType: toggled ? .checkmark : nil,
            toggleState: entry.state == 1 ? .on : entry.state == 0 ? .off : .indeterminate,
            isSubmenu: entry.submenu != nil,
            children: children
        )
    }

    // MARK: Key equivalents

    /// A key equivalent as the `shortcut` property names it, or nil
    /// without one.
    public static func shortcut(_ keyEquivalent: String, modifiers mask: UInt, commandKey: CommandKey) -> DBusMenuShortcut? {
        guard let character = keyEquivalent.first else { return nil }
        var modifiers: DBusMenuShortcut.Modifiers = []
        if mask & DesktopMenuEntry.ModifierMask.control != 0 { modifiers.insert(.control) }
        if mask & DesktopMenuEntry.ModifierMask.option != 0 { modifiers.insert(.alt) }
        if mask & DesktopMenuEntry.ModifierMask.shift != 0 { modifiers.insert(.shift) }
        if mask & DesktopMenuEntry.ModifierMask.command != 0 { modifiers.insert(commandKey == .super ? .super : .control) }
        if let name = namedKeys[character] {
            if character == "\u{19}" { modifiers.insert(.shift) }   // back tab
            return DBusMenuShortcut(name, modifiers: modifiers)
        }
        if let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1,
           (0xF704...0xF723).contains(scalar.value) {
            return DBusMenuShortcut("F\(scalar.value - 0xF704 + 1)", modifiers: modifiers)
        }
        // An uppercase letter is typed with Shift.
        let lower = String(character).lowercased().first ?? character
        if lower != character, character.isLetter { modifiers.insert(.shift) }
        return DBusMenuShortcut(character: lower, modifiers: modifiers)
    }

    /// Keysym names of the keys AppKit writes as control characters or its
    /// function keys' private-use characters.
    static let namedKeys: [Character: String] = [
        "\r": "Return",
        "\n": "Return",
        "\u{3}": "KP_Enter",
        "\u{1B}": "Escape",
        "\t": "Tab",
        "\u{19}": "Tab",
        // Delete to the left (⌫) is 0x7F on the Mac.
        "\u{8}": "BackSpace",
        "\u{7F}": "BackSpace",
        " ": "space",
        "\u{F700}": "Up",
        "\u{F701}": "Down",
        "\u{F702}": "Left",
        "\u{F703}": "Right",
        "\u{F727}": "Insert",
        "\u{F728}": "Delete",
        "\u{F729}": "Home",
        "\u{F72B}": "End",
        "\u{F72C}": "Page_Up",
        "\u{F72D}": "Page_Down",
        "\u{F739}": "Clear",
        "\u{F746}": "Help",
    ]
}

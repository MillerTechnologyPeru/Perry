/// A menu item as AppKit keeps it, read into values on the main thread so
/// the menu can be served from another: an NSMenuItem, with its submenu's
/// items.
public struct DesktopMenuEntry: Hashable, Sendable {
    /// What tells the item apart while it is in the menu: its object's
    /// address. Its identifier in the exported menu stays with it.
    public var key: UInt
    /// The item's title.
    public var title: String
    /// Whether the item is a separator.
    public var isSeparator: Bool
    /// Whether the item is hidden.
    public var isHidden: Bool
    /// Whether the item can be chosen, as its target last validated it.
    public var isEnabled: Bool
    /// NSControlStateValue: 1 on, 0 off, -1 mixed.
    public var state: Int
    /// The key that chooses the item, as AppKit writes it: a character,
    /// an uppercase letter for one typed with Shift, or one of the function
    /// keys' private-use characters (NSUpArrowFunctionKey…).
    public var keyEquivalent: String
    /// NSEventModifierFlags held with the key.
    public var keyEquivalentModifierMask: UInt
    /// The submenu's items, if the item opens one.
    public var submenu: [DesktopMenuEntry]?
    /// The submenu's own title, which the bar shows for an item with none.
    public var submenuTitle: String

    public init(key: UInt, title: String = "", isSeparator: Bool = false, isHidden: Bool = false, isEnabled: Bool = true,
                state: Int = 0, keyEquivalent: String = "", keyEquivalentModifierMask: UInt = ModifierMask.command,
                submenu: [DesktopMenuEntry]? = nil, submenuTitle: String = "") {
        self.key = key
        self.title = title
        self.isSeparator = isSeparator
        self.isHidden = isHidden
        self.isEnabled = isEnabled
        self.state = state
        self.keyEquivalent = keyEquivalent
        self.keyEquivalentModifierMask = keyEquivalentModifierMask
        self.submenu = submenu
        self.submenuTitle = submenuTitle
    }

    /// NSEventModifierFlags' device-independent modifier bits.
    public enum ModifierMask {
        public static let shift: UInt = 1 << 17
        public static let control: UInt = 1 << 18
        public static let option: UInt = 1 << 19
        public static let command: UInt = 1 << 20
    }
}

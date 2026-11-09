import CPerryGeometry
import Glibc
import PerryObjCInterop

// Menus on screen: a menu pops up over the views of the window it belongs
// to, inside that window (a compositor's popups need its cooperation and
// real input, and a refused one stalls drawing), and is tracked modally as
// macOS tracks it: the mouse highlights items,
// releasing it or clicking chooses one, the arrow keys move, Return
// chooses, Escape or a click elsewhere cancels, and typing selects the
// item whose title starts with what was typed. A menu taller than the
// screen scrolls with the wheel and the arrow keys. The chosen item's
// action is sent once the menu is gone.

/// A menu's rows, as drawn.
@ObjCClass("_PerryMenuView")
final class MenuView: NSView {
    var trackedMenu: NSMenu?
    var font = NSFont.menuFont(ofSize: 0)
    var highlighted: Int?
    /// How far the rows are scrolled up, for a menu taller than its window.
    var scroll: CGFloat = 0

    public required init() { super.init() }

    @ObjCMethod("initWithFrame:")
    public required init(frame: CGRect) { super.init(frame: frame) }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) { super.init(coder: coder) }

    static let rowHeight: CGFloat = 22
    static let separatorHeight: CGFloat = 11
    static let inset: CGFloat = 5

    @ObjCMethod("isFlipped") override func isFlipped() -> Bool { true }

    /// A pull-down menu's first item is its button's title, not a choice.
    var skipsFirstItem = false

    var items: [NSMenuItem] { Array((trackedMenu?.items ?? []).dropFirst(skipsFirstItem ? 1 : 0)).filter { !$0.hidden } }

    static func height(of item: NSMenuItem) -> CGFloat { item.separator ? separatorHeight : rowHeight }

    /// The rows' top edges, from the menu's top inset, unscrolled.
    func rowTops() -> [CGFloat] {
        var y = MenuView.inset
        return items.map { item in
            defer { y += MenuView.height(of: item) }
            return y
        }
    }

    var contentHeight: CGFloat { (rowTops().last ?? 0) + (items.last.map(MenuView.height) ?? 0) + MenuView.inset }

    /// The row under a point, if it is an item that can be chosen.
    func row(at point: CGPoint) -> Int? {
        let y = point.y + scroll
        for (index, top) in rowTops().enumerated() where y >= top && y < top + MenuView.height(of: items[index]) {
            let item = items[index]
            return item.separator || !item.enabled ? nil : index
        }
        return nil
    }

    /// The text a key equivalent shows: its modifiers' symbols, then the key.
    static func keyEquivalentText(_ item: NSMenuItem) -> String {
        guard !item.keyEquivalent.isEmpty else { return "" }
        let mask = item.keyEquivalentModifierMask
        // As Linux's menus show them: Command is Control here.
        var text = ""
        if mask & ModifierFlags.control != 0 && mask & ModifierFlags.command == 0 { text += "Ctrl+" }
        if mask & ModifierFlags.command != 0 { text += "Ctrl+" }
        if mask & ModifierFlags.option != 0 { text += "Alt+" }
        var key = item.keyEquivalent
        // An uppercase letter is typed with shift.
        if mask & ModifierFlags.shift != 0 || (key.count == 1 && key.uppercased() == key && key.lowercased() != key) { text += "Shift+" }
        let names: [String: String] = ["\r": "↩", "\u{1b}": "⎋", "\t": "⇥", "\u{8}": "⌫", "\u{7f}": "⌫", " ": "Space",
                                       "\u{F700}": "↑", "\u{F701}": "↓", "\u{F702}": "←", "\u{F703}": "→"]
        key = names[key] ?? key.uppercased()
        return text + key
    }

    /// The width the items need: their titles and key equivalents, with
    /// room for check marks and submenu arrows.
    func neededWidth() -> CGFloat {
        var titles: CGFloat = 0, keys: CGFloat = 0
        for item in items where !item.separator {
            titles = max(titles, Text.width(item.title, font: font) + CGFloat(item.indentationLevel) * 10)
            keys = max(keys, Text.width(MenuView.keyEquivalentText(item), font: font) + (item.submenu != nil ? 16 : 0))
        }
        return ceil(22 + titles + (keys > 0 ? 30 + keys : 0) + 16)
    }

    @ObjCMethod("drawRect:")
    override func draw(_ dirty: CGRect) {
        guard let context = NSGraphicsContext.currentCG else { return }
        let dark = Appearances.currentIsDark
        let background = dark ? NSColor(white: 0.17, alpha: 1) : NSColor(white: 0.96, alpha: 1)
        background.setFill()
        NSRectFill(bounds)
        (dark ? NSColor(white: 1, alpha: 0.15) : NSColor(white: 0, alpha: 0.2)).setStroke()
        CG.strokeRect(context, bounds.insetBy(dx: 0.5, dy: 0.5))
        let text = dark ? NSColor(white: 1, alpha: 0.88) : NSColor(white: 0, alpha: 0.88)
        let disabled = dark ? NSColor(white: 1, alpha: 0.3) : NSColor(white: 0, alpha: 0.3)
        let tops = rowTops()
        for (index, item) in items.enumerated() {
            let top = tops[index] - scroll
            let height = MenuView.height(of: item)
            guard top + height > 0, top < bounds.height else { continue }
            if item.separator {
                (dark ? NSColor(white: 1, alpha: 0.12) : NSColor(white: 0, alpha: 0.12)).setFill()
                NSRectFill(CGRect(x: 10, y: top + height / 2, width: bounds.width - 20, height: 1))
                continue
            }
            let row = CGRect(x: MenuView.inset, y: top, width: bounds.width - 2 * MenuView.inset, height: height)
            let highlight = index == highlighted
            if highlight {
                NSColor.selectedContentBackgroundColor().setFill()
                NSBezierPath.bezierPath(roundedRect: row, xRadius: 4, yRadius: 4).fill()
            }
            let color = !item.enabled ? disabled : highlight ? NSColor.whiteColor() : text
            let lineHeight = Text.lineHeight(font)
            let baseline = CGRect(x: 0, y: top + (height - lineHeight) / 2, width: 0, height: lineHeight)
            // The state column: a check mark, or a dash for mixed.
            if item.state != 0 {
                Text.draw([TextRun(text: item.state == 1 ? "✓" : "–", font: font, color: color)],
                          in: CGRect(x: 10, y: baseline.minY, width: 14, height: baseline.height))
            }
            let indent = 24 + CGFloat(item.indentationLevel) * 10
            Text.draw([TextRun(text: item.title, font: font, color: color)],
                      in: CGRect(x: indent, y: baseline.minY, width: bounds.width - indent - 10, height: baseline.height),
                      style: TextStyle(alignment: 0, lineBreakMode: 4, maximumLines: 1))
            let trailing = item.submenu != nil ? "▸" : MenuView.keyEquivalentText(item)
            if !trailing.isEmpty {
                let keyColor = highlight ? NSColor.whiteColor() : (item.enabled ? (dark ? NSColor(white: 1, alpha: 0.5) : NSColor(white: 0, alpha: 0.5)) : disabled)
                Text.draw([TextRun(text: trailing, font: font, color: keyColor)],
                          in: CGRect(x: 0, y: baseline.minY, width: bounds.width - 16, height: baseline.height), style: TextStyle(alignment: 2))
            }
        }
        // Arrows where the menu scrolls.
        if scroll > 0 {
            Text.draw([TextRun(text: "▴", font: font, color: text)], in: CGRect(x: 0, y: 0, width: bounds.width, height: MenuView.inset + 12),
                      style: TextStyle(alignment: 1))
        }
        if scroll + bounds.height < contentHeight - 0.5 {
            Text.draw([TextRun(text: "▾", font: font, color: text)],
                      in: CGRect(x: 0, y: bounds.height - MenuView.inset - 14, width: bounds.width, height: 14), style: TextStyle(alignment: 1))
        }
    }

    /// Scrolls so that a row shows.
    func reveal(_ index: Int) {
        let tops = rowTops()
        guard tops.indices.contains(index) else { return }
        let top = tops[index], bottom = top + MenuView.height(of: items[index])
        if top - scroll < MenuView.inset { scroll = max(0, top - MenuView.inset) }
        if bottom - scroll > bounds.height - MenuView.inset { scroll = min(contentHeight - bounds.height, bottom - bounds.height + MenuView.inset) }
        setNeedsDisplay(true)
    }

    func scroll(by delta: CGFloat) {
        scroll = max(0, min(max(0, contentHeight - bounds.height), scroll + delta))
        setNeedsDisplay(true)
    }
}

enum MenuTracking {
    nonisolated(unsafe) static var tracking = false

    /// Brings a menu up to date before it shows: its delegate fills it,
    /// and items enable as their targets validate them.
    static func prepare(_ menu: NSMenu) {
        let delegate = menu.delegate
        if let delegate, Send.responds(delegate, "menuNeedsUpdate:") { Send.void(delegate, "menuNeedsUpdate:", menu.objcObject) }
        Send.void(menu.objcObject, "update")
    }

    /// Shows `menu` with `item`'s row at `location` in `view` (or its top
    /// left there), tracks it, and returns the item chosen, after sending
    /// its action.
    @discardableResult
    static func popUp(_ menu: NSMenu, positioning item: NSMenuItem?, at location: CGPoint, in view: NSView?, minimumWidth: CGFloat = 0,
                      font: NSFont? = nil, skipsFirstItem: Bool = false, performs: Bool = true) -> NSMenuItem? {
        guard !tracking, let parent = view?.window ?? Windows.key, parent.sdlWindow != nil else { return nil }
        prepare(menu)
        let menuView = MenuView(frame: .zero)
        menuView.trackedMenu = menu
        menuView.skipsFirstItem = skipsFirstItem
        if let font { menuView.font = font } else if let font = menu.font { menuView.font = font }
        let items = menuView.items
        guard !items.isEmpty else { return nil }
        let delegate = menu.delegate
        if let delegate, Send.responds(delegate, "menuWillOpen:") { Send.void(delegate, "menuWillOpen:", menu.objcObject) }

        // Within the window, y upwards: the menu draws over the window's
        // views, kept inside it, and scrolls when it is taller.
        guard let root = parent.rootView else { return nil }
        let point = view.map { $0.convert(location, to: nil) } ?? location
        let bounds = CGRect(origin: .zero, size: parent.frame.size).insetBy(dx: 2, dy: 2)
        let width = min(max(menuView.neededWidth(), minimumWidth, menu.minimumWidth), bounds.width)
        let tops = menuView.rowTops()
        let positioned = item.flatMap { target in items.firstIndex { $0 === target } }
        let height = min(menuView.contentHeight, bounds.height)
        // The positioning item's row over the location, the menu's top at it
        // otherwise.
        var top = point.y + (positioned.map { tops[$0] + MenuView.rowHeight / 2 + 1 } ?? 0)
        top = min(top, bounds.maxY)
        var frame = CGRect(x: point.x - (positioned != nil ? 20 : 0), y: top - height, width: width, height: height)
        if frame.minY < bounds.minY { frame.origin.y = bounds.minY }
        frame.origin.x = max(bounds.minX, min(frame.minX, bounds.maxX - width))
        place(menuView, at: frame, in: root)
        if let positioned {
            // The menu scrolls so the item is over the location when it can.
            let rowInView = frame.maxY - point.y - MenuView.rowHeight / 2
            menuView.scroll(by: tops[positioned] - rowInView)
            if item?.enabled == true { menuView.highlighted = positioned }
            menuView.reveal(positioned)
        }
        Trace.log("menu of \(items.count) items at \(frame) in window \(parent.windowNumber)")

        tracking = true
        let chosen = Tracker(window: parent, root: root, bounds: bounds, first: Level(view: menuView, frame: frame)).run()
        tracking = false
        Windows.layersChanged()
        if let delegate, Send.responds(delegate, "menuDidClose:") { Send.void(delegate, "menuDidClose:", menu.objcObject) }
        if let chosen, performs { perform(chosen) }
        return chosen
    }

    /// Sets a menu view's frame from one in window coordinates, y upwards.
    static func place(_ view: MenuView, at frame: CGRect, in root: NSView) {
        let origin = root.convert(frame.origin, from: nil)
        view.setFrame(CGRect(x: origin.x, y: root.flipped ? origin.y - frame.height : origin.y, width: frame.width, height: frame.height))
    }

    /// Sends a chosen item's action: to its target, or along the responder
    /// chain from the key window's first responder.
    static func perform(_ item: NSMenuItem) {
        guard let action = item.action, let app = App.shared else { return }
        let sent = app.sendAction(action, to: item.target.map(NSObject.init), from: item)
        Trace.log("menu item \(item.title): \(action.name) \(sent ? "sent" : "had no receiver")")
    }

    /// An open menu: the top one, or a submenu, with its frame in window
    /// coordinates.
    struct Level {
        let view: MenuView
        let frame: CGRect
    }

    /// The modal loop: events go to the open menus until an item is chosen
    /// or the menus are dismissed. A submenu opens beside its item when the
    /// item is highlighted, and closes when another item of its parent is.
    final class Tracker {
        let window: NSWindow
        let root: NSView
        let bounds: CGRect
        var levels: [Level]

        init(window: NSWindow, root: NSView, bounds: CGRect, first: Level) {
            (self.window, self.root, self.bounds, levels) = (window, root, bounds, [first])
            root.addSubview(first.view)
            Windows.layersChanged()
        }

        /// The event's location in a level's view, y down.
        func point(_ location: CGPoint, in level: Level) -> CGPoint {
            CGPoint(x: location.x - level.frame.minX, y: level.frame.maxY - location.y)
        }

        /// The deepest open menu under a location.
        func level(at location: CGPoint) -> Int? { levels.indices.last { levels[$0].frame.contains(location) } }

        /// Closes the submenus deeper than `depth`.
        func close(after depth: Int) {
            while levels.count > depth + 1 {
                let level = levels.removeLast()
                level.view.removeFromSuperview()
                if let menu = level.view.trackedMenu, let delegate = menu.delegate, Send.responds(delegate, "menuDidClose:") {
                    Send.void(delegate, "menuDidClose:", menu.objcObject)
                }
            }
            Windows.layersChanged()
        }

        /// Highlights a row of a level, opening its submenu and closing
        /// deeper ones.
        func highlight(_ row: Int?, at depth: Int, openSubmenu: Bool = true) {
            let level = levels[depth]
            let changed = level.view.highlighted != row
            if changed {
                level.view.highlighted = row
                level.view.setNeedsDisplay(true)
            }
            if changed || levels.count <= depth + 1 { close(after: depth) }
            guard openSubmenu, levels.count == depth + 1, let row, let submenu = level.view.items[row].submenu else { return }
            open(submenu, beside: row, of: depth)
        }

        func open(_ submenu: NSMenu, beside row: Int, of depth: Int) {
            let parent = levels[depth]
            MenuTracking.prepare(submenu)
            let delegate = submenu.delegate
            if let delegate, Send.responds(delegate, "menuWillOpen:") { Send.void(delegate, "menuWillOpen:", submenu.objcObject) }
            let view = MenuView(frame: .zero)
            view.trackedMenu = submenu
            view.font = submenu.font ?? parent.view.font
            guard !view.items.isEmpty else { return }
            let width = min(max(view.neededWidth(), submenu.minimumWidth), bounds.width)
            let height = min(view.contentHeight, bounds.height)
            // Beside the parent, its first row level with the item's; to the
            // left when there is no room on the right.
            var x = parent.frame.maxX - 3
            if x + width > bounds.maxX { x = max(bounds.minX, parent.frame.minX - width + 3) }
            let rowTop = parent.frame.maxY - (parent.view.rowTops()[row] - parent.view.scroll)
            var frame = CGRect(x: x, y: rowTop + MenuView.inset - height, width: width, height: height)
            if frame.minY < bounds.minY { frame.origin.y = bounds.minY }
            if frame.maxY > bounds.maxY { frame.origin.y = bounds.maxY - height }
            MenuTracking.place(view, at: frame, in: root)
            root.addSubview(view)
            levels.append(Level(view: view, frame: frame))
            Windows.layersChanged()
        }

        func run() -> NSMenuItem? {
            defer { close(after: 0); levels[0].view.removeFromSuperview() }
            guard let app = App.shared else { return nil }
            let opened = Clock.now
            var moved = false
            /// The menu the button went down in: a submenu that opens under
            /// the pointer doesn't take that click's release.
            var downDepth: Int?
            var movedSinceDown = false
            var typed = ""
            var lastTyped = 0.0
            let future = NSDate.distantFuture()
            while true {
                guard let event = Send.nextEvent(app.objcObject, mask: UInt64.max, until: future.objcObject, mode: nil, dequeue: true)
                    .flatMap({ NSEvent.objCInstance($0, ownership: .retain) }) else { continue }
                let inWindow = event.window === window || event.window == nil
                let location = event.locationInWindow
                let depth = inWindow ? level(at: location) : nil
                switch event.type {
                case .mouseMoved, .leftMouseDragged, .rightMouseDragged:
                    moved = true
                    movedSinceDown = true
                    guard let depth else {
                        // Off the menus, the deepest menu's highlight goes,
                        // unless it leads to an open submenu.
                        let last = levels.count - 1
                        if levels[last].view.highlighted != nil, levels[last].view.items[levels[last].view.highlighted!].submenu == nil {
                            highlight(nil, at: last, openSubmenu: false)
                        }
                        break
                    }
                    highlight(levels[depth].view.row(at: point(location, in: levels[depth])), at: depth)
                case .leftMouseUp, .rightMouseUp:
                    // The release of the click that opened the menu chooses
                    // only after the mouse moved or a moment passed.
                    guard let depth, moved || Clock.now - opened > 0.4 else { break }
                    if let downDepth, downDepth != depth, !movedSinceDown { break }
                    let view = levels[depth].view
                    let row = view.row(at: point(location, in: levels[depth]))
                    // Releasing on an item with a submenu opens it.
                    highlight(row, at: depth)
                    if let row, view.items[row].submenu == nil { return MenuTracking.choose(view, row) }
                case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                    guard let depth else { return nil }
                    highlight(levels[depth].view.row(at: point(location, in: levels[depth])), at: depth)
                    moved = true
                    downDepth = depth
                    movedSinceDown = false
                case .scrollWheel:
                    if let depth { levels[depth].view.scroll(by: -event.scrollingDeltaY) }
                case .keyDown:
                    // Keys go to the deepest open menu.
                    let active = levels.count - 1
                    let view = levels[active].view
                    let items = view.items
                    func step(_ direction: Int) {
                        var index = view.highlighted ?? (direction > 0 ? -1 : items.count)
                        for _ in items.indices {
                            index += direction
                            guard items.indices.contains(index) else { return }
                            if !items[index].separator && items[index].enabled { break }
                        }
                        guard items.indices.contains(index), !items[index].separator, items[index].enabled else { return }
                        highlight(index, at: active, openSubmenu: false)
                        view.reveal(index)
                    }
                    switch event.keyCode {
                    case 0x35: return nil // escape
                    case 0x24, 0x4C, 0x7C: // return, enter, right: into a submenu, or choose
                        guard let row = view.highlighted else {
                            if event.keyCode != 0x7C { return nil }
                            break
                        }
                        if let submenu = items[row].submenu {
                            if levels.count == active + 1 { open(submenu, beside: row, of: active) }
                            if levels.count > active + 1 { highlight(nil, at: active + 1, openSubmenu: false); stepInto(active + 1) }
                        } else if event.keyCode != 0x7C {
                            return MenuTracking.choose(view, row)
                        }
                    case 0x7B: // left: out of a submenu
                        if active > 0 { close(after: active - 1) }
                    case 0x7E: step(-1)
                    case 0x7D: step(1)
                    case 0x73: highlight(nil, at: active, openSubmenu: false); step(1)
                    case 0x77: highlight(nil, at: active, openSubmenu: false); step(-1)
                    default:
                        // Type-select: the first item whose title starts with
                        // what was typed in the last second.
                        guard !event.characters.isEmpty, event.modifierFlags & ModifierFlags.command == 0 else { break }
                        if Clock.now - lastTyped > 1 { typed = "" }
                        lastTyped = Clock.now
                        typed += event.characters.lowercased()
                        if let index = items.indices.first(where: { !items[$0].separator && items[$0].enabled && items[$0].title.lowercased().hasPrefix(typed) }) {
                            highlight(index, at: active, openSubmenu: false)
                            view.reveal(index)
                        }
                    }
                default:
                    break
                }
                if window.sdlWindow == nil || !window.visible { return nil }
            }
        }

        /// Highlights a submenu's first item that can be chosen.
        private func stepInto(_ depth: Int) {
            let view = levels[depth].view
            if let first = view.items.indices.first(where: { !view.items[$0].separator && view.items[$0].enabled }) {
                highlight(first, at: depth, openSubmenu: false)
            }
        }
    }

    static func choose(_ view: MenuView, _ row: Int) -> NSMenuItem? {
        let items = view.items
        guard items.indices.contains(row) else { return nil }
        let item = items[row]
        // A brief flash of the chosen row, as macOS gives.
        view.highlighted = nil
        view.setNeedsDisplay(true)
        Windows.drawIfNeeded()
        return item.submenu == nil ? item : nil
    }
}

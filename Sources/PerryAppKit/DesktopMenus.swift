import CacaoDBusMenu
import Glibc
import PerryDesktopMenus
import PerryObjCInterop
import SDL3Swift

// The main menu in the desktop's global menu bar, served over
// `com.canonical.dbusmenu` as the app built it: the application menu first,
// titled with the app's name, and the Window menu where the app put it. It
// is served at /MenuBar on a session bus connection of its own, tied to
// each window with the compositor's KDE appmenu protocol where it offers
// one, and found by the app's Wayland app_id (its bundle identifier) through
// the bus name Cacao's AppMenuDiscovery makes from it, for compositors
// without the protocol (sway).
//
// The menu is read again every half second while the app runs and after an
// item is chosen; before the bar opens a menu, the menu's delegate fills
// it and its items are validated (-validateMenuItem:, NSMenuItemValidation,
// NSUserInterfaceValidations), so enabled states and titles are current. A
// click sends the item's action as choosing it in the app does. Key
// equivalents are shown with Command as Super on Cacao's desktop, whose bar
// draws Super as ⌘, and as Control on others; in the app, Super and Control
// both still choose them.
//
// When a menu bar shows the menus (the compositor ties windows to them, or
// a menu bar owns com.canonical.AppMenu.Registrar), windows leave out their
// own menu bar, and take it back if the menu bar quits. With no session bus
// or no menu bar, nothing changes.
//
// PERRY_APPKIT_GLOBAL_MENU=0 serves no menu.

enum DesktopMenus {
    static var enabled: Bool { getenv("PERRY_APPKIT_GLOBAL_MENU").map { String(cString: $0) != "0" } ?? true }

    /// How long the first look at whether a menu bar is there waits, as a
    /// window first decides whether to show its own.
    static let firstLookWait = 2.0

    /// How often the menu is read again.
    static let refreshNanoseconds: Int64 = 500_000_000

    /// How long the bar's AboutToShow waits for the main thread.
    static let validationWait = 1.0

    nonisolated(unsafe) private static var service: DesktopMenuService?
    nonisolated(unsafe) private static var mapping = DesktopMenuMapping(
        commandKey: DesktopMenuMapping.commandKey(forDesktop: getenv("XDG_CURRENT_DESKTOP").map { String(cString: $0) }))
    /// The menu last served.
    nonisolated(unsafe) private static var served: DBusMenuItem?
    /// Whether the first look at the menu bar's presence was waited for.
    nonisolated(unsafe) private static var lookedOnce = false
    /// Whether windows were last laid out with the desktop showing menus.
    nonisolated(unsafe) private static var appliedShown = false

    // MARK: Starting and stopping

    /// Starts serving the menu, with a display: as SDL's video starts, or
    /// as a window first asks whether to show its own menu bar.
    static func start() {
        guard enabled, service == nil, SDLSession.wanted else { return }
        service = DesktopMenuService.start(appID: SDLSession.appID) { id in
            _ = await DesktopMenuService.result(within: validationWait, scheduling: { work in Dispatch.onMain(work) }) {
                DesktopMenus.validate(id)
            }
        } onClick: { id in
            Dispatch.onMain { DesktopMenus.choose(id) }
        } onPresence: { present in
            Dispatch.onMain { DesktopMenus.registrarChanged(present) }
        } onServed: { _ in
            Dispatch.onMain { DesktopMenus.didServe() }
        }
    }

    /// As the app ends: replies to the bar, such as the one to the Quit
    /// item's click, go out first.
    static func stop() {
        guard let service else { return }
        self.service = nil
        for tie in ties.values { tie.destroy() }
        ties = [:]
        service.stop()
    }

    // MARK: Whether the desktop shows the menus

    /// Whether a menu bar shows the menus, so windows leave out their own:
    /// they're served, and the compositor ties windows to them or a menu bar
    /// owns the Registrar.
    static var shownByDesktop: Bool {
        start()
        guard let service else { return false }
        let wait = lookedOnce ? 0 : firstLookWait
        lookedOnce = true
        let registrar = service.menuBarIsPresent(waitingAtMost: wait)
        guard service.address != nil else { return false }
        return registrar || compositorShowsMenus
    }

    private static func registrarChanged(_ present: Bool) {
        Trace.log("global menu bar \(present ? "present" : "absent")")
        applyShown()
    }

    /// Windows show or leave out their menu bars as the desktop does.
    private static func applyShown() {
        let shown = shownByDesktop
        guard shown != appliedShown else { return }
        appliedShown = shown
        // The application menu's items go back where the app put them.
        if shown { MenuBar.restore() }
        for window in Windows.all where window.visible { window.chromeChanged() }
        refresh()
    }

    // MARK: The compositor's appmenu protocol

    nonisolated(unsafe) private static var surfaces: DesktopMenuSurfaces?
    nonisolated(unsafe) private static var askedCompositor = false
    nonisolated(unsafe) private static var ties: [UnsafeMutableRawPointer: DesktopMenuSurfaces.Tie] = [:]

    /// Whether the compositor ties windows to menus: SDL's Wayland display
    /// offers the appmenu manager. Asked once, on the main thread.
    static var compositorShowsMenus: Bool {
        if !askedCompositor, SDLSession.started == true {
            askedCompositor = true
            if SDL.currentVideoDriver == "wayland", let display = SDL.globalProperties.pointer("SDL.video.wayland.wl_display") {
                surfaces = DesktopMenuSurfaces(display: display)
                Trace.log("compositor \(surfaces == nil ? "has no" : "offers the") appmenu protocol")
            }
        }
        return surfaces != nil
    }

    /// Ties a window's new SDL window to the menu, once it is served.
    static func windowMade(_ window: NSWindow) {
        guard compositorShowsMenus, let surfaces, let address = service?.address, let sdlWindow = window.sdlWindow,
              let surface = sdlWindow.properties.pointer("SDL.window.wayland.surface") else { return }
        ties[window.objcObject]?.destroy()
        ties[window.objcObject] = surfaces.tie(surface: surface, to: address)
    }

    /// Unties a window before SDL destroys its surface.
    static func windowGoing(_ window: NSWindow) {
        ties.removeValue(forKey: window.objcObject)?.destroy()
    }

    /// The menu is on the bus: windows are tied to it, and it is read.
    private static func didServe() {
        for window in Windows.all where window.sdlWindow != nil { windowMade(window) }
        refresh()
        applyShown()
        scheduleRefresh()
    }

    // MARK: The menu

    private static func scheduleRefresh() {
        Dispatch.after(nanoseconds: refreshNanoseconds) {
            guard service != nil else { return }
            refresh()
            scheduleRefresh()
        }
    }

    /// Reads the menu again and serves it if it changed.
    static func refresh() {
        guard let service else { return }
        let menu = makeMenu()
        guard menu != served else { return }
        served = menu
        service.publish(menu)
    }

    /// The delegate of the menu with an identifier fills it and its items
    /// are validated, as before it opens in the app; then the menu is served
    /// again if that changed it.
    private static func validate(_ id: Int32) {
        if id == DBusMenuItem.rootID {
            if let main = MenuBar.mainMenu, let delegate = main.delegate, Send.responds(delegate, "menuNeedsUpdate:") {
                Send.void(delegate, "menuNeedsUpdate:", main.objcObject)
            }
        } else if let item = item(withID: id), let submenu = item.submenu {
            MenuTracking.prepare(submenu)
        }
        refresh()
    }

    /// The main menu as the bar reads it.
    private static func makeMenu() -> DBusMenuItem {
        guard let main = MenuBar.mainMenu else { return .root([]) }
        return mapping.menu(for: entries(of: main, depth: 0), appName: appName)
    }

    private static func entries(of menu: NSMenu, depth: Int) -> [DesktopMenuEntry] {
        // A menu inside itself goes no deeper.
        guard depth < 16 else { return [] }
        return menu.items.map { item in
            DesktopMenuEntry(key: UInt(bitPattern: item.objcObject), title: item.title, isSeparator: item.separator,
                             isHidden: item.hidden, isEnabled: item.enabled, state: item.state, keyEquivalent: item.keyEquivalent,
                             keyEquivalentModifierMask: item.keyEquivalentModifierMask,
                             submenu: item.submenu.map { entries(of: $0, depth: depth + 1) }, submenuTitle: item.submenu?.title ?? "")
        }
    }

    /// The app's name, which titles its application menu.
    static var appName: String {
        for key in ["CFBundleName", "CFBundleDisplayName", "CFBundleExecutable"] {
            if let name = NSBundle.main().infoObject(forKey: key)?.stringValue, !name.isEmpty { return name }
        }
        return "Application"
    }

    /// The item an identifier was given to, if it is still in the main menu.
    private static func item(withID id: Int32) -> NSMenuItem? {
        guard let key = mapping.key(for: id), let main = MenuBar.mainMenu else { return nil }
        func find(_ menu: NSMenu, depth: Int) -> NSMenuItem? {
            guard depth < 16 else { return nil }
            for item in menu.items {
                if UInt(bitPattern: item.objcObject) == key { return item }
                if let submenu = item.submenu, let found = find(submenu, depth: depth + 1) { return found }
            }
            return nil
        }
        return find(main, depth: 0)
    }

    /// The bar's click: the item's action is sent, if it is still enabled
    /// once validated, as choosing it in the app does.
    private static func choose(_ id: Int32) {
        guard let item = item(withID: id), item.submenu == nil, !item.separator else { return }
        if let owner = item.menu.map({ NSMenu.objCInstance($0, ownership: .retain) }) { MenuTracking.prepare(owner) }
        guard item.enabled else {
            Trace.log("global menu item \(item.title) is disabled")
            return
        }
        MenuTracking.perform(item)
        refresh()
    }
}

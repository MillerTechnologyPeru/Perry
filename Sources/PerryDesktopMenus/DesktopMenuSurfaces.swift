internal import CacaoWayland

/// Ties windows to the served menu with the compositor's KDE appmenu
/// protocol (`org_kde_kwin_appmenu_manager`), so a compositor that offers it
/// tells the menu bar which menu the focused window has. The tie between
/// windows and menus is all here and in CacaoWayland, so another protocol
/// replacing KDE's changes nothing else.
///
/// Wayland's objects are SDL's: call these on the thread SDL's video runs on.
public final class DesktopMenuSurfaces {
    private let manager: OpaquePointer

    /// Binds the compositor's appmenu manager on a Wayland display (a
    /// `struct wl_display *`); nil if the compositor doesn't offer one.
    public init?(display: UnsafeMutableRawPointer) {
        guard let manager = cacao_wayland_appmenu_manager_create(display) else { return nil }
        self.manager = manager
    }

    deinit { cacao_wayland_appmenu_manager_destroy(manager) }

    /// A window's tie to the menu.
    public final class Tie {
        private var menu: OpaquePointer?
        private var address: DesktopMenuService.Address

        fileprivate init(menu: OpaquePointer, address: DesktopMenuService.Address) {
            self.menu = menu
            self.address = address
        }

        /// Moves the window's menu to another address.
        public func setAddress(_ address: DesktopMenuService.Address) {
            guard let menu, address != self.address else { return }
            self.address = address
            cacao_wayland_appmenu_set_address(menu, address.service, address.path)
        }

        /// Unties the window: before its surface is destroyed.
        public func destroy() {
            guard let menu else { return }
            cacao_wayland_appmenu_destroy(menu)
            self.menu = nil
        }

        deinit { destroy() }
    }

    /// Ties a window's surface (a `struct wl_surface *`) to the menu at an
    /// address, which should be on the bus already.
    public func tie(surface: UnsafeMutableRawPointer, to address: DesktopMenuService.Address) -> Tie? {
        guard let menu = cacao_wayland_appmenu_create(manager, surface, address.service, address.path) else { return nil }
        return Tie(menu: menu, address: address)
    }
}

import CPerryGeometry
import Glibc
import PerryDesktopDock
import PerryObjCInterop

// The app's tile in the desktop's dock: NSDockTile's badge as the count on
// the app's icon, and NSApplication's requests for attention as its urgent
// flag, sent as com.canonical.Unity.LauncherEntry updates for the app's
// desktop entry, named by its app_id (its bundle identifier), which Cacao's
// dock and KDE's read. A badge the dock can't show as a count, such as
// "New", shows nothing yet.
//
// PERRY_APPKIT_DOCK_TILE=0 sends nothing.

enum DockTile {
    static var enabled: Bool { getenv("PERRY_APPKIT_DOCK_TILE").map { String(cString: $0) != "0" } ?? true }

    /// The app's tile.
    nonisolated(unsafe) static let tile = NSDockTile()

    nonisolated(unsafe) private static var entry: DesktopLauncherEntry?
    nonisolated(unsafe) private static var state = DesktopLauncherEntry.State()
    /// The request for attention open, if any.
    nonisolated(unsafe) private static var attentionRequest = 0

    /// The count a badge label shows: a whole number, or none.
    static func count(forBadge label: String?) -> Int64? {
        guard let label else { return nil }
        return Int64(String(label.filter { !$0.isWhitespace }))
    }

    static func setBadge(_ label: String?) {
        state.count = count(forBadge: label)
        send()
    }

    /// NSApplication's requestUserAttention: its request's number.
    static func requestAttention() -> Int {
        attentionRequest += 1
        state.urgent = true
        send()
        return attentionRequest
    }

    static func cancelAttention(_ request: Int) {
        guard request == attentionRequest || request == 0 else { return }
        state.urgent = false
        send()
    }

    private static func send() {
        guard enabled, let appID = SDLSession.appID else { return }
        if entry == nil {
            entry = DesktopLauncherEntry(appID: appID)
        }
        entry?.update(state)
    }
}

@ObjCClass("NSDockTile")
open class NSDockTile: NSObject {
    var badgeLabel: String?
    var contentView: NSObject?
    var showsApplicationBadge = true

    public required override init() { super.init() }

    @ObjCMethod("badgeLabel") func tileBadgeLabel() -> String? { badgeLabel }
    @ObjCMethod("setBadgeLabel:") func setBadgeLabel(_ label: String?) {
        badgeLabel = label?.isEmpty == true ? nil : label
        DockTile.setBadge(badgeLabel)
    }
    @ObjCMethod("contentView") func tileContentView() -> NSObject? { contentView }
    @ObjCMethod("setContentView:") func setContentView(_ view: NSObject?) { contentView = view }
    /// The desktop draws the app's icon itself: a custom view isn't shown.
    @ObjCMethod("display") func display() {}
    @ObjCMethod("size") func size() -> CGSize { CGSize(width: 128, height: 128) }
    @ObjCMethod("showsApplicationBadge") func tileShowsApplicationBadge() -> Bool { showsApplicationBadge }
    @ObjCMethod("setShowsApplicationBadge:") func setShowsApplicationBadge(_ shows: Bool) { showsApplicationBadge = shows }
    @ObjCMethod("owner") func owner() -> NSObject? { App.shared }
}

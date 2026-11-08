import CPerryGeometry
import PerryObjCInterop

// UIRefreshControl: the control a scroll view keeps for pull to refresh. Its
// refreshing state is kept for apps that ask it and for end/beginRefreshing,
// and the scroll view holds it; the pull itself and its spinner aren't
// drawn.

final class RefreshControlState: ObjectState {
    var refreshing = false
    var attributedTitle: AnyObject?
}

@ObjCClass("UIRefreshControl")
open class UIRefreshControl: UIControl {
    static let refreshStates = StateTable<RefreshControlState>()
    var refreshState: RefreshControlState { UIRefreshControl.refreshStates[objcObject] }

    @ObjCMethod("dealloc")
    override func dealloc() {
        UIRefreshControl.refreshStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCMethod("isRefreshing") func isRefreshing() -> Bool { refreshState.refreshing }
    @ObjCMethod("beginRefreshing") func beginRefreshing() { refreshState.refreshing = true }
    @ObjCMethod("endRefreshing") func endRefreshing() { refreshState.refreshing = false }
    @ObjCMethod("beginRefreshingWithOffset:") func beginRefreshing(offset: CGFloat) { refreshState.refreshing = true }
}

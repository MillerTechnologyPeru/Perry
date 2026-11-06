import CPerryGeometry
import PerryObjCInterop

// UISearchController: a search bar, shown below the navigation bar of the
// controller whose navigation item holds it, that tells its results
// updater whenever its text changes. Results show in the controller the
// app made for them only if the app shows it itself; apps that filter
// their own table, as most do, need nothing more.

final class SearchControllerState: ObjectState {
    var searchBar: UISearchBar?
    var resultsController: UIViewController?
    /// Not retained, as UIKit's are weak.
    var resultsUpdater: UnsafeMutableRawPointer?
    var delegate: UnsafeMutableRawPointer?
    var active = false
    var obscuresBackground = true
    var hidesNavigationBar = true
    var showsCancelButton = true
}

@ObjCClass("UISearchController")
open class UISearchController: UIViewController {
    static let searchStates = StateTable<SearchControllerState>()
    var searching: SearchControllerState { UISearchController.searchStates[objcObject] }

    @ObjCMethod("dealloc")
    override func dealloc() {
        searching.searchBar?.search.controller = nil
        UISearchController.searchStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCMethod("initWithSearchResultsController:")
    func initialize(searchResultsController: UIViewController?) -> Self {
        // UIViewController's initializer, as a super call.
        _ = initialize(nibName: nil, bundle: nil)
        searching.resultsController = searchResultsController
        return self
    }

    @ObjCMethod("init")
    override func initialize() -> NSObject { initialize(searchResultsController: nil) }

    /// The search bar, made the first time it is asked for.
    @ObjCMethod("searchBar")
    func searchBar() -> UISearchBar {
        if let bar = searching.searchBar { return bar }
        let bar = UISearchBar.objCClass.object.allocated().initializeView(frame: CGRect(x: 0, y: 0, width: Screen.bounds.width, height: 56))
            .unsafeCast(to: UISearchBar.self)
        bar.search.controller = objcObject
        searching.searchBar = bar
        return bar
    }

    @ObjCMethod("searchResultsController") func searchResultsController() -> UIViewController? { searching.resultsController }
    @ObjCMethod("searchResultsUpdater") func searchResultsUpdater() -> NSObject? { searching.resultsUpdater.map { NSObject($0) } }
    @ObjCMethod("setSearchResultsUpdater:") func setSearchResultsUpdater(_ updater: NSObject?) { searching.resultsUpdater = updater?.objcObject }
    @ObjCMethod("delegate") func delegate() -> NSObject? { searching.delegate.map { NSObject($0) } }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { searching.delegate = delegate?.objcObject }

    @ObjCMethod("isActive") func isActive() -> Bool { searching.active }

    /// Activating tells the delegate the search will show and did; ending
    /// it clears the bar and puts the keyboard away.
    @ObjCMethod("setActive:")
    func setActive(_ active: Bool) {
        guard searching.active != active else { return }
        let delegate = delegate()
        if active {
            if let delegate, delegate.responds(to: "willPresentSearchController:") { delegate.sendWillPresentSearchController(self) }
            searching.active = true
            if let delegate, delegate.responds(to: "didPresentSearchController:") { delegate.sendDidPresentSearchController(self) }
        } else {
            if let delegate, delegate.responds(to: "willDismissSearchController:") { delegate.sendWillDismissSearchController(self) }
            searching.active = false
            let bar = searchBar()
            _ = bar.field.sendResignFirstResponder()
            bar.setText(nil)
            bar.setNeedsLayout()
            if let delegate, delegate.responds(to: "didDismissSearchController:") { delegate.sendDidDismissSearchController(self) }
        }
        updateResults()
    }

    @ObjCMethod("obscuresBackgroundDuringPresentation") func obscuresBackground() -> Bool { searching.obscuresBackground }
    @ObjCMethod("setObscuresBackgroundDuringPresentation:") func setObscuresBackground(_ obscures: Bool) { searching.obscuresBackground = obscures }
    @ObjCMethod("dimsBackgroundDuringPresentation") func dimsBackground() -> Bool { searching.obscuresBackground }
    @ObjCMethod("setDimsBackgroundDuringPresentation:") func setDimsBackground(_ dims: Bool) { searching.obscuresBackground = dims }
    @ObjCMethod("hidesNavigationBarDuringPresentation") func hidesNavigationBar() -> Bool { searching.hidesNavigationBar }
    @ObjCMethod("setHidesNavigationBarDuringPresentation:") func setHidesNavigationBar(_ hides: Bool) { searching.hidesNavigationBar = hides }
    @ObjCMethod("automaticallyShowsCancelButton") func automaticallyShowsCancelButton() -> Bool { searching.showsCancelButton }
    @ObjCMethod("setAutomaticallyShowsCancelButton:") func setAutomaticallyShowsCancelButton(_ shows: Bool) { searching.showsCancelButton = shows }
    @ObjCMethod("automaticallyShowsSearchResultsController") func automaticallyShowsSearchResultsController() -> Bool { false }
    @ObjCMethod("setAutomaticallyShowsSearchResultsController:") func setAutomaticallyShowsSearchResultsController(_ shows: Bool) {}
    @ObjCMethod("showsSearchResultsController") func showsSearchResultsController() -> Bool { false }
    @ObjCMethod("setShowsSearchResultsController:") func setShowsSearchResultsController(_ shows: Bool) {}

    /// Editing the bar begins the search.
    func searchBarBeganEditing() { setActive(true) }

    /// The bar's text changed: the results updater is told.
    func searchBarChanged() {
        if !searching.active { setActive(true) } else { updateResults() }
    }

    private func updateResults() {
        guard let updater = searchResultsUpdater(), updater.responds(to: "updateSearchResultsForSearchController:") else { return }
        updater.sendUpdateSearchResults(for: self)
    }
}

extension NSObject {
    @ObjCMethod("updateSearchResultsForSearchController:") func sendUpdateSearchResults(for controller: UISearchController)
    @ObjCMethod("willPresentSearchController:") func sendWillPresentSearchController(_ controller: UISearchController)
    @ObjCMethod("didPresentSearchController:") func sendDidPresentSearchController(_ controller: UISearchController)
    @ObjCMethod("willDismissSearchController:") func sendWillDismissSearchController(_ controller: UISearchController)
    @ObjCMethod("didDismissSearchController:") func sendDidDismissSearchController(_ controller: UISearchController)
    @ObjCMethod("searchBar:textDidChange:") func sendSearchBar(_ bar: UISearchBar, textDidChange text: String)
    @ObjCMethod("searchBarTextDidBeginEditing:") func sendSearchBarTextDidBeginEditing(_ bar: UISearchBar)
    @ObjCMethod("searchBarTextDidEndEditing:") func sendSearchBarTextDidEndEditing(_ bar: UISearchBar)
    @ObjCMethod("searchBarSearchButtonClicked:") func sendSearchBarSearchButtonClicked(_ bar: UISearchBar)
}

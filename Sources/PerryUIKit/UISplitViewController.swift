import CPerryGeometry
import PerryObjCInterop

// UISplitViewController as an iPhone has it, collapsed: the primary
// controller fills the view, and the secondary is collapsed onto it in the
// first update pass, after the app has had the chance to set a delegate,
// unless the delegate takes care of it. Detail shown later is pushed onto
// the primary navigation controller, as UIKit does when collapsed.

final class SplitViewState: ObjectState {
    var viewControllers: [UIViewController] = []
    var delegate: UnsafeMutableRawPointer?
    var preferredDisplayMode = 0
    var preferredPrimaryColumnWidthFraction: CGFloat = -3.40282347e38      // UISplitViewControllerAutomaticDimension
    var maximumPrimaryColumnWidth: CGFloat = -3.40282347e38
    var minimumPrimaryColumnWidth: CGFloat = -3.40282347e38
    var presentsWithGesture = true
    var displayModeButtonItem: UIBarButtonItem?
    var collapsed = false
    var collapseScheduled = false
}

@ObjCClass("UISplitViewController")
open class UISplitViewController: UIViewController {
    static let splitStates = StateTable<SplitViewState>()
    var split: SplitViewState { UISplitViewController.splitStates[objcObject] }

    @ObjCMethod("initWithNibName:bundle:")
    override func initialize(nibName: String?, bundle: NSObject?) -> Self {
        _ = super.initialize(nibName: nibName, bundle: bundle)
        _ = loadedView
        return self
    }

    /// From a storyboard: the primary and secondary controllers.
    @ObjCMethod("initWithCoder:")
    override func initialize(coder: NSObject) -> Self {
        _ = super.initialize(coder: coder)
        _ = loadedView
        adopt(Coder(coder: coder).array("UIViewControllers").compactMap { $0.as(UIViewController.self) })
        return self
    }

    @ObjCMethod("dealloc")
    override func dealloc() {
        UISplitViewController.splitStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCMethod("loadView")
    override func loadView() {
        let view = UILayoutContainerView.objCClass.object.allocated().initializeView(frame: Screen.bounds).unsafeCast(to: UIView.self)
        view.setAutoresizingMask(18)
        setView(view)
    }

    // MARK: The controllers

    @ObjCMethod("viewControllers") func viewControllers() -> NSObject { NSMutableArray.of(split.viewControllers) }

    @ObjCMethod("setViewControllers:")
    func setViewControllers(_ controllers: NSArray?) {
        for controller in split.viewControllers {
            controller.state.view?.removeFromSuperview()
            controller.removeFromParent()
        }
        adopt(controllers?.elements.compactMap { $0.as(UIViewController.self) } ?? [])
    }

    /// Makes the controllers children, the primary's view the view's
    /// content, and schedules collapsing the secondary.
    private func adopt(_ controllers: [UIViewController]) {
        split.viewControllers = controllers
        split.collapsed = false
        for controller in controllers {
            controller.sendWillMove(toParent: self)
            state.children.append(controller)
            controller.state.parent = objcObject
            controller.sendDidMove(toParent: self)
        }
        if let primary = controllers.first, let view = state.view {
            let primaryView = primary.loadedView
            primaryView.sendSetFrame(view.state.bounds)
            primaryView.setAutoresizingMask(18)
            view.addSubview(primaryView)
        }
        scheduleCollapse()
    }

    private var primary: UIViewController? { split.viewControllers.first }
    private var primaryNavigation: UINavigationController? { primary?.as(UINavigationController.self) }

    private func scheduleCollapse() {
        guard !split.collapseScheduled, split.viewControllers.count > 1 else { return }
        split.collapseScheduled = true
        Updates.transition { [self] in
            split.collapseScheduled = false
            collapse()
        }
    }

    /// Collapses the secondary onto the primary: the delegate's choice, or
    /// the secondary's controllers pushed onto the primary navigation
    /// controller.
    private func collapse() {
        guard !split.collapsed, split.viewControllers.count > 1, let primary else { return }
        split.collapsed = true
        let secondary = split.viewControllers[1]
        if let delegate = split.delegate.map({ NSObject($0) }),
           delegate.responds(to: "splitViewController:collapseSecondaryViewController:ontoPrimaryViewController:"),
           delegate.sendSplitViewController(self, collapseSecondary: secondary, ontoPrimary: primary) {
            return
        }
        push(secondary, animated: false)
    }

    /// Pushes a controller onto the primary navigation controller: a
    /// navigation controller's own stack, taken from it.
    private func push(_ controller: UIViewController, animated: Bool) {
        guard let navigation = primaryNavigation else { return }
        if let nested = controller.as(UINavigationController.self) {
            let controllers = nested.navigation.viewControllers
            nested.navigation.viewControllers = []
            for child in controllers {
                nested.state.children.removeAll { $0.objcObject == child.objcObject }
                child.state.parent = nil
                navigation.push(child, animated: animated && child.objcObject == controllers.last?.objcObject)
            }
        } else {
            navigation.push(controller, animated: animated)
        }
    }

    // MARK: Showing

    @ObjCMethod("showViewController:sender:")
    override func show(_ controller: UIViewController, sender: NSObject?) {
        guard let primary else { return super.show(controller, sender: sender) }
        primary.show(controller, sender: sender)
    }

    /// The delegate's, or pushed onto the primary navigation controller.
    @ObjCMethod("showDetailViewController:sender:")
    override func showDetail(_ controller: UIViewController, sender: NSObject?) {
        if let delegate = split.delegate.map({ NSObject($0) }),
           delegate.responds(to: "splitViewController:showDetailViewController:sender:"),
           delegate.sendSplitViewController(self, showDetail: controller, sender: sender) {
            return
        }
        guard primaryNavigation != nil else { return super.showDetail(controller, sender: sender) }
        push(controller, animated: true)
    }

    // MARK: Properties

    @ObjCMethod("delegate") func delegate() -> NSObject? { split.delegate.map { NSObject($0) } }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { split.delegate = delegate?.objcObject }

    /// Always collapsed: an iPhone in portrait.
    @ObjCMethod("isCollapsed") func isCollapsed() -> Bool { true }
    @ObjCMethod("collapsed") func collapsed() -> Bool { true }

    /// UISplitViewControllerDisplayModeAutomatic (0); collapsed, the
    /// displayed mode is primary hidden (1).
    @ObjCMethod("preferredDisplayMode") func preferredDisplayMode() -> Int { split.preferredDisplayMode }
    @ObjCMethod("setPreferredDisplayMode:") func setPreferredDisplayMode(_ mode: Int) { split.preferredDisplayMode = mode }
    @ObjCMethod("displayMode") func displayMode() -> Int { 1 }

    @ObjCMethod("presentsWithGesture") func presentsWithGesture() -> Bool { split.presentsWithGesture }
    @ObjCMethod("setPresentsWithGesture:") func setPresentsWithGesture(_ presents: Bool) { split.presentsWithGesture = presents }

    @ObjCMethod("preferredPrimaryColumnWidthFraction")
    func preferredPrimaryColumnWidthFraction() -> CGFloat { split.preferredPrimaryColumnWidthFraction }
    @ObjCMethod("setPreferredPrimaryColumnWidthFraction:")
    func setPreferredPrimaryColumnWidthFraction(_ fraction: CGFloat) { split.preferredPrimaryColumnWidthFraction = fraction }
    @ObjCMethod("maximumPrimaryColumnWidth") func maximumPrimaryColumnWidth() -> CGFloat { split.maximumPrimaryColumnWidth }
    @ObjCMethod("setMaximumPrimaryColumnWidth:")
    func setMaximumPrimaryColumnWidth(_ width: CGFloat) { split.maximumPrimaryColumnWidth = width }
    @ObjCMethod("minimumPrimaryColumnWidth") func minimumPrimaryColumnWidth() -> CGFloat { split.minimumPrimaryColumnWidth }
    @ObjCMethod("setMinimumPrimaryColumnWidth:")
    func setMinimumPrimaryColumnWidth(_ width: CGFloat) { split.minimumPrimaryColumnWidth = width }
    /// Collapsed, the primary fills the screen.
    @ObjCMethod("primaryColumnWidth") func primaryColumnWidth() -> CGFloat { state.view?.state.bounds.width ?? Screen.bounds.width }

    /// The item that shows and hides the primary column, which a collapsed
    /// split view never shows: a plain item with no action.
    @ObjCMethod("displayModeButtonItem")
    func displayModeButtonItem() -> UIBarButtonItem {
        if let item = split.displayModeButtonItem { return item }
        let item = UIBarButtonItem.objCClass.object.allocated().initialized().unsafeCast(to: UIBarButtonItem.self)
        split.displayModeButtonItem = item
        return item
    }
}

/// UISplitViewControllerDelegate's messages.
extension NSObject {
    @ObjCMethod("splitViewController:collapseSecondaryViewController:ontoPrimaryViewController:")
    func sendSplitViewController(_ controller: UISplitViewController, collapseSecondary secondary: UIViewController,
                                 ontoPrimary primary: UIViewController) -> Bool

    @ObjCMethod("splitViewController:showDetailViewController:sender:")
    func sendSplitViewController(_ controller: UISplitViewController, showDetail detail: UIViewController, sender: NSObject?) -> Bool
}

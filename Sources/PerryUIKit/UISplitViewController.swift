import CPerryGeometry
import PerryObjCInterop

// UISplitViewController as an iPhone has it, collapsed: the primary
// controller fills the view, and the secondary is collapsed onto it in the
// first update pass, after the app has had the chance to set a delegate,
// unless the delegate takes care of it. Detail shown later is pushed onto
// the primary navigation controller, as UIKit does when collapsed.
//
// A column-style split view controller (iOS 14's double and triple column
// styles) keeps a controller for each column. Collapsed, they are one
// navigation stack, primary first: a column's controller is pushed when
// the column is shown and popped to when it is shown again, and the
// delegate picks the column on top when the split view first collapses.

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
    /// UISplitViewControllerStyle: unspecified 0, double column 1, triple
    /// column 2.
    var style = 0
    /// Column controllers by UISplitViewControllerColumn: primary 0,
    /// supplementary 1, secondary 2, compact 3.
    var columns: [Int: UIViewController] = [:]
    /// The navigation controller the columns are stacked in, collapsed.
    var stack: UINavigationController?
    var preferredSplitBehavior = 0
    var preferredSupplementaryColumnWidth: CGFloat = -3.40282347e38
    var minimumSupplementaryColumnWidth: CGFloat = -3.40282347e38
    var maximumSupplementaryColumnWidth: CGFloat = -3.40282347e38
    var showsSecondaryOnlyButton = false
    var primaryBackgroundStyle = 0
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
        let decoded = Coder(coder: coder)
        split.style = decoded.integer("UISplitViewControllerStyle")
        split.preferredDisplayMode = decoded.integer("UISplitViewControllerPreferredDisplayMode")
        split.preferredSplitBehavior = decoded.integer("UISplitViewControllerPreferredSplitBehavior")
        if split.style != 0 {
            // The columns' controllers, primary first, as the storyboard's
            // relationships list them.
            let controllers = decoded.array("UIChildViewControllers").compactMap { $0.as(UIViewController.self) }
            let order = split.style == 2 ? [0, 1, 2] : [0, 2]
            for (column, controller) in zip(order, controllers) { split.columns[column] = controller }
            state.children = []
            adoptColumns()
        } else {
            adopt(decoded.array("UIViewControllers").compactMap { $0.as(UIViewController.self) })
        }
        return self
    }

    @ObjCMethod("initWithStyle:")
    func initialize(style: Int) -> Self {
        _ = initialize(nibName: nil, bundle: nil)
        split.style = style
        return self
    }

    @ObjCMethod("style") func style() -> Int { split.style }

    // MARK: Columns

    /// The columns of the style, in the order they stack.
    private var columnOrder: [Int] { split.style == 2 ? [0, 1, 2] : [0, 2] }

    /// The column controller itself, not the navigation controller UIKit
    /// keeps it in.
    @ObjCMethod("viewControllerForColumn:")
    func viewController(forColumn column: Int) -> UIViewController? { split.columns[column] }

    @ObjCMethod("setViewController:forColumn:")
    func setViewController(_ controller: UIViewController?, forColumn column: Int) {
        if let old = split.columns[column], let stack = split.stack, stack.navigation.viewControllers.contains(where: { $0 === old }) {
            // Shown: what was above it goes, and the new one takes its place.
            let kept = stack.navigation.viewControllers.prefix { $0 !== old }
            stack.setViewControllers(NSMutableArray.of(Array(kept) + (controller.map { [$0] } ?? [])), animated: false)
        }
        split.columns[column] = controller
        if split.stack == nil, column == 0 { adoptColumns() }
    }

    /// The stack the columns are shown in: the primary's navigation
    /// controller, or one made for it, as the view's content.
    private func adoptColumns() {
        guard split.stack == nil, let primary = split.columns[0] else { return }
        let stack = primary.as(UINavigationController.self) ?? {
            let made = UINavigationController.objCClass.object.allocated().unsafeCast(to: UINavigationController.self)
            return made.initialize(rootViewController: primary).unsafeCast(to: UINavigationController.self)
        }()
        if stack !== primary { split.columns[0] = primary }
        split.stack = stack
        split.viewControllers = [stack]
        stack.sendWillMove(toParent: self)
        state.children.append(stack)
        stack.state.parent = objcObject
        stack.sendDidMove(toParent: self)
        if let view = state.view {
            let stackView = stack.loadedView
            stackView.sendSetFrame(view.state.bounds)
            stackView.setAutoresizingMask(18)
            view.addSubview(stackView)
        }
        // Collapsing, the delegate picks the column on top: the secondary,
        // unless it says otherwise.
        Updates.transition { [self] in
            var top = 2
            if let delegate = split.delegate.map({ NSObject($0) }),
               delegate.responds(to: "splitViewController:topColumnForCollapsingToProposedTopColumn:") {
                top = delegate.sendSplitViewController(self, topColumnForCollapsingToProposedTopColumn: 2)
            }
            showColumn(top, animated: false)
        }
    }

    /// Shows a column: collapsed, its controller on top of the stack, with
    /// the columns before it under it.
    @ObjCMethod("showColumn:")
    func showColumn(_ column: Int) { showColumn(column, animated: true) }

    func showColumn(_ column: Int, animated: Bool) {
        guard let stack = split.stack else { return }
        let order = columnOrder
        guard let index = order.firstIndex(of: column) else { return }
        let wanted = order[...index].compactMap { split.columns[$0] }.filter { $0 !== stack }
        let current = stack.navigation.viewControllers
        if let target = wanted.last, current.contains(where: { $0 === target }) {
            _ = stack.popTo(target, animated: animated)
            return
        }
        // The column controllers below it that aren't there yet, pushed in
        // order; anything the app pushed above an earlier column stays.
        var stackList = current
        for controller in wanted where !stackList.contains(where: { $0 === controller }) {
            stackList.append(controller)
        }
        if stackList.count == current.count + 1, let last = stackList.last {
            stack.push(last, animated: animated)
        } else {
            stack.setViewControllers(NSMutableArray.of(stackList), animated: false)
        }
    }

    /// Hides a column: collapsed, pops back to the column before it.
    @ObjCMethod("hideColumn:")
    func hideColumn(_ column: Int) {
        guard let stack = split.stack, let controller = split.columns[column],
              let index = stack.navigation.viewControllers.firstIndex(where: { $0 === controller }), index > 0 else { return }
        _ = stack.popTo(stack.navigation.viewControllers[index - 1], animated: true)
    }

    @ObjCMethod("preferredSplitBehavior") func preferredSplitBehavior() -> Int { split.preferredSplitBehavior }
    @ObjCMethod("setPreferredSplitBehavior:") func setPreferredSplitBehavior(_ value: Int) { split.preferredSplitBehavior = value }
    @ObjCMethod("splitBehavior") func splitBehavior() -> Int { split.preferredSplitBehavior == 0 ? 1 : split.preferredSplitBehavior }
    @ObjCMethod("preferredSupplementaryColumnWidth") func preferredSupplementaryColumnWidth() -> CGFloat { split.preferredSupplementaryColumnWidth }
    @ObjCMethod("setPreferredSupplementaryColumnWidth:")
    func setPreferredSupplementaryColumnWidth(_ value: CGFloat) { split.preferredSupplementaryColumnWidth = value }
    @ObjCMethod("minimumSupplementaryColumnWidth") func minimumSupplementaryColumnWidth() -> CGFloat { split.minimumSupplementaryColumnWidth }
    @ObjCMethod("setMinimumSupplementaryColumnWidth:")
    func setMinimumSupplementaryColumnWidth(_ value: CGFloat) { split.minimumSupplementaryColumnWidth = value }
    @ObjCMethod("maximumSupplementaryColumnWidth") func maximumSupplementaryColumnWidth() -> CGFloat { split.maximumSupplementaryColumnWidth }
    @ObjCMethod("setMaximumSupplementaryColumnWidth:")
    func setMaximumSupplementaryColumnWidth(_ value: CGFloat) { split.maximumSupplementaryColumnWidth = value }
    @ObjCMethod("supplementaryColumnWidth") func supplementaryColumnWidth() -> CGFloat { primaryColumnWidth() }
    @ObjCMethod("showsSecondaryOnlyButton") func showsSecondaryOnlyButton() -> Bool { split.showsSecondaryOnlyButton }
    @ObjCMethod("setShowsSecondaryOnlyButton:") func setShowsSecondaryOnlyButton(_ value: Bool) { split.showsSecondaryOnlyButton = value }
    @ObjCMethod("primaryBackgroundStyle") func primaryBackgroundStyle() -> Int { split.primaryBackgroundStyle }
    @ObjCMethod("setPrimaryBackgroundStyle:") func setPrimaryBackgroundStyle(_ value: Int) { split.primaryBackgroundStyle = value }
    @ObjCMethod("displayModeButtonVisibility") func displayModeButtonVisibility() -> Int { 0 }
    @ObjCMethod("setDisplayModeButtonVisibility:") func setDisplayModeButtonVisibility(_ value: Int) {}

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

    @ObjCMethod("splitViewController:topColumnForCollapsingToProposedTopColumn:")
    func sendSplitViewController(_ controller: UISplitViewController, topColumnForCollapsingToProposedTopColumn column: Int) -> Int
}

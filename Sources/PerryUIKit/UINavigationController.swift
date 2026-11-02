import CPerryGeometry
import PerryObjCInterop

// UINavigationController: a stack of view controllers, the top one's view
// shown below a navigation bar. Changes to the stack take effect at once;
// the controllers' views change places, with their appearance callbacks,
// in the next update pass, as on Darwin. Its view loads with it.

final class NavigationState: ObjectState {
    var viewControllers: [UIViewController] = []
    /// The controller whose view is shown, kept until another replaces it.
    var displayed: UIViewController?
    var navigationBar: UINavigationBar?
    var barHidden = false
    var toolbarHidden = true
    var delegate: UnsafeMutableRawPointer?
    var transitionScheduled = false
}

/// The navigation bar's height on an iPhone.
private let barHeight: CGFloat = 44

@ObjCClass("UINavigationController")
open class UINavigationController: UIViewController {
    static let navigationStates = StateTable<NavigationState>()
    var navigation: NavigationState { UINavigationController.navigationStates[objcObject] }

    @ObjCMethod("initWithNibName:bundle:")
    override func initialize(nibName: String?, bundle: NSObject?) -> Self {
        _ = super.initialize(nibName: nibName, bundle: bundle)
        _ = loadedView
        return self
    }

    @ObjCMethod("initWithRootViewController:")
    func initialize(rootViewController root: UIViewController) -> NSObject {
        let navigation = initializeViewController(nibName: nil, bundle: nil).unsafeCast(to: UINavigationController.self)
        navigation.push(root, animated: false)
        return navigation
    }

    @ObjCMethod("initWithNavigationBarClass:toolbarClass:")
    func initialize(navigationBarClass: ObjCClass?, toolbarClass: ObjCClass?) -> NSObject {
        initializeViewController(nibName: nil, bundle: nil)
    }

    @ObjCMethod("dealloc")
    override func dealloc() {
        UINavigationController.navigationStates.remove(objcObject)
        super.dealloc()
    }

    /// A container with the bar on top.
    @ObjCMethod("loadView")
    override func loadView() {
        let view = UILayoutContainerView.objCClass.object.allocated().initializeView(frame: Screen.bounds).unsafeCast(to: UIView.self)
        setView(view)
        view.addSubview(navigationBar())
    }

    @ObjCMethod("navigationBar")
    func navigationBar() -> UINavigationBar {
        if let bar = navigation.navigationBar { return bar }
        let bar = UINavigationBar.objCClass.object.allocated()
            .initializeView(frame: CGRect(x: 0, y: 0, width: Screen.bounds.width, height: barHeight)).unsafeCast(to: UINavigationBar.self)
        navigation.navigationBar = bar
        bar.barState.navigationController = objcObject
        return bar
    }

    @ObjCMethod("delegate") func delegate() -> NSObject? { navigation.delegate.map { NSObject($0) } }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { navigation.delegate = delegate?.objcObject }

    // MARK: The stack

    @ObjCMethod("viewControllers") func viewControllers() -> NSObject { NSMutableArray.of(navigation.viewControllers) }
    @ObjCMethod("topViewController") func topViewController() -> UIViewController? { navigation.viewControllers.last }

    /// The top controller, or what it presents.
    @ObjCMethod("visibleViewController")
    func visibleViewController() -> UIViewController? {
        guard let top = navigation.viewControllers.last else { return nil }
        return top.presentedViewController() ?? top
    }

    @ObjCMethod("pushViewController:animated:")
    func push(_ controller: UIViewController, animated: Bool) {
        guard !navigation.viewControllers.contains(where: { $0.objcObject == controller.objcObject }) else {
            uikitFatal("Pushing the same view controller instance more than once is not supported")
        }
        adopt(controller)
        navigation.viewControllers.append(controller)
        stackChanged(animated: animated)
    }

    @ObjCMethod("popViewControllerAnimated:")
    func pop(animated: Bool) -> UIViewController? {
        guard navigation.viewControllers.count > 1, let top = navigation.viewControllers.last else { return nil }
        release(top, now: false)
        navigation.viewControllers.removeLast()
        stackChanged(animated: animated)
        return top
    }

    @ObjCMethod("popToRootViewControllerAnimated:")
    func popToRoot(animated: Bool) -> NSObject? {
        guard let root = navigation.viewControllers.first else { return nil }
        return popTo(root, animated: animated)
    }

    @ObjCMethod("popToViewController:animated:")
    func popTo(_ controller: UIViewController, animated: Bool) -> NSObject? {
        guard let index = navigation.viewControllers.firstIndex(where: { $0.objcObject == controller.objcObject }) else { return nil }
        let popped = Array(navigation.viewControllers[(index + 1)...])
        guard !popped.isEmpty else { return NSMutableArray.of([]) }
        for (offset, removed) in popped.enumerated() { release(removed, now: offset < popped.count - 1) }
        navigation.viewControllers.removeLast(popped.count)
        stackChanged(animated: animated)
        return NSMutableArray.of(popped)
    }

    @ObjCMethod("setViewControllers:") func setViewControllers(_ controllers: NSArray) { setViewControllers(controllers, animated: false) }

    /// Controllers that leave are released, those that come are adopted;
    /// all but the new top finish moving at once.
    @ObjCMethod("setViewControllers:animated:")
    func setViewControllers(_ controllers: NSArray, animated: Bool) {
        let new = controllers.elements.map { $0.unsafeCast(to: UIViewController.self) }
        let old = navigation.viewControllers
        let oldTop = old.last
        for controller in old where !new.contains(where: { $0.objcObject == controller.objcObject }) {
            release(controller, now: controller.objcObject != oldTop?.objcObject || navigation.displayed?.objcObject != controller.objcObject)
        }
        for (index, controller) in new.enumerated() where !old.contains(where: { $0.objcObject == controller.objcObject }) {
            adopt(controller)
            if index < new.count - 1 {
                controller.sendDidMove(toParent: self)
                controller.state.movingToParent = false
            }
        }
        navigation.viewControllers = new
        stackChanged(animated: animated)
    }

    /// Makes `controller` a child, which finishes moving once it appears.
    private func adopt(_ controller: UIViewController) {
        controller.sendWillMove(toParent: self)
        state.children.append(controller)
        controller.state.parent = objcObject
    }

    /// Removes a child; one leaving the screen finishes moving once it has
    /// disappeared, others at once.
    private func release(_ controller: UIViewController, now: Bool) {
        controller.sendWillMove(toParent: nil)
        state.children.removeAll { $0.objcObject == controller.objcObject }
        controller.state.parent = nil
        if now {
            controller.sendDidMove(toParent: nil)
            controller.state.movingFromParent = false
        }
    }

    private func stackChanged(animated: Bool) {
        navigationBar().setItemsFromStack(navigation.viewControllers.map { $0.navigationItem() })
        scheduleTransition(animated: animated)
    }

    func scheduleTransition(animated: Bool) {
        guard !navigation.transitionScheduled else { return }
        navigation.transitionScheduled = true
        Updates.transition { [self] in
            navigation.transitionScheduled = false
            runTransition(animated: animated)
        }
    }

    /// Shows the top controller's view in place of the one shown, with
    /// appearance callbacks when the navigation controller is on screen.
    func runTransition(animated: Bool) {
        guard let view = state.view, let top = navigation.viewControllers.last else { return }
        let from = navigation.displayed
        guard from?.objcObject != top.objcObject else { return }
        let onScreen = view.windowObject != nil && (state.appearance == .appeared || state.appearance == .appearing)
        let delegate = navigation.delegate.map { NSObject($0) }
        let topView = top.loadedView
        if let delegate, delegate.responds(to: "navigationController:willShowViewController:animated:") {
            delegate.sendNavigationController(self, willShow: top, animated: animated)
        }
        if onScreen {
            _ = from?.beginAppearance(false, animated: animated)
            _ = top.beginAppearance(true, animated: animated)
        }
        topView.sendSetFrame(view.state.bounds)
        from?.state.view?.removeFromSuperview()
        view.insertSubview(topView, below: navigationBar())
        navigation.displayed = top
        layoutContent()
        if onScreen {
            from?.finishAppearance()
            top.finishAppearance()
        }
        if let delegate, delegate.responds(to: "navigationController:didShowViewController:animated:") {
            delegate.sendNavigationController(self, didShow: top, animated: animated)
        }
    }

    @ObjCMethod("viewWillLayoutSubviews")
    override func viewWillLayoutSubviews() { layoutContent() }

    /// The bar across the top of the safe area, the content filling the
    /// view beneath it.
    func layoutContent() {
        guard let view = state.view else { return }
        let bounds = view.state.bounds
        let bar = navigationBar()
        let top = view.windowObject != nil ? view.safeAreaInsets(ignoringController: true).top : 0
        bar.sendSetFrame(CGRect(x: 0, y: top, width: bounds.width, height: barHeight))
        if let displayed = navigation.displayed?.state.view {
            displayed.sendSetFrame(bounds)
        }
    }

    // MARK: Bars

    @ObjCMethod("isNavigationBarHidden") func isNavigationBarHidden() -> Bool { navigation.barHidden }
    @ObjCMethod("setNavigationBarHidden:") func setNavigationBarHidden(_ hidden: Bool) { setNavigationBarHidden(hidden, animated: false) }

    @ObjCMethod("setNavigationBarHidden:animated:")
    func setNavigationBarHidden(_ hidden: Bool, animated: Bool) {
        navigation.barHidden = hidden
        navigationBar().sendSetHidden(hidden)
        state.view?.setNeedsLayout()
    }

    @ObjCMethod("toolbar") func toolbar() -> NSObject? { nil }
    @ObjCMethod("isToolbarHidden") func isToolbarHidden() -> Bool { navigation.toolbarHidden }
    @ObjCMethod("setToolbarHidden:") func setToolbarHidden(_ hidden: Bool) { navigation.toolbarHidden = hidden }
    @ObjCMethod("setToolbarHidden:animated:") func setToolbarHidden(_ hidden: Bool, animated: Bool) { navigation.toolbarHidden = hidden }
    @ObjCMethod("hidesBarsOnSwipe") func hidesBarsOnSwipe() -> Bool { false }
    @ObjCMethod("setHidesBarsOnSwipe:") func setHidesBarsOnSwipe(_ hides: Bool) {}
    @ObjCMethod("interactivePopGestureRecognizer") func interactivePopGestureRecognizer() -> NSObject? { nil }

    /// Pushes, as -showViewController:sender: does in a navigation
    /// controller.
    @ObjCMethod("showViewController:sender:")
    override func show(_ controller: UIViewController, sender: NSObject?) { push(controller, animated: true) }

    /// The bar's back button: pops.
    func backTapped() { _ = pop(animated: true) }
}

/// The navigation controller's view.
@ObjCClass("UILayoutContainerView")
open class UILayoutContainerView: UIView {}

/// UINavigationControllerDelegate's messages.
extension NSObject {
    @ObjCMethod("navigationController:willShowViewController:animated:")
    func sendNavigationController(_ navigation: UINavigationController, willShow controller: UIViewController, animated: Bool)

    @ObjCMethod("navigationController:didShowViewController:animated:")
    func sendNavigationController(_ navigation: UINavigationController, didShow controller: UIViewController, animated: Bool)
}

// MARK: - UINavigationBar

final class NavigationBarState: ObjectState {
    var items: [UINavigationItem] = []
    /// The navigation controller that owns the bar; not retained.
    var navigationController: UnsafeMutableRawPointer?
    var delegate: UnsafeMutableRawPointer?
    var barStyle = 0
    var translucent = true
    var prefersLargeTitles = false
    var barTintColor: UIColor?
    var titleTextAttributes: NSObject?
    var largeTitleTextAttributes: NSObject?
    var standardAppearance: NSObject?
    var scrollEdgeAppearance: NSObject?
    var compactAppearance: NSObject?
    var shadowImage: NSObject?
}

@ObjCClass("UINavigationBar")
open class UINavigationBar: UIView {
    static let barStates = StateTable<NavigationBarState>()
    var barState: NavigationBarState { UINavigationBar.barStates[objcObject] }

    @ObjCMethod("dealloc")
    override func dealloc() {
        UINavigationBar.barStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCMethod("items") func items() -> NSObject? { barState.items.isEmpty ? nil : NSMutableArray.of(barState.items) }
    @ObjCMethod("setItems:") func setItems(_ items: NSArray?) { setItems(items, animated: false) }

    @ObjCMethod("setItems:animated:")
    func setItems(_ items: NSArray?, animated: Bool) {
        barState.items = items?.elements.map { $0.unsafeCast(to: UINavigationItem.self) } ?? []
        setNeedsDisplay()
    }

    func setItemsFromStack(_ items: [UINavigationItem]) {
        barState.items = items
        setNeedsDisplay()
    }

    @ObjCMethod("topItem") func topItem() -> UINavigationItem? { barState.items.last }

    @ObjCMethod("backItem")
    func backItem() -> UINavigationItem? { barState.items.count >= 2 ? barState.items[barState.items.count - 2] : nil }

    @ObjCMethod("pushNavigationItem:animated:")
    func push(_ item: UINavigationItem, animated: Bool) {
        barState.items.append(item)
        setNeedsDisplay()
    }

    @ObjCMethod("popNavigationItemAnimated:")
    func popItem(animated: Bool) -> UINavigationItem? {
        guard let item = barState.items.popLast() else { return nil }
        setNeedsDisplay()
        return item
    }

    @ObjCMethod("delegate") func delegate() -> NSObject? { barState.delegate.map { NSObject($0) } }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { barState.delegate = delegate?.objcObject }
    @ObjCMethod("barStyle") func barStyle() -> Int { barState.barStyle }
    @ObjCMethod("setBarStyle:") func setBarStyle(_ style: Int) { barState.barStyle = style }
    @ObjCMethod("isTranslucent") func isTranslucent() -> Bool { barState.translucent }
    @ObjCMethod("setTranslucent:") func setTranslucent(_ translucent: Bool) { barState.translucent = translucent }
    @ObjCMethod("prefersLargeTitles") func prefersLargeTitles() -> Bool { barState.prefersLargeTitles }
    @ObjCMethod("setPrefersLargeTitles:") func setPrefersLargeTitles(_ prefers: Bool) { barState.prefersLargeTitles = prefers }
    @ObjCMethod("barTintColor") func barTintColor() -> UIColor? { barState.barTintColor }
    @ObjCMethod("setBarTintColor:") func setBarTintColor(_ color: UIColor?) {
        barState.barTintColor = color
        setNeedsDisplay()
    }
    @ObjCMethod("titleTextAttributes") func titleTextAttributes() -> NSObject? { barState.titleTextAttributes }
    @ObjCMethod("setTitleTextAttributes:") func setTitleTextAttributes(_ attributes: NSObject?) { barState.titleTextAttributes = attributes }
    @ObjCMethod("largeTitleTextAttributes") func largeTitleTextAttributes() -> NSObject? { barState.largeTitleTextAttributes }
    @ObjCMethod("setLargeTitleTextAttributes:") func setLargeTitleTextAttributes(_ attributes: NSObject?) {
        barState.largeTitleTextAttributes = attributes
    }
    @ObjCMethod("standardAppearance") func standardAppearance() -> NSObject? { barState.standardAppearance }
    @ObjCMethod("setStandardAppearance:") func setStandardAppearance(_ appearance: NSObject?) { barState.standardAppearance = appearance }
    @ObjCMethod("scrollEdgeAppearance") func scrollEdgeAppearance() -> NSObject? { barState.scrollEdgeAppearance }
    @ObjCMethod("setScrollEdgeAppearance:") func setScrollEdgeAppearance(_ appearance: NSObject?) { barState.scrollEdgeAppearance = appearance }
    @ObjCMethod("compactAppearance") func compactAppearance() -> NSObject? { barState.compactAppearance }
    @ObjCMethod("setCompactAppearance:") func setCompactAppearance(_ appearance: NSObject?) { barState.compactAppearance = appearance }
    @ObjCMethod("shadowImage") func shadowImage() -> NSObject? { barState.shadowImage }
    @ObjCMethod("setShadowImage:") func setShadowImage(_ image: NSObject?) { barState.shadowImage = image }

    @ObjCMethod("setBackgroundImage:forBarMetrics:") func setBackgroundImage(_ image: NSObject?, for metrics: Int) {}
    @ObjCMethod("backgroundImageForBarMetrics:") func backgroundImage(for metrics: Int) -> NSObject? { nil }

    @ObjCMethod("sizeThatFits:")
    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: barHeight) }
}

// MARK: - UINavigationItem

final class NavigationItemState: ObjectState {
    var title: String?
    var titleView: UIView?
    var prompt: String?
    var backButtonTitle: String?
    var backBarButtonItem: UIBarButtonItem?
    var hidesBackButton = false
    var leftItems: [UIBarButtonItem] = []
    var rightItems: [UIBarButtonItem] = []
    var leftItemsSupplementBackButton = false
    var largeTitleDisplayMode = 0
    var searchController: NSObject?
    var hidesSearchBarWhenScrolling = true
    var standardAppearance: NSObject?
    var scrollEdgeAppearance: NSObject?
}

@ObjCClass("UINavigationItem")
open class UINavigationItem: NSObject {
    static let states = StateTable<NavigationItemState>()
    var state: NavigationItemState { UINavigationItem.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        UINavigationItem.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UINavigationItem.objCClass.pointer)
    }

    @ObjCMethod("init") func initialize() -> Self { self }

    @ObjCMethod("initWithTitle:")
    func initialize(title: String?) -> Self {
        state.title = title
        return self
    }

    @ObjCMethod("initWithCoder:") func initialize(coder: NSObject?) -> Self { self }

    @ObjCMethod("title") func title() -> String? { state.title }
    @ObjCMethod("setTitle:") func setTitle(_ title: String?) { state.title = title }
    @ObjCMethod("titleView") func titleView() -> UIView? { state.titleView }
    @ObjCMethod("setTitleView:") func setTitleView(_ view: UIView?) { state.titleView = view }
    @ObjCMethod("prompt") func prompt() -> String? { state.prompt }
    @ObjCMethod("setPrompt:") func setPrompt(_ prompt: String?) { state.prompt = prompt }
    @ObjCMethod("backButtonTitle") func backButtonTitle() -> String? { state.backButtonTitle }
    @ObjCMethod("setBackButtonTitle:") func setBackButtonTitle(_ title: String?) { state.backButtonTitle = title }
    @ObjCMethod("backBarButtonItem") func backBarButtonItem() -> UIBarButtonItem? { state.backBarButtonItem }
    @ObjCMethod("setBackBarButtonItem:") func setBackBarButtonItem(_ item: UIBarButtonItem?) { state.backBarButtonItem = item }
    @ObjCMethod("hidesBackButton") func hidesBackButton() -> Bool { state.hidesBackButton }
    @ObjCMethod("setHidesBackButton:") func setHidesBackButton(_ hides: Bool) { state.hidesBackButton = hides }
    @ObjCMethod("setHidesBackButton:animated:") func setHidesBackButton(_ hides: Bool, animated: Bool) { state.hidesBackButton = hides }
    @ObjCMethod("leftItemsSupplementBackButton") func leftItemsSupplementBackButton() -> Bool { state.leftItemsSupplementBackButton }
    @ObjCMethod("setLeftItemsSupplementBackButton:") func setLeftItemsSupplementBackButton(_ supplements: Bool) {
        state.leftItemsSupplementBackButton = supplements
    }
    @ObjCMethod("largeTitleDisplayMode") func largeTitleDisplayMode() -> Int { state.largeTitleDisplayMode }
    @ObjCMethod("setLargeTitleDisplayMode:") func setLargeTitleDisplayMode(_ mode: Int) { state.largeTitleDisplayMode = mode }
    @ObjCMethod("searchController") func searchController() -> NSObject? { state.searchController }
    @ObjCMethod("setSearchController:") func setSearchController(_ controller: NSObject?) { state.searchController = controller }
    @ObjCMethod("hidesSearchBarWhenScrolling") func hidesSearchBarWhenScrolling() -> Bool { state.hidesSearchBarWhenScrolling }
    @ObjCMethod("setHidesSearchBarWhenScrolling:") func setHidesSearchBarWhenScrolling(_ hides: Bool) { state.hidesSearchBarWhenScrolling = hides }
    @ObjCMethod("standardAppearance") func standardAppearance() -> NSObject? { state.standardAppearance }
    @ObjCMethod("setStandardAppearance:") func setStandardAppearance(_ appearance: NSObject?) { state.standardAppearance = appearance }
    @ObjCMethod("scrollEdgeAppearance") func scrollEdgeAppearance() -> NSObject? { state.scrollEdgeAppearance }
    @ObjCMethod("setScrollEdgeAppearance:") func setScrollEdgeAppearance(_ appearance: NSObject?) { state.scrollEdgeAppearance = appearance }

    @ObjCMethod("leftBarButtonItem") func leftBarButtonItem() -> UIBarButtonItem? { state.leftItems.first }
    @ObjCMethod("setLeftBarButtonItem:") func setLeftBarButtonItem(_ item: UIBarButtonItem?) { state.leftItems = item.map { [$0] } ?? [] }
    @ObjCMethod("setLeftBarButtonItem:animated:") func setLeftBarButtonItem(_ item: UIBarButtonItem?, animated: Bool) { setLeftBarButtonItem(item) }
    @ObjCMethod("rightBarButtonItem") func rightBarButtonItem() -> UIBarButtonItem? { state.rightItems.first }
    @ObjCMethod("setRightBarButtonItem:") func setRightBarButtonItem(_ item: UIBarButtonItem?) { state.rightItems = item.map { [$0] } ?? [] }
    @ObjCMethod("setRightBarButtonItem:animated:") func setRightBarButtonItem(_ item: UIBarButtonItem?, animated: Bool) { setRightBarButtonItem(item) }

    @ObjCMethod("leftBarButtonItems")
    func leftBarButtonItems() -> NSObject? { state.leftItems.isEmpty ? nil : NSMutableArray.of(state.leftItems) }

    @ObjCMethod("setLeftBarButtonItems:")
    func setLeftBarButtonItems(_ items: NSArray?) { state.leftItems = items?.elements.map { $0.unsafeCast(to: UIBarButtonItem.self) } ?? [] }

    @ObjCMethod("setLeftBarButtonItems:animated:")
    func setLeftBarButtonItems(_ items: NSArray?, animated: Bool) { setLeftBarButtonItems(items) }

    @ObjCMethod("rightBarButtonItems")
    func rightBarButtonItems() -> NSObject? { state.rightItems.isEmpty ? nil : NSMutableArray.of(state.rightItems) }

    @ObjCMethod("setRightBarButtonItems:")
    func setRightBarButtonItems(_ items: NSArray?) { state.rightItems = items?.elements.map { $0.unsafeCast(to: UIBarButtonItem.self) } ?? [] }

    @ObjCMethod("setRightBarButtonItems:animated:")
    func setRightBarButtonItems(_ items: NSArray?, animated: Bool) { setRightBarButtonItems(items) }
}

extension NSObject {
    @ObjCMethod("initWithTitle:") func initializeNavigationItem(title: String?) -> NSObject
}

// MARK: - UIBarButtonItem

final class BarItemState: ObjectState {
    var title: String?
    var image: UIImage?
    var enabled = true
    var tag = 0
    /// UIBarButtonItemStyle: plain 0, done 2.
    var style = 0
    /// UIBarButtonSystemItem, or -1.
    var systemItem = -1
    /// Not retained, as UIKit's targets.
    var target: UnsafeMutableRawPointer?
    var action: UnsafeRawPointer?
    var customView: UIView?
    var width: CGFloat = 0
    var tintColor: UIColor?
    var menu: NSObject?
    var primaryAction: NSObject?
}

@ObjCClass("UIBarItem")
open class UIBarItem: NSObject {
    static let states = StateTable<BarItemState>()
    var state: BarItemState { UIBarItem.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        UIBarItem.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIBarItem.objCClass.pointer)
    }

    @ObjCMethod("title") func title() -> String? { state.title }
    @ObjCMethod("setTitle:") func setTitle(_ title: String?) { state.title = title }
    @ObjCMethod("image") func image() -> UIImage? { state.image }
    @ObjCMethod("setImage:") func setImage(_ image: UIImage?) { state.image = image }
    @ObjCMethod("isEnabled") func isEnabled() -> Bool { state.enabled }
    @ObjCMethod("setEnabled:") func setEnabled(_ enabled: Bool) { state.enabled = enabled }
    @ObjCMethod("tag") func tag() -> Int { state.tag }
    @ObjCMethod("setTag:") func setTag(_ tag: Int) { state.tag = tag }
    @ObjCMethod("setTitleTextAttributes:forState:") func setTitleTextAttributes(_ attributes: NSObject?, for controlState: UInt) {}
    @ObjCMethod("titleTextAttributesForState:") func titleTextAttributes(for controlState: UInt) -> NSObject? { nil }
}

@ObjCClass("UIBarButtonItem")
open class UIBarButtonItem: UIBarItem {
    /// A new item for a system item: Done and Save are in the done style.
    static func make(systemItem: Int, target: NSObject?, action: UnsafeRawPointer?) -> UIBarButtonItem {
        let item = objCClass.object.allocated().unsafeCast(to: UIBarButtonItem.self)
        item.configure(systemItem: systemItem, target: target, action: action)
        return item
    }

    private func configure(systemItem: Int, target: NSObject?, action: UnsafeRawPointer?) {
        state.systemItem = systemItem
        state.style = systemItem == 0 || systemItem == 3 ? 2 : 0
        state.target = target?.objcObject
        state.action = action
    }

    @ObjCMethod("init") func initialize() -> Self { self }

    @ObjCMethod("initWithTitle:style:target:action:")
    func initialize(title: String?, style: Int, target: NSObject?, action: ObjCSelector?) -> Self {
        (state.title, state.style, state.target, state.action) = (title, style, target?.objcObject, action?.pointer)
        return self
    }

    @ObjCMethod("initWithImage:style:target:action:")
    func initialize(image: UIImage?, style: Int, target: NSObject?, action: ObjCSelector?) -> Self {
        (state.image, state.style, state.target, state.action) = (image, style, target?.objcObject, action?.pointer)
        return self
    }

    @ObjCMethod("initWithBarButtonSystemItem:target:action:")
    func initialize(systemItem: Int, target: NSObject?, action: ObjCSelector?) -> Self {
        configure(systemItem: systemItem, target: target, action: action?.pointer)
        return self
    }

    @ObjCMethod("initWithCustomView:")
    func initialize(customView: UIView?) -> Self {
        state.customView = customView
        return self
    }

    @ObjCMethod("initWithTitle:menu:")
    func initialize(title: String?, menu: NSObject?) -> Self {
        (state.title, state.menu) = (title, menu)
        return self
    }

    @ObjCMethod("initWithImage:menu:")
    func initialize(image: UIImage?, menu: NSObject?) -> Self {
        (state.image, state.menu) = (image, menu)
        return self
    }

    @ObjCMethod("initWithPrimaryAction:")
    func initialize(primaryAction: NSObject?) -> Self {
        state.primaryAction = primaryAction
        return self
    }

    @ObjCMethod("style") func style() -> Int { state.style }
    @ObjCMethod("setStyle:") func setStyle(_ style: Int) { state.style = style }
    @ObjCMethod("target") func target() -> NSObject? { state.target.map { NSObject($0) } }
    @ObjCMethod("setTarget:") func setTarget(_ target: NSObject?) { state.target = target?.objcObject }
    @ObjCMethod("action") func action() -> ObjCSelector? { state.action.map(ObjCSelector.init) }
    @ObjCMethod("setAction:") func setAction(_ action: ObjCSelector?) { state.action = action?.pointer }
    @ObjCMethod("customView") func customView() -> UIView? { state.customView }
    @ObjCMethod("setCustomView:") func setCustomView(_ view: UIView?) { state.customView = view }
    @ObjCMethod("width") func width() -> CGFloat { state.width }
    @ObjCMethod("setWidth:") func setWidth(_ width: CGFloat) { state.width = width }
    @ObjCMethod("tintColor") func tintColor() -> UIColor? { state.tintColor }
    @ObjCMethod("setTintColor:") func setTintColor(_ color: UIColor?) { state.tintColor = color }
    @ObjCMethod("menu") func menu() -> NSObject? { state.menu }
    @ObjCMethod("setMenu:") func setMenu(_ menu: NSObject?) { state.menu = menu }
    @ObjCMethod("isHidden") func isHidden() -> Bool { false }
    @ObjCMethod("setHidden:") func setHidden(_ hidden: Bool) {}
}

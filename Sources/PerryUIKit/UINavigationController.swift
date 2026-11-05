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
    /// Whether a transition's views are sliding.
    var animating = false
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

    /// From a storyboard: the controller's own properties, then its
    /// stack, adopted as -setViewControllers: does.
    @ObjCMethod("initWithCoder:")
    override func initialize(coder: NSObject) -> Self {
        _ = super.initialize(coder: coder)
        _ = loadedView
        let decoded = Coder(coder: coder)
        if let archived = decoded.object("UINavigationBar")?.as(UINavigationBar.self) {
            let bar = navigationBar()
            bar.barState.barStyle = archived.barState.barStyle
            bar.barState.translucent = archived.barState.translucent
            bar.barState.barTintColor = archived.barState.barTintColor
        }
        let controllers = decoded.array("UIViewControllers").compactMap { $0.as(UIViewController.self) }
        for (index, controller) in controllers.enumerated() {
            controller.sendWillMove(toParent: self)
            state.children.append(controller)
            controller.state.parent = objcObject
            if index < controllers.count - 1 {
                controller.sendDidMove(toParent: self)
                controller.state.movingToParent = false
            }
        }
        navigation.viewControllers = controllers
        navigationBar().setItemsFromStack(controllers.map { $0.navigationItem() })
        if decoded.bool("UINavigationBarHidden") { setNavigationBarHidden(true, animated: false) }
        return self
    }

    /// Sets the controller up itself, as Darwin's does, rather than send
    /// -initWithNibName:bundle:: a Swift subclass with initializers of its
    /// own doesn't inherit that one, and traps when it is sent.
    @ObjCMethod("initWithRootViewController:")
    func initialize(rootViewController root: UIViewController) -> NSObject {
        let navigation = initialize(nibName: nil, bundle: nil)
        navigation.push(root, animated: false)
        return navigation
    }

    @ObjCMethod("initWithNavigationBarClass:toolbarClass:")
    func initialize(navigationBarClass: ObjCClass?, toolbarClass: ObjCClass?) -> NSObject {
        initialize(nibName: nil, bundle: nil)
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
        view.setAutoresizingMask(18)
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
        guard !navigation.animating, let view = state.view, let top = navigation.viewControllers.last else { return }
        let from = navigation.displayed
        guard from?.objcObject != top.objcObject else { return }
        let onScreen = view.windowObject != nil && (state.appearance == .appeared || state.appearance == .appearing)
        let delegate = navigation.delegate.map { NSObject($0) }
        let topView = top.loadedView
        let fromView = from?.state.view
        // Whether the views slide: asked for, on screen, from another view,
        // with a live view to show it. The callbacks are told the same.
        let animated = animated && onScreen && fromView != nil && Animations.live
        if let delegate, delegate.responds(to: "navigationController:willShowViewController:animated:") {
            delegate.sendNavigationController(self, willShow: top, animated: animated)
        }
        if onScreen {
            _ = from?.beginAppearance(false, animated: animated)
            _ = top.beginAppearance(true, animated: animated)
        }
        let bounds = contentFrame(for: top), fromBounds = contentFrame(for: from)
        topView.sendSetFrame(bounds)
        // A push brings the new view in over the old; a pop uncovers the
        // one beneath.
        let pushing = from.map { old in !navigation.viewControllers.contains { $0.objcObject == old.objcObject } } == false
        if pushing || fromView == nil {
            view.insertSubview(topView, below: navigationBar())
        } else {
            view.insertSubview(topView, below: fromView)
        }
        navigation.displayed = top
        layoutContent()

        let finish = { [self] in
            fromView?.removeFromSuperview()
            fromView?.sendSetFrame(fromBounds)
            topView.sendSetFrame(bounds)
            navigation.animating = false
            if onScreen {
                from?.finishAppearance()
                top.finishAppearance()
            }
            if let delegate, delegate.responds(to: "navigationController:didShowViewController:animated:") {
                delegate.sendNavigationController(self, didShow: top, animated: animated)
            }
            // A change to the stack while sliding shows once it is over.
            if navigation.viewControllers.last?.objcObject != top.objcObject { scheduleTransition(animated: false) }
        }
        guard animated, let fromView else {
            finish()
            return
        }
        // The new view slides in from the trailing edge as the old one
        // moves a third of the way out, or the reverse for a pop.
        navigation.animating = true
        let width = bounds.width
        let (fromStart, fromEnd, topStart): (CGFloat, CGFloat, CGFloat) = pushing ? (0, -width / 3, width) : (0, width, -width / 3)
        Animations.run(duration: 0.35, { progress in
            fromView.sendSetFrame(fromBounds.offsetBy(x: fromStart + (fromEnd - fromStart) * progress))
            topView.sendSetFrame(bounds.offsetBy(x: topStart * (1 - progress)))
        }, completion: finish)
    }

    @ObjCMethod("viewWillLayoutSubviews")
    override func viewWillLayoutSubviews() { layoutContent() }

    /// Where a child's view goes: the whole view, under the bar, unless
    /// the bar is opaque and the child does not extend under opaque bars,
    /// or does not extend under the top bar at all; then below the bar.
    func contentFrame(for controller: UIViewController?) -> CGRect {
        guard let view = state.view else { return .zero }
        let bounds = view.state.bounds
        let bar = navigationBar()
        guard let controller, !navigation.barHidden, !bar.state.hidden else { return bounds }
        let extends = controller.state.edgesForExtendedLayout & 1 != 0
            && (bar.barState.translucent || controller.state.extendedLayoutIncludesOpaqueBars)
        guard !extends else { return bounds }
        let top = min(bar.state.frame.maxY, bounds.maxY)
        return CGRect(x: bounds.minX, y: top, width: bounds.width, height: bounds.maxY - top)
    }

    /// The bar across the top of the safe area, the content filling the
    /// view beneath it.
    func layoutContent() {
        guard let view = state.view else { return }
        let bounds = view.state.bounds
        let bar = navigationBar()
        let top = view.windowObject != nil ? view.safeAreaInsets(ignoringController: true).top : 0
        bar.sendSetFrame(CGRect(x: 0, y: top, width: bounds.width, height: barHeight))
        bar.extendBackground(above: top)
        if let displayed = navigation.displayed, let displayedView = displayed.state.view, !navigation.animating {
            displayedView.sendSetFrame(contentFrame(for: displayed))
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
    /// What the bar last drew, to tell when its items have changed.
    var drawn = ""
    /// The bar's background above it, behind the status bar.
    var extensionView: UIView?
}

@ObjCClass("UINavigationBar")
open class UINavigationBar: UIView {
    static let barStates = StateTable<NavigationBarState>()
    var barState: NavigationBarState { UINavigationBar.barStates[objcObject] }

    /// From a storyboard. _UIBarTranslucence: default 0, translucent 1, opaque 2.
    @ObjCMethod("initWithCoder:")
    override func initialize(coder: NSObject) -> Self {
        _ = super.initialize(coder: coder)
        let decoded = Coder(coder: coder)
        barState.barStyle = decoded.integer("UIBarStyle")
        barState.translucent = decoded.integer("UIBarTranslucence") != 2
        barState.barTintColor = decoded.object("UIBarTintColor")?.as(UIColor.self)
        return self
    }

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
        barState.extensionView?.setBackgroundColor(backgroundColor)
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

    /// Where the bar's buttons go: the back button at the leading edge,
    /// then the left items, the right items from the trailing edge.
    struct Buttons {
        var back: (title: String, frame: CGRect)?
        var left: [(item: UIBarButtonItem, frame: CGRect)] = []
        var right: [(item: UIBarButtonItem, frame: CGRect)] = []
    }

    func buttons() -> Buttons {
        var buttons = Buttons()
        let bounds = state.bounds
        let font = UIFont.systemFont(size: 17), bold = UIFont.boldSystemFont(size: 17)
        guard let top = barState.items.last else { return buttons }
        var left: CGFloat = 16
        if let back = backItem(), !top.state.hidesBackButton {
            let title = "\u{2039} " + (back.state.backButtonTitle ?? back.state.title ?? "Back")
            let width = Text.size(title, font: font).width
            buttons.back = (title, CGRect(x: 8, y: 0, width: width, height: bounds.height))
            left = 8 + width + 16
        }
        for item in top.state.leftItems {
            let width = Text.size(item.displayTitle, font: font).width
            buttons.left.append((item, CGRect(x: left, y: 0, width: width, height: bounds.height)))
            left += width + 16
        }
        var right = bounds.width - 16
        for item in top.state.rightItems {
            let width = Text.size(item.displayTitle, font: item.state.style == 2 ? bold : font).width
            right -= width
            buttons.right.append((item, CGRect(x: right, y: 0, width: width, height: bounds.height)))
            right -= 16
        }
        return buttons
    }

    /// A light background with a hairline below; the top item's title
    /// centered, the back button and the items' titles in the tint color.
    @ObjCMethod("drawRect:")
    override func draw(_ rect: CGRect) {
        guard let context = Graphics.current else { return }
        let bounds = state.bounds
        // The colors own their CGColors, so they stay alive while used.
        let background = backgroundColor, separator = UIColor.separator()
        withExtendedLifetime((background, separator)) {
            CG.setFillColorWithColor(context, background.state.makeCGColor())
            CG.fillRect(context, bounds)
            // A shadow image replaces the hairline; Perry draws images in
            // its place as nothing.
            if barState.shadowImage == nil {
                CG.setFillColorWithColor(context, separator.state.makeCGColor())
                CG.fillRect(context, CGRect(x: 0, y: bounds.maxY - Screen.pixel, width: bounds.width, height: Screen.pixel))
            }
        }
        let tint = tintColor()
        let font = UIFont.systemFont(size: 17), bold = UIFont.boldSystemFont(size: 17)
        func middle(_ font: UIFont) -> CGFloat { bounds.midY - Text.size("A", font: font).height / 2 }
        let buttons = buttons()
        if let back = buttons.back { Text.draw(back.title, at: CGPoint(x: back.frame.minX, y: middle(font)), font: font, color: tint) }
        for (item, frame) in buttons.left + buttons.right {
            let itemFont = item.state.style == 2 ? bold : font
            Text.draw(item.displayTitle, at: CGPoint(x: frame.minX, y: middle(itemFont)), font: itemFont,
                      color: item.state.enabled ? (item.state.tintColor ?? tint) : UIColor.systemGray())
        }
        if let title = barState.items.last?.state.title {
            let width = Text.size(title, font: bold).width
            Text.draw(title, at: CGPoint(x: bounds.midX - width / 2, y: middle(bold)), font: bold, color: UIColor.label())
        }
    }

    var backgroundColor: UIColor { barState.barTintColor ?? UIColor.gray(0.97) }

    /// Continues the bar's background `height` points up, to the top of
    /// the screen, as UIKit's bars do behind the status bar.
    func extendBackground(above height: CGFloat) {
        let view: UIView
        if let existing = barState.extensionView {
            view = existing
        } else {
            view = UIView.objCClass.object.allocated().initializeView(frame: .zero).unsafeCast(to: UIView.self)
            view.setUserInteractionEnabled(false)
            barState.extensionView = view
            addSubview(view)
        }
        view.setBackgroundColor(backgroundColor)
        view.sendSetFrame(CGRect(x: 0, y: -height, width: state.bounds.width, height: height))
    }

    /// QuartzCore asks before drawing: what the bar shows changes without
    /// its saying so.
    @ObjCMethod("_perryLayerContentChanged:")
    func layerContentChanged(_ layer: NSObject) -> Bool { contentChanged() }

    /// Whether what the bar shows has changed since it last drew.
    func contentChanged() -> Bool {
        let items = barState.items.suffix(2)
        var content = "\(state.bounds.width) \(barState.barTintColor.map { $0.description() } ?? "")"
        for item in items {
            content += "|\(item.state.title ?? "")|\(item.state.backButtonTitle ?? "")|\(item.state.hidesBackButton)"
            for button in item.state.leftItems + item.state.rightItems {
                content += "|\(button.displayTitle)|\(button.state.style)|\(button.state.enabled)"
            }
        }
        guard content != barState.drawn else { return false }
        barState.drawn = content
        return true
    }

    /// A tap: the back button pops, an item sends its action.
    func tap(at point: CGPoint) {
        let buttons = buttons()
        let slop: CGFloat = 8
        func hit(_ frame: CGRect) -> Bool {
            point.x >= frame.minX - slop && point.x <= frame.maxX + slop && point.y >= frame.minY && point.y <= frame.maxY
        }
        if let back = buttons.back, hit(back.frame) {
            if let navigation = barState.navigationController {
                _ = UINavigationController(objcObject: navigation, ownership: .retain).pop(animated: true)
            } else if let item = topItem() {
                // A bar on its own pops its top item, as its delegate allows.
                let delegate = delegate()
                if let delegate, delegate.responds(to: "navigationBar:shouldPopItem:"),
                   !delegate.sendNavigationBar(self, shouldPop: item) { return }
                _ = popItem(animated: true)
                if let delegate, delegate.responds(to: "navigationBar:didPopItem:") { delegate.sendNavigationBar(self, didPop: item) }
            }
            return
        }
        for (item, frame) in buttons.left + buttons.right where hit(frame) && item.state.enabled {
            item.sendAction(from: self)
            return
        }
    }
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

    @ObjCMethod("initWithCoder:")
    func initialize(coder: NSObject) -> Self {
        let decoded = Coder(coder: coder)
        let state = state
        state.title = decoded.string("UITitle")
        state.titleView = decoded.object("UITitleView")?.as(UIView.self)
        state.prompt = decoded.string("UIPrompt")
        state.backButtonTitle = decoded.string("UIBackButtonTitle")
        state.backBarButtonItem = decoded.object("UIBackBarButtonItem")?.as(UIBarButtonItem.self)
        state.hidesBackButton = decoded.bool("UIHidesBackButton")
        func items(_ many: String, _ one: String) -> [UIBarButtonItem] {
            let list = decoded.array(many).compactMap { $0.as(UIBarButtonItem.self) }
            return list.isEmpty ? (decoded.object(one)?.as(UIBarButtonItem.self).map { [$0] } ?? []) : list
        }
        state.leftItems = items("UILeftBarButtonItems", "UILeftBarButtonItem")
        state.rightItems = items("UIRightBarButtonItems", "UIRightBarButtonItem")
        return self
    }

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

    /// The title shown for the item, or its system item's.
    var displayTitle: String {
        if let title = state.title { return title }
        let system = ["Done", "Cancel", "Edit", "Save", "+", "", "", "Compose", "Reply", "Action", "Organize", "Bookmarks",
                      "Search", "Refresh", "Stop", "Camera", "Trash", "Play", "Pause", "Rewind", "Fast Forward", "Undo", "Redo"]
        return system.indices.contains(state.systemItem) ? system[state.systemItem] : ""
    }

    @ObjCMethod("init") func initialize() -> Self { self }

    /// From a nib: the title or image, style, system item and tag.
    @ObjCMethod("initWithCoder:")
    func initialize(coder: NSObject) -> Self {
        let decoded = Coder(coder: coder)
        let state = state
        state.title = decoded.string("UITitle")
        state.image = decoded.object("UIImage")?.as(UIImage.self)
        state.style = decoded.integer("UIStyle")
        state.enabled = decoded.has("UIEnabled") ? decoded.bool("UIEnabled") : true
        state.tag = decoded.integer("UITag")
        state.customView = decoded.object("UICustomView")?.as(UIView.self)
        state.width = decoded.double("UIWidth")
        if decoded.bool("UIIsSystemItem") {
            state.systemItem = decoded.integer("UISystemItem")
            if state.systemItem == 0 || state.systemItem == 3 { state.style = 2 }
        }
        return self
    }

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

    /// Sends the action to the target, or without one up the responder
    /// chain from `responder`, to the first that handles it.
    func sendAction(startingAt responder: NSObject) {
        guard let action = state.action else { return }
        var receiver: NSObject? = state.target.map { NSObject($0) }
        if receiver == nil {
            var candidate: NSObject? = responder
            let name = String(cString: action.assumingMemoryBound(to: CChar.self))
            while let current = candidate, !current.responds(to: name) { candidate = current.sendNextResponder() }
            receiver = candidate
        }
        guard let receiver else { return }
        typealias Send = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Void
        unsafeBitCast(ObjCRuntime.msgSend, to: Send.self)(receiver.objcObject, action, objcObject)
    }

    /// Sends the action to the target, or without one up the responder
    /// chain from the top view controller, to the first that handles it.
    func sendAction(from bar: UINavigationBar) {
        guard let action = state.action else { return }
        var receiver: NSObject? = state.target.map { NSObject($0) }
        if receiver == nil, let navigation = bar.barState.navigationController {
            var responder: NSObject? = UINavigationController(objcObject: navigation, ownership: .retain).topViewController()
            let name = String(cString: action.assumingMemoryBound(to: CChar.self))
            while let candidate = responder, !candidate.responds(to: name) { responder = candidate.sendNextResponder() }
            receiver = responder
        }
        guard let receiver else { return }
        typealias Send = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Void
        unsafeBitCast(ObjCRuntime.msgSend, to: Send.self)(receiver.objcObject, action, objcObject)
    }
}

/// UINavigationBarDelegate's messages, for a bar without a navigation
/// controller.
extension NSObject {
    @ObjCMethod("navigationBar:shouldPopItem:") func sendNavigationBar(_ bar: UINavigationBar, shouldPop item: UINavigationItem) -> Bool
    @ObjCMethod("navigationBar:didPopItem:") func sendNavigationBar(_ bar: UINavigationBar, didPop item: UINavigationItem)
}

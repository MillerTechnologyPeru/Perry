import CPerryGeometry
import PerryObjCInterop

// UITabBarController: view controllers side by side, the selected one's
// view shown above a tab bar with an item for each. A change of selection
// takes effect at once; the views change places, with their appearance
// callbacks, in the next update pass, as on Darwin. Its view loads with it.

final class TabBarControllerState: ObjectState {
    var viewControllers: [UIViewController] = []
    /// NSNotFound when there is nothing to select.
    var selectedIndex = Int.max
    /// The controller whose view is shown, kept until another replaces it.
    var displayed: UIViewController?
    var tabBar: UITabBar?
    var delegate: UnsafeMutableRawPointer?
    var customizableViewControllers: NSObject?
    var transitionScheduled = false
}

/// The tab bar's height on an iPhone, above the home indicator.
private let tabBarHeight: CGFloat = 49

@ObjCClass("UITabBarController")
open class UITabBarController: UIViewController {
    static let tabStates = StateTable<TabBarControllerState>()
    var tabs: TabBarControllerState { UITabBarController.tabStates[objcObject] }

    @ObjCMethod("initWithNibName:bundle:")
    override func initialize(nibName: String?, bundle: NSObject?) -> Self {
        _ = super.initialize(nibName: nibName, bundle: bundle)
        _ = loadedView
        return self
    }

    /// From a nib or storyboard: the bar's colors, then the controllers,
    /// adopted as -setViewControllers: does, the first selected.
    @ObjCMethod("initWithCoder:")
    override func initialize(coder: NSObject) -> Self {
        _ = super.initialize(coder: coder)
        _ = loadedView
        let decoded = Coder(coder: coder)
        if let archived = decoded.object("UITabBar")?.as(UITabBar.self) {
            let bar = tabBar()
            bar.bar.barStyle = archived.bar.barStyle
            bar.bar.translucent = archived.bar.translucent
            bar.bar.barTintColor = archived.bar.barTintColor
            if let tint = archived.state.tintColor { bar.state.tintColor = tint }
        }
        tabs.customizableViewControllers = decoded.object("UICustomizableViewControllers")
        let controllers = decoded.array("UIViewControllers").compactMap { $0.as(UIViewController.self) }
        for controller in controllers { adopt(controller) }
        tabs.viewControllers = controllers
        tabs.selectedIndex = controllers.isEmpty ? Int.max : 0
        itemsChanged()
        return self
    }

    @ObjCMethod("dealloc")
    override func dealloc() {
        UITabBarController.tabStates.remove(objcObject)
        super.dealloc()
    }

    /// A container with the bar along the bottom.
    @ObjCMethod("loadView")
    override func loadView() {
        let view = UILayoutContainerView.objCClass.object.allocated().initializeView(frame: Screen.bounds).unsafeCast(to: UIView.self)
        view.setAutoresizingMask(18)
        setView(view)
        view.addSubview(tabBar())
    }

    @ObjCMethod("tabBar")
    func tabBar() -> UITabBar {
        if let bar = tabs.tabBar { return bar }
        let bounds = Screen.bounds
        let bar = UITabBar.objCClass.object.allocated()
            .initializeView(frame: CGRect(x: 0, y: bounds.height - tabBarHeight, width: bounds.width, height: tabBarHeight))
            .unsafeCast(to: UITabBar.self)
        // Flexible width and top margin.
        bar.setAutoresizingMask(10)
        tabs.tabBar = bar
        bar.bar.controller = objcObject
        return bar
    }

    @ObjCMethod("delegate") func delegate() -> NSObject? { tabs.delegate.map { NSObject($0) } }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { tabs.delegate = delegate?.objcObject }

    // MARK: The controllers

    @ObjCMethod("viewControllers")
    func viewControllers() -> NSObject? { tabs.viewControllers.isEmpty ? nil : NSMutableArray.of(tabs.viewControllers) }

    @ObjCMethod("setViewControllers:") func setViewControllers(_ controllers: NSArray?) { setViewControllers(controllers, animated: false) }

    /// Controllers that leave are released, those that come adopted; the
    /// selected controller stays selected if it is still there, else the
    /// first is.
    @ObjCMethod("setViewControllers:animated:")
    func setViewControllers(_ controllers: NSArray?, animated: Bool) {
        let new = controllers?.elements.map { $0.unsafeCast(to: UIViewController.self) } ?? []
        let old = tabs.viewControllers
        let selected = selectedController
        for controller in old where !new.contains(where: { $0.objcObject == controller.objcObject }) {
            controller.sendWillMove(toParent: nil)
            state.children.removeAll { $0.objcObject == controller.objcObject }
            controller.state.parent = nil
            controller.sendDidMove(toParent: nil)
        }
        for controller in new where !old.contains(where: { $0.objcObject == controller.objcObject }) { adopt(controller) }
        tabs.viewControllers = new
        tabs.selectedIndex = selected.flatMap { kept in new.firstIndex { $0.objcObject == kept.objcObject } }
            ?? (new.isEmpty ? Int.max : 0)
        itemsChanged()
        scheduleTransition()
    }

    @ObjCMethod("customizableViewControllers") func customizableViewControllers() -> NSObject? { tabs.customizableViewControllers }
    @ObjCMethod("setCustomizableViewControllers:")
    func setCustomizableViewControllers(_ controllers: NSObject?) { tabs.customizableViewControllers = controllers }

    /// There is no More tab: every controller has a tab of its own.
    @ObjCMethod("moreNavigationController") func moreNavigationController() -> UIViewController? { nil }

    /// A child at once, as tab bar controllers' children are.
    private func adopt(_ controller: UIViewController) {
        controller.sendWillMove(toParent: self)
        state.children.append(controller)
        controller.state.parent = objcObject
        controller.sendDidMove(toParent: self)
    }

    /// The bar shows the controllers' items, the selected one selected.
    func itemsChanged() {
        let bar = tabBar()
        bar.bar.items = tabs.viewControllers.map { $0.tabBarItem() }
        bar.bar.selected = selectedController?.tabBarItem()
        bar.setNeedsDisplay()
    }

    // MARK: Selection

    var selectedController: UIViewController? {
        tabs.viewControllers.indices.contains(tabs.selectedIndex) ? tabs.viewControllers[tabs.selectedIndex] : nil
    }

    @ObjCMethod("selectedIndex") func selectedIndex() -> Int { tabs.selectedIndex }

    @ObjCMethod("setSelectedIndex:")
    func setSelectedIndex(_ index: Int) {
        guard tabs.viewControllers.indices.contains(index) else { return }
        tabs.selectedIndex = index
        itemsChanged()
        scheduleTransition()
    }

    @ObjCMethod("selectedViewController") func selectedViewController() -> UIViewController? { selectedController }

    @ObjCMethod("setSelectedViewController:")
    func setSelectedViewController(_ controller: UIViewController?) {
        guard let controller, let index = tabs.viewControllers.firstIndex(where: { $0.objcObject == controller.objcObject }) else { return }
        setSelectedIndex(index)
    }

    /// A tap on a tab: the delegate may refuse it; tapping the selected
    /// tab again takes its navigation controller back to the root.
    func tabTapped(_ index: Int) {
        guard tabs.viewControllers.indices.contains(index) else { return }
        let controller = tabs.viewControllers[index]
        let delegate = delegate()
        if let delegate, delegate.responds(to: "tabBarController:shouldSelectViewController:"),
           !delegate.sendTabBarController(self, shouldSelect: controller) { return }
        if index == tabs.selectedIndex {
            if controller.is(UINavigationController.self) {
                _ = controller.unsafeCast(to: UINavigationController.self).popToRoot(animated: true)
            }
        } else {
            setSelectedIndex(index)
        }
        if let delegate, delegate.responds(to: "tabBarController:didSelectViewController:") {
            delegate.sendTabBarController(self, didSelect: controller)
        }
    }

    // MARK: Showing the selected controller

    func scheduleTransition() {
        guard !tabs.transitionScheduled else { return }
        tabs.transitionScheduled = true
        Updates.transition { [self] in
            tabs.transitionScheduled = false
            runTransition()
        }
    }

    /// Shows the selected controller's view in place of the one shown, with
    /// appearance callbacks when the tab bar controller is on screen.
    func runTransition() {
        guard let view = state.view else { return }
        let selected = selectedController
        let from = tabs.displayed
        guard from?.objcObject != selected?.objcObject else { return }
        let onScreen = view.windowObject != nil && (state.appearance == .appeared || state.appearance == .appearing)
        if onScreen {
            _ = from?.beginAppearance(false, animated: false)
            _ = selected?.beginAppearance(true, animated: false)
        }
        from?.state.view?.removeFromSuperview()
        if let selected {
            let selectedView = selected.loadedView
            selectedView.sendSetFrame(contentFrame())
            view.insertSubview(selectedView, below: tabBar())
        }
        tabs.displayed = selected
        layoutContent()
        if onScreen {
            from?.finishAppearance()
            selected?.finishAppearance()
        }
    }

    @ObjCMethod("viewWillLayoutSubviews")
    override func viewWillLayoutSubviews() { layoutContent() }

    /// Where the selected controller's view goes: the view above the bar.
    func contentFrame() -> CGRect {
        guard let view = state.view else { return .zero }
        let bounds = view.state.bounds
        let bar = tabBar()
        guard !bar.state.hidden else { return bounds }
        return CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: max(bar.state.frame.minY - bounds.minY, 0))
    }

    /// The bar across the bottom, over the home indicator's area, the
    /// content filling the view above it.
    func layoutContent() {
        guard let view = state.view else { return }
        let bounds = view.state.bounds
        let bottom = view.windowObject != nil ? view.safeAreaInsets(ignoringController: true).bottom : 0
        let height = tabBarHeight + bottom
        tabBar().sendSetFrame(CGRect(x: 0, y: bounds.maxY - height, width: bounds.width, height: height))
        if let displayed = tabs.displayed, let displayedView = displayed.state.view { displayedView.sendSetFrame(contentFrame()) }
    }

    /// Shows in the selected controller, as -showViewController:sender:
    /// does in a tab bar controller.
    @ObjCMethod("showViewController:sender:")
    override func show(_ controller: UIViewController, sender: NSObject?) {
        guard let selected = selectedController else { return super.show(controller, sender: sender) }
        selected.show(controller, sender: sender)
    }
}

/// UITabBarControllerDelegate's messages.
extension NSObject {
    @ObjCMethod("tabBarController:shouldSelectViewController:")
    func sendTabBarController(_ controller: UITabBarController, shouldSelect viewController: UIViewController) -> Bool

    @ObjCMethod("tabBarController:didSelectViewController:")
    func sendTabBarController(_ controller: UITabBarController, didSelect viewController: UIViewController)

    @ObjCMethod("tabBar:didSelectItem:")
    func sendTabBar(_ bar: UITabBar, didSelect item: UITabBarItem)
}

// MARK: - UITabBar

final class TabBarState: ObjectState {
    var items: [UITabBarItem] = []
    var selected: UITabBarItem?
    var delegate: UnsafeMutableRawPointer?
    /// The tab bar controller that owns the bar; not retained.
    var controller: UnsafeMutableRawPointer?
    var barStyle = 0
    var translucent = true
    var barTintColor: UIColor?
    var unselectedItemTintColor: UIColor?
    var backgroundImage: NSObject?
    var shadowImage: NSObject?
    var selectionIndicatorImage: NSObject?
    var standardAppearance: NSObject?
    var scrollEdgeAppearance: NSObject?
    /// What the bar last drew, to tell when its items have changed.
    var drawn = ""
}

/// A bar of tabs along the bottom, each an icon over its title, the
/// selected one in the tint color and the others gray.
@ObjCClass("UITabBar")
open class UITabBar: UIView {
    static let tabBarStates = StateTable<TabBarState>()
    var bar: TabBarState { UITabBar.tabBarStates[objcObject] }

    @ObjCMethod("dealloc")
    override func dealloc() {
        UITabBar.tabBarStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCMethod("initWithCoder:")
    override func initialize(coder: NSObject) -> Self {
        _ = super.initialize(coder: coder)
        let decoded = Coder(coder: coder)
        bar.items = decoded.array("UIItems").compactMap { $0.as(UITabBarItem.self) }
        bar.barStyle = decoded.integer("UIBarStyle")
        bar.barTintColor = decoded.object("UIBarTintColor")?.as(UIColor.self)
        return self
    }

    @ObjCMethod("items") func items() -> NSObject? { bar.items.isEmpty ? nil : NSMutableArray.of(bar.items) }
    @ObjCMethod("setItems:") func setItems(_ items: NSArray?) { setItems(items, animated: false) }
    @ObjCMethod("setItems:animated:")
    func setItems(_ items: NSArray?, animated: Bool) {
        bar.items = items?.elements.compactMap { $0.as(UITabBarItem.self) } ?? []
        setNeedsDisplay()
    }
    @ObjCMethod("selectedItem") func selectedItem() -> UITabBarItem? { bar.selected }
    @ObjCMethod("setSelectedItem:") func setSelectedItem(_ item: UITabBarItem?) { bar.selected = item; setNeedsDisplay() }
    @ObjCMethod("delegate") func delegate() -> NSObject? { bar.delegate.map { NSObject($0) } }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { bar.delegate = delegate?.objcObject }

    @ObjCMethod("barStyle") func barStyle() -> Int { bar.barStyle }
    @ObjCMethod("setBarStyle:") func setBarStyle(_ style: Int) { bar.barStyle = style; setNeedsDisplay() }
    @ObjCMethod("isTranslucent") func isTranslucent() -> Bool { bar.translucent }
    @ObjCMethod("setTranslucent:") func setTranslucent(_ translucent: Bool) { bar.translucent = translucent }
    @ObjCMethod("barTintColor") func barTintColor() -> UIColor? { bar.barTintColor }
    @ObjCMethod("setBarTintColor:") func setBarTintColor(_ color: UIColor?) { bar.barTintColor = color; setNeedsDisplay() }
    @ObjCMethod("unselectedItemTintColor") func unselectedItemTintColor() -> UIColor? { bar.unselectedItemTintColor }
    @ObjCMethod("setUnselectedItemTintColor:")
    func setUnselectedItemTintColor(_ color: UIColor?) { bar.unselectedItemTintColor = color; setNeedsDisplay() }
    @ObjCMethod("selectedImageTintColor") func selectedImageTintColor() -> UIColor? { tintColor() }
    @ObjCMethod("setSelectedImageTintColor:") func setSelectedImageTintColor(_ color: UIColor?) { setTintColor(color) }
    @ObjCMethod("backgroundImage") func backgroundImage() -> NSObject? { bar.backgroundImage }
    @ObjCMethod("setBackgroundImage:") func setBackgroundImage(_ image: NSObject?) { bar.backgroundImage = image }
    @ObjCMethod("shadowImage") func shadowImage() -> NSObject? { bar.shadowImage }
    @ObjCMethod("setShadowImage:") func setShadowImage(_ image: NSObject?) { bar.shadowImage = image }
    @ObjCMethod("selectionIndicatorImage") func selectionIndicatorImage() -> NSObject? { bar.selectionIndicatorImage }
    @ObjCMethod("setSelectionIndicatorImage:") func setSelectionIndicatorImage(_ image: NSObject?) { bar.selectionIndicatorImage = image }
    @ObjCMethod("standardAppearance") func standardAppearance() -> NSObject? { bar.standardAppearance }
    @ObjCMethod("setStandardAppearance:") func setStandardAppearance(_ appearance: NSObject?) { bar.standardAppearance = appearance }
    @ObjCMethod("scrollEdgeAppearance") func scrollEdgeAppearance() -> NSObject? { bar.scrollEdgeAppearance }
    @ObjCMethod("setScrollEdgeAppearance:") func setScrollEdgeAppearance(_ appearance: NSObject?) { bar.scrollEdgeAppearance = appearance }
    /// UITabBarItemPositioning: automatic 0.
    @ObjCMethod("itemPositioning") func itemPositioning() -> Int { 0 }
    @ObjCMethod("setItemPositioning:") func setItemPositioning(_ positioning: Int) {}
    @ObjCMethod("itemWidth") func itemWidth() -> CGFloat { 0 }
    @ObjCMethod("setItemWidth:") func setItemWidth(_ width: CGFloat) {}
    @ObjCMethod("itemSpacing") func itemSpacing() -> CGFloat { 0 }
    @ObjCMethod("setItemSpacing:") func setItemSpacing(_ spacing: CGFloat) {}

    @ObjCMethod("sizeThatFits:")
    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: tabBarHeight) }

    nonisolated(unsafe) private static let font = UIFont.systemFont(size: 10)

    /// Each item's frame: the bar's width shared equally, the top 49
    /// points high.
    func itemFrames() -> [(item: UITabBarItem, frame: CGRect)] {
        let bounds = state.bounds, items = bar.items
        guard !items.isEmpty else { return [] }
        let width = bounds.width / CGFloat(items.count)
        return items.enumerated().map { index, item in
            (item, CGRect(x: CGFloat(index) * width, y: 0, width: width, height: min(tabBarHeight, bounds.height)))
        }
    }

    /// A light background with a hairline above; each item's icon, drawn
    /// as a template unless it asks to be drawn as it is, over its title,
    /// and its badge.
    @ObjCMethod("drawRect:")
    override func draw(_ rect: CGRect) {
        guard let context = Graphics.current else { return }
        let bounds = state.bounds
        let background = bar.barTintColor ?? UIColor.gray(0.97), separator = UIColor.separator()
        withExtendedLifetime((background, separator)) {
            CG.setFillColorWithColor(context, background.state.makeCGColor())
            CG.fillRect(context, bounds)
            CG.setFillColorWithColor(context, separator.state.makeCGColor())
            CG.fillRect(context, CGRect(x: 0, y: 0, width: bounds.width, height: Screen.pixel))
        }
        let tint = tintColor(), unselected = bar.unselectedItemTintColor ?? UIColor.systemGray()
        for (item, frame) in itemFrames() {
            let isSelected = item.objcObject == bar.selected?.objcObject
            let color = !item.state.enabled ? UIColor.systemGray3() : isSelected ? tint : unselected
            let icon = isSelected ? (item.tab.selectedImage ?? item.state.image) : item.state.image
            var iconFrame = CGRect(x: frame.midX - 15, y: frame.minY + 5, width: 30, height: 30)
            if let icon {
                // Icons keep their aspect, fitted to 30 points.
                let size = icon.state.size
                let scale = min(1, 30 / max(size.width, 1), 30 / max(size.height, 1))
                let fitted = CGSize(width: size.width * scale, height: size.height * scale)
                iconFrame = CGRect(x: frame.midX - fitted.width / 2, y: frame.minY + 5 + (30 - fitted.height) / 2,
                                   width: fitted.width, height: fitted.height)
                let drawn = icon.state.renderingMode == 1 ? icon : icon.withTintColor(color)
                drawn.draw(in: iconFrame)
            }
            if let title = item.displayTitle {
                let size = Text.size(title, font: UITabBar.font)
                Text.draw(title, at: CGPoint(x: frame.midX - size.width / 2, y: frame.minY + 36), font: UITabBar.font, color: color)
            }
            if let badge = item.tab.badgeValue {
                drawBadge(badge, color: item.tab.badgeColor ?? UIColor.systemRed(), at: CGPoint(x: iconFrame.maxX - 6, y: frame.minY + 2),
                          context: context)
            }
        }
    }

    /// A badge: white text on a rounded bar of `color`, at least a circle.
    private func drawBadge(_ text: String, color: UIColor, at origin: CGPoint, context: CGRef) {
        let font = UIFont.systemFont(size: 13)
        let size = Text.size(text, font: font)
        let height: CGFloat = 18
        let width = max(height, size.width + 10)
        let badge = CGRect(x: origin.x, y: origin.y, width: width, height: height)
        withExtendedLifetime(color) {
            CG.setFillColorWithColor(context, color.state.makeCGColor())
            if let path = roundedRectPath(badge, radius: height / 2, corners: 15) {
                CG.addPath(context, path.object)
                CG.fillPath(context)
            }
        }
        Text.draw(text, at: CGPoint(x: badge.midX - size.width / 2, y: badge.midY - size.height / 2), font: font, color: UIColor.white())
    }

    /// QuartzCore asks before drawing: what the bar shows changes without
    /// its saying so.
    @ObjCMethod("_perryLayerContentChanged:")
    func layerContentChanged(_ layer: NSObject) -> Bool { contentChanged() }

    /// Whether what the bar shows has changed since it last drew.
    func contentChanged() -> Bool {
        var content = "\(state.bounds.width) \(bar.selected.map { "\($0.objcObject)" } ?? "")"
        for item in bar.items {
            content += "|\(item.state.title ?? "")|\(item.state.image.map { "\($0.objcObject)" } ?? "")|\(item.tab.badgeValue ?? "")"
            content += "|\(item.state.enabled)"
        }
        guard content != bar.drawn else { return false }
        bar.drawn = content
        return true
    }

    /// A tap selects the item under it, through the controller if there
    /// is one, else telling the delegate.
    func tap(at point: CGPoint) {
        guard let index = itemFrames().firstIndex(where: { point.x >= $0.frame.minX && point.x < $0.frame.maxX }) else { return }
        let item = bar.items[index]
        guard item.state.enabled else { return }
        if let controller = bar.controller {
            UITabBarController(objcObject: controller, ownership: .retain).tabTapped(index)
            return
        }
        bar.selected = item
        setNeedsDisplay()
        if let delegate = delegate(), delegate.responds(to: "tabBar:didSelectItem:") { delegate.sendTabBar(self, didSelect: item) }
    }
}

// MARK: - UITabBarItem

final class TabBarItemState: ObjectState {
    var selectedImage: UIImage?
    var badgeValue: String?
    var badgeColor: UIColor?
    /// UITabBarSystemItem, or -1.
    var systemItem = -1
}

@ObjCClass("UITabBarItem")
open class UITabBarItem: UIBarItem {
    static let tabStates = StateTable<TabBarItemState>()
    var tab: TabBarItemState { UITabBarItem.tabStates[objcObject] }

    @ObjCMethod("dealloc")
    override func dealloc() {
        UITabBarItem.tabStates.remove(objcObject)
        super.dealloc()
    }

    /// UITabBarSystemItem's titles: more 0 through most viewed 11.
    private static let systemTitles = ["More", "Favorites", "Featured", "Top Rated", "Recents", "Contacts", "History",
                                       "Bookmarks", "Search", "Downloads", "Most Recent", "Most Viewed"]

    var displayTitle: String? {
        if let title = state.title { return title }
        return UITabBarItem.systemTitles.indices.contains(tab.systemItem) ? UITabBarItem.systemTitles[tab.systemItem] : nil
    }

    @ObjCMethod("init") func initialize() -> Self { self }

    @ObjCMethod("initWithCoder:")
    func initialize(coder: NSObject) -> Self {
        let decoded = Coder(coder: coder)
        state.title = decoded.string("UITitle")
        state.image = decoded.object("UIImage")?.as(UIImage.self)
        tab.selectedImage = decoded.object("UISelectedImage")?.as(UIImage.self)
        state.enabled = decoded.has("UIEnabled") ? decoded.bool("UIEnabled") : true
        state.tag = decoded.integer("UITag")
        tab.badgeValue = decoded.string("UIBadgeValue")
        if decoded.bool("UIIsSystemItem") { tab.systemItem = decoded.integer("UISystemItem") }
        return self
    }

    @ObjCMethod("initWithTitle:image:tag:")
    func initialize(title: String?, image: UIImage?, tag: Int) -> Self {
        (state.title, state.image, state.tag) = (title, image, tag)
        return self
    }

    @ObjCMethod("initWithTitle:image:selectedImage:")
    func initialize(title: String?, image: UIImage?, selectedImage: UIImage?) -> Self {
        (state.title, state.image) = (title, image)
        tab.selectedImage = selectedImage
        return self
    }

    @ObjCMethod("initWithTabBarSystemItem:tag:")
    func initialize(systemItem: Int, tag: Int) -> Self {
        tab.systemItem = systemItem
        state.tag = tag
        return self
    }

    @ObjCMethod("selectedImage") func selectedImage() -> UIImage? { tab.selectedImage }
    @ObjCMethod("setSelectedImage:") func setSelectedImage(_ image: UIImage?) { tab.selectedImage = image }
    @ObjCMethod("badgeValue") func badgeValue() -> String? { tab.badgeValue }
    @ObjCMethod("setBadgeValue:") func setBadgeValue(_ value: String?) { tab.badgeValue = value }
    @ObjCMethod("badgeColor") func badgeColor() -> UIColor? { tab.badgeColor }
    @ObjCMethod("setBadgeColor:") func setBadgeColor(_ color: UIColor?) { tab.badgeColor = color }
    @ObjCMethod("setFinishedSelectedImage:withFinishedUnselectedImage:")
    func setFinishedImages(selected: UIImage?, unselected: UIImage?) {
        tab.selectedImage = selected?.withRenderingMode(1)
        state.image = unselected?.withRenderingMode(1)
    }
    @ObjCMethod("titlePositionAdjustment") func titlePositionAdjustment() -> CGSize { .zero }
    @ObjCMethod("setTitlePositionAdjustment:") func setTitlePositionAdjustment(_ adjustment: CGSize) {}
    @ObjCMethod("imageInsets") func imageInsets() -> UIEdgeInsets { .zero }
    @ObjCMethod("setImageInsets:") func setImageInsets(_ insets: UIEdgeInsets) {}
    @ObjCMethod("setBadgeTextAttributes:forState:") func setBadgeTextAttributes(_ attributes: NSObject?, for controlState: UInt) {}
}

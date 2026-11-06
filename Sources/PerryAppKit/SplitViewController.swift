import CPerryGeometry
import PerryObjCInterop

/// NSSplitViewItem: a child view controller of a split view controller, and
/// how its pane behaves.
@ObjCClass("NSSplitViewItem")
open class NSSplitViewItem: NSObject {
    /// NSSplitViewItemBehavior: default 0, sidebar 1, content list 2,
    /// inspector 3.
    var behavior = 0
    var viewController: NSViewController?
    var canCollapse = false
    var collapsed = false
    var minimumThickness: CGFloat = -1
    var maximumThickness: CGFloat = -1
    var preferredThicknessFraction: CGFloat = -1
    var holdingPriority: Float = 250
    var titlebarSeparatorStyle = 0
    var allowsFullHeightLayout = false
    var automaticallyAdjustsSafeAreaInsets = false
    var springLoaded = false
    var canCollapseFromWindowResize = true
    /// Not retained: the controller owns its items.
    var controllerObject: UnsafeMutableRawPointer?

    @ObjCMethod("init")
    public required override init() { super.init() }

    convenience init(viewController: NSViewController?, behavior: Int) {
        self.init()
        self.viewController = viewController
        self.behavior = behavior
        switch behavior {
        case 1: (canCollapse, holdingPriority, minimumThickness) = (true, 260, 140)
        case 2: (holdingPriority, minimumThickness) = (255, 200)
        case 3: (canCollapse, holdingPriority, minimumThickness) = (true, 260, 140)
        default: break
        }
    }

    @ObjCClassMethod("splitViewItemWithViewController:")
    class func item(viewController: NSViewController?) -> NSSplitViewItem { NSSplitViewItem(viewController: viewController, behavior: 0) }
    @ObjCClassMethod("sidebarWithViewController:")
    class func sidebar(viewController: NSViewController?) -> NSSplitViewItem { NSSplitViewItem(viewController: viewController, behavior: 1) }
    @ObjCClassMethod("contentListWithViewController:")
    class func contentList(viewController: NSViewController?) -> NSSplitViewItem { NSSplitViewItem(viewController: viewController, behavior: 2) }
    @ObjCClassMethod("inspectorWithViewController:")
    class func inspector(viewController: NSViewController?) -> NSSplitViewItem { NSSplitViewItem(viewController: viewController, behavior: 3) }

    var controller: NSSplitViewController? { controllerObject.map { NSSplitViewController.objCInstance($0, ownership: .retain) } }

    @ObjCMethod("viewController") func itemViewController() -> NSViewController? { viewController }
    @ObjCMethod("setViewController:") func setViewController(_ value: NSViewController?) { viewController = value }
    @ObjCMethod("behavior") func itemBehavior() -> Int { behavior }
    @ObjCMethod("canCollapse") func itemCanCollapse() -> Bool { canCollapse }
    @ObjCMethod("setCanCollapse:") func setCanCollapse(_ value: Bool) { canCollapse = value }
    @ObjCMethod("canCollapseFromWindowResize") func itemCanCollapseFromWindowResize() -> Bool { canCollapseFromWindowResize }
    @ObjCMethod("setCanCollapseFromWindowResize:") func setCanCollapseFromWindowResize(_ value: Bool) { canCollapseFromWindowResize = value }
    @ObjCMethod("isCollapsed") func isCollapsed() -> Bool { collapsed }
    @ObjCMethod("setCollapsed:")
    func setCollapsed(_ value: Bool) {
        guard value != collapsed else { return }
        collapsed = value
        viewController?.viewObject?.setHidden(value)
        controller?.splitViewObject?.adjustSubviews()
    }
    @ObjCMethod("animator") func animator() -> NSSplitViewItem { self }
    @ObjCMethod("minimumThickness") func itemMinimumThickness() -> CGFloat { minimumThickness }
    @ObjCMethod("setMinimumThickness:")
    func setMinimumThickness(_ value: CGFloat) {
        minimumThickness = value
        controller?.splitViewObject?.adjustSubviews()
    }
    @ObjCMethod("maximumThickness") func itemMaximumThickness() -> CGFloat { maximumThickness }
    @ObjCMethod("setMaximumThickness:") func setMaximumThickness(_ value: CGFloat) { maximumThickness = value }
    @ObjCMethod("preferredThicknessFraction") func itemPreferredThicknessFraction() -> CGFloat { preferredThicknessFraction }
    @ObjCMethod("setPreferredThicknessFraction:") func setPreferredThicknessFraction(_ value: CGFloat) { preferredThicknessFraction = value }
    @ObjCMethod("holdingPriority") func itemHoldingPriority() -> Float { holdingPriority }
    @ObjCMethod("setHoldingPriority:")
    func setHoldingPriority(_ value: Float) {
        holdingPriority = value
        controller?.applyHoldingPriorities()
    }
    @ObjCMethod("titlebarSeparatorStyle") func itemTitlebarSeparatorStyle() -> Int { titlebarSeparatorStyle }
    @ObjCMethod("setTitlebarSeparatorStyle:") func setTitlebarSeparatorStyle(_ value: Int) { titlebarSeparatorStyle = value }
    @ObjCMethod("allowsFullHeightLayout") func itemAllowsFullHeightLayout() -> Bool { allowsFullHeightLayout }
    @ObjCMethod("setAllowsFullHeightLayout:") func setAllowsFullHeightLayout(_ value: Bool) { allowsFullHeightLayout = value }
    @ObjCMethod("automaticallyAdjustsSafeAreaInsets") func itemAutomaticallyAdjustsSafeAreaInsets() -> Bool { automaticallyAdjustsSafeAreaInsets }
    @ObjCMethod("setAutomaticallyAdjustsSafeAreaInsets:") func setAutomaticallyAdjustsSafeAreaInsets(_ value: Bool) { automaticallyAdjustsSafeAreaInsets = value }
    @ObjCMethod("isSpringLoaded") func isSpringLoaded() -> Bool { springLoaded }
    @ObjCMethod("setSpringLoaded:") func setSpringLoaded(_ value: Bool) { springLoaded = value }
}

/// NSSplitViewController: its items' views as the panes of a split view,
/// side by side unless the split view says otherwise.
@ObjCClass("NSSplitViewController")
open class NSSplitViewController: NSViewController {
    var items: [NSSplitViewItem] = []
    var splitViewObject: NSSplitView?

    public required init() { super.init() }

    @ObjCMethod("initWithNibName:bundle:")
    public required init(nibName: String?, bundle: NSObject?) { super.init(nibName: nibName, bundle: bundle) }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) { super.init(coder: coder) }

    /// The split view, made the first time it is asked for.
    var splitView: NSSplitView {
        if let splitViewObject { return splitViewObject }
        let view = NSSplitView(frame: .zero)
        view.vertical = true
        installSplitView(view)
        return view
    }

    private func installSplitView(_ view: NSSplitView) {
        splitViewObject = view
        view.autoresizingMask = 18
        if view.delegateObject == nil { view.delegateObject = objcObject }
        view.paneLimits = { [weak self] pane in
            guard let item = self?.items.first(where: { $0.viewController?.viewObject === pane }) else {
                return (0, .greatestFiniteMagnitude)
            }
            return (max(0, item.minimumThickness), item.maximumThickness > 0 ? item.maximumThickness : .greatestFiniteMagnitude)
        }
        for item in items { addPane(item) }
        applyHoldingPriorities()
    }

    @ObjCMethod("splitView") func controllerSplitView() -> NSSplitView { splitView }
    @ObjCMethod("setSplitView:")
    func setSplitView(_ view: NSSplitView?) {
        guard let view, view !== splitViewObject else { return }
        if splitViewObject == nil, viewObject == nil {
            // Before the view loads: AppKit sets the split view
            // controller's split view up as its view.
            if view.panes.isEmpty, !view.vertical { view.vertical = true }
        }
        installSplitView(view)
        if viewObject != nil { setView(view) }
    }

    @ObjCMethod("loadView")
    override func loadView() {
        if nibName != nil { super.loadView() }
        if viewObject == nil { setView(splitView) }
    }

    @ObjCMethod("viewDidLoad")
    override func viewDidLoad() {
        // Panes keep their sizes from their nibs, at least as thick as their
        // items need.
        splitView.adjustSubviews()
    }

    // MARK: Items

    @ObjCMethod("splitViewItems") func splitViewItems() -> NSObject { NSMutableArray.of(items) }
    @ObjCMethod("setSplitViewItems:")
    func setSplitViewItems(_ value: NSObject?) {
        for item in items { removeSplitViewItem(item) }
        for case let item? in (value?.as(NSArray.self)?.elements ?? []).map({ $0.as(NSSplitViewItem.self) }) { addSplitViewItem(item) }
    }
    @ObjCMethod("addSplitViewItem:") func addSplitViewItem(_ item: NSSplitViewItem?) { insertSplitViewItem(item, at: items.count) }
    @ObjCMethod("insertSplitViewItem:atIndex:")
    func insertSplitViewItem(_ item: NSSplitViewItem?, at index: Int) {
        guard let item, !items.contains(where: { $0 === item }) else { return }
        let index = max(0, min(index, items.count))
        items.insert(item, at: index)
        item.controllerObject = objcObject
        if let child = item.viewController { insertChild(child, at: index) }
        if splitViewObject != nil { addPane(item) }
        applyHoldingPriorities()
    }
    @ObjCMethod("removeSplitViewItem:")
    func removeSplitViewItem(_ item: NSSplitViewItem?) {
        guard let item, let index = items.firstIndex(where: { $0 === item }) else { return }
        items.remove(at: index)
        item.controllerObject = nil
        if let child = item.viewController {
            if let view = child.viewObject {
                splitViewObject?.arranged.removeAll { $0 === view }
                view.removeFromSuperview()
            }
            child.removeFromParent()
        }
        applyHoldingPriorities()
        splitViewObject?.adjustSubviews()
    }
    @ObjCMethod("splitViewItemForViewController:")
    func splitViewItem(for controller: NSViewController?) -> NSSplitViewItem? { items.first { $0.viewController === controller } }

    /// Puts an item's view in the split view, in the item's place.
    private func addPane(_ item: NSSplitViewItem) {
        guard let splitView = splitViewObject, let view = item.viewController?.view() else { return }
        let index = items.firstIndex { $0 === item } ?? items.count
        let before = items[..<index].compactMap { $0.viewController?.viewObject }.filter { $0.superview === splitView }.count
        view.autoresizingMask = 18
        view.translatesAutoresizingMask = true
        var frame = view.frame
        let minimum = item.minimumThickness > 0 ? item.minimumThickness : 0
        if splitView.vertical { frame.size.width = max(frame.width, minimum) } else { frame.size.height = max(frame.height, minimum) }
        if frame.size == .zero { frame.size = CGSize(width: 240, height: 240) }
        view.setFrame(frame)
        view.setHidden(item.collapsed)
        if view.superview !== splitView {
            let panes = splitView.subviews
            if before < panes.count { splitView.addSubview(view, positioned: -1, relativeTo: panes[before]) } else { splitView.addSubview(view) }
        }
        if !splitView.arrangesAllSubviews, !splitView.arranged.contains(where: { $0 === view }) {
            splitView.arranged.insert(view, at: min(before, splitView.arranged.count))
        }
        splitView.adjustSubviews()
    }

    func applyHoldingPriorities() {
        guard let splitView = splitViewObject else { return }
        splitView.holdingPriorities = items.map(\.holdingPriority)
    }

    // MARK: Actions

    @ObjCMethod("toggleSidebar:")
    func toggleSidebar(_ sender: NSObject?) {
        guard let sidebar = items.first(where: { $0.behavior == 1 }) ?? items.first(where: \.canCollapse) else { return }
        sidebar.setCollapsed(!sidebar.collapsed)
    }

    @ObjCMethod("toggleInspector:")
    func toggleInspector(_ sender: NSObject?) {
        guard let inspector = items.last(where: { $0.behavior == 3 }) else { return }
        inspector.setCollapsed(!inspector.collapsed)
    }

    @ObjCMethod("minimumThicknessForInlineSidebars") func minimumThicknessForInlineSidebars() -> CGFloat { 0 }
    @ObjCMethod("setMinimumThicknessForInlineSidebars:") func setMinimumThicknessForInlineSidebars(_ value: CGFloat) {}

    // MARK: The split view's delegate

    @ObjCMethod("splitView:canCollapseSubview:")
    func splitView(_ splitView: NSObject?, canCollapseSubview view: NSView?) -> Bool {
        items.first { $0.viewController?.viewObject === view }?.canCollapse ?? false
    }

    @ObjCMethod("splitView:shouldHideDividerAtIndex:") func splitView(_ splitView: NSObject?, shouldHideDividerAt index: Int) -> Bool { false }

    @ObjCMethod("splitViewDidResizeSubviews:") func splitViewDidResizeSubviews(_ notification: NSObject?) {}
}

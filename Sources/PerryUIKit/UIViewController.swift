import CPerryGeometry
import Glibc
import PerryObjCInterop

// UIViewController: owns a view, which it loads the first time it is asked
// for, through -loadView then -viewDidLoad; contains child controllers;
// presents others modally; and goes through appearance transitions, each
// begun (-viewWillAppear:, -viewWillDisappear:) and later ended
// (-viewDidAppear:, -viewDidDisappear:).
//
// As on Darwin, a controller whose view enters or leaves a window begins
// its transition at once and ends it in the next update pass; containers
// and presentations run their transitions in that pass. A controller
// moving to or from a parent gets -didMoveToParentViewController: once its
// transition ends. Transitions forward to the children whose views are in
// the controller's view.

/// Where a controller is in its appearance.
enum Appearance {
    case disappeared, appearing, appeared, disappearing
}

final class ViewControllerState: ObjectState {
    var view: UIView?
    /// overrideUserInterfaceStyle: unspecified 0, light 1, dark 2.
    var userInterfaceStyle = 0
    var title: String?
    var nibName: String?
    /// The parent, which retains this controller; not retained.
    var parent: UnsafeMutableRawPointer?
    var children: [UIViewController] = []
    var navigationItem: UINavigationItem?
    var tabBarItem: UITabBarItem?
    var appearance = Appearance.disappeared
    var animated = false
    var movingToParent = false
    var movingFromParent = false
    var beingPresented = false
    var beingDismissed = false
    var presented: UIViewController?
    /// The controller that presented this one; not retained.
    var presenting: UnsafeMutableRawPointer?
    /// Where the presenter's view was, while a full-screen presentation
    /// covers it.
    var coveredSuperview: UIView?
    /// UIModalPresentationStyle: automatic -2.
    var modalPresentationStyle = -2
    var modalTransitionStyle = 0
    var definesPresentationContext = false
    var providesPresentationContextTransitionStyle = false
    var modalInPresentation = false
    var additionalSafeAreaInsets = UIEdgeInsets.zero
    var hidesBottomBarWhenPushed = false
    /// UIRectEdge: the edges whose bars the view extends under; all 15.
    var edgesForExtendedLayout = 15
    var extendedLayoutIncludesOpaqueBars = false
    var preferredContentSize = CGSize.zero
    var editing = false
    var restorationIdentifier: String?
    /// From a storyboard: the storyboard, its identifier for the
    /// controller, the segues from it, and the objects its view nib's
    /// placeholders stand for.
    var storyboard: UIStoryboard?
    var storyboardIdentifier: String?
    var segueTemplates: [UIStoryboardSegueTemplate] = []
    var externalObjects: [String: NSObject] = [:]
    /// Objects in the controller's storyboard scene that nothing else
    /// holds, such as a delegate the scene makes: kept as long as it is.
    var storyboardObjects: [NSObject] = []
    /// Where the controller's nib is, from its bundle.
    var nibBundlePath: String?
}

@ObjCClass("UIViewController")
open class UIViewController: UIResponder {
    static let states = StateTable<ViewControllerState>()
    var state: ViewControllerState { UIViewController.states[objcObject] }

    static func wrap(_ object: UnsafeMutableRawPointer) -> UIViewController {
        UIViewController(objcObject: object, ownership: .retain)
    }

    /// -init is -initWithNibName:bundle: with neither, sent so a
    /// subclass's initializer runs.
    @ObjCMethod("init")
    func initialize() -> NSObject { initializeViewController(nibName: nil, bundle: nil) }

    @ObjCMethod("initWithNibName:bundle:")
    func initialize(nibName: String?, bundle: NSObject?) -> Self {
        state.nibName = nibName
        state.nibBundlePath = bundle?.as(NSBundle.self)?.bundlePath()
        return self
    }

    /// From a storyboard or nib: the view's nib, the navigation item, the
    /// segues and the view nib's placeholders.
    @ObjCMethod("initWithCoder:")
    func initialize(coder: NSObject) -> Self {
        let decoded = Coder(coder: coder)
        let state = state
        state.nibName = decoded.string("UINibName")
        state.storyboardIdentifier = decoded.string("UIStoryboardIdentifier")
        state.restorationIdentifier = decoded.string("UIRestorationIdentifier")
        state.title = decoded.string("UITitle")
        if let item = decoded.object("UINavigationItem")?.as(UINavigationItem.self) {
            state.navigationItem = item
            if state.title == nil { state.title = item.state.title }
        }
        state.tabBarItem = decoded.object("UITabBarItem")?.as(UITabBarItem.self)
        state.segueTemplates = decoded.array("UIStoryboardSegueTemplates").compactMap { $0.as(UIStoryboardSegueTemplate.self) }
        for template in state.segueTemplates { template.state.viewController = objcObject }
        state.externalObjects = decoded.dictionary("UIExternalObjectsTableForViewLoading")
        state.storyboardObjects = decoded.array("UITopLevelObjectsToKeepAliveFromStoryboard")
        if decoded.has("UIModalPresentationStyle") { state.modalPresentationStyle = decoded.integer("UIModalPresentationStyle") }
        if decoded.has("UIModalTransitionStyle") { state.modalTransitionStyle = decoded.integer("UIModalTransitionStyle") }
        state.definesPresentationContext = decoded.bool("UIDefinesPresentationContext")
        if decoded.has("UIKeyEdgesForExtendedLayout") { state.edgesForExtendedLayout = decoded.integer("UIKeyEdgesForExtendedLayout") }
        state.extendedLayoutIncludesOpaqueBars = decoded.bool("UIKeyExtendedLayoutIncludesOpaqueBars")
        state.hidesBottomBarWhenPushed = decoded.bool("UIHidesBottomBarWhenPushed")
        if decoded.has("UIPreferredContentSize") { state.preferredContentSize = decoded.size("UIPreferredContentSize") }
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        let state = state
        if let view = state.view, view.state.viewController == objcObject { view.state.viewController = nil }
        for child in state.children where child.state.parent == objcObject { child.state.parent = nil }
        if let presented = state.presented, presented.state.presenting == objcObject { presented.state.presenting = nil }
        UIViewController.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIViewController.objCClass.pointer)
    }

    // MARK: The view

    /// The view, loaded on first use. A -loadView that sets none, as SDL's
    /// does before it sets the view itself, leaves it nil, as on iOS, which
    /// loads it again on the next use.
    @ObjCMethod("view")
    func view() -> UIView? {
        if state.view == nil {
            sendLoadView()
            guard state.view != nil else { return nil }
            performSeguesOnViewLoad()
            sendViewDidLoad()
        }
        return state.view
    }

    /// The view, loaded through the messages a subclass may override.
    var loadedView: UIView { state.view ?? sendView() }

    @ObjCMethod("setView:")
    func setView(_ view: UIView?) {
        if let old = state.view, old.state.viewController == objcObject { old.state.viewController = nil }
        state.view = view
        view?.state.viewController = objcObject
    }

    @ObjCMethod("viewIfLoaded") func viewIfLoaded() -> UIView? { state.view }
    @ObjCMethod("isViewLoaded") func isViewLoaded() -> Bool { state.view != nil }
    @ObjCMethod("loadViewIfNeeded") func loadViewIfNeeded() { _ = loadedView }

    /// The view from the controller's nib when it has one, else a plain
    /// view the size of the screen that follows its superview's size.
    @ObjCMethod("loadView")
    func loadView() {
        if loadViewFromNib() { return }
        let view = UIView.objCClass.object.allocated().initializeView(frame: Screen.bounds).unsafeCast(to: UIView.self)
        view.setAutoresizingMask(18)
        setView(view)
    }

    @ObjCMethod("viewDidLoad") func viewDidLoad() {}
    @ObjCMethod("viewWillAppear:") func viewWillAppear(_ animated: Bool) {}
    @ObjCMethod("viewDidAppear:") func viewDidAppear(_ animated: Bool) {}
    @ObjCMethod("viewWillDisappear:") func viewWillDisappear(_ animated: Bool) {}
    @ObjCMethod("viewDidDisappear:") func viewDidDisappear(_ animated: Bool) {}
    @ObjCMethod("viewWillLayoutSubviews") func viewWillLayoutSubviews() {}
    @ObjCMethod("viewDidLayoutSubviews") func viewDidLayoutSubviews() {}
    @ObjCMethod("viewSafeAreaInsetsDidChange") func viewSafeAreaInsetsDidChange() {}
    @ObjCMethod("viewLayoutMarginsDidChange") func viewLayoutMarginsDidChange() {}
    @ObjCMethod("updateViewConstraints") func updateViewConstraints() {}
    @ObjCMethod("didReceiveMemoryWarning") func didReceiveMemoryWarning() {}

    @ObjCMethod("viewWillTransitionToSize:withTransitionCoordinator:")
    func viewWillTransition(to size: CGSize, with coordinator: NSObject?) {}

    // MARK: Properties

    @ObjCMethod("title") func title() -> String? { state.title }

    /// Also the navigation item's title.
    @ObjCMethod("setTitle:")
    func setTitle(_ title: String?) {
        state.title = title
        state.navigationItem?.state.title = title
        state.tabBarItem?.state.title = title
    }

    @ObjCMethod("nibName") func nibName() -> String? { state.nibName }
    @ObjCMethod("nibBundle") func nibBundle() -> NSObject? { nil }
    @ObjCMethod("storyboard") func storyboard() -> NSObject? { nil }

    /// Made on first use, titled with the controller's title.
    /// The controller's tab, titled as the controller is.
    @ObjCMethod("tabBarItem")
    func tabBarItem() -> UITabBarItem {
        if let item = state.tabBarItem { return item }
        let item = UITabBarItem.objCClass.object.newInstance().unsafeCast(to: UITabBarItem.self)
        item.state.title = state.title
        state.tabBarItem = item
        return item
    }

    @ObjCMethod("setTabBarItem:") func setTabBarItem(_ item: UITabBarItem?) { state.tabBarItem = item }

    @ObjCMethod("navigationItem")
    func navigationItem() -> UINavigationItem {
        if let item = state.navigationItem { return item }
        let item = UINavigationItem.objCClass.object.allocated().initializeNavigationItem(title: state.title)
            .unsafeCast(to: UINavigationItem.self)
        state.navigationItem = item
        return item
    }

    @ObjCMethod("isEditing") func isEditing() -> Bool { state.editing }
    @ObjCMethod("setEditing:") func setEditing(_ editing: Bool) { sendSetEditing(editing, animated: false) }
    @ObjCMethod("setEditing:animated:") func setEditing(_ editing: Bool, animated: Bool) { state.editing = editing }
    @ObjCMethod("editButtonItem")
    func editButtonItem() -> UIBarButtonItem { UIBarButtonItem.make(systemItem: 2, target: self, action: nil) }

    @ObjCMethod("modalPresentationStyle") func modalPresentationStyle() -> Int { state.modalPresentationStyle }
    @ObjCMethod("setModalPresentationStyle:") func setModalPresentationStyle(_ style: Int) { state.modalPresentationStyle = style }
    @ObjCMethod("modalTransitionStyle") func modalTransitionStyle() -> Int { state.modalTransitionStyle }
    @ObjCMethod("setModalTransitionStyle:") func setModalTransitionStyle(_ style: Int) { state.modalTransitionStyle = style }
    @ObjCMethod("isModalInPresentation") func isModalInPresentation() -> Bool { state.modalInPresentation }
    @ObjCMethod("setModalInPresentation:") func setModalInPresentation(_ modal: Bool) { state.modalInPresentation = modal }
    @ObjCMethod("definesPresentationContext") func definesPresentationContext() -> Bool { state.definesPresentationContext }
    @ObjCMethod("setDefinesPresentationContext:") func setDefinesPresentationContext(_ defines: Bool) { state.definesPresentationContext = defines }
    @ObjCMethod("providesPresentationContextTransitionStyle") func providesPresentationContextTransitionStyle() -> Bool {
        state.providesPresentationContextTransitionStyle
    }
    @ObjCMethod("setProvidesPresentationContextTransitionStyle:") func setProvidesPresentationContextTransitionStyle(_ provides: Bool) {
        state.providesPresentationContextTransitionStyle = provides
    }
    @ObjCMethod("additionalSafeAreaInsets") func additionalSafeAreaInsets() -> UIEdgeInsets { state.additionalSafeAreaInsets }
    @ObjCMethod("setAdditionalSafeAreaInsets:") func setAdditionalSafeAreaInsets(_ insets: UIEdgeInsets) {
        state.additionalSafeAreaInsets = insets
        state.view?.setNeedsLayout()
    }
    @ObjCMethod("hidesBottomBarWhenPushed") func hidesBottomBarWhenPushed() -> Bool { state.hidesBottomBarWhenPushed }
    @ObjCMethod("edgesForExtendedLayout") func edgesForExtendedLayout() -> Int { state.edgesForExtendedLayout }
    @ObjCMethod("setEdgesForExtendedLayout:") func setEdgesForExtendedLayout(_ edges: Int) { state.edgesForExtendedLayout = edges }
    /// iOS 3's: whether the view lays out under the status bar. Views always
    /// do here, as there is no status bar.
    @ObjCMethod("wantsFullScreenLayout") func wantsFullScreenLayout() -> Bool { true }
    @ObjCMethod("setWantsFullScreenLayout:") func setWantsFullScreenLayout(_ wants: Bool) {}
    @ObjCMethod("extendedLayoutIncludesOpaqueBars") func extendedLayoutIncludesOpaqueBars() -> Bool { state.extendedLayoutIncludesOpaqueBars }
    @ObjCMethod("setExtendedLayoutIncludesOpaqueBars:") func setExtendedLayoutIncludesOpaqueBars(_ includes: Bool) {
        state.extendedLayoutIncludesOpaqueBars = includes
    }
    @ObjCMethod("setHidesBottomBarWhenPushed:") func setHidesBottomBarWhenPushed(_ hides: Bool) { state.hidesBottomBarWhenPushed = hides }
    @ObjCMethod("preferredContentSize") func preferredContentSize() -> CGSize { state.preferredContentSize }
    @ObjCMethod("setPreferredContentSize:") func setPreferredContentSize(_ size: CGSize) { state.preferredContentSize = size }
    @ObjCMethod("restorationIdentifier") func restorationIdentifier() -> String? { state.restorationIdentifier }
    @ObjCMethod("setRestorationIdentifier:") func setRestorationIdentifier(_ identifier: String?) { state.restorationIdentifier = identifier }

    // The status bar and the home indicator, which are not drawn.
    @ObjCMethod("preferredStatusBarStyle") func preferredStatusBarStyle() -> Int { 0 }
    @ObjCMethod("prefersStatusBarHidden") func prefersStatusBarHidden() -> Bool { false }
    @ObjCMethod("prefersHomeIndicatorAutoHidden") func prefersHomeIndicatorAutoHidden() -> Bool { false }
    @ObjCMethod("setNeedsStatusBarAppearanceUpdate") func setNeedsStatusBarAppearanceUpdate() {}
    /// No screen edges defer system gestures and no pointer locks: there is
    /// no home indicator, notification centre or pointer here.
    @ObjCMethod("setNeedsUpdateOfScreenEdgesDeferringSystemGestures") func setNeedsUpdateOfScreenEdgesDeferringSystemGestures() {}
    @ObjCMethod("setNeedsUpdateOfPrefersPointerLocked") func setNeedsUpdateOfPrefersPointerLocked() {}
    @ObjCMethod("setNeedsUpdateOfSupportedInterfaceOrientations") func setNeedsUpdateOfSupportedInterfaceOrientations() {}
    @ObjCMethod("preferredScreenEdgesDeferringSystemGestures") func preferredScreenEdgesDeferringSystemGestures() -> UInt { 0 }
    @ObjCMethod("prefersPointerLocked") func prefersPointerLocked() -> Bool { false }
    @ObjCMethod("setNeedsUpdateOfHomeIndicatorAutoHidden") func setNeedsUpdateOfHomeIndicatorAutoHidden() {}
    @ObjCMethod("supportedInterfaceOrientations") func supportedInterfaceOrientations() -> UInt { 2 }
    /// The screen's orientation (deprecated in iOS 8).
    @ObjCMethod("interfaceOrientation") func interfaceOrientation() -> Int { Screen.orientation }
    @ObjCMethod("preferredInterfaceOrientationForPresentation") func preferredInterfaceOrientationForPresentation() -> Int { Screen.orientation }
    @ObjCMethod("shouldAutorotate") func shouldAutorotate() -> Bool { true }
    // The rotation callbacks from before iOS 8, which subclasses still call
    // on super. The screen never rotates, so nothing sends them.
    @ObjCMethod("shouldAutorotateToInterfaceOrientation:")
    func shouldAutorotate(toInterfaceOrientation orientation: Int) -> Bool { orientation == Screen.orientation }
    @ObjCMethod("willRotateToInterfaceOrientation:duration:")
    func willRotate(toInterfaceOrientation orientation: Int, duration: Double) {}
    @ObjCMethod("willAnimateRotationToInterfaceOrientation:duration:")
    func willAnimateRotation(toInterfaceOrientation orientation: Int, duration: Double) {}
    @ObjCMethod("didRotateFromInterfaceOrientation:")
    func didRotate(fromInterfaceOrientation orientation: Int) {}
    /// The device's, in the appearance this controller overrides it with,
    /// or its view's, or its parent's.
    @ObjCMethod("traitCollection")
    func traitCollection() -> UITraitCollection { UITraitCollection.device(style: interfaceStyle) }

    var interfaceStyle: Int {
        if state.userInterfaceStyle != 0 { return state.userInterfaceStyle }
        if let view = state.view { return view.interfaceStyle }
        if let parent = state.parent { return UIViewController.wrap(parent).interfaceStyle }
        return 1
    }

    /// Nothing to do here; subclasses override it.
    @ObjCMethod("traitCollectionDidChange:") func traitCollectionDidChange(_ previous: UITraitCollection?) {}

    @ObjCMethod("overrideUserInterfaceStyle") func overrideUserInterfaceStyle() -> Int { state.userInterfaceStyle }
    @ObjCMethod("setOverrideUserInterfaceStyle:")
    func setOverrideUserInterfaceStyle(_ style: Int) {
        let previous = traitCollection()
        state.userInterfaceStyle = style
        if let view = state.view {
            view.announceTraitChange(from: previous)
        } else if previous.traits.style != interfaceStyle {
            sendTraitCollectionDidChange(previous)
        }
    }

    // MARK: Containment

    @ObjCMethod("parentViewController")
    func parentViewController() -> UIViewController? { state.parent.map(UIViewController.wrap) }

    @ObjCMethod("childViewControllers") func childViewControllers() -> NSObject { NSMutableArray.of(state.children) }
    @ObjCMethod("children") func children() -> NSObject { NSMutableArray.of(state.children) }

    /// Adds `child`, sending it -willMoveToParentViewController:. Nil, which
    /// World of Goo 2 passes, adds nothing.
    @ObjCMethod("addChildViewController:")
    func addChild(_ child: UIViewController?) {
        guard let child, child.state.parent != objcObject else { return }
        child.state.parent.map(UIViewController.wrap)?.state.children.removeAll { $0.objcObject == child.objcObject }
        child.sendWillMove(toParent: self)
        state.children.append(child)
        child.state.parent = objcObject
    }

    /// Removes the controller from its parent, sending it
    /// -didMoveToParentViewController: with nil.
    @ObjCMethod("removeFromParentViewController")
    func removeFromParent() {
        guard let parent = state.parent else { return }
        let retained = self
        UIViewController.states[parent].children.removeAll { $0.objcObject == objcObject }
        retained.state.parent = nil
        retained.sendDidMove(toParent: nil)
    }

    @ObjCMethod("willMoveToParentViewController:")
    func willMove(toParent parent: UIViewController?) {
        if parent == nil {
            (state.movingFromParent, state.movingToParent) = (true, false)
        } else {
            (state.movingToParent, state.movingFromParent) = (true, false)
        }
    }

    @ObjCMethod("didMoveToParentViewController:") func didMove(toParent parent: UIViewController?) {}

    @ObjCMethod("isMovingToParentViewController") func isMovingToParentViewController() -> Bool { state.movingToParent }
    @ObjCMethod("isMovingFromParentViewController") func isMovingFromParentViewController() -> Bool { state.movingFromParent }
    @ObjCMethod("isBeingPresented") func isBeingPresented() -> Bool { state.beingPresented }
    /// The coordinator of a transition in progress; transitions here run
    /// without one.
    @ObjCMethod("transitionCoordinator") func transitionCoordinator() -> NSObject? { nil }
    @ObjCMethod("isBeingDismissed") func isBeingDismissed() -> Bool { state.beingDismissed }

    /// The nearest navigation controller at or above the parent.
    @ObjCMethod("navigationController")
    func navigationController() -> UIViewController? {
        var current = state.parent
        while let controller = current {
            let wrapped = UIViewController.wrap(controller)
            if wrapped.is(UINavigationController.self) { return wrapped }
            current = wrapped.state.parent
        }
        return nil
    }

    /// The nearest tab bar controller at or above the parent.
    @ObjCMethod("tabBarController")
    func tabBarController() -> UIViewController? {
        var current = state.parent
        while let controller = current {
            let wrapped = UIViewController.wrap(controller)
            if wrapped.is(UITabBarController.self) { return wrapped }
            current = wrapped.state.parent
        }
        return nil
    }
    @ObjCMethod("popoverPresentationController") func popoverPresentationController() -> NSObject? { nil }
    @ObjCMethod("presentationController") func presentationController() -> NSObject? { nil }
    /// The nearest split view controller among the controller's ancestors.
    @ObjCMethod("splitViewController")
    func splitViewController() -> UIViewController? {
        var current = state.parent
        while let parent = current {
            let controller = UIViewController.wrap(parent)
            if controller.is(UISplitViewController.self) { return controller }
            current = controller.state.parent
        }
        return nil
    }

    @ObjCMethod("shouldAutomaticallyForwardAppearanceMethods") func shouldAutomaticallyForwardAppearanceMethods() -> Bool { true }

    @ObjCMethod("beginAppearanceTransition:animated:")
    func beginAppearanceTransition(_ appearing: Bool, animated: Bool) { _ = beginAppearance(appearing, animated: animated) }

    @ObjCMethod("endAppearanceTransition") func endAppearanceTransition() { finishAppearance() }

    // MARK: Appearance

    /// Begins an appearance transition, if the controller is not already
    /// on its way there, and forwards it to the children in its view.
    func beginAppearance(_ appearing: Bool, animated: Bool) -> Bool {
        let state = state
        if appearing {
            guard state.appearance == .disappeared || state.appearance == .disappearing else { return false }
            state.appearance = .appearing
            state.animated = animated
            sendViewWillAppear(animated)
            // A navigation controller that appears shows its top controller.
            if self.is(UINavigationController.self) {
                let navigation = unsafeCast(to: UINavigationController.self)
                navigation.layoutContent()
                navigation.scheduleTransition(animated: false)
            }
            // A tab bar controller that appears shows its selected controller.
            if self.is(UITabBarController.self) {
                let tabs = unsafeCast(to: UITabBarController.self)
                tabs.layoutContent()
                tabs.scheduleTransition()
            }
        } else {
            guard state.appearance == .appeared || state.appearance == .appearing else { return false }
            state.appearance = .disappearing
            state.animated = animated
            sendViewWillDisappear(animated)
        }
        for child in forwardedChildren { _ = child.beginAppearance(appearing, animated: animated) }
        return true
    }

    /// Ends the transition begun, forwarding it to the children in the
    /// view; then a controller moving to or from a parent is told it has.
    func finishAppearance() {
        let state = state
        switch state.appearance {
        case .appearing:
            state.appearance = .appeared
            sendViewDidAppear(state.animated)
            for child in forwardedChildren where child.state.appearance == .appearing { child.finishAppearance() }
            if state.movingToParent {
                sendDidMove(toParent: parentViewController())
                state.movingToParent = false
            }
            state.beingPresented = false
        case .disappearing:
            state.appearance = .disappeared
            sendViewDidDisappear(state.animated)
            for child in forwardedChildren where child.state.appearance == .disappearing { child.finishAppearance() }
            if state.movingFromParent {
                sendDidMove(toParent: nil)
                state.movingFromParent = false
            }
            state.beingDismissed = false
        default:
            break
        }
    }

    /// The children whose views are in this controller's view.
    private var forwardedChildren: [UIViewController] {
        guard let view = state.view, sendShouldAutomaticallyForwardAppearanceMethods() else { return [] }
        return state.children.filter { child in child.state.view.map { $0.isDescendant(of: view) } ?? false }
    }

    /// The controller's view is entering or leaving a window: the
    /// transition begins now and ends in the next update pass, unless a
    /// container or presentation is running it.
    func viewWillMove(toWindow window: UnsafeMutableRawPointer?) {
        if window != nil, let parent = state.parent, UIViewController.states[parent].appearance == .disappeared { return }
        if beginAppearance(window != nil, animated: false) { Updates.endAppearance(of: self) }
    }

    // MARK: Presentation

    @ObjCMethod("presentedViewController")
    func presentedViewController() -> UIViewController? {
        var current: UnsafeMutableRawPointer? = objcObject
        while let controller = current {
            let state = UIViewController.states[controller]
            if let presented = state.presented { return presented }
            current = state.parent
        }
        return nil
    }

    @ObjCMethod("presentingViewController")
    func presentingViewController() -> UIViewController? {
        var current: UnsafeMutableRawPointer? = objcObject
        while let controller = current {
            let state = UIViewController.states[controller]
            if let presenting = state.presenting { return UIViewController.wrap(presenting) }
            current = state.parent
        }
        return nil
    }

    /// Whether a presentation in `style` covers the presenter, which then
    /// disappears.
    static func coversPresenter(_ style: Int) -> Bool { style == 0 || style == 3 }

    /// The style a presentation takes: automatic (-2) is full screen for
    /// player view controllers, and for every controller in apps built
    /// before the iOS 13 SDK, which had no sheets by default; else a page
    /// sheet.
    var presentationStyle: Int {
        let style = state.modalPresentationStyle
        guard style == -2 else { return style }
        if !ProgramSDK.iOS13 || ObjCRuntime.isKind(objcObject, of: AVPlayerViewController.objCClass.pointer) { return 0 }
        return 1
    }

    /// Presents `controller` from the root of this controller's
    /// containment, loading its view now; the transition runs in the next
    /// update pass.
    @ObjCMethod("presentViewController:animated:completion:")
    func present(_ controller: UIViewController, animated: Bool, completion: ObjCBlock?) {
        var presenter: UIViewController = self
        while let parent = presenter.state.parent, !presenter.state.definesPresentationContext {
            presenter = UIViewController.wrap(parent)
        }
        while let presented = presenter.state.presented { presenter = presented }
        guard controller.state.presenting == nil else {
            uikitFatal("Application tried to present modally a view controller that is already being presented.")
        }
        presenter.state.presented = controller
        controller.state.presenting = presenter.objcObject
        controller.state.beingPresented = true
        _ = controller.loadedView
        Updates.transition {
            Presentations.present(controller, from: presenter, animated: animated)
            completion.map(Blocks.call)
        }
    }

    /// Dismisses the controller this one presented, or else this one.
    @ObjCMethod("dismissViewControllerAnimated:completion:")
    func dismiss(animated: Bool, completion: ObjCBlock?) {
        let target: UIViewController
        if let presented = presentedViewController() {
            target = presented
        } else if presentingViewController() != nil {
            var root: UIViewController = self
            while root.state.presenting == nil, let parent = root.state.parent { root = UIViewController.wrap(parent) }
            target = root
        } else {
            completion.map(Blocks.call)
            return
        }
        target.state.beingDismissed = true
        Updates.transition {
            Presentations.dismiss(target, animated: animated)
            completion.map(Blocks.call)
        }
    }

    @ObjCMethod("showViewController:sender:")
    func show(_ controller: UIViewController, sender: NSObject?) {
        if let navigation = navigationController()?.unsafeCast(to: UINavigationController.self) {
            navigation.push(controller, animated: true)
        } else {
            present(controller, animated: true, completion: nil)
        }
    }

    /// The split view controller's, when there is one: it pushes the
    /// controller onto its primary navigation controller.
    @ObjCMethod("showDetailViewController:sender:")
    func showDetail(_ controller: UIViewController, sender: NSObject?) {
        if let split = splitViewController() {
            split.sendShowDetail(controller, sender: sender)
        } else {
            show(controller, sender: sender)
        }
    }

    /// The view's superview: the controller sits between its view and the
    /// view's superview in the responder chain.
    @ObjCMethod("nextResponder")
    override func nextResponder() -> NSObject? {
        if let superview = state.view?.state.superview { return UIView.wrap(superview) }
        return state.presenting.map { NSObject($0) }
    }
}

/// Whether the app was built with an SDK at least iOS 13's, which brought
/// sheets as the default presentation; true when that can't be told.
enum ProgramSDK {
    nonisolated(unsafe) static let iOS13: Bool = {
        // dyld_program_sdk_at_least takes a dyld_build_version_t, a platform
        // (iOS 2) and a version (13.0.0), in one register.
        typealias AtLeast = @convention(c) (UInt64) -> Bool
        let system = dlopen("libPerrySystem.so", RTLD_NOW | RTLD_NOLOAD)
        guard let atLeast = dlsym(system, "_dyld_program_sdk_at_least") else { return true }
        return unsafeBitCast(atLeast, to: AtLeast.self)(UInt64(2) | UInt64(0x000D_0000) << 32)
    }()
}

/// Modal presentation, run in update passes.
enum Presentations {
    static func present(_ controller: UIViewController, from presenter: UIViewController, animated: Bool) {
        guard let presenterView = presenter.state.view, let window = window(for: presenter) else { return }
        let covers = UIViewController.coversPresenter(controller.presentationStyle)
        if covers { _ = presenter.beginAppearance(false, animated: animated) }
        _ = controller.beginAppearance(true, animated: animated)

        let bounds = window.state.bounds
        let container = UITransitionView.objCClass.object.allocated().initializeView(frame: bounds).unsafeCast(to: UIView.self)
        let view = controller.loadedView
        view.sendSetFrame(covers || controller.presentationStyle == 5 ? bounds : sheetFrame(in: window))
        container.setAutoresizingMask(18)
        if covers || controller.presentationStyle == 5 { view.setAutoresizingMask(18) }
        container.addSubview(view)
        window.addSubview(container)
        if covers, let superview = presenterView.superview() {
            presenter.state.coveredSuperview = superview
            presenterView.removeFromSuperview()
        }
        window.layoutIfNeeded()
        // Animated, it slides up from below the screen, as Darwin's modal
        // presentations do.
        if animated, ViewAnimations.enabled {
            let frame = view.state.frame
            view.sendSetFrame(CGRect(x: frame.minX, y: bounds.height, width: frame.width, height: frame.height))
            slide { view.sendSetFrame(frame) }
        }
        controller.finishAppearance()
        if covers { presenter.finishAppearance() }
    }

    /// How long a presentation slides, and how: Darwin's.
    static let slideDuration = 0.35

    /// Runs `changes` so that the views' frames they set slide there.
    static func slide(_ changes: () -> Void) {
        ViewAnimations.contexts.append(ViewAnimations.Context(duration: slideDuration, delay: 0, curve: 2))
        changes()
        ViewAnimations.contexts.removeLast()
    }

    /// The window to present in: the presenter's view's, or, when an app
    /// has taken that view out of its window before the presentation's
    /// update pass, the window whose root view controller the presenter or
    /// one of its parents is, else the key window. UIKit presents at once,
    /// while the presenter's view is still in the window.
    static func window(for presenter: UIViewController) -> UIWindow? {
        if let window = presenter.state.view?.window() { return window.unsafeCast(to: UIWindow.self) }
        var controller: UIViewController? = presenter
        while let current = controller {
            if let window = Windows.visible.first(where: { $0.windowState.rootViewController?.objcObject == current.objcObject }) {
                return window
            }
            controller = current.state.parent.map(UIViewController.wrap)
        }
        return Windows.key.map { UIWindow(objcObject: $0, ownership: .retain) }
    }

    static func dismiss(_ controller: UIViewController, animated: Bool) {
        guard let presenterObject = controller.state.presenting else { return }
        let presenter = UIViewController.wrap(presenterObject)
        if let presented = controller.state.presented { dismiss(presented, animated: false) }
        // Whether the presenter was covered, and so reappears: by the style,
        // as its view may have left its superview before it was presented.
        let covers = UIViewController.coversPresenter(controller.presentationStyle)
        _ = controller.beginAppearance(false, animated: animated)
        if covers { _ = presenter.beginAppearance(true, animated: animated) }
        if let superview = presenter.state.coveredSuperview, let view = presenter.state.view {
            superview.addSubview(view)
            presenter.state.coveredSuperview = nil
        }
        let container = controller.state.view?.superview()
        // Animated, it slides down off the screen first, and goes once it
        // has; the presenter is back underneath it at once.
        if animated, ViewAnimations.enabled, let view = controller.state.view, let container {
            let frame = view.state.frame
            slide { view.sendSetFrame(CGRect(x: frame.minX, y: container.state.bounds.height, width: frame.width, height: frame.height)) }
            Deferred.run(after: slideDuration) {
                view.removeFromSuperview()
                container.removeFromSuperview()
            }
        } else {
            controller.state.view?.removeFromSuperview()
            container?.removeFromSuperview()
        }
        // Unlinked first: the presenter's -viewDidAppear: may present again.
        presenter.state.presented = nil
        controller.state.presenting = nil
        controller.finishAppearance()
        if covers { presenter.finishAppearance() }
    }

    /// A page sheet: below the top safe area, inset a little.
    static func sheetFrame(in window: UIWindow) -> CGRect {
        let bounds = window.state.bounds
        let top = window.safeAreaInsets().top + 10
        return CGRect(x: 0, y: top, width: bounds.width, height: bounds.height - top)
    }
}

/// Calling blocks UIKit is handed.
enum Blocks {
    /// A block taking no arguments.
    static func call(_ block: ObjCBlock) {
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer) -> Void
        block.function(as: Invoke.self)(block.object)
    }

    /// A block taking one Boolean, such as an animation's completion.
    static func call(_ block: ObjCBlock, _ value: Bool) {
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, Bool) -> Void
        block.function(as: Invoke.self)(block.object, value)
    }
}

/// UIViewController's messages, sent so subclasses' overrides run.
extension NSObject {
    @ObjCMethod("initWithNibName:bundle:")
    func initializeViewController(nibName: String?, bundle: NSObject?) -> NSObject

    @ObjCMethod("view") func sendView() -> UIView
    @ObjCMethod("loadView") func sendLoadView()
    @ObjCMethod("viewDidLoad") func sendViewDidLoad()
    @ObjCMethod("viewWillAppear:") func sendViewWillAppear(_ animated: Bool)
    @ObjCMethod("viewDidAppear:") func sendViewDidAppear(_ animated: Bool)
    @ObjCMethod("viewWillDisappear:") func sendViewWillDisappear(_ animated: Bool)
    @ObjCMethod("viewDidDisappear:") func sendViewDidDisappear(_ animated: Bool)
    @ObjCMethod("viewWillLayoutSubviews") func sendViewWillLayoutSubviews()
    @ObjCMethod("viewDidLayoutSubviews") func sendViewDidLayoutSubviews()
    @ObjCMethod("willMoveToParentViewController:") func sendWillMove(toParent parent: UIViewController?)
    @ObjCMethod("didMoveToParentViewController:") func sendDidMove(toParent parent: UIViewController?)
    @ObjCMethod("showDetailViewController:sender:") func sendShowDetail(_ controller: UIViewController, sender: NSObject?)
    @ObjCMethod("shouldAutomaticallyForwardAppearanceMethods") func sendShouldAutomaticallyForwardAppearanceMethods() -> Bool
    @ObjCMethod("setEditing:animated:") func sendSetEditing(_ editing: Bool, animated: Bool)
}

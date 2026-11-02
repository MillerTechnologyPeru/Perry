import CPerryGeometry
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
    var title: String?
    var nibName: String?
    /// The parent, which retains this controller; not retained.
    var parent: UnsafeMutableRawPointer?
    var children: [UIViewController] = []
    var navigationItem: UINavigationItem?
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
    var preferredContentSize = CGSize.zero
    var editing = false
    var restorationIdentifier: String?
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
        return self
    }

    @ObjCMethod("initWithCoder:")
    func initialize(coder: NSObject?) -> Self { self }

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

    /// The view, loaded on first use.
    @ObjCMethod("view")
    func view() -> UIView? {
        if state.view == nil {
            sendLoadView()
            guard state.view != nil else {
                uikitFatal("-loadView did not set the view controller's view")
            }
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

    /// A plain view the size of the screen.
    @ObjCMethod("loadView")
    func loadView() {
        let view = UIView.objCClass.object.allocated().initializeView(frame: Screen.bounds).unsafeCast(to: UIView.self)
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
    }

    @ObjCMethod("nibName") func nibName() -> String? { state.nibName }
    @ObjCMethod("nibBundle") func nibBundle() -> NSObject? { nil }
    @ObjCMethod("storyboard") func storyboard() -> NSObject? { nil }

    /// Made on first use, titled with the controller's title.
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
    @ObjCMethod("setNeedsUpdateOfHomeIndicatorAutoHidden") func setNeedsUpdateOfHomeIndicatorAutoHidden() {}
    @ObjCMethod("supportedInterfaceOrientations") func supportedInterfaceOrientations() -> UInt { 2 }
    @ObjCMethod("shouldAutorotate") func shouldAutorotate() -> Bool { true }
    @ObjCMethod("preferredInterfaceOrientationForPresentation") func preferredInterfaceOrientationForPresentation() -> Int { 1 }
    @ObjCMethod("traitCollection") func traitCollection() -> NSObject? { nil }

    // MARK: Containment

    @ObjCMethod("parentViewController")
    func parentViewController() -> UIViewController? { state.parent.map(UIViewController.wrap) }

    @ObjCMethod("childViewControllers") func childViewControllers() -> NSObject { NSMutableArray.of(state.children) }
    @ObjCMethod("children") func children() -> NSObject { NSMutableArray.of(state.children) }

    /// Adds `child`, sending it -willMoveToParentViewController:.
    @ObjCMethod("addChildViewController:")
    func addChild(_ child: UIViewController) {
        if child.state.parent == objcObject { return }
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

    @ObjCMethod("tabBarController") func tabBarController() -> UIViewController? { nil }
    @ObjCMethod("splitViewController") func splitViewController() -> UIViewController? { nil }

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

    @ObjCMethod("showDetailViewController:sender:")
    func showDetail(_ controller: UIViewController, sender: NSObject?) { show(controller, sender: sender) }

    /// The view's superview: the controller sits between its view and the
    /// view's superview in the responder chain.
    @ObjCMethod("nextResponder")
    override func nextResponder() -> NSObject? {
        if let superview = state.view?.state.superview { return UIView.wrap(superview) }
        return state.presenting.map { NSObject($0) }
    }
}

/// Modal presentation, run in update passes.
enum Presentations {
    static func present(_ controller: UIViewController, from presenter: UIViewController, animated: Bool) {
        guard let presenterView = presenter.state.view, let window = presenterView.window()?.unsafeCast(to: UIWindow.self) else { return }
        let covers = UIViewController.coversPresenter(controller.state.modalPresentationStyle)
        if covers { _ = presenter.beginAppearance(false, animated: animated) }
        _ = controller.beginAppearance(true, animated: animated)

        let bounds = window.state.bounds
        let container = UITransitionView.objCClass.object.allocated().initializeView(frame: bounds).unsafeCast(to: UIView.self)
        let view = controller.loadedView
        view.sendSetFrame(covers || controller.state.modalPresentationStyle == 5 ? bounds : sheetFrame(in: window))
        container.addSubview(view)
        window.addSubview(container)
        if covers, let superview = presenterView.superview() {
            presenter.state.coveredSuperview = superview
            presenterView.removeFromSuperview()
        }
        window.layoutIfNeeded()
        controller.finishAppearance()
        if covers { presenter.finishAppearance() }
    }

    static func dismiss(_ controller: UIViewController, animated: Bool) {
        guard let presenterObject = controller.state.presenting else { return }
        let presenter = UIViewController.wrap(presenterObject)
        if let presented = controller.state.presented { dismiss(presented, animated: false) }
        let covers = presenter.state.coveredSuperview != nil
        _ = controller.beginAppearance(false, animated: animated)
        if covers { _ = presenter.beginAppearance(true, animated: animated) }
        if let superview = presenter.state.coveredSuperview, let view = presenter.state.view {
            superview.addSubview(view)
            presenter.state.coveredSuperview = nil
        }
        let container = controller.state.view?.superview()
        controller.state.view?.removeFromSuperview()
        container?.removeFromSuperview()
        if covers { presenter.finishAppearance() }
        controller.finishAppearance()
        presenter.state.presented = nil
        controller.state.presenting = nil
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
    @ObjCMethod("shouldAutomaticallyForwardAppearanceMethods") func sendShouldAutomaticallyForwardAppearanceMethods() -> Bool
    @ObjCMethod("setEditing:animated:") func sendSetEditing(_ editing: Bool, animated: Bool)
}

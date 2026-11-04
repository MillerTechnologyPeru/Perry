import CPerryGeometry
import PerryObjCInterop

// UIPageViewController: one page, a view controller, shown at a time,
// filling the view. -setViewControllers:direction:animated:completion:
// shows another, in the next update pass, with appearance callbacks; its
// completion block runs once it shows. There is no swiping between pages:
// apps that turn them from their own controls do so as on Darwin.

final class PageViewControllerState: ObjectState {
    var viewControllers: [UIViewController] = []
    /// The page whose view is shown.
    var displayed: UIViewController?
    /// Unretained, as Darwin's are weak.
    var dataSource: UnsafeMutableRawPointer?
    var delegate: UnsafeMutableRawPointer?
    /// UIPageViewControllerTransitionStyle: page curl 0, scroll 1.
    var transitionStyle = 1
    /// UIPageViewControllerNavigationOrientation: horizontal 0, vertical 1.
    var orientation = 0
    var transitionScheduled = false
    var completions: [ObjCBlock] = []
}

@ObjCClass("UIPageViewController")
open class UIPageViewController: UIViewController {
    static let pageStates = StateTable<PageViewControllerState>()
    var pages: PageViewControllerState { UIPageViewController.pageStates[objcObject] }

    @ObjCMethod("dealloc")
    override func dealloc() {
        UIPageViewController.pageStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCMethod("initWithTransitionStyle:navigationOrientation:options:")
    func initialize(transitionStyle: Int, navigationOrientation: Int, options: NSObject?) -> Self {
        _ = initialize(nibName: nil, bundle: nil)
        pages.transitionStyle = transitionStyle
        pages.orientation = navigationOrientation
        return self
    }

    @ObjCMethod("transitionStyle") func transitionStyle() -> Int { pages.transitionStyle }
    @ObjCMethod("navigationOrientation") func navigationOrientation() -> Int { pages.orientation }
    /// UIPageViewControllerSpineLocation: none 0 for scrolling, min 1 for curling.
    @ObjCMethod("spineLocation") func spineLocation() -> Int { pages.transitionStyle == 1 ? 0 : 1 }
    @ObjCMethod("isDoubleSided") func isDoubleSided() -> Bool { false }
    @ObjCMethod("setDoubleSided:") func setDoubleSided(_ doubleSided: Bool) {}
    @ObjCMethod("gestureRecognizers") func gestureRecognizers() -> NSObject { NSMutableArray.of([]) }

    @ObjCMethod("dataSource") func dataSource() -> NSObject? { pages.dataSource.map { NSObject($0) } }
    @ObjCMethod("setDataSource:") func setDataSource(_ dataSource: NSObject?) { pages.dataSource = dataSource?.objcObject }
    @ObjCMethod("delegate") func delegate() -> NSObject? { pages.delegate.map { NSObject($0) } }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { pages.delegate = delegate?.objcObject }

    @ObjCMethod("viewControllers")
    func viewControllers() -> NSObject? { pages.viewControllers.isEmpty ? nil : NSMutableArray.of(pages.viewControllers) }

    /// The pages to show, one for scrolling; UIPageViewControllerNavigationDirection
    /// (forward 0, reverse 1) only says which way they would slide in.
    @ObjCMethod("setViewControllers:direction:animated:completion:")
    func setViewControllers(_ controllers: NSArray?, direction: Int, animated: Bool, completion: ObjCBlock?) {
        let new = controllers?.elements.map { $0.unsafeCast(to: UIViewController.self) } ?? []
        let old = pages.viewControllers
        for controller in old where !new.contains(where: { $0.objcObject == controller.objcObject }) {
            controller.sendWillMove(toParent: nil)
            state.children.removeAll { $0.objcObject == controller.objcObject }
            controller.state.parent = nil
            controller.sendDidMove(toParent: nil)
        }
        for controller in new where !old.contains(where: { $0.objcObject == controller.objcObject }) {
            controller.sendWillMove(toParent: self)
            state.children.append(controller)
            controller.state.parent = objcObject
            controller.sendDidMove(toParent: self)
        }
        pages.viewControllers = new
        if let completion { pages.completions.append(completion) }
        scheduleTransition()
    }

    // MARK: Showing the page

    func scheduleTransition() {
        guard !pages.transitionScheduled else { return }
        pages.transitionScheduled = true
        Updates.transition { [self] in
            pages.transitionScheduled = false
            runTransition()
        }
    }

    /// Shows the first page in place of the one shown, with appearance
    /// callbacks when the page view controller is on screen; then the
    /// completion blocks hear it finished.
    func runTransition() {
        guard let view = state.view else { return }
        let page = pages.viewControllers.first
        let from = pages.displayed
        if from?.objcObject != page?.objcObject {
            let onScreen = view.windowObject != nil && (state.appearance == .appeared || state.appearance == .appearing)
            if onScreen {
                _ = from?.beginAppearance(false, animated: false)
                _ = page?.beginAppearance(true, animated: false)
            }
            from?.state.view?.removeFromSuperview()
            if let page {
                let pageView = page.loadedView
                pageView.sendSetFrame(view.state.bounds)
                pageView.setAutoresizingMask(18)
                view.addSubview(pageView)
            }
            pages.displayed = page
            if onScreen {
                from?.finishAppearance()
                page?.finishAppearance()
            }
        }
        let completions = pages.completions
        pages.completions = []
        for block in completions { Blocks.call(block, true) }
    }

    /// Once the view loads, the page set before shows in it.
    @ObjCMethod("viewDidLoad")
    override func viewDidLoad() {
        super.viewDidLoad()
        if !pages.viewControllers.isEmpty { scheduleTransition() }
    }

    @ObjCMethod("viewWillLayoutSubviews")
    override func viewWillLayoutSubviews() {
        guard let view = state.view else { return }
        pages.displayed?.state.view?.sendSetFrame(view.state.bounds)
    }
}

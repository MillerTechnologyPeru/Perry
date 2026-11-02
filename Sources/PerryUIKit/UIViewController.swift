import CPerryGeometry
import PerryObjCInterop

// UIViewController: owns a view, which it loads the first time it is asked
// for, through -loadView then -viewDidLoad.

final class ViewControllerState: ObjectState {
    var view: UIView?
    var title: String?
    var nibName: String?
}

@ObjCClass("UIViewController")
open class UIViewController: UIResponder {
    static let states = StateTable<ViewControllerState>()
    var state: ViewControllerState { UIViewController.states[objcObject] }

    /// -init is -initWithNibName:bundle: with neither, sent so a
    /// subclass's initializer runs.
    @ObjCMethod("init")
    func initialize() -> NSObject { initializeViewController(nibName: nil, bundle: nil) }

    @ObjCMethod("initWithNibName:bundle:")
    func initialize(nibName: String?, bundle: NSObject?) -> Self {
        state.nibName = nibName
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        if let view = state.view, view.state.viewController == objcObject { view.state.viewController = nil }
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

    @ObjCMethod("setView:")
    func setView(_ view: UIView?) {
        if let old = state.view, old.state.viewController == objcObject { old.state.viewController = nil }
        state.view = view
        view?.state.viewController = objcObject
    }

    @ObjCMethod("viewIfLoaded") func viewIfLoaded() -> UIView? { state.view }
    @ObjCMethod("isViewLoaded") func isViewLoaded() -> Bool { state.view != nil }

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

    @ObjCMethod("title") func title() -> String? { state.title }
    @ObjCMethod("setTitle:") func setTitle(_ title: String?) { state.title = title }
    @ObjCMethod("nibName") func nibName() -> String? { state.nibName }
    @ObjCMethod("parentViewController") func parentViewController() -> UIViewController? { nil }
    @ObjCMethod("presentedViewController") func presentedViewController() -> UIViewController? { nil }

    /// The view's superview: the controller sits between its view and the
    /// view's superview in the responder chain.
    @ObjCMethod("nextResponder")
    override func nextResponder() -> NSObject? { state.view?.state.superview.map(UIView.wrap) }
}

/// UIViewController's messages, sent so subclasses' overrides run.
extension NSObject {
    @ObjCMethod("initWithNibName:bundle:")
    func initializeViewController(nibName: String?, bundle: NSObject?) -> NSObject

    @ObjCMethod("view") func sendView() -> UIView
    @ObjCMethod("loadView") func sendLoadView()
    @ObjCMethod("viewDidLoad") func sendViewDidLoad()
}

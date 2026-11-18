import CPerryGeometry
import PerryObjCInterop

// UIPresentationController: what a presentation is made of, the controllers
// presented and presenting and the delegate. A presentation here is the
// view controller's own (a sheet or a full screen cover); a subclass of
// this class, such as a pod's form sheet, is kept and may be built, and its
// overrides are not called by the presentation.

@ObjCClass("UIPresentationController")
open class UIPresentationController: NSObject {
    /// Retained; the presenting controller and the delegate are not.
    var presented: NSObject?
    var presenting: NSObject?
    var presentationDelegate: NSObject?

    @ObjCMethod("init") public required override init() { super.init() }

    deinit { if let presented { ObjCRuntime.release(presented.objcObject) } }

    @ObjCMethod("initWithPresentedViewController:presentingViewController:")
    public required init(presentedViewController: NSObject?, presentingViewController: NSObject?) {
        super.init()
        presented = ObjCRuntime.retain(presentedViewController?.objcObject).map { NSObject($0) }
        presenting = presentingViewController
    }

    @ObjCMethod("presentedViewController") func presentedViewController() -> NSObject? { presented }
    @ObjCMethod("presentingViewController") func presentingViewController() -> NSObject? { presenting }
    @ObjCMethod("delegate") func delegate() -> NSObject? { presentationDelegate }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { presentationDelegate = delegate }
    @ObjCMethod("containerView") func containerView() -> NSObject? { nil }
    @ObjCMethod("presentedView") func presentedView() -> NSObject? {
        presented?.sendPresentedControllerView()
    }
    @ObjCMethod("shouldPresentInFullscreen") func shouldPresentInFullscreen() -> Bool { true }
    @ObjCMethod("shouldRemovePresentersView") func shouldRemovePresentersView() -> Bool { false }
    @ObjCMethod("adaptivePresentationStyle") func adaptivePresentationStyle() -> Int { 0 }
    @ObjCMethod("presentationStyle") func presentationStyle() -> Int { 0 }
    @ObjCMethod("frameOfPresentedViewInContainerView") func frameOfPresentedViewInContainerView() -> CGRect { .zero }
    @ObjCMethod("presentationTransitionWillBegin") func presentationTransitionWillBegin() {}
    @ObjCMethod("presentationTransitionDidEnd:") func presentationTransitionDidEnd(_ completed: Bool) {}
    @ObjCMethod("dismissalTransitionWillBegin") func dismissalTransitionWillBegin() {}
    @ObjCMethod("dismissalTransitionDidEnd:") func dismissalTransitionDidEnd(_ completed: Bool) {}
    @ObjCMethod("containerViewWillLayoutSubviews") func containerViewWillLayoutSubviews() {}
    @ObjCMethod("containerViewDidLayoutSubviews") func containerViewDidLayoutSubviews() {}
}

extension NSObject {
    @ObjCMethod("view") func sendPresentedControllerView() -> NSObject?
}

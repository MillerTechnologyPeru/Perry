import CPerryGeometry
import PerryObjCInterop

// MARK: - _UIConstraintBasedLayoutHostingView

final class ConstraintHostingState: ObjectState {
    var hostedView: UIView?
}

/// A view that holds one view filling its bounds, and sizes as it does.
/// SwiftUI's host for a UIViewRepresentable's view is one.
@ObjCClass("_UIConstraintBasedLayoutHostingView")
open class UIConstraintBasedLayoutHostingView: UIView {
    static let hostingStates = StateTable<ConstraintHostingState>()
    var hosting: ConstraintHostingState { UIConstraintBasedLayoutHostingView.hostingStates[objcObject] }

    @ObjCMethod("dealloc")
    override func dealloc() {
        UIConstraintBasedLayoutHostingView.hostingStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCClassMethod("requiresConstraintBasedLayout") static func requiresConstraintBasedLayout() -> Bool { false }

    @ObjCMethod("initWithHostedView:")
    func initialize(hostedView: UIView?) -> Self {
        _ = initialize(frame: .zero)
        setHostedView(hostedView)
        return self
    }

    @ObjCMethod("hostedView") func hostedView() -> UIView? { hosting.hostedView }

    @ObjCMethod("setHostedView:")
    func setHostedView(_ view: UIView?) {
        let hosting = hosting
        if let old = hosting.hostedView, old.objcObject != view?.objcObject {
            hosting.hostedView = nil
            old.removeFromSuperview()
        }
        hosting.hostedView = view
        if let view {
            if view.state.superview != objcObject { addSubview(view) }
            view.setFrame(state.bounds)
        }
        setNeedsLayout()
    }

    @ObjCMethod("willRemoveSubview:")
    override func willRemoveSubview(_ subview: UIView) {
        if hosting.hostedView?.objcObject == subview.objcObject { hosting.hostedView = nil }
    }

    @ObjCMethod("layoutSubviews")
    override func layoutSubviews() {
        super.layoutSubviews()
        hosting.hostedView?.setFrame(state.bounds)
    }

    @ObjCMethod("sizeThatFits:")
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        hosting.hostedView?.sendSizeThatFits(size) ?? size
    }

    /// The hosted view's size for `size`, keeping the axes in `fixedAxes`
    /// (1 horizontal, 2 vertical) as given.
    @ObjCMethod("_layoutSizeThatFits:fixedAxes:")
    func layoutSizeThatFits(_ size: CGSize, fixedAxes: UInt64) -> CGSize {
        var fitting = sizeThatFits(size)
        if fixedAxes & 1 != 0 { fitting.width = size.width }
        if fixedAxes & 2 != 0 { fitting.height = size.height }
        return fitting
    }

    @ObjCMethod("_setHostsLayoutEngine:") func setHostsLayoutEngine(_ hosts: Bool) {}
    @ObjCMethod("_priorityForEngineHostConstraints") func priorityForEngineHostConstraints() -> Float { 1000 }
    @ObjCMethod("_layoutMetricsInvalidatedForHostedView") func layoutMetricsInvalidatedForHostedView() { setNeedsLayout() }
    @ObjCMethod("_intrinsicContentSizeInvalidatedForChildView:") func intrinsicContentSizeInvalidated(forChildView view: UIView?) { setNeedsLayout() }
    @ObjCMethod("_layoutHeightDependsOnWidth") func layoutHeightDependsOnWidth() -> Bool { false }
    @ObjCMethod("_setFrameWithAlignmentRect:") func setFrame(alignmentRect rect: CGRect) { setFrame(rect) }
    @ObjCMethod("constraintsDidChangeInEngine:") func constraintsDidChange(inEngine engine: NSObject?) {}
    @ObjCMethod("_scheduleUpdateConstraintsPassAsEngineHostNeedingLayout:") func scheduleUpdateConstraintsPass(needingLayout: Bool) {}
}

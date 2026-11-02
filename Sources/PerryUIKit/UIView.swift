import CPerryGeometry
import PerryObjCInterop

// UIView without drawing: geometry, the view hierarchy with UIKit's
// callbacks, coordinate conversion, layout and the responder chain.

final class ViewState: ObjectState {
    /// The frame is derived from the center and the bounds' size.
    var center = CGPoint.zero
    var bounds = CGRect.zero
    var hidden = false
    var alpha: CGFloat = 1
    var tag = 0
    var userInteractionEnabled = true
    var backgroundColor: NSObject?
    var accessibilityIdentifier: String?
    var needsLayout = true
    /// The superview, which retains this view; not retained.
    var superview: UnsafeMutableRawPointer?
    var subviews: [UIView] = []
    /// The view controller whose view this is; not retained.
    var viewController: UnsafeMutableRawPointer?

    var frame: CGRect {
        CGRect(x: center.x - bounds.size.width / 2, y: center.y - bounds.size.height / 2,
               width: bounds.size.width, height: bounds.size.height)
    }
}

/// The default size of views a controller makes for itself, and of
/// windows: an iPhone's screen, in points.
enum Screen {
    static let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
}

@ObjCClass("UIView")
open class UIView: UIResponder {
    static let states = StateTable<ViewState>()
    var state: ViewState { UIView.states[objcObject] }

    static func wrap(_ object: UnsafeMutableRawPointer) -> UIView { UIView(objcObject: object, ownership: .retain) }

    // MARK: Creating

    /// -init is -initWithFrame: with an empty frame, sent so a subclass's
    /// initializer runs.
    @ObjCMethod("init")
    func initialize() -> NSObject { initializeView(frame: .zero) }

    @ObjCMethod("initWithFrame:")
    func initialize(frame: CGRect) -> Self {
        setFrame(frame)
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        for subview in state.subviews { subview.state.superview = nil }
        UIView.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIView.objCClass.pointer)
    }

    // MARK: Geometry

    @ObjCMethod("frame") func frame() -> CGRect { state.frame }

    @ObjCMethod("setFrame:")
    func setFrame(_ frame: CGRect) {
        state.bounds.size = frame.size
        state.center = CGPoint(x: frame.origin.x + frame.size.width / 2, y: frame.origin.y + frame.size.height / 2)
        state.needsLayout = true
    }

    @ObjCMethod("bounds") func bounds() -> CGRect { state.bounds }

    /// Keeps the center, so the frame grows or shrinks around it.
    @ObjCMethod("setBounds:")
    func setBounds(_ bounds: CGRect) {
        state.bounds = bounds
        state.needsLayout = true
    }

    @ObjCMethod("center") func center() -> CGPoint { state.center }
    @ObjCMethod("setCenter:") func setCenter(_ center: CGPoint) { state.center = center }

    // MARK: Appearance

    @ObjCMethod("isHidden") func isHidden() -> Bool { state.hidden }
    @ObjCMethod("setHidden:") func setHidden(_ hidden: Bool) { state.hidden = hidden }
    @ObjCMethod("alpha") func alpha() -> CGFloat { state.alpha }
    @ObjCMethod("setAlpha:") func setAlpha(_ alpha: CGFloat) { state.alpha = alpha }
    @ObjCMethod("backgroundColor") func backgroundColor() -> NSObject? { state.backgroundColor }
    @ObjCMethod("setBackgroundColor:") func setBackgroundColor(_ color: NSObject?) { state.backgroundColor = color }
    @ObjCMethod("tag") func tag() -> Int { state.tag }
    @ObjCMethod("setTag:") func setTag(_ tag: Int) { state.tag = tag }
    @ObjCMethod("isUserInteractionEnabled") func isUserInteractionEnabled() -> Bool { state.userInteractionEnabled }
    @ObjCMethod("setUserInteractionEnabled:") func setUserInteractionEnabled(_ enabled: Bool) {
        state.userInteractionEnabled = enabled
    }
    @ObjCMethod("accessibilityIdentifier") func accessibilityIdentifier() -> String? { state.accessibilityIdentifier }
    @ObjCMethod("setAccessibilityIdentifier:") func setAccessibilityIdentifier(_ identifier: String?) {
        state.accessibilityIdentifier = identifier
    }

    // MARK: Hierarchy

    @ObjCMethod("superview") func superview() -> UIView? { state.superview.map(UIView.wrap) }
    @ObjCMethod("subviews") func subviews() -> NSObject { NSMutableArray.of(state.subviews) }

    /// The window the view is in: the nearest UIWindow at or above it.
    @ObjCMethod("window")
    func window() -> UIView? { windowObject.map(UIView.wrap) }

    var windowObject: UnsafeMutableRawPointer? {
        var current: UnsafeMutableRawPointer? = objcObject
        while let view = current {
            if UIView.wrap(view).is(UIWindow.self) { return view }
            current = UIView.states[view].superview
        }
        return nil
    }

    @ObjCMethod("addSubview:")
    func addSubview(_ view: UIView) { insert(view, at: state.subviews.count) }

    @ObjCMethod("insertSubview:atIndex:")
    func insertSubview(_ view: UIView, at index: Int) { insert(view, at: index) }

    @ObjCMethod("insertSubview:belowSubview:")
    func insertSubview(_ view: UIView, below sibling: UIView?) {
        insert(view, at: sibling.flatMap(index(of:)) ?? 0)
    }

    @ObjCMethod("insertSubview:aboveSubview:")
    func insertSubview(_ view: UIView, above sibling: UIView?) {
        insert(view, at: sibling.flatMap(index(of:)).map { $0 + 1 } ?? state.subviews.count)
    }

    @ObjCMethod("bringSubviewToFront:")
    func bringSubviewToFront(_ view: UIView) {
        guard let index = index(of: view) else { return }
        state.subviews.append(state.subviews.remove(at: index))
    }

    @ObjCMethod("sendSubviewToBack:")
    func sendSubviewToBack(_ view: UIView) {
        guard let index = index(of: view) else { return }
        state.subviews.insert(state.subviews.remove(at: index), at: 0)
    }

    @ObjCMethod("removeFromSuperview")
    func removeFromSuperview() {
        guard let superviewObject = state.superview else { return }
        let superview = UIView.wrap(superviewObject)
        let window = windowObject
        superview.sendWillRemoveSubview(self)
        sendWillMoveToSuperview(nil)
        if window != nil { UIView.willMove(self, toWindow: nil) }
        superview.state.subviews.removeAll { $0.objcObject == objcObject }
        state.superview = nil
        if window != nil { UIView.didMoveToWindow(self) }
        sendDidMoveToSuperview()
    }

    /// Adds or moves `view` here, with UIKit's callbacks: the superview
    /// move, then the window move down the subtree, then the superview
    /// notified.
    private func insert(_ view: UIView, at index: Int) {
        guard view.objcObject != objcObject else { return }
        if view.state.superview == objcObject {
            guard let current = self.index(of: view) else { return }
            let moved = state.subviews.remove(at: current)
            state.subviews.insert(moved, at: min(max(index, 0), state.subviews.count))
            return
        }
        let oldSuperview = view.state.superview.map(UIView.wrap)
        let oldWindow = view.windowObject, newWindow = windowObject
        oldSuperview?.sendWillRemoveSubview(view)
        view.sendWillMoveToSuperview(self)
        if oldWindow != newWindow { UIView.willMove(view, toWindow: newWindow) }
        oldSuperview?.state.subviews.removeAll { $0.objcObject == view.objcObject }
        state.subviews.insert(view, at: min(max(index, 0), state.subviews.count))
        view.state.superview = objcObject
        if oldWindow != newWindow { UIView.didMoveToWindow(view) }
        view.sendDidMoveToSuperview()
        sendDidAddSubview(view)
        setNeedsLayout()
    }

    private func index(of view: UIView) -> Int? {
        state.subviews.firstIndex { $0.objcObject == view.objcObject }
    }

    /// -willMoveToWindow: to a subtree, each view before its subviews.
    static func willMove(_ view: UIView, toWindow window: UnsafeMutableRawPointer?) {
        view.sendWillMoveToWindow(window.map(UIView.wrap))
        for subview in view.state.subviews { willMove(subview, toWindow: window) }
    }

    /// -didMoveToWindow to a subtree, each view after its subviews.
    static func didMoveToWindow(_ view: UIView) {
        for subview in view.state.subviews { didMoveToWindow(subview) }
        view.sendDidMoveToWindow()
    }

    @ObjCMethod("viewWithTag:")
    func viewWithTag(_ tag: Int) -> UIView? {
        if state.tag == tag { return self }
        for subview in state.subviews {
            if let found = subview.viewWithTag(tag) { return found }
        }
        return nil
    }

    @ObjCMethod("isDescendantOfView:")
    func isDescendant(of view: UIView?) -> Bool {
        guard let view else { return false }
        var current: UnsafeMutableRawPointer? = objcObject
        while let candidate = current {
            if candidate == view.objcObject { return true }
            current = UIView.states[candidate].superview
        }
        return false
    }

    // The hierarchy's callbacks, for subclasses.
    @ObjCMethod("willMoveToSuperview:") func willMoveToSuperview(_ superview: UIView?) {}
    @ObjCMethod("didMoveToSuperview") func didMoveToSuperview() {}
    @ObjCMethod("willMoveToWindow:") func willMoveToWindow(_ window: UIView?) {}
    @ObjCMethod("didMoveToWindow") func didMoveToWindow() {}
    @ObjCMethod("didAddSubview:") func didAddSubview(_ subview: UIView) {}
    @ObjCMethod("willRemoveSubview:") func willRemoveSubview(_ subview: UIView) {}

    // MARK: Coordinates

    /// A point in this view's bounds, in its window's base coordinates.
    private func toBase(_ point: CGPoint) -> CGPoint {
        var point = point
        var current: UnsafeMutableRawPointer? = objcObject
        while let view = current {
            let state = UIView.states[view]
            guard let superview = state.superview else { break }
            let frame = state.frame
            point = CGPoint(x: point.x - state.bounds.origin.x + frame.origin.x,
                            y: point.y - state.bounds.origin.y + frame.origin.y)
            current = superview
        }
        return point
    }

    private func fromBase(_ point: CGPoint) -> CGPoint {
        let origin = toBase(.zero)
        return CGPoint(x: point.x - origin.x, y: point.y - origin.y)
    }

    @ObjCMethod("convertPoint:toView:")
    func convert(_ point: CGPoint, to view: UIView?) -> CGPoint {
        let base = toBase(point)
        return view?.fromBase(base) ?? base
    }

    @ObjCMethod("convertPoint:fromView:")
    func convert(_ point: CGPoint, from view: UIView?) -> CGPoint {
        fromBase(view?.toBase(point) ?? point)
    }

    @ObjCMethod("convertRect:toView:")
    func convert(_ rect: CGRect, to view: UIView?) -> CGRect {
        CGRect(origin: convert(rect.origin, to: view), size: rect.size)
    }

    @ObjCMethod("convertRect:fromView:")
    func convert(_ rect: CGRect, from view: UIView?) -> CGRect {
        CGRect(origin: convert(rect.origin, from: view), size: rect.size)
    }

    // MARK: Layout

    @ObjCMethod("setNeedsLayout") func setNeedsLayout() { state.needsLayout = true }

    /// Lays out the subtree's views that need it, each before its subviews.
    @ObjCMethod("layoutIfNeeded")
    func layoutIfNeeded() {
        if state.needsLayout {
            state.needsLayout = false
            sendLayoutSubviews()
        }
        for subview in state.subviews { subview.layoutIfNeeded() }
    }

    @ObjCMethod("layoutSubviews") func layoutSubviews() {}

    /// A plain view fits its current size.
    @ObjCMethod("sizeThatFits:") func sizeThatFits(_ size: CGSize) -> CGSize { state.bounds.size }

    @ObjCMethod("sizeToFit")
    func sizeToFit() {
        let size = sendSizeThatFits(state.bounds.size)
        let frame = state.frame
        setFrame(CGRect(origin: frame.origin, size: size))
    }

    // MARK: Responder chain

    /// The view's controller, if it is a controller's view; otherwise the
    /// superview.
    @ObjCMethod("nextResponder")
    override func nextResponder() -> NSObject? {
        if let controller = state.viewController { return NSObject(controller) }
        return state.superview.map(UIView.wrap)
    }
}

/// Views UIKit puts between a window and its root view controller's view.
@ObjCClass("UITransitionView")
open class UITransitionView: UIView {}

@ObjCClass("UIDropShadowView")
open class UIDropShadowView: UIView {}

/// UIView's messages, sent so subclasses' overrides run.
extension NSObject {
    @ObjCMethod("initWithFrame:")
    func initializeView(frame: CGRect) -> NSObject

    @ObjCMethod("willMoveToSuperview:") func sendWillMoveToSuperview(_ superview: UIView?)
    @ObjCMethod("didMoveToSuperview") func sendDidMoveToSuperview()
    @ObjCMethod("willMoveToWindow:") func sendWillMoveToWindow(_ window: UIView?)
    @ObjCMethod("didMoveToWindow") func sendDidMoveToWindow()
    @ObjCMethod("didAddSubview:") func sendDidAddSubview(_ subview: UIView)
    @ObjCMethod("willRemoveSubview:") func sendWillRemoveSubview(_ subview: UIView)
    @ObjCMethod("layoutSubviews") func sendLayoutSubviews()
    @ObjCMethod("sizeThatFits:") func sendSizeThatFits(_ size: CGSize) -> CGSize
}

import CPerryGeometry
import PerryObjCInterop

// UIScrollView: the content offset is the bounds' origin, so subviews
// placed in content coordinates move as it changes; the view clips to its
// bounds. Insets are adjusted for the safe area, as UIKit's automatic
// behavior does, and a scroll view resting at the top stays there when
// they change.

final class ScrollViewState: ObjectState {
    var contentSize = CGSize.zero
    var contentInset = UIEdgeInsets.zero
    /// UIScrollViewContentInsetAdjustmentBehavior: automatic 0,
    /// scrollable axes 1, never 2, always 3.
    var adjustmentBehavior = 0
    /// The adjusted insets last applied to the offset.
    var appliedAdjustedInset = UIEdgeInsets.zero
    var delegate: UnsafeMutableRawPointer?
    var scrollEnabled = true
    var pagingEnabled = false
    var bounces = true
    var bouncesZoom = true
    var alwaysBounceVertical = false
    var alwaysBounceHorizontal = false
    var directionalLockEnabled = false
    var scrollsToTop = true
    var showsVerticalIndicator = true
    var showsHorizontalIndicator = true
    var indicatorStyle = 0
    var decelerationRate: CGFloat = 0.998
    var zoomScale: CGFloat = 1
    var minimumZoomScale: CGFloat = 1
    var maximumZoomScale: CGFloat = 1
    var keyboardDismissMode = 0
    var delaysContentTouches = true
    var canCancelContentTouches = true
    var verticalIndicatorInsets = UIEdgeInsets.zero
    var horizontalIndicatorInsets = UIEdgeInsets.zero
    var automaticallyAdjustsScrollIndicatorInsets = true
    var panGestureRecognizer: UIGestureRecognizer?
    var refreshControl: UIView?
    var tracking = false
    var dragging = false
    var decelerating = false
}

@ObjCClass("UIScrollView")
open class UIScrollView: UIView {
    static let scrollStates = StateTable<ScrollViewState>()
    var scroll: ScrollViewState { UIScrollView.scrollStates[objcObject] }

    @ObjCMethod("initWithFrame:")
    override func initialize(frame: CGRect) -> Self {
        _ = super.initialize(frame: frame)
        state.geometry.masksToBounds = true
        let pan = UIScrollViewPanGestureRecognizer.objCClass.object.allocated().unsafeCast(to: UIGestureRecognizer.self)
        scroll.panGestureRecognizer = pan
        addGestureRecognizer(pan)
        return self
    }

    @ObjCMethod("dealloc")
    override func dealloc() {
        UIScrollView.scrollStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCMethod("delegate") func delegate() -> NSObject? { scroll.delegate.map { NSObject($0) } }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { scroll.delegate = delegate?.objcObject }

    // MARK: Content

    @ObjCMethod("contentOffset") func contentOffset() -> CGPoint { state.bounds.origin }

    /// Moves the bounds and tells the delegate, when the offset changes.
    @ObjCMethod("setContentOffset:")
    func setContentOffset(_ offset: CGPoint) {
        var bounds = state.bounds
        guard bounds.origin != offset else { return }
        bounds.origin = offset
        sendSetBounds(bounds)
        didScroll()
    }

    @ObjCMethod("setContentOffset:animated:")
    func setContentOffset(_ offset: CGPoint, animated: Bool) {
        sendSetContentOffset(offset)
        if animated, let delegate = delegate(), delegate.responds(to: "scrollViewDidEndScrollingAnimation:") {
            delegate.sendScrollViewDidEndScrollingAnimation(self)
        }
    }

    func didScroll() {
        guard let delegate = delegate(), delegate.responds(to: "scrollViewDidScroll:") else { return }
        delegate.sendScrollViewDidScroll(self)
    }

    @ObjCMethod("contentSize") func contentSize() -> CGSize { scroll.contentSize }
    @ObjCMethod("setContentSize:") func setContentSize(_ size: CGSize) { scroll.contentSize = size }

    @ObjCMethod("contentInset") func contentInset() -> UIEdgeInsets { scroll.contentInset }

    @ObjCMethod("setContentInset:")
    func setContentInset(_ inset: UIEdgeInsets) {
        scroll.contentInset = inset
        applyAdjustedInset()
    }

    @ObjCMethod("contentInsetAdjustmentBehavior") func contentInsetAdjustmentBehavior() -> Int { scroll.adjustmentBehavior }

    @ObjCMethod("setContentInsetAdjustmentBehavior:")
    func setContentInsetAdjustmentBehavior(_ behavior: Int) {
        scroll.adjustmentBehavior = behavior
        applyAdjustedInset()
    }

    /// The content inset plus the safe area on the edges the behavior
    /// adjusts.
    @ObjCMethod("adjustedContentInset")
    func adjustedContentInset() -> UIEdgeInsets {
        let inset = scroll.contentInset
        let safe = adjustingSafeArea
        return UIEdgeInsets(top: inset.top + safe.top, left: inset.left + safe.left,
                            bottom: inset.bottom + safe.bottom, right: inset.right + safe.right)
    }

    private var adjustingSafeArea: UIEdgeInsets {
        let scroll = scroll
        guard scroll.adjustmentBehavior != 2 else { return .zero }
        let safe = safeAreaInsets()
        if scroll.adjustmentBehavior == 3 { return safe }
        let bounds = state.bounds
        let vertical = scroll.adjustmentBehavior == 0 || scroll.contentSize.height > bounds.height || scroll.alwaysBounceVertical
        let horizontal = scroll.contentSize.width > bounds.width || scroll.alwaysBounceHorizontal
        return UIEdgeInsets(top: vertical ? safe.top : 0, left: horizontal ? safe.left : 0,
                            bottom: vertical ? safe.bottom : 0, right: horizontal ? safe.right : 0)
    }

    /// Keeps a scroll view resting at the top or left edge there when the
    /// adjusted insets change.
    func applyAdjustedInset() {
        let old = scroll.appliedAdjustedInset, new = adjustedContentInset()
        guard old != new else { return }
        scroll.appliedAdjustedInset = new
        var offset = state.bounds.origin
        if offset.y == -old.top { offset.y = -new.top }
        if offset.x == -old.left { offset.x = -new.left }
        sendSetContentOffset(offset)
        if let delegate = delegate(), delegate.responds(to: "scrollViewDidChangeAdjustedContentInset:") {
            delegate.sendScrollViewDidChangeAdjustedContentInset(self)
        }
    }

    @ObjCMethod("adjustedContentInsetDidChange") func adjustedContentInsetDidChange() {}

    @ObjCMethod("safeAreaInsetsDidChange")
    override func safeAreaInsetsDidChange() { applyAdjustedInset() }

    /// The least scrolling that shows `rect`, within the content.
    @ObjCMethod("scrollRectToVisible:animated:")
    func scrollRectToVisible(_ rect: CGRect, animated: Bool) {
        let bounds = state.bounds, inset = adjustedContentInset(), size = scroll.contentSize
        /// One axis: the offset that brings start...end into the visible
        /// part, its start first when it does not fit, within the content.
        func axis(_ offset: CGFloat, _ start: CGFloat, _ end: CGFloat, _ length: CGFloat, _ before: CGFloat, _ after: CGFloat,
                  _ content: CGFloat) -> CGFloat {
            var target = offset
            if start < offset + before {
                target = start - before
            } else if end > offset + length - after {
                target = min(end - length + after, start - before)
            }
            // Adding zero turns a negative zero into zero.
            return min(max(target, -before), max(-before, content + after - length)) + 0
        }
        let x = axis(bounds.minX, rect.minX, rect.maxX, bounds.width, inset.left, inset.right, size.width)
        let y = axis(bounds.minY, rect.minY, rect.maxY, bounds.height, inset.top, inset.bottom, size.height)
        setContentOffset(CGPoint(x: x, y: y), animated: animated)
    }

    @ObjCMethod("flashScrollIndicators") func flashScrollIndicators() {}

    // MARK: Layout

    @ObjCMethod("layoutSubviews")
    override func layoutSubviews() { applyAdjustedInset() }

    // MARK: Properties

    @ObjCMethod("isScrollEnabled") func isScrollEnabled() -> Bool { scroll.scrollEnabled }
    @ObjCMethod("setScrollEnabled:") func setScrollEnabled(_ enabled: Bool) { scroll.scrollEnabled = enabled }
    @ObjCMethod("isPagingEnabled") func isPagingEnabled() -> Bool { scroll.pagingEnabled }
    @ObjCMethod("setPagingEnabled:") func setPagingEnabled(_ enabled: Bool) { scroll.pagingEnabled = enabled }
    @ObjCMethod("bounces") func bounces() -> Bool { scroll.bounces }
    @ObjCMethod("setBounces:") func setBounces(_ bounces: Bool) { scroll.bounces = bounces }
    @ObjCMethod("bouncesZoom") func bouncesZoom() -> Bool { scroll.bouncesZoom }
    @ObjCMethod("setBouncesZoom:") func setBouncesZoom(_ bounces: Bool) { scroll.bouncesZoom = bounces }
    @ObjCMethod("alwaysBounceVertical") func alwaysBounceVertical() -> Bool { scroll.alwaysBounceVertical }
    @ObjCMethod("setAlwaysBounceVertical:") func setAlwaysBounceVertical(_ bounces: Bool) { scroll.alwaysBounceVertical = bounces }
    @ObjCMethod("alwaysBounceHorizontal") func alwaysBounceHorizontal() -> Bool { scroll.alwaysBounceHorizontal }
    @ObjCMethod("setAlwaysBounceHorizontal:") func setAlwaysBounceHorizontal(_ bounces: Bool) { scroll.alwaysBounceHorizontal = bounces }
    @ObjCMethod("isDirectionalLockEnabled") func isDirectionalLockEnabled() -> Bool { scroll.directionalLockEnabled }
    @ObjCMethod("setDirectionalLockEnabled:") func setDirectionalLockEnabled(_ enabled: Bool) { scroll.directionalLockEnabled = enabled }
    @ObjCMethod("scrollsToTop") func scrollsToTop() -> Bool { scroll.scrollsToTop }
    @ObjCMethod("setScrollsToTop:") func setScrollsToTop(_ scrolls: Bool) { scroll.scrollsToTop = scrolls }
    @ObjCMethod("showsVerticalScrollIndicator") func showsVerticalScrollIndicator() -> Bool { scroll.showsVerticalIndicator }
    @ObjCMethod("setShowsVerticalScrollIndicator:") func setShowsVerticalScrollIndicator(_ shows: Bool) { scroll.showsVerticalIndicator = shows }
    @ObjCMethod("showsHorizontalScrollIndicator") func showsHorizontalScrollIndicator() -> Bool { scroll.showsHorizontalIndicator }
    @ObjCMethod("setShowsHorizontalScrollIndicator:") func setShowsHorizontalScrollIndicator(_ shows: Bool) {
        scroll.showsHorizontalIndicator = shows
    }
    @ObjCMethod("indicatorStyle") func indicatorStyle() -> Int { scroll.indicatorStyle }
    @ObjCMethod("setIndicatorStyle:") func setIndicatorStyle(_ style: Int) { scroll.indicatorStyle = style }
    @ObjCMethod("decelerationRate") func decelerationRate() -> CGFloat { scroll.decelerationRate }
    @ObjCMethod("setDecelerationRate:") func setDecelerationRate(_ rate: CGFloat) { scroll.decelerationRate = rate }
    @ObjCMethod("zoomScale") func zoomScale() -> CGFloat { scroll.zoomScale }
    @ObjCMethod("setZoomScale:") func setZoomScale(_ scale: CGFloat) {
        scroll.zoomScale = min(max(scale, scroll.minimumZoomScale), scroll.maximumZoomScale)
    }
    @ObjCMethod("setZoomScale:animated:") func setZoomScale(_ scale: CGFloat, animated: Bool) { setZoomScale(scale) }
    @ObjCMethod("minimumZoomScale") func minimumZoomScale() -> CGFloat { scroll.minimumZoomScale }
    @ObjCMethod("setMinimumZoomScale:") func setMinimumZoomScale(_ scale: CGFloat) { scroll.minimumZoomScale = scale }
    @ObjCMethod("maximumZoomScale") func maximumZoomScale() -> CGFloat { scroll.maximumZoomScale }
    @ObjCMethod("setMaximumZoomScale:") func setMaximumZoomScale(_ scale: CGFloat) { scroll.maximumZoomScale = scale }
    @ObjCMethod("isZooming") func isZooming() -> Bool { false }
    @ObjCMethod("isZoomBouncing") func isZoomBouncing() -> Bool { false }
    @ObjCMethod("keyboardDismissMode") func keyboardDismissMode() -> Int { scroll.keyboardDismissMode }
    @ObjCMethod("setKeyboardDismissMode:") func setKeyboardDismissMode(_ mode: Int) { scroll.keyboardDismissMode = mode }
    @ObjCMethod("delaysContentTouches") func delaysContentTouches() -> Bool { scroll.delaysContentTouches }
    @ObjCMethod("setDelaysContentTouches:") func setDelaysContentTouches(_ delays: Bool) { scroll.delaysContentTouches = delays }
    @ObjCMethod("canCancelContentTouches") func canCancelContentTouches() -> Bool { scroll.canCancelContentTouches }
    @ObjCMethod("setCanCancelContentTouches:") func setCanCancelContentTouches(_ cancels: Bool) { scroll.canCancelContentTouches = cancels }
    @ObjCMethod("verticalScrollIndicatorInsets") func verticalScrollIndicatorInsets() -> UIEdgeInsets { scroll.verticalIndicatorInsets }
    @ObjCMethod("setVerticalScrollIndicatorInsets:") func setVerticalScrollIndicatorInsets(_ insets: UIEdgeInsets) {
        scroll.verticalIndicatorInsets = insets
    }
    @ObjCMethod("horizontalScrollIndicatorInsets") func horizontalScrollIndicatorInsets() -> UIEdgeInsets { scroll.horizontalIndicatorInsets }
    @ObjCMethod("setHorizontalScrollIndicatorInsets:") func setHorizontalScrollIndicatorInsets(_ insets: UIEdgeInsets) {
        scroll.horizontalIndicatorInsets = insets
    }
    @ObjCMethod("scrollIndicatorInsets") func scrollIndicatorInsets() -> UIEdgeInsets { scroll.verticalIndicatorInsets }
    @ObjCMethod("setScrollIndicatorInsets:") func setScrollIndicatorInsets(_ insets: UIEdgeInsets) {
        scroll.verticalIndicatorInsets = insets
        scroll.horizontalIndicatorInsets = insets
    }
    @ObjCMethod("automaticallyAdjustsScrollIndicatorInsets") func automaticallyAdjustsScrollIndicatorInsets() -> Bool {
        scroll.automaticallyAdjustsScrollIndicatorInsets
    }
    @ObjCMethod("setAutomaticallyAdjustsScrollIndicatorInsets:") func setAutomaticallyAdjustsScrollIndicatorInsets(_ adjusts: Bool) {
        scroll.automaticallyAdjustsScrollIndicatorInsets = adjusts
    }
    @ObjCMethod("panGestureRecognizer") func panGestureRecognizer() -> UIGestureRecognizer? { scroll.panGestureRecognizer }
    @ObjCMethod("pinchGestureRecognizer") func pinchGestureRecognizer() -> UIGestureRecognizer? { nil }
    @ObjCMethod("refreshControl") func refreshControl() -> UIView? { scroll.refreshControl }
    @ObjCMethod("setRefreshControl:") func setRefreshControl(_ control: UIView?) { scroll.refreshControl = control }
    @ObjCMethod("isTracking") func isTracking() -> Bool { scroll.tracking }
    @ObjCMethod("isDragging") func isDragging() -> Bool { scroll.dragging }
    @ObjCMethod("isDecelerating") func isDecelerating() -> Bool { scroll.decelerating }
}

/// UIScrollView's messages, and its delegate's.
extension NSObject {
    @ObjCMethod("setBounds:") func sendSetBounds(_ bounds: CGRect)
    @ObjCMethod("setContentOffset:") func sendSetContentOffset(_ offset: CGPoint)
    @ObjCMethod("scrollViewDidScroll:") func sendScrollViewDidScroll(_ scrollView: UIScrollView)
    @ObjCMethod("scrollViewDidEndScrollingAnimation:") func sendScrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView)
    @ObjCMethod("scrollViewDidChangeAdjustedContentInset:") func sendScrollViewDidChangeAdjustedContentInset(_ scrollView: UIScrollView)
}

// MARK: - Gesture recognizers

final class GestureRecognizerState: ObjectState {
    /// The view the recognizer is attached to; not retained.
    var view: UnsafeMutableRawPointer?
    var delegate: UnsafeMutableRawPointer?
    var targets: [(target: UnsafeMutableRawPointer, action: UnsafeRawPointer)] = []
    /// UIGestureRecognizerState: possible 0.
    var state = 0
    var enabled = true
    var cancelsTouchesInView = true
    var delaysTouchesBegan = false
    var delaysTouchesEnded = true
    var name: String?
}

/// The recognizer's targets and its view; touches drive recognizers in the
/// live view.
@ObjCClass("UIGestureRecognizer")
open class UIGestureRecognizer: NSObject {
    static let states = StateTable<GestureRecognizerState>()
    var state: GestureRecognizerState { UIGestureRecognizer.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        UIGestureRecognizer.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIGestureRecognizer.objCClass.pointer)
    }

    @ObjCMethod("initWithTarget:action:")
    func initialize(target: NSObject?, action: ObjCSelector?) -> Self {
        if let target, let action { state.targets.append((target.objcObject, action.pointer)) }
        return self
    }

    @ObjCMethod("addTarget:action:")
    func addTarget(_ target: NSObject, action: ObjCSelector) { state.targets.append((target.objcObject, action.pointer)) }

    @ObjCMethod("removeTarget:action:")
    func removeTarget(_ target: NSObject?, action: ObjCSelector?) {
        state.targets.removeAll { (target == nil || $0.target == target!.objcObject) && (action == nil || $0.action == action!.pointer) }
    }

    @ObjCMethod("view") func view() -> UIView? { state.view.map(UIView.wrap) }
    @ObjCMethod("delegate") func delegate() -> NSObject? { state.delegate.map { NSObject($0) } }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { state.delegate = delegate?.objcObject }
    @ObjCMethod("state") func recognizerState() -> Int { state.state }
    @ObjCMethod("isEnabled") func isEnabled() -> Bool { state.enabled }
    @ObjCMethod("setEnabled:") func setEnabled(_ enabled: Bool) { state.enabled = enabled }
    @ObjCMethod("cancelsTouchesInView") func cancelsTouchesInView() -> Bool { state.cancelsTouchesInView }
    @ObjCMethod("setCancelsTouchesInView:") func setCancelsTouchesInView(_ cancels: Bool) { state.cancelsTouchesInView = cancels }
    @ObjCMethod("delaysTouchesBegan") func delaysTouchesBegan() -> Bool { state.delaysTouchesBegan }
    @ObjCMethod("setDelaysTouchesBegan:") func setDelaysTouchesBegan(_ delays: Bool) { state.delaysTouchesBegan = delays }
    @ObjCMethod("delaysTouchesEnded") func delaysTouchesEnded() -> Bool { state.delaysTouchesEnded }
    @ObjCMethod("setDelaysTouchesEnded:") func setDelaysTouchesEnded(_ delays: Bool) { state.delaysTouchesEnded = delays }
    @ObjCMethod("name") func name() -> String? { state.name }
    @ObjCMethod("setName:") func setName(_ name: String?) { state.name = name }
    @ObjCMethod("numberOfTouches") func numberOfTouches() -> UInt { 0 }
    @ObjCMethod("requireGestureRecognizerToFail:") func requireToFail(_ other: UIGestureRecognizer) {}

    @ObjCMethod("locationInView:")
    func location(in view: UIView?) -> CGPoint { .zero }
}

@ObjCClass("UIPanGestureRecognizer")
open class UIPanGestureRecognizer: UIGestureRecognizer {
    @ObjCMethod("translationInView:") func translation(in view: UIView?) -> CGPoint { .zero }
    @ObjCMethod("setTranslation:inView:") func setTranslation(_ translation: CGPoint, in view: UIView?) {}
    @ObjCMethod("velocityInView:") func velocity(in view: UIView?) -> CGPoint { .zero }
    @ObjCMethod("minimumNumberOfTouches") func minimumNumberOfTouches() -> UInt { 1 }
    @ObjCMethod("maximumNumberOfTouches") func maximumNumberOfTouches() -> UInt { UInt.max }
}

@ObjCClass("UIScrollViewPanGestureRecognizer")
open class UIScrollViewPanGestureRecognizer: UIPanGestureRecognizer {}

@ObjCClass("UITapGestureRecognizer")
open class UITapGestureRecognizer: UIGestureRecognizer {
    @ObjCMethod("numberOfTapsRequired") func numberOfTapsRequired() -> UInt { 1 }
    @ObjCMethod("setNumberOfTapsRequired:") func setNumberOfTapsRequired(_ count: UInt) {}
    @ObjCMethod("numberOfTouchesRequired") func numberOfTouchesRequired() -> UInt { 1 }
    @ObjCMethod("setNumberOfTouchesRequired:") func setNumberOfTouchesRequired(_ count: UInt) {}
}

@ObjCClass("UILongPressGestureRecognizer")
open class UILongPressGestureRecognizer: UIGestureRecognizer {
    @ObjCMethod("minimumPressDuration") func minimumPressDuration() -> Double { 0.5 }
    @ObjCMethod("setMinimumPressDuration:") func setMinimumPressDuration(_ duration: Double) {}
}

@ObjCClass("UISwipeGestureRecognizer")
open class UISwipeGestureRecognizer: UIGestureRecognizer {
    @ObjCMethod("direction") func direction() -> UInt { 1 }
    @ObjCMethod("setDirection:") func setDirection(_ direction: UInt) {}
}

@ObjCClass("UIPinchGestureRecognizer")
open class UIPinchGestureRecognizer: UIGestureRecognizer {
    @ObjCMethod("scale") func scale() -> CGFloat { 1 }
    @ObjCMethod("setScale:") func setScale(_ scale: CGFloat) {}
}

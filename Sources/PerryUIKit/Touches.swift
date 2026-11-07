import CPerryGeometry
import Glibc
import PerryObjCInterop
import PerryScrollPhysics

// Touches from the live view's pointer. A touch goes to the view hit
// under it, through -touchesBegan:withEvent: and the rest, which a view
// that does not handle them passes up the responder chain. In a scroll
// view, a touch that moves ten points pans the content instead, and the
// content keeps going after it lifts, slowing at the deceleration rate. A
// tap selects a table row, and works a navigation bar's back button and
// items.

final class TouchState: ObjectState {
    /// UITouchPhase: began 0, moved 1, stationary 2, ended 3, cancelled 4.
    var phase = 0
    var location = CGPoint.zero
    var previous = CGPoint.zero
    var view: UIView?
    var window: UIWindow?
    var timestamp = 0.0
    var tapCount = 1
}

@ObjCClass("UITouch")
open class UITouch: NSObject {
    static let states = StateTable<TouchState>()
    var state: TouchState { UITouch.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        UITouch.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UITouch.objCClass.pointer)
    }

    /// The location in `view`, or in the window without one.
    @ObjCMethod("locationInView:")
    func location(in view: UIView?) -> CGPoint {
        guard let view else { return state.location }
        return view.convert(state.location, from: state.window)
    }

    @ObjCMethod("previousLocationInView:")
    func previousLocation(in view: UIView?) -> CGPoint {
        guard let view else { return state.previous }
        return view.convert(state.previous, from: state.window)
    }

    @ObjCMethod("phase") func phase() -> Int { state.phase }
    @ObjCMethod("view") func view() -> UIView? { state.view }
    @ObjCMethod("window") func window() -> UIWindow? { state.window }
    @ObjCMethod("timestamp") func timestamp() -> Double { state.timestamp }
    @ObjCMethod("tapCount") func tapCount() -> UInt { UInt(state.tapCount) }
    @ObjCMethod("type") func type() -> Int { 0 }
    @ObjCMethod("force") func force() -> CGFloat { 0 }
    @ObjCMethod("maximumPossibleForce") func maximumPossibleForce() -> CGFloat { 0 }
    @ObjCMethod("majorRadius") func majorRadius() -> CGFloat { 20 }
    @ObjCMethod("majorRadiusTolerance") func majorRadiusTolerance() -> CGFloat { 5 }
    @ObjCMethod("gestureRecognizers") func gestureRecognizers() -> NSObject? { nil }

    // A finger's: upright, with no pencil angles or estimates.
    @ObjCMethod("altitudeAngle") func altitudeAngle() -> CGFloat { .pi / 2 }
    @ObjCMethod("azimuthAngleInView:") func azimuthAngle(in view: UIView?) -> CGFloat { 0 }
    @ObjCMethod("azimuthUnitVectorInView:") func azimuthUnitVector(in view: UIView?) -> CGSize { CGSize(width: 1, height: 0) }
    @ObjCMethod("rollAngle") func rollAngle() -> CGFloat { 0 }
    @ObjCMethod("estimatedProperties") func estimatedProperties() -> Int { 0 }
    @ObjCMethod("estimatedPropertiesExpectingUpdates") func estimatedPropertiesExpectingUpdates() -> Int { 0 }
    @ObjCMethod("estimationUpdateIndex") func estimationUpdateIndex() -> NSObject? { nil }
    @ObjCMethod("preciseLocationInView:") func preciseLocation(in view: UIView?) -> CGPoint { location(in: view) }
    @ObjCMethod("precisePreviousLocationInView:") func precisePreviousLocation(in view: UIView?) -> CGPoint { previousLocation(in: view) }
}

final class EventState: ObjectState {
    var touches: [UITouch] = []
    var timestamp = 0.0
}

@ObjCClass("UIEvent")
open class UIEvent: NSObject {
    static let states = StateTable<EventState>()
    var state: EventState { UIEvent.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        UIEvent.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIEvent.objCClass.pointer)
    }

    private func set(_ touches: [UITouch]) -> NSObject {
        let set = NSMutableSet.empty()
        touches.forEach(set.add)
        return set
    }

    @ObjCMethod("allTouches") func allTouches() -> NSObject? { set(state.touches) }

    @ObjCMethod("touchesForView:")
    func touches(for view: UIView) -> NSObject? { set(state.touches.filter { $0.state.view?.objcObject == view.objcObject }) }

    @ObjCMethod("touchesForWindow:")
    func touches(for window: UIWindow) -> NSObject? { set(state.touches.filter { $0.state.window?.objcObject == window.objcObject }) }

    /// The touches a recognizer hears of: every one, as it hears of all
    /// the touches in its view and the view's subviews.
    @ObjCMethod("touchesForGestureRecognizer:")
    func touches(for recognizer: NSObject) -> NSObject? { set(state.touches) }

    @ObjCMethod("coalescedTouchesForTouch:")
    func coalescedTouches(for touch: UITouch) -> NSObject? { NSMutableArray.of([touch]) }

    @ObjCMethod("predictedTouchesForTouch:")
    func predictedTouches(for touch: UITouch) -> NSObject? { NSMutableArray.of([]) }

    @ObjCMethod("type") func type() -> Int { 0 }
    @ObjCMethod("subtype") func subtype() -> Int { 0 }
    @ObjCMethod("timestamp") func timestamp() -> Double { state.timestamp }
    /// No modifier keys are held, and the touch is a finger's, not a
    /// button's.
    @ObjCMethod("modifierFlags") func modifierFlags() -> Int { 0 }
    @ObjCMethod("buttonMask") func buttonMask() -> Int { 0 }
}

/// UIResponder's touch messages, sent so overrides run.
extension NSObject {
    @ObjCMethod("touchesBegan:withEvent:") func sendTouchesBegan(_ touches: NSObject, with event: NSObject?)
    @ObjCMethod("touchesMoved:withEvent:") func sendTouchesMoved(_ touches: NSObject, with event: NSObject?)
    @ObjCMethod("touchesEnded:withEvent:") func sendTouchesEnded(_ touches: NSObject, with event: NSObject?)
    @ObjCMethod("touchesCancelled:withEvent:") func sendTouchesCancelled(_ touches: NSObject, with event: NSObject?)
    @ObjCMethod("nextResponder") func sendNextResponder() -> NSObject?
    @ObjCMethod("reset") func sendReset()
    @ObjCMethod("canPreventGestureRecognizer:") func sendCanPrevent(_ other: UIGestureRecognizer) -> Bool
    @ObjCMethod("canBePreventedByGestureRecognizer:") func sendCanBePrevented(by other: UIGestureRecognizer) -> Bool
    @ObjCMethod("gestureRecognizerShouldBegin:") func sendGestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool
    @ObjCMethod("gestureRecognizer:shouldRecognizeSimultaneouslyWithGestureRecognizer:")
    func sendGestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool
    @ObjCMethod("setState:") func sendSetState(_ state: Int)
    @ObjCMethod("scrollViewWillBeginDragging:") func sendScrollViewWillBeginDragging(_ scrollView: UIScrollView)
    @ObjCMethod("scrollViewDidEndDragging:willDecelerate:") func sendScrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate: Bool)
    @ObjCMethod("scrollViewDidEndDecelerating:") func sendScrollViewDidEndDecelerating(_ scrollView: UIScrollView)
}

enum Touches {
    /// The touch in progress, its event, and the scroll view it may pan.
    nonisolated(unsafe) private static var touch: UITouch?
    nonisolated(unsafe) private static var event: UIEvent?
    nonisolated(unsafe) private static var scrollView: UIScrollView?
    nonisolated(unsafe) private static var start = CGPoint.zero
    nonisolated(unsafe) private static var startOffset = CGPoint.zero
    nonisolated(unsafe) private static var panning = false
    /// Where a swipe across a table row began moving it.
    nonisolated(unsafe) private static var swipeStart = CGPoint.zero
    /// The touch closed a row's swipe actions, and does nothing else.
    nonisolated(unsafe) private static var swallowed = false
    /// Whether the touched view has been sent -touchesBegan:withEvent:.
    nonisolated(unsafe) private static var delivered = false
    /// The gesture recognizers of the touched view and its ancestors, which
    /// hear of the touch as the view does. Held until the touch is over, as
    /// Darwin holds them: a view the touch began in may go away during it,
    /// and its recognizers with it.
    nonisolated(unsafe) private static var recognizers: [UIGestureRecognizer] = [] {
        didSet {
            for recognizer in recognizers { _ = ObjCRuntime.retain(recognizer.objcObject) }
            for recognizer in oldValue { ObjCRuntime.release(recognizer.objcObject) }
        }
    }

    /// Whether the touched view's touches were cancelled by a recognizer
    /// that began, after which it hears of no more.
    nonisolated(unsafe) private static var viewCancelled = false

    /// A recognizer of the touch began (or recognized): the touch's other
    /// recognizers fail, or are cancelled if they had begun, unless either
    /// delegate lets the two recognize together, or one can't prevent the
    /// other. One that cancels touches in view cancels the touched view's.
    static func recognizerBegan(_ recognizer: UIGestureRecognizer) {
        guard touch != nil, recognizers.contains(where: { $0.objcObject == recognizer.objcObject }) else { return }
        let set = NSMutableSet.empty()
        if let touch { set.add(touch) }
        for other in recognizers where other.objcObject != recognizer.objcObject && other.state.state <= 2 {
            if simultaneous(recognizer, other) { continue }
            guard recognizer.sendCanPrevent(other), other.sendCanBePrevented(by: recognizer) else { continue }
            trace("\(recognizer.objcObject) prevents \(other.objcObject) (state \(other.state.state))")
            if let event { other.sendTouchesCancelled(set, with: event) }
            other.sendSetState(other.state.state == 0 ? 5 : 4)
            other.sendReset()
        }
        if recognizer.state.cancelsTouchesInView, delivered, !viewCancelled, let view = touch?.state.view, let event {
            viewCancelled = true
            touch?.state.phase = 4
            view.sendTouchesCancelled(set, with: event)
        }
    }

    private static func simultaneous(_ first: UIGestureRecognizer, _ second: UIGestureRecognizer) -> Bool {
        for (recognizer, other) in [(first, second), (second, first)] {
            if let delegate = recognizer.delegate(),
               delegate.responds(to: "gestureRecognizer:shouldRecognizeSimultaneouslyWithGestureRecognizer:"),
               delegate.sendGestureRecognizer(recognizer, shouldRecognizeSimultaneouslyWith: other) {
                return true
            }
        }
        return false
    }

    /// The touch in progress, for recognizers' locationInView:.
    static var current: UITouch? { touch }
    nonisolated(unsafe) private static var samples = VelocityTracker()
    /// Momentum after a pan: the scroll view and its coasting, in points
    /// per second.
    nonisolated(unsafe) private static var coasting: (view: UIScrollView, deceleration: Deceleration)?
    /// Where the finger has moved a scroll view's content since the last
    /// frame: applied once a frame, before it draws, not for each move.
    nonisolated(unsafe) private static var pendingPan: (view: UIScrollView, offset: CGPoint)?
    /// Content let go past its edges, springing back along each axis.
    nonisolated(unsafe) private static var springing: (view: UIScrollView, x: SpringBack, y: SpringBack)?

    private static var keyWindow: UIWindow? {
        Windows.key.map { UIWindow(objcObject: $0, ownership: .retain) } ?? Windows.visible.last
    }

    static func down(at point: CGPoint) {
        guard let window = keyWindow else { return }
        stopCoasting()
        // A finger down catches content springing back where it is.
        flushPan()
        if let (view, _, _) = springing {
            springing = nil
            stopCoasting(view)
        }
        let hit = window.sendHitTest(point, with: nil)
        trace("down at \(point.x), \(point.y) hits \(hit?.describedByObject() ?? "nothing")")
        let touch = UITouch.objCClass.object.allocated().unsafeCast(to: UITouch.self)
        (touch.state.location, touch.state.previous, touch.state.window, touch.state.view) = (point, point, window, hit)
        touch.state.timestamp = Clock.now
        // One event for every finger down, as UIKit's: this one joins it
        // when other fingers are already down.
        let event = Touches.event ?? UIEvent.objCClass.object.allocated().unsafeCast(to: UIEvent.self)
        event.state.touches.append(touch)
        event.state.timestamp = touch.state.timestamp
        (Touches.touch, Touches.event) = (touch, event)
        markStationary(except: touch)
        (start, panning) = (point, false)
        samples.reset(x: Double(point.x), y: Double(point.y), time: Clock.now)
        recognizers = []
        viewCancelled = false
        var ancestor = hit
        while let view = ancestor {
            recognizers += view.state.gestureRecognizers.filter { $0.state.enabled }
            ancestor = view.state.superview.map(UIView.wrap)
        }
        // A recognizer that finished (ended, cancelled, failed) after the
        // last touch lifted is possible again for this one.
        for recognizer in recognizers where recognizer.state.state >= 3 {
            recognizer.state.state = 0
            recognizer.sendReset()
        }
        scrollView = hit.flatMap(scrollingAncestor)
        // A touch away from a row's open swipe actions closes them.
        swallowed = false
        if SwipeActions.isOpen, !SwipeActions.isOnButtons(hit) {
            SwipeActions.close(animated: true)
            swallowed = true
        }
        // In a scroll view a cell lights up only once the touch has stayed a
        // moment without moving, as iOS waits to see whether it pans.
        if !swallowed, let cell = hit.flatMap(tableCell) {
            if scrollView == nil {
                highlighted = cell
                setHighlighted(cell, true)
            } else {
                pendingHighlight = (cell, Clock.now)
            }
        }
        startOffset = scrollView?.state.bounds.origin ?? .zero
        scrollView?.scroll.tracking = true
        // Inside a scroll view, the content hears of the touch only once
        // it is clearly not a pan.
        delivered = scrollView == nil
        if delivered { send(.began) }
    }

    static func move(to point: CGPoint) {
        guard let touch else { return }
        touch.state.previous = touch.state.location
        touch.state.location = point
        touch.state.timestamp = Clock.now
        markStationary(except: touch)
        samples.add(x: Double(point.x), y: Double(point.y), time: Clock.now)
        if SwipeActions.dragging {
            SwipeActions.move(dx: point.x - swipeStart.x)
            return
        }
        if let scrollView {
            let distance = hypot(point.x - start.x, point.y - start.y)
            // A drag more across than down a table's row swipes it.
            if !panning, !swallowed, distance >= 10, abs(point.x - start.x) > abs(point.y - start.y) * 1.5,
               let table = scrollView.as(UITableView.self), let cell = touch.state.view.flatMap(rowCell),
               SwipeActions.begin(table: table, cell: cell, dx: point.x - start.x) {
                unhighlight()
                if delivered { send(.cancelled) }
                swipeStart = start
                SwipeActions.move(dx: point.x - swipeStart.x)
                return
            }
            if !panning, distance >= CGFloat(panThreshold) {
                panning = true
                unhighlight()
                if delivered { send(.cancelled) }
                start = point
                startOffset = scrollView.state.bounds.origin
                scrollView.scroll.dragging = true
                if let delegate = scrollView.delegate(), delegate.responds(to: "scrollViewWillBeginDragging:") {
                    delegate.sendScrollViewWillBeginDragging(scrollView)
                }
            }
            if panning {
                pendingPan = (scrollView, banded(scrollView, CGPoint(x: startOffset.x - axis(scrollView).x * (point.x - start.x),
                                                                     y: startOffset.y - axis(scrollView).y * (point.y - start.y))))
                Display.markDirty()
                return
            }
            return
        }
        touch.state.phase = 1
        send(.moved)
        Display.markDirty()
    }

    static func up(at point: CGPoint) {
        guard let touch else { return }
        touch.state.location = point
        touch.state.timestamp = Clock.now
        markStationary(except: touch)
        defer {
            resetRecognizers()
            event?.state.touches.removeAll { $0.objcObject == touch.objcObject }
            if others.isEmpty { event = nil }
            (Touches.touch, scrollView) = (nil, nil)
            Display.markDirty()
        }
        if SwipeActions.dragging {
            scrollView?.scroll.tracking = false
            SwipeActions.end()
            return
        }
        if swallowed, !panning {
            scrollView?.scroll.tracking = false
            return
        }
        if let scrollView, panning {
            flushPan()
            scrollView.scroll.dragging = false
            scrollView.scroll.tracking = false
            // Let go past an edge, the content springs back instead of coasting.
            let offset = scrollView.state.bounds.origin, rest = clamped(scrollView, offset)
            if rest != offset {
                if let delegate = scrollView.delegate(), delegate.responds(to: "scrollViewDidEndDragging:willDecelerate:") {
                    delegate.sendScrollViewDidEndDragging(scrollView, willDecelerate: true)
                }
                springing = (scrollView, SpringBack(from: Double(offset.x), to: Double(rest.x), time: Clock.now),
                             SpringBack(from: Double(offset.y), to: Double(rest.y), time: Clock.now))
                scrollView.scroll.decelerating = true
                return
            }
            let velocity = Touches.velocity(scrollView)
            let deceleration = Deceleration(velocity: (Double(velocity.x), Double(velocity.y)), rate: Double(scrollView.scroll.decelerationRate),
                                            time: Clock.now)
            if let delegate = scrollView.delegate(), delegate.responds(to: "scrollViewDidEndDragging:willDecelerate:") {
                delegate.sendScrollViewDidEndDragging(scrollView, willDecelerate: deceleration != nil)
            }
            if let deceleration {
                coasting = (scrollView, deceleration)
                scrollView.scroll.decelerating = true
            }
            return
        }
        scrollView?.scroll.tracking = false
        unhighlight()
        if !delivered { send(.began) }
        touch.state.phase = 3
        send(.ended)
        tapped(touch)
    }

    // MARK: More fingers

    /// Fingers down besides the first, by the platform's number for them:
    /// each a touch sent to the view it went down on, in the first's event.
    /// The first alone works scroll views, recognizers and controls.
    nonisolated(unsafe) private static var others: [UInt64: UITouch] = [:]

    /// Every finger down but `touch` is stationary in the event it's in.
    private static func markStationary(except touch: UITouch) {
        for other in event?.state.touches ?? [] where other.objcObject != touch.objcObject && other.state.phase < 2 {
            other.state.phase = 2
        }
    }

    /// Another finger down at `point`. As UIKit, a view hears of a second
    /// touch only when it's multiple-touch enabled.
    static func down(at point: CGPoint, finger: UInt64) {
        guard others[finger] == nil, let window = keyWindow, let hit = window.sendHitTest(point, with: nil) else { return }
        let down = ([touch].compactMap { $0 } + others.values).contains { $0.state.view?.objcObject == hit.objcObject }
        guard !down || hit.state.multipleTouchEnabled else { return }
        let added = UITouch.objCClass.object.allocated().unsafeCast(to: UITouch.self)
        (added.state.location, added.state.previous, added.state.window, added.state.view) = (point, point, window, hit)
        added.state.timestamp = Clock.now
        let event = Touches.event ?? UIEvent.objCClass.object.allocated().unsafeCast(to: UIEvent.self)
        event.state.touches.append(added)
        event.state.timestamp = added.state.timestamp
        Touches.event = event
        others[finger] = added
        markStationary(except: added)
        deliver(added, .began, in: event)
        Display.markDirty()
    }

    static func move(to point: CGPoint, finger: UInt64) {
        guard let moved = others[finger], let event else { return }
        moved.state.previous = moved.state.location
        (moved.state.location, moved.state.timestamp, moved.state.phase) = (point, Clock.now, 1)
        event.state.timestamp = moved.state.timestamp
        markStationary(except: moved)
        deliver(moved, .moved, in: event)
        Display.markDirty()
    }

    static func up(at point: CGPoint, finger: UInt64, cancelled: Bool = false) {
        guard let lifted = others.removeValue(forKey: finger), let event else { return }
        (lifted.state.location, lifted.state.timestamp, lifted.state.phase) = (point, Clock.now, cancelled ? 4 : 3)
        event.state.timestamp = lifted.state.timestamp
        markStationary(except: lifted)
        deliver(lifted, cancelled ? .cancelled : .ended, in: event)
        event.state.touches.removeAll { $0.objcObject == lifted.objcObject }
        if touch == nil, others.isEmpty { Touches.event = nil }
        Display.markDirty()
    }

    /// A phase of one of the other fingers, to its view alone.
    private static func deliver(_ finger: UITouch, _ phase: Phase, in event: UIEvent) {
        guard let view = finger.state.view else { return }
        let set = NSMutableSet.empty()
        set.add(finger)
        trace("finger \(finger.objcObject) \(phase) at \(finger.state.location) to \(view.objcObject)")
        switch phase {
        case .began: view.sendTouchesBegan(set, with: event)
        case .moved: view.sendTouchesMoved(set, with: event)
        case .ended: view.sendTouchesEnded(set, with: event)
        case .cancelled: view.sendTouchesCancelled(set, with: event)
        }
    }

    /// The mouse wheel scrolls the scroll view under the pointer.
    static func wheel(at point: CGPoint, by distance: CGFloat) {
        guard let window = keyWindow, let hit = window.sendHitTest(point, with: nil), let scrollView = scrollingAncestor(of: hit) else { return }
        stopCoasting()
        let offset = scrollView.state.bounds.origin
        pan(scrollView, to: clamped(scrollView, CGPoint(x: offset.x, y: offset.y + distance * axis(scrollView).y)))
    }

    /// Lights up a cell held long enough, and moves momentum scrolling on,
    /// from the live view's tick.
    static func step() {
        flushPan()
        if var (view, x, y) = springing {
            let offset = CGPoint(x: CGFloat(x.step(at: Clock.now)), y: CGFloat(y.step(at: Clock.now)))
            pan(view, to: offset)
            Display.markDirty()
            if x.isFinished && y.isFinished {
                springing = nil
                stopCoasting(view)
            } else {
                springing = (view, x, y)
            }
        }
        if let (cell, since) = pendingHighlight, touch != nil, !panning, Clock.now - since >= highlightDelay {
            pendingHighlight = nil
            highlighted = cell
            setHighlighted(cell, true)
            Display.markDirty()
        }
        guard var (view, deceleration) = coasting else { return }
        let distance = deceleration.step(at: Clock.now)
        let offset = view.state.bounds.origin
        let target = clamped(view, CGPoint(x: offset.x - CGFloat(distance.x), y: offset.y - CGFloat(distance.y)))
        pan(view, to: target)
        Display.markDirty()
        if deceleration.isFinished || target == offset {
            stopCoasting()
        } else {
            coasting = (view, deceleration)
        }
    }

    private static func stopCoasting() {
        guard let (view, _) = coasting else { return }
        coasting = nil
        stopCoasting(view)
    }

    private static func stopCoasting(_ view: UIScrollView) {
        view.scroll.decelerating = false
        if let delegate = view.delegate(), delegate.responds(to: "scrollViewDidEndDecelerating:") {
            delegate.sendScrollViewDidEndDecelerating(view)
        }
    }

    /// Moves the content where the finger took it since the last frame.
    private static func flushPan() {
        guard let (view, offset) = pendingPan else { return }
        pendingPan = nil
        pan(view, to: offset)
    }

    /// A dragged offset: within the content, or past its edges by a rubber
    /// band's stretch where the scroll view bounces.
    private static func banded(_ view: UIScrollView, _ offset: CGPoint) -> CGPoint {
        guard view.scroll.bounces else { return clamped(view, offset) }
        let bounds = view.state.bounds, inset = view.adjustedContentInset(), size = view.scroll.contentSize
        let maxX = max(-inset.left, size.width + inset.right - bounds.width)
        let maxY = max(-inset.top, size.height + inset.bottom - bounds.height)
        return CGPoint(x: CGFloat(rubberBand(Double(offset.x), low: Double(-inset.left), high: Double(maxX), dimension: Double(bounds.width))),
                       y: CGFloat(rubberBand(Double(offset.y), low: Double(-inset.top), high: Double(maxY), dimension: Double(bounds.height))))
    }

    private static func pan(_ view: UIScrollView, to offset: CGPoint) {
        guard offset != view.state.bounds.origin else { return }
        view.sendSetContentOffset(offset)
        Updates.schedule()
    }

    /// The axes a scroll view moves along: those its content overflows, and
    /// vertically when it always bounces or has nothing to overflow.
    private static func axis(_ view: UIScrollView) -> CGPoint {
        let bounds = view.state.bounds, inset = view.adjustedContentInset(), size = view.scroll.contentSize
        let horizontal = size.width + inset.left + inset.right > bounds.width || view.scroll.alwaysBounceHorizontal
        let vertical = size.height + inset.top + inset.bottom > bounds.height || view.scroll.alwaysBounceVertical || !horizontal
        return CGPoint(x: horizontal ? 1 : 0, y: vertical ? 1 : 0)
    }

    private static func clamped(_ view: UIScrollView, _ offset: CGPoint) -> CGPoint {
        let bounds = view.state.bounds, inset = view.adjustedContentInset(), size = view.scroll.contentSize
        let maxX = max(-inset.left, size.width + inset.right - bounds.width)
        let maxY = max(-inset.top, size.height + inset.bottom - bounds.height)
        return CGPoint(x: min(max(offset.x, -inset.left), maxX), y: min(max(offset.y, -inset.top), maxY))
    }

    private static func velocity(_ view: UIScrollView) -> CGPoint {
        let velocity = samples.velocity, axis = axis(view)
        return CGPoint(x: CGFloat(velocity.x) * axis.x, y: CGFloat(velocity.y) * axis.y)
    }

    /// The cell a touch began in, highlighted until it lifts or pans.
    nonisolated(unsafe) private static var highlighted: UIView?
    /// A cell in a scroll view, to light up if the touch stays.
    nonisolated(unsafe) private static var pendingHighlight: (cell: UIView, since: Double)?
    /// UIScrollView's delay before content hears of a touch.
    private static let highlightDelay = 0.15

    private static func unhighlight() {
        pendingHighlight = nil
        if let highlighted { setHighlighted(highlighted, false) }
        highlighted = nil
    }

    /// The table cell `view` is in, if any, unless the touch is an
    /// enabled control's, which takes it from the cell.
    private static func tableCell(of view: UIView) -> UIView? {
        var current: UIView? = view
        while let candidate = current {
            if isEnabledControl(candidate) { return nil }
            if candidate.is(UITableViewCell.self) { return candidate }
            if candidate.is(UICollectionViewCell.self), let collection = collectionView(of: candidate) {
                let cell = candidate.unsafeCast(to: UICollectionViewCell.self)
                guard let path = collection.collection.visibleCells.first(where: { $0.value.objcObject == cell.objcObject })?.key,
                      collection.shouldHighlight(path) else { return nil }
                return candidate
            }
            current = candidate.state.superview.map(UIView.wrap)
        }
        return nil
    }

    /// A table cell lights up through -setHighlighted:animated:, a
    /// collection view's cell through -setHighlighted:.
    private static func setHighlighted(_ cell: UIView, _ highlighted: Bool) {
        if cell.is(UITableViewCell.self) {
            cell.sendSetHighlighted(highlighted, animated: false)
        } else {
            cell.sendSetHighlighted(highlighted)
        }
    }

    /// The collection view a cell is shown in: its superview.
    private static func collectionView(of cell: UIView) -> UICollectionView? {
        guard let parent = cell.state.superview, ObjCRuntime.isKind(parent, of: UICollectionView.objCClass.pointer) else { return nil }
        return UICollectionView(objcObject: parent, ownership: .retain)
    }

    /// The table cell `view` is in, controls and all.
    private static func rowCell(of view: UIView) -> UITableViewCell? {
        var current: UIView? = view
        while let candidate = current {
            if candidate.is(UITableViewCell.self) { return candidate.unsafeCast(to: UITableViewCell.self) }
            current = candidate.state.superview.map(UIView.wrap)
        }
        return nil
    }

    private static func isEnabledControl(_ view: UIView) -> Bool {
        view.is(UIControl.self) && view.unsafeCast(to: UIControl.self).control.enabled
    }

    /// The nearest enclosing scroll view that scrolls.
    private static func scrollingAncestor(of view: UIView) -> UIScrollView? {
        var current: UIView? = view
        while let candidate = current {
            if candidate.is(UIScrollView.self) {
                let scroll = candidate.unsafeCast(to: UIScrollView.self)
                if scroll.scroll.scrollEnabled { return scroll }
            }
            current = candidate.state.superview.map(UIView.wrap)
        }
        return nil
    }

    private enum Phase { case began, moved, ended, cancelled }

    /// Recognizers first, as UIKit sends them touches: each still possible,
    /// or recognizing a continuous gesture, hears of the phase.
    /// With PERRY_UIKIT_TOUCH_TRACE set, each phase and the recognizers it
    /// goes to, with their states, are written to standard error.
    nonisolated(unsafe) private static let tracing = getenv("PERRY_UIKIT_TOUCH_TRACE") != nil

    private static func trace(_ message: @autoclosure () -> String) {
        guard tracing else { return }
        let line = "perry: UIKit: touch: \(message())\n"
        line.withCString { _ = write(2, $0, strlen($0)) }
    }

    private static func sendRecognizers(_ phase: Phase, _ set: NSMutableSet, _ event: UIEvent) {
        trace("\(phase) to \(recognizers.map { "\($0.describedByObject()):\($0.state.state)" })")
        for recognizer in recognizers where recognizer.state.state <= 2 {
            switch phase {
            case .began: recognizer.sendTouchesBegan(set, with: event)
            case .moved: recognizer.sendTouchesMoved(set, with: event)
            case .ended: recognizer.sendTouchesEnded(set, with: event)
            case .cancelled: recognizer.sendTouchesCancelled(set, with: event)
            }
        }
    }

    /// Once the touch is over, each recognizer is possible again.
    private static func resetRecognizers() {
        for recognizer in recognizers {
            recognizer.state.state = 0
            recognizer.sendReset()
        }
        recognizers = []
    }

    private static func send(_ phase: Phase) {
        guard let touch, let event, let view = touch.state.view else { return }
        let set = NSMutableSet.empty()
        set.add(touch)
        sendRecognizers(phase, set, event)
        if viewCancelled { return }
        switch phase {
        case .began: view.sendTouchesBegan(set, with: event)
        case .moved: view.sendTouchesMoved(set, with: event)
        case .ended: view.sendTouchesEnded(set, with: event)
        case .cancelled:
            touch.state.phase = 4
            view.sendTouchesCancelled(set, with: event)
        }
        delivered = true
    }

    /// A tap on a navigation bar's buttons or a table's row. A tap on an
    /// enabled control in a cell is the control's, and selects no row.
    private static func tapped(_ touch: UITouch) {
        var current = touch.state.view
        var inControl = false
        while let view = current {
            if isEnabledControl(view) { inControl = true }
            if view.is(UINavigationBar.self) {
                view.unsafeCast(to: UINavigationBar.self).tap(at: touch.location(in: view))
                return
            }
            if view.is(UIToolbar.self) {
                view.unsafeCast(to: UIToolbar.self).tap(at: touch.location(in: view))
                return
            }
            if view.is(UITabBar.self) {
                view.unsafeCast(to: UITabBar.self).tap(at: touch.location(in: view))
                return
            }
            if view.is(UITableViewCell.self) || view.is(UICollectionViewCell.self), inControl { return }
            if view.is(UICollectionViewCell.self), let collection = collectionView(of: view) {
                if let path = collection.collection.visibleCells.first(where: { $0.value.objcObject == view.objcObject })?.key {
                    collection.tapItem(path)
                }
                return
            }
            if view.is(UITableViewCell.self), let tableObject = view.state.superview, ObjCRuntime.isKind(tableObject, of: UITableView.objCClass.pointer) {
                let table = UITableView(objcObject: tableObject, ownership: .retain)
                if let path = table.table.visibleCells.first(where: { $0.value.objcObject == view.objcObject })?.key {
                    table.tapRow(path)
                }
                return
            }
            current = view.state.superview.map(UIView.wrap)
        }
    }
}

/// UIResponder passes touches it does not handle to the next responder.
@ObjCCategory("Touches")
extension UIResponder {
    @ObjCMethod("touchesBegan:withEvent:")
    func touchesBeganForwarding(_ touches: NSObject, with event: NSObject?) { sendNextResponder()?.sendTouchesBegan(touches, with: event) }

    @ObjCMethod("touchesMoved:withEvent:")
    func touchesMovedForwarding(_ touches: NSObject, with event: NSObject?) { sendNextResponder()?.sendTouchesMoved(touches, with: event) }

    @ObjCMethod("touchesEnded:withEvent:")
    func touchesEndedForwarding(_ touches: NSObject, with event: NSObject?) { sendNextResponder()?.sendTouchesEnded(touches, with: event) }

    @ObjCMethod("touchesCancelled:withEvent:")
    func touchesCancelledForwarding(_ touches: NSObject, with event: NSObject?) {
        sendNextResponder()?.sendTouchesCancelled(touches, with: event)
    }
}

/// With PERRY_UIKIT_TAPS set to steps separated by semicolons, each is
/// done in turn, two seconds apart, beginning two seconds after a window
/// first shows: "195,120" taps a point; "drag:195,600,195,200" swipes
/// from the first point to the second over a quarter second;
/// "pinch:195,400,100,200" puts two fingers either side of the point, 100
/// points apart, and spreads them to 200 over a quarter second (closer
/// pinches in); "doubletap:195,400" taps twice; "type:Hello" types text, and
/// "key:return", "key:backspace" and "key:escape" press those keys, for
/// the first responder; "wait" does nothing for its two seconds. To reach
/// an app's later screens without a display, along with
/// PERRY_UIKIT_SNAPSHOT, which then also keeps what shows a second after
/// each step, numbered from 1.
enum TapScript {
    enum Step {
        case tap(CGPoint)
        case drag(CGPoint, CGPoint)
        case pinch(CGPoint, CGFloat, CGFloat)
        case doubleTap(CGPoint)
        case type(String)
        case key(String)
    }

    nonisolated(unsafe) private static var steps: [Step]?
    nonisolated(unsafe) private static var started = false
    nonisolated(unsafe) private static var lastTap = CGPoint.zero
    nonisolated(unsafe) private static var stepsDone = 0

    static func startIfRequested() {
        guard !started, let setting = getenv("PERRY_UIKIT_TAPS") else { return }
        started = true
        steps = String(cString: setting).split(separator: ";").compactMap { item in
            if item == "wait" { return .key("wait") }
            if item.hasPrefix("type:") { return .type(String(item.dropFirst(5))) }
            if item.hasPrefix("key:") { return .key(String(item.dropFirst(4))) }
            if item.hasPrefix("pinch:") {
                let values: [CGFloat] = item.dropFirst(6).split(separator: ",")
                    .compactMap { Double(String($0.filter { $0 != " " })) }.map { CGFloat($0) }
                guard values.count == 4 else { return nil }
                return .pinch(CGPoint(x: values[0], y: values[1]), values[2], values[3])
            }
            if item.hasPrefix("doubletap:") {
                let values: [CGFloat] = item.dropFirst(10).split(separator: ",")
                    .compactMap { Double(String($0.filter { $0 != " " })) }.map { CGFloat($0) }
                guard values.count == 2 else { return nil }
                return .doubleTap(CGPoint(x: values[0], y: values[1]))
            }
            if item.hasPrefix("drag:") {
                let values: [CGFloat] = item.dropFirst(5).split(separator: ",")
                    .compactMap { Double(String($0.filter { $0 != " " })) }.map { CGFloat($0) }
                guard values.count == 4 else { return nil }
                return .drag(CGPoint(x: values[0], y: values[1]), CGPoint(x: values[2], y: values[3]))
            }
            let values: [CGFloat] = item.split(separator: ",").compactMap { Double(String($0.filter { $0 != " " })) }.map { CGFloat($0) }
            return values.count == 2 ? .tap(CGPoint(x: values[0], y: values[1])) : nil
        }
        next()
    }

    private static func next() {
        guard let after = Display.dispatchAfter, let time = Display.dispatchTime, steps?.isEmpty == false else { return }
        after(time(0, 2_000_000_000), Updates.mainQueue, nil) { _ in
            guard let step = TapScript.steps?.removeFirst() else { return }
            switch step {
            case .tap(let point):
                // Held for a few frames, as a finger is, so games polling
                // touches each frame see it.
                TapScript.lastTap = point
                Touches.down(at: point)
                Display.dispatchAfter?(Display.dispatchTime!(0, 150_000_000), Updates.mainQueue, nil) { _ in Touches.up(at: TapScript.lastTap) }
            case .drag(let start, let end):
                TapScript.drag(from: start, to: end)
            case .pinch(let center, let from, let to):
                TapScript.pinch(around: center, from: from, to: to)
            case .doubleTap(let point):
                TapScript.lastTap = point
                Touches.down(at: point)
                Display.dispatchAfter?(Display.dispatchTime!(0, 60_000_000), Updates.mainQueue, nil) { _ in
                    Touches.up(at: TapScript.lastTap)
                    Display.dispatchAfter?(Display.dispatchTime!(0, 120_000_000), Updates.mainQueue, nil) { _ in
                        Touches.down(at: TapScript.lastTap)
                        Display.dispatchAfter?(Display.dispatchTime!(0, 60_000_000), Updates.mainQueue, nil) { _ in
                            Touches.up(at: TapScript.lastTap)
                        }
                    }
                }
            case .type(let text):
                Keyboard.insert(text)
            case .key(let name):
                switch name {
                case "return": Keyboard.returnKey()
                case "backspace": Keyboard.deleteBackward()
                case "escape": Keyboard.escape()
                default: break
                }
            }
            TapScript.stepsDone += 1
            let number = TapScript.stepsDone
            Deferred.run(after: 1) { Snapshot.writeNumbered(number) }
            TapScript.next()
        }
    }

    /// The points a drag under way has still to move through.
    nonisolated(unsafe) private static var dragPath: [CGPoint] = []

    /// Down at `start`, through ten moves 25 ms apart to `end`, and up.
    private static func drag(from start: CGPoint, to end: CGPoint) {
        dragPath = (1...10).map { step in
            let fraction = CGFloat(step) / 10
            return CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction)
        }
        Touches.down(at: start)
        moveAlongDrag()
    }

    /// The second finger's number, as the platform's would be.
    private static let pinchFinger: UInt64 = 0x7E57

    /// The two fingers' points a pinch under way has still to move through.
    nonisolated(unsafe) private static var pinchPath: [(CGPoint, CGPoint)] = []

    /// Two fingers either side of `center`, `from` points apart, through
    /// ten moves 25 ms apart to `to` apart, and up.
    private static func pinch(around center: CGPoint, from: CGFloat, to: CGFloat) {
        func points(_ distance: CGFloat) -> (CGPoint, CGPoint) {
            (CGPoint(x: center.x - distance / 2, y: center.y), CGPoint(x: center.x + distance / 2, y: center.y))
        }
        let start = points(from)
        Touches.down(at: start.0)
        Touches.down(at: start.1, finger: pinchFinger)
        pinchPath = (1...10).map { points(from + (to - from) * CGFloat($0) / 10) }
        moveAlongPinch()
    }

    private static func moveAlongPinch() {
        Display.dispatchAfter?(Display.dispatchTime!(0, 25_000_000), Updates.mainQueue, nil) { _ in
            guard !TapScript.pinchPath.isEmpty else { return }
            let (first, second) = TapScript.pinchPath.removeFirst()
            Touches.move(to: first)
            Touches.move(to: second, finger: TapScript.pinchFinger)
            if TapScript.pinchPath.isEmpty {
                Touches.up(at: second, finger: TapScript.pinchFinger)
                Touches.up(at: first)
            } else {
                TapScript.moveAlongPinch()
            }
        }
    }

    private static func moveAlongDrag() {
        Display.dispatchAfter?(Display.dispatchTime!(0, 25_000_000), Updates.mainQueue, nil) { _ in
            guard !TapScript.dragPath.isEmpty else { return }
            let point = TapScript.dragPath.removeFirst()
            Touches.move(to: point)
            if TapScript.dragPath.isEmpty { Touches.up(at: point) } else { TapScript.moveAlongDrag() }
        }
    }
}

import CPerryGeometry
import Glibc
import PerryObjCInterop
import PerryScrollPhysics

// Touches in scroll views, as AppKit handles them on a touch display: a
// finger dragged over a scroll view's content scrolls it, and coasts on
// with momentum after a flick; a tap there clicks; a finger held still
// for half a second becomes the mouse pressed there, so dragging on drags
// rows or selects text. Touches elsewhere, and in web views (which handle
// their own), are the emulated mouse events SDL makes of them.
//
// A touch over a scroll view is held back until it is clear which it is:
// the content hears of it only as a click or a long press.

final class TouchScrolling {
    private enum Mode { case pending, scrolling, pressing }

    private var down: NSEvent?
    private weak var scrollView: NSScrollView?
    private var mode = Mode.pending
    private var start = CGPoint.zero, last = CGPoint.zero
    private var samples = VelocityTracker()
    /// Bumped by each touch, so a long press or coasting from an earlier
    /// one stops.
    private var generation = 0
    /// How far the finger moved the content since the last frame: applied
    /// once a frame, as the window draws, not for each move.
    private var pending = CGPoint.zero

    /// Moves the content as the finger moved it, before a frame is drawn.
    func flush() {
        guard pending != .zero, let scrollView else { return }
        let delta = pending
        pending = .zero
        scrollView.scroll(contentBy: delta)
    }

    /// Seconds a finger stays still before it presses the mouse.
    static let longPress = 0.5

    /// Whether `event` (a touch's emulated mouse event) went to scrolling,
    /// so the window doesn't send it on.
    func handle(_ event: NSEvent, in window: NSWindow) -> Bool {
        switch event.type {
        case .leftMouseDown:
            generation += 1
            pending = .zero
            guard let view = window.viewAt(event.locationInWindow), let scrollView = Self.scrollView(for: view) else { return false }
            (down, self.scrollView, mode) = (event, scrollView, .pending)
            (start, last) = (event.locationInWindow, event.locationInWindow)
            samples.reset(x: Double(start.x), y: Double(start.y), time: Clock.now)
            let generation = generation
            Dispatch.after(nanoseconds: Int64(Self.longPress * 1e9)) { [weak self, weak window] in
                guard let self, let window, self.generation == generation, self.mode == .pending, let down = self.down else { return }
                self.mode = .pressing
                window.dispatchMouseDown(down)
            }
            return true
        case .leftMouseDragged:
            guard down != nil, let scrollView else { return false }
            let point = event.locationInWindow
            samples.add(x: Double(point.x), y: Double(point.y), time: Clock.now)
            switch mode {
            case .pressing:
                return false
            case .pending:
                guard hypot(point.x - start.x, point.y - start.y) >= CGFloat(panThreshold) else { return true }
                mode = .scrolling
                last = start
                fallthrough
            case .scrolling:
                // The content follows the finger: window y goes up.
                pending.x += point.x - last.x
                pending.y += last.y - point.y
                last = point
                Windows.layersChanged()
                return true
            }
        case .leftMouseUp:
            guard let down else { return false }
            self.down = nil
            switch mode {
            case .pending:
                // A tap: the click the content waited for.
                window.dispatchMouseDown(down)
                return false
            case .pressing:
                return false
            case .scrolling:
                flush()
                let velocity = samples.velocity
                if let scrollView, let deceleration = Deceleration(velocity: (velocity.x, -velocity.y), time: Clock.now) {
                    coast(scrollView, deceleration, generation: generation)
                }
                return true
            }
        default:
            return false
        }
    }

    /// Momentum after a flick, a step every frame until it slows to a stop
    /// or meets an edge, or another touch begins.
    private func coast(_ scrollView: NSScrollView, _ deceleration: Deceleration, generation: Int) {
        Dispatch.after(nanoseconds: 16_000_000) { [weak self, weak scrollView] in
            guard let self, let scrollView, self.generation == generation else { return }
            var deceleration = deceleration
            let distance = deceleration.step(at: Clock.now)
            let moved = scrollView.scroll(contentBy: CGPoint(x: CGFloat(distance.x), y: CGFloat(distance.y)))
            if moved || distance == (0, 0), !deceleration.isFinished { self.coast(scrollView, deceleration, generation: generation) }
        }
    }

    /// The scroll view a touch on `view` scrolls: the nearest around it
    /// with somewhere to scroll and one-finger scrolling; none in a web
    /// view or on a scroller.
    private static func scrollView(for view: NSView) -> NSScrollView? {
        var current: NSView? = view
        while let candidate = current {
            if candidate.as(WKWebView.self) != nil || candidate.as(WebView.self) != nil || candidate.as(NSScroller.self) != nil { return nil }
            if let scrollView = candidate.as(NSScrollView.self), scrollView.canScroll, scrollView.minimumNumberOfTouchesForScrolling == 1 {
                return scrollView
            }
            current = candidate.superview
        }
        return nil
    }
}

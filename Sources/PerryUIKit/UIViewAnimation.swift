import CPerryGeometry
import PerryObjCInterop

// UIView's animations, both the block-based API and the older
// +beginAnimations:context: / +commitAnimations one. A change to a view's
// layer inside a block animates: the layer asks the view for its action,
// and the view gives a basic animation with the block's duration, delay
// and curve, which QuartzCore runs. Completion blocks, and the delegate's
// will-start and did-stop selectors, come after the delay and duration. A
// delegate with no did-stop selector set gets
// -animationDidStop:finished:context: if it has it, as early iOS did.

/// Work for the main queue after a delay.
enum Deferred {
    private final class Work {
        let body: () -> Void
        init(_ body: @escaping () -> Void) { self.body = body }
    }

    static func run(after seconds: Double, _ body: @escaping () -> Void) {
        guard let after = Display.dispatchAfter, let time = Display.dispatchTime else {
            Updates.afterPass(body)
            return
        }
        let context = Unmanaged.passRetained(Work(body)).toOpaque()
        after(time(0, Int64(max(0, seconds) * 1_000_000_000)), Updates.mainQueue, context) { context in
            guard let context else { return }
            Unmanaged<Work>.fromOpaque(context).takeRetainedValue().body()
        }
    }
}

/// One +beginAnimations:context: block's settings.
struct AnimationBlock {
    var identifier: NSObject?
    var context: UnsafeMutableRawPointer?
    var duration = 0.2
    var delay = 0.0
    var delegate: NSObject?
    var willStart: ObjCSelector?
    var didStop: ObjCSelector?
    var curve = 0
    var repeatCount: Float = 0
    var autoreverses = false
}

enum ViewAnimations {
    nonisolated(unsafe) static var blocks: [AnimationBlock] = []
    nonisolated(unsafe) static var enabled = true

    /// The animation blocks running their changes: each change to a view's
    /// layer inside one animates with its timing.
    struct Context {
        var duration: Double
        var delay: Double
        /// UIViewAnimationCurve: ease in out 0, ease in 1, ease out 2, linear 3.
        var curve: Int
        var repeats = false
        var autoreverses = false
    }

    nonisolated(unsafe) static var contexts: [Context] = []

    /// The keys of a view's layer that animate.
    static let animatedKeys: Set<String> = ["position", "bounds", "opacity", "transform", "backgroundColor", "cornerRadius",
                                            "borderWidth", "borderColor", "shadowOpacity", "contentsRect"]

    /// Runs `animations` with changes animating as `context` says.
    static func run(_ context: Context, _ animations: ObjCBlock?) {
        contexts.append(context)
        animations.map { Blocks.call($0) }
        contexts.removeLast()
    }

    /// The animation for a change to `key` now, if one is animating.
    static func action(forKey key: String) -> NSObject? {
        guard enabled, animatedKeys.contains(key) else { return nil }
        let context: Context
        if let last = contexts.last {
            context = last
        } else if let block = blocks.last {
            context = Context(duration: block.duration, delay: block.delay, curve: block.curve, repeats: block.repeatCount > 0,
                              autoreverses: block.autoreverses)
        } else {
            return nil
        }
        guard context.duration > 0 else { return nil }
        let animation = CABasicAnimation.make(keyPath: key)
        animation.setDuration(context.duration)
        if context.delay > 0 {
            animation.setBeginTime(Clock.now + context.delay)
            // The old value holds until the animation begins.
            animation.setFillMode("backwards")
        }
        let names = ["easeInEaseOut", "easeIn", "easeOut", "linear"]
        animation.setTimingFunction(CAMediaTimingFunction.named(names[min(max(context.curve, 0), 3)]))
        if context.repeats { animation.setRepeatCount(.infinity) }
        if context.autoreverses { animation.setAutoreverses(true) }
        return animation
    }

    /// Runs `completion` (a block taking BOOL finished) when the animation
    /// would have finished.
    static func complete(_ completion: ObjCBlock?, delay: Double, duration: Double) {
        guard let completion else { return }
        Deferred.run(after: delay + duration) {
            Blocks.call(completion, true)
            Updates.schedule()
        }
    }

    /// The delegate's callbacks for a committed block.
    static func notify(_ block: AnimationBlock) {
        guard let delegate = block.delegate else { return }
        let identifier = block.identifier?.objcObject, context = block.context
        Deferred.run(after: block.delay) {
            if let willStart = block.willStart, delegate.responds(to: willStart.name) {
                typealias Send = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeMutableRawPointer?,
                                                 UnsafeMutableRawPointer?) -> Void
                unsafeBitCast(ObjCRuntime.msgSend, to: Send.self)(delegate.objcObject, willStart.pointer, identifier, context)
            }
        }
        Deferred.run(after: block.delay + block.duration) {
            let didStop = block.didStop?.name ?? "animationDidStop:finished:context:"
            guard delegate.responds(to: didStop) else { return }
            typealias Send = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeMutableRawPointer?,
                                             UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
            let finished = NSNumber.make(bool: true)
            withExtendedLifetime(finished) {
                unsafeBitCast(ObjCRuntime.msgSend, to: Send.self)(delegate.objcObject, ObjCRuntime.selector(didStop), identifier,
                                                                 finished.objcObject, context)
            }
        }
    }

    static func modify(_ body: (inout AnimationBlock) -> Void) {
        guard !blocks.isEmpty else { return }
        body(&blocks[blocks.count - 1])
    }
}

@ObjCCategory("UIViewAnimationAdditions")
extension UIView {
    // MARK: Blocks

    @ObjCClassMethod("animateWithDuration:animations:")
    static func animate(duration: Double, animations: ObjCBlock?) {
        animate(duration: duration, delay: 0, options: 0, animations: animations, completion: nil)
    }

    @ObjCClassMethod("animateWithDuration:animations:completion:")
    static func animate(duration: Double, animations: ObjCBlock?, completion: ObjCBlock?) {
        animate(duration: duration, delay: 0, options: 0, animations: animations, completion: completion)
    }

    @ObjCClassMethod("animateWithDuration:delay:options:animations:completion:")
    /// UIViewAnimationOptions: repeat 1 << 3, autoreverse 1 << 4, the
    /// curve in bits 16 and 17.
    static func animate(duration: Double, delay: Double, options: UInt, animations: ObjCBlock?, completion: ObjCBlock?) {
        let context = ViewAnimations.Context(duration: duration, delay: delay, curve: Int((options >> 16) & 3),
                                             repeats: options & (1 << 3) != 0, autoreverses: options & (1 << 4) != 0)
        ViewAnimations.run(context, animations)
        ViewAnimations.complete(completion, delay: delay, duration: ViewAnimations.enabled ? duration : 0)
    }

    @ObjCClassMethod("animateWithDuration:delay:usingSpringWithDamping:initialSpringVelocity:options:animations:completion:")
    static func animate(duration: Double, delay: Double, damping: CGFloat, velocity: CGFloat, options: UInt,
                        animations: ObjCBlock?, completion: ObjCBlock?) {
        animate(duration: duration, delay: delay, options: options, animations: animations, completion: completion)
    }

    @ObjCClassMethod("animateKeyframesWithDuration:delay:options:animations:completion:")
    static func animateKeyframes(duration: Double, delay: Double, options: UInt, animations: ObjCBlock?, completion: ObjCBlock?) {
        animate(duration: duration, delay: delay, options: options, animations: animations, completion: completion)
    }

    @ObjCClassMethod("addKeyframeWithRelativeStartTime:relativeDuration:animations:")
    static func addKeyframe(start: Double, duration: Double, animations: ObjCBlock?) {
        // Within the keyframe animation's block: this part of its time.
        guard let outer = ViewAnimations.contexts.last else {
            animations.map { Blocks.call($0) }
            return
        }
        let context = ViewAnimations.Context(duration: outer.duration * duration, delay: outer.delay + outer.duration * start, curve: 3)
        ViewAnimations.run(context, animations)
    }

    @ObjCClassMethod("transitionWithView:duration:options:animations:completion:")
    static func transition(with view: UIView?, duration: Double, options: UInt, animations: ObjCBlock?, completion: ObjCBlock?) {
        animate(duration: duration, delay: 0, options: options, animations: animations, completion: completion)
    }

    /// The new view takes the old one's place in its superview, unless
    /// the options keep both (UIViewAnimationOptionShowHideTransitionViews).
    @ObjCClassMethod("transitionFromView:toView:duration:options:completion:")
    static func transition(from view: UIView, to other: UIView, duration: Double, options: UInt, completion: ObjCBlock?) {
        if options & (1 << 8) != 0 {
            view.setHidden(true)
            other.setHidden(false)
        } else if let superviewObject = view.state.superview {
            let superview = UIView.wrap(superviewObject)
            superview.insertSubview(other, above: view)
            view.removeFromSuperview()
        }
        ViewAnimations.complete(completion, delay: 0, duration: duration)
    }

    @ObjCClassMethod("performWithoutAnimation:")
    static func performWithoutAnimation(_ actions: ObjCBlock?) {
        let enabled = ViewAnimations.enabled
        ViewAnimations.enabled = false
        actions.map { Blocks.call($0) }
        ViewAnimations.enabled = enabled
    }

    @ObjCClassMethod("areAnimationsEnabled") static func areAnimationsEnabled() -> Bool { ViewAnimations.enabled }
    @ObjCClassMethod("setAnimationsEnabled:") static func setAnimationsEnabled(_ enabled: Bool) { ViewAnimations.enabled = enabled }

    // MARK: Begin and commit

    @ObjCClassMethod("beginAnimations:context:")
    static func beginAnimations(_ identifier: NSObject?, context: UnsafeMutableRawPointer?) {
        ViewAnimations.blocks.append(AnimationBlock(identifier: identifier, context: context))
    }

    @ObjCClassMethod("commitAnimations")
    static func commitAnimations() {
        guard let block = ViewAnimations.blocks.popLast() else { return }
        var committed = block
        if !ViewAnimations.enabled { committed.duration = 0 }
        ViewAnimations.notify(committed)
    }

    @ObjCClassMethod("setAnimationDuration:")
    static func setAnimationDuration(_ duration: Double) { ViewAnimations.modify { $0.duration = duration } }
    @ObjCClassMethod("setAnimationDelay:")
    static func setAnimationDelay(_ delay: Double) { ViewAnimations.modify { $0.delay = delay } }
    @ObjCClassMethod("setAnimationDelegate:")
    static func setAnimationDelegate(_ delegate: NSObject?) { ViewAnimations.modify { $0.delegate = delegate } }
    @ObjCClassMethod("setAnimationWillStartSelector:")
    static func setAnimationWillStartSelector(_ selector: ObjCSelector?) { ViewAnimations.modify { $0.willStart = selector } }
    @ObjCClassMethod("setAnimationDidStopSelector:")
    static func setAnimationDidStopSelector(_ selector: ObjCSelector?) { ViewAnimations.modify { $0.didStop = selector } }
    @ObjCClassMethod("setAnimationStartDate:") static func setAnimationStartDate(_ date: NSObject?) {}
    @ObjCClassMethod("setAnimationCurve:") static func setAnimationCurve(_ curve: Int) { ViewAnimations.modify { $0.curve = curve } }
    @ObjCClassMethod("setAnimationRepeatCount:")
    static func setAnimationRepeatCount(_ count: Float) { ViewAnimations.modify { $0.repeatCount = count } }
    @ObjCClassMethod("setAnimationRepeatAutoreverses:")
    static func setAnimationRepeatAutoreverses(_ autoreverses: Bool) { ViewAnimations.modify { $0.autoreverses = autoreverses } }
    @ObjCClassMethod("setAnimationBeginsFromCurrentState:") static func setAnimationBeginsFromCurrentState(_ begins: Bool) {}
    @ObjCClassMethod("setAnimationTransition:forView:cache:")
    static func setAnimationTransition(_ transition: Int, for view: UIView?, cache: Bool) {}
}

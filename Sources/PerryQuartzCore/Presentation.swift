import CPerryGeometry
import Glibc
import PerryObjCInterop

// The animation engine: a layer as it presents is its model with each of
// its animations' values at the current media time applied, in the order
// they were added. Delegates hear animations start and stop as their
// times pass, and finished animations are removed unless told to stay.

enum Presentation {
    /// The layers with animations.
    nonisolated(unsafe) private static var layers: [UnsafeMutableRawPointer] = []
    nonisolated(unsafe) private static var settleAt: Double?

    static func track(_ layer: CALayer) {
        if !layers.contains(layer.objcObject) { layers.append(layer.objcObject) }
        settle()
    }

    static func forget(_ layer: UnsafeMutableRawPointer) { layers.removeAll { $0 == layer } }

    /// Whether anything is animating: frames must keep coming.
    static var animating: Bool { layers.contains { !CALayer.state(of: $0).animations.isEmpty } }

    /// The layer as it presents now.
    static func state(of layer: CALayer) -> LayerState { presented(layer).state }

    /// The layer, and a shape layer's shape, as they present now: the model
    /// itself when nothing animates it.
    static func presented(_ layer: CALayer) -> (state: LayerState, shape: ShapeLayerState?) {
        let model = layer.state
        let shapeModel = layer.as(CAShapeLayer.self)?.shape
        let modifiers = PresentationModifiers.values(on: layer.objcObject)
        guard !model.animations.isEmpty || !modifiers.isEmpty else { return (model, shapeModel) }
        let state = model.copy()
        let shape = shapeModel?.copy()
        let now = Clock.now
        for entry in model.animations {
            evaluate(entry.animation, at: now, keyPath: nil, model: { AnimatedValue.value(of: model, shape: shapeModel, $0) }) { key, value in
                value.write(to: state, shape: shape, key)
            }
        }
        // Presentation modifiers' values, over the animations'.
        for modifier in modifiers {
            guard var value = AnimatedValue(boxed: modifier.value, key: modifier.keyPath) else { continue }
            if modifier.additive, let base = AnimatedValue.value(of: state, shape: shape, modifier.keyPath) {
                value = AnimatedValue.add(base, value)
            }
            value.write(to: state, shape: shape, modifier.keyPath)
        }
        return (state, shape)
    }

    // MARK: Evaluation

    /// The animation's values at `now`, given to `emit` by key path; nothing
    /// when it has no effect then.
    /// A group's animations without durations of their own last as long as
    /// it does.
    static func evaluate(_ animation: CAAnimation, at now: Double, keyPath inherited: String?, groupDuration: Double? = nil,
                         model: (String) -> AnimatedValue?, emit: (String, AnimatedValue) -> Void) {
        let state = animation.state
        if animation.is(CAAnimationGroup.self) {
            let duration = state.duration > 0 ? state.duration : groupDuration ?? 0.25
            guard let fraction = fraction(state, at: now, duration: duration) else { return }
            let local = fraction * duration
            for child in state.values["animations"]?.as(NSArray.self)?.elements ?? [] {
                guard let child = child.as(CAAnimation.self) else { continue }
                evaluate(child, at: local, keyPath: nil, groupDuration: duration, model: model, emit: emit)
            }
            return
        }
        guard !animation.is(CATransition.self), let key = animation.keyPath() ?? inherited, let base = model(key) else { return }
        let spring = animation.is(CASpringAnimation.self) ? Spring(state) : nil
        let duration = state.duration > 0 ? state.duration : spring?.settlingDuration ?? groupDuration ?? 0.25
        guard let fraction = fraction(state, at: now, duration: duration) else { return }
        let value: AnimatedValue?
        if animation.is(CAKeyframeAnimation.self) {
            value = keyframe(animation, key: key, at: state.timingFunction?.value(at: fraction) ?? fraction)
        } else {
            let progress = spring.map { $0.value(at: fraction * duration) } ?? state.timingFunction?.value(at: fraction) ?? fraction
            value = basic(animation, key: key, base: base, at: progress)
        }
        guard var value else { return }
        if state.additive { value = AnimatedValue.add(base, value) }
        emit(key, value)
    }

    /// How far through its duration the animation is at `now`, 0 to 1,
    /// after its begin time, speed, offset, repeats and reversal; nil when
    /// it has not begun or has ended and does not fill.
    static func fraction(_ state: AnimationState, at now: Double, duration: Double) -> Double? {
        let fillsBackwards = state.fillMode == "backwards" || state.fillMode == "both"
        let fillsForwards = state.fillMode == "forwards" || state.fillMode == "both"
        var t = (now - state.beginTime) * Double(state.speed) + state.timeOffset
        guard duration > 0 else { return t >= 0 || fillsBackwards ? 1 : nil }
        let cycle = duration * (state.autoreverses ? 2 : 1)
        let total = active(state, duration: duration)
        if t < 0 {
            guard fillsBackwards else { return nil }
            t = 0
        }
        if t >= total {
            guard fillsForwards else { return nil }
            // The end of the last cycle: back at the start when it reversed.
            let ends = total / cycle
            let partial = ends - ends.rounded(.down)
            if partial == 0 { return state.autoreverses ? 0 : 1 }
            t = total
        }
        let local = t.truncatingRemainder(dividingBy: cycle)
        return local <= duration ? local / duration : (2 * duration - local) / duration
    }

    /// How long the animation runs, repeats included, in its own time.
    static func active(_ state: AnimationState, duration: Double) -> Double {
        let cycle = duration * (state.autoreverses ? 2 : 1)
        if state.repeatDuration > 0 { return state.repeatDuration }
        let count = state.repeatCount > 0 ? Double(state.repeatCount) : 1
        return count.isInfinite ? .infinity : cycle * count
    }

    /// When the animation ends on the media clock; infinity when it repeats
    /// for ever.
    static func end(of animation: CAAnimation) -> Double {
        let state = animation.state
        let duration = state.duration > 0 ? state.duration
            : animation.is(CASpringAnimation.self) ? Spring(state).settlingDuration : 0.25
        let speed = Double(state.speed)
        guard speed > 0 else { return .infinity }
        return state.beginTime + max(active(state, duration: duration) - state.timeOffset, 0) / speed
    }

    /// From, to and by values, each falling back on the model's.
    private static func basic(_ animation: CAAnimation, key: String, base: AnimatedValue, at progress: Double) -> AnimatedValue? {
        let function = animation.valueFunction()?.as(CAValueFunction.self)
        func value(_ name: String) -> AnimatedValue? {
            guard let boxed = animation.state.values[name] else { return nil }
            if let function, key == "transform", let number = AnimatedValue(boxed: boxed, key: "opacity"), case .number(let amount) = number {
                return .transform(function.transform(amount))
            }
            return AnimatedValue(boxed: boxed, key: key)
        }
        let (from, to, by) = (value("fromValue"), value("toValue"), value("byValue"))
        let start: AnimatedValue, end: AnimatedValue
        switch (from, to, by) {
        case (let from?, let to?, _): (start, end) = (from, to)
        case (let from?, nil, let by?): (start, end) = (from, AnimatedValue.add(from, by))
        case (nil, let to?, let by?): (start, end) = (AnimatedValue.subtract(to, by), to)
        case (let from?, nil, nil): (start, end) = (from, animation.state.additive ? zero(like: base) : base)
        case (nil, let to?, nil): (start, end) = (animation.state.additive ? zero(like: base) : base, to)
        case (nil, nil, let by?): (start, end) = (base, AnimatedValue.add(base, by))
        default: return nil
        }
        return AnimatedValue.interpolate(start, end, progress)
    }

    private static func zero(like value: AnimatedValue) -> AnimatedValue {
        switch value {
        case .number: return .number(0)
        case .point: return .point(.zero)
        case .size: return .size(.zero)
        case .rect: return .rect(.zero)
        case .transform: return .transform(.identity)
        case .color: return .color([0, 0, 0, 0])
        case .object: return value
        }
    }

    /// Values at key times, or a point along a path.
    private static func keyframe(_ animation: CAAnimation, key: String, at fraction: Double) -> AnimatedValue? {
        if let path = animation.path() {
            return PathTrimming.point(at: CGFloat(fraction), along: path).map { .point($0) }
        }
        let values = animation.values()?.as(NSArray.self)?.elements.compactMap { AnimatedValue(boxed: $0, key: key) } ?? []
        guard let first = values.first else { return nil }
        guard values.count > 1 else { return first }
        var times = animation.keyTimes()?.as(NSArray.self)?.elements.map { $0.sendDoubleValue() } ?? []
        let discrete = animation.calculationMode() == "discrete"
        if times.count != values.count {
            let segments = Double(discrete ? values.count : values.count - 1)
            times = (0..<values.count).map { Double($0) / segments }
        }
        if discrete {
            let index = times.lastIndex { $0 <= fraction } ?? 0
            return values[min(index, values.count - 1)]
        }
        guard let segment = (0..<values.count - 1).first(where: { fraction <= times[$0 + 1] }) else { return values.last }
        let span = times[segment + 1] - times[segment]
        var local = span > 0 ? (fraction - times[segment]) / span : 1
        let functions = animation.timingFunctions()?.as(NSArray.self)?.elements ?? []
        if segment < functions.count, let function = functions[segment].as(CAMediaTimingFunction.self) { local = function.value(at: local) }
        return AnimatedValue.interpolate(values[segment], values[segment + 1], local)
    }

    // MARK: Starting and stopping

    /// Tells delegates of animations that have started and stopped, removes
    /// those finished, and comes back when the next one starts or ends.
    static func settle() {
        let now = Clock.now
        var next = Double.infinity
        for layerObject in layers {
            let state = CALayer.state(of: layerObject)
            var finished: [(key: String, animation: CAAnimation)] = []
            for entry in state.animations {
                let animation = entry.animation
                if !animation.state.started {
                    if now >= animation.state.beginTime {
                        animation.state.started = true
                        notify(animation, "animationDidStart:")
                    } else {
                        next = min(next, animation.state.beginTime)
                    }
                }
                let end = end(of: animation)
                if now >= end { finished.append(entry) } else { next = min(next, end) }
            }
            for entry in finished where entry.animation.state.removedOnCompletion {
                state.animations.removeAll { $0.animation.objcObject == entry.animation.objcObject }
                stopped(entry.animation, on: CALayer.wrap(layerObject), finished: true)
            }
        }
        layers.removeAll { CALayer.state(of: $0).animations.isEmpty }
        Compositing.changed()
        guard next.isFinite, next != settleAt else { return }
        settleAt = next
        Dispatch.onMain(after: max(next - Clock.now, 0) + 0.001) {
            settleAt = nil
            settle()
        }
    }

    /// Tells the delegate the animation stopped, once.
    static func stopped(_ animation: CAAnimation, on layer: CALayer, finished: Bool) {
        guard animation.state.values["__perry.stopped"] == nil else { return }
        animation.state.values["__perry.stopped"] = NSNumber.make(bool: true)
        guard let delegate = animation.state.delegate, delegate.responds(to: "animationDidStop:finished:") else { return }
        delegate.sendAnimationDidStop(animation, finished: finished)
    }

    private static func notify(_ animation: CAAnimation, _ selector: String) {
        guard let delegate = animation.state.delegate, delegate.responds(to: selector) else { return }
        delegate.sendAnimationDidStart(animation)
    }
}

/// Running the action for a changed property, as Core Animation does
/// within a transaction.
enum Actions {
    /// Whether a change to the layer may have an action: its delegate gives
    /// them, or it is a standalone layer already drawn.
    static func wanted(for layer: CALayer) -> Bool {
        guard !CATransaction.disableActions() else { return false }
        let state = layer.state
        if let delegate = state.delegate { return NSObject(delegate).responds(to: "actionForLayer:forKey:") }
        return state.rendered && state.superlayer != nil
    }

    /// Asks the layer for the action for `key` and runs it: an animation
    /// with no values of its own animates from the old value.
    static func run(for layer: CALayer, key: String, from old: AnimatedValue) {
        guard let action = layer.sendActionForKey(key), !action.is(NSNull.self) else { return }
        if let animation = action.as(CAAnimation.self) {
            let values = animation.state.values
            if values["fromValue"] == nil, values["toValue"] == nil, values["byValue"] == nil {
                animation.setFromValue(old.boxed())
            }
            if animation.keyPath() == nil { animation.setKeyPath(key) }
            layer.addAnimation(animation, forKey: key)
            return
        }
        if action.responds(to: "runActionForKey:object:arguments:") { action.sendRunAction(forKey: key, object: layer, arguments: nil) }
    }
}

/// Telling the live view the layer tree has changed, so it draws a frame.
enum Compositing {
    nonisolated(unsafe) static var dirty = true
    nonisolated(unsafe) static var handler: (@convention(c) () -> Void)?
    nonisolated(unsafe) private static var pending = false

    static func changed() {
        dirty = true
        guard let handler, !pending else { return }
        pending = true
        Dispatch.onMain {
            pending = false
            handler()
        }
    }
}

/// UIKit's display registers a function to hear of changes to layers.
@c(_PerryCASetChangeHandler)
public func PerryCASetChangeHandler(_ handler: (@convention(c) () -> Void)?) { Compositing.handler = handler }

/// Whether the layers have changed since the last frame, or animate.
@c(_PerryCANeedsDisplay)
public func PerryCANeedsDisplay() -> Bool {
    defer { Compositing.dirty = false }
    return Compositing.dirty || Presentation.animating
}

/// Transforms from a value, by name, as an animation of "transform"
/// applies its numbers.
final class ValueFunctionState {
    var name = ""
}

@ObjCClass("CAValueFunction")
open class CAValueFunction: NSObject {
    var state = ValueFunctionState()

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCClassMethod("functionWithName:")
    static func function(_ cls: ObjCClass, name: String) -> NSObject {
        let function = cls.object.allocated().initialized().unsafeCast(to: CAValueFunction.self)
        function.state.name = name
        return function
    }

    @ObjCMethod("name") func name() -> String { state.name }

    func transform(_ value: Double) -> CATransform3D {
        switch state.name {
        case "rotateX": return .rotation(value, 1, 0, 0)
        case "rotateY": return .rotation(value, 0, 1, 0)
        case "rotateZ": return .rotation(value, 0, 0, 1)
        case "scale": return .scale(value, value, value)
        case "scaleX": return .scale(value, 1, 1)
        case "scaleY": return .scale(1, value, 1)
        case "scaleZ": return .scale(1, 1, value)
        case "translateX": return .translation(value, 0, 0)
        case "translateY": return .translation(0, value, 0)
        case "translateZ": return .translation(0, 0, value)
        default: return .identity
        }
    }
}

extension NSObject {
    @ObjCMethod("actionForKey:") func sendActionForKey(_ key: String) -> NSObject?
    @ObjCMethod("animationDidStart:") func sendAnimationDidStart(_ animation: CAAnimation)
    @ObjCMethod("animationDidStop:finished:") func sendAnimationDidStop(_ animation: CAAnimation, finished: Bool)
}

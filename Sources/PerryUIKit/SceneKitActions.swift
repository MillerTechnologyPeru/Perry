import CPerryGeometry
import Glibc
import PerryObjCInterop

// SceneKit's actions: a node's changes over time, run by the view's frames.
// An action is its definition (a move, a rotation, a fade, a sequence of
// actions...) with a duration, timing mode and speed; running it on a node
// makes a runner that keeps what it needs between frames, so one action can
// run on any number of nodes at once. A runner is given each frame's time
// and gives back what it did not use once it is done, which is how a
// sequence goes on to its next action within the same frame.

indirect enum SCNActionDef {
    case move(SCNVector3, by: Bool)
    case rotateEuler(SCNVector3, by: Bool, shortest: Bool)
    case rotateAxis(axis: SCNVector3, angle: Float, by: Bool)
    case scale(SCNVector3, by: Bool)
    case fade(Float, by: Bool)
    case hide(Bool)
    case wait
    case sequence([SCNAction])
    case group([SCNAction])
    case repeatCount(SCNAction, Int)
    case forever(SCNAction)
    case remove
    case block(ObjCBlock)
    case custom(ObjCBlock)
    case nothing
}

final class SCNActionState: ObjectState {
    var def = SCNActionDef.nothing
    var duration = 0.0
    /// SCNActionTimingMode: linear 0, ease in 1, ease out 2, ease in ease out 3.
    var timing = 0
    var speed: CGFloat = 1
}

@ObjCClass("SCNAction")
open class SCNAction: NSObject {
    static let states = StateTable<SCNActionState>()
    var action: SCNActionState { SCNAction.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        SCNAction.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SCNAction.objCClass.pointer)
    }

    static func make(_ def: SCNActionDef, duration: Double = 0) -> SCNAction {
        let made = SCNAction.objCClass.object.allocated().unsafeCast(to: SCNAction.self)
        made.action.def = def
        made.action.duration = max(duration, 0)
        return made
    }

    private static func vector(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> SCNVector3 { SCNVector3(x: Float(x), y: Float(y), z: Float(z)) }

    @ObjCMethod("init") func initialize() -> Self { self }

    // MARK: Moving, rotating, scaling

    @ObjCClassMethod("moveByX:y:z:duration:")
    static func move(_ cls: ObjCClass, byX x: CGFloat, y: CGFloat, z: CGFloat, duration: Double) -> SCNAction {
        make(.move(vector(x, y, z), by: true), duration: duration)
    }
    @ObjCClassMethod("moveBy:duration:")
    static func move(_ cls: ObjCClass, by delta: SCNVector3, duration: Double) -> SCNAction { make(.move(delta, by: true), duration: duration) }
    @ObjCClassMethod("moveTo:duration:")
    static func move(_ cls: ObjCClass, to position: SCNVector3, duration: Double) -> SCNAction { make(.move(position, by: false), duration: duration) }
    @ObjCClassMethod("rotateByX:y:z:duration:")
    static func rotate(_ cls: ObjCClass, byX x: CGFloat, y: CGFloat, z: CGFloat, duration: Double) -> SCNAction {
        make(.rotateEuler(vector(x, y, z), by: true, shortest: false), duration: duration)
    }
    @ObjCClassMethod("rotateToX:y:z:duration:")
    static func rotate(_ cls: ObjCClass, toX x: CGFloat, y: CGFloat, z: CGFloat, duration: Double) -> SCNAction {
        make(.rotateEuler(vector(x, y, z), by: false, shortest: false), duration: duration)
    }
    @ObjCClassMethod("rotateToX:y:z:duration:shortestUnitArc:")
    static func rotate(_ cls: ObjCClass, toX x: CGFloat, y: CGFloat, z: CGFloat, duration: Double, shortestUnitArc: Bool) -> SCNAction {
        make(.rotateEuler(vector(x, y, z), by: false, shortest: shortestUnitArc), duration: duration)
    }
    @ObjCClassMethod("rotateByAngle:aroundAxis:duration:")
    static func rotate(_ cls: ObjCClass, byAngle angle: CGFloat, aroundAxis axis: SCNVector3, duration: Double) -> SCNAction {
        make(.rotateAxis(axis: axis, angle: Float(angle), by: true), duration: duration)
    }
    @ObjCClassMethod("rotateToAxisAngle:duration:")
    static func rotate(_ cls: ObjCClass, toAxisAngle axisAngle: SCNVector4, duration: Double) -> SCNAction {
        make(.rotateAxis(axis: SCNVector3(x: axisAngle.x, y: axisAngle.y, z: axisAngle.z), angle: axisAngle.w, by: false), duration: duration)
    }
    @ObjCClassMethod("scaleBy:duration:")
    static func scale(_ cls: ObjCClass, by scale: CGFloat, duration: Double) -> SCNAction {
        make(.scale(vector(scale, scale, scale), by: true), duration: duration)
    }
    @ObjCClassMethod("scaleTo:duration:")
    static func scale(_ cls: ObjCClass, to scale: CGFloat, duration: Double) -> SCNAction {
        make(.scale(vector(scale, scale, scale), by: false), duration: duration)
    }

    // MARK: Fading, showing, waiting

    @ObjCClassMethod("fadeInWithDuration:")
    static func fadeIn(_ cls: ObjCClass, duration: Double) -> SCNAction { make(.fade(1, by: false), duration: duration) }
    @ObjCClassMethod("fadeOutWithDuration:")
    static func fadeOut(_ cls: ObjCClass, duration: Double) -> SCNAction { make(.fade(0, by: false), duration: duration) }
    @ObjCClassMethod("fadeOpacityBy:duration:")
    static func fadeOpacity(_ cls: ObjCClass, by factor: CGFloat, duration: Double) -> SCNAction { make(.fade(Float(factor), by: true), duration: duration) }
    @ObjCClassMethod("fadeOpacityTo:duration:")
    static func fadeOpacity(_ cls: ObjCClass, to opacity: CGFloat, duration: Double) -> SCNAction { make(.fade(Float(opacity), by: false), duration: duration) }
    @ObjCClassMethod("hide") static func hide(_ cls: ObjCClass) -> SCNAction { make(.hide(true)) }
    @ObjCClassMethod("unhide") static func unhide(_ cls: ObjCClass) -> SCNAction { make(.hide(false)) }
    @ObjCClassMethod("waitForDuration:") static func wait(_ cls: ObjCClass, duration: Double) -> SCNAction { make(.wait, duration: duration) }
    @ObjCClassMethod("waitForDuration:withRange:")
    static func wait(_ cls: ObjCClass, duration: Double, range: Double) -> SCNAction {
        make(.wait, duration: duration + (Double(random() % 1000) / 1000 - 0.5) * range)
    }

    // MARK: Combining

    @ObjCClassMethod("sequence:")
    static func sequence(_ cls: ObjCClass, actions: NSArray) -> SCNAction {
        make(.sequence(actions.elements.map { $0.unsafeCast(to: SCNAction.self) }))
    }
    @ObjCClassMethod("group:")
    static func group(_ cls: ObjCClass, actions: NSArray) -> SCNAction {
        make(.group(actions.elements.map { $0.unsafeCast(to: SCNAction.self) }))
    }
    @ObjCClassMethod("repeatAction:count:")
    static func repeatAction(_ cls: ObjCClass, action: SCNAction, count: Int) -> SCNAction { make(.repeatCount(action, count)) }
    @ObjCClassMethod("repeatActionForever:")
    static func repeatForever(_ cls: ObjCClass, action: SCNAction) -> SCNAction { make(.forever(action)) }

    // MARK: Doing something

    @ObjCClassMethod("removeFromParentNode") static func removeFromParent(_ cls: ObjCClass) -> SCNAction { make(.remove) }
    @ObjCClassMethod("runBlock:") static func run(_ cls: ObjCClass, block: ObjCBlock) -> SCNAction { make(.block(block)) }
    @ObjCClassMethod("customActionWithDuration:actionBlock:")
    static func custom(_ cls: ObjCClass, duration: Double, actionBlock: ObjCBlock) -> SCNAction { make(.custom(actionBlock), duration: duration) }
    /// Sounds are not played yet: the action is a no-op that takes no time.
    @ObjCClassMethod("playAudioSource:waitForCompletion:")
    static func playAudio(_ cls: ObjCClass, source: NSObject, waitForCompletion: Bool) -> SCNAction { make(.nothing) }

    // MARK: Properties

    @ObjCMethod("duration") func duration() -> Double { action.duration }
    @ObjCMethod("setDuration:") func setDuration(_ duration: Double) { action.duration = max(duration, 0) }
    @ObjCMethod("timingMode") func timingMode() -> Int { action.timing }
    @ObjCMethod("setTimingMode:") func setTimingMode(_ mode: Int) { action.timing = mode }
    @ObjCMethod("speed") func speed() -> CGFloat { action.speed }
    @ObjCMethod("setSpeed:") func setSpeed(_ speed: CGFloat) { action.speed = speed }

    /// The action that undoes this one, as far as one can: moves, turns, scales and fades by an amount
    /// are reversed, a sequence runs its reversed actions the other way round, and the rest is as it is.
    @ObjCMethod("reversedAction")
    func reversedAction() -> SCNAction {
        let state = action
        let def: SCNActionDef
        switch state.def {
        case .move(let v, true): def = .move(SCNVector3(x: -v.x, y: -v.y, z: -v.z), by: true)
        case .rotateEuler(let v, true, let shortest): def = .rotateEuler(SCNVector3(x: -v.x, y: -v.y, z: -v.z), by: true, shortest: shortest)
        case .rotateAxis(let axis, let angle, true): def = .rotateAxis(axis: axis, angle: -angle, by: true)
        case .scale(let v, true): def = .scale(SCNVector3(x: 1 / v.x, y: 1 / v.y, z: 1 / v.z), by: true)
        case .fade(let v, true): def = .fade(-v, by: true)
        case .fade(let v, false) where v == 1: def = .fade(0, by: false)
        case .fade(let v, false) where v == 0: def = .fade(1, by: false)
        case .hide(let hide): def = .hide(!hide)
        case .sequence(let actions): def = .sequence(actions.reversed().map { $0.reversedAction() })
        case .group(let actions): def = .group(actions.map { $0.reversedAction() })
        case .repeatCount(let inner, let count): def = .repeatCount(inner.reversedAction(), count)
        case .forever(let inner): def = .forever(inner.reversedAction())
        default: def = state.def
        }
        let made = SCNAction.make(def, duration: state.duration)
        made.action.timing = state.timing
        made.action.speed = state.speed
        return made
    }
}

// MARK: - Running

/// An action running on a node.
final class SCNRunning {
    let key: String?
    let action: SCNAction
    let runner: SCNRunner
    let completion: ObjCBlock?

    init(key: String?, action: SCNAction, completion: ObjCBlock?) {
        self.key = key
        self.action = action
        runner = SCNRunner(action)
        self.completion = completion
    }
}

final class SCNRunner {
    private let action: SCNAction
    private var elapsed = 0.0
    private var lastProgress: Float = 0
    private var started = false
    private var done = false
    // What a runner of one action keeps: where an absolute action began, its children's runners, a repeat's count.
    private var startPosition = SCNVector3(x: 0, y: 0, z: 0), startEuler = SCNVector3(x: 0, y: 0, z: 0), startScale = SCNVector3(x: 1, y: 1, z: 1)
    private var startOpacity: Float = 1
    private var startRotation = SCNMath.noRotation
    private var children: [SCNRunner] = []
    private var index = 0
    private var finishedChildren: [Double?] = []
    private var repeated = 0

    init(_ action: SCNAction) { self.action = action }

    /// Moves the action on by `dt` seconds; nil while it goes on, else the
    /// time it did not need.
    func advance(_ node: SCNNode, _ dt: Double) -> Double? {
        let state = action.action
        let speed = Double(state.speed)
        guard speed > 0 else { return nil }
        guard let left = run(node, dt * speed) else { return nil }
        return left / speed
    }

    private func run(_ node: SCNNode, _ dt: Double) -> Double? {
        let state = action.action
        switch state.def {
        case .hide(let hide):
            node.node.hidden = hide
            return dt
        case .remove:
            node.removeFromParentNode()
            return dt
        case .nothing:
            return dt
        case .block(let block):
            typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?) -> Void
            block.function(as: Invoke.self)(block.object, node.objcObject)
            return dt
        case .sequence(let actions):
            if children.isEmpty { children = actions.map(SCNRunner.init) }
            var left = dt
            while index < children.count {
                guard let remaining = children[index].advance(node, left) else { return nil }
                left = remaining
                index += 1
            }
            return left
        case .group(let actions):
            if children.isEmpty {
                children = actions.map(SCNRunner.init)
                finishedChildren = Array(repeating: nil, count: children.count)
            }
            var allDone = true, leftover = dt
            for i in children.indices {
                if finishedChildren[i] == nil { finishedChildren[i] = children[i].advance(node, dt) }
                if let left = finishedChildren[i] { leftover = min(leftover, left) } else { allDone = false }
            }
            return allDone ? leftover : nil
        case .repeatCount(let inner, let count):
            return runRepeat(node, dt, inner, count: count)
        case .forever(let inner):
            return runRepeat(node, dt, inner, count: nil)
        case .move, .rotateEuler, .rotateAxis, .scale, .fade, .wait, .custom:
            return runInterval(node, dt)
        }
    }

    private func runRepeat(_ node: SCNNode, _ dt: Double, _ inner: SCNAction, count: Int?) -> Double? {
        var left = dt
        var iterations = 0
        while count.map({ repeated < $0 }) ?? true {
            if children.isEmpty { children = [SCNRunner(inner)] }
            guard let remaining = children[0].advance(node, left) else { return nil }
            children = []
            repeated += 1
            // An action that takes no time must not spin: once per frame.
            if remaining >= left { iterations += 1; if iterations > 1 { return nil } }
            left = remaining
        }
        return left
    }

    private func runInterval(_ node: SCNNode, _ dt: Double) -> Double? {
        let state = action.action
        if !started {
            started = true
            let n = node.node
            startPosition = n.position
            startEuler = SCNMath.euler(n.rotation)
            startScale = n.scale
            startOpacity = Float(n.opacity)
            startRotation = n.rotation
        }
        let duration = state.duration
        var step = dt
        if duration > 0 {
            step = min(dt, duration - elapsed)
            elapsed += step
        } else {
            elapsed = 0
        }
        let linear = duration > 0 ? Float(elapsed / duration) : 1
        apply(node, progress: SCNRunner.eased(linear, mode: state.timing), elapsed: elapsed)
        if duration <= 0 || elapsed >= duration { return dt - step }
        return nil
    }

    private static func eased(_ p: Float, mode: Int) -> Float {
        switch mode {
        case 1: return p * p
        case 2: return 1 - (1 - p) * (1 - p)
        case 3: return p * p * (3 - 2 * p)
        default: return p
        }
    }

    private func apply(_ node: SCNNode, progress p: Float, elapsed: Double) {
        let n = node.node
        let step = p - lastProgress
        lastProgress = p
        switch action.action.def {
        case .move(let v, let by):
            if by {
                n.position = SCNVector3(x: n.position.x + v.x * step, y: n.position.y + v.y * step, z: n.position.z + v.z * step)
            } else {
                n.position = SCNVector3(x: startPosition.x + (v.x - startPosition.x) * p, y: startPosition.y + (v.y - startPosition.y) * p,
                                        z: startPosition.z + (v.z - startPosition.z) * p)
            }
        case .rotateEuler(let v, let by, let shortest):
            if by {
                let now = SCNMath.euler(n.rotation)
                n.rotation = SCNMath.quaternion(euler: SCNVector3(x: now.x + v.x * step, y: now.y + v.y * step, z: now.z + v.z * step))
            } else {
                func delta(_ target: Float, _ from: Float) -> Float {
                    var d = target - from
                    if shortest {
                        d = fmodf(d, 2 * .pi)
                        if d > .pi { d -= 2 * .pi } else if d < -.pi { d += 2 * .pi }
                    }
                    return d
                }
                n.rotation = SCNMath.quaternion(euler: SCNVector3(x: startEuler.x + delta(v.x, startEuler.x) * p,
                                                                  y: startEuler.y + delta(v.y, startEuler.y) * p,
                                                                  z: startEuler.z + delta(v.z, startEuler.z) * p))
            }
        case .rotateAxis(let axis, let angle, let by):
            if by {
                n.rotation = SCNMath.normalized(SCNMath.multiply(SCNMath.quaternion(axis: axis, angle: angle * step), n.rotation))
            } else {
                n.rotation = SCNMath.quaternion(axis: axis, angle: angle * p)
            }
        case .scale(let v, let by):
            if by {
                n.scale = SCNVector3(x: n.scale.x * powf(v.x, step), y: n.scale.y * powf(v.y, step), z: n.scale.z * powf(v.z, step))
            } else {
                n.scale = SCNVector3(x: startScale.x + (v.x - startScale.x) * p, y: startScale.y + (v.y - startScale.y) * p,
                                     z: startScale.z + (v.z - startScale.z) * p)
            }
        case .fade(let v, let by):
            n.opacity = CGFloat(by ? Float(n.opacity) + v * step : startOpacity + (v - startOpacity) * p)
        case .custom(let block):
            typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, CGFloat) -> Void
            block.function(as: Invoke.self)(block.object, node.objcObject, CGFloat(elapsed))
        default: break
        }
    }
}

// MARK: - Nodes

enum SCNActions {
    /// Moves every node's actions on by `dt` seconds, parents first.
    static func advance(_ node: SCNNode, _ dt: Double) {
        let state = node.node
        if !state.running.isEmpty {
            var finished: [SCNRunning] = []
            for run in state.running where run.runner.advance(node, dt) != nil { finished.append(run) }
            state.running.removeAll { run in finished.contains { $0 === run } }
            for run in finished {
                guard let completion = run.completion else { continue }
                typealias Invoke = @convention(c) (UnsafeMutableRawPointer) -> Void
                completion.function(as: Invoke.self)(completion.object)
            }
        }
        for child in state.children { advance(child.unsafeCast(to: SCNNode.self), dt) }
    }
}

@ObjCCategory("SCNNodeActions")
extension SCNNode {
    private func start(_ action: SCNAction, key: String?, completion: ObjCBlock?) {
        if let key { node.running.removeAll { $0.key == key } }
        node.running.append(SCNRunning(key: key, action: action, completion: completion))
    }

    @ObjCMethod("runAction:") func runAction(_ action: SCNAction) { start(action, key: nil, completion: nil) }
    @ObjCMethod("runAction:completionHandler:")
    func runAction(_ action: SCNAction, completionHandler: ObjCBlock?) { start(action, key: nil, completion: completionHandler) }
    @ObjCMethod("runAction:forKey:") func runAction(_ action: SCNAction, forKey key: String?) { start(action, key: key, completion: nil) }
    @ObjCMethod("runAction:forKey:completionHandler:")
    func runAction(_ action: SCNAction, forKey key: String?, completionHandler: ObjCBlock?) { start(action, key: key, completion: completionHandler) }
    @ObjCMethod("removeAllActions") func removeAllActions() { node.running = [] }
    @ObjCMethod("removeActionForKey:") func removeAction(forKey key: String) { node.running.removeAll { $0.key == key } }
    @ObjCMethod("actionForKey:") func action(forKey key: String) -> SCNAction? { node.running.first { $0.key == key }?.action }
    @ObjCMethod("hasActions") func hasActions() -> Bool { !node.running.isEmpty }
}

// MARK: - SCNTransaction

/// Changes grouped to be done together. Changes are made at once, not
/// animated: the duration only says when the completion block runs.
enum SCNTimers {
    nonisolated(unsafe) static var pending: [(due: Double, block: ObjCBlock)] = []

    /// Calls what is due.
    static func process(now: Double) {
        guard !pending.isEmpty else { return }
        let due = pending.filter { $0.due <= now }
        pending.removeAll { $0.due <= now }
        for item in due {
            typealias Invoke = @convention(c) (UnsafeMutableRawPointer) -> Void
            item.block.function(as: Invoke.self)(item.block.object)
        }
    }
}

@ObjCClass("SCNTransaction")
open class SCNTransaction: NSObject {
    struct Level {
        var duration = 0.25
        var completion: ObjCBlock?
        var timing: NSObject?
        var disableActions = false
    }
    nonisolated(unsafe) static var levels: [Level] = [Level()]

    @ObjCClassMethod("begin") static func begin(_ cls: ObjCClass) { levels.append(Level()) }

    @ObjCClassMethod("commit")
    static func commit(_ cls: ObjCClass) {
        guard levels.count > 1 else { return }
        let level = levels.removeLast()
        guard let completion = level.completion else { return }
        if level.duration <= 0 {
            typealias Invoke = @convention(c) (UnsafeMutableRawPointer) -> Void
            completion.function(as: Invoke.self)(completion.object)
        } else {
            SCNTimers.pending.append((SKSupport.now() + level.duration, completion))
        }
    }

    @ObjCClassMethod("flush") static func flush(_ cls: ObjCClass) {}
    @ObjCClassMethod("lock") static func lock(_ cls: ObjCClass) {}
    @ObjCClassMethod("unlock") static func unlock(_ cls: ObjCClass) {}
    @ObjCClassMethod("animationDuration") static func animationDuration(_ cls: ObjCClass) -> Double { levels[levels.count - 1].duration }
    @ObjCClassMethod("setAnimationDuration:")
    static func setAnimationDuration(_ cls: ObjCClass, duration: Double) { levels[levels.count - 1].duration = duration }
    @ObjCClassMethod("completionBlock") static func completionBlock(_ cls: ObjCClass) -> ObjCBlock? { levels[levels.count - 1].completion }
    @ObjCClassMethod("setCompletionBlock:")
    static func setCompletionBlock(_ cls: ObjCClass, block: ObjCBlock?) { levels[levels.count - 1].completion = block }
    @ObjCClassMethod("animationTimingFunction") static func animationTimingFunction(_ cls: ObjCClass) -> NSObject? { levels[levels.count - 1].timing }
    @ObjCClassMethod("setAnimationTimingFunction:")
    static func setAnimationTimingFunction(_ cls: ObjCClass, function: NSObject?) { levels[levels.count - 1].timing = function }
    @ObjCClassMethod("disableActions") static func disableActions(_ cls: ObjCClass) -> Bool { levels[levels.count - 1].disableActions }
    @ObjCClassMethod("setDisableActions:")
    static func setDisableActions(_ cls: ObjCClass, disable: Bool) { levels[levels.count - 1].disableActions = disable }
}

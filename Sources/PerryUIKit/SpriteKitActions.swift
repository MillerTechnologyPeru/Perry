import CPerryGeometry
import Glibc
import PerryObjCInterop

// SpriteKit's actions, run by the view's frames after the scene's -update:.
// Like SceneKit's (SceneKitActions.swift), an action is a definition with
// a duration, timing mode and speed, and each run of it on a node has a
// runner that hands back the time it did not use once it is done.

indirect enum SKActionDef {
    case move(CGPoint, by: Bool)
    case rotate(CGFloat, by: Bool)
    case scale(x: CGFloat, y: CGFloat, by: Bool)
    case fade(CGFloat, by: Bool)
    case hide(Bool)
    case wait
    case sequence([SKAction])
    case group([SKAction])
    case repeatCount(SKAction, Int)
    case forever(SKAction)
    case remove
    case block(ObjCBlock)
    case custom(ObjCBlock)
    case nothing
}

final class SKActionState: ObjectState {
    var def = SKActionDef.nothing
    var duration = 0.0
    /// SKActionTimingMode: linear 0, ease in 1, ease out 2, ease in ease out 3.
    var timing = 0
    var speed: CGFloat = 1
}

@ObjCClass("SKAction")
open class SKAction: NSObject {
    static let states = StateTable<SKActionState>()
    var action: SKActionState { SKAction.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        SKAction.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SKAction.objCClass.pointer)
    }

    static func make(_ def: SKActionDef, duration: Double = 0) -> SKAction {
        let made = SKAction.objCClass.object.allocated().unsafeCast(to: SKAction.self)
        made.action.def = def
        made.action.duration = max(duration, 0)
        return made
    }

    @ObjCMethod("init") func initialize() -> Self { self }

    @ObjCClassMethod("moveTo:duration:")
    static func move(_ cls: ObjCClass, to point: CGPoint, duration: Double) -> SKAction { make(.move(point, by: false), duration: duration) }
    @ObjCClassMethod("moveByX:y:duration:")
    static func move(_ cls: ObjCClass, byX x: CGFloat, y: CGFloat, duration: Double) -> SKAction {
        make(.move(CGPoint(x: x, y: y), by: true), duration: duration)
    }
    @ObjCClassMethod("rotateToAngle:duration:")
    static func rotate(_ cls: ObjCClass, toAngle angle: CGFloat, duration: Double) -> SKAction { make(.rotate(angle, by: false), duration: duration) }
    @ObjCClassMethod("rotateByAngle:duration:")
    static func rotate(_ cls: ObjCClass, byAngle angle: CGFloat, duration: Double) -> SKAction { make(.rotate(angle, by: true), duration: duration) }
    @ObjCClassMethod("scaleTo:duration:")
    static func scale(_ cls: ObjCClass, to scale: CGFloat, duration: Double) -> SKAction { make(.scale(x: scale, y: scale, by: false), duration: duration) }
    @ObjCClassMethod("scaleBy:duration:")
    static func scale(_ cls: ObjCClass, by scale: CGFloat, duration: Double) -> SKAction { make(.scale(x: scale, y: scale, by: true), duration: duration) }
    @ObjCClassMethod("scaleXTo:y:duration:")
    static func scale(_ cls: ObjCClass, toX x: CGFloat, y: CGFloat, duration: Double) -> SKAction { make(.scale(x: x, y: y, by: false), duration: duration) }
    @ObjCClassMethod("scaleXBy:y:duration:")
    static func scale(_ cls: ObjCClass, byX x: CGFloat, y: CGFloat, duration: Double) -> SKAction { make(.scale(x: x, y: y, by: true), duration: duration) }

    @ObjCClassMethod("fadeInWithDuration:")
    static func fadeIn(_ cls: ObjCClass, duration: Double) -> SKAction { make(.fade(1, by: false), duration: duration) }
    @ObjCClassMethod("fadeOutWithDuration:")
    static func fadeOut(_ cls: ObjCClass, duration: Double) -> SKAction { make(.fade(0, by: false), duration: duration) }
    @ObjCClassMethod("fadeAlphaTo:duration:")
    static func fadeAlpha(_ cls: ObjCClass, to alpha: CGFloat, duration: Double) -> SKAction { make(.fade(alpha, by: false), duration: duration) }
    @ObjCClassMethod("fadeAlphaBy:duration:")
    static func fadeAlpha(_ cls: ObjCClass, by alpha: CGFloat, duration: Double) -> SKAction { make(.fade(alpha, by: true), duration: duration) }
    @ObjCClassMethod("hide") static func hide(_ cls: ObjCClass) -> SKAction { make(.hide(true)) }
    @ObjCClassMethod("unhide") static func unhide(_ cls: ObjCClass) -> SKAction { make(.hide(false)) }
    @ObjCClassMethod("waitForDuration:") static func wait(_ cls: ObjCClass, duration: Double) -> SKAction { make(.wait, duration: duration) }

    @ObjCClassMethod("sequence:")
    static func sequence(_ cls: ObjCClass, actions: NSArray) -> SKAction { make(.sequence(actions.elements.map { $0.unsafeCast(to: SKAction.self) })) }
    @ObjCClassMethod("group:")
    static func group(_ cls: ObjCClass, actions: NSArray) -> SKAction { make(.group(actions.elements.map { $0.unsafeCast(to: SKAction.self) })) }
    @ObjCClassMethod("repeatAction:count:")
    static func repeatAction(_ cls: ObjCClass, action: SKAction, count: Int) -> SKAction { make(.repeatCount(action, count)) }
    @ObjCClassMethod("repeatActionForever:")
    static func repeatForever(_ cls: ObjCClass, action: SKAction) -> SKAction { make(.forever(action)) }
    @ObjCClassMethod("removeFromParent") static func removeFromParent(_ cls: ObjCClass) -> SKAction { make(.remove) }
    @ObjCClassMethod("runBlock:") static func run(_ cls: ObjCClass, block: ObjCBlock) -> SKAction { make(.block(block)) }
    @ObjCClassMethod("customActionWithDuration:actionBlock:")
    static func custom(_ cls: ObjCClass, duration: Double, actionBlock: ObjCBlock) -> SKAction { make(.custom(actionBlock), duration: duration) }

    @ObjCMethod("duration") func duration() -> Double { action.duration }
    @ObjCMethod("setDuration:") func setDuration(_ duration: Double) { action.duration = max(duration, 0) }
    @ObjCMethod("timingMode") func timingMode() -> Int { action.timing }
    @ObjCMethod("setTimingMode:") func setTimingMode(_ mode: Int) { action.timing = mode }
    @ObjCMethod("speed") func speed() -> CGFloat { action.speed }
    @ObjCMethod("setSpeed:") func setSpeed(_ speed: CGFloat) { action.speed = speed }

    @ObjCMethod("reversedAction")
    func reversedAction() -> SKAction {
        let state = action
        let def: SKActionDef
        switch state.def {
        case .move(let p, true): def = .move(CGPoint(x: -p.x, y: -p.y), by: true)
        case .rotate(let a, true): def = .rotate(-a, by: true)
        case .scale(let x, let y, true): def = .scale(x: 1 / x, y: 1 / y, by: true)
        case .fade(let a, true): def = .fade(-a, by: true)
        case .fade(1, false): def = .fade(0, by: false)
        case .fade(0, false): def = .fade(1, by: false)
        case .hide(let hide): def = .hide(!hide)
        case .sequence(let actions): def = .sequence(actions.reversed().map { $0.reversedAction() })
        case .group(let actions): def = .group(actions.map { $0.reversedAction() })
        case .repeatCount(let inner, let count): def = .repeatCount(inner.reversedAction(), count)
        case .forever(let inner): def = .forever(inner.reversedAction())
        default: def = state.def
        }
        let made = SKAction.make(def, duration: state.duration)
        made.action.timing = state.timing
        made.action.speed = state.speed
        return made
    }
}

final class SKRunning {
    let key: String?
    let action: SKAction
    let runner: SKRunner
    let completion: ObjCBlock?

    init(key: String?, action: SKAction, completion: ObjCBlock?) {
        self.key = key
        self.action = action
        runner = SKRunner(action)
        self.completion = completion
    }
}

final class SKRunner {
    private let action: SKAction
    private var elapsed = 0.0
    private var lastProgress: CGFloat = 0
    private var started = false
    private var start = (position: CGPoint.zero, rotation: CGFloat(0), scaleX: CGFloat(1), scaleY: CGFloat(1), alpha: CGFloat(1))
    private var children: [SKRunner] = []
    private var index = 0
    private var finishedChildren: [Double?] = []
    private var repeated = 0

    init(_ action: SKAction) { self.action = action }

    /// Moves the action on by `dt` seconds; nil while it goes on, else the time it did not need.
    func advance(_ node: SKNode, _ dt: Double) -> Double? {
        let speed = Double(action.action.speed)
        guard speed > 0 else { return nil }
        guard let left = run(node, dt * speed) else { return nil }
        return left / speed
    }

    private func run(_ node: SKNode, _ dt: Double) -> Double? {
        switch action.action.def {
        case .hide(let hide):
            node.node.hidden = hide
            return dt
        case .remove:
            node.removeFromParent()
            return dt
        case .nothing: return dt
        case .block(let block):
            typealias Invoke = @convention(c) (UnsafeMutableRawPointer) -> Void
            block.function(as: Invoke.self)(block.object)
            return dt
        case .sequence(let actions):
            if children.isEmpty { children = actions.map(SKRunner.init) }
            var left = dt
            while index < children.count {
                guard let remaining = children[index].advance(node, left) else { return nil }
                left = remaining
                index += 1
            }
            return left
        case .group(let actions):
            if children.isEmpty {
                children = actions.map(SKRunner.init)
                finishedChildren = Array(repeating: nil, count: children.count)
            }
            var allDone = true, leftover = dt
            for i in children.indices {
                if finishedChildren[i] == nil { finishedChildren[i] = children[i].advance(node, dt) }
                if let left = finishedChildren[i] { leftover = min(leftover, left) } else { allDone = false }
            }
            return allDone ? leftover : nil
        case .repeatCount(let inner, let count): return runRepeat(node, dt, inner, count: count)
        case .forever(let inner): return runRepeat(node, dt, inner, count: nil)
        case .move, .rotate, .scale, .fade, .wait, .custom: return runInterval(node, dt)
        }
    }

    private func runRepeat(_ node: SKNode, _ dt: Double, _ inner: SKAction, count: Int?) -> Double? {
        var left = dt, spins = 0
        while count.map({ repeated < $0 }) ?? true {
            if children.isEmpty { children = [SKRunner(inner)] }
            guard let remaining = children[0].advance(node, left) else { return nil }
            children = []
            repeated += 1
            // An action that takes no time must not spin: once a frame.
            if remaining >= left { spins += 1; if spins > 1 { return nil } }
            left = remaining
        }
        return left
    }

    private func runInterval(_ node: SKNode, _ dt: Double) -> Double? {
        let state = action.action
        if !started {
            started = true
            let n = node.node
            start = (n.position, n.zRotation, n.xScale, n.yScale, n.alpha)
        }
        var step = dt
        if state.duration > 0 {
            step = min(dt, state.duration - elapsed)
            elapsed += step
        }
        let linear = state.duration > 0 ? CGFloat(elapsed / state.duration) : 1
        let p: CGFloat
        switch state.timing {
        case 1: p = linear * linear
        case 2: p = 1 - (1 - linear) * (1 - linear)
        case 3: p = linear * linear * (3 - 2 * linear)
        default: p = linear
        }
        apply(node, p, elapsed: elapsed)
        if state.duration <= 0 || elapsed >= state.duration { return dt - step }
        return nil
    }

    private func apply(_ node: SKNode, _ p: CGFloat, elapsed: Double) {
        let n = node.node
        let step = p - lastProgress
        lastProgress = p
        switch action.action.def {
        case .move(let v, let by):
            n.position = by ? CGPoint(x: n.position.x + v.x * step, y: n.position.y + v.y * step)
                : CGPoint(x: start.position.x + (v.x - start.position.x) * p, y: start.position.y + (v.y - start.position.y) * p)
        case .rotate(let angle, let by):
            n.zRotation = by ? n.zRotation + angle * step : start.rotation + (angle - start.rotation) * p
        case .scale(let x, let y, let by):
            if by {
                n.xScale *= pow(x, step)
                n.yScale *= pow(y, step)
            } else {
                n.xScale = start.scaleX + (x - start.scaleX) * p
                n.yScale = start.scaleY + (y - start.scaleY) * p
            }
        case .fade(let a, let by):
            n.alpha = by ? n.alpha + a * step : start.alpha + (a - start.alpha) * p
        case .custom(let block):
            typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, CGFloat) -> Void
            block.function(as: Invoke.self)(block.object, node.objcObject, CGFloat(elapsed))
        default: break
        }
    }
}

enum SKActions {
    /// Moves every node's actions on by `dt` seconds, parents first.
    static func advance(_ node: SKNode, _ dt: Double) {
        let state = node.node
        if !state.paused, !state.running.isEmpty {
            var finished: [SKRunning] = []
            for run in state.running where run.runner.advance(node, dt) != nil { finished.append(run) }
            state.running.removeAll { run in finished.contains { $0 === run } }
            for run in finished {
                guard let completion = run.completion else { continue }
                typealias Invoke = @convention(c) (UnsafeMutableRawPointer) -> Void
                completion.function(as: Invoke.self)(completion.object)
            }
        }
        guard !state.paused else { return }
        for child in state.children { advance(child.unsafeCast(to: SKNode.self), dt) }
    }
}

@ObjCCategory("SKNodeActions")
extension SKNode {
    private func start(_ action: SKAction?, key: String?, completion: ObjCBlock?) {
        guard let action else { return }
        if let key { node.running.removeAll { $0.key == key } }
        node.running.append(SKRunning(key: key, action: action, completion: completion))
    }

    @ObjCMethod("runAction:") func runAction(_ action: SKAction?) { start(action, key: nil, completion: nil) }
    @ObjCMethod("runAction:withKey:") func runAction(_ action: SKAction?, withKey key: String?) { start(action, key: key, completion: nil) }
    @ObjCMethod("runAction:completion:") func runAction(_ action: SKAction?, completion: ObjCBlock?) { start(action, key: nil, completion: completion) }
    @ObjCMethod("removeAllActions") func removeAllActions() { node.running = [] }
    @ObjCMethod("removeActionForKey:") func removeAction(forKey key: String) { node.running.removeAll { $0.key == key } }
    @ObjCMethod("hasActions") func hasActions() -> Bool { !node.running.isEmpty }
    @ObjCMethod("actionForKey:") func action(forKey key: String) -> SKAction? { node.running.first { $0.key == key }?.action }
}

import CPerryGeometry
import Glibc
import PerryObjCInterop

// SceneKit's keyframed animations: an animation is channels, each the
// transforms a node below the node that plays it takes at a list of times.
// A player advances its time each frame, looping as its animation asks, and
// the players playing on a node set its bones' transforms: the keyframes
// either side of the time blended (position and scale linearly, rotation
// by the shorter arc), and the players' poses blended by their weights.

struct SCNChannel {
    /// The names from the playing node down to the animated one.
    var path: [String]
    var times: [Double]
    var keys: [(position: SCNVector3, rotation: SCNMath.Quaternion, scale: SCNVector3)]

    /// The transform at `time`, the first or last key's outside the times.
    func sample(_ time: Double) -> (position: SCNVector3, rotation: SCNMath.Quaternion, scale: SCNVector3)? {
        guard let first = keys.first, let last = keys.last else { return nil }
        if time <= times[0] { return first }
        if time >= times[times.count - 1] { return last }
        // The last key at or before the time.
        var low = 0, high = times.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if times[middle] <= time { low = middle } else { high = middle }
        }
        let t = Float((time - times[low]) / max(times[high] - times[low], 1e-9))
        let a = keys[low], b = keys[high]
        func mix(_ x: Float, _ y: Float) -> Float { x + (y - x) * t }
        var q = b.rotation
        if a.rotation.x * q.x + a.rotation.y * q.y + a.rotation.z * q.z + a.rotation.w * q.w < 0 { q = (-q.x, -q.y, -q.z, -q.w) }
        let rotation = SCNMath.normalized((mix(a.rotation.x, q.x), mix(a.rotation.y, q.y), mix(a.rotation.z, q.z), mix(a.rotation.w, q.w)))
        return (SCNVector3(x: mix(a.position.x, b.position.x), y: mix(a.position.y, b.position.y), z: mix(a.position.z, b.position.z)), rotation,
                SCNVector3(x: mix(a.scale.x, b.scale.x), y: mix(a.scale.y, b.scale.y), z: mix(a.scale.z, b.scale.z)))
    }
}

extension SCNNode {
    /// The node named by `path` below this one, each name found anywhere below the one before.
    func node(atPath path: [String]) -> SCNNode? {
        var current = self
        for name in path {
            guard let next = current.childNode(withName: name, recursively: true) else { return nil }
            current = next
        }
        return current
    }
}

extension SCNAnimationEvent {
    static func events(of animation: SCNAnimation) -> [(keyTime: Double, block: ObjCBlock)] {
        guard let events = animation.animation.events?.unsafeCast(to: NSArray.self) else { return [] }
        return events.elements.compactMap { object in
            guard let block = SCNAnimationEvent.states.existing(object.objcObject)?.block else { return nil }
            return (Double(SCNAnimationEvent.states[object.objcObject].keyTime), block)
        }
    }
}

enum SCNAnimations {
    /// Advances every playing animation by `dt` seconds and poses the nodes they animate.
    static func advance(_ root: SCNNode, _ dt: Double) {
        let state = root.node
        if !state.animationPlayers.isEmpty { pose(root, dt) }
        for child in state.children { advance(child.unsafeCast(to: SCNNode.self), dt) }
    }

    private static func pose(_ target: SCNNode, _ dt: Double) {
        typealias Sample = (position: SCNVector3, rotation: SCNMath.Quaternion, scale: SCNVector3)
        // For each bone, the poses asked of it and their weights.
        var asked: [ObjectIdentifier: (node: SCNNode, poses: [(weight: Float, pose: Sample)])] = [:]
        for key in target.node.animationKeys {
            guard let player = target.node.animationPlayers[key], player.is(SCNAnimationPlayer.self) else { continue }
            let p = player.unsafeCast(to: SCNAnimationPlayer.self)
            let state = p.player
            guard state.playing, !state.paused, let animation = state.animation else { continue }
            let channels = animation.animation.channels
            guard !channels.isEmpty else { continue }
            let duration = max(animation.animation.duration, 1e-6)
            state.time += dt * Double(state.speed)
            let repeats = Double(animation.animation.repeatCount)
            let total = repeats > 0 ? duration * repeats : duration
            var finished = false
            if state.time >= total, total.isFinite {
                state.time = total
                finished = true
            }
            // The place in one run, as a fraction of it.
            let local = finished && !(repeats > 0 && repeats.isFinite && repeats.truncatingRemainder(dividingBy: 1) != 0) ? duration
                : state.time.truncatingRemainder(dividingBy: duration)
            fire(state, animation, player: p, node: target, fraction: local / duration, looped: state.time >= duration && !finished)
            var weight = Float(state.blendFactor)
            if animation.animation.fadeIn > 0 { weight *= Float(min(state.time / animation.animation.fadeIn, 1)) }
            if state.boneTarget != target.objcObject {
                state.boneTarget = target.objcObject
                state.bones = [:]
                for (index, channel) in channels.enumerated() { if let bone = target.node(atPath: channel.path) { state.bones[index] = bone } }
                if getenv("PERRY_SCENEKIT_TRACE") != nil {
                    let line = "perry: SceneKit: animation \(key) on \(target.node.name ?? "-"): \(state.bones.count) of \(channels.count) channels found, duration \(animation.animation.duration), speed \(state.speed)\n"
                    line.withCString { _ = write(2, $0, strlen($0)) }
                }
            }
            for (index, channel) in channels.enumerated() {
                guard let bone = state.bones[index], let sample = channel.sample(local) else { continue }
                asked[ObjectIdentifier(bone), default: (bone, [])].poses.append((weight, sample))
            }
            if finished {
                state.lastFraction = -1
                state.playing = false
                if animation.animation.removedOnCompletion { state.time = 0 }
            }
        }
        for (_, entry) in asked {
            let total = entry.poses.reduce(Float(0)) { $0 + $1.weight }
            guard total > 1e-6 else { continue }
            var position = SCNVector3(x: 0, y: 0, z: 0), scale = SCNVector3(x: 0, y: 0, z: 0)
            var q: SCNMath.Quaternion = (0, 0, 0, 0)
            let reference = entry.poses[0].pose.rotation
            for (weight, pose) in entry.poses {
                let w = weight / total
                position = SCNVector3(x: position.x + pose.position.x * w, y: position.y + pose.position.y * w, z: position.z + pose.position.z * w)
                scale = SCNVector3(x: scale.x + pose.scale.x * w, y: scale.y + pose.scale.y * w, z: scale.z + pose.scale.z * w)
                var r = pose.rotation
                if reference.x * r.x + reference.y * r.y + reference.z * r.z + reference.w * r.w < 0 { r = (-r.x, -r.y, -r.z, -r.w) }
                q = (q.x + r.x * w, q.y + r.y * w, q.z + r.z * w, q.w + r.w * w)
            }
            let node = entry.node.node
            node.position = position
            node.scale = scale
            node.rotation = SCNMath.normalized(q)
            node.pivot = SCNMath.identity
        }
    }

    /// Calls the events whose key times the animation passed since the last frame.
    private static func fire(_ state: SCNAnimationPlayerState, _ animation: SCNAnimation, player: SCNAnimationPlayer, node: SCNNode, fraction: Double, looped: Bool) {
        let events = SCNAnimationEvent.events(of: animation)
        let previous = state.lastFraction
        state.lastFraction = fraction
        guard !events.isEmpty else { return }
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Bool) -> Void
        for (keyTime, block) in events {
            // Passed this frame: between the last fraction and this one, wrapping at a loop.
            let passed = fraction >= previous ? previous < keyTime && keyTime <= fraction : keyTime > previous || keyTime <= fraction
            if passed { block.function(as: Invoke.self)(block.object, animation.objcObject, node.objcObject, false) }
        }
    }
}

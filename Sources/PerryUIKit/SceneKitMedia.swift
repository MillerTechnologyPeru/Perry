import CPerryGeometry
import Glibc
import PerryObjCInterop

// SceneKit's sounds, animations and particles, as far as nothing plays or
// draws them: the objects an app makes, sets up and hands to nodes are
// there and keep what they are given, so the app runs; a sound is not
// heard, an animation does not move its node, a particle system emits
// nothing.

// MARK: - Audio

final class SCNAudioSourceState: ObjectState {
    var name: String?
    var volume: Float = 1
    var rate: Float = 1
    var reverbBlend: Float = 0
    var positional = true
    var loops = false
    var shouldStream = false
}

@ObjCClass("SCNAudioSource")
open class SCNAudioSource: NSObject {
    static let states = StateTable<SCNAudioSourceState>()
    var source: SCNAudioSourceState { SCNAudioSource.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        SCNAudioSource.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SCNAudioSource.objCClass.pointer)
    }

    @ObjCClassMethod("audioSourceNamed:")
    static func named(_ cls: ObjCClass, name: String) -> SCNAudioSource? {
        let made = cls.object.allocated().unsafeCast(to: SCNAudioSource.self)
        made.source.name = name
        return made
    }
    @ObjCMethod("initWithName:") func initialize(name: String) -> Self? { source.name = name; return self }
    @ObjCMethod("init") func initialize() -> Self { self }
    @ObjCMethod("initWithFileNamed:") func initialize(fileNamed name: String) -> Self? { source.name = name; return self }
    @ObjCMethod("initWithURL:") func initialize(url: NSObject) -> Self? { source.name = url.scnPath(); return self }
    @ObjCMethod("load") func load() {}
    @ObjCMethod("volume") func volume() -> Float { source.volume }
    @ObjCMethod("setVolume:") func setVolume(_ volume: Float) { source.volume = volume }
    @ObjCMethod("rate") func rate() -> Float { source.rate }
    @ObjCMethod("setRate:") func setRate(_ rate: Float) { source.rate = rate }
    @ObjCMethod("reverbBlend") func reverbBlend() -> Float { source.reverbBlend }
    @ObjCMethod("setReverbBlend:") func setReverbBlend(_ blend: Float) { source.reverbBlend = blend }
    @ObjCMethod("isPositional") func isPositional() -> Bool { source.positional }
    @ObjCMethod("setPositional:") func setPositional(_ positional: Bool) { source.positional = positional }
    @ObjCMethod("loops") func loops() -> Bool { source.loops }
    @ObjCMethod("setLoops:") func setLoops(_ loops: Bool) { source.loops = loops }
    @ObjCMethod("shouldStream") func shouldStream() -> Bool { source.shouldStream }
    @ObjCMethod("setShouldStream:") func setShouldStream(_ stream: Bool) { source.shouldStream = stream }
}

final class SCNAudioPlayerState: ObjectState {
    var source: NSObject?
    var willStart: ObjCBlock?
    var didFinish: ObjCBlock?
}

@ObjCClass("SCNAudioPlayer")
open class SCNAudioPlayer: NSObject {
    static let states = StateTable<SCNAudioPlayerState>()
    var player: SCNAudioPlayerState { SCNAudioPlayer.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        SCNAudioPlayer.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SCNAudioPlayer.objCClass.pointer)
    }

    @ObjCMethod("initWithSource:") func initialize(source: NSObject) -> Self { player.source = source; return self }
    @ObjCMethod("audioSource") func audioSource() -> NSObject? { player.source }
    @ObjCMethod("willStartPlayback") func willStartPlayback() -> ObjCBlock? { player.willStart }
    @ObjCMethod("setWillStartPlayback:") func setWillStartPlayback(_ block: ObjCBlock?) { player.willStart = block }
    @ObjCMethod("didFinishPlayback") func didFinishPlayback() -> ObjCBlock? { player.didFinish }
    @ObjCMethod("setDidFinishPlayback:") func setDidFinishPlayback(_ block: ObjCBlock?) { player.didFinish = block }
}

// MARK: - Animation

final class SCNAnimationState: ObjectState {
    var events: NSObject?
    var removedOnCompletion = true
    var duration = 0.0
    var repeatCount: CGFloat = 0
    var autoreverses = false
    var fadeIn = 0.0, fadeOut = 0.0
    var usesSceneTimeBase = false
}

@ObjCClass("SCNAnimation")
open class SCNAnimation: NSObject {
    static let states = StateTable<SCNAnimationState>()
    var animation: SCNAnimationState { SCNAnimation.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        SCNAnimation.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SCNAnimation.objCClass.pointer)
    }

    @ObjCMethod("init") func initialize() -> Self { self }
    @ObjCMethod("animationEvents") func animationEvents() -> NSObject? { animation.events }
    @ObjCMethod("setAnimationEvents:") func setAnimationEvents(_ events: NSObject?) { animation.events = events }
    @ObjCMethod("isRemovedOnCompletion") func isRemovedOnCompletion() -> Bool { animation.removedOnCompletion }
    @ObjCMethod("setRemovedOnCompletion:") func setRemovedOnCompletion(_ removed: Bool) { animation.removedOnCompletion = removed }
    @ObjCMethod("duration") func duration() -> Double { animation.duration }
    @ObjCMethod("setDuration:") func setDuration(_ duration: Double) { animation.duration = duration }
    @ObjCMethod("repeatCount") func repeatCount() -> CGFloat { animation.repeatCount }
    @ObjCMethod("setRepeatCount:") func setRepeatCount(_ count: CGFloat) { animation.repeatCount = count }
    @ObjCMethod("autoreverses") func autoreverses() -> Bool { animation.autoreverses }
    @ObjCMethod("setAutoreverses:") func setAutoreverses(_ autoreverses: Bool) { animation.autoreverses = autoreverses }
    @ObjCMethod("blendInDuration") func blendInDuration() -> Double { animation.fadeIn }
    @ObjCMethod("setBlendInDuration:") func setBlendInDuration(_ duration: Double) { animation.fadeIn = duration }
    @ObjCMethod("blendOutDuration") func blendOutDuration() -> Double { animation.fadeOut }
    @ObjCMethod("setBlendOutDuration:") func setBlendOutDuration(_ duration: Double) { animation.fadeOut = duration }
    @ObjCMethod("usesSceneTimeBase") func usesSceneTimeBase() -> Bool { animation.usesSceneTimeBase }
    @ObjCMethod("setUsesSceneTimeBase:") func setUsesSceneTimeBase(_ uses: Bool) { animation.usesSceneTimeBase = uses }
}

final class SCNAnimationEventState: ObjectState {
    var keyTime: CGFloat = 0
    var block: ObjCBlock?
}

@ObjCClass("SCNAnimationEvent")
open class SCNAnimationEvent: NSObject {
    static let states = StateTable<SCNAnimationEventState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        SCNAnimationEvent.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SCNAnimationEvent.objCClass.pointer)
    }

    @ObjCClassMethod("animationEventWithKeyTime:block:")
    static func event(_ cls: ObjCClass, keyTime: CGFloat, block: ObjCBlock) -> SCNAnimationEvent {
        let made = cls.object.allocated().unsafeCast(to: SCNAnimationEvent.self)
        states[made.objcObject].keyTime = keyTime
        states[made.objcObject].block = block
        return made
    }
}

final class SCNAnimationPlayerState: ObjectState {
    var animation: SCNAnimation?
    var speed: CGFloat = 1
    var blendFactor: CGFloat = 1
    var paused = false
    var playing = false
}

@ObjCClass("SCNAnimationPlayer")
open class SCNAnimationPlayer: NSObject {
    static let states = StateTable<SCNAnimationPlayerState>()
    var player: SCNAnimationPlayerState { SCNAnimationPlayer.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        SCNAnimationPlayer.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SCNAnimationPlayer.objCClass.pointer)
    }

    @ObjCClassMethod("animationPlayerWithAnimation:")
    static func player(_ cls: ObjCClass, animation: SCNAnimation) -> SCNAnimationPlayer {
        let made = cls.object.allocated().unsafeCast(to: SCNAnimationPlayer.self)
        made.player.animation = animation
        return made
    }

    @ObjCMethod("init") func initialize() -> Self { self }
    @ObjCMethod("animation") func animation() -> SCNAnimation {
        if let animation = player.animation { return animation }
        let made = SCNAnimation.objCClass.object.allocated().unsafeCast(to: SCNAnimation.self)
        player.animation = made
        return made
    }
    @ObjCMethod("speed") func speed() -> CGFloat { player.speed }
    @ObjCMethod("setSpeed:") func setSpeed(_ speed: CGFloat) { player.speed = speed }
    @ObjCMethod("blendFactor") func blendFactor() -> CGFloat { player.blendFactor }
    @ObjCMethod("setBlendFactor:") func setBlendFactor(_ factor: CGFloat) { player.blendFactor = factor }
    @ObjCMethod("paused") func paused() -> Bool { player.paused }
    @ObjCMethod("setPaused:") func setPaused(_ paused: Bool) { player.paused = paused }
    @ObjCMethod("play") func play() { player.playing = true }
    @ObjCMethod("stop") func stop() { player.playing = false }
    @ObjCMethod("stopWithBlendOutDuration:") func stop(blendOutDuration: Double) { player.playing = false }
}

@ObjCCategory("SCNNodeAnimations")
extension SCNNode {
    @ObjCMethod("addAnimationPlayer:forKey:")
    func addAnimationPlayer(_ player: SCNAnimationPlayer, forKey key: String?) {
        let name = key ?? "animation\(node.animationKeys.count)"
        if node.animationPlayers[name] == nil { node.animationKeys.append(name) }
        node.animationPlayers[name] = player
    }
    @ObjCMethod("animationPlayerForKey:") func animationPlayer(forKey key: String) -> SCNAnimationPlayer? {
        node.animationPlayers[key].flatMap { $0.is(SCNAnimationPlayer.self) ? $0.unsafeCast(to: SCNAnimationPlayer.self) : nil }
    }
    @ObjCMethod("animationKeys") func animationKeys() -> NSObject {
        NSMutableArray.of(node.animationKeys.compactMap { key in key.objCArgument().map { NSObject(objcObject: $0, ownership: .retain) } })
    }
    /// A Core Animation animation is kept under its key, not played.
    @ObjCMethod("addAnimation:forKey:") func addAnimation(_ animation: NSObject, forKey key: String?) {
        let name = key ?? "animation\(node.animationKeys.count)"
        if node.animationPlayers[name] == nil { node.animationKeys.append(name) }
        node.animationPlayers[name] = animation
    }
    @ObjCMethod("animationForKey:") func animation(forKey key: String) -> NSObject? { node.animationPlayers[key] }
    @ObjCMethod("pauseAnimationForKey:") func pauseAnimation(forKey key: String) {}
    @ObjCMethod("resumeAnimationForKey:") func resumeAnimation(forKey key: String) {}
    @ObjCMethod("isAnimationForKeyPaused:") func isAnimationPaused(forKey key: String) -> Bool { false }
    @ObjCMethod("removeAnimationForKey:fadeOutDuration:") func removeAnimation(forKey key: String, fadeOutDuration: CGFloat) { removeAnimation(forKey: key) }
    @ObjCMethod("removeAnimationForKey:") func removeAnimation(forKey key: String) {
        node.animationPlayers[key] = nil
        node.animationKeys.removeAll { $0 == key }
    }
    @ObjCMethod("removeAllAnimations") func removeAllAnimations() {
        node.animationPlayers = [:]
        node.animationKeys = []
    }
}

// MARK: - Particles

final class SCNParticleSystemState: ObjectState {
    var values: [String: Double] = [:]
    var vectors: [String: [Float]] = [:]
    var objects: [String: NSObject] = [:]
}

@ObjCClass("SCNParticleSystem")
open class SCNParticleSystem: NSObject {
    static let states = StateTable<SCNParticleSystemState>()
    var system: SCNParticleSystemState { SCNParticleSystem.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        SCNParticleSystem.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SCNParticleSystem.objCClass.pointer)
    }

    @ObjCClassMethod("particleSystem") static func make(_ cls: ObjCClass) -> SCNParticleSystem { cls.object.allocated().unsafeCast(to: SCNParticleSystem.self) }
    /// A system named by a particle file; the file's emitter is not read.
    @ObjCClassMethod("particleSystemNamed:inDirectory:")
    static func named(_ cls: ObjCClass, name: String, inDirectory directory: String?) -> SCNParticleSystem? {
        SCNFile.particleSystem(named: name, inDirectory: directory) ?? cls.object.allocated().unsafeCast(to: SCNParticleSystem.self)
    }

    @ObjCMethod("init") func initialize() -> Self { self }
    @ObjCMethod("birthRate") func birthRate() -> CGFloat { CGFloat(system.values["birthRate"] ?? 1) }
    @ObjCMethod("setBirthRate:") func setBirthRate(_ rate: CGFloat) { system.values["birthRate"] = Double(rate) }
    @ObjCMethod("loops") func loops() -> Bool { (system.values["loops"] ?? 1) != 0 }
    @ObjCMethod("setLoops:") func setLoops(_ loops: Bool) { system.values["loops"] = loops ? 1 : 0 }
    @ObjCMethod("emissionDuration") func emissionDuration() -> CGFloat { CGFloat(system.values["emissionDuration"] ?? 1) }
    @ObjCMethod("setEmissionDuration:") func setEmissionDuration(_ duration: CGFloat) { system.values["emissionDuration"] = Double(duration) }
    @ObjCMethod("reset") func reset() {}
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> SCNParticleSystem {
        let made = SCNParticleSystem.objCClass.object.allocated().unsafeCast(to: SCNParticleSystem.self)
        made.system.values = system.values
        return made
    }
}

// MARK: - A capsule

@ObjCClass("SCNCapsule")
open class SCNCapsule: SCNGeometry {
    /// A cylinder, not rounded at its ends: capsules are mostly physics shapes.
    @ObjCClassMethod("capsuleWithCapRadius:height:")
    static func capsule(_ cls: ObjCClass, capRadius: CGFloat, height: CGFloat) -> SCNCapsule {
        let made = cls.object.allocated().unsafeCast(to: SCNCapsule.self)
        made.geometry.kind = .cylinder
        made.geometry.radius = capRadius
        made.geometry.height = height
        return made
    }
}

// MARK: - Copying

@ObjCCategory("SCNAnimationPlayerCopying")
extension SCNAnimationPlayer {
    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> SCNAnimationPlayer {
        let made = SCNAnimationPlayer.objCClass.object.allocated().unsafeCast(to: SCNAnimationPlayer.self)
        made.player.animation = player.animation
        made.player.speed = player.speed
        made.player.blendFactor = player.blendFactor
        made.player.paused = player.paused
        return made
    }
}

@ObjCCategory("SCNAnimationCopying")
extension SCNAnimation {
    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> SCNAnimation {
        let made = SCNAnimation.objCClass.object.allocated().unsafeCast(to: SCNAnimation.self)
        let (from, to) = (animation, made.animation)
        to.events = from.events
        to.removedOnCompletion = from.removedOnCompletion
        to.duration = from.duration
        to.repeatCount = from.repeatCount
        to.autoreverses = from.autoreverses
        to.fadeIn = from.fadeIn
        to.fadeOut = from.fadeOut
        return made
    }
}

/// What has no state of its own to copy is shared.
@ObjCCategory("SCNLightCopying")
extension SCNLight {
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> SCNLight { self }
}

@ObjCCategory("SCNCameraCopying")
extension SCNCamera {
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> SCNCamera { self }
}

@ObjCCategory("SCNAudioSourceCopying")
extension SCNAudioSource {
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> SCNAudioSource { self }
}

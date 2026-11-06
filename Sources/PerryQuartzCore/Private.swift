import CPerryGeometry
import Glibc
import PerryObjCInterop

// Core Animation's private functions that SwiftUI calls, and the gradient
// layer, which keeps its properties but draws as a plain layer.

/// The layer's superlayer, not retained.
@c(_CALayerGetSuperlayer)
public func CALayerGetSuperlayer(_ layer: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    layer.flatMap { CALayer.state(of: $0).superlayer }
}

/// Maps geometry from `from` (an ancestor) down to `to`: calls `unmap` with
/// each layer's transform to its superlayer, from `to` up to `from`.
/// Without a common ancestor nothing is mapped.
@c(_CALayerMapGeometry)
public func CALayerMapGeometry(
    _ from: UnsafeMutableRawPointer?, _ to: UnsafeMutableRawPointer?,
    _ map: (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CATransform3D>) -> Void)?,
    _ unmap: (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CATransform3D>) -> Void)?,
    _ context: UnsafeMutableRawPointer?
) {
    var chain: [UnsafeMutableRawPointer] = []
    var current = to
    while let layer = current, layer != from {
        chain.append(layer)
        current = CALayer.state(of: layer).superlayer
    }
    guard current == from || from == nil else { return }
    for layer in chain {
        let state = CALayer.state(of: layer)
        var transform = CATransform3D(state.toSuperlayer(within: state.superlayer.map { CALayer.state(of: $0) }))
        withUnsafePointer(to: &transform) { unmap?(context, $0) }
    }
}

/// Whether two CAFrameRateRange values (three floats each, passed in
/// floating point registers) are the same.
@c(_CAFrameRateRangeIsEqualToRange)
public func CAFrameRateRangeIsEqualToRange(_ minimum: Float, _ maximum: Float, _ preferred: Float,
                                           _ otherMinimum: Float, _ otherMaximum: Float, _ otherPreferred: Float) -> Bool {
    minimum == otherMinimum && maximum == otherMaximum && preferred == otherPreferred
}

/// CAFrameRateRange CAFrameRateRangeMake(float minimum, float maximum, float preferred).
@c(_CAFrameRateRangeMake)
public func CAFrameRateRangeMake(_ minimum: Float, _ maximum: Float, _ preferred: Float) -> CAFrameRateRange {
    CAFrameRateRange(minimum: minimum, maximum: maximum, preferred: preferred)
}

// MARK: - CAGradientLayer

final class GradientLayerState {
    var colors: NSObject?
    var locations: NSObject?
    var startPoint = CGPoint(x: 0.5, y: 0)
    var endPoint = CGPoint(x: 0.5, y: 1)
    var type = "axial"
}

/// CAGradientLayer: keeps its colors, locations and points; the gradient
/// is not drawn.
@ObjCClass("CAGradientLayer")
open class CAGradientLayer: CALayer {
    var gradient = GradientLayerState()

    @ObjCMethod("init")
    public required init() { super.init() }

    @ObjCMethod("initWithLayer:")
    public required init(layer: CALayer) { super.init(layer: layer) }

    @ObjCMethod("colors") func colors() -> NSObject? { gradient.colors }
    @ObjCMethod("setColors:") func setColors(_ colors: NSObject?) { changed { gradient.colors = colors } }
    @ObjCMethod("locations") func locations() -> NSObject? { gradient.locations }
    @ObjCMethod("setLocations:") func setLocations(_ locations: NSObject?) { changed { gradient.locations = locations } }
    @ObjCMethod("startPoint") func startPoint() -> CGPoint { gradient.startPoint }
    @ObjCMethod("setStartPoint:") func setStartPoint(_ point: CGPoint) { changed { gradient.startPoint = point } }
    @ObjCMethod("endPoint") func endPoint() -> CGPoint { gradient.endPoint }
    @ObjCMethod("setEndPoint:") func setEndPoint(_ point: CGPoint) { changed { gradient.endPoint = point } }
    @ObjCMethod("type") func type() -> String { gradient.type }
    @ObjCMethod("setType:") func setType(_ type: String) { changed { gradient.type = type } }
}

// MARK: - Presentation modifiers

/// Swift state per Objective-C object, made on first use and removed at
/// -dealloc: NSObject subclasses here have no stored Swift state.
final class ObjectStates<State: AnyObject>: @unchecked Sendable {
    private var mutex = pthread_mutex_t()
    private var states: [UnsafeMutableRawPointer: State] = [:]
    private let make: () -> State

    init(_ make: @escaping () -> State) {
        self.make = make
        pthread_mutex_init(&mutex, nil)
    }

    subscript(object: UnsafeMutableRawPointer) -> State {
        pthread_mutex_lock(&mutex)
        defer { pthread_mutex_unlock(&mutex) }
        if let state = states[object] { return state }
        let state = make()
        states[object] = state
        return state
    }

    func remove(_ object: UnsafeMutableRawPointer) {
        pthread_mutex_lock(&mutex)
        let state = states.removeValue(forKey: object)
        pthread_mutex_unlock(&mutex)
        _ = state
    }
}

final class PresentationModifierState {
    var keyPath = ""
    /// The value last set.
    var value: NSObject?
    /// The value shown: the value last set, once its group is flushed.
    var presented: NSObject?
    var enabled = true
    var additive = false
    var group: NSObject?
    /// The layer it was added to; not retained.
    var layer: UnsafeMutableRawPointer?
}

/// CAPresentationModifier (private): a value for a layer's key path that
/// shows in place of the layer's own, or added to it, while the modifier is
/// on the layer: in how the layer presents, not its model. A value set
/// shows at once, or in a group when the group is flushed. SwiftUI shows
/// geometry it lays out off the main thread through these, until the main
/// thread sets the layers' own values and removes them.
@ObjCClass("CAPresentationModifier")
open class CAPresentationModifier: NSObject {
    static let states = ObjectStates { PresentationModifierState() }
    var modifier: PresentationModifierState { CAPresentationModifier.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        CAPresentationModifier.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CAPresentationModifier.objCClass.pointer)
    }

    @ObjCMethod("initWithKeyPath:initialValue:additive:")
    func initialize(keyPath: String, initialValue: NSObject?, additive: Bool) -> Self {
        initialize(keyPath: keyPath, initialValue: initialValue, additive: additive, group: nil)
    }

    @ObjCMethod("initWithKeyPath:initialValue:additive:group:")
    func initialize(keyPath: String, initialValue: NSObject?, additive: Bool, group: NSObject?) -> Self {
        let state = modifier
        (state.keyPath, state.value, state.additive, state.group) = (keyPath, initialValue, additive, group)
        group?.as(CAPresentationModifierGroup.self)?.add(self)
        return self
    }

    @ObjCMethod("initWithKeyPath:initialValue:initialVelocity:additive:preferredFrameRateRangeMaximum:group:")
    func initialize(keyPath: String, initialValue: NSObject?, initialVelocity: NSObject?, additive: Bool,
                    preferredFrameRateRangeMaximum: Int, group: NSObject?) -> Self {
        initialize(keyPath: keyPath, initialValue: initialValue, additive: additive, group: group)
    }

    @ObjCMethod("keyPath") func keyPath() -> String { modifier.keyPath }
    @ObjCMethod("isEnabled") func isEnabled() -> Bool { modifier.enabled }
    @ObjCMethod("setEnabled:") func setEnabled(_ enabled: Bool) {
        PresentationModifiers.withLock { modifier.enabled = enabled }
        Compositing.changed()
    }
    @ObjCMethod("additive") func additive() -> Bool { modifier.additive }
    @ObjCMethod("group") func group() -> NSObject? { modifier.group }
    @ObjCMethod("value") func value() -> NSObject? { modifier.value }

    /// Without a group the value shows at once; in one, when it is flushed.
    @ObjCMethod("setValue:")
    func setValue(_ value: NSObject?) {
        let state = modifier
        PresentationModifiers.withLock {
            state.value = value
            if state.group == nil { state.presented = value }
        }
        if state.group == nil { Compositing.changed() }
    }

    @ObjCMethod("setValue:velocity:")
    func setValue(_ value: NSObject?, velocity: NSObject?) { setValue(value) }

    /// Shows the value last set.
    func show() {
        let state = modifier
        PresentationModifiers.withLock { state.presented = state.value }
    }
}

/// The presentation modifiers on each layer, guarded by one lock, as
/// SwiftUI changes them from its render thread while the main thread draws.
enum PresentationModifiers {
    nonisolated(unsafe) private static let mutex: UnsafeMutablePointer<pthread_mutex_t> = {
        let mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
        pthread_mutex_init(mutex, nil)
        return mutex
    }()
    nonisolated(unsafe) private static var byLayer: [UnsafeMutableRawPointer: [PresentationModifierState]] = [:]

    static func withLock<T>(_ body: () -> T) -> T {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return body()
    }

    static func add(_ modifier: PresentationModifierState, to layer: UnsafeMutableRawPointer) {
        withLock {
            modifier.layer = layer
            if modifier.group == nil || modifier.presented == nil { modifier.presented = modifier.value }
            byLayer[layer, default: []].append(modifier)
        }
        Compositing.changed()
    }

    static func remove(_ modifier: PresentationModifierState, from layer: UnsafeMutableRawPointer) {
        withLock {
            byLayer[layer]?.removeAll { $0 === modifier }
            if byLayer[layer]?.isEmpty == true { byLayer[layer] = nil }
            if modifier.layer == layer { modifier.layer = nil }
        }
        Compositing.changed()
    }

    static func forget(_ layer: UnsafeMutableRawPointer) { withLock { byLayer[layer] = nil } }

    /// The enabled modifiers' shown values on the layer, in the order they
    /// were added.
    static func values(on layer: UnsafeMutableRawPointer) -> [(keyPath: String, value: NSObject, additive: Bool)] {
        withLock {
            (byLayer[layer] ?? []).compactMap { modifier in
                guard modifier.enabled, let value = modifier.presented else { return nil }
                return (modifier.keyPath, value, modifier.additive)
            }
        }
    }

    static var any: Bool { withLock { !byLayer.isEmpty } }
}

final class PresentationModifierGroupState {
    var capacity = 0
    var updatesAsynchronously = true
    var modifiers: [CAPresentationModifier] = []
}

/// CAPresentationModifierGroup (private): modifiers whose values show
/// together when it is flushed.
@ObjCClass("CAPresentationModifierGroup")
open class CAPresentationModifierGroup: NSObject {
    static let states = ObjectStates { PresentationModifierGroupState() }
    var group: PresentationModifierGroupState { CAPresentationModifierGroup.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        CAPresentationModifierGroup.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CAPresentationModifierGroup.objCClass.pointer)
    }

    @ObjCClassMethod("groupWithCapacity:")
    static func make(_ cls: ObjCClass, capacity: UInt) -> CAPresentationModifierGroup {
        let group = cls.object.allocated().initialized().unsafeCast(to: CAPresentationModifierGroup.self)
        group.group.capacity = Int(capacity)
        return group
    }

    func add(_ modifier: CAPresentationModifier) { group.modifiers.append(modifier) }

    @ObjCMethod("count") func count() -> UInt { UInt(group.modifiers.count) }
    @ObjCMethod("capacity") func capacity() -> UInt { UInt(group.capacity) }
    @ObjCMethod("updatesAsynchronously") func updatesAsynchronously() -> Bool { group.updatesAsynchronously }
    @ObjCMethod("setUpdatesAsynchronously:") func setUpdatesAsynchronously(_ value: Bool) { group.updatesAsynchronously = value }

    @ObjCMethod("flush")
    func flush() {
        group.modifiers.forEach { $0.show() }
        Compositing.changed()
    }
    @ObjCMethod("flushWithTargetTime:") func flush(targetTime: Double) { flush() }
    @ObjCMethod("flushLocally") func flushLocally() { flush() }
    @ObjCMethod("flushLocallyWithTargetTime:") func flushLocally(targetTime: Double) { flush() }
    @ObjCMethod("flushWithTransaction") func flushWithTransaction() { flush() }
    @ObjCMethod("flushWithTransactionAndTargetTime:") func flushWithTransaction(targetTime: Double) { flush() }
}

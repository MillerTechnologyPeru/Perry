import CPerryGeometry
import PerryObjCInterop

// Motion effects: parallax as the device tilts. There is no device motion,
// so the effects a view is given are kept and change nothing.

final class MotionEffectState: ObjectState {
    var keyPath: String?
    /// UIInterpolatingMotionEffectType: tilt along the horizontal axis 0,
    /// the vertical axis 1.
    var type = 0
    var minimum: NSObject?
    var maximum: NSObject?
    var effects: [NSObject] = []
}

@ObjCClass("UIMotionEffect")
open class UIMotionEffect: NSObject {
    static let states = StateTable<MotionEffectState>()
    var motion: MotionEffectState { UIMotionEffect.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        UIMotionEffect.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIMotionEffect.objCClass.pointer)
    }

    /// The key paths and values for a view at an offset of the device's
    /// tilt: none, without motion.
    @ObjCMethod("keyPathsAndRelativeValuesForViewerOffset:")
    func keyPathsAndRelativeValues(forViewerOffset offset: UIOffset) -> NSObject? { nil }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }
}

/// UIOffset, a horizontal and a vertical distance, laid out as CGSize.
typealias UIOffset = CGSize

@ObjCClass("UIInterpolatingMotionEffect")
open class UIInterpolatingMotionEffect: UIMotionEffect {
    @ObjCMethod("initWithKeyPath:type:")
    func initialize(keyPath: String, type: Int) -> Self {
        (motion.keyPath, motion.type) = (keyPath, type)
        return self
    }

    @ObjCMethod("keyPath") func keyPath() -> String? { motion.keyPath }
    @ObjCMethod("type") func type() -> Int { motion.type }
    @ObjCMethod("minimumRelativeValue") func minimumRelativeValue() -> NSObject? { motion.minimum }
    @ObjCMethod("setMinimumRelativeValue:") func setMinimumRelativeValue(_ value: NSObject?) { motion.minimum = value }
    @ObjCMethod("maximumRelativeValue") func maximumRelativeValue() -> NSObject? { motion.maximum }
    @ObjCMethod("setMaximumRelativeValue:") func setMaximumRelativeValue(_ value: NSObject?) { motion.maximum = value }
}

@ObjCClass("UIMotionEffectGroup")
open class UIMotionEffectGroup: UIMotionEffect {
    @ObjCMethod("motionEffects") func motionEffects() -> NSObject? { motion.effects.isEmpty ? nil : NSMutableArray.of(motion.effects) }
    @ObjCMethod("setMotionEffects:") func setMotionEffects(_ effects: NSArray?) { motion.effects = effects?.elements ?? [] }
}

@ObjCCategory("UIMotionEffects")
extension UIView {
    @ObjCMethod("motionEffects") func motionEffects() -> NSObject { NSMutableArray.of(state.motionEffects) }
    @ObjCMethod("setMotionEffects:") func setMotionEffects(_ effects: NSArray?) { state.motionEffects = effects?.elements ?? [] }

    @ObjCMethod("addMotionEffect:")
    func addMotionEffect(_ effect: NSObject) {
        guard !state.motionEffects.contains(where: { $0.objcObject == effect.objcObject }) else { return }
        state.motionEffects.append(effect)
    }

    @ObjCMethod("removeMotionEffect:")
    func removeMotionEffect(_ effect: NSObject) { state.motionEffects.removeAll { $0.objcObject == effect.objcObject } }
}

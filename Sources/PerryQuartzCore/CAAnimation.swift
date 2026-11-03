import CPerryGeometry
import Glibc
import PerryObjCInterop

// Core Animation's animations. A layer runs copies of those added to it
// (CALayer.addAnimation:forKey:); each frame, the layer is drawn as it
// presents, its animations' values applied to its model values
// (Presentation). Timing follows CAMediaTiming: begin time, speed, time
// offset, repeats, autoreversing and fill modes, then a timing function's
// cubic Bézier curve.

final class AnimationState {
    var values: [String: NSObject] = [:]
    var duration = 0.0
    var delegate: NSObject?
    var timingFunction: CAMediaTimingFunction?
    var removedOnCompletion = true
    var repeatCount: Float = 0
    var repeatDuration: Double = 0
    var autoreverses = false
    var beginTime: Double = 0
    var timeOffset: Double = 0
    var speed: Float = 1
    var additive = false
    var cumulative = false
    var fillMode = "removed"
    // CASpringAnimation's.
    var mass: Double = 1
    var stiffness: Double = 100
    var damping: Double = 10
    var initialVelocity: Double = 0
    /// When the layer was given it, and whether its delegate has heard it
    /// start.
    var added: Double = 0
    var started = false
}

@ObjCClass("CAAnimation")
open class CAAnimation: NSObject {
    var state = AnimationState()

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCClassMethod("animation") static func animation(_ cls: ObjCClass) -> NSObject { cls.object.allocated().initialized() }

    /// A copy of the same class with the same settings, as a layer keeps.
    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        let copy = NSObject(ObjCRuntime.objectClass(objcObject)!).allocated().initialized().unsafeCast(to: CAAnimation.self)
        let (from, to) = (state, copy.state)
        (to.values, to.duration, to.delegate, to.timingFunction) = (from.values, from.duration, from.delegate, from.timingFunction)
        (to.removedOnCompletion, to.repeatCount, to.repeatDuration, to.autoreverses) = (from.removedOnCompletion, from.repeatCount,
                                                                                      from.repeatDuration, from.autoreverses)
        (to.beginTime, to.timeOffset, to.speed, to.additive, to.cumulative) = (from.beginTime, from.timeOffset, from.speed,
                                                                               from.additive, from.cumulative)
        (to.fillMode, to.mass, to.stiffness, to.damping, to.initialVelocity) = (from.fillMode, from.mass, from.stiffness, from.damping,
                                                                                from.initialVelocity)
        return ObjCRuntime.retain(copy.objcObject)
    }

    func copied() -> CAAnimation { CAAnimation.objCInstance(copy(zone: nil)!, ownership: .adopt) }

    @ObjCMethod("duration") func duration() -> Double { state.duration }
    @ObjCMethod("setDuration:") func setDuration(_ duration: Double) { state.duration = duration }
    @ObjCMethod("delegate") func delegate() -> NSObject? { state.delegate }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { state.delegate = delegate }
    @ObjCMethod("timingFunction") func timingFunction() -> CAMediaTimingFunction? { state.timingFunction }
    @ObjCMethod("setTimingFunction:") func setTimingFunction(_ function: CAMediaTimingFunction?) { state.timingFunction = function }
    @ObjCMethod("isRemovedOnCompletion") func isRemovedOnCompletion() -> Bool { state.removedOnCompletion }
    @ObjCMethod("setRemovedOnCompletion:") func setRemovedOnCompletion(_ removed: Bool) { state.removedOnCompletion = removed }
    @ObjCMethod("fillMode") func fillMode() -> String { state.fillMode }
    @ObjCMethod("setFillMode:") func setFillMode(_ mode: String?) { state.fillMode = mode ?? "removed" }

    /// The other properties (type, subtype, fromValue, keyPath...), kept.
    @ObjCMethod("valueForKey:") func value(forKey key: String) -> NSObject? { state.values[key] }
    @ObjCMethod("setValue:forKey:") func setValue(_ value: NSObject?, forKey key: String) { state.values[key] = value }

    private func string(_ key: String) -> String? { state.values[key]?.stringValue }
    private func setString(_ key: String, _ value: String?) { state.values[key] = value.map { NSObject($0.objCReturnValue()!) } }

    @ObjCMethod("type") func type() -> String? { string("type") }
    @ObjCMethod("setType:") func setType(_ type: String?) { setString("type", type) }
    @ObjCMethod("subtype") func subtype() -> String? { string("subtype") }
    @ObjCMethod("setSubtype:") func setSubtype(_ subtype: String?) { setString("subtype", subtype) }
    @ObjCMethod("keyPath") func keyPath() -> String? { string("keyPath") }
    @ObjCMethod("setKeyPath:") func setKeyPath(_ keyPath: String?) { setString("keyPath", keyPath) }
    @ObjCMethod("fromValue") func fromValue() -> NSObject? { state.values["fromValue"] }
    @ObjCMethod("setFromValue:") func setFromValue(_ value: NSObject?) { state.values["fromValue"] = value }
    @ObjCMethod("toValue") func toValue() -> NSObject? { state.values["toValue"] }
    @ObjCMethod("setToValue:") func setToValue(_ value: NSObject?) { state.values["toValue"] = value }
    @ObjCMethod("byValue") func byValue() -> NSObject? { state.values["byValue"] }
    @ObjCMethod("setByValue:") func setByValue(_ value: NSObject?) { state.values["byValue"] = value }
    @ObjCMethod("valueFunction") func valueFunction() -> NSObject? { state.values["valueFunction"] }
    @ObjCMethod("setValueFunction:") func setValueFunction(_ function: NSObject?) { state.values["valueFunction"] = function }

    // CAMediaTiming.
    @ObjCMethod("repeatCount") func repeatCount() -> Float { state.repeatCount }
    @ObjCMethod("setRepeatCount:") func setRepeatCount(_ count: Float) { state.repeatCount = count }
    @ObjCMethod("repeatDuration") func repeatDuration() -> Double { state.repeatDuration }
    @ObjCMethod("setRepeatDuration:") func setRepeatDuration(_ duration: Double) { state.repeatDuration = duration }
    @ObjCMethod("autoreverses") func autoreverses() -> Bool { state.autoreverses }
    @ObjCMethod("setAutoreverses:") func setAutoreverses(_ autoreverses: Bool) { state.autoreverses = autoreverses }
    @ObjCMethod("beginTime") func beginTime() -> Double { state.beginTime }
    @ObjCMethod("setBeginTime:") func setBeginTime(_ time: Double) { state.beginTime = time }
    @ObjCMethod("timeOffset") func timeOffset() -> Double { state.timeOffset }
    @ObjCMethod("setTimeOffset:") func setTimeOffset(_ offset: Double) { state.timeOffset = offset }
    @ObjCMethod("speed") func speed() -> Float { state.speed }
    @ObjCMethod("setSpeed:") func setSpeed(_ speed: Float) { state.speed = speed }

    @ObjCMethod("isAdditive") func isAdditive() -> Bool { state.additive }
    @ObjCMethod("setAdditive:") func setAdditive(_ additive: Bool) { state.additive = additive }
    @ObjCMethod("isCumulative") func isCumulative() -> Bool { state.cumulative }
    @ObjCMethod("setCumulative:") func setCumulative(_ cumulative: Bool) { state.cumulative = cumulative }

    // CAKeyframeAnimation's and CAAnimationGroup's.
    @ObjCMethod("values") func values() -> NSObject? { state.values["values"] }
    @ObjCMethod("setValues:") func setValues(_ values: NSObject?) { state.values["values"] = values }
    @ObjCMethod("keyTimes") func keyTimes() -> NSObject? { state.values["keyTimes"] }
    @ObjCMethod("setKeyTimes:") func setKeyTimes(_ times: NSObject?) { state.values["keyTimes"] = times }
    @ObjCMethod("timingFunctions") func timingFunctions() -> NSObject? { state.values["timingFunctions"] }
    @ObjCMethod("setTimingFunctions:") func setTimingFunctions(_ functions: NSObject?) { state.values["timingFunctions"] = functions }
    @ObjCMethod("calculationMode") func calculationMode() -> String { string("calculationMode") ?? "linear" }
    @ObjCMethod("setCalculationMode:") func setCalculationMode(_ mode: String?) { setString("calculationMode", mode) }
    @ObjCMethod("rotationMode") func rotationMode() -> String? { string("rotationMode") }
    @ObjCMethod("setRotationMode:") func setRotationMode(_ mode: String?) { setString("rotationMode", mode) }
    @ObjCMethod("path") func path() -> UnsafeMutableRawPointer? { state.values["path"]?.objcObject }
    @ObjCMethod("setPath:") func setPath(_ path: UnsafeMutableRawPointer?) { state.values["path"] = path.map { NSObject($0) } }
    @ObjCMethod("animations") func animations() -> NSObject? { state.values["animations"] }
    @ObjCMethod("setAnimations:") func setAnimations(_ animations: NSObject?) { state.values["animations"] = animations }

    // CASpringAnimation's.
    @ObjCMethod("mass") func mass() -> Double { state.mass }
    @ObjCMethod("setMass:") func setMass(_ mass: Double) { state.mass = mass }
    @ObjCMethod("stiffness") func stiffness() -> Double { state.stiffness }
    @ObjCMethod("setStiffness:") func setStiffness(_ stiffness: Double) { state.stiffness = stiffness }
    @ObjCMethod("damping") func damping() -> Double { state.damping }
    @ObjCMethod("setDamping:") func setDamping(_ damping: Double) { state.damping = damping }
    @ObjCMethod("initialVelocity") func initialVelocity() -> Double { state.initialVelocity }
    @ObjCMethod("setInitialVelocity:") func setInitialVelocity(_ velocity: Double) { state.initialVelocity = velocity }
    @ObjCMethod("settlingDuration") func settlingDuration() -> Double { Spring(state).settlingDuration }

    /// CAAction: an animation run for a key adds itself to the layer.
    @ObjCMethod("runActionForKey:object:arguments:")
    func runAction(forKey key: String, object: NSObject, arguments: NSObject?) {
        object.as(CALayer.self)?.addAnimation(self, forKey: key)
    }

    @ObjCMethod("shouldArchiveValueForKey:") func shouldArchiveValue(forKey key: String) -> Bool { true }

    @ObjCClassMethod("defaultValueForKey:") static func defaultValue(forKey key: String) -> NSObject? { nil }
}

@ObjCClass("CAPropertyAnimation")
open class CAPropertyAnimation: CAAnimation {
    @ObjCClassMethod("animationWithKeyPath:")
    static func animation(_ cls: ObjCClass, keyPath: String?) -> NSObject {
        let animation = cls.object.allocated().initialized().unsafeCast(to: CAAnimation.self)
        animation.setKeyPath(keyPath)
        return animation
    }
}

@ObjCClass("CABasicAnimation") open class CABasicAnimation: CAPropertyAnimation {}
@ObjCClass("CAKeyframeAnimation") open class CAKeyframeAnimation: CAPropertyAnimation {}

/// A basic animation whose progress follows a damped spring, for as long
/// as the spring takes to settle unless told otherwise.
@ObjCClass("CASpringAnimation")
open class CASpringAnimation: CABasicAnimation {
    @ObjCMethod("init") public required init() { super.init() }

    @ObjCMethod("initWithPerceptualDuration:bounce:")
    public required init(perceptualDuration duration: Double, bounce: Double) {
        super.init()
        state.mass = 1
        state.stiffness = pow(2 * .pi / max(duration, 0.01), 2)
        state.damping = 4 * .pi * (1 - min(max(bounce, -1), 1)) / max(duration, 0.01)
    }
}

/// A transition, which shows the layer's new state at once.
@ObjCClass("CATransition") open class CATransition: CAAnimation {}
@ObjCClass("CAAnimationGroup") open class CAAnimationGroup: CAAnimation {}

/// The function pacing an animation: a cubic Bézier curve from (0, 0) to
/// (1, 1) through two control points.
final class TimingFunctionState {
    var points: (Double, Double, Double, Double) = (0, 0, 1, 1)
}

@ObjCClass("CAMediaTimingFunction")
open class CAMediaTimingFunction: NSObject {
    var state = TimingFunctionState()

    @ObjCMethod("init") public required override init() { super.init() }

    static func points(named name: String) -> (Double, Double, Double, Double) {
        switch name {
        case "easeIn": return (0.42, 0, 1, 1)
        case "easeOut": return (0, 0, 0.58, 1)
        case "easeInEaseOut": return (0.42, 0, 0.58, 1)
        case "default": return (0.25, 0.1, 0.25, 1)
        default: return (0, 0, 1, 1)
        }
    }

    static func named(_ name: String) -> CAMediaTimingFunction {
        let function = CAMediaTimingFunction()
        function.state.points = points(named: name)
        return function
    }

    @ObjCClassMethod("functionWithName:")
    static func function(_ cls: ObjCClass, name: String) -> NSObject {
        let function = cls.object.allocated().initialized().unsafeCast(to: CAMediaTimingFunction.self)
        function.state.points = points(named: name)
        return function
    }

    @ObjCClassMethod("functionWithControlPoints::::")
    static func function(_ cls: ObjCClass, x1: Float, y1: Float, x2: Float, y2: Float) -> NSObject {
        let function = cls.object.allocated().initialized().unsafeCast(to: CAMediaTimingFunction.self)
        function.state.points = (Double(x1), Double(y1), Double(x2), Double(y2))
        return function
    }

    @ObjCMethod("initWithControlPoints::::")
    public required init(x1: Float, y1: Float, x2: Float, y2: Float) {
        super.init()
        state.points = (Double(x1), Double(y1), Double(x2), Double(y2))
    }

    /// Point 0 is (0, 0), 1 and 2 the control points, 3 is (1, 1).
    @ObjCMethod("getControlPointAtIndex:values:")
    func getControlPoint(at index: UInt, values: UnsafeMutablePointer<Float>?) {
        guard let values else { return }
        let points = state.points
        let point: (Double, Double) = index == 0 ? (0, 0) : index == 1 ? (points.0, points.1) : index == 2 ? (points.2, points.3) : (1, 1)
        (values[0], values[1]) = (Float(point.0), Float(point.1))
    }

    /// The eased progress at `t`: the curve's y where its x is `t`.
    func value(at t: Double) -> Double {
        let (x1, y1, x2, y2) = state.points
        if x1 == y1, x2 == y2 { return t }
        func bezier(_ s: Double, _ p1: Double, _ p2: Double) -> Double {
            let u = 1 - s
            return 3 * u * u * s * p1 + 3 * u * s * s * p2 + s * s * s
        }
        // x(s) is increasing; find s for t by bisection.
        var low = 0.0, high = 1.0, s = t
        for _ in 0..<40 {
            s = (low + high) / 2
            if bezier(s, x1, x2) < t { low = s } else { high = s }
        }
        return bezier(s, y1, y2)
    }
}

/// A damped spring from 0 to 1, as CASpringAnimation's progress.
struct Spring {
    let mass, stiffness, damping, velocity: Double

    init(_ state: AnimationState) {
        (mass, stiffness, damping, velocity) = (max(state.mass, 0.0001), max(state.stiffness, 0.0001), max(state.damping, 0),
                                                state.initialVelocity)
    }

    /// The displacement at `t` seconds.
    func value(at t: Double) -> Double {
        let omega = (stiffness / mass).squareRoot(), zeta = damping / (2 * (stiffness * mass).squareRoot())
        if zeta < 1 {
            let damped = omega * (1 - zeta * zeta).squareRoot()
            let decay = exp(-zeta * omega * t)
            return 1 - decay * (cos(damped * t) + (zeta * omega - velocity) / damped * sin(damped * t))
        }
        // Critically damped, or heavier, settling without overshoot.
        return 1 - exp(-omega * t) * (1 + (omega - velocity) * t)
    }

    /// How long until it stays within a thousandth of the end.
    var settlingDuration: Double {
        var settled = 0.0
        var t = 0.0
        while t < 30 {
            if abs(1 - value(at: t)) > 0.001 { settled = t + 1.0 / 60 }
            t += 1.0 / 60
        }
        return settled
    }
}

// MARK: - Animated values

/// A value an animation interpolates, read from and written to a layer.
enum AnimatedValue {
    case number(Double)
    case point(CGPoint)
    case size(CGSize)
    case rect(CGRect)
    case transform(CATransform3D)
    /// Red, green, blue and alpha.
    case color([Double])
    /// A value that changes in steps: a path, contents, hidden.
    case object(NSObject?)

    static let colorKeys: Set<String> = ["backgroundColor", "borderColor", "shadowColor", "strokeColor", "fillColor"]
    static let numberKeys: Set<String> = [
        "opacity", "zPosition", "cornerRadius", "borderWidth", "shadowOpacity", "shadowRadius", "position.x", "position.y",
        "bounds.size.width", "bounds.size.height", "bounds.origin.x", "bounds.origin.y", "transform.rotation", "transform.rotation.z",
        "transform.scale", "transform.scale.x", "transform.scale.y", "transform.translation.x", "transform.translation.y",
        "strokeStart", "strokeEnd", "lineWidth", "lineDashPhase", "miterLimit", "hidden",
    ]
    static let discreteKeys: Set<String> = ["hidden", "contents", "path", "masksToBounds"]

    static func animatable(_ key: String) -> Bool {
        colorKeys.contains(key) || numberKeys.contains(key) || discreteKeys.contains(key)
            || ["position", "anchorPoint", "bounds", "bounds.size", "bounds.origin", "transform", "sublayerTransform", "shadowOffset"].contains(key)
    }

    // MARK: Reading and writing

    /// The key's value in the model layer.
    static func model(of layer: CALayer, _ key: String) -> AnimatedValue? {
        value(of: layer.state, shape: layer.as(CAShapeLayer.self)?.shape, key)
    }

    static func value(of state: LayerState, shape: ShapeLayerState?, _ key: String) -> AnimatedValue? {
        let affine = state.transform
        switch key {
        case "opacity": return .number(Double(state.opacity))
        case "zPosition": return .number(state.zPosition)
        case "cornerRadius": return .number(state.cornerRadius)
        case "borderWidth": return .number(state.borderWidth)
        case "shadowOpacity": return .number(Double(state.shadowOpacity))
        case "shadowRadius": return .number(state.shadowRadius)
        case "shadowOffset": return .size(state.shadowOffset)
        case "position": return .point(state.position)
        case "position.x": return .number(state.position.x)
        case "position.y": return .number(state.position.y)
        case "anchorPoint": return .point(state.anchorPoint)
        case "bounds": return .rect(state.bounds)
        case "bounds.size": return .size(state.bounds.size)
        case "bounds.origin": return .point(state.bounds.origin)
        case "bounds.size.width": return .number(state.bounds.width)
        case "bounds.size.height": return .number(state.bounds.height)
        case "bounds.origin.x": return .number(state.bounds.minX)
        case "bounds.origin.y": return .number(state.bounds.minY)
        case "transform": return .transform(state.transform3D)
        case "sublayerTransform": return .transform(state.sublayerTransform)
        case "transform.rotation", "transform.rotation.z": return .number(atan2(affine.b, affine.a))
        case "transform.scale", "transform.scale.x": return .number((affine.a * affine.a + affine.b * affine.b).squareRoot())
        case "transform.scale.y": return .number((affine.c * affine.c + affine.d * affine.d).squareRoot())
        case "transform.translation.x": return .number(affine.tx)
        case "transform.translation.y": return .number(affine.ty)
        case "backgroundColor": return color(state.backgroundColor)
        case "borderColor": return color(state.borderColor)
        case "shadowColor": return color(state.shadowColor)
        case "hidden": return .number(state.hidden ? 1 : 0)
        case "masksToBounds": return .number(state.masksToBounds ? 1 : 0)
        case "contents": return .object(state.contents)
        case "strokeStart": return shape.map { .number($0.strokeStart) }
        case "strokeEnd": return shape.map { .number($0.strokeEnd) }
        case "lineWidth": return shape.map { .number($0.lineWidth) }
        case "lineDashPhase": return shape.map { .number($0.lineDashPhase) }
        case "miterLimit": return shape.map { .number($0.miterLimit) }
        case "strokeColor": return shape.flatMap { color($0.strokeColor) }
        case "fillColor": return shape.flatMap { color($0.fillColor) }
        case "path": return shape.map { .object($0.path.map { NSObject($0) }) }
        default: return nil
        }
    }

    /// Writes the value under `key` into a layer's state, or its shape's.
    func write(to state: LayerState, shape: ShapeLayerState?, _ key: String) {
        func number() -> Double? { if case .number(let value) = self { return value }; return nil }
        func transformed(_ body: (inout Decomposed) -> Void) {
            var parts = Decomposed(state.transform)
            body(&parts)
            state.transform = parts.affine
        }
        switch (key, self) {
        case ("opacity", .number(let value)): state.opacity = Float(value)
        case ("zPosition", .number(let value)): state.zPosition = value
        case ("cornerRadius", .number(let value)): state.cornerRadius = value
        case ("borderWidth", .number(let value)): state.borderWidth = value
        case ("shadowOpacity", .number(let value)): state.shadowOpacity = Float(value)
        case ("shadowRadius", .number(let value)): state.shadowRadius = value
        case ("shadowOffset", .size(let value)): state.shadowOffset = value
        case ("position", .point(let value)): state.position = value
        case ("position.x", .number(let value)): state.position.x = value
        case ("position.y", .number(let value)): state.position.y = value
        case ("anchorPoint", .point(let value)): state.anchorPoint = value
        case ("bounds", .rect(let value)): state.bounds = value
        case ("bounds.size", .size(let value)): state.bounds.size = value
        case ("bounds.origin", .point(let value)): state.bounds.origin = value
        case ("bounds.size.width", .number(let value)): state.bounds.size.width = value
        case ("bounds.size.height", .number(let value)): state.bounds.size.height = value
        case ("bounds.origin.x", .number(let value)): state.bounds.origin.x = value
        case ("bounds.origin.y", .number(let value)): state.bounds.origin.y = value
        case ("transform", .transform(let value)): state.transform3D = value
        case ("sublayerTransform", .transform(let value)): state.sublayerTransform = value
        case ("transform.rotation", .number(let value)), ("transform.rotation.z", .number(let value)): transformed { $0.rotation = value }
        case ("transform.scale", .number(let value)): transformed { ($0.scaleX, $0.scaleY) = (value, value) }
        case ("transform.scale.x", .number(let value)): transformed { $0.scaleX = value }
        case ("transform.scale.y", .number(let value)): transformed { $0.scaleY = value }
        case ("transform.translation.x", .number(let value)): transformed { $0.tx = value }
        case ("transform.translation.y", .number(let value)): transformed { $0.ty = value }
        case ("backgroundColor", .color(let value)): AnimatedValue.assign(&state.backgroundColor, value)
        case ("borderColor", .color(let value)): AnimatedValue.assign(&state.borderColor, value)
        case ("shadowColor", .color(let value)): AnimatedValue.assign(&state.shadowColor, value)
        case ("hidden", _): state.hidden = (number() ?? 0) >= 0.5
        case ("masksToBounds", _): state.masksToBounds = (number() ?? 0) >= 0.5
        case ("contents", .object(let value)): state.contents = value
        case ("strokeStart", .number(let value)): shape?.strokeStart = value
        case ("strokeEnd", .number(let value)): shape?.strokeEnd = value
        case ("lineWidth", .number(let value)): shape?.lineWidth = value
        case ("lineDashPhase", .number(let value)): shape?.lineDashPhase = value
        case ("miterLimit", .number(let value)): shape?.miterLimit = value
        case ("strokeColor", .color(let value)): if let shape { AnimatedValue.assign(&shape.strokeColor, value) }
        case ("fillColor", .color(let value)): if let shape { AnimatedValue.assign(&shape.fillColor, value) }
        case ("path", .object(let value)): if let shape { LayerState.setColor(&shape.path, value?.objcObject) }
        default: break
        }
    }

    /// Sets the model layer's value, as -setValue:forKey: does.
    func apply(to layer: CALayer, key: String) {
        write(to: layer.state, shape: layer.as(CAShapeLayer.self)?.shape, key)
    }

    private static func color(_ color: CGRef?) -> AnimatedValue? {
        guard let color, let components = CG.colorGetComponents(color) else { return .color([0, 0, 0, 0]) }
        if CG.colorGetNumberOfComponents(color) == 2 { return .color([components[0], components[0], components[0], components[1]]) }
        return .color([components[0], components[1], components[2], components[3]])
    }

    /// A new CGColor, +1.
    static func makeColor(_ rgba: [Double]) -> CGRef? { CG.colorCreateSRGB(rgba[0], rgba[1], rgba[2], rgba[3]) }

    /// Puts a new color of `rgba` in `slot`.
    static func assign(_ slot: inout CGRef?, _ rgba: [Double]) {
        let color = makeColor(rgba)
        LayerState.setColor(&slot, color)
        if let color { CG.release(color) }
    }

    // MARK: Boxing

    /// The value an animation or key-value coding gives for `key`.
    init?(boxed object: NSObject?, key: String) {
        guard let object else {
            if AnimatedValue.discreteKeys.contains(key) || key == "contents" { self = .object(nil); return }
            return nil
        }
        if AnimatedValue.colorKeys.contains(key) {
            guard let components = CG.colorGetComponents(object.objcObject) else { return nil }
            let count = CG.colorGetNumberOfComponents(object.objcObject)
            self = .color(count == 2 ? [components[0], components[0], components[0], components[1]]
                                     : [components[0], components[1], components[2], components[3]])
            return
        }
        if key == "contents" || key == "path" { self = .object(object); return }
        if object.is(NSNumber.self) {
            self = .number(object.sendDoubleValue())
            return
        }
        guard object.is(NSValue.self) else { return nil }
        let value = object.unsafeCast(to: NSValue.self)
        if let point = value.unboxed(CGPoint.self) { self = .point(point) }
        else if let size = value.unboxed(CGSize.self) { self = .size(size) }
        else if let rect = value.unboxed(CGRect.self) { self = .rect(rect) }
        else if let transform = value.unboxed(CATransform3D.self) { self = .transform(transform) }
        else if let affine = value.unboxed(CGAffineTransform.self) { self = .transform(CATransform3D(affine)) }
        else { return nil }
    }

    func boxed() -> NSObject? {
        switch self {
        case .number(let value): return NSNumber.make(double: value)
        case .point(let value): return NSValue.boxing(value)
        case .size(let value): return NSValue.boxing(value)
        case .rect(let value): return NSValue.boxing(value)
        case .transform(let value): return NSValue.boxing(value)
        case .color(let value): return AnimatedValue.makeColor(value).map { NSObject(objcObject: $0, ownership: .adopt) }
        case .object(let value): return value
        }
    }

    // MARK: Arithmetic

    /// `a` at 0, `b` at 1.
    static func interpolate(_ a: AnimatedValue, _ b: AnimatedValue, _ t: Double) -> AnimatedValue {
        func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        switch (a, b) {
        case (.number(let x), .number(let y)): return .number(mix(x, y))
        case (.point(let x), .point(let y)): return .point(CGPoint(x: mix(x.x, y.x), y: mix(x.y, y.y)))
        case (.size(let x), .size(let y)): return .size(CGSize(width: mix(x.width, y.width), height: mix(x.height, y.height)))
        case (.rect(let x), .rect(let y)):
            return .rect(CGRect(x: mix(x.minX, y.minX), y: mix(x.minY, y.minY), width: mix(x.width, y.width), height: mix(x.height, y.height)))
        case (.transform(let x), .transform(let y)):
            // By parts, so rotations turn rather than shear.
            guard x.isAffine, y.isAffine else { return .transform(CATransform3D(rows: zip(x.rows, y.rows).map { mix($0, $1) })) }
            let (p, q) = (Decomposed(x.affine), Decomposed(y.affine))
            var mixed = p
            (mixed.tx, mixed.ty) = (mix(p.tx, q.tx), mix(p.ty, q.ty))
            (mixed.scaleX, mixed.scaleY, mixed.rotation) = (mix(p.scaleX, q.scaleX), mix(p.scaleY, q.scaleY), mix(p.rotation, q.rotation))
            return .transform(CATransform3D(mixed.affine))
        case (.color(let x), .color(let y)): return .color(zip(x, y).map { mix($0, $1) })
        default: return t < 0.5 ? a : b
        }
    }

    static func add(_ a: AnimatedValue, _ b: AnimatedValue) -> AnimatedValue {
        switch (a, b) {
        case (.number(let x), .number(let y)): return .number(x + y)
        case (.point(let x), .point(let y)): return .point(CGPoint(x: x.x + y.x, y: x.y + y.y))
        case (.size(let x), .size(let y)): return .size(CGSize(width: x.width + y.width, height: x.height + y.height))
        case (.rect(let x), .rect(let y)): return .rect(CGRect(x: x.minX + y.minX, y: x.minY + y.minY, width: x.width + y.width,
                                                              height: x.height + y.height))
        case (.transform(let x), .transform(let y)): return .transform(y.concatenating(x))
        case (.color(let x), .color(let y)): return .color(zip(x, y).map { min($0 + $1, 1) })
        default: return b
        }
    }

    static func subtract(_ a: AnimatedValue, _ b: AnimatedValue) -> AnimatedValue {
        switch (a, b) {
        case (.number(let x), .number(let y)): return .number(x - y)
        case (.point(let x), .point(let y)): return .point(CGPoint(x: x.x - y.x, y: x.y - y.y))
        case (.size(let x), .size(let y)): return .size(CGSize(width: x.width - y.width, height: x.height - y.height))
        case (.rect(let x), .rect(let y)): return .rect(CGRect(x: x.minX - y.minX, y: x.minY - y.minY, width: x.width - y.width,
                                                              height: x.height - y.height))
        case (.transform(let x), .transform(let y)): return .transform(y.inverted.concatenating(x))
        case (.color(let x), .color(let y)): return .color(zip(x, y).map { max($0 - $1, 0) })
        default: return a
        }
    }
}

/// An affine transform as scale, then rotation, then translation.
struct Decomposed {
    var scaleX, scaleY, rotation, tx, ty: Double

    init(_ t: CGAffineTransform) {
        scaleX = (t.a * t.a + t.b * t.b).squareRoot()
        rotation = atan2(t.b, t.a)
        // The y axis's length, signed to keep a mirror image mirrored.
        let determinant = t.a * t.d - t.b * t.c
        scaleY = scaleX == 0 ? (t.c * t.c + t.d * t.d).squareRoot() : determinant / scaleX
        (tx, ty) = (t.tx, t.ty)
    }

    var affine: CGAffineTransform {
        let c = cos(rotation), s = sin(rotation)
        return CGAffineTransform(a: scaleX * c, b: scaleX * s, c: -scaleY * s, d: scaleY * c, tx: tx, ty: ty)
    }
}

@ObjCConstants
enum AnimationConstants {
    static let kCATransitionFade = "fade"
    static let kCATransitionMoveIn = "moveIn"
    static let kCATransitionPush = "push"
    static let kCATransitionReveal = "reveal"
    static let kCATransitionFromRight = "fromRight"
    static let kCATransitionFromLeft = "fromLeft"
    static let kCATransitionFromTop = "fromTop"
    static let kCATransitionFromBottom = "fromBottom"
    static let kCAAnimationLinear = "linear"
    static let kCAAnimationDiscrete = "discrete"
    static let kCAAnimationPaced = "paced"
    static let kCAAnimationCubic = "cubic"
    static let kCAAnimationCubicPaced = "cubicPaced"
    static let kCAAnimationRotateAuto = "auto"
    static let kCAAnimationRotateAutoReverse = "autoReverse"
    static let kCAValueFunctionRotateX = "rotateX"
    static let kCAValueFunctionRotateY = "rotateY"
    static let kCAValueFunctionRotateZ = "rotateZ"
    static let kCAValueFunctionScale = "scale"
    static let kCAValueFunctionScaleX = "scaleX"
    static let kCAValueFunctionScaleY = "scaleY"
    static let kCAValueFunctionScaleZ = "scaleZ"
    static let kCAValueFunctionTranslate = "translate"
    static let kCAValueFunctionTranslateX = "translateX"
    static let kCAValueFunctionTranslateY = "translateY"
    static let kCAValueFunctionTranslateZ = "translateZ"
    static let kCAOnOrderIn = "onOrderIn"
    static let kCAOnOrderOut = "onOrderOut"
    static let kCATransition = "transition"
}

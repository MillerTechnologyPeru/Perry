import CPerryMotion
import Glibc
import PerryObjCInterop

// CoreMotion, without motion sensors: the device's attitude is the first
// gamepad's left stick, taken for a tilt. Pushed right, the device's right
// edge is down; pushed up, its far edge is; all the way is 30 degrees
// (PERRY_COREMOTION_TILT sets the degrees). At rest the device lies flat
// with its screen up. A game steered by tilting the device is so steered
// by the stick. There is no rotation rate, no acceleration but gravity's
// and a shake's (PERRY_COREMOTION_SHAKE), and no magnetometer; updates'
// queues are not used, and handlers are called on the main queue.

extension CMAcceleration: ObjCScalar { public static var objCTypeEncoding: String { "{?=ddd}" } }
extension CMRotationRate: ObjCScalar { public static var objCTypeEncoding: String { "{?=ddd}" } }
extension CMQuaternion: ObjCScalar { public static var objCTypeEncoding: String { "{?=dddd}" } }
extension CMRotationMatrix: ObjCScalar { public static var objCTypeEncoding: String { "{?=ddddddddd}" } }

/// A rotation from the device's axes (x right, y to the top, z out of the
/// screen) to the reference frame's, whose z is up: a unit quaternion.
struct Rotation {
    var w = 1.0, x = 0.0, y = 0.0, z = 0.0

    static let identity = Rotation()

    /// CoreMotion's angles: roll about the device's y axis, then pitch
    /// about its x, then yaw about z.
    init(roll: Double, pitch: Double, yaw: Double) {
        let aboutY = Rotation(w: cos(roll / 2), x: 0, y: sin(roll / 2), z: 0)
        let aboutX = Rotation(w: cos(pitch / 2), x: sin(pitch / 2), y: 0, z: 0)
        let aboutZ = Rotation(w: cos(yaw / 2), x: 0, y: 0, z: sin(yaw / 2))
        self = aboutZ * aboutX * aboutY
    }

    init(w: Double = 1, x: Double = 0, y: Double = 0, z: Double = 0) { (self.w, self.x, self.y, self.z) = (w, x, y, z) }

    static func * (a: Rotation, b: Rotation) -> Rotation {
        Rotation(w: a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
                 x: a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
                 y: a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
                 z: a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w)
    }

    var inverse: Rotation { Rotation(w: w, x: -x, y: -y, z: -z) }

    /// The matrix's rows.
    var rows: [[Double]] {
        [[1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y)],
         [2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x)],
         [2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y)]]
    }

    var pitch: Double { asin(max(-1, min(1, rows[2][1]))) }
    var roll: Double { atan2(-rows[2][0], rows[2][2]) }
    var yaw: Double { atan2(-rows[0][1], rows[1][1]) }

    /// Gravity in the device's axes, in g: straight down the reference
    /// frame's z.
    var gravity: CMAcceleration {
        let down = rows[2]
        return CMAcceleration(x: -down[0], y: -down[1], z: -down[2])
    }
}

/// The tilt the stick stands for.
enum Tilt {
    /// The tilt at the stick's end, in radians.
    nonisolated(unsafe) static let limit: Double = {
        let degrees = getenv("PERRY_COREMOTION_TILT").flatMap { Double(String(cString: $0)) } ?? 30
        return max(1, min(89, degrees)) * .pi / 180
    }()

    /// PERRY_COREMOTION_STICK, "x,y" or "x,y,seconds": a stick held there,
    /// from that long after the program started, to try a program's
    /// steering without a gamepad.
    nonisolated(unsafe) static let held: (x: Float, y: Float, from: Double)? = {
        guard let text = getenv("PERRY_COREMOTION_STICK").map({ String(cString: $0) }) else { return nil }
        let parts = text.split(separator: ",").compactMap { Float($0) }
        guard parts.count >= 2 else { return nil }
        return (parts[0], parts[1], Controllers.now() + Double(parts.count > 2 ? parts[2] : 0))
    }()

    /// UIKit's interface orientation: portrait 1, upside down 2, landscape
    /// with the home button on the right 3, on the left 4. Landscape
    /// without UIKit.
    static func orientation() -> Int {
        typealias Send = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> UnsafeMutableRawPointer?
        typealias SendInteger = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> Int
        guard let cls = "UIApplication".withCString({ ObjCRuntime.functions.getClass($0) }),
              let application = unsafeBitCast(ObjCRuntime.msgSend, to: Send.self)(cls, ObjCRuntime.selector("sharedApplication"))
        else { return 3 }
        return unsafeBitCast(ObjCRuntime.msgSend, to: SendInteger.self)(application, ObjCRuntime.selector("statusBarOrientation"))
    }

    /// The device's attitude now. The stick is in the interface's
    /// directions, which the device's axes are turned from in landscape.
    static func attitude() -> Rotation {
        var stick = Controllers.leftStick()
        if let held { stick = Controllers.now() >= held.from ? (held.x, held.y) : (0, 0) }
        let right = Double(stick.x) * limit, far = Double(stick.y) * limit
        switch orientation() {
        case 3: return Rotation(roll: far, pitch: right, yaw: 0)
        case 4: return Rotation(roll: -far, pitch: -right, yaw: 0)
        case 2: return Rotation(roll: -right, pitch: far, yaw: 0)
        default: return Rotation(roll: right, pitch: -far, yaw: 0)
        }
    }
}

/// A shake of the device, for programs that take one from the
/// accelerometer (a pinball table's nudge): with PERRY_COREMOTION_SHAKE set
/// to a gamepad's button (as PERRY_GAMECONTROLLER_TOUCHES names them), each
/// press of it is a third of a second of the device thrown back and
/// forth, 2.5 g each way along each of its axes, so that the shake shows
/// however the program holds the device.
enum Shake {
    nonisolated(unsafe) static let button: String? = getenv("PERRY_COREMOTION_SHAKE").map { String(cString: $0).lowercased() }
    nonisolated(unsafe) private static var wasHeld = false
    nonisolated(unsafe) private static var began = -Double.infinity
    private static let length = 1.0 / 3, period = 0.1, strength = 2.5

    /// What the shake adds to the device's acceleration now, in g.
    static func acceleration() -> CMAcceleration {
        guard let button else { return CMAcceleration(x: 0, y: 0, z: 0) }
        let now = Controllers.now(), held = Controllers.isHeld(button)
        if held, !wasHeld {
            began = now
            Controllers.trace("motion: shake")
        }
        wasHeld = held
        let elapsed = now - began
        guard elapsed >= 0, elapsed < length else { return CMAcceleration(x: 0, y: 0, z: 0) }
        // One way for half of each period, the other for the rest.
        let side = elapsed.truncatingRemainder(dividingBy: period) < period / 2 ? strength : -strength
        return CMAcceleration(x: side, y: side, z: side)
    }
}

// MARK: - Data

@ObjCClass("CMLogItem")
open class CMLogItem: NSObject {
    var time = Controllers.now()

    @ObjCMethod("init") public required override init() { super.init() }

    /// Seconds since the device started.
    @ObjCMethod("timestamp") func timestamp() -> Double { time }
}

@ObjCClass("CMAttitude")
open class CMAttitude: NSObject {
    var rotation = Rotation.identity

    @ObjCMethod("init") public required override init() { super.init() }

    static func make(_ rotation: Rotation) -> CMAttitude {
        let attitude = CMAttitude()
        attitude.rotation = rotation
        return attitude
    }

    @ObjCMethod("roll") func roll() -> Double { rotation.roll }
    @ObjCMethod("pitch") func pitch() -> Double { rotation.pitch }
    @ObjCMethod("yaw") func yaw() -> Double { rotation.yaw }

    @ObjCMethod("quaternion")
    func quaternion() -> CMQuaternion { CMQuaternion(x: rotation.x, y: rotation.y, z: rotation.z, w: rotation.w) }

    /// The matrix that takes the reference frame's vectors to the device's.
    @ObjCMethod("rotationMatrix")
    func rotationMatrix() -> CMRotationMatrix {
        let rows = rotation.rows
        return CMRotationMatrix(m11: rows[0][0], m12: rows[1][0], m13: rows[2][0],
                                m21: rows[0][1], m22: rows[1][1], m23: rows[2][1],
                                m31: rows[0][2], m32: rows[1][2], m33: rows[2][2])
    }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> CMAttitude { CMAttitude.make(rotation) }

    /// The attitude as seen from another: the change since it.
    @ObjCMethod("multiplyByInverseOfAttitude:")
    func multiply(byInverseOf attitude: CMAttitude?) {
        if let attitude { rotation = attitude.rotation.inverse * rotation }
    }
}

@ObjCClass("CMAccelerometerData")
open class CMAccelerometerData: CMLogItem {
    var value = CMAcceleration(x: 0, y: 0, z: -1)

    @ObjCMethod("acceleration") func acceleration() -> CMAcceleration { value }
}

@ObjCClass("CMGyroData")
open class CMGyroData: CMLogItem {
    @ObjCMethod("rotationRate") func rotationRate() -> CMRotationRate { CMRotationRate(x: 0, y: 0, z: 0) }
}

@ObjCClass("CMDeviceMotion")
open class CMDeviceMotion: CMLogItem {
    var rotation = Rotation.identity
    var shake = CMAcceleration(x: 0, y: 0, z: 0)

    @ObjCMethod("attitude") func attitude() -> CMAttitude { CMAttitude.make(rotation) }
    @ObjCMethod("gravity") func gravity() -> CMAcceleration { rotation.gravity }
    @ObjCMethod("userAcceleration") func userAcceleration() -> CMAcceleration { shake }
    @ObjCMethod("rotationRate") func rotationRate() -> CMRotationRate { CMRotationRate(x: 0, y: 0, z: 0) }
    /// No magnetometer gives a heading.
    @ObjCMethod("heading") func heading() -> Double { -1 }
}

// MARK: - The manager

@ObjCClass("CMMotionManager")
open class CMMotionManager: NSObject {
    var accelerometerInterval = 1.0 / 60
    var deviceMotionInterval = 1.0 / 60
    var gyroInterval = 1.0 / 60
    var accelerometerActive = false
    var deviceMotionActive = false
    var accelerometerHandler: ObjCBlock?
    var deviceMotionHandler: ObjCBlock?
    var referenceFrame: UInt = 1

    @ObjCMethod("init") public required override init() { super.init() }

    /// CMAttitudeReferenceFrameXArbitraryZVertical, the one frame without
    /// a magnetometer.
    @ObjCClassMethod("availableAttitudeReferenceFrames") static func availableAttitudeReferenceFrames() -> UInt { 1 }
    @ObjCMethod("attitudeReferenceFrame") func attitudeReferenceFrame() -> UInt { referenceFrame }

    // MARK: Accelerometer

    @ObjCMethod("isAccelerometerAvailable") func isAccelerometerAvailable() -> Bool { true }
    @ObjCMethod("isAccelerometerActive") func isAccelerometerActive() -> Bool { accelerometerActive }
    @ObjCMethod("accelerometerUpdateInterval") func accelerometerUpdateInterval() -> Double { accelerometerInterval }
    @ObjCMethod("setAccelerometerUpdateInterval:")
    func setAccelerometerUpdateInterval(_ interval: Double) { accelerometerInterval = max(interval, 0.01) }

    @ObjCMethod("accelerometerData")
    func accelerometerData() -> CMAccelerometerData? {
        guard accelerometerActive else { return nil }
        let data = CMAccelerometerData()
        let gravity = Tilt.attitude().gravity, shake = Shake.acceleration()
        data.value = CMAcceleration(x: gravity.x + shake.x, y: gravity.y + shake.y, z: gravity.z + shake.z)
        return data
    }

    @ObjCMethod("startAccelerometerUpdates")
    func startAccelerometerUpdates() {
        Controllers.trace("motion: accelerometer updates start, to be read")
        accelerometerActive = true
    }

    @ObjCMethod("startAccelerometerUpdatesToQueue:withHandler:")
    func startAccelerometerUpdates(to queue: NSObject?, handler: ObjCBlock?) {
        accelerometerHandler = handler
        Controllers.trace("motion: accelerometer updates start, to a handler every \(accelerometerInterval) s")
        guard !accelerometerActive else { return }
        accelerometerActive = true
        sendAccelerometerData()
    }

    @ObjCMethod("stopAccelerometerUpdates")
    func stopAccelerometerUpdates() {
        accelerometerActive = false
        accelerometerHandler = nil
    }

    private func sendAccelerometerData() {
        Motion.after(accelerometerInterval) { [self] in
            guard accelerometerActive, let handler = accelerometerHandler, let data = accelerometerData() else { return }
            Motion.call(handler, data)
            sendAccelerometerData()
        }
    }

    // MARK: Device motion

    @ObjCMethod("isDeviceMotionAvailable") func isDeviceMotionAvailable() -> Bool { true }
    @ObjCMethod("isDeviceMotionActive") func isDeviceMotionActive() -> Bool { deviceMotionActive }
    @ObjCMethod("deviceMotionUpdateInterval") func deviceMotionUpdateInterval() -> Double { deviceMotionInterval }
    @ObjCMethod("setDeviceMotionUpdateInterval:")
    func setDeviceMotionUpdateInterval(_ interval: Double) { deviceMotionInterval = max(interval, 0.01) }
    @ObjCMethod("showsDeviceMovementDisplay") func showsDeviceMovementDisplay() -> Bool { false }
    @ObjCMethod("setShowsDeviceMovementDisplay:") func setShowsDeviceMovementDisplay(_ shows: Bool) {}

    @ObjCMethod("deviceMotion")
    func deviceMotion() -> CMDeviceMotion? {
        guard deviceMotionActive else { return nil }
        let motion = CMDeviceMotion()
        motion.rotation = Tilt.attitude()
        motion.shake = Shake.acceleration()
        return motion
    }

    @ObjCMethod("startDeviceMotionUpdates")
    func startDeviceMotionUpdates() {
        Controllers.trace("motion: device motion updates start, to be read")
        deviceMotionActive = true
    }

    @ObjCMethod("startDeviceMotionUpdatesUsingReferenceFrame:")
    func startDeviceMotionUpdates(using frame: UInt) {
        referenceFrame = frame
        Controllers.trace("motion: device motion updates start, to be read")
        deviceMotionActive = true
    }

    @ObjCMethod("startDeviceMotionUpdatesToQueue:withHandler:")
    func startDeviceMotionUpdates(to queue: NSObject?, handler: ObjCBlock?) {
        deviceMotionHandler = handler
        Controllers.trace("motion: device motion updates start, to a handler every \(deviceMotionInterval) s")
        guard !deviceMotionActive else { return }
        deviceMotionActive = true
        sendDeviceMotion()
    }

    @ObjCMethod("startDeviceMotionUpdatesUsingReferenceFrame:toQueue:withHandler:")
    func startDeviceMotionUpdates(using frame: UInt, to queue: NSObject?, handler: ObjCBlock?) {
        referenceFrame = frame
        startDeviceMotionUpdates(to: queue, handler: handler)
    }

    @ObjCMethod("stopDeviceMotionUpdates")
    func stopDeviceMotionUpdates() {
        deviceMotionActive = false
        deviceMotionHandler = nil
    }

    private func sendDeviceMotion() {
        Motion.after(deviceMotionInterval) { [self] in
            guard deviceMotionActive, let handler = deviceMotionHandler, let motion = deviceMotion() else { return }
            Motion.call(handler, motion)
            sendDeviceMotion()
        }
    }

    // MARK: Gyroscope and magnetometer, which there are none of

    @ObjCMethod("isGyroAvailable") func isGyroAvailable() -> Bool { false }
    @ObjCMethod("isGyroActive") func isGyroActive() -> Bool { false }
    @ObjCMethod("gyroUpdateInterval") func gyroUpdateInterval() -> Double { gyroInterval }
    @ObjCMethod("setGyroUpdateInterval:") func setGyroUpdateInterval(_ interval: Double) { gyroInterval = interval }
    @ObjCMethod("gyroData") func gyroData() -> CMGyroData? { nil }
    @ObjCMethod("startGyroUpdates") func startGyroUpdates() {}
    @ObjCMethod("startGyroUpdatesToQueue:withHandler:") func startGyroUpdates(to queue: NSObject?, handler: ObjCBlock?) {}
    @ObjCMethod("stopGyroUpdates") func stopGyroUpdates() {}
    @ObjCMethod("isMagnetometerAvailable") func isMagnetometerAvailable() -> Bool { false }
    @ObjCMethod("isMagnetometerActive") func isMagnetometerActive() -> Bool { false }
    @ObjCMethod("magnetometerData") func magnetometerData() -> NSObject? { nil }
    @ObjCMethod("startMagnetometerUpdates") func startMagnetometerUpdates() {}
    @ObjCMethod("stopMagnetometerUpdates") func stopMagnetometerUpdates() {}
}

/// Updates sent to handlers, from the main queue.
enum Motion {
    final class Work {
        let body: () -> Void
        init(_ body: @escaping () -> Void) { self.body = body }
    }

    static func after(_ seconds: Double, _ body: @escaping () -> Void) {
        guard let after = Controllers.dispatchAfter, let time = Controllers.dispatchTime, let main = Controllers.mainQueue else { return }
        let context = Unmanaged.passRetained(Work(body)).toOpaque()
        after(time(0, Int64(seconds * 1e9)), main, context) { context in
            guard let context else { return }
            Unmanaged<Work>.fromOpaque(context).takeRetainedValue().body()
        }
    }

    /// Calls a handler with its data and no error.
    static func call(_ handler: ObjCBlock, _ data: NSObject) {
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
        handler.function(as: Invoke.self)(handler.object, data.objcObject, nil)
    }
}

import Glibc
import PerryObjCInterop

// UIAccelerometer, the shared accelerometer older apps read. There is no
// accelerometer, so its delegate hears of a device held still and upright
// in the interface's orientation, gravity along the side that is down: an
// app that hears nothing may take the device for lying flat or dropped
// (Call of Duty: Zombies pauses itself).

@ObjCClass("UIAccelerometer")
open class UIAccelerometer: NSObject {
    nonisolated(unsafe) static var shared: UIAccelerometer?
    /// Not retained, as Darwin's is weak.
    nonisolated(unsafe) static var delegate: UnsafeMutableRawPointer?
    nonisolated(unsafe) static var updateInterval: Double = 0.1
    nonisolated(unsafe) private static var scheduled = false
    /// The one acceleration the delegate is given, which answers with
    /// gravity and the time as it is read.
    nonisolated(unsafe) private static let acceleration = UIAcceleration.objCClass.object.newInstance()

    @ObjCClassMethod("sharedAccelerometer")
    static func sharedAccelerometer(_ cls: ObjCClass) -> UnsafeMutableRawPointer? {
        if shared == nil { shared = cls.object.allocated().initializeLayer().unsafeCast(to: UIAccelerometer.self) }
        return shared?.objcObject
    }

    @ObjCMethod("delegate") func delegate() -> UnsafeMutableRawPointer? { UIAccelerometer.delegate }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: UnsafeMutableRawPointer?) {
        UIAccelerometer.delegate = delegate
        UIAccelerometer.schedule()
    }
    @ObjCMethod("updateInterval") func updateInterval() -> Double { UIAccelerometer.updateInterval }
    @ObjCMethod("setUpdateInterval:") func setUpdateInterval(_ interval: Double) { UIAccelerometer.updateInterval = interval }

    /// Gravity for the interface's orientation, in g: down the device's
    /// bottom edge upright, its top upside down, and its left or right edge
    /// on its side (landscape right has the home button, and so the device's
    /// right edge, up).
    static var gravity: (x: Double, y: Double, z: Double) {
        switch Screen.orientation {
        case 2: return (0, 1, 0)
        case 3: return (-1, 0, 0)
        case 4: return (1, 0, 0)
        default: return (0, -1, 0)
        }
    }

    /// Tells the delegate of the acceleration each interval, on the main
    /// queue, while there is a delegate.
    private static func schedule() {
        guard !scheduled, delegate != nil, let after = Display.dispatchAfter, let time = Display.dispatchTime else { return }
        scheduled = true
        // No more often than a hundred times a second, as the device's.
        let interval = min(max(updateInterval, 0.01), 1)
        after(time(0, Int64(interval * 1_000_000_000)), Updates.mainQueue, nil) { _ in
            UIAccelerometer.scheduled = false
            guard let delegate = UIAccelerometer.delegate, let shared = UIAccelerometer.shared else { return }
            let selector = ObjCRuntime.selector("accelerometer:didAccelerate:")
            if NSObject(objcObject: delegate, ownership: .retain).responds(to: "accelerometer:didAccelerate:") {
                typealias Send = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeMutableRawPointer?,
                                                 UnsafeMutableRawPointer?) -> Void
                unsafeBitCast(ObjCRuntime.msgSend, to: Send.self)(delegate, selector, shared.objcObject,
                                                                  UIAccelerometer.acceleration.objcObject)
            }
            UIAccelerometer.schedule()
        }
    }
}

/// What the accelerometer's delegate is given: gravity, and when.
@ObjCClass("UIAcceleration")
open class UIAcceleration: NSObject {
    /// Seconds since the system started, as the device's are.
    @ObjCMethod("timestamp") func timestamp() -> Double {
        var time = timespec()
        clock_gettime(CLOCK_MONOTONIC, &time)
        return Double(time.tv_sec) + Double(time.tv_nsec) / 1_000_000_000
    }
    @ObjCMethod("x") func x() -> Double { UIAccelerometer.gravity.x }
    @ObjCMethod("y") func y() -> Double { UIAccelerometer.gravity.y }
    @ObjCMethod("z") func z() -> Double { UIAccelerometer.gravity.z }
}

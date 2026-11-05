import PerryObjCInterop

// UIAccelerometer, the shared accelerometer older apps read: there is no
// accelerometer, so it keeps its delegate and interval and sends nothing.

@ObjCClass("UIAccelerometer")
open class UIAccelerometer: NSObject {
    nonisolated(unsafe) static var shared: UIAccelerometer?
    /// Not retained, as Darwin's is weak.
    nonisolated(unsafe) static var delegate: UnsafeMutableRawPointer?
    nonisolated(unsafe) static var updateInterval: Double = 0.1

    @ObjCClassMethod("sharedAccelerometer")
    static func sharedAccelerometer(_ cls: ObjCClass) -> UnsafeMutableRawPointer? {
        if shared == nil { shared = cls.object.allocated().initializeLayer().unsafeCast(to: UIAccelerometer.self) }
        return shared?.objcObject
    }

    @ObjCMethod("delegate") func delegate() -> UnsafeMutableRawPointer? { UIAccelerometer.delegate }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: UnsafeMutableRawPointer?) { UIAccelerometer.delegate = delegate }
    @ObjCMethod("updateInterval") func updateInterval() -> Double { UIAccelerometer.updateInterval }
    @ObjCMethod("setUpdateInterval:") func setUpdateInterval(_ interval: Double) { UIAccelerometer.updateInterval = interval }
}

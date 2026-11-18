import PerryObjCInterop

// CLHeading: which way the device points. There is no compass here, so none
// is ever reported; the class is there for an app's subclasses and for code
// that asks a heading its values.

@ObjCClass("CLHeading")
open class CLHeading: NSObject {
    @ObjCMethod("init") public required override init() { super.init() }

    /// Negative: the heading is not valid.
    @ObjCMethod("magneticHeading") func magneticHeading() -> Double { -1 }
    @ObjCMethod("trueHeading") func trueHeading() -> Double { -1 }
    @ObjCMethod("headingAccuracy") func headingAccuracy() -> Double { -1 }
    @ObjCMethod("x") func x() -> Double { 0 }
    @ObjCMethod("y") func y() -> Double { 0 }
    @ObjCMethod("z") func z() -> Double { 0 }
    @ObjCMethod("timestamp") func timestamp() -> NSObject? { nil }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { ObjCRuntime.retain(objcObject) }
}

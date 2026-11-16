import CPerryMedia
import PerryObjCInterop

// NSValue's CoreMedia additions: a CMTime boxed under the type encoding
// Darwin gives it, as an AVPlayer's boundary times are passed.

@ObjCWrapper("NSValue")
class TimeValueObject: NSObject {
    @ObjCMethod("initWithBytes:objCType:") func initialize(bytes: UnsafeRawPointer?, objCType: UnsafePointer<CChar>?) -> NSObject
    @ObjCMethod("getValue:") func getValue(_ buffer: UnsafeMutableRawPointer?)
    /// +alloc, sent to the class.
    @ObjCMethod("alloc") func allocate() -> NSObject
}

@ObjCCategory("CoreMediaTimeValues")
extension TimeValueObject {
    @ObjCClassMethod("valueWithCMTime:")
    static func value(_ cls: ObjCClass, time: CMTime) -> NSObject {
        var copy = time
        return "{?=qiIq}".withCString { type in
            withUnsafeBytes(of: &copy) { bytes in
                TimeValueObject(cls.pointer).allocate().unsafeCast(to: TimeValueObject.self).initialize(bytes: bytes.baseAddress, objCType: type)
            }
        }
    }

    @ObjCMethod("CMTimeValue")
    func timeValue() -> CMTime {
        var time = CMTime(value: 0, timescale: 0, flags: 0, epoch: 0)
        withUnsafeMutableBytes(of: &time) { getValue($0.baseAddress) }
        return time
    }
}

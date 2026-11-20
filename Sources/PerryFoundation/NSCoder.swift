import CPerryGeometry
import PerryObjCInterop

/// NSCoder: the abstract coder that programs' own coders subclass
/// (Interface Builder's XML decoder does). A subclass supplies the
/// primitives, -encodeValueOfObjCType:at: and -decodeValueOfObjCType:at:;
/// the object methods here are made of them, and the rest answer as
/// NSCoder's do for a coder that isn't keyed.
@ObjCClass("NSCoder")
public class NSCoder: NSObject {
    private typealias Value = @convention(c) (id?, SEL, UnsafePointer<CChar>, UnsafeMutableRawPointer) -> Void

    private func value(_ selector: String, _ object: inout id?) {
        let send = unsafeBitCast(ObjC.msgSend, to: Value.self)
        withUnsafeMutablePointer(to: &object) { pointer in
            "@".withCString { send(objcObject, ObjC.selector(selector), $0, UnsafeMutableRawPointer(pointer)) }
        }
    }

    @ObjCMethod("allowsKeyedCoding") func allowsKeyedCoding() -> Bool { false }
    @ObjCMethod("requiresSecureCoding") func requiresSecureCoding() -> Bool { false }
    /// Darwin's coders report 1000.
    @ObjCMethod("systemVersion") func systemVersion() -> UInt32 { 1000 }
    @ObjCMethod("versionForClassName:") func version(forClassName name: String?) -> Int { 0 }
    @ObjCMethod("containsValueForKey:") func containsValue(forKey key: String?) -> Bool { false }
    @ObjCMethod("error") func coderError() -> UnsafeMutableRawPointer? { nil }

    /// The next object, as -decodeValueOfObjCType:at: gives it, autoreleased.
    @ObjCMethod("decodeObject")
    func decodeObject() -> UnsafeMutableRawPointer? {
        var object: id?
        value("decodeValueOfObjCType:at:", &object)
        return object.flatMap { ObjC.autorelease($0) }
    }

    @ObjCMethod("encodeObject:")
    func encode(object: UnsafeMutableRawPointer?) {
        var value: id? = object
        self.value("encodeValueOfObjCType:at:", &value)
    }
    // Keyed coding's derived values, made of the subclass's own keyed
    // primitives (Interface Builder's XML decoder has 64-bit integers and
    // objects): integers as 64-bit ones, geometry as strings of it.

    @ObjCMethod("decodeIntegerForKey:")
    func decodeInteger(forKey key: String?) -> Int {
        typealias F = @convention(c) (id?, SEL, id?) -> Int64
        return Int(unsafeBitCast(ObjC.msgSend, to: F.self)(objcObject, ObjC.selector("decodeInt64ForKey:"), Strings.autoreleased(key ?? "")))
    }
    @ObjCMethod("encodeInteger:forKey:")
    func encode(integer value: Int, forKey key: String?) {
        typealias F = @convention(c) (id?, SEL, Int64, id?) -> Void
        unsafeBitCast(ObjC.msgSend, to: F.self)(objcObject, ObjC.selector("encodeInt64:forKey:"), Int64(value), Strings.autoreleased(key ?? ""))
    }
    /// Rectangles, points and sizes, which this library's methods don't
    /// take, as C functions.
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        let rect: @convention(c) (id?, SEL, id?) -> CGRect = { coder, _, key in
            NSRectFromString(ObjC.send(coder, ObjC.selector("decodeObjectForKey:"), key))
        }
        let point: @convention(c) (id?, SEL, id?) -> CGPoint = { coder, _, key in
            NSPointFromString(ObjC.send(coder, ObjC.selector("decodeObjectForKey:"), key))
        }
        let size: @convention(c) (id?, SEL, id?) -> CGSize = { coder, _, key in
            NSSizeFromString(ObjC.send(coder, ObjC.selector("decodeObjectForKey:"), key))
        }
        let encodeRect: @convention(c) (id?, SEL, CGRect, id?) -> Void = { coder, _, value, key in
            _ = ObjC.send(coder, ObjC.selector("encodeObject:forKey:"), NSStringFromRect(value), key)
        }
        let encodePoint: @convention(c) (id?, SEL, CGPoint, id?) -> Void = { coder, _, value, key in
            _ = ObjC.send(coder, ObjC.selector("encodeObject:forKey:"), NSStringFromPoint(value), key)
        }
        let encodeSize: @convention(c) (id?, SEL, CGSize, id?) -> Void = { coder, _, value, key in
            _ = ObjC.send(coder, ObjC.selector("encodeObject:forKey:"), NSStringFromSize(value), key)
        }
        let rectType = "{CGRect={CGPoint=dd}{CGSize=dd}}", pointType = "{CGPoint=dd}", sizeType = "{CGSize=dd}"
        cls.addMethod("decodeRectForKey:", types: "\(rectType)24@0:8@16", implementation: unsafeBitCast(rect, to: UnsafeRawPointer.self),
                      isClassMethod: false)
        cls.addMethod("decodePointForKey:", types: "\(pointType)24@0:8@16", implementation: unsafeBitCast(point, to: UnsafeRawPointer.self),
                      isClassMethod: false)
        cls.addMethod("decodeSizeForKey:", types: "\(sizeType)24@0:8@16", implementation: unsafeBitCast(size, to: UnsafeRawPointer.self),
                      isClassMethod: false)
        cls.addMethod("encodeRect:forKey:", types: "v56@0:8\(rectType)16@48", implementation: unsafeBitCast(encodeRect, to: UnsafeRawPointer.self),
                      isClassMethod: false)
        cls.addMethod("encodePoint:forKey:", types: "v40@0:8\(pointType)16@32", implementation: unsafeBitCast(encodePoint, to: UnsafeRawPointer.self),
                      isClassMethod: false)
        cls.addMethod("encodeSize:forKey:", types: "v40@0:8\(sizeType)16@32", implementation: unsafeBitCast(encodeSize, to: UnsafeRawPointer.self),
                      isClassMethod: false)
    }

    @ObjCMethod("encodeRootObject:") func encodeRoot(object: UnsafeMutableRawPointer?) { encode(object: object) }
    @ObjCMethod("encodeBycopyObject:") func encodeBycopy(object: UnsafeMutableRawPointer?) { encode(object: object) }
    @ObjCMethod("encodeByrefObject:") func encodeByref(object: UnsafeMutableRawPointer?) { encode(object: object) }
    @ObjCMethod("encodeConditionalObject:") func encodeConditional(object: UnsafeMutableRawPointer?) { encode(object: object) }
}

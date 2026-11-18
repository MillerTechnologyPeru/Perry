import CPerryGeometry
import PerryObjCInterop

// NSValue's UIKit additions: CoreGraphics' geometry boxed under the type
// encodings Darwin gives them, as animations and layout code keep them.

@ObjCWrapper("NSValue")
class NSValueObject: NSObject {
    @ObjCMethod("initWithBytes:objCType:") func initialize(bytes: UnsafeRawPointer?, objCType: UnsafePointer<CChar>?) -> NSObject
    @ObjCMethod("getValue:") func getValue(_ buffer: UnsafeMutableRawPointer?)
}

/// The structures' type encodings: CGFloat is a double where pointers are
/// 64 bits wide and a float where they are 32.
private enum Encodings {
    #if _pointerBitWidth(_32)
    static let point = "{CGPoint=ff}"
    static let size = "{CGSize=ff}"
    static let rect = "{CGRect={CGPoint=ff}{CGSize=ff}}"
    static let transform = "{CGAffineTransform=ffffff}"
    static let insets = "{UIEdgeInsets=ffff}"
    static let vector = "{CGVector=ff}"
    #else
    static let point = "{CGPoint=dd}"
    static let size = "{CGSize=dd}"
    static let rect = "{CGRect={CGPoint=dd}{CGSize=dd}}"
    static let transform = "{CGAffineTransform=dddddd}"
    static let insets = "{UIEdgeInsets=dddd}"
    static let vector = "{CGVector=dd}"
    #endif
}

private func box<T>(_ cls: ObjCClass, _ value: T, _ encoding: String) -> NSObject {
    var copy = value
    return encoding.withCString { type in
        withUnsafeBytes(of: &copy) { bytes in
            cls.object.allocated().unsafeCast(to: NSValueObject.self).initialize(bytes: bytes.baseAddress, objCType: type)
        }
    }
}

private func unbox<T>(_ object: NSObject, _ empty: T) -> T {
    // Read into room for the largest of them, as a value boxed as another
    // structure fills as much as it holds.
    var value = empty
    let scratch = UnsafeMutableRawPointer.allocate(byteCount: 256, alignment: 16)
    defer { scratch.deallocate() }
    scratch.initializeMemory(as: UInt8.self, repeating: 0, count: 256)
    withUnsafeBytes(of: &value) { scratch.copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
    object.unsafeCast(to: NSValueObject.self).getValue(scratch)
    withUnsafeMutableBytes(of: &value) { $0.baseAddress!.copyMemory(from: scratch, byteCount: $0.count) }
    return value
}

@ObjCCategory("UIGeometryKeyedCoding")
extension NSValueObject {
    @ObjCClassMethod("valueWithCGPoint:")
    static func value(_ cls: ObjCClass, point: CGPoint) -> NSObject { box(cls, point, Encodings.point) }
    @ObjCClassMethod("valueWithCGSize:")
    static func value(_ cls: ObjCClass, size: CGSize) -> NSObject { box(cls, size, Encodings.size) }
    @ObjCClassMethod("valueWithCGRect:")
    static func value(_ cls: ObjCClass, rect: CGRect) -> NSObject { box(cls, rect, Encodings.rect) }
    @ObjCClassMethod("valueWithCGAffineTransform:")
    static func value(_ cls: ObjCClass, transform: CGAffineTransform) -> NSObject { box(cls, transform, Encodings.transform) }
    @ObjCClassMethod("valueWithUIEdgeInsets:")
    static func value(_ cls: ObjCClass, insets: UIEdgeInsets) -> NSObject { box(cls, insets, Encodings.insets) }
    // NSDirectionalEdgeInsets are four CGFloats, as UIEdgeInsets are
    // (leading is left): they travel as those.
    @ObjCClassMethod("valueWithDirectionalEdgeInsets:")
    static func value(_ cls: ObjCClass, directionalInsets: UIEdgeInsets) -> NSObject { box(cls, directionalInsets, Encodings.insets) }
    @ObjCMethod("directionalEdgeInsetsValue")
    func directionalInsetsValue() -> UIEdgeInsets { unbox(self, UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)) }

    // A CGVector is two CGFloats, as a CGPoint is: it travels as one. (The
    // macro does not see members under #if, so the 64-bit encodings are used on
    // 32-bit too, where the runtime does not read their offsets.)
    @ObjCClassMethod("valueWithCGVector:", types: "@32@0:8{CGVector=dd}16")
    static func value(_ cls: ObjCClass, vector: CGPoint) -> NSObject { box(cls, vector, Encodings.vector) }
    @ObjCMethod("CGVectorValue", types: "{CGVector=dd}16@0:8") func vectorValue() -> CGPoint { unbox(self, CGPoint(x: 0, y: 0)) }

    @ObjCMethod("CGPointValue") func pointValue() -> CGPoint { unbox(self, CGPoint(x: 0, y: 0)) }
    @ObjCMethod("CGSizeValue") func sizeValue() -> CGSize { unbox(self, CGSize(width: 0, height: 0)) }
    @ObjCMethod("CGRectValue") func rectValue() -> CGRect { unbox(self, CGRect(origin: CGPoint(x: 0, y: 0), size: CGSize(width: 0, height: 0))) }
    @ObjCMethod("CGAffineTransformValue")
    func transformValue() -> CGAffineTransform { unbox(self, CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)) }
    @ObjCMethod("UIEdgeInsetsValue") func insetsValue() -> UIEdgeInsets { unbox(self, UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)) }
}

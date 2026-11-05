import CPerryGeometry
import PerryObjCInterop

// NSValue's UIKit additions: CoreGraphics' geometry boxed under the type
// encodings Darwin gives them, as animations and layout code keep them.

@ObjCWrapper("NSValue")
class NSValueObject: NSObject {
    @ObjCMethod("initWithBytes:objCType:") func initialize(bytes: UnsafeRawPointer?, objCType: UnsafePointer<CChar>?) -> NSObject
    @ObjCMethod("getValue:") func getValue(_ buffer: UnsafeMutableRawPointer?)
}

private enum Encodings {
    static let point = "{CGPoint=dd}"
    static let size = "{CGSize=dd}"
    static let rect = "{CGRect={CGPoint=dd}{CGSize=dd}}"
    static let transform = "{CGAffineTransform=dddddd}"
    static let insets = "{UIEdgeInsets=dddd}"
    static let vector = "{CGVector=dd}"
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
    var value = empty
    withUnsafeMutableBytes(of: &value) { object.unsafeCast(to: NSValueObject.self).getValue($0.baseAddress) }
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

    @ObjCMethod("CGPointValue") func pointValue() -> CGPoint { unbox(self, CGPoint(x: 0, y: 0)) }
    @ObjCMethod("CGSizeValue") func sizeValue() -> CGSize { unbox(self, CGSize(width: 0, height: 0)) }
    @ObjCMethod("CGRectValue") func rectValue() -> CGRect { unbox(self, CGRect(origin: CGPoint(x: 0, y: 0), size: CGSize(width: 0, height: 0))) }
    @ObjCMethod("CGAffineTransformValue")
    func transformValue() -> CGAffineTransform { unbox(self, CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)) }
    @ObjCMethod("UIEdgeInsetsValue") func insetsValue() -> UIEdgeInsets { unbox(self, UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)) }
}

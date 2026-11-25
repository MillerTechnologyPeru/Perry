import CPerryGeometry
import Glibc
import PerryObjCInterop

// NSAffineTransform, Mac OS X's transform object: a matrix that moves,
// turns and scales points, with methods to change it in place. Apps make one
// to flip or place what they draw, and AppKit's category concatenates it
// with the current context (-concat). Its NSAffineTransformStruct (m11 m12
// m21 m22 tX tY) is laid out as a CGAffineTransform (a b c d tx ty), which
// keeps it here. armv7, which runs only iOS apps, leaves it out.

#if !arch(arm)

extension CGAffineTransform: ObjCScalar {
    #if arch(i386) || arch(powerpc)
    public static var objCTypeEncoding: String { "{_NSAffineTransformStruct=ffffff}" }
    /// Six words, which i386 and ppc return through memory.
    public static var objCReturnsIndirectly: Bool { true }
    #else
    public static var objCTypeEncoding: String { "{_NSAffineTransformStruct=dddddd}" }
    #endif
}

/// A transform's matrix.
final class AffineTransformStorage {
    var matrix: CGAffineTransform

    init(_ matrix: CGAffineTransform) { self.matrix = matrix }
}

enum AffineTransforms {
    nonisolated(unsafe) static var transformClass: Class!

    static let identity = CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    /// The object's matrix; the identity until one is set, as -init leaves it.
    static func matrix(_ object: id?) -> CGAffineTransform {
        Storage.get(object, as: AffineTransformStorage.self)?.matrix ?? identity
    }

    static func set(_ object: id?, _ matrix: CGAffineTransform) {
        guard let object else { return }
        if let storage = Storage.get(object, as: AffineTransformStorage.self) {
            storage.matrix = matrix
        } else {
            Storage.set(object, AffineTransformStorage(matrix))
        }
    }

    static func autoreleased(_ matrix: CGAffineTransform, cls: UnsafeMutableRawPointer? = nil) -> id? {
        guard let object = Storage.allocate(cls ?? UnsafeMutableRawPointer(transformClass)) else { return nil }
        Storage.set(object, AffineTransformStorage(matrix))
        return ObjC.autorelease(object)
    }

    /// `first` then `second`: points go through `first`, then `second`.
    static func concatenating(_ first: CGAffineTransform, _ second: CGAffineTransform) -> CGAffineTransform {
        CGAffineTransform(a: first.a * second.a + first.b * second.c, b: first.a * second.b + first.b * second.d,
                          c: first.c * second.a + first.d * second.c, d: first.c * second.b + first.d * second.d,
                          tx: first.tx * second.a + first.ty * second.c + second.tx,
                          ty: first.tx * second.b + first.ty * second.d + second.ty)
    }

    static func apply(_ t: CGAffineTransform, _ point: CGPoint) -> CGPoint {
        CGPoint(x: t.a * point.x + t.c * point.y + t.tx, y: t.b * point.x + t.d * point.y + t.ty)
    }
}

/// NSAffineTransform.
@ObjCClass("NSAffineTransform")
public final class NSAffineTransform: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        AffineTransforms.transformClass = cls.storage
    }

    var matrix: CGAffineTransform {
        get { AffineTransforms.matrix(objcObject) }
        set { AffineTransforms.set(objcObject, newValue) }
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: AffineTransforms.transformClass)
    }

    /// An identity transform.
    @ObjCClassMethod("transform")
    static func transform(_ cls: ObjCClass) -> UnsafeMutableRawPointer? {
        AffineTransforms.autoreleased(AffineTransforms.identity, cls: cls.pointer)
    }

    @ObjCMethod("init")
    func initialize() -> UnsafeMutableRawPointer? {
        matrix = AffineTransforms.identity
        return objcObject
    }

    @ObjCMethod("initWithTransform:")
    func initialize(transform: ObjCObject?) -> UnsafeMutableRawPointer? {
        matrix = AffineTransforms.matrix(transform?.id)
        return objcObject
    }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        guard let cls = ObjC.objectGetClass(objcObject), let object = Storage.allocate(UnsafeMutableRawPointer(cls)) else { return nil }
        Storage.set(object, AffineTransformStorage(matrix))
        return object
    }

    // MARK: Changing it
    // Each change applies before what the transform did: translating then
    // drawing places what is drawn after the transform's other changes.

    @ObjCMethod("translateXBy:yBy:")
    func translate(x: GeometryValue, y: GeometryValue) {
        let step = CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: x, ty: y)
        matrix = AffineTransforms.concatenating(step, matrix)
    }

    @ObjCMethod("rotateByRadians:")
    func rotate(radians: GeometryValue) {
        let (cosine, sine) = (GeometryValue(cos(Double(radians))), GeometryValue(sin(Double(radians))))
        let step = CGAffineTransform(a: cosine, b: sine, c: -sine, d: cosine, tx: 0, ty: 0)
        matrix = AffineTransforms.concatenating(step, matrix)
    }

    @ObjCMethod("rotateByDegrees:")
    func rotate(degrees: GeometryValue) { rotate(radians: degrees * .pi / 180) }

    @ObjCMethod("scaleBy:")
    func scale(by factor: GeometryValue) { scale(x: factor, y: factor) }

    @ObjCMethod("scaleXBy:yBy:")
    func scale(x: GeometryValue, y: GeometryValue) {
        let step = CGAffineTransform(a: x, b: 0, c: 0, d: y, tx: 0, ty: 0)
        matrix = AffineTransforms.concatenating(step, matrix)
    }

    /// The inverse; a transform that can't be inverted stays as it is.
    @ObjCMethod("invert")
    func invert() {
        let t = matrix
        let determinant = t.a * t.d - t.b * t.c
        guard determinant != 0 else { return }
        matrix = CGAffineTransform(a: t.d / determinant, b: -t.b / determinant, c: -t.c / determinant, d: t.a / determinant,
                                   tx: (t.c * t.ty - t.d * t.tx) / determinant, ty: (t.b * t.tx - t.a * t.ty) / determinant)
    }

    /// This transform, then the other.
    @ObjCMethod("appendTransform:")
    func append(_ other: ObjCObject?) { matrix = AffineTransforms.concatenating(matrix, AffineTransforms.matrix(other?.id)) }

    /// The other transform, then this one.
    @ObjCMethod("prependTransform:")
    func prepend(_ other: ObjCObject?) { matrix = AffineTransforms.concatenating(AffineTransforms.matrix(other?.id), matrix) }

    // MARK: Using it

    @ObjCMethod("transformPoint:")
    func transform(point: CGPoint) -> CGPoint { AffineTransforms.apply(matrix, point) }

    /// A size moves without the translation.
    @ObjCMethod("transformSize:")
    func transform(size: CGSize) -> CGSize {
        let t = matrix
        return CGSize(width: t.a * size.width + t.c * size.height, height: t.b * size.width + t.d * size.height)
    }

    @ObjCMethod("transformStruct") func transformStruct() -> CGAffineTransform { matrix }
    @ObjCMethod("setTransformStruct:") func setTransformStruct(_ value: CGAffineTransform) { matrix = value }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: ObjCObject?) -> Bool {
        guard let other = other?.id, ObjC.isKind(other, of: AffineTransforms.transformClass) else { return false }
        let (a, b) = (matrix, AffineTransforms.matrix(other))
        return a.a == b.a && a.b == b.b && a.c == b.c && a.d == b.d && a.tx == b.tx && a.ty == b.ty
    }

    @ObjCMethod("description")
    func describe() -> String {
        let t = matrix
        return "transformStruct.m11: \(t.a), transformStruct.m12: \(t.b), transformStruct.m21: \(t.c), "
            + "transformStruct.m22: \(t.d), transformStruct.tX: \(t.tx), transformStruct.tY: \(t.ty)"
    }
}

#endif

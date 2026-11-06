import CPerryGeometry
import Glibc
import PerryObjCInterop

// CoreGraphics' geometry as Objective-C values, and Core Animation's
// CATransform3D with the functions apps build transforms with. Layers
// are drawn in two dimensions: a transform's affine part places them, and
// its depth and perspective are kept but not drawn.

extension CGPoint: ObjCStructure {
    #if _pointerBitWidth(_32)
    public typealias ObjCType = ObjCWords2
    public static var objCTypeEncoding: String { "{CGPoint=ff}" }
    #else
    public typealias ObjCType = CGPoint
    public static var objCTypeEncoding: String { "{CGPoint=dd}" }
    #endif
    static let zero = CGPoint(x: 0, y: 0)
}

extension CGSize: ObjCStructure {
    #if _pointerBitWidth(_32)
    public typealias ObjCType = ObjCWords2
    public static var objCTypeEncoding: String { "{CGSize=ff}" }
    #else
    public typealias ObjCType = CGSize
    public static var objCTypeEncoding: String { "{CGSize=dd}" }
    #endif
    static let zero = CGSize(width: 0, height: 0)
}

extension CGRect: ObjCStructure {
    #if _pointerBitWidth(_32)
    public typealias ObjCType = ObjCWords4
    public static var objCTypeEncoding: String { "{CGRect={CGPoint=ff}{CGSize=ff}}" }
    #else
    public typealias ObjCType = CGRect
    public static var objCTypeEncoding: String { "{CGRect={CGPoint=dd}{CGSize=dd}}" }
    #endif
    static let zero = CGRect(origin: .zero, size: .zero)

    init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.init(origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height))
    }
}

extension CGAffineTransform: ObjCStructure {
    #if _pointerBitWidth(_32)
    public typealias ObjCType = ObjCWords6
    public static var objCTypeEncoding: String { "{CGAffineTransform=ffffff}" }
    #else
    public typealias ObjCType = CGAffineTransform
    public static var objCTypeEncoding: String { "{CGAffineTransform=dddddd}" }
    #endif
    static let identity = CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    var isIdentity: Bool { a == 1 && b == 0 && c == 0 && d == 1 && tx == 0 && ty == 0 }

    func apply(_ point: CGPoint) -> CGPoint {
        CGPoint(x: a * point.x + c * point.y + tx, y: b * point.x + d * point.y + ty)
    }

    /// `self` then `other`.
    func concatenating(_ other: CGAffineTransform) -> CGAffineTransform {
        CGAffineTransform(a: a * other.a + b * other.c, b: a * other.b + b * other.d,
                          c: c * other.a + d * other.c, d: c * other.b + d * other.d,
                          tx: tx * other.a + ty * other.c + other.tx, ty: tx * other.b + ty * other.d + other.ty)
    }

    var inverted: CGAffineTransform {
        let determinant = a * d - b * c
        guard determinant != 0 else { return self }
        return CGAffineTransform(a: d / determinant, b: -b / determinant, c: -c / determinant, d: a / determinant,
                                 tx: (c * ty - d * tx) / determinant, ty: (b * tx - a * ty) / determinant)
    }

    /// The bounding box of `rect` transformed.
    func apply(_ rect: CGRect) -> CGRect {
        let corners = [CGPoint(x: rect.origin.x, y: rect.origin.y),
                       CGPoint(x: rect.origin.x + rect.size.width, y: rect.origin.y),
                       CGPoint(x: rect.origin.x, y: rect.origin.y + rect.size.height),
                       CGPoint(x: rect.origin.x + rect.size.width, y: rect.origin.y + rect.size.height)].map(apply)
        let xs = corners.map(\.x), ys = corners.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    /// Whether it keeps rectangles' sides horizontal and vertical.
    var isAxisAligned: Bool { (b == 0 && c == 0) || (a == 0 && d == 0) }
}

extension CGRect {
    var minX: CGFloat { origin.x }
    var minY: CGFloat { origin.y }
    var maxX: CGFloat { origin.x + size.width }
    var maxY: CGFloat { origin.y + size.height }
    var midX: CGFloat { origin.x + size.width / 2 }
    var midY: CGFloat { origin.y + size.height / 2 }
    var width: CGFloat { size.width }
    var height: CGFloat { size.height }

    func contains(_ point: CGPoint) -> Bool {
        point.x >= minX && point.x < maxX && point.y >= minY && point.y < maxY
    }

    func intersection(_ other: CGRect) -> CGRect {
        let x = max(minX, other.minX), y = max(minY, other.minY)
        return CGRect(x: x, y: y, width: max(min(maxX, other.maxX) - x, 0), height: max(min(maxY, other.maxY) - y, 0))
    }
}

extension CGPoint: Equatable {
    public static func == (a: CGPoint, b: CGPoint) -> Bool { a.x == b.x && a.y == b.y }
}

extension CGSize: Equatable {
    public static func == (a: CGSize, b: CGSize) -> Bool { a.width == b.width && a.height == b.height }
}

extension CGRect: Equatable {
    public static func == (a: CGRect, b: CGRect) -> Bool { a.origin == b.origin && a.size == b.size }
}

// MARK: - CAFrameRateRange

extension CAFrameRateRange: ObjCStructure {
    #if _pointerBitWidth(_32)
    public typealias ObjCType = ObjCWords3
    public static var objCTypeEncoding: String { "{CAFrameRateRange=fff}" }
    #else
    public typealias ObjCType = CAFrameRateRange
    public static var objCTypeEncoding: String { "{CAFrameRateRange=fff}" }
    #endif
}

// MARK: - CATransform3D

extension CATransform3D: ObjCStructure {
    #if _pointerBitWidth(_32)
    public typealias ObjCType = ObjCWords16
    public static var objCTypeEncoding: String { "{CATransform3D=ffffffffffffffff}" }
    #else
    public typealias ObjCType = CATransform3D
    public static var objCTypeEncoding: String { "{CATransform3D=dddddddddddddddd}" }
    #endif

    static let identity = CATransform3D(m11: 1, m12: 0, m13: 0, m14: 0, m21: 0, m22: 1, m23: 0, m24: 0,
                                        m31: 0, m32: 0, m33: 1, m34: 0, m41: 0, m42: 0, m43: 0, m44: 1)

    init(_ affine: CGAffineTransform) {
        self.init(m11: affine.a, m12: affine.b, m13: 0, m14: 0, m21: affine.c, m22: affine.d, m23: 0, m24: 0,
                  m31: 0, m32: 0, m33: 1, m34: 0, m41: affine.tx, m42: affine.ty, m43: 0, m44: 1)
    }

    /// The part that acts on the plane.
    var affine: CGAffineTransform { CGAffineTransform(a: m11, b: m12, c: m21, d: m22, tx: m41, ty: m42) }

    var isAffine: Bool {
        m13 == 0 && m14 == 0 && m23 == 0 && m24 == 0 && m31 == 0 && m32 == 0 && m33 == 1 && m34 == 0 && m43 == 0 && m44 == 1
    }

    var rows: [Double] { [Double(m11), Double(m12), Double(m13), Double(m14), Double(m21), Double(m22), Double(m23), Double(m24), Double(m31), Double(m32), Double(m33), Double(m34), Double(m41), Double(m42), Double(m43), Double(m44)] }

    init(rows: [Double]) {
        let m = rows.map { CGFloat($0) }
        self.init(m11: m[0], m12: m[1], m13: m[2], m14: m[3], m21: m[4], m22: m[5], m23: m[6], m24: m[7],
                  m31: m[8], m32: m[9], m33: m[10], m34: m[11], m41: m[12], m42: m[13], m43: m[14], m44: m[15])
    }

    /// `self` then `other`, as CATransform3DConcat(self, other).
    func concatenating(_ other: CATransform3D) -> CATransform3D {
        let a = rows, b = other.rows
        var result = [Double](repeating: 0, count: 16)
        for row in 0..<4 {
            for column in 0..<4 {
                result[row * 4 + column] = (0..<4).reduce(0) { $0 + a[row * 4 + $1] * b[$1 * 4 + column] }
            }
        }
        return CATransform3D(rows: result)
    }

    static func translation(_ x: Double, _ y: Double, _ z: Double) -> CATransform3D {
        var transform = identity
        (transform.m41, transform.m42, transform.m43) = (CGFloat(x), CGFloat(y), CGFloat(z))
        return transform
    }

    static func scale(_ x: Double, _ y: Double, _ z: Double) -> CATransform3D {
        var transform = identity
        (transform.m11, transform.m22, transform.m33) = (CGFloat(x), CGFloat(y), CGFloat(z))
        return transform
    }

    /// A rotation by `angle` radians about the axis (x, y, z).
    static func rotation(_ angle: Double, _ x: Double, _ y: Double, _ z: Double) -> CATransform3D {
        let length = (x * x + y * y + z * z).squareRoot()
        guard length > 0 else { return identity }
        let (x, y, z) = (x / length, y / length, z / length)
        let c = cos(angle), s = sin(angle), t = 1 - c
        return CATransform3D(rows: [t * x * x + c, t * x * y + z * s, t * x * z - y * s, 0,
                                    t * x * y - z * s, t * y * y + c, t * y * z + x * s, 0,
                                    t * x * z + y * s, t * y * z - x * s, t * z * z + c, 0,
                                    0, 0, 0, 1])
    }

    /// The inverse, by Gauss-Jordan elimination; the transform itself when
    /// it has none.
    var inverted: CATransform3D {
        var a = rows, inverse = CATransform3D.identity.rows
        for column in 0..<4 {
            guard let pivot = (column..<4).max(by: { abs(a[$0 * 4 + column]) < abs(a[$1 * 4 + column]) }),
                  abs(a[pivot * 4 + column]) > 1e-12 else { return self }
            for k in 0..<4 {
                a.swapAt(column * 4 + k, pivot * 4 + k)
                inverse.swapAt(column * 4 + k, pivot * 4 + k)
            }
            let divisor = a[column * 4 + column]
            for k in 0..<4 {
                a[column * 4 + k] /= divisor
                inverse[column * 4 + k] /= divisor
            }
            for row in 0..<4 where row != column {
                let factor = a[row * 4 + column]
                for k in 0..<4 {
                    a[row * 4 + k] -= factor * a[column * 4 + k]
                    inverse[row * 4 + k] -= factor * inverse[column * 4 + k]
                }
            }
        }
        return CATransform3D(rows: inverse)
    }
}

@DarwinC("_CATransform3DIsIdentity")
public func CATransform3DIsIdentity(_ t: CATransform3D) -> Bool { t.rows == CATransform3D.identity.rows }
@DarwinC("_CATransform3DEqualToTransform")
public func CATransform3DEqualToTransform(_ a: CATransform3D, _ b: CATransform3D) -> Bool { a.rows == b.rows }
@DarwinC("_CATransform3DMakeTranslation")
public func CATransform3DMakeTranslation(_ x: Double, _ y: Double, _ z: Double) -> CATransform3D { .translation(x, y, z) }
@DarwinC("_CATransform3DMakeScale")
public func CATransform3DMakeScale(_ x: Double, _ y: Double, _ z: Double) -> CATransform3D { .scale(x, y, z) }
@DarwinC("_CATransform3DMakeRotation")
public func CATransform3DMakeRotation(_ angle: Double, _ x: Double, _ y: Double, _ z: Double) -> CATransform3D {
    .rotation(angle, x, y, z)
}
@DarwinC("_CATransform3DTranslate")
public func CATransform3DTranslate(_ t: CATransform3D, _ x: Double, _ y: Double, _ z: Double) -> CATransform3D {
    CATransform3D.translation(x, y, z).concatenating(t)
}
@DarwinC("_CATransform3DScale")
public func CATransform3DScale(_ t: CATransform3D, _ x: Double, _ y: Double, _ z: Double) -> CATransform3D {
    CATransform3D.scale(x, y, z).concatenating(t)
}
@DarwinC("_CATransform3DRotate")
public func CATransform3DRotate(_ t: CATransform3D, _ angle: Double, _ x: Double, _ y: Double, _ z: Double) -> CATransform3D {
    CATransform3D.rotation(angle, x, y, z).concatenating(t)
}
@DarwinC("_CATransform3DConcat")
public func CATransform3DConcat(_ a: CATransform3D, _ b: CATransform3D) -> CATransform3D { a.concatenating(b) }
@DarwinC("_CATransform3DInvert")
public func CATransform3DInvert(_ t: CATransform3D) -> CATransform3D { t.inverted }
@DarwinC("_CATransform3DMakeAffineTransform")
public func CATransform3DMakeAffineTransform(_ affine: CGAffineTransform) -> CATransform3D { CATransform3D(affine) }
@DarwinC("_CATransform3DIsAffine")
public func CATransform3DIsAffine(_ t: CATransform3D) -> Bool { t.isAffine }
@DarwinC("_CATransform3DGetAffineTransform")
public func CATransform3DGetAffineTransform(_ t: CATransform3D) -> CGAffineTransform { t.affine }

/// Seconds on the clock animations are timed by.
@DarwinC("_CACurrentMediaTime")
public func CACurrentMediaTime() -> Double { Clock.now }

// MARK: - NSValue

/// NSValue's QuartzCore additions: a 3D transform boxed under its type
/// encoding, as animations and layer code keep one.
@ObjCCategory("CATransform3DAdditions")
extension NSValue {
    @ObjCClassMethod("valueWithCATransform3D:")
    static func value(transform: CATransform3D) -> NSValue { NSValue.boxing(transform) }

    /// The transform, or the identity when the value holds another type.
    @ObjCMethod("CATransform3DValue")
    func transform3DValue() -> CATransform3D { unboxed(CATransform3D.self) ?? CATransform3D.identity }
}

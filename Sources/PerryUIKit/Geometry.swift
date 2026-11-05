import CPerryGeometry
import Glibc
import PerryObjCInterop

/// CoreGraphics' scalar: double on 64-bit Darwin.
public typealias CGFloat = Double

// CoreGraphics' geometry as Objective-C values, and UIKit's string forms.

extension CGPoint: ObjCScalar {
    public static var objCTypeEncoding: String { "{CGPoint=dd}" }
    static let zero = CGPoint(x: 0, y: 0)
}

extension CGSize: ObjCScalar {
    public static var objCTypeEncoding: String { "{CGSize=dd}" }
    static let zero = CGSize(width: 0, height: 0)
}

extension CGRect: ObjCScalar {
    public static var objCTypeEncoding: String { "{CGRect={CGPoint=dd}{CGSize=dd}}" }
    static let zero = CGRect(origin: .zero, size: .zero)

    init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.init(origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height))
    }
}

extension CGAffineTransform: ObjCScalar {
    public static var objCTypeEncoding: String { "{CGAffineTransform=dddddd}" }
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
}

extension PerryRange: ObjCScalar {
    public static var objCTypeEncoding: String { "{_NSRange=QQ}" }
}

extension UIEdgeInsets: ObjCScalar {
    public static var objCTypeEncoding: String { "{UIEdgeInsets=dddd}" }
    static let zero = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
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

    func intersects(_ other: CGRect) -> Bool {
        minX < other.maxX && other.minX < maxX && minY < other.maxY && other.minY < maxY
    }

    func offsetBy(x: CGFloat) -> CGRect { CGRect(x: minX + x, y: minY, width: width, height: height) }

    func inset(by insets: UIEdgeInsets) -> CGRect {
        CGRect(x: minX + insets.left, y: minY + insets.top, width: width - insets.left - insets.right,
               height: height - insets.top - insets.bottom)
    }
}

extension CGPoint: Equatable {
    public static func == (a: CGPoint, b: CGPoint) -> Bool { a.x == b.x && a.y == b.y }
}

extension CGSize: Equatable {
    public static func == (a: CGSize, b: CGSize) -> Bool { a.width == b.width && a.height == b.height }
}

extension UIEdgeInsets: Equatable {
    public static func == (a: UIEdgeInsets, b: UIEdgeInsets) -> Bool {
        a.top == b.top && a.left == b.left && a.bottom == b.bottom && a.right == b.right
    }
}

extension CGRect: Equatable {
    public static func == (a: CGRect, b: CGRect) -> Bool { a.origin == b.origin && a.size == b.size }
}

/// A coordinate as UIKit prints it: `%.17g`.
private func format(_ value: CGFloat) -> String {
    var buffer = [CChar](repeating: 0, count: 32)
    _ = withVaList([value]) { vsnprintf(&buffer, buffer.count, "%.17g", $0) }
    return String(cString: buffer)
}

func describe(_ point: CGPoint) -> String { "{\(format(point.x)), \(format(point.y))}" }
func describe(_ size: CGSize) -> String { "{\(format(size.width)), \(format(size.height))}" }
func describe(_ rect: CGRect) -> String { "{\(describe(rect.origin)), \(describe(rect.size))}" }

/// "{top, left, bottom, right}"
@c(_NSStringFromUIEdgeInsets)
public func NSStringFromUIEdgeInsets(_ insets: UIEdgeInsets) -> UnsafeMutableRawPointer? {
    "{\(format(insets.top)), \(format(insets.left)), \(format(insets.bottom)), \(format(insets.right))}".objCReturnValue()
}

/// "{x, y}"
@c(_NSStringFromCGPoint)
public func NSStringFromCGPoint(_ point: CGPoint) -> UnsafeMutableRawPointer? { describe(point).objCReturnValue() }

/// "{width, height}"
@c(_NSStringFromCGSize)
public func NSStringFromCGSize(_ size: CGSize) -> UnsafeMutableRawPointer? { describe(size).objCReturnValue() }

/// "{{x, y}, {width, height}}"
@c(_NSStringFromCGRect)
public func NSStringFromCGRect(_ rect: CGRect) -> UnsafeMutableRawPointer? { describe(rect).objCReturnValue() }

/// The numbers in a string, in order, as UIKit's *FromString functions read
/// "{x, y}" and "{{x, y}, {w, h}}"; missing ones are 0.
func numbers(_ string: UnsafeMutableRawPointer?, count: Int) -> [CGFloat] {
    guard let string else { return Array(repeating: 0, count: count) }
    let text = String(objCArgument: string)
    var values: [CGFloat] = []
    var current = ""
    for character in text + "," {
        if character.isNumber || "+-.eE".contains(character) {
            current.append(character)
        } else if !current.isEmpty {
            values.append(CGFloat(strtod(current, nil)))
            current = ""
        }
    }
    return (values + Array(repeating: 0, count: count)).prefix(count).map { $0 }
}

@c(_CGPointFromString)
public func CGPointFromString(_ string: UnsafeMutableRawPointer?) -> CGPoint {
    let n = numbers(string, count: 2)
    return CGPoint(x: n[0], y: n[1])
}

@c(_CGSizeFromString)
public func CGSizeFromString(_ string: UnsafeMutableRawPointer?) -> CGSize {
    let n = numbers(string, count: 2)
    return CGSize(width: n[0], height: n[1])
}

@c(_CGRectFromString)
public func CGRectFromString(_ string: UnsafeMutableRawPointer?) -> CGRect {
    let n = numbers(string, count: 4)
    return CGRect(origin: CGPoint(x: n[0], y: n[1]), size: CGSize(width: n[2], height: n[3]))
}

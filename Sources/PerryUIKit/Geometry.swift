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

/// A coordinate as UIKit prints it: `%.17g`.
private func format(_ value: CGFloat) -> String {
    var buffer = [CChar](repeating: 0, count: 32)
    _ = withVaList([value]) { vsnprintf(&buffer, buffer.count, "%.17g", $0) }
    return String(cString: buffer)
}

func describe(_ point: CGPoint) -> String { "{\(format(point.x)), \(format(point.y))}" }
func describe(_ size: CGSize) -> String { "{\(format(size.width)), \(format(size.height))}" }
func describe(_ rect: CGRect) -> String { "{\(describe(rect.origin)), \(describe(rect.size))}" }

/// "{x, y}"
@c(_NSStringFromCGPoint)
public func NSStringFromCGPoint(_ point: CGPoint) -> UnsafeMutableRawPointer? { describe(point).objCReturnValue() }

/// "{width, height}"
@c(_NSStringFromCGSize)
public func NSStringFromCGSize(_ size: CGSize) -> UnsafeMutableRawPointer? { describe(size).objCReturnValue() }

/// "{{x, y}, {width, height}}"
@c(_NSStringFromCGRect)
public func NSStringFromCGRect(_ rect: CGRect) -> UnsafeMutableRawPointer? { describe(rect).objCReturnValue() }

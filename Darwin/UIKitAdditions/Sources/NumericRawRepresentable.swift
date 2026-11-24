// UIKit's numeric raw-value types (layout priorities, window levels, font
// weights and widths) compare, add and subtract as their raw values do,
// through _UIKitNumericRawRepresentable; accessibility traits are an
// option set. Programs inline the operators, and look up the conformances
// by their descriptors, which must be UIKit's.

@available(swift 4)
@available(iOS 7.0, *)
public protocol _UIKitNumericRawRepresentable: Comparable, RawRepresentable where RawValue: Comparable, RawValue: Numeric {}

@available(swift 4)
@available(iOS 7.0, *)
extension _UIKitNumericRawRepresentable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public static func + (lhs: Self, rhs: RawValue) -> Self {
        Self(rawValue: lhs.rawValue + rhs)!
    }

    public static func + (lhs: RawValue, rhs: Self) -> Self {
        Self(rawValue: lhs + rhs.rawValue)!
    }

    public static func - (lhs: Self, rhs: RawValue) -> Self {
        Self(rawValue: lhs.rawValue - rhs)!
    }

    public static func - (lhs: Self, rhs: Self) -> RawValue {
        lhs.rawValue - rhs.rawValue
    }

    public static func += (lhs: inout Self, rhs: RawValue) {
        lhs = Self(rawValue: lhs.rawValue + rhs)!
    }

    public static func -= (lhs: inout Self, rhs: RawValue) {
        lhs = Self(rawValue: lhs.rawValue - rhs)!
    }
}

@available(iOS 11.0, *)
extension UIFont.Weight: _UIKitNumericRawRepresentable {}

@available(iOS 11.0, *)
extension UIFont.Width: _UIKitNumericRawRepresentable {}

@available(iOS 7.0, *)
extension UILayoutPriority: _UIKitNumericRawRepresentable {}

@available(iOS 7.0, *)
extension UIWindow.Level: _UIKitNumericRawRepresentable {}

@available(iOS 7.0, *)
extension UIAccessibilityTraits: OptionSet {
    @available(iOS 7.0, *)
    public typealias ArrayLiteralElement = UIAccessibilityTraits
    @available(iOS 7.0, *)
    public typealias Element = UIAccessibilityTraits
}

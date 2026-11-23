import Foundation

// Arithmetic and ordering on AppKit's numeric wrappers: priorities, levels,
// versions, font weights and widths.

@available(swift 4)
@available(macOS 10.13, *)
public protocol _AppKitKitNumericRawRepresentable: Comparable, RawRepresentable
    where RawValue: Comparable & Numeric {}

@available(swift 4)
@available(macOS 10.13, *)
extension _AppKitKitNumericRawRepresentable {
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
        lhs = lhs + rhs
    }

    public static func -= (lhs: inout Self, rhs: RawValue) {
        lhs = lhs - rhs
    }
}

@available(swift 4) @available(macOS 10.13, *)
extension NSAppKitVersion: _AppKitKitNumericRawRepresentable {}

@available(swift 4) @available(macOS 10.13, *)
extension NSLayoutConstraint.Priority: _AppKitKitNumericRawRepresentable {}

@available(swift 4) @available(macOS 10.13, *)
extension NSStackView.VisibilityPriority: _AppKitKitNumericRawRepresentable {}

@available(swift 4) @available(macOS 10.13, *)
extension NSToolbarItem.VisibilityPriority: _AppKitKitNumericRawRepresentable {}

@available(swift 4) @available(macOS 10.13, *)
extension NSTouchBarItem.Priority: _AppKitKitNumericRawRepresentable {}

@available(swift 4) @available(macOS 10.13, *)
extension NSWindow.Level: _AppKitKitNumericRawRepresentable {}

@available(swift 4) @available(macOS 10.13, *)
extension NSFont.Weight: _AppKitKitNumericRawRepresentable {}

@available(swift 4) @available(macOS 13, *)
extension NSFont.Width: _AppKitKitNumericRawRepresentable {}

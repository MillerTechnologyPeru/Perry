import Foundation

// UIKit's geometry structures as Swift values: equality, Codable (an
// unkeyed container of their fields in order) and, for insets and offsets,
// bridging to the NSValues Objective-C code holds them in.

// MARK: - UIEdgeInsets

@available(iOS 7.0, *)
extension UIEdgeInsets: Equatable {
    public static func == (lhs: UIEdgeInsets, rhs: UIEdgeInsets) -> Bool {
        lhs.top == rhs.top && lhs.left == rhs.left && lhs.bottom == rhs.bottom && lhs.right == rhs.right
    }
}

@available(iOS 7.0, *)
extension UIEdgeInsets: Codable {
    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let top = try container.decode(CGFloat.self)
        let left = try container.decode(CGFloat.self)
        let bottom = try container.decode(CGFloat.self)
        let right = try container.decode(CGFloat.self)
        self.init(top: top, left: left, bottom: bottom, right: right)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(top)
        try container.encode(left)
        try container.encode(bottom)
        try container.encode(right)
    }
}

@available(iOS 7.0, *)
extension UIEdgeInsets: _ObjectiveCBridgeable {
    public func _bridgeToObjectiveC() -> NSValue {
        NSValue(uiEdgeInsets: self)
    }

    public static func _forceBridgeFromObjectiveC(_ source: NSValue, result: inout UIEdgeInsets?) {
        result = source.uiEdgeInsetsValue
    }

    public static func _conditionallyBridgeFromObjectiveC(_ source: NSValue, result: inout UIEdgeInsets?) -> Bool {
        result = source.uiEdgeInsetsValue
        return true
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSValue?) -> UIEdgeInsets {
        source?.uiEdgeInsetsValue ?? .zero
    }
}

// MARK: - NSDirectionalEdgeInsets

@available(iOS 11.0, tvOS 11.0, watchOS 4.0, *)
extension NSDirectionalEdgeInsets: Equatable {
    public static func == (lhs: NSDirectionalEdgeInsets, rhs: NSDirectionalEdgeInsets) -> Bool {
        lhs.top == rhs.top && lhs.leading == rhs.leading && lhs.bottom == rhs.bottom && lhs.trailing == rhs.trailing
    }
}

@available(iOS 11.0, tvOS 11.0, watchOS 4.0, *)
extension NSDirectionalEdgeInsets: Codable {
    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let top = try container.decode(CGFloat.self)
        let leading = try container.decode(CGFloat.self)
        let bottom = try container.decode(CGFloat.self)
        let trailing = try container.decode(CGFloat.self)
        self.init(top: top, leading: leading, bottom: bottom, trailing: trailing)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(top)
        try container.encode(leading)
        try container.encode(bottom)
        try container.encode(trailing)
    }
}

@available(iOS 11.0, tvOS 11.0, watchOS 4.0, *)
extension NSDirectionalEdgeInsets: _ObjectiveCBridgeable {
    public func _bridgeToObjectiveC() -> NSValue {
        NSValue(directionalEdgeInsets: self)
    }

    public static func _forceBridgeFromObjectiveC(_ source: NSValue, result: inout NSDirectionalEdgeInsets?) {
        result = source.directionalEdgeInsetsValue
    }

    public static func _conditionallyBridgeFromObjectiveC(_ source: NSValue, result: inout NSDirectionalEdgeInsets?) -> Bool {
        result = source.directionalEdgeInsetsValue
        return true
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSValue?) -> NSDirectionalEdgeInsets {
        source?.directionalEdgeInsetsValue ?? .zero
    }
}

// MARK: - UIOffset

@available(iOS 7.0, *)
extension UIOffset: Equatable {
    public static func == (lhs: UIOffset, rhs: UIOffset) -> Bool {
        lhs.horizontal == rhs.horizontal && lhs.vertical == rhs.vertical
    }
}

@available(iOS 7.0, *)
extension UIOffset: Codable {
    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let horizontal = try container.decode(CGFloat.self)
        let vertical = try container.decode(CGFloat.self)
        self.init(horizontal: horizontal, vertical: vertical)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(horizontal)
        try container.encode(vertical)
    }
}

@available(iOS 7.0, *)
extension UIOffset: _ObjectiveCBridgeable {
    public func _bridgeToObjectiveC() -> NSValue {
        NSValue(uiOffset: self)
    }

    public static func _forceBridgeFromObjectiveC(_ source: NSValue, result: inout UIOffset?) {
        result = source.uiOffsetValue
    }

    public static func _conditionallyBridgeFromObjectiveC(_ source: NSValue, result: inout UIOffset?) -> Bool {
        result = source.uiOffsetValue
        return true
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSValue?) -> UIOffset {
        source?.uiOffsetValue ?? .zero
    }
}

// MARK: - UIFloatRange

@available(iOS 7.0, *)
extension UIFloatRange: Equatable {
    public static func == (lhs: UIFloatRange, rhs: UIFloatRange) -> Bool {
        lhs.minimum == rhs.minimum && lhs.maximum == rhs.maximum
    }
}

@available(iOS 7.0, *)
extension UIFloatRange: Codable {
    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let minimum = try container.decode(CGFloat.self)
        let maximum = try container.decode(CGFloat.self)
        self.init(minimum: minimum, maximum: maximum)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(minimum)
        try container.encode(maximum)
    }
}

// MARK: - The C functions' Swift 4 forms

@available(swift, introduced: 1.0, deprecated: 4.2, message: "Use == operator instead.")
@available(iOS, introduced: 7.0, deprecated: 12.0, message: "Use == operator instead.")
@available(watchOS, introduced: 2.0, deprecated: 5.0, message: "Use == operator instead.")
public func UIEdgeInsetsEqualToEdgeInsets(_ insets1: UIEdgeInsets, _ insets2: UIEdgeInsets) -> Bool {
    insets1 == insets2
}

@available(swift, introduced: 1.0, deprecated: 4.2, message: "Use == operator instead.")
@available(iOS, introduced: 7.0, deprecated: 12.0, message: "Use == operator instead.")
@available(watchOS, introduced: 2.0, deprecated: 5.0, message: "Use == operator instead.")
public func UIOffsetEqualToOffset(_ offset1: UIOffset, _ offset2: UIOffset) -> Bool {
    offset1 == offset2
}

@available(swift, introduced: 1.0, deprecated: 4.2, message: "Use == operator instead.")
@available(iOS, introduced: 7.0, deprecated: 12.0, message: "Use == operator instead.")
public func UIFloatRangeIsEqualToRange(_ range: UIFloatRange, _ otherRange: UIFloatRange) -> Bool {
    range == otherRange
}

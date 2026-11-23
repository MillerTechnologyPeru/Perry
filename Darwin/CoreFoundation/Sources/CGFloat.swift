// CGFloat: Core Graphics' floating-point type, a Double on 64-bit
// platforms. It began in the CoreGraphics overlay and moved here; its
// symbols keep CoreGraphics' names, so programs built against either find
// it. Each operation hands off to the native value.

@available(macOS 10.0, macCatalyst 13.0, iOS 2.0, watchOS 1.0, tvOS 9.0, *)
@_originallyDefinedIn(module: "CoreGraphics", macOS 10.0)
@_originallyDefinedIn(module: "CoreGraphics", macCatalyst 13.0)
@_originallyDefinedIn(module: "CoreGraphics", iOS 2.0)
@_originallyDefinedIn(module: "CoreGraphics", watchOS 1.0)
@_originallyDefinedIn(module: "CoreGraphics", tvOS 9.0)
@frozen public struct CGFloat: Sendable {
#if arch(x86_64) || arch(arm64) || arch(arm64_32) || arch(powerpc64) || arch(powerpc64le) || arch(s390x)
    public typealias NativeType = Double
#else
    public typealias NativeType = Float
#endif

    @_transparent public init() {
        native = 0
    }

    @_transparent public init(_ value: Float) {
        native = NativeType(value)
    }

    @_transparent public init(_ value: Double) {
        native = NativeType(value)
    }

#if !(os(Windows) || os(Android)) && (arch(i386) || arch(x86_64))
    @_transparent public init(_ value: Float80) {
        native = NativeType(value)
    }
#endif

    @_transparent public init(_ value: CGFloat) {
        native = value.native
    }

    /// The value, as the platform's own floating-point type.
    public var native: NativeType
}

@available(macOS 10.0, macCatalyst 13.0, iOS 2.0, watchOS 1.0, tvOS 9.0, *)
@_originallyDefinedIn(module: "CoreGraphics", macOS 10.0)
@_originallyDefinedIn(module: "CoreGraphics", macCatalyst 13.0)
@_originallyDefinedIn(module: "CoreGraphics", iOS 2.0)
@_originallyDefinedIn(module: "CoreGraphics", watchOS 1.0)
@_originallyDefinedIn(module: "CoreGraphics", tvOS 9.0)
extension CGFloat: SignedNumeric {
    @_alwaysEmitIntoClient
    public init<T: BinaryInteger>(_ source: T) {
        native = NativeType(source)
    }

    @_transparent public init?<T: BinaryInteger>(exactly source: T) {
        guard let value = NativeType(exactly: source) else { return nil }
        native = value
    }

    @_transparent public var magnitude: CGFloat {
        CGFloat(native.magnitude)
    }

    public typealias IntegerLiteralType = Int
    public typealias Magnitude = CGFloat
}

@available(macOS 10.0, macCatalyst 13.0, iOS 2.0, watchOS 1.0, tvOS 9.0, *)
@_originallyDefinedIn(module: "CoreGraphics", macOS 10.0)
@_originallyDefinedIn(module: "CoreGraphics", macCatalyst 13.0)
@_originallyDefinedIn(module: "CoreGraphics", iOS 2.0)
@_originallyDefinedIn(module: "CoreGraphics", watchOS 1.0)
@_originallyDefinedIn(module: "CoreGraphics", tvOS 9.0)
extension CGFloat: BinaryFloatingPoint {
    public typealias RawSignificand = UInt
    public typealias Exponent = Int
    public typealias RawExponent = UInt
    public typealias FloatLiteralType = NativeType

    @_transparent public static var exponentBitCount: Int { NativeType.exponentBitCount }
    @_transparent public static var significandBitCount: Int { NativeType.significandBitCount }

    @_transparent public var bitPattern: UInt { UInt(native.bitPattern) }

    @_transparent public init(bitPattern: UInt) {
        native = NativeType(bitPattern: NativeType.RawSignificand(bitPattern))
    }

    @_transparent public var sign: FloatingPointSign { native.sign }
    @_transparent public var exponentBitPattern: UInt { native.exponentBitPattern }
    @_transparent public var significandBitPattern: UInt { UInt(native.significandBitPattern) }

    @_transparent public init(sign: FloatingPointSign, exponentBitPattern: UInt, significandBitPattern: UInt) {
        native = NativeType(sign: sign, exponentBitPattern: exponentBitPattern,
                            significandBitPattern: NativeType.RawSignificand(significandBitPattern))
    }

    @_transparent public init(nan payload: RawSignificand, signaling: Bool) {
        native = NativeType(nan: NativeType.RawSignificand(payload), signaling: signaling)
    }

    @_transparent public static var infinity: CGFloat { CGFloat(NativeType.infinity) }
    @_transparent public static var nan: CGFloat { CGFloat(NativeType.nan) }
    @_transparent public static var signalingNaN: CGFloat { CGFloat(NativeType.signalingNaN) }

    @available(*, unavailable, renamed: "nan")
    public static var quietNaN: CGFloat { nan }

    @_transparent public static var greatestFiniteMagnitude: CGFloat { CGFloat(NativeType.greatestFiniteMagnitude) }
    @_transparent public static var pi: CGFloat { CGFloat(NativeType.pi) }
    @_transparent public var ulp: CGFloat { CGFloat(native.ulp) }
    @_transparent public static var leastNormalMagnitude: CGFloat { CGFloat(NativeType.leastNormalMagnitude) }
    @_transparent public static var leastNonzeroMagnitude: CGFloat { CGFloat(NativeType.leastNonzeroMagnitude) }
    @_transparent public var exponent: Int { native.exponent }
    @_transparent public var significand: CGFloat { CGFloat(native.significand) }

    @_transparent public init(sign: FloatingPointSign, exponent: Int, significand: CGFloat) {
        native = NativeType(sign: sign, exponent: exponent, significand: significand.native)
    }

    @_transparent public mutating func round(_ rule: FloatingPointRoundingRule) { native.round(rule) }
    @_transparent public var nextUp: CGFloat { CGFloat(native.nextUp) }
    @_transparent public mutating func negate() { native.negate() }

    @_transparent public static func += (lhs: inout CGFloat, rhs: CGFloat) { lhs.native += rhs.native }
    @_transparent public static func -= (lhs: inout CGFloat, rhs: CGFloat) { lhs.native -= rhs.native }
    @_transparent public static func *= (lhs: inout CGFloat, rhs: CGFloat) { lhs.native *= rhs.native }
    @_transparent public static func /= (lhs: inout CGFloat, rhs: CGFloat) { lhs.native /= rhs.native }

    @_transparent public mutating func formTruncatingRemainder(dividingBy other: CGFloat) {
        native.formTruncatingRemainder(dividingBy: other.native)
    }

    @_transparent public mutating func formRemainder(dividingBy other: CGFloat) {
        native.formRemainder(dividingBy: other.native)
    }

    @_transparent public mutating func formSquareRoot() { native.formSquareRoot() }

    @_transparent public mutating func addProduct(_ lhs: CGFloat, _ rhs: CGFloat) {
        native.addProduct(lhs.native, rhs.native)
    }

    @_transparent public func isEqual(to other: CGFloat) -> Bool { native.isEqual(to: other.native) }
    @_transparent public func isLess(than other: CGFloat) -> Bool { native.isLess(than: other.native) }
    @_transparent public func isLessThanOrEqualTo(_ other: CGFloat) -> Bool { native.isLessThanOrEqualTo(other.native) }

    @_transparent public var isNormal: Bool { native.isNormal }
    @_transparent public var isFinite: Bool { native.isFinite }
    @_transparent public var isZero: Bool { native.isZero }
    @_transparent public var isSubnormal: Bool { native.isSubnormal }
    @_transparent public var isInfinite: Bool { native.isInfinite }
    @_transparent public var isNaN: Bool { native.isNaN }
    @_transparent public var isSignalingNaN: Bool { native.isSignalingNaN }

    @available(*, unavailable, renamed: "isSignalingNaN")
    public var isSignaling: Bool { isSignalingNaN }

    @_transparent public var isCanonical: Bool { true }
    @_transparent public var floatingPointClass: FloatingPointClassification { native.floatingPointClass }
    @_transparent public var binade: CGFloat { CGFloat(native.binade) }
    @_transparent public var significandWidth: Int { native.significandWidth }

    @_transparent public init(floatLiteral value: NativeType) {
        native = value
    }

    @_transparent public init(integerLiteral value: Int) {
        native = NativeType(value)
    }
}

@available(macOS 10.0, macCatalyst 13.0, iOS 2.0, watchOS 1.0, tvOS 9.0, *)
@_originallyDefinedIn(module: "CoreGraphics", macOS 10.0)
@_originallyDefinedIn(module: "CoreGraphics", macCatalyst 13.0)
@_originallyDefinedIn(module: "CoreGraphics", iOS 2.0)
@_originallyDefinedIn(module: "CoreGraphics", watchOS 1.0)
@_originallyDefinedIn(module: "CoreGraphics", tvOS 9.0)
extension CGFloat: CustomReflectable {
    public var customMirror: Mirror {
        Mirror(reflecting: native)
    }
}

@available(macOS 10.0, macCatalyst 13.0, iOS 2.0, watchOS 1.0, tvOS 9.0, *)
@_originallyDefinedIn(module: "CoreGraphics", macOS 10.0)
@_originallyDefinedIn(module: "CoreGraphics", macCatalyst 13.0)
@_originallyDefinedIn(module: "CoreGraphics", iOS 2.0)
@_originallyDefinedIn(module: "CoreGraphics", watchOS 1.0)
@_originallyDefinedIn(module: "CoreGraphics", tvOS 9.0)
extension CGFloat: CustomStringConvertible {
    @_transparent public var description: String { native.description }
}

@available(macOS 10.0, macCatalyst 13.0, iOS 2.0, watchOS 1.0, tvOS 9.0, *)
@_originallyDefinedIn(module: "CoreGraphics", macOS 10.0)
@_originallyDefinedIn(module: "CoreGraphics", macCatalyst 13.0)
@_originallyDefinedIn(module: "CoreGraphics", iOS 2.0)
@_originallyDefinedIn(module: "CoreGraphics", watchOS 1.0)
@_originallyDefinedIn(module: "CoreGraphics", tvOS 9.0)
extension CGFloat: Hashable {
    @_transparent public var hashValue: Int { native.hashValue }

    @inlinable @_transparent
    public func hash(into hasher: inout Hasher) {
        hasher.combine(native)
    }

    @_alwaysEmitIntoClient @inlinable
    public func _rawHashValue(seed: Int) -> Int {
        native._rawHashValue(seed: seed)
    }
}

// Conversions of the standard library's numbers from CGFloat.

@available(macOS 10.0, macCatalyst 13.0, iOS 2.0, watchOS 1.0, tvOS 9.0, *)
@_originallyDefinedIn(module: "CoreGraphics", macOS 10.0)
@_originallyDefinedIn(module: "CoreGraphics", macCatalyst 13.0)
@_originallyDefinedIn(module: "CoreGraphics", iOS 2.0)
@_originallyDefinedIn(module: "CoreGraphics", watchOS 1.0)
@_originallyDefinedIn(module: "CoreGraphics", tvOS 9.0)
extension UInt8 {
    @_transparent public init(_ value: CGFloat) { self = UInt8(value.native) }
}

@available(macOS 10.0, macCatalyst 13.0, iOS 2.0, watchOS 1.0, tvOS 9.0, *)
@_originallyDefinedIn(module: "CoreGraphics", macOS 10.0)
@_originallyDefinedIn(module: "CoreGraphics", macCatalyst 13.0)
@_originallyDefinedIn(module: "CoreGraphics", iOS 2.0)
@_originallyDefinedIn(module: "CoreGraphics", watchOS 1.0)
@_originallyDefinedIn(module: "CoreGraphics", tvOS 9.0)
extension Int8 {
    @_transparent public init(_ value: CGFloat) { self = Int8(value.native) }
}

@available(macOS 10.0, macCatalyst 13.0, iOS 2.0, watchOS 1.0, tvOS 9.0, *)
@_originallyDefinedIn(module: "CoreGraphics", macOS 10.0)
@_originallyDefinedIn(module: "CoreGraphics", macCatalyst 13.0)
@_originallyDefinedIn(module: "CoreGraphics", iOS 2.0)
@_originallyDefinedIn(module: "CoreGraphics", watchOS 1.0)
@_originallyDefinedIn(module: "CoreGraphics", tvOS 9.0)
extension UInt16 {
    @_transparent public init(_ value: CGFloat) { self = UInt16(value.native) }
}

@available(macOS 10.0, macCatalyst 13.0, iOS 2.0, watchOS 1.0, tvOS 9.0, *)
@_originallyDefinedIn(module: "CoreGraphics", macOS 10.0)
@_originallyDefinedIn(module: "CoreGraphics", macCatalyst 13.0)
@_originallyDefinedIn(module: "CoreGraphics", iOS 2.0)
@_originallyDefinedIn(module: "CoreGraphics", watchOS 1.0)
@_originallyDefinedIn(module: "CoreGraphics", tvOS 9.0)
extension Int16 {
    @_transparent public init(_ value: CGFloat) { self = Int16(value.native) }
}

@available(macOS 10.0, macCatalyst 13.0, iOS 2.0, watchOS 1.0, tvOS 9.0, *)
@_originallyDefinedIn(module: "CoreGraphics", macOS 10.0)
@_originallyDefinedIn(module: "CoreGraphics", macCatalyst 13.0)
@_originallyDefinedIn(module: "CoreGraphics", iOS 2.0)
@_originallyDefinedIn(module: "CoreGraphics", watchOS 1.0)
@_originallyDefinedIn(module: "CoreGraphics", tvOS 9.0)
extension UInt32 {
    @_transparent public init(_ value: CGFloat) { self = UInt32(value.native) }
}

@available(macOS 10.0, macCatalyst 13.0, iOS 2.0, watchOS 1.0, tvOS 9.0, *)
@_originallyDefinedIn(module: "CoreGraphics", macOS 10.0)
@_originallyDefinedIn(module: "CoreGraphics", macCatalyst 13.0)
@_originallyDefinedIn(module: "CoreGraphics", iOS 2.0)
@_originallyDefinedIn(module: "CoreGraphics", watchOS 1.0)
@_originallyDefinedIn(module: "CoreGraphics", tvOS 9.0)
extension Int32 {
    @_transparent public init(_ value: CGFloat) { self = Int32(value.native) }
}

@available(macOS 10.0, macCatalyst 13.0, iOS 2.0, watchOS 1.0, tvOS 9.0, *)
@_originallyDefinedIn(module: "CoreGraphics", macOS 10.0)
@_originallyDefinedIn(module: "CoreGraphics", macCatalyst 13.0)
@_originallyDefinedIn(module: "CoreGraphics", iOS 2.0)
@_originallyDefinedIn(module: "CoreGraphics", watchOS 1.0)
@_originallyDefinedIn(module: "CoreGraphics", tvOS 9.0)
extension UInt64 {
    @_transparent public init(_ value: CGFloat) { self = UInt64(value.native) }
}

@available(macOS 10.0, macCatalyst 13.0, iOS 2.0, watchOS 1.0, tvOS 9.0, *)
@_originallyDefinedIn(module: "CoreGraphics", macOS 10.0)
@_originallyDefinedIn(module: "CoreGraphics", macCatalyst 13.0)
@_originallyDefinedIn(module: "CoreGraphics", iOS 2.0)
@_originallyDefinedIn(module: "CoreGraphics", watchOS 1.0)
@_originallyDefinedIn(module: "CoreGraphics", tvOS 9.0)
extension Int64 {
    @_transparent public init(_ value: CGFloat) { self = Int64(value.native) }
}

@available(macOS 10.0, macCatalyst 13.0, iOS 2.0, watchOS 1.0, tvOS 9.0, *)
@_originallyDefinedIn(module: "CoreGraphics", macOS 10.0)
@_originallyDefinedIn(module: "CoreGraphics", macCatalyst 13.0)
@_originallyDefinedIn(module: "CoreGraphics", iOS 2.0)
@_originallyDefinedIn(module: "CoreGraphics", watchOS 1.0)
@_originallyDefinedIn(module: "CoreGraphics", tvOS 9.0)
extension UInt {
    @_transparent public init(_ value: CGFloat) { self = UInt(value.native) }
}

@available(macOS 10.0, macCatalyst 13.0, iOS 2.0, watchOS 1.0, tvOS 9.0, *)
@_originallyDefinedIn(module: "CoreGraphics", macOS 10.0)
@_originallyDefinedIn(module: "CoreGraphics", macCatalyst 13.0)
@_originallyDefinedIn(module: "CoreGraphics", iOS 2.0)
@_originallyDefinedIn(module: "CoreGraphics", watchOS 1.0)
@_originallyDefinedIn(module: "CoreGraphics", tvOS 9.0)
extension Int {
    @_transparent public init(_ value: CGFloat) { self = Int(value.native) }
}

@available(macOS 10.0, macCatalyst 13.0, iOS 2.0, watchOS 1.0, tvOS 9.0, *)
@_originallyDefinedIn(module: "CoreGraphics", macOS 10.0)
@_originallyDefinedIn(module: "CoreGraphics", macCatalyst 13.0)
@_originallyDefinedIn(module: "CoreGraphics", iOS 2.0)
@_originallyDefinedIn(module: "CoreGraphics", watchOS 1.0)
@_originallyDefinedIn(module: "CoreGraphics", tvOS 9.0)
extension Double {
    @_transparent public init(_ value: CGFloat) { self = Double(value.native) }
}

@available(macOS 10.0, macCatalyst 13.0, iOS 2.0, watchOS 1.0, tvOS 9.0, *)
@_originallyDefinedIn(module: "CoreGraphics", macOS 10.0)
@_originallyDefinedIn(module: "CoreGraphics", macCatalyst 13.0)
@_originallyDefinedIn(module: "CoreGraphics", iOS 2.0)
@_originallyDefinedIn(module: "CoreGraphics", watchOS 1.0)
@_originallyDefinedIn(module: "CoreGraphics", tvOS 9.0)
extension Float {
    @_transparent public init(_ value: CGFloat) { self = Float(value.native) }
}

// Arithmetic, striding, C variadic arguments and coding.

@available(macOS 10.0, macCatalyst 13.0, iOS 2.0, watchOS 1.0, tvOS 9.0, *)
@_originallyDefinedIn(module: "CoreGraphics", macOS 10.0)
@_originallyDefinedIn(module: "CoreGraphics", macCatalyst 13.0)
@_originallyDefinedIn(module: "CoreGraphics", iOS 2.0)
@_originallyDefinedIn(module: "CoreGraphics", watchOS 1.0)
@_originallyDefinedIn(module: "CoreGraphics", tvOS 9.0)
extension CGFloat {
    @_transparent public static func + (lhs: CGFloat, rhs: CGFloat) -> CGFloat { CGFloat(lhs.native + rhs.native) }
    @_transparent public static func - (lhs: CGFloat, rhs: CGFloat) -> CGFloat { CGFloat(lhs.native - rhs.native) }
    @_transparent public static func * (lhs: CGFloat, rhs: CGFloat) -> CGFloat { CGFloat(lhs.native * rhs.native) }
    @_transparent public static func / (lhs: CGFloat, rhs: CGFloat) -> CGFloat { CGFloat(lhs.native / rhs.native) }
}

@available(macOS 10.0, macCatalyst 13.0, iOS 2.0, watchOS 1.0, tvOS 9.0, *)
@_originallyDefinedIn(module: "CoreGraphics", macOS 10.0)
@_originallyDefinedIn(module: "CoreGraphics", macCatalyst 13.0)
@_originallyDefinedIn(module: "CoreGraphics", iOS 2.0)
@_originallyDefinedIn(module: "CoreGraphics", watchOS 1.0)
@_originallyDefinedIn(module: "CoreGraphics", tvOS 9.0)
extension CGFloat: Strideable {
    public typealias Stride = CGFloat

    @_transparent public func distance(to other: CGFloat) -> CGFloat { CGFloat(other.native - native) }
    @_transparent public func advanced(by amount: CGFloat) -> CGFloat { CGFloat(native + amount.native) }
}

@available(macOS 10.0, macCatalyst 13.0, iOS 2.0, watchOS 1.0, tvOS 9.0, *)
@_originallyDefinedIn(module: "CoreGraphics", macOS 10.0)
@_originallyDefinedIn(module: "CoreGraphics", macCatalyst 13.0)
@_originallyDefinedIn(module: "CoreGraphics", iOS 2.0)
@_originallyDefinedIn(module: "CoreGraphics", watchOS 1.0)
@_originallyDefinedIn(module: "CoreGraphics", tvOS 9.0)
extension CGFloat: _CVarArgPassedAsDouble, _CVarArgAligned {
    @_transparent public var _cVarArgEncoding: [Int] { native._cVarArgEncoding }
    @_transparent public var _cVarArgAlignment: Int { native._cVarArgAlignment }
}

@available(macOS 10.0, macCatalyst 13.0, iOS 2.0, watchOS 1.0, tvOS 9.0, *)
@_originallyDefinedIn(module: "CoreGraphics", macOS 10.0)
@_originallyDefinedIn(module: "CoreGraphics", macCatalyst 13.0)
@_originallyDefinedIn(module: "CoreGraphics", iOS 2.0)
@_originallyDefinedIn(module: "CoreGraphics", watchOS 1.0)
@_originallyDefinedIn(module: "CoreGraphics", tvOS 9.0)
extension CGFloat: Codable {
    /// Decodes the native type; a value written as the other width (a
    /// Float where Double is native, or the reverse) is taken too.
    @_transparent public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(NativeType.self) {
            native = value
        } else if NativeType.self == Double.self, let value = try? container.decode(Float.self) {
            native = NativeType(value)
        } else if NativeType.self == Float.self, let value = try? container.decode(Double.self) {
            native = NativeType(value)
        } else {
            native = try container.decode(NativeType.self)
        }
    }

    @_transparent public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(native)
    }
}

@available(macOS 10.0, macCatalyst 13.0, iOS 2.0, watchOS 1.0, tvOS 9.0, *)
@_originallyDefinedIn(module: "CoreGraphics", macOS 10.0)
@_originallyDefinedIn(module: "CoreGraphics", macCatalyst 13.0)
@_originallyDefinedIn(module: "CoreGraphics", iOS 2.0)
@_originallyDefinedIn(module: "CoreGraphics", watchOS 1.0)
@_originallyDefinedIn(module: "CoreGraphics", tvOS 9.0)
extension CGFloat: BitwiseCopyable {}

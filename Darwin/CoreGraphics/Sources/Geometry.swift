import Foundation

// CGPoint, CGSize, CGRect, CGVector and CGAffineTransform: initializers,
// constants, comparisons, reflection and coding. Each codes as an unkeyed
// list of its members (a rect as its origin and size), the form archives
// written by Apple's overlay take.

extension CGPoint {
    public static var zero: CGPoint {
        @_transparent get { CGPoint(x: 0, y: 0) }
    }

    @_transparent public init(x: Int, y: Int) {
        self.init(x: CGFloat(x), y: CGFloat(y))
    }

    @_transparent public init(x: Double, y: Double) {
        self.init(x: CGFloat(x), y: CGFloat(y))
    }

    public init?(dictionaryRepresentation dict: CFDictionary) {
        var point = CGPoint()
        guard CGPointMakeWithDictionaryRepresentation(dict, &point) else { return nil }
        self = point
    }
}

extension CGPoint: @retroactive CustomReflectable {
    public var customMirror: Mirror {
        Mirror(self, children: ["x": x, "y": y], displayStyle: .struct)
    }
}

extension CGPoint: @retroactive _CustomPlaygroundQuickLookable {
    @available(*, deprecated, message: "CGPoint.customPlaygroundQuickLook will be removed in a future Swift version")
    public var customPlaygroundQuickLook: PlaygroundQuickLook {
        .point(Double(x), Double(y))
    }
}

extension CGPoint: @retroactive CustomDebugStringConvertible {
    public var debugDescription: String {
        "(\(x), \(y))"
    }
}

extension CGPoint: @retroactive Equatable {
    @_transparent public static func == (lhs: CGPoint, rhs: CGPoint) -> Bool {
        lhs.x == rhs.x && lhs.y == rhs.y
    }
}

extension CGPoint {
    @_alwaysEmitIntoClient public func hash(into hasher: inout Hasher) {
        hasher.combine(x)
        hasher.combine(y)
    }

    @_alwaysEmitIntoClient public var hashValue: Int {
        var hasher = Hasher()
        hash(into: &hasher)
        return hasher.finalize()
    }
}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
extension CGPoint: @retroactive Hashable {}

extension CGPoint: @retroactive Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let x = try container.decode(CGFloat.self)
        let y = try container.decode(CGFloat.self)
        self.init(x: x, y: y)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(x)
        try container.encode(y)
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
@_cdecl("CGPointNearlyEqualToPoint")
@usableFromInline
internal func CGPointNearlyEqualToPoint(_ lhs: CGPoint, _ rhs: CGPoint) -> Bool {
    CGPointNearlyEqualToPointWithTolerance(lhs, rhs, defaultNearlyEqualTolerance)
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
@_cdecl("CGPointNearlyEqualToPointWithTolerance")
@usableFromInline
internal func CGPointNearlyEqualToPointWithTolerance(_ lhs: CGPoint, _ rhs: CGPoint, _ tolerance: CGFloat) -> Bool {
    nearlyEqual(lhs.x, rhs.x, tolerance) && nearlyEqual(lhs.y, rhs.y, tolerance)
}

extension CGSize {
    public static var zero: CGSize {
        @_transparent get { CGSize(width: 0, height: 0) }
    }

    @_transparent public init(width: Int, height: Int) {
        self.init(width: CGFloat(width), height: CGFloat(height))
    }

    @_transparent public init(width: Double, height: Double) {
        self.init(width: CGFloat(width), height: CGFloat(height))
    }

    public init?(dictionaryRepresentation dict: CFDictionary) {
        var size = CGSize()
        guard CGSizeMakeWithDictionaryRepresentation(dict, &size) else { return nil }
        self = size
    }
}

extension CGSize: @retroactive CustomReflectable {
    public var customMirror: Mirror {
        Mirror(self, children: ["width": width, "height": height], displayStyle: .struct)
    }
}

extension CGSize: @retroactive _CustomPlaygroundQuickLookable {
    @available(*, deprecated, message: "CGSize.customPlaygroundQuickLook will be removed in a future Swift version")
    public var customPlaygroundQuickLook: PlaygroundQuickLook {
        .size(Double(width), Double(height))
    }
}

extension CGSize: @retroactive CustomDebugStringConvertible {
    public var debugDescription: String {
        "(\(width), \(height))"
    }
}

extension CGSize: @retroactive Equatable {
    @_transparent public static func == (lhs: CGSize, rhs: CGSize) -> Bool {
        lhs.width == rhs.width && lhs.height == rhs.height
    }
}

extension CGSize {
    @_alwaysEmitIntoClient public func hash(into hasher: inout Hasher) {
        hasher.combine(width)
        hasher.combine(height)
    }

    @_alwaysEmitIntoClient public var hashValue: Int {
        var hasher = Hasher()
        hash(into: &hasher)
        return hasher.finalize()
    }
}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
extension CGSize: @retroactive Hashable {}

extension CGSize: @retroactive Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let width = try container.decode(CGFloat.self)
        let height = try container.decode(CGFloat.self)
        self.init(width: width, height: height)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(width)
        try container.encode(height)
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
@_cdecl("CGSizeNearlyEqualToSize")
@usableFromInline
internal func CGSizeNearlyEqualToSize(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
    CGSizeNearlyEqualToSizeWithTolerance(lhs, rhs, defaultNearlyEqualTolerance)
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
@_cdecl("CGSizeNearlyEqualToSizeWithTolerance")
@usableFromInline
internal func CGSizeNearlyEqualToSizeWithTolerance(_ lhs: CGSize, _ rhs: CGSize, _ tolerance: CGFloat) -> Bool {
    nearlyEqual(lhs.width, rhs.width, tolerance) && nearlyEqual(lhs.height, rhs.height, tolerance)
}

extension CGVector {
    public static var zero: CGVector {
        @_transparent get { CGVector(dx: 0, dy: 0) }
    }

    @_transparent public init(dx: Int, dy: Int) {
        self.init(dx: CGFloat(dx), dy: CGFloat(dy))
    }

    @_transparent public init(dx: Double, dy: Double) {
        self.init(dx: CGFloat(dx), dy: CGFloat(dy))
    }
}

extension CGVector: @retroactive Equatable {
    @_transparent public static func == (lhs: CGVector, rhs: CGVector) -> Bool {
        lhs.dx == rhs.dx && lhs.dy == rhs.dy
    }
}

extension CGVector {
    @_alwaysEmitIntoClient public func hash(into hasher: inout Hasher) {
        hasher.combine(dx)
        hasher.combine(dy)
    }

    @_alwaysEmitIntoClient public var hashValue: Int {
        var hasher = Hasher()
        hash(into: &hasher)
        return hasher.finalize()
    }
}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
extension CGVector: @retroactive Hashable {}

extension CGVector: @retroactive CustomDebugStringConvertible {
    public var debugDescription: String {
        "(\(dx), \(dy))"
    }
}

extension CGVector: @retroactive Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let dx = try container.decode(CGFloat.self)
        let dy = try container.decode(CGFloat.self)
        self.init(dx: dx, dy: dy)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(dx)
        try container.encode(dy)
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
@_cdecl("CGVectorNearlyEqualToVector")
@usableFromInline
internal func CGVectorNearlyEqualToVector(_ lhs: CGVector, _ rhs: CGVector) -> Bool {
    CGVectorNearlyEqualToVectorWithTolerance(lhs, rhs, defaultNearlyEqualTolerance)
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
@_cdecl("CGVectorNearlyEqualToVectorWithTolerance")
@usableFromInline
internal func CGVectorNearlyEqualToVectorWithTolerance(_ lhs: CGVector, _ rhs: CGVector, _ tolerance: CGFloat) -> Bool {
    nearlyEqual(lhs.dx, rhs.dx, tolerance) && nearlyEqual(lhs.dy, rhs.dy, tolerance)
}

extension CGRect {
    public static var zero: CGRect {
        @_transparent get { CGRect(x: 0, y: 0, width: 0, height: 0) }
    }

    @_transparent public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.init(origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height))
    }

    @_transparent public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height))
    }

    @_transparent public init(x: Int, y: Int, width: Int, height: Int) {
        self.init(origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height))
    }

    public init?(dictionaryRepresentation dict: CFDictionary) {
        var rect = CGRect()
        guard CGRectMakeWithDictionaryRepresentation(dict, &rect) else { return nil }
        self = rect
    }

    @_transparent public func divided(atDistance: CGFloat, from fromEdge: CGRectEdge) -> (slice: CGRect, remainder: CGRect) {
        var slice = CGRect.zero
        var remainder = CGRect.zero
        __divided(slice: &slice, remainder: &remainder, atDistance: atDistance, from: fromEdge)
        return (slice, remainder)
    }

    @_transparent public func __divided(slice: UnsafeMutablePointer<CGRect>, remainder: UnsafeMutablePointer<CGRect>,
                                        atDistance: CGFloat, from: CGRectEdge) {
        __CGRectDivide(self, slice, remainder, atDistance, from)
    }

    @available(*, unavailable, renamed: "minX")
    public var x: CGFloat { minX }

    @available(*, unavailable, renamed: "minY")
    public var y: CGFloat { minY }
}

extension CGRect: @retroactive CustomReflectable {
    public var customMirror: Mirror {
        Mirror(self, children: ["origin": origin, "size": size], displayStyle: .struct)
    }
}

extension CGRect: @retroactive _CustomPlaygroundQuickLookable {
    @available(*, deprecated, message: "CGRect.customPlaygroundQuickLook will be removed in a future Swift version")
    public var customPlaygroundQuickLook: PlaygroundQuickLook {
        .rectangle(Double(origin.x), Double(origin.y), Double(size.width), Double(size.height))
    }
}

extension CGRect: @retroactive CustomDebugStringConvertible {
    public var debugDescription: String {
        "(\(origin.x), \(origin.y), \(size.width), \(size.height))"
    }
}

extension CGRect: @retroactive Equatable {
    @_transparent public static func == (lhs: CGRect, rhs: CGRect) -> Bool {
        lhs.equalTo(rhs)
    }
}

extension CGRect {
    @_alwaysEmitIntoClient public func hash(into hasher: inout Hasher) {
        let standard = standardized
        hasher.combine(standard.origin.x)
        hasher.combine(standard.origin.y)
        hasher.combine(standard.size.width)
        hasher.combine(standard.size.height)
    }

    @_alwaysEmitIntoClient public var hashValue: Int {
        var hasher = Hasher()
        hash(into: &hasher)
        return hasher.finalize()
    }
}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
extension CGRect: @retroactive Hashable {}

extension CGRect: @retroactive Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let origin = try container.decode(CGPoint.self)
        let size = try container.decode(CGSize.self)
        self.init(origin: origin, size: size)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(origin)
        try container.encode(size)
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
@_cdecl("CGRectNearlyEqualToRect")
@usableFromInline
internal func CGRectNearlyEqualToRect(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
    CGRectNearlyEqualToRectWithTolerance(lhs, rhs, defaultNearlyEqualTolerance)
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
@_cdecl("CGRectNearlyEqualToRectWithTolerance")
@usableFromInline
internal func CGRectNearlyEqualToRectWithTolerance(_ lhs: CGRect, _ rhs: CGRect, _ tolerance: CGFloat) -> Bool {
    CGPointNearlyEqualToPointWithTolerance(lhs.origin, rhs.origin, tolerance)
        && CGSizeNearlyEqualToSizeWithTolerance(lhs.size, rhs.size, tolerance)
}

extension CGAffineTransform {
    public static var identity: CGAffineTransform {
        @_transparent get { CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0) }
    }
}

extension CGAffineTransform: @retroactive Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let a = try container.decode(CGFloat.self)
        let b = try container.decode(CGFloat.self)
        let c = try container.decode(CGFloat.self)
        let d = try container.decode(CGFloat.self)
        let tx = try container.decode(CGFloat.self)
        let ty = try container.decode(CGFloat.self)
        self.init(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(a)
        try container.encode(b)
        try container.encode(c)
        try container.encode(d)
        try container.encode(tx)
        try container.encode(ty)
    }
}

extension CGAffineTransform: @retroactive Equatable {
    public static func == (lhs: CGAffineTransform, rhs: CGAffineTransform) -> Bool {
        transformsEqual(lhs, rhs)
    }
}

extension CGAffineTransform {
    @_alwaysEmitIntoClient public func hash(into hasher: inout Hasher) {
        hasher.combine(a)
        hasher.combine(b)
        hasher.combine(c)
        hasher.combine(d)
        hasher.combine(tx)
        hasher.combine(ty)
    }

    @_alwaysEmitIntoClient public var hashValue: Int {
        var hasher = Hasher()
        hash(into: &hasher)
        return hasher.finalize()
    }
}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
extension CGAffineTransform: @retroactive Hashable {}

// The functions the headers declare but Swift renames or hides, for the
// inlinable code of the interface.

@_alwaysEmitIntoClient public func __CGAffineTransformMake(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat, _ tx: CGFloat, _ ty: CGFloat) -> CGAffineTransform {
    CGAffineTransformMake(a, b, c, d, tx, ty)
}

@_alwaysEmitIntoClient public func __CGPointApplyAffineTransform(_ point: CGPoint, _ t: CGAffineTransform) -> CGPoint {
    CGPointApplyAffineTransform(point, t)
}

@_alwaysEmitIntoClient public func __CGSizeApplyAffineTransform(_ size: CGSize, _ t: CGAffineTransform) -> CGSize {
    CGSizeApplyAffineTransform(size, t)
}

// The C forms Swift had before the members above, unavailable now but
// still linked by programs built against Swift 4 and 5's SDKs.

@available(*, unavailable, message: "Use == instead")
public func CGAffineTransformEqualToTransform(_ t1: CGAffineTransform, _ t2: CGAffineTransform) -> Bool {
    transformsEqual(t1, t2)
}

@available(*, unavailable, message: "Use divided(atDistance:from:)")
public func CGRectDivide(_ rect: CGRect, _ slice: UnsafeMutablePointer<CGRect>, _ remainder: UnsafeMutablePointer<CGRect>,
                         _ amount: CGFloat, _ edge: CGRectEdge) {
    __CGRectDivide(rect, slice, remainder, amount, edge)
}

@available(*, unavailable, message: "Use CGPoint.init(dictionaryRepresentation:)")
public func CGPointMakeWithDictionaryRepresentation(_ dict: CFDictionary?, _ point: UnsafeMutablePointer<CGPoint>) -> Bool {
    guard let dict else { return false }
    return CoreGraphics.CGPointMakeWithDictionaryRepresentation(dict, point)
}

@available(*, unavailable, message: "Use CGSize.init(dictionaryRepresentation:)")
public func CGSizeMakeWithDictionaryRepresentation(_ dict: CFDictionary?, _ size: UnsafeMutablePointer<CGSize>) -> Bool {
    guard let dict else { return false }
    return CoreGraphics.CGSizeMakeWithDictionaryRepresentation(dict, size)
}

@available(*, unavailable, message: "Use CGRect.init(dictionaryRepresentation:)")
public func CGRectMakeWithDictionaryRepresentation(_ dict: CFDictionary?, _ rect: UnsafeMutablePointer<CGRect>) -> Bool {
    guard let dict else { return false }
    return CoreGraphics.CGRectMakeWithDictionaryRepresentation(dict, rect)
}

/// Whether two transforms have the same six members.
func transformsEqual(_ t1: CGAffineTransform, _ t2: CGAffineTransform) -> Bool {
    t1.a == t2.a && t1.b == t2.b && t1.c == t2.c && t1.d == t2.d && t1.tx == t2.tx && t1.ty == t2.ty
}

// NSRange's Swift API, as Apple's Foundation overlay has it: ranges compare
// and hash by their location and length, print as "{location, length}", and
// combine as NSUnionRange and NSIntersectionRange do.

extension NSRange: @retroactive Hashable {
    public static func == (lhs: NSRange, rhs: NSRange) -> Bool {
        lhs.location == rhs.location && lhs.length == rhs.length
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(location)
        hasher.combine(length)
    }
}

extension NSRange: @retroactive CustomStringConvertible, @retroactive CustomDebugStringConvertible {
    public var description: String { "{\(location), \(length)}" }
    public var debugDescription: String {
        guard location != NSNotFound else { return "{NSNotFound, \(length)}" }
        return "{\(location), \(length)}"
    }
}

extension NSRange {
    public var lowerBound: Int { location }
    public var upperBound: Int { location + length }

    public func contains(_ index: Int) -> Bool { index >= location && index - location < length }

    /// The smallest range that holds both.
    public func union(_ other: NSRange) -> NSRange {
        let start = Swift.min(location, other.location)
        return NSRange(location: start, length: Swift.max(upperBound, other.upperBound) - start)
    }

    /// What both ranges hold; nil when they hold nothing in common.
    public func intersection(_ other: NSRange) -> NSRange? {
        let start = Swift.max(location, other.location), end = Swift.min(upperBound, other.upperBound)
        guard start < end else { return nil }
        return NSRange(location: start, length: end - start)
    }

    public mutating func formUnion(_ other: NSRange) { self = union(other) }

    /// The range as one of integers; nil when it is not found.
    public func toRange() -> Range<Int>? {
        location == NSNotFound ? nil : location ..< location + length
    }
}

extension NSRange {
    public init<R: RangeExpression>(_ region: R) where R.Bound: FixedWidthInteger {
        let range = region.relative(to: 0 ..< R.Bound.max)
        self.init(location: Int(range.lowerBound), length: Int(range.upperBound - range.lowerBound))
    }
}

extension Range where Bound: BinaryInteger {
    public init?(_ range: NSRange) {
        guard range.location != NSNotFound else { return nil }
        self.init(uncheckedBounds: (Bound(range.location), Bound(range.location + range.length)))
    }
}

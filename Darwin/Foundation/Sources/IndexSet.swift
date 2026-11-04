/// A set of integers, held as sorted, separate ranges: [0..<3, 5..<6] for
/// {0, 1, 2, 5}. Its indices walk the integers in order; its range view
/// walks the ranges.
@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
public struct IndexSet: ReferenceConvertible, Equatable, BidirectionalCollection, SetAlgebra {
    public typealias Element = Int
    public typealias ReferenceType = NSIndexSet

    /// Sorted, non-empty, neither overlapping nor touching.
    var _ranges: [Range<Int>]

    init(_ranges ranges: [Range<Int>]) {
        _ranges = ranges
    }

    // MARK: Indices

    public struct Index: CustomStringConvertible, Comparable, Sendable {
        /// The range the integer is in, and the integer; the end index is
        /// past the last range.
        let rangeIndex: Int
        let value: Int

        public var description: String { "index \(value) in a range of the index set" }

        public static func == (lhs: Index, rhs: Index) -> Bool {
            lhs.rangeIndex == rhs.rangeIndex && lhs.value == rhs.value
        }

        public static func < (lhs: Index, rhs: Index) -> Bool {
            lhs.rangeIndex < rhs.rangeIndex || (lhs.rangeIndex == rhs.rangeIndex && lhs.value < rhs.value)
        }
    }

    public struct RangeView: Equatable, BidirectionalCollection, Sendable {
        public typealias Index = Int
        let ranges: [Range<Int>]

        public let startIndex: Int
        public let endIndex: Int

        init(_ ranges: [Range<Int>]) {
            self.ranges = ranges
            startIndex = 0
            endIndex = ranges.count
        }

        public func makeIterator() -> IndexingIterator<RangeView> { IndexingIterator(_elements: self) }
        public subscript(index: Int) -> Range<Int> { ranges[index] }
        public subscript(bounds: Range<Int>) -> Slice<RangeView> { Slice(base: self, bounds: bounds) }
        public func index(after i: Int) -> Int { i + 1 }
        public func index(before i: Int) -> Int { i - 1 }
    }

    public var startIndex: Index { Index(rangeIndex: 0, value: _ranges.first?.lowerBound ?? 0) }
    public var endIndex: Index { Index(rangeIndex: _ranges.count, value: 0) }

    public subscript(index: Index) -> Int { index.value }

    public subscript(bounds: Range<Index>) -> Slice<IndexSet> { Slice(base: self, bounds: bounds) }

    public func index(after i: Index) -> Index {
        let next = i.value + 1
        if next < _ranges[i.rangeIndex].upperBound { return Index(rangeIndex: i.rangeIndex, value: next) }
        let following = i.rangeIndex + 1
        return following < _ranges.count ? Index(rangeIndex: following, value: _ranges[following].lowerBound) : endIndex
    }

    public func formIndex(after i: inout Index) { i = index(after: i) }

    public func index(before i: Index) -> Index {
        if i.rangeIndex < _ranges.count, i.value > _ranges[i.rangeIndex].lowerBound {
            return Index(rangeIndex: i.rangeIndex, value: i.value - 1)
        }
        let previous = i.rangeIndex - 1
        return Index(rangeIndex: previous, value: _ranges[previous].upperBound - 1)
    }

    public func formIndex(before i: inout Index) { i = index(before: i) }

    public func makeIterator() -> IndexingIterator<IndexSet> { IndexingIterator(_elements: self) }

    // MARK: Creating

    public init() { _ranges = [] }

    public init(integer: Int) { _ranges = [integer..<integer + 1] }

    public init(integersIn range: Range<Int>) { _ranges = range.isEmpty ? [] : [range] }

    public init<R: RangeExpression>(integersIn range: R) where R.Bound == Int {
        self.init(integersIn: range.relative(to: Int.min..<Int.max))
    }

    public init(arrayLiteral elements: Int...) {
        self.init()
        for element in elements { insert(element) }
    }

    // MARK: Inspecting

    public var count: Int { _ranges.reduce(0) { $0 + $1.count } }
    public var isEmpty: Bool { _ranges.isEmpty }
    public var first: Int? { _ranges.first?.lowerBound }
    public var last: Int? { _ranges.last.map { $0.upperBound - 1 } }

    public var rangeView: RangeView { RangeView(_ranges) }

    public func rangeView(of range: Range<Int>) -> RangeView {
        RangeView(_ranges.compactMap { $0.overlaps(range) ? $0.clamped(to: range) : nil })
    }

    public func rangeView<R: RangeExpression>(of range: R) -> RangeView where R.Bound == Int {
        rangeView(of: range.relative(to: Int.min..<Int.max))
    }

    public func contains(_ integer: Int) -> Bool { _ranges.contains { $0.contains(integer) } }

    public func contains(integersIn range: Range<Int>) -> Bool {
        range.isEmpty || _ranges.contains { $0.lowerBound <= range.lowerBound && range.upperBound <= $0.upperBound }
    }

    public func contains<R: RangeExpression>(integersIn range: R) -> Bool where R.Bound == Int {
        contains(integersIn: range.relative(to: Int.min..<Int.max))
    }

    public func contains(integersIn indexSet: IndexSet) -> Bool {
        indexSet._ranges.allSatisfy { contains(integersIn: $0) }
    }

    public func intersects(integersIn range: Range<Int>) -> Bool { _ranges.contains { $0.overlaps(range) } }

    public func intersects<R: RangeExpression>(integersIn range: R) -> Bool where R.Bound == Int {
        intersects(integersIn: range.relative(to: Int.min..<Int.max))
    }

    public func count(in range: Range<Int>) -> Int {
        _ranges.reduce(0) { $0 + ($1.overlaps(range) ? $1.clamped(to: range).count : 0) }
    }

    public func count<R: RangeExpression>(in range: R) -> Int where R.Bound == Int {
        count(in: range.relative(to: Int.min..<Int.max))
    }

    public func integerGreaterThan(_ integer: Int) -> Int? { first { $0 > integer } }
    public func integerGreaterThanOrEqualTo(_ integer: Int) -> Int? { first { $0 >= integer } }
    public func integerLessThan(_ integer: Int) -> Int? { reversed().first { $0 < integer } }
    public func integerLessThanOrEqualTo(_ integer: Int) -> Int? { reversed().first { $0 <= integer } }

    /// The indices of the integers in `range`.
    public func indexRange(in range: Range<Int>) -> Range<Index> {
        guard let lower = firstIndex(where: { $0 >= range.lowerBound }), self[lower] < range.upperBound else {
            return endIndex..<endIndex
        }
        let upper = self[lower...].firstIndex { $0 >= range.upperBound } ?? endIndex
        return lower..<upper
    }

    public func indexRange<R: RangeExpression>(in range: R) -> Range<Index> where R.Bound == Int {
        indexRange(in: range.relative(to: Int.min..<Int.max))
    }

    // MARK: Changing

    /// The ranges, with `range` added, merged where they overlap or touch.
    private static func merging(_ ranges: [Range<Int>], _ range: Range<Int>) -> [Range<Int>] {
        guard !range.isEmpty else { return ranges }
        var result: [Range<Int>] = []
        var added = range
        var placed = false
        for existing in ranges {
            if existing.upperBound < added.lowerBound {
                result.append(existing)
            } else if added.upperBound < existing.lowerBound {
                if !placed { result.append(added); placed = true }
                result.append(existing)
            } else {
                added = Swift.min(existing.lowerBound, added.lowerBound)..<Swift.max(existing.upperBound, added.upperBound)
            }
        }
        if !placed { result.append(added) }
        return result
    }

    private static func removing(_ ranges: [Range<Int>], _ range: Range<Int>) -> [Range<Int>] {
        guard !range.isEmpty else { return ranges }
        var result: [Range<Int>] = []
        for existing in ranges {
            if !existing.overlaps(range) { result.append(existing); continue }
            if existing.lowerBound < range.lowerBound { result.append(existing.lowerBound..<range.lowerBound) }
            if range.upperBound < existing.upperBound { result.append(range.upperBound..<existing.upperBound) }
        }
        return result
    }

    public mutating func insert(integersIn range: Range<Int>) { _ranges = IndexSet.merging(_ranges, range) }

    public mutating func insert<R: RangeExpression>(integersIn range: R) where R.Bound == Int {
        insert(integersIn: range.relative(to: Int.min..<Int.max))
    }

    public mutating func remove(integersIn range: Range<Int>) { _ranges = IndexSet.removing(_ranges, range) }

    public mutating func remove(integersIn range: ClosedRange<Int>) { remove(integersIn: Range(range)) }

    @discardableResult
    public mutating func insert(_ integer: Int) -> (inserted: Bool, memberAfterInsert: Int) {
        let present = contains(integer)
        if !present { insert(integersIn: integer..<integer + 1) }
        return (!present, integer)
    }

    @discardableResult
    public mutating func update(with integer: Int) -> Int? {
        let present = contains(integer)
        insert(integersIn: integer..<integer + 1)
        return present ? integer : nil
    }

    @discardableResult
    public mutating func remove(_ integer: Int) -> Int? {
        guard contains(integer) else { return nil }
        remove(integersIn: integer..<integer + 1)
        return integer
    }

    public mutating func removeAll() { _ranges = [] }

    /// Moves the integers from `integer` on by `delta`; moving down removes
    /// those it passes over.
    public mutating func shift(startingAt integer: Int, by delta: Int) {
        guard delta != 0 else { return }
        let below = IndexSet.removing(_ranges, integer..<Int.max)
        let moving = _ranges.compactMap { $0.overlaps(integer..<Int.max) ? $0.clamped(to: integer..<Int.max) : nil }
        var result = delta < 0 ? IndexSet.removing(below, (integer + delta)..<integer) : below
        for range in moving { result = IndexSet.merging(result, (range.lowerBound + delta)..<(range.upperBound + delta)) }
        _ranges = result
    }

    // MARK: Combining

    public mutating func formUnion(_ other: IndexSet) {
        for range in other._ranges { insert(integersIn: range) }
    }

    public func union(_ other: IndexSet) -> IndexSet {
        var result = self
        result.formUnion(other)
        return result
    }

    public func intersection(_ other: IndexSet) -> IndexSet {
        var result: [Range<Int>] = []
        for range in _ranges {
            for otherRange in other._ranges where range.overlaps(otherRange) { result.append(range.clamped(to: otherRange)) }
        }
        return IndexSet(_ranges: result.sorted { $0.lowerBound < $1.lowerBound })
    }

    public mutating func formIntersection(_ other: IndexSet) { self = intersection(other) }

    public func symmetricDifference(_ other: IndexSet) -> IndexSet {
        var result = union(other)
        for range in intersection(other)._ranges { result.remove(integersIn: range) }
        return result
    }

    public mutating func formSymmetricDifference(_ other: IndexSet) { self = symmetricDifference(other) }

    public func filteredIndexSet(in range: Range<Int>, includeInteger: (Int) throws -> Bool) rethrows -> IndexSet {
        var result = IndexSet()
        for integer in self where range.contains(integer) {
            if try includeInteger(integer) { result.insert(integer) }
        }
        return result
    }

    public func filteredIndexSet(in range: ClosedRange<Int>, includeInteger: (Int) throws -> Bool) rethrows -> IndexSet {
        try filteredIndexSet(in: Range(range), includeInteger: includeInteger)
    }

    public func filteredIndexSet(includeInteger: (Int) throws -> Bool) rethrows -> IndexSet {
        try filteredIndexSet(in: Int.min..<Int.max, includeInteger: includeInteger)
    }

    public func hash(into hasher: inout Hasher) {
        for range in _ranges {
            hasher.combine(range.lowerBound)
            hasher.combine(range.upperBound)
        }
    }

    public static func == (lhs: IndexSet, rhs: IndexSet) -> Bool { lhs._ranges == rhs._ranges }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension IndexSet: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "\(count) indexes" }
    public var debugDescription: String { "IndexSet(\(_ranges.map { "\($0.lowerBound)..<\($0.upperBound)" }))" }
    public var customMirror: Mirror { Mirror(self, children: ["ranges": _ranges]) }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension IndexSet: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSIndexSet

    public static func _getObjectiveCType() -> Any.Type { NSIndexSet.self }

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSIndexSet {
        let set = NSMutableIndexSet()
        for range in _ranges { set.add(in: NSRange(location: range.lowerBound, length: range.count)) }
        return set
    }

    static func _bridging(_ source: NSIndexSet) -> IndexSet {
        var result = IndexSet()
        source.enumerateRanges { range, _ in
            result.insert(integersIn: range.location..<(range.location + range.length))
        }
        return result
    }

    public static func _forceBridgeFromObjectiveC(_ x: NSIndexSet, result: inout IndexSet?) {
        result = _bridging(x)
    }

    @discardableResult
    public static func _conditionallyBridgeFromObjectiveC(_ x: NSIndexSet, result: inout IndexSet?) -> Bool {
        result = _bridging(x)
        return true
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSIndexSet?) -> IndexSet {
        source.map(_bridging) ?? IndexSet()
    }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension IndexSet: Codable {
    private enum CodingKeys: String, CodingKey { case indexes }

    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.init()
        while !container.isAtEnd {
            let range = try container.decode([Int].self)
            if range.count == 2 { insert(integersIn: range[0]..<(range[0] + range[1])) }
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        for range in _ranges { try container.encode([range.lowerBound, range.count]) }
    }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension IndexSet: @unchecked Sendable {}

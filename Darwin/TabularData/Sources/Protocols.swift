// TabularData's protocols: columns of optional and non-optional elements,
// type-erased columns and their prototypes, and the data frame protocol
// DataFrame and DataFrame.Slice share.

import Foundation

/// A column: a named collection of elements.
public protocol ColumnProtocol<Element>: BidirectionalCollection {
    var name: String { get set }
}

/// A column whose elements are optional.
public protocol OptionalColumnProtocol<WrappedElement>: ColumnProtocol {
    associatedtype WrappedElement where Self.Element == Self.WrappedElement?
}

/// A column of elements of a type known only at run time.
public protocol AnyColumnProtocol {
    var name: String { get set }
    var count: Int { get }
    var wrappedElementType: any Any.Type { get }
    subscript(position: Int) -> Any? { get }
    subscript(range: Range<Int>) -> AnyColumnSlice { get }
}

/// Makes empty columns of a type known only at run time.
public protocol AnyColumnPrototype {
    var name: String { get set }
    func makeColumn(capacity: Int) -> AnyColumn
}

/// What DataFrame and DataFrame.Slice share.
public protocol DataFrameProtocol {
    associatedtype ColumnType: AnyColumnProtocol
    var base: DataFrame { get }
    var rows: DataFrame.Rows { get set }
    var columns: [ColumnType] { get }
    var shape: (rows: Int, columns: Int) { get }
    subscript(range: Range<Int>) -> DataFrame.Slice { get set }
}

extension DataFrameProtocol {
    public var isEmpty: Bool {
        shape.rows == 0
    }

    public subscript(range: Range<Int>) -> DataFrame.Slice {
        get {
            DataFrame.Slice(base: base, ranges: rows.subranges.intersection(range))
        }
        set {
            rows[range] = newValue.rows
        }
    }

    public subscript<R>(r: R) -> DataFrame.Slice where R: RangeExpression, R.Bound == Int {
        get {
            self[r.relative(to: rows.indices)]
        }
        set {
            self[r.relative(to: rows.indices)] = newValue
        }
    }

    /// The base frame's indices of the rows this frame has, in order.
    internal var _rowIndices: [Int] {
        rows.subranges.indices
    }
}

/// A prototype of a Column<T>.
internal struct _ColumnPrototype<T>: AnyColumnPrototype {
    var name: String

    func makeColumn(capacity: Int) -> AnyColumn {
        Column<T>(name: name, capacity: capacity).eraseToAnyColumn()
    }
}

/// Ordered, non-overlapping ranges of a frame's or column's indices.
internal struct _RangeSet: Hashable, CustomStringConvertible {
    private(set) var ranges: [Range<Int>]

    init() {
        ranges = []
    }

    init(_ range: Range<Int>) {
        ranges = range.isEmpty ? [] : [range]
    }

    /// Ranges in any order, possibly overlapping.
    init<S: Sequence>(ranges: S) where S.Element == Range<Int> {
        let sorted = ranges.filter { !$0.isEmpty }.sorted { $0.lowerBound < $1.lowerBound }
        var merged: [Range<Int>] = []
        for range in sorted {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound ..< Swift.max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        self.ranges = merged
    }

    /// Indices in ascending order (duplicates are dropped).
    init<S: Sequence>(sortedIndices: S) where S.Element == Int {
        var merged: [Range<Int>] = []
        for index in sortedIndices {
            if let last = merged.last {
                if index < last.upperBound { continue }
                if index == last.upperBound {
                    merged[merged.count - 1] = last.lowerBound ..< index + 1
                    continue
                }
            }
            merged.append(index ..< index + 1)
        }
        ranges = merged
    }

    var count: Int {
        ranges.reduce(0) { $0 + $1.count }
    }

    var isEmpty: Bool {
        ranges.isEmpty
    }

    var lowerBound: Int {
        ranges.first?.lowerBound ?? 0
    }

    var upperBound: Int {
        ranges.last?.upperBound ?? 0
    }

    var indices: [Int] {
        var result: [Int] = []
        result.reserveCapacity(count)
        for range in ranges { result.append(contentsOf: range) }
        return result
    }

    /// The position of the range containing index or, if none does, of the first range after it.
    private func rangePosition(_ index: Int) -> Int {
        var low = 0, high = ranges.count
        while low < high {
            let middle = (low + high) / 2
            if ranges[middle].upperBound <= index { low = middle + 1 } else { high = middle }
        }
        return low
    }

    func contains(_ index: Int) -> Bool {
        let position = rangePosition(index)
        return position < ranges.count && ranges[position].contains(index)
    }

    func index(after index: Int) -> Int {
        let position = rangePosition(index + 1)
        guard position < ranges.count else { return upperBound }
        return Swift.max(index + 1, ranges[position].lowerBound)
    }

    func index(before index: Int) -> Int {
        // The last range starting before index.
        var low = 0, high = ranges.count
        while low < high {
            let middle = (low + high) / 2
            if ranges[middle].lowerBound < index { low = middle + 1 } else { high = middle }
        }
        precondition(low > 0, "Index out of range")
        let range = ranges[low - 1]
        return Swift.min(index - 1, range.upperBound - 1)
    }

    /// The index offset positions from the first one.
    func index(atOffset offset: Int) -> Int {
        var remaining = offset
        for range in ranges {
            if remaining < range.count { return range.lowerBound + remaining }
            remaining -= range.count
        }
        precondition(remaining == 0, "Index out of range")
        return upperBound
    }

    func intersection(_ range: Range<Int>) -> _RangeSet {
        var result = _RangeSet()
        result.ranges = ranges.compactMap {
            let clamped = $0.clamped(to: range)
            return clamped.isEmpty ? nil : clamped
        }
        return result
    }

    func intersection(_ other: _RangeSet) -> _RangeSet {
        var result: [Range<Int>] = []
        for range in other.ranges {
            result.append(contentsOf: intersection(range).ranges)
        }
        return _RangeSet(ranges: result)
    }

    /// The first count indices.
    func prefix(_ count: Int) -> _RangeSet {
        var remaining = Swift.max(count, 0)
        var result: [Range<Int>] = []
        for range in ranges where remaining > 0 {
            let taken = Swift.min(remaining, range.count)
            result.append(range.lowerBound ..< range.lowerBound + taken)
            remaining -= taken
        }
        var set = _RangeSet()
        set.ranges = result
        return set
    }

    /// The last count indices.
    func suffix(_ count: Int) -> _RangeSet {
        var remaining = Swift.max(count, 0)
        var result: [Range<Int>] = []
        for range in ranges.reversed() where remaining > 0 {
            let taken = Swift.min(remaining, range.count)
            result.insert(range.upperBound - taken ..< range.upperBound, at: 0)
            remaining -= taken
        }
        var set = _RangeSet()
        set.ranges = result
        return set
    }

    var description: String {
        "_RangeSet(" + ranges.map { "\($0.lowerBound)..<\($0.upperBound)" }.joined(separator: ", ") + ")"
    }
}

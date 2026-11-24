// Slices of columns: contiguous (ColumnSlice), discontiguous
// (DiscontiguousColumnSlice), and columns with missing elements filled
// with a default (FilledColumn).

import Foundation

public struct ColumnSlice<WrappedElement>: OptionalColumnProtocol {
    public typealias Element = WrappedElement?
    public typealias Index = Int
    public typealias Indices = Range<ColumnSlice<WrappedElement>.Index>
    public typealias Iterator = IndexingIterator<ColumnSlice<WrappedElement>>
    public typealias SubSequence = ColumnSlice<WrappedElement>

    @usableFromInline
    internal var slice: Slice<Column<WrappedElement>>

    public var name: String {
        get {
            slice.base.name
        }
        set {
            var base = slice.base
            base.name = newValue
            slice = Slice(base: base, bounds: slice.startIndex ..< slice.endIndex)
        }
    }

    public var wrappedElementType: any Any.Type {
        WrappedElement.self
    }

    public var prototype: any AnyColumnPrototype {
        _ColumnPrototype<WrappedElement>(name: name)
    }

    @usableFromInline
    internal init(_ slice: Slice<Column<WrappedElement>>) {
        self.slice = slice
    }

    @usableFromInline
    internal init(base: Column<WrappedElement>, bounds: Range<Int>) {
        slice = Slice(base: base, bounds: bounds)
    }

    public init(_ column: Column<WrappedElement>) {
        self.init(base: column, bounds: 0 ..< column.count)
    }

    public func map<T>(_ transform: (Element) throws -> T?) rethrows -> Column<T> {
        try Column<T>(name: name, contents: slice.map(transform))
    }

    public func filter(_ isIncluded: (Element) throws -> Bool) rethrows -> DiscontiguousColumnSlice<WrappedElement> {
        var included: [Int] = []
        for i in slice.indices where try isIncluded(slice[i]) { included.append(i) }
        return DiscontiguousColumnSlice(column: slice.base, set: _RangeSet(sortedIndices: included))
    }

    public func eraseToAnyColumn() -> AnyColumnSlice {
        AnyColumnSlice(column: slice.base.eraseToAnyColumn(), set: _RangeSet(slice.startIndex ..< slice.endIndex))
    }
}

extension ColumnSlice: @unchecked Sendable where WrappedElement: Sendable {}

extension ColumnSlice: RandomAccessCollection, MutableCollection {
    public var startIndex: Int {
        slice.startIndex
    }

    public var endIndex: Int {
        slice.endIndex
    }

    public func index(after i: Int) -> Int {
        slice.index(after: i)
    }

    public func index(before i: Int) -> Int {
        slice.index(before: i)
    }

    public var count: Int {
        slice.count
    }

    public var missingCount: Int {
        indices.filter { slice.base.isNil(at: $0) }.count
    }

    public subscript(position: Int) -> Element {
        get {
            slice[position]
        }
        set {
            slice[position] = newValue
        }
    }

    public func isNil(at index: Int) -> Bool {
        slice.base.isNil(at: index)
    }

    public subscript(range: Range<Int>) -> ColumnSlice<WrappedElement> {
        get {
            ColumnSlice(slice[range])
        }
        set {
            slice[range] = newValue.slice
        }
    }
}

extension ColumnSlice: Equatable where WrappedElement: Equatable {
    public static func == (lhs: ColumnSlice<WrappedElement>, rhs: ColumnSlice<WrappedElement>) -> Bool {
        lhs.name == rhs.name && lhs.elementsEqual(rhs)
    }
}

extension ColumnSlice: Hashable where WrappedElement: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(count)
        for element in self { hasher.combine(element) }
    }

    public func distinct() -> DiscontiguousColumnSlice<WrappedElement> {
        DiscontiguousColumnSlice(column: slice.base, set: _RangeSet(sortedIndices: _distinctIndices(slice.base, indices: indices)))
    }
}

public struct DiscontiguousColumnSlice<WrappedElement>: OptionalColumnProtocol {
    public typealias Element = WrappedElement?
    public typealias Index = Int
    public typealias Indices = DefaultIndices<DiscontiguousColumnSlice<WrappedElement>>
    public typealias Iterator = IndexingIterator<DiscontiguousColumnSlice<WrappedElement>>
    public typealias SubSequence = DiscontiguousColumnSlice<WrappedElement>

    internal var _column: Column<WrappedElement>
    internal var _set: _RangeSet

    internal init(column: Column<WrappedElement>, set: _RangeSet) {
        _column = column
        _set = set
    }

    public var name: String {
        get { _column.name }
        set { _column.name = newValue }
    }

    public var wrappedElementType: any Any.Type {
        WrappedElement.self
    }

    public var prototype: any AnyColumnPrototype {
        _ColumnPrototype<WrappedElement>(name: name)
    }

    public init(_ column: Column<WrappedElement>) {
        self.init(column: column, set: _RangeSet(0 ..< column.count))
    }

    public init(column: Column<WrappedElement>, ranges: [Range<Int>]) {
        self.init(column: column, set: _RangeSet(ranges: ranges))
    }

    public func map<T>(_ transform: (Element) throws -> T?) rethrows -> Column<T> {
        var result = Column<T>(name: name, capacity: count)
        for element in self { result.append(try transform(element)) }
        return result
    }

    public func filter(_ isIncluded: (Element) throws -> Bool) rethrows -> DiscontiguousColumnSlice<WrappedElement> {
        var included: [Int] = []
        for i in _set.indices where try isIncluded(_column[i]) { included.append(i) }
        return DiscontiguousColumnSlice(column: _column, set: _RangeSet(sortedIndices: included))
    }

    public func eraseToAnyColumn() -> AnyColumnSlice {
        AnyColumnSlice(column: _column.eraseToAnyColumn(), set: _set)
    }
}

extension DiscontiguousColumnSlice: @unchecked Sendable where WrappedElement: Sendable {}

extension DiscontiguousColumnSlice: BidirectionalCollection, MutableCollection {
    public var startIndex: Int {
        _set.lowerBound
    }

    public var endIndex: Int {
        _set.upperBound
    }

    public func index(after i: Int) -> Int {
        _set.index(after: i)
    }

    public func index(before i: Int) -> Int {
        _set.index(before: i)
    }

    public var count: Int {
        _set.count
    }

    public var missingCount: Int {
        _set.indices.filter { _column.isNil(at: $0) }.count
    }

    public subscript(position: Int) -> Element {
        get {
            _column[position]
        }
        set {
            _column[position] = newValue
        }
    }

    public func isNil(at index: Int) -> Bool {
        _column.isNil(at: index)
    }

    public subscript(range: Range<Int>) -> DiscontiguousColumnSlice<WrappedElement> {
        get {
            DiscontiguousColumnSlice(column: _column, set: _set.intersection(range))
        }
        set {
            let destination = _set.intersection(range).indices
            precondition(destination.count == newValue.count, "Replacement must have the same count")
            for (i, element) in zip(destination, newValue) { _column[i] = element }
        }
    }

    public subscript<R>(range: R) -> DiscontiguousColumnSlice<WrappedElement> where R: RangeExpression, R.Bound == Int {
        get {
            self[range.relative(to: self)]
        }
        set {
            self[range.relative(to: self)] = newValue
        }
    }

    public subscript(range: UnboundedRange) -> DiscontiguousColumnSlice<WrappedElement> {
        get {
            self[startIndex...]
        }
        set {
            self[startIndex...] = newValue
        }
    }
}

extension DiscontiguousColumnSlice: Equatable where WrappedElement: Equatable {
    public static func == (lhs: DiscontiguousColumnSlice<WrappedElement>, rhs: DiscontiguousColumnSlice<WrappedElement>) -> Bool {
        lhs.name == rhs.name && lhs.elementsEqual(rhs)
    }
}

extension DiscontiguousColumnSlice: Hashable where WrappedElement: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(count)
        for element in self { hasher.combine(element) }
    }

    public func distinct() -> DiscontiguousColumnSlice<WrappedElement> {
        DiscontiguousColumnSlice(column: _column, set: _RangeSet(sortedIndices: _distinctIndices(_column, indices: _set.indices)))
    }
}

extension OptionalColumnProtocol {
    public func filled(with value: WrappedElement) -> FilledColumn<Self> {
        FilledColumn(base: self, defaultValue: value)
    }
}

/// A column whose missing elements read as a default value.
public struct FilledColumn<Base>: ColumnProtocol where Base: OptionalColumnProtocol {
    public typealias Element = Base.WrappedElement
    public typealias WrappedElement = Base.WrappedElement
    public typealias Index = Base.Index
    public typealias Indices = DefaultIndices<FilledColumn<Base>>
    public typealias Iterator = IndexingIterator<FilledColumn<Base>>
    public typealias SubSequence = Slice<FilledColumn<Base>>

    @usableFromInline
    internal var base: Base
    @usableFromInline
    internal let defaultValue: Base.WrappedElement

    internal init(base: Base, defaultValue: Base.WrappedElement) {
        self.base = base
        self.defaultValue = defaultValue
    }

    public var name: String {
        get { base.name }
        set { base.name = newValue }
    }

    public var startIndex: Base.Index {
        base.startIndex
    }

    public var endIndex: Base.Index {
        base.endIndex
    }

    public func index(after i: Base.Index) -> Base.Index {
        base.index(after: i)
    }

    public func index(before i: Base.Index) -> Base.Index {
        base.index(before: i)
    }

    public subscript(position: Base.Index) -> Base.WrappedElement {
        base[position] ?? defaultValue
    }
}

extension FilledColumn: @unchecked Sendable where Base: Sendable, Base.WrappedElement: Sendable {}

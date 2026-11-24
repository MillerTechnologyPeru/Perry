// Column: a named, copy-on-write collection of optional elements.

import Foundation

public struct Column<WrappedElement>: OptionalColumnProtocol {
    public typealias Element = WrappedElement?
    public typealias Index = Int
    public typealias Indices = Range<Int>
    public typealias Iterator = IndexingIterator<Column<WrappedElement>>
    public typealias SubSequence = ColumnSlice<WrappedElement>

    public var name: String
    internal var _storage: PackedOptionalsStorage<WrappedElement>

    public var count: Int {
        _storage.count
    }

    public var missingCount: Int {
        _storage.nilCount
    }

    public var wrappedElementType: any Any.Type {
        WrappedElement.self
    }

    public var prototype: any AnyColumnPrototype {
        _ColumnPrototype<WrappedElement>(name: name)
    }

    public init(name: String, capacity: Int) {
        self.name = name
        _storage = PackedOptionalsStorage(capacity: Swift.max(capacity, 0))
    }

    public init(_ id: ColumnID<WrappedElement>, capacity: Int) {
        self.init(name: id.name, capacity: capacity)
    }

    public init<S>(name: String, contents: S) where S: Sequence, S.Element == WrappedElement? {
        self.init(name: name, capacity: contents.underestimatedCount)
        append(contentsOf: contents)
    }

    public init<S>(name: String, contents: S) where WrappedElement == S.Element, S: Sequence {
        self.init(name: name, capacity: contents.underestimatedCount)
        append(contentsOf: contents)
    }

    public init<S>(_ id: ColumnID<S.Element>, contents: S) where S: Sequence, S.Element == WrappedElement? {
        self.init(name: id.name, contents: contents)
    }

    public init<S>(_ id: ColumnID<S.Element>, contents: S) where WrappedElement == S.Element, S: Sequence {
        self.init(name: id.name, contents: contents)
    }

    public init(_ slice: ColumnSlice<WrappedElement>) {
        self.init(name: slice.name, contents: slice.slice)
    }

    /// Makes the storage unique with room for extra more elements.
    internal mutating func _reserve(_ extra: Int) {
        let needed = _storage.count + extra
        if !isKnownUniquelyReferenced(&_storage) {
            _storage = _storage.createNew(minimumCapacity: needed, growForAppend: extra > 0)
        } else if needed > _storage.capacity {
            _storage.grow(minimumCapacity: needed, growForAppend: true)
        }
    }

    public mutating func append(_ element: Element) {
        _reserve(1)
        _storage.append(element)
    }

    public mutating func append(_ element: WrappedElement) {
        _reserve(1)
        _storage.append(element)
    }

    public mutating func append<S>(contentsOf sequence: S) where S: Sequence, S.Element == WrappedElement? {
        _reserve(sequence.underestimatedCount)
        for element in sequence {
            if _storage.count == _storage.capacity { _reserve(1) }
            _storage.append(element)
        }
    }

    public mutating func append<S>(contentsOf sequence: S) where WrappedElement == S.Element, S: Sequence {
        _reserve(sequence.underestimatedCount)
        for element in sequence {
            if _storage.count == _storage.capacity { _reserve(1) }
            _storage.append(element)
        }
    }

    internal mutating func _insert(_ element: Element, at index: Int) {
        precondition(index >= 0 && index <= count, "Index out of range")
        _reserve(1)
        _storage.buffer.replaceSubrange(index ..< index, with: CollectionOfOne(element))
    }

    public mutating func remove(at index: Int) {
        precondition(index >= 0 && index < count, "Index out of range")
        _reserve(0)
        _storage.buffer.replaceSubrange(index ..< index + 1, with: EmptyCollection())
    }

    public func map<T>(_ transform: (Element) throws -> T?) rethrows -> Column<T> {
        let result = Column<T>(name: name, capacity: count)
        for element in self { result._storage.append(try transform(element)) }
        return result
    }

    /// The transformed present elements; missing ones are left out.
    public func mapNonNil<T>(_ transform: (WrappedElement) throws -> T?) rethrows -> Column<T> {
        let result = Column<T>(name: name, capacity: count - missingCount)
        for case let element? in self { result._storage.append(try transform(element)) }
        return result
    }

    public mutating func transform(_ transform: (Element) throws -> Element) rethrows {
        _reserve(0)
        let buffer = _storage.buffer
        for i in 0 ..< buffer.count { buffer[i] = try transform(buffer[i]) }
    }

    public mutating func transform(_ transform: (WrappedElement) throws -> WrappedElement) rethrows {
        _reserve(0)
        let buffer = _storage.buffer
        for i in 0 ..< buffer.count where !buffer.isNil(at: i) {
            buffer[i] = try transform(buffer.firstElementAddress[i])
        }
    }

    public func filter(_ isIncluded: (Element) throws -> Bool) rethrows -> DiscontiguousColumnSlice<WrappedElement> {
        var included: [Int] = []
        for i in 0 ..< count where try isIncluded(self[i]) { included.append(i) }
        return DiscontiguousColumnSlice(column: self, set: _RangeSet(sortedIndices: included))
    }

    public func eraseToAnyColumn() -> AnyColumn {
        AnyColumn(_ColumnBox(column: self))
    }

    /// The elements at the indices given, nil where an index is.
    internal func _gathering<S: Sequence>(_ indices: S) -> Column<WrappedElement> where S.Element == Int? {
        var result = Column(name: name, capacity: indices.underestimatedCount)
        for index in indices {
            if result._storage.count == result._storage.capacity { result._reserve(1) }
            result._storage.append(index.flatMap { self[$0] })
        }
        return result
    }
}

extension Column: RandomAccessCollection, MutableCollection {
    public var startIndex: Int {
        0
    }

    public var endIndex: Int {
        count
    }

    public func index(after i: Int) -> Int {
        i + 1
    }

    public func index(before i: Int) -> Int {
        i - 1
    }

    public subscript(position: Int) -> Element {
        get {
            precondition(position >= 0 && position < count, "Index out of range")
            return _storage.buffer[position]
        }
        set {
            precondition(position >= 0 && position < count, "Index out of range")
            _reserve(0)
            _storage.buffer[position] = newValue
        }
    }

    @usableFromInline
    internal func isNil(at index: Int) -> Bool {
        _storage.buffer.isNil(at: index)
    }

    public subscript(bounds: Range<Int>) -> ColumnSlice<WrappedElement> {
        get {
            precondition(bounds.lowerBound >= 0 && bounds.upperBound <= count, "Range out of bounds")
            return ColumnSlice(base: self, bounds: bounds)
        }
        set {
            precondition(newValue.count == bounds.count, "Replacement must have the same count")
            var position = bounds.lowerBound
            for element in newValue {
                self[position] = element
                position += 1
            }
        }
    }

    public subscript<R>(range: R) -> ColumnSlice<WrappedElement> where R: RangeExpression, R.Bound == Int {
        get {
            self[range.relative(to: self)]
        }
        set {
            self[range.relative(to: self)] = newValue
        }
    }

    public subscript<C>(mask: C) -> DiscontiguousColumnSlice<WrappedElement> where C: Collection, C.Element == Bool {
        precondition(mask.count == count, "Length mismatch. mask: \(mask.count)    column: \(count)")
        var included: [Int] = []
        for (i, isIncluded) in mask.enumerated() where isIncluded && i < count { included.append(i) }
        return DiscontiguousColumnSlice(column: self, set: _RangeSet(sortedIndices: included))
    }

    /// Elements are packed, not stored as optionals: there is no contiguous storage of optionals.
    public func withContiguousStorageIfAvailable<R>(_ body: (UnsafeBufferPointer<WrappedElement?>) throws -> R) rethrows -> R? {
        nil
    }

    public mutating func withContiguousMutableStorageIfAvailable<R>(_ body: (inout UnsafeMutableBufferPointer<WrappedElement?>) throws -> R) rethrows -> R? {
        nil
    }

    /// The packed elements, when none is missing.
    public func withContiguousStorageIfAvailable<R>(_ body: (UnsafeBufferPointer<WrappedElement>) throws -> R) rethrows -> R? {
        guard missingCount == 0 else { return nil }
        return try body(UnsafeBufferPointer(start: _storage.buffer.firstElementAddress, count: count))
    }

    public mutating func withContiguousMutableStorageIfAvailable<R>(_ body: (inout UnsafeMutableBufferPointer<WrappedElement>) throws -> R) rethrows -> R? {
        guard missingCount == 0 else { return nil }
        _reserve(0)
        var buffer = UnsafeMutableBufferPointer(start: _storage.buffer.firstElementAddress, count: count)
        let start = buffer.baseAddress, length = buffer.count
        defer { precondition(buffer.baseAddress == start && buffer.count == length, "The buffer can't be replaced") }
        return try body(&buffer)
    }
}

extension Column: Equatable where WrappedElement: Equatable {
    public static func == (a: Column<WrappedElement>, b: Column<WrappedElement>) -> Bool {
        a.name == b.name && a.elementsEqual(b)
    }
}

extension Column: Hashable where WrappedElement: Hashable {
    public func distinct() -> DiscontiguousColumnSlice<WrappedElement> {
        DiscontiguousColumnSlice(column: self, set: _RangeSet(sortedIndices: _distinctIndices(self, indices: 0 ..< count)))
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(count)
        for element in self { hasher.combine(element) }
    }
}

/// The indices of the first occurrence of each value (nil included).
internal func _distinctIndices<C: Collection, I: Sequence>(_ collection: C, indices: I) -> [Int]
where C.Index == Int, I.Element == Int, C.Element: Hashable {
    var seen = Set<C.Element>()
    var result: [Int] = []
    for i in indices where seen.insert(collection[i]).inserted { result.append(i) }
    return result
}

private enum _ColumnCodingKeys: String, CodingKey {
    case name, elements
}

extension Column: Encodable where WrappedElement: Encodable {
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: _ColumnCodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(Array(self), forKey: .elements)
    }
}

extension Column: Decodable where WrappedElement: Decodable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: _ColumnCodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        let elements = try container.decode([WrappedElement?].self, forKey: .elements)
        self.init(name: name, contents: elements)
    }
}

extension Column: @unchecked Sendable where WrappedElement: Sendable {}

/// A column's identifier: its name and element type.
public struct ColumnID<T>: Sendable {
    public var name: String

    public var type: any Any.Type {
        T.self
    }

    public init(_ name: String, _ type: T.Type) {
        self.name = name
    }
}

extension ColumnID: CustomStringConvertible {
    public var description: String {
        "ColumnID(\(name), \(T.self))"
    }
}

// Type-erased columns: AnyColumn holds a Column<T> in a box that does the
// typed work, AnyColumnSlice a set of an AnyColumn's indices.

import Foundation

/// Whether a value is an optional holding nothing.
internal func _isNilValue(_ value: Any) -> Bool {
    let mirror = Mirror(reflecting: value)
    return mirror.displayStyle == .optional && mirror.children.isEmpty
}

/// A value of Any? as T?, trapping if it is something else.
internal func _cast<T>(_ value: Any?, to type: T.Type, column: String) -> T? {
    guard let value else { return nil }
    if let typed = value as? T { return typed }
    if _isNilValue(value) { return nil }
    fatalError("Can't store a value of type \(Swift.type(of: value)) in column '\(column)' of type \(T.self).")
}

/// Whether two values of unknown types are equal: by their hashable
/// representations when they have them, otherwise by their descriptions.
internal func _valuesEqual(_ a: Any?, _ b: Any?) -> Bool {
    switch (a, b) {
    case (nil, nil):
        return true
    case (nil, _), (_, nil):
        return false
    case let (a?, b?):
        if _isNilValue(a) || _isNilValue(b) { return _isNilValue(a) && _isNilValue(b) }
        if let ha = a as? AnyHashable, let hb = b as? AnyHashable { return ha == hb }
        return String(reflecting: a) == String(reflecting: b)
    }
}

internal func _hashValue(_ value: Any?, into hasher: inout Hasher) {
    guard let value, !_isNilValue(value) else {
        hasher.combine(0 as UInt8)
        return
    }
    hasher.combine(1 as UInt8)
    if let hashable = value as? AnyHashable {
        hasher.combine(hashable)
    } else {
        hasher.combine(String(reflecting: value))
    }
}

/// The operations on a column of a type known only at run time.
internal protocol _AnyColumnBox {
    var name: String { get set }
    var count: Int { get }
    var missingCount: Int { get }
    var wrappedElementType: any Any.Type { get }
    var prototype: any AnyColumnPrototype { get }
    func get(_ index: Int) -> Any?
    mutating func set(_ index: Int, _ value: Any?)
    func isNil(at index: Int) -> Bool
    mutating func append(_ value: Any?)
    /// Appends the elements of another box of the same type, at the indices given or all.
    mutating func append(contentsOf other: any _AnyColumnBox, indices: [Int]?)
    mutating func insert(_ value: Any?, at index: Int)
    mutating func remove(at index: Int)
    /// A column of the elements at the indices given, nil where an index is.
    func gathering(_ indices: [Int?]) -> any _AnyColumnBox
    /// The elements at the indices given as AnyHashable, nil for missing ones
    /// or all nil if the type isn't hashable.
    func hashable(_ index: Int) -> AnyHashable?
    var isHashable: Bool { get }
}

internal struct _ColumnBox<T>: _AnyColumnBox {
    var column: Column<T>

    var name: String {
        get { column.name }
        set { column.name = newValue }
    }

    var count: Int { column.count }
    var missingCount: Int { column.missingCount }
    var wrappedElementType: any Any.Type { T.self }
    var prototype: any AnyColumnPrototype { column.prototype }

    func get(_ index: Int) -> Any? {
        column[index].map { $0 as Any }
    }

    mutating func set(_ index: Int, _ value: Any?) {
        column[index] = _cast(value, to: T.self, column: column.name)
    }

    func isNil(at index: Int) -> Bool {
        column.isNil(at: index)
    }

    mutating func append(_ value: Any?) {
        column.append(_cast(value, to: T.self, column: column.name))
    }

    mutating func append(contentsOf other: any _AnyColumnBox, indices: [Int]?) {
        guard let other = other as? _ColumnBox<T> else {
            fatalError("Can't append a column of type \(other.wrappedElementType) to column '\(column.name)' of type \(T.self).")
        }
        if let indices {
            column.append(contentsOf: indices.lazy.map { other.column[$0] })
        } else {
            column.append(contentsOf: other.column)
        }
    }

    mutating func insert(_ value: Any?, at index: Int) {
        column._insert(_cast(value, to: T.self, column: column.name), at: index)
    }

    mutating func remove(at index: Int) {
        column.remove(at: index)
    }

    func gathering(_ indices: [Int?]) -> any _AnyColumnBox {
        _ColumnBox(column: column._gathering(indices))
    }

    var isHashable: Bool {
        T.self is any Hashable.Type
    }

    func hashable(_ index: Int) -> AnyHashable? {
        guard let value = column[index] else { return nil }
        return value as? AnyHashable
    }
}

public struct AnyColumn: AnyColumnProtocol, Hashable {
    public typealias Element = Any?
    public typealias Index = Int
    public typealias Indices = Range<Int>
    public typealias Iterator = IndexingIterator<AnyColumn>
    public typealias SubSequence = AnyColumnSlice

    internal var _box: any _AnyColumnBox

    internal init(_ box: any _AnyColumnBox) {
        _box = box
    }

    public var name: String {
        get { _box.name }
        set { _box.name = newValue }
    }

    public var wrappedElementType: any Any.Type {
        _box.wrappedElementType
    }

    public var prototype: any AnyColumnPrototype {
        _box.prototype
    }

    public var count: Int {
        _box.count
    }

    public var missingCount: Int {
        _box.missingCount
    }

    public func assumingType<T>(_ type: T.Type) -> Column<T> {
        guard let box = _box as? _ColumnBox<T> else {
            fatalError("Column '\(name)' has type \(wrappedElementType), not \(T.self).")
        }
        return box.column
    }

    public func isNil(at index: Int) -> Bool {
        _box.isNil(at: index)
    }

    public mutating func append(_ element: Any?) {
        _box.append(element)
    }

    public mutating func append(contentsOf other: AnyColumn) {
        _box.append(contentsOf: other._box, indices: nil)
    }

    public mutating func append(contentsOf other: AnyColumnSlice) {
        _box.append(contentsOf: other._column._box, indices: other._set.indices)
    }

    public mutating func remove(at index: Int) {
        _box.remove(at: index)
    }

    internal mutating func _insert(_ element: Any?, at index: Int) {
        _box.insert(element, at: index)
    }

    internal func _gathering(_ indices: [Int?]) -> AnyColumn {
        AnyColumn(_box.gathering(indices))
    }

    internal func _gathering(_ indices: [Int]) -> AnyColumn {
        AnyColumn(_box.gathering(indices.map { $0 }))
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(count)
        for i in 0 ..< count { _hashValue(_box.get(i), into: &hasher) }
    }
}

extension AnyColumn: RandomAccessCollection, MutableCollection {
    public var startIndex: Int {
        0
    }

    public var endIndex: Int {
        _box.count
    }

    public func index(after i: Int) -> Int {
        i + 1
    }

    public func index(before i: Int) -> Int {
        i - 1
    }

    public subscript(position: Int) -> Any? {
        get { _box.get(position) }
        set { _box.set(position, newValue) }
    }

    public subscript(range: Range<Int>) -> AnyColumnSlice {
        get {
            precondition(range.lowerBound >= 0 && range.upperBound <= count, "Range out of bounds")
            return AnyColumnSlice(column: self, set: _RangeSet(range))
        }
        set {
            precondition(newValue.count == range.count, "Replacement must have the same count")
            for (i, element) in zip(range, newValue) { self[i] = element }
        }
    }

    public subscript<C>(mask: C) -> AnyColumnSlice where C: Collection, C.Element == Bool {
        precondition(mask.count == count, "Length mismatch. mask: \(mask.count)    column: \(count)")
        var included: [Int] = []
        for (i, isIncluded) in mask.enumerated() where isIncluded && i < count { included.append(i) }
        return AnyColumnSlice(column: self, set: _RangeSet(sortedIndices: included))
    }

    public static func == (lhs: AnyColumn, rhs: AnyColumn) -> Bool {
        guard lhs.name == rhs.name, lhs.count == rhs.count, lhs.wrappedElementType == rhs.wrappedElementType else {
            return false
        }
        for i in 0 ..< lhs.count where !_valuesEqual(lhs[i], rhs[i]) { return false }
        return true
    }
}

extension AnyColumn {
    public func distinct() -> AnyColumnSlice {
        AnyColumnSlice(column: self, set: _RangeSet(sortedIndices: _distinctIndices(of: _box, indices: 0 ..< count)))
    }
}

/// The indices of the first occurrence of each value (nil included).
internal func _distinctIndices<S: Sequence>(of box: any _AnyColumnBox, indices: S) -> [Int] where S.Element == Int {
    var seen = Set<AnyHashable?>()
    var result: [Int] = []
    for i in indices {
        let key: AnyHashable? = box.isNil(at: i) ? nil : (box.hashable(i) ?? AnyHashable(String(reflecting: box.get(i)!)))
        if seen.insert(key).inserted { result.append(i) }
    }
    return result
}

public struct AnyColumnSlice: AnyColumnProtocol, Hashable {
    public typealias Element = Any?
    public typealias Index = Int
    public typealias Indices = Range<Int>
    public typealias Iterator = IndexingIterator<AnyColumnSlice>
    public typealias SubSequence = AnyColumnSlice

    internal var _column: AnyColumn
    internal var _set: _RangeSet

    internal init(column: AnyColumn, set: _RangeSet) {
        _column = column
        _set = set
    }

    public var name: String {
        get { _column.name }
        set { _column.name = newValue }
    }

    public var wrappedElementType: any Any.Type {
        _column.wrappedElementType
    }

    public var count: Int {
        _set.count
    }

    public var missingCount: Int {
        _set.indices.filter { _column.isNil(at: $0) }.count
    }

    public func assumingType<T>(_ type: T.Type) -> DiscontiguousColumnSlice<T> {
        DiscontiguousColumnSlice(column: _column.assumingType(T.self), set: _set)
    }

    public func isNil(at index: Int) -> Bool {
        _column.isNil(at: index)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(count)
        for i in _set.indices { _hashValue(_column[i], into: &hasher) }
    }

    /// The slice's elements as a column of their own.
    internal var _materialized: AnyColumn {
        _column._gathering(_set.indices)
    }
}

extension AnyColumnSlice: RandomAccessCollection, MutableCollection {
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

    public func index(_ i: Int, offsetBy distance: Int) -> Int {
        var index = i
        if distance >= 0 {
            for _ in 0 ..< distance { index = self.index(after: index) }
        } else {
            for _ in 0 ..< -distance { index = self.index(before: index) }
        }
        return index
    }

    public func distance(from start: Int, to end: Int) -> Int {
        if start <= end {
            return _set.intersection(start ..< end).count
        }
        return -_set.intersection(end ..< start).count
    }

    public subscript(position: Int) -> Any? {
        get { _column[position] }
        set { _column[position] = newValue }
    }

    public subscript(range: Range<Int>) -> AnyColumnSlice {
        get {
            AnyColumnSlice(column: _column, set: _set.intersection(range))
        }
        set {
            let destination = _set.intersection(range).indices
            precondition(destination.count == newValue.count, "Replacement must have the same count")
            for (i, element) in zip(destination, newValue) { _column[i] = element }
        }
    }

    public static func == (lhs: AnyColumnSlice, rhs: AnyColumnSlice) -> Bool {
        guard lhs.name == rhs.name, lhs.count == rhs.count, lhs.wrappedElementType == rhs.wrappedElementType else {
            return false
        }
        return zip(lhs._set.indices, rhs._set.indices).allSatisfy { _valuesEqual(lhs._column[$0], rhs._column[$1]) }
    }
}

extension AnyColumnSlice {
    public func distinct() -> AnyColumnSlice {
        AnyColumnSlice(column: _column, set: _RangeSet(sortedIndices: _distinctIndices(of: _column._box, indices: _set.indices)))
    }
}

@available(*, unavailable)
extension AnyColumn: Sendable {}

@available(*, unavailable)
extension AnyColumnSlice: Sendable {}

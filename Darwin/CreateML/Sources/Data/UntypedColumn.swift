import Foundation

// MLUntypedColumn: a column of values of any one type, which carries the
// error of the operation that made it, if one failed.

@available(macOS 10.14, iOS 15.0, tvOS 16.0, *)
public struct MLUntypedColumn {
    @usableFromInline
    var _result: _ResultType<_UntypedColumn>

    @usableFromInline
    init(result: _ResultType<_UntypedColumn>) {
        _result = result
    }

    @usableFromInline
    init(impl: CMLColumn) {
        _result = .success(_UntypedColumn(impl: impl))
    }

    @usableFromInline
    init(error: any Error) {
        _result = .failure(error)
    }

    /// The column's storage, if it's valid.
    @usableFromInline
    var underlyingColumn: _UntypedColumn? { _result.value }

    /// The column's values, none if it's invalid.
    var values: [MLDataValue] { underlyingColumn?._impl.values ?? [] }

    /// The column's storage type.
    var storageType: CMLFeatureValueType { underlyingColumn?._impl.type ?? .undefined }

    /// A column of values of a type.
    init(values: [MLDataValue], type: CMLFeatureValueType) {
        self.init(impl: CMLColumn(values: values, type: type))
    }

    /// A column made by an operation on this one's storage, or this one's
    /// error.
    func derived(_ body: (CMLColumn) throws -> CMLColumn) -> MLUntypedColumn {
        MLUntypedColumn(result: unaryDo(_result) { _UntypedColumn(impl: try body($0._impl)) })
    }

    public var count: Int { underlyingColumn?.count ?? 0 }
    public var isEmpty: Bool { count == 0 }
    public var type: MLDataValue.ValueType { underlyingColumn?.type ?? .invalid }
    public var error: (any Error)? { _result.error }
    public var isValid: Bool { error == nil }

    /// The column as a column of a type, if its values are of that type.
    public func column<T>(type: T.Type) -> MLDataColumn<T>? where T: MLDataValueConvertible {
        guard isValid else { return MLDataColumn(from: self) }
        guard storageType == CMLFeatureValueType(T.dataValueType) || storageType == .undefined else { return nil }
        return MLDataColumn(from: self)
    }

    public var ints: MLDataColumn<Int>? { column(type: Int.self) }
    public var doubles: MLDataColumn<Double>? { column(type: Double.self) }
    public var strings: MLDataColumn<String>? { column(type: String.self) }
    public var sequences: MLDataColumn<MLDataValue.SequenceType>? { column(type: MLDataValue.SequenceType.self) }
    public var dictionaries: MLDataColumn<MLDataValue.DictionaryType>? { column(type: MLDataValue.DictionaryType.self) }
    public var multiArrays: MLDataColumn<MLDataValue.MultiArrayType>? { column(type: MLDataValue.MultiArrayType.self) }

    public init<S>(_ source: S) where S: Sequence, S.Element == MLDataValue {
        self.init(impl: CMLColumn(values: Array(source)))
    }

    public init<S>(_ source: S) where S: Sequence, S.Element: MLDataValueConvertible {
        self.init(impl: CMLColumn(values: source.map(\.dataValue), type: CMLFeatureValueType(S.Element.dataValueType)))
    }

    public init(repeating repeatedValue: MLDataValue, count: Int) {
        self.init(result: .success(_UntypedColumn(repeating: repeatedValue, count: count)))
    }

    public init<T>(repeating repeatedValue: T, count: Int) where T: MLDataValueConvertible {
        self.init(result: .success(_UntypedColumn(repeating: repeatedValue, count: count)))
    }

    public init(_ range: Range<Int>) {
        self.init(result: .success(_UntypedColumn(range)))
    }

    public init(_ range: ClosedRange<Int>) {
        self.init(result: .success(_UntypedColumn(range)))
    }

    public init() {
        self.init(impl: CMLColumn(values: [], type: .undefined))
    }

    public mutating func append(contentsOf newColumn: MLUntypedColumn) {
        _result = binaryDo(_result, newColumn._result) { try $0.appending(contentsOf: $1) }
    }
}

@available(*, unavailable)
extension MLUntypedColumn: Sendable {}

// Operators, element by element.

extension MLUntypedColumn {
    func combined(_ other: MLUntypedColumn, _ operation: ValueOperation) -> MLUntypedColumn {
        MLUntypedColumn(result: binaryDo(_result, other._result) {
            _UntypedColumn(impl: try CMLColumn.combine($0._impl, $1._impl, operation))
        })
    }

    func combined(_ value: any MLDataValueConvertible, _ operation: ValueOperation) -> MLUntypedColumn {
        derived { CMLColumn.combine($0, value.dataValue, operation) }
    }

    func combined(left value: any MLDataValueConvertible, _ operation: ValueOperation) -> MLUntypedColumn {
        derived { CMLColumn.combine(value.dataValue, $0, operation) }
    }

    public static func == (a: MLUntypedColumn, b: any MLDataValueConvertible) -> MLUntypedColumn { a.combined(b, .equal) }
    public static func != (a: MLUntypedColumn, b: any MLDataValueConvertible) -> MLUntypedColumn { a.combined(b, .notEqual) }
    public static func > (a: MLUntypedColumn, b: any MLDataValueConvertible) -> MLUntypedColumn { a.combined(b, .greater) }
    public static func < (a: MLUntypedColumn, b: any MLDataValueConvertible) -> MLUntypedColumn { a.combined(b, .less) }
    public static func >= (a: MLUntypedColumn, b: any MLDataValueConvertible) -> MLUntypedColumn { a.combined(b, .greaterOrEqual) }
    public static func <= (a: MLUntypedColumn, b: any MLDataValueConvertible) -> MLUntypedColumn { a.combined(b, .lessOrEqual) }
    public static func + (a: MLUntypedColumn, b: any MLDataValueConvertible) -> MLUntypedColumn { a.combined(b, .add) }
    public static func - (a: MLUntypedColumn, b: any MLDataValueConvertible) -> MLUntypedColumn { a.combined(b, .subtract) }
    public static func * (a: MLUntypedColumn, b: any MLDataValueConvertible) -> MLUntypedColumn { a.combined(b, .multiply) }
    public static func / (a: MLUntypedColumn, b: any MLDataValueConvertible) -> MLUntypedColumn { a.combined(b, .divide) }

    public static func == (a: any MLDataValueConvertible, b: MLUntypedColumn) -> MLUntypedColumn { b.combined(left: a, .equal) }
    public static func != (a: any MLDataValueConvertible, b: MLUntypedColumn) -> MLUntypedColumn { b.combined(left: a, .notEqual) }
    public static func > (a: any MLDataValueConvertible, b: MLUntypedColumn) -> MLUntypedColumn { b.combined(left: a, .greater) }
    public static func < (a: any MLDataValueConvertible, b: MLUntypedColumn) -> MLUntypedColumn { b.combined(left: a, .less) }
    public static func >= (a: any MLDataValueConvertible, b: MLUntypedColumn) -> MLUntypedColumn { b.combined(left: a, .greaterOrEqual) }
    public static func <= (a: any MLDataValueConvertible, b: MLUntypedColumn) -> MLUntypedColumn { b.combined(left: a, .lessOrEqual) }
    public static func + (a: any MLDataValueConvertible, b: MLUntypedColumn) -> MLUntypedColumn { b.combined(left: a, .add) }
    public static func - (a: any MLDataValueConvertible, b: MLUntypedColumn) -> MLUntypedColumn { b.combined(left: a, .subtract) }
    public static func * (a: any MLDataValueConvertible, b: MLUntypedColumn) -> MLUntypedColumn { b.combined(left: a, .multiply) }
    public static func / (a: any MLDataValueConvertible, b: MLUntypedColumn) -> MLUntypedColumn { b.combined(left: a, .divide) }

    public static func == (a: MLUntypedColumn, b: MLUntypedColumn) -> MLUntypedColumn { a.combined(b, .equal) }
    public static func != (a: MLUntypedColumn, b: MLUntypedColumn) -> MLUntypedColumn { a.combined(b, .notEqual) }
    public static func > (a: MLUntypedColumn, b: MLUntypedColumn) -> MLUntypedColumn { a.combined(b, .greater) }
    public static func < (a: MLUntypedColumn, b: MLUntypedColumn) -> MLUntypedColumn { a.combined(b, .less) }
    public static func >= (a: MLUntypedColumn, b: MLUntypedColumn) -> MLUntypedColumn { a.combined(b, .greaterOrEqual) }
    public static func <= (a: MLUntypedColumn, b: MLUntypedColumn) -> MLUntypedColumn { a.combined(b, .lessOrEqual) }
    public static func && (a: MLUntypedColumn, b: MLUntypedColumn) -> MLUntypedColumn { a.combined(b, .and) }
    public static func || (a: MLUntypedColumn, b: MLUntypedColumn) -> MLUntypedColumn { a.combined(b, .or) }
    public static func + (a: MLUntypedColumn, b: MLUntypedColumn) -> MLUntypedColumn { a.combined(b, .add) }
    public static func - (a: MLUntypedColumn, b: MLUntypedColumn) -> MLUntypedColumn { a.combined(b, .subtract) }
    public static func * (a: MLUntypedColumn, b: MLUntypedColumn) -> MLUntypedColumn { a.combined(b, .multiply) }
    public static func / (a: MLUntypedColumn, b: MLUntypedColumn) -> MLUntypedColumn { a.combined(b, .divide) }
}

// Transformations.

extension MLUntypedColumn {
    public subscript(mask: MLUntypedColumn) -> MLUntypedColumn {
        MLUntypedColumn(result: binaryDo(_result, mask._result) { try $0.filter($1) })
    }

    public subscript(mask: MLDataColumn<Bool>) -> MLUntypedColumn {
        self[mask._untypedColumn]
    }

    /// The values a transform makes of the present ones; missing ones,
    /// and those it makes nil of, are missing.
    public func map<T>(_ lazyTransform: @escaping (MLDataValue) -> T?) -> MLDataColumn<T> where T: MLDataValueConvertible {
        MLDataColumn(from: derived { column in
            CMLColumn(values: column.values.map { $0.isValid ? (lazyTransform($0)?.dataValue ?? .invalid) : .invalid },
                      type: CMLFeatureValueType(T.dataValueType))
        })
    }

    public func map<T>(_ lazyTransform: @escaping (MLDataValue) -> T) -> MLDataColumn<T> where T: MLDataValueConvertible {
        MLDataColumn(from: derived { column in
            CMLColumn(values: column.values.map { $0.isValid ? lazyTransform($0).dataValue : .invalid },
                      type: CMLFeatureValueType(T.dataValueType))
        })
    }

    /// The values a transform makes of all of them, missing ones included.
    public func mapMissing<T>(_ lazyTransform: @escaping (MLDataValue) -> T?) -> MLDataColumn<T> where T: MLDataValueConvertible {
        MLDataColumn(from: derived { column in
            CMLColumn(values: column.values.map { lazyTransform($0)?.dataValue ?? .invalid },
                      type: CMLFeatureValueType(T.dataValueType))
        })
    }

    /// The values converted to a type; those that don't convert are
    /// missing.
    public func map<T>(to type: T.Type) -> MLDataColumn<T> where T: MLDataValueConvertible {
        MLDataColumn(from: derived { try $0.toType(CMLFeatureValueType(T.dataValueType)) })
    }

    public func dropMissing() -> MLUntypedColumn { derived { try $0.dropMissingValues() } }

    public func fillMissing(with value: MLDataValue) -> MLUntypedColumn {
        derived { try $0.fillMissing(with: CMLFeatureValue(value: value)) }
    }

    public func dropDuplicates() -> MLUntypedColumn { derived { try $0.dropDuplicates() } }

    public func prefix(_ maxLength: Int = 10) -> MLUntypedColumn {
        derived { try $0.prefix(UInt64(Swift.max(maxLength, 0))) }
    }

    public func suffix(_ maxLength: Int = 10) -> MLUntypedColumn {
        derived { try $0.suffix(UInt64(Swift.max(maxLength, 0))) }
    }

    /// The values sorted, missing ones last.
    public func sort(byIncreasingOrder: Bool = true) -> MLUntypedColumn {
        derived { column in
            let present = column.values.filter(\.isValid).sorted {
                $0.compare($1) == (byIncreasingOrder ? .orderedAscending : .orderedDescending)
            }
            return CMLColumn(values: present + column.values.filter { !$0.isValid }, type: column.type)
        }
    }

    public func copy() -> MLUntypedColumn { derived { CMLColumn(values: $0.values, type: $0.type) } }

    public func materialize() throws -> MLUntypedColumn {
        try underlyingColumn?.materialize()
        if let error { throw error }
        return self
    }
}

extension MLUntypedColumn {
    public init(ints: MLUntypedColumn) { self = ints.derived { try $0.toType(.int64) } }
    public init(doubles: MLUntypedColumn) { self = doubles.derived { try $0.toType(.double) } }
    public init(strings: MLUntypedColumn) { self = strings.derived { try $0.toType(.string) } }
    public init(sequences: MLUntypedColumn) { self = sequences.derived { try $0.toType(.sequence) } }
    public init(dictionaries: MLUntypedColumn) { self = dictionaries.derived { try $0.toType(.dictionary) } }
    public init(multiArrays: MLUntypedColumn) { self = multiArrays.derived { try $0.toType(.multiArray) } }
}

extension MLUntypedColumn {
    /// The value at an index; missing if it's out of the column.
    public subscript(index: Int) -> MLDataValue {
        underlyingColumn?.valueAtIndex(index: index) ?? .invalid
    }
}

extension MLUntypedColumn {
    public subscript(slice: Range<Int>) -> MLUntypedColumn {
        derived { column in
            let range = slice.clamped(to: 0..<column.size)
            return CMLColumn(values: Array(column.values[range]), type: column.type)
        }
    }

    public subscript<R>(slice: R) -> MLUntypedColumn where R: RangeExpression, R.Bound == Int {
        self[slice.relative(to: 0..<count)]
    }
}

extension Array where Element == MLDataValue {
    public init(_ untypedColumn: MLUntypedColumn) {
        self = untypedColumn.values
    }
}

extension MLUntypedColumn {
    public func show() -> any MLStreamingVisualizable {
        TextVisualization(text: description)
    }
}

extension MLUntypedColumn: CustomReflectable {
    public var customMirror: Mirror {
        Mirror(self, unlabeledChildren: values, displayStyle: .collection)
    }
}

extension MLUntypedColumn: CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
    public var description: String {
        if let error { return "Invalid column: \(error)" }
        return describeColumn(values, type: type)
    }

    public var debugDescription: String { description }
    public var playgroundDescription: Any { description }
}

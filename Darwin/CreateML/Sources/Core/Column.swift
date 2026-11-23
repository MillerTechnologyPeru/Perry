import Foundation

// The storage of a column: its values and their type, and the operations
// columns have, element by element. CMLColumn and _UntypedColumn are the
// names the Swift 5.0 overlay gave the column of its C engine and the
// class over it; Perry's keep the values in an array.

/// Arithmetic, comparison and logic on values, as columns do it: a missing
/// value makes a missing result, integers stay integers unless a double
/// joins them, strings concatenate with +, and comparisons and logic make
/// integers 0 and 1.
enum ValueOperation: Hashable {
    case add, subtract, multiply, divide
    case equal, notEqual, less, greater, lessOrEqual, greaterOrEqual
    case and, or

    func apply(_ a: MLDataValue, _ b: MLDataValue) -> MLDataValue {
        guard a.isValid, b.isValid else { return .invalid }
        switch self {
        case .add, .subtract, .multiply, .divide:
            if case .string(let x) = a, case .string(let y) = b, self == .add { return .string(x + y) }
            if case .int(let x) = a, case .int(let y) = b {
                switch self {
                case .add: return .int(x &+ y)
                case .subtract: return .int(x &- y)
                case .multiply: return .int(x &* y)
                default: return y == 0 ? .invalid : .int(x / y)
                }
            }
            guard let x = a.number, let y = b.number else { return .invalid }
            switch self {
            case .add: return .double(x + y)
            case .subtract: return .double(x - y)
            case .multiply: return .double(x * y)
            default: return .double(x / y)
            }
        case .equal: return .int(a.equals(b) ? 1 : 0)
        case .notEqual: return .int(a.equals(b) ? 0 : 1)
        case .less: return .int(a.compare(b) == .orderedAscending ? 1 : 0)
        case .greater: return .int(a.compare(b) == .orderedDescending ? 1 : 0)
        case .lessOrEqual: return .int(a.compare(b) != .orderedDescending ? 1 : 0)
        case .greaterOrEqual: return .int(a.compare(b) != .orderedAscending ? 1 : 0)
        case .and: return .int(a.isTrue && b.isTrue ? 1 : 0)
        case .or: return .int(a.isTrue || b.isTrue ? 1 : 0)
        }
    }

    /// The type of the results on values of two types.
    func resultType(_ a: CMLFeatureValueType, _ b: CMLFeatureValueType) -> CMLFeatureValueType {
        switch self {
        case .add, .subtract, .multiply, .divide:
            if a == .int64 && b == .int64 { return .int64 }
            if a == .string && b == .string && self == .add { return .string }
            return .double
        default:
            return .int64
        }
    }
}

extension MLDataValue {
    /// The value as a number, if it is one.
    var number: Double? {
        switch self {
        case .int(let value): return Double(value)
        case .double(let value): return value
        default: return nil
        }
    }

    /// Whether the value is true as a mask's element: a nonzero number.
    var isTrue: Bool {
        guard let number else { return false }
        return number != 0 && !number.isNaN
    }

    /// Equality that takes an integer and a double of the same value as
    /// equal.
    func equals(_ other: MLDataValue) -> Bool {
        if let x = number, let y = other.number { return x == y }
        return self == other
    }

    /// The order columns sort in: missing values last, numbers by value,
    /// strings by their characters, other values by their descriptions.
    func compare(_ other: MLDataValue) -> ComparisonResult {
        switch (isValid, other.isValid) {
        case (false, false): return .orderedSame
        case (false, true): return .orderedDescending
        case (true, false): return .orderedAscending
        default: break
        }
        if let x = number, let y = other.number {
            return x < y ? .orderedAscending : x > y ? .orderedDescending : .orderedSame
        }
        let x = stringValue ?? description, y = other.stringValue ?? other.description
        return x < y ? .orderedAscending : x > y ? .orderedDescending : .orderedSame
    }

    /// The value converted to a type, or missing if it doesn't convert.
    func converted(to type: CMLFeatureValueType) -> MLDataValue {
        guard isValid else { return .invalid }
        switch (type, self) {
        case (.int64, .int), (.double, .double), (.string, .string), (.sequence, .sequence),
             (.dictionary, .dictionary), (.multiArray, .multiArray):
            return self
        case (.int64, .double(let value)):
            return value.isFinite ? .int(Int(value)) : .invalid
        case (.int64, .string(let value)):
            return Int(value.trimmingCharacters(in: .whitespaces)).map(MLDataValue.int) ?? .invalid
        case (.double, .int(let value)):
            return .double(Double(value))
        case (.double, .string(let value)):
            return Double(value.trimmingCharacters(in: .whitespaces)).map(MLDataValue.double) ?? .invalid
        case (.string, _):
            return .string(description)
        case (.sequence, .multiArray(let value)):
            return .sequence(MLDataValue.SequenceType(value.elements))
        case (.undefined, _):
            return self
        default:
            return .invalid
        }
    }
}

/// The type a column of values has: the type of its values, or Double for
/// integers and doubles mixed.
func inferredType<S: Sequence>(of values: S) -> CMLFeatureValueType where S.Element == MLDataValue {
    var type: CMLFeatureValueType = .undefined
    for value in values where value.isValid {
        let next = CMLFeatureValueType(value.type)
        if type == .undefined {
            type = next
        } else if type != next {
            if Set([type, next]) == [.int64, .double] { type = .double } else { return .string }
        }
    }
    return type
}

/// A column's values and type.
@usableFromInline
final class CMLColumn {
    var values: [MLDataValue]
    private let valueType: CMLFeatureValueType

    /// A column of values of a type, which those not of it are converted
    /// to.
    init(values: [MLDataValue], type: CMLFeatureValueType) {
        self.valueType = type
        if type == .undefined {
            self.values = values
        } else {
            self.values = values.map { $0.isValid && CMLFeatureValueType($0.type) != type ? $0.converted(to: type) : $0 }
        }
    }

    /// A column of values, of the type they have.
    convenience init(values: [MLDataValue]) {
        self.init(values: values, type: inferredType(of: values))
    }

    @usableFromInline
    convenience init(_ sequence: CMLSequence) throws {
        self.init(values: sequence.values)
    }

    @usableFromInline
    convenience init(_ sequence: CMLSequence, type: CMLFeatureValueType) throws {
        self.init(values: sequence.values, type: type)
    }

    @usableFromInline
    convenience init(_ range: Range<Int>) throws {
        self.init(values: range.map(MLDataValue.int), type: .int64)
    }

    @usableFromInline
    convenience init(repeating value: CMLFeatureValue, count: Int) throws {
        guard count >= 0 else { throw MLCreateError.generic(reason: "A column can't have \(count) values.") }
        self.init(values: Array(repeating: value.value, count: count), type: value.type)
    }

    @usableFromInline
    convenience init(concatenating first: CMLColumn, and second: CMLColumn) throws {
        let type: CMLFeatureValueType
        switch (first.type, second.type) {
        case let (a, b) where a == b: type = a
        case (.undefined, let b) where first.size == 0 || first.values.allSatisfy({ !$0.isValid }): type = b
        case (let a, .undefined): type = a
        case (.int64, .double), (.double, .int64): type = .double
        default:
            throw MLCreateError.type(reason: "A column of \(first.type.valueType) values can't be joined with one of \(second.type.valueType) values.")
        }
        self.init(values: first.values + second.values, type: type)
    }

    @usableFromInline var size: Int { values.count }
    @usableFromInline var type: CMLFeatureValueType { valueType }

    @usableFromInline
    func value(at index: Int) throws -> CMLFeatureValue {
        guard values.indices.contains(index) else {
            throw MLCreateError.generic(reason: "Index \(index) is out of the column's range 0..<\(values.count).")
        }
        return CMLFeatureValue(value: values[index])
    }

    /// The column's values, described as a string value.
    @usableFromInline
    func description() throws -> CMLFeatureValue {
        CMLFeatureValue(value: .string(describeColumn(values, type: type.valueType)))
    }

    /// Lazy columns compute their values when read; this one has them.
    @usableFromInline
    func materialize() throws {}

    @usableFromInline
    func fillMissing(with value: CMLFeatureValue) throws -> CMLColumn {
        CMLColumn(values: values.map { $0.isValid ? $0 : value.value }, type: type == .undefined ? value.type : type)
    }

    @usableFromInline
    func dropMissingValues() throws -> CMLColumn {
        CMLColumn(values: values.filter(\.isValid), type: type)
    }

    @usableFromInline
    func dropDuplicates() throws -> CMLColumn {
        var seen = Set<MLDataValue>()
        return CMLColumn(values: values.filter { seen.insert($0).inserted }, type: type)
    }

    @usableFromInline
    func prefix(_ count: UInt64) throws -> CMLColumn {
        CMLColumn(values: Array(values.prefix(Int(clamping: count))), type: type)
    }

    @usableFromInline
    func suffix(_ count: UInt64) throws -> CMLColumn {
        CMLColumn(values: Array(values.suffix(Int(clamping: count))), type: type)
    }

    @usableFromInline
    func toType(_ type: CMLFeatureValueType) throws -> CMLColumn {
        CMLColumn(values: values.map { $0.converted(to: type) }, type: type)
    }

    /// The values a mask's true elements select.
    @usableFromInline
    func apply(mask: CMLColumn) throws -> CMLColumn {
        guard mask.size == size else {
            throw MLCreateError.generic(reason: "A mask of \(mask.size) values can't filter a column of \(size).")
        }
        return CMLColumn(values: zip(values, mask.values).filter { $0.1.isTrue }.map(\.0), type: type)
    }

    @usableFromInline
    func apply(transform: @escaping (CMLFeatureValue) -> CMLFeatureValue, type: CMLFeatureValueType, skipUndefined: Bool) throws -> CMLColumn {
        CMLColumn(values: values.map { value in
            skipUndefined && !value.isValid ? .invalid : transform(CMLFeatureValue(value: value)).value
        }, type: type)
    }

    /// The numbers of the column, or an error if it isn't numeric.
    private func numbers() throws -> [Double] {
        guard type == .int64 || type == .double || type == .undefined else {
            throw MLCreateError.type(reason: "A column of \(type.valueType) values has no numeric summary.")
        }
        return values.compactMap(\.number)
    }

    @usableFromInline
    func sum() throws -> CMLFeatureValue {
        if type == .int64 { return CMLFeatureValue(value: .int(values.compactMap(\.intValue).reduce(0, &+))) }
        return CMLFeatureValue(value: .double(try numbers().reduce(0, +)))
    }

    @usableFromInline
    func min() throws -> CMLFeatureValue {
        if type != .int64 && type != .double && type != .undefined {
            return CMLFeatureValue(value: values.filter(\.isValid).min { $0.compare($1) == .orderedAscending } ?? .invalid)
        }
        _ = try numbers()
        return CMLFeatureValue(value: values.filter(\.isValid).min { $0.compare($1) == .orderedAscending } ?? .invalid)
    }

    @usableFromInline
    func max() throws -> CMLFeatureValue {
        if type != .int64 && type != .double && type != .undefined {
            return CMLFeatureValue(value: values.filter(\.isValid).max { $0.compare($1) == .orderedAscending } ?? .invalid)
        }
        _ = try numbers()
        return CMLFeatureValue(value: values.filter(\.isValid).max { $0.compare($1) == .orderedAscending } ?? .invalid)
    }

    @usableFromInline
    func mean() throws -> CMLFeatureValue {
        let numbers = try numbers()
        guard !numbers.isEmpty else { return CMLFeatureValue() }
        return CMLFeatureValue(value: .double(numbers.reduce(0, +) / Double(numbers.count)))
    }

    /// The population standard deviation.
    @usableFromInline
    func std() throws -> CMLFeatureValue {
        let numbers = try numbers()
        guard !numbers.isEmpty else { return CMLFeatureValue() }
        let mean = numbers.reduce(0, +) / Double(numbers.count)
        let variance = numbers.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(numbers.count)
        return CMLFeatureValue(value: .double(variance.squareRoot()))
    }

    // Element-by-element operations.

    static func combine(_ a: CMLColumn, _ b: CMLColumn, _ operation: ValueOperation) throws -> CMLColumn {
        guard a.size == b.size else {
            throw MLCreateError.generic(reason: "Columns of \(a.size) and \(b.size) values can't be combined.")
        }
        return CMLColumn(values: zip(a.values, b.values).map { operation.apply($0, $1) },
                         type: operation.resultType(a.type, b.type))
    }

    static func combine(_ a: CMLColumn, _ b: MLDataValue, _ operation: ValueOperation) -> CMLColumn {
        CMLColumn(values: a.values.map { operation.apply($0, b) },
                  type: operation.resultType(a.type, CMLFeatureValueType(b.type)))
    }

    static func combine(_ a: MLDataValue, _ b: CMLColumn, _ operation: ValueOperation) -> CMLColumn {
        CMLColumn(values: b.values.map { operation.apply(a, $0) },
                  type: operation.resultType(CMLFeatureValueType(a.type), b.type))
    }

    @usableFromInline static func + (a: CMLColumn, b: CMLColumn) throws -> CMLColumn { try combine(a, b, .add) }
    @usableFromInline static func - (a: CMLColumn, b: CMLColumn) throws -> CMLColumn { try combine(a, b, .subtract) }
    @usableFromInline static func * (a: CMLColumn, b: CMLColumn) throws -> CMLColumn { try combine(a, b, .multiply) }
    @usableFromInline static func / (a: CMLColumn, b: CMLColumn) throws -> CMLColumn { try combine(a, b, .divide) }
    @usableFromInline static func == (a: CMLColumn, b: CMLColumn) throws -> CMLColumn { try combine(a, b, .equal) }
    @usableFromInline static func != (a: CMLColumn, b: CMLColumn) throws -> CMLColumn { try combine(a, b, .notEqual) }
    @usableFromInline static func < (a: CMLColumn, b: CMLColumn) throws -> CMLColumn { try combine(a, b, .less) }
    @usableFromInline static func > (a: CMLColumn, b: CMLColumn) throws -> CMLColumn { try combine(a, b, .greater) }
    @usableFromInline static func <= (a: CMLColumn, b: CMLColumn) throws -> CMLColumn { try combine(a, b, .lessOrEqual) }
    @usableFromInline static func >= (a: CMLColumn, b: CMLColumn) throws -> CMLColumn { try combine(a, b, .greaterOrEqual) }
    @usableFromInline static func && (a: CMLColumn, b: CMLColumn) throws -> CMLColumn { try combine(a, b, .and) }
    @usableFromInline static func || (a: CMLColumn, b: CMLColumn) throws -> CMLColumn { try combine(a, b, .or) }

    @usableFromInline static func + (a: CMLColumn, b: CMLFeatureValue) throws -> CMLColumn { combine(a, b.value, .add) }
    @usableFromInline static func - (a: CMLColumn, b: CMLFeatureValue) throws -> CMLColumn { combine(a, b.value, .subtract) }
    @usableFromInline static func * (a: CMLColumn, b: CMLFeatureValue) throws -> CMLColumn { combine(a, b.value, .multiply) }
    @usableFromInline static func / (a: CMLColumn, b: CMLFeatureValue) throws -> CMLColumn { combine(a, b.value, .divide) }
    @usableFromInline static func == (a: CMLColumn, b: CMLFeatureValue) throws -> CMLColumn { combine(a, b.value, .equal) }
    @usableFromInline static func != (a: CMLColumn, b: CMLFeatureValue) throws -> CMLColumn { combine(a, b.value, .notEqual) }
    @usableFromInline static func < (a: CMLColumn, b: CMLFeatureValue) throws -> CMLColumn { combine(a, b.value, .less) }
    @usableFromInline static func > (a: CMLColumn, b: CMLFeatureValue) throws -> CMLColumn { combine(a, b.value, .greater) }
    @usableFromInline static func <= (a: CMLColumn, b: CMLFeatureValue) throws -> CMLColumn { combine(a, b.value, .lessOrEqual) }
    @usableFromInline static func >= (a: CMLColumn, b: CMLFeatureValue) throws -> CMLColumn { combine(a, b.value, .greaterOrEqual) }

    @usableFromInline static func + (a: CMLFeatureValue, b: CMLColumn) throws -> CMLColumn { combine(a.value, b, .add) }
    @usableFromInline static func - (a: CMLFeatureValue, b: CMLColumn) throws -> CMLColumn { combine(a.value, b, .subtract) }
    @usableFromInline static func * (a: CMLFeatureValue, b: CMLColumn) throws -> CMLColumn { combine(a.value, b, .multiply) }
    @usableFromInline static func / (a: CMLFeatureValue, b: CMLColumn) throws -> CMLColumn { combine(a.value, b, .divide) }
    @usableFromInline static func == (a: CMLFeatureValue, b: CMLColumn) throws -> CMLColumn { combine(a.value, b, .equal) }
    @usableFromInline static func != (a: CMLFeatureValue, b: CMLColumn) throws -> CMLColumn { combine(a.value, b, .notEqual) }
    @usableFromInline static func < (a: CMLFeatureValue, b: CMLColumn) throws -> CMLColumn { combine(a.value, b, .less) }
    @usableFromInline static func > (a: CMLFeatureValue, b: CMLColumn) throws -> CMLColumn { combine(a.value, b, .greater) }
    @usableFromInline static func <= (a: CMLFeatureValue, b: CMLColumn) throws -> CMLColumn { combine(a.value, b, .lessOrEqual) }
    @usableFromInline static func >= (a: CMLFeatureValue, b: CMLColumn) throws -> CMLColumn { combine(a.value, b, .greaterOrEqual) }
}

/// The class an untyped column keeps its storage in.
@usableFromInline @_fixed_layout
class _UntypedColumn: CustomStringConvertible, CustomDebugStringConvertible {
    @usableFromInline
    let _impl: CMLColumn

    @usableFromInline
    init(impl: CMLColumn) {
        _impl = impl
    }

    @usableFromInline
    init<S>(_ source: S) throws where S: Sequence, S.Element == MLDataValue {
        _impl = CMLColumn(values: Array(source))
    }

    @usableFromInline
    init<S>(_ source: S) throws where S: Sequence, S.Element: MLDataValueConvertible {
        _impl = CMLColumn(values: source.map(\.dataValue), type: CMLFeatureValueType(S.Element.dataValueType))
    }

    @usableFromInline
    init(repeating value: MLDataValue, count: Int) {
        _impl = CMLColumn(values: Array(repeating: value, count: Swift.max(count, 0)), type: CMLFeatureValueType(value.type))
    }

    @usableFromInline
    init<T>(repeating value: T, count: Int) where T: MLDataValueConvertible {
        _impl = CMLColumn(values: Array(repeating: value.dataValue, count: Swift.max(count, 0)),
                                  type: CMLFeatureValueType(T.dataValueType))
    }

    @usableFromInline
    init(_ range: Range<Int>) {
        _impl = CMLColumn(values: range.map(MLDataValue.int), type: .int64)
    }

    @usableFromInline
    init(_ range: ClosedRange<Int>) {
        _impl = CMLColumn(values: range.map(MLDataValue.int), type: .int64)
    }

    /// The operations untyped columns have.
    @usableFromInline
    enum MathOp: Hashable {
        case add, subtract, multiply, divide
        case equal, notEqual, less, greater, lessOrEqual, greaterOrEqual
        case and, or

        var operation: ValueOperation {
            switch self {
            case .add: return .add
            case .subtract: return .subtract
            case .multiply: return .multiply
            case .divide: return .divide
            case .equal: return .equal
            case .notEqual: return .notEqual
            case .less: return .less
            case .greater: return .greater
            case .lessOrEqual: return .lessOrEqual
            case .greaterOrEqual: return .greaterOrEqual
            case .and: return .and
            case .or: return .or
            }
        }
    }

    @usableFromInline
    static func perform(op: MathOp, a: _UntypedColumn, b: _UntypedColumn) throws -> _UntypedColumn {
        _UntypedColumn(impl: try CMLColumn.combine(a._impl, b._impl, op.operation))
    }

    @usableFromInline
    static func performLeftScalar(op: MathOp, a: MLDataValue, b: _UntypedColumn) throws -> _UntypedColumn {
        _UntypedColumn(impl: CMLColumn.combine(a, b._impl, op.operation))
    }

    @usableFromInline
    static func performRightScalar(op: MathOp, a: _UntypedColumn, b: MLDataValue) throws -> _UntypedColumn {
        _UntypedColumn(impl: CMLColumn.combine(a._impl, b, op.operation))
    }

    @usableFromInline var count: Int { _impl.size }
    @usableFromInline var type: MLDataValue.ValueType { _impl.type.valueType }

    @usableFromInline
    func valueAtIndex(index: Int) -> MLDataValue {
        _impl.values.indices.contains(index) ? _impl.values[index] : .invalid
    }

    @usableFromInline
    func appending(contentsOf other: _UntypedColumn) throws -> _UntypedColumn {
        _UntypedColumn(impl: try CMLColumn(concatenating: _impl, and: other._impl))
    }

    @usableFromInline
    func filter(_ mask: _UntypedColumn) throws -> _UntypedColumn {
        _UntypedColumn(impl: try _impl.apply(mask: mask._impl))
    }

    @usableFromInline
    func map(_ transform: @escaping (CMLFeatureValue) -> CMLFeatureValue, skipUndefined: Bool, outputType: MLDataValue.ValueType) -> _UntypedColumn {
        _UntypedColumn(impl: CMLColumn(values: _impl.values.map { value in
            skipUndefined && !value.isValid ? .invalid : transform(CMLFeatureValue(value: value)).value
        }, type: CMLFeatureValueType(outputType)))
    }

    @usableFromInline func dropMissingValues() throws -> _UntypedColumn { _UntypedColumn(impl: try _impl.dropMissingValues()) }
    @usableFromInline func dropDuplicates() throws -> _UntypedColumn { _UntypedColumn(impl: try _impl.dropDuplicates()) }
    @usableFromInline func fillMissing(with value: CMLFeatureValue) throws -> _UntypedColumn { _UntypedColumn(impl: try _impl.fillMissing(with: value)) }
    @usableFromInline func prefix(_ count: UInt64) throws -> _UntypedColumn { _UntypedColumn(impl: try _impl.prefix(count)) }
    @usableFromInline func suffix(_ count: UInt64) throws -> _UntypedColumn { _UntypedColumn(impl: try _impl.suffix(count)) }
    @usableFromInline func toType(_ type: CMLFeatureValueType) throws -> _UntypedColumn { _UntypedColumn(impl: try _impl.toType(type)) }
    @usableFromInline func materialize() throws { try _impl.materialize() }
    @usableFromInline func sum() throws -> CMLFeatureValue { try _impl.sum() }
    @usableFromInline func mean() throws -> CMLFeatureValue { try _impl.mean() }
    @usableFromInline func std() throws -> CMLFeatureValue { try _impl.std() }
    @usableFromInline func minimum() throws -> CMLFeatureValue { try _impl.min() }
    @usableFromInline func maximum() throws -> CMLFeatureValue { try _impl.max() }

    @usableFromInline
    var description: String { describeColumn(_impl.values, type: type) }

    @usableFromInline
    var debugDescription: String { "_UntypedColumn(\(type), \(count) values)" }
}

/// A column's values as CreateML shows them: its type, then its first
/// values one to a line.
func describeColumn(_ values: [MLDataValue], type: MLDataValue.ValueType, limit: Int = 10) -> String {
    var lines = ["\(type.description) column, \(values.count) value\(values.count == 1 ? "" : "s")"]
    for value in values.prefix(limit) { lines.append("  \(value)") }
    if values.count > limit { lines.append("  ...") }
    return lines.joined(separator: "\n")
}

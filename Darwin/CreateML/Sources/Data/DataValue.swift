import CoreML
import Foundation

// MLDataValue: the values of CreateML's tables and columns, and the Swift
// types that convert to and from them.

@available(macOS 10.14, iOS 15.0, tvOS 16.0, *)
public enum MLDataValue {
    case int(Int)
    case double(Double)
    case string(String)
    case sequence(MLDataValue.SequenceType)
    case dictionary(MLDataValue.DictionaryType)
    case multiArray(MLDataValue.MultiArrayType)
    case invalid

    public var type: MLDataValue.ValueType {
        switch self {
        case .int: return .int
        case .double: return .double
        case .string: return .string
        case .sequence: return .sequence
        case .dictionary: return .dictionary
        case .multiArray: return .multiArray
        case .invalid: return .invalid
        }
    }

    public var isValid: Bool {
        if case .invalid = self { return false }
        return true
    }

    public var intValue: Int? {
        if case .int(let value) = self { return value }
        return nil
    }

    public var doubleValue: Double? {
        if case .double(let value) = self { return value }
        return nil
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var sequenceValue: MLDataValue.SequenceType? {
        if case .sequence(let value) = self { return value }
        return nil
    }

    public var dictionaryValue: MLDataValue.DictionaryType? {
        if case .dictionary(let value) = self { return value }
        return nil
    }

    public var multiArrayValue: MLDataValue.MultiArrayType? {
        if case .multiArray(let value) = self { return value }
        return nil
    }

    /// An ordered sequence of values.
    public struct SequenceType {
        @usableFromInline
        var _contents: CMLSequence

        @usableFromInline
        init(_contents: CMLSequence) {
            self._contents = _contents
        }
    }

    /// Values by key.
    public struct DictionaryType {
        @usableFromInline
        var _contents: [MLDataValue: MLDataValue]

        @usableFromInline
        init(_contents: [MLDataValue: MLDataValue]) {
            self._contents = _contents
        }
    }

    /// A multi-dimensional array of numbers.
    public struct MultiArrayType {
        @usableFromInline
        var _contents: MLMultiArray

        @usableFromInline
        init(_contents: MLMultiArray) {
            self._contents = _contents
        }
    }

    /// The value as a feature value.
    @usableFromInline
    var featureValue: CMLFeatureValue { CMLFeatureValue(value: self) }

    @usableFromInline
    init(_ featureValue: CMLFeatureValue) {
        self = featureValue.value
    }

    /// The value an Objective-C or Swift object stands for: a number, a
    /// string, an array, a dictionary, a multi-array or another value.
    @usableFromInline
    init(fromAny any: Any) throws {
        switch any {
        case let value as MLDataValue: self = value
        case let value as any MLDataValueConvertible: self = value.dataValue
        case let value as NSNumber:
            let type = String(cString: value.objCType)
            self = ["f", "d"].contains(type) ? .double(value.doubleValue) : .int(value.intValue)
        case let value as NSString: self = .string(value as String)
        case let value as MLMultiArray: self = .multiArray(MultiArrayType(value))
        case let value as [Any]: self = .sequence(SequenceType(try value.map { try MLDataValue(fromAny: $0) }))
        case let value as [AnyHashable: Any]:
            var contents: [MLDataValue: MLDataValue] = [:]
            for (key, element) in value { contents[try MLDataValue(fromAny: key.base)] = try MLDataValue(fromAny: element) }
            self = .dictionary(DictionaryType(contents))
        case is NSNull: self = .invalid
        default:
            throw MLCreateError.type(reason: "A value of type \(Swift.type(of: any)) can't be a data value.")
        }
    }

    /// The value as a Swift value: a number, string, array or dictionary of
    /// them, or a multi-array; nil when it's missing.
    @usableFromInline
    func toAny() -> Any? {
        switch self {
        case .int(let value): return value
        case .double(let value): return value
        case .string(let value): return value
        case .sequence(let value): return value.map { $0.toAny() as Any }
        case .dictionary(let value):
            var result: [AnyHashable: Any] = [:]
            for (key, element) in value._contents {
                if let key = key.toAny() as? AnyHashable { result[key] = element.toAny() as Any }
            }
            return result
        case .multiArray(let value): return value._contents
        case .invalid: return nil
        }
    }
}

@available(*, unavailable)
extension MLDataValue: Sendable {}

@available(macOS 10.14, iOS 15.0, tvOS 16.0, *)
extension MLDataValue {
    public enum ValueType: Hashable {
        case int
        case double
        case string
        case sequence
        case dictionary
        case multiArray
        case invalid

        @usableFromInline
        var featureValueType: CMLFeatureValueType { CMLFeatureValueType(self) }

        @usableFromInline
        init(featureValueType: CMLFeatureValueType) {
            self = featureValueType.valueType
        }
    }
}

extension MLDataValue.ValueType: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        switch self {
        case .int: return "Int"
        case .double: return "Double"
        case .string: return "String"
        case .sequence: return "Sequence"
        case .dictionary: return "Dictionary"
        case .multiArray: return "MultiArray"
        case .invalid: return "Undefined"
        }
    }

    public var debugDescription: String { description }
}

extension MLDataValue: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        switch self {
        case .int(let value): return String(value)
        case .double(let value): return String(value)
        case .string(let value): return value
        case .sequence(let value): return value.description
        case .dictionary(let value): return value.description
        case .multiArray(let value): return value.description
        case .invalid: return "nil"
        }
    }

    /// The value as it's shown in a collection: strings quoted.
    public var debugDescription: String {
        if case .string(let value) = self { return String(reflecting: value) }
        return description
    }
}

extension MLDataValue: Hashable {
    public static func == (left: MLDataValue, right: MLDataValue) -> Bool {
        switch (left, right) {
        case (.int(let a), .int(let b)): return a == b
        case (.double(let a), .double(let b)): return a == b || (a.isNaN && b.isNaN)
        case (.string(let a), .string(let b)): return a == b
        case (.sequence(let a), .sequence(let b)): return a == b
        case (.dictionary(let a), .dictionary(let b)): return a == b
        case (.multiArray(let a), .multiArray(let b)): return a == b
        case (.invalid, .invalid): return true
        default: return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(type)
        switch self {
        case .int(let value): hasher.combine(value)
        case .double(let value): hasher.combine(value.isNaN ? .nan : value)
        case .string(let value): hasher.combine(value)
        case .sequence(let value):
            hasher.combine(value.count)
            for element in value { hasher.combine(element) }
        case .dictionary(let value):
            // Unordered: combine the pairs' hashes order-independently.
            hasher.combine(value._contents.reduce(0) { $0 ^ $1.key.hashValue &+ 31 &* $1.value.hashValue })
        case .multiArray(let value):
            hasher.combine(value._contents.shape)
        case .invalid:
            break
        }
    }
}

// Sequences.

extension MLDataValue.SequenceType {
    public init() {
        self.init(_contents: CMLSequence())
    }

    public init<S>(_ elements: S) where S: Sequence, S.Element == MLDataValue {
        self.init(_contents: CMLSequence(values: Array(elements)))
    }

    public init<S>(_ elements: S) where S: Sequence, S.Element: MLDataValueConvertible {
        self.init(_contents: CMLSequence(values: elements.map(\.dataValue)))
    }

    /// The values.
    var values: [MLDataValue] { _contents.values }

    @usableFromInline
    var featureValue: CMLFeatureValue { CMLFeatureValue(value: .sequence(self)) }

    @usableFromInline
    init?(from featureValue: CMLFeatureValue) {
        guard let sequence = featureValue.value.sequenceValue else { return nil }
        self = sequence
    }
}

@available(*, unavailable)
extension MLDataValue.SequenceType: Sendable {}

extension MLDataValue.SequenceType: RandomAccessCollection {
    public typealias Element = MLDataValue
    public typealias Index = Int

    public var startIndex: Index { 0 }
    public var endIndex: Index { _contents.values.count }

    public subscript(index: Index) -> Element {
        _contents.values[index]
    }

    public typealias Indices = Range<Index>
    public typealias Iterator = IndexingIterator<MLDataValue.SequenceType>
    public typealias SubSequence = Slice<MLDataValue.SequenceType>
}

extension MLDataValue.SequenceType: ExpressibleByArrayLiteral {
    public init(arrayLiteral: Element...) {
        self.init(arrayLiteral)
    }

    public typealias ArrayLiteralElement = Element
}

extension MLDataValue.SequenceType: Equatable {
    public static func == (lhs: MLDataValue.SequenceType, rhs: MLDataValue.SequenceType) -> Bool {
        lhs._contents === rhs._contents || lhs._contents.values == rhs._contents.values
    }
}

extension MLDataValue.SequenceType: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        "[" + values.map { $0.type == .string ? String(reflecting: $0.description) : $0.description }.joined(separator: ", ") + "]"
    }

    public var debugDescription: String { "MLDataValue.SequenceType(\(description))" }
}

extension MLDataValue.SequenceType: MLDataValueConvertible, FeatureValueConvertible {
    public static var dataValueType: MLDataValue.ValueType { .sequence }

    public init?(from dataValue: MLDataValue) {
        guard let sequence = dataValue.sequenceValue else { return nil }
        self = sequence
    }

    public var dataValue: MLDataValue { .sequence(self) }
}

extension Array: MLDataValueConvertible where Element: MLDataValueConvertible {
    public static var dataValueType: MLDataValue.ValueType { .sequence }

    /// The elements of a sequence, when all of them convert.
    public init?(from dataValue: MLDataValue) {
        guard let sequence = dataValue.sequenceValue else { return nil }
        var elements: [Element] = []
        elements.reserveCapacity(sequence.count)
        for value in sequence {
            guard let element = Element(from: value) else { return nil }
            elements.append(element)
        }
        self = elements
    }

    public var dataValue: MLDataValue { .sequence(MLDataValue.SequenceType(self)) }
}

// Dictionaries.

extension MLDataValue.DictionaryType {
    public typealias Key = MLDataValue
    public typealias Value = MLDataValue

    public init() {
        self.init(_contents: [:])
    }

    public init(_ contents: [MLDataValue: MLDataValue]) {
        self.init(_contents: contents)
    }

    public init<S>(uniqueKeysWithValues keysAndValues: S) where S: Sequence, S.Element == (MLDataValue, MLDataValue) {
        self.init(_contents: Dictionary(uniqueKeysWithValues: keysAndValues))
    }

    public var count: Int { _contents.count }
    public var isEmpty: Bool { _contents.isEmpty }

    public subscript(key: Key) -> Value? {
        _contents[key]
    }

    @usableFromInline
    var featureValue: CMLFeatureValue { CMLFeatureValue(value: .dictionary(self)) }

    @usableFromInline
    init?(from featureValue: CMLFeatureValue) {
        guard let dictionary = featureValue.value.dictionaryValue else { return nil }
        self = dictionary
    }
}

@available(*, unavailable)
extension MLDataValue.DictionaryType: Sendable {}

extension MLDataValue.DictionaryType: Collection {
    public struct Index: Comparable {
        let base: Dictionary<MLDataValue, MLDataValue>.Index

        public static func == (lhs: Index, rhs: Index) -> Bool { lhs.base == rhs.base }
        public static func < (lhs: Index, rhs: Index) -> Bool { lhs.base < rhs.base }
    }

    public typealias Element = (key: MLDataValue, value: MLDataValue)

    public var startIndex: Index { Index(base: _contents.startIndex) }
    public var endIndex: Index { Index(base: _contents.endIndex) }

    public subscript(index: Index) -> Element {
        _contents[index.base]
    }

    public func index(after i: Index) -> Index {
        Index(base: _contents.index(after: i.base))
    }

    public typealias Indices = DefaultIndices<MLDataValue.DictionaryType>
    public typealias Iterator = IndexingIterator<MLDataValue.DictionaryType>
    public typealias SubSequence = Slice<MLDataValue.DictionaryType>
}

extension MLDataValue.DictionaryType: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        if _contents.isEmpty { return "[:]" }
        func show(_ value: MLDataValue) -> String {
            value.type == .string ? String(reflecting: value.description) : value.description
        }
        return "[" + _contents.map { "\(show($0.key)): \(show($0.value))" }.sorted().joined(separator: ", ") + "]"
    }

    public var debugDescription: String { "MLDataValue.DictionaryType(\(description))" }
}

extension MLDataValue.DictionaryType: Equatable {
    public static func == (lhs: MLDataValue.DictionaryType, rhs: MLDataValue.DictionaryType) -> Bool {
        lhs._contents == rhs._contents
    }
}

extension MLDataValue.DictionaryType: MLDataValueConvertible, FeatureValueConvertible {
    public static var dataValueType: MLDataValue.ValueType { .dictionary }

    public init?(from dataValue: MLDataValue) {
        guard let dictionary = dataValue.dictionaryValue else { return nil }
        self = dictionary
    }

    public var dataValue: MLDataValue { .dictionary(self) }
}

extension Dictionary: MLDataValueConvertible where Key: MLDataValueConvertible, Value: MLDataValueConvertible {
    public static var dataValueType: MLDataValue.ValueType { .dictionary }

    public init?(from dataValue: MLDataValue) {
        guard let dictionary = dataValue.dictionaryValue else { return nil }
        self.init(from: dictionary)
    }

    /// The pairs of a dictionary value, when all of them convert.
    public init?(from dictionaryType: MLDataValue.DictionaryType) {
        var result: [Key: Value] = [:]
        for (key, value) in dictionaryType._contents {
            guard let key = Key(from: key), let value = Value(from: value) else { return nil }
            result[key] = value
        }
        self = result
    }

    public var dataValue: MLDataValue {
        var contents: [MLDataValue: MLDataValue] = [:]
        for (key, value) in self { contents[key.dataValue] = value.dataValue }
        return .dictionary(MLDataValue.DictionaryType(contents))
    }
}

// Multi-arrays.

@available(*, unavailable)
extension MLDataValue.MultiArrayType: Sendable {}

extension MLDataValue.MultiArrayType: Equatable {
    /// A multi-array of doubles of a shape, filled with zeros.
    public init(shape: [Int]) {
        let array = (try? MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: .double))
            ?? (try! MLMultiArray(shape: [0], dataType: .double))
        for index in 0..<array.count { array[index] = 0 }
        self.init(_contents: array)
    }

    public init(_ contents: MLMultiArray) {
        self.init(_contents: contents)
    }

    /// The element at a linear index into the array.
    public subscript(index: Int) -> Double {
        _contents[index].doubleValue
    }

    public subscript(index: [Int]) -> Double {
        _contents[index.map { NSNumber(value: $0) }].doubleValue
    }

    public var mlMultiArray: MLMultiArray { _contents }

    /// The elements in row-major order.
    var elements: [Double] {
        var elements: [Double] = []
        elements.reserveCapacity(_contents.count)
        forEachIndex(shape: _contents.shape.map(\.intValue)) { index in
            elements.append(_contents[index.map { NSNumber(value: $0) }].doubleValue)
        }
        return elements
    }

    public static func == (lhs: MLDataValue.MultiArrayType, rhs: MLDataValue.MultiArrayType) -> Bool {
        lhs._contents === rhs._contents || (lhs._contents.shape == rhs._contents.shape && lhs.elements == rhs.elements)
    }

    @usableFromInline
    var featureValue: CMLFeatureValue { CMLFeatureValue(value: .multiArray(self)) }

    @usableFromInline
    init?(from featureValue: CMLFeatureValue) {
        guard let multiArray = featureValue.value.multiArrayValue else { return nil }
        self = multiArray
    }
}

extension MLDataValue.MultiArrayType: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        let shape = _contents.shape.map(\.stringValue).joined(separator: " x ")
        let elements = self.elements
        let shown = elements.prefix(10).map { String($0) }.joined(separator: ", ")
        return "MultiArray(\(shape)) [\(shown)\(elements.count > 10 ? ", ..." : "")]"
    }

    public var debugDescription: String { "MLDataValue.MultiArrayType(\(description))" }
}

extension MLDataValue.MultiArrayType: MLDataValueConvertible, FeatureValueConvertible {
    public static var dataValueType: MLDataValue.ValueType { .multiArray }

    public init?(from dataValue: MLDataValue) {
        guard let multiArray = dataValue.multiArrayValue else { return nil }
        self = multiArray
    }

    public init() {
        self.init(shape: [0])
    }

    public var dataValue: MLDataValue { .multiArray(self) }
}

// The values Swift's own types convert to.

@available(macOS 10.14, iOS 15.0, tvOS 16.0, *)
public protocol MLDataValueConvertible {
    static var dataValueType: MLDataValue.ValueType { get }
    init?(from dataValue: MLDataValue)
    init()
    var dataValue: MLDataValue { get }
}

extension Int: MLDataValueConvertible {
    public static var dataValueType: MLDataValue.ValueType { .int }

    public init?(from dataValue: MLDataValue) {
        guard case .int(let value) = dataValue else { return nil }
        self = value
    }

    public var dataValue: MLDataValue { .int(self) }
}

extension Bool: MLDataValueConvertible {
    public static var dataValueType: MLDataValue.ValueType { .int }

    /// An integer value's truth: nonzero is true.
    public init?(from dataValue: MLDataValue) {
        guard case .int(let value) = dataValue else { return nil }
        self = value != 0
    }

    public var dataValue: MLDataValue { .int(self ? 1 : 0) }
}

extension Int64: MLDataValueConvertible {
    public static var dataValueType: MLDataValue.ValueType { .int }

    public init?(from dataValue: MLDataValue) {
        guard case .int(let value) = dataValue else { return nil }
        self = Int64(value)
    }

    public var dataValue: MLDataValue { .int(Int(self)) }
}

extension Double: MLDataValueConvertible {
    public static var dataValueType: MLDataValue.ValueType { .double }

    /// A double value, or an integer one as a double.
    public init?(from dataValue: MLDataValue) {
        switch dataValue {
        case .double(let value): self = value
        case .int(let value): self = Double(value)
        default: return nil
        }
    }

    public var dataValue: MLDataValue { .double(self) }
}

extension String: MLDataValueConvertible {
    public static var dataValueType: MLDataValue.ValueType { .string }

    public init?(from dataValue: MLDataValue) {
        guard case .string(let value) = dataValue else { return nil }
        self = value
    }

    public var dataValue: MLDataValue { .string(self) }
}

// Identifiers of a recommender's users and items.

public protocol MLIdentifier {
    var identifierValue: MLDataValue { get }
}

extension Int: MLIdentifier {
    public var identifierValue: MLDataValue { .int(self) }
}

extension String: MLIdentifier {
    public var identifierValue: MLDataValue { .string(self) }
}

// The multi-array data types of Swift's numbers.

extension Int32 {
    public static var mlMultiArrayDataType: MLMultiArrayDataType { .int32 }
}

extension Float {
    public static var mlMultiArrayDataType: MLMultiArrayDataType { .float32 }
}

extension Double {
    public static var mlMultiArrayDataType: MLMultiArrayDataType { .double }
}

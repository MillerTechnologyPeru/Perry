import CoreML
import Foundation

// The storage under CreateML's values: feature values, sequences,
// dictionaries and multi-arrays as classes, named as the Swift 5.0
// overlay's bridge to its C engine named them. Perry's are plain Swift
// over MLDataValue.

/// The type of a feature value.
@usableFromInline
enum CMLFeatureValueType: Hashable {
    case int64
    case double
    case string
    case sequence
    case dictionary
    case multiArray
    case undefined

    init(_ type: MLDataValue.ValueType) {
        switch type {
        case .int: self = .int64
        case .double: self = .double
        case .string: self = .string
        case .sequence: self = .sequence
        case .dictionary: self = .dictionary
        case .multiArray: self = .multiArray
        case .invalid: self = .undefined
        }
    }

    var valueType: MLDataValue.ValueType {
        switch self {
        case .int64: return .int
        case .double: return .double
        case .string: return .string
        case .sequence: return .sequence
        case .dictionary: return .dictionary
        case .multiArray: return .multiArray
        case .undefined: return .invalid
        }
    }
}

/// One value: an MLDataValue in a reference.
@usableFromInline
final class CMLFeatureValue {
    let value: MLDataValue

    init(value: MLDataValue) {
        self.value = value
    }

    /// The missing value.
    @usableFromInline
    init() {
        value = .invalid
    }

    @usableFromInline
    convenience init(_ other: CMLFeatureValue) throws {
        self.init(value: other.value)
    }

    @usableFromInline
    convenience init(_ string: String) throws {
        self.init(value: .string(string))
    }

    @usableFromInline
    convenience init(_ double: Double) throws {
        self.init(value: .double(double))
    }

    @usableFromInline
    convenience init(_ int: Int) throws {
        self.init(value: .int(int))
    }

    @usableFromInline
    convenience init(_ sequence: CMLSequence) throws {
        self.init(value: .sequence(MLDataValue.SequenceType(_contents: sequence)))
    }

    @usableFromInline
    convenience init(_ dictionary: CMLDictionary) throws {
        var contents: [MLDataValue: MLDataValue] = [:]
        for (key, value) in dictionary.pairs { contents[key] = value }
        self.init(value: .dictionary(MLDataValue.DictionaryType(_contents: contents)))
    }

    @usableFromInline
    convenience init(_ multiArray: CMLMultiArray) throws {
        self.init(value: .multiArray(MLDataValue.MultiArrayType(_contents: try multiArray.mlMultiArray())))
    }

    @usableFromInline
    var type: CMLFeatureValueType { CMLFeatureValueType(value.type) }

    @usableFromInline var isUndefined: Bool { !value.isValid }
    @usableFromInline var isInt64: Bool { value.type == .int }
    @usableFromInline var isDouble: Bool { value.type == .double }
    @usableFromInline var isString: Bool { value.type == .string }
    @usableFromInline var isSequence: Bool { value.type == .sequence }
    @usableFromInline var isMultiArray: Bool { value.type == .multiArray }

    /// The error a value of the wrong type is read with.
    private func mismatch(_ wanted: String) -> MLCreateError {
        .type(reason: "The value \(value) is not \(wanted).")
    }

    @usableFromInline
    func intValue() throws -> Int {
        guard let int = value.intValue else { throw mismatch("an integer") }
        return int
    }

    @usableFromInline
    func doubleValue() throws -> Double {
        guard let double = value.doubleValue ?? value.intValue.map(Double.init) else { throw mismatch("a double") }
        return double
    }

    @usableFromInline
    func stringValue() throws -> String {
        guard let string = value.stringValue else { throw mismatch("a string") }
        return string
    }

    @usableFromInline
    func sequenceValue() throws -> CMLSequence {
        guard let sequence = value.sequenceValue else { throw mismatch("a sequence") }
        return sequence._contents
    }

    @usableFromInline
    func dictionaryValue() throws -> CMLDictionary {
        guard let dictionary = value.dictionaryValue else { throw mismatch("a dictionary") }
        let result = CMLDictionary()
        result.pairs = dictionary._contents.map { ($0.key, $0.value) }
        return result
    }

    @usableFromInline
    func multiArrayValue() throws -> CMLMultiArray {
        guard let multiArray = value.multiArrayValue else { throw mismatch("a multi-array") }
        return CMLMultiArray(multiArray._contents)
    }
}

/// An ordered sequence of values.
@usableFromInline
final class CMLSequence: RandomAccessCollection {
    var values: [MLDataValue]

    init(values: [MLDataValue]) {
        self.values = values
    }

    @usableFromInline
    init() {
        values = []
    }

    @usableFromInline var startIndex: Int { 0 }
    @usableFromInline var endIndex: Int { values.count }
    @usableFromInline var size: Int { values.count }

    @usableFromInline
    subscript(position: Int) -> CMLFeatureValue {
        CMLFeatureValue(value: values[position])
    }

    @usableFromInline
    func value(at index: Int) throws -> CMLFeatureValue {
        guard values.indices.contains(index) else {
            throw MLCreateError.generic(reason: "Index \(index) is out of the sequence's range 0..<\(values.count).")
        }
        return self[index]
    }

    /// Appends a value, returning the sequence's new size.
    @discardableResult
    @usableFromInline
    func append(_ value: CMLFeatureValue) throws -> Int {
        values.append(value.value)
        return values.count
    }
}

/// Key-value pairs, in the order they were added.
@usableFromInline
final class CMLDictionary: RandomAccessCollection {
    var pairs: [(MLDataValue, MLDataValue)] = []

    @usableFromInline
    init() {}

    @usableFromInline var startIndex: Int { 0 }
    @usableFromInline var endIndex: Int { pairs.count }
    @usableFromInline var size: Int { pairs.count }

    @usableFromInline
    subscript(position: Int) -> (CMLFeatureValue, CMLFeatureValue) {
        (CMLFeatureValue(value: pairs[position].0), CMLFeatureValue(value: pairs[position].1))
    }

    @usableFromInline
    func keyAndValue(at index: Int) throws -> (CMLFeatureValue, CMLFeatureValue) {
        guard pairs.indices.contains(index) else {
            throw MLCreateError.generic(reason: "Index \(index) is out of the dictionary's range 0..<\(pairs.count).")
        }
        return self[index]
    }

    /// Adds a pair, replacing the value of a key already there; returns
    /// the dictionary's size.
    @discardableResult
    @usableFromInline
    func add(key: CMLFeatureValue, value: CMLFeatureValue) throws -> Int {
        if let index = pairs.firstIndex(where: { $0.0 == key.value }) {
            pairs[index].1 = value.value
        } else {
            pairs.append((key.value, value.value))
        }
        return pairs.count
    }
}

/// A multi-array of doubles, with its shape and strides.
@usableFromInline
final class CMLMultiArray {
    let shapeBuffer: UnsafeMutableBufferPointer<UInt64>
    let stridesBuffer: UnsafeMutableBufferPointer<Int64>
    let dataBuffer: UnsafeMutableBufferPointer<Double>

    /// A multi-array of a shape and strides, holding `data`.
    init(shape: [UInt64], strides: [Int64], data: [Double]) {
        shapeBuffer = .allocate(capacity: shape.count)
        _ = shapeBuffer.initialize(from: shape)
        stridesBuffer = .allocate(capacity: strides.count)
        _ = stridesBuffer.initialize(from: strides)
        dataBuffer = .allocate(capacity: data.count)
        _ = dataBuffer.initialize(from: data)
    }

    @usableFromInline
    convenience init(dimensions: Int, shape: UnsafePointer<UInt64>, strides: UnsafePointer<Int64>, data: UnsafePointer<Double>) throws {
        guard dimensions >= 0 else { throw MLCreateError.generic(reason: "A multi-array can't have \(dimensions) dimensions.") }
        let shape = Array(UnsafeBufferPointer(start: shape, count: dimensions))
        let strides = Array(UnsafeBufferPointer(start: strides, count: dimensions))
        let count = CMLMultiArray.span(shape: shape, strides: strides)
        self.init(shape: shape, strides: strides, data: Array(UnsafeBufferPointer(start: data, count: count)))
    }

    /// A copy of an MLMultiArray's elements, as doubles.
    convenience init(_ array: MLMultiArray) {
        let shape = array.shape.map { UInt64($0.intValue) }
        let strides = array.strides.map { Int64($0.intValue) }
        var data = [Double](repeating: 0, count: CMLMultiArray.span(shape: shape, strides: strides))
        // Each element read by its index, so any data type and layout works.
        forEachIndex(shape: shape.map(Int.init)) { index in
            let offset = zip(index, strides).reduce(0) { $0 + $1.0 * Int($1.1) }
            data[offset] = array[index.map { NSNumber(value: $0) }].doubleValue
        }
        self.init(shape: shape, strides: strides, data: data)
    }

    /// The elements a strided array spans: one past its farthest one.
    static func span(shape: [UInt64], strides: [Int64]) -> Int {
        if shape.isEmpty { return 1 }
        if shape.contains(0) { return 0 }
        return zip(shape, strides).reduce(0) { $0 + Int($1.0 - 1) * Int($1.1) } + 1
    }

    deinit {
        shapeBuffer.deallocate()
        stridesBuffer.deallocate()
        dataBuffer.deallocate()
    }

    @usableFromInline func dimensions() throws -> Int { shapeBuffer.count }
    @usableFromInline func shape() throws -> UnsafePointer<UInt64> { UnsafePointer(shapeBuffer.baseAddress!) }
    @usableFromInline func strides() throws -> UnsafePointer<Int64> { UnsafePointer(stridesBuffer.baseAddress!) }
    @usableFromInline func data() throws -> UnsafePointer<Double> { UnsafePointer(dataBuffer.baseAddress!) }

    /// The elements as an MLMultiArray of doubles.
    func mlMultiArray() throws -> MLMultiArray {
        let shape = shapeBuffer.map { NSNumber(value: Int($0)) }
        let array = try MLMultiArray(shape: shape, dataType: .double)
        forEachIndex(shape: shapeBuffer.map(Int.init)) { index in
            let offset = zip(index, stridesBuffer).reduce(0) { $0 + $1.0 * Int($1.1) }
            array[index.map { NSNumber(value: $0) }] = NSNumber(value: dataBuffer[offset])
        }
        return array
    }
}

/// Calls `body` with every index of an array of a shape, in row-major order.
func forEachIndex(shape: [Int], _ body: ([Int]) -> Void) {
    guard !shape.contains(where: { $0 <= 0 }) else { return }
    var index = [Int](repeating: 0, count: shape.count)
    while true {
        body(index)
        var dimension = shape.count - 1
        while dimension >= 0 {
            index[dimension] += 1
            if index[dimension] < shape[dimension] { break }
            index[dimension] = 0
            dimension -= 1
        }
        if dimension < 0 { return }
    }
}

// Conversions between Swift values and feature values.

/// A value that converts to and from a feature value.
@usableFromInline
protocol FeatureValueConvertible: MLDataValueConvertible {
    init?(from featureValue: CMLFeatureValue)
    var featureValue: CMLFeatureValue { get }
}

/// A value that converts to a column.
@usableFromInline
protocol CMLColumnConvertible {
    var featureColumn: CMLColumn { get }
}

/// A typed column made over an untyped one.
@usableFromInline
protocol ImplementedByUntypedColumn {
    init(from untypedColumn: MLUntypedColumn)
    var _untypedColumn: MLUntypedColumn { get set }
}

extension MLDataValueConvertible {
    @usableFromInline
    var featureValue: CMLFeatureValue { CMLFeatureValue(value: dataValue) }

    @usableFromInline
    var featureColumn: CMLColumn { CMLColumn(values: [dataValue], type: CMLFeatureValueType(Self.dataValueType)) }

    @usableFromInline
    static func makeInstance(featureValue: CMLFeatureValue) -> Self? {
        Self(from: featureValue.value)
    }
}

extension Int: FeatureValueConvertible {
    @usableFromInline var featureValue: CMLFeatureValue { CMLFeatureValue(value: dataValue) }
    @usableFromInline init?(from featureValue: CMLFeatureValue) { self.init(from: featureValue.value) }
}

extension Int64: FeatureValueConvertible {
    @usableFromInline var featureValue: CMLFeatureValue { CMLFeatureValue(value: dataValue) }
    @usableFromInline init?(from featureValue: CMLFeatureValue) { self.init(from: featureValue.value) }
}

extension Double: FeatureValueConvertible {
    @usableFromInline var featureValue: CMLFeatureValue { CMLFeatureValue(value: dataValue) }
    @usableFromInline init?(from featureValue: CMLFeatureValue) { self.init(from: featureValue.value) }
}

extension String: FeatureValueConvertible {
    @usableFromInline var featureValue: CMLFeatureValue { CMLFeatureValue(value: dataValue) }
    @usableFromInline init?(from featureValue: CMLFeatureValue) { self.init(from: featureValue.value) }
}

extension Bool: FeatureValueConvertible {
    @usableFromInline var featureValue: CMLFeatureValue { CMLFeatureValue(value: dataValue) }
    @usableFromInline init?(from featureValue: CMLFeatureValue) { self.init(from: featureValue.value) }
}

extension Array: FeatureValueConvertible, CMLColumnConvertible where Element: MLDataValueConvertible {
    @usableFromInline var featureValue: CMLFeatureValue { CMLFeatureValue(value: dataValue) }
    @usableFromInline init?(from featureValue: CMLFeatureValue) { self.init(from: featureValue.value) }

    /// The elements as a sequence of values.
    @usableFromInline
    var featureSequence: CMLSequence { CMLSequence(values: map(\.dataValue)) }

    /// The elements as a column.
    @usableFromInline
    var featureColumn: CMLColumn { CMLColumn(values: map(\.dataValue), type: CMLFeatureValueType(Element.dataValueType)) }
}

extension Dictionary: FeatureValueConvertible where Key: MLDataValueConvertible, Value: MLDataValueConvertible {
    @usableFromInline var featureValue: CMLFeatureValue { CMLFeatureValue(value: dataValue) }
    @usableFromInline init?(from featureValue: CMLFeatureValue) { self.init(from: featureValue.value) }
}

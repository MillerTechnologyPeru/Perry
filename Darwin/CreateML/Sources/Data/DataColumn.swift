import Foundation

// MLDataColumn: a column of values of one Swift type, over an untyped one.

@available(macOS 10.14, iOS 15.0, tvOS 16.0, *)
public struct MLDataColumn<Element> where Element: MLDataValueConvertible {
    @usableFromInline
    var _untypedColumn: MLUntypedColumn

    @usableFromInline
    init(from untypedColumn: MLUntypedColumn) {
        _untypedColumn = untypedColumn
    }

    /// The column's values.
    var values: [MLDataValue] { _untypedColumn.values }

    /// A column of values, converted to the element type.
    init(values: [MLDataValue]) {
        self.init(from: MLUntypedColumn(values: values, type: CMLFeatureValueType(Element.dataValueType)))
    }

    /// A column made by an operation on this one's storage.
    func derived(_ body: (CMLColumn) throws -> CMLColumn) -> MLDataColumn<Element> {
        MLDataColumn(from: _untypedColumn.derived(body))
    }

    public var count: Int { _untypedColumn.count }
    public var isEmpty: Bool { _untypedColumn.isEmpty }
    public var error: (any Error)? { _untypedColumn.error }
    public var isValid: Bool { _untypedColumn.isValid }

    public init<S>(_ source: S) where Element == S.Element, S: Sequence {
        self.init(from: MLUntypedColumn(source))
    }

    public init(repeating repeatedValue: MLDataValue, count: Int) {
        self.init(values: Array(repeating: repeatedValue, count: Swift.max(count, 0)))
    }

    public init(repeating repeatedValue: Element, count: Int) {
        self.init(from: MLUntypedColumn(repeating: repeatedValue, count: count))
    }

    public init() {
        self.init(values: [])
    }

    public mutating func append(contentsOf newColumn: MLDataColumn<Element>) {
        _untypedColumn.append(contentsOf: newColumn._untypedColumn)
    }
}

extension MLDataColumn: ImplementedByUntypedColumn {}

extension MLDataColumn where Element == Int {
    @usableFromInline
    init(_ range: Range<Int>) {
        self.init(from: MLUntypedColumn(range))
    }
}

@available(*, unavailable)
extension MLDataColumn: Sendable {}

// Comparisons and arithmetic, element by element.

extension MLDataColumn {
    static func compare(_ a: MLDataColumn<Element>, _ b: MLDataColumn<Element>, _ operation: ValueOperation) -> MLDataColumn<Bool> {
        MLDataColumn<Bool>(from: a._untypedColumn.combined(b._untypedColumn, operation))
    }

    static func compare(_ a: MLDataColumn<Element>, _ b: Element, _ operation: ValueOperation) -> MLDataColumn<Bool> {
        MLDataColumn<Bool>(from: a._untypedColumn.combined(b, operation))
    }

    static func compare(_ a: Element, _ b: MLDataColumn<Element>, _ operation: ValueOperation) -> MLDataColumn<Bool> {
        MLDataColumn<Bool>(from: b._untypedColumn.combined(left: a, operation))
    }

    public static func == (a: MLDataColumn<Element>, b: MLDataColumn<Element>) -> MLDataColumn<Bool> { compare(a, b, .equal) }
    public static func != (a: MLDataColumn<Element>, b: MLDataColumn<Element>) -> MLDataColumn<Bool> { compare(a, b, .notEqual) }
    public static func > (a: MLDataColumn<Element>, b: MLDataColumn<Element>) -> MLDataColumn<Bool> { compare(a, b, .greater) }
    public static func < (a: MLDataColumn<Element>, b: MLDataColumn<Element>) -> MLDataColumn<Bool> { compare(a, b, .less) }
    public static func >= (a: MLDataColumn<Element>, b: MLDataColumn<Element>) -> MLDataColumn<Bool> { compare(a, b, .greaterOrEqual) }
    public static func <= (a: MLDataColumn<Element>, b: MLDataColumn<Element>) -> MLDataColumn<Bool> { compare(a, b, .lessOrEqual) }
    public static func == (a: MLDataColumn<Element>, b: Element) -> MLDataColumn<Bool> { compare(a, b, .equal) }
    public static func != (a: MLDataColumn<Element>, b: Element) -> MLDataColumn<Bool> { compare(a, b, .notEqual) }
    public static func > (a: MLDataColumn<Element>, b: Element) -> MLDataColumn<Bool> { compare(a, b, .greater) }
    public static func < (a: MLDataColumn<Element>, b: Element) -> MLDataColumn<Bool> { compare(a, b, .less) }
    public static func >= (a: MLDataColumn<Element>, b: Element) -> MLDataColumn<Bool> { compare(a, b, .greaterOrEqual) }
    public static func <= (a: MLDataColumn<Element>, b: Element) -> MLDataColumn<Bool> { compare(a, b, .lessOrEqual) }
    public static func == (a: Element, b: MLDataColumn<Element>) -> MLDataColumn<Bool> { compare(a, b, .equal) }
    public static func != (a: Element, b: MLDataColumn<Element>) -> MLDataColumn<Bool> { compare(a, b, .notEqual) }
    public static func > (a: Element, b: MLDataColumn<Element>) -> MLDataColumn<Bool> { compare(a, b, .greater) }
    public static func < (a: Element, b: MLDataColumn<Element>) -> MLDataColumn<Bool> { compare(a, b, .less) }
    public static func >= (a: Element, b: MLDataColumn<Element>) -> MLDataColumn<Bool> { compare(a, b, .greaterOrEqual) }
    public static func <= (a: Element, b: MLDataColumn<Element>) -> MLDataColumn<Bool> { compare(a, b, .lessOrEqual) }

    /// An arithmetic result, in this column's type.
    static func arithmetic(_ a: MLUntypedColumn, _ operation: ValueOperation) -> MLDataColumn<Element> {
        MLDataColumn(from: a.derived { try $0.toType(CMLFeatureValueType(Element.dataValueType)) })
    }
}

extension MLDataColumn where Element == Int {
    public static func + (a: MLDataColumn<Int>, b: MLDataColumn<Int>) -> MLDataColumn<Int> { arithmetic(a._untypedColumn.combined(b._untypedColumn, .add), .add) }
    public static func - (a: MLDataColumn<Int>, b: MLDataColumn<Int>) -> MLDataColumn<Int> { arithmetic(a._untypedColumn.combined(b._untypedColumn, .subtract), .subtract) }
    public static func * (a: MLDataColumn<Int>, b: MLDataColumn<Int>) -> MLDataColumn<Int> { arithmetic(a._untypedColumn.combined(b._untypedColumn, .multiply), .multiply) }
    public static func / (a: MLDataColumn<Int>, b: MLDataColumn<Int>) -> MLDataColumn<Int> { arithmetic(a._untypedColumn.combined(b._untypedColumn, .divide), .divide) }
    public static func + (a: Int, b: MLDataColumn<Int>) -> MLDataColumn<Int> { arithmetic(b._untypedColumn.combined(left: a, .add), .add) }
    public static func - (a: Int, b: MLDataColumn<Int>) -> MLDataColumn<Int> { arithmetic(b._untypedColumn.combined(left: a, .subtract), .subtract) }
    public static func * (a: Int, b: MLDataColumn<Int>) -> MLDataColumn<Int> { arithmetic(b._untypedColumn.combined(left: a, .multiply), .multiply) }
    public static func / (a: Int, b: MLDataColumn<Int>) -> MLDataColumn<Int> { arithmetic(b._untypedColumn.combined(left: a, .divide), .divide) }
    public static func + (a: MLDataColumn<Int>, b: Int) -> MLDataColumn<Int> { arithmetic(a._untypedColumn.combined(b, .add), .add) }
    public static func - (a: MLDataColumn<Int>, b: Int) -> MLDataColumn<Int> { arithmetic(a._untypedColumn.combined(b, .subtract), .subtract) }
    public static func * (a: MLDataColumn<Int>, b: Int) -> MLDataColumn<Int> { arithmetic(a._untypedColumn.combined(b, .multiply), .multiply) }
    public static func / (a: MLDataColumn<Int>, b: Int) -> MLDataColumn<Int> { arithmetic(a._untypedColumn.combined(b, .divide), .divide) }
}

extension MLDataColumn where Element == Double {
    public static func + (a: MLDataColumn<Double>, b: MLDataColumn<Double>) -> MLDataColumn<Double> { arithmetic(a._untypedColumn.combined(b._untypedColumn, .add), .add) }
    public static func - (a: MLDataColumn<Double>, b: MLDataColumn<Double>) -> MLDataColumn<Double> { arithmetic(a._untypedColumn.combined(b._untypedColumn, .subtract), .subtract) }
    public static func * (a: MLDataColumn<Double>, b: MLDataColumn<Double>) -> MLDataColumn<Double> { arithmetic(a._untypedColumn.combined(b._untypedColumn, .multiply), .multiply) }
    public static func / (a: MLDataColumn<Double>, b: MLDataColumn<Double>) -> MLDataColumn<Double> { arithmetic(a._untypedColumn.combined(b._untypedColumn, .divide), .divide) }
    public static func + (a: Double, b: MLDataColumn<Double>) -> MLDataColumn<Double> { arithmetic(b._untypedColumn.combined(left: a, .add), .add) }
    public static func - (a: Double, b: MLDataColumn<Double>) -> MLDataColumn<Double> { arithmetic(b._untypedColumn.combined(left: a, .subtract), .subtract) }
    public static func * (a: Double, b: MLDataColumn<Double>) -> MLDataColumn<Double> { arithmetic(b._untypedColumn.combined(left: a, .multiply), .multiply) }
    public static func / (a: Double, b: MLDataColumn<Double>) -> MLDataColumn<Double> { arithmetic(b._untypedColumn.combined(left: a, .divide), .divide) }
    public static func + (a: MLDataColumn<Double>, b: Double) -> MLDataColumn<Double> { arithmetic(a._untypedColumn.combined(b, .add), .add) }
    public static func - (a: MLDataColumn<Double>, b: Double) -> MLDataColumn<Double> { arithmetic(a._untypedColumn.combined(b, .subtract), .subtract) }
    public static func * (a: MLDataColumn<Double>, b: Double) -> MLDataColumn<Double> { arithmetic(a._untypedColumn.combined(b, .multiply), .multiply) }
    public static func / (a: MLDataColumn<Double>, b: Double) -> MLDataColumn<Double> { arithmetic(a._untypedColumn.combined(b, .divide), .divide) }
}

extension MLDataColumn where Element == Bool {
    public static func || (a: MLDataColumn<Bool>, b: MLDataColumn<Bool>) -> MLDataColumn<Bool> {
        MLDataColumn<Bool>(from: a._untypedColumn.combined(b._untypedColumn, .or))
    }

    public static func && (a: MLDataColumn<Bool>, b: MLDataColumn<Bool>) -> MLDataColumn<Bool> {
        MLDataColumn<Bool>(from: a._untypedColumn.combined(b._untypedColumn, .and))
    }
}

// Transformations.

extension MLDataColumn {
    public subscript(mask: MLUntypedColumn) -> MLDataColumn<Element> {
        MLDataColumn(from: _untypedColumn[mask])
    }

    public subscript(mask: MLDataColumn<Bool>) -> MLDataColumn<Element> {
        MLDataColumn(from: _untypedColumn[mask._untypedColumn])
    }

    /// The elements a transform makes of the present ones; missing ones,
    /// and those it makes nil of, are missing.
    public func map<T>(_ lazyTransform: @escaping (Element) -> T?) -> MLDataColumn<T> where T: MLDataValueConvertible {
        _untypedColumn.map { value -> T? in Element(from: value).flatMap(lazyTransform) }
    }

    public func map<T>(_ lazyTransform: @escaping (Element) -> T) -> MLDataColumn<T> where T: MLDataValueConvertible {
        _untypedColumn.map { value -> T? in Element(from: value).map(lazyTransform) }
    }

    /// The elements a transform makes of all of them, nil for missing ones.
    public func mapMissing<T>(_ lazyTransform: @escaping (Element?) -> T?) -> MLDataColumn<T> where T: MLDataValueConvertible {
        _untypedColumn.mapMissing { lazyTransform(Element(from: $0)) }
    }

    public func map<T>(to type: T.Type) -> MLDataColumn<T> where T: MLDataValueConvertible {
        _untypedColumn.map(to: type)
    }

    public func dropMissing() -> MLDataColumn<Element> { MLDataColumn(from: _untypedColumn.dropMissing()) }
    public func fillMissing(with value: Element) -> MLDataColumn<Element> { MLDataColumn(from: _untypedColumn.fillMissing(with: value.dataValue)) }
    public func dropDuplicates() -> MLDataColumn<Element> { MLDataColumn(from: _untypedColumn.dropDuplicates()) }
    public func prefix(_ maxLength: Int = 10) -> MLDataColumn<Element> { MLDataColumn(from: _untypedColumn.prefix(maxLength)) }
    public func suffix(_ maxLength: Int = 10) -> MLDataColumn<Element> { MLDataColumn(from: _untypedColumn.suffix(maxLength)) }

    public func sort(byIncreasingOrder: Bool = true) -> MLDataColumn<Element> {
        MLDataColumn(from: _untypedColumn.sort(byIncreasingOrder: byIncreasingOrder))
    }

    public func copy() -> MLDataColumn<Element> { MLDataColumn(from: _untypedColumn.copy()) }

    public func materialize() throws -> MLDataColumn<Element> {
        MLDataColumn(from: try _untypedColumn.materialize())
    }
}

extension MLDataColumn {
    /// The element at an index, nil when it's missing or out of the column.
    public func element(at index: Int) -> Element? {
        Element(from: _untypedColumn[index])
    }

    /// The element at an index; the element type's empty value when it's
    /// missing.
    public subscript(index: Int) -> Element {
        element(at: index) ?? Element()
    }
}

extension MLDataColumn {
    public subscript(slice: Range<Int>) -> MLDataColumn<Element> {
        MLDataColumn(from: _untypedColumn[slice])
    }

    public subscript<R>(slice: R) -> MLDataColumn<Element> where R: RangeExpression, R.Bound == Int {
        MLDataColumn(from: _untypedColumn[slice])
    }
}

extension MLDataColumn {
    public func show() -> any MLStreamingVisualizable {
        TextVisualization(text: description)
    }
}

extension Array where Element: MLDataValueConvertible {
    /// The column's elements, the element type's empty value for missing
    /// ones.
    public init(_ column: MLDataColumn<Element>) {
        self = column.values.map { Element(from: $0) ?? Element() }
    }
}

// Conversions and statistics.

extension MLDataColumn {
    /// Another column's values converted with `convert`.
    init<T>(converting column: MLDataColumn<T>, _ convert: @escaping (MLDataValue) -> MLDataValue) {
        self.init(from: column._untypedColumn.derived { source in
            CMLColumn(values: source.values.map(convert), type: CMLFeatureValueType(Element.dataValueType))
        })
    }

    /// A sequence value's elements converted to a type, or missing if any
    /// doesn't convert.
    static func convertElements(_ value: MLDataValue, to type: CMLFeatureValueType) -> MLDataValue {
        guard let sequence = value.converted(to: .sequence).sequenceValue else { return .invalid }
        let elements = sequence.map { $0.converted(to: type) }
        return elements.allSatisfy(\.isValid) ? .sequence(MLDataValue.SequenceType(elements)) : .invalid
    }

    /// The column's numbers.
    var numbers: [Double] { values.compactMap(\.number) }

    var standardDeviation: Double? {
        let numbers = self.numbers
        guard !numbers.isEmpty else { return nil }
        let mean = numbers.reduce(0, +) / Double(numbers.count)
        return (numbers.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(numbers.count)).squareRoot()
    }

    var average: Double? {
        let numbers = self.numbers
        return numbers.isEmpty ? nil : numbers.reduce(0, +) / Double(numbers.count)
    }
}

extension MLDataColumn where Element == Int {
    public init<T>(column: MLDataColumn<T>) where T: MLDataValueConvertible {
        self.init(converting: column) { $0.converted(to: .int64) }
    }

    public func sum() -> Int? {
        let ints = values.compactMap(\.intValue)
        return isValid ? ints.reduce(0, &+) : nil
    }

    public func min() -> Int? { values.compactMap(\.intValue).min() }
    public func max() -> Int? { values.compactMap(\.intValue).max() }
    public func std() -> Double? { standardDeviation }
    public func mean() -> Double? { average }
}

extension MLDataColumn where Element == Double {
    public init<T>(column: MLDataColumn<T>) where T: MLDataValueConvertible {
        self.init(converting: column) { $0.converted(to: .double) }
    }

    public func sum() -> Double? { isValid ? numbers.reduce(0, +) : nil }
    public func min() -> Double? { numbers.min() }
    public func max() -> Double? { numbers.max() }
    public func std() -> Double? { standardDeviation }
    public func mean() -> Double? { average }
}

extension MLDataColumn where Element == Int {
    public func stdev() -> Double? { standardDeviation }
}

extension MLDataColumn where Element == Double {
    public func stdev() -> Double? { standardDeviation }
}

extension MLDataColumn where Element == String {
    public init<T>(column: MLDataColumn<T>) where T: MLDataValueConvertible {
        self.init(converting: column) { $0.converted(to: .string) }
    }
}

extension MLDataColumn where Element == MLDataValue.SequenceType {
    public init<T>(column: MLDataColumn<T>) where T: MLDataValueConvertible {
        self.init(converting: column) { $0.converted(to: .sequence) }
    }
}

extension MLDataColumn where Element == [Int] {
    public init<T>(column: MLDataColumn<T>) where T: MLDataValueConvertible {
        self.init(converting: column) { MLDataColumn.convertElements($0, to: .int64) }
    }
}

extension MLDataColumn where Element == [Double] {
    public init<T>(column: MLDataColumn<T>) where T: MLDataValueConvertible {
        self.init(converting: column) { MLDataColumn.convertElements($0, to: .double) }
    }
}

extension MLDataColumn where Element == [String] {
    public init<T>(column: MLDataColumn<T>) where T: MLDataValueConvertible {
        self.init(converting: column) { MLDataColumn.convertElements($0, to: .string) }
    }
}

extension MLDataColumn where Element == MLDataValue.DictionaryType {
    public init<T>(column: MLDataColumn<T>) where T: MLDataValueConvertible {
        self.init(converting: column) { $0.converted(to: .dictionary) }
    }
}

extension MLDataColumn: CustomReflectable {
    public var customMirror: Mirror {
        Mirror(self, unlabeledChildren: values.map { Element(from: $0) as Any }, displayStyle: .collection)
    }
}

extension MLDataColumn: CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
    public var description: String {
        if let error { return "Invalid column: \(error)" }
        return describeColumn(values, type: Element.dataValueType)
    }

    public var debugDescription: String { description }
    public var playgroundDescription: Any { description }
}

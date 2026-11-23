import Foundation

// MLDataTable: named columns of the same length, which carries the error
// of the operation that made it, if one failed.

@available(macOS 10.14, iOS 15.0, tvOS 16.0, *)
public struct MLDataTable {
    var _result: _ResultType<CMLTable>

    init(result: _ResultType<CMLTable>) {
        _result = result
    }

    @usableFromInline
    init(_ impl: CMLTable) {
        _result = .success(impl)
    }

    init(error: any Error) {
        _result = .failure(error)
    }

    /// The table's storage, or its error thrown.
    @usableFromInline
    func getImpl() throws -> CMLTable {
        try _result.get()
    }

    /// The table's storage, if it's valid.
    var table: CMLTable? { _result.value }

    /// The columns' indices by name.
    @usableFromInline
    var columnIndexes: [String: Int] {
        Dictionary(uniqueKeysWithValues: (table?.names ?? []).enumerated().map { ($1, $0) })
    }

    /// A table made by an operation on this one's storage.
    func derived(_ body: (CMLTable) throws -> CMLTable) -> MLDataTable {
        MLDataTable(result: unaryDo(_result, body))
    }

    /// Changes the table's storage: a copy of it, so other tables that
    /// share it don't change.
    mutating func mutate(_ body: (CMLTable) throws -> Void) {
        _result = unaryDo(_result) { table in
            let copy = table.copy()
            try body(copy)
            return copy
        }
    }

    public var error: (any Error)? { _result.error }
    public var isValid: Bool { error == nil }

    public var size: (rows: Int, columns: Int) {
        (table?.rowCount ?? 0, table?.columnList.count ?? 0)
    }

    public var columnTypes: [String: MLDataValue.ValueType] {
        guard let table else { return [:] }
        return Dictionary(uniqueKeysWithValues: zip(table.names, table.columnList.map(\.type.valueType)))
    }

    public init() {
        self.init(CMLTable())
    }

    public init(namedColumns: [String: MLUntypedColumn]) throws {
        try self.init(uniqueKeysWithValues: namedColumns.sorted { $0.key < $1.key }.map { (key: $0.key, value: $0.value) })
    }

    @usableFromInline
    init<S>(uniqueKeysWithValues keysAndValues: S) throws where S: Sequence, S.Element == (key: String, value: MLUntypedColumn) {
        let table = CMLTable()
        for (name, column) in keysAndValues {
            if table.names.contains(name) { throw MLCreateError.generic(reason: "The column name \(name) is repeated.") }
            guard let column = column.underlyingColumn else {
                throw column.error ?? MLCreateError.generic(reason: "The column \(name) is invalid.")
            }
            try table.addColumn(name: name, column._impl)
        }
        self.init(table)
    }

    /// A table of columns of values: arrays of convertible values, one
    /// column each.
    public init(dictionary: [String: any MLDataValueConvertible]) throws {
        let table = CMLTable()
        for (name, value) in dictionary.sorted(by: { $0.key < $1.key }) {
            let column: CMLColumn
            switch value.dataValue {
            case .sequence(let sequence): column = CMLColumn(values: Array(sequence))
            case let single: column = CMLColumn(values: [single])
            }
            try table.addColumn(name: name, column)
        }
        self.init(table)
    }

    public subscript(columnName: String) -> MLUntypedColumn {
        get {
            MLUntypedColumn(result: unaryDo(_result) { _UntypedColumn(impl: try $0.column(name: columnName)) })
        }
        set(newValue) {
            addColumn(newValue, named: columnName)
        }
    }

    public subscript<Element>(columnName: String) -> MLDataColumn<Element> where Element: MLDataValueConvertible {
        get {
            MLDataColumn(from: self[columnName])
        }
        set(newValue) {
            addColumn(newValue, named: columnName)
        }
    }

    /// A column as a column of a type, if its values are of that type.
    public subscript<T>(columnName: String, columnType: T.Type) -> MLDataColumn<T>? where T: MLDataValueConvertible {
        let column = self[columnName]
        return column.isValid ? column.column(type: columnType) : nil
    }

    public subscript<S>(columnNames: S) -> MLDataTable where S: Sequence, S.Element == String {
        derived { table in
            let names = Array(columnNames)
            return CMLTable(names: names, columns: try names.map { try table.column(name: $0) })
        }
    }

    public subscript(slice: Range<Int>) -> MLDataTable {
        derived { try $0.slice(lower: slice.lowerBound, upper: slice.upperBound) }
    }

    public subscript<R>(slice: R) -> MLDataTable where R: RangeExpression, R.Bound == Int {
        self[slice.relative(to: 0..<size.rows)]
    }

    public mutating func addColumn(_ newColumn: MLUntypedColumn, named: String) {
        guard let column = newColumn.underlyingColumn else {
            _result = .failure(newColumn.error ?? MLCreateError.generic(reason: "The column \(named) is invalid."))
            return
        }
        mutate { try $0.addColumn(name: named, column._impl) }
    }

    public mutating func addColumn<Element>(_ newColumn: MLDataColumn<Element>, named: String) where Element: MLDataValueConvertible {
        addColumn(newColumn._untypedColumn, named: named)
    }

    public mutating func removeColumn(named: String) {
        mutate { try $0.removeColumn(name: named) }
    }

    public mutating func renameColumn(named: String, to: String) {
        mutate { try $0.renameColumn(named: named, to: to) }
    }

    public mutating func append(contentsOf newTable: MLDataTable) {
        _result = binaryDo(_result, newTable._result) { try CMLTable(concatenating: $0, and: $1) }
    }

    /// About `proportion` of the rows, picked at random.
    public func randomSample(by proportion: Double, seed: Int = 42) -> MLDataTable {
        derived { try $0.split(fraction: proportion, seed: seed).0 }
    }

    /// The rows whose value of a column is one of `values`.
    public func intersect<T>(_ values: T..., of columnNamed: String) -> MLDataTable where T: MLDataValueConvertible {
        let wanted = Set(values.map(\.dataValue))
        return derived { table in
            let column = try table.column(name: columnNamed)
            return table.rows(at: column.values.indices.filter { wanted.contains(column.values[$0]) })
        }
    }

    /// The rows whose value of a column isn't one of `values`.
    public func exclude<T>(_ values: T..., of columnNamed: String) -> MLDataTable where T: MLDataValueConvertible {
        let unwanted = Set(values.map(\.dataValue))
        return derived { table in
            let column = try table.column(name: columnNamed)
            return table.rows(at: column.values.indices.filter { !unwanted.contains(column.values[$0]) })
        }
    }

    public func join(with: MLDataTable, on columnsNamed: String..., type: MLDataTable.JoinType = .inner) -> MLDataTable {
        let method: String
        switch type {
        case .inner: method = "inner"
        case .outer: method = "outer"
        case .left: method = "left"
        case .right: method = "right"
        }
        return MLDataTable(result: binaryDo(_result, with._result) { left, right in
            let keys = columnsNamed.isEmpty ? left.names.filter(right.names.contains) : columnsNamed
            return try CMLTable(joining: left, and: right, on: keys, method: method)
        })
    }

    public enum JoinType: Hashable, Sendable {
        case inner
        case outer
        case left
        case right
    }

    public subscript(mask: MLUntypedColumn) -> MLDataTable {
        MLDataTable(result: binaryDo(_result, mask._result) { table, mask in
            guard mask.count == table.rowCount else {
                throw MLCreateError.generic(reason: "A mask of \(mask.count) values can't filter a table of \(table.rowCount) rows.")
            }
            return table.rows(at: mask._impl.values.indices.filter { mask._impl.values[$0].isTrue })
        })
    }

    public subscript(mask: MLDataColumn<Bool>) -> MLDataTable {
        self[mask._untypedColumn]
    }

    /// The values a transform makes of each row.
    public func map<T>(_ lazyTransform: @escaping (MLDataTable.Row) -> T?) -> MLDataColumn<T> where T: MLDataValueConvertible {
        let rows = self.rows
        return MLDataColumn(from: MLUntypedColumn(result: unaryDo(_result) { _ in
            _UntypedColumn(impl: CMLColumn(values: rows.map { lazyTransform($0)?.dataValue ?? .invalid },
                                           type: CMLFeatureValueType(T.dataValueType)))
        }))
    }

    public func map<T>(_ lazyTransform: @escaping (MLDataTable.Row) -> T) -> MLDataColumn<T> where T: MLDataValueConvertible {
        map { row -> T? in lazyTransform(row) }
    }

    public func dropMissing() -> MLDataTable { derived { try $0.dropMissing() } }

    public func fillMissing(columnNamed: String, with value: MLDataValue) -> MLDataTable {
        derived { try $0.fillMissing(columnNamed: columnNamed, with: CMLFeatureValue(value: value)) }
    }

    public func dropDuplicates() -> MLDataTable { derived { try $0.dropDuplicates() } }
    public func prefix(_ maxLength: Int = 10) -> MLDataTable { derived { try $0.prefix(maxLength) } }
    public func suffix(_ maxLength: Int = 10) -> MLDataTable { derived { try $0.suffix(maxLength) } }

    /// The rows sorted by a column's values, missing ones last.
    public func sort(columnNamed: String, byIncreasingOrder: Bool = true) -> MLDataTable {
        derived { table in
            let column = try table.column(name: columnNamed)
            let order = column.values.indices.sorted { a, b in
                let x = column.values[a], y = column.values[b]
                if x.isValid != y.isValid { return x.isValid }
                let comparison = x.compare(y)
                if comparison == .orderedSame { return a < b }
                return comparison == (byIncreasingOrder ? .orderedAscending : .orderedDescending)
            }
            return table.rows(at: order)
        }
    }

    /// A row for each element of a sequence column's values, or each pair
    /// of a dictionary column's ([key, value] sequences), in column `to`.
    public func expand(columnNamed: String, to: String) -> MLDataTable {
        derived { table in
            let index = try table.index(of: columnNamed)
            let column = table.columnList[index]
            var rows: [Int] = [], elements: [MLDataValue] = []
            for (row, value) in column.values.enumerated() {
                switch value {
                case .sequence(let sequence):
                    for element in sequence { rows.append(row); elements.append(element) }
                case .dictionary(let dictionary):
                    for (key, element) in dictionary._contents {
                        rows.append(row); elements.append(.sequence(MLDataValue.SequenceType([key, element])))
                    }
                default:
                    rows.append(row); elements.append(.invalid)
                }
            }
            let result = table.rows(at: rows)
            try result.removeColumn(name: columnNamed)
            try result.addColumn(name: to, CMLColumn(values: elements))
            return result
        }
    }

    /// The rows that agree on every other column made one, the values of
    /// a column collected in a sequence column `to`.
    public func condense(columnNamed: String, to: String) -> MLDataTable {
        derived { table in
            let index = try table.index(of: columnNamed)
            let others = table.names.indices.filter { $0 != index }
            var order: [[MLDataValue]] = [], groups: [[MLDataValue]: [MLDataValue]] = [:]
            for row in 0..<table.rowCount {
                let key = others.map { table.columnList[$0].values[row] }
                if groups[key] == nil { order.append(key) }
                groups[key, default: []].append(table.columnList[index].values[row])
            }
            let result = CMLTable(names: others.map { table.names[$0] }, columns: others.enumerated().map { position, column in
                CMLColumn(values: order.map { $0[position] }, type: table.columnList[column].type)
            })
            try result.addColumn(name: to, CMLColumn(values: order.map { .sequence(MLDataValue.SequenceType(groups[$0]!)) },
                                                     type: .sequence))
            return result
        }
    }
}

@available(*, unavailable)
extension MLDataTable: Sendable {}

extension MLDataTable {
    public func show() -> any MLStreamingVisualizable {
        TextVisualization(text: description)
    }
}

extension MLDataTable: CustomStringConvertible, CustomPlaygroundDisplayConvertible {
    public var playgroundDescription: Any { description }

    public var description: String {
        switch _result {
        case .success(let table): return describeTable(table)
        case .failure(let error): return "Invalid table: \(error)"
        }
    }
}

// Column names.

extension MLDataTable {
    public struct ColumnNames: RandomAccessCollection {
        @usableFromInline
        let _names: CMLSequence

        @usableFromInline
        init(_names: CMLSequence) {
            self._names = _names
        }

        public var startIndex: Int { 0 }
        public var endIndex: Int { _names.values.count }

        public subscript(i: Int) -> String {
            _names.values[i].stringValue ?? _names.values[i].description
        }

        public typealias Element = String
        public typealias Index = Int
        public typealias Indices = Range<Int>
        public typealias Iterator = IndexingIterator<MLDataTable.ColumnNames>
        public typealias SubSequence = Slice<MLDataTable.ColumnNames>
    }

    public var columnNames: MLDataTable.ColumnNames {
        ColumnNames(_names: CMLSequence(values: (table?.names ?? []).map(MLDataValue.string)))
    }
}

@available(*, unavailable)
extension MLDataTable.ColumnNames: Sendable {}

extension MLDataTable.ColumnNames: Equatable {
    public static func == (lhs: MLDataTable.ColumnNames, rhs: MLDataTable.ColumnNames) -> Bool {
        Array(lhs) == Array(rhs)
    }
}

extension MLDataTable.ColumnNames: CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
    public var description: String { Array(self).description }
    public var debugDescription: String { "ColumnNames(\(description))" }
    public var playgroundDescription: Any { description }
}

// Writing.

extension MLDataTable {
    /// Writes the table to a directory, which `init(contentsOf:)` reads.
    public func write(to directoryURL: URL) throws {
        try TableFiles.writeDirectory(try getImpl(), to: directoryURL)
    }

    public func write(toDirectory path: String) throws {
        try write(to: URL(fileURLWithPath: path))
    }

    public func writeCSV(to fileURL: URL) throws {
        try TableFiles.writeCSV(try getImpl(), to: fileURL)
    }

    public func writeCSV(toFile path: String) throws {
        try writeCSV(to: URL(fileURLWithPath: path))
    }
}

// Rows.

extension MLDataTable {
    public var rows: MLDataTable.Rows { Rows(_table: self) }

    public struct Rows {
        @usableFromInline
        let _table: MLDataTable

        @usableFromInline
        init(_table: MLDataTable) {
            self._table = _table
        }
    }
}

@available(*, unavailable)
extension MLDataTable.Rows: Sendable {}

extension MLDataTable.Rows: RandomAccessCollection {
    public typealias Element = MLDataTable.Row

    public subscript(index: Int) -> MLDataTable.Rows.Element {
        let table = _table.table ?? CMLTable()
        let names = MLDataTable.ColumnNames(_names: CMLSequence(values: table.names.map(MLDataValue.string)))
        return MLDataTable.Row(_names: names, _indices: _table.columnIndexes,
                               _values: MLDataTable.Row.Values(_values: CMLSequence(values: table.rowValues(index))))
    }

    public var startIndex: Int { 0 }
    public var endIndex: Int { _table.size.rows }

    public typealias Index = Int
    public typealias Indices = Range<Int>
    public typealias Iterator = IndexingIterator<MLDataTable.Rows>
    public typealias SubSequence = Slice<MLDataTable.Rows>
}

extension MLDataTable.Rows: CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
    public var description: String { _table.description }
    public var debugDescription: String { "Rows(\(count))" }
    public var playgroundDescription: Any { description }
}

extension MLDataTable {
    public struct Row {
        public typealias Keys = MLDataTable.ColumnNames
        public typealias Key = MLDataTable.Row.Keys.Element
        public typealias Value = MLDataTable.Row.Values.Element

        @usableFromInline let _names: MLDataTable.ColumnNames
        @usableFromInline let _indices: [String: Int]
        @usableFromInline let _values: MLDataTable.Row.Values

        @usableFromInline
        init(_names: MLDataTable.ColumnNames, _indices: [String: Int], _values: MLDataTable.Row.Values) {
            self._names = _names
            self._indices = _indices
            self._values = _values
        }

        public var keys: MLDataTable.Row.Keys { _names }
        public var values: MLDataTable.Row.Values { _values }

        public subscript(name: MLDataTable.Row.Key) -> MLDataTable.Row.Value? {
            _indices[name].map { _values[$0] }
        }

        public subscript<T>(name: MLDataTable.Row.Key, type: T.Type) -> T? where T: MLDataValueConvertible {
            self[name].flatMap(T.init(from:))
        }
    }
}

@available(*, unavailable)
extension MLDataTable.Row: Sendable {}

extension MLDataTable.Row: Equatable {
    public static func == (lhs: MLDataTable.Row, rhs: MLDataTable.Row) -> Bool {
        lhs._names == rhs._names && lhs._values == rhs._values
    }
}

extension MLDataTable.Row: Collection {
    public typealias Element = (MLDataTable.Row.Key, MLDataTable.Row.Value)
    public typealias Index = Int

    public var count: Int { _values.count }
    public var isEmpty: Bool { _values.isEmpty }
    public var startIndex: Int { 0 }
    public var endIndex: Int { _values.count }

    public func index(after i: Int) -> Int { i + 1 }

    public func index(forKey key: MLDataTable.Row.Key) -> MLDataTable.Row.Index? {
        _indices[key]
    }

    public subscript(position: Int) -> (MLDataTable.Row.Key, MLDataTable.Row.Value) {
        (_names[position], _values[position])
    }

    public typealias Indices = DefaultIndices<MLDataTable.Row>
    public typealias Iterator = IndexingIterator<MLDataTable.Row>
    public typealias SubSequence = Slice<MLDataTable.Row>
}

extension MLDataTable.Row: CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
    public var description: String {
        "[" + zip(_names, _values).map { "\"\($0)\": \($1)" }.joined(separator: ", ") + "]"
    }

    public var debugDescription: String { "Row(\(description))" }
    public var playgroundDescription: Any { description }
}

extension MLDataTable.Row {
    public struct Values: RandomAccessCollection {
        @usableFromInline
        let _values: CMLSequence

        @usableFromInline
        init(_values: CMLSequence) {
            self._values = _values
        }

        public var startIndex: Int { 0 }
        public var endIndex: Int { _values.values.count }

        public subscript(i: Int) -> MLDataValue {
            _values.values[i]
        }

        public typealias Element = MLDataValue
        public typealias Index = Int
        public typealias Indices = Range<Int>
        public typealias Iterator = IndexingIterator<MLDataTable.Row.Values>
        public typealias SubSequence = Slice<MLDataTable.Row.Values>
    }
}

@available(*, unavailable)
extension MLDataTable.Row.Values: Sendable {}

extension MLDataTable.Row.Values: Equatable {
    public static func == (lhs: MLDataTable.Row.Values, rhs: MLDataTable.Row.Values) -> Bool {
        lhs._values.values == rhs._values.values
    }
}

extension MLDataTable.Row.Values: CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
    public var description: String { Array(self).description }
    public var debugDescription: String { "Values(\(description))" }
    public var playgroundDescription: Any { description }
}

// Reading files.

extension MLDataTable {
    /// The table a CSV or JSON file holds, or a directory `write(to:)`
    /// wrote.
    public init(contentsOf url: URL, options: MLDataTable.ParsingOptions = ParsingOptions()) throws {
        self.init(try CMLTable(from: url.path, isCSV: url.pathExtension.lowercased() != "json", options: options))
    }

    public struct ParsingOptions: Sendable {
        public var containsHeader: Bool
        public var delimiter: String
        public var comment: String
        public var escape: String
        public var doubleQuote: Bool
        public var quote: String
        public var skipInitialSpaces: Bool
        public var missingValues: [String]
        public var lineTerminator: String
        public var selectColumns: [String]?
        public var maxRows: Int?
        public var skipRows: Int

        public init(containsHeader: Bool = true, delimiter: String = ",", comment: String = "", escape: String = "\\",
                    doubleQuote: Bool = true, quote: String = "\"", skipInitialSpaces: Bool = true,
                    missingValues: [String] = ["NA"], lineTerminator: String = "\n", selectColumns: [String]? = nil,
                    maxRows: Int? = nil, skipRows: Int = 0) {
            self.containsHeader = containsHeader
            self.delimiter = delimiter
            self.comment = comment
            self.escape = escape
            self.doubleQuote = doubleQuote
            self.quote = quote
            self.skipInitialSpaces = skipInitialSpaces
            self.missingValues = missingValues
            self.lineTerminator = lineTerminator
            self.selectColumns = selectColumns
            self.maxRows = maxRows
            self.skipRows = skipRows
        }
    }
}

// Grouping.

extension MLDataTable {
    /// A row for each combination of the values of some columns, with the
    /// aggregators' results over the rows that have it.
    public func group<S>(columnsNamed: String..., aggregators: S) -> MLDataTable where S: Sequence, S.Element == MLDataTable.Aggregator {
        let aggregators = Array(aggregators)
        return derived { table in
            let keys = try columnsNamed.map { try table.index(of: $0) }
            var order: [[MLDataValue]] = [], groups: [[MLDataValue]: [Int]] = [:]
            for row in 0..<table.rowCount {
                let key = keys.map { table.columnList[$0].values[row] }
                if groups[key] == nil { order.append(key) }
                groups[key, default: []].append(row)
            }
            let result = CMLTable(names: columnsNamed, columns: keys.enumerated().map { position, column in
                CMLColumn(values: order.map { $0[position] }, type: table.columnList[column].type)
            })
            for aggregator in aggregators {
                let column = try table.column(name: aggregator.columnName)
                for operation in aggregator.operations {
                    let values = try order.map { key in
                        try operation.apply(to: groups[key]!, column: column, table: table)
                    }
                    try result.addColumn(name: operation.outputName(of: aggregator.columnName), CMLColumn(values: values))
                }
            }
            return result
        }
    }

    public struct Aggregator: Sendable {
        public var operations: [MLDataTable.Aggregator.Operations]
        public var columnName: String

        public init(operations: MLDataTable.Aggregator.Operations..., of columnNamed: String) {
            self.operations = operations
            self.columnName = columnNamed
        }

        public enum Operations: Sendable {
            case min
            case max
            case sum
            case mean
            case stdev
            case count
            case distinctCount
            case variance
            case sequenceMerge
            case randomlySelectOne
            case dictionaryMerge(valueColumn: String)
            case argmin(outputColumn: String)
            case argmax(outputColumn: String)
        }
    }
}

extension MLDataTable.Aggregator.Operations {
    /// The name of the column an operation on a column makes.
    func outputName(of column: String) -> String {
        switch self {
        case .min: return "Min of \(column)"
        case .max: return "Max of \(column)"
        case .sum: return "Sum of \(column)"
        case .mean: return "Mean of \(column)"
        case .stdev: return "Stdv of \(column)"
        case .count: return "Count"
        case .distinctCount: return "Distinct count of \(column)"
        case .variance: return "Variance of \(column)"
        case .sequenceMerge: return "Sequence merge of \(column)"
        case .randomlySelectOne: return "Random selection of \(column)"
        case .dictionaryMerge(let valueColumn): return "Dictionary of \(column) and \(valueColumn)"
        case .argmin(let output): return "Argmin of \(column) for \(output)"
        case .argmax(let output): return "Argmax of \(column) for \(output)"
        }
    }

    /// The operation's result over some rows of a column.
    func apply(to rows: [Int], column: CMLColumn, table: CMLTable) throws -> MLDataValue {
        let values = rows.map { column.values[$0] }.filter(\.isValid)
        let numbers = values.compactMap(\.number)
        func variance() -> Double? {
            guard !numbers.isEmpty else { return nil }
            let mean = numbers.reduce(0, +) / Double(numbers.count)
            return numbers.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(numbers.count)
        }
        switch self {
        case .min: return values.min { $0.compare($1) == .orderedAscending } ?? .invalid
        case .max: return values.max { $0.compare($1) == .orderedAscending } ?? .invalid
        case .sum:
            if column.type == .int64 { return .int(values.compactMap(\.intValue).reduce(0, &+)) }
            return .double(numbers.reduce(0, +))
        case .mean: return numbers.isEmpty ? .invalid : .double(numbers.reduce(0, +) / Double(numbers.count))
        case .stdev: return variance().map { .double($0.squareRoot()) } ?? .invalid
        case .variance: return variance().map(MLDataValue.double) ?? .invalid
        case .count: return .int(rows.count)
        case .distinctCount: return .int(Set(values).count)
        case .sequenceMerge:
            return .sequence(MLDataValue.SequenceType(values.flatMap { $0.sequenceValue.map(Array.init) ?? [$0] }))
        case .randomlySelectOne: return values.randomElement() ?? .invalid
        case .dictionaryMerge(let valueColumn):
            let valuesColumn = try table.column(name: valueColumn)
            var contents: [MLDataValue: MLDataValue] = [:]
            for row in rows where column.values[row].isValid { contents[column.values[row]] = valuesColumn.values[row] }
            return .dictionary(MLDataValue.DictionaryType(contents))
        case .argmin(let output), .argmax(let output):
            let outputColumn = try table.column(name: output)
            let wanted: ComparisonResult
            if case .argmin = self { wanted = .orderedAscending } else { wanted = .orderedDescending }
            let best = rows.filter { column.values[$0].isValid }.reduce(nil as Int?) { best, row in
                guard let best else { return row }
                return column.values[row].compare(column.values[best]) == wanted ? row : best
            }
            return best.map { outputColumn.values[$0] } ?? .invalid
        }
    }
}

// Splitting.

extension MLDataTable {
    /// The rows of about `proportion` of the sequences a column
    /// identifies, and the rows of the rest.
    public func randomSplitBySequence(proportion: Double, by sequenceIdentifierColumn: String, on column: String,
                                      seed: Int = 1) -> (MLDataTable, remaining: MLDataTable) {
        var generator = SeededGenerator(seed: seed)
        let split = unaryDo(_result) { table -> (CMLTable, CMLTable) in
            let identifiers = try table.column(name: sequenceIdentifierColumn)
            _ = try table.column(name: column)
            var chosen: [MLDataValue: Bool] = [:]
            var first: [Int] = [], second: [Int] = []
            for row in 0..<table.rowCount {
                let identifier = identifiers.values[row]
                if chosen[identifier] == nil { chosen[identifier] = Double.random(in: 0..<1, using: &generator) < proportion }
                if chosen[identifier]! { first.append(row) } else { second.append(row) }
            }
            return (table.rows(at: first), table.rows(at: second))
        }
        return (MLDataTable(result: unaryDo(split) { $0.0 }), MLDataTable(result: unaryDo(split) { $0.1 }))
    }

    public func randomSplit(by proportion: Double, seed: Int = 1) -> (MLDataTable, MLDataTable) {
        let split = unaryDo(_result) { try $0.split(fraction: proportion, seed: seed) }
        return (MLDataTable(result: unaryDo(split) { $0.0 }), MLDataTable(result: unaryDo(split) { $0.1 }))
    }

    /// The table with a column "split" that assigns each row to one of
    /// the proportions, keeping each value of a column in the same
    /// proportions.
    public func stratifiedSplit(proportions: [Double], on column: String, seed: Int = timestampSeed()) throws -> MLDataTable {
        var generator = SeededGenerator(seed: seed)
        return try stratifiedSplit(proportions: proportions, on: column, generator: &generator)
    }

    public func stratifiedSplit<RNG>(proportions: [Double], on column: String, generator: inout RNG) throws -> MLDataTable where RNG: RandomNumberGenerator {
        let table = try getImpl()
        let values = try table.column(name: column).values
        var groups: [MLDataValue: [Int]] = [:]
        for (row, value) in values.enumerated() { groups[value, default: []].append(row) }
        var assignment = [MLDataValue](repeating: .int(0), count: table.rowCount)
        for key in groups.keys.sorted(by: { $0.compare($1) == .orderedAscending }) {
            let rows = groups[key]!.shuffled(using: &generator)
            for (part, range) in Self.parts(of: rows.count, proportions: proportions).enumerated() {
                for index in range { assignment[rows[index]] = .int(part) }
            }
        }
        let result = table.copy()
        try result.addColumn(name: "split", CMLColumn(values: assignment, type: .int64))
        return MLDataTable(result)
    }

    public func stratifiedSplitBySequence<RNG>(proportions: [Double], by sequenceIdentifierColumn: String, on column: String,
                                               generator: inout RNG) throws -> MLDataTable where RNG: RandomNumberGenerator {
        let table = try getImpl()
        let identifiers = try table.column(name: sequenceIdentifierColumn).values
        let labels = try table.column(name: column).values
        // Each sequence goes to one part, by its first row's label.
        var sequences: [MLDataValue: MLDataValue] = [:], order: [MLDataValue] = []
        for (row, identifier) in identifiers.enumerated() where sequences[identifier] == nil {
            sequences[identifier] = labels[row]
            order.append(identifier)
        }
        var groups: [MLDataValue: [MLDataValue]] = [:]
        for identifier in order { groups[sequences[identifier]!, default: []].append(identifier) }
        var part: [MLDataValue: Int] = [:]
        for key in groups.keys.sorted(by: { $0.compare($1) == .orderedAscending }) {
            let members = groups[key]!.shuffled(using: &generator)
            for (index, range) in Self.parts(of: members.count, proportions: proportions).enumerated() {
                for member in range { part[members[member]] = index }
            }
        }
        let result = table.copy()
        try result.addColumn(name: "split", CMLColumn(values: identifiers.map { .int(part[$0] ?? 0) }, type: .int64))
        return MLDataTable(result)
    }

    public func stratifiedSplitBySequence(proportions: [Double], by sequenceIdentifierColumn: String, on column: String,
                                          seed: Int = timestampSeed()) throws -> MLDataTable {
        var generator = SeededGenerator(seed: seed)
        return try stratifiedSplitBySequence(proportions: proportions, by: sequenceIdentifierColumn, on: column, generator: &generator)
    }

    /// Ranges of `count` items in the proportions given.
    static func parts(of count: Int, proportions: [Double]) -> [Range<Int>] {
        let total = proportions.reduce(0, +)
        guard total > 0 else { return [0..<count] }
        var ranges: [Range<Int>] = [], start = 0, cumulative = 0.0
        for (index, proportion) in proportions.enumerated() {
            cumulative += proportion
            let end = index == proportions.count - 1 ? count : Int((cumulative / total * Double(count)).rounded())
            ranges.append(start..<max(start, end))
            start = max(start, end)
        }
        return ranges
    }
}

// Packing and unpacking.

extension MLDataTable {
    /// Columns made into one of sequences or dictionaries, their missing
    /// values filled.
    public func pack(columnsNamed: String..., to: String, type: MLDataTable.PackType = .sequence,
                     filling: MLDataValue = MLDataValue.invalid) -> MLDataTable {
        derived { table in
            let indices = try columnsNamed.map { try table.index(of: $0) }
            let packed: [MLDataValue] = (0..<table.rowCount).map { row in
                let values = indices.map { index -> MLDataValue in
                    let value = table.columnList[index].values[row]
                    return value.isValid ? value : filling
                }
                switch type {
                case .sequence:
                    return .sequence(MLDataValue.SequenceType(values))
                case .dictionary:
                    var contents: [MLDataValue: MLDataValue] = [:]
                    for (name, value) in zip(columnsNamed, values) where value.isValid { contents[.string(name)] = value }
                    return .dictionary(MLDataValue.DictionaryType(contents))
                }
            }
            let result = table.copy()
            for name in columnsNamed { try result.removeColumn(name: name) }
            try result.addColumn(name: to, CMLColumn(values: packed, type: type == .sequence ? .sequence : .dictionary))
            return result
        }
    }

    /// A sequence or dictionary column made into a column for each index
    /// or key, named "column.index" or "column.key".
    public func unpack(columnNamed: String, valueTypes: [MLDataValue.ValueType]? = nil, indexSubset: [Int]? = nil,
                       keySubset: [String]? = nil) -> MLDataTable {
        derived { table in
            let values = try table.column(name: columnNamed).values
            let result = table.copy()
            try result.removeColumn(name: columnNamed)
            var keys: [MLDataValue] = []
            if values.contains(where: { $0.type == .dictionary }) {
                var seen = Set<MLDataValue>()
                for value in values { for key in value.dictionaryValue?._contents.keys.sorted(by: { $0.compare($1) == .orderedAscending }) ?? [] where seen.insert(key).inserted { keys.append(key) } }
                if let keySubset { keys = keySubset.map(MLDataValue.string) }
            } else {
                let width = values.map { $0.sequenceValue?.count ?? 0 }.max() ?? 0
                keys = (indexSubset ?? Array(0..<width)).map(MLDataValue.int)
            }
            for (position, key) in keys.enumerated() {
                let column = values.map { value -> MLDataValue in
                    if let dictionary = value.dictionaryValue { return dictionary[key] ?? .invalid }
                    if let sequence = value.sequenceValue, let index = key.intValue, sequence.indices.contains(index) { return sequence[index] }
                    return .invalid
                }
                let type = valueTypes.flatMap { position < $0.count ? CMLFeatureValueType($0[position]) : nil }
                try result.addColumn(name: "\(columnNamed).\(key.stringValue ?? key.description)",
                                     type.map { CMLColumn(values: column, type: $0) } ?? CMLColumn(values: column))
            }
            return result
        }
    }

    public enum PackType: Hashable, Sendable {
        case sequence
        case dictionary
    }
}

/// A seed from the current time.
public func timestampSeed() -> Int {
    Int(Date().timeIntervalSince1970 * 1000)
}

// Grouping rows by keys: RowGrouping, its aggregations and summaries, and
// random and stratified splits.

import Foundation

public protocol RowGroupingProtocol: CustomStringConvertible {
    var count: Int { get }
    func ungrouped() -> DataFrame
    func counts(order: Order?) -> DataFrame
    func aggregated<Element, Result>(on columnNames: [String], naming: (String) -> String,
                                     transform: (DiscontiguousColumnSlice<Element>) throws -> Result?) rethrows -> DataFrame
    func filter(_ isIncluded: (DataFrame.Slice) throws -> Bool) rethrows -> Self
    func mapGroups(_ transform: (DataFrame.Slice) throws -> DataFrame) rethrows -> Self
    func randomSplit(by proportion: Double, seed: Int?) -> (Self, Self)
    func summary() -> any GroupSummaries
    func summary(of columnNames: [String]) -> any GroupSummaries
    subscript(keys: Any?...) -> DataFrame.Slice? { get }
}

public protocol GroupSummaries: CustomStringConvertible {
    subscript(keys: Any?...) -> DataFrame? { get }
    var description: String { get }
    func description(options: FormattingOptions) -> String
}

/// A random number generator from a seed (SplitMix64), for reproducible splits.
internal struct _SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    init(seed: Int) {
        state = UInt64(bitPattern: Int64(seed))
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Indices split in two at random: the first proportion of them, and the rest, each in order.
internal func _randomSplit<G: RandomNumberGenerator>(_ indices: [Int], _ proportion: Double, using generator: inout G) -> ([Int], [Int]) {
    let shuffled = indices.shuffled(using: &generator)
    let count = Swift.min(Swift.max(Int(Double(indices.count) * proportion), 0), indices.count)
    return (shuffled.prefix(count).sorted(), shuffled.dropFirst(count).sorted())
}

internal func _randomSplit(_ indices: [Int], _ proportion: Double, seed: Int?) -> ([Int], [Int]) {
    if let seed {
        var generator = _SeededGenerator(seed: seed)
        return _randomSplit(indices, proportion, using: &generator)
    }
    var generator = SystemRandomNumberGenerator()
    return _randomSplit(indices, proportion, using: &generator)
}

/// The key of a group of several columns: their values.
internal struct _CompositeKey: Hashable {
    var values: [AnyHashable?]
}

/// Row indices grouped by key, groups in order of their first row.
internal func _groupIndices<K: Hashable>(_ rows: [Int], _ key: (Int) -> K?) -> [(key: K?, rows: [Int])] {
    var positions: [K?: Int] = [:]
    var groups: [(key: K?, rows: [Int])] = []
    for row in rows {
        let value = key(row)
        if let position = positions[value] {
            groups[position].rows.append(row)
        } else {
            positions[value] = groups.count
            groups.append((value, [row]))
        }
    }
    return groups
}

public struct RowGrouping<GroupingKey>: RowGroupingProtocol where GroupingKey: Hashable {
    public typealias Element = (key: GroupingKey?, group: DataFrame.Slice)
    public typealias Index = Int
    public typealias Indices = Range<Int>
    public typealias Iterator = IndexingIterator<RowGrouping<GroupingKey>>
    public typealias SubSequence = Slice<RowGrouping<GroupingKey>>

    internal var _groups: [(key: GroupingKey?, group: DataFrame.Slice)]
    internal var _keyColumnName: String
    /// For keys of several columns: prototypes of the key columns.
    internal var _keyPrototypes: [any AnyColumnPrototype]?

    public init<D>(groups: [(GroupingKey?, D)], groupKeysColumnName: String) where D: DataFrameProtocol {
        _groups = groups.map { ($0.0, DataFrame.Slice(base: $0.1.base, ranges: $0.1.rows.subranges)) }
        _keyColumnName = groupKeysColumnName
        _keyPrototypes = nil
    }

    internal init(_groups groups: [(key: GroupingKey?, group: DataFrame.Slice)], keyColumnName: String,
                  keyPrototypes: [any AnyColumnPrototype]?) {
        _groups = groups
        _keyColumnName = keyColumnName
        _keyPrototypes = keyPrototypes
    }

    /// Groups the rows of a frame by a key of each row.
    internal init(base: DataFrame, rows: [Int], keyColumnName: String, keyPrototypes: [any AnyColumnPrototype]? = nil,
                  key: (Int) -> GroupingKey?) {
        _groups = _groupIndices(rows, key).map { ($0.key, DataFrame.Slice(base: base, ranges: _RangeSet(sortedIndices: $0.rows))) }
        _keyColumnName = keyColumnName
        _keyPrototypes = keyPrototypes
    }

    internal var _keyColumnNames: [String] {
        _keyPrototypes?.map(\.name) ?? [_keyColumnName]
    }

    /// Columns of the keys given, one per key column.
    internal func _keyColumns<S: Sequence>(_ keys: S) -> [AnyColumn] where S.Element == GroupingKey? {
        if let prototypes = _keyPrototypes {
            let keys = Array(keys)
            var columns = prototypes.map { $0.makeColumn(capacity: keys.count) }
            for key in keys {
                let values = (key as? _CompositeKey)?.values ?? Array(repeating: nil, count: columns.count)
                for i in columns.indices { columns[i].append(values[i]?.base) }
            }
            return columns
        }
        return [Column<GroupingKey>(name: _keyColumnName, contents: keys).eraseToAnyColumn()]
    }

    /// A frame of the key columns and a count of each group's rows.
    internal func _counts(named name: String, order: Order?) -> DataFrame {
        var frame = DataFrame(columns: _keyColumns(_groups.map(\.key)))
        frame.append(column: Column(name: name, contents: _groups.map(\.group.shape.rows)))
        if let order { frame.sort(on: ColumnID(name, Int.self), order: order) }
        return frame
    }

    public var description: String {
        _counts(named: "rows", order: nil).description
    }

    public func counts(order: Order? = nil) -> DataFrame {
        _counts(named: "count", order: order)
    }

    public func aggregated<Element, Result>(on columnNames: [String], naming: (String) -> String,
                                            transform: (DiscontiguousColumnSlice<Element>) throws -> Result?) rethrows -> DataFrame {
        var frame = DataFrame(columns: _keyColumns(_groups.map(\.key)))
        for name in columnNames {
            var column = Column<Result>(name: naming(name), capacity: _groups.count)
            for group in _groups { column.append(try transform(group.group[name, Element.self])) }
            frame.append(column: column)
        }
        return frame
    }

    public func ungrouped() -> DataFrame {
        var result: DataFrame?
        let keyNames = Set(_keyColumnNames)
        for (key, group) in _groups {
            var frame = DataFrame(group)
            frame._columns.removeAll { keyNames.contains($0.name) }
            let keyColumns = _keyColumns(repeatElement(key, count: frame.shape.rows))
            if frame._columns.isEmpty {
                frame = DataFrame(columns: keyColumns)
            } else {
                for column in keyColumns { frame.append(column: column) }
            }
            if result == nil {
                result = frame
            } else {
                result!.append(frame)
            }
        }
        return result ?? DataFrame()
    }

    public func filter(_ isIncluded: (DataFrame.Slice) throws -> Bool) rethrows -> RowGrouping<GroupingKey> {
        RowGrouping(_groups: try _groups.filter { try isIncluded($0.group) }, keyColumnName: _keyColumnName,
                    keyPrototypes: _keyPrototypes)
    }

    public func mapGroups(_ transform: (DataFrame.Slice) throws -> DataFrame) rethrows -> RowGrouping<GroupingKey> {
        let groups = try _groups.map { group -> (key: GroupingKey?, group: DataFrame.Slice) in
            let frame = try transform(group.group)
            return (group.key, DataFrame.Slice(base: frame, ranges: _RangeSet(0 ..< frame.shape.rows)))
        }
        return RowGrouping(_groups: groups, keyColumnName: _keyColumnName, keyPrototypes: _keyPrototypes)
    }

    /// The group whose key matches the values given.
    public subscript(keys: Any?...) -> DataFrame.Slice? {
        if _keyPrototypes != nil {
            for group in _groups {
                guard let key = group.key as? _CompositeKey, key.values.count == keys.count else { continue }
                if zip(key.values, keys).allSatisfy({ _valuesEqual($0.map { $0.base }, $1) }) { return group.group }
            }
            return nil
        }
        guard keys.count == 1, let key = keys[0] as? GroupingKey else { return nil }
        return _groups.first { $0.key == key }?.group
    }

    internal func _summaries(of columnNames: [String]?) -> any GroupSummaries {
        let keyNames = Set(_keyColumnNames)
        var entries: [(key: GroupingKey?, summary: DataFrame)] = []
        var combined: DataFrame?
        for (key, group) in _groups {
            let base = group._base
            let columns = columnNames.map { $0.map(base._requireColumn) }
                ?? base._columns.indices.filter { !keyNames.contains(base._columns[$0].name) }
            let summary = _summary(of: base, columns: columns, rows: group._set.indices)
            entries.append((key, summary))
            var frame = DataFrame(columns: _keyColumns(repeatElement(key, count: summary.shape.rows)))
            for column in summary._columns { frame.append(column: column) }
            if combined == nil { combined = frame } else { combined!.append(frame) }
        }
        return _GroupSummaries(frame: combined ?? DataFrame()) { keys in
            if self._keyPrototypes != nil {
                return entries.first { entry in
                    guard let key = entry.key as? _CompositeKey, key.values.count == keys.count else { return false }
                    return zip(key.values, keys).allSatisfy { _valuesEqual($0.map { $0.base }, $1) }
                }?.summary
            }
            guard keys.count == 1, let key = keys[0] as? GroupingKey else { return nil }
            return entries.first { $0.key == key }?.summary
        }
    }

}

extension RowGrouping {
    /// Splits each group's rows at random in the proportion given; both
    /// groupings have every group.
    public func randomSplit(by proportion: Double, seed: Int? = nil) -> (RowGrouping<GroupingKey>, RowGrouping<GroupingKey>) {
        var generator: any RandomNumberGenerator = seed.map { _SeededGenerator(seed: $0) as any RandomNumberGenerator }
            ?? SystemRandomNumberGenerator()
        var first: [(key: GroupingKey?, group: DataFrame.Slice)] = [], second: [(key: GroupingKey?, group: DataFrame.Slice)] = []
        for (key, group) in _groups {
            let (a, b) = _randomSplit(group._set.indices, proportion, using: &generator)
            first.append((key, DataFrame.Slice(base: group._base, ranges: _RangeSet(sortedIndices: a))))
            second.append((key, DataFrame.Slice(base: group._base, ranges: _RangeSet(sortedIndices: b))))
        }
        return (RowGrouping(_groups: first, keyColumnName: _keyColumnName, keyPrototypes: _keyPrototypes),
                RowGrouping(_groups: second, keyColumnName: _keyColumnName, keyPrototypes: _keyPrototypes))
    }
}

extension RowGrouping {
    public init<D>(frame: D, columnName: String, timeUnit: Calendar.Component) where GroupingKey == Int, D: DataFrameProtocol {
        let column = frame.base[columnName, Date.self]
        let calendar = Calendar.current
        self.init(base: frame.base, rows: frame._rowIndices, keyColumnName: columnName) { row in
            column[row].map { calendar.component(timeUnit, from: $0) }
        }
    }
}

extension RowGrouping: RandomAccessCollection {
    public var startIndex: Int {
        0
    }

    public var endIndex: Int {
        _groups.count
    }

    public func index(after i: Int) -> Int {
        i + 1
    }

    public func index(before i: Int) -> Int {
        i - 1
    }

    public var count: Int {
        _groups.count
    }

    public subscript(position: Int) -> (key: GroupingKey?, group: DataFrame.Slice) {
        _groups[position]
    }
}

extension RowGrouping {
    public func summary() -> any GroupSummaries {
        _summaries(of: nil)
    }

    public func summary(of columnNames: [String]) -> any GroupSummaries {
        _summaries(of: columnNames)
    }
}

/// Summaries of each group's columns, in one frame with the key columns first.
internal struct _GroupSummaries: GroupSummaries {
    let frame: DataFrame
    let lookup: ([Any?]) -> DataFrame?

    subscript(keys: Any?...) -> DataFrame? {
        lookup(keys)
    }

    var description: String {
        frame.description
    }

    func description(options: FormattingOptions) -> String {
        frame.description(options: options)
    }
}

extension RowGroupingProtocol {
    public func counts() -> DataFrame {
        counts(order: nil)
    }

    /// An aggregation of one column, sorted by its value if an order is given.
    private func _aggregated<N: Comparable>(_ name: String, _ type: N.Type, prefix: String, order: Order?, _ transform: (DiscontiguousColumnSlice<N>) -> N?) -> DataFrame {
        let resultName = "\(prefix)(\(name))"
        var frame = aggregated(on: [name], naming: { _ in resultName }, transform: transform)
        if let order { frame.sort(on: ColumnID(resultName, N.self), order: order) }
        return frame
    }

    public func sums<N>(_ columnName: String, _ type: N.Type, order: Order? = nil) -> DataFrame where N: AdditiveArithmetic, N: Comparable {
        _aggregated(columnName, N.self, prefix: "sum", order: order) { $0.sum() }
    }

    public func sums<N>(_ columnID: ColumnID<N>, order: Order? = nil) -> DataFrame where N: AdditiveArithmetic, N: Comparable {
        sums(columnID.name, N.self, order: order)
    }

    public func means<N>(_ columnName: String, _ type: N.Type, order: Order? = nil) -> DataFrame where N: FloatingPoint {
        _aggregated(columnName, N.self, prefix: "mean", order: order) { $0.mean() }
    }

    public func means<N>(_ columnID: ColumnID<N>, order: Order? = nil) -> DataFrame where N: FloatingPoint {
        means(columnID.name, N.self, order: order)
    }

    public func quantiles<N>(_ columnName: String, _ type: N.Type, quantile: N, order: Order? = nil) -> DataFrame where N: BinaryFloatingPoint {
        _aggregated(columnName, N.self, prefix: "quantile", order: order) { (slice: DiscontiguousColumnSlice<N>) -> N? in
            let values = slice.compactMap { $0 }.sorted()
            return values.isEmpty ? nil : _quantile(values, quantile)
        }
    }

    public func quantiles<N>(_ columnID: ColumnID<N>, quantile: N, order: Order? = nil) -> DataFrame where N: BinaryFloatingPoint {
        quantiles(columnID.name, N.self, quantile: quantile, order: order)
    }

    public func minimums<N>(_ columnName: String, _ type: N.Type, order: Order? = nil) -> DataFrame where N: Comparable {
        _aggregated(columnName, N.self, prefix: "min", order: order) { $0.min() }
    }

    public func minimums<N>(_ columnID: ColumnID<N>, order: Order? = nil) -> DataFrame where N: Comparable {
        minimums(columnID.name, N.self, order: order)
    }

    public func maximums<N>(_ columnName: String, _ type: N.Type, order: Order? = nil) -> DataFrame where N: Comparable {
        _aggregated(columnName, N.self, prefix: "max", order: order) { $0.max() }
    }

    public func maximums<N>(_ columnID: ColumnID<N>, order: Order? = nil) -> DataFrame where N: Comparable {
        maximums(columnID.name, N.self, order: order)
    }

    public func aggregated<Element, Result>(on columnNames: String..., naming: (String) -> String,
                                            transform: (DiscontiguousColumnSlice<Element>) throws -> Result?) rethrows -> DataFrame {
        try aggregated(on: columnNames, naming: naming, transform: transform)
    }

    public func aggregated<Element, Result>(on columnID: ColumnID<Element>, into aggregatedColumnName: String? = nil,
                                            transform: (DiscontiguousColumnSlice<Element>) throws -> Result) rethrows -> DataFrame {
        try aggregated(on: [columnID.name], naming: { aggregatedColumnName ?? "aggregate(\($0))" }) { slice -> Result? in
            try transform(slice)
        }
    }

    public func randomSplit(by proportion: Double) -> (Self, Self) {
        randomSplit(by: proportion, seed: nil)
    }

    public func summary(of columnNames: String...) -> any GroupSummaries {
        summary(of: columnNames)
    }
}

// MARK: - Grouping frames

/// Groups the rows of a frame by a column whose type is only known to be hashable at run time.
internal func _groupedDynamically(_ base: DataFrame, rows: [Int], by columnName: String) -> any RowGroupingProtocol {
    let column = base[columnName]
    guard let type = column.wrappedElementType as? any Hashable.Type else {
        fatalError("Column '\(column.name)' of type \(column.wrappedElementType) isn't hashable.")
    }
    func typed<T: Hashable>(_ type: T.Type) -> any RowGroupingProtocol {
        let typedColumn = column.assumingType(T.self)
        return RowGrouping<T>(base: base, rows: rows, keyColumnName: column.name) { typedColumn[$0] }
    }
    return typed(type)
}

/// Groups the rows of a frame by the values of several columns.
internal func _groupedByColumns(_ base: DataFrame, rows: [Int], by columnNames: [String]) -> RowGrouping<_CompositeKey> {
    let columns = columnNames.map { base[$0] }
    return RowGrouping(base: base, rows: rows, keyColumnName: columnNames.joined(separator: ", "),
                       keyPrototypes: columns.map(\.prototype)) { row in
        _CompositeKey(values: columns.map { column in
            column.isNil(at: row) ? nil : (column._box.hashable(row) ?? AnyHashable(String(reflecting: column[row]!)))
        })
    }
}

extension DataFrame {
    public func grouped(by columnName: String) -> any RowGroupingProtocol {
        _groupedDynamically(self, rows: Array(0 ..< _rowCount), by: columnName)
    }
}

extension DataFrame.Slice {
    public func grouped(by columnName: String) -> any RowGroupingProtocol {
        _groupedDynamically(_base, rows: _set.indices, by: columnName)
    }
}

extension DataFrameProtocol {
    public func grouped<GroupingKey>(by columnID: ColumnID<GroupingKey>) -> RowGrouping<GroupingKey> where GroupingKey: Hashable {
        let column = base[columnID]
        return RowGrouping(base: base, rows: _rowIndices, keyColumnName: column.name) { column[$0] }
    }

    public func grouped<InputKey, GroupingKey>(by columnName: String, transform: (InputKey?) -> GroupingKey?) -> RowGrouping<GroupingKey>
    where GroupingKey: Hashable {
        let column = base[columnName, InputKey.self]
        return RowGrouping(base: base, rows: _rowIndices, keyColumnName: column.name) { transform(column[$0]) }
    }

    public func grouped<InputKey, GroupingKey>(by columnID: ColumnID<InputKey>, transform: (InputKey?) -> GroupingKey?) -> RowGrouping<GroupingKey>
    where GroupingKey: Hashable {
        grouped(by: columnID.name, transform: transform)
    }

    public func grouped(by columnName: String, timeUnit: Calendar.Component) -> RowGrouping<Int> {
        RowGrouping(frame: self, columnName: columnName, timeUnit: timeUnit)
    }

    public func grouped(by columnID: ColumnID<Date>, timeUnit: Calendar.Component) -> RowGrouping<Int> {
        RowGrouping(frame: self, columnName: columnID.name, timeUnit: timeUnit)
    }

    public func grouped(by columnNames: String...) -> some RowGroupingProtocol {
        _groupedByColumns(base, rows: _rowIndices, by: columnNames)
    }

    @_disfavoredOverload
    public func grouped<T>(by columnIDs: ColumnID<T>...) -> some RowGroupingProtocol where T: Hashable {
        _groupedByColumns(base, rows: _rowIndices, by: columnIDs.map(\.name))
    }

    public func grouped<T0, T1>(by column0: ColumnID<T0>, _ column1: ColumnID<T1>) -> some RowGroupingProtocol
    where T0: Hashable, T1: Hashable {
        _groupedByColumns(base, rows: _rowIndices, by: [column0.name, column1.name])
    }

    public func grouped<T0, T1, T2>(by column0: ColumnID<T0>, _ column1: ColumnID<T1>, _ column2: ColumnID<T2>) -> some RowGroupingProtocol
    where T0: Hashable, T1: Hashable, T2: Hashable {
        _groupedByColumns(base, rows: _rowIndices, by: [column0.name, column1.name, column2.name])
    }
}

// MARK: - Splits

extension DataFrameProtocol {
    public func randomSplit(by proportion: Double, seed: Int? = nil) -> (DataFrame.Slice, DataFrame.Slice) {
        let (first, second) = _randomSplit(_rowIndices, proportion, seed: seed)
        return (DataFrame.Slice(base: base, ranges: _RangeSet(sortedIndices: first)),
                DataFrame.Slice(base: base, ranges: _RangeSet(sortedIndices: second)))
    }

    public func randomSplit<G>(by proportion: Double, using generator: inout G) -> (DataFrame.Slice, DataFrame.Slice)
    where G: RandomNumberGenerator {
        let (first, second) = _randomSplit(_rowIndices, proportion, using: &generator)
        return (DataFrame.Slice(base: base, ranges: _RangeSet(sortedIndices: first)),
                DataFrame.Slice(base: base, ranges: _RangeSet(sortedIndices: second)))
    }

    /// Splits each group's rows at random in the proportion given; each
    /// side's groups are then ungrouped (the key columns last).
    internal func _stratifiedSplit<K: Hashable>(_ grouping: RowGrouping<K>, _ proportion: Double, _ seed: Int?) -> (DataFrame, DataFrame) {
        let (first, second) = grouping.randomSplit(by: proportion, seed: seed)
        return (first.ungrouped(), second.ungrouped())
    }

    public func stratifiedSplit(on columnName: String, by proportion: Double, randomSeed: Int? = nil) -> (DataFrame, DataFrame) {
        stratifiedSplit(on: [columnName], by: proportion, randomSeed: randomSeed)
    }

    public func stratifiedSplit(on columnNames: String..., by proportion: Double, randomSeed: Int? = nil) -> (DataFrame, DataFrame) {
        stratifiedSplit(on: columnNames, by: proportion, randomSeed: randomSeed)
    }

    internal func stratifiedSplit(on columnNames: [String], by proportion: Double, randomSeed: Int?) -> (DataFrame, DataFrame) {
        if columnNames.count == 1 {
            let column = base[columnNames[0]]
            guard let type = column.wrappedElementType as? any Hashable.Type else {
                fatalError("Column '\(column.name)' of type \(column.wrappedElementType) isn't hashable.")
            }
            func typed<T: Hashable>(_ type: T.Type) -> (DataFrame, DataFrame) {
                _stratifiedSplit(grouped(by: ColumnID(columnNames[0], T.self)), proportion, randomSeed)
            }
            return typed(type)
        }
        return _stratifiedSplit(_groupedByColumns(base, rows: _rowIndices, by: columnNames), proportion, randomSeed)
    }

    public func stratifiedSplit<T>(on columnID: ColumnID<T>, by proportion: Double, randomSeed: Int? = nil) -> (DataFrame, DataFrame)
    where T: Hashable {
        _stratifiedSplit(grouped(by: columnID), proportion, randomSeed)
    }

    public func stratifiedSplit<T0, T1>(on columnID0: ColumnID<T0>, _ columnID1: ColumnID<T1>, by proportion: Double,
                                        randomSeed: Int? = nil) -> (DataFrame, DataFrame) where T0: Hashable, T1: Hashable {
        stratifiedSplit(on: [columnID0.name, columnID1.name], by: proportion, randomSeed: randomSeed)
    }

    public func stratifiedSplit<T0, T1, T2>(on columnID0: ColumnID<T0>, _ columnID1: ColumnID<T1>, _ columnID2: ColumnID<T2>,
                                            by proportion: Double, randomSeed: Int? = nil) -> (DataFrame, DataFrame)
    where T0: Hashable, T1: Hashable, T2: Hashable {
        stratifiedSplit(on: [columnID0.name, columnID1.name, columnID2.name], by: proportion, randomSeed: randomSeed)
    }
}

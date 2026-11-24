// DataFrame: columns of equal length, by name, with rows.

import Foundation

@dynamicMemberLookup
public struct DataFrame: DataFrameProtocol {
    public typealias ColumnType = AnyColumn

    internal var _columns: [AnyColumn]
    /// Alias names of columns, each to the names it stands for.
    internal var _aliases: [String: [String]]

    public var columns: [AnyColumn] {
        _columns
    }

    internal var _rowCount: Int {
        _columns.first?.count ?? 0
    }

    public var rows: Rows {
        get {
            Rows(base: self, subranges: _RangeSet(0 ..< _rowCount))
        }
        set {
            self = newValue.base
        }
    }

    public var shape: (rows: Int, columns: Int) {
        (_rowCount, _columns.count)
    }

    public var base: DataFrame {
        self
    }

    public init() {
        _columns = []
        _aliases = [:]
    }

    public init<S>(columns: S) where S: Sequence, S.Element == AnyColumn {
        self.init()
        for column in columns { append(column: column) }
    }

    public init(_ other: Slice) {
        self = other._base._gathering(other._set.indices)
    }

    internal init(_columns columns: [AnyColumn]) {
        _columns = columns
        _aliases = [:]
    }

    /// A frame of the base's rows at the indices given, all rows nil where an index is.
    internal func _gathering(_ indices: [Int?]) -> DataFrame {
        DataFrame(_columns: _columns.map { $0._gathering(indices) })
    }

    internal func _gathering(_ indices: [Int]) -> DataFrame {
        DataFrame(_columns: _columns.map { $0._gathering(indices) })
    }

    public func indexOfColumn(_ columnName: String) -> Int? {
        if let index = _columns.firstIndex(where: { $0.name == columnName }) { return index }
        if let names = _aliases[columnName] {
            for name in names {
                if let index = _columns.firstIndex(where: { $0.name == name }) { return index }
            }
        }
        return nil
    }

    internal func _requireColumn(_ name: String) -> Int {
        guard let index = indexOfColumn(name) else {
            fatalError("There is no column named '\(name)' in the DataFrame.")
        }
        return index
    }

    public func containsColumn<T>(_ id: ColumnID<T>) -> Bool {
        guard let index = indexOfColumn(id.name) else { return false }
        return columns[index].wrappedElementType == T.self
    }

    public func containsColumn<T>(_ name: String, _ type: T.Type) -> Bool {
        guard let index = indexOfColumn(name) else { return false }
        return columns[index].wrappedElementType == T.self
    }

    public func containsColumn(_ name: String) -> Bool {
        indexOfColumn(name) != nil
    }

    public func columnNames(forAlias alias: String) -> [String] {
        _aliases[alias] ?? []
    }

    public mutating func addAlias(_ alias: String, forColumn columnName: String) {
        precondition(indexOfColumn(columnName) != nil, "There is no column named '\(columnName)' in the DataFrame.")
        var names = _aliases[alias] ?? []
        if !names.contains(columnName) { names.append(columnName) }
        _aliases[alias] = names
    }

    public mutating func removeAlias(_ alias: String) {
        _aliases[alias] = nil
    }

    public mutating func append<T>(column: Column<T>) {
        append(column: column.eraseToAnyColumn())
    }

    public mutating func append(column: AnyColumn) {
        insert(column: column, at: _columns.count)
    }

    public mutating func insert<T>(column: Column<T>, at index: Int) {
        insert(column: column.eraseToAnyColumn(), at: index)
    }

    public mutating func insert(column: AnyColumn, at index: Int) {
        precondition(!_columns.contains { $0.name == column.name }, "DataFrame already has a column named '\(column.name)'.")
        precondition(_columns.isEmpty || column.count == _rowCount,
                     "Can't add column '\(column.name)' with \(column.count) rows to a DataFrame with \(_rowCount) rows.")
        _columns.insert(column, at: index)
    }

    @discardableResult
    public mutating func removeColumn<T>(_ id: ColumnID<T>) -> Column<T> {
        removeColumn(id.name).assumingType(T.self)
    }

    @discardableResult
    public mutating func removeColumn(_ name: String) -> AnyColumn {
        let index = _requireColumn(name)
        let removed = _columns.remove(at: index)
        for (alias, names) in _aliases {
            let remaining = names.filter { $0 != removed.name }
            _aliases[alias] = remaining.isEmpty ? nil : remaining
        }
        return removed
    }

    public mutating func renameColumn(_ name: String, to newName: String) {
        let index = _requireColumn(name)
        let oldName = _columns[index].name
        _columns[index].name = newName
        for (alias, names) in _aliases {
            _aliases[alias] = names.map { $0 == oldName ? newName : $0 }
        }
    }

    public mutating func replaceColumn(_ name: String, with newColumn: AnyColumn) {
        let index = _requireColumn(name)
        precondition(newColumn.count == _rowCount,
                     "Can't replace column '\(name)' with a column of \(newColumn.count) rows in a DataFrame with \(_rowCount) rows.")
        _columns[index] = newColumn
    }

    public mutating func replaceColumn<T>(_ id: ColumnID<T>, with newColumn: AnyColumn) {
        replaceColumn(id.name, with: newColumn)
    }

    public mutating func replaceColumn<T>(_ name: String, with newColumn: Column<T>) {
        replaceColumn(name, with: newColumn.eraseToAnyColumn())
    }

    public mutating func replaceColumn<T, U>(_ id: ColumnID<T>, with newColumn: Column<U>) {
        replaceColumn(id.name, with: newColumn.eraseToAnyColumn())
    }

    public mutating func transformColumn<From, To>(_ id: ColumnID<From>, _ transform: (From?) throws -> To?) rethrows {
        try transformColumn(id.name, transform)
    }

    public mutating func transformColumn<From, To>(_ id: ColumnID<From>, _ transform: (From) throws -> To?) rethrows {
        try transformColumn(id.name, transform)
    }

    public mutating func transformColumn<From, To>(_ name: String, _ transform: (From?) throws -> To?) rethrows {
        let index = _requireColumn(name)
        let column = _columns[index].assumingType(From.self)
        _columns[index] = try column.map(transform).eraseToAnyColumn()
    }

    public mutating func transformColumn<From, To>(_ name: String, _ transform: (From) throws -> To?) rethrows {
        let index = _requireColumn(name)
        let column = _columns[index].assumingType(From.self)
        _columns[index] = try column.map { try $0.flatMap(transform) }.eraseToAnyColumn()
    }

    public mutating func append(row: Row) {
        precondition(row.count == _columns.count, "Can't append row of size \(row.count). Expected size to be \(_columns.count).")
        for i in _columns.indices { _columns[i].append(row[i]) }
    }

    public mutating func append(row: Any?...) {
        precondition(row.count == _columns.count, "Can't append row of size \(row.count). Expected size to be \(_columns.count).")
        for i in _columns.indices { _columns[i].append(row[i]) }
    }

    public mutating func append(valuesByColumn dictionary: [String: Any?]) {
        precondition(dictionary.count == _columns.count, "Can't append row of size \(dictionary.count). Expected size to be \(_columns.count).")
        for name in dictionary.keys {
            precondition(indexOfColumn(name) != nil, "There is no column named '\(name)' in the DataFrame.")
        }
        for i in _columns.indices {
            _columns[i].append(dictionary[_columns[i].name] ?? nil)
        }
    }

    public mutating func appendEmptyRow() {
        for i in _columns.indices { _columns[i].append(nil) }
    }

    public mutating func insert(row: Row, at index: Int) {
        precondition(row.count == _columns.count, "Can't insert row of size \(row.count). Expected size to be \(_columns.count).")
        for i in _columns.indices { _columns[i]._insert(row[i], at: index) }
    }

    public mutating func removeRow(at index: Int) {
        for i in _columns.indices { _columns[i].remove(at: index) }
    }

    public func prefix(_ maxLength: Int) -> Slice {
        Slice(base: self, ranges: _RangeSet(0 ..< Swift.min(Swift.max(maxLength, 0), _rowCount)))
    }

    public func suffix(_ maxLength: Int) -> Slice {
        Slice(base: self, ranges: _RangeSet(Swift.max(_rowCount - Swift.max(maxLength, 0), 0) ..< _rowCount))
    }

    public mutating func append(rowsOf other: DataFrame) {
        _appendRows(other, indices: nil)
    }

    public mutating func append(_ other: DataFrame) {
        _appendRows(other, indices: nil)
    }

    public mutating func append(_ other: Slice) {
        _appendRows(other._base, indices: other._set.indices)
    }

    /// Appends rows of another frame, matching columns by name; columns the
    /// other frame lacks get nils.
    private mutating func _appendRows(_ other: DataFrame, indices: [Int]?) {
        if _columns.isEmpty {
            self = indices.map { other._gathering($0) } ?? other
            return
        }
        let added = indices?.count ?? other._rowCount
        for i in _columns.indices {
            if let j = other.indexOfColumn(_columns[i].name) {
                _columns[i]._box.append(contentsOf: other._columns[j]._box, indices: indices)
            } else {
                for _ in 0 ..< added { _columns[i].append(nil) }
            }
        }
    }

    public func filter<T>(on columnName: String, _ type: T.Type, _ isIncluded: (T?) throws -> Bool) rethrows -> Slice {
        let column = self[columnName, T.self]
        var included: [Int] = []
        for i in 0 ..< column.count where try isIncluded(column[i]) { included.append(i) }
        return Slice(base: self, ranges: _RangeSet(sortedIndices: included))
    }

    public func filter<T>(on columnID: ColumnID<T>, _ isIncluded: (T?) throws -> Bool) rethrows -> Slice {
        try filter(on: columnID.name, T.self, isIncluded)
    }

    public func filter(_ isIncluded: (Row) throws -> Bool) rethrows -> Slice {
        var included: [Int] = []
        for i in 0 ..< _rowCount where try isIncluded(Row(base: self, index: i)) { included.append(i) }
        return Slice(base: self, ranges: _RangeSet(sortedIndices: included))
    }

    public func selecting<S>(columnNames: S) -> DataFrame where S: Sequence, S.Element == String {
        var frame = DataFrame(_columns: columnNames.map { _columns[_requireColumn($0)] })
        frame._aliases = _aliases.compactMapValues { names in
            let kept = names.filter { name in frame._columns.contains { $0.name == name } }
            return kept.isEmpty ? nil : kept
        }
        return frame
    }

    public func selecting(columnNames: String...) -> DataFrame {
        selecting(columnNames: columnNames)
    }
}

extension DataFrame {
    public subscript(dynamicMember columnName: String) -> AnyColumn {
        get { self[columnName] }
        set { self[columnName] = newValue }
    }

    public subscript(columnName: String) -> AnyColumn {
        get {
            _columns[_requireColumn(columnName)]
        }
        set {
            if indexOfColumn(columnName) != nil {
                replaceColumn(columnName, with: newValue)
            } else {
                var column = newValue
                column.name = columnName
                append(column: column)
            }
        }
    }

    @_disfavoredOverload
    public subscript<T>(columnName: String, type: T.Type = T.self) -> [T?] {
        get {
            Array(self[column: _requireColumn(columnName), T.self])
        }
        set {
            if indexOfColumn(columnName) != nil {
                replaceColumn(columnName, with: Column(name: columnName, contents: newValue).eraseToAnyColumn())
            } else {
                append(column: Column(name: columnName, contents: newValue))
            }
        }
    }

    public subscript<T>(columnName: String, type: T.Type) -> Column<T> {
        get {
            _columns[_requireColumn(columnName)].assumingType(T.self)
        }
        set {
            if indexOfColumn(columnName) != nil {
                replaceColumn(columnName, with: newValue.eraseToAnyColumn())
            } else {
                var column = newValue
                column.name = columnName
                append(column: column)
            }
        }
    }

    public subscript<T>(id: ColumnID<T>) -> Column<T> {
        get {
            self[id.name, T.self]
        }
        set {
            self[id.name, T.self] = newValue
        }
    }

    public subscript<S>(columnNames: S) -> DataFrame where S: Sequence, S.Element == String {
        selecting(columnNames: columnNames)
    }

    public subscript(column index: Int) -> AnyColumn {
        get {
            _columns[index]
        }
        set {
            precondition(newValue.count == _rowCount || _columns.count == 1,
                         "Can't replace a column of \(_rowCount) rows with one of \(newValue.count) rows.")
            _columns[index] = newValue
        }
    }

    public subscript<T>(column index: Int, type: T.Type) -> Column<T> {
        get {
            _columns[index].assumingType(T.self)
        }
        set {
            self[column: index] = newValue.eraseToAnyColumn()
        }
    }

    public subscript(row index: Int) -> Row {
        get {
            precondition(index >= 0 && index < _rowCount, "Row index out of range")
            return Row(base: self, index: index)
        }
        set {
            _setRow(index, from: newValue)
        }
    }

    public subscript<C>(mask: C) -> Slice where C: Collection, C.Element == Bool {
        precondition(mask.count == _rowCount, "Length mismatch. mask: \(mask.count)    rows: \(_rowCount)")
        var included: [Int] = []
        for (i, isIncluded) in mask.enumerated() where isIncluded && i < _rowCount { included.append(i) }
        return Slice(base: self, ranges: _RangeSet(sortedIndices: included))
    }

    /// Writes a row's values, by position, into a row of this frame.
    internal mutating func _setRow(_ index: Int, from row: Row) {
        precondition(row.count == _columns.count, "Can't set a row of size \(row.count) in a DataFrame with \(_columns.count) columns.")
        for i in _columns.indices { _columns[i][index] = row[i] }
    }
}

extension DataFrame: Hashable {
    public static func == (lhs: DataFrame, rhs: DataFrame) -> Bool {
        lhs._columns == rhs._columns
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(_columns)
    }
}

extension DataFrame: ExpressibleByDictionaryLiteral {
    public typealias Key = String
    public typealias Value = [Any?]

    /// Columns of the type all their values have, or of Any if they differ.
    public init(dictionaryLiteral elements: (String, [Any?])...) {
        self.init()
        for (name, values) in elements {
            append(column: _makeColumn(name: name, values: values))
        }
    }
}

/// A column of the values given, of the type they all have (Any if they
/// differ or are all nil).
internal func _makeColumn(name: String, values: [Any?]) -> AnyColumn {
    var elementType: (any Any.Type)?
    for case let value? in values where !_isNilValue(value) {
        let valueType = type(of: value)
        if elementType == nil {
            elementType = valueType
        } else if elementType! != valueType {
            elementType = nil
            return Column<Any>(name: name, contents: values.map { $0.flatMap { _isNilValue($0) ? nil : $0 } }).eraseToAnyColumn()
        }
    }
    func make<T>(_ type: T.Type) -> AnyColumn {
        Column<T>(name: name, contents: values.map { _cast($0, to: T.self, column: name) }).eraseToAnyColumn()
    }
    guard let elementType else {
        return Column<Any>(name: name, contents: values.map { _ in nil as Any? }).eraseToAnyColumn()
    }
    return _openExistential(elementType, do: make)
}

extension DataFrame {
    /// A view of a data frame's rows.
    @dynamicMemberLookup
    public struct Slice: DataFrameProtocol {
        public typealias ColumnType = AnyColumnSlice

        internal var _base: DataFrame
        internal var _set: _RangeSet

        internal init(base: DataFrame, ranges: _RangeSet) {
            _base = base
            _set = ranges
        }

        public var base: DataFrame {
            _base
        }

        public var rows: Rows {
            get {
                Rows(base: _base, subranges: _set)
            }
            set {
                _base = newValue.base
                _set = newValue.subranges
            }
        }

        public var columns: [AnyColumnSlice] {
            _base._columns.map { AnyColumnSlice(column: $0, set: _set) }
        }

        public var shape: (rows: Int, columns: Int) {
            (_set.count, _base._columns.count)
        }
    }

    /// A data frame's rows.
    public struct Rows: BidirectionalCollection, MutableCollection {
        public typealias Element = Row
        public typealias Index = Int
        public typealias Indices = DefaultIndices<Rows>
        public typealias Iterator = IndexingIterator<Rows>
        public typealias SubSequence = Rows

        internal var base: DataFrame
        internal var subranges: _RangeSet

        internal init(base: DataFrame, subranges: _RangeSet) {
            self.base = base
            self.subranges = subranges
        }

        public var startIndex: Int {
            subranges.lowerBound
        }

        public var endIndex: Int {
            subranges.upperBound
        }

        public var count: Int {
            subranges.count
        }

        public func index(after i: Int) -> Int {
            subranges.index(after: i)
        }

        public func index(before i: Int) -> Int {
            subranges.index(before: i)
        }

        public subscript(position: Int) -> Row {
            get {
                Row(base: base, index: position)
            }
            set {
                base._setRow(position, from: newValue)
            }
        }

        /// Setting a range of rows replaces these rows (their frame and
        /// indices) with the new ones, as Apple's TabularData does.
        public subscript(bounds: Range<Int>) -> Rows {
            get {
                Rows(base: base, subranges: subranges.intersection(bounds))
            }
            set {
                self = newValue
            }
        }
    }

    /// A row of a data frame.
    public struct Row {
        internal var _base: DataFrame
        public let index: Int

        internal init(base: DataFrame, index: Int) {
            _base = base
            self.index = index
        }

        public var base: DataFrame {
            _base
        }

        public subscript<T>(position: Int, type: T.Type) -> T? {
            get {
                _base._columns[position].assumingType(T.self)[index]
            }
            set {
                _base._columns[position][index] = newValue
            }
        }

        public subscript<T>(columnName: String, type: T.Type) -> T? {
            get {
                self[_base._requireColumn(columnName), T.self]
            }
            set {
                self[_base._requireColumn(columnName), T.self] = newValue
            }
        }

        public subscript(columnName: String) -> Any? {
            get {
                self[_base._requireColumn(columnName)]
            }
            set {
                self[_base._requireColumn(columnName)] = newValue
            }
        }

        public subscript<T>(columnID: ColumnID<T>) -> T? {
            get {
                self[columnID.name, T.self]
            }
            set {
                self[columnID.name, T.self] = newValue
            }
        }
    }
}

extension DataFrame.Row: RandomAccessCollection, MutableCollection {
    public typealias Element = Any?
    public typealias Index = Int
    public typealias Indices = Range<Int>
    public typealias Iterator = IndexingIterator<DataFrame.Row>
    public typealias SubSequence = Slice<DataFrame.Row>

    public var startIndex: Int {
        0
    }

    public var endIndex: Int {
        _base._columns.count
    }

    public func index(after i: Int) -> Int {
        i + 1
    }

    public func index(before i: Int) -> Int {
        i - 1
    }

    public var count: Int {
        _base._columns.count
    }

    public subscript(position: Int) -> Any? {
        get {
            _base._columns[position][index]
        }
        set {
            _base._columns[position][index] = newValue
        }
    }

    public subscript(bounds: Range<Int>) -> Slice<DataFrame.Row> {
        get {
            Slice(base: self, bounds: bounds)
        }
        set {
            for i in bounds { self[i] = newValue[i] }
        }
    }
}

extension DataFrame.Row: Hashable {
    public static func == (lhs: DataFrame.Row, rhs: DataFrame.Row) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { _valuesEqual($0, $1) }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(count)
        for value in self { _hashValue(value, into: &hasher) }
    }
}

extension DataFrame.Slice {
    public subscript(dynamicMember columnName: String) -> AnyColumnSlice {
        self[columnName]
    }

    public subscript(columnName: String) -> AnyColumnSlice {
        AnyColumnSlice(column: _base[columnName], set: _set)
    }

    public subscript<T>(columnName: String, type: T.Type) -> DiscontiguousColumnSlice<T> {
        DiscontiguousColumnSlice(column: _base[columnName, T.self], set: _set)
    }

    public subscript<T>(columnID: ColumnID<T>) -> DiscontiguousColumnSlice<T> {
        self[columnID.name, T.self]
    }

    public subscript<T>(column index: Int, type: T.Type) -> DiscontiguousColumnSlice<T> {
        DiscontiguousColumnSlice(column: _base[column: index, T.self], set: _set)
    }

    public subscript<S>(columnNames: S) -> DataFrame.Slice where S: Sequence, S.Element == String {
        selecting(columnNames: columnNames)
    }

    public func filter<T>(on columnName: String, _ type: T.Type, _ isIncluded: (T?) throws -> Bool) rethrows -> DataFrame.Slice {
        let column = _base[columnName, T.self]
        var included: [Int] = []
        for i in _set.indices where try isIncluded(column[i]) { included.append(i) }
        return DataFrame.Slice(base: _base, ranges: _RangeSet(sortedIndices: included))
    }

    public func filter<T>(on columnID: ColumnID<T>, _ isIncluded: (T?) throws -> Bool) rethrows -> DataFrame.Slice {
        try filter(on: columnID.name, T.self, isIncluded)
    }

    public func prefix(_ length: Int) -> DataFrame.Slice {
        DataFrame.Slice(base: _base, ranges: _set.prefix(length))
    }

    /// The rows up to and including the one at an offset in the slice.
    public func prefix(through position: Int) -> DataFrame.Slice {
        prefix(position + 1)
    }

    /// The rows before the one at an offset in the slice.
    public func prefix(upTo position: Int) -> DataFrame.Slice {
        prefix(position)
    }

    public func suffix(_ length: Int) -> DataFrame.Slice {
        DataFrame.Slice(base: _base, ranges: _set.suffix(length))
    }

    /// The rows from a base frame's row index on.
    public func suffix(from position: Int) -> DataFrame.Slice {
        DataFrame.Slice(base: _base, ranges: _set.intersection(position ..< Int.max))
    }

    public func selecting<S>(columnNames: S) -> DataFrame.Slice where S: Sequence, S.Element == String {
        DataFrame.Slice(base: _base.selecting(columnNames: columnNames), ranges: _set)
    }

    public func selecting(columnNames: String...) -> DataFrame.Slice {
        selecting(columnNames: columnNames)
    }
}

extension DataFrame.Slice: Hashable {
    public static func == (lhs: DataFrame.Slice, rhs: DataFrame.Slice) -> Bool {
        DataFrame(lhs) == DataFrame(rhs)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(DataFrame(self))
    }
}

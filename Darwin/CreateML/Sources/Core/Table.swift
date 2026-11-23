import Foundation

// The storage of a table: named columns of the same length, in order.
// CMLTable is the name the Swift 5.0 overlay gave its C engine's table;
// Perry's is plain Swift, and reads and writes CSV and JSON itself.

@usableFromInline
final class CMLTable {
    var names: [String]
    var columnList: [CMLColumn]

    init(names: [String], columns: [CMLColumn]) {
        self.names = names
        self.columnList = columns
    }

    @usableFromInline
    init() {
        names = []
        columnList = []
    }

    /// A copy whose column list can change without changing this one's.
    func copy() -> CMLTable {
        CMLTable(names: names, columns: columnList)
    }

    var rowCount: Int { columnList.first?.size ?? 0 }

    func index(of name: String) throws -> Int {
        guard let index = names.firstIndex(of: name) else {
            throw MLCreateError.generic(reason: "The table has no column named \(name).")
        }
        return index
    }

    /// The table of the rows at some indices, in their order.
    func rows(at indices: [Int]) -> CMLTable {
        CMLTable(names: names, columns: columnList.map { column in
            CMLColumn(values: indices.map { column.values[$0] }, type: column.type)
        })
    }

    /// A row's values, in column order.
    func rowValues(_ row: Int) -> [MLDataValue] {
        columnList.map { $0.values[row] }
    }

    @usableFromInline func rows() throws -> Int { rowCount }
    @usableFromInline func columns() throws -> Int { columnList.count }

    @usableFromInline
    func columnNames() throws -> CMLSequence {
        CMLSequence(values: names.map(MLDataValue.string))
    }

    @usableFromInline
    func columnType(name: String) throws -> CMLFeatureValueType {
        columnList[try index(of: name)].type
    }

    @usableFromInline
    func column(name: String) throws -> CMLColumn {
        columnList[try index(of: name)]
    }

    @usableFromInline
    func row(at index: Int) throws -> CMLSequence {
        guard (0..<rowCount).contains(index) else {
            throw MLCreateError.generic(reason: "Row \(index) is out of the table's range 0..<\(rowCount).")
        }
        return CMLSequence(values: rowValues(index))
    }

    @usableFromInline
    func addColumn(name: String, _ column: CMLColumn) throws {
        guard columnList.isEmpty || column.size == rowCount else {
            throw MLCreateError.generic(reason: "A column of \(column.size) values can't be added to a table of \(rowCount) rows.")
        }
        if let index = names.firstIndex(of: name) {
            columnList[index] = column
        } else {
            names.append(name)
            columnList.append(column)
        }
    }

    @usableFromInline
    func removeColumn(name: String) throws {
        let index = try index(of: name)
        names.remove(at: index)
        columnList.remove(at: index)
    }

    @usableFromInline
    func renameColumn(named name: String, to newName: String) throws {
        let index = try index(of: name)
        if name != newName, names.contains(newName) {
            throw MLCreateError.generic(reason: "The table already has a column named \(newName).")
        }
        names[index] = newName
    }

    @usableFromInline
    convenience init(concatenating first: CMLTable, and second: CMLTable) throws {
        if first.columnList.isEmpty { self.init(names: second.names, columns: second.columnList); return }
        if second.columnList.isEmpty { self.init(names: first.names, columns: first.columnList); return }
        guard Set(first.names) == Set(second.names) else {
            throw MLCreateError.generic(reason: "Tables with the columns \(first.names) and \(second.names) can't be appended.")
        }
        let columns = try first.names.indices.map { index in
            try CMLColumn(concatenating: first.columnList[index], and: second.columnList[try second.index(of: first.names[index])])
        }
        self.init(names: first.names, columns: columns)
    }

    /// The rows of two tables whose values of a column match.
    @usableFromInline
    convenience init(joining left: CMLTable, and right: CMLTable, columnName: String, method: String) throws {
        try self.init(joining: left, and: right, on: [columnName], method: method)
    }

    /// The rows of two tables whose values of some columns match: "inner",
    /// "left", "right" or "outer".
    convenience init(joining left: CMLTable, and right: CMLTable, on keys: [String], method: String) throws {
        let leftKeys = try keys.map { try left.index(of: $0) }
        let rightKeys = try keys.map { try right.index(of: $0) }
        let rightOthers = right.names.indices.filter { !rightKeys.contains($0) }
        var rightRows: [[MLDataValue]: [Int]] = [:]
        for row in 0..<right.rowCount {
            rightRows[rightKeys.map { right.columnList[$0].values[row] }, default: []].append(row)
        }
        var rows: [(left: Int?, right: Int?)] = []
        var matched = Set<Int>()
        for row in 0..<left.rowCount {
            let key = leftKeys.map { left.columnList[$0].values[row] }
            if let others = rightRows[key] {
                for other in others { rows.append((row, other)); matched.insert(other) }
            } else if method == "left" || method == "outer" {
                rows.append((row, nil))
            }
        }
        if method == "right" || method == "outer" {
            for row in 0..<right.rowCount where !matched.contains(row) { rows.append((nil, row)) }
        }
        var names = left.names, columns: [CMLColumn] = []
        for (index, column) in left.columnList.enumerated() {
            let key = leftKeys.firstIndex(of: index)
            columns.append(CMLColumn(values: rows.map { pair in
                if let row = pair.left { return column.values[row] }
                if let key, let row = pair.right { return right.columnList[rightKeys[key]].values[row] }
                return .invalid
            }, type: column.type))
        }
        for index in rightOthers {
            var name = right.names[index]
            while names.contains(name) { name += ".1" }
            names.append(name)
            let column = right.columnList[index]
            columns.append(CMLColumn(values: rows.map { $0.right.map { column.values[$0] } ?? .invalid }, type: column.type))
        }
        self.init(names: names, columns: columns)
    }

    @usableFromInline
    func slice(lower: Int, upper: Int) throws -> CMLTable {
        let range = (max(lower, 0)..<max(min(upper, rowCount), max(lower, 0)))
        return rows(at: Array(range))
    }

    @usableFromInline func prefix(_ count: Int) throws -> CMLTable { try slice(lower: 0, upper: count) }
    @usableFromInline func suffix(_ count: Int) throws -> CMLTable { try slice(lower: rowCount - max(count, 0), upper: rowCount) }

    @usableFromInline
    func dropMissing() throws -> CMLTable {
        rows(at: (0..<rowCount).filter { row in columnList.allSatisfy { $0.values[row].isValid } })
    }

    @usableFromInline
    func dropDuplicates() throws -> CMLTable {
        var seen = Set<[MLDataValue]>()
        return rows(at: (0..<rowCount).filter { seen.insert(rowValues($0)).inserted })
    }

    @usableFromInline
    func fillMissing(columnNamed name: String, with value: CMLFeatureValue) throws -> CMLTable {
        let table = copy()
        let index = try index(of: name)
        table.columnList[index] = try columnList[index].fillMissing(with: value)
        return table
    }

    /// The column a transform of each row makes.
    @usableFromInline
    func apply(transform: @escaping (CMLSequence) -> CMLFeatureValue, type: CMLFeatureValueType) throws -> CMLColumn {
        CMLColumn(values: (0..<rowCount).map { transform(CMLSequence(values: rowValues($0))).value }, type: type)
    }

    /// The rows split at random in two: about `fraction` of them, and the
    /// rest.
    @usableFromInline
    func split(fraction: Double, seed: Int) throws -> (CMLTable, CMLTable) {
        var generator = SeededGenerator(seed: seed)
        var first: [Int] = [], second: [Int] = []
        for row in 0..<rowCount {
            if Double.random(in: 0..<1, using: &generator) < fraction { first.append(row) } else { second.append(row) }
        }
        return (rows(at: first), rows(at: second))
    }

    @usableFromInline
    func description() throws -> String {
        describeTable(self)
    }

    /// Writes the table to a path: 0 for CSV, 1 for the directory format
    /// `write(to:)` makes, 2 for JSON.
    @usableFromInline
    func save(to path: String, type: Int) throws {
        let url = URL(fileURLWithPath: path)
        switch type {
        case 0: try TableFiles.writeCSV(self, to: url)
        case 2: try TableFiles.writeJSON(self, to: url)
        default: try TableFiles.writeDirectory(self, to: url)
        }
    }

    /// The table a file or a directory written by `write(to:)` holds: CSV,
    /// or JSON when `isCSV` is false.
    @usableFromInline
    convenience init(from path: String, isCSV: Bool, options: MLDataTable.ParsingOptions?) throws {
        let table = try TableFiles.read(URL(fileURLWithPath: path), isCSV: isCSV, options: options ?? MLDataTable.ParsingOptions())
        self.init(names: table.names, columns: table.columnList)
    }
}

/// A random number generator of a seed: the same seed makes the same
/// numbers (SplitMix64).
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    init(seed: Int) {
        state = UInt64(bitPattern: Int64(seed)) &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A table as CreateML prints it: its columns' names and types, then its
/// first rows.
func describeTable(_ table: CMLTable, limit: Int = 10) -> String {
    if table.columnList.isEmpty { return "Empty table" }
    let header = table.names
    let types = table.columnList.map { $0.type.valueType.description }
    let rows = (0..<min(table.rowCount, limit)).map { row in table.columnList.map { $0.values[row].description } }
    var widths = header.indices.map { max(header[$0].count, types[$0].count) }
    for row in rows {
        for (index, cell) in row.enumerated() { widths[index] = max(widths[index], min(cell.count, 40)) }
    }
    func line(_ cells: [String]) -> String {
        cells.enumerated().map { index, cell in
            let cell = cell.count > 40 ? String(cell.prefix(37)) + "..." : cell
            return cell.padding(toLength: widths[index], withPad: " ", startingAt: 0)
        }.joined(separator: " | ")
    }
    var lines = [line(header), line(types), widths.map { String(repeating: "-", count: $0) }.joined(separator: "-+-")]
    lines += rows.map(line)
    if table.rowCount > limit { lines.append("[\(table.rowCount) rows x \(table.columnList.count) columns]") }
    return lines.joined(separator: "\n")
}

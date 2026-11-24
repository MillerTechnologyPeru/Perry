// Reading and writing comma-separated values (RFC 4180, with the options
// CSVReadingOptions and CSVWritingOptions describe).

import Foundation

public enum CSVType: Sendable {
    case integer
    case boolean
    case float
    case double
    case date
    case string
    case data
}

public struct CSVReadingOptions {
    public var hasHeaderRow: Bool
    public var nilEncodings: Set<String>
    public var trueEncodings: Set<String>
    public var falseEncodings: Set<String>
    public var floatingPointType: CSVType
    public var dateParsers: [(String) -> Date?]
    public var ignoresEmptyLines: Bool
    public var usesQuoting: Bool
    public var usesEscaping: Bool
    internal var _delimiter: Character
    internal var _escapeCharacter: Character

    public var delimiter: Character {
        _delimiter
    }

    public var escapeCharacter: Character {
        _escapeCharacter
    }

    public init(hasHeaderRow: Bool = true,
                nilEncodings: Set<String> = ["", "#N/A", "#N/A N/A", "#NA", "N/A", "NA", "NULL", "n/a", "nil", "null"],
                trueEncodings: Set<String> = ["1", "True", "TRUE", "true"],
                falseEncodings: Set<String> = ["0", "False", "FALSE", "false"],
                floatingPointType: CSVType = .double, ignoresEmptyLines: Bool = true, usesQuoting: Bool = true,
                usesEscaping: Bool = false, delimiter: Character = Character(","), escapeCharacter: Character = Character("\\")) {
        self.hasHeaderRow = hasHeaderRow
        self.nilEncodings = nilEncodings
        self.trueEncodings = trueEncodings
        self.falseEncodings = falseEncodings
        self.floatingPointType = floatingPointType
        self.dateParsers = []
        self.ignoresEmptyLines = ignoresEmptyLines
        self.usesQuoting = usesQuoting
        self.usesEscaping = usesEscaping
        _delimiter = delimiter
        _escapeCharacter = escapeCharacter
    }

    public mutating func addDateParseStrategy<T>(_ strategy: T) where T: ParseStrategy, T.ParseInput == String, T.ParseOutput == Date {
        dateParsers.append { try? strategy.parse($0) }
    }
}

public enum CSVReadingError: Error {
    case badEncoding(row: Int, column: Int, cellContents: Data)
    case unsupportedEncoding(String)
    case misplacedQuote(row: Int, column: Int)
    case wrongNumberOfColumns(row: Int, columns: Int, expected: Int)
    case failedToParse(row: Int, column: Int, type: CSVType, cellContents: Data)
    case missingColumn(columnName: String)
    case outOfBounds(requested: Int, actual: Int)
    case unsupportedColumnType(columnIndex: Int, columnName: String, type: String)

    public var row: Int {
        switch self {
        case .badEncoding(let row, _, _), .misplacedQuote(let row, _), .wrongNumberOfColumns(let row, _, _),
             .failedToParse(let row, _, _, _):
            return row
        case .outOfBounds(let requested, _):
            return requested
        case .unsupportedEncoding, .missingColumn, .unsupportedColumnType:
            return 0
        }
    }

    public var column: Int? {
        switch self {
        case .badEncoding(_, let column, _), .misplacedQuote(_, let column), .failedToParse(_, let column, _, _):
            return column
        case .unsupportedColumnType(let column, _, _):
            return column
        case .unsupportedEncoding, .wrongNumberOfColumns, .missingColumn, .outOfBounds:
            return nil
        }
    }
}

extension CSVReadingError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .badEncoding(let row, let column, let contents):
            return "Bad UTF8 encoding at row \(row) column \(column): \(Array(contents))."
        case .unsupportedEncoding(let encoding):
            return "Usupported encoding \(encoding). Only UTF8 encoding is supported."
        case .misplacedQuote(let row, let column):
            return "Misplaced quote at row \(row) column \(column)."
        case .wrongNumberOfColumns(let row, let columns, let expected):
            return "Wrong number of columns at row \(row). Expected \(expected) but found \(columns)."
        case .failedToParse(let row, let column, let type, let contents):
            return "Failed to parse cell at row \(row) column \(column) as \(type). Cell contents are '\(String(decoding: contents, as: UTF8.self))'."
        case .missingColumn(let name):
            return "Missing required column \(name)."
        case .outOfBounds(let requested, let actual):
            return "The requested row \(requested) is beyond the number of rows in the file \(actual)."
        case .unsupportedColumnType(let index, let name, let type):
            return "Unsupported column type \(type) requested for column \"\(name)\" at index \(index). Only Bool, Int, Float, Double, String, Date, and Data are supported."
        }
    }
}

extension CSVReadingError: LocalizedError {
    public var errorDescription: String? {
        description
    }
}

// MARK: - Reading

/// A parsed record: its fields' bytes and its row in the file.
private struct _CSVRecord {
    var fields: [[UInt8]]
    var row: Int
}

/// Splits CSV bytes into records of fields.
private struct _CSVParser {
    let bytes: [UInt8]
    let options: CSVReadingOptions
    let delimiter: [UInt8]
    let escape: [UInt8]
    static let quote = UInt8(ascii: "\"")

    init(bytes: [UInt8], options: CSVReadingOptions) {
        self.bytes = bytes
        self.options = options
        delimiter = Array(String(options.delimiter).utf8)
        escape = Array(String(options.escapeCharacter).utf8)
    }

    private func matches(_ sequence: [UInt8], at index: Int) -> Bool {
        guard !sequence.isEmpty, index + sequence.count <= bytes.count else { return false }
        for (offset, byte) in sequence.enumerated() where bytes[index + offset] != byte { return false }
        return true
    }

    private func isNewline(_ index: Int) -> Bool {
        bytes[index] == 0x0A || bytes[index] == 0x0D
    }

    /// The index after the newline at index.
    private func skipNewline(_ index: Int) -> Int {
        if bytes[index] == 0x0D && index + 1 < bytes.count && bytes[index + 1] == 0x0A { return index + 2 }
        return index + 1
    }

    func records() throws -> [_CSVRecord] {
        var records: [_CSVRecord] = []
        var i = 0
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { i = 3 }
        var row = 0
        let count = bytes.count
        while i < count {
            if isNewline(i) && options.ignoresEmptyLines {
                i = skipNewline(i)
                row += 1
                continue
            }
            var fields: [[UInt8]] = []
            var column = 0
            while true {
                var field: [UInt8] = []
                if options.usesQuoting && i < count && bytes[i] == Self.quote {
                    i += 1
                    var closed = false
                    while i < count {
                        if options.usesEscaping && matches(escape, at: i) && i + escape.count < count {
                            i += escape.count
                            field.append(bytes[i])
                            i += 1
                            continue
                        }
                        if bytes[i] == Self.quote {
                            if i + 1 < count && bytes[i + 1] == Self.quote {
                                field.append(Self.quote)
                                i += 2
                                continue
                            }
                            closed = true
                            i += 1
                            break
                        }
                        field.append(bytes[i])
                        i += 1
                    }
                    if !closed || (i < count && !matches(delimiter, at: i) && !isNewline(i)) {
                        throw CSVReadingError.misplacedQuote(row: row, column: column)
                    }
                } else {
                    while i < count && !matches(delimiter, at: i) && !isNewline(i) {
                        if options.usesEscaping && matches(escape, at: i) && i + escape.count < count {
                            i += escape.count
                            field.append(bytes[i])
                            i += 1
                            continue
                        }
                        if options.usesQuoting && bytes[i] == Self.quote {
                            throw CSVReadingError.misplacedQuote(row: row, column: column)
                        }
                        field.append(bytes[i])
                        i += 1
                    }
                }
                fields.append(field)
                if i < count && matches(delimiter, at: i) {
                    i += delimiter.count
                    column += 1
                    continue
                }
                break
            }
            if i < count { i = skipNewline(i) }
            records.append(_CSVRecord(fields: fields, row: row))
            row += 1
        }
        return records
    }
}

/// Parses cells as one type, or tells whether they all are of it.
internal struct _CSVCellParser {
    let options: CSVReadingOptions
    let isoFormatter: ISO8601DateFormatter
    let fractionalFormatter: ISO8601DateFormatter

    init(options: CSVReadingOptions) {
        self.options = options
        isoFormatter = ISO8601DateFormatter()
        fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func integer(_ text: String) -> Int? {
        Int(text.trimmingCharacters(in: .whitespaces))
    }

    func boolean(_ text: String) -> Bool? {
        if options.trueEncodings.contains(text) { return true }
        if options.falseEncodings.contains(text) { return false }
        return nil
    }

    func double(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces))
    }

    func float(_ text: String) -> Float? {
        Float(text.trimmingCharacters(in: .whitespaces))
    }

    func date(_ text: String) -> Date? {
        for parser in options.dateParsers {
            if let date = parser(text) { return date }
        }
        return _parseISODate(text, isoFormatter, fractionalFormatter)
    }
}

/// An ISO 8601 date and time, with or without fractional seconds.
internal func _parseISODate(_ text: String, _ formatter: ISO8601DateFormatter, _ fractionalFormatter: ISO8601DateFormatter) -> Date? {
    guard text.count >= 16, text.contains("T") || text.contains("t") else { return nil }
    return formatter.date(from: text) ?? fractionalFormatter.date(from: text)
}

/// A column of cells parsed as the type given.
private func _parseColumn(name: String, type: CSVType, cells: [(text: String?, bytes: [UInt8], row: Int)], column: Int,
                          parser: _CSVCellParser) throws -> AnyColumn {
    func build<T>(_ convert: (String) -> T?) throws -> AnyColumn {
        var result = Column<T>(name: name, capacity: cells.count)
        for cell in cells {
            guard let text = cell.text else {
                result.append(nil)
                continue
            }
            guard let value = convert(text) else {
                throw CSVReadingError.failedToParse(row: cell.row, column: column, type: type, cellContents: Data(cell.bytes))
            }
            result.append(value)
        }
        return result.eraseToAnyColumn()
    }
    switch type {
    case .integer: return try build(parser.integer)
    case .boolean: return try build(parser.boolean)
    case .float: return try build(parser.float)
    case .double: return try build(parser.double)
    case .date: return try build(parser.date)
    case .string: return try build { $0 }
    case .data:
        var result = Column<Data>(name: name, capacity: cells.count)
        for cell in cells { result.append(cell.text == nil ? nil : Data(cell.bytes)) }
        return result.eraseToAnyColumn()
    }
}

/// The type all of a column's cells parse as: integers, then booleans,
/// then floating-point numbers, then dates, otherwise strings.
private func _inferType(_ texts: [String], parser: _CSVCellParser) -> CSVType {
    guard !texts.isEmpty else { return .string }
    if texts.allSatisfy({ parser.integer($0) != nil }) { return .integer }
    if texts.allSatisfy({ parser.boolean($0) != nil }) { return .boolean }
    if texts.allSatisfy({ parser.double($0) != nil }) {
        return parser.options.floatingPointType == .float ? .float : .double
    }
    if texts.allSatisfy({ parser.date($0) != nil }) { return .date }
    return .string
}

internal func _readCSV(_ data: Data, columns selectedColumns: [String]?, rows: Range<Int>?, types: [String: CSVType],
                       options: CSVReadingOptions) throws -> DataFrame {
    let records = try _CSVParser(bytes: Array(data), options: options).records()
    guard !records.isEmpty else { return DataFrame() }

    func text(_ bytes: [UInt8], row: Int, column: Int) throws -> String {
        guard let string = String(validating: bytes, as: UTF8.self) else {
            throw CSVReadingError.badEncoding(row: row, column: column, cellContents: Data(bytes))
        }
        return string
    }

    // Column names, made unique.
    var names: [String] = []
    var dataRecords = records[...]
    if options.hasHeaderRow {
        let header = records[0]
        dataRecords = records.dropFirst()
        var used = Set<String>()
        for (index, bytes) in header.fields.enumerated() {
            var name = try text(bytes, row: header.row, column: index)
            if name.isEmpty { name = "Column \(index)" }
            if used.contains(name) {
                var suffix = 1
                while used.contains("\(name).\(suffix)") { suffix += 1 }
                name = "\(name).\(suffix)"
            }
            used.insert(name)
            names.append(name)
        }
    } else {
        names = (0 ..< records[0].fields.count).map { "Column \($0)" }
    }
    for record in dataRecords where record.fields.count != names.count {
        throw CSVReadingError.wrongNumberOfColumns(row: record.row, columns: record.fields.count, expected: names.count)
    }

    var chosen = Array(dataRecords)
    if let rows {
        guard rows.lowerBound < chosen.count || rows.isEmpty else {
            throw CSVReadingError.outOfBounds(requested: rows.upperBound, actual: records.count)
        }
        chosen = Array(chosen[rows.lowerBound ..< Swift.min(rows.upperBound, chosen.count)])
    }

    var columnIndices = Array(names.indices)
    if let selectedColumns {
        columnIndices = try selectedColumns.map { name in
            guard let index = names.firstIndex(of: name) else { throw CSVReadingError.missingColumn(columnName: name) }
            return index
        }
    }

    let parser = _CSVCellParser(options: options)
    var frame = DataFrame()
    for index in columnIndices {
        let cells = try chosen.map { record -> (text: String?, bytes: [UInt8], row: Int) in
            let bytes = record.fields[index]
            let string = try text(bytes, row: record.row, column: index)
            return (options.nilEncodings.contains(string) ? nil : string, bytes, record.row)
        }
        let type = types[names[index]] ?? _inferType(cells.compactMap(\.text), parser: parser)
        frame.append(column: try _parseColumn(name: names[index], type: type, cells: cells, column: index, parser: parser))
    }
    return frame
}

/// The CSV type of a column's element type, for columns requested by ID.
private func _csvType(of type: any Any.Type) -> CSVType? {
    switch type {
    case is Bool.Type: return .boolean
    case is Int.Type: return .integer
    case is Float.Type: return .float
    case is Double.Type: return .double
    case is String.Type: return .string
    case is Date.Type: return .date
    case is Data.Type: return .data
    default: return nil
    }
}

extension DataFrame {
    public init(contentsOfCSVFile url: URL, columns: [String]? = nil, rows: Range<Int>? = nil, types: [String: CSVType] = [:],
                options: CSVReadingOptions = .init()) throws {
        try self.init(csvData: Data(contentsOf: url), columns: columns, rows: rows, types: types, options: options)
    }

    public init(csvData data: Data, columns: [String]? = nil, rows: Range<Int>? = nil, types: [String: CSVType] = [:],
                options: CSVReadingOptions = .init()) throws {
        self = try _readCSV(data, columns: columns, rows: rows, types: types, options: options)
    }

    public init<each T>(contentsOfCSVFile url: URL, columns: repeat ColumnID<each T>, rows: Range<Int>? = nil,
                        options: CSVReadingOptions = .init()) throws {
        try self.init(csvData: Data(contentsOf: url), columns: repeat each columns, rows: rows, options: options)
    }

    public init<each T>(csvData data: Data, columns: repeat ColumnID<each T>, rows: Range<Int>? = nil,
                        options: CSVReadingOptions = .init()) throws {
        var requested: [(name: String, type: any Any.Type)] = []
        func describe<U>(_ id: ColumnID<U>) -> (name: String, type: any Any.Type) {
            (id.name, U.self)
        }
        repeat requested.append(describe(each columns))
        var types: [String: CSVType] = [:]
        for (index, column) in requested.enumerated() {
            guard let type = _csvType(of: column.type) else {
                throw CSVReadingError.unsupportedColumnType(columnIndex: index, columnName: column.name, type: "\(column.type)")
            }
            types[column.name] = type
        }
        self = try _readCSV(data, columns: requested.map(\.name), rows: rows, types: types, options: options)
    }
}

// MARK: - Writing

public struct CSVWritingOptions {
    public var includesHeader: Bool

    @available(*, deprecated, message: "Use dateFormatter instead.")
    public var dateFormat: String? {
        get { _dateFormat }
        set { _dateFormat = newValue }
    }

    internal var _dateFormat: String?
    internal var _dateFormatter: (Date) -> String

    public var dateFormatter: (Date) -> String {
        get { _dateFormatter }
        set { _dateFormatter = newValue }
    }

    public var nilEncoding: String
    public var trueEncoding: String
    public var falseEncoding: String
    public var newline: String
    public var delimiter: Character

    @_alwaysEmitIntoClient
    public init() {
        self.init(includesHeader: true, dateFormat: nil, nilEncoding: "", trueEncoding: "true", falseEncoding: "false",
                  newline: "\n", delimiter: ",")
    }

    @available(*, deprecated, message: "Use dateFormatter instead or dateFormat.")
    public init(includesHeader: Bool = true, dateFormat: String?, nilEncoding: String = "", trueEncoding: String = "true",
                falseEncoding: String = "false", newline: String = "\n", delimiter: Character = ",") {
        self.includesHeader = includesHeader
        _dateFormat = dateFormat
        _dateFormatter = { $0.ISO8601Format() }
        self.nilEncoding = nilEncoding
        self.trueEncoding = trueEncoding
        self.falseEncoding = falseEncoding
        self.newline = newline
        self.delimiter = delimiter
    }

    @_alwaysEmitIntoClient
    public init(includesHeader: Bool = true, nilEncoding: String = "", trueEncoding: String = "true",
                falseEncoding: String = "false", newline: String = "\n", delimiter: Character = ",") {
        self.init()
        self.includesHeader = includesHeader
        self.nilEncoding = nilEncoding
        self.trueEncoding = trueEncoding
        self.falseEncoding = falseEncoding
        self.delimiter = delimiter
    }
}

public enum CSVWritingError: Error {
    case badEncoding(row: Int, column: String, Data)

    public var row: Int {
        switch self {
        case .badEncoding(let row, _, _): return row
        }
    }

    public var column: String? {
        switch self {
        case .badEncoding(_, let column, _): return column
        }
    }
}

extension CSVWritingError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .badEncoding(let row, let column, let data):
            return "Bad UTF8 encoding at row \(row) column '\(column)': \(Array(data))."
        }
    }
}

internal func _csvRepresentation(_ frame: DataFrame, rows: [Int], options: CSVWritingOptions) throws -> Data {
    let delimiter = String(options.delimiter)
    func quoted(_ field: String) -> String {
        guard field.contains(where: { $0 == options.delimiter || $0 == "\"" || $0 == "\n" || $0 == "\r" || $0 == "\r\n" }) else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    var dateFormatter: DateFormatter?
    if let format = options._dateFormat {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        dateFormatter = formatter
    }
    var output = ""
    if options.includesHeader {
        output += frame._columns.map { quoted($0.name) }.joined(separator: delimiter) + options.newline
    }
    for row in rows {
        var fields: [String] = []
        fields.reserveCapacity(frame._columns.count)
        for column in frame._columns {
            guard let value = column[row], !_isNilValue(value) else {
                fields.append(options.nilEncoding)
                continue
            }
            let text: String
            switch value {
            case let bool as Bool:
                text = bool ? options.trueEncoding : options.falseEncoding
            case let string as String:
                text = string
            case let date as Date:
                text = dateFormatter?.string(from: date) ?? options._dateFormatter(date)
            case let data as Data:
                guard let string = String(data: data, encoding: .utf8) else {
                    throw CSVWritingError.badEncoding(row: row, column: column.name, data)
                }
                text = string
            default:
                text = String(describing: value)
            }
            fields.append(quoted(text))
        }
        output += fields.joined(separator: delimiter) + options.newline
    }
    return Data(output.utf8)
}

extension DataFrameProtocol {
    public func writeCSV(to url: URL, options: CSVWritingOptions = .init()) throws {
        try csvRepresentation(options: options).write(to: url)
    }

    public func csvRepresentation(options: CSVWritingOptions = .init()) throws -> Data {
        try _csvRepresentation(base, rows: _rowIndices, options: options)
    }
}

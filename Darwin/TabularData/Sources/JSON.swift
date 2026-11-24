// Reading and writing JSON: an array of objects, one per row, through
// Foundation's JSONSerialization.

import Foundation

public enum JSONType: Sendable {
    case integer
    case boolean
    case double
    case date
    case string
    case array
    case object
}

public struct JSONReadingOptions {
    public var dateParsers: [(String) -> Date?]

    public init() {
        dateParsers = []
    }

    public mutating func addDateParseStrategy<T>(_ strategy: T) where T: ParseStrategy, T.ParseInput == String, T.ParseOutput == Date {
        dateParsers.append { try? strategy.parse($0) }
    }
}

public struct JSONWritingOptions {
    public var sortKeys: Bool
    public var prettyPrint: Bool
    public var dateFormatter: (Date) -> String

    public init() {
        sortKeys = false
        prettyPrint = false
        dateFormatter = { $0.ISO8601Format() }
    }
}

public enum JSONReadingError: Error {
    case unsupportedStructure
    case wrongType(row: Int, column: String, expectedType: JSONType, value: any Sendable)
    case incompatibleValues(column: String)
    case failedToParse(row: Int, column: String, type: JSONType, contents: String)
}

extension JSONReadingError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unsupportedStructure:
            return "Usupported JSON structure. Top-level object must be a sequence."
        case .wrongType(let row, let column, let type, let value):
            return "Wrong type for value '\(value)' at row \(row), column '\(column)'. Expected a value of type \(type)."
        case .incompatibleValues(let column):
            return "Incompatible values in column '\(column)'. All values in a given column must have the same type."
        case .failedToParse(let row, let column, let type, let contents):
            return "Failed to parse value at row \(row) column '\(column)' as \(type). Cell contents are '\(contents)'."
        }
    }
}

extension JSONReadingError: LocalizedError {
    public var errorDescription: String? {
        description
    }
}

/// A value in a JSON array or object as a column keeps it: as
/// JSONSerialization made it, null as nil.
private func _elementValue(_ value: Any) -> Any? {
    value is NSNull ? nil : value
}

private func _isIntegral(_ number: NSNumber) -> Bool {
    let type = String(cString: number.objCType)
    return !(type == "d" || type == "f")
}

/// The kind of a JSONSerialization value.
private func _jsonType(_ value: Any) -> JSONType? {
    switch value {
    case let number as NSNumber:
        // Booleans are numbers: they read as integers unless booleans are asked for.
        return _isIntegral(number) ? .integer : .double
    case is String: return .string
    case is [Any]: return .array
    case is [String: Any]: return .object
    default: return nil
    }
}

internal func _readJSON(_ data: Data, columns selectedColumns: [String]?, types: [String: JSONType],
                        options: JSONReadingOptions) throws -> DataFrame {
    let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    guard let array = object as? [Any] else { throw JSONReadingError.unsupportedStructure }
    var rows: [[String: Any]] = []
    rows.reserveCapacity(array.count)
    for element in array {
        guard let row = element as? [String: Any] else { throw JSONReadingError.unsupportedStructure }
        rows.append(row)
    }
    var names = Set<String>()
    for row in rows { names.formUnion(row.keys) }
    var columnNames = names.sorted()
    if let selectedColumns {
        columnNames = selectedColumns.filter(names.contains)
    }

    let isoFormatter = ISO8601DateFormatter()
    let fractionalFormatter = ISO8601DateFormatter()
    fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    func date(_ text: String) -> Date? {
        for parser in options.dateParsers {
            if let date = parser(text) { return date }
        }
        return _parseISODate(text, isoFormatter, fractionalFormatter)
    }

    var frame = DataFrame()
    for name in columnNames {
        let values: [Any?] = rows.map { row in
            guard let value = row[name], !(value is NSNull) else { return nil }
            return value
        }
        let type: JSONType
        if let requested = types[name] {
            type = requested
        } else {
            let kinds = Set(values.compactMap { $0.flatMap(_jsonType) })
            if kinds.isEmpty {
                type = .string
            } else if kinds.count == 1 {
                let kind = kinds.first!
                if kind == .string, values.allSatisfy({ ($0 as? String).map { date($0) != nil } ?? true }) {
                    type = .date
                } else {
                    type = kind
                }
            } else if kinds.isSubset(of: [.integer, .double]) {
                type = .double
            } else {
                throw JSONReadingError.incompatibleValues(column: name)
            }
        }

        func build<T>(_ convert: (Any, Int) throws -> T?) throws -> AnyColumn {
            var column = Column<T>(name: name, capacity: values.count)
            for (row, value) in values.enumerated() {
                guard let value else {
                    column.append(nil)
                    continue
                }
                guard let converted = try convert(value, row) else {
                    throw JSONReadingError.wrongType(row: row, column: name, expectedType: type, value: "\(value)")
                }
                column.append(converted)
            }
            return column.eraseToAnyColumn()
        }
        let column: AnyColumn
        switch type {
        case .integer:
            column = try build { value, _ in (value as? NSNumber).flatMap { _jsonType($0) == .double ? nil : $0.intValue } }
        case .boolean:
            column = try build { value, _ in (value as? NSNumber).flatMap { _isIntegral($0) ? $0.boolValue : nil } }
        case .double:
            column = try build { value, _ in (value as? NSNumber)?.doubleValue }
        case .date:
            column = try build { value, row -> Date? in
                guard let text = value as? String else { return nil }
                guard let parsed = date(text) else {
                    throw JSONReadingError.failedToParse(row: row, column: name, type: .date, contents: text)
                }
                return parsed
            }
        case .string:
            column = try build { value, _ in value as? String }
        case .array:
            column = try build { value, _ in (value as? [Any]).map { $0.map(_elementValue) } }
        case .object:
            column = try build { value, _ in (value as? [String: Any]).map { $0.mapValues(_elementValue) } }
        }
        frame.append(column: column)
    }
    return frame
}

extension DataFrame {
    public init(contentsOfJSONFile url: URL, columns: [String]? = nil, types: [String: JSONType] = [:],
                options: JSONReadingOptions = .init()) throws {
        try self.init(jsonData: Data(contentsOf: url), columns: columns, types: types, options: options)
    }

    public init(jsonData data: Data, columns: [String]? = nil, types: [String: JSONType] = [:],
                options: JSONReadingOptions = .init()) throws {
        self = try _readJSON(data, columns: columns, types: types, options: options)
    }
}

/// A Swift value as one JSONSerialization can write.
private func _jsonObject(_ value: Any?, _ options: JSONWritingOptions) -> Any {
    guard let value, !_isNilValue(value) else { return NSNull() }
    switch value {
    case let bool as Bool: return bool
    case let int as Int: return int
    case let double as Double: return double
    case let float as Float: return Double(float)
    case let string as String: return string
    case let date as Date: return options.dateFormatter(date)
    case let data as Data: return data.base64EncodedString()
    case let integer as any BinaryInteger: return NSNumber(value: Int64(truncatingIfNeeded: integer))
    case let array as [Any?]: return array.map { _jsonObject($0, options) }
    case let array as [Any]: return array.map { _jsonObject($0, options) }
    case let object as [String: Any?]: return object.mapValues { _jsonObject($0, options) }
    case let object as [String: Any]: return object.mapValues { _jsonObject($0, options) }
    default:
        if let number = value as? NSNumber { return number }
        return String(describing: value)
    }
}

extension DataFrameProtocol {
    public func writeJSON(to url: URL, options: JSONWritingOptions = .init()) throws {
        try jsonRepresentation(options: options).write(to: url)
    }

    public func jsonRepresentation(options: JSONWritingOptions = .init()) throws -> Data {
        let frame = base
        let rows: [[String: Any]] = _rowIndices.map { row in
            var object: [String: Any] = [:]
            for column in frame._columns { object[column.name] = _jsonObject(column[row], options) }
            return object
        }
        var writing: JSONSerialization.WritingOptions = [.fragmentsAllowed]
        if options.sortKeys { writing.insert(.sortedKeys) }
        if options.prettyPrint { writing.insert(.prettyPrinted) }
        return try JSONSerialization.data(withJSONObject: rows, options: writing)
    }
}

import Foundation

// Reading and writing tables: CSV with CreateML's parsing options, JSON
// (an array of row objects), and the directory `MLDataTable.write(to:)`
// makes. Apple's writes its engine's own binary format there; Perry's
// writes a JSON file that keeps the columns' types, `table.json`.

enum TableFiles {
    static let directoryFileName = "table.json"

    static func read(_ url: URL, isCSV: Bool, options: MLDataTable.ParsingOptions) throws -> CMLTable {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw MLCreateError.io(reason: "There is no file at \(url.path).")
        }
        if isDirectory.boolValue {
            return try readDirectory(url)
        }
        let data = try Data(contentsOf: url)
        if !isCSV || url.pathExtension.lowercased() == "json" {
            return try readJSON(data)
        }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw MLCreateError.io(reason: "The file at \(url.path) isn't text.")
        }
        return try readCSV(text, options: options)
    }

    // CSV.

    static func readCSV(_ text: String, options: MLDataTable.ParsingOptions) throws -> CMLTable {
        var records = parseCSV(text, options: options)
        if options.skipRows > 0 { records.removeFirst(min(options.skipRows, records.count)) }
        var header: [String]
        if options.containsHeader {
            guard !records.isEmpty else { return CMLTable() }
            header = records.removeFirst().map { $0 ?? "" }
        } else {
            let width = records.map(\.count).max() ?? 0
            header = (0..<width).map { "X\($0 + 1)" }
        }
        if let maxRows = options.maxRows { records = Array(records.prefix(maxRows)) }
        let missing = Set(options.missingValues)
        var columns: [[String?]] = Array(repeating: [], count: header.count)
        for record in records {
            for index in header.indices {
                let cell = index < record.count ? record[index] : nil
                columns[index].append(cell.flatMap { missing.contains($0) || $0.isEmpty ? nil : $0 })
            }
        }
        var names: [String] = [], typed: [CMLColumn] = []
        for (index, name) in header.enumerated() {
            if let selected = options.selectColumns, !selected.contains(name) { continue }
            names.append(name)
            typed.append(typedColumn(columns[index]))
        }
        return CMLTable(names: names, columns: typed)
    }

    /// A column of text cells as the type all of them are: integers,
    /// doubles, sequences or dictionaries written as JSON, or strings.
    static func typedColumn(_ cells: [String?]) -> CMLColumn {
        let present = cells.compactMap { $0 }
        if !present.isEmpty, present.allSatisfy({ Int($0) != nil }) {
            return CMLColumn(values: cells.map { $0.flatMap(Int.init).map(MLDataValue.int) ?? .invalid }, type: .int64)
        }
        if !present.isEmpty, present.allSatisfy({ Double($0) != nil }) {
            return CMLColumn(values: cells.map { $0.flatMap(Double.init).map(MLDataValue.double) ?? .invalid }, type: .double)
        }
        for (open, type) in [("[", CMLFeatureValueType.sequence), ("{", .dictionary)] {
            if !present.isEmpty, present.allSatisfy({ $0.hasPrefix(open) }) {
                let values = cells.map { cell -> MLDataValue in
                    guard let cell, let object = try? JSONSerialization.jsonObject(with: Data(cell.utf8), options: [.fragmentsAllowed])
                    else { return .invalid }
                    return (try? MLDataValue(fromAny: object)) ?? .invalid
                }
                if values.allSatisfy({ !$0.isValid || CMLFeatureValueType($0.type) == type }) {
                    return CMLColumn(values: values, type: type)
                }
            }
        }
        return CMLColumn(values: cells.map { $0.map(MLDataValue.string) ?? .invalid }, type: .string)
    }

    /// The records of CSV text, by the options' delimiter, quoting,
    /// escaping and comments; nil for a field that's absent.
    static func parseCSV(_ text: String, options: MLDataTable.ParsingOptions) -> [[String?]] {
        let delimiter = Array(options.delimiter), quote = options.quote.first, escape = options.escape.first
        let terminator = options.lineTerminator.isEmpty ? "\n" : options.lineTerminator
        let comment = options.comment
        let characters = Array(text.replacingOccurrences(of: "\r\n", with: "\n"))
        let terminatorCharacters = Array(terminator == "\r\n" ? "\n" : terminator)
        var records: [[String?]] = [], record: [String?] = [], field = ""
        var inQuotes = false, quoted = false, atFieldStart = true, index = 0
        func matches(_ pattern: [Character], at position: Int) -> Bool {
            !pattern.isEmpty && position + pattern.count <= characters.count
                && Array(characters[position..<position + pattern.count]) == pattern
        }
        func endField() {
            record.append(field)
            field = ""; quoted = false; atFieldStart = true
        }
        func endRecord() {
            endField()
            let line = record.compactMap { $0 }.joined()
            if !(record.count == 1 && line.isEmpty) && !(!comment.isEmpty && (record.first??.hasPrefix(comment) ?? false)) {
                records.append(record)
            }
            record = []
        }
        while index < characters.count {
            let character = characters[index]
            if inQuotes {
                if let escape, character == escape, escape != quote, index + 1 < characters.count {
                    let next = characters[index + 1]
                    switch next {
                    case "n": field.append("\n")
                    case "t": field.append("\t")
                    default: field.append(next)
                    }
                    index += 2
                    continue
                }
                if character == quote {
                    if options.doubleQuote, index + 1 < characters.count, characters[index + 1] == quote {
                        field.append(character); index += 2; continue
                    }
                    inQuotes = false; index += 1; continue
                }
                field.append(character); index += 1; continue
            }
            if atFieldStart, options.skipInitialSpaces, character == " " { index += 1; continue }
            if atFieldStart, character == quote { inQuotes = true; quoted = true; atFieldStart = false; index += 1; continue }
            if matches(delimiter, at: index) { endField(); index += delimiter.count; continue }
            if matches(terminatorCharacters, at: index) { endRecord(); index += terminatorCharacters.count; continue }
            if let escape, character == escape, escape != quote, index + 1 < characters.count {
                field.append(characters[index + 1]); index += 2; atFieldStart = false; continue
            }
            field.append(character); atFieldStart = false; index += 1
        }
        if !field.isEmpty || !record.isEmpty || quoted { endRecord() }
        return records
    }

    static func writeCSV(_ table: CMLTable, to url: URL) throws {
        func cell(_ value: MLDataValue) -> String {
            switch value {
            case .invalid: return ""
            case .int, .double: return value.description
            case .sequence, .dictionary, .multiArray:
                let json = (try? JSONSerialization.data(withJSONObject: jsonObject(value), options: [.fragmentsAllowed]))
                return quoteCSV(json.flatMap { String(data: $0, encoding: .utf8) } ?? value.description)
            case .string(let string): return quoteCSV(string)
            }
        }
        var lines = [table.names.map(quoteCSV).joined(separator: ",")]
        for row in 0..<table.rowCount {
            lines.append(table.rowValues(row).map(cell).joined(separator: ","))
        }
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    static func quoteCSV(_ string: String) -> String {
        guard string.contains(where: { [",", "\"", "\n", "\r"].contains($0) }) || string.hasPrefix(" ") else { return string }
        return "\"" + string.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // JSON: an array of objects, one per row.

    static func jsonObject(_ value: MLDataValue) -> Any {
        switch value {
        case .int(let value): return value
        case .double(let value): return value.isFinite ? value as Any : String(value)
        case .string(let value): return value
        case .sequence(let value): return value.map(jsonObject)
        case .dictionary(let value):
            var object: [String: Any] = [:]
            for (key, element) in value._contents { object[key.stringValue ?? key.description] = jsonObject(element) }
            return object
        case .multiArray(let value): return value.elements
        case .invalid: return NSNull()
        }
    }

    static func readJSON(_ data: Data) throws -> CMLTable {
        let object = try JSONSerialization.jsonObject(with: data)
        if let directory = object as? [String: Any], directory["columns"] != nil {
            return try decodeDirectory(directory)
        }
        guard let rows = object as? [[String: Any]] else {
            throw MLCreateError.io(reason: "A JSON table must be an array of objects, one per row.")
        }
        var names: [String] = []
        for row in rows { for key in row.keys.sorted() where !names.contains(key) { names.append(key) } }
        let columns = names.map { name in
            CMLColumn(values: rows.map { row in row[name].flatMap { try? MLDataValue(fromAny: $0) } ?? .invalid })
        }
        return CMLTable(names: names, columns: columns)
    }

    static func writeJSON(_ table: CMLTable, to url: URL) throws {
        let rows = (0..<table.rowCount).map { row in
            Dictionary(uniqueKeysWithValues: zip(table.names, table.rowValues(row).map(jsonObject)))
        }
        try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]).write(to: url)
    }

    // The directory format: columns with their types, values tagged with
    // theirs, so a table reads back as it was.

    static func tagged(_ value: MLDataValue) -> Any {
        switch value {
        case .int(let value): return ["i": value]
        case .double(let value): return ["d": value.isFinite ? value as Any : String(value)]
        case .string(let value): return ["s": value]
        case .sequence(let value): return ["q": value.map(tagged)]
        case .dictionary(let value): return ["m": value._contents.map { [tagged($0.key), tagged($0.value)] }]
        case .multiArray(let value):
            return ["a": ["shape": value._contents.shape.map(\.intValue), "values": value.elements]]
        case .invalid: return NSNull()
        }
    }

    static func untagged(_ object: Any) -> MLDataValue {
        guard let object = object as? [String: Any], let (tag, payload) = object.first else { return .invalid }
        switch tag {
        case "i": return (payload as? NSNumber).map { .int($0.intValue) } ?? .invalid
        case "d":
            if let number = payload as? NSNumber { return .double(number.doubleValue) }
            return (payload as? String).flatMap(Double.init).map(MLDataValue.double) ?? .invalid
        case "s": return (payload as? String).map(MLDataValue.string) ?? .invalid
        case "q": return .sequence(MLDataValue.SequenceType(((payload as? [Any]) ?? []).map(untagged)))
        case "m":
            var contents: [MLDataValue: MLDataValue] = [:]
            for pair in (payload as? [[Any]]) ?? [] where pair.count == 2 { contents[untagged(pair[0])] = untagged(pair[1]) }
            return .dictionary(MLDataValue.DictionaryType(contents))
        case "a":
            guard let payload = payload as? [String: Any], let shape = payload["shape"] as? [Int],
                  let values = payload["values"] as? [Double] else { return .invalid }
            let array = MLDataValue.MultiArrayType(shape: shape)
            for (index, value) in values.enumerated() where index < array._contents.count {
                array._contents[index] = NSNumber(value: value)
            }
            return .multiArray(array)
        default: return .invalid
        }
    }

    static func typeName(_ type: CMLFeatureValueType) -> String {
        switch type {
        case .int64: return "int"
        case .double: return "double"
        case .string: return "string"
        case .sequence: return "sequence"
        case .dictionary: return "dictionary"
        case .multiArray: return "multiArray"
        case .undefined: return "undefined"
        }
    }

    static func type(named name: String) -> CMLFeatureValueType {
        ["int": .int64, "double": .double, "string": .string, "sequence": .sequence,
         "dictionary": .dictionary, "multiArray": .multiArray][name] ?? .undefined
    }

    static func writeDirectory(_ table: CMLTable, to url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let columns = zip(table.names, table.columnList).map { name, column -> [String: Any] in
            ["name": name, "type": typeName(column.type), "values": column.values.map(tagged)]
        }
        let object: [String: Any] = ["format": "Perry CreateML table", "version": 1, "columns": columns]
        try JSONSerialization.data(withJSONObject: object).write(to: url.appendingPathComponent(directoryFileName))
    }

    static func readDirectory(_ url: URL) throws -> CMLTable {
        let file = url.appendingPathComponent(directoryFileName)
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw MLCreateError.io(reason: "\(url.path) isn't a table written by MLDataTable.write(to:) in Perry.")
        }
        guard let object = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any] else {
            throw MLCreateError.io(reason: "\(file.path) isn't a table.")
        }
        return try decodeDirectory(object)
    }

    static func decodeDirectory(_ object: [String: Any]) throws -> CMLTable {
        guard let columns = object["columns"] as? [[String: Any]] else {
            throw MLCreateError.io(reason: "The table file has no columns.")
        }
        var names: [String] = [], list: [CMLColumn] = []
        for column in columns {
            guard let name = column["name"] as? String, let values = column["values"] as? [Any] else {
                throw MLCreateError.io(reason: "A column of the table file is malformed.")
            }
            names.append(name)
            list.append(CMLColumn(values: values.map(untagged), type: type(named: column["type"] as? String ?? "")))
        }
        return CMLTable(names: names, columns: list)
    }
}

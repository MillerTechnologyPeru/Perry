// Descriptions: frames, rows and columns drawn as tables with box-drawing
// characters, cells formatted per FormattingOptions.

import Foundation

public struct FormattingOptions: Sendable {
    public var maximumLineWidth: Int
    public var maximumCellWidth: Int
    public var maximumRowCount: Int
    public var includesColumnTypes: Bool
    public var includesRowIndices: Bool = true
    public var includesRowAndColumnCounts: Bool = true

    internal var _floatingPointFormatStyle: FloatingPointFormatStyle<Double>
    internal var _integerFormatStyle: IntegerFormatStyle<Int>
    internal var _dateFormatStyle: Date.FormatStyle
    internal var _locale: Locale

    public var floatingPointFormatStyle: FloatingPointFormatStyle<Double> {
        get { _floatingPointFormatStyle }
        set { _floatingPointFormatStyle = newValue }
    }

    public var integerFormatStyle: IntegerFormatStyle<Int> {
        get { _integerFormatStyle }
        set { _integerFormatStyle = newValue }
    }

    public var dateFormatStyle: Date.FormatStyle {
        get { _dateFormatStyle }
        set { _dateFormatStyle = newValue }
    }

    /// Setting the locale sets the format styles' locales too.
    public var locale: Locale {
        get { _locale }
        set {
            _locale = newValue
            _floatingPointFormatStyle = _floatingPointFormatStyle.locale(newValue)
            _integerFormatStyle = _integerFormatStyle.locale(newValue)
            _dateFormatStyle = _dateFormatStyle.locale(newValue)
        }
    }

    public init() {
        self.init(maximumLineWidth: 200)
    }

    public init(locale: Locale) {
        self.init()
        self.locale = locale
    }

    public init(maximumLineWidth: Int, maximumCellWidth: Int = 50, maximumRowCount: Int = 20, includesColumnTypes: Bool = true) {
        self.maximumLineWidth = maximumLineWidth
        self.maximumCellWidth = maximumCellWidth
        self.maximumRowCount = maximumRowCount
        self.includesColumnTypes = includesColumnTypes
        _locale = .current
        _floatingPointFormatStyle = FloatingPointFormatStyle<Double>(locale: .current).precision(.fractionLength(1 ... 6))
        _integerFormatStyle = IntegerFormatStyle<Int>(locale: .current)
        _dateFormatStyle = Date.FormatStyle(date: .numeric, time: .shortened, locale: .current)
    }

    /// Whether values of a type are numbers formatted by the styles and aligned right.
    internal static func isNumeric(_ type: any Any.Type) -> Bool {
        type == Int.self || type == Double.self || type == Float.self
    }

    /// A cell's text.
    internal func format(_ value: Any?) -> String {
        guard let value, !_isNilValue(value) else { return "nil" }
        switch value {
        case let int as Int:
            return _integerFormatStyle.format(int)
        case let double as Double:
            return _floatingPointFormatStyle.format(double)
        case let float as Float:
            return _floatingPointFormatStyle.format(Double(float))
        case let date as Date:
            return _dateFormatStyle.format(date)
        case let data as Data:
            return "\(data.count) bytes"
        case let string as String:
            return string
        default:
            return String(describing: value)
        }
    }
}

/// A column to draw: its header and cells.
internal struct _TableColumn {
    var name: String
    var typeName: String
    var alignsRight: Bool
    var cells: [String]

    init(name: String, type: any Any.Type, values: [Any?], options: FormattingOptions) {
        self.name = name
        typeName = "<\(type)>"
        alignsRight = FormattingOptions.isNumeric(type)
        cells = values.map { options.format($0) }
    }
}

/// Draws a table. rowLabels are the row indices shown (nil to show none);
/// totalRows and totalColumns are counted in the footer.
internal func _drawTable(columns allColumns: [_TableColumn], rowLabels: [String], rowCount: Int,
                         showsIndices: Bool, footer: (rows: Int, columns: Int)?, options: FormattingOptions) -> String {
    if allColumns.isEmpty { return "" }
    func truncated(_ text: String) -> String {
        let limit = Swift.max(options.maximumCellWidth, 1)
        guard text.count > limit else { return text }
        return String(text.prefix(limit - 1)) + "…"
    }
    func padded(_ text: String, _ width: Int, right: Bool) -> String {
        let padding = String(repeating: " ", count: Swift.max(width - text.count, 0))
        return right ? padding + text : text + padding
    }
    let shownRows = Swift.min(rowCount, Swift.max(options.maximumRowCount, 0))
    let rowsTruncated = shownRows < rowCount
    let types = options.includesColumnTypes

    struct Drawn {
        var header: String
        var type: String
        var cells: [String]
        var right: Bool
        var width: Int
    }
    let drawnColumns = allColumns.map { column -> Drawn in
        let cells = column.cells.prefix(shownRows).map(truncated)
        let header = truncated(column.name), type = truncated(column.typeName)
        let width = ([header.count, types ? type.count : 0] + cells.map(\.count)).max()!
        return Drawn(header: header, type: type, cells: Array(cells), right: column.alignsRight, width: width)
    }
    let labels = Array(rowLabels.prefix(shownRows))
    let indexWidth = labels.map(\.count).max() ?? 0

    // Fit columns into the line width, leaving room for a column counting the rest.
    var lineWidth = 1 + (showsIndices ? indexWidth + 3 : 0)
    let fullWidth = drawnColumns.reduce(lineWidth) { $0 + $1.width + 3 }
    var shown = drawnColumns.count
    var moreLines: [String] = []
    var moreWidth = 0
    if fullWidth > options.maximumLineWidth {
        func moreColumn(_ remaining: Int) -> (lines: [String], width: Int) {
            let lines = types ? ["\(remaining)", "more"] : ["\(remaining) more"]
            return (lines, lines.map(\.count).max()!)
        }
        shown = 0
        while shown < drawnColumns.count {
            let next = lineWidth + drawnColumns[shown].width + 3
            let more = moreColumn(drawnColumns.count - shown - 1)
            if shown + 1 < drawnColumns.count && next + more.width + 3 > options.maximumLineWidth { break }
            if shown + 1 == drawnColumns.count && next > options.maximumLineWidth { break }
            lineWidth = next
            shown += 1
        }
        if shown < drawnColumns.count {
            (moreLines, moreWidth) = moreColumn(drawnColumns.count - shown)
        }
    }
    let columns = Array(drawnColumns.prefix(shown))
    let hasMore = !moreLines.isEmpty

    var widths = columns.map(\.width)
    if showsIndices { widths.insert(indexWidth, at: 0) }
    func border(_ left: String, _ fill: String, _ join: String, _ right: String, moreFill: String, moreRight: String) -> String {
        var line = left + widths.map { String(repeating: fill, count: $0 + 2) }.joined(separator: join)
        if hasMore {
            line += join + String(repeating: moreFill, count: moreWidth + 2) + moreRight
        } else {
            line += right
        }
        return line
    }
    func row(_ cells: [String], _ separator: String, more: String, moreRight: String) -> String {
        var line = separator + cells.map { " \($0) " }.joined(separator: separator)
        if hasMore {
            line += separator + " " + padded(more, moreWidth, right: false) + " " + moreRight
        } else {
            line += separator
        }
        return line
    }

    var lines: [String] = []
    lines.append(border("┏", "━", "┳", "┓", moreFill: "╍", moreRight: "┓"))
    var headerCells = columns.map { padded($0.header, $0.width, right: false) }
    if showsIndices { headerCells.insert(padded("", indexWidth, right: false), at: 0) }
    lines.append(row(headerCells, "┃", more: moreLines.first ?? "", moreRight: "┇"))
    if types {
        var typeCells = columns.map { padded($0.type, $0.width, right: false) }
        if showsIndices { typeCells.insert(padded("", indexWidth, right: false), at: 0) }
        lines.append(row(typeCells, "┃", more: moreLines.count > 1 ? moreLines[1] : "", moreRight: "┇"))
    }
    lines.append(border("┡", "━", "╇", "┩", moreFill: "╍", moreRight: "┩"))
    for r in 0 ..< shownRows {
        var cells = columns.map { padded($0.cells[r], $0.width, right: $0.right) }
        if showsIndices { cells.insert(padded(labels[r], indexWidth, right: false), at: 0) }
        lines.append(row(cells, "│", more: "", moreRight: "┆"))
    }
    if rowsTruncated {
        let bottom = border("┢", "╍", "┷", "┪", moreFill: "╍", moreRight: "┪")
        let inner = bottom.count - 2
        lines.append(bottom)
        lines.append("┇" + padded(" ...", inner, right: false) + "┇")
        lines.append("┗" + String(repeating: "╍", count: inner) + "┛")
    } else {
        lines.append(border("└", "─", "┴", "┘", moreFill: "╌", moreRight: "┘"))
    }
    if let footer, options.includesRowAndColumnCounts {
        let rows = footer.rows == 1 ? "1 row" : "\(footer.rows) rows"
        let columns = footer.columns == 1 ? "1 column" : "\(footer.columns) columns"
        lines.append("\(rows), \(columns)")
    }
    return lines.map { $0 + "\n" }.joined()
}

extension DataFrameProtocol {
    public func description(options: FormattingOptions) -> String {
        let frame = base
        let indices = _rowIndices
        let shown = Array(indices.prefix(Swift.max(options.maximumRowCount, 0)))
        let columns = frame._columns.map { column in
            _TableColumn(name: column.name, type: column.wrappedElementType, values: shown.map { column[$0] }, options: options)
        }
        return _drawTable(columns: columns, rowLabels: shown.map(String.init), rowCount: indices.count,
                          showsIndices: options.includesRowIndices, footer: (indices.count, frame._columns.count), options: options)
    }
}

extension DataFrame: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        description(options: FormattingOptions())
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(self, children: ["column names": _columns.map(\.name), "number of rows": _rowCount], displayStyle: .struct)
    }
}

extension DataFrame.Slice: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        description(options: FormattingOptions())
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(self, children: ["column names": _base._columns.map(\.name), "number of rows": _set.count], displayStyle: .struct)
    }
}

extension DataFrame.Row: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        description(options: FormattingOptions())
    }

    public func description(options: FormattingOptions) -> String {
        DataFrame.Slice(base: _base, ranges: _RangeSet(index ..< index + 1)).description(options: options)
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(self, children: ["index": index, "base": _base], displayStyle: .struct)
    }
}

/// A column drawn alone: no row indices or counts.
internal func _columnDescription<C: Collection>(name: String, type: any Any.Type, values: C, options: FormattingOptions) -> String
where C.Element == Any? {
    let shown = Array(values.prefix(Swift.max(options.maximumRowCount, 0)))
    let column = _TableColumn(name: name, type: type, values: shown, options: options)
    return _drawTable(columns: [column], rowLabels: [], rowCount: values.count, showsIndices: false, footer: nil, options: options)
}

extension OptionalColumnProtocol {
    public func description(options: FormattingOptions) -> String {
        _columnDescription(name: name, type: WrappedElement.self, values: map { $0.map { $0 as Any } }, options: options)
    }
}

extension Column: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        description(options: FormattingOptions())
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(self, children: ["name": name, "count": count, "contents": Array(self)], displayStyle: .struct)
    }
}

extension ColumnSlice: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        description(options: FormattingOptions())
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(self, children: ["name": name, "count": count, "contents": Array(self)], displayStyle: .struct)
    }
}

extension DiscontiguousColumnSlice: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        description(options: FormattingOptions())
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(self, children: ["name": name, "count": count, "contents": Array(self)], displayStyle: .struct)
    }
}

extension FilledColumn: CustomStringConvertible {
    public var description: String {
        description(options: FormattingOptions())
    }

    public var debugDescription: String {
        description
    }

    public func description(options: FormattingOptions) -> String {
        _columnDescription(name: name, type: WrappedElement.self, values: map { $0 as Any? }, options: options)
    }
}

extension AnyColumn: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        _columnDescription(name: name, type: wrappedElementType, values: self, options: FormattingOptions())
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(self, children: ["name": name, "count": count, "contents": Array(self)], displayStyle: .struct)
    }
}

extension AnyColumnSlice: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        _columnDescription(name: name, type: wrappedElementType, values: self, options: FormattingOptions())
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(self, children: ["name": name, "count": count, "contents": Array(self)], displayStyle: .struct)
    }
}

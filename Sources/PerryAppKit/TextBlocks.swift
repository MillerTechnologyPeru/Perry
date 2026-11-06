import CPerryGeometry
import PerryObjCInterop

// The text system's blocks and tabs: NSTextBlock (a paragraph's box, with
// widths, padding, borders and a background), NSTextTable and
// NSTextTableBlock (a table and one of its cells), NSTextList and NSTextTab.
// Text is laid out as plain paragraphs here; these keep what is set so it
// reads back.

/// NSTextBlockValueType: absolute 0, percentage 1. NSTextBlockDimension:
/// width 0, minimum 1, maximum 2, height 4, minimum 5, maximum 6.
/// NSTextBlockLayer: padding -1, border 0, margin 1. NSRectEdge: min x 0,
/// min y 1, max x 2, max y 3.
@ObjCClass("NSTextBlock")
open class NSTextBlock: NSObject {
    var dimensions: [Int: (value: CGFloat, type: Int)] = [:]
    var widths: [Int: (value: CGFloat, type: Int)] = [:]
    var borderColors: [Int: NSColor] = [:]
    var backgroundColor: NSColor?
    var verticalAlignment = 0

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("setValue:type:forDimension:")
    func setValue(_ value: CGFloat, type: Int, forDimension dimension: Int) { dimensions[dimension] = (value, type) }
    @ObjCMethod("valueForDimension:") func value(forDimension dimension: Int) -> CGFloat { dimensions[dimension]?.value ?? 0 }
    @ObjCMethod("valueTypeForDimension:") func valueType(forDimension dimension: Int) -> Int { dimensions[dimension]?.type ?? 0 }

    @ObjCMethod("setContentWidth:type:")
    func setContentWidth(_ value: CGFloat, type: Int) { dimensions[0] = (value, type) }
    @ObjCMethod("contentWidth") func contentWidth() -> CGFloat { dimensions[0]?.value ?? 0 }
    @ObjCMethod("contentWidthValueType") func contentWidthValueType() -> Int { dimensions[0]?.type ?? 0 }

    private func key(_ layer: Int, _ edge: Int) -> Int { (layer + 1) * 4 + edge }

    @ObjCMethod("setWidth:type:forLayer:edge:")
    func setWidth(_ value: CGFloat, type: Int, forLayer layer: Int, edge: Int) { widths[key(layer, edge)] = (value, type) }
    @ObjCMethod("setWidth:type:forLayer:")
    func setWidth(_ value: CGFloat, type: Int, forLayer layer: Int) { for edge in 0..<4 { widths[key(layer, edge)] = (value, type) } }
    @ObjCMethod("widthForLayer:edge:") func width(forLayer layer: Int, edge: Int) -> CGFloat { widths[key(layer, edge)]?.value ?? 0 }
    @ObjCMethod("widthValueTypeForLayer:edge:") func widthValueType(forLayer layer: Int, edge: Int) -> Int { widths[key(layer, edge)]?.type ?? 0 }

    @ObjCMethod("setBorderColor:forEdge:") func setBorderColor(_ color: NSColor?, forEdge edge: Int) { borderColors[edge] = color }
    @ObjCMethod("setBorderColor:") func setBorderColor(_ color: NSColor?) { for edge in 0..<4 { borderColors[edge] = color } }
    @ObjCMethod("borderColorForEdge:") func borderColor(forEdge edge: Int) -> NSColor? { borderColors[edge] }
    @ObjCMethod("backgroundColor") func backgroundColorValue() -> NSColor? { backgroundColor }
    @ObjCMethod("setBackgroundColor:") func setBackgroundColor(_ color: NSColor?) { backgroundColor = color }
    /// NSTextBlockVerticalAlignment: top 0, middle 1, bottom 2, baseline 3.
    @ObjCMethod("verticalAlignment") func verticalAlignmentValue() -> Int { verticalAlignment }
    @ObjCMethod("setVerticalAlignment:") func setVerticalAlignment(_ value: Int) { verticalAlignment = value }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { Send.object(objcObject, "retain")! }
}

@ObjCClass("NSTextTable")
open class NSTextTable: NSTextBlock {
    var numberOfColumns = 0
    var layoutAlgorithm = 0
    var collapsesBorders = false
    var hidesEmptyCells = false

    @ObjCMethod("init")
    public required init() { super.init() }

    @ObjCMethod("numberOfColumns") func numberOfColumnsValue() -> UInt { UInt(numberOfColumns) }
    @ObjCMethod("setNumberOfColumns:") func setNumberOfColumns(_ value: UInt) { numberOfColumns = Int(value) }
    @ObjCMethod("layoutAlgorithm") func layoutAlgorithmValue() -> Int { layoutAlgorithm }
    @ObjCMethod("setLayoutAlgorithm:") func setLayoutAlgorithm(_ value: Int) { layoutAlgorithm = value }
    @ObjCMethod("collapsesBorders") func collapsesBordersValue() -> Bool { collapsesBorders }
    @ObjCMethod("setCollapsesBorders:") func setCollapsesBorders(_ value: Bool) { collapsesBorders = value }
    @ObjCMethod("hidesEmptyCells") func hidesEmptyCellsValue() -> Bool { hidesEmptyCells }
    @ObjCMethod("setHidesEmptyCells:") func setHidesEmptyCells(_ value: Bool) { hidesEmptyCells = value }
}

@ObjCClass("NSTextTableBlock")
open class NSTextTableBlock: NSTextBlock {
    var table: NSTextTable?
    var row = 0, rowSpan = 1, column = 0, columnSpan = 1

    @ObjCMethod("init")
    public required init() { super.init() }

    @ObjCMethod("initWithTable:startingRow:rowSpan:startingColumn:columnSpan:")
    public required init(table: NSTextTable?, startingRow row: Int, rowSpan: Int, startingColumn column: Int, columnSpan: Int) {
        super.init()
        self.table = table
        (self.row, self.rowSpan, self.column, self.columnSpan) = (row, rowSpan, column, columnSpan)
    }

    @ObjCMethod("table") func tableValue() -> NSTextTable? { table }
    @ObjCMethod("startingRow") func startingRow() -> Int { row }
    @ObjCMethod("rowSpan") func rowSpanValue() -> Int { rowSpan }
    @ObjCMethod("startingColumn") func startingColumn() -> Int { column }
    @ObjCMethod("columnSpan") func columnSpanValue() -> Int { columnSpan }
}

@ObjCClass("NSTextList")
open class NSTextList: NSObject {
    var markerFormat = ""
    var options: UInt = 0
    var startingItemNumber = 1

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithMarkerFormat:options:")
    public required init(markerFormat: String?, options: UInt) {
        super.init()
        self.markerFormat = markerFormat ?? ""
        self.options = options
    }

    @ObjCMethod("markerFormat") func markerFormatValue() -> String { markerFormat }
    @ObjCMethod("listOptions") func listOptions() -> UInt { options }
    @ObjCMethod("startingItemNumber") func startingItemNumberValue() -> Int { startingItemNumber }
    @ObjCMethod("setStartingItemNumber:") func setStartingItemNumber(_ value: Int) { startingItemNumber = value }

    @ObjCMethod("markerForItemNumber:")
    func marker(forItemNumber number: Int) -> String {
        markerFormat.split(separator: "{decimal}", omittingEmptySubsequences: false).joined(separator: String(number))
    }
}

/// A tab stop: its alignment (NSTextAlignment, left 0) and location.
@ObjCClass("NSTextTab")
open class NSTextTab: NSObject {
    var alignment = 0
    var location: CGFloat = 0
    var options: NSObject?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithTextAlignment:location:options:")
    public required init(textAlignment alignment: Int, location: CGFloat, options: NSObject?) {
        super.init()
        (self.alignment, self.location, self.options) = (alignment, location, options)
    }

    /// NSTextTabType: left 0, right 1, center 2, decimal 3.
    @ObjCMethod("initWithType:location:")
    public required init(type: UInt, location: CGFloat) {
        super.init()
        alignment = [0, 2, 1, 2][Int(min(type, 3))]
        self.location = location
    }

    @ObjCMethod("alignment") func alignmentValue() -> Int { alignment }
    @ObjCMethod("location") func locationValue() -> CGFloat { location }
    @ObjCMethod("options") func optionsValue() -> NSObject? { options }
    @ObjCMethod("tabStopType") func tabStopType() -> UInt { alignment == 2 ? 1 : alignment == 1 ? 2 : 0 }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { Send.object(objcObject, "retain")! }
}

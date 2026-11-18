import CPerryGeometry
import Glibc
import PerryObjCInterop

// NSMatrix: a grid of cells of one size, row by row, that a click selects
// in: in radio mode one cell is on at a time, in highlight and list modes
// cells highlight as they are chosen, in track mode the cell tracks the
// mouse itself. A matrix sends its action (or the selected cell's own) when
// the click ends, and its double action on a double click. Nibs keep the
// cells in "NSCells", the grid in "NSNumRows" and "NSNumCols", and the
// mode and drawing settings in the bits of "NSMatrixFlags".

@ObjCClass("NSMatrix")
open class NSMatrix: NSControl {
    /// NSMatrixMode.
    enum Mode: UInt {
        case radio = 0, highlight = 1, list = 2, track = 3
    }

    var cells: [NSCell] = []
    var rows = 0
    var columns = 0
    var cellSize = CGSize(width: 100, height: 17)
    var intercellSpacing = CGSize(width: 1, height: 1)
    var mode = Mode.radio
    var prototype: NSCell?
    var matrixCellClass: ObjCClass?
    var selectedRow = -1
    var selectedColumn = -1
    var keyRow = -1
    var keyColumn = -1
    var allowsEmptySelection = false
    var selectionByRect = true
    var autosizesCells = false
    var tabKeyTraversesCells = false
    var drawsBackground = false
    var drawsCellBackground = false
    var backgroundColor: NSColor?
    var cellBackgroundColor: NSColor?
    var doubleAction: ObjCSelector?
    /// Not retained.
    var delegate: UnsafeMutableRawPointer?
    var cellToolTips: [ObjectIdentifier: String] = [:]

    public required init() { super.init() }

    @ObjCMethod("initWithFrame:")
    public required init(frame: CGRect) { super.init(frame: frame) }

    @ObjCMethod("initWithFrame:mode:prototype:numberOfRows:numberOfColumns:")
    public required init(frame: CGRect, mode: UInt, prototype: NSCell?, rows: Int, columns: Int) {
        super.init(frame: frame)
        self.mode = Mode(rawValue: mode) ?? .radio
        self.prototype = prototype
        if let size = prototype.map({ Send.size($0.objcObject, "cellSize") }), size.width > 0 { cellSize = size }
        renew(rows: rows, columns: columns)
        selectInitially()
    }

    @ObjCMethod("initWithFrame:mode:cellClass:numberOfRows:numberOfColumns:")
    public required init(frame: CGRect, mode: UInt, cellClass: ObjCClass?, rows: Int, columns: Int) {
        super.init(frame: frame)
        self.mode = Mode(rawValue: mode) ?? .radio
        matrixCellClass = cellClass
        renew(rows: rows, columns: columns)
        selectInitially()
    }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init(coder: coder)
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        // The bits, from the highest: highlight, radio, list, allows empty
        // selection, autoscroll, selection by rect, draws cell background,
        // draws background, autosizes cells, (drawing ancestor), tab key
        // traverses cells.
        let flags = UInt32(truncatingIfNeeded: decoded.integer("NSMatrixFlags"))
        if decoded.has("NSMatrixFlags") {
            mode = flags & 0x4000_0000 != 0 ? .radio : flags & 0x2000_0000 != 0 ? .list : flags & 0x8000_0000 != 0 ? .highlight : .track
            allowsEmptySelection = flags & 0x1000_0000 != 0
            selectionByRect = flags & 0x0400_0000 != 0
            drawsCellBackground = flags & 0x0200_0000 != 0
            drawsBackground = flags & 0x0100_0000 != 0
            autosizesCells = flags & 0x0080_0000 != 0
            tabKeyTraversesCells = flags & 0x0020_0000 != 0
        }
        rows = decoded.integer("NSNumRows")
        columns = decoded.integer("NSNumCols")
        if decoded.has("NSCellSize") { cellSize = decoded.size("NSCellSize") }
        if decoded.has("NSIntercellSpacing") { intercellSpacing = decoded.size("NSIntercellSpacing") }
        prototype = decoded.object("NSProtoCell")?.as(NSCell.self)
        matrixCellClass = decoded.string("NSCellClass").flatMap(Classes.named)
            ?? decoded.object("NSCellClass").flatMap { $0.responds(to: "UTF8String") ? Classes.named($0.stringValue) : nil }
        backgroundColor = decoded.object("NSBackgroundColor")?.as(NSColor.self)
        cellBackgroundColor = decoded.object("NSCellBackgroundColor")?.as(NSColor.self)
        doubleAction = decoded.selector("NSDoubleAction")
        cells = decoded.array("NSCells").compactMap { $0.as(NSCell.self) }
        for cell in cells { cell.controlViewObject = objcObject }
        if cells.count != rows * columns { renew(rows: rows, columns: columns) }
        if let selected = decoded.object("NSSelectedCell"), let index = cells.firstIndex(where: { $0.objcObject == selected.objcObject }) {
            (selectedRow, selectedColumn) = (index / max(columns, 1), index % max(columns, 1))
            if mode == .radio { cells[index].state = 1 }
        } else {
            selectInitially()
        }
        (keyRow, keyColumn) = (selectedRow, selectedColumn)
    }

    /// A radio matrix that can't be empty has a cell on.
    func selectInitially() {
        if let index = cells.firstIndex(where: { $0.state != 0 }) {
            (selectedRow, selectedColumn) = (index / max(columns, 1), index % max(columns, 1))
        } else if mode == .radio, !allowsEmptySelection, !cells.isEmpty {
            select(index: 0)
        }
    }

    // MARK: Cells

    func index(row: Int, column: Int) -> Int? {
        guard row >= 0, row < rows, column >= 0, column < columns else { return nil }
        let index = row * columns + column
        return cells.indices.contains(index) ? index : nil
    }

    func cell(row: Int, column: Int) -> NSCell? { index(row: row, column: column).map { cells[$0] } }

    var selectedIndex: Int? { index(row: selectedRow, column: selectedColumn) }

    /// A new cell: a copy of the prototype, or one of the cell class.
    func makeCell() -> NSCell? {
        let made: UnsafeMutableRawPointer?
        if let prototype {
            made = Send.object(prototype.objcObject, "copyWithZone:", nil)
        } else {
            let cls = matrixCellClass?.pointer ?? Send.object(ObjCRuntime.objectClass(objcObject), "cellClass")
            made = cls.flatMap { Send.object($0, "alloc") }.flatMap { Send.object($0, "init") }
        }
        guard let made else { return nil }
        let cell = NSCell.objCInstance(made, ownership: .adopt)
        cell.controlViewObject = objcObject
        return cell
    }

    /// Resizes the grid, keeping the cells that stay in it and making new
    /// ones for the rest.
    func renew(rows newRows: Int, columns newColumns: Int) {
        let (newRows, newColumns) = (max(newRows, 0), max(newColumns, 0))
        var renewed: [NSCell] = []
        for row in 0..<newRows {
            for column in 0..<newColumns {
                if let kept = cell(row: row, column: column) {
                    renewed.append(kept)
                } else if let made = makeCell() {
                    renewed.append(made)
                }
            }
        }
        (cells, rows, columns) = (renewed, newRows, newColumns)
        if selectedIndex == nil { (selectedRow, selectedColumn) = (-1, -1) }
        cellsChanged()
    }

    func cellsChanged() {
        if autosizesCells { fitCellsToBounds() }
        setNeedsDisplay(true)
    }

    var cellsSize: CGSize {
        CGSize(width: CGFloat(columns) * cellSize.width + CGFloat(max(columns - 1, 0)) * intercellSpacing.width,
               height: CGFloat(rows) * cellSize.height + CGFloat(max(rows - 1, 0)) * intercellSpacing.height)
    }

    /// The cells grown or shrunk to fill the matrix's bounds.
    func fitCellsToBounds() {
        guard rows > 0, columns > 0 else { return }
        let width = (bounds.width - CGFloat(columns - 1) * intercellSpacing.width) / CGFloat(columns)
        let height = (bounds.height - CGFloat(rows - 1) * intercellSpacing.height) / CGFloat(rows)
        cellSize = CGSize(width: max(width, 0), height: max(height, 0))
    }

    func frame(row: Int, column: Int) -> CGRect {
        CGRect(x: CGFloat(column) * (cellSize.width + intercellSpacing.width),
               y: CGFloat(row) * (cellSize.height + intercellSpacing.height),
               width: cellSize.width, height: cellSize.height)
    }

    func location(of point: CGPoint) -> (row: Int, column: Int)? {
        let strideX = cellSize.width + intercellSpacing.width
        let strideY = cellSize.height + intercellSpacing.height
        guard strideX > 0, strideY > 0, point.x >= 0, point.y >= 0 else { return nil }
        let column = Int(point.x / strideX), row = Int(point.y / strideY)
        guard index(row: row, column: column) != nil, frame(row: row, column: column).contains(point) else { return nil }
        return (row, column)
    }

    // MARK: Selection

    /// Selects the cell at `index`, or none for nil: in radio mode it alone
    /// is on; in highlight and list modes it alone is highlighted.
    func select(index: Int?) {
        for (other, cell) in cells.enumerated() where other != index {
            if mode == .radio, cell.state != 0 { cell.state = 0 }
            if mode == .highlight || mode == .list, cell.highlighted { cell.highlighted = false }
        }
        if let index {
            let cell = cells[index]
            switch mode {
            case .radio: cell.state = 1
            case .highlight, .list: cell.highlighted = true; cell.state = 1
            case .track: break
            }
            (selectedRow, selectedColumn) = (index / max(columns, 1), index % max(columns, 1))
            (keyRow, keyColumn) = (selectedRow, selectedColumn)
        } else {
            (selectedRow, selectedColumn) = (-1, -1)
        }
        setNeedsDisplay(true)
    }

    // MARK: Drawing

    @ObjCMethod("isFlipped") override func isFlipped() -> Bool { true }
    @ObjCMethod("isOpaque") override func isOpaque() -> Bool { drawsBackground && backgroundColor != nil }

    @ObjCMethod("drawRect:")
    override func draw(_ rect: CGRect) {
        if drawsBackground, let backgroundColor, let context = NSGraphicsContext.currentCG {
            CG.fill(CG.roundedRect(bounds, radius: 0), backgroundColor, in: context)
        }
        for row in 0..<rows {
            for column in 0..<columns {
                let frame = frame(row: row, column: column)
                guard frame.minX < rect.maxX, rect.minX < frame.maxX, frame.minY < rect.maxY, rect.minY < frame.maxY, let cell = cell(row: row, column: column) else { continue }
                if drawsCellBackground, let cellBackgroundColor, let context = NSGraphicsContext.currentCG {
                    CG.fill(CG.roundedRect(frame, radius: 0), cellBackgroundColor, in: context)
                }
                drawCell(cell, in: frame)
            }
        }
    }

    func drawCell(_ cell: NSCell, in frame: CGRect) {
        typealias F = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, CGRect, UnsafeMutableRawPointer?) -> Void
        unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(cell.objcObject, ObjCRuntime.selector("drawWithFrame:inView:"), frame, objcObject)
    }

    // MARK: Clicks

    var pressedIndex: Int?

    @ObjCMethod("mouseDown:")
    override func mouseDown(_ event: NSObject?) {
        guard enabled, let event = event?.as(NSEvent.self),
              let (row, column) = location(of: convert(event.locationInWindow, from: nil)),
              let index = index(row: row, column: column), cells[index].enabled else { return }
        _ = window?.makeFirstResponder(self)
        pressedIndex = index
        switch mode {
        case .track:
            cells[index].setHighlighted(true)
        case .radio, .highlight, .list:
            select(index: index)
        }
        if event.clickCount == 2, let doubleAction {
            pressedIndex = nil
            if mode == .track { cells[index].setHighlighted(false) }
            _ = sendAction(doubleAction, to: target.map(NSObject.init))
        }
    }

    @ObjCMethod("mouseDragged:")
    override func mouseDragged(_ event: NSObject?) {
        guard pressedIndex != nil, mode == .list || mode == .radio, let event = event?.as(NSEvent.self),
              let (row, column) = location(of: convert(event.locationInWindow, from: nil)),
              let index = index(row: row, column: column), index != selectedIndex, cells[index].enabled else { return }
        pressedIndex = index
        select(index: index)
    }

    @ObjCMethod("mouseUp:")
    override func mouseUp(_ event: NSObject?) {
        guard let index = pressedIndex else { return }
        pressedIndex = nil
        if mode == .track {
            cells[index].setHighlighted(false)
            guard let event = event?.as(NSEvent.self), location(of: convert(event.locationInWindow, from: nil)).map({ $0.row * columns + $0.column }) == index
            else { return }
            cells[index].setNextState()
            (selectedRow, selectedColumn) = (index / max(columns, 1), index % max(columns, 1))
        }
        _ = sendMatrixAction()
    }

    /// The selected cell's action to its target, or the matrix's own.
    func sendMatrixAction() -> Bool {
        if let cell = selectedIndex.map({ cells[$0] })?.as(NSActionCell.self), let action = cell.action {
            return sendAction(action, to: cell.target.map(NSObject.init) ?? target.map(NSObject.init))
        }
        guard let action else { return false }
        return sendAction(action, to: target.map(NSObject.init))
    }

    @ObjCMethod("acceptsFirstResponder") override func acceptsFirstResponder() -> Bool { enabled && !refusesFirstResponder }

    @ObjCMethod("performClick:")
    override func performClick(_ sender: NSObject?) { _ = sendMatrixAction() }

    // MARK: API

    @ObjCClassMethod("cellClass") static func matrixDefaultCellClass() -> ObjCClass? { Classes.named("NSActionCell") }

    @ObjCMethod("cellClass") func cellClassValue() -> ObjCClass? { matrixCellClass ?? Classes.named("NSActionCell") }
    @ObjCMethod("setCellClass:") func setCellClass(_ cls: ObjCClass?) { matrixCellClass = cls }
    @ObjCMethod("prototype") func prototypeValue() -> NSCell? { prototype }
    @ObjCMethod("setPrototype:") func setPrototype(_ cell: NSCell?) { prototype = cell }
    @ObjCMethod("mode") func modeValue() -> UInt { mode.rawValue }
    @ObjCMethod("setMode:") func setMode(_ value: UInt) { mode = Mode(rawValue: value) ?? .radio }
    @ObjCMethod("allowsEmptySelection") func allowsEmptySelectionValue() -> Bool { allowsEmptySelection }
    @ObjCMethod("setAllowsEmptySelection:") func setAllowsEmptySelection(_ value: Bool) { allowsEmptySelection = value }
    @ObjCMethod("isSelectionByRect") func isSelectionByRect() -> Bool { selectionByRect }
    @ObjCMethod("setSelectionByRect:") func setSelectionByRect(_ value: Bool) { selectionByRect = value }
    @ObjCMethod("autosizesCells") func autosizesCellsValue() -> Bool { autosizesCells }
    @ObjCMethod("setAutosizesCells:") func setAutosizesCells(_ value: Bool) { autosizesCells = value; cellsChanged() }
    @ObjCMethod("tabKeyTraversesCells") func tabKeyTraversesCellsValue() -> Bool { tabKeyTraversesCells }
    @ObjCMethod("setTabKeyTraversesCells:") func setTabKeyTraversesCells(_ value: Bool) { tabKeyTraversesCells = value }
    @ObjCMethod("drawsBackground") func drawsBackgroundValue() -> Bool { drawsBackground }
    @ObjCMethod("setDrawsBackground:") func setDrawsBackground(_ value: Bool) { drawsBackground = value; setNeedsDisplay(true) }
    @ObjCMethod("drawsCellBackground") func drawsCellBackgroundValue() -> Bool { drawsCellBackground }
    @ObjCMethod("setDrawsCellBackground:") func setDrawsCellBackground(_ value: Bool) { drawsCellBackground = value; setNeedsDisplay(true) }
    @ObjCMethod("backgroundColor") func backgroundColorValue() -> NSColor? { backgroundColor }
    @ObjCMethod("setBackgroundColor:") func setBackgroundColor(_ color: NSColor?) { backgroundColor = color; setNeedsDisplay(true) }
    @ObjCMethod("cellBackgroundColor") func cellBackgroundColorValue() -> NSColor? { cellBackgroundColor }
    @ObjCMethod("setCellBackgroundColor:") func setCellBackgroundColor(_ color: NSColor?) { cellBackgroundColor = color; setNeedsDisplay(true) }
    @ObjCMethod("doubleAction") func doubleActionValue() -> ObjCSelector? { doubleAction }
    @ObjCMethod("setDoubleAction:") func setDoubleAction(_ value: ObjCSelector?) { doubleAction = value }
    @ObjCMethod("delegate") func delegateValue() -> NSObject? { delegate.map(NSObject.init) }
    @ObjCMethod("setDelegate:") func setDelegate(_ value: NSObject?) { delegate = value?.objcObject }
    @ObjCMethod("setScrollable:") func setScrollable(_ value: Bool) { for cell in cells { cell.scrollable = value } }
    @ObjCMethod("setValidateSize:") func setValidateSize(_ value: Bool) {}
    @ObjCMethod("autoscroll") func autoscrollValue() -> Bool { false }
    @ObjCMethod("setAutoscroll:") func setAutoscroll(_ value: Bool) {}

    @ObjCMethod("cellSize") func cellSizeValue() -> CGSize { cellSize }
    @ObjCMethod("setCellSize:") func setCellSize(_ size: CGSize) { cellSize = size; setNeedsDisplay(true) }
    @ObjCMethod("intercellSpacing") func intercellSpacingValue() -> CGSize { intercellSpacing }
    @ObjCMethod("setIntercellSpacing:") func setIntercellSpacing(_ size: CGSize) { intercellSpacing = size; setNeedsDisplay(true) }

    @ObjCMethod("cells") func cellsArray() -> NSObject { NSMutableArray.of(cells) }
    @ObjCMethod("numberOfRows") func numberOfRows() -> Int { rows }
    @ObjCMethod("numberOfColumns") func numberOfColumns() -> Int { columns }
    @ObjCMethod("getNumberOfRows:columns:")
    func getNumber(ofRows rowsOut: UnsafeMutablePointer<Int>?, columns columnsOut: UnsafeMutablePointer<Int>?) {
        rowsOut?.pointee = rows
        columnsOut?.pointee = columns
    }

    @ObjCMethod("cellAtRow:column:") func cellAt(row: Int, column: Int) -> NSCell? { cell(row: row, column: column) }
    @ObjCMethod("cellWithTag:") func cell(withTag tag: Int) -> NSCell? { cells.first { $0.tag == tag } }
    @ObjCMethod("cellFrameAtRow:column:") func cellFrame(row: Int, column: Int) -> CGRect { frame(row: row, column: column) }

    @ObjCMethod("getRow:column:ofCell:")
    func getRow(_ rowOut: UnsafeMutablePointer<Int>?, column columnOut: UnsafeMutablePointer<Int>?, of cell: NSCell?) -> Bool {
        guard let cell, let index = cells.firstIndex(where: { $0 === cell }) else { return false }
        rowOut?.pointee = index / max(columns, 1)
        columnOut?.pointee = index % max(columns, 1)
        return true
    }

    @ObjCMethod("getRow:column:forPoint:")
    func getRow(_ rowOut: UnsafeMutablePointer<Int>?, column columnOut: UnsafeMutablePointer<Int>?, for point: CGPoint) -> Bool {
        guard let (row, column) = location(of: point) else { return false }
        rowOut?.pointee = row
        columnOut?.pointee = column
        return true
    }

    @ObjCMethod("putCell:atRow:column:")
    func put(_ cell: NSCell?, row: Int, column: Int) {
        guard let cell, let index = index(row: row, column: column) else { return }
        cell.controlViewObject = objcObject
        cells[index] = cell
        setNeedsDisplay(true)
    }

    @ObjCMethod("makeCellAtRow:column:") func makeCell(row: Int, column: Int) -> NSCell? { makeCell() }

    @ObjCMethod("renewRows:columns:") func renewRows(_ newRows: Int, columns newColumns: Int) { renew(rows: newRows, columns: newColumns) }
    @ObjCMethod("addRow") func addRow() { renew(rows: rows + 1, columns: max(columns, 1)) }
    @ObjCMethod("addColumn") func addColumn() { insertColumn(columns) }

    @ObjCMethod("addRowWithCells:")
    func addRow(withCells array: NSObject?) {
        insertRow(rows, withCells: array)
    }

    @ObjCMethod("insertRow:") func insertRow(_ row: Int) { insertRow(row, withCells: nil) }

    @ObjCMethod("insertRow:withCells:")
    func insertRow(_ row: Int, withCells array: NSObject?) {
        let given = array?.as(NSArray.self)?.elements.compactMap { $0.as(NSCell.self) } ?? []
        if columns == 0 { columns = max(given.count, 1) }
        let row = min(max(row, 0), rows)
        let inserted = (0..<columns).compactMap { column in column < given.count ? given[column] : makeCell() }
        for cell in inserted { cell.controlViewObject = objcObject }
        cells.insert(contentsOf: inserted, at: row * columns)
        rows += 1
        if selectedRow >= row { selectedRow += 1 }
        cellsChanged()
    }

    @ObjCMethod("insertColumn:")
    func insertColumn(_ column: Int) {
        if rows == 0 { rows = 1 }
        let column = min(max(column, 0), columns)
        var renewed: [NSCell] = []
        for row in 0..<rows {
            for old in 0...columns {
                if old == column {
                    if let made = makeCell() { renewed.append(made) }
                }
                if old < columns, let kept = cell(row: row, column: old) { renewed.append(kept) }
            }
        }
        cells = renewed
        columns += 1
        if selectedColumn >= column { selectedColumn += 1 }
        cellsChanged()
    }

    @ObjCMethod("removeRow:")
    func removeRow(_ row: Int) {
        guard row >= 0, row < rows else { return }
        cells.removeSubrange(row * columns..<(row + 1) * columns)
        rows -= 1
        if selectedRow == row { (selectedRow, selectedColumn) = (-1, -1) } else if selectedRow > row { selectedRow -= 1 }
        cellsChanged()
    }

    @ObjCMethod("removeColumn:")
    func removeColumn(_ column: Int) {
        guard column >= 0, column < columns else { return }
        for row in (0..<rows).reversed() { cells.remove(at: row * columns + column) }
        columns -= 1
        if columns == 0 { rows = 0 }
        if selectedColumn == column { (selectedRow, selectedColumn) = (-1, -1) } else if selectedColumn > column { selectedColumn -= 1 }
        cellsChanged()
    }

    @ObjCMethod("sizeToCells")
    func sizeToCells() { Send.void(objcObject, "setFrameSize:", size: cellsSize) }

    @ObjCMethod("sizeToFit") override func sizeToFit() { sizeToCells() }

    @ObjCMethod("setFrameSize:")
    override func setFrameSize(_ size: CGSize) {
        super.setFrameSize(size)
        if autosizesCells { fitCellsToBounds() }
    }

    @ObjCMethod("selectedCell") override func selectedCell() -> NSCell? { selectedIndex.map { cells[$0] } }
    @ObjCMethod("selectedCells")
    func selectedCells() -> NSObject {
        NSMutableArray.of(cells.filter { mode == .radio ? $0.state != 0 : $0.highlighted || $0.state != 0 })
    }
    @ObjCMethod("selectedRow") func selectedRowValue() -> Int { selectedRow }
    @ObjCMethod("selectedColumn") func selectedColumnValue() -> Int { selectedColumn }
    @ObjCMethod("selectedTag") override func selectedTag() -> Int { selectedCell()?.tag ?? -1 }

    @ObjCMethod("selectCellAtRow:column:")
    func selectCell(row: Int, column: Int) {
        if row < 0 || column < 0 {
            if allowsEmptySelection || mode != .radio { select(index: nil) }
            return
        }
        guard let index = index(row: row, column: column) else { return }
        select(index: index)
    }

    @ObjCMethod("selectCellWithTag:")
    func selectCell(withTag tag: Int) -> Bool {
        guard let index = cells.firstIndex(where: { $0.tag == tag }) else { return false }
        select(index: index)
        return true
    }

    @ObjCMethod("selectCell:")
    func selectCell(_ cell: NSCell?) {
        guard let cell, let index = cells.firstIndex(where: { $0 === cell }) else { return }
        select(index: index)
    }

    @ObjCMethod("selectAll:")
    func selectAll(_ sender: NSObject?) {
        guard mode == .list else { return }
        for cell in cells { cell.highlighted = true; cell.state = 1 }
        setNeedsDisplay(true)
    }

    @ObjCMethod("deselectAllCells")
    func deselectAllCells() {
        guard allowsEmptySelection || mode != .radio else { return }
        for cell in cells { cell.highlighted = false; if mode != .track { cell.state = 0 } }
        (selectedRow, selectedColumn) = (-1, -1)
        setNeedsDisplay(true)
    }

    @ObjCMethod("deselectSelectedCell")
    func deselectSelectedCell() {
        guard let index = selectedIndex, allowsEmptySelection || mode != .radio else { return }
        cells[index].highlighted = false
        cells[index].state = 0
        (selectedRow, selectedColumn) = (-1, -1)
        setNeedsDisplay(true)
    }

    @ObjCMethod("setSelectionFrom:to:anchor:highlight:")
    func setSelection(from start: Int, to end: Int, anchor: Int, highlight: Bool) {
        guard !cells.isEmpty else { return }
        let range = max(min(start, end), 0)...min(max(start, end), cells.count - 1)
        for index in range {
            cells[index].highlighted = highlight
            cells[index].state = highlight ? 1 : 0
        }
        if highlight { (selectedRow, selectedColumn) = (end / max(columns, 1), end % max(columns, 1)) }
        setNeedsDisplay(true)
    }

    @ObjCMethod("highlightCell:atRow:column:")
    func highlightCell(_ flag: Bool, row: Int, column: Int) {
        cell(row: row, column: column)?.setHighlighted(flag)
        setNeedsDisplay(true)
    }

    @ObjCMethod("keyCell") func keyCellValue() -> NSCell? { cell(row: keyRow, column: keyColumn) }
    @ObjCMethod("setKeyCell:")
    func setKeyCell(_ cell: NSCell?) {
        guard let cell, let index = cells.firstIndex(where: { $0 === cell }) else { return }
        (keyRow, keyColumn) = (index / max(columns, 1), index % max(columns, 1))
    }

    @ObjCMethod("sendAction") func sendActionValue() -> Bool { sendMatrixAction() }
    @ObjCMethod("sendDoubleAction")
    func sendDoubleAction() {
        if let doubleAction { _ = sendAction(doubleAction, to: target.map(NSObject.init)) } else { _ = sendMatrixAction() }
    }

    @ObjCMethod("drawCellAtRow:column:") func drawCell(row: Int, column: Int) { setNeedsDisplay(true) }

    @ObjCMethod("scrollCellToVisibleAtRow:column:")
    func scrollCellToVisible(row: Int, column: Int) {
        guard index(row: row, column: column) != nil else { return }
        _ = scrollRectToVisible(frame(row: row, column: column))
    }

    @ObjCMethod("setToolTip:forCell:")
    func setToolTip(_ toolTip: String?, for cell: NSCell?) {
        guard let cell else { return }
        cellToolTips[ObjectIdentifier(cell)] = toolTip
    }

    @ObjCMethod("toolTipForCell:")
    func toolTip(for cell: NSCell?) -> String? { cell.flatMap { cellToolTips[ObjectIdentifier($0)] } }

    @ObjCMethod("selectText:")
    func selectText(_ sender: NSObject?) { _ = window?.makeFirstResponder(self) }

    @ObjCMethod("selectTextAtRow:column:")
    func selectText(row: Int, column: Int) -> NSCell? {
        _ = window?.makeFirstResponder(self)
        return cell(row: row, column: column)
    }

    @ObjCMethod("textDidEndEditing:") func textDidEndEditing(_ notification: NSObject?) {}

    /// Arrows move the selection through the grid, as AppKit's do.
    @ObjCMethod("keyDown:")
    override func keyDown(_ event: NSObject?) {
        guard let event = event?.as(NSEvent.self) else { return super.keyDown(event) }
        let (row, column) = selectedIndex == nil ? (0, 0) : (selectedRow, selectedColumn)
        let target: (Int, Int)
        switch event.keyCode {
        case 0x7B: target = (row, column - 1)
        case 0x7C: target = (row, column + 1)
        case 0x7E: target = (row - 1, column)
        case 0x7D: target = (row + 1, column)
        default: return super.keyDown(event)
        }
        guard let index = index(row: target.0, column: target.1), cells[index].enabled else { return }
        select(index: index)
        scrollCellToVisible(row: target.0, column: target.1)
        _ = sendMatrixAction()
    }
}

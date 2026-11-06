import CPerryGeometry
import Glibc
import PerryObjCInterop

// Tables and outlines. NSTableView asks its data source for its rows and
// lays them out one under another, its columns side by side. A view-based
// table (its delegate makes views) shows each visible row as an
// NSTableRowView holding the delegate's cell views, made from the nibs
// Interface Builder archived with the table and reused as rows scroll
// away; a cell-based one draws each row's values with its columns' data
// cells. Clicks select rows (with ⌘ and ⇧ extending the selection), a
// double click sends the double action, the arrow keys move the selection;
// the delegate hears of each change. NSOutlineView shows a tree, its
// expanded items' children under them, indented, with a disclosure
// triangle to open and close each expandable item.

/// NSIndexSet, as tables take and give their selections.
enum IndexSets {
    static func make(_ indexes: [Int]) -> NSObject {
        let set = NSObject(Send.object(Classes.named("NSMutableIndexSet")?.pointer, "indexSet")!)
        typealias Add = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, UInt) -> Void
        for index in indexes { unsafeBitCast(ObjCRuntime.msgSend, to: Add.self)(set.objcObject, ObjCRuntime.selector("addIndex:"), UInt(index)) }
        return set
    }

    static func indexes(_ set: NSObject?) -> [Int] {
        guard let set, Send.integer(set.objcObject, "count") > 0 else { return [] }
        typealias After = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, UInt) -> UInt
        let after = unsafeBitCast(ObjCRuntime.msgSend, to: After.self)
        var result: [Int] = []
        var index = UInt(bitPattern: Send.integer(set.objcObject, "firstIndex"))
        let notFound = UInt(Int.max)
        while index != notFound, result.count < 1_000_000 {
            result.append(Int(index))
            index = after(set.objcObject, ObjCRuntime.selector("indexGreaterThanIndex:"), index)
        }
        return result
    }
}

@ObjCClass("NSTableView")
open class NSTableView: NSControl {
    var columns: [NSTableColumn] = []
    var headerView: NSTableHeaderView?
    var cornerView: NSView?
    var rowHeight: CGFloat = 17
    var intercellSpacing = CGSize(width: 3, height: 2)
    var backgroundColor: NSColor? = NSColor.controlBackgroundColor()
    var gridColor: NSColor = NSColor.gridColor()
    var gridStyleMask: UInt = 0
    var usesAlternatingRowBackgroundColors = false
    var allowsMultipleSelection = false
    var allowsEmptySelection = true
    var allowsColumnSelection = false
    var allowsColumnReordering = true
    var allowsColumnResizing = true
    var allowsTypeSelect = true
    /// NSTableViewColumnAutoresizingStyle: none 0, uniform 1, sequential 2,
    /// reverse sequential 3, last column only 4, first column only 5.
    var columnAutoresizingStyle: UInt = 1
    /// NSTableViewSelectionHighlightStyle: none -1, regular 0, source list 1.
    var selectionHighlightStyle = 0
    var dataSourceObject: UnsafeMutableRawPointer?
    var delegateObject: UnsafeMutableRawPointer?
    var doubleAction: ObjCSelector?
    var clickedRow = -1
    var clickedColumn = -1
    var selection: [Int] = []
    var lastSelected = -1
    var nibs: [String: NSNib] = [:]
    var reusable: [String: [NSView]] = [:]
    var rowViews: [Int: NSTableRowView] = [:]
    var rowCount = 0
    /// Each row's top and height, when the delegate gives heights.
    var rowTops: [CGFloat] = []
    var sortDescriptors: NSObject?
    var autosaveName: String?
    var floatsGroupRows = false
    var usesAutomaticRowHeights = false
    var style = 0
    var rowSizeStyle = -1
    var loaded = false
    var reloading = false

    public required init() { super.init() }

    @ObjCMethod("initWithFrame:")
    public required init(frame: CGRect) {
        super.init(frame: frame)
        let header = NSTableHeaderView(frame: CGRect(x: 0, y: 0, width: frame.width, height: 23))
        header.tableViewObject = objcObject
        headerView = header
    }

    /// NSTableView's archive: its columns, header and corner views, row
    /// height, spacing, colors, "NSTvFlags" (column reordering 0x80000000,
    /// resizing 0x40000000, empty selection 0x10000000, multiple selection
    /// 0x08000000, column selection 0x04000000, alternating rows 0x00800000)
    /// and the cell view nibs by identifier.
    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init(coder: coder)
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        columns = decoded.array("NSTableColumns").compactMap { $0.as(NSTableColumn.self) }
        for column in columns { column.tableViewObject = objcObject }
        headerView = decoded.object("NSHeaderView")?.as(NSTableHeaderView.self)
        headerView?.tableViewObject = objcObject
        cornerView = decoded.object("NSCornerView")?.as(NSView.self)
        if decoded.has("NSRowHeight") { rowHeight = decoded.double("NSRowHeight") }
        if decoded.has("NSIntercellSpacingWidth") {
            intercellSpacing = CGSize(width: decoded.double("NSIntercellSpacingWidth"), height: decoded.double("NSIntercellSpacingHeight"))
        }
        backgroundColor = decoded.object("NSBackgroundColor")?.as(NSColor.self) ?? backgroundColor
        gridColor = decoded.object("NSGridColor")?.as(NSColor.self) ?? gridColor
        gridStyleMask = UInt(decoded.integer("NSGridStyleMask"))
        let flags = UInt32(truncatingIfNeeded: decoded.integer("NSTvFlags"))
        if decoded.has("NSTvFlags") {
            allowsColumnReordering = flags & 0x8000_0000 != 0
            allowsColumnResizing = flags & 0x4000_0000 != 0
            allowsEmptySelection = flags & 0x1000_0000 != 0
            allowsMultipleSelection = flags & 0x0800_0000 != 0
            allowsColumnSelection = flags & 0x0400_0000 != 0
            usesAlternatingRowBackgroundColors = flags & 0x0080_0000 != 0
        }
        if decoded.has("NSColumnAutoresizingStyle") { columnAutoresizingStyle = UInt(decoded.integer("NSColumnAutoresizingStyle")) }
        if decoded.has("NSTableViewSelectionHighlightStyle") { selectionHighlightStyle = decoded.integer("NSTableViewSelectionHighlightStyle") }
        style = decoded.integer("NSTableViewStyle")
        floatsGroupRows = decoded.bool("NSTableViewShouldFloatGroupRows")
        usesAutomaticRowHeights = decoded.bool("NSTableViewUsesAutomaticRowHeights")
        autosaveName = decoded.string("NSAutosaveName")
        for (identifier, nib) in decoded.dictionary("NSTableViewArchivedReusableViewsKey") {
            if let nib = nib.as(NSNib.self) { nibs[identifier] = nib }
        }
        sortDescriptors = decoded.object("NSSortDescriptors")
    }

    static func wrapTable(_ object: UnsafeMutableRawPointer) -> NSTableView { NSTableView.objCInstance(object, ownership: .retain) }

    @ObjCClassMethod("cellClass") static func tableCellClass() -> ObjCClass? { nil }
    @ObjCMethod("isFlipped") override func isFlipped() -> Bool { true }
    @ObjCMethod("acceptsFirstResponder") override func acceptsFirstResponder() -> Bool { true }

    var dataSource: NSObject? { dataSourceObject.map(NSObject.init) }
    var delegate: NSObject? { delegateObject.map(NSObject.init) }
    var visibleColumns: [NSTableColumn] { columns.filter { !$0.hidden } }

    // MARK: What the data source and delegate say, as a table asks them

    var isViewBased: Bool { Send.responds(delegateObject, "tableView:viewForTableColumn:row:") || !nibs.isEmpty && Send.responds(delegateObject, "tableView:viewForTableColumn:row:") }
    func numberOfRowsFromSource() -> Int {
        guard let dataSourceObject, Send.responds(dataSourceObject, "numberOfRowsInTableView:") else { return 0 }
        return max(0, Send.integer(dataSourceObject, "numberOfRowsInTableView:", objcObject))
    }
    func objectValue(column: NSTableColumn?, row: Int) -> NSObject? {
        guard let dataSourceObject, Send.responds(dataSourceObject, "tableView:objectValueForTableColumn:row:") else { return nil }
        return Send.object(dataSourceObject, "tableView:objectValueForTableColumn:row:", objcObject, column?.objcObject, row).map(NSObject.init)
    }
    func viewFromDelegate(column: NSTableColumn?, row: Int) -> NSView? {
        Send.object(delegateObject, "tableView:viewForTableColumn:row:", objcObject, column?.objcObject, row).map(NSView.wrap)
    }
    func rowViewFromDelegate(row: Int) -> NSTableRowView? {
        guard Send.responds(delegateObject, "tableView:rowViewForRow:") else { return nil }
        return Send.object(delegateObject, "tableView:rowViewForRow:", objcObject, nil, row, skipSecond: true).flatMap { NSObject($0).as(NSTableRowView.self) }
    }
    func heightFromDelegate(row: Int) -> CGFloat? {
        guard Send.responds(delegateObject, "tableView:heightOfRow:") else { return nil }
        return Send.doubleRow(delegateObject!, "tableView:heightOfRow:", objcObject, row)
    }
    func isGroup(row: Int) -> Bool {
        guard Send.responds(delegateObject, "tableView:isGroupRow:") else { return false }
        return Send.boolRow(delegateObject!, "tableView:isGroupRow:", objcObject, row)
    }
    func shouldSelect(row: Int) -> Bool {
        guard Send.responds(delegateObject, "tableView:shouldSelectRow:") else { return true }
        return Send.boolRow(delegateObject!, "tableView:shouldSelectRow:", objcObject, row)
    }
    func willDisplay(cell: NSCell, column: NSTableColumn, row: Int) {
        guard Send.responds(delegateObject, "tableView:willDisplayCell:forTableColumn:row:") else { return }
        typealias F = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, UnsafeMutableRawPointer, UnsafeMutableRawPointer, UnsafeMutableRawPointer, Int) -> Void
        unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(delegateObject!, ObjCRuntime.selector("tableView:willDisplayCell:forTableColumn:row:"),
                                                       objcObject, cell.objcObject, column.objcObject, row)
    }
    func didAdd(rowView: NSTableRowView, row: Int) {
        guard Send.responds(delegateObject, "tableView:didAddRowView:forRow:") else { return }
        Send.void(delegateObject, "tableView:didAddRowView:forRow:", objcObject, rowView.objcObject, row)
    }
    var selectionDidChange: (selector: String, notification: String) { ("tableViewSelectionDidChange:", "NSTableViewSelectionDidChangeNotification") }
    var selectionIsChanging: (selector: String, notification: String) { ("tableViewSelectionIsChanging:", "NSTableViewSelectionIsChangingNotification") }
    /// How far a row's cells sit inside its outline column.
    func indentation(row: Int) -> CGFloat { 0 }
    var outlineColumn: NSTableColumn? { nil }

    // MARK: Data source, delegate and actions

    @ObjCMethod("dataSource") func tableDataSource() -> NSObject? { dataSource }
    @ObjCMethod("setDataSource:")
    func setDataSource(_ value: NSObject?) {
        dataSourceObject = value?.objcObject
        scheduleReload()
    }
    @ObjCMethod("delegate") func tableDelegate() -> NSObject? { delegate }
    @ObjCMethod("setDelegate:")
    func setDelegate(_ value: NSObject?) {
        delegateObject = value?.objcObject
        scheduleReload()
    }
    @ObjCMethod("doubleAction") func tableDoubleAction() -> ObjCSelector? { doubleAction }
    @ObjCMethod("setDoubleAction:") func setDoubleAction(_ value: ObjCSelector?) { doubleAction = value }
    @ObjCMethod("clickedRow") func tableClickedRow() -> Int { clickedRow }
    @ObjCMethod("clickedColumn") func tableClickedColumn() -> Int { clickedColumn }

    /// The first reload, once the table has a data source and is in a window,
    /// as AppKit's tables load themselves.
    private func scheduleReload() {
        guard !loaded else { return }
        Dispatch.onMain { [weak self] in
            guard let self, !self.loaded else { return }
            self.reloadData()
        }
    }

    // MARK: Columns

    @ObjCMethod("tableColumns") func tableColumns() -> NSObject { NSMutableArray.of(columns) }
    @ObjCMethod("numberOfColumns") func numberOfColumns() -> Int { columns.count }
    @ObjCMethod("addTableColumn:")
    func addTableColumn(_ column: NSTableColumn?) {
        guard let column else { return }
        column.tableViewObject = objcObject
        columns.append(column)
        tile()
    }
    @ObjCMethod("removeTableColumn:")
    func removeTableColumn(_ column: NSTableColumn?) {
        columns.removeAll { $0 === column }
        tile()
    }
    @ObjCMethod("moveColumn:toColumn:")
    func moveColumn(_ from: Int, toColumn to: Int) {
        guard columns.indices.contains(from), columns.indices.contains(to) else { return }
        columns.insert(columns.remove(at: from), at: to)
        tile()
    }
    @ObjCMethod("tableColumnWithIdentifier:") func tableColumn(withIdentifier identifier: String?) -> NSTableColumn? { columns.first { $0.identifier == identifier } }
    @ObjCMethod("columnWithIdentifier:") func column(withIdentifier identifier: String?) -> Int { columns.firstIndex { $0.identifier == identifier } ?? -1 }
    @ObjCMethod("headerView") func tableHeaderView() -> NSTableHeaderView? { headerView }
    @ObjCMethod("setHeaderView:")
    func setHeaderView(_ view: NSTableHeaderView?) {
        headerView = view
        view?.tableViewObject = objcObject
        let scrollView = enclosingScrollView()?.as(NSScrollView.self)
        if view == nil { scrollView?.headerClip?.removeFromSuperview(); scrollView?.headerClip = nil }
        scrollView?.tile()
    }
    @ObjCMethod("cornerView") func tableCornerView() -> NSView? { cornerView }
    @ObjCMethod("setCornerView:") func setCornerView(_ view: NSView?) { cornerView = view }
    @ObjCMethod("highlightedTableColumn") func highlightedTableColumn() -> NSTableColumn? { nil }
    @ObjCMethod("setHighlightedTableColumn:") func setHighlightedTableColumn(_ column: NSTableColumn?) {}
    @ObjCMethod("indicatorImageInTableColumn:") func indicatorImage(in column: NSTableColumn?) -> NSImage? { nil }
    @ObjCMethod("setIndicatorImage:inTableColumn:") func setIndicatorImage(_ image: NSImage?, in column: NSTableColumn?) {}
    @ObjCMethod("sortDescriptors") func tableSortDescriptors() -> NSObject { sortDescriptors ?? NSMutableArray.empty() }
    @ObjCMethod("setSortDescriptors:")
    func setSortDescriptors(_ value: NSObject?) {
        let old = sortDescriptors ?? NSMutableArray.empty()
        sortDescriptors = value
        if Send.responds(dataSourceObject, "tableView:sortDescriptorsDidChange:") {
            Send.void(dataSourceObject, "tableView:sortDescriptorsDidChange:", objcObject, old.objcObject)
        }
        headerView?.setNeedsDisplay(true)
    }

    /// Each visible column's x and width.
    func columnRects() -> [(column: NSTableColumn, x: CGFloat, width: CGFloat)] {
        var x: CGFloat = 0
        return visibleColumns.map { column in
            defer { x += column.width + intercellSpacing.width }
            return (column, x, column.width + intercellSpacing.width)
        }
    }

    var columnsWidth: CGFloat { visibleColumns.reduce(0) { $0 + $1.width + intercellSpacing.width } }

    @ObjCMethod("sizeLastColumnToFit")
    func sizeLastColumnToFit() {
        guard let last = visibleColumns.last else { return }
        let available = (superview?.as(NSClipView.self)?.bounds.width ?? frame.width)
        let others = columnsWidth - last.width - intercellSpacing.width
        let width = max(last.minWidth, min(last.maxWidth, available - others - intercellSpacing.width))
        if width != last.width { last.width = width }
        tile()
    }

    @ObjCMethod("sizeToFit") func sizeToFitColumns() { sizeLastColumnToFit() }

    /// The clip view changed size: the columns fill its width as the
    /// column autoresizing style asks, and the table at least its height.
    func clipResized() {
        if columnAutoresizingStyle != 0 { fitColumns() }
        tile()
    }

    private func fitColumns() {
        guard let clip = superview?.as(NSClipView.self) else { return }
        let available = clip.bounds.width
        let visible = visibleColumns
        guard !visible.isEmpty else { return }
        var extra = available - columnsWidth
        guard abs(extra) > 0.5 else { return }
        // Uniform: shared among resizable columns; otherwise the last one.
        let resizable = visible.filter { $0.resizingMask & 1 != 0 }
        let targets = columnAutoresizingStyle == 1 && !resizable.isEmpty ? resizable
            : columnAutoresizingStyle == 5 ? [visible[0]] : [resizable.last ?? visible[visible.count - 1]]
        for (index, column) in targets.enumerated() {
            let share = extra / CGFloat(targets.count - index)
            let width = max(column.minWidth, min(column.maxWidth, column.width + share))
            extra -= width - column.width
            column.width = width
        }
    }

    // MARK: Rows

    @ObjCMethod("numberOfRows") func numberOfRows() -> Int { rowCount }
    @ObjCMethod("rowHeight") func tableRowHeight() -> CGFloat { rowHeight }
    @ObjCMethod("setRowHeight:") func setRowHeight(_ value: CGFloat) { rowHeight = value; tile() }
    @ObjCMethod("intercellSpacing") func tableIntercellSpacing() -> CGSize { intercellSpacing }
    @ObjCMethod("setIntercellSpacing:") func setIntercellSpacing(_ value: CGSize) { intercellSpacing = value; tile() }
    @ObjCMethod("rowSizeStyle") func tableRowSizeStyle() -> Int { rowSizeStyle }
    @ObjCMethod("setRowSizeStyle:") func setRowSizeStyle(_ value: Int) { rowSizeStyle = value }
    @ObjCMethod("effectiveRowSizeStyle") func effectiveRowSizeStyle() -> Int { rowSizeStyle == -1 ? 2 : rowSizeStyle }
    @ObjCMethod("style") func tableStyle() -> Int { style }
    @ObjCMethod("setStyle:") func setStyle(_ value: Int) { style = value }
    @ObjCMethod("effectiveStyle") func effectiveStyle() -> Int { style == 0 ? 1 : style }
    @ObjCMethod("usesAutomaticRowHeights") func tableUsesAutomaticRowHeights() -> Bool { usesAutomaticRowHeights }
    @ObjCMethod("setUsesAutomaticRowHeights:") func setUsesAutomaticRowHeights(_ value: Bool) { usesAutomaticRowHeights = value }
    @ObjCMethod("floatsGroupRows") func tableFloatsGroupRows() -> Bool { floatsGroupRows }
    @ObjCMethod("setFloatsGroupRows:") func setFloatsGroupRows(_ value: Bool) { floatsGroupRows = value }

    /// A row's height: the delegate's, or the row height and spacing.
    var standardRowHeight: CGFloat { max(1, effectiveRowHeight + intercellSpacing.height) }

    /// A source list (NSTableViewStyleSourceList, or the source-list
    /// highlight) draws as a sidebar.
    var isSourceList: Bool { style == 3 || selectionHighlightStyle == 1 }

    /// A sidebar's rows are as tall as its row size style says (small,
    /// medium, large), unless it is custom; other tables' are rowHeight.
    var effectiveRowHeight: CGFloat {
        guard isSourceList, rowSizeStyle != 0 else { return rowHeight }
        switch effectiveRowSizeStyle() {
        case 1: return 20
        case 3: return 32
        default: return 24
        }
    }

    func rowTop(_ row: Int) -> CGFloat { rowTops.isEmpty ? CGFloat(row) * standardRowHeight : rowTops.indices.contains(row) ? rowTops[row] : 0 }
    func height(ofRow row: Int) -> CGFloat {
        guard !rowTops.isEmpty else { return standardRowHeight }
        let next = row + 1 < rowTops.count ? rowTops[row + 1] : rowsHeight
        return next - rowTop(row)
    }
    var rowsHeight: CGFloat = 0

    @ObjCMethod("rectOfRow:")
    func rect(ofRow row: Int) -> CGRect {
        guard row >= 0, row < rowCount else { return .zero }
        return CGRect(x: 0, y: rowTop(row), width: max(frame.width, columnsWidth), height: height(ofRow: row))
    }

    @ObjCMethod("rectOfColumn:")
    func rect(ofColumn column: Int) -> CGRect {
        let rects = columnRects()
        guard rects.indices.contains(column) else { return .zero }
        return CGRect(x: rects[column].x, y: 0, width: rects[column].width, height: max(frame.height, rowsHeight))
    }

    @ObjCMethod("rowAtPoint:")
    func row(at point: CGPoint) -> Int {
        guard point.y >= 0, point.y < rowsHeight else { return -1 }
        if rowTops.isEmpty { return min(rowCount - 1, Int(point.y / standardRowHeight)) }
        var low = 0, high = rowCount - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if rowTops[middle] <= point.y { low = middle } else { high = middle - 1 }
        }
        return low
    }

    @ObjCMethod("columnAtPoint:")
    func column(at point: CGPoint) -> Int { columnRects().firstIndex { point.x >= $0.x && point.x < $0.x + $0.width } ?? -1 }

    @ObjCMethod("rowsInRect:")
    func rows(in rect: CGRect) -> NSRange {
        let first = max(0, row(at: CGPoint(x: 0, y: max(0, rect.minY))))
        var last = row(at: CGPoint(x: 0, y: rect.maxY - 0.5))
        if last < 0 { last = rowCount - 1 }
        return first <= last && rowCount > 0 ? NSRange(location: UInt(first), length: UInt(last - first + 1)) : NSRange(location: 0, length: 0)
    }

    @ObjCMethod("frameOfCellAtColumn:row:")
    func frameOfCell(atColumn column: Int, row: Int) -> CGRect {
        let rects = columnRects()
        guard rects.indices.contains(column) else { return .zero }
        let rowRect = rect(ofRow: row)
        var x = rects[column].x + intercellSpacing.width / 2, width = rects[column].column.width
        if rects[column].column === (outlineColumn ?? nil) {
            let indent = indentation(row: row)
            x += indent
            width -= indent
        }
        return CGRect(x: x, y: rowRect.minY + intercellSpacing.height / 2, width: max(0, width), height: max(0, rowRect.height - intercellSpacing.height))
    }

    // MARK: Loading

    @ObjCMethod("reloadData")
    func reloadData() {
        loaded = true
        reloading = true
        defer { reloading = false }
        prepareRows()
        rowCount = numberOfRowsFromSource()
        Trace.log("table: \(rowCount) rows, \(isViewBased ? "view" : "cell") based, \(columns.count) columns, \(frame)")
        measureRows()
        for (_, rowView) in rowViews { recycle(rowView) }
        rowViews = [:]
        selection = selection.filter { $0 < rowCount }
        tile()
        setNeedsDisplay(true)
    }

    /// Before rows are counted: an outline gathers its items.
    func prepareRows() {}

    private func measureRows() {
        if Send.responds(delegateObject, "tableView:heightOfRow:") || hasDelegateHeights {
            var tops: [CGFloat] = []
            var y: CGFloat = 0
            for row in 0..<rowCount {
                tops.append(y)
                y += max(1, (heightFromDelegate(row: row) ?? effectiveRowHeight) + intercellSpacing.height)
            }
            rowTops = tops
            rowsHeight = y
        } else {
            rowTops = []
            rowsHeight = CGFloat(rowCount) * standardRowHeight
        }
    }

    var hasDelegateHeights: Bool { false }

    @ObjCMethod("noteNumberOfRowsChanged") func noteNumberOfRowsChanged() { reloadData() }
    @ObjCMethod("noteHeightOfRowsWithIndexesChanged:") func noteHeightOfRowsWithIndexesChanged(_ indexes: NSObject?) { measureRows(); tile() }
    @ObjCMethod("reloadDataForRowIndexes:columnIndexes:")
    func reloadData(forRowIndexes rows: NSObject?, columnIndexes columns: NSObject?) {
        for row in IndexSets.indexes(rows) { if let rowView = rowViews.removeValue(forKey: row) { recycle(rowView) } }
        tile()
        setNeedsDisplay(true)
    }
    @ObjCMethod("beginUpdates") func beginUpdates() {}
    @ObjCMethod("endUpdates") func endUpdates() { reloadData() }
    @ObjCMethod("insertRowsAtIndexes:withAnimation:") func insertRows(at indexes: NSObject?, withAnimation options: UInt) { reloadData() }
    @ObjCMethod("removeRowsAtIndexes:withAnimation:") func removeRows(at indexes: NSObject?, withAnimation options: UInt) { reloadData() }
    @ObjCMethod("moveRowAtIndex:toIndex:") func moveRow(at from: Int, to: Int) { reloadData() }
    @ObjCMethod("hideRowsAtIndexes:withAnimation:") func hideRows(at indexes: NSObject?, withAnimation options: UInt) {}
    @ObjCMethod("unhideRowsAtIndexes:withAnimation:") func unhideRows(at indexes: NSObject?, withAnimation options: UInt) {}
    @ObjCMethod("hiddenRowIndexes") func hiddenRowIndexes() -> NSObject { IndexSets.make([]) }

    // MARK: Layout and row views

    /// The table's size: its columns' width (at least the clip view's) and
    /// its rows' height (at least the clip view's); the visible rows' views.
    @ObjCMethod("tile")
    func tile() {
        let clip = superview?.as(NSClipView.self)
        let width = max(columnsWidth, clip?.bounds.width ?? 0)
        let height = max(rowsHeight, clip?.bounds.height ?? 0)
        if frame.size != CGSize(width: width, height: height) { Send.void(objcObject, "setFrameSize:", size: CGSize(width: width, height: height)) }
        if let headerView {
            headerView.setFrameSize(CGSize(width: width, height: headerView.frame.height > 0 ? headerView.frame.height : 23))
            headerView.setNeedsDisplay(true)
        }
        updateRowViews()
        setNeedsDisplay(true)
    }

    @ObjCMethod("setFrameSize:")
    override func setFrameSize(_ size: CGSize) {
        super.setFrameSize(size)
        for (row, rowView) in rowViews { placeRowView(rowView, row: row) }
    }

    /// The rows the clip view shows have views; the others' are reused.
    func updateRowViews() {
        guard isViewBased, rowCount > 0 else {
            for (_, rowView) in rowViews { recycle(rowView) }
            rowViews = [:]
            return
        }
        let shown = visibleRect()
        var range = rows(in: CGRect(x: 0, y: shown.minY - 100, width: frame.width, height: shown.height + 200))
        if shown.height <= 0 { range = NSRange(location: 0, length: UInt(min(rowCount, 50))) }
        let visible = Set(Int(range.location)..<Int(range.location + range.length))
        for (row, rowView) in rowViews where !visible.contains(row) {
            recycle(rowView)
            rowViews[row] = nil
        }
        for row in visible.sorted() where rowViews[row] == nil {
            _ = makeRowView(row)
        }
    }

    /// A sidebar's group row's text fields draw as headings.
    private func markHeadings(in view: NSView) {
        if let cell = view.as(NSTextField.self)?.cellObject?.as(NSTextFieldCell.self) { cell.sourceListHeading = true }
        for subview in view.subviews { markHeadings(in: subview) }
    }

    @discardableResult
    func makeRowView(_ row: Int) -> NSTableRowView? {
        let rowView = rowViewFromDelegate(row: row) ?? NSTableRowView(frame: .zero)
        rowView.tableViewObject = objcObject
        rowView.row = row
        rowView.groupRowStyle = isGroup(row: row)
        rowView.selected = selection.contains(row)
        placeRowView(rowView, row: row)
        let rects = columnRects()
        for (index, entry) in rects.enumerated() {
            guard let cell = viewFromDelegate(column: rowView.groupRowStyle ? nil : entry.column, row: row) else { continue }
            if cell.superview !== rowView { rowView.addSubview(cell) }
            var frame = frameOfCell(atColumn: index, row: row)
            frame.origin.y = (rowView.frame.height - frame.height) / 2
            if rowView.groupRowStyle { frame = CGRect(x: 0, y: 0, width: rowView.frame.width, height: rowView.frame.height) }
            Send.void(cell.objcObject, "setFrame:", rect: frame)
            // Cell views show their object value; a table's own data source can give it.
            if let cellView = cell.as(NSTableCellView.self), Send.responds(dataSourceObject, objectValueSelector) {
                cellView.setObjectValue(objectValue(column: entry.column, row: row))
            } else if let cellView = cell.as(NSTableCellView.self), cellView.objectValue == nil, let item = item(forRow: row) {
                cellView.setObjectValue(item)
            }
            rowView.cellViews.append(cell)
            if rowView.groupRowStyle {
                if isSourceList { markHeadings(in: cell) }
                break
            }
        }
        rowView.updateBackgroundStyle()
        rowViews[row] = rowView
        if rowView.superview !== self { addSubview(rowView) }
        didAdd(rowView: rowView, row: row)
        return rowView
    }

    var objectValueSelector: String { "tableView:objectValueForTableColumn:row:" }
    func item(forRow row: Int) -> NSObject? { nil }

    func placeRowView(_ rowView: NSTableRowView, row: Int) {
        let rect = self.rect(ofRow: row)
        Send.void(rowView.objcObject, "setFrame:", rect: CGRect(x: 0, y: rect.minY, width: frame.width, height: rect.height))
    }

    /// A row view's cell views go back to be made again for other rows.
    func recycle(_ rowView: NSTableRowView) {
        if Send.responds(delegateObject, "tableView:didRemoveRowView:forRow:") {
            Send.void(delegateObject, "tableView:didRemoveRowView:forRow:", objcObject, rowView.objcObject, rowView.row)
        }
        for cell in rowView.cellViews {
            cell.removeFromSuperview()
            if let identifier = cell.identifier { reusable[identifier, default: []].append(cell) }
        }
        rowView.cellViews = []
        rowView.removeFromSuperview()
    }

    func visibleRectChanged() { if loaded { updateRowViews() } }

    @ObjCMethod("rowViewAtRow:makeIfNecessary:")
    func rowView(atRow row: Int, makeIfNecessary: Bool) -> NSTableRowView? {
        if let rowView = rowViews[row] { return rowView }
        guard makeIfNecessary, row >= 0, row < rowCount, isViewBased else { return nil }
        return makeRowView(row)
    }

    @ObjCMethod("viewAtColumn:row:makeIfNecessary:")
    func view(atColumn column: Int, row: Int, makeIfNecessary: Bool) -> NSView? {
        guard let rowView = rowView(atRow: row, makeIfNecessary: makeIfNecessary) else { return nil }
        return rowView.view(atColumn: column)
    }

    @ObjCMethod("rowForView:")
    func row(for view: NSView?) -> Int {
        var current = view
        while let candidate = current {
            if let rowView = candidate.as(NSTableRowView.self), rowView.tableViewObject == objcObject { return rowView.row }
            current = candidate.superview
        }
        return -1
    }

    @ObjCMethod("columnForView:")
    func column(for view: NSView?) -> Int {
        var current = view
        while let candidate = current, let parent = candidate.superview {
            if let rowView = parent.as(NSTableRowView.self) { return rowView.cellViews.firstIndex { $0 === candidate } ?? -1 }
            current = parent
        }
        return -1
    }

    @ObjCMethod("enumerateAvailableRowViewsUsingBlock:")
    func enumerateAvailableRowViews(_ block: ObjCBlock?) {
        guard let block else { return }
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer, Int) -> Void
        for (row, rowView) in rowViews.sorted(by: { $0.key < $1.key }) { block.function(as: Invoke.self)(block.object, rowView.objcObject, row) }
    }

    /// A cell view for `identifier`: one that scrolled away, or one made
    /// from the nib registered or archived for it.
    @ObjCMethod("makeViewWithIdentifier:owner:")
    func makeView(withIdentifier identifier: String?, owner: NSObject?) -> NSView? {
        guard let identifier else { return nil }
        if var pool = reusable[identifier], let view = pool.popLast() {
            reusable[identifier] = pool
            Send.void(view.objcObject, "prepareForReuse")
            return view
        }
        guard let nib = nibs[identifier] else { return nil }
        let objects = nib.instantiate(owner: owner)
        guard let view = objects.lazy.compactMap({ $0.as(NSView.self) }).first else { return nil }
        view.identifier = identifier
        return view
    }

    @ObjCMethod("registerNib:forIdentifier:")
    func register(_ nib: NSNib?, forIdentifier identifier: String?) {
        guard let identifier else { return }
        nibs[identifier] = nib
    }
    @ObjCMethod("registeredNibsByIdentifier")
    func registeredNibsByIdentifier() -> NSObject {
        let dictionary = NSMutableDictionary.empty()
        for (identifier, nib) in nibs { dictionary.set(nib, forKey: identifier) }
        return dictionary
    }

    // MARK: Selection

    @ObjCMethod("selectedRowIndexes") func selectedRowIndexes() -> NSObject { IndexSets.make(selection.sorted()) }
    @ObjCMethod("selectedRow") func selectedRow() -> Int { selection.last ?? -1 }
    @ObjCMethod("numberOfSelectedRows") func numberOfSelectedRows() -> Int { selection.count }
    @ObjCMethod("isRowSelected:") func isRowSelected(_ row: Int) -> Bool { selection.contains(row) }
    @ObjCMethod("selectedColumn") func selectedColumn() -> Int { -1 }
    @ObjCMethod("selectedColumnIndexes") func selectedColumnIndexes() -> NSObject { IndexSets.make([]) }
    @ObjCMethod("numberOfSelectedColumns") func numberOfSelectedColumns() -> Int { 0 }
    @ObjCMethod("isColumnSelected:") func isColumnSelected(_ column: Int) -> Bool { false }
    @ObjCMethod("selectColumnIndexes:byExtendingSelection:") func selectColumnIndexes(_ indexes: NSObject?, byExtendingSelection extend: Bool) {}
    @ObjCMethod("allowsMultipleSelection") func tableAllowsMultipleSelection() -> Bool { allowsMultipleSelection }
    @ObjCMethod("setAllowsMultipleSelection:") func setAllowsMultipleSelection(_ value: Bool) { allowsMultipleSelection = value }
    @ObjCMethod("allowsEmptySelection") func tableAllowsEmptySelection() -> Bool { allowsEmptySelection }
    @ObjCMethod("setAllowsEmptySelection:") func setAllowsEmptySelection(_ value: Bool) { allowsEmptySelection = value }
    @ObjCMethod("allowsColumnSelection") func tableAllowsColumnSelection() -> Bool { allowsColumnSelection }
    @ObjCMethod("setAllowsColumnSelection:") func setAllowsColumnSelection(_ value: Bool) { allowsColumnSelection = value }
    @ObjCMethod("allowsColumnReordering") func tableAllowsColumnReordering() -> Bool { allowsColumnReordering }
    @ObjCMethod("setAllowsColumnReordering:") func setAllowsColumnReordering(_ value: Bool) { allowsColumnReordering = value }
    @ObjCMethod("allowsColumnResizing") func tableAllowsColumnResizing() -> Bool { allowsColumnResizing }
    @ObjCMethod("setAllowsColumnResizing:") func setAllowsColumnResizing(_ value: Bool) { allowsColumnResizing = value }
    @ObjCMethod("allowsTypeSelect") func tableAllowsTypeSelect() -> Bool { allowsTypeSelect }
    @ObjCMethod("setAllowsTypeSelect:") func setAllowsTypeSelect(_ value: Bool) { allowsTypeSelect = value }
    @ObjCMethod("columnAutoresizingStyle") func tableColumnAutoresizingStyle() -> UInt { columnAutoresizingStyle }
    @ObjCMethod("setColumnAutoresizingStyle:") func setColumnAutoresizingStyle(_ value: UInt) { columnAutoresizingStyle = value; clipResized() }
    @ObjCMethod("selectionHighlightStyle") func tableSelectionHighlightStyle() -> Int { selectionHighlightStyle }
    @ObjCMethod("setSelectionHighlightStyle:") func setSelectionHighlightStyle(_ value: Int) { selectionHighlightStyle = value; refreshSelection() }

    @ObjCMethod("selectRowIndexes:byExtendingSelection:")
    func selectRowIndexes(_ indexes: NSObject?, byExtendingSelection extend: Bool) {
        let rows = IndexSets.indexes(indexes).filter { $0 >= 0 && $0 < rowCount }
        var new = extend ? selection : []
        for row in rows where !new.contains(row) { new.append(row) }
        if !allowsMultipleSelection, let last = new.last { new = [last] }
        setSelection(new, notify: false)
    }

    @ObjCMethod("selectRow:byExtendingSelection:")
    func selectRow(_ row: Int, byExtendingSelection extend: Bool) { selectRowIndexes(IndexSets.make([row]), byExtendingSelection: extend) }

    @ObjCMethod("deselectRow:") func deselectRow(_ row: Int) { setSelection(selection.filter { $0 != row }, notify: false) }
    @ObjCMethod("deselectAll:") func deselectAll(_ sender: NSObject?) { setSelection([], notify: false) }
    @ObjCMethod("selectAll:") func selectAll(_ sender: NSObject?) { if allowsMultipleSelection { setSelection(Array(0..<rowCount), notify: true) } }

    /// The selection changes, the rows show it, and the delegate hears.
    func setSelection(_ rows: [Int], notify: Bool) {
        guard rows != selection else { return }
        selection = rows
        lastSelected = rows.last ?? -1
        refreshSelection()
        let names = selectionDidChange
        let notification = NSNotification.make(name: names.notification, object: self)
        if Send.responds(delegateObject, names.selector) { Send.void(delegateObject, names.selector, notification.objcObject) }
        NSNotificationCenter.defaultCenter().post(notification)
    }

    func refreshSelection() {
        for (row, rowView) in rowViews {
            rowView.selected = selection.contains(row)
            rowView.updateBackgroundStyle()
            rowView.setNeedsDisplay(true)
        }
        setNeedsDisplay(true)
    }

    @ObjCMethod("scrollRowToVisible:")
    func scrollRowToVisible(_ row: Int) {
        guard row >= 0, row < rowCount else { return }
        _ = scrollRectToVisible(rect(ofRow: row))
    }
    @ObjCMethod("scrollColumnToVisible:") func scrollColumnToVisible(_ column: Int) {}

    // MARK: Clicks and keys

    @ObjCMethod("mouseDown:")
    override func mouseDown(_ eventObject: NSObject?) {
        guard let event = eventObject?.as(NSEvent.self) else { return }
        _ = window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        clickedRow = row
        clickedColumn = column(at: point)
        if handleDisclosureClick(at: point, row: row) { return }
        if row >= 0 {
            guard shouldSelect(row: row) else { return }
            let flags = event.modifierFlags
            if flags & ModifierFlags.command != 0, allowsMultipleSelection {
                setSelection(selection.contains(row) ? selection.filter { $0 != row } : selection + [row], notify: true)
            } else if flags & ModifierFlags.shift != 0, allowsMultipleSelection, lastSelected >= 0 {
                let range = min(lastSelected, row)...max(lastSelected, row)
                let anchor = lastSelected
                setSelection(Array(range), notify: true)
                lastSelected = anchor
            } else {
                setSelection([row], notify: true)
            }
        } else if allowsEmptySelection {
            setSelection([], notify: true)
        }
        if event.clickCount >= 2, let doubleAction {
            _ = sendAction(doubleAction, to: target.map(NSObject.init))
        } else if let action {
            _ = sendAction(action, to: target.map(NSObject.init))
        }
    }

    /// An outline's disclosure triangle.
    func handleDisclosureClick(at point: CGPoint, row: Int) -> Bool { false }

    @ObjCMethod("keyDown:")
    override func keyDown(_ eventObject: NSObject?) {
        guard let event = eventObject?.as(NSEvent.self) else { return }
        let current = selection.last ?? -1
        switch event.keyCode {
        case 125: // down
            let next = min(rowCount - 1, current + 1)
            if next >= 0, shouldSelect(row: next) { setSelection([next], notify: true); scrollRowToVisible(next) }
        case 126: // up
            let next = max(0, current - 1)
            if rowCount > 0, shouldSelect(row: next) { setSelection([next], notify: true); scrollRowToVisible(next) }
        case 36, 76: // return
            if let doubleAction, current >= 0 {
                clickedRow = current
                _ = sendAction(doubleAction, to: target.map(NSObject.init))
            }
        default:
            if !handleKey(event) { super.keyDown(eventObject) }
        }
    }

    func handleKey(_ event: NSEvent) -> Bool { false }

    // MARK: Drawing

    @ObjCMethod("backgroundColor") func tableBackgroundColor() -> NSColor? { backgroundColor }
    @ObjCMethod("setBackgroundColor:") func setBackgroundColor(_ color: NSColor?) { backgroundColor = color; setNeedsDisplay(true) }
    @ObjCMethod("gridColor") func tableGridColor() -> NSColor { gridColor }
    @ObjCMethod("setGridColor:") func setGridColor(_ color: NSColor?) { gridColor = color ?? NSColor.gridColor(); setNeedsDisplay(true) }
    @ObjCMethod("gridStyleMask") func tableGridStyleMask() -> UInt { gridStyleMask }
    @ObjCMethod("setGridStyleMask:") func setGridStyleMask(_ value: UInt) { gridStyleMask = value; setNeedsDisplay(true) }
    @ObjCMethod("usesAlternatingRowBackgroundColors") func tableUsesAlternatingRowBackgroundColors() -> Bool { usesAlternatingRowBackgroundColors }
    @ObjCMethod("setUsesAlternatingRowBackgroundColors:") func setUsesAlternatingRowBackgroundColors(_ value: Bool) { usesAlternatingRowBackgroundColors = value; setNeedsDisplay(true) }
    @ObjCMethod("autosaveName") func tableAutosaveName() -> String? { autosaveName }
    @ObjCMethod("setAutosaveName:") func setAutosaveName(_ name: String?) { autosaveName = name }
    @ObjCMethod("setAutosaveTableColumns:") func setAutosaveTableColumns(_ value: Bool) {}
    @ObjCMethod("autosaveTableColumns") func autosaveTableColumns() -> Bool { false }
    @ObjCMethod("setVerticalMotionCanBeginDrag:") func setVerticalMotionCanBeginDrag(_ value: Bool) {}
    @ObjCMethod("setDraggingSourceOperationMask:forLocal:") func setDraggingSourceOperationMask(_ mask: UInt, forLocal local: Bool) {}
    @ObjCMethod("setDraggingDestinationFeedbackStyle:") func setDraggingDestinationFeedbackStyle(_ style: Int) {}
    @ObjCMethod("setDropRow:dropOperation:") func setDropRow(_ row: Int, dropOperation: UInt) {}
    @ObjCMethod("editColumn:row:withEvent:select:") func editColumn(_ column: Int, row: Int, with event: NSObject?, select: Bool) {}
    @ObjCMethod("editedRow") func editedRow() -> Int { -1 }
    @ObjCMethod("editedColumn") func editedColumn() -> Int { -1 }
    @ObjCMethod("textDidEndEditing:") func textDidEndEditing(_ notification: NSObject?) {}
    @ObjCMethod("userInterfaceLayoutDirection") override func userInterfaceLayoutDirection() -> Int { 0 }

    @ObjCMethod("drawRect:")
    override func draw(_ rect: CGRect) {
        guard let context = NSGraphicsContext.currentCG else { return }
        Send.void(objcObject, "drawBackgroundInClipRect:", rect: rect)
        // Cell-based rows: selection, then each column's cell.
        if !isViewBased, rowCount > 0 {
            let range = rows(in: rect)
            let rects = columnRects()
            for row in Int(range.location)..<Int(range.location + range.length) {
                if selection.contains(row), selectionHighlightStyle != -1 {
                    CG.saveGState(context)
                    CG.setFillColorWithColor(context, (window?.isKeyWindow() == false ? NSColor.unemphasizedSelectedContentBackgroundColor()
                        : NSColor.selectedContentBackgroundColor()).cgColorRef)
                    CG.fillRect(context, self.rect(ofRow: row))
                    CG.restoreGState(context)
                }
                for (index, entry) in rects.enumerated() {
                    guard let cell = entry.column.dataCell(forRow: row) else { continue }
                    let value = objectValue(column: entry.column, row: row)
                    cell.objectValue = value
                    cell.backgroundStyle = selection.contains(row) && window?.isKeyWindow() != false ? 1 : 0
                    willDisplay(cell: cell, column: entry.column, row: row)
                    drawDisclosure(row: row, column: entry.column, context: context)
                    typealias F = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, CGRect, UnsafeMutableRawPointer?) -> Void
                    unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(cell.objcObject, ObjCRuntime.selector("drawWithFrame:inView:"),
                                                                   frameOfCell(atColumn: index, row: row), objcObject)
                }
            }
        }
        Send.void(objcObject, "drawGridInClipRect:", rect: rect)
    }

    /// An outline's triangle, for cell-based rows.
    func drawDisclosure(row: Int, column: NSTableColumn, context: CGRef) {}

    @ObjCMethod("drawBackgroundInClipRect:")
    func drawBackground(inClipRect rect: CGRect) {
        guard let context = NSGraphicsContext.currentCG else { return }
        CG.saveGState(context)
        defer { CG.restoreGState(context) }
        if let backgroundColor {
            CG.setFill(context, backgroundColor)
            CG.fillRect(context, rect)
        }
        guard usesAlternatingRowBackgroundColors else { return }
        let alternate = NSColor(red: 0.96, green: 0.96, blue: 0.96, alpha: 1)
        CG.setFill(context, alternate)
        // Past the last row, rows of the standard height go on alternating.
        var row = 0
        var y: CGFloat = 0
        while y < max(frame.height, rect.maxY) {
            let height = row < rowCount ? self.height(ofRow: row) : standardRowHeight
            if row % 2 == 1, y + height > rect.minY { CG.fillRect(context, CGRect(x: rect.minX, y: y, width: rect.width, height: height)) }
            y += height
            row += 1
            if row > 100_000 { break }
        }
    }

    @ObjCMethod("drawGridInClipRect:")
    func drawGrid(inClipRect rect: CGRect) {
        guard gridStyleMask != 0, let context = NSGraphicsContext.currentCG else { return }
        CG.saveGState(context)
        CG.setFill(context, gridColor)
        if gridStyleMask & 1 != 0 {
            for entry in columnRects() { CG.fillRect(context, CGRect(x: entry.x + entry.width - 1, y: rect.minY, width: 1, height: rect.height)) }
        }
        if gridStyleMask & 2 != 0 {
            for row in 0..<rowCount { CG.fillRect(context, CGRect(x: rect.minX, y: rowTop(row) + height(ofRow: row) - 1, width: rect.width, height: 1)) }
        }
        CG.restoreGState(context)
    }

    @ObjCMethod("highlightSelectionInClipRect:") func highlightSelection(inClipRect rect: CGRect) {}
    @ObjCMethod("drawRow:clipRect:") func drawRow(_ row: Int, clipRect: CGRect) {}

    @ObjCMethod("viewDidMoveToWindow")
    override func viewDidMoveToWindow() {
        if window != nil, !loaded { scheduleReload() }
    }

    @ObjCMethod("layout")
    override func layout() {
        super.layout()
        if loaded { updateRowViews() }
    }

    @ObjCMethod("awakeFromNib")
    func tableAwakeFromNib() {
        if dataSourceObject != nil || delegateObject != nil { scheduleReload() }
    }
}

/// NSOutlineView: the items of a tree, its expanded items' children under
/// them, indented a level each.
@ObjCClass("NSOutlineView")
open class NSOutlineView: NSTableView {
    var indentationPerLevel: CGFloat = 16
    var outlineTableColumn: NSTableColumn?
    var indentationMarkerFollowsCell = true
    var autoresizesOutlineColumn = true
    var autosaveExpandedItems = false
    var stronglyReferencesItems = true
    /// The rows: each item, its level and parent.
    var items: [(item: NSObject, level: Int, parent: NSObject?)] = []
    var expanded: Set<UnsafeMutableRawPointer> = []
    /// What the expanded items are, kept while they are expanded.
    var expandedItems: [UnsafeMutableRawPointer: NSObject] = [:]

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init(coder: coder)
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        if decoded.has("NSOutlineViewIndentationPerLevelKey") { indentationPerLevel = decoded.double("NSOutlineViewIndentationPerLevelKey") }
        outlineTableColumn = decoded.object("NSOutlineViewOutlineTableColumnKey")?.as(NSTableColumn.self)
        autosaveExpandedItems = decoded.bool("NSOutlineViewAutosaveExpandedItemsKey")
    }

    public required init() { super.init() }

    @ObjCMethod("initWithFrame:")
    public required init(frame: CGRect) { super.init(frame: frame) }

    override var outlineColumn: NSTableColumn? { outlineTableColumn ?? visibleColumns.first }

    // MARK: The data source's tree

    private func numberOfChildren(of item: NSObject?) -> Int {
        guard let dataSourceObject, Send.responds(dataSourceObject, "outlineView:numberOfChildrenOfItem:") else { return 0 }
        return max(0, Send.integer(dataSourceObject, "outlineView:numberOfChildrenOfItem:", objcObject, item?.objcObject))
    }

    private func child(_ index: Int, of item: NSObject?) -> NSObject? {
        guard let dataSourceObject else { return nil }
        typealias F = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, UnsafeMutableRawPointer, Int, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
        return unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(dataSourceObject, ObjCRuntime.selector("outlineView:child:ofItem:"), objcObject, index,
                                                              item?.objcObject).map(NSObject.init)
    }

    private func expandable(_ item: NSObject?) -> Bool {
        guard let dataSourceObject, let item, Send.responds(dataSourceObject, "outlineView:isItemExpandable:") else { return false }
        return Send.bool(dataSourceObject, "outlineView:isItemExpandable:", objcObject, item.objcObject)
    }

    override func prepareRows() {
        var rows: [(item: NSObject, level: Int, parent: NSObject?)] = []
        var still: [UnsafeMutableRawPointer: NSObject] = [:]
        func add(_ parent: NSObject?, level: Int) {
            for index in 0..<numberOfChildren(of: parent) {
                guard let item = child(index, of: parent), rows.count < 200_000 else { continue }
                rows.append((item, level, parent))
                if expanded.contains(item.objcObject), expandable(item) {
                    still[item.objcObject] = item
                    add(item, level: level + 1)
                }
            }
        }
        add(nil, level: 0)
        items = rows
        expanded = Set(still.keys)
        expandedItems = still
    }

    override func numberOfRowsFromSource() -> Int { items.count }

    override var isViewBased: Bool { Send.responds(delegateObject, "outlineView:viewForTableColumn:item:") }
    override var objectValueSelector: String { "outlineView:objectValueForTableColumn:byItem:" }
    override var hasDelegateHeights: Bool { Send.responds(delegateObject, "outlineView:heightOfRowByItem:") }
    override var selectionDidChange: (selector: String, notification: String) { ("outlineViewSelectionDidChange:", "NSOutlineViewSelectionDidChangeNotification") }
    override var selectionIsChanging: (selector: String, notification: String) { ("outlineViewSelectionIsChanging:", "NSOutlineViewSelectionIsChangingNotification") }
    override func item(forRow row: Int) -> NSObject? { items.indices.contains(row) ? items[row].item : nil }

    override func objectValue(column: NSTableColumn?, row: Int) -> NSObject? {
        guard let dataSourceObject, items.indices.contains(row), Send.responds(dataSourceObject, "outlineView:objectValueForTableColumn:byItem:") else { return nil }
        return Send.object(dataSourceObject, "outlineView:objectValueForTableColumn:byItem:", objcObject, column?.objcObject, items[row].item.objcObject).map(NSObject.init)
    }

    override func viewFromDelegate(column: NSTableColumn?, row: Int) -> NSView? {
        guard items.indices.contains(row) else { return nil }
        return Send.object(delegateObject, "outlineView:viewForTableColumn:item:", objcObject, column?.objcObject, items[row].item.objcObject).map(NSView.wrap)
    }

    override func rowViewFromDelegate(row: Int) -> NSTableRowView? {
        guard items.indices.contains(row), Send.responds(delegateObject, "outlineView:rowViewForItem:") else { return nil }
        return Send.object(delegateObject, "outlineView:rowViewForItem:", objcObject, items[row].item.objcObject).flatMap { NSObject($0).as(NSTableRowView.self) }
    }

    override func heightFromDelegate(row: Int) -> CGFloat? {
        guard items.indices.contains(row), Send.responds(delegateObject, "outlineView:heightOfRowByItem:") else { return nil }
        typealias F = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, UnsafeMutableRawPointer, UnsafeMutableRawPointer) -> CGFloat
        return unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(delegateObject!, ObjCRuntime.selector("outlineView:heightOfRowByItem:"), objcObject,
                                                              items[row].item.objcObject)
    }

    override func isGroup(row: Int) -> Bool {
        guard items.indices.contains(row), Send.responds(delegateObject, "outlineView:isGroupItem:") else { return false }
        return Send.bool(delegateObject, "outlineView:isGroupItem:", objcObject, items[row].item.objcObject)
    }

    override func shouldSelect(row: Int) -> Bool {
        guard items.indices.contains(row), Send.responds(delegateObject, "outlineView:shouldSelectItem:") else { return true }
        return Send.bool(delegateObject, "outlineView:shouldSelectItem:", objcObject, items[row].item.objcObject)
    }

    override func willDisplay(cell: NSCell, column: NSTableColumn, row: Int) {
        guard items.indices.contains(row), Send.responds(delegateObject, "outlineView:willDisplayCell:forTableColumn:item:") else { return }
        typealias F = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, UnsafeMutableRawPointer, UnsafeMutableRawPointer, UnsafeMutableRawPointer,
                                      UnsafeMutableRawPointer) -> Void
        unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(delegateObject!, ObjCRuntime.selector("outlineView:willDisplayCell:forTableColumn:item:"),
                                                       objcObject, cell.objcObject, column.objcObject, items[row].item.objcObject)
    }

    override func didAdd(rowView: NSTableRowView, row: Int) {
        guard Send.responds(delegateObject, "outlineView:didAddRowView:forRow:") else { return super.didAdd(rowView: rowView, row: row) }
        Send.void(delegateObject, "outlineView:didAddRowView:forRow:", objcObject, rowView.objcObject, row)
    }

    /// The cells of a row sit past its level's indentation and the
    /// disclosure triangle.
    override func indentation(row: Int) -> CGFloat {
        guard items.indices.contains(row) else { return 0 }
        return CGFloat(items[row].level) * indentationPerLevel + 16
    }

    // MARK: Items

    @ObjCMethod("itemAtRow:") func itemAtRow(_ row: Int) -> NSObject? { item(forRow: row) }
    @ObjCMethod("rowForItem:") func row(forItem item: NSObject?) -> Int { items.firstIndex { $0.item.objcObject == item?.objcObject } ?? -1 }
    @ObjCMethod("levelForItem:") func level(forItem item: NSObject?) -> Int { items.first { $0.item.objcObject == item?.objcObject }?.level ?? -1 }
    @ObjCMethod("levelForRow:") func level(forRow row: Int) -> Int { items.indices.contains(row) ? items[row].level : -1 }
    @ObjCMethod("parentForItem:") func parent(forItem item: NSObject?) -> NSObject? { items.first { $0.item.objcObject == item?.objcObject }?.parent }
    @ObjCMethod("childIndexForItem:")
    func childIndex(forItem item: NSObject?) -> Int {
        guard let entry = items.first(where: { $0.item.objcObject == item?.objcObject }) else { return -1 }
        return items.filter { $0.parent?.objcObject == entry.parent?.objcObject && $0.level == entry.level }.firstIndex { $0.item.objcObject == item?.objcObject } ?? -1
    }
    @ObjCMethod("numberOfChildrenOfItem:") func numberOfChildren(ofItem item: NSObject?) -> Int { numberOfChildren(of: item) }
    @ObjCMethod("child:ofItem:") func child(_ index: Int, ofItem item: NSObject?) -> NSObject? { child(index, of: item) }
    @ObjCMethod("isExpandable:") func isExpandable(_ item: NSObject?) -> Bool { expandable(item) }
    @ObjCMethod("isItemExpanded:") func isItemExpanded(_ item: NSObject?) -> Bool { item.map { expanded.contains($0.objcObject) } ?? false }
    @ObjCMethod("outlineTableColumn") func outlineViewTableColumn() -> NSTableColumn? { outlineColumn }
    @ObjCMethod("setOutlineTableColumn:") func setOutlineTableColumn(_ column: NSTableColumn?) { outlineTableColumn = column; tile() }
    @ObjCMethod("indentationPerLevel") func outlineIndentationPerLevel() -> CGFloat { indentationPerLevel }
    @ObjCMethod("setIndentationPerLevel:") func setIndentationPerLevel(_ value: CGFloat) { indentationPerLevel = value; reloadData() }
    @ObjCMethod("indentationMarkerFollowsCell") func outlineIndentationMarkerFollowsCell() -> Bool { indentationMarkerFollowsCell }
    @ObjCMethod("setIndentationMarkerFollowsCell:") func setIndentationMarkerFollowsCell(_ value: Bool) { indentationMarkerFollowsCell = value }
    @ObjCMethod("autoresizesOutlineColumn") func outlineAutoresizesOutlineColumn() -> Bool { autoresizesOutlineColumn }
    @ObjCMethod("setAutoresizesOutlineColumn:") func setAutoresizesOutlineColumn(_ value: Bool) { autoresizesOutlineColumn = value }
    @ObjCMethod("autosaveExpandedItems") func outlineAutosaveExpandedItems() -> Bool { autosaveExpandedItems }
    @ObjCMethod("setAutosaveExpandedItems:") func setAutosaveExpandedItems(_ value: Bool) { autosaveExpandedItems = value }
    @ObjCMethod("stronglyReferencesItems") func outlineStronglyReferencesItems() -> Bool { stronglyReferencesItems }
    @ObjCMethod("setStronglyReferencesItems:") func setStronglyReferencesItems(_ value: Bool) { stronglyReferencesItems = value }
    @ObjCMethod("frameOfOutlineCellAtRow:")
    func frameOfOutlineCell(atRow row: Int) -> CGRect {
        guard items.indices.contains(row), let column = outlineColumn, let index = visibleColumns.firstIndex(where: { $0 === column }) else { return .zero }
        let rect = self.rect(ofRow: row)
        let x = columnRects()[index].x + CGFloat(items[row].level) * indentationPerLevel
        return CGRect(x: x, y: rect.minY, width: 16, height: rect.height)
    }
    @ObjCMethod("frameOfCellAtColumn:row:")
    override func frameOfCell(atColumn column: Int, row: Int) -> CGRect { super.frameOfCell(atColumn: column, row: row) }

    /// Tells the delegate and the default center, as AppKit's outlines do.
    private func notify(_ selector: String, _ name: String, _ item: NSObject) {
        let info = NSMutableDictionary.empty()
        info.set(item, forKey: "NSObject")
        let notification = NSNotification.make(name: name, object: self, userInfo: info)
        if Send.responds(delegateObject, selector) { Send.void(delegateObject, selector, notification.objcObject) }
        NSNotificationCenter.defaultCenter().post(notification)
    }

    @ObjCMethod("expandItem:") func expandItem(_ item: NSObject?) { expandItem(item, expandChildren: false) }

    @ObjCMethod("expandItem:expandChildren:")
    func expandItem(_ item: NSObject?, expandChildren: Bool) {
        Trace.log("outline: expand \(item.map { String(describing: $0.objcObject) } ?? "nil")")
        if !loaded { reloadData() }
        guard let item else {
            // nil expands every item.
            for entry in items where expandable(entry.item) { expandItem(entry.item, expandChildren: expandChildren) }
            return
        }
        guard expandable(item) else { return }
        if !expanded.contains(item.objcObject) {
            if Send.responds(delegateObject, "outlineView:shouldExpandItem:"), !Send.bool(delegateObject, "outlineView:shouldExpandItem:", objcObject, item.objcObject) {
                return
            }
            notify("outlineViewItemWillExpand:", "NSOutlineViewItemWillExpandNotification", item)
            expanded.insert(item.objcObject)
            expandedItems[item.objcObject] = item
            reloadKeepingSelection()
            notify("outlineViewItemDidExpand:", "NSOutlineViewItemDidExpandNotification", item)
        }
        if expandChildren {
            for index in 0..<numberOfChildren(of: item) {
                if let child = child(index, of: item) { expandItem(child, expandChildren: true) }
            }
        }
    }

    @ObjCMethod("collapseItem:") func collapseItem(_ item: NSObject?) { collapseItem(item, collapseChildren: false) }

    @ObjCMethod("collapseItem:collapseChildren:")
    func collapseItem(_ item: NSObject?, collapseChildren: Bool) {
        guard let item else {
            for entry in items where expanded.contains(entry.item.objcObject) { collapseItem(entry.item, collapseChildren: collapseChildren) }
            return
        }
        guard expanded.contains(item.objcObject) else { return }
        if Send.responds(delegateObject, "outlineView:shouldCollapseItem:"), !Send.bool(delegateObject, "outlineView:shouldCollapseItem:", objcObject, item.objcObject) {
            return
        }
        notify("outlineViewItemWillCollapse:", "NSOutlineViewItemWillCollapseNotification", item)
        expanded.remove(item.objcObject)
        expandedItems[item.objcObject] = nil
        if collapseChildren {
            for entry in items where entry.parent?.objcObject == item.objcObject { expanded.remove(entry.item.objcObject) }
        }
        reloadKeepingSelection()
        notify("outlineViewItemDidCollapse:", "NSOutlineViewItemDidCollapseNotification", item)
    }

    /// Reloads the rows, keeping the same items selected.
    private func reloadKeepingSelection() {
        let selected = selection.compactMap { items.indices.contains($0) ? items[$0].item.objcObject : nil }
        reloadData()
        let rows = selected.compactMap { pointer in items.firstIndex { $0.item.objcObject == pointer } }
        if rows != selection { setSelection(rows, notify: true) }
    }

    @ObjCMethod("reloadItem:") func reloadItem(_ item: NSObject?) { reloadItem(item, reloadChildren: false) }

    @ObjCMethod("reloadItem:reloadChildren:")
    func reloadItem(_ item: NSObject?, reloadChildren: Bool) {
        Trace.log("outline: reload item \(item.map { String(describing: $0.objcObject) } ?? "nil") children \(reloadChildren)")
        if item == nil || reloadChildren {
            reloadKeepingSelection()
            return
        }
        let row = row(forItem: item)
        if row >= 0, let rowView = rowViews.removeValue(forKey: row) {
            recycle(rowView)
            updateRowViews()
        }
        setNeedsDisplay(true)
    }

    @ObjCMethod("insertItemsAtIndexes:inParent:withAnimation:")
    func insertItems(at indexes: NSObject?, inParent parent: NSObject?, withAnimation options: UInt) {
        Trace.log("outline: insert \(IndexSets.indexes(indexes)) in \(parent.map { String(describing: $0.objcObject) } ?? "nil")")
        reloadKeepingSelection()
    }
    @ObjCMethod("removeItemsAtIndexes:inParent:withAnimation:")
    func removeItems(at indexes: NSObject?, inParent parent: NSObject?, withAnimation options: UInt) { reloadKeepingSelection() }
    @ObjCMethod("moveItemAtIndex:inParent:toIndex:inParent:")
    func moveItem(at from: Int, inParent oldParent: NSObject?, to: Int, inParent newParent: NSObject?) { reloadKeepingSelection() }
    @ObjCMethod("setDropItem:dropChildIndex:") func setDropItem(_ item: NSObject?, dropChildIndex index: Int) {}
    @ObjCMethod("shouldCollapseAutoExpandedItemsForDeposited:") func shouldCollapseAutoExpandedItems(forDeposited deposited: Bool) -> Bool { true }

    /// The triangle's square at the row's level, in the outline column.
    private func disclosureRect(row: Int) -> CGRect? {
        guard items.indices.contains(row), expandable(items[row].item) else { return nil }
        let frame = frameOfOutlineCell(atRow: row)
        return frame.width > 0 ? frame : nil
    }

    override func handleDisclosureClick(at point: CGPoint, row: Int) -> Bool {
        guard let rect = disclosureRect(row: row), rect.contains(point) else { return false }
        let item = items[row].item
        let all = NSEvent.currentModifierFlags & ModifierFlags.option != 0
        if expanded.contains(item.objcObject) { collapseItem(item, collapseChildren: all) } else { expandItem(item, expandChildren: all) }
        return true
    }

    override func handleKey(_ event: NSEvent) -> Bool {
        guard let row = selection.last, items.indices.contains(row) else { return false }
        let item = items[row].item
        switch event.keyCode {
        case 124:
            if expandable(item), !expanded.contains(item.objcObject) { expandItem(item) } else if row + 1 < items.count, items[row + 1].level > items[row].level {
                setSelection([row + 1], notify: true)
            }
            return true
        case 123:
            if expanded.contains(item.objcObject) { collapseItem(item) } else if let parent = items[row].parent {
                let parentRow = self.row(forItem: parent)
                if parentRow >= 0 { setSelection([parentRow], notify: true) }
            }
            return true
        default:
            return false
        }
    }

    /// The triangle, pointing right when closed and down when open.
    func drawTriangle(row: Int, in rowRect: CGRect, context: CGRef, light: Bool) {
        // A sidebar's group rows show theirs only under the mouse.
        guard !(isSourceList && isGroup(row: row)), let rect = disclosureRect(row: row) else { return }
        let open = expanded.contains(items[row].item.objcObject)
        let cx = rect.midX, cy = rowRect.midY
        let points = open ? [CGPoint(x: cx - 4, y: cy - 2), CGPoint(x: cx + 4, y: cy - 2), CGPoint(x: cx, y: cy + 3)]
            : [CGPoint(x: cx - 2, y: cy - 4), CGPoint(x: cx + 3, y: cy), CGPoint(x: cx - 2, y: cy + 4)]
        CG.fill(CG.polygon(points), light ? NSColor.whiteColor() : NSColor.tertiaryLabelColor(), in: context)
    }

    override func drawDisclosure(row: Int, column: NSTableColumn, context: CGRef) {
        guard column === outlineColumn else { return }
        drawTriangle(row: row, in: rect(ofRow: row), context: context, light: selection.contains(row))
    }
}

@ObjCClass("NSTableColumn")
open class NSTableColumn: NSObject {
    var identifier: String?
    var width: CGFloat = 100 {
        didSet { if width != oldValue { tableView?.columnResized() } }
    }
    var minWidth: CGFloat = 10
    var maxWidth: CGFloat = 100_000
    var headerCell: NSCell?
    var dataCell: NSCell?
    /// NSTableColumnResizingOptions: autoresizing 1, user resizing 2.
    var resizingMask: UInt = 3
    var hidden = false
    var editable = true
    var sortDescriptorPrototype: NSObject?
    var headerToolTip: String?
    /// Not retained.
    var tableViewObject: UnsafeMutableRawPointer?

    @ObjCMethod("init")
    public required override init() {
        super.init()
        makeCells()
    }

    @ObjCMethod("initWithIdentifier:")
    public required init(identifier: String?) {
        super.init()
        self.identifier = identifier
        makeCells()
    }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init()
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        identifier = decoded.string("NSIdentifier")
        width = decoded.has("NSWidth") ? decoded.double("NSWidth") : 100
        if decoded.has("NSMinWidth") { minWidth = decoded.double("NSMinWidth") }
        if decoded.has("NSMaxWidth") { maxWidth = decoded.double("NSMaxWidth") }
        headerCell = decoded.object("NSHeaderCell")?.as(NSCell.self)
        dataCell = decoded.object("NSDataCell")?.as(NSCell.self)
        if decoded.has("NSResizingMask") { resizingMask = UInt(decoded.integer("NSResizingMask")) }
        hidden = decoded.bool("NSHidden")
        editable = decoded.bool("NSIsEditable")
        sortDescriptorPrototype = decoded.object("NSSortDescriptorPrototype")
        headerToolTip = decoded.string("NSHeaderToolTip")
        tableViewObject = decoded.object("NSTableView")?.objcObject
        if headerCell == nil || dataCell == nil { makeCells() }
    }

    private func makeCells() {
        if headerCell == nil {
            let header = NSTableHeaderCell(textCell: "")
            header.font = NSFont.system(size: 11)
            headerCell = header
        }
        if dataCell == nil {
            let cell = NSTextFieldCell(textCell: "Field")
            (cell.editable, cell.bezeled, cell.drawsBackground) = (false, false, false)
            dataCell = cell
        }
    }

    var tableView: NSTableView? { tableViewObject.map(NSTableView.wrapTable) }

    @ObjCMethod("identifier") func columnIdentifier() -> String? { identifier }
    @ObjCMethod("setIdentifier:") func setIdentifier(_ value: String?) { identifier = value }
    @ObjCMethod("title") func title() -> String { headerCell?.cellString ?? "" }
    @ObjCMethod("setTitle:") func setTitle(_ value: String?) { headerCell?.setStringValue(value); tableView?.headerView?.setNeedsDisplay(true) }
    @ObjCMethod("width") func columnWidth() -> CGFloat { width }
    @ObjCMethod("setWidth:") func setWidth(_ value: CGFloat) { width = max(minWidth, min(maxWidth, value)) }
    @ObjCMethod("minWidth") func columnMinWidth() -> CGFloat { minWidth }
    @ObjCMethod("setMinWidth:") func setMinWidth(_ value: CGFloat) { minWidth = value; if width < value { width = value } }
    @ObjCMethod("maxWidth") func columnMaxWidth() -> CGFloat { maxWidth }
    @ObjCMethod("setMaxWidth:") func setMaxWidth(_ value: CGFloat) { maxWidth = value; if width > value { width = value } }
    @ObjCMethod("headerCell") func columnHeaderCell() -> NSCell? { headerCell }
    @ObjCMethod("setHeaderCell:") func setHeaderCell(_ cell: NSCell?) { headerCell = cell }
    @ObjCMethod("dataCell") func columnDataCell() -> NSCell? { dataCell }
    @ObjCMethod("setDataCell:") func setDataCell(_ cell: NSCell?) { dataCell = cell }
    @ObjCMethod("dataCellForRow:")
    func dataCell(forRow row: Int) -> NSCell? {
        if Methods.overrides(objcObject, "dataCellForRow:", of: NSTableColumn.objCClass.pointer) {
            return Send.objectRow(objcObject, "dataCellForRow:", row).map { NSCell.objCInstance($0, ownership: .retain) }
        }
        return dataCell
    }
    @ObjCMethod("resizingMask") func columnResizingMask() -> UInt { resizingMask }
    @ObjCMethod("setResizingMask:") func setResizingMask(_ value: UInt) { resizingMask = value }
    @ObjCMethod("isHidden") func isHidden() -> Bool { hidden }
    @ObjCMethod("setHidden:") func setHidden(_ value: Bool) { hidden = value; tableView?.tile() }
    @ObjCMethod("isEditable") func isEditable() -> Bool { editable }
    @ObjCMethod("setEditable:") func setEditable(_ value: Bool) { editable = value }
    @ObjCMethod("tableView") func columnTableView() -> NSTableView? { tableView }
    @ObjCMethod("setTableView:") func setTableView(_ table: NSTableView?) { tableViewObject = table?.objcObject }
    @ObjCMethod("sortDescriptorPrototype") func columnSortDescriptorPrototype() -> NSObject? { sortDescriptorPrototype }
    @ObjCMethod("setSortDescriptorPrototype:") func setSortDescriptorPrototype(_ value: NSObject?) { sortDescriptorPrototype = value }
    @ObjCMethod("headerToolTip") func columnHeaderToolTip() -> String? { headerToolTip }
    @ObjCMethod("setHeaderToolTip:") func setHeaderToolTip(_ value: String?) { headerToolTip = value }
    @ObjCMethod("sizeToFit") func sizeToFit() {}
    @ObjCMethod("setUserInterfaceIdentifier:") func setUserInterfaceIdentifier(_ value: NSObject?) {}
}

extension NSTableView {
    /// A column's width changed: the table and its rows are laid out again.
    func columnResized() {
        guard loaded else { return }
        let width = max(columnsWidth, superview?.as(NSClipView.self)?.bounds.width ?? 0)
        if frame.width != width { Send.void(objcObject, "setFrameSize:", size: CGSize(width: width, height: frame.height)) }
        for (row, rowView) in rowViews {
            recycle(rowView)
            rowViews[row] = nil
        }
        updateRowViews()
        headerView?.setNeedsDisplay(true)
        setNeedsDisplay(true)
    }
}

/// The columns' titles above a table; a click on one sorts by it.
@ObjCClass("NSTableHeaderView")
open class NSTableHeaderView: NSView {
    /// Not retained.
    var tableViewObject: UnsafeMutableRawPointer?

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init(coder: coder)
        if let coder { tableViewObject = Coder(coder: coder).object("NSTableView")?.objcObject }
    }

    public required init() { super.init() }

    @ObjCMethod("initWithFrame:")
    public required init(frame: CGRect) { super.init(frame: frame) }

    var tableView: NSTableView? { tableViewObject.map(NSTableView.wrapTable) }

    @ObjCMethod("tableView") func headerTableView() -> NSTableView? { tableView }
    @ObjCMethod("setTableView:") func setTableView(_ table: NSTableView?) { tableViewObject = table?.objcObject }
    @ObjCMethod("isFlipped") override func isFlipped() -> Bool { true }
    @ObjCMethod("headerRectOfColumn:")
    func headerRect(ofColumn column: Int) -> CGRect {
        guard let rects = tableView?.columnRects(), rects.indices.contains(column) else { return .zero }
        return CGRect(x: rects[column].x, y: 0, width: rects[column].width, height: frame.height)
    }
    @ObjCMethod("columnAtPoint:") func column(at point: CGPoint) -> Int { tableView?.column(at: point) ?? -1 }
    @ObjCMethod("draggedColumn") func draggedColumn() -> Int { -1 }
    @ObjCMethod("resizedColumn") func resizedColumn() -> Int { -1 }

    @ObjCMethod("drawRect:")
    override func draw(_ rect: CGRect) {
        guard let context = NSGraphicsContext.currentCG, let tableView else { return }
        CG.saveGState(context)
        CG.setFill(context, NSColor.headerColor())
        CG.fillRect(context, bounds)
        CG.setFill(context, NSColor.separatorColor())
        CG.fillRect(context, CGRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1))
        CG.restoreGState(context)
        for entry in tableView.columnRects() {
            guard let cell = entry.column.headerCell else { continue }
            typealias F = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, CGRect, UnsafeMutableRawPointer?) -> Void
            unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(cell.objcObject, ObjCRuntime.selector("drawWithFrame:inView:"),
                                                           CGRect(x: entry.x, y: 0, width: entry.width, height: bounds.height - 1), objcObject)
        }
    }

    @ObjCMethod("mouseDown:")
    override func mouseDown(_ eventObject: NSObject?) {
        guard let event = eventObject?.as(NSEvent.self), let tableView else { return }
        let index = tableView.column(at: convert(event.locationInWindow, from: nil))
        let columns = tableView.visibleColumns
        guard columns.indices.contains(index) else { return }
        let column = columns[index]
        if Send.responds(tableView.delegateObject, "tableView:mouseDownInHeaderOfTableColumn:") {
            Send.void(tableView.delegateObject, "tableView:mouseDownInHeaderOfTableColumn:", tableView.objcObject, column.objcObject)
        }
        // Sorting by the column's prototype, reversed when it already sorts.
        if let prototype = column.sortDescriptorPrototype {
            let current = tableView.sortDescriptors?.as(NSArray.self)?.elements.first
            let sameKey = current.flatMap { Send.object($0.objcObject, "key") }.map { String(objCArgument: $0) }
                == Send.object(prototype.objcObject, "key").map { String(objCArgument: $0) }
            let descriptor = sameKey ? NSObject(Send.object(current!.objcObject, "reversedSortDescriptor")!) : prototype
            tableView.setSortDescriptors(NSMutableArray.of([descriptor]))
        }
        if Send.responds(tableView.delegateObject, "tableView:didClickTableColumn:") {
            Send.void(tableView.delegateObject, "tableView:didClickTableColumn:", tableView.objcObject, column.objcObject)
        }
        setNeedsDisplay(true)
    }
}

/// A row: its cell views side by side, and the selection behind them.
@ObjCClass("NSTableRowView")
open class NSTableRowView: NSView {
    /// Not retained.
    var tableViewObject: UnsafeMutableRawPointer?
    var row = -1
    var selected = false
    var emphasized = true
    var groupRowStyle = false
    var floating = false
    var cellViews: [NSView] = []
    var backgroundColorValue: NSColor?
    var selectionHighlightStyle = 0

    public required init() { super.init() }

    @ObjCMethod("initWithFrame:")
    public required init(frame: CGRect) { super.init(frame: frame) }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) { super.init(coder: coder) }

    var tableView: NSTableView? { tableViewObject.map(NSTableView.wrapTable) }

    @ObjCMethod("isFlipped") override func isFlipped() -> Bool { true }
    @ObjCMethod("isSelected") func isSelected() -> Bool { selected }
    @ObjCMethod("setSelected:") func setSelected(_ value: Bool) { selected = value; updateBackgroundStyle(); setNeedsDisplay(true) }
    @ObjCMethod("isEmphasized") func isEmphasized() -> Bool { emphasized }
    @ObjCMethod("setEmphasized:") func setEmphasized(_ value: Bool) { emphasized = value; updateBackgroundStyle(); setNeedsDisplay(true) }
    @ObjCMethod("isGroupRowStyle") func isGroupRowStyle() -> Bool { groupRowStyle }
    @ObjCMethod("setGroupRowStyle:") func setGroupRowStyle(_ value: Bool) { groupRowStyle = value }
    @ObjCMethod("isFloating") func isFloating() -> Bool { floating }
    @ObjCMethod("setFloating:") func setFloating(_ value: Bool) { floating = value }
    @ObjCMethod("isTargetForDropOperation") func isTargetForDropOperation() -> Bool { false }
    @ObjCMethod("setTargetForDropOperation:") func setTargetForDropOperation(_ value: Bool) {}
    @ObjCMethod("isNextRowSelected") func isNextRowSelected() -> Bool { tableView?.selection.contains(row + 1) ?? false }
    @ObjCMethod("isPreviousRowSelected") func isPreviousRowSelected() -> Bool { tableView?.selection.contains(row - 1) ?? false }
    @ObjCMethod("selectionHighlightStyle") func rowSelectionHighlightStyle() -> Int { tableView?.selectionHighlightStyle ?? selectionHighlightStyle }
    @ObjCMethod("setSelectionHighlightStyle:") func setSelectionHighlightStyle(_ value: Int) { selectionHighlightStyle = value }
    @ObjCMethod("backgroundColor") func rowBackgroundColor() -> NSColor? { backgroundColorValue }
    @ObjCMethod("setBackgroundColor:") func setBackgroundColor(_ value: NSColor?) { backgroundColorValue = value; setNeedsDisplay(true) }
    @ObjCMethod("numberOfColumns") func numberOfColumns() -> Int { cellViews.count }
    @ObjCMethod("viewAtColumn:") func view(atColumn column: Int) -> NSView? { cellViews.indices.contains(column) ? cellViews[column] : nil }
    @ObjCMethod("interiorBackgroundStyle") func interiorBackgroundStyle() -> Int { selected && emphasized && rowSelectionHighlightStyle() != -1 ? 1 : 0 }

    /// Cell views show light text on a selected row's emphasized color.
    func updateBackgroundStyle() {
        emphasized = window?.isKeyWindow() != false
        let style = interiorBackgroundStyle()
        for cell in cellViews where Send.responds(cell.objcObject, "setBackgroundStyle:") {
            typealias F = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, Int) -> Void
            unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(cell.objcObject, ObjCRuntime.selector("setBackgroundStyle:"), style)
        }
    }

    @ObjCMethod("drawRect:")
    override func draw(_ rect: CGRect) {
        Send.void(objcObject, "drawBackgroundInRect:", rect: rect)
        if selected, rowSelectionHighlightStyle() != -1 { Send.void(objcObject, "drawSelectionInRect:", rect: rect) }
        if let outline = tableView?.as(NSOutlineView.self), let context = NSGraphicsContext.currentCG {
            outline.drawTriangle(row: row, in: CGRect(origin: .zero, size: frame.size), context: context, light: selected && emphasized)
        }
    }

    @ObjCMethod("drawBackgroundInRect:")
    func drawBackground(in rect: CGRect) {
        guard let context = NSGraphicsContext.currentCG else { return }
        if let backgroundColorValue {
            CG.saveGState(context)
            CG.setFill(context, backgroundColorValue)
            CG.fillRect(context, rect)
            CG.restoreGState(context)
        } else if groupRowStyle, tableView?.isSourceList != true {
            // A sidebar's group rows are headings on its own background.
            CG.saveGState(context)
            CG.setFill(context, NSColor(white: Appearances.currentIsDark ? 0.16 : 0.95, alpha: 1))
            CG.fillRect(context, bounds)
            CG.restoreGState(context)
        }
    }

    @ObjCMethod("drawSelectionInRect:")
    func drawSelection(in rect: CGRect) {
        guard let context = NSGraphicsContext.currentCG else { return }
        let color = emphasized ? NSColor.selectedContentBackgroundColor() : NSColor.unemphasizedSelectedContentBackgroundColor()
        // A sidebar's selection is a rounded bar inside the row.
        let sidebar = tableView?.isSourceList == true
        let inset = sidebar ? bounds.insetBy(dx: 10, dy: 1) : bounds
        CG.fill(CG.roundedRect(inset, radius: sidebar ? 5 : 0), color, in: context)
    }

    @ObjCMethod("drawSeparatorInRect:") func drawSeparator(in rect: CGRect) {}
    @ObjCMethod("drawDraggingDestinationFeedbackInRect:") func drawDraggingDestinationFeedback(in rect: CGRect) {}
}

/// A view-based table's cell: its text field and image view, which show
/// its object value as the app sets them up.
@ObjCClass("NSTableCellView")
open class NSTableCellView: NSView {
    var objectValue: NSObject?
    var textField: NSTextField?
    var imageView: NSImageView?
    var backgroundStyle = 0
    var rowSizeStyle = -1
    var draggingImageComponents: NSObject?

    public required init() { super.init() }

    @ObjCMethod("initWithFrame:")
    public required init(frame: CGRect) { super.init(frame: frame) }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init(coder: coder)
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        textField = decoded.object("NSTableCellViewTextField")?.as(NSTextField.self)
        imageView = decoded.object("NSTableCellViewImageView")?.as(NSImageView.self)
    }

    @ObjCMethod("objectValue") func cellObjectValue() -> NSObject? { objectValue }
    @ObjCMethod("setObjectValue:") func setObjectValue(_ value: NSObject?) { objectValue = value }
    @ObjCMethod("textField") func cellTextField() -> NSTextField? { textField }
    @ObjCMethod("setTextField:") func setTextField(_ field: NSTextField?) { textField = field }
    @ObjCMethod("imageView") func cellImageView() -> NSImageView? { imageView }
    @ObjCMethod("setImageView:") func setImageView(_ view: NSImageView?) { imageView = view }
    @ObjCMethod("backgroundStyle") func cellBackgroundStyle() -> Int { backgroundStyle }

    /// The style reaches the cells of its controls, which draw in light
    /// colors on an emphasized background.
    @ObjCMethod("setBackgroundStyle:")
    func setBackgroundStyle(_ value: Int) {
        backgroundStyle = value
        for view in allViews.dropFirst() {
            guard let control = view.as(NSControl.self), let cell = control.cellObject, cell.backgroundStyle != value else { continue }
            cell.setBackgroundStyle(value)
        }
    }
    @ObjCMethod("rowSizeStyle") func cellRowSizeStyle() -> Int { rowSizeStyle }
    @ObjCMethod("setRowSizeStyle:") func setRowSizeStyle(_ value: Int) { rowSizeStyle = value }
    @ObjCMethod("draggingImageComponents") func cellDraggingImageComponents() -> NSObject { draggingImageComponents ?? NSMutableArray.empty() }
    @ObjCMethod("prepareForReuse") func prepareForReuse() {}
    @ObjCMethod("isFlipped") override func isFlipped() -> Bool { false }
}

/// The corner above a table's vertical scroller, which draws the header's
/// background.
@ObjCClass("_NSCornerView")
open class NSCornerView: NSView {
    @ObjCMethod("drawRect:")
    override func draw(_ rect: CGRect) {
        guard let context = NSGraphicsContext.currentCG else { return }
        CG.saveGState(context)
        CG.setFill(context, NSColor.headerColor())
        CG.fillRect(context, bounds)
        CG.restoreGState(context)
    }
}

extension Send {
    static func integer(_ receiver: Object, _ selector: String, _ argument: Object?) -> Int {
        typealias F = @convention(c) (Object, Selector, Object?) -> Int
        return unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector(selector), argument)
    }

    static func integer(_ receiver: Object, _ selector: String, _ first: Object?, _ second: Object?) -> Int {
        typealias F = @convention(c) (Object, Selector, Object?, Object?) -> Int
        return unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector(selector), first, second)
    }

    static func bool(_ receiver: Object?, _ selector: String, _ first: Object?, _ second: Object?) -> Bool {
        guard let receiver else { return false }
        typealias F = @convention(c) (Object, Selector, Object?, Object?) -> Bool
        return unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector(selector), first, second)
    }

    static func object(_ receiver: Object?, _ selector: String, _ first: Object?, _ second: Object?) -> Object? {
        guard let receiver else { return nil }
        typealias F = @convention(c) (Object, Selector, Object?, Object?) -> Object?
        return unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector(selector), first, second)
    }

    /// tableView:x:row: — two objects and a row.
    static func object(_ receiver: Object?, _ selector: String, _ first: Object?, _ second: Object?, _ row: Int) -> Object? {
        guard let receiver else { return nil }
        typealias F = @convention(c) (Object, Selector, Object?, Object?, Int) -> Object?
        return unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector(selector), first, second, row)
    }

    static func object(_ receiver: Object?, _ selector: String, _ first: Object?, _ second: Object?, _ third: Object?) -> Object? {
        guard let receiver else { return nil }
        typealias F = @convention(c) (Object, Selector, Object?, Object?, Object?) -> Object?
        return unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector(selector), first, second, third)
    }

    /// tableView:x:row: with no second object: the table and a row.
    static func object(_ receiver: Object?, _ selector: String, _ table: Object?, _ unused: Object?, _ row: Int, skipSecond: Bool) -> Object? {
        guard let receiver else { return nil }
        typealias F = @convention(c) (Object, Selector, Object?, Int) -> Object?
        return unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector(selector), table, row)
    }

    static func objectRow(_ receiver: Object, _ selector: String, _ row: Int) -> Object? {
        typealias F = @convention(c) (Object, Selector, Int) -> Object?
        return unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector(selector), row)
    }

    static func void(_ receiver: Object?, _ selector: String, _ first: Object?, _ second: Object?, _ row: Int) {
        guard let receiver else { return }
        typealias F = @convention(c) (Object, Selector, Object?, Object?, Int) -> Void
        unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector(selector), first, second, row)
    }

    static func doubleRow(_ receiver: Object, _ selector: String, _ table: Object?, _ row: Int) -> CGFloat {
        typealias F = @convention(c) (Object, Selector, Object?, Int) -> CGFloat
        return unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector(selector), table, row)
    }

    static func boolRow(_ receiver: Object, _ selector: String, _ table: Object?, _ row: Int) -> Bool {
        typealias F = @convention(c) (Object, Selector, Object?, Int) -> Bool
        return unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector(selector), table, row)
    }
}

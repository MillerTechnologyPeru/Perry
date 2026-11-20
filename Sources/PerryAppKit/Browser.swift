import CPerryGeometry
import PerryObjCInterop

// NSBrowser and NSBrowserCell: a hierarchy shown as columns, which
// Interface Builder's tools subclass. The browser keeps its settings and
// asks its delegate for its columns' rows; it doesn't draw columns yet.

@ObjCClass("NSBrowser")
open class NSBrowser: NSControl {
    /// Not retained.
    var delegateObject: UnsafeMutableRawPointer?
    var cellClass: UnsafeMutableRawPointer?
    var cellPrototype: NSObject?
    var maxVisibleColumns = 3
    var minColumnWidth: CGFloat = 100
    var separatesColumns = true
    var titled = true
    var hasHorizontalScroller = true
    var allowsMultipleSelection = false
    var allowsEmptySelection = true
    var pathSeparator = "/"
    var lastColumn = 0
    var columnTitles: [Int: String] = [:]
    var selections: [Int: Int] = [:]
    var doubleAction: ObjCSelector?

    @ObjCClassMethod("cellClass") static func browserCellClass() -> UnsafeMutableRawPointer? { Classes.named("NSBrowserCell")?.pointer }

    @ObjCMethod("delegate") func browserDelegate() -> NSObject? { delegateObject.map(NSObject.init) }
    @ObjCMethod("setDelegate:") func setDelegate(_ value: NSObject?) { delegateObject = value?.objcObject }
    @ObjCMethod("setCellClass:") func setCellClass(_ value: UnsafeMutableRawPointer?) { cellClass = value }
    @ObjCMethod("cellPrototype") func browserCellPrototype() -> NSObject? { cellPrototype }
    @ObjCMethod("setCellPrototype:") func setCellPrototype(_ value: NSObject?) { cellPrototype = value }
    @ObjCMethod("maxVisibleColumns") func browserMaxVisibleColumns() -> Int { maxVisibleColumns }
    @ObjCMethod("setMaxVisibleColumns:") func setMaxVisibleColumns(_ value: Int) { maxVisibleColumns = value }
    @ObjCMethod("minColumnWidth") func browserMinColumnWidth() -> CGFloat { minColumnWidth }
    @ObjCMethod("setMinColumnWidth:") func setMinColumnWidth(_ value: CGFloat) { minColumnWidth = value }
    @ObjCMethod("separatesColumns") func browserSeparatesColumns() -> Bool { separatesColumns }
    @ObjCMethod("setSeparatesColumns:") func setSeparatesColumns(_ value: Bool) { separatesColumns = value }
    @ObjCMethod("isTitled") func isTitled() -> Bool { titled }
    @ObjCMethod("setTitled:") func setTitled(_ value: Bool) { titled = value }
    @ObjCMethod("hasHorizontalScroller") func browserHasHorizontalScroller() -> Bool { hasHorizontalScroller }
    @ObjCMethod("setHasHorizontalScroller:") func setHasHorizontalScroller(_ value: Bool) { hasHorizontalScroller = value }
    @ObjCMethod("allowsMultipleSelection") func browserAllowsMultipleSelection() -> Bool { allowsMultipleSelection }
    @ObjCMethod("setAllowsMultipleSelection:") func setAllowsMultipleSelection(_ value: Bool) { allowsMultipleSelection = value }
    @ObjCMethod("allowsEmptySelection") func browserAllowsEmptySelection() -> Bool { allowsEmptySelection }
    @ObjCMethod("setAllowsEmptySelection:") func setAllowsEmptySelection(_ value: Bool) { allowsEmptySelection = value }
    @ObjCMethod("pathSeparator") func browserPathSeparator() -> String { pathSeparator }
    @ObjCMethod("setPathSeparator:") func setPathSeparator(_ value: String?) { pathSeparator = value ?? "/" }
    @ObjCMethod("doubleAction") func browserDoubleAction() -> ObjCSelector? { doubleAction }
    @ObjCMethod("setDoubleAction:") func setDoubleAction(_ value: ObjCSelector?) { doubleAction = value }
    @ObjCMethod("lastColumn") func browserLastColumn() -> Int { lastColumn }
    @ObjCMethod("setLastColumn:") func setLastColumn(_ value: Int) { lastColumn = max(0, value) }
    @ObjCMethod("numberOfVisibleColumns") func numberOfVisibleColumns() -> Int { min(maxVisibleColumns, lastColumn + 1) }
    @ObjCMethod("firstVisibleColumn") func firstVisibleColumn() -> Int { 0 }
    @ObjCMethod("lastVisibleColumn") func lastVisibleColumn() -> Int { lastColumn }
    @ObjCMethod("titleOfColumn:") func title(ofColumn column: Int) -> String? { columnTitles[column] }
    @ObjCMethod("setTitle:ofColumn:") func setTitle(_ value: String?, ofColumn column: Int) { columnTitles[column] = value }
    @ObjCMethod("selectedColumn") func selectedColumn() -> Int { selections.keys.max() ?? -1 }
    @ObjCMethod("selectedRowInColumn:") func selectedRow(inColumn column: Int) -> Int { selections[column] ?? -1 }
    @ObjCMethod("selectRow:inColumn:")
    func selectRow(_ row: Int, inColumn column: Int) {
        selections = selections.filter { $0.key < column }
        selections[column] = row
        lastColumn = column
    }
    @ObjCMethod("path") func path() -> String { pathSeparator }
    @ObjCMethod("setPath:") func setPath(_ value: String?) -> Bool { true }
    @ObjCMethod("loadColumnZero") func loadColumnZero() { lastColumn = 0; selections.removeAll() }
    @ObjCMethod("reloadColumn:") func reloadColumn(_ column: Int) { setNeedsDisplay(true) }
    @ObjCMethod("validateVisibleColumns") func validateVisibleColumns() {}
    @ObjCMethod("tile") func tile() {}
    @ObjCMethod("scrollColumnToVisible:") func scrollColumnToVisible(_ column: Int) {}

    /// The delegate's count of rows in a column (passive delegates), or 0.
    @ObjCMethod("numberOfRowsInColumn:")
    func numberOfRows(inColumn column: Int) -> Int {
        guard Send.responds(delegateObject, "browser:numberOfRowsInColumn:") else { return 0 }
        typealias F = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, UnsafeMutableRawPointer, Int) -> Int
        return unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(delegateObject!, ObjCRuntime.selector("browser:numberOfRowsInColumn:"),
                                                              objcObject, column)
    }
}

@ObjCClass("NSBrowserCell")
open class NSBrowserCell: NSCell {
    var leaf = false
    var loaded = false
    var alternateImage: NSImage?

    @ObjCMethod("isLeaf") func isLeaf() -> Bool { leaf }
    @ObjCMethod("setLeaf:") func setLeaf(_ value: Bool) { leaf = value }
    @ObjCMethod("isLoaded") func isLoaded() -> Bool { loaded }
    @ObjCMethod("setLoaded:") func setLoaded(_ value: Bool) { loaded = value }
    @ObjCMethod("reset") func reset() { highlighted = false; state = 0 }
    @ObjCMethod("set") func set() { highlighted = true; state = 1 }
    @ObjCMethod("alternateImage") func cellAlternateImage() -> NSImage? { alternateImage }
    @ObjCMethod("setAlternateImage:") func setAlternateImage(_ value: NSImage?) { alternateImage = value }
    @ObjCClassMethod("branchImage") static func branchImage() -> NSImage? { nil }
    @ObjCClassMethod("highlightedBranchImage") static func highlightedBranchImage() -> NSImage? { nil }
}

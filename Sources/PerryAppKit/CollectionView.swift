import CPerryGeometry
import PerryObjCInterop

// NSCollectionView as Mac OS X 10.5 made it: an array of content objects,
// an item for each (-newItemForRepresentedObject:, which apps override,
// or a copy of the item prototype), and the items' views tiled in rows
// from the top, each the prototype's size, with selection by clicking.
// The 10.11 kind, with a data source and a layout object, keeps its data
// source, delegate and layout but shows no items: its layouts are not here.

@ObjCClass("NSCollectionView")
open class NSCollectionView: NSView {
    var content: [NSObject] = []
    var contentArray: NSObject?
    var items: [NSObject] = []
    var itemPrototype: NSObject?
    var selection: [Int] = []
    var selectable = false
    var allowsMultipleSelection = false
    var allowsEmptySelection = true
    var maxNumberOfRows = 0
    var maxNumberOfColumns = 0
    var minItemSize = CGSize.zero
    var maxItemSize = CGSize.zero
    var backgroundColors: NSObject?
    /// Not retained.
    var delegateObject: UnsafeMutableRawPointer?
    /// Not retained.
    var dataSourceObject: UnsafeMutableRawPointer?
    var collectionViewLayout: NSObject?
    private var tiling = false

    /// Items run down from the top.
    @ObjCMethod("isFlipped") override func isFlipped() -> Bool { true }
    @ObjCMethod("acceptsFirstResponder") override func acceptsFirstResponder() -> Bool { selectable }

    // MARK: Content and items

    @ObjCMethod("content") func collectionContent() -> NSObject { contentArray ?? NSMutableArray.of(content) }

    /// Makes an item for each object, through -newItemForRepresentedObject:,
    /// and tiles their views.
    @ObjCMethod("setContent:")
    func setContent(_ value: NSObject?) {
        contentArray = value
        content = value?.as(NSArray.self)?.elements ?? []
        selection = selection.filter { $0 < content.count }
        reloadItems()
    }

    @ObjCMethod("itemPrototype") func collectionItemPrototype() -> NSObject? { itemPrototype }
    @ObjCMethod("setItemPrototype:") func setItemPrototype(_ value: NSObject?) { itemPrototype = value }

    /// A copy of the prototype showing `object`, owned by the caller as a
    /// new… method's result is: nil when the prototype can't be copied.
    @ObjCMethod("newItemForRepresentedObject:")
    func newItem(forRepresentedObject object: NSObject?) -> UnsafeMutableRawPointer? {
        guard let prototype = itemPrototype?.objcObject, Send.responds(prototype, "copyWithZone:"),
              let item = Send.object(prototype, "copy") else {
            appKitWarning("NSCollectionView: no item for an object: its item prototype can't be copied")
            return nil
        }
        Send.void(item, "setRepresentedObject:", object?.objcObject)
        return item
    }

    @ObjCMethod("itemAtIndex:")
    func item(at index: UInt) -> NSObject? { index < UInt(items.count) ? items[Int(index)] : nil }

    /// The items laid out: all of them.
    @ObjCMethod("visibleItems") func visibleItems() -> NSObject { NSMutableArray.of(items) }

    @ObjCMethod("frameForItemAtIndex:")
    func frameForItem(at index: UInt) -> CGRect {
        guard index < UInt(items.count), let view = itemView(items[Int(index)]) else { return .zero }
        return Send.rect(view, "frame")
    }

    @ObjCMethod("frameForItemAtIndex:withNumberOfItems:")
    func frameForItem(at index: UInt, numberOfItems: UInt) -> CGRect { frameForItem(at: index) }

    /// The content's items again; with a data source, nothing, as its
    /// layouts are not here.
    @ObjCMethod("reloadData")
    func reloadData() {
        if dataSourceObject != nil {
            appKitWarning("NSCollectionView: data source collection views show no items here (no collection view layouts)")
            return
        }
        reloadItems()
    }

    private func itemView(_ item: NSObject) -> UnsafeMutableRawPointer? { Send.object(item.objcObject, "view") }

    private func reloadItems() {
        for item in items { if let view = itemView(item) { Send.void(view, "removeFromSuperview") } }
        items = content.compactMap { object in
            Send.object(objcObject, "newItemForRepresentedObject:", object.objcObject).map { NSObject(objcObject: $0, ownership: .adopt) }
        }
        for item in items { if let view = itemView(item) { Send.void(objcObject, "addSubview:", view) } }
        updateItemSelection()
        tile()
    }

    /// Lays the items' views out in rows, each item the minimum item size
    /// or else the first view's size, widened to share the width among the
    /// columns up to the maximum item size; and grows to hold the rows (and
    /// at least to fill the clip view it scrolls in).
    func tile() {
        guard !tiling else { return }
        tiling = true
        defer { tiling = false }
        let views = items.compactMap(itemView)
        guard let first = views.first else { return }
        var size = Send.rect(first, "frame").size
        if minItemSize.width > 0 { size.width = minItemSize.width }
        if minItemSize.height > 0 { size.height = minItemSize.height }
        size.width = max(size.width, 1)
        size.height = max(size.height, 1)
        var columns = max(1, Int(frame.width / size.width))
        if maxNumberOfColumns > 0 { columns = min(columns, maxNumberOfColumns) }
        if maxNumberOfRows > 0 { columns = max(columns, (views.count + maxNumberOfRows - 1) / maxNumberOfRows) }
        var width = max(size.width, frame.width / CGFloat(columns))
        if maxItemSize.width > 0 { width = min(width, max(maxItemSize.width, size.width)) }
        for (index, view) in views.enumerated() {
            let rect = CGRect(x: CGFloat(index % columns) * width, y: CGFloat(index / columns) * size.height, width: width, height: size.height)
            Send.void(view, "setFrame:", rect: rect)
        }
        let rows = (views.count + columns - 1) / columns
        var height = CGFloat(rows) * size.height
        if let clip = superview?.as(NSClipView.self) { height = max(height, clip.frame.height) }
        if height != frame.height { Send.void(objcObject, "setFrameSize:", size: CGSize(width: frame.width, height: height)) }
    }

    /// A change of width tiles the items again.
    @ObjCMethod("resizeSubviewsWithOldSize:")
    override func resizeSubviews(withOldSize old: CGSize) {
        if old.width != frame.width { tile() }
    }

    // MARK: Selection

    @ObjCMethod("selectionIndexes") func selectionIndexes() -> NSObject { IndexSets.make(selection) }

    @ObjCMethod("setSelectionIndexes:")
    func setSelectionIndexes(_ value: NSObject?) {
        selection = IndexSets.indexes(value).filter { $0 < content.count }
        updateItemSelection()
    }

    @ObjCMethod("isSelectable") func isSelectable() -> Bool { selectable }
    @ObjCMethod("setSelectable:") func setSelectable(_ value: Bool) { selectable = value }
    @ObjCMethod("allowsMultipleSelection") func collectionAllowsMultipleSelection() -> Bool { allowsMultipleSelection }
    @ObjCMethod("setAllowsMultipleSelection:") func setAllowsMultipleSelection(_ value: Bool) { allowsMultipleSelection = value }
    @ObjCMethod("allowsEmptySelection") func collectionAllowsEmptySelection() -> Bool { allowsEmptySelection }
    @ObjCMethod("setAllowsEmptySelection:") func setAllowsEmptySelection(_ value: Bool) { allowsEmptySelection = value }

    @ObjCMethod("selectAll:")
    func selectAll(_ sender: NSObject?) {
        guard selectable, allowsMultipleSelection else { return }
        selection = Array(content.indices)
        updateItemSelection()
    }

    @ObjCMethod("deselectAll:")
    func deselectAll(_ sender: NSObject?) {
        guard allowsEmptySelection else { return }
        selection = []
        updateItemSelection()
    }

    /// Tells each item whether it is selected, for the items that take it.
    private func updateItemSelection() {
        for (index, item) in items.enumerated() where Send.responds(item.objcObject, "setSelected:") {
            Send.void(item.objcObject, "setSelected:", bool: selection.contains(index))
        }
    }

    /// A click selects the item under it, or nothing when empty selection
    /// is allowed; a shift-click adds to the selection when that's allowed.
    @ObjCMethod("mouseDown:")
    override func mouseDown(_ event: NSObject?) {
        guard selectable, let event = event?.as(NSEvent.self) else { return super.mouseDown(event) }
        _ = window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        let hit = items.firstIndex { item in itemView(item).map { Send.rect($0, "frame").contains(point) } ?? false }
        if let hit {
            let extending = allowsMultipleSelection && event.modifierFlags & (1 << 17) != 0
            selection = extending ? Array(Set(selection + [hit])).sorted() : [hit]
        } else if allowsEmptySelection {
            selection = []
        }
        updateItemSelection()
    }

    // MARK: Appearance and the rest

    @ObjCMethod("maxNumberOfRows") func collectionMaxNumberOfRows() -> UInt { UInt(maxNumberOfRows) }
    @ObjCMethod("setMaxNumberOfRows:") func setMaxNumberOfRows(_ value: UInt) { maxNumberOfRows = Int(value); tile() }
    @ObjCMethod("maxNumberOfColumns") func collectionMaxNumberOfColumns() -> UInt { UInt(maxNumberOfColumns) }
    @ObjCMethod("setMaxNumberOfColumns:") func setMaxNumberOfColumns(_ value: UInt) { maxNumberOfColumns = Int(value); tile() }
    @ObjCMethod("minItemSize") func collectionMinItemSize() -> CGSize { minItemSize }
    @ObjCMethod("setMinItemSize:") func setMinItemSize(_ value: CGSize) { minItemSize = value; tile() }
    @ObjCMethod("maxItemSize") func collectionMaxItemSize() -> CGSize { maxItemSize }
    @ObjCMethod("setMaxItemSize:") func setMaxItemSize(_ value: CGSize) { maxItemSize = value; tile() }
    @ObjCMethod("backgroundColors") func collectionBackgroundColors() -> NSObject { backgroundColors ?? NSMutableArray.empty() }
    @ObjCMethod("setBackgroundColors:") func setBackgroundColors(_ value: NSObject?) { backgroundColors = value; setNeedsDisplay(true) }

    @ObjCMethod("delegate") func collectionDelegate() -> NSObject? { delegateObject.map(NSObject.init) }
    @ObjCMethod("setDelegate:") func setDelegate(_ value: NSObject?) { delegateObject = value?.objcObject }
    @ObjCMethod("dataSource") func collectionDataSource() -> NSObject? { dataSourceObject.map(NSObject.init) }
    @ObjCMethod("setDataSource:") func setDataSource(_ value: NSObject?) { dataSourceObject = value?.objcObject }
    @ObjCMethod("collectionViewLayout") func layoutObject() -> NSObject? { collectionViewLayout }
    @ObjCMethod("setCollectionViewLayout:") func setCollectionViewLayout(_ value: NSObject?) { collectionViewLayout = value }
    /// Drags from the view aren't started here; the mask is kept for none.
    @ObjCMethod("setDraggingSourceOperationMask:forLocal:") func setDraggingSourceOperationMask(_ mask: UInt, forLocal local: Bool) {}

    /// The first background color, behind the items.
    @ObjCMethod("drawRect:")
    override func draw(_ rect: CGRect) {
        guard let color = backgroundColors?.as(NSArray.self)?.elements.first, let context = NSGraphicsContext.currentCG else { return }
        CG.saveGState(context)
        Send.void(color.objcObject, "setFill")
        CG.fillRect(context, rect)
        CG.restoreGState(context)
    }
}

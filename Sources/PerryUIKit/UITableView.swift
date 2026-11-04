import CPerryGeometry
import PerryObjCInterop

// UITableView: a scroll view of sections of rows. Layout asks the data
// source for a cell for each row that comes into view, then puts cells
// that left it in their reuse pool, so a long jump makes new cells rather
// than reusing the old ones, as on Darwin. In the plain style, section
// headers float at the top of the visible area. Updates to rows move the
// cells already shown and ask only for the new ones.

/// A row's place: its section and its row in it.
struct RowPath: Hashable, Comparable {
    var section: Int
    var row: Int

    static func < (a: RowPath, b: RowPath) -> Bool { (a.section, a.row) < (b.section, b.row) }

    init(section: Int, row: Int) {
        self.section = section
        self.row = row
    }

    init(_ indexPath: NSObject) {
        section = indexPath.sendSection()
        row = indexPath.sendRow()
    }

    var object: NSObject { IndexPaths.make(section: section, row: row) }
}

enum IndexPaths {
    static func make(section: Int, row: Int) -> NSObject {
        var indexes = [UInt(section), UInt(row)]
        return ObjCClass(named: "NSIndexPath").object.sendIndexPath(withIndexes: &indexes, length: 2)
    }
}

/// UIKit's additions to NSIndexPath: sections, rows and items.
@ObjCWrapper("NSIndexPath")
class NSIndexPath: NSObject {}

@ObjCCategory("UIKitAdditions")
extension NSIndexPath {
    @ObjCClassMethod("indexPathForRow:inSection:")
    static func indexPath(row: Int, section: Int) -> NSObject { IndexPaths.make(section: section, row: row) }

    @ObjCClassMethod("indexPathForItem:inSection:")
    static func indexPath(item: Int, section: Int) -> NSObject { IndexPaths.make(section: section, row: item) }

    @ObjCMethod("section") func section() -> Int { Int(bitPattern: sendIndex(atPosition: 0)) }
    @ObjCMethod("row") func row() -> Int { Int(bitPattern: sendIndex(atPosition: 1)) }
    @ObjCMethod("item") func item() -> Int { Int(bitPattern: sendIndex(atPosition: 1)) }
}

extension NSObject {
    @ObjCMethod("indexPathWithIndexes:length:")
    func sendIndexPath(withIndexes indexes: UnsafePointer<UInt>, length: UInt) -> NSObject
    @ObjCMethod("indexAtPosition:") func sendIndex(atPosition position: UInt) -> UInt
    @ObjCMethod("section") func sendSection() -> Int
    @ObjCMethod("row") func sendRow() -> Int
}

// MARK: - Cells

final class CellState: ObjectState {
    var style = 0
    var reuseIdentifier: String?
    var contentView: UIView?
    var textLabel: UILabel?
    var detailTextLabel: UILabel?
    var imageView: UIImageView?
    var backgroundView: UIView?
    var selectedBackgroundView: UIView?
    var accessoryView: UIView?
    var accessoryType = 0
    /// A cell from a nib: its height as designed, which stands for the
    /// height its constraints would give it.
    var designHeight: CGFloat = 0
    /// UITableViewCellSelectionStyle: default 3.
    var selectionStyle = 3
    var selected = false
    var highlighted = false
    var editing = false
    var separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 0)
    var indentationLevel = 0
    var indentationWidth: CGFloat = 10
    var separator: UIView?
    /// The gray behind the content while highlighted or selected, unless
    /// the app gives a selected background view.
    var highlight: UIView?
    /// The background colors of the content's views, cleared while the
    /// cell shows highlighted.
    var clearedBackgrounds: [(view: UIView, color: UIColor)] = []
    /// A storyboard prototype's segues, performed when the cell or its
    /// accessory is tapped.
    var selectionSegueTemplate: UIStoryboardSegueTemplate?
    var accessoryActionSegueTemplate: UIStoryboardSegueTemplate?
}

@ObjCClass("UITableViewCell")
open class UITableViewCell: UIView {
    static let cellStates = StateTable<CellState>()
    var cell: CellState { UITableViewCell.cellStates[objcObject] }

    @ObjCMethod("initWithFrame:")
    override func initialize(frame: CGRect) -> Self {
        _ = super.initialize(frame: frame)
        setUp(style: 0, reuseIdentifier: nil)
        return self
    }

    @ObjCMethod("selectionSegueTemplate") func selectionSegueTemplate() -> UIStoryboardSegueTemplate? { cell.selectionSegueTemplate }
    @ObjCMethod("setSelectionSegueTemplate:")
    func setSelectionSegueTemplate(_ template: UIStoryboardSegueTemplate?) { cell.selectionSegueTemplate = template }
    @ObjCMethod("accessoryActionSegueTemplate")
    func accessoryActionSegueTemplate() -> UIStoryboardSegueTemplate? { cell.accessoryActionSegueTemplate }
    @ObjCMethod("setAccessoryActionSegueTemplate:")
    func setAccessoryActionSegueTemplate(_ template: UIStoryboardSegueTemplate?) { cell.accessoryActionSegueTemplate = template }

    /// A cell 320 by 44 points, until the table sizes it.
    @ObjCMethod("initWithStyle:reuseIdentifier:")
    func initialize(style: Int, reuseIdentifier: String?) -> NSObject {
        let cell = initializeView(frame: CGRect(x: 0, y: 0, width: 320, height: 44)).unsafeCast(to: UITableViewCell.self)
        cell.setUp(style: style, reuseIdentifier: reuseIdentifier)
        return cell
    }

    /// From a nib: the content view and labels it decoded, the reuse
    /// identifier, the accessory and the selection style.
    @ObjCMethod("initWithCoder:")
    override func initialize(coder: NSObject) -> Self {
        _ = super.initialize(coder: coder)
        let decoded = Coder(coder: coder)
        let cell = cell
        cell.style = decoded.integer("UITableViewCellStyle")
        cell.designHeight = state.bounds.height
        cell.reuseIdentifier = decoded.string("UIReuseIdentifier")
        cell.contentView = decoded.object("UIContentView")?.as(UIView.self)
        cell.textLabel = decoded.object("UITextLabel")?.as(UILabel.self)
        cell.detailTextLabel = decoded.object("UIDetailTextLabel")?.as(UILabel.self)
        cell.imageView = decoded.object("UIImageView")?.as(UIImageView.self)
        cell.accessoryType = decoded.integer("UIAccessoryType")
        if decoded.has("UISelectionStyle") { cell.selectionStyle = decoded.integer("UISelectionStyle") }
        if cell.contentView == nil { setUp(style: cell.style, reuseIdentifier: cell.reuseIdentifier) }
        if state.backgroundColor == nil { setBackgroundColor(UIColor.systemBackground()) }
        return self
    }

    /// The width the accessory takes from the content view.
    var accessoryWidth: CGFloat { cell.accessoryView.map { $0.state.bounds.width + 16 } ?? (cell.accessoryType != 0 ? 38 : 0) }

    func setUp(style: Int, reuseIdentifier: String?) {
        let cell = cell
        cell.style = style
        cell.reuseIdentifier = reuseIdentifier
        if cell.contentView == nil {
            let content = UITableViewCellContentView.objCClass.object.allocated().initializeView(frame: state.bounds)
                .unsafeCast(to: UIView.self)
            cell.contentView = content
            addSubview(content)
        }
        setBackgroundColor(UIColor.systemBackground())
    }

    @ObjCMethod("dealloc")
    override func dealloc() {
        UITableViewCell.cellStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCMethod("reuseIdentifier") func reuseIdentifier() -> String? { cell.reuseIdentifier }
    @ObjCMethod("contentView") func contentView() -> UIView? { cell.contentView }

    /// Made on first use, in the content view.
    @ObjCMethod("textLabel")
    func textLabel() -> UILabel? {
        if let label = cell.textLabel { return label }
        let label = makeLabel()
        cell.textLabel = label
        return label
    }

    /// Only the styles with a second line or value have one.
    @ObjCMethod("detailTextLabel")
    func detailTextLabel() -> UILabel? {
        guard cell.style != 0 else { return nil }
        if let label = cell.detailTextLabel { return label }
        let label = makeLabel()
        label.setTextColor(UIColor.secondaryLabel())
        cell.detailTextLabel = label
        return label
    }

    @ObjCMethod("imageView")
    func imageView() -> UIImageView? {
        if let view = cell.imageView { return view }
        let view = UIImageView.objCClass.object.allocated().initializeView(frame: .zero).unsafeCast(to: UIImageView.self)
        cell.imageView = view
        cell.contentView?.addSubview(view)
        return view
    }

    private func makeLabel() -> UILabel {
        let label = UILabel.objCClass.object.allocated().initializeView(frame: .zero).unsafeCast(to: UILabel.self)
        cell.contentView?.addSubview(label)
        setNeedsLayout()
        return label
    }

    @ObjCMethod("backgroundView") func backgroundView() -> UIView? { cell.backgroundView }
    @ObjCMethod("setBackgroundView:") func setBackgroundView(_ view: UIView?) {
        cell.backgroundView?.removeFromSuperview()
        cell.backgroundView = view
        if let view { insertSubview(view, at: 0) }
    }
    @ObjCMethod("selectedBackgroundView") func selectedBackgroundView() -> UIView? { cell.selectedBackgroundView }
    @ObjCMethod("setSelectedBackgroundView:") func setSelectedBackgroundView(_ view: UIView?) { cell.selectedBackgroundView = view }
    @ObjCMethod("accessoryType") func accessoryType() -> Int { cell.accessoryType }
    @ObjCMethod("setAccessoryType:") func setAccessoryType(_ type: Int) { cell.accessoryType = type; setNeedsLayout() }
    @ObjCMethod("accessoryView") func accessoryView() -> UIView? { cell.accessoryView }
    @ObjCMethod("setAccessoryView:") func setAccessoryView(_ view: UIView?) {
        cell.accessoryView?.removeFromSuperview()
        cell.accessoryView = view
        if let view { addSubview(view) }
        setNeedsLayout()
    }
    @ObjCMethod("selectionStyle") func selectionStyle() -> Int { cell.selectionStyle }
    @ObjCMethod("setSelectionStyle:") func setSelectionStyle(_ style: Int) { cell.selectionStyle = style }
    @ObjCMethod("isSelected") func isSelected() -> Bool { cell.selected }
    @ObjCMethod("setSelected:") func setSelected(_ selected: Bool) { sendSetSelected(selected, animated: false) }
    @ObjCMethod("setSelected:animated:")
    func setSelected(_ selected: Bool, animated: Bool) {
        cell.selected = selected
        showSelection()
    }
    @ObjCMethod("isHighlighted") func isHighlighted() -> Bool { cell.highlighted }
    @ObjCMethod("setHighlighted:") func setHighlighted(_ highlighted: Bool) { sendSetHighlighted(highlighted, animated: false) }
    @ObjCMethod("setHighlighted:animated:")
    func setHighlighted(_ highlighted: Bool, animated: Bool) {
        cell.highlighted = highlighted
        showSelection()
    }

    /// Shows the selected background behind the content while the cell is
    /// highlighted or selected, unless its selection style is none.
    private func showSelection() {
        let cell = cell
        let shown = (cell.selected || cell.highlighted) && cell.selectionStyle != 0
        let background: UIView
        if let custom = cell.selectedBackgroundView {
            background = custom
        } else {
            if cell.highlight == nil {
                let view = UIView.objCClass.object.allocated().initializeView(frame: state.bounds).unsafeCast(to: UIView.self)
                view.setBackgroundColor(UIColor.systemGray4())
                cell.highlight = view
            }
            background = cell.highlight!
        }
        if shown {
            if background.state.superview != objcObject { insertSubview(background, at: cell.backgroundView == nil ? 0 : 1) }
            background.sendSetFrame(state.bounds)
        } else {
            background.removeFromSuperview()
        }
        if let contentView = cell.contentView { showContent(highlighted: shown, contentView) }
    }

    /// While highlighted, the content's labels and image views outside
    /// controls show their highlighted colors and images, and its views'
    /// background colors are cleared so the selection shows through, as
    /// UIKit does; then they are as they were.
    private func showContent(highlighted: Bool, _ contentView: UIView) {
        let cell = cell
        if !highlighted {
            for (view, color) in cell.clearedBackgrounds { view.setBackgroundColor(color) }
            cell.clearedBackgrounds = []
        } else if cell.clearedBackgrounds.isEmpty {
            func clear(_ view: UIView) {
                for subview in view.state.subviews where !subview.is(UIControl.self) {
                    if let color = subview.state.backgroundColor, color.state.alpha > 0 {
                        cell.clearedBackgrounds.append((subview, color))
                        subview.setBackgroundColor(UIColor.clear())
                    }
                    clear(subview)
                }
            }
            clear(contentView)
        }
        func highlight(_ view: UIView) {
            for subview in view.state.subviews where !subview.is(UIControl.self) {
                if subview.is(UILabel.self) || subview.is(UIImageView.self) { subview.sendHighlighted(highlighted) }
                highlight(subview)
            }
        }
        highlight(contentView)
    }
    @ObjCMethod("isEditing") func isEditing() -> Bool { cell.editing }
    @ObjCMethod("setEditing:") func setEditing(_ editing: Bool) { cell.editing = editing }
    @ObjCMethod("setEditing:animated:") func setEditing(_ editing: Bool, animated: Bool) { cell.editing = editing }
    @ObjCMethod("separatorInset") func separatorInset() -> UIEdgeInsets { cell.separatorInset }
    @ObjCMethod("setSeparatorInset:") func setSeparatorInset(_ inset: UIEdgeInsets) { cell.separatorInset = inset }
    @ObjCMethod("indentationLevel") func indentationLevel() -> Int { cell.indentationLevel }
    @ObjCMethod("setIndentationLevel:") func setIndentationLevel(_ level: Int) { cell.indentationLevel = level }
    @ObjCMethod("indentationWidth") func indentationWidth() -> CGFloat { cell.indentationWidth }
    @ObjCMethod("setIndentationWidth:") func setIndentationWidth(_ width: CGFloat) { cell.indentationWidth = width }

    /// Clears the selection and highlight before the cell is used again.
    @ObjCMethod("prepareForReuse")
    func prepareForReuse() {
        cell.selected = false
        cell.highlighted = false
        showSelection()
    }

    /// The content view fills the cell, less an accessory; labels sit
    /// inside the margins, a value at the trailing edge or below.
    @ObjCMethod("layoutSubviews")
    override func layoutSubviews() {
        let bounds = state.bounds
        let accessoryWidth = self.accessoryWidth
        let content = CGRect(x: 0, y: 0, width: bounds.width - accessoryWidth, height: bounds.height)
        cell.contentView?.sendSetFrame(content)
        cell.backgroundView?.sendSetFrame(bounds)
        if let accessory = cell.accessoryView {
            let size = accessory.state.bounds.size
            accessory.sendSetFrame(CGRect(x: bounds.width - 16 - size.width, y: (bounds.height - size.height) / 2,
                                          width: size.width, height: size.height))
        }
        // A hairline along the bottom, from the separator inset.
        if cell.separator == nil {
            let line = UIView.objCClass.object.allocated().initializeView(frame: .zero).unsafeCast(to: UIView.self)
            line.setBackgroundColor(UIColor.separator())
            cell.separator = line
            addSubview(line)
        }
        let hairline = Screen.pixel
        cell.separator?.sendSetFrame(CGRect(x: cell.separatorInset.left, y: bounds.height - hairline,
                                            width: max(bounds.width - cell.separatorInset.left - cell.separatorInset.right, 0),
                                            height: hairline))
        var x: CGFloat = 16
        if let image = cell.imageView, let size = image.imageState.image?.state.size {
            image.sendSetFrame(CGRect(x: 16, y: (bounds.height - size.height) / 2, width: size.width, height: size.height))
            x += size.width + 16
        }
        let width = max(content.width - x - 16, 0)
        switch (cell.style, cell.textLabel, cell.detailTextLabel) {
        case (3, let text?, let detail?):
            text.sendSetFrame(CGRect(x: x, y: content.height / 2 - 21, width: width, height: 21))
            detail.sendSetFrame(CGRect(x: x, y: content.height / 2, width: width, height: 18))
        case (1, let text, let detail?):
            text?.sendSetFrame(CGRect(x: x, y: 0, width: width, height: content.height))
            detail.setTextAlignment(2)
            detail.sendSetFrame(CGRect(x: x, y: 0, width: width, height: content.height))
        case (_, let text?, _):
            text.sendSetFrame(CGRect(x: x, y: 0, width: width, height: content.height))
        default:
            break
        }
    }
}

/// Its margins are a cell's: 11 points above and below, 16 at the sides.
@ObjCClass("UITableViewCellContentView")
open class UITableViewCellContentView: UIView {
    @ObjCMethod("layoutMargins")
    override func layoutMargins() -> UIEdgeInsets { UIEdgeInsets(top: 11, left: 16, bottom: 11, right: 16) }
}

extension NSObject {
    @ObjCMethod("setSelected:animated:") func sendSetSelected(_ selected: Bool, animated: Bool)
    @ObjCMethod("setHighlighted:animated:") func sendSetHighlighted(_ highlighted: Bool, animated: Bool)
    @ObjCMethod("prepareForReuse") func sendPrepareForReuse()
}

// MARK: - Header and footer views

final class HeaderFooterState: ObjectState {
    var reuseIdentifier: String?
    var contentView: UIView?
    var textLabel: UILabel?
    var detailTextLabel: UILabel?
    var backgroundView: UIView?
}

@ObjCClass("UITableViewHeaderFooterView")
open class UITableViewHeaderFooterView: UIView {
    static let headerStates = StateTable<HeaderFooterState>()
    var header: HeaderFooterState { UITableViewHeaderFooterView.headerStates[objcObject] }

    @ObjCMethod("initWithReuseIdentifier:")
    func initialize(reuseIdentifier: String?) -> NSObject {
        let view = initializeView(frame: .zero).unsafeCast(to: UITableViewHeaderFooterView.self)
        view.header.reuseIdentifier = reuseIdentifier
        return view
    }

    @ObjCMethod("initWithFrame:")
    override func initialize(frame: CGRect) -> Self {
        _ = super.initialize(frame: frame)
        let content = UIView.objCClass.object.allocated().initializeView(frame: state.bounds).unsafeCast(to: UIView.self)
        header.contentView = content
        addSubview(content)
        setBackgroundColor(UIColor.systemGray6())
        return self
    }

    @ObjCMethod("dealloc")
    override func dealloc() {
        UITableViewHeaderFooterView.headerStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCMethod("reuseIdentifier") func reuseIdentifier() -> String? { header.reuseIdentifier }
    @ObjCMethod("contentView") func contentView() -> UIView? { header.contentView }
    @ObjCMethod("backgroundView") func backgroundView() -> UIView? { header.backgroundView }
    @ObjCMethod("setBackgroundView:") func setBackgroundView(_ view: UIView?) { header.backgroundView = view }

    @ObjCMethod("textLabel")
    func textLabel() -> UILabel? {
        if let label = header.textLabel { return label }
        let label = UILabel.objCClass.object.allocated().initializeView(frame: .zero).unsafeCast(to: UILabel.self)
        label.setFont(UIFont.boldSystemFont(size: 17))
        header.textLabel = label
        header.contentView?.addSubview(label)
        return label
    }

    @ObjCMethod("detailTextLabel") func detailTextLabel() -> UILabel? { nil }
    @ObjCMethod("prepareForReuse") func prepareForReuse() {}

    @ObjCMethod("layoutSubviews")
    override func layoutSubviews() {
        let bounds = state.bounds
        header.contentView?.sendSetFrame(bounds)
        header.backgroundView?.sendSetFrame(bounds)
        header.textLabel?.sendSetFrame(CGRect(x: 16, y: 0, width: max(bounds.width - 32, 0), height: bounds.height))
    }
}

// MARK: - The table

/// The table's geometry: each section's header, rows and footer.
struct TableLayout {
    struct Section {
        var header: CGRect
        var rows: [CGRect]
        var footer: CGRect
        var rect: CGRect { CGRect(x: header.minX, y: header.minY, width: header.width, height: footer.maxY - header.minY) }
    }

    var sections: [Section] = []
    var height: CGFloat = 0
}

final class TableState: ObjectState {
    var style = 0
    var dataSource: UnsafeMutableRawPointer?
    var rowHeight: CGFloat = -1
    var estimatedRowHeight: CGFloat = -1
    var sectionHeaderHeight: CGFloat = -1
    var estimatedSectionHeaderHeight: CGFloat = -1
    var sectionFooterHeight: CGFloat = -1
    var estimatedSectionFooterHeight: CGFloat = -1
    var sectionHeaderTopPadding: CGFloat = -1
    var separatorStyle = 1
    var separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 0)
    var separatorColor: UIColor?
    var allowsSelection = true
    var allowsMultipleSelection = false
    var allowsSelectionDuringEditing = false
    var editing = false
    var cellClasses: [String: ObjCClass] = [:]
    /// Nibs cells are made from, with what their placeholders stand for.
    var cellNibs: [String: (nib: UINib, external: [String: NSObject])] = [:]
    var headerClasses: [String: ObjCClass] = [:]
    var reusableCells: [String: [UITableViewCell]] = [:]
    var reusableHeaders: [String: [UIView]] = [:]
    var visibleCells: [RowPath: UITableViewCell] = [:]
    var visibleHeaders: [Int: UIView] = [:]
    /// Header views asked for to measure, until they are shown.
    var headerViews: [Int: UIView] = [:]
    var selected: Set<RowPath> = []
    var tableHeaderView: UIView?
    var tableFooterView: UIView?
    var backgroundView: UIView?
    var layout: TableLayout?
    /// The width the layout was computed at.
    var layoutWidth: CGFloat = 0
    /// Rows the delegate leaves to size themselves (UITableViewAutomaticDimension),
    /// and the heights their cells have given them.
    var automaticRows: Set<RowPath> = []
    var measuredHeights: [RowPath: CGFloat] = [:]
    var updating = 0
}

@ObjCClass("UITableView")
open class UITableView: UIScrollView {
    static let tableStates = StateTable<TableState>()
    var table: TableState { UITableView.tableStates[objcObject] }

    @ObjCMethod("initWithFrame:")
    override func initialize(frame: CGRect) -> Self {
        _ = super.initialize(frame: frame)
        setBackgroundColor(UIColor.systemBackground())
        return self
    }

    /// From a nib: the style, heights, header and footer, and the
    /// prototype cells' nibs, registered by reuse identifier.
    @ObjCMethod("initWithCoder:")
    override func initialize(coder: NSObject) -> Self {
        _ = super.initialize(coder: coder)
        let decoded = Coder(coder: coder)
        let table = table
        table.style = decoded.integer("UIStyle")
        if decoded.has("UIRowHeight") { table.rowHeight = decoded.double("UIRowHeight") }
        if decoded.has("UISectionHeaderHeight") { table.sectionHeaderHeight = decoded.double("UISectionHeaderHeight") }
        if decoded.has("UISectionFooterHeight") { table.sectionFooterHeight = decoded.double("UISectionFooterHeight") }
        if decoded.has("UIEstimatedRowHeight") { table.estimatedRowHeight = decoded.double("UIEstimatedRowHeight") }
        if decoded.has("UISeparatorStyle") { table.separatorStyle = decoded.integer("UISeparatorStyle") }
        table.allowsMultipleSelection = decoded.bool("UIAllowsMultipleSelection")
        if decoded.has("UIAllowsSelection") { table.allowsSelection = decoded.bool("UIAllowsSelection") }
        let external = decoded.dictionary("UITableViewCellPrototypeNibExternalObjects")
        for (identifier, nib) in decoded.dictionary("UITableViewCellPrototypeNibs") {
            guard let nib = nib.as(UINib.self) else { continue }
            table.cellNibs[identifier] = (nib, Nibs.strings(external[identifier]))
        }
        if let header = decoded.object("UITableHeaderView")?.as(UIView.self) { setTableHeaderView(header) }
        if let footer = decoded.object("UITableFooterView")?.as(UIView.self) { setTableFooterView(footer) }
        if state.backgroundColor == nil { setBackgroundColor(UIColor.systemBackground()) }
        return self
    }

    @ObjCMethod("initWithFrame:style:")
    func initialize(frame: CGRect, style: Int) -> NSObject {
        let table = initializeView(frame: frame).unsafeCast(to: UITableView.self)
        table.table.style = style
        if style != 0 { table.setBackgroundColor(UIColor.systemGroupedBackground()) }
        return table
    }

    @ObjCMethod("dealloc")
    override func dealloc() {
        UITableView.tableStates.remove(objcObject)
        super.dealloc()
    }

    // MARK: Properties

    @ObjCMethod("style") func style() -> Int { table.style }
    @ObjCMethod("dataSource") func dataSource() -> NSObject? { table.dataSource.map { NSObject($0) } }
    @ObjCMethod("setDataSource:") func setDataSource(_ source: NSObject?) {
        table.dataSource = source?.objcObject
        invalidate()
    }

    @ObjCMethod("setDelegate:")
    override func setDelegate(_ delegate: NSObject?) {
        scroll.delegate.object = delegate?.objcObject
        invalidate()
    }

    @ObjCMethod("rowHeight") func rowHeight() -> CGFloat { table.rowHeight }
    @ObjCMethod("setRowHeight:") func setRowHeight(_ height: CGFloat) { table.rowHeight = height; invalidate() }
    @ObjCMethod("estimatedRowHeight") func estimatedRowHeight() -> CGFloat { table.estimatedRowHeight }
    @ObjCMethod("setEstimatedRowHeight:") func setEstimatedRowHeight(_ height: CGFloat) { table.estimatedRowHeight = height }
    @ObjCMethod("sectionHeaderHeight") func sectionHeaderHeight() -> CGFloat { table.sectionHeaderHeight }
    @ObjCMethod("setSectionHeaderHeight:") func setSectionHeaderHeight(_ height: CGFloat) { table.sectionHeaderHeight = height; invalidate() }
    @ObjCMethod("estimatedSectionHeaderHeight") func estimatedSectionHeaderHeight() -> CGFloat { table.estimatedSectionHeaderHeight }
    @ObjCMethod("setEstimatedSectionHeaderHeight:") func setEstimatedSectionHeaderHeight(_ height: CGFloat) {
        table.estimatedSectionHeaderHeight = height
    }
    @ObjCMethod("sectionFooterHeight") func sectionFooterHeight() -> CGFloat { table.sectionFooterHeight }
    @ObjCMethod("setSectionFooterHeight:") func setSectionFooterHeight(_ height: CGFloat) { table.sectionFooterHeight = height; invalidate() }
    @ObjCMethod("estimatedSectionFooterHeight") func estimatedSectionFooterHeight() -> CGFloat { table.estimatedSectionFooterHeight }
    @ObjCMethod("setEstimatedSectionFooterHeight:") func setEstimatedSectionFooterHeight(_ height: CGFloat) {
        table.estimatedSectionFooterHeight = height
    }
    @ObjCMethod("sectionHeaderTopPadding") func sectionHeaderTopPadding() -> CGFloat { table.sectionHeaderTopPadding }
    @ObjCMethod("setSectionHeaderTopPadding:") func setSectionHeaderTopPadding(_ padding: CGFloat) {
        table.sectionHeaderTopPadding = padding
        invalidate()
    }
    @ObjCMethod("separatorStyle") func separatorStyle() -> Int { table.separatorStyle }
    @ObjCMethod("setSeparatorStyle:") func setSeparatorStyle(_ style: Int) { table.separatorStyle = style }
    @ObjCMethod("separatorInset") func separatorInset() -> UIEdgeInsets { table.separatorInset }
    @ObjCMethod("setSeparatorInset:") func setSeparatorInset(_ inset: UIEdgeInsets) { table.separatorInset = inset }
    @ObjCMethod("separatorColor") func separatorColor() -> UIColor { table.separatorColor ?? UIColor.separator() }
    @ObjCMethod("setSeparatorColor:") func setSeparatorColor(_ color: UIColor?) { table.separatorColor = color }
    @ObjCMethod("allowsSelection") func allowsSelection() -> Bool { table.allowsSelection }
    @ObjCMethod("setAllowsSelection:") func setAllowsSelection(_ allows: Bool) { table.allowsSelection = allows }
    @ObjCMethod("allowsMultipleSelection") func allowsMultipleSelection() -> Bool { table.allowsMultipleSelection }
    @ObjCMethod("setAllowsMultipleSelection:") func setAllowsMultipleSelection(_ allows: Bool) { table.allowsMultipleSelection = allows }
    @ObjCMethod("allowsSelectionDuringEditing") func allowsSelectionDuringEditing() -> Bool { table.allowsSelectionDuringEditing }
    @ObjCMethod("setAllowsSelectionDuringEditing:") func setAllowsSelectionDuringEditing(_ allows: Bool) {
        table.allowsSelectionDuringEditing = allows
    }
    @ObjCMethod("allowsMultipleSelectionDuringEditing") func allowsMultipleSelectionDuringEditing() -> Bool { false }
    @ObjCMethod("setAllowsMultipleSelectionDuringEditing:") func setAllowsMultipleSelectionDuringEditing(_ allows: Bool) {}
    @ObjCMethod("isEditing") func isEditing() -> Bool { table.editing }
    @ObjCMethod("setEditing:") func setEditing(_ editing: Bool) { table.editing = editing }
    @ObjCMethod("setEditing:animated:") func setEditing(_ editing: Bool, animated: Bool) { table.editing = editing }
    @ObjCMethod("cellLayoutMarginsFollowReadableWidth") func cellLayoutMarginsFollowReadableWidth() -> Bool { false }
    @ObjCMethod("setCellLayoutMarginsFollowReadableWidth:") func setCellLayoutMarginsFollowReadableWidth(_ follows: Bool) {}
    @ObjCMethod("remembersLastFocusedIndexPath") func remembersLastFocusedIndexPath() -> Bool { false }
    @ObjCMethod("setRemembersLastFocusedIndexPath:") func setRemembersLastFocusedIndexPath(_ remembers: Bool) {}
    @ObjCMethod("prefetchDataSource") func prefetchDataSource() -> NSObject? { nil }
    @ObjCMethod("setPrefetchDataSource:") func setPrefetchDataSource(_ source: NSObject?) {}
    @ObjCMethod("dragInteractionEnabled") func dragInteractionEnabled() -> Bool { false }
    @ObjCMethod("setDragInteractionEnabled:") func setDragInteractionEnabled(_ enabled: Bool) {}

    @ObjCMethod("backgroundView") func backgroundView() -> UIView? { table.backgroundView }
    @ObjCMethod("setBackgroundView:") func setBackgroundView(_ view: UIView?) { table.backgroundView = view }

    @ObjCMethod("tableHeaderView") func tableHeaderView() -> UIView? { table.tableHeaderView }

    @ObjCMethod("setTableHeaderView:")
    func setTableHeaderView(_ view: UIView?) {
        table.tableHeaderView?.removeFromSuperview()
        table.tableHeaderView = view
        if let view { addSubview(view) }
        invalidate()
    }

    @ObjCMethod("tableFooterView") func tableFooterView() -> UIView? { table.tableFooterView }

    @ObjCMethod("setTableFooterView:")
    func setTableFooterView(_ view: UIView?) {
        table.tableFooterView?.removeFromSuperview()
        table.tableFooterView = view
        if let view { addSubview(view) }
        invalidate()
    }

    // MARK: Registration and reuse

    @ObjCMethod("registerClass:forCellReuseIdentifier:")
    func register(_ cls: ObjCClass?, forCellReuseIdentifier identifier: String) { table.cellClasses[identifier] = cls }

    @ObjCMethod("registerNib:forCellReuseIdentifier:")
    func register(nib: NSObject?, forCellReuseIdentifier identifier: String) {
        table.cellNibs[identifier] = nib?.as(UINib.self).map { ($0, [:]) }
    }

    @ObjCMethod("registerClass:forHeaderFooterViewReuseIdentifier:")
    func register(_ cls: ObjCClass?, forHeaderFooterViewReuseIdentifier identifier: String) { table.headerClasses[identifier] = cls }

    /// A cell from the pool, prepared for reuse, or a new one of the
    /// registered class; nil without either.
    @ObjCMethod("dequeueReusableCellWithIdentifier:")
    func dequeueReusableCell(identifier: String) -> UITableViewCell? {
        if let cell = table.reusableCells[identifier]?.popLast() {
            cell.sendPrepareForReuse()
            return cell
        }
        if let (nib, external) = table.cellNibs[identifier] {
            return nib.instantiate(owner: nil, external: external).first { $0.is(UITableViewCell.self) }?
                .unsafeCast(to: UITableViewCell.self)
        }
        guard let cls = table.cellClasses[identifier] else { return nil }
        return cls.object.allocated().initializeCell(style: 0, reuseIdentifier: identifier).unsafeCast(to: UITableViewCell.self)
    }

    @ObjCMethod("dequeueReusableCellWithIdentifier:forIndexPath:")
    func dequeueReusableCell(identifier: String, for indexPath: NSObject) -> UITableViewCell {
        guard let cell = dequeueReusableCell(identifier: identifier) else {
            uikitFatal("unable to dequeue a cell with identifier \(identifier) - must register a nib or a class for the identifier")
        }
        return cell
    }

    @ObjCMethod("dequeueReusableHeaderFooterViewWithIdentifier:")
    func dequeueReusableHeaderFooterView(identifier: String) -> UIView? {
        if let view = table.reusableHeaders[identifier]?.popLast() { return view }
        guard let cls = table.headerClasses[identifier] else { return nil }
        return cls.object.allocated().initializeHeaderFooter(reuseIdentifier: identifier).unsafeCast(to: UIView.self)
    }

    // MARK: Data

    private var source: NSObject? { dataSource() }

    /// The geometry, computed from the data source and delegate when the
    /// data, heights or width change.
    var layout: TableLayout {
        let width = state.bounds.width
        if let layout = table.layout, table.layoutWidth == width { return layout }
        let layout = computeLayout()
        table.layout = layout
        table.layoutWidth = width
        let size = CGSize(width: state.bounds.width, height: layout.height)
        if scroll.contentSize != size { scroll.contentSize = size }
        return layout
    }

    private func invalidate() {
        table.layout = nil
        setNeedsLayout()
    }

    private func computeLayout() -> TableLayout {
        let width = state.bounds.width
        var y: CGFloat = table.tableHeaderView?.state.bounds.height ?? 0
        var layout = TableLayout()
        let source = source, delegate = delegate()
        table.automaticRows = []
        let sections = source.map { $0.responds(to: "numberOfSectionsInTableView:") ? $0.sendNumberOfSections(in: self) : 1 } ?? 0
        for section in 0..<max(sections, 0) {
            let header = headerHeight(section, source: source, delegate: delegate)
            let padding = header > 0 && table.sectionHeaderTopPadding > 0 ? table.sectionHeaderTopPadding : 0
            y += padding
            let headerRect = CGRect(x: 0, y: y, width: width, height: header)
            y += header
            let count = source?.sendTableView(self, numberOfRowsInSection: section) ?? 0
            var rows: [CGRect] = []
            rows.reserveCapacity(count)
            let asks = delegate?.responds(to: "tableView:heightForRowAtIndexPath:") ?? false
            for row in 0..<max(count, 0) {
                var height = asks ? delegate!.sendTableView(self, heightForRowAt: IndexPaths.make(section: section, row: row))
                    : table.rowHeight
                if height < 0 {
                    let path = RowPath(section: section, row: row)
                    table.automaticRows.insert(path)
                    height = table.measuredHeights[path] ?? automaticRowHeight
                }
                rows.append(CGRect(x: 0, y: y, width: width, height: height))
                y += height
            }
            let footer = footerHeight(section, source: source, delegate: delegate)
            let footerRect = CGRect(x: 0, y: y, width: width, height: footer)
            y += footer
            layout.sections.append(.init(header: headerRect, rows: rows, footer: footerRect))
        }
        layout.height = y + (table.tableFooterView?.state.bounds.height ?? 0)
        return layout
    }

    /// UITableViewAutomaticDimension's height until the row's cell is made:
    /// the estimate, else the standard row height.
    private var automaticRowHeight: CGFloat { table.estimatedRowHeight > 0 ? table.estimatedRowHeight : 44 }

    /// The delegate's height, else the table's when the section has a
    /// header, else none.
    private func headerHeight(_ section: Int, source: NSObject?, delegate: NSObject?) -> CGFloat {
        if let delegate, delegate.responds(to: "tableView:heightForHeaderInSection:") {
            let height = delegate.sendTableView(self, heightForHeaderInSection: section)
            if height >= 0 { return height }
        }
        guard hasHeader(section, source: source, delegate: delegate) else { return 0 }
        if table.sectionHeaderHeight >= 0 { return table.sectionHeaderHeight }
        // UITableViewAutomaticDimension: the delegate's view, sized by its
        // constraints, which is kept to be shown.
        if let delegate, delegate.responds(to: "tableView:viewForHeaderInSection:"),
           let view = table.headerViews[section] ?? delegate.sendTableView(self, viewForHeaderInSection: section) {
            table.headerViews[section] = view
            let measured = view.as(UITableViewCell.self)?.cell.contentView ?? view
            if let height = AutoLayout.fittingHeight(measured, width: state.bounds.width) { return height }
        }
        return 28
    }

    private func footerHeight(_ section: Int, source: NSObject?, delegate: NSObject?) -> CGFloat {
        if let delegate, delegate.responds(to: "tableView:heightForFooterInSection:") {
            let height = delegate.sendTableView(self, heightForFooterInSection: section)
            if height >= 0 { return height }
        }
        guard footerTitle(section, source: source) != nil
                || (delegate?.responds(to: "tableView:viewForFooterInSection:") ?? false) else { return 0 }
        return table.sectionFooterHeight >= 0 ? table.sectionFooterHeight : 28
    }

    private func hasHeader(_ section: Int, source: NSObject?, delegate: NSObject?) -> Bool {
        headerTitle(section, source: source) != nil || (delegate?.responds(to: "tableView:viewForHeaderInSection:") ?? false)
    }

    private func headerTitle(_ section: Int, source: NSObject?) -> String? {
        guard let source, source.responds(to: "tableView:titleForHeaderInSection:") else { return nil }
        return source.sendTableView(self, titleForHeaderInSection: section)
    }

    private func footerTitle(_ section: Int, source: NSObject?) -> String? {
        guard let source, source.responds(to: "tableView:titleForFooterInSection:") else { return nil }
        return source.sendTableView(self, titleForFooterInSection: section)
    }

    @ObjCMethod("numberOfSections") func numberOfSections() -> Int { layout.sections.count }

    @ObjCMethod("numberOfRowsInSection:")
    func numberOfRows(inSection section: Int) -> Int {
        let sections = layout.sections
        return sections.indices.contains(section) ? sections[section].rows.count : 0
    }

    private func rect(_ path: RowPath) -> CGRect? {
        let sections = layout.sections
        guard sections.indices.contains(path.section), sections[path.section].rows.indices.contains(path.row) else { return nil }
        return sections[path.section].rows[path.row]
    }

    @ObjCMethod("rectForRowAtIndexPath:")
    func rectForRow(at indexPath: NSObject) -> CGRect { rect(RowPath(indexPath)) ?? .zero }

    @ObjCMethod("rectForSection:")
    func rectForSection(_ section: Int) -> CGRect {
        let sections = layout.sections
        return sections.indices.contains(section) ? sections[section].rect : .zero
    }

    @ObjCMethod("rectForHeaderInSection:")
    func rectForHeader(inSection section: Int) -> CGRect {
        let sections = layout.sections
        return sections.indices.contains(section) ? sections[section].header : .zero
    }

    @ObjCMethod("rectForFooterInSection:")
    func rectForFooter(inSection section: Int) -> CGRect {
        let sections = layout.sections
        return sections.indices.contains(section) ? sections[section].footer : .zero
    }

    @ObjCMethod("indexPathForRowAtPoint:")
    func indexPathForRow(at point: CGPoint) -> NSObject? {
        for (section, layout) in layout.sections.enumerated() {
            for (row, rect) in layout.rows.enumerated() where rect.contains(point) {
                return IndexPaths.make(section: section, row: row)
            }
        }
        return nil
    }

    @ObjCMethod("indexPathsForRowsInRect:")
    func indexPathsForRows(in rect: CGRect) -> NSObject {
        NSMutableArray.of(rows(in: rect).map(\.object))
    }

    private func rows(in rect: CGRect) -> [RowPath] {
        var paths: [RowPath] = []
        for (section, layout) in layout.sections.enumerated() where layout.rect.intersects(rect) || layout.rows.isEmpty {
            for (row, frame) in layout.rows.enumerated() where frame.height > 0 && frame.intersects(rect) {
                paths.append(RowPath(section: section, row: row))
            }
        }
        return paths
    }

    @ObjCMethod("cellForRowAtIndexPath:")
    func cellForRow(at indexPath: NSObject) -> UITableViewCell? { table.visibleCells[RowPath(indexPath)] }

    @ObjCMethod("indexPathForCell:")
    func indexPath(for cell: UITableViewCell) -> NSObject? {
        table.visibleCells.first { $0.value.objcObject == cell.objcObject }?.key.object
    }

    @ObjCMethod("visibleCells")
    func visibleCells() -> NSObject { NSMutableArray.of(table.visibleCells.sorted { $0.key < $1.key }.map(\.value)) }

    @ObjCMethod("indexPathsForVisibleRows")
    func indexPathsForVisibleRows() -> NSObject? { NSMutableArray.of(table.visibleCells.keys.sorted().map(\.object)) }

    @ObjCMethod("headerViewForSection:") func headerView(forSection section: Int) -> UIView? { table.visibleHeaders[section] }
    @ObjCMethod("footerViewForSection:") func footerView(forSection section: Int) -> UIView? { nil }

    // MARK: Layout

    /// Applies the insets, then shows a cell for each row in view and a
    /// header for each section in view, floating headers in the plain
    /// style; cells that left the view go to their pools afterwards.
    @ObjCMethod("layoutSubviews")
    override func layoutSubviews() {
        applyAdjustedInset()
        let layout = layout
        let bounds = state.bounds
        layOutTableViews(layout)

        let wanted = Set(rows(in: bounds))
        let delegate = delegate()
        for path in wanted.sorted() where table.visibleCells[path] == nil {
            guard let cell = source?.sendTableView(self, cellForRowAt: path.object) else {
                uikitFatal("UITableView dataSource returned a nil cell for row at index path: \(path.section).\(path.row)")
            }
            measure(cell, at: path)
            show(cell, at: path)
            if let delegate, delegate.responds(to: "tableView:willDisplayCell:forRowAtIndexPath:") {
                delegate.sendTableView(self, willDisplay: cell, forRowAt: path.object)
            }
        }
        // Rows that sized themselves move the rows after them: lay out again.
        if table.layout == nil {
            layoutSubviews()
            return
        }
        for (path, cell) in table.visibleCells where !wanted.contains(path) {
            table.visibleCells[path] = nil
            enqueue(cell)
            if let delegate, delegate.responds(to: "tableView:didEndDisplayingCell:forRowAtIndexPath:") {
                delegate.sendTableView(self, didEndDisplaying: cell, forRowAt: path.object)
            }
        }
        for (path, cell) in table.visibleCells {
            if let frame = rect(path), cell.state.frame != frame { cell.sendSetFrame(frame) }
        }
        layOutHeaders(layout, bounds: bounds)
    }

    /// A self-sizing row takes the height its content view's constraints
    /// give it at the row's width, and the separator's; else the height the
    /// cell was designed at. The layout is redone if that changes it.
    private func measure(_ cell: UITableViewCell, at path: RowPath) {
        guard table.automaticRows.contains(path) else { return }
        var height = cell.cell.designHeight
        if let content = cell.cell.contentView {
            let width = state.bounds.width - cell.accessoryWidth
            if let fitting = AutoLayout.fittingHeight(content, width: width) { height = fitting + Screen.pixel }
        }
        guard height > 0, table.measuredHeights[path] != height else { return }
        let estimated = table.measuredHeights[path] ?? automaticRowHeight
        table.measuredHeights[path] = height
        if estimated != height { table.layout = nil }
    }

    private func show(_ cell: UITableViewCell, at path: RowPath) {
        table.visibleCells[path] = cell
        if cell.state.superview != objcObject {
            insertSubview(cell, at: 0)
        }
        cell.state.hidden = false
        if let frame = rect(path) { cell.sendSetFrame(frame) }
        if table.selected.contains(path) != cell.cell.selected { cell.sendSetSelected(table.selected.contains(path), animated: false) }
        cell.layoutIfNeeded()
    }

    /// Puts a cell in its pool, out of sight.
    private func enqueue(_ cell: UITableViewCell) {
        cell.state.hidden = true
        guard let identifier = cell.cell.reuseIdentifier else {
            cell.removeFromSuperview()
            return
        }
        table.reusableCells[identifier, default: []].append(cell)
    }

    private func layOutTableViews(_ layout: TableLayout) {
        let width = state.bounds.width
        if let header = table.tableHeaderView {
            header.sendSetFrame(CGRect(x: 0, y: 0, width: width, height: header.state.bounds.height))
        }
        if let footer = table.tableFooterView {
            let height = footer.state.bounds.height
            footer.sendSetFrame(CGRect(x: 0, y: layout.height - height, width: width, height: height))
        }
    }

    private func layOutHeaders(_ layout: TableLayout, bounds: CGRect) {
        let source = source, delegate = delegate()
        let top = bounds.minY + adjustedContentInset().top
        var wanted: [Int: CGRect] = [:]
        for (section, geometry) in layout.sections.enumerated() where geometry.header.height > 0 {
            var frame = geometry.header
            if table.style == 0 {
                frame.origin.y = min(max(frame.minY, top), geometry.rect.maxY - geometry.footer.height - frame.height)
                frame.origin.y = max(frame.minY, geometry.header.minY)
            }
            if frame.intersects(bounds) { wanted[section] = frame }
        }
        for (section, view) in table.visibleHeaders where wanted[section] == nil {
            table.visibleHeaders[section] = nil
            view.removeFromSuperview()
        }
        for (section, frame) in wanted.sorted(by: { $0.key < $1.key }) {
            let view: UIView
            if let shown = table.visibleHeaders[section] {
                view = shown
            } else if let delegate, delegate.responds(to: "tableView:viewForHeaderInSection:"),
                      let custom = table.headerViews.removeValue(forKey: section) ?? delegate.sendTableView(self, viewForHeaderInSection: section) {
                view = custom
                table.visibleHeaders[section] = view
            } else {
                let header = UITableViewHeaderFooterView.objCClass.object.allocated().initializeHeaderFooter(reuseIdentifier: nil)
                    .unsafeCast(to: UITableViewHeaderFooterView.self)
                header.textLabel()?.setText(headerTitle(section, source: source))
                view = header
                table.visibleHeaders[section] = view
            }
            if view.state.superview != objcObject { addSubview(view) } else { bringSubviewToFront(view) }
            view.sendSetFrame(frame)
            view.layoutIfNeeded()
        }
    }

    // MARK: Reloading and updating

    /// Every visible cell goes back to its pool; layout asks again.
    @ObjCMethod("reloadData")
    func reloadData() {
        for (_, cell) in table.visibleCells { enqueue(cell) }
        table.visibleCells = [:]
        for (_, view) in table.visibleHeaders { view.removeFromSuperview() }
        table.visibleHeaders = [:]
        table.selected = []
        table.measuredHeights = [:]
        table.headerViews = [:]
        invalidate()
    }

    @ObjCMethod("reloadSections:withRowAnimation:")
    func reloadSections(_ sections: NSObject, with animation: Int) { reloadData() }

    @ObjCMethod("reloadSectionIndexTitles") func reloadSectionIndexTitles() {}

    @ObjCMethod("insertRowsAtIndexPaths:withRowAnimation:")
    func insertRows(at paths: NSArray, with animation: Int) {
        for path in paths.elements.map(RowPath.init).sorted() {
            shiftRows(in: path.section, from: path.row, by: 1)
        }
        invalidate()
    }

    @ObjCMethod("deleteRowsAtIndexPaths:withRowAnimation:")
    func deleteRows(at paths: NSArray, with animation: Int) {
        for path in paths.elements.map(RowPath.init).sorted().reversed() {
            if let cell = table.visibleCells.removeValue(forKey: path) { enqueue(cell) }
            table.selected.remove(path)
            shiftRows(in: path.section, from: path.row + 1, by: -1)
        }
        invalidate()
    }

    @ObjCMethod("reloadRowsAtIndexPaths:withRowAnimation:")
    func reloadRows(at paths: NSArray, with animation: Int) {
        for path in paths.elements.map(RowPath.init) {
            if let cell = table.visibleCells.removeValue(forKey: path) { enqueue(cell) }
        }
        invalidate()
    }

    @ObjCMethod("insertSections:withRowAnimation:") func insertSections(_ sections: NSObject, with animation: Int) { reloadData() }
    @ObjCMethod("deleteSections:withRowAnimation:") func deleteSections(_ sections: NSObject, with animation: Int) { reloadData() }

    @ObjCMethod("moveRowAtIndexPath:toIndexPath:")
    func moveRow(at from: NSObject, to destination: NSObject) { reloadData() }

    /// Visible cells and selections at or after `row` move by `offset`.
    private func shiftRows(in section: Int, from row: Int, by offset: Int) {
        func moved(_ path: RowPath) -> RowPath {
            path.section == section && path.row >= row ? RowPath(section: section, row: path.row + offset) : path
        }
        table.visibleCells = Dictionary(uniqueKeysWithValues: table.visibleCells.map { (moved($0.key), $0.value) })
        table.selected = Set(table.selected.map(moved))
    }

    @ObjCMethod("beginUpdates") func beginUpdates() { table.updating += 1 }
    @ObjCMethod("endUpdates") func endUpdates() { table.updating = max(table.updating - 1, 0) }

    @ObjCMethod("performBatchUpdates:completion:")
    func performBatchUpdates(_ updates: ObjCBlock?, completion: ObjCBlock?) {
        updates.map(Blocks.call)
        layoutIfNeeded()
        if let completion { Updates.afterPass { Blocks.call(completion, true) } }
    }

    // MARK: Selection

    @ObjCMethod("indexPathForSelectedRow")
    func indexPathForSelectedRow() -> NSObject? { table.selected.sorted().first?.object }

    @ObjCMethod("indexPathsForSelectedRows")
    func indexPathsForSelectedRows() -> NSObject? {
        table.selected.isEmpty ? nil : NSMutableArray.of(table.selected.sorted().map(\.object))
    }

    /// Selects without telling the delegate, as UIKit does for selection
    /// made in code.
    @ObjCMethod("selectRowAtIndexPath:animated:scrollPosition:")
    func selectRow(at indexPath: NSObject?, animated: Bool, scrollPosition: Int) {
        guard let indexPath else {
            deselectAll()
            return
        }
        let path = RowPath(indexPath)
        if !table.allowsMultipleSelection { deselectAll() }
        table.selected.insert(path)
        table.visibleCells[path]?.sendSetSelected(true, animated: animated)
        if scrollPosition != 0 { scrollToRow(at: indexPath, at: scrollPosition, animated: animated) }
    }

    /// The cell shows the change once the update pass runs.
    @ObjCMethod("deselectRowAtIndexPath:animated:")
    func deselectRow(at indexPath: NSObject, animated: Bool) {
        let path = RowPath(indexPath)
        table.selected.remove(path)
        if let cell = table.visibleCells[path] {
            let state = table
            Updates.afterPass {
                if !state.selected.contains(path) { cell.sendSetSelected(false, animated: animated) }
            }
        }
    }

    private func deselectAll() {
        for path in table.selected { table.visibleCells[path]?.sendSetSelected(false, animated: false) }
        table.selected = []
    }

    /// Selects a row as a tap does, asking and telling the delegate.
    func tapRow(_ path: RowPath) {
        guard table.allowsSelection else { return }
        let delegate = delegate()
        var indexPath: NSObject? = path.object
        if let delegate, delegate.responds(to: "tableView:willSelectRowAtIndexPath:") {
            indexPath = delegate.sendTableView(self, willSelectRowAt: path.object)
        }
        guard let chosen = indexPath else { return }
        selectRow(at: chosen, animated: false, scrollPosition: 0)
        if let delegate, delegate.responds(to: "tableView:didSelectRowAtIndexPath:") {
            delegate.sendTableView(self, didSelectRowAt: chosen)
        }
        // A prototype cell's segue, with the cell as sender.
        if let cell = table.visibleCells[RowPath(chosen)], let template = cell.cell.selectionSegueTemplate {
            template.perform(cell)
        }
    }

    // MARK: Scrolling

    /// UITableViewScrollPosition: none 0, top 1, middle 2, bottom 3. The
    /// top leaves room for the section's floating header.
    @ObjCMethod("scrollToRowAtIndexPath:atScrollPosition:animated:")
    func scrollToRow(at indexPath: NSObject, at position: Int, animated: Bool) {
        let path = RowPath(indexPath)
        guard let rect = rect(path) else { return }
        let bounds = state.bounds, inset = adjustedContentInset()
        let header = table.style == 0 ? layout.sections[path.section].header.height : 0
        var y: CGFloat
        switch position {
        case 1: y = rect.minY - header - inset.top
        case 2: y = rect.midY - bounds.height / 2
        case 3: y = rect.maxY - bounds.height + inset.bottom
        default:
            scrollRectToVisible(rect, animated: animated)
            return
        }
        let maximum = max(-inset.top, layout.height + inset.bottom - bounds.height)
        y = min(max(y, -inset.top), maximum)
        setContentOffset(CGPoint(x: bounds.minX, y: y), animated: animated)
    }

    @ObjCMethod("scrollToNearestSelectedRowAtScrollPosition:animated:")
    func scrollToNearestSelectedRow(at position: Int, animated: Bool) {
        guard let path = table.selected.sorted().first else { return }
        scrollToRow(at: path.object, at: position, animated: animated)
    }
}

/// UITableView's messages to its cells, data source and delegate.
extension NSObject {
    @ObjCMethod("initWithStyle:reuseIdentifier:") func initializeCell(style: Int, reuseIdentifier: String?) -> NSObject
    @ObjCMethod("initWithReuseIdentifier:") func initializeHeaderFooter(reuseIdentifier: String?) -> NSObject
    @ObjCMethod("numberOfSectionsInTableView:") func sendNumberOfSections(in table: UITableView) -> Int
    @ObjCMethod("tableView:numberOfRowsInSection:") func sendTableView(_ table: UITableView, numberOfRowsInSection section: Int) -> Int
    @ObjCMethod("tableView:cellForRowAtIndexPath:") func sendTableView(_ table: UITableView, cellForRowAt path: NSObject) -> UITableViewCell?
    @ObjCMethod("tableView:titleForHeaderInSection:") func sendTableView(_ table: UITableView, titleForHeaderInSection section: Int) -> String?
    @ObjCMethod("tableView:titleForFooterInSection:") func sendTableView(_ table: UITableView, titleForFooterInSection section: Int) -> String?
    @ObjCMethod("tableView:heightForRowAtIndexPath:") func sendTableView(_ table: UITableView, heightForRowAt path: NSObject) -> CGFloat
    @ObjCMethod("tableView:heightForHeaderInSection:") func sendTableView(_ table: UITableView, heightForHeaderInSection section: Int) -> CGFloat
    @ObjCMethod("tableView:heightForFooterInSection:") func sendTableView(_ table: UITableView, heightForFooterInSection section: Int) -> CGFloat
    @ObjCMethod("tableView:viewForHeaderInSection:") func sendTableView(_ table: UITableView, viewForHeaderInSection section: Int) -> UIView?
    @ObjCMethod("tableView:willDisplayCell:forRowAtIndexPath:")
    func sendTableView(_ table: UITableView, willDisplay cell: UITableViewCell, forRowAt path: NSObject)
    @ObjCMethod("tableView:didEndDisplayingCell:forRowAtIndexPath:")
    func sendTableView(_ table: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt path: NSObject)
    @ObjCMethod("tableView:willSelectRowAtIndexPath:") func sendTableView(_ table: UITableView, willSelectRowAt path: NSObject) -> NSObject?
    @ObjCMethod("tableView:didSelectRowAtIndexPath:") func sendTableView(_ table: UITableView, didSelectRowAt path: NSObject)
}

// MARK: - UITableViewController

final class TableControllerState: ObjectState {
    var style = 0
    var clearsSelectionOnViewWillAppear = true
}

@ObjCClass("UITableViewController")
open class UITableViewController: UIViewController {
    static let tableControllerStates = StateTable<TableControllerState>()
    var tableController: TableControllerState { UITableViewController.tableControllerStates[objcObject] }

    @ObjCMethod("initWithCoder:")
    override func initialize(coder: NSObject) -> Self {
        _ = super.initialize(coder: coder)
        tableController.style = Coder(coder: coder).integer("UIStyle")
        return self
    }

    @ObjCMethod("initWithStyle:")
    func initialize(style: Int) -> NSObject {
        let controller = initializeViewController(nibName: nil, bundle: nil).unsafeCast(to: UITableViewController.self)
        controller.tableController.style = style
        return controller
    }

    @ObjCMethod("dealloc")
    override func dealloc() {
        UITableViewController.tableControllerStates.remove(objcObject)
        super.dealloc()
    }

    /// A table view the size of the screen, following its superview's size,
    /// whose data source and delegate the controller is.
    @ObjCMethod("loadView")
    override func loadView() {
        if loadViewFromNib() { return }
        let table = UITableView.objCClass.object.allocated().initializeTable(frame: Screen.bounds, style: tableController.style)
            .unsafeCast(to: UITableView.self)
        table.setAutoresizingMask(18)
        table.setDataSource(self)
        table.setDelegate(self)
        setView(table)
    }

    @ObjCMethod("tableView") func tableView() -> UITableView? { loadedView.as(UITableView.self) }
    @ObjCMethod("setTableView:") func setTableView(_ table: UITableView?) { setView(table) }
    @ObjCMethod("clearsSelectionOnViewWillAppear") func clearsSelectionOnViewWillAppear() -> Bool { tableController.clearsSelectionOnViewWillAppear }
    @ObjCMethod("setClearsSelectionOnViewWillAppear:") func setClearsSelectionOnViewWillAppear(_ clears: Bool) {
        tableController.clearsSelectionOnViewWillAppear = clears
    }
    @ObjCMethod("refreshControl") func refreshControl() -> UIView? { tableView()?.scroll.refreshControl }
    @ObjCMethod("setRefreshControl:") func setRefreshControl(_ control: UIView?) { tableView()?.scroll.refreshControl = control }

    @ObjCMethod("numberOfSectionsInTableView:") func numberOfSections(in table: UITableView) -> Int { 1 }
    @ObjCMethod("tableView:numberOfRowsInSection:") func tableView(_ table: UITableView, numberOfRowsInSection section: Int) -> Int { 0 }

    /// Clears the selection as the controller appears, when it should.
    @ObjCMethod("viewWillAppear:")
    override func viewWillAppear(_ animated: Bool) {
        guard tableController.clearsSelectionOnViewWillAppear, let table = state.view?.as(UITableView.self) else { return }
        for path in table.table.selected.sorted() { table.deselectRow(at: path.object, animated: animated) }
    }
}

extension NSObject {
    @ObjCMethod("initWithFrame:style:") func initializeTable(frame: CGRect, style: Int) -> NSObject
}

/// UIKit's private classes table view cells archive their labels and
/// separators as.
@ObjCClass("UITableViewLabel")
open class UITableViewLabel: UILabel {}

@ObjCClass("_UITableViewCellSeparatorView")
open class UITableViewCellSeparatorView: UIView {}

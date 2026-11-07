import CPerryGeometry
import PerryObjCInterop

// Swipe actions on table rows. A drag across a row, more sideways than
// up or down, slides its content aside to uncover the buttons its
// table's delegate gives for that side; let go past half of them, they
// stay open. Tapping one runs its handler, whose completion closes the
// row; touching anything else closes it. A data source that commits
// edits and gives no trailing actions gets a Delete button, as on iOS.

final class ContextualActionState: ObjectState {
    /// UIContextualActionStyle: normal 0, destructive 1.
    var style = 0
    var title: String?
    var image: UIImage?
    var backgroundColor: UIColor?
    var handler: ObjCBlock?
}

@ObjCClass("UIContextualAction")
open class UIContextualAction: NSObject {
    static let states = StateTable<ContextualActionState>()
    var action: ContextualActionState { UIContextualAction.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        UIContextualAction.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIContextualAction.objCClass.pointer)
    }

    @ObjCClassMethod("contextualActionWithStyle:title:handler:")
    static func action(_ cls: ObjCClass, style: Int, title: String?, handler: ObjCBlock?) -> NSObject {
        let made = cls.object.allocated().unsafeCast(to: UIContextualAction.self)
        (made.action.style, made.action.title, made.action.handler) = (style, title, handler)
        return made
    }

    @ObjCMethod("style") func style() -> Int { action.style }
    @ObjCMethod("title") func title() -> String? { action.title }
    @ObjCMethod("setTitle:") func setTitle(_ title: String?) { action.title = title }
    @ObjCMethod("image") func image() -> UIImage? { action.image }
    @ObjCMethod("setImage:") func setImage(_ image: UIImage?) { action.image = image }
    @ObjCMethod("backgroundColor") func backgroundColor() -> UIColor { color }
    @ObjCMethod("setBackgroundColor:") func setBackgroundColor(_ color: UIColor?) { action.backgroundColor = color }
    @ObjCMethod("handler") func handler() -> ObjCBlock? { action.handler }

    /// Red for destructive actions, gray otherwise, unless given.
    var color: UIColor { action.backgroundColor ?? (action.style == 1 ? UIColor.systemRed() : UIColor.systemGray()) }
}

final class SwipeConfigurationState: ObjectState {
    var actions: [UIContextualAction] = []
    var performsFirstActionWithFullSwipe = true
}

@ObjCClass("UISwipeActionsConfiguration")
open class UISwipeActionsConfiguration: NSObject {
    static let states = StateTable<SwipeConfigurationState>()
    var configuration: SwipeConfigurationState { UISwipeActionsConfiguration.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        UISwipeActionsConfiguration.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UISwipeActionsConfiguration.objCClass.pointer)
    }

    @ObjCClassMethod("configurationWithActions:")
    static func configuration(_ cls: ObjCClass, actions: NSArray) -> NSObject {
        let made = cls.object.allocated().unsafeCast(to: UISwipeActionsConfiguration.self)
        made.configuration.actions = actions.elements.compactMap { $0.as(UIContextualAction.self) }
        return made
    }

    @ObjCMethod("actions") func actions() -> NSObject { NSMutableArray.of(configuration.actions) }
    @ObjCMethod("performsFirstActionWithFullSwipe") func performsFirstActionWithFullSwipe() -> Bool {
        configuration.performsFirstActionWithFullSwipe
    }
    @ObjCMethod("setPerformsFirstActionWithFullSwipe:") func setPerformsFirstActionWithFullSwipe(_ performs: Bool) {
        configuration.performsFirstActionWithFullSwipe = performs
    }
}

extension NSObject {
    @ObjCMethod("tableView:trailingSwipeActionsConfigurationForRowAtIndexPath:")
    func sendTableView(_ table: UITableView, trailingSwipeActionsConfigurationForRowAt path: NSObject) -> NSObject?
    @ObjCMethod("tableView:leadingSwipeActionsConfigurationForRowAtIndexPath:")
    func sendTableView(_ table: UITableView, leadingSwipeActionsConfigurationForRowAt path: NSObject) -> NSObject?
    @ObjCMethod("tableView:commitEditingStyle:forRowAtIndexPath:")
    func sendTableView(_ table: UITableView, commit style: Int, forRowAt path: NSObject)
    @ObjCMethod("tableView:canEditRowAtIndexPath:")
    func sendTableView(_ table: UITableView, canEditRowAt path: NSObject) -> Bool
}

/// The buttons a swipe uncovers, beside the row's content.
@ObjCClass("_PerrySwipeActionsView")
open class PerrySwipeActionsView: UIView {
    @ObjCMethod("_perrySwipeAction:")
    func chose(_ sender: UIButton) { SwipeActions.perform(index: sender.state.tag) }
}

enum SwipeActions {
    /// The row a swipe is uncovering, or has left open.
    private struct Swipe {
        let table: UITableView
        let cell: UITableViewCell
        let path: NSObject
        /// Trailing: the buttons are on the right, uncovered dragging left.
        let trailing: Bool
        let actions: [UIContextualAction]
        /// The default Delete, which commits the edit rather than run a handler.
        let commitsDelete: Bool
        let buttons: PerrySwipeActionsView
        let width: CGFloat
        /// The content's offset as the drag began.
        var startOffset: CGFloat
    }

    nonisolated(unsafe) private static var swipe: Swipe?
    /// Whether a drag is moving the row now.
    nonisolated(unsafe) private(set) static var dragging = false

    static var isOpen: Bool { swipe != nil && !dragging }

    /// Whether the touch is on the open row's buttons.
    static func isOnButtons(_ view: UIView?) -> Bool {
        guard let swipe else { return false }
        var current = view
        while let candidate = current {
            if candidate.objcObject == swipe.buttons.objcObject { return true }
            current = candidate.state.superview.map(UIView.wrap)
        }
        return false
    }

    /// A sideways drag in `cell` of `table` has begun, `dx` points from
    /// where it went down. False when the row has no actions that way.
    static func begin(table: UITableView, cell: UITableViewCell, dx: CGFloat) -> Bool {
        let continuing = swipe.map { $0.cell.objcObject == cell.objcObject } ?? false
        if !continuing { close(animated: false) }
        if continuing, var open = swipe {
            open.startOffset = open.cell.state.bounds.origin.x
            swipe = open
            dragging = true
            return true
        }
        guard let path = table.indexPath(for: cell) else { return false }
        let trailing = dx < 0
        let delegate = table.delegate()
        var actions: [UIContextualAction] = []
        var commitsDelete = false
        let selector = trailing ? "tableView:trailingSwipeActionsConfigurationForRowAtIndexPath:"
                                : "tableView:leadingSwipeActionsConfigurationForRowAtIndexPath:"
        if let delegate, delegate.responds(to: selector) {
            let configuration = trailing ? delegate.sendTableView(table, trailingSwipeActionsConfigurationForRowAt: path)
                                         : delegate.sendTableView(table, leadingSwipeActionsConfigurationForRowAt: path)
            actions = configuration?.as(UISwipeActionsConfiguration.self)?.configuration.actions ?? []
        } else if trailing, let source = table.dataSource(), source.responds(to: "tableView:commitEditingStyle:forRowAtIndexPath:"),
                  !source.responds(to: "tableView:canEditRowAtIndexPath:") || source.sendTableView(table, canEditRowAt: path) {
            let delete = UIContextualAction.action(UIContextualAction.objCClass, style: 1, title: "Delete", handler: nil)
                .unsafeCast(to: UIContextualAction.self)
            actions = [delete]
            commitsDelete = true
        }
        guard !actions.isEmpty else { return false }
        // The first action sits nearest the edge, as UIKit's do.
        let font = UIFont.systemFont(size: 15)
        let widths = actions.map { action -> CGFloat in
            let text = action.action.title.map { Text.width($0, font: font).rounded(.up) } ?? 0
            return max(74, text + 30)
        }
        let width = widths.reduce(0, +)
        let height = cell.state.bounds.height
        let buttons = PerrySwipeActionsView.objCClass.object.allocated()
            .initializeView(frame: CGRect(x: trailing ? cell.state.bounds.width : -width, y: 0, width: width, height: height))
            .unsafeCast(to: PerrySwipeActionsView.self)
        var x: CGFloat = trailing ? width : 0
        for (index, action) in actions.enumerated() {
            let buttonWidth = widths[index]
            if trailing { x -= buttonWidth }
            let button = UIButton.button(UIButton.objCClass, type: 0).unsafeCast(to: UIButton.self)
            button.sendSetFrame(CGRect(x: x, y: 0, width: buttonWidth, height: height))
            button.setBackgroundColor(action.color)
            if let image = action.action.image {
                button.setImage(image.withTintColor(UIColor.white()), for: 0)
            } else {
                button.setTitle(action.action.title, for: 0)
                button.setTitleColor(UIColor.white(), for: 0)
                button.titleLabel().setFont(font)
            }
            button.setTag(index)
            button.addTarget(buttons, action: ObjCSelector("_perrySwipeAction:"), for: 1 << 6)
            buttons.addSubview(button)
            if !trailing { x += buttonWidth }
        }
        cell.addSubview(buttons)
        swipe = Swipe(table: table, cell: cell, path: path, trailing: trailing, actions: actions, commitsDelete: commitsDelete,
                      buttons: buttons, width: width, startOffset: 0)
        dragging = true
        return true
    }

    /// The drag is `dx` points across from where the row began moving.
    static func move(dx: CGFloat) {
        guard let swipe else { return }
        // The row's content moves with the finger, no further than its
        // buttons' width, nor back past where it rests.
        let offset = swipe.trailing ? min(max(swipe.startOffset - dx, 0), swipe.width)
                                    : max(min(swipe.startOffset - dx, 0), -swipe.width)
        setOffset(offset)
    }

    /// The finger lifted: open if past half the buttons, else closed.
    static func end() {
        dragging = false
        guard let swipe else { return }
        if abs(swipe.cell.state.bounds.origin.x) > swipe.width / 2 {
            setOffset(swipe.trailing ? swipe.width : -swipe.width)
        } else {
            close(animated: true)
        }
    }

    private static func setOffset(_ offset: CGFloat) {
        guard let swipe else { return }
        var bounds = swipe.cell.state.bounds
        bounds.origin.x = offset
        swipe.cell.setBounds(bounds)
        Display.markDirty()
    }

    /// The row's content goes back over its buttons.
    static func close(animated: Bool) {
        guard let open = swipe else { return }
        swipe = nil
        dragging = false
        var bounds = open.cell.state.bounds
        bounds.origin.x = 0
        open.cell.setBounds(bounds)
        open.buttons.removeFromSuperview()
        Display.markDirty()
    }

    /// The button at `index` was tapped.
    static func perform(index: Int) {
        guard let open = swipe, open.actions.indices.contains(index) else { return }
        let action = open.actions[index]
        if open.commitsDelete {
            close(animated: true)
            open.table.dataSource()?.sendTableView(open.table, commit: 1, forRowAt: open.path)
            return
        }
        guard let handler = action.action.handler else {
            close(animated: true)
            return
        }
        // handler(action, sourceView, completionHandler); the completion
        // closes the row, as does the handler's not keeping it open.
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?,
                                           UnsafeMutableRawPointer?) -> Void
        handler.function(as: Invoke.self)(handler.object, action.objcObject, open.buttons.objcObject, CompletionBlock.block)
    }

    /// The handlers' completion: closes the open row, whatever it is told.
    enum CompletionBlock {
        nonisolated(unsafe) static let block: UnsafeMutableRawPointer? = {
            guard let isa = Display.globalBlockClass else { return nil }
            let invoke: @convention(c) (UnsafeMutableRawPointer?, Bool) -> Void = { _, _ in
                SwipeActions.close(animated: true)
            }
            let descriptor = UnsafeMutableRawPointer.allocate(byteCount: 16, alignment: 8)
            descriptor.storeBytes(of: 0, as: UInt.self)
            descriptor.storeBytes(of: UInt(3 * MemoryLayout<UnsafeRawPointer>.size + 8), toByteOffset: MemoryLayout<UnsafeRawPointer>.size, as: UInt.self)
            let block = UnsafeMutableRawPointer.allocate(byteCount: 3 * MemoryLayout<UnsafeRawPointer>.size + 8, alignment: 8)
            block.storeBytes(of: isa, as: UnsafeMutableRawPointer.self)
            block.storeBytes(of: Int32(1 << 28), toByteOffset: MemoryLayout<UnsafeRawPointer>.size, as: Int32.self)   // BLOCK_IS_GLOBAL
            block.storeBytes(of: Int32(0), toByteOffset: MemoryLayout<UnsafeRawPointer>.size + 4, as: Int32.self)
            block.storeBytes(of: unsafeBitCast(invoke, to: UnsafeRawPointer.self), toByteOffset: MemoryLayout<UnsafeRawPointer>.size + 8, as: UnsafeRawPointer.self)
            block.storeBytes(of: UnsafeRawPointer(descriptor), toByteOffset: 2 * MemoryLayout<UnsafeRawPointer>.size + 8, as: UnsafeRawPointer.self)
            return block
        }()
    }
}

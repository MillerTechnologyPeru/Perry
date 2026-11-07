import PerryObjCInterop

// The keyboard: what is typed in the live view goes to the first
// responder that takes text: a text field, or a view adopting UIKeyInput
// (-insertText:, -deleteBackward). Return inserts a newline in such a view
// and ends editing in a field; Escape ends editing.

enum Keyboard {
    /// The first responder taking text, retained while it is.
    nonisolated(unsafe) private(set) static var responder: NSObject?

    static func isFirstResponder(_ object: NSObject) -> Bool { responder?.objcObject == object.objcObject }

    /// Makes `object` (or nobody) the one typing goes to.
    static func focus(_ object: NSObject?) {
        guard responder?.objcObject != object?.objcObject else { return }
        let previous = responder
        responder = object
        if let field = previous?.as(UITextField.self) { field.setNeedsDisplay() }
        Display.setTextInput(object != nil)
    }

    static func insert(_ text: String) {
        guard let responder else { return }
        if let field = responder.as(UITextField.self) {
            field.insert(text)
        } else if responder.responds(to: "insertText:") {
            responder.sendInsertText(text)
        }
        Display.markDirty()
        Updates.schedule()
    }

    static func deleteBackward() {
        guard let responder else { return }
        if let field = responder.as(UITextField.self) {
            field.deleteBackward()
        } else if responder.responds(to: "deleteBackward") {
            responder.sendDeleteBackward()
        }
        Display.markDirty()
        Updates.schedule()
    }

    static func returnKey() {
        guard let responder else { return }
        if let field = responder.as(UITextField.self) {
            field.returnKey()
        } else {
            insert("\n")
        }
        Display.markDirty()
        Updates.schedule()
    }

    static func escape() {
        _ = responder?.sendResignFirstResponder()
        Display.markDirty()
        Updates.schedule()
    }
}

extension NSObject {
    @ObjCMethod("insertText:") func sendInsertText(_ text: String)
    @ObjCMethod("deleteBackward") func sendDeleteBackward()
    @ObjCMethod("becomeFirstResponder") func sendBecomeFirstResponder() -> Bool
    @ObjCMethod("resignFirstResponder") func sendResignFirstResponder() -> Bool
}

// MARK: - UIKeyCommand

final class KeyCommandState {
    var input: String?
    var modifierFlags = 0
    var action: ObjCSelector?
    var title: String?
    var discoverabilityTitle: String?
    var wantsPriorityOverSystemBehavior = false
    var image: NSObject?
    var propertyList: NSObject?
    var attributes: UInt = 0
    var state = 0
}

/// A key command, kept for the responders that list it; with no hardware
/// keyboard, none is ever performed.
@ObjCClass("UIKeyCommand")
open class UIKeyCommand: NSObject {
    var command = KeyCommandState()

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCClassMethod("keyCommandWithInput:modifierFlags:action:")
    static func make(input: String?, modifierFlags: Int, action: ObjCSelector?) -> UIKeyCommand {
        let command = UIKeyCommand()
        command.command.input = input
        command.command.modifierFlags = modifierFlags
        command.command.action = action
        return command
    }

    @ObjCClassMethod("keyCommandWithInput:modifierFlags:action:discoverabilityTitle:")
    static func make(input: String?, modifierFlags: Int, action: ObjCSelector?, discoverabilityTitle: String?) -> UIKeyCommand {
        let command = make(input: input, modifierFlags: modifierFlags, action: action)
        command.command.discoverabilityTitle = discoverabilityTitle
        return command
    }

    @ObjCClassMethod("commandWithTitle:image:action:input:modifierFlags:propertyList:")
    static func make(title: String?, image: NSObject?, action: ObjCSelector?, input: String?, modifierFlags: Int,
                     propertyList: NSObject?) -> UIKeyCommand {
        let command = make(input: input, modifierFlags: modifierFlags, action: action)
        command.command.title = title
        command.command.image = image
        command.command.propertyList = propertyList
        return command
    }

    @ObjCMethod("input") func input() -> String? { command.input }
    @ObjCMethod("modifierFlags") func modifierFlags() -> Int { command.modifierFlags }
    @ObjCMethod("action") func action() -> ObjCSelector? { command.action }
    @ObjCMethod("title") func title() -> String? { command.title }
    @ObjCMethod("setTitle:") func setTitle(_ title: String?) { command.title = title }
    @ObjCMethod("discoverabilityTitle") func discoverabilityTitle() -> String? { command.discoverabilityTitle }
    @ObjCMethod("setDiscoverabilityTitle:") func setDiscoverabilityTitle(_ title: String?) { command.discoverabilityTitle = title }
    // UICommand's: an image, attributes (disabled, destructive, hidden) and
    // a state (off, on, mixed), kept for menus that show the command.
    @ObjCMethod("image") func image() -> NSObject? { command.image }
    @ObjCMethod("setImage:") func setImage(_ image: NSObject?) { command.image = image }
    @ObjCMethod("propertyList") func propertyList() -> NSObject? { command.propertyList }
    @ObjCMethod("attributes") func attributes() -> UInt { command.attributes }
    @ObjCMethod("setAttributes:") func setAttributes(_ attributes: UInt) { command.attributes = attributes }
    @ObjCMethod("state") func state() -> Int { command.state }
    @ObjCMethod("setState:") func setState(_ state: Int) { command.state = state }
    @ObjCMethod("alternates") func alternates() -> NSObject { NSMutableArray.empty() }
    @ObjCMethod("wantsPriorityOverSystemBehavior") func wantsPriorityOverSystemBehavior() -> Bool { command.wantsPriorityOverSystemBehavior }
    @ObjCMethod("setWantsPriorityOverSystemBehavior:") func setWantsPriorityOverSystemBehavior(_ wants: Bool) {
        command.wantsPriorityOverSystemBehavior = wants
    }
}

// MARK: - UIPointerInteraction

final class PointerInteractionState {
    var delegate: UnsafeMutableRawPointer?
    var view: UnsafeMutableRawPointer?
    var enabled = true
}

/// A pointer interaction; there is no pointer, so it never asks its
/// delegate for regions or styles.
@ObjCClass("UIPointerInteraction")
open class UIPointerInteraction: NSObject {
    var pointer = PointerInteractionState()

    @ObjCMethod("initWithDelegate:")
    public required init(delegate: UnsafeMutableRawPointer?) {
        super.init()
        pointer.delegate = delegate
    }

    @ObjCMethod("delegate") func delegate() -> UnsafeMutableRawPointer? { pointer.delegate }
    @ObjCMethod("view") func view() -> UnsafeMutableRawPointer? { pointer.view }
    @ObjCMethod("willMoveToView:") func willMove(toView view: UnsafeMutableRawPointer?) {}
    @ObjCMethod("didMoveToView:") func didMove(toView view: UnsafeMutableRawPointer?) { pointer.view = view }
    @ObjCMethod("isEnabled") func isEnabled() -> Bool { pointer.enabled }
    @ObjCMethod("setEnabled:") func setEnabled(_ enabled: Bool) { pointer.enabled = enabled }
    @ObjCMethod("invalidate") func invalidate() {}
}

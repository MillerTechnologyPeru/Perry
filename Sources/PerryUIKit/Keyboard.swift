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

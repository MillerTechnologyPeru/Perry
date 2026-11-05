import PerryObjCInterop

/// UIResponder: the responder chain. A plain responder has no next
/// responder and does not become first responder.
@ObjCClass("UIResponder")
open class UIResponder: NSObject {
    @ObjCMethod("nextResponder")
    func nextResponder() -> NSObject? { nil }

    @ObjCMethod("canBecomeFirstResponder") func canBecomeFirstResponder() -> Bool { false }
    @ObjCMethod("becomeFirstResponder") func becomeFirstResponder() -> Bool { false }
    @ObjCMethod("canResignFirstResponder") func canResignFirstResponder() -> Bool { true }
    @ObjCMethod("resignFirstResponder") func resignFirstResponder() -> Bool { true }
    @ObjCMethod("isFirstResponder") func isFirstResponder() -> Bool { false }
    /// There is no undo here: apps that clear a field's undo stack message nil.
    @ObjCMethod("undoManager") func undoManager() -> NSObject? { nil }

    // UIResponderStandardEditActions, which responders that edit override.
    @ObjCMethod("selectAll:") func selectAll(_ sender: NSObject?) {}
    @ObjCMethod("select:") func select(_ sender: NSObject?) {}
    @ObjCMethod("copy:") func copy(_ sender: NSObject?) {}
    @ObjCMethod("cut:") func cut(_ sender: NSObject?) {}
    @ObjCMethod("paste:") func paste(_ sender: NSObject?) {}
    @ObjCMethod("delete:") func delete(_ sender: NSObject?) {}
}

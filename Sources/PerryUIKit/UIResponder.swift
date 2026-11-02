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
}

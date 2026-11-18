import CPerryGeometry
import PerryObjCInterop

// UITextPosition, UITextRange and UITextSelectionRect: the abstract classes
// of UITextInput, which a text view of an app's own subclasses to say where
// its text is. They hold nothing; the subclasses do.

@ObjCClass("UITextPosition")
open class UITextPosition: NSObject {
    @ObjCMethod("init") public required override init() { super.init() }
}

@ObjCClass("UITextRange")
open class UITextRange: NSObject {
    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("isEmpty") func isEmpty() -> Bool { true }
    @ObjCMethod("start") func start() -> NSObject? { nil }
    @ObjCMethod("end") func end() -> NSObject? { nil }
}

@ObjCClass("UITextSelectionRect")
open class UITextSelectionRect: NSObject {
    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("rect") func rect() -> CGRect { .zero }
    /// NSWritingDirectionLeftToRight.
    @ObjCMethod("writingDirection") func writingDirection() -> Int { 0 }
    @ObjCMethod("containsStart") func containsStart() -> Bool { false }
    @ObjCMethod("containsEnd") func containsEnd() -> Bool { false }
    @ObjCMethod("isVertical") func isVertical() -> Bool { false }
}

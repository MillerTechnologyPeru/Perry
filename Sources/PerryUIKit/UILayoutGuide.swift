import CPerryGeometry
import PerryObjCInterop

// UILayoutGuide, as nibs have them for safe areas and margins: a rectangle
// in its owning view. Perry lays views out by their frames and
// autoresizing, so a guide is its owning view's bounds.

final class LayoutGuideState: ObjectState {
    /// Not retained, as Darwin's is weak.
    var owningView: UnsafeMutableRawPointer?
    var identifier = ""
}

@ObjCClass("UILayoutGuide")
open class UILayoutGuide: NSObject {
    static let states = StateTable<LayoutGuideState>()
    var guide: LayoutGuideState { UILayoutGuide.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        UILayoutGuide.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UILayoutGuide.objCClass.pointer)
    }

    @ObjCMethod("initWithCoder:")
    func initialize(coder: NSObject) -> Self {
        let decoded = Coder(coder: coder)
        guide.identifier = decoded.string("UILayoutGuideIdentifier") ?? decoded.string("identifier") ?? ""
        guide.owningView = decoded.object("UILayoutGuideOwningView")?.objcObject
        return self
    }

    @ObjCMethod("owningView")
    func owningView() -> UIView? { guide.owningView.map { UIView(objcObject: $0, ownership: .retain) } }
    @ObjCMethod("setOwningView:") func setOwningView(_ view: UIView?) { guide.owningView = view?.objcObject }
    @ObjCMethod("identifier") func identifier() -> String { guide.identifier }
    @ObjCMethod("setIdentifier:") func setIdentifier(_ identifier: String) { guide.identifier = identifier }
    @ObjCMethod("layoutFrame") func layoutFrame() -> CGRect { owningView()?.state.bounds ?? .zero }
}

import CPerryGeometry
import PerryObjCInterop

// UIPercentDrivenInteractiveTransition: a view controller transition a
// gesture drives. Transitions here are not interactive, so the object
// keeps its percentage and duration and finishes or cancels at once.

final class PercentTransitionState: ObjectState {
    var percent: CGFloat = 0
    var duration: CGFloat = 0
    var completionSpeed: CGFloat = 1
}

@ObjCClass("UIPercentDrivenInteractiveTransition")
open class UIPercentDrivenInteractiveTransition: NSObject {
    static let states = StateTable<PercentTransitionState>()
    var transition: PercentTransitionState { UIPercentDrivenInteractiveTransition.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        UIPercentDrivenInteractiveTransition.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIPercentDrivenInteractiveTransition.objCClass.pointer)
    }

    @ObjCMethod("percentComplete") func percentComplete() -> CGFloat { transition.percent }
    @ObjCMethod("duration") func duration() -> CGFloat { transition.duration }
    @ObjCMethod("completionSpeed") func completionSpeed() -> CGFloat { transition.completionSpeed }
    @ObjCMethod("setCompletionSpeed:") func setCompletionSpeed(_ speed: CGFloat) { transition.completionSpeed = speed }
    @ObjCMethod("startInteractiveTransition:") func startInteractiveTransition(_ context: NSObject?) {}
    @ObjCMethod("updateInteractiveTransition:") func updateInteractiveTransition(_ percent: CGFloat) { transition.percent = percent }
    @ObjCMethod("finishInteractiveTransition") func finishInteractiveTransition() { transition.percent = 1 }
    @ObjCMethod("cancelInteractiveTransition") func cancelInteractiveTransition() { transition.percent = 0 }
}

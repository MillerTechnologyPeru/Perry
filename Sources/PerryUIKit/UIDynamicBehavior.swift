import PerryObjCInterop

// UIDynamicBehavior: a rule a dynamic animator applies to its items, such
// as gravity or a spring. There is no physics simulation, so a behavior
// keeps its children and its action block and changes nothing; an app's
// subclass can still be made and added.

final class DynamicBehaviorState: ObjectState {
    var children: [NSObject] = []
    var action: ObjCBlock?
}

@ObjCClass("UIDynamicBehavior")
open class UIDynamicBehavior: NSObject {
    static let states = StateTable<DynamicBehaviorState>()
    var behavior: DynamicBehaviorState { UIDynamicBehavior.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        UIDynamicBehavior.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIDynamicBehavior.objCClass.pointer)
    }

    @ObjCMethod("childBehaviors") func childBehaviors() -> NSObject { NSMutableArray.of(behavior.children) }
    @ObjCMethod("addChildBehavior:") func addChildBehavior(_ child: NSObject?) {
        guard let child, !behavior.children.contains(where: { $0.objcObject == child.objcObject }) else { return }
        behavior.children.append(child)
    }
    @ObjCMethod("removeChildBehavior:")
    func removeChildBehavior(_ child: NSObject?) { behavior.children.removeAll { $0.objcObject == child?.objcObject } }
    @ObjCMethod("dynamicAnimator") func dynamicAnimator() -> NSObject? { nil }
    @ObjCMethod("willMoveToAnimator:") func willMove(toAnimator animator: NSObject?) {}
    @ObjCMethod("action") func action() -> ObjCBlock? { behavior.action }
    @ObjCMethod("setAction:") func setAction(_ action: ObjCBlock?) { behavior.action = action }
}

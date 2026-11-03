import CPerryGeometry
import PerryObjCInterop

// Haptic feedback generators. There is no haptic engine, so preparing
// and occurring do nothing, as on a device without one.

@ObjCClass("UIFeedbackGenerator")
open class UIFeedbackGenerator: NSObject {
    @ObjCMethod("prepare") func prepare() {}
    @ObjCClassMethod("feedbackGeneratorForView:") static func generator(_ cls: ObjCClass, for view: UIView?) -> NSObject {
        cls.object.allocated().initialized()
    }
}

/// UINotificationFeedbackType: success 0, warning 1, error 2.
@ObjCClass("UINotificationFeedbackGenerator")
open class UINotificationFeedbackGenerator: UIFeedbackGenerator {
    @ObjCMethod("notificationOccurred:") func notificationOccurred(_ type: Int) {}
    @ObjCMethod("notificationOccurred:atLocation:") func notificationOccurred(_ type: Int, at location: CGPoint) {}
}

/// UIImpactFeedbackStyle: light 0, medium 1, heavy 2, soft 3, rigid 4.
@ObjCClass("UIImpactFeedbackGenerator")
open class UIImpactFeedbackGenerator: UIFeedbackGenerator {
    @ObjCMethod("initWithStyle:") func initialize(style: Int) -> Self { self }
    @ObjCMethod("initWithStyle:view:") func initialize(style: Int, view: UIView?) -> Self { self }
    @ObjCMethod("impactOccurred") func impactOccurred() {}
    @ObjCMethod("impactOccurredWithIntensity:") func impactOccurred(intensity: CGFloat) {}
    @ObjCMethod("impactOccurredAtLocation:") func impactOccurred(at location: CGPoint) {}
    @ObjCMethod("impactOccurredWithIntensity:atLocation:") func impactOccurred(intensity: CGFloat, at location: CGPoint) {}
}

@ObjCClass("UISelectionFeedbackGenerator")
open class UISelectionFeedbackGenerator: UIFeedbackGenerator {
    @ObjCMethod("selectionChanged") func selectionChanged() {}
    @ObjCMethod("selectionChangedAtLocation:") func selectionChanged(at location: CGPoint) {}
}

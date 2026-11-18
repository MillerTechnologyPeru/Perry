import PerryObjCInterop

// UIActivity: a custom activity of a share sheet (Open in Safari, a copy
// action). There is no share sheet here, so an activity is never offered;
// an app's subclass overrides what it answers and the base answers what
// UIKit's does.

@ObjCClass("UIActivity")
open class UIActivity: NSObject {
    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCClassMethod("activityCategory") static func activityCategory(_ cls: ObjCClass) -> Int { 0 }

    @ObjCMethod("activityType") func activityType() -> String? { nil }
    @ObjCMethod("activityTitle") func activityTitle() -> String? { nil }
    @ObjCMethod("activityImage") func activityImage() -> NSObject? { nil }
    @ObjCMethod("canPerformWithActivityItems:") func canPerform(activityItems: NSObject?) -> Bool { false }
    @ObjCMethod("prepareWithActivityItems:") func prepare(activityItems: NSObject?) {}
    @ObjCMethod("activityViewController") func activityViewController() -> NSObject? { nil }
    @ObjCMethod("performActivity") func performActivity() { activityDidFinish(true) }
    @ObjCMethod("activityDidFinish:") func activityDidFinish(_ completed: Bool) {}
}

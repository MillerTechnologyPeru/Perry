import PerryObjCInterop

// UIActivityItemProvider: an item a share sheet asks for when an activity
// is chosen. There is no share sheet here, so the provider keeps its
// placeholder, and an app's subclass overrides -item. (Apple's is an
// NSOperation; nothing here runs it.)

final class ActivityItemProviderState: ObjectState {
    var placeholder: NSObject?
    var activityType: NSObject?
}

@ObjCClass("UIActivityItemProvider")
open class UIActivityItemProvider: NSObject {
    static let states = StateTable<ActivityItemProviderState>()
    var provider: ActivityItemProviderState { UIActivityItemProvider.states[objcObject] }

    @ObjCMethod("initWithPlaceholderItem:")
    func initialize(placeholderItem: NSObject?) -> Self {
        provider.placeholder = placeholderItem
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        UIActivityItemProvider.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIActivityItemProvider.objCClass.pointer)
    }

    @ObjCMethod("placeholderItem") func placeholderItem() -> NSObject? { provider.placeholder }
    @ObjCMethod("activityType") func activityType() -> NSObject? { provider.activityType }

    /// What the activity is given: the placeholder, unless a subclass has
    /// something better.
    @ObjCMethod("item") func item() -> NSObject? { provider.placeholder }
}

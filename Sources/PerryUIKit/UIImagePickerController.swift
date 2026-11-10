import PerryObjCInterop

// UIImagePickerController: the camera and the photo library. A handheld
// has neither to offer, so no source type is available (a program asks
// before it shows one) and the controller keeps the options it is given.

final class ImagePickerState: ObjectState {
    var sourceType = 0
    var mediaTypes: NSObject?
    var allowsEditing = false
}

@ObjCClass("UIImagePickerController")
open class UIImagePickerController: UINavigationController {
    static let pickerStates = StateTable<ImagePickerState>()
    var picker: ImagePickerState { UIImagePickerController.pickerStates[objcObject] }

    @ObjCMethod("dealloc")
    override func dealloc() {
        UIImagePickerController.pickerStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCClassMethod("isSourceTypeAvailable:") static func isSourceTypeAvailable(_ cls: ObjCClass, _ type: Int) -> Bool { false }
    @ObjCClassMethod("isCameraDeviceAvailable:") static func isCameraDeviceAvailable(_ cls: ObjCClass, _ device: Int) -> Bool { false }
    @ObjCClassMethod("availableMediaTypesForSourceType:")
    static func availableMediaTypes(_ cls: ObjCClass, forSourceType type: Int) -> NSObject? { nil }

    /// UIImagePickerControllerSourceType: photo library 0, camera 1, saved photos album 2.
    @ObjCMethod("sourceType") func sourceType() -> Int { picker.sourceType }
    @ObjCMethod("setSourceType:") func setSourceType(_ type: Int) { picker.sourceType = type }
    @ObjCMethod("mediaTypes") func mediaTypes() -> NSObject? { picker.mediaTypes }
    @ObjCMethod("setMediaTypes:") func setMediaTypes(_ types: NSObject?) { picker.mediaTypes = types }
    @ObjCMethod("allowsEditing") func allowsEditing() -> Bool { picker.allowsEditing }
    @ObjCMethod("setAllowsEditing:") func setAllowsEditing(_ allows: Bool) { picker.allowsEditing = allows }
}

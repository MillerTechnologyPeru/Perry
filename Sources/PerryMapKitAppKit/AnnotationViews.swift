import CPerryGeometry
import PerryMapKitShared
import PerryObjCInterop

// A Mac app's annotation views, NSViews: their methods are the shared
// categories' (PerryMapKitShared).

@ObjCClass("MKAnnotationView")
class MKAnnotationView: NSView {
    override class func didDefineObjCClass(_ cls: ObjCClass) { AnnotationViewObject.registerObjCCategoryAnnotationView(cls) }

    @ObjCMethod("dealloc")
    func dealloc() {
        AnnotationViews.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: MKAnnotationView.objCClass.pointer)
    }

    @ObjCMethod("initWithAnnotation:reuseIdentifier:")
    func initialize(annotation: NSObject?, reuseIdentifier: String?) -> Self {
        Super.initialize(objcObject, frame: CGRect(origin: CGPoint(x: 0, y: 0), size: CGSize(width: 0, height: 0)),
                         definedOn: MKAnnotationView.objCClass)
        AnnotationViews.initialize(objcObject, annotation: annotation, reuseIdentifier: reuseIdentifier)
        return self
    }

    @ObjCMethod("isFlipped") func isFlipped() -> Bool { true }
}

@ObjCClass("MKPinAnnotationView")
class MKPinAnnotationView: MKAnnotationView {
    override class func didDefineObjCClass(_ cls: ObjCClass) { AnnotationViewObject.registerObjCCategoryPinAnnotationView(cls) }

    @ObjCClassMethod("redPinColor") static func redPinColor() -> NSColor { NSColor.make(red: 1, green: 0.23, blue: 0.19, alpha: 1) }
    @ObjCClassMethod("greenPinColor") static func greenPinColor() -> NSColor { NSColor.make(red: 0.2, green: 0.78, blue: 0.35, alpha: 1) }
    @ObjCClassMethod("purplePinColor") static func purplePinColor() -> NSColor { NSColor.make(red: 0.69, green: 0.32, blue: 0.87, alpha: 1) }
}

@ObjCClass("MKMarkerAnnotationView")
class MKMarkerAnnotationView: MKAnnotationView {
    override class func didDefineObjCClass(_ cls: ObjCClass) { AnnotationViewObject.registerObjCCategoryMarkerAnnotationView(cls) }
}

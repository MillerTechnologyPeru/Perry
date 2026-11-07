import CPerryGeometry
import PerryMapKitShared
import PerryObjCInterop

// An iOS app's MKMapView, a UIView: its methods are the shared MapView and
// MapViewGestures categories' (PerryMapKitShared); this class sets the land
// color, takes every finger's touches, and makes and resizes the map's tiles
// as it lays out. A Mac app's is
// PerryMapKitAppKit's NSView.

@ObjCClass("MKMapView")
class MKMapView: UIView {
    override class var objCSuperclassName: String? { UIKitViews.superclassName }

    override class func didDefineObjCClass(_ cls: ObjCClass) {
        MapViewObject.registerObjCCategoryMapView(cls)
        MapViewObject.registerObjCCategoryMapViewGestures(cls)
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        MapViews.states.remove(objcObject)
        MapViews.removeGestures(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: MKMapView.objCClass.pointer)
    }

    @ObjCMethod("initWithFrame:")
    func initialize(frame: CGRect) -> Self {
        Super.initialize(objcObject, frame: frame, definedOn: MKMapView.objCClass)
        showLand()
        return self
    }

    @ObjCMethod("initWithCoder:")
    func initialize(coder: NSObject) -> Self {
        Super.initialize(objcObject, coder: coder, definedOn: MKMapView.objCClass)
        showLand()
        return self
    }

    /// The land color, and every finger's touches, for the gestures.
    private func showLand() {
        setMultipleTouchEnabled(true)
        let (red, green, blue) = MapViews.land
        setBackgroundColor(UIColor.make(red: red, green: green, blue: blue, alpha: 1))
    }

    @ObjCMethod("layoutSubviews")
    func layoutSubviews() {
        Super.send(objcObject, "layoutSubviews", definedOn: MKMapView.objCClass)
        MapViews.layOut(objcObject, size: bounds().size, scale: contentScaleFactor())
    }
}

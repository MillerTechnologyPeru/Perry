import CPerryGeometry
import PerryMapKitShared
import PerryObjCInterop

// A Mac app's MKMapView, an NSView: its methods are the shared MapView
// category's (PerryMapKitShared). This class is flipped, as the shared
// conversions put the region's top first; it shows the land color through
// its layer, which the map's frames are drawn into, and makes and resizes
// the map's tiles as it lays out, which it does after each change of size.

@ObjCClass("MKMapView")
class MKMapView: NSView {
    override class func didDefineObjCClass(_ cls: ObjCClass) {
        MapViewObject.registerObjCCategoryMapView(cls)
        MapViewObject.registerObjCCategoryMapViewMouse(cls)
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

    private func showLand() {
        setWantsLayer(true)
        let (red, green, blue) = MapViews.land
        layer()?.setBackgroundColor(NSColor.make(red: red, green: green, blue: blue, alpha: 1).cgColor())
    }

    @ObjCMethod("isFlipped") func isFlipped() -> Bool { true }

    @ObjCMethod("layout")
    func layout() {
        Super.send(objcObject, "layout", definedOn: MKMapView.objCClass)
        MapViews.layOut(objcObject, size: bounds().size, scale: window()?.backingScaleFactor() ?? 1)
    }
}

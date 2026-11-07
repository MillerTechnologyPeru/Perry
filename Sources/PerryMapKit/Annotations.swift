import CPerryGeometry
import PerryMapKitShared
import PerryObjCInterop

// Annotations and the views for them, placemarks and map items. The views
// keep what they are given; with no map drawn, they are not shown.

final class ShapeState: ObjectState {
    var title: String?
    var subtitle: String?
    var coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
}

@ObjCClass("MKShape")
open class MKShape: NSObject {
    static let states = StateTable<ShapeState>()
    var shape: ShapeState { MKShape.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        MKShape.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: MKShape.objCClass.pointer)
    }

    @ObjCMethod("title") func title() -> String? { shape.title }
    @ObjCMethod("setTitle:") func setTitle(_ title: String?) { shape.title = title }
    @ObjCMethod("subtitle") func subtitle() -> String? { shape.subtitle }
    @ObjCMethod("setSubtitle:") func setSubtitle(_ subtitle: String?) { shape.subtitle = subtitle }
}

@ObjCClass("MKPointAnnotation")
open class MKPointAnnotation: MKShape {
    @ObjCMethod("initWithCoordinate:")
    func initialize(coordinate: CLLocationCoordinate2D) -> Self {
        shape.coordinate = coordinate
        return self
    }

    @ObjCMethod("initWithCoordinate:title:subtitle:")
    func initialize(coordinate: CLLocationCoordinate2D, title: String?, subtitle: String?) -> Self {
        (shape.coordinate, shape.title, shape.subtitle) = (coordinate, title, subtitle)
        return self
    }

    @ObjCMethod("coordinate") func coordinate() -> CLLocationCoordinate2D { shape.coordinate }
    @ObjCMethod("setCoordinate:") func setCoordinate(_ coordinate: CLLocationCoordinate2D) { shape.coordinate = coordinate }
}

/// The user's location: where CoreLocation says the device is.
@ObjCClass("MKUserLocation")
open class MKUserLocation: MKShape {
    @ObjCMethod("init")
    func initialize() -> Self {
        shape.title = "My Location"
        shape.coordinate = DeviceLocation.coordinate ?? CLLocationCoordinate2D(latitude: -180, longitude: -180)
        return self
    }

    @ObjCMethod("coordinate") func coordinate() -> CLLocationCoordinate2D { shape.coordinate }
    @ObjCMethod("location") func location() -> NSObject? { DeviceLocation.coordinate.map { CLLocation.make($0) } }
    @ObjCMethod("heading") func heading() -> NSObject? { nil }
    @ObjCMethod("isUpdating") func isUpdating() -> Bool { false }
}

// MARK: - Annotation views

// An iOS app's annotation views, UIViews: their methods are the shared
// categories' (PerryMapKitShared). A Mac app's are PerryMapKitAppKit's.

@ObjCClass("MKAnnotationView")
class MKAnnotationView: UIView {
    override class var objCSuperclassName: String? { UIKitViews.superclassName }

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
}

@ObjCClass("MKPinAnnotationView")
class MKPinAnnotationView: MKAnnotationView {
    override class func didDefineObjCClass(_ cls: ObjCClass) { AnnotationViewObject.registerObjCCategoryPinAnnotationView(cls) }

    @ObjCClassMethod("redPinColor") static func redPinColor() -> UIColor { UIColor.make(red: 1, green: 0.23, blue: 0.19, alpha: 1) }
    @ObjCClassMethod("greenPinColor") static func greenPinColor() -> UIColor { UIColor.make(red: 0.2, green: 0.78, blue: 0.35, alpha: 1) }
    @ObjCClassMethod("purplePinColor") static func purplePinColor() -> UIColor { UIColor.make(red: 0.69, green: 0.32, blue: 0.87, alpha: 1) }
}

@ObjCClass("MKMarkerAnnotationView")
class MKMarkerAnnotationView: MKAnnotationView {
    override class func didDefineObjCClass(_ cls: ObjCClass) { AnnotationViewObject.registerObjCCategoryMarkerAnnotationView(cls) }
}

// MARK: - Placemarks and map items

/// A placemark at a coordinate, with an address dictionary if given.
@ObjCClass("MKPlacemark")
class MKPlacemark: CLPlacemark {
    @ObjCMethod("initWithCoordinate:addressDictionary:")
    func initialize(coordinate: CLLocationCoordinate2D, addressDictionary: NSObject?) -> NSObject {
        initializePlacemark(location: CLLocation.make(coordinate), addressDictionary: addressDictionary, region: nil, areasOfInterest: nil)
    }

    @ObjCMethod("initWithCoordinate:")
    func initialize(coordinate: CLLocationCoordinate2D) -> NSObject { initialize(coordinate: coordinate, addressDictionary: nil) }

    @ObjCMethod("initWithCoordinate:postalAddress:")
    func initialize(coordinate: CLLocationCoordinate2D, postalAddress: NSObject?) -> NSObject {
        initialize(coordinate: coordinate, addressDictionary: nil)
    }

    @ObjCMethod("coordinate")
    func coordinate() -> CLLocationCoordinate2D {
        location()?.coordinate() ?? CLLocationCoordinate2D(latitude: -180, longitude: -180)
    }

    @ObjCMethod("title") func title() -> String? { name() }
    @ObjCMethod("subtitle") func subtitle() -> String? { nil }
    @ObjCMethod("countryCode") func countryCode() -> String? { isoCountryCode() }
}

final class MapItemState: ObjectState {
    var placemark: NSObject?
    var name: String?
    var phoneNumber: String?
    var url: NSObject?
    var timeZone: NSObject?
    var pointOfInterestCategory: String?
    var isCurrentLocation = false
}

/// A place to show in Maps, which there is none of to open.
@ObjCClass("MKMapItem")
open class MKMapItem: NSObject {
    static let states = StateTable<MapItemState>()
    var item: MapItemState { MKMapItem.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        MKMapItem.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: MKMapItem.objCClass.pointer)
    }

    @ObjCClassMethod("mapItemForCurrentLocation")
    static func mapItemForCurrentLocation(_ cls: ObjCClass) -> NSObject {
        let item = cls.object.newInstance().unsafeCast(to: MKMapItem.self)
        item.item.isCurrentLocation = true
        item.item.name = "Current Location"
        return item
    }

    /// Maps is not installed.
    @ObjCClassMethod("openMapsWithItems:launchOptions:")
    static func openMaps(with items: NSObject?, launchOptions: NSObject?) -> Bool { false }

    @ObjCMethod("initWithPlacemark:")
    func initialize(placemark: NSObject?) -> Self {
        item.placemark = placemark
        item.name = placemark?.unsafeCast(to: CLPlacemark.self).name()
        return self
    }

    @ObjCMethod("placemark") func placemark() -> NSObject? { item.placemark }
    @ObjCMethod("isCurrentLocation") func isCurrentLocation() -> Bool { item.isCurrentLocation }
    @ObjCMethod("name") func name() -> String? { item.name }
    @ObjCMethod("setName:") func setName(_ name: String?) { item.name = name }
    @ObjCMethod("phoneNumber") func phoneNumber() -> String? { item.phoneNumber }
    @ObjCMethod("setPhoneNumber:") func setPhoneNumber(_ number: String?) { item.phoneNumber = number }
    @ObjCMethod("url") func url() -> NSObject? { item.url }
    @ObjCMethod("setUrl:") func setURL(_ url: NSObject?) { item.url = url }
    @ObjCMethod("timeZone") func timeZone() -> NSObject? { item.timeZone }
    @ObjCMethod("setTimeZone:") func setTimeZone(_ zone: NSObject?) { item.timeZone = zone }
    @ObjCMethod("pointOfInterestCategory") func pointOfInterestCategory() -> String? { item.pointOfInterestCategory }
    @ObjCMethod("setPointOfInterestCategory:")
    func setPointOfInterestCategory(_ category: String?) { item.pointOfInterestCategory = category }

    /// Maps is not installed.
    @ObjCMethod("openInMapsWithLaunchOptions:") func openInMaps(launchOptions: NSObject?) -> Bool { false }
}

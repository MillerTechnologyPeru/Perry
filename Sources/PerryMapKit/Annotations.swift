import CPerryGeometry
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

/// The user's location, which is never known.
@ObjCClass("MKUserLocation")
open class MKUserLocation: MKShape {
    @ObjCMethod("init")
    func initialize() -> Self {
        shape.title = "My Location"
        shape.coordinate = CLLocationCoordinate2D(latitude: -180, longitude: -180)
        return self
    }

    @ObjCMethod("coordinate") func coordinate() -> CLLocationCoordinate2D { shape.coordinate }
    @ObjCMethod("location") func location() -> NSObject? { nil }
    @ObjCMethod("heading") func heading() -> NSObject? { nil }
    @ObjCMethod("isUpdating") func isUpdating() -> Bool { false }
}

// MARK: - Annotation views

final class AnnotationViewState: ObjectState {
    var annotation: NSObject?
    var reuseIdentifier: String?
    var image: NSObject?
    var centerOffset = CGPoint(x: 0, y: 0)
    var calloutOffset = CGPoint(x: 0, y: 0)
    var canShowCallout = false
    var enabled = true
    var highlighted = false
    var selected = false
    var draggable = false
    var dragState = 0
    var leftCalloutAccessoryView: NSObject?
    var rightCalloutAccessoryView: NSObject?
    var detailCalloutAccessoryView: NSObject?
    var displayPriority: Float = 1000
    var clusteringIdentifier: String?
    var collisionMode = 0
    // MKPinAnnotationView's and MKMarkerAnnotationView's.
    var pinColor = 0
    var tintColor: NSObject?
    var animatesDrop = false
    var glyphText: String?
    var glyphImage: NSObject?
}

@ObjCClass("MKAnnotationView")
class MKAnnotationView: UIView {
    static let states = StateTable<AnnotationViewState>()
    var annotationView: AnnotationViewState { MKAnnotationView.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        MKAnnotationView.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: MKAnnotationView.objCClass.pointer)
    }

    @ObjCMethod("initWithAnnotation:reuseIdentifier:")
    func initialize(annotation: NSObject?, reuseIdentifier: String?) -> Self {
        Super.initialize(objcObject, frame: CGRect(origin: CGPoint(x: 0, y: 0), size: CGSize(width: 0, height: 0)),
                         definedOn: MKAnnotationView.objCClass)
        annotationView.annotation = annotation
        annotationView.reuseIdentifier = reuseIdentifier
        return self
    }

    @ObjCMethod("annotation") func annotation() -> NSObject? { annotationView.annotation }
    @ObjCMethod("setAnnotation:") func setAnnotation(_ annotation: NSObject?) { annotationView.annotation = annotation }
    @ObjCMethod("reuseIdentifier") func reuseIdentifier() -> String? { annotationView.reuseIdentifier }
    @ObjCMethod("prepareForReuse") func prepareForReuse() {}
    @ObjCMethod("prepareForDisplay") func prepareForDisplay() {}

    /// The view takes its image's size.
    @ObjCMethod("image") func image() -> NSObject? { annotationView.image }
    @ObjCMethod("setImage:")
    func setImage(_ image: NSObject?) {
        annotationView.image = image
        guard let image else { return }
        let size = image.imageSize()
        let frame = self.frame()
        setFrame(CGRect(origin: frame.origin, size: size))
    }

    @ObjCMethod("centerOffset") func centerOffset() -> CGPoint { annotationView.centerOffset }
    @ObjCMethod("setCenterOffset:") func setCenterOffset(_ offset: CGPoint) { annotationView.centerOffset = offset }
    @ObjCMethod("calloutOffset") func calloutOffset() -> CGPoint { annotationView.calloutOffset }
    @ObjCMethod("setCalloutOffset:") func setCalloutOffset(_ offset: CGPoint) { annotationView.calloutOffset = offset }
    @ObjCMethod("canShowCallout") func canShowCallout() -> Bool { annotationView.canShowCallout }
    @ObjCMethod("setCanShowCallout:") func setCanShowCallout(_ shows: Bool) { annotationView.canShowCallout = shows }
    @ObjCMethod("isEnabled") func isEnabled() -> Bool { annotationView.enabled }
    @ObjCMethod("setEnabled:") func setEnabled(_ enabled: Bool) { annotationView.enabled = enabled }
    @ObjCMethod("isHighlighted") func isHighlighted() -> Bool { annotationView.highlighted }
    @ObjCMethod("setHighlighted:") func setHighlighted(_ highlighted: Bool) { annotationView.highlighted = highlighted }
    @ObjCMethod("isSelected") func isSelected() -> Bool { annotationView.selected }
    @ObjCMethod("setSelected:") func setSelected(_ selected: Bool) { annotationView.selected = selected }
    @ObjCMethod("setSelected:animated:") func setSelected(_ selected: Bool, animated: Bool) { annotationView.selected = selected }
    @ObjCMethod("isDraggable") func isDraggable() -> Bool { annotationView.draggable }
    @ObjCMethod("setDraggable:") func setDraggable(_ draggable: Bool) { annotationView.draggable = draggable }
    @ObjCMethod("dragState") func dragState() -> Int { annotationView.dragState }
    @ObjCMethod("setDragState:") func setDragState(_ state: Int) { annotationView.dragState = state }
    @ObjCMethod("setDragState:animated:") func setDragState(_ state: Int, animated: Bool) { annotationView.dragState = state }
    @ObjCMethod("leftCalloutAccessoryView") func leftCalloutAccessoryView() -> NSObject? { annotationView.leftCalloutAccessoryView }
    @ObjCMethod("setLeftCalloutAccessoryView:")
    func setLeftCalloutAccessoryView(_ view: NSObject?) { annotationView.leftCalloutAccessoryView = view }
    @ObjCMethod("rightCalloutAccessoryView") func rightCalloutAccessoryView() -> NSObject? { annotationView.rightCalloutAccessoryView }
    @ObjCMethod("setRightCalloutAccessoryView:")
    func setRightCalloutAccessoryView(_ view: NSObject?) { annotationView.rightCalloutAccessoryView = view }
    @ObjCMethod("detailCalloutAccessoryView") func detailCalloutAccessoryView() -> NSObject? { annotationView.detailCalloutAccessoryView }
    @ObjCMethod("setDetailCalloutAccessoryView:")
    func setDetailCalloutAccessoryView(_ view: NSObject?) { annotationView.detailCalloutAccessoryView = view }
    @ObjCMethod("displayPriority") func displayPriority() -> Float { annotationView.displayPriority }
    @ObjCMethod("setDisplayPriority:") func setDisplayPriority(_ priority: Float) { annotationView.displayPriority = priority }
    @ObjCMethod("clusteringIdentifier") func clusteringIdentifier() -> String? { annotationView.clusteringIdentifier }
    @ObjCMethod("setClusteringIdentifier:")
    func setClusteringIdentifier(_ identifier: String?) { annotationView.clusteringIdentifier = identifier }
    @ObjCMethod("collisionMode") func collisionMode() -> Int { annotationView.collisionMode }
    @ObjCMethod("setCollisionMode:") func setCollisionMode(_ mode: Int) { annotationView.collisionMode = mode }
}

/// A pin: MKPinAnnotationColor red 0, green 1, purple 2.
@ObjCClass("MKPinAnnotationView")
class MKPinAnnotationView: MKAnnotationView {
    @ObjCClassMethod("redPinColor") static func redPinColor() -> UIColor { UIColor.make(red: 1, green: 0.23, blue: 0.19, alpha: 1) }
    @ObjCClassMethod("greenPinColor") static func greenPinColor() -> UIColor { UIColor.make(red: 0.2, green: 0.78, blue: 0.35, alpha: 1) }
    @ObjCClassMethod("purplePinColor") static func purplePinColor() -> UIColor { UIColor.make(red: 0.69, green: 0.32, blue: 0.87, alpha: 1) }

    @ObjCMethod("pinColor") func pinColor() -> Int { annotationView.pinColor }
    @ObjCMethod("setPinColor:") func setPinColor(_ color: Int) { annotationView.pinColor = color }
    @ObjCMethod("pinTintColor") func pinTintColor() -> NSObject? { annotationView.tintColor }
    @ObjCMethod("setPinTintColor:") func setPinTintColor(_ color: NSObject?) { annotationView.tintColor = color }
    @ObjCMethod("animatesDrop") func animatesDrop() -> Bool { annotationView.animatesDrop }
    @ObjCMethod("setAnimatesDrop:") func setAnimatesDrop(_ animates: Bool) { annotationView.animatesDrop = animates }
}

@ObjCClass("MKMarkerAnnotationView")
class MKMarkerAnnotationView: MKAnnotationView {
    @ObjCMethod("markerTintColor") func markerTintColor() -> NSObject? { annotationView.tintColor }
    @ObjCMethod("setMarkerTintColor:") func setMarkerTintColor(_ color: NSObject?) { annotationView.tintColor = color }
    @ObjCMethod("glyphText") func glyphText() -> String? { annotationView.glyphText }
    @ObjCMethod("setGlyphText:") func setGlyphText(_ text: String?) { annotationView.glyphText = text }
    @ObjCMethod("glyphImage") func glyphImage() -> NSObject? { annotationView.glyphImage }
    @ObjCMethod("setGlyphImage:") func setGlyphImage(_ image: NSObject?) { annotationView.glyphImage = image }
    @ObjCMethod("animatesWhenAdded") func animatesWhenAdded() -> Bool { annotationView.animatesDrop }
    @ObjCMethod("setAnimatesWhenAdded:") func setAnimatesWhenAdded(_ animates: Bool) { annotationView.animatesDrop = animates }
}

extension NSObject {
    @ObjCMethod("size") func imageSize() -> CGSize
    /// MKAnnotation's coordinate.
    @ObjCMethod("coordinate") func annotationCoordinate() -> CLLocationCoordinate2D
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

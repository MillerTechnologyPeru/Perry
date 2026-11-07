import CPerryGeometry
import PerryObjCInterop

// What MKAnnotationView, MKPinAnnotationView and MKMarkerAnnotationView do
// on either platform: they keep what they are given; with no map drawn,
// they are not shown. Each provider's classes, UIViews or NSViews, add
// these categories when they are defined.

public final class AnnotationViewState: ObjectState {
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

public enum AnnotationViews {
    public static let states = StateTable<AnnotationViewState>()

    /// What -initWithAnnotation:reuseIdentifier: keeps, once the view's
    /// superclass has initialized it.
    public static func initialize(_ view: UnsafeMutableRawPointer, annotation: NSObject?, reuseIdentifier: String?) {
        let state = states[view]
        state.annotation = annotation
        state.reuseIdentifier = reuseIdentifier
    }
}

/// An MKAnnotationView of either platform, as its methods call it.
@ObjCWrapper("MKAnnotationView")
public class AnnotationViewObject: NSObject {
    @ObjCMethod("frame") public func frame() -> CGRect
    @ObjCMethod("setFrame:") public func setFrame(_ frame: CGRect)

    public var annotationView: AnnotationViewState { AnnotationViews.states[objcObject] }
}

@ObjCCategory("AnnotationView", addedAtStartup: false)
public extension AnnotationViewObject {
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

/// A pin's: MKPinAnnotationColor red 0, green 1, purple 2.
@ObjCCategory("PinAnnotationView", addedAtStartup: false)
public extension AnnotationViewObject {
    @ObjCMethod("pinColor") func pinColor() -> Int { annotationView.pinColor }
    @ObjCMethod("setPinColor:") func setPinColor(_ color: Int) { annotationView.pinColor = color }
    @ObjCMethod("pinTintColor") func pinTintColor() -> NSObject? { annotationView.tintColor }
    @ObjCMethod("setPinTintColor:") func setPinTintColor(_ color: NSObject?) { annotationView.tintColor = color }
    @ObjCMethod("animatesDrop") func animatesDrop() -> Bool { annotationView.animatesDrop }
    @ObjCMethod("setAnimatesDrop:") func setAnimatesDrop(_ animates: Bool) { annotationView.animatesDrop = animates }
}

/// A marker's.
@ObjCCategory("MarkerAnnotationView", addedAtStartup: false)
public extension AnnotationViewObject {
    @ObjCMethod("markerTintColor") func markerTintColor() -> NSObject? { annotationView.tintColor }
    @ObjCMethod("setMarkerTintColor:") func setMarkerTintColor(_ color: NSObject?) { annotationView.tintColor = color }
    @ObjCMethod("glyphText") func glyphText() -> String? { annotationView.glyphText }
    @ObjCMethod("setGlyphText:") func setGlyphText(_ text: String?) { annotationView.glyphText = text }
    @ObjCMethod("glyphImage") func glyphImage() -> NSObject? { annotationView.glyphImage }
    @ObjCMethod("setGlyphImage:") func setGlyphImage(_ image: NSObject?) { annotationView.glyphImage = image }
    @ObjCMethod("animatesWhenAdded") func animatesWhenAdded() -> Bool { annotationView.animatesDrop }
    @ObjCMethod("setAnimatesWhenAdded:") func setAnimatesWhenAdded(_ animates: Bool) { annotationView.animatesDrop = animates }
}

public extension NSObject {
    @ObjCMethod("size") func imageSize() -> CGSize
    /// MKAnnotation's coordinate.
    @ObjCMethod("coordinate") func annotationCoordinate() -> CLLocationCoordinate2D
    @ObjCMethod("initWithAnnotation:reuseIdentifier:")
    func sendInitialize(annotation: NSObject?, reuseIdentifier: String?) -> NSObject
}

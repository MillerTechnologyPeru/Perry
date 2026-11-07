import CPerryGeometry
import Glibc
import PerryObjCInterop

// What MKMapView does on either platform: the map MapLibre draws
// (MapTiles.swift), else an empty map in the color of land. It keeps its
// region, annotations and overlays, converts between coordinates and its
// points across the region, and tells its delegate when the region
// changes. Its annotations get no views on screen.
//
// Each provider's MKMapView, a UIView or an NSView, adds the MapView
// category's methods when its class is defined and makes the tiles when it
// lays out (MapViews.layOut).

public final class MapViewState: ObjectState {
    /// Not retained, as Darwin's is weak.
    var delegate: UnsafeMutableRawPointer?
    /// MKMapType: standard 0.
    var mapType = 0
    /// The contiguous United States, as a new map shows there.
    public internal(set) var region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
                                                         span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 60))
    var showsUserLocation = false
    var userLocation: NSObject?
    var userTrackingMode = 0
    var zoomEnabled = true
    var scrollEnabled = true
    var rotateEnabled = true
    var pitchEnabled = true
    var showsCompass = true
    var showsScale = false
    var showsTraffic = false
    var showsBuildings = true
    var showsPointsOfInterest = true
    var annotations: [NSObject] = []
    var selected: [NSObject] = []
    var overlays: [NSObject] = []
    var registered: [String: ObjCClass] = [:]
    /// The size the map was last laid out at, in points.
    var size = CGSize(width: 0, height: 0)
    /// The map MapLibre draws, made at the first layout; nil without it.
    var tiles: MapTiles?
    var triedTiles = false
}

public enum MapViews {
    public static let states = StateTable<MapViewState>()

    /// The map view's land color, red, green and blue.
    public static let land: (CGFloat, CGFloat, CGFloat) = (0.96, 0.95, 0.92)

    /// Makes or resizes the map's tiles to the view and shows the region:
    /// what each MKMapView does when it lays out, `scale` its pixels to a
    /// point.
    public static func layOut(_ view: UnsafeMutableRawPointer, size: CGSize, scale: CGFloat) {
        guard size.width >= 1, size.height >= 1 else { return }
        let map = states[view]
        // A new size shows more or less of the region: the delegate hears
        // that the visible region changed.
        if size.width != map.size.width || size.height != map.size.height {
            map.size = size
            MapViewObject(view).regionDidChange(animated: false)
        }
        if map.tiles == nil, !map.triedTiles {
            map.triedTiles = true
            map.tiles = MapTiles(view: view, size: size, scale: Float(scale))
            map.tiles?.startPresenting()
        }
        map.tiles?.resize(to: size)
        map.tiles?.show(map.region)
    }
}

extension MapViewState {
    /// The region shown: the region set, widened along one axis to the
    /// view's shape, as MapLibre fits it (MapLibre.zoom) and MapKit reports
    /// it. The region set until the view has a size.
    var shownRegion: MKCoordinateRegion {
        guard size.width >= 1, size.height >= 1 else { return region }
        let zoom = MapLibre.zoom(for: region, in: size)
        let worldPoints = 512 * pow(2, zoom)
        let longitudeDelta = min(360 * Double(size.width) / worldPoints, 360)
        // Mercator: the height's share of the world's, around the center.
        func mercator(_ latitude: Double) -> Double {
            let clamped = min(max(latitude, -85.0511), 85.0511) * .pi / 180
            return log(tan(.pi / 4 + clamped / 2))
        }
        func latitude(_ y: Double) -> Double { (2 * atan(exp(y)) - .pi / 2) * 180 / .pi }
        let center = mercator(region.center.latitude)
        let half = Double(size.height) * .pi / worldPoints
        let latitudeDelta = latitude(center + half) - latitude(center - half)
        return MKCoordinateRegion(center: region.center,
                                  span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta))
    }
}

/// An MKMapView of either platform, as its methods call it: messages that
/// UIView and NSView both answer.
@ObjCWrapper("MKMapView")
public class MapViewObject: NSObject {
    @ObjCMethod("bounds") public func bounds() -> CGRect
    @ObjCMethod("convertPoint:toView:") public func convert(_ point: CGPoint, to view: NSObject?) -> CGPoint
    @ObjCMethod("convertPoint:fromView:") public func convert(_ point: CGPoint, from view: NSObject?) -> CGPoint

    public var map: MapViewState { MapViews.states[objcObject] }
}

@ObjCCategory("MapView", addedAtStartup: false)
public extension MapViewObject {
    @ObjCMethod("delegate") func delegate() -> NSObject? { map.delegate.map { NSObject($0) } }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { map.delegate = delegate?.objcObject }

    // MARK: The region

    @ObjCMethod("mapType") func mapType() -> Int { map.mapType }
    @ObjCMethod("setMapType:") func setMapType(_ type: Int) { map.mapType = type }

    /// The region shown, which the view's shape widens from the one set.
    @ObjCMethod("region") func region() -> MKCoordinateRegion { map.shownRegion }
    @ObjCMethod("setRegion:") func setRegion(_ region: MKCoordinateRegion) { setRegion(region, animated: false) }

    /// The region, its span within the world, as the delegate hears: that
    /// it will change now, and that it did once the map has moved.
    @ObjCMethod("setRegion:animated:")
    func setRegion(_ region: MKCoordinateRegion, animated: Bool) {
        let delegate = delegate()
        if let delegate, delegate.responds(to: "mapView:regionWillChangeAnimated:") { delegate.sendMapView(self, regionWillChangeAnimated: animated) }
        map.region = MKCoordinateRegion(center: region.center, span: MKCoordinateSpan(
            latitudeDelta: min(max(region.span.latitudeDelta, 0), 180), longitudeDelta: min(max(region.span.longitudeDelta, 0), 360)))
        map.tiles?.show(map.region)
        regionDidChange(animated: animated)
    }

    /// Tells the delegate, once the map has moved, that the visible region
    /// changed.
    func regionDidChange(animated: Bool) {
        let owner = self
        Dispatch.onMain {
            guard let delegate = owner.delegate() else { return }
            if delegate.responds(to: "mapViewDidChangeVisibleRegion:") { delegate.sendMapViewDidChangeVisibleRegion(owner) }
            if delegate.responds(to: "mapView:regionDidChangeAnimated:") { delegate.sendMapView(owner, regionDidChangeAnimated: animated) }
        }
    }

    @ObjCMethod("regionThatFits:") func regionThatFits(_ region: MKCoordinateRegion) -> MKCoordinateRegion { region }

    @ObjCMethod("centerCoordinate") func centerCoordinate() -> CLLocationCoordinate2D { map.region.center }
    @ObjCMethod("setCenterCoordinate:") func setCenterCoordinate(_ center: CLLocationCoordinate2D) { setCenterCoordinate(center, animated: false) }
    @ObjCMethod("setCenterCoordinate:animated:")
    func setCenterCoordinate(_ center: CLLocationCoordinate2D, animated: Bool) {
        setRegion(MKCoordinateRegion(center: center, span: map.region.span), animated: animated)
    }

    @ObjCMethod("visibleMapRect") func visibleMapRect() -> MKMapRect { MapGeometry.rect(map.shownRegion) }
    @ObjCMethod("setVisibleMapRect:") func setVisibleMapRect(_ rect: MKMapRect) { setVisibleMapRect(rect, animated: false) }
    @ObjCMethod("setVisibleMapRect:animated:")
    func setVisibleMapRect(_ rect: MKMapRect, animated: Bool) { setRegion(MapGeometry.region(rect), animated: animated) }
    @ObjCMethod("setVisibleMapRect:edgePadding:animated:")
    func setVisibleMapRect(_ rect: MKMapRect, edgePadding: UIEdgeInsets, animated: Bool) { setVisibleMapRect(rect, animated: animated) }
    @ObjCMethod("mapRectThatFits:") func mapRectThatFits(_ rect: MKMapRect) -> MKMapRect { rect }

    // MARK: Conversions, across the region, in the view's coordinates
    // (top first: both platforms' map views are flipped)

    @ObjCMethod("convertCoordinate:toPointToView:")
    func convert(_ coordinate: CLLocationCoordinate2D, toPointTo view: NSObject?) -> CGPoint {
        let bounds = self.bounds(), region = map.shownRegion
        let span = region.span
        let x = span.longitudeDelta > 0 ? (coordinate.longitude - (region.center.longitude - span.longitudeDelta / 2)) / span.longitudeDelta : 0.5
        let y = span.latitudeDelta > 0 ? ((region.center.latitude + span.latitudeDelta / 2) - coordinate.latitude) / span.latitudeDelta : 0.5
        let point = CGPoint(x: bounds.origin.x + CGFloat(x) * bounds.size.width, y: bounds.origin.y + CGFloat(y) * bounds.size.height)
        return view.map { convert(point, to: $0) } ?? point
    }

    @ObjCMethod("convertPoint:toCoordinateFromView:")
    func convert(_ point: CGPoint, toCoordinateFrom view: NSObject?) -> CLLocationCoordinate2D {
        let local = view.map { convert(point, from: $0) } ?? point
        let bounds = self.bounds(), region = map.shownRegion
        let x = Double(bounds.size.width > 0 ? (local.x - bounds.origin.x) / bounds.size.width : 0.5)
        let y = Double(bounds.size.height > 0 ? (local.y - bounds.origin.y) / bounds.size.height : 0.5)
        return CLLocationCoordinate2D(latitude: region.center.latitude + region.span.latitudeDelta * (0.5 - y),
                                      longitude: region.center.longitude + region.span.longitudeDelta * (x - 0.5))
    }

    @ObjCMethod("convertRegion:toRectToView:")
    func convert(_ region: MKCoordinateRegion, toRectTo view: NSObject?) -> CGRect {
        let topLeft = convert(CLLocationCoordinate2D(latitude: region.center.latitude + region.span.latitudeDelta / 2,
                                                     longitude: region.center.longitude - region.span.longitudeDelta / 2), toPointTo: view)
        let bottomRight = convert(CLLocationCoordinate2D(latitude: region.center.latitude - region.span.latitudeDelta / 2,
                                                         longitude: region.center.longitude + region.span.longitudeDelta / 2), toPointTo: view)
        return CGRect(origin: topLeft, size: CGSize(width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y))
    }

    @ObjCMethod("convertRect:toRegionFromView:")
    func convert(_ rect: CGRect, toRegionFrom view: NSObject?) -> MKCoordinateRegion {
        let topLeft = convert(rect.origin, toCoordinateFrom: view)
        let bottomRight = convert(CGPoint(x: rect.origin.x + rect.size.width, y: rect.origin.y + rect.size.height), toCoordinateFrom: view)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (topLeft.latitude + bottomRight.latitude) / 2,
                                           longitude: (topLeft.longitude + bottomRight.longitude) / 2),
            span: MKCoordinateSpan(latitudeDelta: topLeft.latitude - bottomRight.latitude,
                                   longitudeDelta: bottomRight.longitude - topLeft.longitude))
    }

    // MARK: Interaction and decoration

    @ObjCMethod("isZoomEnabled") func isZoomEnabled() -> Bool { map.zoomEnabled }
    @ObjCMethod("setZoomEnabled:") func setZoomEnabled(_ enabled: Bool) { map.zoomEnabled = enabled }
    @ObjCMethod("isScrollEnabled") func isScrollEnabled() -> Bool { map.scrollEnabled }
    @ObjCMethod("setScrollEnabled:") func setScrollEnabled(_ enabled: Bool) { map.scrollEnabled = enabled }
    @ObjCMethod("isRotateEnabled") func isRotateEnabled() -> Bool { map.rotateEnabled }
    @ObjCMethod("setRotateEnabled:") func setRotateEnabled(_ enabled: Bool) { map.rotateEnabled = enabled }
    @ObjCMethod("isPitchEnabled") func isPitchEnabled() -> Bool { map.pitchEnabled }
    @ObjCMethod("setPitchEnabled:") func setPitchEnabled(_ enabled: Bool) { map.pitchEnabled = enabled }
    @ObjCMethod("showsCompass") func showsCompass() -> Bool { map.showsCompass }
    @ObjCMethod("setShowsCompass:") func setShowsCompass(_ shows: Bool) { map.showsCompass = shows }
    @ObjCMethod("showsScale") func showsScale() -> Bool { map.showsScale }
    @ObjCMethod("setShowsScale:") func setShowsScale(_ shows: Bool) { map.showsScale = shows }
    @ObjCMethod("showsTraffic") func showsTraffic() -> Bool { map.showsTraffic }
    @ObjCMethod("setShowsTraffic:") func setShowsTraffic(_ shows: Bool) { map.showsTraffic = shows }
    @ObjCMethod("showsBuildings") func showsBuildings() -> Bool { map.showsBuildings }
    @ObjCMethod("setShowsBuildings:") func setShowsBuildings(_ shows: Bool) { map.showsBuildings = shows }
    @ObjCMethod("showsPointsOfInterest") func showsPointsOfInterest() -> Bool { map.showsPointsOfInterest }
    @ObjCMethod("setShowsPointsOfInterest:") func setShowsPointsOfInterest(_ shows: Bool) { map.showsPointsOfInterest = shows }

    // MARK: The user's location

    @ObjCMethod("showsUserLocation") func showsUserLocation() -> Bool { map.showsUserLocation }
    @ObjCMethod("setShowsUserLocation:") func setShowsUserLocation(_ shows: Bool) { map.showsUserLocation = shows }
    @ObjCMethod("isUserLocationVisible")
    func isUserLocationVisible() -> Bool {
        guard map.showsUserLocation, let coordinate = DeviceLocation.coordinate else { return false }
        return MapGeometry.contains(MapGeometry.rect(map.shownRegion), MapGeometry.point(coordinate))
    }
    /// An MKUserLocation, which PerryMapKit defines for both platforms.
    @ObjCMethod("userLocation")
    func userLocation() -> NSObject {
        if let location = map.userLocation { return location }
        let location = ObjCClass(named: "MKUserLocation").object.allocated().initialized()
        map.userLocation = location
        return location
    }
    @ObjCMethod("userTrackingMode") func userTrackingMode() -> Int { map.userTrackingMode }
    @ObjCMethod("setUserTrackingMode:") func setUserTrackingMode(_ mode: Int) { map.userTrackingMode = mode }
    @ObjCMethod("setUserTrackingMode:animated:") func setUserTrackingMode(_ mode: Int, animated: Bool) { map.userTrackingMode = mode }

    // MARK: Annotations

    @ObjCMethod("annotations") func annotations() -> NSObject { NSMutableArray.of(map.annotations) }
    @ObjCMethod("addAnnotation:") func addAnnotation(_ annotation: NSObject) { addAnnotations([annotation]) }
    @ObjCMethod("addAnnotations:") func addAnnotations(_ annotations: NSArray) { addAnnotations(annotations.elements) }

    func addAnnotations(_ annotations: [NSObject]) {
        for annotation in annotations where !map.annotations.contains(where: { $0.objcObject == annotation.objcObject }) {
            map.annotations.append(annotation)
        }
    }

    @ObjCMethod("removeAnnotation:") func removeAnnotation(_ annotation: NSObject) { removeAnnotations([annotation]) }
    @ObjCMethod("removeAnnotations:") func removeAnnotations(_ annotations: NSArray) { removeAnnotations(annotations.elements) }

    func removeAnnotations(_ annotations: [NSObject]) {
        let removed = Set(annotations.map(\.objcObject))
        map.annotations.removeAll { removed.contains($0.objcObject) }
        map.selected.removeAll { removed.contains($0.objcObject) }
    }

    @ObjCMethod("annotationsInMapRect:")
    func annotations(in rect: MKMapRect) -> NSObject {
        NSMutableSet.of(map.annotations.filter { MapGeometry.contains(rect, MapGeometry.point($0.annotationCoordinate())) })
    }

    /// The region around the annotations, a little larger, as MapKit fits
    /// them.
    @ObjCMethod("showAnnotations:animated:")
    func showAnnotations(_ annotations: NSArray, animated: Bool) {
        let coordinates = annotations.elements.map { $0.annotationCoordinate() }
        guard let first = coordinates.first else { return }
        var (minLatitude, maxLatitude, minLongitude, maxLongitude) = (first.latitude, first.latitude, first.longitude, first.longitude)
        for coordinate in coordinates {
            minLatitude = min(minLatitude, coordinate.latitude)
            maxLatitude = max(maxLatitude, coordinate.latitude)
            minLongitude = min(minLongitude, coordinate.longitude)
            maxLongitude = max(maxLongitude, coordinate.longitude)
        }
        addAnnotations(annotations.elements)
        setRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLatitude + maxLatitude) / 2, longitude: (minLongitude + maxLongitude) / 2),
            span: MKCoordinateSpan(latitudeDelta: max((maxLatitude - minLatitude) * 1.2, 0.01),
                                   longitudeDelta: max((maxLongitude - minLongitude) * 1.2, 0.01))), animated: animated)
    }

    @ObjCMethod("selectedAnnotations") func selectedAnnotations() -> NSObject { NSMutableArray.of(map.selected) }
    @ObjCMethod("setSelectedAnnotations:") func setSelectedAnnotations(_ annotations: NSArray?) { map.selected = annotations?.elements ?? [] }
    @ObjCMethod("selectAnnotation:animated:") func selectAnnotation(_ annotation: NSObject, animated: Bool) { map.selected = [annotation] }
    @ObjCMethod("deselectAnnotation:animated:")
    func deselectAnnotation(_ annotation: NSObject?, animated: Bool) {
        map.selected.removeAll { $0.objcObject == annotation?.objcObject }
    }

    /// No annotation has a view on screen.
    @ObjCMethod("viewForAnnotation:") func view(for annotation: NSObject) -> NSObject? { nil }
    @ObjCMethod("dequeueReusableAnnotationViewWithIdentifier:")
    func dequeueReusableAnnotationView(withIdentifier identifier: String) -> NSObject? { nil }

    /// A new view of the class registered for the identifier, or a marker,
    /// of the platform's annotation views.
    @ObjCMethod("dequeueReusableAnnotationViewWithIdentifier:forAnnotation:")
    func dequeueReusableAnnotationView(withIdentifier identifier: String, for annotation: NSObject) -> NSObject {
        let cls = map.registered[identifier] ?? ObjCClass(named: "MKMarkerAnnotationView")
        return cls.object.allocated().sendInitialize(annotation: annotation, reuseIdentifier: identifier)
    }

    @ObjCMethod("registerClass:forAnnotationViewWithReuseIdentifier:")
    func register(_ cls: ObjCClass?, forAnnotationViewWithReuseIdentifier identifier: String) { map.registered[identifier] = cls }

    // MARK: Overlays

    @ObjCMethod("overlays") func overlays() -> NSObject { NSMutableArray.of(map.overlays) }
    @ObjCMethod("addOverlay:") func addOverlay(_ overlay: NSObject) { map.overlays.append(overlay) }
    @ObjCMethod("addOverlay:level:") func addOverlay(_ overlay: NSObject, level: Int) { map.overlays.append(overlay) }
    @ObjCMethod("addOverlays:") func addOverlays(_ overlays: NSArray) { map.overlays += overlays.elements }
    @ObjCMethod("addOverlays:level:") func addOverlays(_ overlays: NSArray, level: Int) { map.overlays += overlays.elements }
    @ObjCMethod("insertOverlay:atIndex:")
    func insertOverlay(_ overlay: NSObject, at index: Int) { map.overlays.insert(overlay, at: min(max(index, 0), map.overlays.count)) }
    @ObjCMethod("removeOverlay:") func removeOverlay(_ overlay: NSObject) { map.overlays.removeAll { $0.objcObject == overlay.objcObject } }
    @ObjCMethod("removeOverlays:")
    func removeOverlays(_ overlays: NSArray) {
        let removed = Set(overlays.elements.map(\.objcObject))
        map.overlays.removeAll { removed.contains($0.objcObject) }
    }
    @ObjCMethod("rendererForOverlay:") func renderer(for overlay: NSObject) -> NSObject? { nil }
}

/// MKMapViewDelegate's messages.
extension NSObject {
    @ObjCMethod("mapView:regionWillChangeAnimated:")
    func sendMapView(_ mapView: MapViewObject, regionWillChangeAnimated animated: Bool)

    @ObjCMethod("mapView:regionDidChangeAnimated:")
    func sendMapView(_ mapView: MapViewObject, regionDidChangeAnimated animated: Bool)

    @ObjCMethod("mapViewDidChangeVisibleRegion:")
    func sendMapViewDidChangeVisibleRegion(_ mapView: MapViewObject)
}

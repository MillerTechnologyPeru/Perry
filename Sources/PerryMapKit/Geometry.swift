import CPerryGeometry
import Glibc
import PerryMapKitShared
import PerryObjCInterop

// MapKit's geometry functions and string constants, over the shared
// geometry (PerryMapKitShared).

@DarwinC("_MKCoordinateSpanMake")
public func MKCoordinateSpanMake(_ latitudeDelta: Double, _ longitudeDelta: Double) -> MKCoordinateSpan {
    MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
}

@DarwinC("_MKCoordinateRegionMake")
public func MKCoordinateRegionMake(_ center: CLLocationCoordinate2D, _ span: MKCoordinateSpan) -> MKCoordinateRegion {
    MKCoordinateRegion(center: center, span: span)
}

/// A region `latitudinalMeters` tall and `longitudinalMeters` wide.
@DarwinC("_MKCoordinateRegionMakeWithDistance")
public func MKCoordinateRegionMakeWithDistance(_ center: CLLocationCoordinate2D, _ latitudinalMeters: Double,
                                               _ longitudinalMeters: Double) -> MKCoordinateRegion {
    let longitudeScale = max(cos(center.latitude * .pi / 180), 0.000001)
    return MKCoordinateRegion(center: center, span: MKCoordinateSpan(
        latitudeDelta: latitudinalMeters / MapGeometry.metersPerDegree,
        longitudeDelta: longitudinalMeters / (MapGeometry.metersPerDegree * longitudeScale)))
}

@DarwinC("_MKCoordinateRegionForMapRect")
public func MKCoordinateRegionForMapRect(_ rect: MKMapRect) -> MKCoordinateRegion { MapGeometry.region(rect) }

@DarwinC("_MKMapPointForCoordinate")
public func MKMapPointForCoordinate(_ coordinate: CLLocationCoordinate2D) -> MKMapPoint { MapGeometry.point(coordinate) }

@DarwinC("_MKCoordinateForMapPoint")
public func MKCoordinateForMapPoint(_ point: MKMapPoint) -> CLLocationCoordinate2D { MapGeometry.coordinate(point) }

@DarwinC("_MKMetersPerMapPointAtLatitude")
public func MKMetersPerMapPointAtLatitude(_ latitude: Double) -> Double { MapGeometry.metersPerMapPoint(latitude) }

@DarwinC("_MKMapPointsPerMeterAtLatitude")
public func MKMapPointsPerMeterAtLatitude(_ latitude: Double) -> Double { 1 / MapGeometry.metersPerMapPoint(latitude) }

@DarwinC("_MKMetersBetweenMapPoints")
public func MKMetersBetweenMapPoints(_ a: MKMapPoint, _ b: MKMapPoint) -> Double {
    let from = MapGeometry.coordinate(a), to = MapGeometry.coordinate(b)
    let radians = Double.pi / 180
    let Δφ = (to.latitude - from.latitude) * radians, Δλ = (to.longitude - from.longitude) * radians
    let h = sin(Δφ / 2) * sin(Δφ / 2) + cos(from.latitude * radians) * cos(to.latitude * radians) * sin(Δλ / 2) * sin(Δλ / 2)
    return 6_371_008.8 * 2 * atan2(h.squareRoot(), (1 - h).squareRoot())
}

@DarwinC("_MKMapRectUnion") public func MKMapRectUnion(_ a: MKMapRect, _ b: MKMapRect) -> MKMapRect { MapGeometry.union(a, b) }
@DarwinC("_MKMapRectIntersection") public func MKMapRectIntersection(_ a: MKMapRect, _ b: MKMapRect) -> MKMapRect { MapGeometry.intersection(a, b) }
@DarwinC("_MKMapRectIntersectsRect")
public func MKMapRectIntersectsRect(_ a: MKMapRect, _ b: MKMapRect) -> Bool { !MapGeometry.isNull(MapGeometry.intersection(a, b)) }
@DarwinC("_MKMapRectContainsPoint") public func MKMapRectContainsPoint(_ rect: MKMapRect, _ point: MKMapPoint) -> Bool { MapGeometry.contains(rect, point) }

@DarwinC("_MKMapRectContainsRect")
public func MKMapRectContainsRect(_ a: MKMapRect, _ b: MKMapRect) -> Bool {
    let both = MapGeometry.intersection(a, b)
    return !MapGeometry.isNull(both) && both.origin.x == b.origin.x && both.origin.y == b.origin.y
        && both.size.width == b.size.width && both.size.height == b.size.height
}

@DarwinC("_MKMapRectInset")
public func MKMapRectInset(_ rect: MKMapRect, _ dx: Double, _ dy: Double) -> MKMapRect {
    MKMapRect(origin: MKMapPoint(x: rect.origin.x + dx, y: rect.origin.y + dy),
              size: MKMapSize(width: rect.size.width - 2 * dx, height: rect.size.height - 2 * dy))
}

@DarwinC("_MKMapRectOffset")
public func MKMapRectOffset(_ rect: MKMapRect, _ dx: Double, _ dy: Double) -> MKMapRect {
    MKMapRect(origin: MKMapPoint(x: rect.origin.x + dx, y: rect.origin.y + dy), size: rect.size)
}

@DarwinC("_MKMapRectSpans180thMeridian")
public func MKMapRectSpans180thMeridian(_ rect: MKMapRect) -> Bool { rect.origin.x + rect.size.width > MapGeometry.worldSize.width }

@ObjCConstants
enum MapConstants {
    static let MKLaunchOptionsDirectionsModeKey = "MKLaunchOptionsDirectionsMode"
    static let MKLaunchOptionsMapTypeKey = "MKLaunchOptionsMapType"
    static let MKLaunchOptionsMapCenterKey = "MKLaunchOptionsMapCenter"
    static let MKLaunchOptionsMapSpanKey = "MKLaunchOptionsMapSpan"
    static let MKLaunchOptionsShowsTrafficKey = "MKLaunchOptionsShowsTraffic"
    static let MKLaunchOptionsCameraKey = "MKLaunchOptionsCamera"
    static let MKLaunchOptionsDirectionsModeDefault = "MKLaunchOptionsDirectionsModeDefault"
    static let MKLaunchOptionsDirectionsModeDriving = "MKLaunchOptionsDirectionsModeDriving"
    static let MKLaunchOptionsDirectionsModeWalking = "MKLaunchOptionsDirectionsModeWalking"
    static let MKLaunchOptionsDirectionsModeTransit = "MKLaunchOptionsDirectionsModeTransit"
    static let MKAnnotationCalloutInfoDidChangeNotification = "MKAnnotationCalloutInfoDidChangeNotification"
    static let MKErrorDomain = "MKErrorDomain"
}

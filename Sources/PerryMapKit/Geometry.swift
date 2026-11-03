import CPerryGeometry
import Glibc
import PerryObjCInterop

// MapKit's geometry: regions in degrees, and map points on the Web Mercator
// projection of the world onto a square 2^28 points across, as MapKit's.

extension CLLocationCoordinate2D: ObjCScalar { public static var objCTypeEncoding: String { "{CLLocationCoordinate2D=dd}" } }
extension MKCoordinateSpan: ObjCScalar { public static var objCTypeEncoding: String { "{MKCoordinateSpan=dd}" } }
extension MKCoordinateRegion: ObjCScalar {
    public static var objCTypeEncoding: String { "{MKCoordinateRegion={CLLocationCoordinate2D=dd}{MKCoordinateSpan=dd}}" }
}
extension MKMapPoint: ObjCScalar { public static var objCTypeEncoding: String { "{MKMapPoint=dd}" } }
extension MKMapSize: ObjCScalar { public static var objCTypeEncoding: String { "{MKMapSize=dd}" } }
extension MKMapRect: ObjCScalar { public static var objCTypeEncoding: String { "{MKMapRect={MKMapPoint=dd}{MKMapSize=dd}}" } }

enum MapGeometry {
    static let worldSize = MKMapSize(width: 268_435_456, height: 268_435_456)
    static let nullRect = MKMapRect(origin: MKMapPoint(x: .infinity, y: .infinity), size: MKMapSize(width: 0, height: 0))
    /// Meters in a degree of latitude.
    static let metersPerDegree = 111_319.9

    static func point(_ coordinate: CLLocationCoordinate2D) -> MKMapPoint {
        let latitude = min(max(coordinate.latitude, -85.05112878), 85.05112878) * .pi / 180
        let x = (coordinate.longitude + 180) / 360 * worldSize.width
        let y = (1 - log(tan(latitude) + 1 / cos(latitude)) / .pi) / 2 * worldSize.height
        return MKMapPoint(x: x, y: y)
    }

    static func coordinate(_ point: MKMapPoint) -> CLLocationCoordinate2D {
        let longitude = point.x / worldSize.width * 360 - 180
        let n = Double.pi * (1 - 2 * point.y / worldSize.height)
        return CLLocationCoordinate2D(latitude: atan(sinh(n)) * 180 / .pi, longitude: longitude)
    }

    static func region(_ rect: MKMapRect) -> MKCoordinateRegion {
        let topLeft = coordinate(rect.origin)
        let bottomRight = coordinate(MKMapPoint(x: rect.origin.x + rect.size.width, y: rect.origin.y + rect.size.height))
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (topLeft.latitude + bottomRight.latitude) / 2,
                                           longitude: (topLeft.longitude + bottomRight.longitude) / 2),
            span: MKCoordinateSpan(latitudeDelta: topLeft.latitude - bottomRight.latitude,
                                   longitudeDelta: bottomRight.longitude - topLeft.longitude))
    }

    static func rect(_ region: MKCoordinateRegion) -> MKMapRect {
        let topLeft = point(CLLocationCoordinate2D(latitude: region.center.latitude + region.span.latitudeDelta / 2,
                                                   longitude: region.center.longitude - region.span.longitudeDelta / 2))
        let bottomRight = point(CLLocationCoordinate2D(latitude: region.center.latitude - region.span.latitudeDelta / 2,
                                                       longitude: region.center.longitude + region.span.longitudeDelta / 2))
        return MKMapRect(origin: topLeft, size: MKMapSize(width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y))
    }

    static func isNull(_ rect: MKMapRect) -> Bool { rect.origin.x.isInfinite || rect.origin.y.isInfinite }

    static func union(_ a: MKMapRect, _ b: MKMapRect) -> MKMapRect {
        if isNull(a) { return b }
        if isNull(b) { return a }
        let minX = min(a.origin.x, b.origin.x), minY = min(a.origin.y, b.origin.y)
        let maxX = max(a.origin.x + a.size.width, b.origin.x + b.size.width), maxY = max(a.origin.y + a.size.height, b.origin.y + b.size.height)
        return MKMapRect(origin: MKMapPoint(x: minX, y: minY), size: MKMapSize(width: maxX - minX, height: maxY - minY))
    }

    static func intersection(_ a: MKMapRect, _ b: MKMapRect) -> MKMapRect {
        let minX = max(a.origin.x, b.origin.x), minY = max(a.origin.y, b.origin.y)
        let maxX = min(a.origin.x + a.size.width, b.origin.x + b.size.width), maxY = min(a.origin.y + a.size.height, b.origin.y + b.size.height)
        guard !isNull(a), !isNull(b), maxX >= minX, maxY >= minY else { return nullRect }
        return MKMapRect(origin: MKMapPoint(x: minX, y: minY), size: MKMapSize(width: maxX - minX, height: maxY - minY))
    }

    static func contains(_ rect: MKMapRect, _ point: MKMapPoint) -> Bool {
        point.x >= rect.origin.x && point.x < rect.origin.x + rect.size.width
            && point.y >= rect.origin.y && point.y < rect.origin.y + rect.size.height
    }

    /// Meters a map point spans at a latitude.
    static func metersPerMapPoint(_ latitude: Double) -> Double {
        40_075_016.686 * cos(latitude * .pi / 180) / worldSize.width
    }
}

@c(_MKCoordinateSpanMake)
public func MKCoordinateSpanMake(_ latitudeDelta: Double, _ longitudeDelta: Double) -> MKCoordinateSpan {
    MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
}

@c(_MKCoordinateRegionMake)
public func MKCoordinateRegionMake(_ center: CLLocationCoordinate2D, _ span: MKCoordinateSpan) -> MKCoordinateRegion {
    MKCoordinateRegion(center: center, span: span)
}

/// A region `latitudinalMeters` tall and `longitudinalMeters` wide.
@c(_MKCoordinateRegionMakeWithDistance)
public func MKCoordinateRegionMakeWithDistance(_ center: CLLocationCoordinate2D, _ latitudinalMeters: Double,
                                               _ longitudinalMeters: Double) -> MKCoordinateRegion {
    let longitudeScale = max(cos(center.latitude * .pi / 180), 0.000001)
    return MKCoordinateRegion(center: center, span: MKCoordinateSpan(
        latitudeDelta: latitudinalMeters / MapGeometry.metersPerDegree,
        longitudeDelta: longitudinalMeters / (MapGeometry.metersPerDegree * longitudeScale)))
}

@c(_MKCoordinateRegionForMapRect)
public func MKCoordinateRegionForMapRect(_ rect: MKMapRect) -> MKCoordinateRegion { MapGeometry.region(rect) }

@c(_MKMapPointForCoordinate)
public func MKMapPointForCoordinate(_ coordinate: CLLocationCoordinate2D) -> MKMapPoint { MapGeometry.point(coordinate) }

@c(_MKCoordinateForMapPoint)
public func MKCoordinateForMapPoint(_ point: MKMapPoint) -> CLLocationCoordinate2D { MapGeometry.coordinate(point) }

@c(_MKMetersPerMapPointAtLatitude)
public func MKMetersPerMapPointAtLatitude(_ latitude: Double) -> Double { MapGeometry.metersPerMapPoint(latitude) }

@c(_MKMapPointsPerMeterAtLatitude)
public func MKMapPointsPerMeterAtLatitude(_ latitude: Double) -> Double { 1 / MapGeometry.metersPerMapPoint(latitude) }

@c(_MKMetersBetweenMapPoints)
public func MKMetersBetweenMapPoints(_ a: MKMapPoint, _ b: MKMapPoint) -> Double {
    let from = MapGeometry.coordinate(a), to = MapGeometry.coordinate(b)
    let radians = Double.pi / 180
    let Δφ = (to.latitude - from.latitude) * radians, Δλ = (to.longitude - from.longitude) * radians
    let h = sin(Δφ / 2) * sin(Δφ / 2) + cos(from.latitude * radians) * cos(to.latitude * radians) * sin(Δλ / 2) * sin(Δλ / 2)
    return 6_371_008.8 * 2 * atan2(h.squareRoot(), (1 - h).squareRoot())
}

@c(_MKMapRectUnion) public func MKMapRectUnion(_ a: MKMapRect, _ b: MKMapRect) -> MKMapRect { MapGeometry.union(a, b) }
@c(_MKMapRectIntersection) public func MKMapRectIntersection(_ a: MKMapRect, _ b: MKMapRect) -> MKMapRect { MapGeometry.intersection(a, b) }
@c(_MKMapRectIntersectsRect)
public func MKMapRectIntersectsRect(_ a: MKMapRect, _ b: MKMapRect) -> Bool { !MapGeometry.isNull(MapGeometry.intersection(a, b)) }
@c(_MKMapRectContainsPoint) public func MKMapRectContainsPoint(_ rect: MKMapRect, _ point: MKMapPoint) -> Bool { MapGeometry.contains(rect, point) }

@c(_MKMapRectContainsRect)
public func MKMapRectContainsRect(_ a: MKMapRect, _ b: MKMapRect) -> Bool {
    let both = MapGeometry.intersection(a, b)
    return !MapGeometry.isNull(both) && both.origin.x == b.origin.x && both.origin.y == b.origin.y
        && both.size.width == b.size.width && both.size.height == b.size.height
}

@c(_MKMapRectInset)
public func MKMapRectInset(_ rect: MKMapRect, _ dx: Double, _ dy: Double) -> MKMapRect {
    MKMapRect(origin: MKMapPoint(x: rect.origin.x + dx, y: rect.origin.y + dy),
              size: MKMapSize(width: rect.size.width - 2 * dx, height: rect.size.height - 2 * dy))
}

@c(_MKMapRectOffset)
public func MKMapRectOffset(_ rect: MKMapRect, _ dx: Double, _ dy: Double) -> MKMapRect {
    MKMapRect(origin: MKMapPoint(x: rect.origin.x + dx, y: rect.origin.y + dy), size: rect.size)
}

@c(_MKMapRectSpans180thMeridian)
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

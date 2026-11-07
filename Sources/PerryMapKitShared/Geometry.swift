import CPerryGeometry
import Glibc
import PerryObjCInterop

// MapKit's geometry: regions in degrees, and map points on the Web Mercator
// projection of the world onto a square 2^28 points across, as MapKit's.

extension CLLocationCoordinate2D: ObjCStructure {
    #if _pointerBitWidth(_32)
    public typealias ObjCType = ObjCWords4
    public static var objCTypeEncoding: String { "{CLLocationCoordinate2D=dd}" }
    #else
    public typealias ObjCType = CLLocationCoordinate2D
    public static var objCTypeEncoding: String { "{CLLocationCoordinate2D=dd}" }
    #endif
}
extension MKCoordinateSpan: ObjCStructure {
    #if _pointerBitWidth(_32)
    public typealias ObjCType = ObjCWords4
    public static var objCTypeEncoding: String { "{MKCoordinateSpan=dd}" }
    #else
    public typealias ObjCType = MKCoordinateSpan
    public static var objCTypeEncoding: String { "{MKCoordinateSpan=dd}" }
    #endif
}
extension MKCoordinateRegion: ObjCStructure {
    #if _pointerBitWidth(_32)
    public typealias ObjCType = ObjCWords8
    public static var objCTypeEncoding: String { "{MKCoordinateRegion={CLLocationCoordinate2D=dd}{MKCoordinateSpan=dd}}" }
    #else
    public typealias ObjCType = MKCoordinateRegion
    public static var objCTypeEncoding: String { "{MKCoordinateRegion={CLLocationCoordinate2D=dd}{MKCoordinateSpan=dd}}" }
    #endif
}
extension MKMapPoint: ObjCStructure {
    #if _pointerBitWidth(_32)
    public typealias ObjCType = ObjCWords4
    public static var objCTypeEncoding: String { "{MKMapPoint=dd}" }
    #else
    public typealias ObjCType = MKMapPoint
    public static var objCTypeEncoding: String { "{MKMapPoint=dd}" }
    #endif
}
extension MKMapSize: ObjCStructure {
    #if _pointerBitWidth(_32)
    public typealias ObjCType = ObjCWords4
    public static var objCTypeEncoding: String { "{MKMapSize=dd}" }
    #else
    public typealias ObjCType = MKMapSize
    public static var objCTypeEncoding: String { "{MKMapSize=dd}" }
    #endif
}
extension MKMapRect: ObjCStructure {
    #if _pointerBitWidth(_32)
    public typealias ObjCType = ObjCWords8
    public static var objCTypeEncoding: String { "{MKMapRect={MKMapPoint=dd}{MKMapSize=dd}}" }
    #else
    public typealias ObjCType = MKMapRect
    public static var objCTypeEncoding: String { "{MKMapRect={MKMapPoint=dd}{MKMapSize=dd}}" }
    #endif
}

public enum MapGeometry {
    public static let worldSize = MKMapSize(width: 268_435_456, height: 268_435_456)
    public static let nullRect = MKMapRect(origin: MKMapPoint(x: .infinity, y: .infinity), size: MKMapSize(width: 0, height: 0))
    /// Meters in a degree of latitude.
    public static let metersPerDegree = 111_319.9

    public static func point(_ coordinate: CLLocationCoordinate2D) -> MKMapPoint {
        let latitude = min(max(coordinate.latitude, -85.05112878), 85.05112878) * .pi / 180
        let x = (coordinate.longitude + 180) / 360 * worldSize.width
        let y = (1 - log(tan(latitude) + 1 / cos(latitude)) / .pi) / 2 * worldSize.height
        return MKMapPoint(x: x, y: y)
    }

    public static func coordinate(_ point: MKMapPoint) -> CLLocationCoordinate2D {
        let longitude = point.x / worldSize.width * 360 - 180
        let n = Double.pi * (1 - 2 * point.y / worldSize.height)
        return CLLocationCoordinate2D(latitude: atan(sinh(n)) * 180 / .pi, longitude: longitude)
    }

    public static func region(_ rect: MKMapRect) -> MKCoordinateRegion {
        let topLeft = coordinate(rect.origin)
        let bottomRight = coordinate(MKMapPoint(x: rect.origin.x + rect.size.width, y: rect.origin.y + rect.size.height))
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (topLeft.latitude + bottomRight.latitude) / 2,
                                           longitude: (topLeft.longitude + bottomRight.longitude) / 2),
            span: MKCoordinateSpan(latitudeDelta: topLeft.latitude - bottomRight.latitude,
                                   longitudeDelta: bottomRight.longitude - topLeft.longitude))
    }

    public static func rect(_ region: MKCoordinateRegion) -> MKMapRect {
        let topLeft = point(CLLocationCoordinate2D(latitude: region.center.latitude + region.span.latitudeDelta / 2,
                                                   longitude: region.center.longitude - region.span.longitudeDelta / 2))
        let bottomRight = point(CLLocationCoordinate2D(latitude: region.center.latitude - region.span.latitudeDelta / 2,
                                                       longitude: region.center.longitude + region.span.longitudeDelta / 2))
        return MKMapRect(origin: topLeft, size: MKMapSize(width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y))
    }

    public static func isNull(_ rect: MKMapRect) -> Bool { rect.origin.x.isInfinite || rect.origin.y.isInfinite }

    public static func union(_ a: MKMapRect, _ b: MKMapRect) -> MKMapRect {
        if isNull(a) { return b }
        if isNull(b) { return a }
        let minX = min(a.origin.x, b.origin.x), minY = min(a.origin.y, b.origin.y)
        let maxX = max(a.origin.x + a.size.width, b.origin.x + b.size.width), maxY = max(a.origin.y + a.size.height, b.origin.y + b.size.height)
        return MKMapRect(origin: MKMapPoint(x: minX, y: minY), size: MKMapSize(width: maxX - minX, height: maxY - minY))
    }

    public static func intersection(_ a: MKMapRect, _ b: MKMapRect) -> MKMapRect {
        let minX = max(a.origin.x, b.origin.x), minY = max(a.origin.y, b.origin.y)
        let maxX = min(a.origin.x + a.size.width, b.origin.x + b.size.width), maxY = min(a.origin.y + a.size.height, b.origin.y + b.size.height)
        guard !isNull(a), !isNull(b), maxX >= minX, maxY >= minY else { return nullRect }
        return MKMapRect(origin: MKMapPoint(x: minX, y: minY), size: MKMapSize(width: maxX - minX, height: maxY - minY))
    }

    public static func contains(_ rect: MKMapRect, _ point: MKMapPoint) -> Bool {
        point.x >= rect.origin.x && point.x < rect.origin.x + rect.size.width
            && point.y >= rect.origin.y && point.y < rect.origin.y + rect.size.height
    }

    /// Meters a map point spans at a latitude.
    public static func metersPerMapPoint(_ latitude: Double) -> Double {
        40_075_016.686 * cos(latitude * .pi / 180) / worldSize.width
    }
}

/// Where the device is, as CoreLocation's provider reports it:
/// PERRY_LOCATION's "latitude,longitude", Apple Park by default, or none.
public enum DeviceLocation {
    public nonisolated(unsafe) static let coordinate: CLLocationCoordinate2D? = {
        guard let setting = getenv("PERRY_LOCATION").map({ String(cString: $0) }) else {
            return CLLocationCoordinate2D(latitude: 37.334_886, longitude: -122.008_988)
        }
        let values = setting.split(separator: ",").compactMap { Double(String($0.filter { $0 != " " })) }
        guard values.count == 2, abs(values[0]) <= 90, abs(values[1]) <= 180 else { return nil }
        return CLLocationCoordinate2D(latitude: values[0], longitude: values[1])
    }()
}

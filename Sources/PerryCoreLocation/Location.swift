import CPerryGeometry
import Glibc
import PerryObjCInterop

// CLLocation and the coordinate functions and constants. Locations are
// values an app makes or is given; there is no location to be given here.

extension CLLocationCoordinate2D: ObjCScalar {
    public static var objCTypeEncoding: String { "{CLLocationCoordinate2D=dd}" }
}

enum Coordinates {
    static let invalid = CLLocationCoordinate2D(latitude: -180, longitude: -180)

    static func isValid(_ coordinate: CLLocationCoordinate2D) -> Bool {
        abs(coordinate.latitude) <= 90 && abs(coordinate.longitude) <= 180
    }

    /// The great-circle distance in meters, on a sphere of Earth's mean
    /// radius.
    static func distance(_ from: CLLocationCoordinate2D, _ to: CLLocationCoordinate2D) -> Double {
        let radians = Double.pi / 180
        let φ1 = from.latitude * radians, φ2 = to.latitude * radians
        let Δφ = φ2 - φ1, Δλ = (to.longitude - from.longitude) * radians
        let a = sin(Δφ / 2) * sin(Δφ / 2) + cos(φ1) * cos(φ2) * sin(Δλ / 2) * sin(Δλ / 2)
        return 6_371_008.8 * 2 * atan2(a.squareRoot(), (1 - a).squareRoot())
    }
}

@c(_CLLocationCoordinate2DMake)
public func CLLocationCoordinate2DMake(_ latitude: Double, _ longitude: Double) -> CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
}

@c(_CLLocationCoordinate2DIsValid)
public func CLLocationCoordinate2DIsValid(_ coordinate: CLLocationCoordinate2D) -> Bool { Coordinates.isValid(coordinate) }

@ObjCConstants
enum LocationConstants {
    static let kCLLocationAccuracyBestForNavigation: Double = -2
    static let kCLLocationAccuracyBest: Double = -1
    static let kCLLocationAccuracyNearestTenMeters: Double = 10
    static let kCLLocationAccuracyHundredMeters: Double = 100
    static let kCLLocationAccuracyKilometer: Double = 1000
    static let kCLLocationAccuracyThreeKilometers: Double = 3000
    static let kCLLocationAccuracyReduced: Double = 3000
    static let kCLDistanceFilterNone: Double = -1
    static let kCLHeadingFilterNone: Double = -1
    static let CLLocationDistanceMax: Double = 1.7976931348623157e308
    static let CLTimeIntervalMax: Double = 1.7976931348623157e308
    static let kCLErrorDomain = "kCLErrorDomain"
    static let kCLErrorUserInfoAlternateRegionKey = "alternateRegion"
}

final class LocationState: ObjectState {
    var coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    var altitude: Double = 0
    var horizontalAccuracy: Double = 0
    var verticalAccuracy: Double = -1
    var course: Double = -1
    var speed: Double = -1
    var timestamp: NSDate?
}

@ObjCClass("CLLocation")
open class CLLocation: NSObject {
    static let states = StateTable<LocationState>()
    var location: LocationState { CLLocation.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        CLLocation.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CLLocation.objCClass.pointer)
    }

    @ObjCMethod("init")
    func initialize() -> Self {
        location.timestamp = NSDate.now()
        return self
    }

    @ObjCMethod("initWithLatitude:longitude:")
    func initialize(latitude: Double, longitude: Double) -> Self {
        location.coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        location.timestamp = NSDate.now()
        return self
    }

    @ObjCMethod("initWithCoordinate:altitude:horizontalAccuracy:verticalAccuracy:timestamp:")
    func initialize(coordinate: CLLocationCoordinate2D, altitude: Double, horizontalAccuracy: Double, verticalAccuracy: Double,
                    timestamp: NSDate?) -> Self {
        initialize(coordinate: coordinate, altitude: altitude, horizontalAccuracy: horizontalAccuracy,
                   verticalAccuracy: verticalAccuracy, course: -1, speed: -1, timestamp: timestamp)
    }

    @ObjCMethod("initWithCoordinate:altitude:horizontalAccuracy:verticalAccuracy:course:speed:timestamp:")
    func initialize(coordinate: CLLocationCoordinate2D, altitude: Double, horizontalAccuracy: Double, verticalAccuracy: Double,
                    course: Double, speed: Double, timestamp: NSDate?) -> Self {
        let location = location
        location.coordinate = coordinate
        location.altitude = altitude
        location.horizontalAccuracy = horizontalAccuracy
        location.verticalAccuracy = verticalAccuracy
        location.course = course
        location.speed = speed
        location.timestamp = timestamp ?? NSDate.now()
        return self
    }

    @ObjCMethod("coordinate") func coordinate() -> CLLocationCoordinate2D { location.coordinate }
    @ObjCMethod("altitude") func altitude() -> Double { location.altitude }
    @ObjCMethod("ellipsoidalAltitude") func ellipsoidalAltitude() -> Double { location.altitude }
    @ObjCMethod("horizontalAccuracy") func horizontalAccuracy() -> Double { location.horizontalAccuracy }
    @ObjCMethod("verticalAccuracy") func verticalAccuracy() -> Double { location.verticalAccuracy }
    @ObjCMethod("course") func course() -> Double { location.course }
    @ObjCMethod("courseAccuracy") func courseAccuracy() -> Double { -1 }
    @ObjCMethod("speed") func speed() -> Double { location.speed }
    @ObjCMethod("speedAccuracy") func speedAccuracy() -> Double { -1 }
    @ObjCMethod("timestamp") func timestamp() -> NSDate? { location.timestamp }
    @ObjCMethod("floor") func floor() -> NSObject? { nil }

    /// Meters along the surface to another location.
    @ObjCMethod("distanceFromLocation:")
    func distance(from other: CLLocation) -> Double { Coordinates.distance(location.coordinate, other.location.coordinate) }

    @ObjCMethod("getDistanceFrom:")
    func getDistance(from other: CLLocation) -> Double { distance(from: other) }

    /// Immutable, so a copy is the location itself.
    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { ObjCRuntime.retain(objcObject) }

    @ObjCMethod("description")
    func description() -> String {
        let location = location
        func signed(_ value: Double) -> String {
            let text = String(format8: value)
            return value >= 0 ? "+" + text : text
        }
        return "<\(signed(location.coordinate.latitude)),\(signed(location.coordinate.longitude))> +/- "
            + "\(String(format2: location.horizontalAccuracy))m (speed \(String(format2: location.speed)) mps / "
            + "course \(String(format2: location.course)))"
    }
}

extension String {
    /// The value to 8 decimal places, as CLLocation describes coordinates.
    init(format8 value: Double) { self = Self.fixed(value, places: 8) }
    /// The value to 2 decimal places.
    init(format2 value: Double) { self = Self.fixed(value, places: 2) }

    private static func fixed(_ value: Double, places: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 64)
        _ = withVaList([value]) { vsnprintf(&buffer, buffer.count, "%.\(places)f", $0) }
        return String(cString: buffer)
    }
}

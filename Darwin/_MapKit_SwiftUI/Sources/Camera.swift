// Where a map looks: its camera and position, the bounds the camera keeps
// to, the interactions it allows, and what it tells views as it moves.

public import CoreLocation
public import Foundation
public import MapKit

// MARK: - MapCamera

/// A camera looking at a point on the map, from a distance, with a heading
/// and a pitch.
public struct MapCamera: Equatable {
    public var centerCoordinate: CLLocationCoordinate2D
    public var distance: Double
    public var heading: Double
    public var pitch: Double

    public static func == (lhs: MapCamera, rhs: MapCamera) -> Bool {
        lhs.centerCoordinate.latitude == rhs.centerCoordinate.latitude
            && lhs.centerCoordinate.longitude == rhs.centerCoordinate.longitude
            && lhs.distance == rhs.distance && lhs.heading == rhs.heading && lhs.pitch == rhs.pitch
    }

    public init(centerCoordinate: CLLocationCoordinate2D, distance: Double, heading: Double = 0, pitch: Double = 0) {
        self.centerCoordinate = centerCoordinate
        self.distance = distance
        self.heading = heading
        self.pitch = pitch
    }

    public init(_ camera: MKMapCamera) {
        self.init(centerCoordinate: camera.centerCoordinate, distance: camera.centerCoordinateDistance,
                  heading: camera.heading, pitch: camera.pitch)
    }

    /// The region a camera straight down sees across its distance.
    var region: MKCoordinateRegion {
        MapGeometry.region(center: centerCoordinate, meters: distance)
    }
}

/// Conversions between distances and spans of degrees, on a sphere.
enum MapGeometry {
    static let metersPerDegree = 111_320.0

    static func region(center: CLLocationCoordinate2D, meters: Double) -> MKCoordinateRegion {
        let latitudeDelta = max(meters / metersPerDegree, 0.0005)
        let longitudeDelta = latitudeDelta / max(cos(center.latitude * .pi / 180), 0.01)
        return MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta))
    }

    static func meters(of region: MKCoordinateRegion) -> Double {
        region.span.latitudeDelta * metersPerDegree
    }

    static func rect(of region: MKCoordinateRegion) -> MKMapRect {
        let topLeft = MKMapPoint(CLLocationCoordinate2D(
            latitude: region.center.latitude + region.span.latitudeDelta / 2,
            longitude: region.center.longitude - region.span.longitudeDelta / 2))
        let bottomRight = MKMapPoint(CLLocationCoordinate2D(
            latitude: region.center.latitude - region.span.latitudeDelta / 2,
            longitude: region.center.longitude + region.span.longitudeDelta / 2))
        return MKMapRect(x: topLeft.x, y: topLeft.y, width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y)
    }

    static func region(of rect: MKMapRect) -> MKCoordinateRegion {
        let topLeft = MKMapPoint(x: rect.minX, y: rect.minY).coordinate
        let bottomRight = MKMapPoint(x: rect.maxX, y: rect.maxY).coordinate
        let center = CLLocationCoordinate2D(latitude: (topLeft.latitude + bottomRight.latitude) / 2,
                                            longitude: (topLeft.longitude + bottomRight.longitude) / 2)
        return MKCoordinateRegion(center: center, span: MKCoordinateSpan(
            latitudeDelta: abs(topLeft.latitude - bottomRight.latitude),
            longitudeDelta: abs(bottomRight.longitude - topLeft.longitude)))
    }
}

// MARK: - MapCameraPosition

/// Where a map's camera is: chosen by the map, framing a region, a rect or
/// an item, from a camera, or following the user's location.
public struct MapCameraPosition: Equatable {
    enum Kind {
        case automatic
        case camera(MapCamera)
        case region(MKCoordinateRegion)
        case rect(MKMapRect)
        case item(MKMapItem, allowsAutomaticPitch: Bool)
        case userLocation(followsHeading: Bool)
    }

    var kind: Kind
    var fallback: [MapCameraPosition] = []
    var isPositionedByUser = false

    public static var automatic: MapCameraPosition { MapCameraPosition(kind: .automatic) }

    public static func camera(_ camera: MapCamera) -> MapCameraPosition {
        MapCameraPosition(kind: .camera(camera))
    }

    public static func region(_ region: MKCoordinateRegion) -> MapCameraPosition {
        MapCameraPosition(kind: .region(region))
    }

    public static func rect(_ rect: MKMapRect) -> MapCameraPosition {
        MapCameraPosition(kind: .rect(rect))
    }

    public static func item(_ item: MKMapItem, allowsAutomaticPitch: Bool = true) -> MapCameraPosition {
        MapCameraPosition(kind: .item(item, allowsAutomaticPitch: allowsAutomaticPitch))
    }

    public static func userLocation(followsHeading: Bool = false, fallback: MapCameraPosition) -> MapCameraPosition {
        MapCameraPosition(kind: .userLocation(followsHeading: followsHeading), fallback: [fallback])
    }

    public var camera: MapCamera? {
        if case let .camera(camera) = kind { return camera }
        return nil
    }

    public var region: MKCoordinateRegion? {
        if case let .region(region) = kind { return region }
        return nil
    }

    public var rect: MKMapRect? {
        if case let .rect(rect) = kind { return rect }
        return nil
    }

    public var item: MKMapItem? {
        if case let .item(item, _) = kind { return item }
        return nil
    }

    public var positionedByUser: Bool { isPositionedByUser }

    public var followsUserLocation: Bool {
        if case .userLocation = kind { return true }
        return false
    }

    public var followsUserHeading: Bool {
        if case let .userLocation(followsHeading) = kind { return followsHeading }
        return false
    }

    public var fallbackPosition: MapCameraPosition? { fallback.first }

    public var allowsAutomaticPitch: Bool {
        if case let .item(_, allows) = kind { return allows }
        return false
    }

    /// The region the position frames, where it says; nil leaves the map
    /// where it is.
    var resolvedRegion: MKCoordinateRegion? {
        switch kind {
        case .automatic: nil
        case let .camera(camera): camera.region
        case let .region(region): region
        case let .rect(rect): MapGeometry.region(of: rect)
        case let .item(item, _): MapGeometry.region(center: item.placemark.coordinate, meters: 1000)
        case .userLocation: fallback.first?.resolvedRegion
        }
    }

    public static func == (a: MapCameraPosition, b: MapCameraPosition) -> Bool {
        guard a.isPositionedByUser == b.isPositionedByUser, a.fallback == b.fallback else { return false }
        switch (a.kind, b.kind) {
        case (.automatic, .automatic): return true
        case let (.camera(x), .camera(y)): return x == y
        case let (.region(x), .region(y)):
            return x.center.latitude == y.center.latitude && x.center.longitude == y.center.longitude
                && x.span.latitudeDelta == y.span.latitudeDelta && x.span.longitudeDelta == y.span.longitudeDelta
        case let (.rect(x), .rect(y)): return MKMapRectEqualToRect(x, y)
        case let (.item(x, p), .item(y, q)): return x === y && p == q
        case let (.userLocation(x), .userLocation(y)): return x == y
        default: return false
        }
    }
}

// MARK: - Bounds and interactions

/// Limits on where a map's camera can go.
public struct MapCameraBounds {
    var centerCoordinateBounds: MKCoordinateRegion?
    var minimumDistance: Double?
    var maximumDistance: Double?

    public init(centerCoordinateBounds: MKCoordinateRegion, minimumDistance: Double? = nil, maximumDistance: Double? = nil) {
        self.centerCoordinateBounds = centerCoordinateBounds
        self.minimumDistance = minimumDistance
        self.maximumDistance = maximumDistance
    }

    public init(centerCoordinateBounds: MKMapRect, minimumDistance: Double? = nil, maximumDistance: Double? = nil) {
        self.centerCoordinateBounds = MapGeometry.region(of: centerCoordinateBounds)
        self.minimumDistance = minimumDistance
        self.maximumDistance = maximumDistance
    }

    public init(minimumDistance: Double? = nil, maximumDistance: Double? = nil) {
        self.minimumDistance = minimumDistance
        self.maximumDistance = maximumDistance
    }
}

/// The ways people can move a map.
public struct MapInteractionModes: OptionSet {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let pan = MapInteractionModes(rawValue: 1 << 0)
    public static let zoom = MapInteractionModes(rawValue: 1 << 1)
    public static let all = MapInteractionModes(rawValue: 0xff)
}

extension MapInteractionModes {
    public static let rotate = MapInteractionModes(rawValue: 1 << 2)
    public static let pitch = MapInteractionModes(rawValue: 1 << 3)
}

// MARK: - Camera changes

/// Where the camera is, as views watching it are told.
public struct MapCameraUpdateContext {
    public let camera: MapCamera
    public let region: MKCoordinateRegion
    public let rect: MKMapRect

    init(region: MKCoordinateRegion) {
        self.region = region
        self.camera = MapCamera(centerCoordinate: region.center, distance: MapGeometry.meters(of: region))
        self.rect = MapGeometry.rect(of: region)
    }
}

/// How often views watching the camera are told it moved: when it stops,
/// or as it moves.
public struct MapCameraUpdateFrequency {
    var isContinuous: Bool

    public static var onEnd: MapCameraUpdateFrequency { MapCameraUpdateFrequency(isContinuous: false) }
    public static var continuous: MapCameraUpdateFrequency { MapCameraUpdateFrequency(isContinuous: true) }
}

// MARK: - Styles

/// Points of interest a map shows.
public struct PointOfInterestCategories {
    var included: [MKPointOfInterestCategory]?
    var excluded: [MKPointOfInterestCategory]

    public static var all: PointOfInterestCategories { PointOfInterestCategories(included: nil, excluded: []) }
    public static var excludingAll: PointOfInterestCategories { PointOfInterestCategories(included: [], excluded: []) }

    public static func including(_ categories: [MKPointOfInterestCategory]) -> PointOfInterestCategories {
        PointOfInterestCategories(included: categories, excluded: [])
    }

    public static func including(_ categories: MKPointOfInterestCategory...) -> PointOfInterestCategories {
        including(categories)
    }

    public static func excluding(_ categories: [MKPointOfInterestCategory]) -> PointOfInterestCategories {
        PointOfInterestCategories(included: nil, excluded: categories)
    }

    public static func excluding(_ categories: MKPointOfInterestCategory...) -> PointOfInterestCategories {
        excluding(categories)
    }
}

extension PointOfInterestCategories: ExpressibleByArrayLiteral {
    public init(arrayLiteral: MKPointOfInterestCategory...) {
        self = .including(arrayLiteral)
    }
}

/// How a map draws its tiles: as a street map, as imagery, or both.
public struct MapStyle {
    enum Kind { case standard, imagery, hybrid }

    var kind: Kind
    var showsTraffic = false

    /// How the map shows height.
    public struct Elevation {
        public static var automatic: Elevation { Elevation() }
        public static var flat: Elevation { Elevation() }
        public static var realistic: Elevation { Elevation() }
    }

    /// How strongly a street map draws its features.
    public struct StandardEmphasis {
        public static var automatic: StandardEmphasis { StandardEmphasis() }
        public static var muted: StandardEmphasis { StandardEmphasis() }
    }

    public static var standard: MapStyle { MapStyle(kind: .standard) }
    public static var imagery: MapStyle { MapStyle(kind: .imagery) }
    public static var hybrid: MapStyle { MapStyle(kind: .hybrid) }

    public static func standard(
        elevation: Elevation = .automatic,
        emphasis: StandardEmphasis = .automatic,
        pointsOfInterest: PointOfInterestCategories = .all,
        showsTraffic: Bool = false
    ) -> MapStyle {
        MapStyle(kind: .standard, showsTraffic: showsTraffic)
    }

    public static func imagery(elevation: Elevation = .automatic) -> MapStyle {
        MapStyle(kind: .imagery)
    }

    public static func hybrid(
        elevation: Elevation = .automatic,
        pointsOfInterest: PointOfInterestCategories = .all,
        showsTraffic: Bool = false
    ) -> MapStyle {
        MapStyle(kind: .hybrid, showsTraffic: showsTraffic)
    }

    var mapType: MKMapType {
        switch kind {
        case .standard: .standard
        case .imagery: .satellite
        case .hybrid: .hybrid
        }
    }
}

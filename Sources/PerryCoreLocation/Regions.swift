import CPerryGeometry
import PerryObjCInterop

// Regions, which an app makes to monitor: kept as made, though monitoring
// them fails. A circular region knows whether it contains a coordinate.

final class RegionState: ObjectState {
    var identifier: String?
    var center = Coordinates.invalid
    var radius: Double = 0
    var notifyOnEntry = true
    var notifyOnExit = true
    var notifyEntryStateOnDisplay = false
    // A beacon region's.
    var uuid: NSObject?
    var major: NSObject?
    var minor: NSObject?
}

@ObjCClass("CLRegion")
open class CLRegion: NSObject {
    static let states = StateTable<RegionState>()
    var region: RegionState { CLRegion.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        CLRegion.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CLRegion.objCClass.pointer)
    }

    /// iOS 4's circular region, from before CLCircularRegion.
    @ObjCMethod("initCircularRegionWithCenter:radius:identifier:")
    func initialize(center: CLLocationCoordinate2D, radius: Double, identifier: String?) -> Self {
        (region.center, region.radius, region.identifier) = (center, radius, identifier)
        return self
    }

    @ObjCMethod("identifier") func identifier() -> String? { region.identifier }
    @ObjCMethod("center") func center() -> CLLocationCoordinate2D { region.center }
    @ObjCMethod("radius") func radius() -> Double { region.radius }
    @ObjCMethod("notifyOnEntry") func notifyOnEntry() -> Bool { region.notifyOnEntry }
    @ObjCMethod("setNotifyOnEntry:") func setNotifyOnEntry(_ notify: Bool) { region.notifyOnEntry = notify }
    @ObjCMethod("notifyOnExit") func notifyOnExit() -> Bool { region.notifyOnExit }
    @ObjCMethod("setNotifyOnExit:") func setNotifyOnExit(_ notify: Bool) { region.notifyOnExit = notify }

    @ObjCMethod("containsCoordinate:")
    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        Coordinates.isValid(region.center) && Coordinates.distance(region.center, coordinate) <= region.radius
    }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { ObjCRuntime.retain(objcObject) }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: NSObject?) -> Bool {
        guard let other, other.is(CLRegion.self) else { return false }
        return other.unsafeCast(to: CLRegion.self).region.identifier == region.identifier
    }

    @ObjCMethod("hash") func hash() -> UInt { UInt(bitPattern: (region.identifier ?? "").hashValue) }
}

@ObjCClass("CLCircularRegion")
open class CLCircularRegion: CLRegion {
    @ObjCMethod("initWithCenter:radius:identifier:")
    func initializeCircle(center: CLLocationCoordinate2D, radius: Double, identifier: String?) -> Self {
        initialize(center: center, radius: radius, identifier: identifier)
    }
}

/// A region of beacons with a UUID, and a major and minor value if given.
@ObjCClass("CLBeaconRegion")
open class CLBeaconRegion: CLRegion {
    private func configure(_ uuid: NSObject?, major: Int?, minor: Int?, identifier: String?) -> Self {
        let region = region
        region.uuid = uuid
        region.major = major.map { NSNumber.make(integer: $0) }
        region.minor = minor.map { NSNumber.make(integer: $0) }
        region.identifier = identifier
        return self
    }

    @ObjCMethod("initWithProximityUUID:identifier:")
    func initialize(proximityUUID uuid: NSObject?, identifier: String?) -> Self {
        configure(uuid, major: nil, minor: nil, identifier: identifier)
    }

    @ObjCMethod("initWithProximityUUID:major:identifier:")
    func initialize(proximityUUID uuid: NSObject?, major: UInt16, identifier: String?) -> Self {
        configure(uuid, major: Int(major), minor: nil, identifier: identifier)
    }

    @ObjCMethod("initWithProximityUUID:major:minor:identifier:")
    func initialize(proximityUUID uuid: NSObject?, major: UInt16, minor: UInt16, identifier: String?) -> Self {
        configure(uuid, major: Int(major), minor: Int(minor), identifier: identifier)
    }

    @ObjCMethod("initWithUUID:identifier:")
    func initialize(uuid: NSObject?, identifier: String?) -> Self { configure(uuid, major: nil, minor: nil, identifier: identifier) }

    @ObjCMethod("initWithUUID:major:identifier:")
    func initialize(uuid: NSObject?, major: UInt16, identifier: String?) -> Self {
        configure(uuid, major: Int(major), minor: nil, identifier: identifier)
    }

    @ObjCMethod("initWithUUID:major:minor:identifier:")
    func initialize(uuid: NSObject?, major: UInt16, minor: UInt16, identifier: String?) -> Self {
        configure(uuid, major: Int(major), minor: Int(minor), identifier: identifier)
    }

    @ObjCMethod("proximityUUID") func proximityUUID() -> NSObject? { region.uuid }
    @ObjCMethod("UUID") func uuid() -> NSObject? { region.uuid }
    @ObjCMethod("major") func major() -> NSObject? { region.major }
    @ObjCMethod("minor") func minor() -> NSObject? { region.minor }
    @ObjCMethod("notifyEntryStateOnDisplay") func notifyEntryStateOnDisplay() -> Bool { region.notifyEntryStateOnDisplay }
    @ObjCMethod("setNotifyEntryStateOnDisplay:")
    func setNotifyEntryStateOnDisplay(_ notify: Bool) { region.notifyEntryStateOnDisplay = notify }

    /// The advertisement a device would send as the region's beacon; there
    /// is no Bluetooth to send it.
    @ObjCMethod("peripheralDataWithMeasuredPower:") func peripheralData(measuredPower: NSObject?) -> NSObject? { nil }
}

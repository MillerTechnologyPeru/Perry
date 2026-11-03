import CPerryGeometry
import PerryObjCInterop

// CLLocationManager, with no location to give: location services are on,
// but the app is denied them, as when a user declines. Asking for
// authorization changes it from not determined to denied; updates,
// region monitoring and beacon ranging fail with kCLErrorDenied. The
// delegate hears of each on the main queue, as on Darwin.

/// CLAuthorizationStatus: not determined 0, denied 2.
enum Authorization {
    nonisolated(unsafe) static var status: Int32 = 0
}

/// CLError codes.
private enum LocationError {
    static let locationUnknown = 0
    static let denied = 1
    static let regionMonitoringDenied = 4
    static let rangingUnavailable = 16
}

final class ManagerState: ObjectState {
    /// Not retained, as Darwin's is weak.
    var delegate: UnsafeMutableRawPointer?
    var desiredAccuracy: Double = -1
    var distanceFilter: Double = -1
    var headingFilter: Double = 1
    /// CLActivityType: other 1.
    var activityType = 1
    var pausesLocationUpdatesAutomatically = true
    var allowsBackgroundLocationUpdates = false
    var showsBackgroundLocationIndicator = false
    var purpose: String?
    var monitoredRegions: [NSObject] = []
}

@ObjCClass("CLLocationManager")
open class CLLocationManager: NSObject {
    static let states = StateTable<ManagerState>()
    var manager: ManagerState { CLLocationManager.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        CLLocationManager.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CLLocationManager.objCClass.pointer)
    }

    // MARK: Availability

    @ObjCClassMethod("locationServicesEnabled") static func locationServicesEnabled() -> Bool { true }
    @ObjCClassMethod("authorizationStatus") static func authorizationStatus() -> Int32 { Authorization.status }
    @ObjCClassMethod("headingAvailable") static func headingAvailable() -> Bool { false }
    @ObjCClassMethod("significantLocationChangeMonitoringAvailable")
    static func significantLocationChangeMonitoringAvailable() -> Bool { false }
    @ObjCClassMethod("isMonitoringAvailableForClass:") static func isMonitoringAvailable(for cls: ObjCClass?) -> Bool { false }
    @ObjCClassMethod("isRangingAvailable") static func isRangingAvailable() -> Bool { false }
    @ObjCClassMethod("regionMonitoringAvailable") static func regionMonitoringAvailable() -> Bool { false }
    @ObjCClassMethod("regionMonitoringEnabled") static func regionMonitoringEnabled() -> Bool { false }
    @ObjCClassMethod("deferredLocationUpdatesAvailable") static func deferredLocationUpdatesAvailable() -> Bool { false }

    @ObjCMethod("authorizationStatus") func authorizationStatus() -> Int32 { Authorization.status }
    /// CLAccuracyAuthorization: full 0.
    @ObjCMethod("accuracyAuthorization") func accuracyAuthorization() -> Int { 0 }

    // MARK: Settings

    @ObjCMethod("delegate") func delegate() -> NSObject? { manager.delegate.map { NSObject($0) } }

    /// A new delegate hears the authorization status, as on Darwin.
    @ObjCMethod("setDelegate:")
    func setDelegate(_ delegate: NSObject?) {
        manager.delegate = delegate?.objcObject
        guard delegate != nil else { return }
        let owner = self
        Dispatch.onMain { owner.authorizationChanged() }
    }

    @ObjCMethod("desiredAccuracy") func desiredAccuracy() -> Double { manager.desiredAccuracy }
    @ObjCMethod("setDesiredAccuracy:") func setDesiredAccuracy(_ accuracy: Double) { manager.desiredAccuracy = accuracy }
    @ObjCMethod("distanceFilter") func distanceFilter() -> Double { manager.distanceFilter }
    @ObjCMethod("setDistanceFilter:") func setDistanceFilter(_ filter: Double) { manager.distanceFilter = filter }
    @ObjCMethod("headingFilter") func headingFilter() -> Double { manager.headingFilter }
    @ObjCMethod("setHeadingFilter:") func setHeadingFilter(_ filter: Double) { manager.headingFilter = filter }
    @ObjCMethod("activityType") func activityType() -> Int { manager.activityType }
    @ObjCMethod("setActivityType:") func setActivityType(_ type: Int) { manager.activityType = type }
    @ObjCMethod("pausesLocationUpdatesAutomatically")
    func pausesLocationUpdatesAutomatically() -> Bool { manager.pausesLocationUpdatesAutomatically }
    @ObjCMethod("setPausesLocationUpdatesAutomatically:")
    func setPausesLocationUpdatesAutomatically(_ pauses: Bool) { manager.pausesLocationUpdatesAutomatically = pauses }
    @ObjCMethod("allowsBackgroundLocationUpdates")
    func allowsBackgroundLocationUpdates() -> Bool { manager.allowsBackgroundLocationUpdates }
    @ObjCMethod("setAllowsBackgroundLocationUpdates:")
    func setAllowsBackgroundLocationUpdates(_ allows: Bool) { manager.allowsBackgroundLocationUpdates = allows }
    @ObjCMethod("showsBackgroundLocationIndicator")
    func showsBackgroundLocationIndicator() -> Bool { manager.showsBackgroundLocationIndicator }
    @ObjCMethod("setShowsBackgroundLocationIndicator:")
    func setShowsBackgroundLocationIndicator(_ shows: Bool) { manager.showsBackgroundLocationIndicator = shows }
    @ObjCMethod("purpose") func purpose() -> String? { manager.purpose }
    @ObjCMethod("setPurpose:") func setPurpose(_ purpose: String?) { manager.purpose = purpose }

    @ObjCMethod("location") func location() -> NSObject? { nil }
    @ObjCMethod("heading") func heading() -> NSObject? { nil }
    @ObjCMethod("maximumRegionMonitoringDistance") func maximumRegionMonitoringDistance() -> Double { -1 }
    @ObjCMethod("monitoredRegions") func monitoredRegions() -> NSObject { NSMutableSet.of(manager.monitoredRegions) }
    @ObjCMethod("rangedRegions") func rangedRegions() -> NSObject { NSMutableSet.of([]) }

    // MARK: Authorization

    @ObjCMethod("requestWhenInUseAuthorization") func requestWhenInUseAuthorization() { deny() }
    @ObjCMethod("requestAlwaysAuthorization") func requestAlwaysAuthorization() { deny() }
    @ObjCMethod("requestTemporaryFullAccuracyAuthorizationWithPurposeKey:")
    func requestTemporaryFullAccuracyAuthorization(purposeKey: String?) {}

    /// The user is asked once, and declines.
    private func deny() {
        guard Authorization.status == 0 else { return }
        Authorization.status = 2
        let owner = self
        Dispatch.onMain { owner.authorizationChanged() }
    }

    private func authorizationChanged() {
        guard let delegate = delegate() else { return }
        if delegate.responds(to: "locationManagerDidChangeAuthorization:") {
            delegate.sendLocationManagerDidChangeAuthorization(self)
        }
        if delegate.responds(to: "locationManager:didChangeAuthorizationStatus:") {
            delegate.sendLocationManager(self, didChangeAuthorization: Authorization.status)
        }
    }

    // MARK: Updates

    @ObjCMethod("startUpdatingLocation") func startUpdatingLocation() { failUpdates() }
    @ObjCMethod("requestLocation") func requestLocation() { failUpdates() }
    @ObjCMethod("startMonitoringSignificantLocationChanges") func startMonitoringSignificantLocationChanges() { failUpdates() }
    @ObjCMethod("startMonitoringVisits") func startMonitoringVisits() {}
    @ObjCMethod("stopUpdatingLocation") func stopUpdatingLocation() {}
    @ObjCMethod("stopMonitoringSignificantLocationChanges") func stopMonitoringSignificantLocationChanges() {}
    @ObjCMethod("stopMonitoringVisits") func stopMonitoringVisits() {}
    @ObjCMethod("startUpdatingHeading") func startUpdatingHeading() {}
    @ObjCMethod("stopUpdatingHeading") func stopUpdatingHeading() {}
    @ObjCMethod("dismissHeadingCalibrationDisplay") func dismissHeadingCalibrationDisplay() {}
    @ObjCMethod("allowDeferredLocationUpdatesUntilTraveled:timeout:")
    func allowDeferredLocationUpdates(untilTraveled distance: Double, timeout: Double) {}
    @ObjCMethod("disallowDeferredLocationUpdates") func disallowDeferredLocationUpdates() {}

    /// Denied once the user has declined; until then the location is
    /// unknown.
    private func failUpdates() {
        let code = Authorization.status == 2 ? LocationError.denied : LocationError.locationUnknown
        let owner = self
        Dispatch.onMain {
            guard let delegate = owner.delegate(), delegate.responds(to: "locationManager:didFailWithError:") else { return }
            delegate.sendLocationManager(owner, didFailWithError: NSError.location(code))
        }
    }

    // MARK: Regions

    @ObjCMethod("startMonitoringForRegion:")
    func startMonitoring(for region: NSObject) {
        manager.monitoredRegions.append(region)
        let owner = self
        Dispatch.onMain {
            guard let delegate = owner.delegate(), delegate.responds(to: "locationManager:monitoringDidFailForRegion:withError:") else { return }
            delegate.sendLocationManager(owner, monitoringDidFailFor: region, withError: NSError.location(LocationError.regionMonitoringDenied))
        }
    }

    @ObjCMethod("startMonitoringForRegion:desiredAccuracy:")
    func startMonitoring(for region: NSObject, desiredAccuracy: Double) { startMonitoring(for: region) }

    @ObjCMethod("stopMonitoringForRegion:")
    func stopMonitoring(for region: NSObject) { manager.monitoredRegions.removeAll { $0.objcObject == region.objcObject } }

    @ObjCMethod("requestStateForRegion:") func requestState(for region: NSObject) {}

    @ObjCMethod("startRangingBeaconsInRegion:")
    func startRangingBeacons(in region: NSObject) {
        let owner = self
        Dispatch.onMain {
            guard let delegate = owner.delegate(), delegate.responds(to: "locationManager:rangingBeaconsDidFailForRegion:withError:") else { return }
            delegate.sendLocationManager(owner, rangingBeaconsDidFailFor: region, withError: NSError.location(LocationError.rangingUnavailable))
        }
    }

    @ObjCMethod("stopRangingBeaconsInRegion:") func stopRangingBeacons(in region: NSObject) {}
    @ObjCMethod("startRangingBeaconsSatisfyingConstraint:") func startRangingBeacons(satisfying constraint: NSObject) {}
    @ObjCMethod("stopRangingBeaconsSatisfyingConstraint:") func stopRangingBeacons(satisfying constraint: NSObject) {}
}

/// CLLocationManagerDelegate's messages.
extension NSObject {
    @ObjCMethod("locationManagerDidChangeAuthorization:")
    func sendLocationManagerDidChangeAuthorization(_ manager: CLLocationManager)

    @ObjCMethod("locationManager:didChangeAuthorizationStatus:")
    func sendLocationManager(_ manager: CLLocationManager, didChangeAuthorization status: Int32)

    @ObjCMethod("locationManager:didFailWithError:")
    func sendLocationManager(_ manager: CLLocationManager, didFailWithError error: NSError)

    @ObjCMethod("locationManager:monitoringDidFailForRegion:withError:")
    func sendLocationManager(_ manager: CLLocationManager, monitoringDidFailFor region: NSObject, withError error: NSError)

    @ObjCMethod("locationManager:rangingBeaconsDidFailForRegion:withError:")
    func sendLocationManager(_ manager: CLLocationManager, rangingBeaconsDidFailFor region: NSObject, withError error: NSError)
}

@ObjCWrapper("NSMutableSet")
class NSMutableSet: NSObject {
    @ObjCClassMethod("set") static func empty() -> NSMutableSet
    @ObjCMethod("addObject:") func add(_ object: NSObject)

    static func of(_ objects: [NSObject]) -> NSMutableSet {
        let set = empty()
        objects.forEach(set.add)
        return set
    }
}

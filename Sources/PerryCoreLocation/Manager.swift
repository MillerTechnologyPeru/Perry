import CPerryGeometry
import PerryObjCInterop

// CLLocationManager, at a fixed location (FakeLocation): the user allows
// the app what it asks for, and updates deliver the location once, on the
// main queue, as on Darwin. Apps of iOS 7 and before, which start updates
// without asking, are allowed when they do. With no location, the user
// declines and updates fail with kCLErrorDenied. Region monitoring and
// beacon ranging always fail.

/// CLAuthorizationStatus: not determined 0, denied 2, authorized always 3,
/// authorized when in use 4.
enum Authorization {
    nonisolated(unsafe) static var status: Int32 = 0

    static var allowed: Bool { status == 3 || status == 4 }
}

/// CLError codes.
private enum LocationError {
    static let denied = 1
    static let regionMonitoringDenied = 4
    static let regionMonitoringFailure = 5
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

    /// The last location delivered.
    @ObjCMethod("location") func location() -> NSObject? { Authorization.allowed ? FakeLocation.location() : nil }
    @ObjCMethod("heading") func heading() -> NSObject? { nil }
    @ObjCMethod("maximumRegionMonitoringDistance") func maximumRegionMonitoringDistance() -> Double { -1 }
    @ObjCMethod("monitoredRegions") func monitoredRegions() -> NSObject { NSMutableSet.of(manager.monitoredRegions) }
    @ObjCMethod("rangedRegions") func rangedRegions() -> NSObject { NSMutableSet.of([]) }

    // MARK: Authorization

    @ObjCMethod("requestWhenInUseAuthorization") func requestWhenInUseAuthorization() { answer(allowing: 4) }
    @ObjCMethod("requestAlwaysAuthorization") func requestAlwaysAuthorization() { answer(allowing: 3) }
    @ObjCMethod("requestTemporaryFullAccuracyAuthorizationWithPurposeKey:")
    func requestTemporaryFullAccuracyAuthorization(purposeKey: String?) {}

    /// The user is asked once, and allows `status` if there is a location,
    /// else declines.
    private func answer(allowing status: Int32) {
        guard Authorization.status == 0 else { return }
        Authorization.status = FakeLocation.coordinate == nil ? 2 : status
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

    @ObjCMethod("startUpdatingLocation") func startUpdatingLocation() { update() }
    @ObjCMethod("requestLocation") func requestLocation() { update() }
    @ObjCMethod("startMonitoringSignificantLocationChanges") func startMonitoringSignificantLocationChanges() { update() }
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

    /// The location, once: to -locationManager:didUpdateLocations:, or
    /// iOS 2's -locationManager:didUpdateToLocation:fromLocation:. Starting
    /// without having asked asks for when in use, as iOS 7 did.
    private func update() {
        answer(allowing: 4)
        guard Authorization.allowed else { return failUpdates() }
        let owner = self
        Dispatch.onMain {
            guard let delegate = owner.delegate(), let location = FakeLocation.location() else { return }
            if delegate.responds(to: "locationManager:didUpdateLocations:") {
                delegate.sendLocationManager(owner, didUpdateLocations: NSMutableArray.of([location]))
            } else if delegate.responds(to: "locationManager:didUpdateToLocation:fromLocation:") {
                delegate.sendLocationManager(owner, didUpdateTo: location, from: nil)
            }
        }
    }

    /// Denied once the user has declined.
    private func failUpdates() {
        let code = LocationError.denied
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
            let code = Authorization.allowed ? LocationError.regionMonitoringFailure : LocationError.regionMonitoringDenied
            delegate.sendLocationManager(owner, monitoringDidFailFor: region, withError: NSError.location(code))
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

    @ObjCMethod("locationManager:didUpdateLocations:")
    func sendLocationManager(_ manager: CLLocationManager, didUpdateLocations locations: NSMutableArray)

    @ObjCMethod("locationManager:didUpdateToLocation:fromLocation:")
    func sendLocationManager(_ manager: CLLocationManager, didUpdateTo location: CLLocation, from previous: CLLocation?)

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

@ObjCWrapper("NSMutableArray")
class NSMutableArray: NSObject {
    @ObjCClassMethod("array") static func empty() -> NSMutableArray
    @ObjCMethod("addObject:") func add(_ object: NSObject)

    static func of(_ objects: [NSObject]) -> NSMutableArray {
        let array = empty()
        objects.forEach(array.add)
        return array
    }
}

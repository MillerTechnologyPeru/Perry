import CPerryGeometry
import Glibc
import PerryObjCInterop

// CLLocationManager, over the desktop's location service, GeoClue
// (GeoClue.swift): asking for authorization starts GeoClue's client for the
// app, and the desktop's agent asks the user, the first time, whether the
// app may know where it is; the answer is the authorization status, kept in
// the app's defaults as iOS keeps it. Updates deliver each location GeoClue
// reports, on the main queue, as on Darwin. Without GeoClue (no system bus,
// or no GeoClue on it) location services are disabled: authorization is
// denied and updates fail with kCLErrorDenied. Apps of iOS 7 and before,
// which start updates without asking, ask when they do.
//
// PERRY_LOCATION fixes the location instead (FakeLocation): the user allows
// the app what it asks for, and updates deliver that location once. Region
// monitoring and beacon ranging always fail.

/// CLAuthorizationStatus: not determined 0, denied 2, authorized always 3,
/// authorized when in use 4.
enum Authorization {
    /// Whether the location is PERRY_LOCATION's, not GeoClue's.
    static let fixed = getenv("PERRY_LOCATION") != nil

    private static let key = "PerryCLAuthorizationStatus"

    /// The status the app was given before, if any. The desktop's
    /// permission, which the user may have changed since, then corrects it.
    nonisolated(unsafe) static var status: Int32 = {
        guard !fixed else { return 0 }
        let stored = Int32(truncatingIfNeeded: NSUserDefaults.standard().integer(forKey: key))
        let status: Int32 = [2, 3, 4].contains(stored) ? stored : 0
        if status != 0 { reconcile() }
        return status
    }()

    /// Takes the desktop's kept permission over the status the app was
    /// given: allowed there, authorized when in use (or always, as given);
    /// denied there, denied.
    private static func reconcile() {
        let id = desktopID
        Task.detached {
            guard let kept = await DesktopPermission.kept(appID: id) else { return }
            Dispatch.onMain {
                let updated: Int32
                switch kept {
                case .allowed: updated = allowed ? status : 4
                case .denied: updated = 2
                case .unknown: return
                }
                guard updated != status else { return }
                status = updated
                store()
                for manager in Managers.all { manager.authorizationChanged() }
                if allowed {
                    Locating.start()
                    for manager in Managers.all { manager.resumeIfWaiting() }
                }
            }
        }
    }

    static var allowed: Bool { status == 3 || status == 4 }

    /// Whether GeoClue is answering a request now, and what runs once it has.
    nonisolated(unsafe) static var asking = false
    nonisolated(unsafe) static var pending: [() -> Void] = []

    /// Keeps the status the user gave.
    static func store() {
        guard !fixed else { return }
        NSUserDefaults.standard().set(integer: Int(status), forKey: key)
    }

    /// The app's desktop ID, as its desktop entry is named (PerryUIKit's
    /// DesktopEntry): its bundle identifier, keeping the characters a
    /// desktop file's name may have.
    /// The app's name, as its home screen shows it.
    static let appName: String = NSBundle.main().infoObject(forKey: "CFBundleDisplayName")?.stringValue
        ?? NSBundle.main().infoObject(forKey: "CFBundleName")?.stringValue ?? desktopID

    /// Why the app wants the location, as it tells the user.
    static let reason: String? = {
        for key in ["NSLocationWhenInUseUsageDescription", "NSLocationAlwaysAndWhenInUseUsageDescription", "NSLocationUsageDescription"] {
            if let reason = NSBundle.main().infoObject(forKey: key)?.stringValue, !reason.isEmpty { return reason }
        }
        return nil
    }()

    static let desktopID: String = {
        let identifier = NSBundle.main().infoObject(forKey: "CFBundleIdentifier")?.stringValue ?? "perry-app"
        let kept = String(identifier.map { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) ? $0 : "_" })
        return kept.isEmpty ? "perry-app" : kept
    }()
}

/// Whether location services are there: GeoClue is, or PERRY_LOCATION
/// fixes the location. Asked once; the answer waits at most 3 seconds.
enum Services {
    nonisolated(unsafe) private static var known: Bool?

    static var enabled: Bool {
        if Authorization.fixed { return true }
        if let known { return known }
        final class Answer: @unchecked Sendable {
            var value = false
            var semaphore = sem_t()
        }
        let answer = Answer()
        sem_init(&answer.semaphore, 0, 0)
        Task.detached {
            answer.value = await GeoClue.shared.isAvailable()
            sem_post(&answer.semaphore)
        }
        var deadline = timespec()
        clock_gettime(CLOCK_REALTIME, &deadline)
        deadline.tv_sec += 3
        let answered = sem_timedwait(&answer.semaphore, &deadline) == 0
        let value = answered && answer.value
        if answered { known = value }
        return value
    }
}

/// The managers made, which hear authorization changes and locations; not
/// retained.
enum Managers {
    nonisolated(unsafe) static var live: [UnsafeMutableRawPointer] = []

    static func add(_ manager: UnsafeMutableRawPointer) {
        if !live.contains(manager) { live.append(manager) }
    }

    static func remove(_ manager: UnsafeMutableRawPointer) { live.removeAll { $0 == manager } }

    static var all: [CLLocationManager] { live.map { CLLocationManager.objCInstance($0, ownership: .retain) } }
}

/// GeoClue's locations, delivered to the managers updating.
enum Locating {
    nonisolated(unsafe) private static var started = false
    /// The newest location.
    nonisolated(unsafe) static var latest: CLLocation?

    /// Starts GeoClue's client for the app, once allowed; a client GeoClue
    /// refuses takes the authorization back.
    static func start() {
        guard !started, !Authorization.fixed else { return }
        started = true
        let (id, name, reason) = (Authorization.desktopID, Authorization.appName, Authorization.reason)
        Task.detached {
            let answer = await GeoClue.shared.authorize(desktopID: id, name: name, reason: reason, level: 8)
            guard answer == .authorized else {
                Dispatch.onMain {
                    started = false
                    guard Authorization.allowed else { return }
                    Authorization.status = 2
                    if answer == .denied { Authorization.store() }
                    for manager in Managers.all { manager.authorizationChanged(); manager.failIfUpdating() }
                }
                return
            }
            await GeoClue.shared.observe { fix in Dispatch.onMain { deliver(fix) } }
        }
    }

    private static func deliver(_ fix: GeoClueFix) {
        let location = CLLocation.objCClass.object.allocated().unsafeCast(to: CLLocation.self).initialize(
            coordinate: CLLocationCoordinate2D(latitude: fix.latitude, longitude: fix.longitude), altitude: fix.altitude ?? 0,
            horizontalAccuracy: fix.accuracy, verticalAccuracy: fix.altitude == nil ? -1 : fix.accuracy,
            course: fix.heading ?? -1, speed: fix.speed ?? -1, timestamp: nil)
        latest = location
        for manager in Managers.all { manager.deliverIfWanted(location) }
    }
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
    /// Delivering each location, or the next one only.
    var updating = false
    var once = false
}

@ObjCClass("CLLocationManager")
open class CLLocationManager: NSObject {
    static let states = StateTable<ManagerState>()
    var manager: ManagerState { CLLocationManager.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        CLLocationManager.states.remove(objcObject)
        Managers.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CLLocationManager.objCClass.pointer)
    }

    // MARK: Availability

    @ObjCClassMethod("locationServicesEnabled") static func locationServicesEnabled() -> Bool { Services.enabled }
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
        Managers.add(objcObject)
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
    @ObjCMethod("location")
    func location() -> NSObject? {
        guard Authorization.allowed else { return nil }
        return Authorization.fixed ? FakeLocation.location() : Locating.latest
    }
    @ObjCMethod("heading") func heading() -> NSObject? { nil }
    @ObjCMethod("maximumRegionMonitoringDistance") func maximumRegionMonitoringDistance() -> Double { -1 }
    @ObjCMethod("monitoredRegions") func monitoredRegions() -> NSObject { NSMutableSet.of(manager.monitoredRegions) }
    @ObjCMethod("rangedRegions") func rangedRegions() -> NSObject { NSMutableSet.of([]) }

    // MARK: Authorization

    @ObjCMethod("requestWhenInUseAuthorization") func requestWhenInUseAuthorization() { answer(allowing: 4, then: nil) }
    @ObjCMethod("requestAlwaysAuthorization") func requestAlwaysAuthorization() { answer(allowing: 3, then: nil) }
    @ObjCMethod("requestTemporaryFullAccuracyAuthorizationWithPurposeKey:")
    func requestTemporaryFullAccuracyAuthorization(purposeKey: String?) {}

    /// The user is asked once, through GeoClue's agent, and allows `status`
    /// or declines; without GeoClue, declines. With a fixed location, allows
    /// `status` if there is one. `then` runs once answered.
    private func answer(allowing status: Int32, then: (() -> Void)?) {
        Managers.add(objcObject)
        guard Authorization.status == 0 else {
            if let then { Dispatch.onMain(then) }
            return
        }
        if Authorization.fixed {
            Authorization.status = FakeLocation.coordinate == nil ? 2 : status
            let owner = self
            Dispatch.onMain {
                owner.authorizationChanged()
                then?()
            }
            return
        }
        if let then { Authorization.pending.append(then) }
        guard !Authorization.asking else { return }
        Authorization.asking = true
        let (id, name, reason) = (Authorization.desktopID, Authorization.appName, Authorization.reason)
        Task.detached {
            let answer = await GeoClue.shared.authorize(desktopID: id, name: name, reason: reason, level: 8)
            Dispatch.onMain {
                Authorization.asking = false
                Authorization.status = answer == .authorized ? status : 2
                if answer != .unavailable { Authorization.store() }
                for manager in Managers.all { manager.authorizationChanged() }
                if Authorization.allowed { Locating.start() }
                let pending = Authorization.pending
                Authorization.pending = []
                pending.forEach { $0() }
            }
        }
    }

    func authorizationChanged() {
        guard let delegate = delegate() else { return }
        if delegate.responds(to: "locationManagerDidChangeAuthorization:") {
            delegate.sendLocationManagerDidChangeAuthorization(self)
        }
        if delegate.responds(to: "locationManager:didChangeAuthorizationStatus:") {
            delegate.sendLocationManager(self, didChangeAuthorization: Authorization.status)
        }
    }

    // MARK: Updates

    @ObjCMethod("startUpdatingLocation") func startUpdatingLocation() { update(once: false) }
    @ObjCMethod("requestLocation") func requestLocation() { update(once: true) }
    @ObjCMethod("startMonitoringSignificantLocationChanges") func startMonitoringSignificantLocationChanges() { update(once: false) }
    @ObjCMethod("startMonitoringVisits") func startMonitoringVisits() {}
    @ObjCMethod("stopUpdatingLocation") func stopUpdatingLocation() { manager.updating = false }
    @ObjCMethod("stopMonitoringSignificantLocationChanges") func stopMonitoringSignificantLocationChanges() { manager.updating = false }
    @ObjCMethod("stopMonitoringVisits") func stopMonitoringVisits() {}
    @ObjCMethod("startUpdatingHeading") func startUpdatingHeading() {}
    @ObjCMethod("stopUpdatingHeading") func stopUpdatingHeading() {}
    @ObjCMethod("dismissHeadingCalibrationDisplay") func dismissHeadingCalibrationDisplay() {}
    @ObjCMethod("allowDeferredLocationUpdatesUntilTraveled:timeout:")
    func allowDeferredLocationUpdates(untilTraveled distance: Double, timeout: Double) {}
    @ObjCMethod("disallowDeferredLocationUpdates") func disallowDeferredLocationUpdates() {}

    /// Locations: to -locationManager:didUpdateLocations:, or iOS 2's
    /// -locationManager:didUpdateToLocation:fromLocation:, each GeoClue
    /// reports, or the next only, starting with the newest there is; a
    /// fixed location once. Starting without having asked asks for when in
    /// use, as iOS 7 did.
    private func update(once: Bool) {
        if once { manager.once = true } else { manager.updating = true }
        let owner = self
        answer(allowing: 4) {
            guard Authorization.allowed else {
                owner.manager.once = false
                owner.manager.updating = false
                return owner.failUpdates()
            }
            if Authorization.fixed {
                owner.manager.once = false
                owner.manager.updating = false
                if let location = FakeLocation.location() { owner.send(location) }
                return
            }
            Locating.start()
            if let latest = Locating.latest { owner.deliverIfWanted(latest) }
        }
    }

    /// A location, if this manager is updating or waits for one.
    func deliverIfWanted(_ location: CLLocation) {
        guard manager.updating || manager.once else { return }
        manager.once = false
        send(location)
    }

    /// Locations again, once allowed after all, for a manager that asked.
    func resumeIfWaiting() {
        guard manager.updating || manager.once, let latest = Locating.latest else { return }
        deliverIfWanted(latest)
    }

    /// Updates fail once location is denied.
    func failIfUpdating() {
        guard manager.updating || manager.once else { return }
        manager.updating = false
        manager.once = false
        failUpdates()
    }

    private func send(_ location: CLLocation) {
        guard let delegate = delegate() else { return }
        if delegate.responds(to: "locationManager:didUpdateLocations:") {
            delegate.sendLocationManager(self, didUpdateLocations: NSMutableArray.of([location]))
        } else if delegate.responds(to: "locationManager:didUpdateToLocation:fromLocation:") {
            delegate.sendLocationManager(self, didUpdateTo: location, from: nil)
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

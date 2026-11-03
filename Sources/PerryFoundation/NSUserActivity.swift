import CPerryFoundation
import PerryObjCInterop

/// An NSUserActivity's properties. Nothing here hands activities to other
/// devices or to search, so an activity only keeps what it is given.
final class UserActivityStorage {
    var activityType: String
    var title: String?
    var userInfo: ObjCObject?
    var requiredUserInfoKeys: ObjCObject?
    var keywords: ObjCObject?
    var webpageURL: ObjCObject?
    var referrerURL: ObjCObject?
    var expirationDate: ObjCObject?
    var targetContentIdentifier: String?
    var persistentIdentifier: String?
    /// Unretained, as the delegate property is weak.
    var delegate: id?
    var needsSave = false
    var supportsContinuationStreams = false
    var eligibleForHandoff = true
    var eligibleForSearch = false
    var eligibleForPublicIndexing = false
    var eligibleForPrediction = false

    init(activityType: String) {
        self.activityType = activityType
    }
}

enum UserActivities {
    nonisolated(unsafe) static var activityClass: Class!
}

/// NSUserActivity, which UIKit declares in CoreServices and Foundation
/// defines.
@ObjCClass("NSUserActivity")
public final class NSUserActivity: NSObject {
    /// Set-up after the class is defined.
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        UserActivities.activityClass = cls.storage
    }

    var storage: UserActivityStorage {
        if let storage = Storage.get(objcObject, as: UserActivityStorage.self) { return storage }
        let storage = UserActivityStorage(activityType: "")
        Storage.set(objcObject, storage)
        return storage
    }

    @ObjCMethod("initWithActivityType:")
    func initialize(activityType: String) -> Self {
        Storage.set(objcObject, UserActivityStorage(activityType: activityType))
        return self
    }

    /// The main bundle's first NSUserActivityTypes entry, as Foundation
    /// takes it; none here.
    @ObjCMethod("init") func initialize() -> Self { initialize(activityType: "") }

    @ObjCMethod("activityType") func activityType() -> String { storage.activityType }

    @ObjCMethod("title") func title() -> String? { storage.title }
    @ObjCMethod("setTitle:") func setTitle(_ title: String?) { storage.title = title }

    @ObjCMethod("userInfo") func userInfo() -> UnsafeMutableRawPointer? { storage.userInfo?.id }
    @ObjCMethod("setUserInfo:")
    func setUserInfo(_ userInfo: ObjCObject?) {
        storage.userInfo = userInfo.flatMap { ObjC.send($0.id, Selectors.copyWithZone, nil) }.map { ObjCObject(objCOwned: $0) }
    }

    @ObjCMethod("addUserInfoEntriesFromDictionary:")
    func addUserInfoEntries(_ entries: ObjCObject?) {
        guard let entries else { return }
        guard let cls = ObjC.getClass("NSMutableDictionary"),
              let merged = ObjC.send(ObjC.send(UnsafeMutableRawPointer(cls), ObjC.selector("alloc")), ObjC.selector("init")) else {
            return
        }
        if let userInfo = storage.userInfo {
            _ = ObjC.send(merged, ObjC.selector("addEntriesFromDictionary:"), userInfo.id)
        }
        _ = ObjC.send(merged, ObjC.selector("addEntriesFromDictionary:"), entries.id)
        setUserInfo(ObjCObject(merged))
        ObjC.release(merged)
    }

    @ObjCMethod("requiredUserInfoKeys") func requiredUserInfoKeys() -> UnsafeMutableRawPointer? { storage.requiredUserInfoKeys?.id }
    @ObjCMethod("setRequiredUserInfoKeys:") func setRequiredUserInfoKeys(_ keys: ObjCObject?) { storage.requiredUserInfoKeys = keys }

    @ObjCMethod("keywords") func keywords() -> UnsafeMutableRawPointer? { storage.keywords?.id }
    @ObjCMethod("setKeywords:") func setKeywords(_ keywords: ObjCObject?) { storage.keywords = keywords }

    @ObjCMethod("webpageURL") func webpageURL() -> UnsafeMutableRawPointer? { storage.webpageURL?.id }
    @ObjCMethod("setWebpageURL:") func setWebpageURL(_ url: ObjCObject?) { storage.webpageURL = url }

    @ObjCMethod("referrerURL") func referrerURL() -> UnsafeMutableRawPointer? { storage.referrerURL?.id }
    @ObjCMethod("setReferrerURL:") func setReferrerURL(_ url: ObjCObject?) { storage.referrerURL = url }

    @ObjCMethod("expirationDate") func expirationDate() -> UnsafeMutableRawPointer? { storage.expirationDate?.id }
    @ObjCMethod("setExpirationDate:") func setExpirationDate(_ date: ObjCObject?) { storage.expirationDate = date }

    @ObjCMethod("targetContentIdentifier") func targetContentIdentifier() -> String? { storage.targetContentIdentifier }
    @ObjCMethod("setTargetContentIdentifier:")
    func setTargetContentIdentifier(_ identifier: String?) { storage.targetContentIdentifier = identifier }

    @ObjCMethod("persistentIdentifier") func persistentIdentifier() -> String? { storage.persistentIdentifier }
    @ObjCMethod("setPersistentIdentifier:")
    func setPersistentIdentifier(_ identifier: String?) { storage.persistentIdentifier = identifier }

    @ObjCMethod("delegate") func delegate() -> UnsafeMutableRawPointer? { storage.delegate }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: UnsafeMutableRawPointer?) { storage.delegate = delegate }

    @ObjCMethod("needsSave") func needsSave() -> Bool { storage.needsSave }
    @ObjCMethod("setNeedsSave:") func setNeedsSave(_ value: Bool) { storage.needsSave = value }

    @ObjCMethod("supportsContinuationStreams") func supportsContinuationStreams() -> Bool { storage.supportsContinuationStreams }
    @ObjCMethod("setSupportsContinuationStreams:")
    func setSupportsContinuationStreams(_ value: Bool) { storage.supportsContinuationStreams = value }

    @ObjCMethod("isEligibleForHandoff") func isEligibleForHandoff() -> Bool { storage.eligibleForHandoff }
    @ObjCMethod("setEligibleForHandoff:") func setEligibleForHandoff(_ value: Bool) { storage.eligibleForHandoff = value }

    @ObjCMethod("isEligibleForSearch") func isEligibleForSearch() -> Bool { storage.eligibleForSearch }
    @ObjCMethod("setEligibleForSearch:") func setEligibleForSearch(_ value: Bool) { storage.eligibleForSearch = value }

    @ObjCMethod("isEligibleForPublicIndexing") func isEligibleForPublicIndexing() -> Bool { storage.eligibleForPublicIndexing }
    @ObjCMethod("setEligibleForPublicIndexing:")
    func setEligibleForPublicIndexing(_ value: Bool) { storage.eligibleForPublicIndexing = value }

    @ObjCMethod("isEligibleForPrediction") func isEligibleForPrediction() -> Bool { storage.eligibleForPrediction }
    @ObjCMethod("setEligibleForPrediction:") func setEligibleForPrediction(_ value: Bool) { storage.eligibleForPrediction = value }

    /// Advertising the activity to other devices, which nothing does here.
    @ObjCMethod("becomeCurrent") func becomeCurrent() {}
    @ObjCMethod("resignCurrent") func resignCurrent() {}
    @ObjCMethod("invalidate") func invalidate() {}

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: UserActivities.activityClass)
    }
}

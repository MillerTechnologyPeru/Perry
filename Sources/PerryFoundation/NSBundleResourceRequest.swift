import CPerryFoundation
import Glibc
import PerryObjCInterop
import Synchronization

// On-demand resources: tagged asset packs the App Store serves apart from an
// app, which NSBundleResourceRequest downloads when the app asks for their
// tags. There is no store to download from here, so a request's tags are
// available only when the app carries their packs itself, as a development
// build that embeds its asset packs does: the bundle's
// OnDemandResources.plist names each tag's packs (NSBundleResourceRequestTags),
// found as <pack>.assetpack in an OnDemandResources folder in the bundle or
// beside it. A tag the manifest doesn't name, or whose packs are missing,
// fails as Darwin fails a tag it doesn't know, with
// NSBundleOnDemandResourceInvalidTagError.

private func resourceRequestClass(_ name: String) -> id? {
    name.withCString { ObjC.getClass($0) }.map { UnsafeMutableRawPointer($0) }
}

enum OnDemandResources {
    /// The bundle's tags and the asset packs each needs, if it has a manifest.
    static func manifest(_ bundle: id?) -> [String: [String]]? {
        guard let bundlePath = Strings.value(of: ObjC.send(bundle, ObjC.selector("bundlePath"))) else { return nil }
        let file = Strings.autoreleased(bundlePath + "/OnDemandResources.plist")
        guard let plist = ObjC.send(resourceRequestClass("NSDictionary"), ObjC.selector("dictionaryWithContentsOfFile:"), file),
              let tags = Dictionaries.value(plist, for: Strings.autoreleased("NSBundleResourceRequestTags")) else { return nil }
        var result: [String: [String]] = [:]
        for (key, value) in Dictionaries.entries(tags) {
            guard let tag = Strings.value(of: key) else { continue }
            let packs = Dictionaries.value(value, for: Strings.autoreleased("NSAssetPacks"))
            result[tag] = Arrays.elements(packs).compactMap { Strings.value(of: $0) }
        }
        return result
    }

    /// Whether the pack is on disk, in the bundle or beside it.
    static func hasPack(_ pack: String, bundle: id?) -> Bool {
        guard let bundlePath = Strings.value(of: ObjC.send(bundle, ObjC.selector("bundlePath"))) else { return false }
        let parent = String(bundlePath[..<(bundlePath.lastIndex(of: "/") ?? bundlePath.startIndex)])
        return [bundlePath + "/OnDemandResources/", parent + "/OnDemandResources/"].contains { folder in
            var info = stat()
            return stat(folder + pack + ".assetpack", &info) == 0
        }
    }

    /// nil when every tag is in the manifest with its packs on disk, else
    /// the error Darwin gives for the request (autoreleased).
    static func failure(tags: [String], bundle: id?) -> id? {
        guard let tagPacks = manifest(bundle) else {
            let identifier = Strings.value(of: ObjC.send(bundle, ObjC.selector("bundleIdentifier"))) ?? ""
            let underlying = ObjC.autorelease(Errors.make(domain: Strings.autoreleased("_NSBundleResourceRequestErrorDomain"), code: 100,
                                                          entries: [("NSLocalizedFailureReason",
                                                                     Strings.autoreleased("No manifest found for bundle ID \(identifier)"))]))
            return invalidTag(underlying)
        }
        let available = !tags.isEmpty && tags.allSatisfy { tag in
            guard let packs = tagPacks[tag] else { return false }
            return packs.allSatisfy { hasPack($0, bundle: bundle) }
        }
        return available ? nil : invalidTag(nil)
    }

    /// NSBundleOnDemandResourceInvalidTagError.
    private static func invalidTag(_ underlying: id?) -> id? {
        ObjC.autorelease(Errors.make(domain: Errors.cocoaDomain, code: 4994,
                                     entries: underlying.map { [("NSUnderlyingError", $0)] } ?? []))
    }
}

/// Preservation priorities set for tags a manifest names, by bundle path and tag.
private let preservationPriorities = Mutex<[String: Double]>([:])

final class BundleResourceRequestStorage {
    var tags: ObjCObject?
    var bundle: ObjCObject?
    var loadingPriority: Double = 0.5
    var progress: ObjCObject?
    var accessing = false
}

@ObjCClass("NSBundleResourceRequest")
public class NSBundleResourceRequest: NSObject {
    nonisolated(unsafe) static var requestClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        requestClass = cls.storage
    }

    var storage: BundleResourceRequestStorage {
        if let storage = Storage.get(objcObject, as: BundleResourceRequestStorage.self) { return storage }
        let storage = BundleResourceRequestStorage()
        Storage.set(objcObject, storage)
        return storage
    }

    @ObjCMethod("initWithTags:")
    func initialize(tags: UnsafeMutableRawPointer?) -> Self {
        initialize(tags: tags, bundle: ObjC.send(resourceRequestClass("NSBundle"), ObjC.selector("mainBundle")))
    }

    /// The tags' resources in the bundle, of which a progress of one unit
    /// tells the loading.
    @ObjCMethod("initWithTags:bundle:")
    func initialize(tags: UnsafeMutableRawPointer?, bundle: UnsafeMutableRawPointer?) -> Self {
        let storage = BundleResourceRequestStorage()
        storage.tags = ObjCObject(objCOwned: tags.flatMap { ObjC.send($0, Selectors.copyWithZone, nil) } ?? Sets.make([]))
        storage.bundle = bundle.map { ObjCObject($0) }
        typealias Make = @convention(c) (id?, SEL, Int64) -> id?
        storage.progress = unsafeBitCast(ObjC.msgSend, to: Make.self)(resourceRequestClass("NSProgress"),
                                                                     ObjC.selector("discreteProgressWithTotalUnitCount:"), 1)
            .map { ObjCObject($0) }
        Storage.set(objcObject, storage)
        return self
    }

    @ObjCMethod("loadingPriority") func loadingPriority() -> Double { storage.loadingPriority }
    @ObjCMethod("setLoadingPriority:") func setLoadingPriority(_ priority: Double) { storage.loadingPriority = priority }

    @ObjCMethod("tags") func tags() -> UnsafeMutableRawPointer? { storage.tags?.id }
    @ObjCMethod("bundle") func bundle() -> UnsafeMutableRawPointer? { storage.bundle?.id }
    @ObjCMethod("progress") func progress() -> UnsafeMutableRawPointer? { storage.progress?.id }

    private var tagNames: [String] { Sets.elements(storage.tags?.id).compactMap { Strings.value(of: $0) } }

    private func completeProgress() {
        typealias SetCompleted = @convention(c) (id?, SEL, Int64) -> Void
        guard let progress = storage.progress?.id else { return }
        unsafeBitCast(ObjC.msgSend, to: SetCompleted.self)(progress, ObjC.selector("setCompletedUnitCount:"), 1)
    }

    /// Calls the handler, on a background queue as Darwin does, with nil
    /// once the resources are there, else the error.
    @ObjCMethod("beginAccessingResourcesWithCompletionHandler:")
    func beginAccessingResources(completionHandler: UnsafeMutableRawPointer?) {
        let failure = OnDemandResources.failure(tags: tagNames, bundle: storage.bundle?.id)
        if failure == nil { storage.accessing = true }
        completeProgress()
        let handler = completionHandler.flatMap { ObjC.retainBlock($0) }.map { ObjCObject(objCOwned: $0) }
        let error = failure.map { ObjCObject($0) }
        guard let handler else { return }
        ItemProviderQueue.background {
            Blocks.invoke(handler.id, as: (@convention(c) (id, id?) -> Void).self)(handler.id, error?.id)
        }
    }

    /// Whether the resources are already there, without loading them.
    @ObjCMethod("conditionallyBeginAccessingResourcesWithCompletionHandler:")
    func conditionallyBeginAccessingResources(completionHandler: UnsafeMutableRawPointer?) {
        let available = OnDemandResources.failure(tags: tagNames, bundle: storage.bundle?.id) == nil
        if available { storage.accessing = true }
        let handler = completionHandler.flatMap { ObjC.retainBlock($0) }.map { ObjCObject(objCOwned: $0) }
        guard let handler else { return }
        ItemProviderQueue.background {
            Blocks.invoke(handler.id, as: (@convention(c) (id, Bool) -> Void).self)(handler.id, available)
        }
    }

    @ObjCMethod("endAccessingResources") func endAccessingResources() { storage.accessing = false }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NSBundleResourceRequest.requestClass)
    }
}

/// How long the system should keep a tag's resources: kept for the tags
/// the bundle's manifest names, 0 for others, as on Darwin.
@ObjCCategory("NSBundleResourceRequestAdditions")
extension NSBundle {
    @ObjCMethod("setPreservationPriority:forTags:")
    func setPreservationPriority(_ priority: Double, forTags tags: UnsafeMutableRawPointer?) {
        guard let manifest = OnDemandResources.manifest(objcObject),
              let path = Strings.value(of: ObjC.send(objcObject, ObjC.selector("bundlePath"))) else { return }
        let known = Sets.elements(tags).compactMap { Strings.value(of: $0) }.filter { manifest[$0] != nil }
        preservationPriorities.withLock { table in
            for tag in known { table[path + "\u{0}" + tag] = priority }
        }
    }

    @ObjCMethod("preservationPriorityForTag:")
    func preservationPriority(forTag tag: String?) -> Double {
        guard let tag, let path = Strings.value(of: ObjC.send(objcObject, ObjC.selector("bundlePath"))) else { return 0 }
        return preservationPriorities.withLock { $0[path + "\u{0}" + tag] } ?? 0
    }
}

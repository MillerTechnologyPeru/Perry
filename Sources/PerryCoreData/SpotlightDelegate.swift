import PerryObjCInterop

// NSCoreDataCoreSpotlightDelegate: what indexes a store's objects in
// Spotlight. There is no Spotlight here: apps make their subclass of it, set
// it up and start it as they do on an iPhone, and nothing is indexed.

@ObjCClass("NSCoreDataCoreSpotlightDelegate")
open class NSCoreDataCoreSpotlightDelegate: NSObject {
    @ObjCMethod("initForStoreWithDescription:coordinator:")
    func initialize(forStoreWith description: NSObject?, coordinator: NSObject?) -> Self { self }

    @ObjCMethod("initForStoreWithDescription:model:")
    func initialize(forStoreWith description: NSObject?, model: NSObject?) -> Self { self }

    @ObjCMethod("isIndexingEnabled") func isIndexingEnabled() -> Bool { false }
    @ObjCMethod("indexName") func indexName() -> String? { nil }
    @ObjCMethod("domainIdentifier") func domainIdentifier() -> String { "" }
    @ObjCMethod("attributeSetForObject:") func attributeSet(forObject object: NSObject?) -> NSObject? { nil }

    @ObjCMethod("startSpotlightIndexing") func startSpotlightIndexing() {}
    @ObjCMethod("stopSpotlightIndexing") func stopSpotlightIndexing() {}

    /// The index is empty already: deleting it succeeds.
    @ObjCMethod("deleteSpotlightIndexWithCompletionHandler:")
    func deleteSpotlightIndex(completionHandler: ObjCBlock?) {
        if let completionHandler { Blocks.call(completionHandler, nil as NSObject?) }
    }
}

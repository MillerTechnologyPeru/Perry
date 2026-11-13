import PerryAssetCatalog
import PerryObjCInterop

// NSDataAsset: a data set in an asset catalog, bytes the app keeps there
// (scripts, a JSON list) rather than loose in its bundle. Perry can't read
// a catalog's data sets itself: Scripts/extract-assets.sh writes each to
// data/<name> beside the catalog, and that is what is read here.

final class DataAssetState: ObjectState {
    var name = ""
    var contents: NSData?

    init() {}
}

@ObjCClass("NSDataAsset")
open class NSDataAsset: NSObject {
    static let states = StateTable<DataAssetState>()
    var state: DataAssetState { NSDataAsset.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        NSDataAsset.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSDataAsset.objCClass.pointer)
    }

    @ObjCMethod("initWithName:")
    func initialize(name: String) -> Self? { load(name, in: NSBundle.main()) }

    @ObjCMethod("initWithName:bundle:")
    func initialize(name: String, bundle: NSBundle?) -> Self? { load(name, in: bundle ?? NSBundle.main()) }

    private func load(_ name: String, in bundle: NSBundle) -> Self? {
        let catalog = bundle === NSBundle.main() ? AssetCatalog.main : AssetCatalog.catalog(in: bundle)
        guard let file = catalog?.extractedDataFile(named: name), let data = NSData.contents(ofFile: file) else { return nil }
        state.name = name
        state.contents = data
        return self
    }

    @ObjCMethod("name") func name() -> String { state.name }
    @ObjCMethod("data") func data() -> NSData? { state.contents }
    @ObjCMethod("typeIdentifier") func typeIdentifier() -> String { "public.data" }
}

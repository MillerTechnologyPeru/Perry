import PerryAssetCatalog
import PerryObjCInterop

// NSDataAsset: a data set in an asset catalog, bytes the app keeps there
// (scripts, a JSON list) rather than loose in its bundle. Perry can't read
// a catalog's data sets itself: Scripts/extract-assets.sh writes each to
// data/<name> beside the catalog, and that is what is read here.

@ObjCClass("NSDataAsset")
open class NSDataAsset: NSObject {
    var assetName = ""
    var contents: NSData?

    @ObjCMethod("initWithName:")
    func initialize(name: String) -> Self? { load(name, in: NSBundle.main()) }

    @ObjCMethod("initWithName:bundle:")
    func initialize(name: String, bundle: NSBundle?) -> Self? { load(name, in: bundle ?? NSBundle.main()) }

    private func load(_ name: String, in bundle: NSBundle) -> Self? {
        let catalog = bundle === NSBundle.main() ? AssetCatalog.main : AssetCatalog.catalog(in: bundle)
        guard let file = catalog?.extractedDataFile(named: name), let data = NSData.contents(ofFile: file) else { return nil }
        assetName = name
        contents = data
        return self
    }

    @ObjCMethod("name") func name() -> String { assetName }
    @ObjCMethod("data") func data() -> NSData? { contents }
    @ObjCMethod("typeIdentifier") func typeIdentifier() -> String { "public.data" }
}

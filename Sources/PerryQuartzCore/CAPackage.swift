import PerryObjCInterop

// CAPackage: layers and animations a program loads from a Core Animation
// archive (a .caar file or the data of one), whose root layer it shows.
// Those archives' format is not read here, so a package loads with an empty
// root layer: a program that holds one (Swift Playgrounds' accessory views)
// goes on, showing nothing for it.

@ObjCClass("CAPackage")
open class CAPackage: NSObject {
    /// The root layer: a layer with no sublayers.
    var root: NSObject?

    @ObjCMethod("init") public required override init() { super.init() }

    private static func make(_ cls: ObjCClass) -> CAPackage {
        let package = cls.object.allocated().initialized().unsafeCast(to: CAPackage.self)
        package.root = ObjCClass(named: "CALayer").object.allocated().initialized()
        return package
    }

    @ObjCClassMethod("packageWithContentsOfURL:type:options:error:")
    static func package(_ cls: ObjCClass, contentsOf url: NSObject?, type: String?, options: NSObject?,
                        error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> CAPackage? {
        make(cls)
    }

    @ObjCClassMethod("packageWithData:type:options:error:")
    static func package(_ cls: ObjCClass, data: NSObject?, type: String?, options: NSObject?,
                        error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> CAPackage? {
        make(cls)
    }

    @ObjCMethod("rootLayer") func rootLayer() -> NSObject? { root }

    /// An object the package published by name: none is.
    @ObjCMethod("publishedObjectWithName:") func publishedObject(named name: String?) -> NSObject? { nil }

    @ObjCMethod("isGeometryFlipped") func isGeometryFlipped() -> Bool { false }
}

/// The kinds of package a program asks to load.
@ObjCConstants
enum PackageTypes {
    static let kCAPackageTypeArchive = "com.apple.coreanimation-archive"
    static let kCAPackageTypeCAMLFile = "com.apple.coreanimation-caml"
    static let kCAPackageTypeCAMLBundle = "com.apple.coreanimation-caml-bundle"
}

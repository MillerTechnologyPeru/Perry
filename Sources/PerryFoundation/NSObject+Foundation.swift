import CPerryFoundation
import PerryObjCInterop

// Foundation's categories on NSObject.

/// Foundation's additions to NSObject. libobjc's -description returns nil.
@ObjCCategory("Foundation")
extension NSObject {
    @ObjCMethod("description")
    func objectDescription() -> String { "<\(ObjC.className(objcObject)): \(objcObject)>" }
}

/// retain, release and autorelease for static objects such as literals.
/// A category of NSObject's methods that each literal class gets.
@ObjCCategory("Immortal")
extension NSObject {
    @ObjCMethod("retain") func immortalRetain() -> UnsafeMutableRawPointer { objcObject }
    @ObjCMethod("release", types: "Vv16@0:8") func immortalRelease() {}
    @ObjCMethod("autorelease") func immortalAutorelease() -> UnsafeMutableRawPointer { objcObject }
    @ObjCMethod("retainCount") func immortalRetainCount() -> UInt { UInt.max }
}

/// +alloc for classes whose instances keep Swift state in an extra word.
/// A category of NSObject's methods that each such class gets.
@ObjCCategory("StorageAllocated")
extension NSObject {
    @ObjCClassMethod("alloc")
    static func allocateWithStorage(_ cls: ObjCClass) -> UnsafeMutableRawPointer? { Storage.allocate(cls.pointer) }

    @ObjCClassMethod("allocWithZone:")
    static func allocateWithStorage(_ cls: ObjCClass, zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        Storage.allocate(cls.pointer)
    }
}

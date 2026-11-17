import CPerryGeometry
import PerryObjCInterop

// NSShadow, the shadow an attributed string asks for as its NSShadowAttribute:
// an offset, a blur radius and a color, kept and read back. Text drawing does
// not paint it.

@ObjCClass("NSShadow")
open class NSShadow: NSObject {
    var offset = CGSize.zero
    var blurRadius: CGFloat = 0
    /// Retained.
    var color: NSObject?

    @ObjCMethod("init") public required override init() { super.init() }

    deinit { if let color { ObjCRuntime.release(color.objcObject) } }

    @ObjCMethod("shadowOffset") func shadowOffset() -> CGSize { offset }
    @ObjCMethod("setShadowOffset:") func setShadowOffset(_ offset: CGSize) { self.offset = offset }
    @ObjCMethod("shadowBlurRadius") func shadowBlurRadius() -> CGFloat { blurRadius }
    @ObjCMethod("setShadowBlurRadius:") func setShadowBlurRadius(_ radius: CGFloat) { blurRadius = radius }
    @ObjCMethod("shadowColor") func shadowColor() -> NSObject? { color }

    @ObjCMethod("setShadowColor:")
    func setShadowColor(_ color: NSObject?) {
        let retained = ObjCRuntime.retain(color?.objcObject)
        if let old = self.color { ObjCRuntime.release(old.objcObject) }
        self.color = retained.map { NSObject($0) }
    }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        let copy = NSShadow.objCClass.object.allocated().initialized().unsafeCast(to: NSShadow.self)
        copy.offset = offset
        copy.blurRadius = blurRadius
        copy.setShadowColor(color)
        return ObjCRuntime.retain(copy.objcObject)
    }

    @ObjCClassMethod("supportsSecureCoding") static func supportsSecureCoding(_ cls: ObjCClass) -> Bool { true }
}

import CPerryGeometry
import PerryObjCInterop

// AppKit's NSAffineTransform category: a transform applied to the current
// graphics context, or to a Bézier path. The class and its matrix are
// Foundation's; this reaches them through its -transformStruct.

extension CGAffineTransform: ObjCScalar {
    #if arch(i386) || arch(powerpc)
    public static var objCTypeEncoding: String { "{_NSAffineTransformStruct=ffffff}" }
    /// Six words, which 32-bit Intel and ppc return through memory.
    public static var objCReturnsIndirectly: Bool { true }
    #else
    public static var objCTypeEncoding: String { "{_NSAffineTransformStruct=dddddd}" }
    #endif
}

@ObjCWrapper("NSAffineTransform")
class NSAffineTransform: NSObject {
    @ObjCMethod("transformStruct") func transformStruct() -> CGAffineTransform

    var matrix: CGAffineTransform { transformStruct() }
}

@ObjCCategory("NSAppKitAdditions")
extension NSAffineTransform {
    /// Concatenated with the current context's transform: what's drawn next
    /// is transformed, then placed as the context's transform places it.
    @ObjCMethod("concat")
    func concat() {
        guard let context = NSGraphicsContext.currentCG else { return }
        CG.concatCTM(context, matrix)
    }

    /// In place of the current context's transform.
    @ObjCMethod("set")
    func set() {
        guard let context = NSGraphicsContext.currentCG else { return }
        let current = CG.getCTM(context)
        let determinant = current.a * current.d - current.b * current.c
        guard determinant != 0 else { return }
        let inverse = CGAffineTransform(a: current.d / determinant, b: -current.b / determinant,
                                        c: -current.c / determinant, d: current.a / determinant,
                                        tx: (current.c * current.ty - current.d * current.tx) / determinant,
                                        ty: (current.b * current.tx - current.a * current.ty) / determinant)
        CG.concatCTM(context, inverse)
        CG.concatCTM(context, matrix)
    }

    /// A copy of the path with its points transformed.
    @ObjCMethod("transformBezierPath:")
    func transform(_ path: NSBezierPath?) -> NSBezierPath? {
        guard let path else { return nil }
        let copy = NSBezierPath()
        copy.append(path)
        (copy.lineWidth, copy.windingRule, copy.lineCap, copy.lineJoin, copy.dash) = (path.lineWidth, path.windingRule, path.lineCap,
                                                                                    path.lineJoin, path.dash)
        copy.transform(using: self)
        return copy
    }
}

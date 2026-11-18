import CPerryGeometry
import PerryObjCInterop

// NSLayoutManager, TextKit's layout of a text storage into containers. Text
// here is laid out by the views that draw it, so a layout manager keeps its
// containers, storage and delegate for the app that set them up, which an
// app's subclass of it overrides drawing in, and lays nothing out itself.

@ObjCClass("NSLayoutManager")
open class NSLayoutManager: NSObject {
    var containers: [NSObject] = []
    /// Not retained, as TextKit's: the storage keeps its layout managers.
    var storage: NSObject?
    var layoutDelegate: NSObject?
    var fontLeading = true
    var nonContiguous = false

    @ObjCMethod("init") public required override init() { super.init() }

    deinit { for container in containers { ObjCRuntime.release(container.objcObject) } }

    @ObjCMethod("textStorage") func textStorage() -> NSObject? { storage }
    @ObjCMethod("setTextStorage:") func setTextStorage(_ storage: NSObject?) { self.storage = storage }
    @ObjCMethod("delegate") func delegate() -> NSObject? { layoutDelegate }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { layoutDelegate = delegate }
    @ObjCMethod("usesFontLeading") func usesFontLeading() -> Bool { fontLeading }
    @ObjCMethod("setUsesFontLeading:") func setUsesFontLeading(_ uses: Bool) { fontLeading = uses }
    @ObjCMethod("allowsNonContiguousLayout") func allowsNonContiguousLayout() -> Bool { nonContiguous }
    @ObjCMethod("setAllowsNonContiguousLayout:") func setAllowsNonContiguousLayout(_ allows: Bool) { nonContiguous = allows }

    @ObjCMethod("textContainers") func textContainers() -> NSObject { NSMutableArray.of(containers) }

    @ObjCMethod("addTextContainer:")
    func addTextContainer(_ container: NSObject?) {
        guard let container, let kept = ObjCRuntime.retain(container.objcObject) else { return }
        containers.append(NSObject(kept))
    }

    @ObjCMethod("removeTextContainerAtIndex:")
    func removeTextContainer(at index: Int) {
        guard containers.indices.contains(index) else { return }
        ObjCRuntime.release(containers.remove(at: index).objcObject)
    }

    @ObjCMethod("numberOfGlyphs") func numberOfGlyphs() -> Int { 0 }
    @ObjCMethod("glyphRangeForTextContainer:") func glyphRange(for container: NSObject?) -> PerryRange { PerryRange(location: 0, length: 0) }
    @ObjCMethod("usedRectForTextContainer:") func usedRect(for container: NSObject?) -> CGRect { .zero }
    @ObjCMethod("ensureLayoutForTextContainer:") func ensureLayout(for container: NSObject?) {}
    @ObjCMethod("invalidateLayoutForCharacterRange:actualCharacterRange:")
    func invalidateLayout(forCharacterRange range: PerryRange, actualCharacterRange: UnsafeMutablePointer<PerryRange>?) {
        actualCharacterRange?.pointee = range
    }
    @ObjCMethod("invalidateDisplayForCharacterRange:") func invalidateDisplay(forCharacterRange range: PerryRange) {}
    @ObjCMethod("drawBackgroundForGlyphRange:atPoint:") func drawBackground(forGlyphRange range: PerryRange, at point: CGPoint) {}
    @ObjCMethod("drawGlyphsForGlyphRange:atPoint:") func drawGlyphs(forGlyphRange range: PerryRange, at point: CGPoint) {}
}

import CPerryGeometry
import PerryObjCInterop

// NSLayoutManager, TextKit's layout of a text storage into containers. It
// keeps its containers, storage and delegate, which an app's subclass of it
// overrides drawing in; the text is measured and drawn as attributed string
// drawing lays it out, in lines as wide as the first container less its
// line fragment padding. A glyph is a character here.

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

    /// The storage's text, which a subclass of NSTextStorage may keep
    /// itself: it is read through the storage's own messages.
    private var text: NSAttributedString? { storage?.unsafeCast(to: NSAttributedString.self) }

    private var length: UInt { text?.length() ?? 0 }

    /// The rectangle text is laid out in: the container's width and height
    /// less its line fragment padding at each side.
    private func layoutRect(_ container: NSObject?) -> (rect: CGRect, padding: CGFloat) {
        let state = (container ?? containers.first)?.as(NSTextContainer.self)?.container
        let size = state?.size ?? CGSize(width: 10_000_000, height: 10_000_000)
        let padding = state?.lineFragmentPadding ?? 5
        return (CGRect(x: padding, y: 0, width: max(size.width - padding * 2, 0), height: size.height), padding)
    }

    @ObjCMethod("numberOfGlyphs") func numberOfGlyphs() -> Int { Int(length) }
    @ObjCMethod("glyphRangeForTextContainer:")
    func glyphRange(for container: NSObject?) -> PerryRange { PerryRange(location: 0, length: length) }
    @ObjCMethod("glyphRangeForCharacterRange:actualCharacterRange:")
    func glyphRange(forCharacterRange range: PerryRange, actualCharacterRange: UnsafeMutablePointer<PerryRange>?) -> PerryRange {
        actualCharacterRange?.pointee = range
        return range
    }
    @ObjCMethod("characterRangeForGlyphRange:actualGlyphRange:")
    func characterRange(forGlyphRange range: PerryRange, actualGlyphRange: UnsafeMutablePointer<PerryRange>?) -> PerryRange {
        actualGlyphRange?.pointee = range
        return range
    }

    /// Where the text's lines are, from the top of the container: as wide
    /// as the widest line and its padding, as tall as the lines.
    @ObjCMethod("usedRectForTextContainer:")
    func usedRect(for container: NSObject?) -> CGRect {
        guard let text, text.length() > 0 else { return .zero }
        let (rect, padding) = layoutRect(container)
        let used = text.boundingRect(with: rect.size, options: 1, context: nil)
        return CGRect(x: 0, y: 0, width: (used.width + padding * 2).rounded(.up), height: used.height.rounded(.up))
    }

    @ObjCMethod("boundingRectForGlyphRange:inTextContainer:")
    func boundingRect(forGlyphRange range: PerryRange, in container: NSObject?) -> CGRect { usedRect(for: container) }

    /// Layout is done when it is measured or drawn.
    @ObjCMethod("ensureLayoutForTextContainer:") func ensureLayout(for container: NSObject?) {}
    @ObjCMethod("ensureLayoutForGlyphRange:") func ensureLayout(forGlyphRange range: PerryRange) {}
    @ObjCMethod("ensureLayoutForCharacterRange:") func ensureLayout(forCharacterRange range: PerryRange) {}
    @ObjCMethod("invalidateLayoutForCharacterRange:actualCharacterRange:")
    func invalidateLayout(forCharacterRange range: PerryRange, actualCharacterRange: UnsafeMutablePointer<PerryRange>?) {
        actualCharacterRange?.pointee = range
    }
    @ObjCMethod("invalidateDisplayForCharacterRange:") func invalidateDisplay(forCharacterRange range: PerryRange) {}
    @ObjCMethod("drawBackgroundForGlyphRange:atPoint:") func drawBackground(forGlyphRange range: PerryRange, at point: CGPoint) {}
    /// The text, all of it, laid out in the first container with its top
    /// left at `point` in the current context.
    @ObjCMethod("drawGlyphsForGlyphRange:atPoint:")
    func drawGlyphs(forGlyphRange range: PerryRange, at point: CGPoint) {
        guard let text, range.length > 0, text.length() > 0 else { return }
        var (rect, _) = layoutRect(nil)
        rect.origin.x += point.x
        rect.origin.y += point.y
        text.draw(with: rect, options: 1, context: nil)
    }
}

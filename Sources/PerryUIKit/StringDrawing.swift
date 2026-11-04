import CPerryGeometry
import PerryObjCInterop

// NSString's drawing additions: iOS 7's, with attributes (the font under
// NSFont, the color under NSColor), and iOS 6's, with a font, which draw in
// the context's fill color. Text breaks into lines between words, and lines
// that do not fit end in an ellipsis.

@ObjCWrapper("NSString")
class NSString: NSObject {}

/// NSLineBreakMode: truncating head 3, tail 4, middle 5.
private func truncates(_ mode: Int) -> Bool { (3...5).contains(mode) }

/// The lines `text` takes in `size`: as many whole lines as fit its height
/// (0 for any number), the last cut short if text was left out.
private func layOut(_ text: String, font: UIFont, size: CGSize, lineBreakMode: Int = 0) -> (lines: [String], size: CGSize) {
    let lineHeight = Text.lineHeight(font)
    let limit = size.height > 0 ? max(1, Int((size.height / lineHeight).rounded(.down))) : 0
    var lines = Text.lines(text, font: font, width: size.width > 0 ? size.width : .greatestFiniteMagnitude, limit: limit)
    if truncates(lineBreakMode), size.width > 0 { lines = lines.map { Text.truncated($0, font: font, width: size.width) } }
    let width = lines.map { Text.size($0, font: font).width }.max() ?? 0
    return (lines, CGSize(width: size.width > 0 ? min(width, size.width) : width, height: CGFloat(lines.count) * lineHeight))
}

/// Draws laid-out lines from the top of `rect`, aligned in its width:
/// NSTextAlignment left 0, center 1, right 2.
private func drawLines(_ lines: [String], in rect: CGRect, font: UIFont, color: UIColor?, alignment: Int) {
    let lineHeight = Text.lineHeight(font)
    for (index, line) in lines.enumerated() {
        let width = Text.size(line, font: font).width
        let x = alignment == 1 ? rect.minX + (rect.width - width) / 2 : alignment == 2 ? rect.maxX - width : rect.minX
        Text.draw(line, at: CGPoint(x: x, y: rect.minY + CGFloat(index) * lineHeight), font: font, color: color)
    }
}

/// The font and color in attributes, Helvetica 12 and black by default as
/// on Darwin.
private func style(_ attributes: NSDictionary?) -> (font: UIFont, color: UIColor) {
    let font = attributes?.object(forKey: "NSFont")?.as(UIFont.self) ?? UIFont.systemFont(size: 12)
    let color = attributes?.object(forKey: "NSColor")?.as(UIColor.self) ?? UIColor.black()
    return (font, color)
}

@ObjCCategory("UIStringDrawing")
extension NSString {
    // MARK: With attributes

    @ObjCMethod("sizeWithAttributes:")
    func size(withAttributes attributes: NSDictionary?) -> CGSize { Text.size(stringValue, font: style(attributes).font) }

    /// NSStringDrawingOptions: uses line fragment origin 1 lays the text out
    /// in lines; otherwise it is one line.
    @ObjCMethod("boundingRectWithSize:options:attributes:context:")
    func boundingRect(with size: CGSize, options: Int, attributes: NSDictionary?, context: NSObject?) -> CGRect {
        let font = style(attributes).font
        if options & 1 == 0 { return CGRect(origin: .zero, size: Text.size(stringValue, font: font)) }
        return CGRect(origin: .zero, size: layOut(stringValue, font: font, size: CGSize(width: size.width, height: 0)).size)
    }

    @ObjCMethod("drawAtPoint:withAttributes:")
    func draw(at point: CGPoint, withAttributes attributes: NSDictionary?) {
        let (font, color) = style(attributes)
        Text.draw(stringValue, at: point, font: font, color: color)
    }

    @ObjCMethod("drawInRect:withAttributes:")
    func draw(in rect: CGRect, withAttributes attributes: NSDictionary?) {
        let (font, color) = style(attributes)
        drawLines(layOut(stringValue, font: font, size: rect.size).lines, in: rect, font: font, color: color, alignment: 0)
    }

    @ObjCMethod("drawWithRect:options:attributes:context:")
    func draw(with rect: CGRect, options: Int, attributes: NSDictionary?, context: NSObject?) {
        draw(in: rect, withAttributes: attributes)
    }

    // MARK: With a font

    @ObjCMethod("sizeWithFont:") func size(withFont font: UIFont?) -> CGSize { Text.size(stringValue, font: font ?? UIFont.systemFont(size: 12)) }

    @ObjCMethod("sizeWithFont:forWidth:lineBreakMode:")
    func size(withFont font: UIFont?, forWidth width: CGFloat, lineBreakMode: Int) -> CGSize {
        let size = Text.size(stringValue, font: font ?? UIFont.systemFont(size: 12))
        return CGSize(width: min(size.width, width), height: size.height)
    }

    @ObjCMethod("sizeWithFont:constrainedToSize:")
    func size(withFont font: UIFont?, constrainedTo size: CGSize) -> CGSize {
        self.size(withFont: font, constrainedTo: size, lineBreakMode: 0)
    }

    @ObjCMethod("sizeWithFont:constrainedToSize:lineBreakMode:")
    func size(withFont font: UIFont?, constrainedTo size: CGSize, lineBreakMode: Int) -> CGSize {
        layOut(stringValue, font: font ?? UIFont.systemFont(size: 12), size: size, lineBreakMode: lineBreakMode).size
    }

    @ObjCMethod("sizeWithFont:minFontSize:actualFontSize:forWidth:lineBreakMode:")
    func size(withFont font: UIFont?, minFontSize: CGFloat, actualFontSize: UnsafeMutablePointer<CGFloat>?, forWidth width: CGFloat,
              lineBreakMode: Int) -> CGSize {
        let font = font ?? UIFont.systemFont(size: 12)
        actualFontSize?.pointee = font.state.pointSize
        return size(withFont: font, forWidth: width, lineBreakMode: lineBreakMode)
    }

    @ObjCMethod("drawAtPoint:withFont:")
    func draw(at point: CGPoint, withFont font: UIFont?) -> CGSize {
        let font = font ?? UIFont.systemFont(size: 12)
        Text.draw(stringValue, at: point, font: font, color: nil)
        return Text.size(stringValue, font: font)
    }

    @ObjCMethod("drawAtPoint:forWidth:withFont:lineBreakMode:")
    func draw(at point: CGPoint, forWidth width: CGFloat, withFont font: UIFont?, lineBreakMode: Int) -> CGSize {
        let font = font ?? UIFont.systemFont(size: 12)
        let line = Text.truncated(stringValue, font: font, width: width)
        Text.draw(line, at: point, font: font, color: nil)
        return Text.size(line, font: font)
    }

    @ObjCMethod("drawInRect:withFont:")
    func draw(in rect: CGRect, withFont font: UIFont?) -> CGSize { draw(in: rect, withFont: font, lineBreakMode: 0, alignment: 0) }

    @ObjCMethod("drawInRect:withFont:lineBreakMode:")
    func draw(in rect: CGRect, withFont font: UIFont?, lineBreakMode: Int) -> CGSize {
        draw(in: rect, withFont: font, lineBreakMode: lineBreakMode, alignment: 0)
    }

    @ObjCMethod("drawInRect:withFont:lineBreakMode:alignment:")
    func draw(in rect: CGRect, withFont font: UIFont?, lineBreakMode: Int, alignment: Int) -> CGSize {
        let font = font ?? UIFont.systemFont(size: 12)
        let laidOut = layOut(stringValue, font: font, size: rect.size, lineBreakMode: lineBreakMode)
        drawLines(laidOut.lines, in: rect, font: font, color: nil, alignment: alignment)
        return laidOut.size
    }
}

// MARK: - Attributed strings

@ObjCWrapper("NSAttributedString")
class NSAttributedString: NSObject {
    @ObjCMethod("string")
    func string() -> String

    @ObjCMethod("length")
    func length() -> UInt

    @ObjCMethod("attributesAtIndex:effectiveRange:")
    func attributes(at index: UInt, effectiveRange: UnsafeMutableRawPointer?) -> NSDictionary?
}

final class StringDrawingContextState: ObjectState {
    var minimumScaleFactor: CGFloat = 0
    var actualScaleFactor: CGFloat = 1
    var totalBounds = CGRect.zero
    var baselineOffset: CGFloat = 0
    var firstBaselineOffset: CGFloat = 0
    var scaledLineHeight: CGFloat = 0
    var scaledBaselineOffset: CGFloat = 0
    var wrapsForTruncationMode = false
    var wantsBaselineOffset = false
    var wantsScaledLineHeight = false
    var wantsScaledBaselineOffset = false
    var cachesLayout = false
    var maximumNumberOfLines = 0
    var wantsNumberOfLineFragments = false
    var activeRenderers: UInt = 0
    var layout: NSObject?
    var numberOfLineFragments = 0
    var hasTruncatedRanges = false
    var linkTextAttributesProvider: ObjCBlock?
}

/// NSStringDrawingContext: what measuring and drawing a string may do
/// (scale it down, how many lines), and, after, what it did.
@ObjCClass("NSStringDrawingContext")
open class NSStringDrawingContext: NSObject {
    static let states = StateTable<StringDrawingContextState>()
    var state: StringDrawingContextState { NSStringDrawingContext.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        NSStringDrawingContext.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSStringDrawingContext.objCClass.pointer)
    }

    @ObjCMethod("minimumScaleFactor") func minimumScaleFactor() -> CGFloat { state.minimumScaleFactor }
    @ObjCMethod("setMinimumScaleFactor:") func setMinimumScaleFactor(_ factor: CGFloat) { state.minimumScaleFactor = factor }
    @ObjCMethod("actualScaleFactor") func actualScaleFactor() -> CGFloat { state.actualScaleFactor }
    @ObjCMethod("totalBounds") func totalBounds() -> CGRect { state.totalBounds }

    // Private to UIKit, which SwiftUI uses.
    @ObjCMethod("baselineOffset") func baselineOffset() -> CGFloat { state.baselineOffset }
    @ObjCMethod("setBaselineOffset:") func setBaselineOffset(_ offset: CGFloat) { state.baselineOffset = offset }
    @ObjCMethod("firstBaselineOffset") func firstBaselineOffset() -> CGFloat { state.firstBaselineOffset }
    @ObjCMethod("setFirstBaselineOffset:") func setFirstBaselineOffset(_ offset: CGFloat) { state.firstBaselineOffset = offset }
    @ObjCMethod("scaledLineHeight") func scaledLineHeight() -> CGFloat { state.scaledLineHeight }
    @ObjCMethod("setScaledLineHeight:") func setScaledLineHeight(_ height: CGFloat) { state.scaledLineHeight = height }
    @ObjCMethod("scaledBaselineOffset") func scaledBaselineOffset() -> CGFloat { state.scaledBaselineOffset }
    @ObjCMethod("setScaledBaselineOffset:") func setScaledBaselineOffset(_ offset: CGFloat) { state.scaledBaselineOffset = offset }
    @ObjCMethod("wrapsForTruncationMode") func wrapsForTruncationMode() -> Bool { state.wrapsForTruncationMode }
    @ObjCMethod("setWrapsForTruncationMode:") func setWrapsForTruncationMode(_ value: Bool) { state.wrapsForTruncationMode = value }
    @ObjCMethod("wantsBaselineOffset") func wantsBaselineOffset() -> Bool { state.wantsBaselineOffset }
    @ObjCMethod("setWantsBaselineOffset:") func setWantsBaselineOffset(_ value: Bool) { state.wantsBaselineOffset = value }
    @ObjCMethod("wantsScaledLineHeight") func wantsScaledLineHeight() -> Bool { state.wantsScaledLineHeight }
    @ObjCMethod("setWantsScaledLineHeight:") func setWantsScaledLineHeight(_ value: Bool) { state.wantsScaledLineHeight = value }
    @ObjCMethod("wantsScaledBaselineOffset") func wantsScaledBaselineOffset() -> Bool { state.wantsScaledBaselineOffset }
    @ObjCMethod("setWantsScaledBaselineOffset:") func setWantsScaledBaselineOffset(_ value: Bool) { state.wantsScaledBaselineOffset = value }
    @ObjCMethod("cachesLayout") func cachesLayout() -> Bool { state.cachesLayout }
    @ObjCMethod("setCachesLayout:") func setCachesLayout(_ value: Bool) { state.cachesLayout = value }
    @ObjCMethod("maximumNumberOfLines") func maximumNumberOfLines() -> Int { state.maximumNumberOfLines }
    @ObjCMethod("setMaximumNumberOfLines:") func setMaximumNumberOfLines(_ lines: Int) { state.maximumNumberOfLines = lines }
    @ObjCMethod("wantsNumberOfLineFragments") func wantsNumberOfLineFragments() -> Bool { state.wantsNumberOfLineFragments }
    @ObjCMethod("setWantsNumberOfLineFragments:") func setWantsNumberOfLineFragments(_ value: Bool) { state.wantsNumberOfLineFragments = value }
    @ObjCMethod("activeRenderers") func activeRenderers() -> UInt { state.activeRenderers }
    @ObjCMethod("setActiveRenderers:") func setActiveRenderers(_ renderers: UInt) { state.activeRenderers = renderers }
    @ObjCMethod("layout") func layout() -> NSObject? { state.layout }
    @ObjCMethod("setLayout:") func setLayout(_ layout: NSObject?) { state.layout = layout }
    @ObjCMethod("numberOfLineFragments") func numberOfLineFragments() -> Int { state.numberOfLineFragments }
    @ObjCMethod("hasTruncatedRanges") func hasTruncatedRanges() -> Bool { state.hasTruncatedRanges }
    @ObjCMethod("linkTextAttributesProvider") func linkTextAttributesProvider() -> ObjCBlock? { state.linkTextAttributesProvider }
    @ObjCMethod("setLinkTextAttributesProvider:")
    func setLinkTextAttributesProvider(_ provider: ObjCBlock?) { state.linkTextAttributesProvider = provider }
}

/// The text's layout, in its first run's font, color and paragraph style:
/// lines between words, as many as the height and line limit allow, the
/// last truncated when text is left out.
private struct AttributedLayout {
    var lines: [String]
    var size: CGSize
    var font: UIFont
    var color: UIColor
    var alignment: Int
    var truncated: Bool

    init(_ string: NSAttributedString, size: CGSize, lineLimit: Int) {
        let text = string.string()
        let attributes = string.length() > 0 ? string.attributes(at: 0, effectiveRange: nil) : nil
        let (font, color) = style(attributes)
        let paragraph = attributes?.object(forKey: "NSParagraphStyle")?.as(NSParagraphStyle.self)
        let lineHeight = Text.lineHeight(font)
        var limit = size.height > 0 && size.height < .greatestFiniteMagnitude ? max(1, Int((size.height / lineHeight).rounded(.down))) : 0
        if lineLimit > 0 { limit = limit > 0 ? min(limit, lineLimit) : lineLimit }
        let width = size.width > 0 && size.width < .greatestFiniteMagnitude ? size.width : .greatestFiniteMagnitude
        let all = Text.lines(text, font: font, width: width, limit: 0)
        var lines = limit > 0 ? Array(all.prefix(limit)) : all
        let truncated = lines.count < all.count
        if truncated, let last = lines.indices.last, width < .greatestFiniteMagnitude {
            lines[last] = Text.truncated(lines[last] + " " + all[lines.count...].joined(separator: " "), font: font, width: width)
        }
        let measured = lines.map { Text.size($0, font: font).width }.max() ?? 0
        self.lines = lines
        self.font = font
        self.color = color
        // NSTextAlignment: natural 4 is left.
        self.alignment = paragraph.map { $0.state.alignment == 4 ? 0 : $0.state.alignment } ?? 0
        self.truncated = truncated
        self.size = CGSize(width: min(measured, width), height: CGFloat(max(lines.count, 1)) * lineHeight)
    }

    /// What drawing reports to its context.
    func report(to context: NSStringDrawingContext?) {
        guard let state = context?.state else { return }
        let lineHeight = Text.lineHeight(font)
        state.numberOfLineFragments = lines.count
        state.hasTruncatedRanges = truncated
        state.actualScaleFactor = 1
        state.totalBounds = CGRect(origin: .zero, size: size)
        state.firstBaselineOffset = font.ascender()
        state.baselineOffset = CGFloat(max(lines.count - 1, 0)) * lineHeight + font.ascender()
    }
}

@ObjCCategory("NSExtendedStringDrawing")
extension NSAttributedString {
    @ObjCMethod("size")
    func size() -> CGSize { AttributedLayout(self, size: .zero, lineLimit: 1).size }

    /// NSStringDrawingOptions: uses line fragment origin 1 lays the text out
    /// in lines; otherwise it is one line.
    @ObjCMethod("boundingRectWithSize:options:context:")
    func boundingRect(with size: CGSize, options: Int, context: NSStringDrawingContext?) -> CGRect {
        let lineLimit = options & 1 == 0 ? 1 : context?.state.maximumNumberOfLines ?? 0
        let layout = AttributedLayout(self, size: size, lineLimit: lineLimit)
        layout.report(to: context)
        return CGRect(origin: .zero, size: layout.size)
    }

    @ObjCMethod("drawWithRect:options:context:")
    func draw(with rect: CGRect, options: Int, context: NSStringDrawingContext?) {
        let lineLimit = options & 1 == 0 ? 1 : context?.state.maximumNumberOfLines ?? 0
        let layout = AttributedLayout(self, size: rect.size, lineLimit: lineLimit)
        layout.report(to: context)
        drawLines(layout.lines, in: rect, font: layout.font, color: layout.color, alignment: layout.alignment)
    }

    @ObjCMethod("drawAtPoint:")
    func draw(at point: CGPoint) {
        let layout = AttributedLayout(self, size: .zero, lineLimit: 1)
        drawLines(layout.lines, in: CGRect(origin: point, size: layout.size), font: layout.font, color: layout.color, alignment: 0)
    }

    @ObjCMethod("drawInRect:")
    func draw(in rect: CGRect) {
        draw(with: rect, options: 1, context: nil)
    }
}

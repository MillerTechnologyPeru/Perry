import CPerryGeometry
import Glibc
import PerryObjCInterop

// Text, as AppKit measures and draws it for cells, string drawing and
// attributed strings: runs of one font and color, broken into lines between
// words to fit a width, drawn through CoreGraphics' text functions in the
// current context, upright whether or not its y axis points down. And
// NSStringDrawing, AppKit's additions to NSString and NSAttributedString,
// with NSParagraphStyle for their alignment and line breaks.

/// A piece of text in one style.
struct TextRun {
    var text: String
    var font: NSFont
    var color: NSColor?
    var background: NSColor?
    var underline = false
    var strikethrough = false
}

/// The style of a paragraph: NSTextAlignment, as arm64 Macs number it,
/// left 0, center 1, right 2, justified 3, natural 4 (left here); NSLineBreakMode word wrap 0, char
/// wrap 1, clip 2, truncating head 3, tail 4, middle 5.
struct TextStyle {
    var alignment = 4
    var lineBreakMode = 0
    var lineSpacing: CGFloat = 0
    /// Lines at most, 0 for any number.
    var maximumLines = 0
}

enum Text {
    /// A context to measure text in.
    nonisolated(unsafe) private static var scratch: CGRef?
    /// Widths measured, by font and text.
    nonisolated(unsafe) private static var widths: [String: CGFloat] = [:]

    /// The width of `text` in `font`, on one line.
    static func width(_ text: String, font: NSFont) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let key = "\(font.drawingName)|\(font.size)|\(text)"
        if let width = widths[key] { return width }
        let width = measure(text, font: font)
        if widths.count > 8192 { widths = [:] }
        widths[key] = width
        return width
    }

    private static func measure(_ text: String, font: NSFont) -> CGFloat {
        if scratch == nil { scratch = CG.makeContext(size: CGSize(width: 1, height: 1), scale: 1) }
        guard let context = scratch else { return CGFloat(text.count) * font.size * 0.55 }
        CG.saveGState(context)
        defer { CG.restoreGState(context) }
        font.drawingName.withCString { CG.selectFont(context, $0, font.size, 1) }
        CG.setTextDrawingMode(context, 3) // invisible
        CG.setTextPosition(context, 0, 0)
        show(text, in: context)
        return CG.getTextPosition(context).x
    }

    private static func show(_ text: String, in context: CGRef) {
        var utf8 = Array(text.utf8)
        utf8.withUnsafeMutableBufferPointer { buffer in
            buffer.baseAddress!.withMemoryRebound(to: CChar.self, capacity: buffer.count) { CG.showText(context, $0, buffer.count) }
        }
    }

    static func ascent(_ font: NSFont) -> CGFloat { (font.size * 0.95).rounded(.up) }
    static func lineHeight(_ font: NSFont) -> CGFloat { (font.size * 1.19).rounded(.up) }

    /// A laid-out line: its pieces, each with its width.
    struct Line {
        var pieces: [(run: TextRun, width: CGFloat)] = []
        var width: CGFloat = 0
        var ascent: CGFloat = 0
        var height: CGFloat = 0
        var text: String { pieces.map(\.run.text).joined() }
    }

    /// `runs` broken into lines no wider than `width` (infinite for no
    /// wrapping): at newlines, then between words, and within a word too
    /// long for a line. Lines past `style.maximumLines` are left out, and
    /// the last shown is cut short with an ellipsis when text was.
    static func layout(_ runs: [TextRun], width: CGFloat, style: TextStyle = TextStyle()) -> [Line] {
        var lines: [Line] = []
        var line = Line()
        let wraps = width.isFinite && style.lineBreakMode <= 1
        func finish() {
            if line.pieces.isEmpty, let run = runs.last {
                line.ascent = ascent(run.font)
                line.height = lineHeight(run.font)
            }
            lines.append(line)
            line = Line()
        }
        func append(_ text: String, _ run: TextRun) {
            guard !text.isEmpty else { return }
            var piece = run
            piece.text = text
            let w = self.width(text, font: run.font)
            if let last = line.pieces.indices.last, line.pieces[last].run.font === run.font, line.pieces[last].run.color === run.color,
               line.pieces[last].run.underline == run.underline {
                line.pieces[last].run.text += text
                line.pieces[last].width = self.width(line.pieces[last].run.text, font: run.font)
            } else {
                line.pieces.append((piece, w))
            }
            line.width = line.pieces.reduce(0) { $0 + $1.width }
            line.ascent = max(line.ascent, ascent(run.font))
            line.height = max(line.height, lineHeight(run.font))
        }
        for run in runs {
            let paragraphs = run.text.split(separator: "\n", omittingEmptySubsequences: false)
            for (index, paragraph) in paragraphs.enumerated() {
                if index > 0 { finish() }
                guard wraps else {
                    append(String(paragraph), run)
                    continue
                }
                // Words with the spaces after them.
                var words: [String] = []
                var current = ""
                for character in paragraph {
                    current.append(character)
                    if character == " " {
                        words.append(current)
                        current = ""
                    }
                }
                if !current.isEmpty { words.append(current) }
                for word in words {
                    let trimmed = word.trimmingSpaces
                    let fits = line.width + self.width(trimmed, font: run.font) <= width
                    if fits || line.pieces.isEmpty && self.width(trimmed, font: run.font) <= width {
                        append(word, run)
                        continue
                    }
                    if !line.pieces.isEmpty { finish() }
                    if self.width(trimmed, font: run.font) <= width {
                        append(word, run)
                        continue
                    }
                    // Too long for any line: broken between characters.
                    for character in word {
                        if !line.pieces.isEmpty, line.width + self.width(String(character), font: run.font) > width { finish() }
                        append(String(character), run)
                    }
                }
            }
        }
        if !line.pieces.isEmpty || lines.isEmpty { finish() }
        // Trailing spaces take no room at a line's end.
        for index in lines.indices {
            guard let last = lines[index].pieces.indices.last else { continue }
            let text = lines[index].pieces[last].run.text
            let trimmed = String(text.reversed().drop { $0 == " " }.reversed())
            if trimmed != text {
                lines[index].pieces[last].run.text = trimmed
                lines[index].pieces[last].width = self.width(trimmed, font: lines[index].pieces[last].run.font)
                lines[index].width = lines[index].pieces.reduce(0) { $0 + $1.width }
            }
        }
        if style.maximumLines > 0, lines.count > style.maximumLines {
            let cut = lines[style.maximumLines...].map(\.text).joined(separator: " ")
            lines = Array(lines.prefix(style.maximumLines))
            if var last = lines.popLast(), let piece = last.pieces.last {
                last.pieces[last.pieces.count - 1].run.text += " " + cut
                last.pieces[last.pieces.count - 1].width = self.width(last.pieces[last.pieces.count - 1].run.text, font: piece.run.font)
                last.width = last.pieces.reduce(0) { $0 + $1.width }
                lines.append(last)
            }
        }
        // Truncating modes, and wrapped text cut at its last line, end in an
        // ellipsis when they don't fit.
        if width.isFinite, style.lineBreakMode >= 3 || style.maximumLines > 0 {
            for index in lines.indices where lines[index].width > width {
                lines[index] = truncated(lines[index], width: width, mode: style.lineBreakMode)
            }
        }
        return lines
    }

    /// A line cut short with an ellipsis to fit `width`.
    static func truncated(_ line: Line, width: CGFloat, mode: Int) -> Line {
        guard let first = line.pieces.first else { return line }
        let font = first.run.font
        let full = line.text
        let ellipsis = "…"
        var kept = Substring(full)
        func fits(_ text: String) -> Bool { self.width(text, font: font) <= width }
        var result: String
        switch mode {
        case 3:
            while !kept.isEmpty, !fits(ellipsis + kept) { kept = kept.dropFirst() }
            result = ellipsis + kept
        case 5:
            var head = Substring(full.prefix(full.count / 2)), tail = Substring(full.suffix(full.count - full.count / 2))
            while !(head.isEmpty && tail.isEmpty), !fits(String(head) + ellipsis + tail) {
                if head.count >= tail.count { head = head.dropLast() } else { tail = tail.dropFirst() }
            }
            result = String(head) + ellipsis + tail
        default:
            while !kept.isEmpty, !fits(String(kept).trimmingTrailingSpaces + ellipsis) { kept = kept.dropLast() }
            result = String(kept).trimmingTrailingSpaces + ellipsis
        }
        var run = first.run
        run.text = result
        var cut = Line()
        cut.pieces = [(run, self.width(result, font: font))]
        (cut.width, cut.ascent, cut.height) = (cut.pieces[0].width, line.ascent, line.height)
        return cut
    }

    /// The size laid-out lines take.
    static func size(_ lines: [Line], style: TextStyle = TextStyle()) -> CGSize {
        let width = lines.map(\.width).max() ?? 0
        let height = lines.reduce(0) { $0 + $1.height } + CGFloat(max(0, lines.count - 1)) * style.lineSpacing
        return CGSize(width: width.rounded(.up), height: height.rounded(.up))
    }

    static func size(_ runs: [TextRun], width: CGFloat = .infinity, style: TextStyle = TextStyle()) -> CGSize {
        size(layout(runs, width: width, style: style), style: style)
    }

    /// Draws laid-out lines from the top of `rect` in the current context,
    /// aligned in its width.
    static func draw(_ lines: [Line], in rect: CGRect, style: TextStyle = TextStyle()) {
        guard let context = NSGraphicsContext.currentCG else { return }
        let flipped = NSGraphicsContext.current?.flipped ?? false
        var top: CGFloat = 0
        for line in lines {
            let x: CGFloat
            switch style.alignment {
            case 1: x = rect.minX + ((rect.width - line.width) / 2).rounded()
            case 2: x = rect.maxX - line.width
            default: x = rect.minX
            }
            var position = x
            let baseline = top + line.ascent
            for piece in line.pieces {
                let y = flipped ? rect.minY + baseline : rect.maxY - baseline
                draw(piece.run, at: CGPoint(x: position, y: y), width: piece.width, lineTop: flipped ? rect.minY + top : rect.maxY - top,
                     lineHeight: line.height, flipped: flipped, context: context)
                position += piece.width
            }
            top += line.height + style.lineSpacing
        }
    }

    /// Draws a run with its baseline at `point`.
    private static func draw(_ run: TextRun, at point: CGPoint, width: CGFloat, lineTop: CGFloat, lineHeight: CGFloat, flipped: Bool,
                             context: CGRef) {
        CG.saveGState(context)
        defer { CG.restoreGState(context) }
        if let background = run.background {
            CG.setFill(context, background)
            CG.fillRect(context, CGRect(x: point.x, y: flipped ? lineTop : lineTop - lineHeight, width: width, height: lineHeight))
        }
        let color = run.color ?? NSColor.textColor()
        CG.setFill(context, color)
        run.font.drawingName.withCString { CG.selectFont(context, $0, run.font.size, 1) }
        CG.setTextDrawingMode(context, 0)
        CG.setTextMatrix(context, CGAffineTransform(a: 1, b: 0, c: 0, d: flipped ? -1 : 1, tx: 0, ty: 0))
        CG.setTextPosition(context, point.x, point.y)
        show(run.text, in: context)
        let thickness = max(1, run.font.size / 14)
        if run.underline {
            let y = flipped ? point.y + thickness * 1.5 : point.y - thickness * 2.5
            CG.fillRect(context, CGRect(x: point.x, y: y, width: width, height: thickness))
        }
        if run.strikethrough {
            let middle = run.font.size * 0.3
            CG.fillRect(context, CGRect(x: point.x, y: flipped ? point.y - middle : point.y + middle - thickness, width: width, height: thickness))
        }
    }

    static func draw(_ runs: [TextRun], in rect: CGRect, style: TextStyle = TextStyle()) {
        draw(layout(runs, width: rect.width > 0 ? rect.width : .infinity, style: style), in: rect, style: style)
    }

    // MARK: Attributed strings

    /// The runs of an NSAttributedString, in its fonts and colors (`font`
    /// and `color` where it has none), and its first paragraph style.
    static func runs(_ attributed: NSObject, font: NSFont, color: NSColor?) -> (runs: [TextRun], paragraph: NSObject?) {
        guard let stringObject = Send.object(attributed.objcObject, "string") else { return ([], nil) }
        let string = String(objCArgument: stringObject)
        let units = Array(string.utf16)
        var runs: [TextRun] = []
        var paragraph: NSObject?
        var location = 0
        typealias AttributesAt = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, UInt, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
        let attributesAt = unsafeBitCast(ObjCRuntime.msgSend, to: AttributesAt.self)
        while location < units.count {
            var range = NSRange(location: 0, length: 0)
            let attributes = attributesAt(attributed.objcObject, ObjCRuntime.selector("attributesAtIndex:effectiveRange:"), UInt(location), &range)
                .map(NSObject.init)?.as(NSDictionary.self)
            let end = min(units.count, max(location + 1, Int(range.location + range.length)))
            let text = String(decoding: units[location..<end], as: UTF16.self)
            var run = TextRun(text: text, font: font, color: color)
            if let attributes { style(&run, attributes, paragraph: &paragraph) }
            runs.append(run)
            location = end
        }
        return (runs, paragraph)
    }

    /// The font, colors and lines an attributes dictionary names.
    static func style(_ run: inout TextRun, _ attributes: NSDictionary, paragraph: inout NSObject?) {
        if let font = attributes.object(forKey: "NSFont")?.as(NSFont.self) { run.font = font }
        if let color = attributes.object(forKey: "NSColor")?.as(NSColor.self) { run.color = color }
        if let background = attributes.object(forKey: "NSBackgroundColor")?.as(NSColor.self) { run.background = background }
        if let underline = attributes.object(forKey: "NSUnderline") { run.underline = Send.integer(underline.objcObject, "integerValue") != 0 }
        if let strike = attributes.object(forKey: "NSStrikethrough") { run.strikethrough = Send.integer(strike.objcObject, "integerValue") != 0 }
        if attributes.object(forKey: "NSLink") != nil {
            if attributes.object(forKey: "NSColor") == nil { run.color = NSColor.linkColor() }
            run.underline = true
        }
        if paragraph == nil { paragraph = attributes.object(forKey: "NSParagraphStyle") }
    }

    /// A paragraph style's alignment and line breaks.
    static func style(_ paragraph: NSObject?, into style: inout TextStyle) {
        guard let paragraph else { return }
        style.alignment = Send.integer(paragraph.objcObject, "alignment")
        style.lineBreakMode = Send.integer(paragraph.objcObject, "lineBreakMode")
        style.lineSpacing = CGFloat(Send.double(paragraph.objcObject, "lineSpacing"))
    }

    /// The runs and style of a string with attributes.
    static func runs(_ string: String, attributes: NSObject?) -> (runs: [TextRun], style: TextStyle) {
        var run = TextRun(text: string, font: NSFont(name: "Helvetica", size: 12), color: NSColor.blackColor())
        var paragraph: NSObject?
        if let attributes = attributes?.as(NSDictionary.self) { self.style(&run, attributes, paragraph: &paragraph) }
        var style = TextStyle()
        self.style(paragraph, into: &style)
        return ([run], style)
    }
}

/// Foundation's NSRange.
typealias NSRange = PerryRange

extension PerryRange: ObjCStructure {
    public typealias ObjCType = PerryRange
    public static var objCTypeEncoding: String { "{_NSRange=QQ}" }
}

extension String {
    var trimmingSpaces: String { String(drop { $0 == " " }.reversed().drop { $0 == " " }.reversed()) }
    var trimmingTrailingSpaces: String { String(reversed().drop { $0 == " " }.reversed()) }
}

extension Send {
    static func integer(_ receiver: Object?, _ selector: String) -> Int {
        guard let receiver else { return 0 }
        typealias F = @convention(c) (Object, Selector) -> Int
        return unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector(selector))
    }

    static func double(_ receiver: Object?, _ selector: String) -> Double {
        guard let receiver else { return 0 }
        typealias F = @convention(c) (Object, Selector) -> Double
        return unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector(selector))
    }
}

// MARK: - NSStringDrawing

/// NSStringDrawingOptions: uses line fragment origin 1 (wrapping in the
/// rectangle's width; otherwise one line, from the baseline).
private let usesLineFragmentOrigin: UInt = 1

@ObjCWrapper("NSString")
class NSString: NSObject {}

@ObjCCategory("NSStringDrawing")
extension NSString {
    @ObjCMethod("sizeWithAttributes:")
    func size(withAttributes attributes: NSObject?) -> CGSize {
        let (runs, style) = Text.runs(stringValue, attributes: attributes)
        return Text.size(runs, style: style)
    }

    @ObjCMethod("drawAtPoint:withAttributes:")
    func draw(at point: CGPoint, withAttributes attributes: NSObject?) {
        let (runs, style) = Text.runs(stringValue, attributes: attributes)
        let lines = Text.layout(runs, width: .infinity, style: style)
        let size = Text.size(lines, style: style)
        // The point is the text's origin: its top left in a flipped view,
        // its bottom left otherwise.
        let flipped = NSGraphicsContext.current?.flipped ?? false
        Text.draw(lines, in: CGRect(x: point.x, y: flipped ? point.y : point.y, width: size.width, height: size.height), style: style)
    }

    @ObjCMethod("drawInRect:withAttributes:")
    func draw(in rect: CGRect, withAttributes attributes: NSObject?) {
        let (runs, style) = Text.runs(stringValue, attributes: attributes)
        Text.draw(runs, in: rect, style: style)
    }

    @ObjCMethod("drawWithRect:options:attributes:")
    func draw(with rect: CGRect, options: UInt, attributes: NSObject?) {
        draw(with: rect, options: options, attributes: attributes, context: nil)
    }

    @ObjCMethod("drawWithRect:options:attributes:context:")
    func draw(with rect: CGRect, options: UInt, attributes: NSObject?, context: NSObject?) {
        var (runs, style) = Text.runs(stringValue, attributes: attributes)
        if options & usesLineFragmentOrigin == 0 { style.maximumLines = 1 }
        Text.draw(runs, in: rect, style: style)
    }

    @ObjCMethod("boundingRectWithSize:options:attributes:")
    func boundingRect(with size: CGSize, options: UInt, attributes: NSObject?) -> CGRect {
        boundingRect(with: size, options: options, attributes: attributes, context: nil)
    }

    @ObjCMethod("boundingRectWithSize:options:attributes:context:")
    func boundingRect(with size: CGSize, options: UInt, attributes: NSObject?, context: NSObject?) -> CGRect {
        let (runs, style) = Text.runs(stringValue, attributes: attributes)
        let width = options & usesLineFragmentOrigin != 0 && size.width > 0 ? size.width : .infinity
        return CGRect(origin: .zero, size: Text.size(runs, width: width, style: style))
    }
}

@ObjCWrapper("NSAttributedString")
class NSAttributedString: NSObject {}

@ObjCCategory("NSStringDrawing")
extension NSAttributedString {
    private func laidOut(width: CGFloat) -> (lines: [Text.Line], style: TextStyle) {
        let (runs, paragraph) = Text.runs(self, font: NSFont(name: "Helvetica", size: 12), color: NSColor.blackColor())
        var style = TextStyle()
        Text.style(paragraph, into: &style)
        return (Text.layout(runs, width: width, style: style), style)
    }

    @ObjCMethod("size")
    func attributedSize() -> CGSize {
        let (lines, style) = laidOut(width: .infinity)
        return Text.size(lines, style: style)
    }

    @ObjCMethod("drawAtPoint:")
    func draw(at point: CGPoint) {
        let (lines, style) = laidOut(width: .infinity)
        let size = Text.size(lines, style: style)
        Text.draw(lines, in: CGRect(origin: point, size: size), style: style)
    }

    @ObjCMethod("drawInRect:")
    func draw(in rect: CGRect) {
        let (lines, style) = laidOut(width: rect.width > 0 ? rect.width : .infinity)
        Text.draw(lines, in: rect, style: style)
    }

    @ObjCMethod("drawWithRect:options:") func draw(with rect: CGRect, options: UInt) { draw(in: rect) }
    @ObjCMethod("drawWithRect:options:context:") func draw(with rect: CGRect, options: UInt, context: NSObject?) { draw(in: rect) }

    @ObjCMethod("boundingRectWithSize:options:")
    func boundingRect(with size: CGSize, options: UInt) -> CGRect { boundingRect(with: size, options: options, context: nil) }

    @ObjCMethod("boundingRectWithSize:options:context:")
    func boundingRect(with size: CGSize, options: UInt, context: NSObject?) -> CGRect {
        let width = options & usesLineFragmentOrigin != 0 && size.width > 0 ? size.width : .infinity
        let (lines, style) = laidOut(width: width)
        return CGRect(origin: .zero, size: Text.size(lines, style: style))
    }
}

// MARK: - NSParagraphStyle

@ObjCClass("NSParagraphStyle")
open class NSParagraphStyle: NSObject {
    var alignment = 4
    var lineBreakMode = 0
    var lineSpacing: CGFloat = 0
    var paragraphSpacing: CGFloat = 0
    var paragraphSpacingBefore: CGFloat = 0
    var firstLineHeadIndent: CGFloat = 0
    var headIndent: CGFloat = 0
    var tailIndent: CGFloat = 0
    var minimumLineHeight: CGFloat = 0
    var maximumLineHeight: CGFloat = 0
    var lineHeightMultiple: CGFloat = 0
    var baseWritingDirection = -1
    var hyphenationFactor: Float = 0
    var allowsDefaultTighteningForTruncation = false
    var tabStops: NSObject?
    var textBlocks: NSObject?
    var textLists: NSObject?
    var defaultTabInterval: CGFloat = 0

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init()
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        if decoded.has("NSAlignment") { alignment = decoded.integer("NSAlignment") }
        lineBreakMode = decoded.integer("NSLineBreakMode")
        lineSpacing = decoded.double("NSLineSpacing")
        paragraphSpacing = decoded.double("NSParagraphSpacing")
    }

    @ObjCClassMethod("defaultParagraphStyle") static func defaultParagraphStyle() -> NSParagraphStyle { NSParagraphStyle() }
    @ObjCClassMethod("defaultWritingDirectionForLanguage:") static func defaultWritingDirection(forLanguage language: String?) -> Int { 0 }

    func copyValues(to copy: NSParagraphStyle) {
        (copy.alignment, copy.lineBreakMode, copy.lineSpacing, copy.paragraphSpacing) = (alignment, lineBreakMode, lineSpacing, paragraphSpacing)
        (copy.paragraphSpacingBefore, copy.firstLineHeadIndent, copy.headIndent, copy.tailIndent) =
            (paragraphSpacingBefore, firstLineHeadIndent, headIndent, tailIndent)
        (copy.minimumLineHeight, copy.maximumLineHeight, copy.lineHeightMultiple) = (minimumLineHeight, maximumLineHeight, lineHeightMultiple)
        (copy.baseWritingDirection, copy.hyphenationFactor, copy.tabStops, copy.defaultTabInterval) =
            (baseWritingDirection, hyphenationFactor, tabStops, defaultTabInterval)
        (copy.textBlocks, copy.textLists) = (textBlocks, textLists)
        copy.allowsDefaultTighteningForTruncation = allowsDefaultTighteningForTruncation
    }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
        let copy = NSParagraphStyle()
        copyValues(to: copy)
        return ObjCRuntime.retain(copy.objcObject)!
    }

    @ObjCMethod("mutableCopyWithZone:")
    func mutableCopy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
        let copy = NSMutableParagraphStyle()
        copyValues(to: copy)
        return ObjCRuntime.retain(copy.objcObject)!
    }

    @ObjCMethod("alignment") func styleAlignment() -> Int { alignment }
    @ObjCMethod("lineBreakMode") func styleLineBreakMode() -> Int { lineBreakMode }
    @ObjCMethod("lineSpacing") func styleLineSpacing() -> CGFloat { lineSpacing }
    @ObjCMethod("paragraphSpacing") func styleParagraphSpacing() -> CGFloat { paragraphSpacing }
    @ObjCMethod("paragraphSpacingBefore") func styleParagraphSpacingBefore() -> CGFloat { paragraphSpacingBefore }
    @ObjCMethod("firstLineHeadIndent") func styleFirstLineHeadIndent() -> CGFloat { firstLineHeadIndent }
    @ObjCMethod("headIndent") func styleHeadIndent() -> CGFloat { headIndent }
    @ObjCMethod("tailIndent") func styleTailIndent() -> CGFloat { tailIndent }
    @ObjCMethod("minimumLineHeight") func styleMinimumLineHeight() -> CGFloat { minimumLineHeight }
    @ObjCMethod("maximumLineHeight") func styleMaximumLineHeight() -> CGFloat { maximumLineHeight }
    @ObjCMethod("lineHeightMultiple") func styleLineHeightMultiple() -> CGFloat { lineHeightMultiple }
    @ObjCMethod("baseWritingDirection") func styleBaseWritingDirection() -> Int { baseWritingDirection }
    @ObjCMethod("hyphenationFactor") func styleHyphenationFactor() -> Float { hyphenationFactor }
    @ObjCMethod("allowsDefaultTighteningForTruncation") func styleAllowsTightening() -> Bool { allowsDefaultTighteningForTruncation }
    @ObjCMethod("tabStops") func styleTabStops() -> NSObject { tabStops ?? NSMutableArray.empty() }
    @ObjCMethod("defaultTabInterval") func styleDefaultTabInterval() -> CGFloat { defaultTabInterval }
    @ObjCMethod("textBlocks") func textBlocksValue() -> NSObject { textBlocks ?? NSMutableArray.empty() }
    @ObjCMethod("textLists") func textListsValue() -> NSObject { textLists ?? NSMutableArray.empty() }
    @ObjCMethod("headerLevel") func headerLevel() -> Int { 0 }
}

@ObjCClass("NSMutableParagraphStyle")
open class NSMutableParagraphStyle: NSParagraphStyle {
    @ObjCMethod("setAlignment:") func setAlignment(_ value: Int) { alignment = value }
    @ObjCMethod("setLineBreakMode:") func setLineBreakMode(_ value: Int) { lineBreakMode = value }
    @ObjCMethod("setLineSpacing:") func setLineSpacing(_ value: CGFloat) { lineSpacing = value }
    @ObjCMethod("setParagraphSpacing:") func setParagraphSpacing(_ value: CGFloat) { paragraphSpacing = value }
    @ObjCMethod("setParagraphSpacingBefore:") func setParagraphSpacingBefore(_ value: CGFloat) { paragraphSpacingBefore = value }
    @ObjCMethod("setFirstLineHeadIndent:") func setFirstLineHeadIndent(_ value: CGFloat) { firstLineHeadIndent = value }
    @ObjCMethod("setHeadIndent:") func setHeadIndent(_ value: CGFloat) { headIndent = value }
    @ObjCMethod("setTailIndent:") func setTailIndent(_ value: CGFloat) { tailIndent = value }
    @ObjCMethod("setMinimumLineHeight:") func setMinimumLineHeight(_ value: CGFloat) { minimumLineHeight = value }
    @ObjCMethod("setMaximumLineHeight:") func setMaximumLineHeight(_ value: CGFloat) { maximumLineHeight = value }
    @ObjCMethod("setLineHeightMultiple:") func setLineHeightMultiple(_ value: CGFloat) { lineHeightMultiple = value }
    @ObjCMethod("setBaseWritingDirection:") func setBaseWritingDirection(_ value: Int) { baseWritingDirection = value }
    @ObjCMethod("setHyphenationFactor:") func setHyphenationFactor(_ value: Float) { hyphenationFactor = value }
    @ObjCMethod("setAllowsDefaultTighteningForTruncation:") func setAllowsTightening(_ value: Bool) { allowsDefaultTighteningForTruncation = value }
    @ObjCMethod("setTabStops:") func setTabStops(_ value: NSObject?) { tabStops = value }
    @ObjCMethod("setTextBlocks:") func setTextBlocks(_ value: NSObject?) { textBlocks = value }
    @ObjCMethod("setTextLists:") func setTextLists(_ value: NSObject?) { textLists = value }
    @ObjCMethod("setDefaultTabInterval:") func setDefaultTabInterval(_ value: CGFloat) { defaultTabInterval = value }
    @ObjCMethod("setParagraphStyle:")
    func setParagraphStyle(_ other: NSParagraphStyle?) { other?.copyValues(to: self) }
}

/// NSShadow: kept, not drawn.
@ObjCClass("NSShadow")
open class NSShadow: NSObject {
    var offset = CGSize.zero
    var blurRadius: CGFloat = 0
    var color: NSObject?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) { super.init() }

    @ObjCMethod("shadowOffset") func shadowOffset() -> CGSize { offset }
    @ObjCMethod("setShadowOffset:") func setShadowOffset(_ value: CGSize) { offset = value }
    @ObjCMethod("shadowBlurRadius") func shadowBlurRadius() -> CGFloat { blurRadius }
    @ObjCMethod("setShadowBlurRadius:") func setShadowBlurRadius(_ value: CGFloat) { blurRadius = value }
    @ObjCMethod("shadowColor") func shadowColor() -> NSObject? { color }
    @ObjCMethod("setShadowColor:") func setShadowColor(_ value: NSObject?) { color = value }
    @ObjCMethod("set") func set() {}
}

import CPerryGeometry
import Glibc
import PerryObjCInterop

// Text and images in views: UIFont, which names a font and its size;
// UILabel, which draws its text through CoreGraphics; and UIImageView,
// whose layer shows its image.

final class FontState: ObjectState {
    var name = "Helvetica"
    var pointSize: CGFloat = 17
    var weight: CGFloat = 0
}

@ObjCClass("UIFont")
open class UIFont: NSObject {
    static let states = StateTable<FontState>()
    var state: FontState { UIFont.states[objcObject] }

    static func make(name: String, size: CGFloat, weight: CGFloat = 0) -> UIFont {
        let font = objCClass.object.allocated().unsafeCast(to: UIFont.self)
        (font.state.name, font.state.pointSize, font.state.weight) = (name, size, weight)
        return font
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        UIFont.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIFont.objCClass.pointer)
    }

    /// From a nib: the font's name and size, or the system font.
    @ObjCMethod("initWithCoder:")
    func initialize(coder: NSObject) -> Self {
        let decoded = Coder(coder: coder)
        let traits = decoded.integer("UIFontTraits")
        state.pointSize = decoded.has("UIFontPointSize") ? decoded.double("UIFontPointSize") : 17
        if decoded.bool("UISystemFont") || decoded.string("UIFontName")?.hasPrefix(".") == true {
            state.name = ".SFUI-Regular"
            state.weight = traits & 2 != 0 || decoded.string("UIFontName")?.contains("Bold") == true
                || decoded.string("UIFontName")?.contains("Semibold") == true ? 0.4 : 0
        } else {
            state.name = decoded.string("UIFontName") ?? "Helvetica"
        }
        return self
    }

    @ObjCClassMethod("systemFontOfSize:") static func systemFont(size: CGFloat) -> UIFont { make(name: ".SFUI-Regular", size: size) }
    @ObjCClassMethod("boldSystemFontOfSize:") static func boldSystemFont(size: CGFloat) -> UIFont { make(name: ".SFUI-Semibold", size: size, weight: 0.4) }
    @ObjCClassMethod("italicSystemFontOfSize:") static func italicSystemFont(size: CGFloat) -> UIFont { make(name: ".SFUI-RegularItalic", size: size) }

    @ObjCClassMethod("systemFontOfSize:weight:")
    static func systemFont(size: CGFloat, weight: CGFloat) -> UIFont { make(name: ".SFUI-Regular", size: size, weight: weight) }

    @ObjCClassMethod("monospacedSystemFontOfSize:weight:")
    static func monospacedSystemFont(size: CGFloat, weight: CGFloat) -> UIFont { make(name: "Courier", size: size, weight: weight) }

    @ObjCClassMethod("monospacedDigitSystemFontOfSize:weight:")
    static func monospacedDigitSystemFont(size: CGFloat, weight: CGFloat) -> UIFont { make(name: ".SFUI-Regular", size: size, weight: weight) }

    @ObjCClassMethod("fontWithName:size:")
    static func font(name: String, size: CGFloat) -> UIFont? { make(name: name, size: size) }

    /// Text styles at their default sizes.
    @ObjCClassMethod("preferredFontForTextStyle:")
    static func preferredFont(textStyle: String) -> UIFont {
        let sizes: [String: CGFloat] = [
            "UICTFontTextStyleLargeTitle": 34, "UICTFontTextStyleTitle1": 28, "UICTFontTextStyleTitle2": 22,
            "UICTFontTextStyleTitle3": 20, "UICTFontTextStyleHeadline": 17, "UICTFontTextStyleSubhead": 15,
            "UICTFontTextStyleBody": 17, "UICTFontTextStyleCallout": 16, "UICTFontTextStyleFootnote": 13,
            "UICTFontTextStyleCaption1": 12, "UICTFontTextStyleCaption2": 11,
        ]
        return make(name: ".SFUI-Regular", size: sizes[textStyle] ?? 17, weight: textStyle == "UICTFontTextStyleHeadline" ? 0.3 : 0)
    }

    @ObjCClassMethod("systemFontSize") static func systemFontSize() -> CGFloat { 14 }
    @ObjCClassMethod("labelFontSize") static func labelFontSize() -> CGFloat { 17 }

    @ObjCMethod("fontName") func fontName() -> String { state.name }
    @ObjCMethod("familyName") func familyName() -> String { state.name.hasPrefix(".SFUI") ? ".AppleSystemUIFont" : state.name }
    @ObjCMethod("pointSize") func pointSize() -> CGFloat { state.pointSize }
    @ObjCMethod("ascender") func ascender() -> CGFloat { state.pointSize * 0.95 }
    @ObjCMethod("descender") func descender() -> CGFloat { -state.pointSize * 0.24 }
    @ObjCMethod("lineHeight") func lineHeight() -> CGFloat { state.pointSize * 1.19 }
    @ObjCMethod("capHeight") func capHeight() -> CGFloat { state.pointSize * 0.7 }
    @ObjCMethod("xHeight") func xHeight() -> CGFloat { state.pointSize * 0.52 }
    @ObjCMethod("leading") func leading() -> CGFloat { 0 }

    @ObjCMethod("fontWithSize:")
    func withSize(_ size: CGFloat) -> UIFont { UIFont.make(name: state.name, size: size, weight: state.weight) }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: NSObject?) -> Bool {
        guard let other = other?.as(UIFont.self) else { return false }
        return other.state.name == state.name && other.state.pointSize == state.pointSize
    }

    @ObjCMethod("hash") func hash() -> UInt { UInt(bitPattern: state.name.hashValue) ^ UInt(state.pointSize) }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }

    /// The font CoreGraphics draws with: a bold or regular sans serif for
    /// the system font.
    var drawingName: String {
        if state.name.hasPrefix(".SFUI") { return state.weight >= 0.3 ? "DejaVu Sans Bold" : "DejaVu Sans" }
        return state.name
    }
}

// MARK: - Measuring and drawing text

enum Text {
    /// A context to measure text in.
    nonisolated(unsafe) private static var scratch: CGRef?

    /// Widths measured, by font and text.
    nonisolated(unsafe) private static var widths: [String: CGFloat] = [:]

    /// The width of `text` in `font`, on one line.
    static func width(_ text: String, font: UIFont) -> CGFloat {
        let key = "\(font.drawingName)|\(font.state.pointSize)|\(text)"
        if let width = widths[key] { return width }
        let width = measure(text, font: font)
        if widths.count > 4096 { widths = [:] }
        widths[key] = width
        return width
    }

    private static func measure(_ text: String, font: UIFont) -> CGFloat {
        if scratch == nil { scratch = CG.makeContext(size: CGSize(width: 1, height: 1), scale: 1, opaque: false) }
        guard let context = scratch else { return 0 }
        CG.saveGState(context)
        defer { CG.restoreGState(context) }
        font.drawingName.withCString { CG.selectFont(context, $0, font.state.pointSize, 1) }
        CG.setTextDrawingMode(context, 3) // invisible
        CG.setTextPosition(context, 0, 0)
        var utf8 = Array(text.utf8)
        utf8.withUnsafeMutableBufferPointer { buffer in
            buffer.baseAddress!.withMemoryRebound(to: CChar.self, capacity: buffer.count) { CG.showText(context, $0, buffer.count) }
        }
        return CG.getTextPosition(context).x
    }

    /// The size of `text` on one line.
    static func size(_ text: String, font: UIFont) -> CGSize {
        CGSize(width: (width(text, font: font)).rounded(.up), height: lineHeight(font))
    }

    static func lineHeight(_ font: UIFont) -> CGFloat { (font.state.pointSize * 1.19).rounded(.up) }

    /// `text` broken into lines no wider than `width`: at its newlines, then
    /// between words, and within a word too long for a line. With `limit`
    /// lines at most (0 for any number), the last shown ends in an ellipsis
    /// if text was left out.
    static func lines(_ text: String, font: UIFont, width: CGFloat, limit: Int) -> [String] {
        var lines: [String] = []
        for paragraph in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = ""
            for word in paragraph.split(separator: " ", omittingEmptySubsequences: false) {
                let candidate = line.isEmpty ? String(word) : line + " " + word
                if self.width(candidate, font: font) <= width || line.isEmpty && word.isEmpty {
                    line = candidate
                    continue
                }
                if !line.isEmpty { lines.append(line) }
                // A word wider than the line is broken between characters.
                line = ""
                for character in word {
                    if !line.isEmpty, self.width(line + String(character), font: font) > width {
                        lines.append(line)
                        line = ""
                    }
                    line.append(character)
                }
            }
            lines.append(line)
        }
        guard limit > 0, lines.count > limit else { return lines }
        var shown = Array(lines.prefix(limit))
        shown[limit - 1] = truncated(lines[limit - 1] + " " + lines[limit...].joined(separator: " "), font: font, width: width)
        return shown
    }

    /// `text` cut short with an ellipsis to fit `width`, if it does not.
    static func truncated(_ text: String, font: UIFont, width: CGFloat) -> String {
        guard self.width(text, font: font) > width else { return text }
        var kept = Substring(text)
        while !kept.isEmpty, self.width(kept.trimmingSuffixSpaces() + "…", font: font) > width { kept = kept.dropLast() }
        return kept.trimmingSuffixSpaces() + "…"
    }

    /// Draws one line of `text` in the current context with its top left
    /// at `point`, in `color`, or the context's fill color.
    static func draw(_ text: String, at point: CGPoint, font: UIFont, color: UIColor?) {
        guard let context = Graphics.current else { return }
        CG.saveGState(context)
        defer { CG.restoreGState(context) }
        font.drawingName.withCString { CG.selectFont(context, $0, font.state.pointSize, 1) }
        if let color { CG.setFillColorWithColor(context, color.state.makeCGColor()) }
        CG.setTextDrawingMode(context, 0)
        // Glyphs are drawn upright in UIKit's flipped coordinates.
        CG.setTextMatrix(context, CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0))
        CG.setTextPosition(context, point.x, point.y + font.state.pointSize * 0.95)
        var utf8 = Array(text.utf8)
        utf8.withUnsafeMutableBufferPointer { buffer in
            buffer.baseAddress!.withMemoryRebound(to: CChar.self, capacity: buffer.count) { CG.showText(context, $0, buffer.count) }
        }
    }
}

// MARK: - UILabel

final class LabelState: ObjectState {
    var text: String?
    var attributedText: NSObject?
    var font: UIFont?
    var textColor: UIColor?
    var highlightedTextColor: UIColor?
    /// NSTextAlignment: natural 4.
    var textAlignment = 4
    var numberOfLines = 1
    var lineBreakMode = 4
    var adjustsFontSizeToFitWidth = false
    var minimumScaleFactor: CGFloat = 0
    /// UIBaselineAdjustment: align baselines 0.
    var baselineAdjustment = 0
    var shadowColor: UIColor?
    var shadowOffset = CGSize(width: 0, height: -1)
    var allowsDefaultTighteningForTruncation = false
    var adjustsFontForContentSizeCategory = false
    var highlighted = false
    var enabled = true
    var preferredMaxLayoutWidth: CGFloat = 0
}

@ObjCClass("UILabel")
open class UILabel: UIView {
    static let labelStates = StateTable<LabelState>()
    var label: LabelState { UILabel.labelStates[objcObject] }

    @ObjCMethod("initWithFrame:")
    override func initialize(frame: CGRect) -> Self {
        _ = super.initialize(frame: frame)
        state.userInteractionEnabled = false
        state.contentMode = 7
        return self
    }

    @ObjCMethod("initWithCoder:")
    override func initialize(coder: NSObject) -> Self {
        _ = super.initialize(coder: coder)
        let decoded = Coder(coder: coder)
        let label = label
        label.text = decoded.string("UIText")
        if let attributed = decoded.object("UIAttributedText") {
            label.attributedText = attributed
            label.text = attributed.sendString() ?? label.text
        }
        label.font = decoded.object("UIFont")?.as(UIFont.self)
        label.textColor = decoded.object("UITextColor")?.as(UIColor.self)
        label.highlightedTextColor = decoded.object("UIHighlightedColor")?.as(UIColor.self)
        if decoded.has("UITextAlignment") { label.textAlignment = decoded.integer("UITextAlignment") }
        if decoded.has("UINumberOfLines") { label.numberOfLines = decoded.integer("UINumberOfLines") }
        if decoded.has("UILineBreakMode") { label.lineBreakMode = decoded.integer("UILineBreakMode") }
        if decoded.has("UIPreferredMaxLayoutWidth") { label.preferredMaxLayoutWidth = decoded.double("UIPreferredMaxLayoutWidth") }
        label.adjustsFontSizeToFitWidth = decoded.bool("UIAdjustsFontSizeToFit")
        return self
    }

    @ObjCMethod("dealloc")
    override func dealloc() {
        UILabel.labelStates.remove(objcObject)
        super.dealloc()
    }

    var font: UIFont { label.font ?? UIFont.systemFont(size: 17) }

    @ObjCMethod("text") func text() -> String? { label.text }

    @ObjCMethod("setText:")
    func setText(_ text: String?) {
        label.text = text
        setNeedsDisplay()
        superviewNeedsLayout()
    }

    @ObjCMethod("attributedText") func attributedText() -> NSObject? { label.attributedText }

    /// Its string becomes the text.
    @ObjCMethod("setAttributedText:")
    func setAttributedText(_ text: NSObject?) {
        label.attributedText = text
        setText(text?.sendString())
    }

    @ObjCMethod("font") func fontObject() -> UIFont { font }
    @ObjCMethod("setFont:") func setFont(_ font: UIFont?) { label.font = font; setNeedsDisplay(); superviewNeedsLayout() }
    @ObjCMethod("textColor") func textColor() -> UIColor { label.textColor ?? UIColor.label() }
    @ObjCMethod("setTextColor:") func setTextColor(_ color: UIColor?) { label.textColor = color; setNeedsDisplay() }
    @ObjCMethod("highlightedTextColor") func highlightedTextColor() -> UIColor? { label.highlightedTextColor }
    @ObjCMethod("setHighlightedTextColor:") func setHighlightedTextColor(_ color: UIColor?) { label.highlightedTextColor = color }
    @ObjCMethod("textAlignment") func textAlignment() -> Int { label.textAlignment }
    @ObjCMethod("setTextAlignment:") func setTextAlignment(_ alignment: Int) { label.textAlignment = alignment; setNeedsDisplay() }
    @ObjCMethod("numberOfLines") func numberOfLines() -> Int { label.numberOfLines }
    @ObjCMethod("setNumberOfLines:") func setNumberOfLines(_ lines: Int) { label.numberOfLines = lines; setNeedsDisplay(); superviewNeedsLayout() }
    @ObjCMethod("lineBreakMode") func lineBreakMode() -> Int { label.lineBreakMode }
    @ObjCMethod("setLineBreakMode:") func setLineBreakMode(_ mode: Int) { label.lineBreakMode = mode }
    @ObjCMethod("adjustsFontSizeToFitWidth") func adjustsFontSizeToFitWidth() -> Bool { label.adjustsFontSizeToFitWidth }
    @ObjCMethod("setAdjustsFontSizeToFitWidth:") func setAdjustsFontSizeToFitWidth(_ adjusts: Bool) { label.adjustsFontSizeToFitWidth = adjusts }
    @ObjCMethod("minimumScaleFactor") func minimumScaleFactor() -> CGFloat { label.minimumScaleFactor }
    @ObjCMethod("setMinimumScaleFactor:") func setMinimumScaleFactor(_ factor: CGFloat) { label.minimumScaleFactor = factor }
    /// iOS 6's minimum size, as a scale of the font's.
    @ObjCMethod("minimumFontSize")
    func minimumFontSize() -> CGFloat { label.minimumScaleFactor * (label.font?.state.pointSize ?? 17) }
    @ObjCMethod("setMinimumFontSize:")
    func setMinimumFontSize(_ size: CGFloat) { label.minimumScaleFactor = size / max(label.font?.state.pointSize ?? 17, 1) }
    @ObjCMethod("baselineAdjustment") func baselineAdjustment() -> Int { label.baselineAdjustment }
    @ObjCMethod("setBaselineAdjustment:") func setBaselineAdjustment(_ adjustment: Int) { label.baselineAdjustment = adjustment }
    /// The shadow is kept but not drawn.
    @ObjCMethod("shadowColor") func shadowColor() -> UIColor? { label.shadowColor }
    @ObjCMethod("setShadowColor:") func setShadowColor(_ color: UIColor?) { label.shadowColor = color }
    @ObjCMethod("shadowOffset") func shadowOffset() -> CGSize { label.shadowOffset }
    @ObjCMethod("setShadowOffset:") func setShadowOffset(_ offset: CGSize) { label.shadowOffset = offset }
    @ObjCMethod("allowsDefaultTighteningForTruncation")
    func allowsDefaultTighteningForTruncation() -> Bool { label.allowsDefaultTighteningForTruncation }
    @ObjCMethod("setAllowsDefaultTighteningForTruncation:")
    func setAllowsDefaultTighteningForTruncation(_ allows: Bool) { label.allowsDefaultTighteningForTruncation = allows }
    @ObjCMethod("adjustsFontForContentSizeCategory")
    func adjustsFontForContentSizeCategory() -> Bool { label.adjustsFontForContentSizeCategory }
    @ObjCMethod("setAdjustsFontForContentSizeCategory:")
    func setAdjustsFontForContentSizeCategory(_ adjusts: Bool) { label.adjustsFontForContentSizeCategory = adjusts }
    @ObjCMethod("isHighlighted") func isHighlighted() -> Bool { label.highlighted }
    @ObjCMethod("setHighlighted:") func setHighlighted(_ highlighted: Bool) { label.highlighted = highlighted }
    @ObjCMethod("isEnabled") func isEnabled() -> Bool { label.enabled }
    @ObjCMethod("setEnabled:") func setEnabled(_ enabled: Bool) { label.enabled = enabled }
    @ObjCMethod("preferredMaxLayoutWidth") func preferredMaxLayoutWidth() -> CGFloat { label.preferredMaxLayoutWidth }
    @ObjCMethod("setPreferredMaxLayoutWidth:") func setPreferredMaxLayoutWidth(_ width: CGFloat) { label.preferredMaxLayoutWidth = width }

    /// The lines the text takes at `width`: one, shortened with an
    /// ellipsis in the truncating line break modes, unless the label has
    /// more lines.
    func lines(width: CGFloat) -> [String] {
        guard let text = label.text, !text.isEmpty else { return [] }
        if label.numberOfLines == 1 {
            let line = text.replacingNewlines()
            return [(3...5).contains(label.lineBreakMode) ? Text.truncated(line, font: font, width: width) : line]
        }
        return Text.lines(text, font: font, width: width, limit: label.numberOfLines)
    }

    /// The text's size: on one line, or wrapped at the width given (else
    /// the preferred maximum width) when the label has more lines.
    @ObjCMethod("sizeThatFits:")
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        guard let text = label.text, !text.isEmpty else { return .zero }
        guard label.numberOfLines != 1 else { return Text.size(text.replacingNewlines(), font: font) }
        let width = size.width > 0 ? size.width : label.preferredMaxLayoutWidth > 0 ? label.preferredMaxLayoutWidth : .greatestFiniteMagnitude
        let lines = lines(width: width)
        let widest = lines.map { Text.width($0, font: font).rounded(.up) }.max() ?? 0
        return CGSize(width: min(widest, width), height: CGFloat(lines.count) * Text.lineHeight(font))
    }

    @ObjCMethod("intrinsicContentSize") func intrinsicContentSize() -> CGSize { sizeThatFits(.zero) }

    @ObjCMethod("drawRect:")
    override func draw(_ rect: CGRect) { sendDrawText(in: state.bounds) }

    /// The lines centered vertically as a block, each placed by the alignment.
    @ObjCMethod("drawTextInRect:")
    func drawText(in rect: CGRect) {
        let lines = lines(width: rect.width)
        guard !lines.isEmpty else { return }
        let lineHeight = Text.lineHeight(font)
        // As many whole lines as fit, when the label is too short for all.
        let shown = label.numberOfLines == 1 ? lines : Array(lines.prefix(max(1, Int((rect.height + 0.5) / lineHeight))))
        var y = rect.midY - CGFloat(shown.count) * lineHeight / 2
        let color = label.highlighted ? (label.highlightedTextColor ?? textColor()) : textColor()
        for line in shown {
            let width = Text.width(line, font: font).rounded(.up)
            let x: CGFloat
            switch label.textAlignment {
            case 1: x = rect.midX - width / 2
            case 2: x = rect.maxX - width
            default: x = rect.minX
            }
            Text.draw(line, at: CGPoint(x: x, y: y), font: font, color: color)
            y += lineHeight
        }
    }
}

extension NSObject {
    @ObjCMethod("string") func sendString() -> String?
    @ObjCMethod("drawTextInRect:") func sendDrawText(in rect: CGRect)
}

// MARK: - UIImageView

final class ImageViewState: ObjectState {
    var image: UIImage?
    var highlightedImage: UIImage?
    var highlighted = false
}

@ObjCClass("UIImageView")
open class UIImageView: UIView {
    static let imageStates = StateTable<ImageViewState>()
    var imageState: ImageViewState { UIImageView.imageStates[objcObject] }

    @ObjCMethod("initWithFrame:")
    override func initialize(frame: CGRect) -> Self {
        _ = super.initialize(frame: frame)
        state.userInteractionEnabled = false
        return self
    }

    /// The image's size.
    @ObjCMethod("initWithImage:")
    func initialize(image: UIImage?) -> NSObject {
        let view = initializeView(frame: CGRect(origin: .zero, size: image?.state.size ?? .zero)).unsafeCast(to: UIImageView.self)
        view.setImage(image)
        return view
    }

    @ObjCMethod("initWithCoder:")
    override func initialize(coder: NSObject) -> Self {
        _ = super.initialize(coder: coder)
        let decoded = Coder(coder: coder)
        imageState.highlightedImage = decoded.object("UIHighlightedImage")?.as(UIImage.self)
        setImage(decoded.object("UIImage")?.as(UIImage.self))
        return self
    }

    @ObjCMethod("dealloc")
    override func dealloc() {
        UIImageView.imageStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCMethod("image") func image() -> UIImage? { imageState.image }

    @ObjCMethod("setImage:")
    func setImage(_ image: UIImage?) {
        imageState.image = image
        showImage()
    }

    @ObjCMethod("highlightedImage") func highlightedImage() -> UIImage? { imageState.highlightedImage }
    @ObjCMethod("setHighlightedImage:") func setHighlightedImage(_ image: UIImage?) { imageState.highlightedImage = image }
    @ObjCMethod("isHighlighted") func isHighlighted() -> Bool { imageState.highlighted }
    @ObjCMethod("setHighlighted:") func setHighlighted(_ highlighted: Bool) {
        imageState.highlighted = highlighted
        showImage()
    }

    @ObjCMethod("setContentMode:")
    override func setContentMode(_ mode: Int) {
        state.contentMode = mode
        showImage()
    }

    @ObjCMethod("sizeThatFits:")
    override func sizeThatFits(_ size: CGSize) -> CGSize { imageState.image?.state.size ?? .zero }

    @ObjCMethod("intrinsicContentSize") func intrinsicContentSize() -> CGSize { imageState.image?.state.size ?? CGSize(width: -1, height: -1) }

    /// The layer shows the image, placed by the content mode.
    private func showImage() {
        let image = imageState.highlighted ? (imageState.highlightedImage ?? imageState.image) : imageState.image
        let geometry = state.geometry!
        geometry.contents = image.flatMap { $0.state.cgImage.map { NSObject($0) } }
        geometry.contentsScale = image?.state.scale ?? 1
        let gravities = ["resize", "resizeAspect", "resizeAspectFill", "resize", "center", "top", "bottom", "left", "right",
                         "topLeft", "topRight", "bottomLeft", "bottomRight"]
        geometry.contentsGravity = gravities.indices.contains(state.contentMode) ? gravities[state.contentMode] : "resize"
    }
}

extension StringProtocol {
    func trimmingSuffixSpaces() -> String {
        var text = String(self)
        while text.last == " " { text.removeLast() }
        return text
    }

    func replacingNewlines() -> String { split(separator: "\n", omittingEmptySubsequences: false).joined(separator: " ") }
}

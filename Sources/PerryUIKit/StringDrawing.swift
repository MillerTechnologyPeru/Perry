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

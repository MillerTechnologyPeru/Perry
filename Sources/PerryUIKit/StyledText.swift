import CPerryGeometry
import PerryObjCInterop

// Attributed text in more than one style, laid out and drawn run by run:
// each run in its font and color, struck through or underlined, on lines
// broken between words whose height and baseline fit the tallest font on
// them. Inline presentation intents, which Markdown gives text, are drawn
// as UIKit draws them: strongly emphasized text bold, emphasized text
// italic, code monospaced, and strikethrough struck through.

/// NSInlinePresentationIntent.
private enum InlineIntent {
    static let emphasized: UInt32 = 1 << 0
    static let stronglyEmphasized: UInt32 = 1 << 1
    static let code: UInt32 = 1 << 2
    static let strikethrough: UInt32 = 1 << 5
}

/// A run of text in one style.
struct StyledRun {
    var text: String
    var font: UIFont
    var color: UIColor
    var strikethrough: Bool
    var underline: Bool
    var strikethroughColor: UIColor?
    var underlineColor: UIColor?

    /// Drawn the same as `other`, whatever their text.
    func looksLike(_ other: StyledRun) -> Bool {
        font.isEqual(other.font) && color.isEqual(other.color) && strikethrough == other.strikethrough
            && underline == other.underline
    }

    var hasDecoration: Bool { strikethrough || underline }
}

extension NSAttributedString {
    /// The string's runs, in their drawing styles.
    var styledRuns: [StyledRun] {
        let text = string()
        let units = Array(text.utf16)
        var runs: [StyledRun] = []
        var index: UInt = 0
        while index < length() {
            var range = PerryRange(location: 0, length: 0)
            let attributes = withUnsafeMutablePointer(to: &range) { self.attributes(at: index, effectiveRange: UnsafeMutableRawPointer($0)) }
            let end = min(Int(range.location + range.length), units.count)
            guard end > Int(index) else { break }
            let piece = String(decoding: units[Int(index)..<end], as: UTF16.self)
            runs.append(StyledRun(piece, attributes: attributes))
            index = UInt(end)
        }
        return runs
    }
}

extension StyledRun {
    init(_ text: String, attributes: NSDictionary?) {
        var font = attributes?.object(forKey: "NSFont")?.as(UIFont.self) ?? UIFont.systemFont(size: 12)
        let color = attributes?.object(forKey: "NSColor")?.as(UIColor.self) ?? UIColor.black()
        let number = { (key: String) in attributes?.object(forKey: key)?.as(NSNumber.self)?.doubleValue() ?? 0 }
        let intent = UInt32(truncatingIfNeeded: Int(number("NSInlinePresentationIntent")))
        if intent & (InlineIntent.emphasized | InlineIntent.stronglyEmphasized | InlineIntent.code) != 0 {
            var traits = font.state.traits
            var weight = font.state.weight
            if intent & InlineIntent.emphasized != 0 { traits |= italicTrait }
            if intent & InlineIntent.stronglyEmphasized != 0 {
                traits |= boldTrait
                weight = Swift.max(weight, 0.4)
            }
            var name = font.state.name
            if intent & InlineIntent.code != 0 {
                traits |= monoSpaceTrait
                if !name.hasPrefix(".") { name = "Courier" }
            }
            font = UIFont.make(name: name, size: font.state.pointSize, weight: weight, traits: traits, design: font.state.design)
        }
        self.init(text: text, font: font, color: color,
                  strikethrough: number("NSStrikethrough") != 0 || intent & InlineIntent.strikethrough != 0,
                  underline: number("NSUnderline") != 0,
                  strikethroughColor: attributes?.object(forKey: "NSStrikethroughColor")?.as(UIColor.self),
                  underlineColor: attributes?.object(forKey: "NSUnderlineColor")?.as(UIColor.self))
    }
}

/// Styled runs on lines: as many as the height and line limit allow, the
/// last ending in an ellipsis when text is left out.
struct StyledLayout {
    struct Line {
        var pieces: [StyledRun] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
        var ascent: CGFloat = 0
    }

    var lines: [Line]
    var size: CGSize
    var truncated: Bool

    /// Whether `runs` need this layout: whether they are drawn in more than
    /// one style or decorated.
    static func needed(_ runs: [StyledRun]) -> Bool {
        guard let first = runs.first else { return false }
        return runs.contains { !$0.looksLike(first) || $0.hasDecoration }
    }

    init(_ runs: [StyledRun], width: CGFloat, height: CGFloat, lineLimit: Int) {
        let maxWidth = width > 0 && width < .greatestFiniteMagnitude ? width : .greatestFiniteMagnitude
        // Words, the spaces between them and line breaks, each in its run's style.
        var all: [Line] = [Line()]
        func place(_ piece: StyledRun) {
            let pieceWidth = Text.width(piece.text, font: piece.font)
            all[all.count - 1].pieces.append(piece)
            all[all.count - 1].width += pieceWidth
        }
        for run in runs {
            for (paragraphIndex, paragraph) in run.text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                if paragraphIndex > 0 {
                    if all[all.count - 1].pieces.isEmpty { all[all.count - 1].pieces.append(StyledRun(run, text: "")) }
                    all.append(Line())
                }
                for (wordIndex, word) in paragraph.split(separator: " ", omittingEmptySubsequences: false).enumerated() {
                    // Spaces between words; those at the end of a line are
                    // dropped when it breaks.
                    if wordIndex > 0, !all[all.count - 1].pieces.isEmpty { place(StyledRun(run, text: " ")) }
                    guard !word.isEmpty else { continue }
                    let piece = StyledRun(run, text: String(word))
                    let wordWidth = Text.width(piece.text, font: run.font)
                    if all[all.count - 1].width + wordWidth > maxWidth, !all[all.count - 1].pieces.isEmpty {
                        Self.trimTrailingSpaces(&all[all.count - 1])
                        all.append(Line())
                    }
                    if wordWidth <= maxWidth {
                        place(piece)
                    } else {
                        // A word wider than the line is broken between characters.
                        var chunk = ""
                        for character in word {
                            let candidate = chunk + String(character)
                            if !chunk.isEmpty, all[all.count - 1].width + Text.width(candidate, font: run.font) > maxWidth {
                                place(StyledRun(run, text: chunk))
                                all.append(Line())
                                chunk = String(character)
                            } else {
                                chunk = candidate
                            }
                        }
                        if !chunk.isEmpty { place(StyledRun(run, text: chunk)) }
                    }
                }
            }
        }
        for index in all.indices {
            if all[index].pieces.isEmpty, let last = runs.last { all[index].pieces = [StyledRun(last, text: "")] }
            Self.measure(&all[index])
        }

        var limit = lineLimit
        if height > 0, height < .greatestFiniteMagnitude {
            var used: CGFloat = 0, fitting = 0
            for line in all where used + line.height <= height || fitting == 0 {
                used += line.height
                fitting += 1
            }
            limit = limit > 0 ? Swift.min(limit, fitting) : fitting
        }
        var lines = limit > 0 ? Array(all.prefix(limit)) : all
        let truncated = lines.count < all.count
        if truncated, let last = lines.indices.last {
            Self.truncate(&lines[last], width: maxWidth)
        } else if let last = lines.indices.last, maxWidth < .greatestFiniteMagnitude, lines[last].width > maxWidth {
            Self.truncate(&lines[last], width: maxWidth)
        }
        self.lines = lines
        self.truncated = truncated
        let measured = lines.map(\.width).max() ?? 0
        size = CGSize(width: Swift.min(measured, maxWidth).rounded(.up), height: lines.reduce(0) { $0 + $1.height })
    }

    static func trimTrailingSpaces(_ line: inout Line) {
        while let last = line.pieces.last, last.text == " " {
            line.pieces.removeLast()
            line.width -= Text.width(" ", font: last.font)
        }
    }

    /// The line's width, and its height and ascent: its tallest font's.
    static func measure(_ line: inout Line) {
        trimTrailingSpaces(&line)
        line.width = line.pieces.reduce(0) { $0 + Text.width($1.text, font: $1.font) }
        line.height = line.pieces.map { Text.lineHeight($0.font) }.max() ?? 0
        line.ascent = line.pieces.map { $0.font.ascender() }.max() ?? 0
    }

    /// Ends the line in an ellipsis within `width`, dropping what does not
    /// fit before it.
    static func truncate(_ line: inout Line, width: CGFloat) {
        guard let style = line.pieces.last else { return }
        let ellipsis = StyledRun(style, text: "…")
        let ellipsisWidth = Text.width("…", font: style.font)
        while let last = line.pieces.last, line.width + ellipsisWidth > width {
            line.pieces.removeLast()
            line.width -= Text.width(last.text, font: last.font)
            if last.text.count > 1 {
                var shorter = last
                shorter.text = String(last.text.dropLast())
                line.pieces.append(shorter)
                line.width += Text.width(shorter.text, font: shorter.font)
            }
            if line.pieces.isEmpty { break }
        }
        trimTrailingSpaces(&line)
        line.pieces.append(ellipsis)
        measure(&line)
    }

    var firstBaseline: CGFloat { lines.first?.ascent ?? 0 }

    var lastBaseline: CGFloat {
        guard let last = lines.last else { return 0 }
        return lines.dropLast().reduce(0) { $0 + $1.height } + last.ascent
    }

    /// Draws the lines from the top of `rect`, aligned in its width:
    /// NSTextAlignment left 0, center 1, right 2.
    func draw(in rect: CGRect, alignment: Int) {
        var top = rect.minY
        for line in lines {
            var x = alignment == 1 ? rect.minX + (rect.width - line.width) / 2 : alignment == 2 ? rect.maxX - line.width : rect.minX
            let baseline = top + line.ascent
            for piece in line.pieces where !piece.text.isEmpty {
                let width = Text.width(piece.text, font: piece.font)
                Text.draw(piece.text, at: CGPoint(x: x, y: baseline - piece.font.ascender()), font: piece.font, color: piece.color)
                let thickness = Swift.max(1, (piece.font.state.pointSize / 14).rounded())
                if piece.strikethrough {
                    Self.rule(x: x, y: baseline - piece.font.xHeight() / 2, width: width, thickness: thickness,
                              color: piece.strikethroughColor ?? piece.color)
                }
                if piece.underline {
                    Self.rule(x: x, y: baseline + piece.font.state.pointSize * 0.1, width: width, thickness: thickness,
                              color: piece.underlineColor ?? piece.color)
                }
                x += width
            }
            top += line.height
        }
    }

    private static func rule(x: CGFloat, y: CGFloat, width: CGFloat, thickness: CGFloat, color: UIColor) {
        guard let context = Graphics.current else { return }
        CG.saveGState(context)
        defer { CG.restoreGState(context) }
        CG.setFillColorWithColor(context, color.state.makeCGColor())
        CG.fillRect(context, CGRect(x: x, y: y - thickness / 2, width: width, height: thickness))
    }
}

private extension StyledRun {
    /// The run's style with other text.
    init(_ style: StyledRun, text: String) {
        self = style
        self.text = text
    }
}

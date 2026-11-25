import CPerryGeometry
import PerryObjCInterop

// Core Text's glyph runs, typesetters, truncated lines, glyph infos and font
// descriptors, for Mac apps that lay text out and draw glyphs themselves. A
// run has a glyph for each character of its text, a surrogate pair's at its
// first unit, from its font's character map, advanced by the font's own
// advance, so that CTFontDrawGlyphs puts the glyphs where they were
// measured. There is no shaping, font fallback or bidirectional reordering:
// a run is left to right, in string order, in its own font. A tab advances
// to its paragraph style's next tab stop, or to the next of Core Text's
// default stops every 28 points; line ends and other controls take no room.

/// The CFTypeIDs Perry gives Core Text's types, as UIKit's Core Text does.
enum CoreTextTypeIDs {
    static let fontDescriptor: UInt = 0x50_02
    static let glyphInfo: UInt = 0x50_03
    static let run: UInt = 0x50_07
    static let typesetter: UInt = 0x50_09
}

// MARK: - Glyph layout

enum GlyphLayout {
    /// A run's glyphs: each one's position from its line's origin, its
    /// advance, and the characters it stands for, from `indices` up to
    /// `ends`, by UTF-16 index in the string.
    struct Glyphs {
        var glyphs: [UInt16] = []
        var positions: [CGPoint] = []
        var advances: [CGSize] = []
        var indices: [Int] = []
        var ends: [Int] = []
        var width: CGFloat = 0
    }

    static func isLineEnd(_ unit: UInt16) -> Bool { unit == 0x0A || unit == 0x0D || unit == 0x85 || unit == 0x2028 || unit == 0x2029 }
    static func isSpace(_ unit: UInt16) -> Bool { unit == 0x20 || unit == 0x09 || unit == 0x3000 }
    /// Ideographs, kana and Hangul, which a line may break before and after.
    static func breaksAnywhere(_ unit: UInt16) -> Bool {
        (0x2E80...0x9FFF).contains(unit) || (0xAC00...0xD7A3).contains(unit) || (0xF900...0xFAFF).contains(unit) || (0xFF00...0xFFEF).contains(unit)
    }

    /// The tab stop after `x`: the paragraph style's next one, else the
    /// next multiple of its default tab interval, 28 points if it has none.
    static func tabStop(after x: CGFloat, _ attributes: NSDictionary?) -> CGFloat {
        let style = attributes?.object(forKey: "NSParagraphStyle")?.as(NSParagraphStyle.self)
        if let stops = style?.tabStops?.as(NSArray.self),
           let next = stops.elements.compactMap({ $0.as(NSTextTab.self)?.location }).filter({ $0 > x }).min() {
            return next
        }
        let interval = style.map { $0.defaultTabInterval > 0 ? $0.defaultTabInterval : 28 } ?? 28
        return ((x / interval).rounded(.down) + 1) * interval
    }

    /// Lays a run out from `x` on its line.
    static func lay(_ run: CTLine.Run, from x: CGFloat) -> Glyphs {
        var laid = Glyphs()
        let units = Array(run.text.utf16)
        guard !units.isEmpty else { return laid }
        let font = run.font.objcObject
        var mapped = [UInt16](repeating: 0, count: units.count)
        _ = CTFontGetGlyphsForCharacters(font, units, &mapped, units.count)
        // A glyph for each character, where it starts.
        var starts: [Int] = []
        var index = 0
        while index < units.count {
            starts.append(index)
            let pair = (0xD800..<0xDC00).contains(units[index]) && index + 1 < units.count && (0xDC00..<0xE000).contains(units[index + 1])
            index += pair ? 2 : 1
        }
        var glyphs = starts.map { mapped[$0] }
        // A glyph info (kCTGlyphInfoAttributeName) for the run's text is its
        // one glyph.
        if !run.isToken, let info = run.attributes?.object(forKey: "NSGlyphInfo")?.as(CTGlyphInfo.self), info.glyph != 0,
           info.baseString == run.text {
            starts = [0]
            glyphs = [info.glyph]
        }
        // Tabs and line ends show the font's space, which draws nothing.
        var space: UInt16 = 0
        var spaceCharacter: UInt16 = 0x20
        _ = CTFontGetGlyphsForCharacters(font, &spaceCharacter, &space, 1)
        var advances = [CGSize](repeating: .zero, count: glyphs.count)
        let measured = CoreText.face(run.font) != nil && CTFontGetAdvancesForGlyphs(font, 0, glyphs, &advances, glyphs.count) > 0
        var pen = x
        for (n, start) in starts.enumerated() {
            let end = n + 1 < starts.count ? starts[n + 1] : units.count
            let unit = units[start]
            var glyph = glyphs[n]
            let advance: CGFloat
            if unit == 0x09 {
                glyph = space
                advance = tabStop(after: pen, run.attributes) - pen
            } else if unit < 0x20 || unit == 0x7F || isLineEnd(unit) {
                glyph = space
                advance = 0
            } else if measured {
                advance = advances[n].width
            } else {
                // Without the font's face, the width its text is drawn in.
                advance = Text.width(String(decoding: units[start..<end], as: UTF16.self), font: run.font)
            }
            laid.glyphs.append(glyph)
            laid.positions.append(CGPoint(x: pen, y: 0))
            laid.advances.append(CGSize(width: advance, height: 0))
            // A truncation token's glyphs all stand for what it replaced.
            laid.indices.append(run.isToken ? run.location : run.location + start)
            laid.ends.append(run.isToken ? run.location + run.length : run.location + end)
            pen += advance
        }
        laid.width = pen - x
        return laid
    }

    /// Lays a line's runs out one after another from its origin.
    static func lay(_ runs: [CTLine.Run]) -> [Glyphs] {
        var x: CGFloat = 0
        return runs.map { run in
            let laid = lay(run, from: x)
            x += laid.width
            return laid
        }
    }

    static func width(_ runs: [CTLine.Run]) -> CGFloat { lay(runs).reduce(0) { $0 + $1.width } }

    /// How many characters from `start` make a line within `width`: up to
    /// the last space, hyphen or ideograph that fits, or with `clusters` the
    /// last character that does, or through a line end. Spaces past the
    /// width stay on the line, and a line has at least one character.
    static func lineBreak(_ runs: [CTLine.Run], units: [UInt16], from start: Int, width: Double, clusters: Bool) -> Int {
        guard start >= 0, start < units.count else { return 0 }
        var pen: CGFloat = 0
        var fitted = start
        var opportunity: Int?
        for run in runs where run.location + run.length > start {
            let part = run.location < start ? CTLine.slice([run], start..<(run.location + run.length)).first ?? run : run
            let laid = lay(part, from: pen)
            for n in laid.glyphs.indices {
                let first = laid.indices[n], end = laid.ends[n]
                let unit = units[first]
                if isLineEnd(unit) {
                    // A carriage return and line feed end the line as one.
                    return (unit == 0x0D && end < units.count && units[end] == 0x0A ? end + 1 : end) - start
                }
                if isSpace(unit) {
                    fitted = end
                    if !clusters { opportunity = end }
                    continue
                }
                if !clusters, breaksAnywhere(unit), first > start { opportunity = first }
                if laid.positions[n].x + laid.advances[n].width > CGFloat(width) + 0.001 {
                    if let opportunity, opportunity > start { return opportunity - start }
                    return (fitted > start ? fitted : end) - start
                }
                fitted = end
                if !clusters, unit == 0x2D || breaksAnywhere(unit) { opportunity = end }
            }
            pen += laid.width
        }
        return units.count - start
    }

    /// The width of the spaces and line ends a line ends with.
    static func trailingWhitespace(_ line: CTLine) -> CGFloat {
        var width: CGFloat = 0
        for (run, laid) in zip(line.runs, lay(line.runs)).reversed() {
            guard !run.isToken else { return width }
            let units = Array(run.text.utf16)
            for n in laid.glyphs.indices.reversed() {
                let unit = units[laid.indices[n] - run.location]
                guard isSpace(unit) || isLineEnd(unit) else { return width }
                width += laid.advances[n].width
            }
        }
        return width
    }

    /// A line within `width`: the line if it fits, else its characters
    /// that do with the token's runs for those left out, at the start
    /// (kCTLineTruncationStart 0), the end (1) or the middle (2), where the
    /// characters on each side have half the room. Nil if the token itself
    /// doesn't fit.
    static func truncate(_ line: CTLine, width: Double, type: UInt32, token: CTLine?) -> CTLine? {
        let laid = lay(line.runs)
        let total = laid.reduce(0) { $0 + $1.width }
        guard total > CGFloat(width) else { return CTLine.make(runs: line.runs, range: line.range) }
        let tokenRuns = token?.runs ?? []
        let tokenWidth = GlyphLayout.width(tokenRuns)
        guard tokenWidth <= CGFloat(width) else { return nil }
        // The glyphs, by the characters they stand for and where they lie.
        var glyphs: [(first: Int, end: Int, left: CGFloat, right: CGFloat)] = []
        for (run, runGlyphs) in zip(line.runs, laid) where !run.isToken {
            for n in runGlyphs.glyphs.indices {
                let left = runGlyphs.positions[n].x
                glyphs.append((runGlyphs.indices[n], runGlyphs.ends[n], left, left + runGlyphs.advances[n].width))
            }
        }
        guard let start = glyphs.first?.first, let end = glyphs.last?.end else { return CTLine.make(runs: line.runs, range: line.range) }
        let room = CGFloat(width) - tokenWidth
        /// Where the characters from the start that fit in `space` end.
        func head(_ space: CGFloat) -> Int {
            var cut = start
            for glyph in glyphs {
                guard glyph.right <= space + 0.001 else { break }
                cut = glyph.end
            }
            return cut
        }
        /// Where the characters to the end that fit in `space` start.
        func tail(_ space: CGFloat) -> Int {
            var cut = end
            for glyph in glyphs.reversed() {
                guard total - glyph.left <= space + 0.001 else { break }
                cut = glyph.first
            }
            return cut
        }
        func replacing(_ range: Range<Int>) -> [CTLine.Run] {
            tokenRuns.map { tokenRun in
                var run = tokenRun
                (run.isToken, run.location, run.length) = (true, range.lowerBound, range.count)
                return run
            }
        }
        let runs: [CTLine.Run]
        switch type {
        case 0:
            let cut = tail(room)
            runs = replacing(start..<cut) + CTLine.slice(line.runs, cut..<end)
        case 2:
            let first = head(room / 2), last = max(tail(room / 2), first)
            runs = CTLine.slice(line.runs, start..<first) + replacing(first..<last) + CTLine.slice(line.runs, last..<end)
        default:
            let cut = head(room)
            runs = CTLine.slice(line.runs, start..<cut) + replacing(cut..<end)
        }
        return CTLine.make(runs: runs, range: line.range)
    }
}

// MARK: - Lines

/// The line's runs, in order, which live as long as the line.
@c(_CTLineGetGlyphRuns)
public func CTLineGetGlyphRuns(_ line: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let line = CTLine.line(line) else { return nil }
    if let runs = line.glyphRuns { return runs.objcObject }
    let laid = GlyphLayout.lay(line.runs)
    let runs = NSMutableArray.of(zip(line.runs, laid).filter { !$0.1.glyphs.isEmpty }.map { CTRun.make($0.0, $0.1) })
    line.glyphRuns = runs
    return runs.objcObject
}

@c(_CTLineGetGlyphCount)
public func CTLineGetGlyphCount(_ line: UnsafeMutableRawPointer?) -> Int {
    guard let line = CTLine.line(line) else { return 0 }
    return GlyphLayout.lay(line.runs).reduce(0) { $0 + $1.glyphs.count }
}

/// The characters of its string the line was made from; a truncated
/// line's are its original's.
@c(_CTLineGetStringRange)
public func CTLineGetStringRange(_ line: UnsafeMutableRawPointer?) -> PerryCFRange {
    guard let line = CTLine.line(line) else { return PerryCFRange(location: 0, length: 0) }
    return PerryCFRange(location: line.range.lowerBound, length: line.range.count)
}

@DarwinC("_CTLineGetTrailingWhitespaceWidth")
public func CTLineGetTrailingWhitespaceWidth(_ line: UnsafeMutableRawPointer?) -> Double {
    CTLine.line(line).map { Double(GlyphLayout.trailingWhitespace($0)) } ?? 0
}

/// How far to move the pen for the line, without its trailing whitespace,
/// to be flush in `flushWidth`: a factor of 0 or less is left, 0.5 centered,
/// 1 or more right. Negative for a line wider than the width, as on Darwin.
@DarwinC("_CTLineGetPenOffsetForFlush")
public func CTLineGetPenOffsetForFlush(_ line: UnsafeMutableRawPointer?, _ flushFactor: CGFloat, _ flushWidth: Double) -> Double {
    guard let line = CTLine.line(line) else { return 0 }
    let used = Double(line.bounds.width - GlyphLayout.trailingWhitespace(line))
    return (flushWidth - used) * Double(min(max(flushFactor, 0), 1))
}

/// A new line that fits `width`: a copy of the line if it does, else with
/// the token for the characters left out (none for a NULL token). NULL if
/// the token is wider than `width`.
@DarwinC("_CTLineCreateTruncatedLine")
public func CTLineCreateTruncatedLine(_ line: UnsafeMutableRawPointer?, _ width: Double, _ truncationType: UInt32,
                                      _ truncationToken: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let line = CTLine.line(line) else { return nil }
    return GlyphLayout.truncate(line, width: width, type: truncationType, token: CTLine.line(truncationToken))?.objCOwnedReturnValue()
}

// MARK: - Runs

/// A glyph run: its glyphs, their positions from the line's origin, their
/// advances and string indices, kept in buffers of its own that the
/// …Ptr functions point into, and the attributes of its characters, which
/// always include the font, as Darwin's do.
@ObjCClass("PerryCTRun")
final class CTRun: NSObject {
    var font: NSFont?
    var cgColor: NSObject?
    var color: NSColor?
    var attributes: NSDictionary?
    var range: Range<Int> = 0..<0
    var glyphs = UnsafeMutableBufferPointer<UInt16>(start: nil, count: 0)
    var positions = UnsafeMutableBufferPointer<CGPoint>(start: nil, count: 0)
    var advances = UnsafeMutableBufferPointer<CGSize>(start: nil, count: 0)
    var indices = UnsafeMutableBufferPointer<Int>(start: nil, count: 0)

    @ObjCMethod("init")
    public required override init() { super.init() }

    deinit {
        glyphs.deallocate()
        positions.deallocate()
        advances.deallocate()
        indices.deallocate()
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { CoreTextTypeIDs.run }

    private static func buffer<Element>(_ values: [Element]) -> UnsafeMutableBufferPointer<Element> {
        let buffer = UnsafeMutableBufferPointer<Element>.allocate(capacity: values.count)
        _ = buffer.initialize(fromContentsOf: values)
        return buffer
    }

    static func make(_ run: CTLine.Run, _ laid: GlyphLayout.Glyphs) -> CTRun {
        let made = CTRun()
        made.font = run.font
        (made.cgColor, made.color) = (run.cgColor, run.color)
        if let attributes = run.attributes, attributes.object(forKey: "NSFont") != nil {
            made.attributes = attributes
        } else {
            let attributes = NSMutableDictionary.empty()
            if let own = run.attributes { Send.void(attributes.objcObject, "addEntriesFromDictionary:", own.objcObject) }
            attributes.set(run.font, forKey: "NSFont")
            made.attributes = attributes
        }
        made.range = run.location..<(run.location + run.length)
        made.glyphs = buffer(laid.glyphs)
        made.positions = buffer(laid.positions)
        made.advances = buffer(laid.advances)
        made.indices = buffer(laid.indices)
        return made
    }

    static func run(_ object: UnsafeMutableRawPointer?) -> CTRun? {
        object.flatMap { NSObject(objCArgument: $0).as(CTRun.self) }
    }

    /// The glyphs a CFRange names; a length of 0 is to the run's end.
    func part(_ range: PerryCFRange) -> Range<Int> {
        let first = min(max(range.location, 0), glyphs.count)
        return first..<(range.length > 0 ? min(first + range.length, glyphs.count) : glyphs.count)
    }

    /// Copies the values of the glyphs a CFRange names to `buffer`.
    func copyValues<Element>(_ values: UnsafeMutableBufferPointer<Element>, _ range: PerryCFRange, to buffer: UnsafeMutablePointer<Element>?) {
        let wanted = part(range)
        guard let buffer, let base = values.baseAddress, !wanted.isEmpty else { return }
        buffer.update(from: base + wanted.lowerBound, count: wanted.count)
    }
}

@c(_CTRunGetTypeID) public func CTRunGetTypeID() -> UInt { CoreTextTypeIDs.run }

@c(_CTRunGetGlyphCount)
public func CTRunGetGlyphCount(_ run: UnsafeMutableRawPointer?) -> Int { CTRun.run(run)?.glyphs.count ?? 0 }

@c(_CTRunGetAttributes)
public func CTRunGetAttributes(_ run: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { CTRun.run(run)?.attributes?.objcObject }

/// kCTRunStatusNoStatus: left to right, in string order, through the
/// context's own text matrix.
@c(_CTRunGetStatus) public func CTRunGetStatus(_ run: UnsafeMutableRawPointer?) -> UInt32 { 0 }

@c(_CTRunGetStringRange)
public func CTRunGetStringRange(_ run: UnsafeMutableRawPointer?) -> PerryCFRange {
    guard let run = CTRun.run(run) else { return PerryCFRange(location: 0, length: 0) }
    return PerryCFRange(location: run.range.lowerBound, length: run.range.count)
}

@c(_CTRunGetGlyphsPtr)
public func CTRunGetGlyphsPtr(_ run: UnsafeMutableRawPointer?) -> UnsafeRawPointer? { CTRun.run(run)?.glyphs.baseAddress.map { UnsafeRawPointer($0) } }

@c(_CTRunGetGlyphs)
public func CTRunGetGlyphs(_ run: UnsafeMutableRawPointer?, _ range: PerryCFRange, _ buffer: UnsafeMutablePointer<UInt16>?) {
    guard let run = CTRun.run(run) else { return }
    run.copyValues(run.glyphs, range, to: buffer)
}

@c(_CTRunGetPositionsPtr)
public func CTRunGetPositionsPtr(_ run: UnsafeMutableRawPointer?) -> UnsafeRawPointer? { CTRun.run(run)?.positions.baseAddress.map { UnsafeRawPointer($0) } }

/// Each glyph's origin, from the line's origin, on the baseline.
@c(_CTRunGetPositions)
public func CTRunGetPositions(_ run: UnsafeMutableRawPointer?, _ range: PerryCFRange, _ buffer: UnsafeMutablePointer<CGPoint>?) {
    guard let run = CTRun.run(run) else { return }
    run.copyValues(run.positions, range, to: buffer)
}

@c(_CTRunGetAdvancesPtr)
public func CTRunGetAdvancesPtr(_ run: UnsafeMutableRawPointer?) -> UnsafeRawPointer? { CTRun.run(run)?.advances.baseAddress.map { UnsafeRawPointer($0) } }

@c(_CTRunGetAdvances)
public func CTRunGetAdvances(_ run: UnsafeMutableRawPointer?, _ range: PerryCFRange, _ buffer: UnsafeMutablePointer<CGSize>?) {
    guard let run = CTRun.run(run) else { return }
    run.copyValues(run.advances, range, to: buffer)
}

@c(_CTRunGetStringIndicesPtr)
public func CTRunGetStringIndicesPtr(_ run: UnsafeMutableRawPointer?) -> UnsafeRawPointer? {
    CTRun.run(run)?.indices.baseAddress.map { UnsafeRawPointer($0) }
}

/// Each glyph's first character, by its UTF-16 index in the string.
@c(_CTRunGetStringIndices)
public func CTRunGetStringIndices(_ run: UnsafeMutableRawPointer?, _ range: PerryCFRange, _ buffer: UnsafeMutablePointer<Int>?) {
    guard let run = CTRun.run(run) else { return }
    run.copyValues(run.indices, range, to: buffer)
}

/// The glyphs' width, and the run's font's ascent, descent and leading.
@DarwinC("_CTRunGetTypographicBounds")
public func CTRunGetTypographicBounds(_ run: UnsafeMutableRawPointer?, _ range: PerryCFRange, _ ascent: UnsafeMutablePointer<CGFloat>?,
                                      _ descent: UnsafeMutablePointer<CGFloat>?, _ leading: UnsafeMutablePointer<CGFloat>?) -> Double {
    guard let run = CTRun.run(run), let font = run.font else { return 0 }
    let wanted = run.part(range)
    guard !wanted.isEmpty else { return 0 }
    ascent?.pointee = CTFontGetAscent(font.objcObject)
    descent?.pointee = CTFontGetDescent(font.objcObject)
    leading?.pointee = CTFontGetLeading(font.objcObject)
    return Double(wanted.reduce(0) { $0 + run.advances[$1].width })
}

@DarwinC("_CTRunGetTextMatrix")
public func CTRunGetTextMatrix(_ run: UnsafeMutableRawPointer?) -> CGAffineTransform {
    CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)
}

/// The box of the glyphs from the baseline, from their font's descent to
/// its ascent, at the context's text position.
@DarwinC("_CTRunGetImageBounds")
public func CTRunGetImageBounds(_ run: UnsafeMutableRawPointer?, _ context: UnsafeMutableRawPointer?, _ range: PerryCFRange) -> CGRect {
    guard let run = CTRun.run(run), let font = run.font else { return .zero }
    let wanted = run.part(range)
    guard !wanted.isEmpty else { return .zero }
    var origin = CGPoint(x: 0, y: 0)
    if let context, CG.ready { origin = CG.getTextPosition(context) }
    let ascent = CTFontGetAscent(font.objcObject), descent = CTFontGetDescent(font.objcObject)
    let left = run.positions[wanted.lowerBound].x
    let right = run.positions[wanted.upperBound - 1].x + run.advances[wanted.upperBound - 1].width
    return CGRect(x: origin.x + left, y: origin.y - descent, width: right - left, height: ascent + descent)
}

/// Draws the run's glyphs where its line puts them, the line's origin at
/// the context's text position, in the run's color as CTLineDraw does.
@c(_CTRunDraw)
public func CTRunDraw(_ run: UnsafeMutableRawPointer?, _ context: UnsafeMutableRawPointer?, _ range: PerryCFRange) {
    guard let run = CTRun.run(run), let context, let font = run.font, let glyphs = run.glyphs.baseAddress, CG.ready else { return }
    let wanted = run.part(range)
    guard !wanted.isEmpty else { return }
    let origin = CG.getTextPosition(context)
    let points = wanted.map { CGPoint(x: origin.x + run.positions[$0].x, y: origin.y + run.positions[$0].y) }
    CG.saveGState(context)
    if let cgColor = run.cgColor {
        CG.setFillColorWithColor(context, cgColor.objcObject)
    } else if let color = run.color {
        CG.setFill(context, color)
    }
    points.withUnsafeBufferPointer { CoreText.draw(font, glyphs + wanted.lowerBound, $0.baseAddress!, wanted.count, in: context) }
    CG.restoreGState(context)
}

// MARK: - Drawing glyphs

/// Draws the font's glyphs at their positions, as
/// CGContextShowGlyphsAtPositions places them, in the context's fill
/// color; the context keeps the font and its size, as on Darwin.
@c(_CTFontDrawGlyphs)
public func CTFontDrawGlyphs(_ font: UnsafeMutableRawPointer?, _ glyphs: UnsafePointer<UInt16>?, _ positions: UnsafePointer<CGPoint>?,
                             _ count: Int, _ context: UnsafeMutableRawPointer?) {
    guard let font = CoreText.font(font), let glyphs, let positions, let context else { return }
    CoreText.draw(font, glyphs, positions, count, in: context)
}

// MARK: - Typesetters

/// A typesetter: its string's characters and runs, taken when it is made,
/// which its lines are cut from.
@ObjCClass("PerryCTTypesetter")
final class CTTypesetter: NSObject {
    var units: [UInt16] = []
    var runs: [CTLine.Run] = []

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { CoreTextTypeIDs.typesetter }

    static func typesetter(_ object: UnsafeMutableRawPointer?) -> CTTypesetter? {
        object.flatMap { NSObject(objCArgument: $0).as(CTTypesetter.self) }
    }

    /// The characters a CFRange names; a length of 0 is to the string's end.
    func characters(_ range: PerryCFRange) -> Range<Int> {
        let first = min(max(range.location, 0), units.count)
        return first..<(range.length > 0 ? min(first + range.length, units.count) : units.count)
    }
}

@c(_CTTypesetterGetTypeID) public func CTTypesetterGetTypeID() -> UInt { CoreTextTypeIDs.typesetter }

@c(_CTTypesetterCreateWithAttributedString)
public func CTTypesetterCreateWithAttributedString(_ string: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let string else { return nil }
    let typesetter = CTTypesetter()
    typesetter.units = CTLine.units(string)
    typesetter.runs = CTLine.attributeRuns(of: string, units: typesetter.units, in: 0..<typesetter.units.count)
    return typesetter.objCOwnedReturnValue()
}

/// The options (unbounded layout, a forced embedding level) change nothing
/// here: layout is always bounded and left to right.
@c(_CTTypesetterCreateWithAttributedStringAndOptions)
public func CTTypesetterCreateWithAttributedStringAndOptions(_ string: UnsafeMutableRawPointer?,
                                                             _ options: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    CTTypesetterCreateWithAttributedString(string)
}

/// A line of the characters in the range; a length of 0 is to the
/// string's end. The offset, which moves tab stops on Darwin, isn't used.
@DarwinC("_CTTypesetterCreateLineWithOffset")
public func CTTypesetterCreateLineWithOffset(_ typesetter: UnsafeMutableRawPointer?, _ stringRange: PerryCFRange,
                                             _ offset: Double) -> UnsafeMutableRawPointer? {
    guard let typesetter = CTTypesetter.typesetter(typesetter) else { return nil }
    let characters = typesetter.characters(stringRange)
    return CTLine.make(runs: CTLine.slice(typesetter.runs, characters), range: characters).objCOwnedReturnValue()
}

@c(_CTTypesetterCreateLine)
public func CTTypesetterCreateLine(_ typesetter: UnsafeMutableRawPointer?, _ stringRange: PerryCFRange) -> UnsafeMutableRawPointer? {
    CTTypesetterCreateLineWithOffset(typesetter, stringRange, 0)
}

/// How many characters from `startIndex` make a line within `width`,
/// breaking between words.
@DarwinC("_CTTypesetterSuggestLineBreakWithOffset")
public func CTTypesetterSuggestLineBreakWithOffset(_ typesetter: UnsafeMutableRawPointer?, _ startIndex: Int, _ width: Double,
                                                   _ offset: Double) -> Int {
    guard let typesetter = CTTypesetter.typesetter(typesetter) else { return 0 }
    return GlyphLayout.lineBreak(typesetter.runs, units: typesetter.units, from: startIndex, width: width, clusters: false)
}

@DarwinC("_CTTypesetterSuggestLineBreak")
public func CTTypesetterSuggestLineBreak(_ typesetter: UnsafeMutableRawPointer?, _ startIndex: Int, _ width: Double) -> Int {
    CTTypesetterSuggestLineBreakWithOffset(typesetter, startIndex, width, 0)
}

/// As CTTypesetterSuggestLineBreak, breaking between any characters.
@DarwinC("_CTTypesetterSuggestClusterBreakWithOffset")
public func CTTypesetterSuggestClusterBreakWithOffset(_ typesetter: UnsafeMutableRawPointer?, _ startIndex: Int, _ width: Double,
                                                      _ offset: Double) -> Int {
    guard let typesetter = CTTypesetter.typesetter(typesetter) else { return 0 }
    return GlyphLayout.lineBreak(typesetter.runs, units: typesetter.units, from: startIndex, width: width, clusters: true)
}

@DarwinC("_CTTypesetterSuggestClusterBreak")
public func CTTypesetterSuggestClusterBreak(_ typesetter: UnsafeMutableRawPointer?, _ startIndex: Int, _ width: Double) -> Int {
    CTTypesetterSuggestClusterBreakWithOffset(typesetter, startIndex, width, 0)
}

// MARK: - Glyph infos

/// A glyph info: the glyph that stands for its base string where an
/// attributed string gives it as kCTGlyphInfoAttributeName.
@ObjCClass("PerryCTGlyphInfo")
final class CTGlyphInfo: NSObject {
    var glyph: UInt16 = 0
    var name: NSObject?
    var baseString = ""
    var characterIdentifier: UInt16 = 0
    var collection: UInt16 = 0

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { CoreTextTypeIDs.glyphInfo }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }

    static func info(_ object: UnsafeMutableRawPointer?) -> CTGlyphInfo? {
        object.flatMap { NSObject(objCArgument: $0).as(CTGlyphInfo.self) }
    }

    static func make(glyph: UInt16, baseString: UnsafeMutableRawPointer?) -> CTGlyphInfo {
        let info = CTGlyphInfo()
        info.glyph = glyph
        info.baseString = baseString.map { String(objCArgument: $0) } ?? ""
        return info
    }

    /// The glyph a name gives in the font. Perry reads no glyph names from
    /// fonts, so only names of characters work: "uniXXXX", "uXXXX" to
    /// "uXXXXXX", and a character itself, through the font's character map.
    static func glyphNamed(_ name: String, in font: NSFont?) -> UInt16 {
        var scalar: UInt32?
        if name.hasPrefix("uni"), name.count == 7 {
            scalar = UInt32(name.dropFirst(3), radix: 16)
        } else if name.hasPrefix("u"), (5...7).contains(name.count) {
            scalar = UInt32(name.dropFirst(), radix: 16)
        } else if name.unicodeScalars.count == 1 {
            scalar = name.unicodeScalars.first?.value
        }
        guard let scalar, let font, let face = CoreText.face(font), let lookup = CoreText.glyphForCharacter else { return 0 }
        return lookup(face, scalar)
    }
}

@c(_CTGlyphInfoGetTypeID) public func CTGlyphInfoGetTypeID() -> UInt { CoreTextTypeIDs.glyphInfo }

@c(_CTGlyphInfoCreateWithGlyph)
public func CTGlyphInfoCreateWithGlyph(_ glyph: UInt16, _ font: UnsafeMutableRawPointer?, _ baseString: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    CTGlyphInfo.make(glyph: glyph, baseString: baseString).objCOwnedReturnValue()
}

/// NULL for a name the font has no glyph for, as on Darwin.
@c(_CTGlyphInfoCreateWithGlyphName)
public func CTGlyphInfoCreateWithGlyphName(_ glyphName: UnsafeMutableRawPointer?, _ font: UnsafeMutableRawPointer?,
                                           _ baseString: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let glyphName else { return nil }
    let glyph = CTGlyphInfo.glyphNamed(String(objCArgument: glyphName), in: CoreText.font(font))
    guard glyph != 0 else { return nil }
    let info = CTGlyphInfo.make(glyph: glyph, baseString: baseString)
    info.name = NSObject(glyphName)
    return info.objCOwnedReturnValue()
}

/// A character identifier is a glyph in kCTCharacterCollectionIdentityMapping
/// (0); in Adobe's collections, which Perry has no tables for, it has none.
@c(_CTGlyphInfoCreateWithCharacterIdentifier)
public func CTGlyphInfoCreateWithCharacterIdentifier(_ cid: UInt16, _ collection: UInt16,
                                                     _ baseString: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    let info = CTGlyphInfo.make(glyph: collection == 0 ? cid : 0, baseString: baseString)
    (info.characterIdentifier, info.collection) = (cid, collection)
    return info.objCOwnedReturnValue()
}

@DarwinC("_CTGlyphInfoGetGlyph")
public func CTGlyphInfoGetGlyph(_ glyphInfo: UnsafeMutableRawPointer?) -> UInt16 { CTGlyphInfo.info(glyphInfo)?.glyph ?? 0 }

@c(_CTGlyphInfoGetGlyphName)
public func CTGlyphInfoGetGlyphName(_ glyphInfo: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { CTGlyphInfo.info(glyphInfo)?.name?.objcObject }

@DarwinC("_CTGlyphInfoGetCharacterIdentifier")
public func CTGlyphInfoGetCharacterIdentifier(_ glyphInfo: UnsafeMutableRawPointer?) -> UInt16 {
    CTGlyphInfo.info(glyphInfo)?.characterIdentifier ?? 0
}

@DarwinC("_CTGlyphInfoGetCharacterCollection")
public func CTGlyphInfoGetCharacterCollection(_ glyphInfo: UnsafeMutableRawPointer?) -> UInt16 { CTGlyphInfo.info(glyphInfo)?.collection ?? 0 }

// MARK: - Font descriptors

/// A font descriptor: the attributes it was made with, of which a font
/// made from it takes the name (NSFontNameAttribute), family and face
/// (NSFontFamilyAttribute, NSFontFaceAttribute), size (NSFontSizeAttribute)
/// and bold and italic traits (NSCTFontTraitsAttribute's symbolic traits
/// or weight). A matrix (NSCTFontMatrixAttribute) isn't kept: Perry's fonts
/// draw through the context's text matrix alone, as CTFontCreateWithName's do.
@ObjCClass("PerryCTFontDescriptor")
final class CTFontDescriptor: NSObject {
    var attributes: NSDictionary?
    var name: String?
    var family: String?
    var face: String?
    var size: CGFloat = 0
    var bold: Bool?
    var italic: Bool?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { CoreTextTypeIDs.fontDescriptor }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }
    @ObjCMethod("fontAttributes") func fontAttributes() -> NSObject? { attributes }
    @ObjCMethod("objectForKey:") func object(forKey key: String?) -> NSObject? { key.flatMap { attributes?.object(forKey: $0) } }
    @ObjCMethod("pointSize") func pointSize() -> CGFloat { size }
    @ObjCMethod("postscriptName") func postscriptName() -> String? { name }

    static func descriptor(_ object: UnsafeMutableRawPointer?) -> CTFontDescriptor? {
        object.flatMap { NSObject(objCArgument: $0).as(CTFontDescriptor.self) }
    }

    static func make(_ attributes: UnsafeMutableRawPointer?) -> CTFontDescriptor {
        let descriptor = CTFontDescriptor()
        guard let dictionary = attributes.map(NSObject.init)?.as(NSDictionary.self) else { return descriptor }
        descriptor.attributes = dictionary
        descriptor.name = dictionary.object(forKey: "NSFontNameAttribute")?.stringValue
        descriptor.family = dictionary.object(forKey: "NSFontFamilyAttribute")?.stringValue
        descriptor.face = dictionary.object(forKey: "NSFontFaceAttribute")?.stringValue
        if let size = dictionary.object(forKey: "NSFontSizeAttribute")?.as(NSNumber.self) { descriptor.size = CGFloat(size.doubleValue()) }
        if let traits = dictionary.object(forKey: "NSCTFontTraitsAttribute")?.as(NSDictionary.self) {
            // kCTFontTraitItalic 1 and kCTFontTraitBold 2; else a weight of
            // semibold (0.3) or more is bold, as NSFont's system fonts are.
            if let symbolic = traits.object(forKey: "NSCTFontSymbolicTrait")?.as(NSNumber.self) {
                let value = UInt32(truncatingIfNeeded: Int64(symbolic.doubleValue()))
                (descriptor.italic, descriptor.bold) = (value & 1 != 0, value & 2 != 0)
            } else if let weight = traits.object(forKey: "NSCTFontWeightTrait")?.as(NSNumber.self) {
                descriptor.bold = weight.doubleValue() >= 0.3
            }
        }
        if let face = descriptor.face {
            descriptor.bold = descriptor.bold ?? (face.contains("Bold") || face.contains("Heavy") || face.contains("Black"))
            descriptor.italic = descriptor.italic ?? (face.contains("Italic") || face.contains("Oblique"))
        }
        return descriptor
    }

    /// The font the descriptor names at `size`, else its own size, else
    /// `original`'s, else 12 points. A copy of `original` keeps its face
    /// unless the descriptor names another, as Darwin's copies do.
    func font(size: CGFloat, copying original: NSFont?) -> NSFont {
        let pointSize = size > 0 ? size : self.size > 0 ? self.size : original?.size ?? 12
        let font: NSFont
        if let name {
            font = NSFont(name: name, size: pointSize)
        } else if let family {
            font = NSFont(name: family + (self.face.map { "-" + $0.split(separator: " ").joined() } ?? ""), size: pointSize)
        } else if let original {
            return original.with(size: pointSize)
        } else {
            font = NSFont(name: "Helvetica", size: pointSize)
        }
        // A new font takes the traits; a copy keeps the face its name gives.
        return original == nil && (bold != nil || italic != nil) ? font.with(bold: bold, italic: italic) : font
    }
}

@c(_CTFontDescriptorGetTypeID) public func CTFontDescriptorGetTypeID() -> UInt { CoreTextTypeIDs.fontDescriptor }

@c(_CTFontDescriptorCreateWithAttributes)
public func CTFontDescriptorCreateWithAttributes(_ attributes: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    CTFontDescriptor.make(attributes).objCOwnedReturnValue()
}

@DarwinC("_CTFontDescriptorCreateWithNameAndSize")
public func CTFontDescriptorCreateWithNameAndSize(_ name: UnsafeMutableRawPointer?, _ size: CGFloat) -> UnsafeMutableRawPointer? {
    let attributes = NSMutableDictionary.empty()
    if let name { attributes.set(NSObject(name), forKey: "NSFontNameAttribute") }
    attributes.set(NSNumber.make(double: Double(size)), forKey: "NSFontSizeAttribute")
    return CTFontDescriptor.make(attributes.objcObject).objCOwnedReturnValue()
}

/// One of the attributes the descriptor was made with, +1.
@c(_CTFontDescriptorCopyAttribute)
public func CTFontDescriptorCopyAttribute(_ descriptor: UnsafeMutableRawPointer?, _ attribute: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let descriptor = CTFontDescriptor.descriptor(descriptor), let attribute,
          let value = descriptor.attributes?.object(forKey: String(objCArgument: attribute)) else { return nil }
    return ObjCRuntime.retain(value.objcObject)
}

/// The font the descriptor names, at `size` (0 for the descriptor's, else
/// 12); the matrix isn't kept, as CTFontCreateWithName's isn't.
@DarwinC("_CTFontCreateWithFontDescriptor")
public func CTFontCreateWithFontDescriptor(_ descriptor: UnsafeMutableRawPointer?, _ size: CGFloat,
                                           _ matrix: UnsafeRawPointer?) -> UnsafeMutableRawPointer? {
    let font = CTFontDescriptor.descriptor(descriptor)?.font(size: size, copying: nil) ?? NSFont(name: "Helvetica", size: size > 0 ? size : 12)
    return font.objCOwnedReturnValue()
}

/// A copy of the font at `size`, else the descriptor's size, else its own,
/// in the font the descriptor names if it names one. As on Darwin, traits
/// alone don't change the copy's face; the matrix isn't kept.
@DarwinC("_CTFontCreateCopyWithAttributes")
public func CTFontCreateCopyWithAttributes(_ font: UnsafeMutableRawPointer?, _ size: CGFloat, _ matrix: UnsafeRawPointer?,
                                           _ attributes: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let original = CoreText.font(font) else { return nil }
    let descriptor = CTFontDescriptor.descriptor(attributes) ?? CTFontDescriptor()
    return descriptor.font(size: size, copying: original).objCOwnedReturnValue()
}

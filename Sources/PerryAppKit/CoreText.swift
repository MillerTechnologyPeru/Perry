import CPerryGeometry
import Glibc
import PerryObjCInterop

// Core Text for Mac apps, which bind it to ApplicationServices: a CTFont is
// an NSFont, as they are toll-free bridged on macOS, and its metrics,
// glyphs, advances, bounds and outlines are those of the CGFont FontConfig
// finds by its name, scaled from the face's units to points. A CTLine is an
// attributed string's runs, drawn through CoreGraphics' text functions at the
// context's text position; its glyph runs, typesetters and truncated lines
// are in CoreTextRuns.swift.

enum CoreText {
    typealias Ref = UnsafeMutableRawPointer?
    private static let coreGraphics = "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"

    nonisolated(unsafe) static var createWithFontName: (@convention(c) (Ref) -> Ref)?
    nonisolated(unsafe) static var retainFont: (@convention(c) (Ref) -> Ref)?
    nonisolated(unsafe) static var unitsPerEm: (@convention(c) (Ref) -> Int32)?
    nonisolated(unsafe) static var ascent: (@convention(c) (Ref) -> Int32)?
    nonisolated(unsafe) static var descent: (@convention(c) (Ref) -> Int32)?
    nonisolated(unsafe) static var leading: (@convention(c) (Ref) -> Int32)?
    nonisolated(unsafe) static var fontBBox: (@convention(c) (Ref) -> CGRect)?
    nonisolated(unsafe) static var glyphAdvances: (@convention(c) (Ref, UnsafePointer<UInt16>?, Int, UnsafeMutablePointer<Int32>?) -> Bool)?
    nonisolated(unsafe) static var glyphBBoxes: (@convention(c) (Ref, UnsafePointer<UInt16>?, Int, UnsafeMutablePointer<CGRect>?) -> Bool)?
    nonisolated(unsafe) static var glyphForCharacter: (@convention(c) (Ref, UInt32) -> UInt16)?
    nonisolated(unsafe) static var pathForGlyph: (@convention(c) (Ref, UInt16, CGFloat, UnsafePointer<CGAffineTransform>?) -> Ref)?

    nonisolated(unsafe) static var copyPostScriptName: (@convention(c) (Ref) -> Ref)?

    // A context's font and size, and glyphs by index at positions, for
    // CTFontDrawGlyphs.
    nonisolated(unsafe) static var setContextFont: (@convention(c) (Ref, Ref) -> Void)?
    nonisolated(unsafe) static var setContextFontSize: (@convention(c) (Ref, CGFloat) -> Void)?
    nonisolated(unsafe) static var showGlyphsAtPositions: (@convention(c) (Ref, UnsafePointer<UInt16>?, UnsafePointer<CGPoint>?, Int) -> Void)?

    nonisolated(unsafe) private static var loaded = false

    /// Binds CoreGraphics' font functions; a missing one leaves its Core
    /// Text functions answering nothing.
    private static func load() {
        guard !loaded else { return }
        loaded = true
        func bind<T>(_ name: String) -> T? {
            (Symbols.symbol(coreGraphics, "perry_native_" + name) ?? Symbols.symbol(coreGraphics, "_" + name))
                .map { unsafeBitCast($0, to: T.self) }
        }
        createWithFontName = bind("CGFontCreateWithFontName")
        retainFont = bind("CGFontRetain")
        unitsPerEm = bind("CGFontGetUnitsPerEm")
        ascent = bind("CGFontGetAscent")
        descent = bind("CGFontGetDescent")
        leading = bind("CGFontGetLeading")
        fontBBox = bind("CGFontGetFontBBox")
        glyphAdvances = bind("CGFontGetGlyphAdvances")
        glyphBBoxes = bind("CGFontGetGlyphBBoxes")
        glyphForCharacter = bind("perry_cgfont_glyph_for_character")
        pathForGlyph = bind("perry_cgfont_create_path_for_glyph")
        copyPostScriptName = bind("CGFontCopyPostScriptName")
        setContextFont = bind("CGContextSetFont")
        setContextFontSize = bind("CGContextSetFontSize")
        showGlyphsAtPositions = bind("CGContextShowGlyphsAtPositions")
    }

    /// Draws glyphs of the font at positions in text space, leaving the
    /// context's font and size the font's, as Core Text does. Glyph 0xFFFF
    /// (kCGFontIndexInvalid) draws nothing.
    static func draw(_ font: NSFont, _ glyphs: UnsafePointer<UInt16>, _ positions: UnsafePointer<CGPoint>, _ count: Int,
                     in context: UnsafeMutableRawPointer) {
        guard count > 0, let face = face(font), let setContextFont, let setContextFontSize, let showGlyphsAtPositions else { return }
        setContextFont(context, face)
        setContextFontSize(context, font.size)
        var shown: [UInt16] = [], points: [CGPoint] = []
        shown.reserveCapacity(count)
        points.reserveCapacity(count)
        for index in 0..<count where glyphs[index] != 0xFFFF {
            shown.append(glyphs[index])
            points.append(positions[index])
        }
        guard !shown.isEmpty else { return }
        showGlyphsAtPositions(context, shown, points, shown.count)
    }

    /// The family the system font is drawn in: Inter, which is drawn after
    /// Apple's San Francisco, when FontConfig has it, and DejaVu Sans, which
    /// Perry's packages install, otherwise.
    static let systemFamily: String = {
        load()
        guard let face = named("Inter") else { return "DejaVu Sans" }
        defer { ObjCRuntime.release(face) }
        guard let name = copyPostScriptName?(face) else { return "DejaVu Sans" }
        defer { ObjCRuntime.release(name) }
        return String(objCArgument: name).hasPrefix("Inter") ? "Inter" : "DejaVu Sans"
    }()

    private static func named(_ name: String) -> UnsafeMutableRawPointer? {
        let string = name.objCOwnedReturnValue()
        defer { ObjCRuntime.release(string) }
        return createWithFontName?(string)
    }

    /// The CGFont of each name a font draws in, made once.
    nonisolated(unsafe) private static var faces: [String: UnsafeMutableRawPointer] = [:]

    static func face(_ font: NSFont) -> UnsafeMutableRawPointer? {
        load()
        let name = font.drawingName
        if let face = faces[name] { return face }
        guard let face = named(name) ?? named("sans-serif") else { return nil }
        faces[name] = face
        return face
    }

    /// Points per font unit at the font's size.
    static func scale(_ font: NSFont, _ face: UnsafeMutableRawPointer) -> CGFloat {
        let units = CGFloat(unitsPerEm?(face) ?? 1000)
        return font.size / (units > 0 ? units : 1000)
    }

    /// A face's metric in points, or nil without the face.
    static func metric(_ font: NSFont, _ value: ((Ref) -> Int32)?) -> CGFloat? {
        guard let face = face(font), let value else { return nil }
        return CGFloat(value(face)) * scale(font, face)
    }

    static func font(_ object: UnsafeMutableRawPointer?) -> NSFont? {
        object.flatMap { NSObject(objCArgument: $0).as(NSFont.self) }
    }

    static func scaled(_ box: CGRect, _ scale: CGFloat) -> CGRect {
        CGRect(x: box.origin.x * scale, y: box.origin.y * scale, width: box.size.width * scale, height: box.size.height * scale)
    }

    static func union(_ a: CGRect?, _ b: CGRect) -> CGRect {
        guard let a else { return b }
        let minX = min(a.origin.x, b.origin.x), minY = min(a.origin.y, b.origin.y)
        let maxX = max(a.origin.x + a.size.width, b.origin.x + b.size.width)
        let maxY = max(a.origin.y + a.size.height, b.origin.y + b.size.height)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

@ObjCConstants
enum CoreTextConstants {
    static let kCTFontAttributeName = "NSFont"
    static let kCTForegroundColorAttributeName = "CTForegroundColor"
    static let kCTForegroundColorFromContextAttributeName = "CTForegroundColorFromContext"
    static let kCTGlyphInfoAttributeName = "NSGlyphInfo"
    // Typesetter options, which Perry's typesetters take and don't need.
    static let kCTTypesetterOptionAllowUnboundedLayout = "CTTypesetterOptionAllowUnboundedLayout"
    static let kCTTypesetterOptionForcedEmbeddingLevel = "CTTypesetterOptionForcedEmbeddingLevel"
}

// MARK: - Fonts

/// A font by its PostScript name, at a size (12 for 0).
@DarwinC("_CTFontCreateWithName")
public func CTFontCreateWithName(_ name: UnsafeMutableRawPointer?, _ size: CGFloat, _ matrix: UnsafeRawPointer?) -> UnsafeMutableRawPointer? {
    let fontName = name.map { String(objCArgument: $0) } ?? "Helvetica"
    return NSFont(name: fontName, size: size > 0 ? size : 12).objCOwnedReturnValue()
}

/// The system font of the size; 0 is the type's default size.
@DarwinC("_CTFontCreateUIFontForLanguage")
public func CTFontCreateUIFontForLanguage(_ type: UInt32, _ size: CGFloat, _ language: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    NSFont.system(size: size > 0 ? size : 13).objCOwnedReturnValue()
}

/// kCTFontItalicTrait 1 and kCTFontBoldTrait 2 changed as `mask` says.
@DarwinC("_CTFontCreateCopyWithSymbolicTraits")
public func CTFontCreateCopyWithSymbolicTraits(_ font: UnsafeMutableRawPointer?, _ size: CGFloat, _ matrix: UnsafeRawPointer?,
                                               _ value: UInt32, _ mask: UInt32) -> UnsafeMutableRawPointer? {
    guard let original = CoreText.font(font) else { return nil }
    let copy = original.with(bold: mask & 2 != 0 ? value & 2 != 0 : nil, italic: mask & 1 != 0 ? value & 1 != 0 : nil,
                             size: size > 0 ? size : original.size)
    return copy.objCOwnedReturnValue()
}

@c(_CTFontCopyGraphicsFont)
public func CTFontCopyGraphicsFont(_ font: UnsafeMutableRawPointer?, _ attributes: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UnsafeMutableRawPointer? {
    attributes?.pointee = nil
    guard let font = CoreText.font(font), let face = CoreText.face(font) else { return nil }
    return CoreText.retainFont?(face) ?? ObjCRuntime.retain(face)
}

// MARK: - Metrics, in points

@DarwinC("_CTFontGetSize")
public func CTFontGetSize(_ font: UnsafeMutableRawPointer?) -> CGFloat { CoreText.font(font)?.size ?? 0 }

@DarwinC("_CTFontGetAscent")
public func CTFontGetAscent(_ font: UnsafeMutableRawPointer?) -> CGFloat {
    guard let font = CoreText.font(font) else { return 0 }
    return CoreText.metric(font, CoreText.ascent) ?? font.ascender()
}

@DarwinC("_CTFontGetDescent")
public func CTFontGetDescent(_ font: UnsafeMutableRawPointer?) -> CGFloat {
    guard let font = CoreText.font(font) else { return 0 }
    // CoreGraphics' descent is below the baseline, negative; Core Text's is
    // its distance.
    return abs(CoreText.metric(font, CoreText.descent) ?? font.descender())
}

@DarwinC("_CTFontGetLeading")
public func CTFontGetLeading(_ font: UnsafeMutableRawPointer?) -> CGFloat {
    guard let font = CoreText.font(font) else { return 0 }
    return CoreText.metric(font, CoreText.leading) ?? 0
}

/// The x-height and cap height, as NSFont gives them.
@DarwinC("_CTFontGetXHeight")
public func CTFontGetXHeight(_ font: UnsafeMutableRawPointer?) -> CGFloat { CoreText.font(font)?.xHeight() ?? 0 }

@DarwinC("_CTFontGetCapHeight")
public func CTFontGetCapHeight(_ font: UnsafeMutableRawPointer?) -> CGFloat { CoreText.font(font)?.capHeight() ?? 0 }

@DarwinC("_CTFontGetBoundingBox")
public func CTFontGetBoundingBox(_ font: UnsafeMutableRawPointer?) -> CGRect {
    guard let font = CoreText.font(font), let face = CoreText.face(font), let box = CoreText.fontBBox?(face) else { return .zero }
    return CoreText.scaled(box, CoreText.scale(font, face))
}

// MARK: - Glyphs

/// Each UTF-16 unit's glyph; a surrogate pair's is at its first unit, with
/// 0 at its second. False if any character has none.
@c(_CTFontGetGlyphsForCharacters)
public func CTFontGetGlyphsForCharacters(_ font: UnsafeMutableRawPointer?, _ characters: UnsafePointer<UInt16>?,
                                         _ glyphs: UnsafeMutablePointer<UInt16>?, _ count: Int) -> Bool {
    guard let characters, let glyphs, count > 0 else { return false }
    guard let font = CoreText.font(font), let face = CoreText.face(font), let lookup = CoreText.glyphForCharacter else {
        glyphs.update(repeating: 0, count: count)
        return false
    }
    var all = true, i = 0
    while i < count {
        var scalar = UInt32(characters[i])
        var units = 1
        if (0xD800..<0xDC00).contains(scalar), i + 1 < count, (0xDC00..<0xE000).contains(UInt32(characters[i + 1])) {
            scalar = 0x10000 + ((scalar - 0xD800) << 10) + (UInt32(characters[i + 1]) - 0xDC00)
            units = 2
        }
        let glyph = lookup(face, scalar)
        if glyph == 0 { all = false }
        glyphs[i] = glyph
        if units == 2 { glyphs[i + 1] = 0 }
        i += units
    }
    return all
}

/// The glyphs' advances, horizontal unless the orientation is vertical (2);
/// their sum.
@DarwinC("_CTFontGetAdvancesForGlyphs")
public func CTFontGetAdvancesForGlyphs(_ font: UnsafeMutableRawPointer?, _ orientation: UInt32, _ glyphs: UnsafePointer<UInt16>?,
                                       _ advances: UnsafeMutablePointer<CGSize>?, _ count: Int) -> Double {
    guard let glyphs, count > 0, let font = CoreText.font(font), let face = CoreText.face(font) else { return 0 }
    var units = [Int32](repeating: 0, count: count)
    guard CoreText.glyphAdvances?(face, glyphs, count, &units) == true else { return 0 }
    let scale = CoreText.scale(font, face)
    var total: CGFloat = 0
    for (index, unit) in units.enumerated() {
        let advance = CGFloat(unit) * scale
        advances?[index] = orientation == 2 ? CGSize(width: 0, height: advance) : CGSize(width: advance, height: 0)
        total += advance
    }
    return Double(total)
}

/// The glyphs' bounding rectangles from their origins; their union.
@DarwinC("_CTFontGetBoundingRectsForGlyphs")
public func CTFontGetBoundingRectsForGlyphs(_ font: UnsafeMutableRawPointer?, _ orientation: UInt32, _ glyphs: UnsafePointer<UInt16>?,
                                            _ rects: UnsafeMutablePointer<CGRect>?, _ count: Int) -> CGRect {
    guard let glyphs, count > 0, let font = CoreText.font(font), let face = CoreText.face(font) else { return .zero }
    var boxes = [CGRect](repeating: .zero, count: count)
    guard CoreText.glyphBBoxes?(face, glyphs, count, &boxes) == true else { return .zero }
    let scale = CoreText.scale(font, face)
    var union: CGRect?
    for (index, box) in boxes.enumerated() {
        let rect = CoreText.scaled(box, scale)
        rects?[index] = rect
        union = CoreText.union(union, rect)
    }
    return union ?? .zero
}

@c(_CTFontCreatePathForGlyph)
public func CTFontCreatePathForGlyph(_ font: UnsafeMutableRawPointer?, _ glyph: UInt16,
                                     _ transform: UnsafePointer<CGAffineTransform>?) -> UnsafeMutableRawPointer? {
    guard let font = CoreText.font(font), let face = CoreText.face(font) else { return nil }
    return CoreText.pathForGlyph?(face, glyph, CoreText.scale(font, face), transform)
}

// MARK: - Lines

/// A line of an attributed string: its runs, each in one font and color.
/// A run's color is a CGColor (kCTForegroundColorAttributeName) or NSColor
/// (NSForegroundColorAttributeName); without either, or with
/// kCTForegroundColorFromContextAttributeName, the context's fill color.
@ObjCClass("PerryCTLine")
final class CTLine: NSObject {
    struct Run {
        var text: String
        var font: NSFont
        var cgColor: NSObject?
        var color: NSColor?
        /// The attributes the string gives the run's text.
        var attributes: NSDictionary?
        /// The characters of the string the run stands for, by UTF-16
        /// index: its text's, or a truncation token's the ones it replaces.
        var location = 0
        var length = 0
        var isToken = false
    }

    var runs: [Run] = []
    /// The characters of its string the line was made from.
    var range: Range<Int> = 0..<0
    /// The runs as CTRun objects, made when first asked for.
    var glyphRuns: NSMutableArray?

    @ObjCMethod("init")
    public required override init() { super.init() }

    /// The UTF-16 units of an attributed string's text.
    static func units(_ attributed: UnsafeMutableRawPointer) -> [UInt16] {
        guard let stringObject = Send.object(attributed, "string") else { return [] }
        return Array(String(objCArgument: stringObject).utf16)
    }

    /// The runs of an attributed string's characters in `range`; Core
    /// Text's default font is Helvetica at 12 points.
    static func attributeRuns(of attributed: UnsafeMutableRawPointer, units: [UInt16], in range: Range<Int>) -> [Run] {
        typealias AttributesAt = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, UInt, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
        let attributesAt = unsafeBitCast(ObjCRuntime.msgSend, to: AttributesAt.self)
        var runs: [Run] = []
        var location = range.lowerBound
        while location < range.upperBound {
            var effective = NSRange(location: 0, length: 0)
            let attributes = attributesAt(attributed, ObjCRuntime.selector("attributesAtIndex:effectiveRange:"), UInt(location), &effective)
                .map(NSObject.init)?.as(NSDictionary.self)
            let end = min(range.upperBound, max(location + 1, Int(effective.location + effective.length)))
            var run = Run(text: String(decoding: units[location..<end], as: UTF16.self), font: NSFont(name: "Helvetica", size: 12),
                          attributes: attributes, location: location, length: end - location)
            if let attributes {
                if let font = attributes.object(forKey: "NSFont")?.as(NSFont.self) { run.font = font }
                if attributes.object(forKey: "CTForegroundColorFromContext") == nil {
                    if let cgColor = attributes.object(forKey: "CTForegroundColor") {
                        run.cgColor = cgColor
                    } else {
                        run.color = attributes.object(forKey: "NSColor")?.as(NSColor.self)
                    }
                }
            }
            runs.append(run)
            location = end
        }
        return runs
    }

    /// A line of the runs of the string's characters in `range`, all of
    /// them for nil.
    static func make(_ attributed: UnsafeMutableRawPointer, range wanted: Range<Int>? = nil) -> CTLine {
        let text = CTLine.units(attributed)
        let range = wanted.map { $0.clamped(to: 0..<text.count) } ?? 0..<text.count
        return CTLine.make(runs: CTLine.attributeRuns(of: attributed, units: text, in: range), range: range)
    }

    static func make(runs: [Run], range: Range<Int>) -> CTLine {
        let line = CTLine()
        line.runs = runs
        line.range = range
        return line
    }

    /// The parts of runs in a range of their string's characters; truncation
    /// tokens are left out.
    static func slice(_ runs: [Run], _ range: Range<Int>) -> [Run] {
        var sliced: [Run] = []
        for run in runs where !run.isToken {
            let start = max(run.location, range.lowerBound), end = min(run.location + run.length, range.upperBound)
            guard start < end else { continue }
            var part = run
            if start > run.location || end < run.location + run.length {
                let units = Array(run.text.utf16)
                part.text = String(decoding: units[(start - run.location)..<(end - run.location)], as: UTF16.self)
                (part.location, part.length) = (start, end - start)
            }
            sliced.append(part)
        }
        return sliced
    }

    static func line(_ object: UnsafeMutableRawPointer?) -> CTLine? {
        object.flatMap { NSObject(objCArgument: $0).as(CTLine.self) }
    }

    /// The line's width, and its greatest ascent and descent.
    var bounds: (width: CGFloat, ascent: CGFloat, descent: CGFloat) {
        var width: CGFloat = 0, ascent: CGFloat = 0, descent: CGFloat = 0
        for run in runs {
            width += Text.width(run.text, font: run.font)
            ascent = max(ascent, CTFontGetAscent(run.font.objcObject))
            descent = max(descent, CTFontGetDescent(run.font.objcObject))
        }
        return (width, ascent, descent)
    }
}

@c(_CTLineCreateWithAttributedString)
public func CTLineCreateWithAttributedString(_ string: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let string else { return nil }
    return CTLine.make(string).objCOwnedReturnValue()
}

/// The line's ink: from its descent to its ascent, over its width.
@DarwinC("_CTLineGetImageBounds")
public func CTLineGetImageBounds(_ line: UnsafeMutableRawPointer?, _ context: UnsafeMutableRawPointer?) -> CGRect {
    guard let bounds = CTLine.line(line)?.bounds else { return .zero }
    return CGRect(x: 0, y: -bounds.descent, width: bounds.width, height: bounds.ascent + bounds.descent)
}

@DarwinC("_CTLineGetTypographicBounds")
public func CTLineGetTypographicBounds(_ line: UnsafeMutableRawPointer?, _ ascent: UnsafeMutablePointer<CGFloat>?,
                                       _ descent: UnsafeMutablePointer<CGFloat>?, _ leading: UnsafeMutablePointer<CGFloat>?) -> Double {
    guard let bounds = CTLine.line(line)?.bounds else { return 0 }
    ascent?.pointee = bounds.ascent
    descent?.pointee = bounds.descent
    leading?.pointee = 0
    return Double(bounds.width)
}

/// Draws the line with its baseline at the context's text position, through
/// its text matrix, and leaves the position after it.
@c(_CTLineDraw)
public func CTLineDraw(_ line: UnsafeMutableRawPointer?, _ context: UnsafeMutableRawPointer?) {
    guard let line = CTLine.line(line), let context, CG.ready else { return }
    var position = CG.getTextPosition(context)
    for run in line.runs where !run.text.isEmpty {
        CG.saveGState(context)
        if let cgColor = run.cgColor {
            CG.setFillColorWithColor(context, cgColor.objcObject)
        } else if let color = run.color {
            CG.setFill(context, color)
        }
        run.font.drawingName.withCString { CG.selectFont(context, $0, run.font.size, 1) }
        CG.setTextDrawingMode(context, 0)
        CG.setTextPosition(context, position.x, position.y)
        var utf8 = Array(run.text.utf8)
        utf8.withUnsafeMutableBufferPointer { buffer in
            buffer.baseAddress!.withMemoryRebound(to: CChar.self, capacity: buffer.count) { CG.showText(context, $0, buffer.count) }
        }
        position = CG.getTextPosition(context)
        CG.restoreGState(context)
    }
    CG.setTextPosition(context, position.x, position.y)
}

import CPerryGeometry
import Glibc
import PerryObjCInterop

// Core Text for Mac apps, which bind it to ApplicationServices: a CTFont is
// an NSFont, as they are toll-free bridged on macOS, and its metrics,
// glyphs, advances, bounds and outlines are those of the CGFont FontConfig
// finds by its name, scaled from the face's units to points. A CTLine is an
// attributed string's runs, drawn through CoreGraphics' text functions at the
// context's text position.

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
    }

    /// The CGFont of each name a font draws in, made once.
    nonisolated(unsafe) private static var faces: [String: UnsafeMutableRawPointer] = [:]

    static func face(_ font: NSFont) -> UnsafeMutableRawPointer? {
        load()
        let name = font.drawingName
        if let face = faces[name] { return face }
        func named(_ name: String) -> UnsafeMutableRawPointer? {
            let string = name.objCOwnedReturnValue()
            defer { ObjCRuntime.release(string) }
            return createWithFontName?(string)
        }
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
        var cgColor: UnsafeMutableRawPointer?
        var color: NSColor?
    }

    var runs: [Run] = []

    @ObjCMethod("init")
    public required override init() { super.init() }

    deinit {
        for run in runs { ObjCRuntime.release(run.cgColor) }
    }

    /// The runs of an attributed string; Core Text's default font is
    /// Helvetica at 12 points.
    static func make(_ attributed: UnsafeMutableRawPointer) -> CTLine {
        let line = CTLine()
        guard let stringObject = Send.object(attributed, "string") else { return line }
        let units = Array(String(objCArgument: stringObject).utf16)
        typealias AttributesAt = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, UInt, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
        let attributesAt = unsafeBitCast(ObjCRuntime.msgSend, to: AttributesAt.self)
        var location = 0
        while location < units.count {
            var range = NSRange(location: 0, length: 0)
            let attributes = attributesAt(attributed, ObjCRuntime.selector("attributesAtIndex:effectiveRange:"), UInt(location), &range)
                .map(NSObject.init)?.as(NSDictionary.self)
            let end = min(units.count, max(location + 1, Int(range.location + range.length)))
            var run = Run(text: String(decoding: units[location..<end], as: UTF16.self), font: NSFont(name: "Helvetica", size: 12))
            if let attributes {
                if let font = attributes.object(forKey: "NSFont")?.as(NSFont.self) { run.font = font }
                if attributes.object(forKey: "CTForegroundColorFromContext") == nil {
                    if let cgColor = attributes.object(forKey: "CTForegroundColor") {
                        run.cgColor = ObjCRuntime.retain(cgColor.objcObject)
                    } else {
                        run.color = attributes.object(forKey: "NSColor")?.as(NSColor.self)
                    }
                }
            }
            line.runs.append(run)
            location = end
        }
        return line
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
            CG.setFillColorWithColor(context, cgColor)
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

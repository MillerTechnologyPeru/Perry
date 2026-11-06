import CPerryGeometry
import CFontConfig
import CCairo
import CFreeType
import Cairo
import Glibc
import PerryObjCInterop
import Silica
import SilicaCairo

// CGFont: a font face, by name through FontConfig or from a font file's
// data, loaded by FreeType through Cairo's scaled fonts, as Silica's fonts
// are. Apps that lay text out themselves read its metrics, in font units,
// and its tables, and draw its glyphs by index.

final class FontState {
    let font: Silica.CGFont
    /// The file a font made from data was written to, removed with it
    /// unless the font was registered.
    let file: String?
    /// Whether CTFontManagerRegisterGraphicsFont registered it: its file
    /// stays, for FontConfig to find by name.
    var registered = false

    init(font: Silica.CGFont, file: String? = nil) {
        self.font = font
        self.file = file
    }

    deinit {
        if let file, !registered { unlink(file) }
    }

    var scaled: Cairo.ScaledFont { font.scaledFont }

    /// The font file's bytes, read once.
    private(set) lazy var bytes: [UInt8]? = {
        guard let path = font.file?.path, let data = NSData.make(contentsOfFile: path) else { return nil }
        return data.array
    }()

    /// One of the font file's tables, from its table directory (a
    /// collection's, for the face's index in it); nil without it.
    func table(_ tag: UInt32) -> [UInt8]? {
        guard let bytes else { return nil }
        func word(_ offset: Int) -> Int? {
            guard offset >= 0, offset + 4 <= bytes.count else { return nil }
            return Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16 | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
        }
        var directory = 0
        // 'ttcf': a collection, whose header lists each face's directory.
        if word(0) == 0x7474_6366 {
            guard let offset = word(12 + 4 * (font.file?.index ?? 0)) else { return nil }
            directory = offset
        }
        guard directory + 6 <= bytes.count else { return nil }
        let count = Int(bytes[directory + 4]) << 8 | Int(bytes[directory + 5])
        for index in 0..<count {
            let record = directory + 12 + index * 16
            guard let name = word(record), let offset = word(record + 8), let length = word(record + 12) else { return nil }
            if UInt32(name) == tag {
                guard offset + length <= bytes.count else { return nil }
                return Array(bytes[offset..<offset + length])
            }
        }
        return nil
    }
}

@ObjCClass("CGFont")
public final class CGFontObject: NSObject {
    static let states = StateTable<FontState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        CGFontObject.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CGFontObject.objCClass.pointer)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { TypeIDs.font }
}

enum Fonts {
    static func make(_ state: FontState) -> Ref { makeObject(CGFontObject.objCClass, CGFontObject.states, state) }
    static func state(_ font: Ref?) -> FontState? { CGFontObject.states[font] }

    static func rect(_ x: Int, _ y: Int, _ width: Int, _ height: Int) -> CGRect {
        CGRect(origin: CGPoint(x: CGFloat(x), y: CGFloat(y)), size: CGSize(width: CGFloat(width), height: CGFloat(height)))
    }

    /// Where fonts made from data are written for FreeType to open.
    static var directory: String {
        getenv("PERRY_TMP").map { String(cString: $0) } ?? "/tmp"
    }
}

@c(_CGFontGetTypeID) public func CGFontGetTypeID() -> UInt { TypeIDs.font }

/// Adds a font made from data to the fonts FontConfig chooses from, so text
/// drawn in its name uses it: CTFontManagerRegisterGraphicsFont, which
/// UIKit's CoreText calls this for. A font made from a name is already
/// among them.
@c(_perry_cgfont_register)
public func perryCGFontRegister(_ font: Ref?) -> Bool {
    guard let state = Fonts.state(font) else { return false }
    guard let file = state.file else { return true }
    if !state.registered {
        state.registered = true
        _ = file.withCString { FcConfigAppFontAddFile(nil, $0) }
    }
    return true
}

/// A font by its PostScript or full name; nil when there is none by it.
@c(_CGFontCreateWithFontName)
public func CGFontCreateWithFontName(_ name: Ref?) -> Ref? {
    guard let name, let font = Silica.CGFont(name: String(objCArgument: name)) else { return nil }
    return Fonts.make(FontState(font: font))
}

/// A font from a font file's bytes (TrueType, OpenType), written out for
/// FreeType to open; nil when they are not a font.
@c(_CGFontCreateWithDataProvider)
public func CGFontCreateWithDataProvider(_ provider: Ref?) -> Ref? {
    guard let bytes = DataProviders.bytes(provider), !bytes.isEmpty else { return nil }
    mkdir(Fonts.directory, 0o755)
    var template = Array((Fonts.directory + "/perry-font-XXXXXX").utf8CString)
    let file = mkstemp(&template)
    guard file >= 0 else { return nil }
    let path = String(cString: template)
    let written = bytes.withUnsafeBytes { write(file, $0.baseAddress, $0.count) }
    close(file)
    guard written == bytes.count, let font = Silica.CGFont(file: path) else {
        unlink(path)
        return nil
    }
    return Fonts.make(FontState(font: font, file: path))
}

@c(_CGFontRetain) public func CGFontRetain(_ font: Ref?) -> Ref? { ObjCRuntime.retain(font) }
@c(_CGFontRelease) public func CGFontRelease(_ font: Ref?) { ObjCRuntime.release(font) }

@c(_CGFontCopyFullName)
public func CGFontCopyFullName(_ font: Ref?) -> Ref? { Fonts.state(font).flatMap { $0.scaled.fullName.objCOwnedReturnValue() } }

@c(_CGFontCopyPostScriptName)
public func CGFontCopyPostScriptName(_ font: Ref?) -> Ref? {
    Fonts.state(font).flatMap { ($0.scaled.postScriptName ?? $0.scaled.fullName).objCOwnedReturnValue() }
}

// Metrics, in the font's units.

@c(_CGFontGetUnitsPerEm) public func CGFontGetUnitsPerEm(_ font: Ref?) -> Int32 { Int32(Fonts.state(font)?.scaled.unitsPerEm ?? 0) }
@c(_CGFontGetAscent) public func CGFontGetAscent(_ font: Ref?) -> Int32 { Int32(Fonts.state(font)?.scaled.ascent ?? 0) }
@c(_CGFontGetDescent) public func CGFontGetDescent(_ font: Ref?) -> Int32 { Int32(Fonts.state(font)?.scaled.descent ?? 0) }
@c(_CGFontGetLeading) public func CGFontGetLeading(_ font: Ref?) -> Int32 { Int32(Fonts.state(font)?.scaled.leading ?? 0) }
@c(_CGFontGetCapHeight) public func CGFontGetCapHeight(_ font: Ref?) -> Int32 { Int32(Fonts.state(font)?.scaled.capHeight ?? 0) }
@c(_CGFontGetXHeight) public func CGFontGetXHeight(_ font: Ref?) -> Int32 { Int32(Fonts.state(font)?.scaled.xHeight ?? 0) }
@c(_CGFontGetNumberOfGlyphs) public func CGFontGetNumberOfGlyphs(_ font: Ref?) -> Int { Fonts.state(font)?.scaled.glyphCount ?? 0 }

@DarwinC("_CGFontGetFontBBox")
public func CGFontGetFontBBox(_ font: Ref?) -> CGRect {
    guard let box = Fonts.state(font)?.scaled.fontBBox else { return Fonts.rect(0, 0, 0, 0) }
    return Fonts.rect(box.x, box.y, box.width, box.height)
}

/// One of the font file's tables ('cmap', 'head'…), as data; nil without it.
@c(_CGFontCopyTableForTag)
public func CGFontCopyTableForTag(_ font: Ref?, _ tag: UInt32) -> Ref? {
    guard let table = Fonts.state(font)?.table(tag) else { return nil }
    return NSData.of(table).objCOwnedReturnValue()
}

/// The glyphs' bounding boxes, in the font's units.
@c(_CGFontGetGlyphBBoxes)
public func CGFontGetGlyphBBoxes(_ font: Ref?, _ glyphs: UnsafePointer<UInt16>?, _ count: Int, _ boxes: UnsafeMutablePointer<CGRect>?) -> Bool {
    guard let state = Fonts.state(font), let glyphs, let boxes, count >= 0 else { return false }
    let found = state.scaled.boundingBoxes(for: Array(UnsafeBufferPointer(start: glyphs, count: count)))
    guard found.count == count else { return false }
    for (index, box) in found.enumerated() { boxes[index] = Fonts.rect(box.x, box.y, box.width, box.height) }
    return true
}

/// The glyphs' advances, in the font's units.
@c(_CGFontGetGlyphAdvances)
public func CGFontGetGlyphAdvances(_ font: Ref?, _ glyphs: UnsafePointer<UInt16>?, _ count: Int, _ advances: UnsafeMutablePointer<Int32>?) -> Bool {
    guard let state = Fonts.state(font), let glyphs, let advances, count >= 0 else { return false }
    let found = state.scaled.advances(for: Array(UnsafeBufferPointer(start: glyphs, count: count)))
    guard found.count == count else { return false }
    for (index, advance) in found.enumerated() { advances[index] = Int32(advance) }
    return true
}

// MARK: - Characters and outlines, for CoreText

/// The glyph of a Unicode scalar in the font's character map; 0 without one.
@c(_perry_cgfont_glyph_for_character)
public func perryCGFontGlyphForCharacter(_ font: Ref?, _ character: UInt32) -> UInt16 {
    guard let state = Fonts.state(font) else { return 0 }
    return UInt16(truncatingIfNeeded: state.scaled[UInt(character)])
}

/// A glyph's outline, in the font's units times `scale`, y up, through the
/// transform: CTFontCreatePathForGlyph. nil for a glyph without one.
@c(_perry_cgfont_create_path_for_glyph)
public func perryCGFontCreatePathForGlyph(_ font: Ref?, _ glyph: UInt16, _ scale: CGFloat,
                                          _ transform: UnsafePointer<CPerryGeometry.CGAffineTransform>?) -> Ref? {
    guard let state = Fonts.state(font) else { return nil }
    let commands: [PathCommand]? = state.scaled.withUnsafePointer { scaledFont in
        guard let face = cairo_ft_scaled_font_lock_face(scaledFont) else { return nil }
        defer { cairo_ft_scaled_font_unlock_face(scaledFont) }
        guard FT_Load_Glyph(face, FT_UInt(glyph), Int32(FT_LOAD_NO_SCALE)) == 0,
              face.pointee.glyph.pointee.format == FT_GLYPH_FORMAT_OUTLINE else { return nil }
        return Fonts.decompose(face.pointee.glyph.pointee.outline, scale: Double(scale))
    }
    guard let commands else { return nil }
    let path = Paths.make()
    Paths.append(path, transform, commands)
    return path
}

extension Fonts {
    /// An outline's contours as path commands, as FT_Outline_Decompose
    /// walks them: on-curve points, quadratic (conic) control points with
    /// implied on-curve midpoints between two in a row, and cubic pairs.
    static func decompose(_ outline: FT_Outline, scale: Double) -> [PathCommand] {
        var commands: [PathCommand] = []
        guard let points = outline.points, let tags = outline.tags, let contours = outline.contours else { return [] }
        func point(_ i: Int) -> (Double, Double) { (Double(points[i].x) * scale, Double(points[i].y) * scale) }
        func kind(_ i: Int) -> UInt8 { UInt8(truncatingIfNeeded: tags[i]) & 3 }   // 1 on, 0 conic, 2 cubic
        var first = 0
        for c in 0..<Int(outline.n_contours) {
            let last = Int(contours[c])
            defer { first = last + 1 }
            guard last >= first else { continue }
            var start = point(first), index = first
            if kind(first) == 0 {
                // Starts off the curve: from the last point if it is on, else their midpoint.
                if kind(last) == 1 { start = point(last) } else {
                    let l = point(last)
                    start = ((start.0 + l.0) / 2, (start.1 + l.1) / 2)
                }
                index -= 1
            }
            commands.append(.move(start.0, start.1))
            var i = index + 1
            var pending: (Double, Double)?
            while i <= last {
                let p = point(i)
                switch kind(i) {
                case 1:
                    if let control = pending { commands.append(.quad(control.0, control.1, p.0, p.1)); pending = nil }
                    else { commands.append(.line(p.0, p.1)) }
                    i += 1
                case 0:
                    if let control = pending {
                        let mid = ((control.0 + p.0) / 2, (control.1 + p.1) / 2)
                        commands.append(.quad(control.0, control.1, mid.0, mid.1))
                    }
                    pending = p
                    i += 1
                default:
                    // Two cubic controls, then an on-curve point (the start, past the end).
                    let second = i + 1 <= last ? point(i + 1) : start
                    let end = i + 2 <= last ? point(i + 2) : start
                    commands.append(.curve(p.0, p.1, second.0, second.1, end.0, end.1))
                    i += 3
                }
            }
            if let control = pending { commands.append(.quad(control.0, control.1, start.0, start.1)) }
            commands.append(.close)
        }
        return commands
    }
}

// MARK: - Drawing glyphs

@c(_CGContextSetFont)
public func CGContextSetFont(_ context: Ref?, _ font: Ref?) {
    guard let state = Fonts.state(font) else { return }
    Contexts.canvas(context)?.setFont(state.font)
}

/// Glyphs by index from the text position, each after the last's advance.
@c(_CGContextShowGlyphs)
public func CGContextShowGlyphs(_ context: Ref?, _ glyphs: UnsafePointer<UInt16>?, _ count: Int) {
    guard let glyphs, count > 0 else { return }
    let indexes = Array(UnsafeBufferPointer(start: glyphs, count: count))
    Contexts.paint(context) { $0.showGlyphs(indexes) }
}

@DarwinC("_CGContextShowGlyphsAtPoint")
public func CGContextShowGlyphsAtPoint(_ context: Ref?, _ x: CGFloat, _ y: CGFloat, _ glyphs: UnsafePointer<UInt16>?, _ count: Int) {
    CGContextSetTextPosition(context, x, y)
    CGContextShowGlyphs(context, glyphs, count)
}

/// Glyphs by index, each at its own position in text space.
@c(_CGContextShowGlyphsAtPositions)
public func CGContextShowGlyphsAtPositions(_ context: Ref?, _ glyphs: UnsafePointer<UInt16>?, _ positions: UnsafePointer<CGPoint>?, _ count: Int) {
    guard let glyphs, let positions, count > 0 else { return }
    let indexes = Array(UnsafeBufferPointer(start: glyphs, count: count))
    let points = (0..<count).map { (Double(positions[$0].x), Double(positions[$0].y)) }
    Contexts.paint(context) { $0.showGlyphs(indexes, at: points) }
}

// Glyphs are placed and smoothed as Cairo does, whatever is asked.

@c(_CGContextSetAllowsFontSubpixelPositioning) public func CGContextSetAllowsFontSubpixelPositioning(_ context: Ref?, _ value: Bool) {}
@c(_CGContextSetShouldSubpixelPositionFonts) public func CGContextSetShouldSubpixelPositionFonts(_ context: Ref?, _ value: Bool) {}
@c(_CGContextSetAllowsFontSubpixelQuantization) public func CGContextSetAllowsFontSubpixelQuantization(_ context: Ref?, _ value: Bool) {}
@c(_CGContextSetShouldSubpixelQuantizeFonts) public func CGContextSetShouldSubpixelQuantizeFonts(_ context: Ref?, _ value: Bool) {}
@c(_CGContextSetAllowsFontSmoothing) public func CGContextSetAllowsFontSmoothing(_ context: Ref?, _ value: Bool) {}
@c(_CGContextSetShouldSmoothFonts) public func CGContextSetShouldSmoothFonts(_ context: Ref?, _ value: Bool) {}

// MARK: - Images from encoded data

/// An image from PNG data; the decode array and interpolation are not used.
@c(_CGImageCreateWithPNGDataProvider)
public func CGImageCreateWithPNGDataProvider(_ provider: Ref?, _ decode: UnsafePointer<CGFloat>?, _ interpolate: Bool, _ intent: Int32) -> Ref? {
    guard let source = CGImageSourceCreateWithDataProvider(provider, nil) else { return nil }
    defer { ObjCRuntime.release(source) }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

/// An image from JPEG data.
@c(_CGImageCreateWithJPEGDataProvider)
public func CGImageCreateWithJPEGDataProvider(_ provider: Ref?, _ decode: UnsafePointer<CGFloat>?, _ interpolate: Bool, _ intent: Int32) -> Ref? {
    CGImageCreateWithPNGDataProvider(provider, decode, interpolate, intent)
}

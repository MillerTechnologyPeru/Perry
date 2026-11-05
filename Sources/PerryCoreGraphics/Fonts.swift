import CPerryGeometry
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
    /// The file a font made from data was written to, removed with it.
    let file: String?

    init(font: Silica.CGFont, file: String? = nil) {
        self.font = font
        self.file = file
    }

    deinit {
        if let file { unlink(file) }
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
        CGRect(origin: CGPoint(x: Double(x), y: Double(y)), size: CGSize(width: Double(width), height: Double(height)))
    }

    /// Where fonts made from data are written for FreeType to open.
    static var directory: String {
        getenv("PERRY_TMP").map { String(cString: $0) } ?? "/tmp"
    }
}

@c(_CGFontGetTypeID) public func CGFontGetTypeID() -> UInt { TypeIDs.font }

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

@c(_CGFontGetFontBBox)
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

@c(_CGContextShowGlyphsAtPoint)
public func CGContextShowGlyphsAtPoint(_ context: Ref?, _ x: Double, _ y: Double, _ glyphs: UnsafePointer<UInt16>?, _ count: Int) {
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
public func CGImageCreateWithPNGDataProvider(_ provider: Ref?, _ decode: UnsafePointer<Double>?, _ interpolate: Bool, _ intent: Int32) -> Ref? {
    guard let source = CGImageSourceCreateWithDataProvider(provider, nil) else { return nil }
    defer { ObjCRuntime.release(source) }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

/// An image from JPEG data.
@c(_CGImageCreateWithJPEGDataProvider)
public func CGImageCreateWithJPEGDataProvider(_ provider: Ref?, _ decode: UnsafePointer<Double>?, _ interpolate: Bool, _ intent: Int32) -> Ref? {
    CGImageCreateWithPNGDataProvider(provider, decode, interpolate, intent)
}

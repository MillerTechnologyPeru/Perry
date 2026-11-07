import CPerryGeometry
import Glibc
import PerryObjCInterop

// CoreText's font functions over CoreGraphics' fonts: a CTFont (a UIFont)
// is the CGFont FontConfig finds by its name, at its size. Metrics, glyphs,
// advances, bounds and outlines are the face's, through FreeType, scaled
// from its units to points. Fonts made from data are registered as they are
// made, so a descriptor of one names it.

enum CTFonts {
    typealias Ref = UnsafeMutableRawPointer?
    typealias Transform = UnsafePointer<CGAffineTransform>?

    nonisolated(unsafe) static var createWithFontName: (@convention(c) (Ref) -> Ref)?
    nonisolated(unsafe) static var unitsPerEm: (@convention(c) (Ref) -> Int32)?
    nonisolated(unsafe) static var ascent: (@convention(c) (Ref) -> Int32)?
    nonisolated(unsafe) static var descent: (@convention(c) (Ref) -> Int32)?
    nonisolated(unsafe) static var leading: (@convention(c) (Ref) -> Int32)?
    nonisolated(unsafe) static var glyphCount: (@convention(c) (Ref) -> Int)?
    nonisolated(unsafe) static var fontBBox: (@convention(c) (Ref) -> CGRect)?
    nonisolated(unsafe) static var glyphAdvances: (@convention(c) (Ref, UnsafePointer<UInt16>?, Int, UnsafeMutablePointer<Int32>?) -> Bool)?
    nonisolated(unsafe) static var glyphBBoxes: (@convention(c) (Ref, UnsafePointer<UInt16>?, Int, UnsafeMutablePointer<CGRect>?) -> Bool)?
    nonisolated(unsafe) static var glyphForCharacter: (@convention(c) (Ref, UInt32) -> UInt16)?
    nonisolated(unsafe) static var pathForGlyph: (@convention(c) (Ref, UInt16, CGFloat, Transform) -> Ref)?
    nonisolated(unsafe) static var copyPostScriptName: (@convention(c) (Ref) -> Ref)?
    nonisolated(unsafe) static var dataProviderCreateWithCFData: (@convention(c) (Ref) -> Ref)?

    /// Binds what CoreGraphics has; a missing one leaves its CoreText
    /// functions answering nothing.
    static func load(_ lookup: (String) -> UnsafeMutableRawPointer?) {
        func bind<T>(_ name: String) -> T? {
            (lookup("perry_native_" + name) ?? lookup("_" + name)).map { unsafeBitCast($0, to: T.self) }
        }
        createWithFontName = bind("CGFontCreateWithFontName")
        unitsPerEm = bind("CGFontGetUnitsPerEm")
        ascent = bind("CGFontGetAscent")
        descent = bind("CGFontGetDescent")
        leading = bind("CGFontGetLeading")
        glyphCount = bind("CGFontGetNumberOfGlyphs")
        fontBBox = bind("CGFontGetFontBBox")
        glyphAdvances = bind("CGFontGetGlyphAdvances")
        glyphBBoxes = bind("CGFontGetGlyphBBoxes")
        glyphForCharacter = bind("perry_cgfont_glyph_for_character")
        pathForGlyph = bind("perry_cgfont_create_path_for_glyph")
        copyPostScriptName = bind("CGFontCopyPostScriptName")
        dataProviderCreateWithCFData = bind("CGDataProviderCreateWithCFData")
    }

    /// The CGFont of each font name, made once.
    nonisolated(unsafe) private static var faces: [String: UnsafeMutableRawPointer] = [:]

    /// A system font's name is FontConfig's sans-serif.
    static func face(_ font: UIFont) -> UnsafeMutableRawPointer? {
        let name = font.state.name.hasPrefix(".") ? "sans-serif" : font.state.name
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
    static func scale(_ font: UIFont, _ face: UnsafeMutableRawPointer) -> CGFloat {
        let units = CGFloat(unitsPerEm?(face) ?? 1000)
        return font.state.pointSize / (units > 0 ? units : 1000)
    }

    static func font(_ object: UnsafeMutableRawPointer?) -> UIFont? {
        object.flatMap { NSObject(objCArgument: $0).as(UIFont.self) }
    }

    /// A descriptor naming the font made from a file's or data's provider,
    /// registered with FontConfig; nil when it isn't a font.
    static func descriptor(provider: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        guard let provider, let face = CG.fontCreateWithDataProvider(provider) else { return nil }
        defer { CG.fontRelease(face) }
        _ = CG.fontRegister?(face)
        guard let name = copyPostScriptName?(face) else { return nil }
        defer { ObjCRuntime.release(name) }
        let postScriptName = String(objCArgument: name)
        return UIFontDescriptor.make { $0.name = postScriptName }
    }
}

// MARK: - Fonts

/// The system font of the size; 0 is the type's default size.
@DarwinC("_CTFontCreateUIFontForLanguage")
public func CTFontCreateUIFontForLanguage(_ type: UInt32, _ size: CGFloat, _ language: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    ObjCRuntime.retain(UIFont.make(name: ".SFUI-Regular", size: size > 0 ? size : 13).objcObject)
}

/// The same font: its faces cover the string here as FontConfig matched them.
@DarwinC("_CTFontCreateForString")
public func CTFontCreateForString(_ font: UnsafeMutableRawPointer?, _ string: UnsafeMutableRawPointer?, _ range: PerryCFRange) -> UnsafeMutableRawPointer? {
    ObjCRuntime.retain(font)
}

@DarwinC("_CTFontCreateCopyWithSymbolicTraits")
public func CTFontCreateCopyWithSymbolicTraits(_ font: UnsafeMutableRawPointer?, _ size: CGFloat, _ matrix: UnsafeRawPointer?,
                                               _ value: UInt32, _ mask: UInt32) -> UnsafeMutableRawPointer? {
    guard let original = CTFonts.font(font) else { return nil }
    let state = original.state
    let traits = (state.traits & ~mask) | (value & mask)
    return ObjCRuntime.retain(UIFont.make(name: state.name, size: size > 0 ? size : state.pointSize, weight: state.weight,
                                          traits: traits, design: state.design).objcObject)
}


@c(_CTFontCopyFamilyName)
public func CTFontCopyFamilyName(_ font: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    CTFonts.font(font).flatMap { $0.familyName().objCOwnedReturnValue() }
}

@c(_CTFontCopyFullName)
public func CTFontCopyFullName(_ font: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    CTFonts.font(font).flatMap { $0.fontName().objCOwnedReturnValue() }
}

// MARK: - Metrics, in points

// CTFontGetSize, Ascent, Descent and Leading are CoreText.swift's, UIFont's.

@DarwinC("_CTFontGetBoundingBox")
public func CTFontGetBoundingBox(_ font: UnsafeMutableRawPointer?) -> CGRect {
    guard let font = CTFonts.font(font), let face = CTFonts.face(font), let box = CTFonts.fontBBox?(face) else { return .zero }
    let scale = CTFonts.scale(font, face)
    return CGRect(x: box.origin.x * scale, y: box.origin.y * scale, width: box.size.width * scale, height: box.size.height * scale)
}

@c(_CTFontGetGlyphCount)
public func CTFontGetGlyphCount(_ font: UnsafeMutableRawPointer?) -> Int {
    guard let font = CTFonts.font(font), let face = CTFonts.face(font) else { return 0 }
    return CTFonts.glyphCount?(face) ?? 0
}

// MARK: - Glyphs

/// Each UTF-16 unit's glyph; a surrogate pair's is at its first unit, with
/// 0 at its second. False if any character has none.
@c(_CTFontGetGlyphsForCharacters)
public func CTFontGetGlyphsForCharacters(_ font: UnsafeMutableRawPointer?, _ characters: UnsafePointer<UInt16>?,
                                         _ glyphs: UnsafeMutablePointer<UInt16>?, _ count: Int) -> Bool {
    guard let characters, let glyphs, count > 0 else { return false }
    guard let font = CTFonts.font(font), let face = CTFonts.face(font), let lookup = CTFonts.glyphForCharacter else {
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

/// The glyphs' advances, horizontal; their sum.
@DarwinC("_CTFontGetAdvancesForGlyphs")
public func CTFontGetAdvancesForGlyphs(_ font: UnsafeMutableRawPointer?, _ orientation: UInt32, _ glyphs: UnsafePointer<UInt16>?,
                                       _ advances: UnsafeMutablePointer<CGSize>?, _ count: Int) -> Double {
    guard let glyphs, count > 0, let font = CTFonts.font(font), let face = CTFonts.face(font) else { return 0 }
    var units = [Int32](repeating: 0, count: count)
    guard CTFonts.glyphAdvances?(face, glyphs, count, &units) == true else { return 0 }
    let scale = CTFonts.scale(font, face)
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
    guard let glyphs, count > 0, let font = CTFonts.font(font), let face = CTFonts.face(font) else { return .zero }
    var boxes = [CGRect](repeating: .zero, count: count)
    guard CTFonts.glyphBBoxes?(face, glyphs, count, &boxes) == true else { return .zero }
    let scale = CTFonts.scale(font, face)
    var union: CGRect?
    for (index, box) in boxes.enumerated() {
        let rect = CGRect(x: box.origin.x * scale, y: box.origin.y * scale, width: box.size.width * scale, height: box.size.height * scale)
        rects?[index] = rect
        union = union.map { u in
            let minX = min(u.origin.x, rect.origin.x), minY = min(u.origin.y, rect.origin.y)
            let maxX = max(u.origin.x + u.size.width, rect.origin.x + rect.size.width)
            let maxY = max(u.origin.y + u.size.height, rect.origin.y + rect.size.height)
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        } ?? rect
    }
    return union ?? .zero
}

@c(_CTFontCreatePathForGlyph)
public func CTFontCreatePathForGlyph(_ font: UnsafeMutableRawPointer?, _ glyph: UInt16,
                                     _ transform: UnsafePointer<CGAffineTransform>?) -> UnsafeMutableRawPointer? {
    guard let font = CTFonts.font(font), let face = CTFonts.face(font) else { return nil }
    return CTFonts.pathForGlyph?(face, glyph, CTFonts.scale(font, face), transform)
}

// MARK: - Collections and the font manager

/// A collection of descriptors is their array here, which matching answers.
@c(_CTFontCollectionCreateWithFontDescriptors)
public func CTFontCollectionCreateWithFontDescriptors(_ descriptors: UnsafeMutableRawPointer?, _ options: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    descriptors.map { ObjCRuntime.retain($0)! } ?? ObjCRuntime.retain(NSMutableArray.of([]).objcObject)
}

@c(_CTFontCollectionCreateMatchingFontDescriptors)
public func CTFontCollectionCreateMatchingFontDescriptors(_ collection: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    collection.map { ObjCRuntime.retain($0)! }
}

@c(_CTFontManagerCreateFontDescriptorsFromData)
public func CTFontManagerCreateFontDescriptorsFromData(_ data: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    let provider = data.flatMap { CTFonts.dataProviderCreateWithCFData?($0) }
    defer { if let provider { CG.dataProviderRelease(provider) } }
    let descriptor = CTFonts.descriptor(provider: provider)
    defer { ObjCRuntime.release(descriptor) }
    return ObjCRuntime.retain(NSMutableArray.of(descriptor.map { [NSObject($0)] } ?? []).objcObject)
}

@c(_CTFontManagerCreateFontDescriptorsFromURL)
public func CTFontManagerCreateFontDescriptorsFromURL(_ url: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let url, let provider = CG.dataProviderCreateWithURL(url) else { return nil }
    defer { CG.dataProviderRelease(provider) }
    guard let descriptor = CTFonts.descriptor(provider: provider) else { return nil }
    defer { ObjCRuntime.release(descriptor) }
    return ObjCRuntime.retain(NSMutableArray.of([NSObject(descriptor)]).objcObject)
}

/// Descriptors' fonts were registered when they were made: none fails, and
/// the handler hears so at once.
@c(_CTFontManagerRegisterFontDescriptors)
public func CTFontManagerRegisterFontDescriptors(_ descriptors: UnsafeMutableRawPointer?, _ scope: UInt32, _ enabled: Bool,
                                                 _ handler: UnsafeMutableRawPointer?) {
    // A block: its invoke function follows its isa, flags and reserved words.
    typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, Bool) -> Bool
    guard let handler, let invoke = handler.load(fromByteOffset: MemoryLayout<UnsafeRawPointer>.size + 8, as: UnsafeRawPointer?.self) else { return }
    let errors = NSMutableArray.of([])
    _ = unsafeBitCast(invoke, to: Invoke.self)(handler, errors.objcObject, true)
}

// MARK: - Lines

/// The line's typographic box: its width, from the descent to the ascent.
@DarwinC("_CTLineGetBoundsWithOptions")
public func CTLineGetBoundsWithOptions(_ line: UnsafeMutableRawPointer?, _ options: UInt) -> CGRect {
    var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
    let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
    return CGRect(x: 0, y: -descent, width: CGFloat(width), height: ascent + descent)
}

import CPerryGeometry
import Glibc
import PerryObjCInterop

// CoreText's typesetting as UIKit's string drawing does it: a framesetter
// holds an attributed string, a frame that string laid out in a path's
// bounding box, and drawing a frame draws its lines in its first run's
// font, color and paragraph style, as NSAttributedString draws. Frames are
// drawn in CoreText's coordinates, y up, as apps flip their contexts for.

/// A framesetter's or frame's attributed string, and a frame's box.
final class TypesetState: ObjectState {
    var string: NSAttributedString?
    var box: CGRect = .zero
    required init() {}
}

enum Typesetting {
    static let states = StateTable<TypesetState>()

    /// The state of a framesetter or frame that holds a string.
    static func state(_ object: UnsafeMutableRawPointer?) -> (state: TypesetState, string: NSAttributedString)? {
        guard let object else { return nil }
        let state = states[object]
        return state.string.map { (state, $0) }
    }

    /// A new object of `cls` holding `string` in `box`, +1.
    static func make(_ cls: ObjCClass, _ string: NSAttributedString, box: CGRect = .zero) -> UnsafeMutableRawPointer {
        let object = cls.object.allocated().initialized()
        let state = states[object.objcObject]
        (state.string, state.box) = (string, box)
        return ObjCRuntime.retain(object.objcObject)!
    }
}

@ObjCClass("__NSCFFramesetter")
final class CTFramesetter: NSObject {
    @ObjCMethod("dealloc")
    func dealloc() {
        Typesetting.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CTFramesetter.objCClass.pointer)
    }
}

@ObjCClass("__NSCFFrame")
final class CTFrame: NSObject {
    @ObjCMethod("dealloc")
    func dealloc() {
        Typesetting.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CTFrame.objCClass.pointer)
    }
}

// MARK: Fonts and paragraph styles

/// The font of that PostScript or family name, or the system font.
@c(_CTFontCreateWithName)
public func CTFontCreateWithName(_ name: UnsafeMutableRawPointer?, _ size: CGFloat, _ matrix: UnsafeRawPointer?) -> UnsafeMutableRawPointer? {
    let fontName = name.map { String(objCArgument: $0) } ?? ".SFUI-Regular"
    let font = UIFont.make(name: fontName, size: size > 0 ? size : 12, weight: 0)
    return ObjCRuntime.retain(font.objcObject)
}

/// CTParagraphStyleSetting: the specifier, the value's size and the value.
struct CTParagraphStyleSetting {
    var spec: UInt32
    var valueSize: Int
    var value: UnsafeRawPointer?
}

/// A paragraph style from CoreText's settings: alignment (its order is
/// left, right, center, justified, natural; NSTextAlignment's is left,
/// center, right), line breaking, spacing and indents.
@c(_CTParagraphStyleCreate)
public func CTParagraphStyleCreate(_ settings: UnsafeRawPointer?, _ count: Int) -> UnsafeMutableRawPointer? {
    let style = NSMutableParagraphStyle.objCClass.object.allocated().initialized().unsafeCast(to: NSMutableParagraphStyle.self)
    let list = settings?.assumingMemoryBound(to: CTParagraphStyleSetting.self)
    for index in 0..<max(count, 0) {
        guard let setting = list?[index], let value = setting.value else { continue }
        func float() -> CGFloat { setting.valueSize >= 8 ? value.load(as: CGFloat.self) : 0 }
        switch setting.spec {
        case 0:     // alignment, a uint8_t
            let alignment = Int(value.load(as: UInt8.self))
            style.setAlignment([0, 2, 1, 3, 4][min(alignment, 4)])
        case 6:     // line break mode, a uint8_t
            style.setLineBreakMode(Int(value.load(as: UInt8.self)))
        case 1: style.setFirstLineHeadIndent(float())
        case 10: style.setParagraphSpacing(float())
        case 11, 13: style.setLineSpacing(float())     // line spacing, or the maximum
        default: break
        }
    }
    return ObjCRuntime.retain(style.objcObject)
}

// MARK: Framesetters

@c(_CTFramesetterCreateWithAttributedString)
public func CTFramesetterCreateWithAttributedString(_ string: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let string else { return nil }
    let copy = NSObject(objCArgument: string).unsafeCast(to: NSAttributedString.self)
    return Typesetting.make(CTFramesetter.objCClass, copy)
}

/// The size the text takes within `constraints`, all of it.
@c(_CTFramesetterSuggestFrameSizeWithConstraints)
public func CTFramesetterSuggestFrameSizeWithConstraints(_ framesetter: UnsafeMutableRawPointer?, _ range: PerryCFRange, _ attributes: UnsafeMutableRawPointer?,
                                                         _ constraints: CGSize, _ fitRange: UnsafeMutablePointer<PerryCFRange>?) -> CGSize {
    guard let (_, string) = Typesetting.state(framesetter) else { return .zero }
    let width = constraints.width > 0 && constraints.width < 1e8 ? constraints.width : .greatestFiniteMagnitude
    let height = constraints.height > 0 && constraints.height < 1e8 ? constraints.height : .greatestFiniteMagnitude
    let layout = AttributedLayout(string, size: CGSize(width: width, height: height), lineLimit: 0)
    fitRange?.pointee = PerryCFRange(location: 0, length: Int(string.length()))
    return CGSize(width: ceil(layout.size.width), height: ceil(layout.size.height))
}

/// The text laid out in the path's bounding box.
@c(_CTFramesetterCreateFrame)
public func CTFramesetterCreateFrame(_ framesetter: UnsafeMutableRawPointer?, _ range: PerryCFRange, _ path: UnsafeMutableRawPointer?,
                                     _ attributes: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let (_, string) = Typesetting.state(framesetter) else { return nil }
    return Typesetting.make(CTFrame.objCClass, string, box: path.map { CG.pathGetBoundingBox($0) } ?? .zero)
}

/// Draws the frame's lines from the top of its box: in CoreText's
/// coordinates, y up, so flipped to UIKit's to draw them upright. A run
/// colored from the context (kCTForegroundColorFromContextAttributeName)
/// draws in its fill color and text drawing mode, which outlining apps set.
/// The color a string's first run draws in: its NSColor, else CoreText's
/// CGColor (kCTForegroundColorAttributeName), or nil to draw in the
/// context's fill color (kCTForegroundColorFromContextAttributeName).
private func runColor(_ string: NSAttributedString, _ layout: AttributedLayout) -> (color: UIColor?, fromContext: Bool) {
    let attributes = string.length() > 0 ? string.attributes(at: 0, effectiveRange: nil) : nil
    if attributes?.object(forKey: "CTForegroundColorFromContext") != nil { return (nil, true) }
    if attributes?.object(forKey: "NSColor") == nil, let cgColor = attributes?.object(forKey: "CTForegroundColor") {
        return (UIColor.color(UIColor.objCClass, cgColor: cgColor.objcObject), false)
    }
    return (layout.color, false)
}

@c(_CTFrameDraw)
public func CTFrameDraw(_ frame: UnsafeMutableRawPointer?, _ context: UnsafeMutableRawPointer?) {
    guard let (state, string) = Typesetting.state(frame), let context else { return }
    let box = state.box
    let layout = AttributedLayout(string, size: box.size, lineLimit: 0)
    let (color, fromContext) = runColor(string, layout)
    Graphics.push(context)
    defer { Graphics.pop() }
    CG.saveGState(context)
    defer { CG.restoreGState(context) }
    CG.translateCTM(context, 0, box.minY + box.maxY)
    CG.scaleCTM(context, 1, -1)
    let lineHeight = Text.lineHeight(layout.font)
    for (index, line) in layout.lines.enumerated() {
        let width = Text.size(line, font: layout.font).width
        let x = layout.alignment == 1 ? box.minX + (box.width - width) / 2 : layout.alignment == 2 ? box.maxX - width : box.minX
        Text.draw(line, at: CGPoint(x: x, y: box.minY + CGFloat(index) * lineHeight), font: layout.font, color: color, keepingMode: fromContext)
    }
}

@c(_CTFrameGetStringRange)
public func CTFrameGetStringRange(_ frame: UnsafeMutableRawPointer?) -> PerryCFRange {
    PerryCFRange(location: 0, length: Int(Typesetting.state(frame)?.string.length() ?? 0))
}

@c(_CTFrameGetVisibleStringRange)
public func CTFrameGetVisibleStringRange(_ frame: UnsafeMutableRawPointer?) -> PerryCFRange { CTFrameGetStringRange(frame) }

@c(_CTFramesetterGetTypeID) public func CTFramesetterGetTypeID() -> UInt { 0x50_04 }
@c(_CTFrameGetTypeID) public func CTFrameGetTypeID() -> UInt { 0x50_05 }
@c(_CTParagraphStyleGetTypeID) public func CTParagraphStyleGetTypeID() -> UInt { 0x50_06 }

/// CoreText's string attribute keys, with Darwin's values.
@ObjCConstants
enum CoreTextAttributeKeys {
    static let kCTKernAttributeName = "NSKern"
    static let kCTParagraphStyleAttributeName = "NSParagraphStyle"
    static let kCTForegroundColorFromContextAttributeName = "CTForegroundColorFromContext"
    static let kCTStrokeWidthAttributeName = "NSStrokeWidth"
    static let kCTStrokeColorAttributeName = "NSStrokeColor"
    static let kCTUnderlineStyleAttributeName = "NSUnderline"
    static let kCTLigatureAttributeName = "NSLigature"
}

/// NSTextAlignment (left, center, right, justified, natural) as
/// CTTextAlignment (left, right, center, justified, natural).
@c(_NSTextAlignmentToCTTextAlignment)
public func NSTextAlignmentToCTTextAlignment(_ alignment: Int) -> UInt8 { [0, 2, 1, 3, 4][min(max(alignment, 0), 4)] }

@c(_NSTextAlignmentFromCTTextAlignment)
public func NSTextAlignmentFromCTTextAlignment(_ alignment: UInt8) -> Int { [0, 2, 1, 3, 4][min(Int(alignment), 4)] }

// MARK: Lines

/// A line of the whole string, in its first run's font and color.
@ObjCClass("__NSCFLine")
final class CTLine: NSObject {
    @ObjCMethod("dealloc")
    func dealloc() {
        Typesetting.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CTLine.objCClass.pointer)
    }
}

@c(_CTLineGetTypeID) public func CTLineGetTypeID() -> UInt { 0x50_06 }

@c(_CTLineCreateWithAttributedString)
public func CTLineCreateWithAttributedString(_ string: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let string else { return nil }
    let copy = NSObject(objCArgument: string).unsafeCast(to: NSAttributedString.self)
    return Typesetting.make(CTLine.objCClass, copy)
}

/// The line's text on one line, with no width limit.
private func lineLayout(_ line: UnsafeMutableRawPointer?) -> AttributedLayout? {
    guard let (_, string) = Typesetting.state(line) else { return nil }
    return AttributedLayout(string, size: CGSize(width: .greatestFiniteMagnitude, height: .greatestFiniteMagnitude), lineLimit: 1)
}

/// The width, and the font's ascent, descent and leading.
@c(_CTLineGetTypographicBounds)
public func CTLineGetTypographicBounds(_ line: UnsafeMutableRawPointer?, _ ascent: UnsafeMutablePointer<CGFloat>?,
                                       _ descent: UnsafeMutablePointer<CGFloat>?, _ leading: UnsafeMutablePointer<CGFloat>?) -> Double {
    guard let layout = lineLayout(line) else { return 0 }
    ascent?.pointee = layout.font.ascender()
    descent?.pointee = -layout.font.descender()
    leading?.pointee = layout.font.leading()
    return Double(layout.lines.first.map { Text.size($0, font: layout.font).width } ?? 0)
}

/// The box from the baseline down by the descent to up by the ascent.
@c(_CTLineGetImageBounds)
public func CTLineGetImageBounds(_ line: UnsafeMutableRawPointer?, _ context: UnsafeMutableRawPointer?) -> CGRect {
    guard lineLayout(line) != nil else { return .zero }
    var ascent: CGFloat = 0, descent: CGFloat = 0
    let width = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
    return CGRect(x: 0, y: -descent, width: CGFloat(width), height: ascent + descent)
}

@c(_CTLineGetStringRange)
public func CTLineGetStringRange(_ line: UnsafeMutableRawPointer?) -> PerryCFRange {
    PerryCFRange(location: 0, length: Int(Typesetting.state(line)?.string.length() ?? 0))
}

@c(_CTLineGetGlyphCount)
public func CTLineGetGlyphCount(_ line: UnsafeMutableRawPointer?) -> Int {
    Int(Typesetting.state(line)?.string.length() ?? 0)
}

/// The x of the caret before the character at `index`: the width of the
/// text before it.
@DarwinC("_CTLineGetOffsetForStringIndex")
public func CTLineGetOffsetForStringIndex(_ line: UnsafeMutableRawPointer?, _ index: Int, _ secondary: UnsafeMutablePointer<CGFloat>?) -> CGFloat {
    guard let layout = lineLayout(line), let text = layout.lines.first else { return 0 }
    let units = Array(text.utf16)
    let prefix = String(decoding: units.prefix(max(0, min(index, units.count))), as: UTF16.self)
    let offset = Text.size(prefix, font: layout.font).width
    secondary?.pointee = offset
    return offset
}

/// The index of the character boundary nearest to `position`'s x.
@c(_CTLineGetStringIndexForPosition)
public func CTLineGetStringIndexForPosition(_ line: UnsafeMutableRawPointer?, _ position: CGPoint) -> Int {
    guard let layout = lineLayout(line), let text = layout.lines.first else { return 0 }
    var index = 0
    var previous: CGFloat = 0
    for character in text {
        let next = previous + Text.size(String(character), font: layout.font).width
        if position.x < (previous + next) / 2 { return index }
        index += character.utf16.count
        previous = next
    }
    return index
}

/// A tab stop, as an NSTextTab: CTTextTabRef and NSTextTab are toll-free
/// bridged. CTTextAlignment: left 0, right 1, center 2.
@DarwinC("_CTTextTabCreate")
public func CTTextTabCreate(_ alignment: UInt8, _ location: Double, _ options: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let cls = "NSTextTab".withCString({ ObjCRuntime.functions.getClass($0) }).map({ UnsafeMutableRawPointer($0) }) else { return nil }
    typealias Alloc = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer) -> UnsafeMutableRawPointer?
    typealias Initialize = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer, Int, Double, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
    let object = unsafeBitCast(ObjCRuntime.msgSend, to: Alloc.self)(cls, ObjCRuntime.selector("alloc"))
    // NSTextAlignment: left 0, center 1, right 2.
    let textAlignment = [0, 2, 1, 3, 4][min(Int(alignment), 4)]
    return unsafeBitCast(ObjCRuntime.msgSend, to: Initialize.self)(object, ObjCRuntime.selector("initWithTextAlignment:location:options:"),
                                                                   textAlignment, location, options)
}

/// Draws the line with its baseline at the context's text position, in
/// CoreText's coordinates, y up: flipped there to draw it upright.
@c(_CTLineDraw)
public func CTLineDraw(_ line: UnsafeMutableRawPointer?, _ context: UnsafeMutableRawPointer?) {
    guard let (_, string) = Typesetting.state(line), let layout = lineLayout(line), let text = layout.lines.first, let context else { return }
    let (color, fromContext) = runColor(string, layout)
    let position = CG.getTextPosition(context)
    Graphics.push(context)
    defer { Graphics.pop() }
    CG.saveGState(context)
    defer { CG.restoreGState(context) }
    CG.translateCTM(context, position.x, position.y)
    CG.scaleCTM(context, 1, -1)
    Text.draw(text, at: CGPoint(x: 0, y: -layout.font.ascender()), font: layout.font, color: color, keepingMode: fromContext)
}

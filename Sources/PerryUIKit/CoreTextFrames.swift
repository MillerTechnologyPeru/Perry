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
@c(_CTFrameDraw)
public func CTFrameDraw(_ frame: UnsafeMutableRawPointer?, _ context: UnsafeMutableRawPointer?) {
    guard let (state, string) = Typesetting.state(frame), let context else { return }
    let box = state.box
    let layout = AttributedLayout(string, size: box.size, lineLimit: 0)
    let attributes = string.length() > 0 ? string.attributes(at: 0, effectiveRange: nil) : nil
    let fromContext = attributes?.object(forKey: "CTForegroundColorFromContext") != nil
    var color: UIColor? = layout.color
    if fromContext {
        color = nil
    } else if attributes?.object(forKey: "NSColor") == nil, let cgColor = attributes?.object(forKey: "CTForegroundColor") {
        color = UIColor.color(UIColor.objCClass, cgColor: cgColor.objcObject)
    }
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

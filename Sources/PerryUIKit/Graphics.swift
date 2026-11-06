import CPerryGeometry
import PerryObjCInterop

// UIKit's graphics contexts: the stack of current contexts that UIColor,
// UIBezierPath and UIImage draw into, image contexts, and the image
// renderers built on them. Contexts are bitmaps in UIKit's coordinates.

enum Graphics {
    /// The current contexts, the last on top; each retained.
    nonisolated(unsafe) static var contexts: [CGRef] = []
    /// The image contexts begun and not ended, with their scales.
    nonisolated(unsafe) static var imageContexts: [(context: CGRef, scale: CGFloat)] = []

    static var current: CGRef? { contexts.last }

    static func push(_ context: CGRef) { contexts.append(ObjCRuntime.retain(context)!) }

    static func pop() {
        guard let context = contexts.popLast() else { return }
        CG.release(context)
    }

    /// Makes `context` current while `body` draws.
    static func drawing<Result>(in context: CGRef, _ body: () -> Result) -> Result {
        push(context)
        defer { pop() }
        return body()
    }

    /// Fills `rect` in the current context with `blendMode`.
    static func fill(_ rect: CGRect, blendMode: Int32) {
        guard let context = current else { return }
        CG.saveGState(context)
        CG.setBlendMode(context, blendMode)
        CG.fillRect(context, rect)
        CG.restoreGState(context)
    }

    static func frame(_ rect: CGRect, blendMode: Int32) {
        guard let context = current else { return }
        CG.saveGState(context)
        CG.setBlendMode(context, blendMode)
        CG.setLineWidth(context, 1)
        CG.strokeRect(context, CGRect(x: rect.minX + 0.5, y: rect.minY + 0.5, width: rect.width - 1, height: rect.height - 1))
        CG.restoreGState(context)
    }
}

/// kCGBlendModeNormal and kCGBlendModeCopy.
private let normalBlend: Int32 = 0
private let copyBlend: Int32 = 17

@c(_UIGraphicsGetCurrentContext)
public func UIGraphicsGetCurrentContext() -> UnsafeMutableRawPointer? { Graphics.current }

@c(_UIGraphicsPushContext)
public func UIGraphicsPushContext(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    Graphics.push(context)
}

@c(_UIGraphicsPopContext)
public func UIGraphicsPopContext() { Graphics.pop() }

@DarwinC("_UIGraphicsBeginImageContext")
public func UIGraphicsBeginImageContext(_ size: CGSize) { UIGraphicsBeginImageContextWithOptions(size, false, 1) }

/// A scale of 0 is the screen's.
@DarwinC("_UIGraphicsBeginImageContextWithOptions")
public func UIGraphicsBeginImageContextWithOptions(_ size: CGSize, _ opaque: Bool, _ scale: CGFloat) {
    let scale = scale > 0 ? scale : Screen.scale
    guard let context = CG.makeContext(size: size, scale: scale, opaque: opaque) else { return }
    Graphics.imageContexts.append((context, scale))
    Graphics.push(context)
    CG.release(context)
}

@c(_UIGraphicsGetImageFromCurrentImageContext)
public func UIGraphicsGetImageFromCurrentImageContext() -> UnsafeMutableRawPointer? {
    guard let (context, scale) = Graphics.imageContexts.last, let image = CG.bitmapContextCreateImage(context) else { return nil }
    defer { CG.release(image) }
    return UIImage.make(cgImage: image, scale: scale).objCReturnValue()
}

@c(_UIGraphicsEndImageContext)
public func UIGraphicsEndImageContext() {
    guard let (context, _) = Graphics.imageContexts.popLast() else { return }
    if let index = Graphics.contexts.lastIndex(of: context) {
        Graphics.contexts.remove(at: index)
        CG.release(context)
    }
}

@DarwinC("_UIRectFill")
public func UIRectFill(_ rect: CGRect) { Graphics.fill(rect, blendMode: copyBlend) }

@DarwinC("_UIRectFillUsingBlendMode")
public func UIRectFillUsingBlendMode(_ rect: CGRect, _ blendMode: Int32) { Graphics.fill(rect, blendMode: blendMode) }

@DarwinC("_UIRectFrame")
public func UIRectFrame(_ rect: CGRect) { Graphics.frame(rect, blendMode: copyBlend) }

@DarwinC("_UIRectFrameUsingBlendMode")
public func UIRectFrameUsingBlendMode(_ rect: CGRect, _ blendMode: Int32) { Graphics.frame(rect, blendMode: blendMode) }

@DarwinC("_UIRectClip")
public func UIRectClip(_ rect: CGRect) {
    guard let context = Graphics.current else { return }
    CG.clipToRect(context, rect)
}

// MARK: - Renderers

final class RendererFormatState: ObjectState {
    var bounds = CGRect.zero
    var scale = Screen.scale
    var opaque = false
    /// UIGraphicsImageRendererFormatRange: automatic 0.
    var preferredRange = 0
}

@ObjCClass("UIGraphicsRendererFormat")
open class UIGraphicsRendererFormat: NSObject {
    static let states = StateTable<RendererFormatState>()
    var state: RendererFormatState { UIGraphicsRendererFormat.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        UIGraphicsRendererFormat.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIGraphicsRendererFormat.objCClass.pointer)
    }

    /// A new format each time: formats are mutable.
    @ObjCClassMethod("defaultFormat")
    static func defaultFormat(_ cls: ObjCClass) -> NSObject { cls.object.allocated().unsafeCast(to: NSObject.self) }

    @ObjCClassMethod("preferredFormat")
    static func preferredFormat(_ cls: ObjCClass) -> NSObject { defaultFormat(cls) }

    @ObjCMethod("bounds") func bounds() -> CGRect { state.bounds }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
        let copy = objCClass.object.allocated().unsafeCast(to: UIGraphicsRendererFormat.self)
        let (from, to) = (state, copy.state)
        (to.bounds, to.scale, to.opaque, to.preferredRange) = (from.bounds, from.scale, from.opaque, from.preferredRange)
        return ObjCRuntime.retain(copy.objcObject)!
    }
}

@ObjCClass("UIGraphicsImageRendererFormat")
open class UIGraphicsImageRendererFormat: UIGraphicsRendererFormat {
    @ObjCClassMethod("formatForTraitCollection:")
    static func format(_ cls: ObjCClass, for traits: NSObject?) -> NSObject { defaultFormat(cls) }

    @ObjCMethod("scale") func scale() -> CGFloat { state.scale }
    @ObjCMethod("setScale:") func setScale(_ scale: CGFloat) { state.scale = scale }
    @ObjCMethod("opaque") func opaque() -> Bool { state.opaque }
    @ObjCMethod("setOpaque:") func setOpaque(_ opaque: Bool) { state.opaque = opaque }
    @ObjCMethod("preferredRange") func preferredRange() -> Int { state.preferredRange }
    @ObjCMethod("setPreferredRange:") func setPreferredRange(_ range: Int) { state.preferredRange = range }
    @ObjCMethod("prefersExtendedRange") func prefersExtendedRange() -> Bool { state.preferredRange == 1 }
    @ObjCMethod("setPrefersExtendedRange:") func setPrefersExtendedRange(_ extended: Bool) { state.preferredRange = extended ? 1 : 2 }
}

final class RendererContextState: ObjectState {
    var context: CGRef?
    var format: NSObject?
    var scale: CGFloat = 1

    deinit { if let context { CG.release(context) } }
}

@ObjCClass("UIGraphicsRendererContext")
open class UIGraphicsRendererContext: NSObject {
    static let states = StateTable<RendererContextState>()
    var state: RendererContextState { UIGraphicsRendererContext.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        UIGraphicsRendererContext.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIGraphicsRendererContext.objCClass.pointer)
    }

    @ObjCMethod("CGContext") func cgContext() -> UnsafeMutableRawPointer? { state.context }
    @ObjCMethod("format") func format() -> NSObject? { state.format }

    @ObjCMethod("fillRect:") func fill(_ rect: CGRect) { fill(rect, blendMode: normalBlend) }

    @ObjCMethod("fillRect:blendMode:")
    func fill(_ rect: CGRect, blendMode: Int32) {
        guard let context = state.context else { return }
        CG.saveGState(context)
        CG.setBlendMode(context, blendMode)
        CG.fillRect(context, rect)
        CG.restoreGState(context)
    }

    @ObjCMethod("strokeRect:") func stroke(_ rect: CGRect) { stroke(rect, blendMode: normalBlend) }

    @ObjCMethod("strokeRect:blendMode:")
    func stroke(_ rect: CGRect, blendMode: Int32) {
        guard let context = state.context else { return }
        CG.saveGState(context)
        CG.setBlendMode(context, blendMode)
        CG.strokeRect(context, rect)
        CG.restoreGState(context)
    }

    @ObjCMethod("clipToRect:")
    func clip(to rect: CGRect) {
        guard let context = state.context else { return }
        CG.clipToRect(context, rect)
    }
}

@ObjCClass("UIGraphicsImageRendererContext")
open class UIGraphicsImageRendererContext: UIGraphicsRendererContext {
    /// The image drawn so far.
    @ObjCMethod("currentImage")
    func currentImage() -> UIImage? {
        guard let context = state.context, let image = CG.bitmapContextCreateImage(context) else { return nil }
        defer { CG.release(image) }
        return UIImage.make(cgImage: image, scale: state.scale)
    }
}

final class RendererState: ObjectState {
    var bounds = CGRect.zero
    var format: UIGraphicsRendererFormat?
}

@ObjCClass("UIGraphicsRenderer")
open class UIGraphicsRenderer: NSObject {
    static let states = StateTable<RendererState>()
    var state: RendererState { UIGraphicsRenderer.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        UIGraphicsRenderer.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIGraphicsRenderer.objCClass.pointer)
    }

    @ObjCMethod("initWithBounds:")
    func initialize(bounds: CGRect) -> Self { initialize(bounds: bounds, format: nil) }

    /// Keeps a copy of the format, with the renderer's bounds.
    @ObjCMethod("initWithBounds:format:")
    func initialize(bounds: CGRect, format: UIGraphicsRendererFormat?) -> Self {
        let copy = (format ?? UIGraphicsImageRendererFormat.objCClass.object.allocated().unsafeCast(to: UIGraphicsRendererFormat.self))
            .copied().unsafeCast(to: UIGraphicsRendererFormat.self)
        copy.state.bounds = bounds
        state.bounds = bounds
        state.format = copy
        return self
    }

    @ObjCMethod("format") func format() -> NSObject? { state.format }
    @ObjCMethod("allowsImageOutput") func allowsImageOutput() -> Bool { true }
}

@ObjCClass("UIGraphicsImageRenderer")
open class UIGraphicsImageRenderer: UIGraphicsRenderer {
    @ObjCMethod("initWithSize:")
    func initialize(size: CGSize) -> Self { initialize(bounds: CGRect(origin: .zero, size: size), format: nil) }

    @ObjCMethod("initWithSize:format:")
    func initialize(size: CGSize, format: UIGraphicsRendererFormat?) -> Self {
        initialize(bounds: CGRect(origin: .zero, size: size), format: format)
    }

    /// Runs `actions` with a renderer context for a new bitmap, which is
    /// current meanwhile, and returns the bitmap's image.
    private func render(_ actions: ObjCBlock) -> (image: Owned, scale: CGFloat)? {
        let bounds = state.bounds
        let format = state.format?.state ?? RendererFormatState()
        let scale = format.scale > 0 ? format.scale : Screen.scale
        guard let context = CG.makeContext(size: bounds.size, scale: scale, opaque: format.opaque) else { return nil }
        CG.translateCTM(context, -bounds.minX, -bounds.minY)
        let rendererContext = UIGraphicsImageRendererContext.objCClass.object.allocated()
            .unsafeCast(to: UIGraphicsImageRendererContext.self)
        rendererContext.state.context = context
        rendererContext.state.format = state.format
        rendererContext.state.scale = scale
        typealias Actions = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?) -> Void
        Graphics.drawing(in: context) {
            actions.function(as: Actions.self)(actions.object, rendererContext.objcObject)
        }
        return CG.bitmapContextCreateImage(context).map { (Owned($0), scale) }
    }

    @ObjCMethod("imageWithActions:")
    func image(actions: ObjCBlock) -> UIImage? {
        render(actions).map { UIImage.make(cgImage: $0.image.object, scale: $0.scale) }
    }

    @ObjCMethod("PNGDataWithActions:")
    func pngData(actions: ObjCBlock) -> NSObject? {
        render(actions).flatMap { UIImage.encode($0.image.object, type: "public.png") }
    }

    @ObjCMethod("JPEGDataWithCompressionQuality:actions:")
    func jpegData(compressionQuality quality: CGFloat, actions: ObjCBlock) -> NSObject? {
        guard let rendered = render(actions) else { return nil }
        let properties = NSMutableDictionary.empty()
        properties.set(NSNumber.make(double: Double(quality)), forKey: "kCGImageDestinationLossyCompressionQuality")
        return UIImage.encode(rendered.image.object, type: "public.jpeg", properties: properties)
    }
}

/// UIGraphicsRenderer's private -pushContext: and -popContext:, which make
/// a graphics context object's CGContext current and restore the one
/// before. Callers take the implementations and call them with no
/// receiver, so they are C functions that do not use one.
enum RendererContexts {
    typealias Function = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Bool

    nonisolated(unsafe) static let push: Function = { _, _, context in
        guard let context else { return false }
        typealias Get = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> UnsafeMutableRawPointer?
        let cgContext = unsafeBitCast(ObjCRuntime.msgSend, to: Get.self)(context, ObjCRuntime.selector("CGContext"))
        UIGraphicsPushContext(cgContext)
        return cgContext != nil
    }

    nonisolated(unsafe) static let pop: Function = { _, _, _ in
        UIGraphicsPopContext()
        return true
    }

    static func install() {
        let renderer = UIGraphicsRenderer.objCClass
        renderer.addMethod("pushContext:", types: "B24@0:8@16", implementation: unsafeBitCast(push, to: UnsafeRawPointer.self), isClassMethod: false)
        renderer.addMethod("popContext:", types: "B24@0:8@16", implementation: unsafeBitCast(pop, to: UnsafeRawPointer.self), isClassMethod: false)
    }
}

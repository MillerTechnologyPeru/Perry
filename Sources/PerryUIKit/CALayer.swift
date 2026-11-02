import CPerryGeometry
import Glibc
import PerryObjCInterop

// QuartzCore's CALayer, which the loader maps to UIKit: a layer tree with
// geometry and appearance, rendered through CoreGraphics. Each view has a
// layer, whose delegate it is; a view's geometry is its layer's. There is
// no animation: changes show at once.

final class LayerState: ObjectState {
    var bounds = CGRect.zero
    var position = CGPoint.zero
    var anchorPoint = CGPoint(x: 0.5, y: 0.5)
    var zPosition: CGFloat = 0
    var transform = CGAffineTransform.identity
    var hidden = false
    var opacity: Float = 1
    var masksToBounds = false
    var cornerRadius: CGFloat = 0
    /// CACornerMask: all four corners.
    var maskedCorners: UInt = 0xf
    var borderWidth: CGFloat = 0
    var backgroundColor: CGRef?
    var borderColor: CGRef?
    var shadowColor: CGRef?
    var shadowOpacity: Float = 0
    var shadowOffset = CGSize(width: 0, height: -3)
    var shadowRadius: CGFloat = 3
    var contents: NSObject?
    var contentsScale: CGFloat = 1
    var contentsGravity = "resize"
    var name: String?
    var isOpaque = false
    var needsDisplayOnBoundsChange = false
    var sublayers: [CALayer] = []
    /// The superlayer, which retains this layer; not retained.
    var superlayer: UnsafeMutableRawPointer?
    /// Not retained.
    var delegate: UnsafeMutableRawPointer?
    var mask: CALayer?
    var needsDisplay = false
    var needsLayout = true
    /// What -display drew, and the size it drew at.
    var backing: CGRef?
    var backingSize = CGSize.zero
    var values: [String: NSObject] = [:]

    deinit {
        for color in [backgroundColor, borderColor, shadowColor, backing] { if let color { CG.release(color) } }
    }

    /// The frame in the superlayer: the bounds around the position, at the
    /// anchor point, through the transform.
    var frame: CGRect {
        get {
            let local = CGRect(x: -anchorPoint.x * bounds.width, y: -anchorPoint.y * bounds.height, width: bounds.width, height: bounds.height)
            let rect = transform.isIdentity ? local : transform.apply(local)
            return CGRect(x: rect.minX + position.x, y: rect.minY + position.y, width: rect.width, height: rect.height)
        }
        set {
            if transform.isIdentity {
                bounds.size = newValue.size
            } else {
                // The size before the transform whose transformed box is the frame.
                let unit = transform.apply(CGRect(x: 0, y: 0, width: 1, height: 1))
                if unit.width > 0, unit.height > 0 {
                    bounds.size = CGSize(width: newValue.width / unit.width, height: newValue.height / unit.height)
                }
            }
            position = CGPoint(x: newValue.minX + anchorPoint.x * newValue.width, y: newValue.minY + anchorPoint.y * newValue.height)
        }
    }

    /// From this layer's coordinates to its superlayer's.
    var toSuperlayer: CGAffineTransform {
        let anchor = CGPoint(x: bounds.minX + anchorPoint.x * bounds.width, y: bounds.minY + anchorPoint.y * bounds.height)
        return CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: -anchor.x, ty: -anchor.y)
            .concatenating(transform)
            .concatenating(CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: position.x, ty: position.y))
    }

    static func setColor(_ slot: inout CGRef?, _ color: CGRef?) {
        let retained = ObjCRuntime.retain(color)
        if let old = slot { CG.release(old) }
        slot = retained
    }
}

@ObjCClass("CALayer")
open class CALayer: NSObject {
    static let states = StateTable<LayerState>()
    var state: LayerState { CALayer.states[objcObject] }

    static func wrap(_ object: UnsafeMutableRawPointer) -> CALayer { CALayer(objcObject: object, ownership: .retain) }

    @ObjCClassMethod("layer")
    static func layer(_ cls: ObjCClass) -> NSObject { cls.object.allocated().initializeLayer() }

    @ObjCMethod("init")
    func initialize() -> Self {
        state.borderColor = CG.colorCreateGenericGray(0, 1)
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        for sublayer in state.sublayers { sublayer.state.superlayer = nil }
        CALayer.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CALayer.objCClass.pointer)
    }

    /// The layer itself: there are no animations in flight.
    @ObjCMethod("presentationLayer") func presentationLayer() -> CALayer? { self }
    @ObjCMethod("modelLayer") func modelLayer() -> CALayer { self }

    // MARK: Geometry

    @ObjCMethod("bounds") func bounds() -> CGRect { state.bounds }

    @ObjCMethod("setBounds:")
    func setBounds(_ bounds: CGRect) {
        let state = state
        if state.bounds.size != bounds.size {
            state.needsLayout = true
            if state.needsDisplayOnBoundsChange { state.needsDisplay = true }
        }
        state.bounds = bounds
    }

    @ObjCMethod("position") func position() -> CGPoint { state.position }
    @ObjCMethod("setPosition:") func setPosition(_ position: CGPoint) { state.position = position }
    @ObjCMethod("anchorPoint") func anchorPoint() -> CGPoint { state.anchorPoint }
    @ObjCMethod("setAnchorPoint:") func setAnchorPoint(_ point: CGPoint) { state.anchorPoint = point }
    @ObjCMethod("zPosition") func zPosition() -> CGFloat { state.zPosition }
    @ObjCMethod("setZPosition:") func setZPosition(_ z: CGFloat) { state.zPosition = z }
    @ObjCMethod("frame") func frame() -> CGRect { state.frame }

    @ObjCMethod("setFrame:")
    func setFrame(_ frame: CGRect) {
        let state = state
        let size = state.bounds.size
        state.frame = frame
        if state.bounds.size != size {
            state.needsLayout = true
            if state.needsDisplayOnBoundsChange { state.needsDisplay = true }
        }
    }

    @ObjCMethod("affineTransform") func affineTransform() -> CGAffineTransform { state.transform }
    @ObjCMethod("setAffineTransform:") func setAffineTransform(_ transform: CGAffineTransform) { state.transform = transform }

    // MARK: Appearance

    @ObjCMethod("isHidden") func isHidden() -> Bool { state.hidden }
    @ObjCMethod("setHidden:") func setHidden(_ hidden: Bool) { state.hidden = hidden }
    @ObjCMethod("opacity") func opacity() -> Float { state.opacity }
    @ObjCMethod("setOpacity:") func setOpacity(_ opacity: Float) { state.opacity = opacity }
    @ObjCMethod("masksToBounds") func masksToBounds() -> Bool { state.masksToBounds }
    @ObjCMethod("setMasksToBounds:") func setMasksToBounds(_ masks: Bool) { state.masksToBounds = masks }
    @ObjCMethod("cornerRadius") func cornerRadius() -> CGFloat { state.cornerRadius }
    @ObjCMethod("setCornerRadius:") func setCornerRadius(_ radius: CGFloat) { state.cornerRadius = radius }
    @ObjCMethod("maskedCorners") func maskedCorners() -> UInt { state.maskedCorners }
    @ObjCMethod("setMaskedCorners:") func setMaskedCorners(_ corners: UInt) { state.maskedCorners = corners }
    @ObjCMethod("borderWidth") func borderWidth() -> CGFloat { state.borderWidth }
    @ObjCMethod("setBorderWidth:") func setBorderWidth(_ width: CGFloat) { state.borderWidth = width }
    @ObjCMethod("backgroundColor") func backgroundColor() -> UnsafeMutableRawPointer? { state.backgroundColor }
    @ObjCMethod("setBackgroundColor:") func setBackgroundColor(_ color: UnsafeMutableRawPointer?) { LayerState.setColor(&state.backgroundColor, color) }
    @ObjCMethod("borderColor") func borderColor() -> UnsafeMutableRawPointer? { state.borderColor }
    @ObjCMethod("setBorderColor:") func setBorderColor(_ color: UnsafeMutableRawPointer?) { LayerState.setColor(&state.borderColor, color) }
    @ObjCMethod("shadowColor") func shadowColor() -> UnsafeMutableRawPointer? { state.shadowColor }
    @ObjCMethod("setShadowColor:") func setShadowColor(_ color: UnsafeMutableRawPointer?) { LayerState.setColor(&state.shadowColor, color) }
    @ObjCMethod("shadowOpacity") func shadowOpacity() -> Float { state.shadowOpacity }
    @ObjCMethod("setShadowOpacity:") func setShadowOpacity(_ opacity: Float) { state.shadowOpacity = opacity }
    @ObjCMethod("shadowOffset") func shadowOffset() -> CGSize { state.shadowOffset }
    @ObjCMethod("setShadowOffset:") func setShadowOffset(_ offset: CGSize) { state.shadowOffset = offset }
    @ObjCMethod("shadowRadius") func shadowRadius() -> CGFloat { state.shadowRadius }
    @ObjCMethod("setShadowRadius:") func setShadowRadius(_ radius: CGFloat) { state.shadowRadius = radius }
    @ObjCMethod("contents") func contents() -> NSObject? { state.contents }
    @ObjCMethod("setContents:") func setContents(_ contents: NSObject?) { state.contents = contents }
    @ObjCMethod("contentsScale") func contentsScale() -> CGFloat { state.contentsScale }
    @ObjCMethod("setContentsScale:") func setContentsScale(_ scale: CGFloat) { state.contentsScale = scale }
    @ObjCMethod("contentsGravity") func contentsGravity() -> String { state.contentsGravity }
    @ObjCMethod("setContentsGravity:") func setContentsGravity(_ gravity: String) { state.contentsGravity = gravity }
    @ObjCMethod("name") func name() -> String? { state.name }
    @ObjCMethod("setName:") func setName(_ name: String?) { state.name = name }
    @ObjCMethod("isOpaque") func isOpaque() -> Bool { state.isOpaque }
    @ObjCMethod("setOpaque:") func setOpaque(_ opaque: Bool) { state.isOpaque = opaque }
    @ObjCMethod("mask") func mask() -> CALayer? { state.mask }
    @ObjCMethod("setMask:") func setMask(_ mask: CALayer?) { state.mask = mask }
    @ObjCMethod("needsDisplayOnBoundsChange") func needsDisplayOnBoundsChange() -> Bool { state.needsDisplayOnBoundsChange }
    @ObjCMethod("setNeedsDisplayOnBoundsChange:") func setNeedsDisplayOnBoundsChange(_ needs: Bool) { state.needsDisplayOnBoundsChange = needs }

    @ObjCMethod("delegate") func delegate() -> NSObject? { state.delegate.map { NSObject($0) } }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { state.delegate = delegate?.objcObject }

    /// Key-value coding's values for keys a layer does not define.
    @ObjCMethod("valueForKey:")
    func value(forKey key: String) -> NSObject? { state.values[key] }

    @ObjCMethod("setValue:forKey:")
    func setValue(_ value: NSObject?, forKey key: String) { state.values[key] = value }

    // MARK: The layer tree

    @ObjCMethod("superlayer") func superlayer() -> CALayer? { state.superlayer.map(CALayer.wrap) }

    /// nil when there are none, as Core Animation's.
    @ObjCMethod("sublayers")
    func sublayers() -> NSObject? { state.sublayers.isEmpty ? nil : NSMutableArray.of(state.sublayers) }

    @ObjCMethod("setSublayers:")
    func setSublayers(_ sublayers: NSArray?) {
        for sublayer in state.sublayers { sublayer.state.superlayer = nil }
        state.sublayers = []
        for sublayer in sublayers?.elements ?? [] { addSublayer(sublayer.unsafeCast(to: CALayer.self)) }
    }

    @ObjCMethod("addSublayer:")
    func addSublayer(_ layer: CALayer) { insert(layer, at: state.sublayers.count) }

    @ObjCMethod("insertSublayer:atIndex:")
    func insertSublayer(_ layer: CALayer, at index: UInt32) { insert(layer, at: Int(index)) }

    @ObjCMethod("insertSublayer:below:")
    func insertSublayer(_ layer: CALayer, below sibling: CALayer?) {
        insert(layer, at: sibling.flatMap(index(of:)) ?? 0)
    }

    @ObjCMethod("insertSublayer:above:")
    func insertSublayer(_ layer: CALayer, above sibling: CALayer?) {
        insert(layer, at: sibling.flatMap(index(of:)).map { $0 + 1 } ?? state.sublayers.count)
    }

    @ObjCMethod("replaceSublayer:with:")
    func replaceSublayer(_ old: CALayer, with new: CALayer) {
        guard let index = index(of: old) else { return }
        old.removeFromSuperlayer()
        insert(new, at: index)
    }

    @ObjCMethod("removeFromSuperlayer")
    func removeFromSuperlayer() {
        guard let superlayer = state.superlayer else { return }
        let retained = self
        CALayer.states[superlayer].sublayers.removeAll { $0.objcObject == objcObject }
        retained.state.superlayer = nil
    }

    /// Adds or moves `layer` to `index` among the sublayers.
    func insert(_ layer: CALayer, at index: Int) {
        guard layer.objcObject != objcObject else { return }
        let retained = layer
        if let old = retained.state.superlayer { CALayer.states[old].sublayers.removeAll { $0.objcObject == layer.objcObject } }
        state.sublayers.insert(retained, at: min(max(index, 0), state.sublayers.count))
        retained.state.superlayer = objcObject
    }

    func index(of layer: CALayer) -> Int? { state.sublayers.firstIndex { $0.objcObject == layer.objcObject } }

    // MARK: Coordinates

    /// From this layer's coordinates to the root's.
    var toRoot: CGAffineTransform {
        var transform = CGAffineTransform.identity
        var current: UnsafeMutableRawPointer? = objcObject
        while let layer = current {
            let state = CALayer.states[layer]
            guard state.superlayer != nil else { break }
            transform = transform.concatenating(state.toSuperlayer)
            current = state.superlayer
        }
        return transform
    }

    @ObjCMethod("convertPoint:toLayer:")
    func convert(_ point: CGPoint, to layer: CALayer?) -> CGPoint {
        let root = toRoot.apply(point)
        return layer.map { $0.toRoot.inverted.apply(root) } ?? root
    }

    @ObjCMethod("convertPoint:fromLayer:")
    func convert(_ point: CGPoint, from layer: CALayer?) -> CGPoint {
        toRoot.inverted.apply(layer.map { $0.toRoot.apply(point) } ?? point)
    }

    @ObjCMethod("convertRect:toLayer:")
    func convert(_ rect: CGRect, to layer: CALayer?) -> CGRect {
        let transform = layer.map { toRoot.concatenating($0.toRoot.inverted) } ?? toRoot
        return transform.apply(rect)
    }

    @ObjCMethod("convertRect:fromLayer:")
    func convert(_ rect: CGRect, from layer: CALayer?) -> CGRect {
        let transform = (layer?.toRoot ?? .identity).concatenating(toRoot.inverted)
        return transform.apply(rect)
    }

    @ObjCMethod("containsPoint:") func contains(_ point: CGPoint) -> Bool { state.bounds.contains(point) }

    /// The deepest visible layer at `point`, in the superlayer's coordinates.
    @ObjCMethod("hitTest:")
    func hitTest(_ point: CGPoint) -> CALayer? {
        let state = state
        guard !state.hidden else { return nil }
        let local = state.toSuperlayer.inverted.apply(point)
        if state.masksToBounds, !state.bounds.contains(local) { return nil }
        for sublayer in state.sublayers.reversed() {
            if let hit = sublayer.hitTest(local) { return hit }
        }
        return state.bounds.contains(local) ? self : nil
    }

    // MARK: Layout and display

    @ObjCMethod("setNeedsLayout") func setNeedsLayout() { state.needsLayout = true }
    @ObjCMethod("needsLayout") func needsLayout() -> Bool { state.needsLayout }

    @ObjCMethod("layoutIfNeeded")
    func layoutIfNeeded() {
        if state.needsLayout {
            state.needsLayout = false
            sendLayoutSublayers()
        }
        for sublayer in state.sublayers { sublayer.layoutIfNeeded() }
    }

    /// Asks the delegate to lay out the layer.
    @ObjCMethod("layoutSublayers")
    func layoutSublayers() {
        guard let delegate = state.delegate.map({ NSObject($0) }), delegate.responds(to: "layoutSublayersOfLayer:") else { return }
        delegate.sendLayoutSublayers(of: self)
    }

    @ObjCMethod("setNeedsDisplay") func setNeedsDisplay() { state.needsDisplay = true }
    @ObjCMethod("setNeedsDisplayInRect:") func setNeedsDisplay(in rect: CGRect) { state.needsDisplay = true }
    @ObjCMethod("needsDisplay") func needsDisplay() -> Bool { state.needsDisplay }

    @ObjCMethod("displayIfNeeded")
    func displayIfNeeded() {
        if state.needsDisplay { sendDisplay() }
    }

    /// The delegate's -displayLayer: if it has one; otherwise draws into a
    /// backing bitmap through -drawInContext:, when the layer draws.
    @ObjCMethod("display")
    func display() {
        let state = state
        state.needsDisplay = false
        let delegate = state.delegate.map { NSObject($0) }
        if let delegate, delegate.responds(to: "displayLayer:") {
            delegate.sendDisplay(self)
            return
        }
        guard draws, state.bounds.width > 0, state.bounds.height > 0,
              let context = CG.makeContext(size: state.bounds.size, scale: state.contentsScale, opaque: false) else { return }
        defer { CG.release(context) }
        CG.translateCTM(context, -state.bounds.minX, -state.bounds.minY)
        sendDraw(in: context)
        LayerState.setColor(&state.backing, nil)
        state.backing = CG.bitmapContextCreateImage(context)
        state.backingSize = state.bounds.size
    }

    /// The delegate's -drawLayer:inContext:.
    @ObjCMethod("drawInContext:")
    func draw(in context: UnsafeMutableRawPointer?) {
        guard let delegate = state.delegate.map({ NSObject($0) }), delegate.responds(to: "drawLayer:inContext:") else { return }
        delegate.sendDrawLayer(self, in: context)
    }

    /// Whether the layer draws its own content: a subclass's
    /// -drawInContext:, or a delegate that draws (a view whose class has
    /// -drawRect:).
    var draws: Bool {
        if Methods.overrides(objcObject, "drawInContext:", of: CALayer.objCClass.pointer) { return true }
        guard let delegate = state.delegate else { return false }
        if ObjCRuntime.isKind(delegate, of: UIView.objCClass.pointer) {
            return Methods.overrides(delegate, "drawRect:", of: UIView.objCClass.pointer)
        }
        return NSObject(delegate).responds(to: "drawLayer:inContext:")
    }

    /// Draws the layer and its sublayers into `context`, in the layer's
    /// coordinates.
    @ObjCMethod("renderInContext:")
    func render(in context: UnsafeMutableRawPointer?) {
        guard let context else { return }
        CALayer.render(self, in: context, root: true)
    }

    // MARK: Animation, which is not run

    @ObjCMethod("addAnimation:forKey:") func addAnimation(_ animation: NSObject, forKey key: String?) {}
    @ObjCMethod("removeAnimationForKey:") func removeAnimation(forKey key: String) {}
    @ObjCMethod("removeAllAnimations") func removeAllAnimations() {}
    @ObjCMethod("animationForKey:") func animation(forKey key: String) -> NSObject? { nil }
    @ObjCMethod("animationKeys") func animationKeys() -> NSObject? { nil }
    @ObjCMethod("actionForKey:") func action(forKey key: String) -> NSObject? { nil }
}

// MARK: - Rendering

extension CALayer {
    /// Draws `layer`: its background, its content, its sublayers by
    /// zPosition, then its border, at its opacity and clipped when it
    /// masks to its bounds.
    static func render(_ layer: CALayer, in context: CGRef, root: Bool = false) {
        let state = layer.state
        guard !state.hidden, state.opacity > 0 else { return }
        CG.saveGState(context)
        defer { CG.restoreGState(context) }
        if !root { CG.concatCTM(context, state.toSuperlayer) }
        let group = state.opacity < 1
        if group {
            CG.setAlpha(context, CGFloat(state.opacity))
            CG.beginTransparencyLayer(context, nil)
        }
        let bounds = state.bounds
        let shape = state.cornerRadius > 0 ? roundedRect(bounds, radius: state.cornerRadius, corners: state.maskedCorners) : nil

        if let background = state.backgroundColor {
            CG.setFillColorWithColor(context, background)
            if let shape {
                CG.addPath(context, shape.object)
                CG.fillPath(context)
            } else {
                CG.fillRect(context, bounds)
            }
        }
        CG.saveGState(context)
        if state.masksToBounds {
            if let shape {
                CG.addPath(context, shape.object)
                CG.clip(context)
            } else {
                CG.clipToRect(context, bounds)
            }
        }
        // A navigation bar draws its items, which change without telling it.
        let redraws = state.delegate.map {
            ObjCRuntime.isKind($0, of: UINavigationBar.objCClass.pointer)
                && UINavigationBar(objcObject: $0, ownership: .retain).contentChanged()
        } ?? false
        if layer.draws, redraws || state.needsDisplay || state.backing == nil || state.backingSize != bounds.size {
            layer.sendDisplay()
        }
        if let backing = state.backing {
            CG.drawFlipped(backing, in: CGRect(origin: bounds.origin, size: state.backingSize), context: context)
        }
        if let contents = state.contents {
            drawContents(contents, of: state, in: context)
        }
        let ordered = state.sublayers.enumerated().sorted {
            ($0.element.state.zPosition, $0.offset) < ($1.element.state.zPosition, $1.offset)
        }
        for (_, sublayer) in ordered { render(sublayer, in: context) }
        CG.restoreGState(context)

        if state.borderWidth > 0, let border = state.borderColor {
            let half = state.borderWidth / 2
            let inset = CGRect(x: bounds.minX + half, y: bounds.minY + half, width: bounds.width - state.borderWidth,
                               height: bounds.height - state.borderWidth)
            CG.setStrokeColorWithColor(context, border)
            CG.setLineWidth(context, state.borderWidth)
            if state.cornerRadius > 0, let path = roundedRect(inset, radius: max(state.cornerRadius - half, 0), corners: state.maskedCorners) {
                CG.addPath(context, path.object)
                CG.strokePath(context)
            } else {
                CG.strokeRect(context, inset)
            }
        }
        if group { CG.endTransparencyLayer(context) }
    }

    static func roundedRect(_ rect: CGRect, radius: CGFloat, corners: UInt) -> Owned? {
        guard let path = CG.pathCreateMutable() else { return nil }
        // CACornerMask's min-x min-y, max-x min-y, min-x max-y, max-x max-y
        // are UIRectCorner's top left, top right, bottom left, bottom right.
        UIBezierPath.addRoundedRect(path, rect, corners: corners, radii: CGSize(width: radius, height: radius))
        return Owned(path)
    }

    /// A CGImage (or a UIImage's) placed by the contents gravity.
    private static func drawContents(_ contents: NSObject, of state: LayerState, in context: CGRef) {
        let image = contents.is(UIImage.self) ? contents.unsafeCast(to: UIImage.self).state.cgImage : contents.objcObject
        guard let image else { return }
        let size = CGSize(width: CGFloat(CG.imageGetWidth(image)) / state.contentsScale,
                          height: CGFloat(CG.imageGetHeight(image)) / state.contentsScale)
        CG.drawFlipped(image, in: place(size, in: state.bounds, gravity: state.contentsGravity), context: context)
    }

    /// Where content of `size` goes in `bounds` by a gravity.
    static func place(_ size: CGSize, in bounds: CGRect, gravity: String) -> CGRect {
        switch gravity {
        case "resizeAspect", "resizeAspectFill":
            guard size.width > 0, size.height > 0 else { return bounds }
            let scales = (bounds.width / size.width, bounds.height / size.height)
            let scale = gravity == "resizeAspect" ? min(scales.0, scales.1) : max(scales.0, scales.1)
            let fitted = CGSize(width: size.width * scale, height: size.height * scale)
            return CGRect(x: bounds.midX - fitted.width / 2, y: bounds.midY - fitted.height / 2, width: fitted.width, height: fitted.height)
        case "resize":
            return bounds
        default:
            let x: CGFloat = gravity.hasSuffix("Left") || gravity == "left" ? bounds.minX
                : gravity.hasSuffix("Right") || gravity == "right" ? bounds.maxX - size.width : bounds.midX - size.width / 2
            let y: CGFloat = gravity.hasPrefix("top") ? bounds.minY
                : gravity.hasPrefix("bottom") ? bounds.maxY - size.height : bounds.midY - size.height / 2
            return CGRect(x: x, y: y, width: size.width, height: size.height)
        }
    }
}

/// CALayer's messages, sent so subclasses' overrides and delegates run.
extension NSObject {
    @ObjCMethod("init") func initializeLayer() -> NSObject
    @ObjCMethod("layoutSublayers") func sendLayoutSublayers()
    @ObjCMethod("layoutSublayersOfLayer:") func sendLayoutSublayers(of layer: CALayer)
    @ObjCMethod("display") func sendDisplay()
    @ObjCMethod("displayLayer:") func sendDisplay(_ layer: CALayer)
    @ObjCMethod("drawInContext:") func sendDraw(in context: UnsafeMutableRawPointer?)
    @ObjCMethod("drawLayer:inContext:") func sendDrawLayer(_ layer: CALayer, in context: UnsafeMutableRawPointer?)
}

/// Core Animation's string constants.
@ObjCConstants
enum LayerConstants {
    static let kCAGravityCenter = "center"
    static let kCAGravityTop = "top"
    static let kCAGravityBottom = "bottom"
    static let kCAGravityLeft = "left"
    static let kCAGravityRight = "right"
    static let kCAGravityTopLeft = "topLeft"
    static let kCAGravityTopRight = "topRight"
    static let kCAGravityBottomLeft = "bottomLeft"
    static let kCAGravityBottomRight = "bottomRight"
    static let kCAGravityResize = "resize"
    static let kCAGravityResizeAspect = "resizeAspect"
    static let kCAGravityResizeAspectFill = "resizeAspectFill"
    static let kCACornerCurveCircular = "circular"
    static let kCACornerCurveContinuous = "continuous"
    static let kCAFillModeForwards = "forwards"
    static let kCAFillModeBackwards = "backwards"
    static let kCAFillModeBoth = "both"
    static let kCAFillModeRemoved = "removed"
    static let kCAMediaTimingFunctionLinear = "linear"
    static let kCAMediaTimingFunctionEaseIn = "easeIn"
    static let kCAMediaTimingFunctionEaseOut = "easeOut"
    static let kCAMediaTimingFunctionEaseInEaseOut = "easeInEaseOut"
    static let kCAMediaTimingFunctionDefault = "default"
}

/// Method lookups, to tell whether a class overrides a method.
enum Methods {
    typealias Implementation = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> UnsafeRawPointer?
    nonisolated(unsafe) static var implementation: Implementation!

    /// Whether `object`'s class implements `selector` other than as `base`
    /// does.
    static func overrides(_ object: UnsafeMutableRawPointer, _ selector: String, of base: UnsafeMutableRawPointer) -> Bool {
        let sel = ObjCRuntime.selector(selector)
        return implementation(ObjCRuntime.objectClass(object), sel) != implementation(base, sel)
    }
}

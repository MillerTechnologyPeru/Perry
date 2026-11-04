import CPerryGeometry
import Glibc
import PerryObjCInterop

// CALayer: a layer tree with geometry and appearance, rendered through
// CoreGraphics. Each of UIKit's views is backed by a layer, whose delegate
// it is. Changing an animatable property asks the layer for an action, as
// Core Animation does: its delegate's -actionForLayer:forKey:, its actions,
// then a default, which animates a standalone layer already on screen for
// the transaction's duration. Layers are drawn as they present, with the
// animations running on them applied (Presentation).
//
// Two private messages tell a layer about its delegate, as UIKit's views
// know: -_perryDrawsLayer: whether the delegate draws the layer's content
// (a view whose class has -drawRect:), and -_perryLayerContentChanged:
// whether what it draws has changed without its saying so.

final class LayerState {
    /// kCAContentsFormatRGBA8Uint; the contents are drawn as RGBA whatever
    /// the format asked for.
    var contentsFormat = "RGBA8"
    var bounds = CGRect.zero
    var position = CGPoint.zero
    var anchorPoint = CGPoint(x: 0.5, y: 0.5)
    var zPosition: CGFloat = 0
    var transform3D = CATransform3D.identity
    var sublayerTransform = CATransform3D.identity
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
    var allowsGroupOpacity = true
    var sublayers: [CALayer] = []
    /// The superlayer, which retains this layer; not retained.
    var superlayer: UnsafeMutableRawPointer?
    /// Not retained.
    var delegate: UnsafeMutableRawPointer?
    var mask: CALayer?
    var actions: NSObject?
    var style: NSObject?
    var needsDisplay = false
    var needsLayout = true
    /// What -display drew, and the size it drew at.
    var backing: CGRef?
    var backingSize = CGSize.zero
    /// Whether the delegate has displayed the layer itself, through
    /// -displayLayer:.
    var displayedByDelegate = false
    /// Whether the layer has been drawn, after which changes to it animate.
    var rendered = false
    var values: [String: NSObject] = [:]
    /// The animations running on the layer, in the order they were added.
    var animations: [(key: String, animation: CAAnimation)] = []

    deinit {
        for color in [backgroundColor, borderColor, shadowColor, backing] { if let color { CG.release(color) } }
    }

    var transform: CGAffineTransform {
        get { transform3D.affine }
        set { transform3D = CATransform3D(newValue) }
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

    /// From this layer's coordinates to its superlayer's, which applies
    /// its sublayer transform about its center to this one.
    func toSuperlayer(within superlayer: LayerState?) -> CGAffineTransform {
        let anchor = CGPoint(x: bounds.minX + anchorPoint.x * bounds.width, y: bounds.minY + anchorPoint.y * bounds.height)
        var result = CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: -anchor.x, ty: -anchor.y)
            .concatenating(transform)
            .concatenating(CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: position.x, ty: position.y))
        if let superlayer, !superlayer.sublayerTransform.affine.isIdentity {
            let center = CGPoint(x: superlayer.bounds.midX, y: superlayer.bounds.midY)
            result = result.concatenating(CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: -center.x, ty: -center.y))
                .concatenating(superlayer.sublayerTransform.affine)
                .concatenating(CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: center.x, ty: center.y))
        }
        return result
    }

    /// From this layer's coordinates to its superlayer's.
    var toSuperlayer: CGAffineTransform { toSuperlayer(within: superlayer.map(CALayer.state(of:))) }

    static func setColor(_ slot: inout CGRef?, _ color: CGRef?) {
        let retained = ObjCRuntime.retain(color)
        if let old = slot { CG.release(old) }
        slot = retained
    }

    /// A copy to present, with the colors and backing retained again.
    func copy() -> LayerState {
        let copy = LayerState()
        (copy.bounds, copy.position, copy.anchorPoint, copy.zPosition) = (bounds, position, anchorPoint, zPosition)
        (copy.transform3D, copy.sublayerTransform, copy.hidden, copy.opacity) = (transform3D, sublayerTransform, hidden, opacity)
        (copy.masksToBounds, copy.cornerRadius, copy.maskedCorners, copy.borderWidth) = (masksToBounds, cornerRadius, maskedCorners, borderWidth)
        LayerState.setColor(&copy.backgroundColor, backgroundColor)
        LayerState.setColor(&copy.borderColor, borderColor)
        LayerState.setColor(&copy.shadowColor, shadowColor)
        LayerState.setColor(&copy.backing, backing)
        (copy.shadowOpacity, copy.shadowOffset, copy.shadowRadius) = (shadowOpacity, shadowOffset, shadowRadius)
        (copy.contents, copy.contentsScale, copy.contentsGravity) = (contents, contentsScale, contentsGravity)
        (copy.isOpaque, copy.sublayers, copy.superlayer, copy.delegate, copy.mask) = (isOpaque, sublayers, superlayer, delegate, mask)
        (copy.backingSize, copy.displayedByDelegate, copy.allowsGroupOpacity) = (backingSize, displayedByDelegate, allowsGroupOpacity)
        return copy
    }
}

@ObjCClass("CALayer")
open class CALayer: NSObject {
    /// The model values.
    var state = LayerState()

    /// The layer at `object`: its Swift object.
    static func wrap(_ object: UnsafeMutableRawPointer) -> CALayer { CALayer.objCInstance(object, ownership: .retain) }

    /// The model values of the layer at `object`.
    static func state(of object: UnsafeMutableRawPointer) -> LayerState { wrap(object).state }

    @ObjCClassMethod("layer")
    static func layer(_ cls: ObjCClass) -> NSObject { cls.object.allocated().initialized() }

    @ObjCMethod("init")
    public required override init() {
        super.init()
        state.borderColor = CG.colorCreateGenericGray(0, 1)
    }

    /// A copy of the model layer, as -presentationLayer's starting point.
    @ObjCMethod("initWithLayer:")
    public required init(layer: CALayer) {
        let copy = layer.state.copy()
        copy.sublayers = []
        copy.superlayer = nil
        state = copy
        super.init()
    }

    deinit {
        for sublayer in state.sublayers { sublayer.state.superlayer = nil }
        Presentation.forget(objcObject)
    }

    /// The layer as it presents now: a copy with its animations applied.
    @ObjCMethod("presentationLayer")
    func presentationLayer() -> CALayer? {
        guard !state.animations.isEmpty else { return self }
        let presented = CALayer()
        presented.state = Presentation.state(of: self)
        return presented
    }

    @ObjCMethod("modelLayer") func modelLayer() -> CALayer { self }

    // MARK: Geometry

    @ObjCMethod("bounds") func bounds() -> CGRect { state.bounds }

    @ObjCMethod("setBounds:")
    func setBounds(_ bounds: CGRect) {
        let state = state
        change("bounds") {
            if state.bounds.size != bounds.size {
                state.needsLayout = true
                if state.needsDisplayOnBoundsChange { state.needsDisplay = true }
            }
            state.bounds = bounds
        }
    }

    @ObjCMethod("position") func position() -> CGPoint { state.position }
    @ObjCMethod("setPosition:") func setPosition(_ position: CGPoint) { change("position") { state.position = position } }
    @ObjCMethod("anchorPoint") func anchorPoint() -> CGPoint { state.anchorPoint }
    @ObjCMethod("setAnchorPoint:") func setAnchorPoint(_ point: CGPoint) { change("anchorPoint") { state.anchorPoint = point } }
    @ObjCMethod("zPosition") func zPosition() -> CGFloat { state.zPosition }
    @ObjCMethod("setZPosition:") func setZPosition(_ z: CGFloat) { change("zPosition") { state.zPosition = z } }
    @ObjCMethod("frame") func frame() -> CGRect { state.frame }

    /// The bounds and position the frame makes, each changing as a property.
    @ObjCMethod("setFrame:")
    func setFrame(_ frame: CGRect) {
        let state = state
        let model = LayerState()
        (model.bounds, model.position, model.anchorPoint, model.transform3D) = (state.bounds, state.position, state.anchorPoint, state.transform3D)
        model.frame = frame
        if model.position != state.position { setPosition(model.position) }
        if model.bounds != state.bounds { setBounds(model.bounds) }
    }

    @ObjCMethod("transform") func transform() -> CATransform3D { state.transform3D }
    @ObjCMethod("setTransform:") func setTransform(_ transform: CATransform3D) { change("transform") { state.transform3D = transform } }
    @ObjCMethod("affineTransform") func affineTransform() -> CGAffineTransform { state.transform }
    @ObjCMethod("setAffineTransform:")
    func setAffineTransform(_ transform: CGAffineTransform) { change("transform") { state.transform = transform } }
    @ObjCMethod("sublayerTransform") func sublayerTransform() -> CATransform3D { state.sublayerTransform }
    @ObjCMethod("setSublayerTransform:")
    func setSublayerTransform(_ transform: CATransform3D) { change("sublayerTransform") { state.sublayerTransform = transform } }

    // MARK: Appearance

    @ObjCMethod("isHidden") func isHidden() -> Bool { state.hidden }
    @ObjCMethod("setHidden:") func setHidden(_ hidden: Bool) { change("hidden") { state.hidden = hidden } }
    @ObjCMethod("opacity") func opacity() -> Float { state.opacity }
    @ObjCMethod("setOpacity:") func setOpacity(_ opacity: Float) { change("opacity") { state.opacity = opacity } }
    @ObjCMethod("masksToBounds") func masksToBounds() -> Bool { state.masksToBounds }
    @ObjCMethod("setMasksToBounds:") func setMasksToBounds(_ masks: Bool) { changed { state.masksToBounds = masks } }
    @ObjCMethod("cornerRadius") func cornerRadius() -> CGFloat { state.cornerRadius }
    @ObjCMethod("setCornerRadius:") func setCornerRadius(_ radius: CGFloat) { change("cornerRadius") { state.cornerRadius = radius } }
    @ObjCMethod("maskedCorners") func maskedCorners() -> UInt { state.maskedCorners }
    @ObjCMethod("setMaskedCorners:") func setMaskedCorners(_ corners: UInt) { changed { state.maskedCorners = corners } }
    @ObjCMethod("cornerCurve") func cornerCurve() -> String { state.values["cornerCurve"]?.stringValue ?? "circular" }
    @ObjCMethod("setCornerCurve:") func setCornerCurve(_ curve: NSObject?) { state.values["cornerCurve"] = curve }
    @ObjCMethod("borderWidth") func borderWidth() -> CGFloat { state.borderWidth }
    @ObjCMethod("setBorderWidth:") func setBorderWidth(_ width: CGFloat) { change("borderWidth") { state.borderWidth = width } }
    @ObjCMethod("backgroundColor") func backgroundColor() -> UnsafeMutableRawPointer? { state.backgroundColor }
    @ObjCMethod("setBackgroundColor:")
    func setBackgroundColor(_ color: UnsafeMutableRawPointer?) { change("backgroundColor") { LayerState.setColor(&state.backgroundColor, color) } }
    @ObjCMethod("borderColor") func borderColor() -> UnsafeMutableRawPointer? { state.borderColor }
    @ObjCMethod("setBorderColor:")
    func setBorderColor(_ color: UnsafeMutableRawPointer?) { change("borderColor") { LayerState.setColor(&state.borderColor, color) } }
    @ObjCMethod("shadowColor") func shadowColor() -> UnsafeMutableRawPointer? { state.shadowColor }
    @ObjCMethod("setShadowColor:")
    func setShadowColor(_ color: UnsafeMutableRawPointer?) { change("shadowColor") { LayerState.setColor(&state.shadowColor, color) } }
    @ObjCMethod("shadowOpacity") func shadowOpacity() -> Float { state.shadowOpacity }
    @ObjCMethod("setShadowOpacity:") func setShadowOpacity(_ opacity: Float) { change("shadowOpacity") { state.shadowOpacity = opacity } }
    @ObjCMethod("shadowOffset") func shadowOffset() -> CGSize { state.shadowOffset }
    @ObjCMethod("setShadowOffset:") func setShadowOffset(_ offset: CGSize) { change("shadowOffset") { state.shadowOffset = offset } }
    @ObjCMethod("shadowRadius") func shadowRadius() -> CGFloat { state.shadowRadius }
    @ObjCMethod("setShadowRadius:") func setShadowRadius(_ radius: CGFloat) { change("shadowRadius") { state.shadowRadius = radius } }
    @ObjCMethod("shadowPath") func shadowPath() -> UnsafeMutableRawPointer? { nil }
    @ObjCMethod("setShadowPath:") func setShadowPath(_ path: UnsafeMutableRawPointer?) {}
    @ObjCMethod("contents") func contents() -> NSObject? { state.contents }
    @ObjCMethod("setContents:") func setContents(_ contents: NSObject?) { change("contents") { state.contents = contents } }
    @ObjCMethod("contentsScale") func contentsScale() -> CGFloat { state.contentsScale }
    @ObjCMethod("setContentsScale:") func setContentsScale(_ scale: CGFloat) { changed { state.contentsScale = scale } }
    @ObjCMethod("contentsGravity") func contentsGravity() -> String { state.contentsGravity }
    @ObjCMethod("setContentsGravity:") func setContentsGravity(_ gravity: String) { changed { state.contentsGravity = gravity } }
    @ObjCMethod("name") func name() -> String? { state.name }
    @ObjCMethod("setName:") func setName(_ name: String?) { state.name = name }
    @ObjCMethod("isOpaque") func isOpaque() -> Bool { state.isOpaque }
    @ObjCMethod("setOpaque:") func setOpaque(_ opaque: Bool) { state.isOpaque = opaque }
    @ObjCMethod("mask") func mask() -> CALayer? { state.mask }
    @ObjCMethod("setMask:") func setMask(_ mask: CALayer?) { changed { state.mask = mask } }
    @ObjCMethod("needsDisplayOnBoundsChange") func needsDisplayOnBoundsChange() -> Bool { state.needsDisplayOnBoundsChange }
    @ObjCMethod("setNeedsDisplayOnBoundsChange:") func setNeedsDisplayOnBoundsChange(_ needs: Bool) { state.needsDisplayOnBoundsChange = needs }
    @ObjCMethod("allowsGroupOpacity") func allowsGroupOpacity() -> Bool { state.allowsGroupOpacity }
    @ObjCMethod("setAllowsGroupOpacity:") func setAllowsGroupOpacity(_ allows: Bool) { state.allowsGroupOpacity = allows }
    @ObjCMethod("shouldRasterize") func shouldRasterize() -> Bool { false }
    @ObjCMethod("setShouldRasterize:") func setShouldRasterize(_ rasterize: Bool) {}
    @ObjCMethod("rasterizationScale") func rasterizationScale() -> CGFloat { state.contentsScale }
    @ObjCMethod("setRasterizationScale:") func setRasterizationScale(_ scale: CGFloat) {}
    @ObjCMethod("contentsFormat") func contentsFormat() -> String { state.contentsFormat }
    @ObjCMethod("setContentsFormat:") func setContentsFormat(_ format: String) { state.contentsFormat = format }
    @ObjCMethod("drawsAsynchronously") func drawsAsynchronously() -> Bool { false }
    @ObjCMethod("setDrawsAsynchronously:") func setDrawsAsynchronously(_ asynchronously: Bool) {}

    @ObjCMethod("delegate") func delegate() -> NSObject? { state.delegate.map { NSObject($0) } }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { state.delegate = delegate?.objcObject }
    @ObjCMethod("actions") func actions() -> NSObject? { state.actions }
    @ObjCMethod("setActions:") func setActions(_ actions: NSObject?) { state.actions = actions }
    @ObjCMethod("style") func style() -> NSObject? { state.style }
    @ObjCMethod("setStyle:") func setStyle(_ style: NSObject?) { state.style = style }

    /// The animatable properties by name, boxed, and key-value coding's
    /// values for keys a layer does not define.
    @ObjCMethod("valueForKey:")
    func value(forKey key: String) -> NSObject? {
        if let value = AnimatedValue.model(of: self, key) { return value.boxed() }
        return state.values[key]
    }

    @ObjCMethod("valueForKeyPath:")
    func value(forKeyPath keyPath: String) -> NSObject? { value(forKey: keyPath) }

    @ObjCMethod("setValue:forKey:")
    func setValue(_ value: NSObject?, forKey key: String) {
        if let value, let unboxed = AnimatedValue(boxed: value, key: key) {
            change(key) { unboxed.apply(to: self, key: key) }
            return
        }
        state.values[key] = value
    }

    @ObjCMethod("setValue:forKeyPath:")
    func setValue(_ value: NSObject?, forKeyPath keyPath: String) { setValue(value, forKey: keyPath) }

    // MARK: Actions

    /// Changes an animatable property, running the action for it.
    func change(_ key: String, _ body: () -> Void) {
        let old = Actions.wanted(for: self) ? AnimatedValue.model(of: self, key) : nil
        body()
        if let old { Actions.run(for: self, key: key, from: old) }
        Compositing.changed()
    }

    /// Changes a property that does not animate.
    func changed(_ body: () -> Void) {
        body()
        Compositing.changed()
    }

    /// The delegate's action, the layer's actions' or style's, then the
    /// default; nil for none.
    @ObjCMethod("actionForKey:")
    func action(forKey key: String) -> NSObject? {
        if let delegate = state.delegate.map({ NSObject($0) }), delegate.responds(to: "actionForLayer:forKey:") {
            if let action = delegate.sendAction(for: self, forKey: key) { return action }
        }
        if let action = state.actions?.sendObject(forKey: key) { return action }
        if let actions = state.style?.sendObject(forKey: "actions"), let action = actions.sendObject(forKey: key) { return action }
        return CALayer.defaultAction(forKey: key)
    }

    /// A basic animation of the key, for the transaction's duration and
    /// timing function, when it animates.
    @ObjCClassMethod("defaultActionForKey:")
    static func defaultAction(forKey key: String) -> NSObject? {
        guard AnimatedValue.animatable(key) else { return nil }
        let animation = CABasicAnimation()
        animation.setKeyPath(key)
        animation.state.duration = CATransaction.animationDuration()
        animation.state.timingFunction = CATransaction.animationTimingFunction()
            ?? CAMediaTimingFunction.named(LayerConstants.kCAMediaTimingFunctionDefault)
        return animation
    }

    @ObjCClassMethod("needsDisplayForKey:") static func needsDisplay(forKey key: String) -> Bool { false }

    // MARK: Animations

    /// A copy of the animation runs on the layer, from now unless it says
    /// when; one under the same key is replaced.
    @ObjCMethod("addAnimation:forKey:")
    func addAnimation(_ animation: CAAnimation, forKey key: String?) {
        let copy = animation.copied()
        if copy.state.beginTime == 0 { copy.state.beginTime = Clock.now }
        copy.state.added = Clock.now
        let key = key ?? "__perry.animation.\(copy.objcObject)"
        if let index = state.animations.firstIndex(where: { $0.key == key }) {
            let replaced = state.animations.remove(at: index).animation
            Presentation.stopped(replaced, on: self, finished: false)
        }
        state.animations.append((key, copy))
        CATransaction.added(copy)
        Presentation.track(self)
        Compositing.changed()
    }

    @ObjCMethod("removeAnimationForKey:")
    func removeAnimation(forKey key: String) {
        guard let index = state.animations.firstIndex(where: { $0.key == key }) else { return }
        let removed = state.animations.remove(at: index).animation
        Presentation.stopped(removed, on: self, finished: false)
        Compositing.changed()
    }

    @ObjCMethod("removeAllAnimations")
    func removeAllAnimations() {
        let removed = state.animations
        state.animations = []
        for entry in removed { Presentation.stopped(entry.animation, on: self, finished: false) }
        Compositing.changed()
    }

    @ObjCMethod("animationForKey:")
    func animation(forKey key: String) -> CAAnimation? { state.animations.first { $0.key == key }?.animation }

    @ObjCMethod("animationKeys")
    func animationKeys() -> NSObject? {
        let keys = state.animations.map(\.key).filter { !$0.hasPrefix("__perry.") }
        return keys.isEmpty ? nil : NSMutableArray.of(keys.map { NSObject($0.objCReturnValue()!) })
    }

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
        CALayer.state(of: superlayer).sublayers.removeAll { $0.objcObject == objcObject }
        retained.state.superlayer = nil
        retained.state.rendered = false
        Compositing.changed()
    }

    /// Adds or moves `layer` to `index` among the sublayers.
    func insert(_ layer: CALayer, at index: Int) {
        guard layer.objcObject != objcObject else { return }
        let retained = layer
        var index = index
        // Moving within the same layer: the index counts the layer itself.
        if retained.state.superlayer == objcObject, let current = self.index(of: layer), current < index { index -= 1 }
        if let old = retained.state.superlayer { CALayer.state(of: old).sublayers.removeAll { $0.objcObject == layer.objcObject } }
        state.sublayers.insert(retained, at: min(max(index, 0), state.sublayers.count))
        retained.state.superlayer = objcObject
        Compositing.changed()
    }

    func index(of layer: CALayer) -> Int? { state.sublayers.firstIndex { $0.objcObject == layer.objcObject } }

    // MARK: Coordinates

    /// From this layer's coordinates to the root's.
    var toRoot: CGAffineTransform {
        var transform = CGAffineTransform.identity
        var current: UnsafeMutableRawPointer? = objcObject
        while let layer = current {
            let state = CALayer.state(of: layer)
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

    /// From this layer's coordinates to its superlayer's.
    @ObjCMethod("_perryTransformToSuperlayer")
    func transformToSuperlayer() -> CGAffineTransform { state.toSuperlayer }

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

    @ObjCMethod("preferredFrameSize") func preferredFrameSize() -> CGSize { state.bounds.size }

    @ObjCMethod("setNeedsDisplay") func setNeedsDisplay() { changed { state.needsDisplay = true } }
    @ObjCMethod("setNeedsDisplayInRect:") func setNeedsDisplay(in rect: CGRect) { changed { state.needsDisplay = true } }
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
            state.displayedByDelegate = true
            state.backingSize = state.bounds.size
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
    /// -drawInContext:, or a delegate that draws.
    var draws: Bool {
        if Methods.overrides(objcObject, "drawInContext:", of: CALayer.objCClass.pointer) { return true }
        guard let delegate = state.delegate.map({ NSObject($0) }) else { return false }
        if delegate.responds(to: "displayLayer:") { return true }
        if delegate.responds(to: "_perryDrawsLayer:") { return delegate.sendDraws(self) }
        return delegate.responds(to: "drawLayer:inContext:")
    }

    /// Draws the layer and its sublayers into `context`, in the layer's
    /// coordinates, as they present now.
    @ObjCMethod("renderInContext:")
    func render(in context: UnsafeMutableRawPointer?) {
        guard let context else { return }
        CALayer.render(self, in: context, root: true)
    }
}

// MARK: - Rendering

extension CALayer {
    /// Draws `layer` as it presents: its background, its content, its
    /// sublayers by zPosition, then its border, at its opacity and clipped
    /// when it masks to its bounds.
    static func render(_ layer: CALayer, in context: CGRef, root: Bool = false, parent: LayerState? = nil) {
        let (state, shape) = Presentation.presented(layer)
        layer.state.rendered = true
        guard !state.hidden, state.opacity > 0 else { return }
        CG.saveGState(context)
        defer { CG.restoreGState(context) }
        if !root { CG.concatCTM(context, state.toSuperlayer(within: parent)) }
        let group = state.opacity < 1
        if group {
            CG.setAlpha(context, CGFloat(state.opacity))
            CG.beginTransparencyLayer(context, nil)
        }
        if let masked = maskedImage(of: layer, state: state, shape: shape) {
            CG.drawFlipped(masked.object, in: state.bounds, context: context)
        } else {
            drawTree(of: layer, state: state, shape: shape, in: context)
        }
        if group { CG.endTransparencyLayer(context) }
    }

    /// The layer's own drawing and its sublayers', in its coordinates.
    static func drawTree(of layer: CALayer, state: LayerState, shape: ShapeLayerState?, in context: CGRef) {
        drawBackground(of: state, in: context)
        CG.saveGState(context)
        if state.masksToBounds { clip(to: state, in: context) }
        drawContent(of: layer, state: state, shape: shape, in: context)
        for sublayer in orderedSublayers(of: state) { render(sublayer, in: context, parent: state) }
        CG.restoreGState(context)
        drawBorder(of: state, in: context)
    }

    /// A layer with a mask, drawn with its sublayers into an image of its
    /// bounds where the mask layer, drawn in its coordinates, is opaque;
    /// nil without a mask.
    static func maskedImage(of layer: CALayer, state: LayerState, shape: ShapeLayerState?) -> Owned? {
        guard let mask = state.mask, state.bounds.width > 0, state.bounds.height > 0 else { return nil }
        let scale = max(state.contentsScale, mask.state.contentsScale, 1)
        guard let content = CG.makeContext(size: state.bounds.size, scale: scale, opaque: false),
              let alpha = CG.makeContext(size: state.bounds.size, scale: scale, opaque: false) else { return nil }
        defer {
            CG.release(content)
            CG.release(alpha)
        }
        CG.translateCTM(content, -state.bounds.minX, -state.bounds.minY)
        drawTree(of: layer, state: state, shape: shape, in: content)
        CG.translateCTM(alpha, -state.bounds.minX, -state.bounds.minY)
        render(mask, in: alpha, parent: state)
        guard let maskImage = CG.bitmapContextCreateImage(alpha) else { return nil }
        defer { CG.release(maskImage) }
        // kCGBlendModeDestinationIn: the content stays where the mask is.
        CG.saveGState(content)
        CG.setBlendMode(content, 22)
        CG.drawFlipped(maskImage, in: state.bounds, context: content)
        CG.restoreGState(content)
        return CG.bitmapContextCreateImage(content).map(Owned.init)
    }

    /// The sublayers back to front: by zPosition, then in order.
    static func orderedSublayers(of state: LayerState) -> [CALayer] {
        state.sublayers.enumerated().sorted {
            ($0.element.state.zPosition, $0.offset) < ($1.element.state.zPosition, $1.offset)
        }.map(\.element)
    }

    /// The background color, in the shape of the corners.
    static func drawBackground(of state: LayerState, in context: CGRef) {
        guard let background = state.backgroundColor else { return }
        CG.setFillColorWithColor(context, background)
        if state.cornerRadius > 0, let shape = roundedRect(state.bounds, radius: state.cornerRadius, corners: state.maskedCorners) {
            CG.addPath(context, shape.object)
            CG.fillPath(context)
        } else {
            CG.fillRect(context, state.bounds)
        }
    }

    /// Clips to the bounds, in the shape of the corners.
    static func clip(to state: LayerState, in context: CGRef) {
        if state.cornerRadius > 0, let shape = roundedRect(state.bounds, radius: state.cornerRadius, corners: state.maskedCorners) {
            CG.addPath(context, shape.object)
            CG.clip(context)
        } else {
            CG.clipToRect(context, state.bounds)
        }
    }

    /// Displays the layer if it needs to, then draws what it displayed, its
    /// contents, and a shape layer's path.
    static func drawContent(of layer: CALayer, state: LayerState, shape: ShapeLayerState?, in context: CGRef) {
        displayIfNeeded(layer)
        let model = layer.state
        if let backing = model.backing {
            CG.drawFlipped(backing, in: CGRect(origin: state.bounds.origin, size: model.backingSize), context: context)
        }
        if let contents = state.contents {
            drawContents(contents, of: state, in: context)
        }
        if let shape, let shapeLayer = layer.as(CAShapeLayer.self) { shapeLayer.drawShape(shape, in: context) }
    }

    /// Displays a layer that draws when it needs to.
    static func displayIfNeeded(_ layer: CALayer) {
        let state = layer.state
        let delegate = state.delegate.map { NSObject($0) }
        let redraws = delegate.map { $0.responds(to: "_perryLayerContentChanged:") && $0.sendContentChanged(layer) } ?? false
        let undrawn = state.backing == nil && !state.displayedByDelegate
        if layer.draws, redraws || state.needsDisplay || undrawn || state.backingSize != state.bounds.size {
            layer.sendDisplay()
        }
    }

    /// The border, inside the bounds and over the sublayers.
    static func drawBorder(of state: LayerState, in context: CGRef) {
        guard state.borderWidth > 0, let border = state.borderColor else { return }
        let bounds = state.bounds, half = state.borderWidth / 2
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

    /// A rounded rectangle, with the radius limited to half the sides.
    /// CACornerMask's min-x min-y, max-x min-y, min-x max-y and max-x max-y
    /// corners are the top left, top right, bottom left and bottom right.
    static func roundedRect(_ rect: CGRect, radius: CGFloat, corners: UInt) -> Owned? {
        guard let path = CG.pathCreateMutable() else { return nil }
        let r = min(max(radius, 0), rect.width / 2, rect.height / 2)
        guard r > 0 else {
            CG.pathAddRect(path, nil, rect)
            return Owned(path)
        }
        let (topLeft, topRight, bottomLeft, bottomRight) = (corners & 1 != 0, corners & 2 != 0, corners & 4 != 0, corners & 8 != 0)
        CG.pathMoveToPoint(path, nil, rect.minX + (topLeft ? r : 0), rect.minY)
        if topRight {
            CG.pathAddLineToPoint(path, nil, rect.maxX - r, rect.minY)
            CG.pathAddArc(path, nil, rect.maxX - r, rect.minY + r, r, -.pi / 2, 0, false)
        } else {
            CG.pathAddLineToPoint(path, nil, rect.maxX, rect.minY)
        }
        if bottomRight {
            CG.pathAddLineToPoint(path, nil, rect.maxX, rect.maxY - r)
            CG.pathAddArc(path, nil, rect.maxX - r, rect.maxY - r, r, 0, .pi / 2, false)
        } else {
            CG.pathAddLineToPoint(path, nil, rect.maxX, rect.maxY)
        }
        if bottomLeft {
            CG.pathAddLineToPoint(path, nil, rect.minX + r, rect.maxY)
            CG.pathAddArc(path, nil, rect.minX + r, rect.maxY - r, r, .pi / 2, .pi, false)
        } else {
            CG.pathAddLineToPoint(path, nil, rect.minX, rect.maxY)
        }
        if topLeft {
            CG.pathAddLineToPoint(path, nil, rect.minX, rect.minY + r)
            CG.pathAddArc(path, nil, rect.minX + r, rect.minY + r, r, .pi, 3 * .pi / 2, false)
        } else {
            CG.pathAddLineToPoint(path, nil, rect.minX, rect.minY)
        }
        CG.pathCloseSubpath(path)
        return Owned(path)
    }

    /// A CGImage, or an object with one (a UIImage), placed by the contents
    /// gravity.
    static func drawContents(_ contents: NSObject, of state: LayerState, in context: CGRef) {
        let image = contents.responds(to: "CGImage") ? contents.sendCGImage() : contents.objcObject
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

/// A CoreGraphics object released when its owner goes.
final class Owned {
    let object: CGRef

    init(_ object: CGRef) { self.object = object }
    deinit { CG.release(object) }
}

/// CALayer's messages, sent so subclasses' overrides and delegates run.
extension NSObject {
    @ObjCMethod("layoutSublayers") func sendLayoutSublayers()
    @ObjCMethod("layoutSublayersOfLayer:") func sendLayoutSublayers(of layer: CALayer)
    @ObjCMethod("display") func sendDisplay()
    @ObjCMethod("displayLayer:") func sendDisplay(_ layer: CALayer)
    @ObjCMethod("drawInContext:") func sendDraw(in context: UnsafeMutableRawPointer?)
    @ObjCMethod("drawLayer:inContext:") func sendDrawLayer(_ layer: CALayer, in context: UnsafeMutableRawPointer?)
    @ObjCMethod("actionForLayer:forKey:") func sendAction(for layer: CALayer, forKey key: String) -> NSObject?
    @ObjCMethod("objectForKey:") func sendObject(forKey key: String) -> NSObject?
    @ObjCMethod("CGImage") func sendCGImage() -> UnsafeMutableRawPointer?
    @ObjCMethod("_perryDrawsLayer:") func sendDraws(_ layer: CALayer) -> Bool
    @ObjCMethod("_perryLayerContentChanged:") func sendContentChanged(_ layer: CALayer) -> Bool
    @ObjCMethod("runActionForKey:object:arguments:")
    func sendRunAction(forKey key: String, object: NSObject, arguments: NSObject?)
}

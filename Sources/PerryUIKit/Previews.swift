import CPerryGeometry
import PerryObjCInterop

// Targeted previews, pointer styles and context menu configurations: what
// an app gives the pointer and context menu interactions, which show no
// pointer or menu here. Each keeps what it was made with, for the app to
// read back and for the interactions to have something to answer with.

@ObjCClass("UIPreviewParameters")
open class UIPreviewParameters: NSObject {
    var visible: UIBezierPath?
    var shadow: UIBezierPath?
    var background: UIColor?

    @ObjCMethod("init") public required override init() { super.init() }

    /// Parameters for text: the visible path is the lines' rectangles.
    @ObjCMethod("initWithTextLineRects:")
    public required init(textLineRects: NSObject) {
        super.init()
        let path = UIBezierPath.bezierPath(UIBezierPath.objCClass)
        for value in textLineRects.as(NSArray.self)?.elements ?? [] {
            path.append(UIBezierPath.bezierPath(UIBezierPath.objCClass, rect: value.sendCGRectValue()))
        }
        visible = path
    }

    @ObjCMethod("visiblePath") func visiblePath() -> UIBezierPath? { visible }
    @ObjCMethod("setVisiblePath:") func setVisiblePath(_ path: UIBezierPath?) { visible = path }
    @ObjCMethod("shadowPath") func shadowPath() -> UIBezierPath? { shadow }
    @ObjCMethod("setShadowPath:") func setShadowPath(_ path: UIBezierPath?) { shadow = path }
    @ObjCMethod("backgroundColor") func backgroundColor() -> UIColor? { background }
    @ObjCMethod("setBackgroundColor:") func setBackgroundColor(_ color: UIColor?) { background = color }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
        let copy = UIPreviewParameters.objCClass.object.newInstance().unsafeCast(to: UIPreviewParameters.self)
        (copy.visible, copy.shadow, copy.background) = (visible, shadow, background)
        return ObjCRuntime.retain(copy.objcObject)!
    }
}

/// Where a preview goes: a container view, a point in it and a transform.
@ObjCClass("UIPreviewTarget")
open class UIPreviewTarget: NSObject {
    var targetContainer: UIView?
    var targetCenter = CGPoint.zero
    var targetTransform = CGAffineTransform.identity

    @ObjCMethod("initWithContainer:center:")
    public required init(container: UIView?, center: CGPoint) {
        super.init()
        (targetContainer, targetCenter) = (container, center)
    }

    @ObjCMethod("initWithContainer:center:transform:")
    public required init(container: UIView?, center: CGPoint, transform: CGAffineTransform) {
        super.init()
        (targetContainer, targetCenter, targetTransform) = (container, center, transform)
    }

    @ObjCMethod("container") func container() -> UIView? { targetContainer }
    @ObjCMethod("center") func center() -> CGPoint { targetCenter }
    @ObjCMethod("transform") func transform() -> CGAffineTransform { targetTransform }
}

/// A view shown as a preview: the view, how, and where; without a target,
/// the view's superview at its center.
@ObjCClass("UITargetedPreview")
open class UITargetedPreview: NSObject {
    var previewView: UIView?
    var previewParameters: UIPreviewParameters?
    var previewTarget: UIPreviewTarget?

    @ObjCMethod("initWithView:")
    public required init(view: UIView?) {
        super.init()
        previewView = view
    }

    @ObjCMethod("initWithView:parameters:")
    public required init(view: UIView?, parameters: UIPreviewParameters?) {
        super.init()
        (previewView, previewParameters) = (view, parameters)
    }

    @ObjCMethod("initWithView:parameters:target:")
    public required init(view: UIView?, parameters: UIPreviewParameters?, target: UIPreviewTarget?) {
        super.init()
        (previewView, previewParameters, previewTarget) = (view, parameters, target)
    }

    @ObjCMethod("view") func view() -> UIView? { previewView }

    @ObjCMethod("parameters")
    func parameters() -> UIPreviewParameters? {
        if previewParameters == nil {
            previewParameters = UIPreviewParameters.objCClass.object.newInstance().unsafeCast(to: UIPreviewParameters.self)
        }
        return previewParameters
    }

    @ObjCMethod("target")
    func target() -> UIPreviewTarget? {
        if let previewTarget { return previewTarget }
        guard let view = previewView, let superview = view.state.superview.map({ NSObject($0).unsafeCast(to: UIView.self) }) else { return nil }
        let frame = view.state.frame
        return UIPreviewTarget(container: superview, center: CGPoint(x: frame.midX, y: frame.midY))
    }

    @ObjCMethod("size") func size() -> CGSize { previewView?.state.bounds.size ?? .zero }

    @ObjCMethod("retargetedPreviewWithTarget:")
    func retargeted(with target: UIPreviewTarget?) -> UITargetedPreview {
        UITargetedPreview(view: previewView, parameters: previewParameters, target: target)
    }
}

// MARK: - Pointer effects, shapes and styles

/// A pointer effect: which kind, and the preview it applies to.
@ObjCClass("UIPointerEffect")
open class UIPointerEffectObject: NSObject {
    var effectPreview: UITargetedPreview?
    /// UIPointerEffectTintMode: none 0, overlay 1, underlay 2.
    var tintMode = 0
    var prefersShadow = false
    var prefersScaledContent = true

    @ObjCClassMethod("effectWithPreview:")
    static func effect(_ cls: ObjCClass, preview: UITargetedPreview?) -> NSObject {
        let effect = cls.object.newInstance().unsafeCast(to: UIPointerEffectObject.self)
        effect.effectPreview = preview
        return effect
    }

    @ObjCMethod("preview") func preview() -> UITargetedPreview? { effectPreview }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }
}

@ObjCClass("UIPointerHighlightEffect") open class UIPointerHighlightEffect: UIPointerEffectObject {}

@ObjCClass("UIPointerLiftEffect") open class UIPointerLiftEffect: UIPointerEffectObject {}

@ObjCClass("UIPointerHoverEffect")
open class UIPointerHoverEffect: UIPointerEffectObject {
    @ObjCMethod("preferredTintMode") func preferredTintMode() -> Int { tintMode }
    @ObjCMethod("setPreferredTintMode:") func setPreferredTintMode(_ mode: Int) { tintMode = mode }
    @ObjCMethod("prefersShadow") func shadow() -> Bool { prefersShadow }
    @ObjCMethod("setPrefersShadow:") func setPrefersShadow(_ value: Bool) { prefersShadow = value }
    @ObjCMethod("prefersScaledContent") func scaledContent() -> Bool { prefersScaledContent }
    @ObjCMethod("setPrefersScaledContent:") func setPrefersScaledContent(_ value: Bool) { prefersScaledContent = value }
}

/// A pointer's shape: a path, a rounded rectangle, or a text beam of a
/// length along an axis.
@ObjCClass("UIPointerShape")
open class UIPointerShape: NSObject {
    var path: UIBezierPath?
    var rect = CGRect.zero
    var cornerRadius: CGFloat = 0
    var beamLength: CGFloat = 0
    var beamAxis = 0

    private static func make(_ cls: ObjCClass) -> UIPointerShape { cls.object.newInstance().unsafeCast(to: UIPointerShape.self) }

    @ObjCClassMethod("shapeWithPath:")
    static func shape(_ cls: ObjCClass, path: UIBezierPath?) -> NSObject {
        let shape = make(cls)
        shape.path = path
        return shape
    }

    @ObjCClassMethod("shapeWithRoundedRect:")
    static func shape(_ cls: ObjCClass, roundedRect rect: CGRect) -> NSObject {
        let shape = make(cls)
        shape.rect = rect
        shape.cornerRadius = 8
        return shape
    }

    @ObjCClassMethod("shapeWithRoundedRect:cornerRadius:")
    static func shape(_ cls: ObjCClass, roundedRect rect: CGRect, cornerRadius: CGFloat) -> NSObject {
        let shape = make(cls)
        shape.rect = rect
        shape.cornerRadius = cornerRadius
        return shape
    }

    @ObjCClassMethod("beamWithPreferredLength:axis:")
    static func beam(_ cls: ObjCClass, preferredLength: CGFloat, axis: Int) -> NSObject {
        let shape = make(cls)
        shape.beamLength = preferredLength
        shape.beamAxis = axis
        return shape
    }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }
}

/// A pointer style: an effect and a shape, or the system's, or hidden.
@ObjCClass("UIPointerStyle")
open class UIPointerStyle: NSObject {
    var effect: UIPointerEffectObject?
    var shape: UIPointerShape?
    var hidden = false
    /// UIAxis of the axes the pointer is held to.
    var constrainedAxes = 0
    var accessories: NSArray?

    private static func make(_ cls: ObjCClass) -> UIPointerStyle { cls.object.newInstance().unsafeCast(to: UIPointerStyle.self) }

    @ObjCClassMethod("styleWithEffect:shape:")
    static func style(_ cls: ObjCClass, effect: UIPointerEffectObject?, shape: UIPointerShape?) -> NSObject {
        let style = make(cls)
        (style.effect, style.shape) = (effect, shape)
        return style
    }

    @ObjCClassMethod("styleWithShape:constrainedAxes:")
    static func style(_ cls: ObjCClass, shape: UIPointerShape?, constrainedAxes: Int) -> NSObject {
        let style = make(cls)
        (style.shape, style.constrainedAxes) = (shape, constrainedAxes)
        return style
    }

    @ObjCClassMethod("hiddenPointerStyle")
    static func hidden(_ cls: ObjCClass) -> NSObject {
        let style = make(cls)
        style.hidden = true
        return style
    }

    @ObjCClassMethod("systemPointerStyle") static func system(_ cls: ObjCClass) -> NSObject { make(cls) }

    @ObjCMethod("accessories") func pointerAccessories() -> NSArray { accessories ?? NSMutableArray.of([]) }
    @ObjCMethod("setAccessories:") func setAccessories(_ value: NSArray?) { accessories = value }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }
}

// MARK: - Context menus

/// A context menu's configuration: its identifier and the blocks that make
/// its preview and its menu, which nothing calls as no menu is shown.
@ObjCClass("UIContextMenuConfiguration")
open class UIContextMenuConfiguration: NSObject {
    var configurationIdentifier: NSObject?
    var previewProvider: ObjCBlock?
    var actionProvider: ObjCBlock?
    /// UIContextMenuConfigurationElementOrder: automatic 0.
    var elementOrder = 0
    var secondaryItemIdentifiers: NSObject?
    var badgeCount = 0

    @ObjCClassMethod("configurationWithIdentifier:previewProvider:actionProvider:")
    static func configuration(_ cls: ObjCClass, identifier: NSObject?, previewProvider: ObjCBlock?, actionProvider: ObjCBlock?) -> NSObject {
        let configuration = cls.object.newInstance().unsafeCast(to: UIContextMenuConfiguration.self)
        configuration.configurationIdentifier = identifier
        configuration.previewProvider = previewProvider
        configuration.actionProvider = actionProvider
        return configuration
    }

    @ObjCMethod("identifier") func identifier() -> NSObject? { configurationIdentifier }
    @ObjCMethod("preferredMenuElementOrder") func preferredMenuElementOrder() -> Int { elementOrder }
    @ObjCMethod("setPreferredMenuElementOrder:") func setPreferredMenuElementOrder(_ order: Int) { elementOrder = order }
    @ObjCMethod("secondaryItemIdentifiers") func secondaryIdentifiers() -> NSObject? { secondaryItemIdentifiers }
    @ObjCMethod("setSecondaryItemIdentifiers:") func setSecondaryItemIdentifiers(_ value: NSObject?) { secondaryItemIdentifiers = value }
    @ObjCMethod("badgeCount") func badge() -> Int { badgeCount }
    @ObjCMethod("setBadgeCount:") func setBadgeCount(_ count: Int) { badgeCount = count }
}

extension NSObject {
    @ObjCMethod("CGRectValue") func sendCGRectValue() -> CGRect
}

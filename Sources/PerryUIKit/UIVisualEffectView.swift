import Glibc
import CPerryGeometry
import PerryObjCInterop

// UIVisualEffectView and its effects. A blur effect blurs what is behind
// the view, as far as the style says, under the material's tint, light or
// dark, behind the content view: the blur is a backdrop layer's, which the
// GPU compositor draws (PERRY_UIKIT_NO_BLUR shows the tint alone, as thick
// as the style says). A vibrancy effect shows its content as it is. The
// fill follows the view's corners, so a rounded panel stays rounded
// wherever it is drawn.

final class EffectState: ObjectState {
    /// UIBlurEffectStyle, or -1 for a vibrancy effect.
    var style = 1
    var vibrancy = false
}

@ObjCClass("UIVisualEffect")
open class UIVisualEffect: NSObject {
    static let states = StateTable<EffectState>()
    var effect: EffectState { UIVisualEffect.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        UIVisualEffect.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIVisualEffect.objCClass.pointer)
    }

    /// Effects are immutable.
    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }

    @ObjCMethod("initWithCoder:")
    func initialize(coder: NSObject) -> Self {
        effect.style = Coder(coder: coder).integer("UIBlurEffectStyle")
        return self
    }

    nonisolated(unsafe) static let blurs = getenv("PERRY_UIKIT_NO_BLUR") == nil

    /// How far the effect blurs, in points, and how much it saturates what
    /// is behind.
    var blur: (radius: CGFloat, saturation: CGFloat)? {
        guard !effect.vibrancy, UIVisualEffect.blurs else { return nil }
        switch effect.style {
        case 6, 11, 16: return (10, 1.6)
        case 7, 12, 17: return (15, 1.6)
        case 9, 14, 19: return (30, 1.8)
        default: return (22, 1.8)
        }
    }

    /// The fill the effect shows: gray level and opacity.
    var tint: (white: CGFloat, alpha: CGFloat)? {
        guard !effect.vibrancy else { return nil }
        // UIBlurEffectStyle: extra light 0, light 1, dark 2, extra dark 3,
        // regular 4, prominent 5, then the system materials from ultra thin
        // to chrome (6-10), in light (11-15) and dark (16-20).
        let style = effect.style
        let dark = style == 2 || style == 3 || (16...20).contains(style)
        let thickness: CGFloat
        switch style {
        case 6, 11, 16: thickness = 0.55
        case 7, 12, 17: thickness = 0.7
        case 9, 14, 19, 5: thickness = 0.9
        case 10, 15, 20: thickness = 0.85
        default: thickness = 0.8
        }
        // With no blur the tint stands in for it, more opaque than the
        // material's own.
        let opacity = UIVisualEffect.blurs ? 0.3 + thickness * 0.4 : 0.6 + thickness * 0.4
        if style == 0 { return (0.98, 0.92) }
        if style == 3 { return (0.05, 0.92) }
        return dark ? (0.12, opacity) : (0.96, opacity)
    }
}

@ObjCClass("UIBlurEffect")
open class UIBlurEffect: UIVisualEffect {
    @ObjCClassMethod("effectWithStyle:")
    static func effect(_ cls: ObjCClass, style: Int) -> UIBlurEffect {
        let effect = cls.object.allocated().initialized().unsafeCast(to: UIBlurEffect.self)
        effect.effect.style = style
        return effect
    }

    @ObjCMethod("style") func style() -> Int { effect.style }
}

@ObjCClass("UIVibrancyEffect")
open class UIVibrancyEffect: UIVisualEffect {
    @ObjCClassMethod("effectForBlurEffect:")
    static func effect(_ cls: ObjCClass, blurEffect: UIBlurEffect?) -> UIVibrancyEffect {
        let effect = cls.object.allocated().initialized().unsafeCast(to: UIVibrancyEffect.self)
        effect.effect.vibrancy = true
        return effect
    }

    @ObjCClassMethod("effectForBlurEffect:style:")
    static func effect(_ cls: ObjCClass, blurEffect: UIBlurEffect?, style: Int) -> UIVibrancyEffect { effect(cls, blurEffect: blurEffect) }
}

/// The view that blurs what is behind a visual effect view: its layer is a
/// backdrop's.
@ObjCClass("_UIVisualEffectBackdropView")
open class _UIVisualEffectBackdropView: UIView {
    @ObjCClassMethod("layerClass") static func backdropLayerClass() -> ObjCClass { ObjCClass(named: "CABackdropLayer") }
}

final class VisualEffectViewState: ObjectState {
    var effect: UIVisualEffect?
    var contentView: UIView?
    /// The effect's fill, behind the content view.
    var backdrop: UIView?
    /// The backdrop group, which apps read and write by key (LNPopupController does).
    var groupName: String?
}

/// The view a visual effect view's subviews go in, which nibs archive with
/// its own class.
@ObjCClass("_UIVisualEffectContentView")
open class _UIVisualEffectContentView: UIView {}

@ObjCClass("UIVisualEffectView")
open class UIVisualEffectView: UIView {
    static let effectViewStates = StateTable<VisualEffectViewState>()
    var effectView: VisualEffectViewState { UIVisualEffectView.effectViewStates[objcObject] }

    @ObjCMethod("dealloc")
    override func dealloc() {
        UIVisualEffectView.effectViewStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCMethod("initWithEffect:")
    func initialize(effect: UIVisualEffect?) -> Self {
        _ = initializeView(frame: .zero)
        setEffect(effect)
        return self
    }

    @ObjCMethod("initWithFrame:")
    override func initialize(frame: CGRect) -> Self {
        _ = super.initialize(frame: frame)
        makeSubviews(contentView: nil)
        return self
    }

    /// From a nib: the effect, and the content view among the subviews.
    @ObjCMethod("initWithCoder:")
    override func initialize(coder: NSObject) -> Self {
        _ = super.initialize(coder: coder)
        let decoded = Coder(coder: coder)
        let content = decoded.object("UIVisualEffectViewContentView")?.as(UIView.self)
        makeSubviews(contentView: content)
        setEffect(decoded.object("UIVisualEffectViewEffect")?.as(UIVisualEffect.self))
        return self
    }

    /// The fill, then the content view, each the size of the view.
    private func makeSubviews(contentView: UIView?) {
        let effectView = effectView
        guard effectView.contentView == nil else { return }
        let backdrop = _UIVisualEffectBackdropView.objCClass.object.allocated().initializeView(frame: state.bounds).unsafeCast(to: UIView.self)
        backdrop.state.userInteractionEnabled = false
        backdrop.setAutoresizingMask(18)
        insertSubview(backdrop, at: 0)
        let content = contentView ?? UIView.objCClass.object.allocated().initializeView(frame: state.bounds).unsafeCast(to: UIView.self)
        if content.state.superview != objcObject { addSubview(content) }
        content.sendSetFrame(state.bounds)
        content.setAutoresizingMask(18)
        (effectView.backdrop, effectView.contentView) = (backdrop, content)
    }

    @ObjCMethod("contentView") func contentView() -> UIView? { effectView.contentView }
    @ObjCMethod("effect") func effect() -> UIVisualEffect? { effectView.effect }
    @ObjCMethod("groupName") func groupName() -> String? { effectView.groupName }
    @ObjCMethod("setGroupName:") func setGroupName(_ name: String?) { effectView.groupName = name }

    @ObjCMethod("setEffect:")
    func setEffect(_ effect: UIVisualEffect?) {
        effectView.effect = effect
        let tint = effect?.tint
        effectView.backdrop?.setBackgroundColor(tint.map { UIColor.gray($0.white, $0.alpha) })
        if let backdrop = effectView.backdrop {
            // The blur, or none for no effect or a vibrancy's.
            let blur = effect?.blur ?? (radius: 0, saturation: 1)
            backdrop.state.layer.setBlur(radius: blur.radius, saturation: blur.saturation)
        }
    }

    /// The fill takes the view's corners.
    @ObjCMethod("layoutSubviews")
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let backdrop = effectView.backdrop else { return }
        backdrop.state.geometry.cornerRadius = state.geometry.cornerRadius
        backdrop.sendSetFrame(state.bounds)
        effectView.contentView?.sendSetFrame(state.bounds)
    }
}

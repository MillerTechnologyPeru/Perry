import CPerryGeometry
import PerryObjCInterop

// UISwitch, drawn as iOS draws it: a 51 × 31 capsule, gray when off and
// green (or its on tint) when on, with a white knob at the end it is
// switched to. A tap that lifts inside it flips it and sends value changed.

final class SwitchState: ObjectState {
    var on = false
    var onTintColor: UIColor?
    var thumbTintColor: UIColor?
    /// UISwitchStyle: automatic 0, checkbox 1, sliding 2.
    var preferredStyle = 0
}

@ObjCClass("UISwitch")
open class UISwitch: UIControl {
    static let switchStates = StateTable<SwitchState>()
    var switchState: SwitchState { UISwitch.switchStates[objcObject] }

    static let size = CGSize(width: 51, height: 31)

    @ObjCMethod("dealloc")
    override func dealloc() {
        UISwitch.switchStates.remove(objcObject)
        super.dealloc()
    }

    /// The switch's own size, whatever the frame's.
    @ObjCMethod("initWithFrame:")
    override func initialize(frame: CGRect) -> Self {
        _ = super.initialize(frame: CGRect(origin: frame.origin, size: UISwitch.size))
        return self
    }

    @ObjCMethod("initWithCoder:")
    override func initialize(coder: NSObject) -> Self {
        _ = super.initialize(coder: coder)
        let decoded = Coder(coder: coder)
        switchState.on = decoded.bool("UISwitchOn")
        switchState.onTintColor = decoded.object("UIOnTintColor")?.as(UIColor.self)
        return self
    }

    @ObjCMethod("isOn") func isOn() -> Bool { switchState.on }
    @ObjCMethod("setOn:") func setOn(_ on: Bool) { setOn(on, animated: false) }
    @ObjCMethod("setOn:animated:")
    func setOn(_ on: Bool, animated: Bool) {
        guard switchState.on != on else { return }
        switchState.on = on
        setNeedsDisplay()
    }

    @ObjCMethod("onTintColor") func onTintColor() -> UIColor? { switchState.onTintColor }
    @ObjCMethod("setOnTintColor:") func setOnTintColor(_ color: UIColor?) { switchState.onTintColor = color; setNeedsDisplay() }
    @ObjCMethod("thumbTintColor") func thumbTintColor() -> UIColor? { switchState.thumbTintColor }
    @ObjCMethod("setThumbTintColor:") func setThumbTintColor(_ color: UIColor?) { switchState.thumbTintColor = color; setNeedsDisplay() }
    @ObjCMethod("preferredStyle") func preferredStyle() -> Int { switchState.preferredStyle }
    @ObjCMethod("setPreferredStyle:") func setPreferredStyle(_ style: Int) { switchState.preferredStyle = style }
    /// Sliding, the only style drawn.
    @ObjCMethod("style") func style() -> Int { 2 }
    @ObjCMethod("title") func title() -> String? { nil }
    @ObjCMethod("setTitle:") func setTitle(_ title: String?) {}

    @ObjCMethod("intrinsicContentSize") func intrinsicContentSize() -> CGSize { UISwitch.size }
    @ObjCMethod("sizeThatFits:") override func sizeThatFits(_ size: CGSize) -> CGSize { UISwitch.size }

    // MARK: Touches

    @ObjCMethod("touchesBegan:withEvent:")
    override func touchesBegan(_ touches: NSObject, with event: NSObject?) {
        guard control.enabled else { return }
        control.tracking = true
    }

    @ObjCMethod("touchesMoved:withEvent:")
    override func touchesMoved(_ touches: NSObject, with event: NSObject?) {}

    /// Flips as a touch lifts inside, or near, it.
    @ObjCMethod("touchesEnded:withEvent:")
    override func touchesEnded(_ touches: NSObject, with event: NSObject?) {
        guard control.tracking else { return }
        control.tracking = false
        guard let touch = touches.as(NSSet.self)?.anyObject()?.as(UITouch.self),
              state.bounds.insetBy(-16).contains(touch.location(in: self)) else { return }
        switchState.on.toggle()
        setNeedsDisplay()
        sendActions(for: 1 << 12)
    }

    @ObjCMethod("touchesCancelled:withEvent:")
    override func touchesCancelled(_ touches: NSObject, with event: NSObject?) { control.tracking = false }

    // MARK: Drawing

    @ObjCMethod("drawRect:")
    override func draw(_ rect: CGRect) {
        guard let context = Graphics.current else { return }
        let bounds = state.bounds
        let track = CGRect(x: bounds.minX, y: bounds.midY - UISwitch.size.height / 2,
                           width: UISwitch.size.width, height: UISwitch.size.height)
        let on = switchState.on
        let trackColor = on ? (switchState.onTintColor ?? UIColor.systemGreen())
                            : UIColor.rgb(120.0 / 255, 120.0 / 255, 128.0 / 255, 0.16)
        fill(roundedRectPath(track, radius: track.height / 2, corners: 0xf), with: trackColor, in: context)
        let knobSide: CGFloat = 27
        let knob = CGRect(x: on ? track.maxX - 2 - knobSide : track.minX + 2, y: track.midY - knobSide / 2,
                          width: knobSide, height: knobSide)
        // A faint ring for the knob's shadow, then the knob.
        fill(roundedRectPath(knob.insetBy(-0.5), radius: knobSide / 2 + 0.5, corners: 0xf),
             with: UIColor.gray(0, 0.12), in: context)
        fill(roundedRectPath(knob, radius: knobSide / 2, corners: 0xf), with: switchState.thumbTintColor ?? UIColor.white(), in: context)
        if !control.enabled {
            fill(roundedRectPath(track, radius: track.height / 2, corners: 0xf), with: UIColor.gray(1, 0.5), in: context)
        }
    }

    private func fill(_ path: Owned?, with color: UIColor, in context: CGRef) {
        guard let path else { return }
        withExtendedLifetime(color) {
            CG.setFillColorWithColor(context, color.state.makeCGColor())
            CG.addPath(context, path.object)
            CG.fillPath(context)
        }
    }
}

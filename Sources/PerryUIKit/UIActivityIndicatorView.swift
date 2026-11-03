import CPerryGeometry
import Glibc
import PerryObjCInterop

// UIActivityIndicatorView: iOS's spinner, eight spokes fading around a
// circle. While it animates, its layer steps around once a second through
// a keyframe animation; stopped, it hides unless told not to.

final class ActivityIndicatorState: ObjectState {
    /// UIActivityIndicatorViewStyle: white large 0, white 1, gray 2,
    /// medium 100, large 101.
    var style = 100
    var color: UIColor?
    var animating = false
    var hidesWhenStopped = true
}

@ObjCClass("UIActivityIndicatorView")
open class UIActivityIndicatorView: UIView {
    static let indicatorStates = StateTable<ActivityIndicatorState>()
    var indicator: ActivityIndicatorState { UIActivityIndicatorView.indicatorStates[objcObject] }

    @ObjCMethod("dealloc")
    override func dealloc() {
        UIActivityIndicatorView.indicatorStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCMethod("initWithActivityIndicatorStyle:")
    func initialize(style: Int) -> Self {
        indicator.style = style
        let side = UIActivityIndicatorView.side(style)
        _ = initializeView(frame: CGRect(x: 0, y: 0, width: side, height: side))
        return self
    }

    @ObjCMethod("initWithFrame:")
    override func initialize(frame: CGRect) -> Self {
        _ = super.initialize(frame: frame)
        state.userInteractionEnabled = false
        state.hidden = true
        return self
    }

    @ObjCMethod("initWithCoder:")
    override func initialize(coder: NSObject) -> Self {
        _ = super.initialize(coder: coder)
        let decoded = Coder(coder: coder)
        let indicator = indicator
        if decoded.has("UIActivityIndicatorViewStyle") { indicator.style = decoded.integer("UIActivityIndicatorViewStyle") }
        indicator.color = decoded.object("UIColor")?.as(UIColor.self)
        indicator.hidesWhenStopped = !decoded.has("UIHidesWhenStopped") || decoded.bool("UIHidesWhenStopped")
        state.userInteractionEnabled = false
        if decoded.bool("UIAnimating") { startAnimating() } else if indicator.hidesWhenStopped { state.hidden = true }
        return self
    }

    /// 37 points across for the large styles, 20 for the others.
    private static func side(_ style: Int) -> CGFloat { style == 0 || style == 101 ? 37 : 20 }

    @ObjCMethod("activityIndicatorViewStyle") func activityIndicatorViewStyle() -> Int { indicator.style }
    @ObjCMethod("setActivityIndicatorViewStyle:")
    func setActivityIndicatorViewStyle(_ style: Int) {
        indicator.style = style
        setNeedsDisplay()
        invalidateIntrinsicContentSize()
    }

    /// The style's: white, gray, or the label's secondary gray.
    @ObjCMethod("color")
    func color() -> UIColor {
        if let color = indicator.color { return color }
        switch indicator.style {
        case 0, 1: return UIColor.white()
        case 2: return UIColor.gray(0.5)
        default: return UIColor.rgb(60.0 / 255, 60.0 / 255, 67.0 / 255, 0.6)
        }
    }

    @ObjCMethod("setColor:") func setColor(_ color: UIColor?) { indicator.color = color; setNeedsDisplay() }
    @ObjCMethod("hidesWhenStopped") func hidesWhenStopped() -> Bool { indicator.hidesWhenStopped }
    @ObjCMethod("setHidesWhenStopped:")
    func setHidesWhenStopped(_ hides: Bool) {
        indicator.hidesWhenStopped = hides
        if !indicator.animating { setHidden(hides) }
    }

    @ObjCMethod("isAnimating") func isAnimating() -> Bool { indicator.animating }

    /// Shows and turns, a spoke's step at a time.
    @ObjCMethod("startAnimating")
    func startAnimating() {
        guard !indicator.animating else { return }
        indicator.animating = true
        setHidden(false)
        let turn = CAKeyframeAnimation.make(keyPath: "transform.rotation.z")
        turn.setValues(NSMutableArray.of((0..<8).map { NSNumber.make(double: Double($0) * .pi / 4) }))
        turn.setCalculationMode("discrete")
        turn.setDuration(1)
        turn.setRepeatCount(.infinity)
        state.layer.addAnimation(turn, forKey: "perry.activityIndicator.turn")
    }

    @ObjCMethod("stopAnimating")
    func stopAnimating() {
        guard indicator.animating else { return }
        indicator.animating = false
        state.layer.removeAnimation(forKey: "perry.activityIndicator.turn")
        if indicator.hidesWhenStopped { setHidden(true) }
    }

    @ObjCMethod("intrinsicContentSize")
    func intrinsicContentSize() -> CGSize {
        let side = UIActivityIndicatorView.side(indicator.style)
        return CGSize(width: side, height: side)
    }

    @ObjCMethod("sizeThatFits:")
    override func sizeThatFits(_ size: CGSize) -> CGSize { intrinsicContentSize() }

    /// Eight rounded spokes, the leading one darkest, fading behind it.
    @ObjCMethod("drawRect:")
    override func draw(_ rect: CGRect) {
        guard let context = Graphics.current else { return }
        let bounds = state.bounds
        let side = min(bounds.width, bounds.height)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let outer = side / 2, inner = side * 0.22, width = max(side * 0.09, 1.5)
        let color = color()
        let components = (color.state.red, color.state.green, color.state.blue, color.state.alpha)
        CG.saveGState(context)
        CG.setLineWidth(context, width)
        CG.setLineCap(context, 1)
        for spoke in 0..<8 {
            // Clockwise from the top, the brightest last drawn ahead.
            let angle = -CGFloat.pi / 2 + CGFloat(spoke) * .pi / 4
            let level = 1 - CGFloat((8 - spoke) % 8) * 0.1
            let spokeColor = UIColor.rgb(components.0, components.1, components.2, components.3 * level)
            withExtendedLifetime(spokeColor) {
                CG.setStrokeColorWithColor(context, spokeColor.state.makeCGColor())
                guard let path = CG.pathCreateMutable() else { return }
                defer { CG.release(path) }
                CG.pathMoveToPoint(path, nil, center.x + cos(angle) * inner, center.y + sin(angle) * inner)
                CG.pathAddLineToPoint(path, nil, center.x + cos(angle) * (outer - width / 2), center.y + sin(angle) * (outer - width / 2))
                CG.addPath(context, path)
                CG.strokePath(context)
            }
        }
        CG.restoreGState(context)
    }
}

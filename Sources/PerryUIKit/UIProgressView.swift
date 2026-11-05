import CPerryGeometry
import PerryObjCInterop

// UIProgressView, drawn as iOS draws it: a 4-point capsule track, gray (or
// the track tint or image), filled from the leading edge to the progress
// with the tint color (or the progress tint or image).

final class ProgressViewState: ObjectState {
    var progress: Float = 0
    /// UIProgressViewStyle: default 0, bar 1.
    var style = 0
    var progressTintColor: UIColor?
    var trackTintColor: UIColor?
    var progressImage: UIImage?
    var trackImage: UIImage?
    var observedProgress: NSObject?
}

@ObjCClass("UIProgressView")
open class UIProgressView: UIView {
    static let progressStates = StateTable<ProgressViewState>()
    var progressState: ProgressViewState { UIProgressView.progressStates[objcObject] }

    static let trackHeight: CGFloat = 4

    @ObjCMethod("dealloc")
    override func dealloc() {
        UIProgressView.progressStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCMethod("initWithProgressViewStyle:")
    func initialize(style: Int) -> NSObject {
        let view = initializeView(frame: CGRect(origin: .zero, size: CGSize(width: 150, height: UIProgressView.trackHeight)))
        UIProgressView.progressStates[view.objcObject].style = style
        return view
    }

    @ObjCMethod("initWithCoder:")
    override func initialize(coder: NSObject) -> Self {
        _ = super.initialize(coder: coder)
        let decoded = Coder(coder: coder)
        let s = progressState
        if decoded.has("UIProgress") { s.progress = min(max(Float(decoded.double("UIProgress")), 0), 1) }
        if decoded.has("UIProgressViewStyle") { s.style = decoded.integer("UIProgressViewStyle") }
        s.progressTintColor = decoded.object("UIProgressTintColor")?.as(UIColor.self)
        s.trackTintColor = decoded.object("UITrackTintColor")?.as(UIColor.self)
        return self
    }

    @ObjCMethod("progress") func progress() -> Float { progressState.progress }
    @ObjCMethod("setProgress:") func setProgress(_ progress: Float) { setProgress(progress, animated: false) }
    @ObjCMethod("setProgress:animated:")
    func setProgress(_ progress: Float, animated: Bool) {
        progressState.progress = progress.isNaN ? 0 : min(max(progress, 0), 1)
        setNeedsDisplay()
    }

    @ObjCMethod("progressViewStyle") func progressViewStyle() -> Int { progressState.style }
    @ObjCMethod("setProgressViewStyle:") func setProgressViewStyle(_ style: Int) { progressState.style = style; setNeedsDisplay() }
    @ObjCMethod("progressTintColor") func progressTintColor() -> UIColor? { progressState.progressTintColor }
    @ObjCMethod("setProgressTintColor:")
    func setProgressTintColor(_ color: UIColor?) { progressState.progressTintColor = color; setNeedsDisplay() }
    @ObjCMethod("trackTintColor") func trackTintColor() -> UIColor? { progressState.trackTintColor }
    @ObjCMethod("setTrackTintColor:")
    func setTrackTintColor(_ color: UIColor?) { progressState.trackTintColor = color; setNeedsDisplay() }
    @ObjCMethod("progressImage") func progressImage() -> UIImage? { progressState.progressImage }
    @ObjCMethod("setProgressImage:")
    func setProgressImage(_ image: UIImage?) { progressState.progressImage = image; setNeedsDisplay() }
    @ObjCMethod("trackImage") func trackImage() -> UIImage? { progressState.trackImage }
    @ObjCMethod("setTrackImage:")
    func setTrackImage(_ image: UIImage?) { progressState.trackImage = image; setNeedsDisplay() }
    @ObjCMethod("observedProgress") func observedProgress() -> NSObject? { progressState.observedProgress }
    @ObjCMethod("setObservedProgress:") func setObservedProgress(_ progress: NSObject?) { progressState.observedProgress = progress }

    @ObjCMethod("sizeThatFits:")
    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: UIProgressView.trackHeight) }

    @ObjCMethod("drawRect:")
    override func draw(_ rect: CGRect) {
        guard let context = Graphics.current else { return }
        let bounds = state.bounds
        let height = min(bounds.height, UIProgressView.trackHeight)
        let track = CGRect(x: bounds.minX, y: bounds.midY - height / 2, width: bounds.width, height: height)
        let s = progressState
        let filled = CGRect(x: track.minX, y: track.minY, width: track.width * CGFloat(s.progress), height: height)
        let radius = s.style == 1 ? 0 : height / 2
        if let image = s.trackImage {
            image.draw(in: track)
        } else {
            fill(roundedRectPath(track, radius: radius, corners: 0xf), with: s.trackTintColor ?? UIColor.systemFill(), in: context)
        }
        if let image = s.progressImage {
            image.draw(in: filled)
        } else if filled.width > 0 {
            fill(roundedRectPath(filled, radius: radius, corners: 0xf), with: s.progressTintColor ?? tintColor(), in: context)
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

// GameController's GCEventViewController: a view controller that, with
// controller interaction off, keeps game controller input from UIKit. Here
// controllers never drive UIKit, so it is a plain view controller.

final class EventViewControllerState: ObjectState {
    var controllerUserInteractionEnabled = false
}

@ObjCClass("GCEventViewController")
open class GCEventViewController: UIViewController {
    static let eventStates = StateTable<EventViewControllerState>()

    @ObjCMethod("dealloc")
    override func dealloc() {
        GCEventViewController.eventStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCMethod("controllerUserInteractionEnabled")
    func controllerUserInteractionEnabled() -> Bool { GCEventViewController.eventStates[objcObject].controllerUserInteractionEnabled }
    @ObjCMethod("setControllerUserInteractionEnabled:")
    func setControllerUserInteractionEnabled(_ enabled: Bool) {
        GCEventViewController.eventStates[objcObject].controllerUserInteractionEnabled = enabled
    }
}

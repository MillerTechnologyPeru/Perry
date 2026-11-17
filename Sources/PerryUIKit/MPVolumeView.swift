import CPerryGeometry
import PerryObjCInterop

// MPVolumeView, MediaPlayer's volume slider and route button. There is no
// system volume here to follow and no wireless route to pick: the view
// holds a slider, as apps that look for it among the subviews expect, and
// keeps the settings it is given.

final class VolumeViewState: ObjectState {
    var showsRouteButton = true
    var showsVolumeSlider = true
    var slider: UISlider?
    var images: [String: UIImage] = [:]
}

@ObjCClass("MPVolumeView")
open class MPVolumeView: UIView {
    static let volumeStates = StateTable<VolumeViewState>()
    var volume: VolumeViewState { MPVolumeView.volumeStates[objcObject] }

    @ObjCMethod("dealloc")
    override func dealloc() {
        MPVolumeView.volumeStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCMethod("initWithFrame:")
    override func initialize(frame: CGRect) -> Self {
        _ = super.initialize(frame: frame)
        makeSlider()
        return self
    }

    @ObjCMethod("initWithCoder:")
    override func initialize(coder: NSObject) -> Self {
        _ = super.initialize(coder: coder)
        makeSlider()
        return self
    }

    private func makeSlider() {
        guard volume.slider == nil else { return }
        let slider = UISlider.objCClass.object.allocated().initializeView(frame: state.bounds).unsafeCast(to: UISlider.self)
        slider.setAutoresizingMask(2)
        slider.setValue(1)
        addSubview(slider)
        volume.slider = slider
    }

    @ObjCMethod("showsRouteButton") func showsRouteButton() -> Bool { volume.showsRouteButton }
    @ObjCMethod("setShowsRouteButton:") func setShowsRouteButton(_ shows: Bool) { volume.showsRouteButton = shows }
    @ObjCMethod("showsVolumeSlider") func showsVolumeSlider() -> Bool { volume.showsVolumeSlider }
    @ObjCMethod("setShowsVolumeSlider:")
    func setShowsVolumeSlider(_ shows: Bool) {
        volume.showsVolumeSlider = shows
        volume.slider?.setHidden(!shows)
    }

    @ObjCMethod("isWirelessRouteActive") func isWirelessRouteActive() -> Bool { false }
    @ObjCMethod("areWirelessRoutesAvailable") func areWirelessRoutesAvailable() -> Bool { false }

    @ObjCMethod("setMinimumVolumeSliderImage:forState:")
    func setMinimumVolumeSliderImage(_ image: UIImage?, for state: UInt) { volume.slider?.setMinimumTrackImage(image, for: state) }
    @ObjCMethod("setMaximumVolumeSliderImage:forState:")
    func setMaximumVolumeSliderImage(_ image: UIImage?, for state: UInt) { volume.slider?.setMaximumTrackImage(image, for: state) }
    @ObjCMethod("setVolumeThumbImage:forState:")
    func setVolumeThumbImage(_ image: UIImage?, for state: UInt) { volume.slider?.setThumbImage(image, for: state) }

    @ObjCMethod("volumeSliderRectForBounds:")
    func volumeSliderRect(forBounds bounds: CGRect) -> CGRect { bounds }
    @ObjCMethod("routeButtonRectForBounds:")
    func routeButtonRect(forBounds bounds: CGRect) -> CGRect { .zero }
    @ObjCMethod("volumeThumbRectForBounds:volumeSliderRect:value:")
    func volumeThumbRect(forBounds bounds: CGRect, volumeSliderRect rect: CGRect, value: Float) -> CGRect {
        CGRect(x: rect.minX + CGFloat(value) * (rect.width - 28), y: rect.midY - 14, width: 28, height: 28)
    }
}

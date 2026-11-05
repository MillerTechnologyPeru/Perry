import CPerryGeometry
import PerryObjCInterop

// UISlider, drawn as iOS draws it: a 4-point capsule track, tinted (the
// tint color by default) left of the thumb and gray right of it, and a
// 28-point white thumb, or the images the app sets. Dragging moves the
// thumb with the touch and sends value changed: as it moves when the
// slider is continuous, once it lifts otherwise.

final class SliderState: ObjectState {
    var value: Float = 0
    var minimumValue: Float = 0
    var maximumValue: Float = 1
    var continuous = true
    var minimumTrackTintColor: UIColor?
    var maximumTrackTintColor: UIColor?
    var thumbTintColor: UIColor?
    var minimumValueImage: UIImage?
    var maximumValueImage: UIImage?
    /// Images by UIControlState: normal 0, highlighted 1, disabled 2, selected 4.
    var thumbImages: [UInt: UIImage] = [:]
    var minimumTrackImages: [UInt: UIImage] = [:]
    var maximumTrackImages: [UInt: UIImage] = [:]
    /// Where in the thumb the drag began, so the thumb doesn't jump to it.
    var grabOffset: CGFloat = 0
}

@ObjCClass("UISlider")
open class UISlider: UIControl {
    static let sliderStates = StateTable<SliderState>()
    var slider: SliderState { UISlider.sliderStates[objcObject] }

    static let thumbSide: CGFloat = 28
    static let trackHeight: CGFloat = 4

    @ObjCMethod("dealloc")
    override func dealloc() {
        UISlider.sliderStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCMethod("initWithCoder:")
    override func initialize(coder: NSObject) -> Self {
        _ = super.initialize(coder: coder)
        let decoded = Coder(coder: coder)
        let s = slider
        if decoded.has("UIMinValue") { s.minimumValue = Float(decoded.double("UIMinValue")) }
        if decoded.has("UIMaxValue") { s.maximumValue = Float(decoded.double("UIMaxValue")) }
        if decoded.has("UIValue") { s.value = Float(decoded.double("UIValue")) }
        if decoded.has("UIContinuous") { s.continuous = decoded.bool("UIContinuous") }
        s.minimumTrackTintColor = decoded.object("UIMinimumTintColor")?.as(UIColor.self)
        s.maximumTrackTintColor = decoded.object("UIMaximumTintColor")?.as(UIColor.self)
        s.thumbTintColor = decoded.object("UIThumbTintColor")?.as(UIColor.self)
        s.value = clamped(s.value)
        return self
    }

    private func clamped(_ value: Float) -> Float {
        let s = slider
        return min(max(value, s.minimumValue), max(s.minimumValue, s.maximumValue))
    }

    // MARK: Value

    @ObjCMethod("value") func value() -> Float { slider.value }
    @ObjCMethod("setValue:") func setValue(_ value: Float) { setValue(value, animated: false) }
    @ObjCMethod("setValue:animated:")
    func setValue(_ value: Float, animated: Bool) {
        slider.value = clamped(value)
        setNeedsDisplay()
    }

    @ObjCMethod("minimumValue") func minimumValue() -> Float { slider.minimumValue }
    @ObjCMethod("setMinimumValue:")
    func setMinimumValue(_ value: Float) {
        slider.minimumValue = value
        if slider.maximumValue < value { slider.maximumValue = value }
        slider.value = clamped(slider.value)
        setNeedsDisplay()
    }

    @ObjCMethod("maximumValue") func maximumValue() -> Float { slider.maximumValue }
    @ObjCMethod("setMaximumValue:")
    func setMaximumValue(_ value: Float) {
        slider.maximumValue = value
        if slider.minimumValue > value { slider.minimumValue = value }
        slider.value = clamped(slider.value)
        setNeedsDisplay()
    }

    @ObjCMethod("isContinuous") func isContinuous() -> Bool { slider.continuous }
    @ObjCMethod("setContinuous:") func setContinuous(_ continuous: Bool) { slider.continuous = continuous }

    // MARK: Appearance

    @ObjCMethod("minimumTrackTintColor") func minimumTrackTintColor() -> UIColor? { slider.minimumTrackTintColor }
    @ObjCMethod("setMinimumTrackTintColor:")
    func setMinimumTrackTintColor(_ color: UIColor?) { slider.minimumTrackTintColor = color; setNeedsDisplay() }
    @ObjCMethod("maximumTrackTintColor") func maximumTrackTintColor() -> UIColor? { slider.maximumTrackTintColor }
    @ObjCMethod("setMaximumTrackTintColor:")
    func setMaximumTrackTintColor(_ color: UIColor?) { slider.maximumTrackTintColor = color; setNeedsDisplay() }
    @ObjCMethod("thumbTintColor") func thumbTintColor() -> UIColor? { slider.thumbTintColor }
    @ObjCMethod("setThumbTintColor:") func setThumbTintColor(_ color: UIColor?) { slider.thumbTintColor = color; setNeedsDisplay() }

    @ObjCMethod("minimumValueImage") func minimumValueImage() -> UIImage? { slider.minimumValueImage }
    @ObjCMethod("setMinimumValueImage:") func setMinimumValueImage(_ image: UIImage?) { slider.minimumValueImage = image; setNeedsDisplay() }
    @ObjCMethod("maximumValueImage") func maximumValueImage() -> UIImage? { slider.maximumValueImage }
    @ObjCMethod("setMaximumValueImage:") func setMaximumValueImage(_ image: UIImage?) { slider.maximumValueImage = image; setNeedsDisplay() }

    @ObjCMethod("setThumbImage:forState:")
    func setThumbImage(_ image: UIImage?, for state: UInt) { slider.thumbImages[state] = image; setNeedsDisplay() }
    @ObjCMethod("thumbImageForState:") func thumbImage(for state: UInt) -> UIImage? { slider.thumbImages[state] }
    @ObjCMethod("setMinimumTrackImage:forState:")
    func setMinimumTrackImage(_ image: UIImage?, for state: UInt) { slider.minimumTrackImages[state] = image; setNeedsDisplay() }
    @ObjCMethod("minimumTrackImageForState:") func minimumTrackImage(for state: UInt) -> UIImage? { slider.minimumTrackImages[state] }
    @ObjCMethod("setMaximumTrackImage:forState:")
    func setMaximumTrackImage(_ image: UIImage?, for state: UInt) { slider.maximumTrackImages[state] = image; setNeedsDisplay() }
    @ObjCMethod("maximumTrackImageForState:") func maximumTrackImage(for state: UInt) -> UIImage? { slider.maximumTrackImages[state] }

    /// The image for the control's state, else the normal one.
    private func current(_ images: [UInt: UIImage]) -> UIImage? {
        let state: UInt = !control.enabled ? 2 : control.highlighted ? 1 : control.selected ? 4 : 0
        return images[state] ?? images[0]
    }

    @ObjCMethod("currentThumbImage") func currentThumbImage() -> UIImage? { current(slider.thumbImages) }
    @ObjCMethod("currentMinimumTrackImage") func currentMinimumTrackImage() -> UIImage? { current(slider.minimumTrackImages) }
    @ObjCMethod("currentMaximumTrackImage") func currentMaximumTrackImage() -> UIImage? { current(slider.maximumTrackImages) }

    // MARK: Geometry

    private var thumbSize: CGSize {
        currentThumbImage().map { $0.size() } ?? CGSize(width: UISlider.thumbSide, height: UISlider.thumbSide)
    }

    @ObjCMethod("minimumValueImageRectForBounds:")
    func minimumValueImageRect(forBounds bounds: CGRect) -> CGRect {
        guard let image = slider.minimumValueImage else { return CGRect(x: bounds.minX, y: bounds.midY, width: 0, height: 0) }
        let size = image.size()
        return CGRect(x: bounds.minX, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }

    @ObjCMethod("maximumValueImageRectForBounds:")
    func maximumValueImageRect(forBounds bounds: CGRect) -> CGRect {
        guard let image = slider.maximumValueImage else { return CGRect(x: bounds.maxX, y: bounds.midY, width: 0, height: 0) }
        let size = image.size()
        return CGRect(x: bounds.maxX - size.width, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }

    /// The track between the value images, as tall as its image or 4 points.
    @ObjCMethod("trackRectForBounds:")
    func trackRect(forBounds bounds: CGRect) -> CGRect {
        let left = minimumValueImageRect(forBounds: bounds), right = maximumValueImageRect(forBounds: bounds)
        let minX = left.width > 0 ? left.maxX + 8 : bounds.minX
        let maxX = right.width > 0 ? right.minX - 8 : bounds.maxX
        let height = currentMinimumTrackImage()?.size().height ?? UISlider.trackHeight
        return CGRect(x: minX, y: bounds.midY - height / 2, width: max(maxX - minX, 0), height: height)
    }

    /// The thumb at the value's place along the track, its ends at the
    /// track's ends.
    @ObjCMethod("thumbRectForBounds:trackRect:value:")
    func thumbRect(forBounds bounds: CGRect, trackRect track: CGRect, value: Float) -> CGRect {
        let size = thumbSize
        let s = slider
        let range = s.maximumValue - s.minimumValue
        let fraction = range > 0 ? CGFloat((min(max(value, s.minimumValue), s.maximumValue) - s.minimumValue) / range) : 0
        let x = track.minX + (track.width - size.width) * fraction
        return CGRect(x: x, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }

    private var currentThumbRect: CGRect {
        let bounds = state.bounds
        return thumbRect(forBounds: bounds, trackRect: trackRect(forBounds: bounds), value: slider.value)
    }

    /// No width of its own; as tall as the thumb.
    @ObjCMethod("intrinsicContentSize")
    func intrinsicContentSize() -> CGSize { CGSize(width: -1, height: max(thumbSize.height, 34) ) }

    @ObjCMethod("sizeThatFits:")
    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: max(size.width, 118), height: max(thumbSize.height, 34)) }

    // MARK: Touches

    private func value(at x: CGFloat) -> Float {
        let bounds = state.bounds
        let track = trackRect(forBounds: bounds)
        let travel = track.width - thumbSize.width
        guard travel > 0 else { return slider.minimumValue }
        let fraction = Float(min(max((x - slider.grabOffset - track.minX) / travel, 0), 1))
        return slider.minimumValue + fraction * (slider.maximumValue - slider.minimumValue)
    }

    @ObjCMethod("touchesBegan:withEvent:")
    override func touchesBegan(_ touches: NSObject, with event: NSObject?) {
        guard control.enabled, let touch = touches.as(NSSet.self)?.anyObject()?.as(UITouch.self) else { return }
        let point = touch.location(in: self)
        let thumb = currentThumbRect
        control.tracking = true
        control.highlighted = true
        if thumb.insetBy(-8).contains(point) {
            // Dragging the thumb from where it was grabbed.
            slider.grabOffset = point.x - thumb.minX
        } else {
            // Elsewhere on the track: the thumb's middle goes to the touch.
            slider.grabOffset = thumb.width / 2
            move(to: point.x)
        }
        sendActions(for: 1)
        setNeedsDisplay()
    }

    private func move(to x: CGFloat) {
        let new = value(at: x)
        guard new != slider.value else { return }
        slider.value = new
        setNeedsDisplay()
        if slider.continuous { sendActions(for: 1 << 12) }
    }

    @ObjCMethod("touchesMoved:withEvent:")
    override func touchesMoved(_ touches: NSObject, with event: NSObject?) {
        guard control.tracking, let touch = touches.as(NSSet.self)?.anyObject()?.as(UITouch.self) else { return }
        move(to: touch.location(in: self).x)
    }

    @ObjCMethod("touchesEnded:withEvent:")
    override func touchesEnded(_ touches: NSObject, with event: NSObject?) {
        guard control.tracking else { return }
        control.tracking = false
        control.highlighted = false
        if !slider.continuous { sendActions(for: 1 << 12) }
        sendActions(for: 1 << 6)
        setNeedsDisplay()
    }

    @ObjCMethod("touchesCancelled:withEvent:")
    override func touchesCancelled(_ touches: NSObject, with event: NSObject?) {
        control.tracking = false
        control.highlighted = false
        setNeedsDisplay()
    }

    // MARK: Drawing

    @ObjCMethod("drawRect:")
    override func draw(_ rect: CGRect) {
        guard let context = Graphics.current else { return }
        let bounds = state.bounds
        let track = trackRect(forBounds: bounds)
        let thumb = currentThumbRect
        slider.minimumValueImage?.draw(in: minimumValueImageRect(forBounds: bounds))
        slider.maximumValueImage?.draw(in: maximumValueImageRect(forBounds: bounds))
        let split = thumb.midX
        let left = CGRect(x: track.minX, y: track.minY, width: max(split - track.minX, 0), height: track.height)
        let right = CGRect(x: split, y: track.minY, width: max(track.maxX - split, 0), height: track.height)
        if let image = currentMinimumTrackImage() {
            image.draw(in: left)
        } else {
            fill(roundedRectPath(left, radius: track.height / 2, corners: 0x5), with: slider.minimumTrackTintColor ?? tintColor(), in: context)
        }
        if let image = currentMaximumTrackImage() {
            image.draw(in: right)
        } else {
            fill(roundedRectPath(right, radius: track.height / 2, corners: 0xa), with: slider.maximumTrackTintColor ?? UIColor.systemFill(),
                 in: context)
        }
        if let image = currentThumbImage() {
            image.draw(in: thumb)
        } else {
            // A faint ring for the thumb's shadow, then the thumb.
            fill(roundedRectPath(thumb.insetBy(-0.5), radius: thumb.height / 2 + 0.5, corners: 0xf), with: UIColor.gray(0, 0.15), in: context)
            fill(roundedRectPath(thumb, radius: thumb.height / 2, corners: 0xf), with: slider.thumbTintColor ?? UIColor.white(), in: context)
        }
        if !control.enabled {
            fill(roundedRectPath(bounds, radius: 0, corners: 0), with: UIColor.gray(1, 0.5), in: context)
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

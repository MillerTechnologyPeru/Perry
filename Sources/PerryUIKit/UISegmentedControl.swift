import CPerryGeometry
import PerryObjCInterop

// UISegmentedControl, drawn as iOS 13 and later draw it: a gray track with
// the selected segment raised on a white tile, its title in semibold. A
// tap on an enabled segment selects it as the touch lifts and sends value
// changed; a momentary control shows nothing selected. Nibs archive the
// segments as UISegment subviews, which the control reads and draws.

final class SegmentState: ObjectState {
    var title: String?
    var image: UIImage?
    var width: CGFloat = 0
    var enabled = true
}

/// One segment as a nib archives it.
@ObjCClass("UISegment")
open class UISegment: UIView {
    static let segmentStates = StateTable<SegmentState>()
    var segment: SegmentState { UISegment.segmentStates[objcObject] }

    @ObjCMethod("dealloc")
    override func dealloc() {
        UISegment.segmentStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCMethod("initWithCoder:")
    override func initialize(coder: NSObject) -> Self {
        _ = super.initialize(coder: coder)
        let decoded = Coder(coder: coder)
        let info = decoded.object("UISegmentInfo")
        if let image = info?.as(UIImage.self) { segment.image = image } else { segment.title = info?.stringValue }
        segment.width = decoded.double("UISegmentWidth")
        segment.enabled = !decoded.bool("UISegmentDisabled")
        return self
    }
}

final class SegmentedControlState: ObjectState {
    struct Segment {
        var title: String?
        var image: UIImage?
        /// Zero sizes the segment automatically.
        var width: CGFloat = 0
        var enabled = true
    }

    var segments: [Segment] = []
    var selected = -1
    /// The segment a touch is down on.
    var pressed: Int?
    var momentary = false
    var apportionsWidthsByContent = false
    var selectedTintColor: UIColor?
    var titleAttributes: [UInt: NSDictionary] = [:]
}

@ObjCClass("UISegmentedControl")
open class UISegmentedControl: UIControl {
    static let segmentedStates = StateTable<SegmentedControlState>()
    var segmented: SegmentedControlState { UISegmentedControl.segmentedStates[objcObject] }

    nonisolated(unsafe) private static let font = UIFont.systemFont(size: 13)
    nonisolated(unsafe) private static let selectedFont = UIFont.boldSystemFont(size: 13)

    @ObjCMethod("dealloc")
    override func dealloc() {
        UISegmentedControl.segmentedStates.remove(objcObject)
        super.dealloc()
    }

    /// Titles and images, one segment each.
    @ObjCMethod("initWithItems:")
    func initialize(items: NSArray?) -> Self {
        _ = initializeView(frame: .zero)
        segmented.segments = items?.elements.map(UISegmentedControl.segment) ?? []
        var frame = state.frame
        frame.size = intrinsicContentSize()
        setFrame(frame)
        return self
    }

    @ObjCMethod("initWithCoder:")
    override func initialize(coder: NSObject) -> Self {
        _ = super.initialize(coder: coder)
        let decoded = Coder(coder: coder)
        let nibSegments = decoded.array("UISegments").compactMap { $0.as(UISegment.self) }
        segmented.segments = nibSegments.map { nib in
            let segment = nib.segment
            return SegmentedControlState.Segment(title: segment.title, image: segment.image, width: segment.width, enabled: segment.enabled)
        }
        for segment in nibSegments where segment.state.superview == objcObject { segment.removeFromSuperview() }
        segmented.selected = decoded.has("UISelectedSegmentIndex") ? decoded.integer("UISelectedSegmentIndex") : -1
        segmented.momentary = decoded.bool("UIMomentary")
        segmented.apportionsWidthsByContent = decoded.bool("UIApportionsSegmentWidthsByContent")
        segmented.selectedTintColor = decoded.object("UISelectedSegmentTintColor")?.as(UIColor.self)
        return self
    }

    private static func segment(_ item: NSObject) -> SegmentedControlState.Segment {
        if let image = item.as(UIImage.self) { return SegmentedControlState.Segment(image: image) }
        return SegmentedControlState.Segment(title: item.stringValue)
    }

    private func changed() {
        setNeedsDisplay()
        invalidateIntrinsicContentSize()
    }

    // MARK: Segments

    @ObjCMethod("numberOfSegments") func numberOfSegments() -> UInt { UInt(segmented.segments.count) }

    @ObjCMethod("insertSegmentWithTitle:atIndex:animated:")
    func insertSegment(title: String?, at index: UInt, animated: Bool) {
        insert(SegmentedControlState.Segment(title: title), at: index)
    }

    @ObjCMethod("insertSegmentWithImage:atIndex:animated:")
    func insertSegment(image: UIImage?, at index: UInt, animated: Bool) {
        insert(SegmentedControlState.Segment(image: image), at: index)
    }

    /// The selection stays on its segment.
    private func insert(_ segment: SegmentedControlState.Segment, at index: UInt) {
        let index = min(Int(index), segmented.segments.count)
        segmented.segments.insert(segment, at: index)
        if segmented.selected >= index { segmented.selected += 1 }
        changed()
    }

    @ObjCMethod("removeSegmentAtIndex:animated:")
    func removeSegment(at index: UInt, animated: Bool) {
        let index = Int(index)
        guard segmented.segments.indices.contains(index) else { return }
        segmented.segments.remove(at: index)
        if segmented.selected == index { segmented.selected = -1 } else if segmented.selected > index { segmented.selected -= 1 }
        changed()
    }

    @ObjCMethod("removeAllSegments")
    func removeAllSegments() {
        segmented.segments = []
        segmented.selected = -1
        changed()
    }

    private func update(_ index: UInt, _ body: (inout SegmentedControlState.Segment) -> Void) {
        guard segmented.segments.indices.contains(Int(index)) else { return }
        body(&segmented.segments[Int(index)])
        changed()
    }

    private func segment(_ index: UInt) -> SegmentedControlState.Segment? {
        segmented.segments.indices.contains(Int(index)) ? segmented.segments[Int(index)] : nil
    }

    @ObjCMethod("setTitle:forSegmentAtIndex:")
    func setTitle(_ title: String?, forSegmentAt index: UInt) { update(index) { $0.title = title; $0.image = nil } }
    @ObjCMethod("titleForSegmentAtIndex:") func title(forSegmentAt index: UInt) -> String? { segment(index)?.title }
    @ObjCMethod("setImage:forSegmentAtIndex:")
    func setImage(_ image: UIImage?, forSegmentAt index: UInt) { update(index) { $0.image = image; $0.title = nil } }
    @ObjCMethod("imageForSegmentAtIndex:") func image(forSegmentAt index: UInt) -> UIImage? { segment(index)?.image }
    @ObjCMethod("setWidth:forSegmentAtIndex:")
    func setWidth(_ width: CGFloat, forSegmentAt index: UInt) { update(index) { $0.width = max(width, 0) } }
    @ObjCMethod("widthForSegmentAtIndex:") func width(forSegmentAt index: UInt) -> CGFloat { segment(index)?.width ?? 0 }
    @ObjCMethod("setEnabled:forSegmentAtIndex:")
    func setEnabled(_ enabled: Bool, forSegmentAt index: UInt) { update(index) { $0.enabled = enabled } }
    @ObjCMethod("isEnabledForSegmentAtIndex:") func isEnabled(forSegmentAt index: UInt) -> Bool { segment(index)?.enabled ?? false }

    // MARK: Selection and appearance

    /// UISegmentedControlNoSegment is -1. Setting it sends no actions.
    @ObjCMethod("selectedSegmentIndex") func selectedSegmentIndex() -> Int { segmented.selected }
    @ObjCMethod("setSelectedSegmentIndex:")
    func setSelectedSegmentIndex(_ index: Int) {
        segmented.selected = segmented.segments.indices.contains(index) ? index : -1
        setNeedsDisplay()
    }

    @ObjCMethod("isMomentary") func isMomentary() -> Bool { segmented.momentary }
    @ObjCMethod("setMomentary:") func setMomentary(_ momentary: Bool) { segmented.momentary = momentary; setNeedsDisplay() }
    @ObjCMethod("apportionsSegmentWidthsByContent") func apportionsSegmentWidthsByContent() -> Bool { segmented.apportionsWidthsByContent }
    @ObjCMethod("setApportionsSegmentWidthsByContent:")
    func setApportionsSegmentWidthsByContent(_ apportions: Bool) { segmented.apportionsWidthsByContent = apportions; changed() }
    @ObjCMethod("selectedSegmentTintColor") func selectedSegmentTintColor() -> UIColor? { segmented.selectedTintColor }
    @ObjCMethod("setSelectedSegmentTintColor:")
    func setSelectedSegmentTintColor(_ color: UIColor?) { segmented.selectedTintColor = color; setNeedsDisplay() }

    /// The font and color of titles in a UIControlState.
    @ObjCMethod("setTitleTextAttributes:forState:")
    func setTitleTextAttributes(_ attributes: NSDictionary?, for controlState: UInt) {
        segmented.titleAttributes[controlState] = attributes
        changed()
    }

    @ObjCMethod("titleTextAttributesForState:")
    func titleTextAttributes(for controlState: UInt) -> NSDictionary? { segmented.titleAttributes[controlState] }

    /// UISegmentedControlStyle, from before iOS 7: plain 0, bordered 1, bar 2.
    @ObjCMethod("segmentedControlStyle") func segmentedControlStyle() -> Int { 1 }
    @ObjCMethod("setSegmentedControlStyle:") func setSegmentedControlStyle(_ style: Int) {}

    // Images for the bar's parts are not drawn.
    @ObjCMethod("setBackgroundImage:forState:barMetrics:")
    func setBackgroundImage(_ image: UIImage?, for controlState: UInt, barMetrics: Int) {}
    @ObjCMethod("setDividerImage:forLeftSegmentState:rightSegmentState:barMetrics:")
    func setDividerImage(_ image: UIImage?, forLeftSegmentState left: UInt, rightSegmentState right: UInt, barMetrics: Int) {}
    @ObjCMethod("setContentPositionAdjustment:forSegmentType:barMetrics:")
    func setContentPositionAdjustment(_ adjustment: CGSize, forSegmentType type: Int, barMetrics: Int) {}
    @ObjCMethod("setContentOffset:forSegmentAtIndex:")
    func setContentOffset(_ offset: CGSize, forSegmentAt index: UInt) {}

    // MARK: Layout

    /// The font and color of a title in a segment, selected or not.
    private func titleStyle(selected: Bool, enabled: Bool) -> (font: UIFont, color: UIColor) {
        let normal = segmented.titleAttributes[0]
        let own = !enabled ? segmented.titleAttributes[2] : selected ? segmented.titleAttributes[4] : nil
        func attribute(_ key: String) -> NSObject? { own?.object(forKey: key) ?? normal?.object(forKey: key) }
        let font = attribute("NSFont")?.as(UIFont.self) ?? (selected ? UISegmentedControl.selectedFont : UISegmentedControl.font)
        let color = attribute("NSColor")?.as(UIColor.self) ?? (enabled && control.enabled ? UIColor.label() : UIColor.systemGray())
        return (font, color)
    }

    private func contentWidth(_ segment: SegmentedControlState.Segment) -> CGFloat {
        if let image = segment.image { return image.state.size.width }
        return Text.size(segment.title ?? "", font: titleStyle(selected: true, enabled: true).font).width
    }

    /// Fixed widths as set; the rest share what is left, equally or by
    /// their content.
    func segmentFrames() -> [CGRect] {
        let segments = segmented.segments, bounds = state.bounds
        guard !segments.isEmpty else { return [] }
        let fixed = segments.reduce(0) { $0 + $1.width }
        let open = segments.indices.filter { segments[$0].width <= 0 }
        let left = max(bounds.width - fixed, 0)
        let content = open.map { contentWidth(segments[$0]) + 20 }
        let total = content.reduce(0, +)
        var widths = segments.map(\.width)
        for (position, index) in open.enumerated() {
            widths[index] = segmented.apportionsWidthsByContent && total > 0 ? left * content[position] / total : left / CGFloat(open.count)
        }
        var x = bounds.minX
        return widths.map { width in
            defer { x += width }
            return CGRect(x: x, y: bounds.minY, width: width, height: bounds.height)
        }
    }

    /// Room for each segment's content, equal widths unless apportioned,
    /// 32 points high.
    @ObjCMethod("intrinsicContentSize")
    func intrinsicContentSize() -> CGSize {
        let segments = segmented.segments
        let content = segments.map { $0.width > 0 ? $0.width : contentWidth($0) + 20 }
        let width = segmented.apportionsWidthsByContent ? content.reduce(0, +) : (content.max() ?? 0) * CGFloat(segments.count)
        return CGSize(width: width, height: 32)
    }

    @ObjCMethod("sizeThatFits:")
    override func sizeThatFits(_ size: CGSize) -> CGSize { intrinsicContentSize() }

    // MARK: Touches

    private func segmentIndex(_ touches: NSObject) -> Int? {
        guard let touch = touches.as(NSSet.self)?.anyObject()?.as(UITouch.self) else { return nil }
        let point = touch.location(in: self)
        guard state.bounds.insetBy(-16).contains(point) else { return nil }
        let frames = segmentFrames()
        let x = min(max(point.x, state.bounds.minX), state.bounds.maxX - 0.5)
        return frames.firstIndex { $0.minX <= x && x < $0.maxX } ?? (frames.isEmpty ? nil : frames.count - 1)
    }

    @ObjCMethod("touchesBegan:withEvent:")
    override func touchesBegan(_ touches: NSObject, with event: NSObject?) {
        guard control.enabled else { return }
        control.tracking = true
        segmented.pressed = segmentIndex(touches)
        setNeedsDisplay()
    }

    @ObjCMethod("touchesMoved:withEvent:")
    override func touchesMoved(_ touches: NSObject, with event: NSObject?) {
        guard control.tracking else { return }
        segmented.pressed = segmentIndex(touches)
        setNeedsDisplay()
    }

    /// Selects the segment as the touch lifts on it. A momentary control
    /// keeps the index but shows nothing selected.
    @ObjCMethod("touchesEnded:withEvent:")
    override func touchesEnded(_ touches: NSObject, with event: NSObject?) {
        guard control.tracking else { return }
        control.tracking = false
        segmented.pressed = nil
        setNeedsDisplay()
        guard let index = segmentIndex(touches), segmented.segments[index].enabled else { return }
        guard index != segmented.selected || segmented.momentary else { return }
        segmented.selected = index
        sendActions(for: 1 << 12)
    }

    @ObjCMethod("touchesCancelled:withEvent:")
    override func touchesCancelled(_ touches: NSObject, with event: NSObject?) {
        control.tracking = false
        segmented.pressed = nil
        setNeedsDisplay()
    }

    // MARK: Drawing

    @ObjCMethod("drawRect:")
    override func draw(_ rect: CGRect) {
        guard let context = Graphics.current else { return }
        let bounds = state.bounds, frames = segmentFrames()
        let selected = segmented.momentary ? segmented.pressed ?? -1 : segmented.selected
        let track = UIColor.rgb(118.0 / 255, 118.0 / 255, 128.0 / 255, 0.12)
        let tile = segmented.selectedTintColor ?? UIColor.white()
        let separator = UIColor.rgb(142.0 / 255, 142.0 / 255, 147.0 / 255, 0.3)
        let pressed = UIColor.gray(0, 0.06)
        withExtendedLifetime((track, tile, separator, pressed)) {
            func fill(_ rect: CGRect, radius: CGFloat, _ color: UIColor) {
                CG.setFillColorWithColor(context, color.state.makeCGColor())
                if let shape = roundedRectPath(rect, radius: radius, corners: 0xf) {
                    CG.addPath(context, shape.object)
                    CG.fillPath(context)
                }
            }
            fill(bounds, radius: min(9, bounds.height / 2), track)
            if let pressedIndex = segmented.pressed, pressedIndex != selected, frames.indices.contains(pressedIndex) {
                fill(frames[pressedIndex].insetBy(2), radius: 7, pressed)
            }
            if frames.indices.contains(selected) {
                fill(frames[selected].insetBy(2), radius: min(7, bounds.height / 2 - 2), tile)
            }
            // Dividers between segments neither of which is selected.
            CG.setFillColorWithColor(context, separator.state.makeCGColor())
            for index in frames.indices.dropLast() where index != selected && index + 1 != selected {
                CG.fillRect(context, CGRect(x: frames[index].maxX - Screen.pixel / 2, y: bounds.minY + 7, width: Screen.pixel,
                                            height: max(bounds.height - 14, 0)))
            }
        }
        for (index, frame) in frames.enumerated() {
            let segment = segmented.segments[index]
            let (font, color) = titleStyle(selected: index == selected, enabled: segment.enabled)
            if let image = segment.image {
                // Fitted inside the segment, as a template in the title's color
                // unless it asks to be drawn as it is.
                let size = image.state.size
                let scale = min(1, (frame.width - 8) / max(size.width, 1), (frame.height - 8) / max(size.height, 1))
                let fitted = CGSize(width: size.width * scale, height: size.height * scale)
                let drawn = image.state.renderingMode == 1 ? image : image.withTintColor(color)
                drawn.draw(in: CGRect(x: frame.midX - fitted.width / 2, y: frame.midY - fitted.height / 2,
                                      width: fitted.width, height: fitted.height))
            } else if let title = segment.title {
                // A title wider than its segment ends in an ellipsis, as
                // UIKit's do, rather than run into the next segment.
                let fitted = Text.truncated(title, font: font, width: max(frame.width - 8, 0))
                let size = Text.size(fitted, font: font)
                Text.draw(fitted, at: CGPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2),
                          font: font, color: color)
            }
        }
    }
}

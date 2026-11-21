import CPerryGeometry
import Glibc
import PerryObjCInterop

/// NSRulerView: a strip a scroll view shows beside (vertical) or above
/// (horizontal) its clip view, measuring its document. It draws its hash
/// marks and labels, then its markers, each by a method a subclass
/// overrides (Xcode's editor gutter draws line numbers so); here its own
/// draw nothing over its background. Its thickness is the rule's, the
/// markers' and the accessory view's.
@ObjCClass("NSRulerView")
open class NSRulerView: NSView {
    /// Not retained: the scroll view holds the ruler.
    var scrollViewObject: UnsafeMutableRawPointer?
    /// NSRulerOrientation: horizontal 0, vertical 1.
    var orientation: UInt = 1
    var ruleThickness: CGFloat = 16
    var reservedThicknessForMarkers: CGFloat = 15
    var reservedThicknessForAccessoryView: CGFloat = 0
    var originOffset: CGFloat = 0
    var measurementUnits = "Inches"
    /// Not retained, as AppKit's.
    var clientViewObject: UnsafeMutableRawPointer?
    var accessoryView: NSView?
    var markers: [NSObject] = []

    public required init() { super.init() }

    @ObjCMethod("initWithFrame:")
    public required init(frame: CGRect) { super.init(frame: frame) }

    @ObjCMethod("initWithScrollView:orientation:")
    public required init(scrollView: NSScrollView?, orientation: UInt) {
        super.init(frame: .zero)
        scrollViewObject = scrollView?.objcObject
        self.orientation = orientation
    }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) { super.init(coder: coder) }

    @ObjCMethod("scrollView") func rulerScrollView() -> NSScrollView? {
        scrollViewObject.map { NSScrollView.objCInstance($0, ownership: .retain) }
    }
    @ObjCMethod("setScrollView:") func setScrollView(_ view: NSScrollView?) { scrollViewObject = view?.objcObject }
    @ObjCMethod("orientation") func rulerOrientation() -> UInt { orientation }
    @ObjCMethod("setOrientation:") func setOrientation(_ value: UInt) { orientation = value; thicknessChanged() }
    @ObjCMethod("ruleThickness") func rulerRuleThickness() -> CGFloat { ruleThickness }
    @ObjCMethod("setRuleThickness:") func setRuleThickness(_ value: CGFloat) { ruleThickness = value; thicknessChanged() }
    @ObjCMethod("reservedThicknessForMarkers") func rulerReservedThicknessForMarkers() -> CGFloat { reservedThicknessForMarkers }
    @ObjCMethod("setReservedThicknessForMarkers:")
    func setReservedThicknessForMarkers(_ value: CGFloat) { reservedThicknessForMarkers = value; thicknessChanged() }
    @ObjCMethod("reservedThicknessForAccessoryView") func rulerReservedThicknessForAccessoryView() -> CGFloat {
        reservedThicknessForAccessoryView
    }
    @ObjCMethod("setReservedThicknessForAccessoryView:")
    func setReservedThicknessForAccessoryView(_ value: CGFloat) { reservedThicknessForAccessoryView = value; thicknessChanged() }

    /// The rule, the markers' room and the accessory view's, each as the
    /// ruler (or a subclass) answers it.
    @ObjCMethod("requiredThickness")
    func requiredThickness() -> CGFloat {
        sentThickness("ruleThickness") + sentThickness("reservedThicknessForMarkers") + sentThickness("reservedThicknessForAccessoryView")
    }
    /// Where the rule's baseline is: past the markers and the accessory view.
    @ObjCMethod("baselineLocation")
    func baselineLocation() -> CGFloat { sentThickness("reservedThicknessForMarkers") + sentThickness("reservedThicknessForAccessoryView") }

    private func sentThickness(_ selector: String) -> CGFloat {
        typealias Get = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer) -> CGFloat
        return unsafeBitCast(ObjCRuntime.msgSend, to: Get.self)(objcObject, ObjCRuntime.selector(selector))
    }

    /// A change of thickness has the scroll view lay its parts out again.
    private func thicknessChanged() {
        rulerScrollView()?.tile()
    }

    @ObjCMethod("originOffset") func rulerOriginOffset() -> CGFloat { originOffset }
    @ObjCMethod("setOriginOffset:") func setOriginOffset(_ value: CGFloat) { originOffset = value; setNeedsDisplay(true) }
    @ObjCMethod("measurementUnits") func rulerMeasurementUnits() -> String { measurementUnits }
    @ObjCMethod("setMeasurementUnits:") func setMeasurementUnits(_ value: String?) { measurementUnits = value ?? "Inches"; setNeedsDisplay(true) }
    @ObjCMethod("clientView") func clientView() -> NSView? { clientViewObject.map { NSView.objCInstance($0, ownership: .retain) } }
    @ObjCMethod("setClientView:") func setClientView(_ view: NSView?) { clientViewObject = view?.objcObject; setNeedsDisplay(true) }
    @ObjCMethod("accessoryView") func rulerAccessoryView() -> NSView? { accessoryView }
    @ObjCMethod("setAccessoryView:")
    func setAccessoryView(_ view: NSView?) {
        accessoryView?.removeFromSuperview()
        accessoryView = view
        if let view { addSubview(view) }
    }
    @ObjCMethod("markers") func rulerMarkers() -> NSObject? { markers.isEmpty ? nil : NSMutableArray.of(markers) }
    @ObjCMethod("setMarkers:")
    func setMarkers(_ value: NSObject?) {
        markers = value?.as(NSArray.self)?.elements ?? []
        setNeedsDisplay(true)
    }
    @ObjCMethod("addMarker:") func addMarker(_ marker: NSObject?) { marker.map { markers.append($0) }; setNeedsDisplay(true) }
    @ObjCMethod("removeMarker:") func removeMarker(_ marker: NSObject?) { markers.removeAll { $0 === marker }; setNeedsDisplay(true) }
    @ObjCMethod("invalidateHashMarks") func invalidateHashMarks() { setNeedsDisplay(true) }
    @ObjCMethod("drawHashMarksAndLabelsInRect:") func drawHashMarksAndLabels(in rect: CGRect) {}
    @ObjCMethod("drawMarkersInRect:") func drawMarkers(in rect: CGRect) {}
    @ObjCMethod("trackMarker:withMouseEvent:") func trackMarker(_ marker: NSObject?, with event: NSObject?) -> Bool { false }

    /// Flipped as its client view is, so a vertical ruler's marks line up
    /// with a flipped document's.
    @ObjCMethod("isFlipped")
    override func isFlipped() -> Bool {
        if orientation == 0 { return true }
        return rulerScrollView()?.contentView()?.documentView?.flipped ?? true
    }

    /// The background, then the hash marks and labels and the markers, each
    /// sent so a subclass's draw.
    @ObjCMethod("drawRect:")
    override func draw(_ dirty: CGRect) {
        NSColor(white: 0.93, alpha: 1).setFill()
        NSRectFill(bounds)
        Send.void(objcObject, "drawHashMarksAndLabelsInRect:", rect: dirty)
        Send.void(objcObject, "drawMarkersInRect:", rect: dirty)
    }
}

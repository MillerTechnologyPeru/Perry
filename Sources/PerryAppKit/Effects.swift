import CPerryGeometry
import Glibc
import PerryObjCInterop

// NSVisualEffectView (a translucent material behind other views, drawn as
// its plain color), NSTitlebarAccessoryViewController, NSAnimationContext
// (changes made at once, then the completion handler) and NSGradient.

/// NSVisualEffectMaterial's colors, light: titlebar 3, selection 4, menu 5,
/// popover 6, sidebar 7, header 10, sheet 11, window background 12, HUD
/// 13, full-screen UI 15, tooltip 17, content background 18, under window
/// background 21, under page background 22.
@ObjCClass("NSVisualEffectView")
open class NSVisualEffectView: NSView {
    var material = 0
    var blendingMode = 0
    var state = 0
    var emphasized = false
    var maskImage: NSImage?

    @ObjCMethod("init")
    public required init() { super.init() }

    @ObjCMethod("initWithFrame:")
    public required init(frame: CGRect) { super.init(frame: frame) }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init(coder: coder)
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        material = decoded.integer("NSVisualEffectViewMaterial")
        blendingMode = decoded.integer("NSVisualEffectViewBlendingMode")
        state = decoded.integer("NSVisualEffectViewState")
    }

    /// The material's gray, in the light or dark appearance.
    var fillWhite: CGFloat {
        let dark = Appearances.currentIsDark
        switch material {
        case 4: return dark ? 0.27 : 0.84
        case 3, 10, 7: return dark ? 0.2 : 0.93
        case 5, 6, 17: return dark ? 0.16 : 0.97
        case 13: return 0.2
        case 18, 22: return dark ? 0.12 : 1
        default: return dark ? 0.2 : 0.95
        }
    }

    @ObjCMethod("drawRect:")
    override func draw(_ dirty: CGRect) {
        NSColor(white: fillWhite, alpha: 1).setFill()
        NSRectFill(bounds)
    }

    @ObjCMethod("material") func materialValue() -> Int { material }
    @ObjCMethod("setMaterial:") func setMaterial(_ value: Int) { material = value; setNeedsDisplay(true) }
    @ObjCMethod("blendingMode") func blendingModeValue() -> Int { blendingMode }
    @ObjCMethod("setBlendingMode:") func setBlendingMode(_ value: Int) { blendingMode = value }
    @ObjCMethod("state") func stateValue() -> Int { state }
    @ObjCMethod("setState:") func setState(_ value: Int) { state = value }
    @ObjCMethod("isEmphasized") func isEmphasized() -> Bool { emphasized }
    @ObjCMethod("setEmphasized:") func setEmphasized(_ value: Bool) { emphasized = value }
    @ObjCMethod("maskImage") func maskImageValue() -> NSImage? { maskImage }
    @ObjCMethod("setMaskImage:") func setMaskImage(_ value: NSImage?) { maskImage = value }
    @ObjCMethod("interiorBackgroundStyle") func interiorBackgroundStyle() -> Int { material == 13 ? 2 : 1 }
}

/// A view controller whose view goes in a window's titlebar, at its bottom
/// (NSLayoutAttributeBottom, 4) or beside its buttons (left 1, right 2).
@ObjCClass("NSTitlebarAccessoryViewController")
open class NSTitlebarAccessoryViewController: NSViewController {
    var layoutAttribute = 4
    var fullScreenMinHeight: CGFloat = 0
    var hidden = false
    var automaticallyAdjustsSize = true

    public required init() { super.init() }

    @ObjCMethod("initWithNibName:bundle:")
    public required init(nibName: String?, bundle: NSObject?) { super.init(nibName: nibName, bundle: bundle) }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) { super.init(coder: coder) }

    @ObjCMethod("layoutAttribute") func layoutAttributeValue() -> Int { layoutAttribute }
    @ObjCMethod("setLayoutAttribute:") func setLayoutAttribute(_ value: Int) { layoutAttribute = value }
    @ObjCMethod("fullScreenMinHeight") func fullScreenMinHeightValue() -> CGFloat { fullScreenMinHeight }
    @ObjCMethod("setFullScreenMinHeight:") func setFullScreenMinHeight(_ value: CGFloat) { fullScreenMinHeight = value }
    @ObjCMethod("isHidden") func isHidden() -> Bool { hidden }
    @ObjCMethod("setHidden:") func setHidden(_ value: Bool) { hidden = value }
    @ObjCMethod("automaticallyAdjustsSize") func automaticallyAdjustsSizeValue() -> Bool { automaticallyAdjustsSize }
    @ObjCMethod("setAutomaticallyAdjustsSize:") func setAutomaticallyAdjustsSize(_ value: Bool) { automaticallyAdjustsSize = value }
}

/// Animation groups: there is no animation, so changes take effect at once
/// and the completion handler runs once the group ends.
@ObjCClass("NSAnimationContext")
open class NSAnimationContext: NSObject {
    nonisolated(unsafe) static var stack: [NSAnimationContext] = []
    nonisolated(unsafe) static var idle: NSAnimationContext?
    var duration: Double = 0.25
    var timingFunction: NSObject?
    var allowsImplicitAnimation = false
    var completionHandler: ObjCBlock?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCClassMethod("currentContext")
    static func currentContext() -> NSAnimationContext {
        if let context = stack.last { return context }
        if let idle { return idle }
        let context = NSAnimationContext()
        idle = context
        return context
    }

    @ObjCClassMethod("beginGrouping")
    static func beginGrouping() { stack.append(NSAnimationContext()) }

    @ObjCClassMethod("endGrouping")
    static func endGrouping() {
        guard let context = stack.popLast() else { return }
        if let handler = context.completionHandler { Blocks.call(handler) }
    }

    @ObjCClassMethod("runAnimationGroup:completionHandler:")
    static func runAnimationGroup(_ changes: ObjCBlock?, completionHandler: ObjCBlock?) {
        beginGrouping()
        if let changes { Blocks.call(changes, stack.last?.objcObject) }
        endGrouping()
        if let completionHandler { Blocks.call(completionHandler) }
    }

    @ObjCClassMethod("runAnimationGroup:")
    static func runAnimationGroup(_ changes: ObjCBlock?) { runAnimationGroup(changes, completionHandler: nil) }

    @ObjCMethod("duration") func durationValue() -> Double { duration }
    @ObjCMethod("setDuration:") func setDuration(_ value: Double) { duration = value }
    @ObjCMethod("timingFunction") func timingFunctionValue() -> NSObject? { timingFunction }
    @ObjCMethod("setTimingFunction:") func setTimingFunction(_ value: NSObject?) { timingFunction = value }
    @ObjCMethod("allowsImplicitAnimation") func allowsImplicitAnimationValue() -> Bool { allowsImplicitAnimation }
    @ObjCMethod("setAllowsImplicitAnimation:") func setAllowsImplicitAnimation(_ value: Bool) { allowsImplicitAnimation = value }
    @ObjCMethod("completionHandler") func completionHandlerValue() -> ObjCBlock? { completionHandler }
    @ObjCMethod("setCompletionHandler:") func setCompletionHandler(_ value: ObjCBlock?) { completionHandler = value }
}

/// Colors at locations from 0 to 1, drawn as bands of the colors between.
@ObjCClass("NSGradient")
open class NSGradient: NSObject {
    var stops: [(color: NSColor, location: CGFloat)] = []

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithStartingColor:endingColor:")
    public required init(startingColor: NSColor?, endingColor: NSColor?) {
        super.init()
        if let startingColor, let endingColor { stops = [(startingColor, 0), (endingColor, 1)] }
    }

    @ObjCMethod("initWithColors:")
    public required init(colors: NSObject?) {
        super.init()
        let list = colors?.as(NSArray.self)?.elements.compactMap { $0.as(NSColor.self) } ?? []
        stops = list.enumerated().map { ($0.element, list.count > 1 ? CGFloat($0.offset) / CGFloat(list.count - 1) : 0) }
    }

    @ObjCMethod("initWithColors:atLocations:colorSpace:")
    public required init(colors: NSObject?, atLocations locations: UnsafePointer<CGFloat>?, colorSpace: NSObject?) {
        super.init()
        let list = colors?.as(NSArray.self)?.elements.compactMap { $0.as(NSColor.self) } ?? []
        stops = list.enumerated().map { ($0.element, locations?[$0.offset] ?? 0) }.sorted { $0.location < $1.location }
    }

    @ObjCMethod("numberOfColorStops") func numberOfColorStops() -> Int { stops.count }

    func color(at location: CGFloat) -> NSColor {
        guard let first = stops.first, let last = stops.last else { return NSColor.clearColor() }
        if location <= first.location { return first.color }
        if location >= last.location { return last.color }
        for (a, b) in zip(stops, stops.dropFirst()) where location <= b.location {
            let t = b.location > a.location ? (location - a.location) / (b.location - a.location) : 0
            return NSColor(red: a.color.red + (b.color.red - a.color.red) * t, green: a.color.green + (b.color.green - a.color.green) * t,
                           blue: a.color.blue + (b.color.blue - a.color.blue) * t, alpha: a.color.alpha + (b.color.alpha - a.color.alpha) * t)
        }
        return last.color
    }

    @ObjCMethod("interpolatedColorAtLocation:") func interpolatedColor(atLocation location: CGFloat) -> NSColor { color(at: location) }

    /// Bands a point apart across the rectangle, at the angle in degrees
    /// (0 is left to right, 90 bottom to top) along whichever axis is nearer.
    @ObjCMethod("drawInRect:angle:")
    func draw(in rect: CGRect, angle: CGFloat) {
        guard let context = NSGraphicsContext.currentCG, !stops.isEmpty else { return }
        let normalized = (angle.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let vertical = (45..<135).contains(normalized) || (225..<315).contains(normalized)
        let reversed = (135..<315).contains(normalized)
        let length = vertical ? rect.height : rect.width
        let bands = max(1, Int(length.rounded(.up)))
        CG.saveGState(context)
        defer { CG.restoreGState(context) }
        for band in 0..<bands {
            var t = (CGFloat(band) + 0.5) / CGFloat(bands)
            if reversed { t = 1 - t }
            let step = length / CGFloat(bands)
            let strip = vertical ? CGRect(x: rect.minX, y: rect.minY + CGFloat(band) * step, width: rect.width, height: step + 0.5)
                                 : CGRect(x: rect.minX + CGFloat(band) * step, y: rect.minY, width: step + 0.5, height: rect.height)
            color(at: t).setFill()
            CG.fillRect(context, strip)
        }
    }

    @ObjCMethod("drawInBezierPath:angle:")
    func draw(in path: NSBezierPath?, angle: CGFloat) {
        guard let path, let context = NSGraphicsContext.currentCG else { return }
        CG.saveGState(context)
        path.addClip()
        draw(in: path.bounds(), angle: angle)
        CG.restoreGState(context)
    }

    @ObjCMethod("drawFromPoint:toPoint:options:")
    func draw(from start: CGPoint, to end: CGPoint, options: UInt) {
        let angle = atan2(end.y - start.y, end.x - start.x) * 180 / .pi
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: max(1, abs(end.x - start.x)), height: max(1, abs(end.y - start.y)))
        draw(in: rect, angle: angle)
    }

    @ObjCMethod("drawInRect:relativeCenterPosition:")
    func draw(in rect: CGRect, relativeCenterPosition: CGPoint) { draw(in: rect, angle: 90) }
}

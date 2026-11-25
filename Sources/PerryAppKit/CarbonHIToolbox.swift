import CPerryGeometry
import Glibc
import PerryObjCInterop

// Mac apps' alone: armv7 runs only iOS apps, so it has none of this.
#if !arch(arm)
// The rest of Carbon's HIToolbox, and its Apple Help, that Cocoa apps still
// call (the loader maps Carbon to AppKit): pages for a Help Viewer there
// isn't, the check for the user cancelling, mouse tracking's thresholds and
// the theme's chasing arrows.

private let noErr: Int32 = 0
private let paramErr: Int32 = -50
/// kAHInternalErr.
private let helpInternalErr: Int32 = -10790

/// OSStatus AHGotoPage(CFStringRef bookname, CFStringRef path, CFStringRef
/// anchor): there's no Help Viewer here to open the page in, so it says so
/// and answers kAHInternalErr. With neither a book nor a path, paramErr.
@c(_AHGotoPage)
public func AHGotoPage(_ book: UnsafeMutableRawPointer?, _ path: UnsafeMutableRawPointer?, _ anchor: UnsafeMutableRawPointer?) -> Int32 {
    guard book != nil || path != nil else { return paramErr }
    func text(_ string: UnsafeMutableRawPointer?) -> String? { string.map { String(objCArgument: $0) } }
    var page = [text(book), text(path)].compactMap { $0 }.joined(separator: ": ")
    if let anchor = text(anchor) { page += "#" + anchor }
    appKitWarning("no Help Viewer here to open \(page)")
    return helpInternalErr
}

/// Boolean CheckEventQueueForUserCancel(void): whether Escape or
/// Command-period is waiting in the application's queue, SDL's events taken
/// first. If one is, it goes, with the mouse and key events ahead of it.
/// The queue is the main thread's; asked on another thread, false.
@c(_CheckEventQueueForUserCancel)
public func CheckEventQueueForUserCancel() -> Bool {
    guard Dispatch.isMainThread, let app = App.shared else { return false }
    Events.pump()
    guard let index = app.queue.firstIndex(where: isUserCancel) else { return false }
    app.queue = app.queue.enumerated().filter { $0.offset > index || !($0.element.type.isMouse || $0.element.type.isKey) }.map(\.element)
    return true
}

private func isUserCancel(_ event: NSEvent) -> Bool {
    guard event.type == .keyDown else { return false }
    // kVK_Escape.
    if event.keyCode == 0x35 { return true }
    return event.modifierFlags & ModifierFlags.command != 0 && event.charactersIgnoringModifiers == "."
}

/// OSStatus HIMouseTrackingGetParameters(OSType selector, EventTime *outTime,
/// HISize *outDistance). macOS doesn't document its values; these are
/// Perry's: NSEvent's double-click interval (half a second, GetDblTime's
/// 30 ticks) and 4 points either way. kMouseParamsClickAndHold has no
/// distance and kMouseParamsDragInitiation no time, which are 0, as the
/// header says. Another selector is paramErr.
@c(_HIMouseTrackingGetParameters)
public func HIMouseTrackingGetParameters(_ selector: UInt32, _ time: UnsafeMutablePointer<Double>?,
                                         _ distance: UnsafeMutablePointer<CGSize>?) -> Int32 {
    let interval = NSEvent.doubleClickInterval()
    let reach = CGSize(width: 4, height: 4), none = CGSize(width: 0, height: 0)
    let values: (Double, CGSize)
    switch selector {
    case 0x7374_6963, 0x7072_6f78: values = (interval, reach)  // 'stic' (kMouseParamsSticky), 'prox' (kMouseParamsProxyIcon)
    case 0x636c_686f: values = (interval, none)  // 'clho' (kMouseParamsClickAndHold)
    case 0x6472_6167: values = (0, reach)  // 'drag' (kMouseParamsDragInitiation)
    default: return paramErr
    }
    time?.pointee = values.0
    distance?.pointee = values.1
    return noErr
}

/// OSStatus HIThemeDrawChasingArrows(const HIRect *, const
/// HIThemeChasingArrowsDrawInfo *, CGContextRef, HIThemeOrientation): three
/// quarters of a circle ending in an arrowhead, centered in the rect, an
/// eighth of a turn further clockwise for each index; gray, lighter when
/// inactive (kThemeStateInactive, 0). The draw info is three UInt32s:
/// version, state and index. kHIThemeOrientationNormal (0) is a context
/// whose origin is at the top left, kHIThemeOrientationInverted (1) at the
/// bottom left.
@c(_HIThemeDrawChasingArrows)
public func HIThemeDrawChasingArrows(_ bounds: UnsafePointer<CGRect>?, _ info: UnsafeRawPointer?, _ context: UnsafeMutableRawPointer?,
                                     _ orientation: UInt32) -> Int32 {
    guard let bounds, let info, let context else { return paramErr }
    let rect = bounds.pointee
    let state = info.loadUnaligned(fromByteOffset: 4, as: UInt32.self), index = info.loadUnaligned(fromByteOffset: 8, as: UInt32.self)
    let size = Double(min(abs(rect.size.width), abs(rect.size.height)))
    let lineWidth = max(1, size / 8), radius = size / 2 - lineWidth * 1.5
    guard radius > 0, CG.ready else { return noErr }
    let centerX = Double(rect.origin.x + rect.size.width / 2), centerY = Double(rect.origin.y + rect.size.height / 2)
    /// A point `x` across and `y` down from the center, as the context has it.
    func place(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: CGFloat(centerX + x), y: CGFloat(centerY + (orientation == 1 ? -y : y)))
    }
    let gray: CGFloat = state == 0 ? 0.65 : 0.35
    guard let color = CG.colorCreateSRGB(gray, gray, gray, 1) else { return noErr }
    defer { CG.release(color) }
    // Angles grow clockwise, as seen.
    let start = Double(index % 8) * Double.pi / 4, end = start + 1.5 * Double.pi
    let steps = 24
    guard let arc = CG.pathCreateMutable() else { return noErr }
    defer { CG.release(arc) }
    for step in 0...steps {
        let angle = start + (end - start) * Double(step) / Double(steps)
        let point = place(radius * cos(angle), radius * sin(angle))
        if step == 0 { CG.pathMoveToPoint(arc, nil, point.x, point.y) } else { CG.pathAddLineToPoint(arc, nil, point.x, point.y) }
    }
    // The arrowhead: across the arc's end, pointing on round.
    let head = lineWidth * 1.5
    let endX = radius * cos(end), endY = radius * sin(end)
    let outX = cos(end), outY = sin(end), onX = -sin(end), onY = cos(end)
    let arrowhead = CG.polygon([place(endX + onX * head, endY + onY * head),
                                place(endX + outX * head, endY + outY * head),
                                place(endX - outX * head, endY - outY * head)])
    defer { if let arrowhead { CG.release(arrowhead) } }
    CG.saveGState(context)
    CG.setStrokeColorWithColor(context, color)
    CG.setFillColorWithColor(context, color)
    CG.setLineWidth(context, CGFloat(lineWidth))
    // kCGLineCapRound.
    CG.setLineCap(context, 1)
    CG.addPath(context, arc)
    CG.strokePath(context)
    if let arrowhead {
        CG.addPath(context, arrowhead)
        CG.fillPath(context)
    }
    CG.restoreGState(context)
    return noErr
}
#endif

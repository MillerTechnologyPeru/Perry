//
//  CairoContext+CoreGraphics.swift
//  SilicaCairo
//
//  Added for Perry: the CoreGraphics operations Silica's CGContext does not
//  cover, which Perry's CoreGraphics provider calls.
//

#if canImport(Cairo)

import Cairo
import CCairo
import Foundation
import Silica

public extension CairoContext {

    // MARK: Painting

    /// The fill color with the global alpha applied.
    internal var fillPattern: Cairo.Pattern { pattern(internalState.fill?.color ?? CGColor.black) }

    /// The stroke color with the global alpha applied.
    internal var strokePattern: Cairo.Pattern { pattern(internalState.stroke?.color ?? CGColor.black) }

    private func pattern(_ color: CGColor) -> Cairo.Pattern {
        var color = color
        color.alpha *= internalState.alpha
        return Pattern(color: color)
    }

    /// Clears the rect to transparent, within the clip.
    func clear(rect: CGRect) {
        internalContext.save()
        internalContext.newPath()
        addRect(rect)
        internalContext.clip()
        clear()
        internalContext.restore()
    }

    /// CGBlendMode, as Cairo operators; modes Cairo lacks draw normally.
    var blendMode: Int32 {
        get { blendModes.firstIndex(of: internalContext.operator).map(Int32.init) ?? 0 }
        set { internalContext.operator = blendModes.indices.contains(Int(newValue)) ? blendModes[Int(newValue)] : CAIRO_OPERATOR_OVER }
    }

    // MARK: Gradients

    /// A linear gradient from `start` to `end` through the stops (location
    /// and color), within the clip; extending carries the end colors on.
    func drawLinearGradient(stops: [(location: Double, color: CGColor)], start: CGPoint, end: CGPoint, extend: Bool) {
        let gradient = Pattern(linear: (origin: (Double(start.x), Double(start.y)), destination: (Double(end.x), Double(end.y))))
        paint(gradient: gradient, stops: stops, extend: extend)
    }

    /// A radial gradient between two circles.
    func drawRadialGradient(stops: [(location: Double, color: CGColor)], startCenter: CGPoint, startRadius: CGFloat,
                            endCenter: CGPoint, endRadius: CGFloat, extend: Bool) {
        let gradient = Pattern(radial: (start: (center: (Double(startCenter.x), Double(startCenter.y)), radius: Double(startRadius)),
                                        end: (center: (Double(endCenter.x), Double(endCenter.y)), radius: Double(endRadius))))
        paint(gradient: gradient, stops: stops, extend: extend)
    }

    private func paint(gradient: Pattern, stops: [(location: Double, color: CGColor)], extend: Bool) {
        for stop in stops {
            gradient.addColorStop(stop.location, red: Double(stop.color.red), green: Double(stop.color.green),
                                  blue: Double(stop.color.blue), alpha: Double(stop.color.alpha * internalState.alpha))
        }
        gradient.extend = extend ? .pad : .none
        internalContext.source = gradient
        internalContext.paint()
    }

    // MARK: Transforms

    /// The Cairo matrix: device space from user space.
    var matrix: CGAffineTransform {
        get { currentTransform }
        set { internalContext.matrix = newValue.toCairo() }
    }

    // MARK: Paths

    /// Whether the current path has no elements.
    var isPathEmpty: Bool { path.elements.isEmpty }

    /// The current path's bounding box, in user space.
    var pathBoundingBox: CGRect {
        // cairo_path_extents gives the corners; the wrapper labels the
        // second one width and height.
        let extents = internalContext.pathExtents
        return CGRect(x: extents.x, y: extents.y, width: extents.width - extents.x, height: extents.height - extents.y)
    }

    /// Whether a user-space point is inside the current path.
    func pathContains(_ point: CGPoint, evenOdd: Bool) -> Bool {
        let rule = internalContext.fillRule
        internalContext.fillRule = evenOdd ? CAIRO_FILL_RULE_EVEN_ODD : CAIRO_FILL_RULE_WINDING
        defer { internalContext.fillRule = rule }
        return internalContext.withUnsafePointer { cairo_in_fill($0, Double(point.x), Double(point.y)) } != 0
    }

    // MARK: Surface

    /// Flushes drawing to the surface's memory.
    func flush() { surface.flush() }

    /// Tells Cairo the surface's memory changed outside it.
    func markDirty() { surface.withUnsafePointer { cairo_surface_mark_dirty($0) } }
}

/// CGBlendMode's order: normal, multiply, screen, overlay, darken, lighten,
/// color dodge, color burn, soft light, hard light, difference, exclusion,
/// hue, saturation, color, luminosity, then the Porter-Duff modes clear,
/// copy, source in, source out, source atop, destination over, destination
/// in, destination out, destination atop, XOR, plus darker, plus lighter.
private let blendModes: [cairo_operator_t] = [
    CAIRO_OPERATOR_OVER, CAIRO_OPERATOR_MULTIPLY, CAIRO_OPERATOR_SCREEN, CAIRO_OPERATOR_OVERLAY, CAIRO_OPERATOR_DARKEN,
    CAIRO_OPERATOR_LIGHTEN, CAIRO_OPERATOR_COLOR_DODGE, CAIRO_OPERATOR_COLOR_BURN, CAIRO_OPERATOR_SOFT_LIGHT,
    CAIRO_OPERATOR_HARD_LIGHT, CAIRO_OPERATOR_DIFFERENCE, CAIRO_OPERATOR_EXCLUSION, CAIRO_OPERATOR_HSL_HUE,
    CAIRO_OPERATOR_HSL_SATURATION, CAIRO_OPERATOR_HSL_COLOR, CAIRO_OPERATOR_HSL_LUMINOSITY, CAIRO_OPERATOR_CLEAR,
    CAIRO_OPERATOR_SOURCE, CAIRO_OPERATOR_IN, CAIRO_OPERATOR_OUT, CAIRO_OPERATOR_ATOP, CAIRO_OPERATOR_DEST_OVER,
    CAIRO_OPERATOR_DEST_IN, CAIRO_OPERATOR_DEST_OUT, CAIRO_OPERATOR_DEST_ATOP, CAIRO_OPERATOR_XOR, CAIRO_OPERATOR_SATURATE,
    CAIRO_OPERATOR_ADD,
]

#endif

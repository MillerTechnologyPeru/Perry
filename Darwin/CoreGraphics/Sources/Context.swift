import Foundation

extension CGContext {
    public func setLineDash(phase: CGFloat, lengths: [CGFloat]) {
        __setLineDash(phase: phase, lengths: lengths, count: lengths.count)
    }

    public func move(to point: CGPoint) {
        __moveTo(x: point.x, y: point.y)
    }

    public func addLine(to point: CGPoint) {
        __addLineTo(x: point.x, y: point.y)
    }

    public func addCurve(to end: CGPoint, control1: CGPoint, control2: CGPoint) {
        __addCurveTo(cp1x: control1.x, cp1y: control1.y, cp2x: control2.x, cp2y: control2.y, endingAtX: end.x, y: end.y)
    }

    public func addQuadCurve(to end: CGPoint, control: CGPoint) {
        __addQuadCurveTo(cpx: control.x, cpy: control.y, endingAtX: end.x, y: end.y)
    }

    public func addRects(_ rects: [CGRect]) {
        __addRects(rects, count: rects.count)
    }

    public func addLines(between points: [CGPoint]) {
        __addLines(between: points, count: points.count)
    }

    public func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool) {
        __addArc(centerX: center.x, y: center.y, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: clockwise ? 1 : 0)
    }

    public func addArc(tangent1End: CGPoint, tangent2End: CGPoint, radius: CGFloat) {
        __addArc(x1: tangent1End.x, y1: tangent1End.y, x2: tangent2End.x, y2: tangent2End.y, radius: radius)
    }

    public func fillPath(using rule: CGPathFillRule = .winding) {
        switch rule {
        case .winding: __fillPath()
        case .evenOdd: __eoFillPath()
        }
    }

    public func clip(using rule: CGPathFillRule = .winding) {
        switch rule {
        case .winding: __clip()
        case .evenOdd: __eoClip()
        }
    }

    public func fill(_ rects: [CGRect]) {
        __fill(rects, count: rects.count)
    }

    public func strokeLineSegments(between points: [CGPoint]) {
        __strokeLineSegments(between: points, count: points.count)
    }

    public func clip(to rects: [CGRect]) {
        __clip(to: rects, count: rects.count)
    }

    public func draw(_ image: CGImage, in rect: CGRect, byTiling: Bool = false) {
        if byTiling {
            __draw(in: rect, byTiling: image)
        } else {
            __draw(in: rect, image: image)
        }
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    public func draw(_ image: CGImage, in rect: CGRect, by toneMapping: CGToneMapping = .default, options: CFDictionary?) -> Bool {
        __draw(in: rect, image: image, applying: toneMapping, options: options)
    }

    public var textPosition: CGPoint {
        get { __textPosition }
        set { __setTextPosition(x: newValue.x, y: newValue.y) }
    }

    public func showGlyphs(_ glyphs: [CGGlyph], at positions: [CGPoint]) {
        precondition(glyphs.count == positions.count, "There must be a position for each glyph")
        __showGlyphs(glyphs, atPositions: positions, count: glyphs.count)
    }

    public func draw(_ layer: CGLayer, in rect: CGRect) {
        __draw(in: rect, layer: layer)
    }

    public func draw(_ layer: CGLayer, at point: CGPoint) {
        __draw(at: point, layer: layer)
    }
}

// The C forms of before.

@available(*, unavailable, message: "Use setLineDash(self:phase:lengths:)")
public func CGContextSetLineDash(_ c: CGContext?, _ phase: CGFloat, _ lengths: UnsafePointer<CGFloat>, _ count: Int) {
    c?.__setLineDash(phase: phase, lengths: lengths, count: count)
}

@available(*, unavailable, message: "Use move(to:) instead")
public func CGContextMoveToPoint(_ c: CGContext?, _ x: CGFloat, _ y: CGFloat) {
    c?.__moveTo(x: x, y: y)
}

@available(*, unavailable, message: "Use addLine(to:) instead")
public func CGContextAddLineToPoint(_ c: CGContext?, _ x: CGFloat, _ y: CGFloat) {
    c?.__addLineTo(x: x, y: y)
}

@available(*, unavailable, message: "Use addCurve(to:control1:control2:) instead")
public func CGContextAddCurveToPoint(_ c: CGContext?, _ cp1x: CGFloat, _ cp1y: CGFloat, _ cp2x: CGFloat, _ cp2y: CGFloat,
                                     _ x: CGFloat, _ y: CGFloat) {
    c?.__addCurveTo(cp1x: cp1x, cp1y: cp1y, cp2x: cp2x, cp2y: cp2y, endingAtX: x, y: y)
}

@available(*, unavailable, message: "Use addQuadCurve(to:control:)")
public func CGContextAddQuadCurveToPoint(_ c: CGContext?, _ cpx: CGFloat, _ cpy: CGFloat, _ x: CGFloat, _ y: CGFloat) {
    c?.__addQuadCurveTo(cpx: cpx, cpy: cpy, endingAtX: x, y: y)
}

@available(*, unavailable, message: "Use addRects(_:)")
public func CGContextAddRects(_ c: CGContext?, _ rects: UnsafePointer<CGRect>, _ count: Int) {
    c?.__addRects(rects, count: count)
}

@available(*, unavailable, message: "Use addLines(between:)")
public func CGContextAddLines(_ c: CGContext?, _ points: UnsafePointer<CGPoint>, _ count: Int) {
    c?.__addLines(between: points, count: count)
}

@available(*, unavailable, message: "Use addArc(center:radius:startAngle:endAngle:clockwise:)")
public func CGContextAddArc(_ c: CGContext?, _ x: CGFloat, _ y: CGFloat, _ radius: CGFloat, _ startAngle: CGFloat,
                            _ endAngle: CGFloat, _ clockwise: Int32) {
    c?.__addArc(centerX: x, y: y, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: clockwise)
}

@available(*, unavailable, message: "Use addArc(self:x1:y1:x2:y2:radius:)")
public func CGContextAddArcToPoint(_ c: CGContext?, _ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ radius: CGFloat) {
    c?.__addArc(x1: x1, y1: y1, x2: x2, y2: y2, radius: radius)
}

@available(*, unavailable, message: "Use fill(self:_:count:)")
public func CGContextFillRects(_ c: CGContext?, _ rects: UnsafePointer<CGRect>, _ count: Int) {
    c?.__fill(rects, count: count)
}

@available(*, unavailable, message: "Use strokeLineSegments(self:between:count:)")
public func CGContextStrokeLineSegments(_ c: CGContext?, _ points: UnsafePointer<CGPoint>, _ count: Int) {
    c?.__strokeLineSegments(between: points, count: count)
}

@available(*, unavailable, message: "Use clip(to:)")
public func CGContextClipToRects(_ c: CGContext?, _ rects: UnsafePointer<CGRect>, _ count: Int) {
    c?.__clip(to: rects, count: count)
}

@available(*, unavailable, message: "Use draw(_:in:)")
public func CGContextDrawImage(_ c: CGContext?, _ rect: CGRect, _ image: CGImage?) {
    guard let image else { return }
    c?.__draw(in: rect, image: image)
}

@available(*, unavailable, message: "Use draw(_:in:byTiling:)")
public func CGContextDrawTiledImage(_ c: CGContext?, _ rect: CGRect, _ image: CGImage?) {
    guard let image else { return }
    c?.__draw(in: rect, byTiling: image)
}

@available(*, unavailable, message: "Use draw(_:in:by:options:)")
public func CGContextDrawImageApplyingToneMapping(_ c: CGContext?, _ rect: CGRect, _ image: CGImage?, applying: CGToneMapping,
                                                  options: CFDictionary?) -> Bool {
    guard let c, let image else { return false }
    if #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *) {
        return c.__draw(in: rect, image: image, applying: applying, options: options)
    }
    c.__draw(in: rect, image: image)
    return true
}

@available(*, unavailable, renamed: "getter:CGContext.textPosition(self:)")
public func CGContextGetTextPosition(_ c: CGContext?) -> CGPoint {
    c?.__textPosition ?? .zero
}

@available(*, unavailable, message: "Use var textPosition")
public func CGContextSetTextPosition(_ c: CGContext?, _ x: CGFloat, _ y: CGFloat) {
    c?.__setTextPosition(x: x, y: y)
}

@available(*, unavailable, message: "Use showGlyphs(_:at:)")
public func CGContextShowGlyphsAtPositions(_ c: CGContext?, _ glyphs: UnsafePointer<CGGlyph>, _ Lpositions: UnsafePointer<CGPoint>, _ count: Int) {
    c?.__showGlyphs(glyphs, atPositions: Lpositions, count: count)
}

@available(*, unavailable, renamed: "CGContext.fillPath(self:)")
public func CGContextFillPath(_ c: CGContext?) {
    c?.__fillPath()
}

@available(*, unavailable, message: "Use fillPath(using:)")
public func CGContextEOFillPath(_ c: CGContext?) {
    c?.__eoFillPath()
}

@available(*, unavailable, renamed: "CGContext.clip(self:)")
public func CGContextClip(_ c: CGContext?) {
    c?.__clip()
}

@available(*, unavailable, message: "Use clip(using:)")
public func CGContextEOClip(_ c: CGContext?) {
    c?.__eoClip()
}

@available(*, unavailable, message: "Use draw(_:in:)")
public func CGContextDrawLayerInRect(_ context: CGContext?, _ rect: CGRect, _ layer: CGLayer?) {
    guard let layer else { return }
    context?.__draw(in: rect, layer: layer)
}

@available(*, unavailable, message: "Use draw(_:at:)")
public func CGContextDrawLayerAtPoint(_ context: CGContext?, _ point: CGPoint, _ layer: CGLayer?) {
    guard let layer else { return }
    context?.__draw(at: point, layer: layer)
}

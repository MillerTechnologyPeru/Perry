import CPerryGeometry
import Glibc
import PerryObjCInterop

// System images: SF Symbols are Apple's font, so they are drawn from what
// macOS renders of them into the app's copy (<App>.app/SFSymbols, by
// Scripts/extract-assets.sh), or else, for the common ones, drawn here in
// lines of the regular weight on a 24-point square. Either is a template
// that takes the tint of the view showing it. Names with neither give nil,
// as unknown symbols do.

enum Symbols {
    /// Names that are another symbol's drawing: the leading and trailing
    /// directions, left to right here.
    static let aliases: [String: String] = [
        "chevron.forward": "chevron.right", "chevron.backward": "chevron.left",
        "arrow.forward": "arrow.right", "arrow.backward": "arrow.left",
    ]

    /// The symbol's image at the screen's scale, at the size and weight of
    /// a configuration (UIImageSymbolConfiguration) when given one.
    static func image(named name: String, configuration: UIImageConfiguration? = nil) -> UIImage? {
        if let image = renderedImage(named: name, configuration: configuration) { return image }
        guard let draw = drawings[name] ?? aliases[name].flatMap({ drawings[$0] }) else {
            missing(name)
            return nil
        }
        let (side, lineWidth) = metrics(configuration)
        let size = CGSize(width: side, height: side)
        guard let context = CG.makeContext(size: size, scale: Screen.scale, opaque: false) else { return nil }
        defer { CG.release(context) }
        let black = UIColor.black()
        withExtendedLifetime(black) {
            CG.scaleCTM(context, side / 24, side / 24)
            CG.setStrokeColorWithColor(context, black.state.makeCGColor())
            CG.setFillColorWithColor(context, black.state.makeCGColor())
            CG.setLineWidth(context, lineWidth)
            CG.setLineCap(context, 1)
            CG.setLineJoin(context, 1)
            draw(Pen(context: context))
        }
        guard let cgImage = CG.bitmapContextCreateImage(context) else { return nil }
        defer { CG.release(cgImage) }
        let image = UIImage.make(cgImage: cgImage, scale: Screen.scale)
        image.state.renderingMode = 2
        image.state.symbolName = name
        image.state.configuration = configuration
        return image
    }

    /// The point size Scripts/extract-symbols renders symbols at, at 3
    /// pixels a point.
    static let renderedPointSize: CGFloat = 34

    /// Symbols macOS rendered, by name: nil for one it didn't.
    nonisolated(unsafe) private static var rendered: [String: Owned?] = [:]

    /// The symbol as macOS rendered it into the app's copy, at the
    /// configuration's point size and scale (the body text's, 17 points, when
    /// none is given); nil if it wasn't rendered.
    static func renderedImage(named name: String, configuration: UIImageConfiguration?) -> UIImage? {
        let glyph: Owned?
        if let cached = rendered[name] {
            glyph = cached
        } else {
            let path = NSBundle.main().bundlePath() + "/SFSymbols/" + name + ".png"
            glyph = NSData.contents(ofFile: path).flatMap { UIImage.decode($0) }
            rendered[name] = glyph
        }
        guard let glyph else { return nil }
        let state = configuration?.configuration
        let scale: CGFloat = state?.scale == 1 ? 0.8 : state?.scale == 3 ? 1.3 : 1
        let pointSize = (state?.pointSize ?? 0) > 0 ? state!.pointSize : 17
        let factor = pointSize / renderedPointSize * scale
        let size = CGSize(width: (CGFloat(CG.imageGetWidth(glyph.object)) / 3 * factor).rounded(),
                          height: (CGFloat(CG.imageGetHeight(glyph.object)) / 3 * factor).rounded())
        guard size.width > 0, size.height > 0, let context = CG.makeContext(size: size, scale: Screen.scale, opaque: false) else { return nil }
        defer { CG.release(context) }
        CG.drawFlipped(glyph.object, in: CGRect(origin: .zero, size: size), context: context)
        guard let cgImage = CG.bitmapContextCreateImage(context) else { return nil }
        defer { CG.release(cgImage) }
        let image = UIImage.make(cgImage: cgImage, scale: Screen.scale)
        image.state.renderingMode = 2
        image.state.symbolName = name
        image.state.configuration = configuration
        return image
    }

    /// Says once, with PERRY_UIKIT_SYMBOL_TRACE set, which symbol an app
    /// asked for has no drawing.
    private static func missing(_ name: String) {
        guard getenv("PERRY_UIKIT_SYMBOL_TRACE") != nil, reported.insert(name).inserted else { return }
        let line = "perry: UIKit: no drawing for SF Symbol \(name)\n"
        line.withCString { _ = write(2, $0, strlen($0)) }
    }
    nonisolated(unsafe) private static var reported: Set<String> = []

    /// Strokes and fills in the 24-point square.
    struct Pen {
        let context: CGRef

        func stroke(_ points: [(CGFloat, CGFloat)], closed: Bool = false) {
            guard let path = CG.pathCreateMutable(), let first = points.first else { return }
            defer { CG.release(path) }
            CG.pathMoveToPoint(path, nil, first.0, first.1)
            for point in points.dropFirst() { CG.pathAddLineToPoint(path, nil, point.0, point.1) }
            if closed { CG.pathCloseSubpath(path) }
            CG.addPath(context, path)
            CG.strokePath(context)
        }

        func fill(_ points: [(CGFloat, CGFloat)]) {
            guard let path = CG.pathCreateMutable(), let first = points.first else { return }
            defer { CG.release(path) }
            CG.pathMoveToPoint(path, nil, first.0, first.1)
            for point in points.dropFirst() { CG.pathAddLineToPoint(path, nil, point.0, point.1) }
            CG.pathCloseSubpath(path)
            CG.addPath(context, path)
            CG.fillPath(context)
        }

        func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, filled: Bool = false) {
            guard let path = CG.pathCreateMutable() else { return }
            defer { CG.release(path) }
            CG.pathAddEllipseInRect(path, nil, CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
            CG.addPath(context, path)
            if filled { CG.fillPath(context) } else { CG.strokePath(context) }
        }

        func arc(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, from start: CGFloat, to end: CGFloat) {
            guard let path = CG.pathCreateMutable() else { return }
            defer { CG.release(path) }
            CG.pathAddArc(path, nil, cx, cy, r, start, end, false)
            CG.addPath(context, path)
            CG.strokePath(context)
        }

        /// Clears where the next drawing goes, for marks inside a filled shape.
        func knockOut(_ body: () -> Void) {
            CG.saveGState(context)
            CG.setBlendMode(context, 16) // kCGBlendModeClear
            body()
            CG.restoreGState(context)
        }
    }

    private static func star(_ pen: Pen, filled: Bool) {
        let points = (0..<10).map { index -> (CGFloat, CGFloat) in
            let angle = -CGFloat.pi / 2 + CGFloat(index) * .pi / 5
            let radius: CGFloat = index % 2 == 0 ? 10 : 4.2
            return (12 + cos(angle) * radius, 12.5 + sin(angle) * radius)
        }
        if filled { pen.fill(points) } else { pen.stroke(points, closed: true) }
    }

    private static func heart(_ pen: Pen, filled: Bool) {
        let points = stride(from: 0.0, to: 2 * Double.pi, by: Double.pi / 40).map { t -> (CGFloat, CGFloat) in
            let x = 16 * pow(sin(t), 3)
            let y = 13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)
            return (CGFloat(12 + x * 0.6), CGFloat(11.5 - y * 0.6))
        }
        if filled { pen.fill(points) } else { pen.stroke(points, closed: true) }
    }

    private static func cross(_ pen: Pen, _ size: CGFloat) {
        pen.stroke([(12 - size, 12 - size), (12 + size, 12 + size)])
        pen.stroke([(12 + size, 12 - size), (12 - size, 12 + size)])
    }

    private static func check(_ pen: Pen, _ scale: CGFloat) {
        pen.stroke([(12 - 7 * scale, 12.5), (12 - 2 * scale, 12 + 5.5 * scale), (12 + 7.5 * scale, 12 - 6.5 * scale)])
    }

    nonisolated(unsafe) static let drawings: [String: (Pen) -> Void] = [
        "checkmark": { check($0, 1) },
        "xmark": { cross($0, 7) },
        "plus": { $0.stroke([(12, 4), (12, 20)]); $0.stroke([(4, 12), (20, 12)]) },
        "minus": { $0.stroke([(4, 12), (20, 12)]) },
        "info": { $0.stroke([(12, 10), (12, 19)]); $0.circle(12, 5.5, 1.3, filled: true) },
        "info.circle": { pen in
            pen.circle(12, 12, 10)
            pen.stroke([(12, 11), (12, 17)])
            pen.circle(12, 7.3, 1.2, filled: true)
        },
        "info.circle.fill": { pen in
            pen.circle(12, 12, 11, filled: true)
            pen.knockOut {
                pen.stroke([(12, 11), (12, 17)])
                pen.circle(12, 7.3, 1.2, filled: true)
            }
        },
        "exclamationmark.circle": { pen in
            pen.circle(12, 12, 10)
            pen.stroke([(12, 6.5), (12, 13)])
            pen.circle(12, 17, 1.2, filled: true)
        },
        "exclamationmark.triangle": { pen in
            pen.stroke([(12, 3), (22, 20.5), (2, 20.5)], closed: true)
            pen.stroke([(12, 9), (12, 14)])
            pen.circle(12, 17.3, 1.1, filled: true)
        },
        "checkmark.circle": { pen in
            pen.circle(12, 12, 10)
            check(pen, 0.6)
        },
        "checkmark.circle.fill": { pen in
            pen.circle(12, 12, 11, filled: true)
            pen.knockOut { check(pen, 0.6) }
        },
        "xmark.circle": { pen in
            pen.circle(12, 12, 10)
            cross(pen, 4)
        },
        "xmark.circle.fill": { pen in
            pen.circle(12, 12, 11, filled: true)
            pen.knockOut { cross(pen, 4) }
        },
        "chevron.left": { $0.stroke([(15.5, 4), (8, 12), (15.5, 20)]) },
        "chevron.right": { $0.stroke([(8.5, 4), (16, 12), (8.5, 20)]) },
        "chevron.up": { $0.stroke([(4, 15.5), (12, 8), (20, 15.5)]) },
        "chevron.down": { $0.stroke([(4, 8.5), (12, 16), (20, 8.5)]) },
        "arrow.left": { $0.stroke([(20, 12), (4, 12)]); $0.stroke([(10, 6), (4, 12), (10, 18)]) },
        "arrow.right": { $0.stroke([(4, 12), (20, 12)]); $0.stroke([(14, 6), (20, 12), (14, 18)]) },
        "arrow.up": { $0.stroke([(12, 20), (12, 4)]); $0.stroke([(6, 10), (12, 4), (18, 10)]) },
        "arrow.down": { $0.stroke([(12, 4), (12, 20)]); $0.stroke([(6, 14), (12, 20), (18, 14)]) },
        "arrow.clockwise": { pen in
            pen.arc(12, 12.5, 8, from: -.pi / 2 + 0.3, to: -.pi / 2 - 0.4 + 2 * .pi)
            pen.stroke([(9.5, 1.5), (13.5, 4.3), (10, 7.5)])
        },
        "magnifyingglass": { pen in
            pen.circle(10, 10, 6.5)
            pen.stroke([(14.8, 14.8), (21, 21)])
        },
        "star": { star($0, filled: false) },
        "star.fill": { star($0, filled: true) },
        "heart": { heart($0, filled: false) },
        "heart.fill": { heart($0, filled: true) },
        "trash": { pen in
            pen.stroke([(3.5, 6), (20.5, 6)])
            pen.stroke([(9, 6), (9.5, 3), (14.5, 3), (15, 6)])
            pen.stroke([(5.5, 6), (6.5, 21), (17.5, 21), (18.5, 6)])
            pen.stroke([(10, 10), (10, 17)])
            pen.stroke([(14, 10), (14, 17)])
        },
        "gear": { pen in
            for tooth in 0..<8 {
                let angle = CGFloat(tooth) * .pi / 4
                pen.stroke([(12 + cos(angle) * 7.5, 12 + sin(angle) * 7.5), (12 + cos(angle) * 10.5, 12 + sin(angle) * 10.5)])
            }
            pen.circle(12, 12, 7)
            pen.circle(12, 12, 2.8)
        },
        "house": { pen in
            pen.stroke([(2.5, 11.5), (12, 3), (21.5, 11.5)])
            pen.stroke([(5, 9.5), (5, 21), (19, 21), (19, 9.5)])
            pen.stroke([(10, 21), (10, 15), (14, 15), (14, 21)])
        },
        "person": { pen in
            pen.circle(12, 7.5, 4.5)
            pen.arc(12, 22, 8.5, from: .pi, to: 2 * .pi)
        },
        "ellipsis": { pen in
            pen.circle(5, 12, 1.8, filled: true)
            pen.circle(12, 12, 1.8, filled: true)
            pen.circle(19, 12, 1.8, filled: true)
        },
        "square.and.arrow.up": { pen in
            pen.stroke([(8.5, 9), (5, 9), (5, 21.5), (19, 21.5), (19, 9), (15.5, 9)])
            pen.stroke([(12, 15), (12, 2.5)])
            pen.stroke([(8, 6.5), (12, 2.5), (16, 6.5)])
        },
        // A padlock: its shackle over a filled body.
        "lock.fill": { pen in
            pen.arc(12, 9, 4.5, from: .pi, to: 2 * .pi)
            pen.stroke([(7.5, 9), (7.5, 11)])
            pen.stroke([(16.5, 9), (16.5, 11)])
            pen.fill([(5, 11), (19, 11), (19, 21.5), (5, 21.5)])
        },
        // Safari's compass: a ring with its needle.
        "safari": { pen in
            pen.circle(12, 12, 10)
            pen.fill([(16.5, 7.5), (13.4, 13.4), (10.6, 10.6)])
            pen.stroke([(16.5, 7.5), (7.5, 16.5)])
        },
        // A small A and a large A.
        "textformat.size": { pen in
            pen.stroke([(2, 20), (6, 10), (10, 20)])
            pen.stroke([(3.6, 16.5), (8.4, 16.5)])
            pen.stroke([(10, 20), (16, 4), (22, 20)])
            pen.stroke([(12.3, 14.5), (19.7, 14.5)])
        },
    ]
}

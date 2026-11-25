import CPerryGeometry
import CacaoRender
import CacaoSDLRenderer
import Foundation
import Glibc
import PerryObjCInterop

// Compositing through Cacao's engine: the presented layer trees become a
// display list each frame, which Cacao's compositor draws with the SDL3
// renderer UIKit's window has.
//
// A layer's own drawing is still CoreGraphics': its background in the shape
// of its corners, what it displayed, its contents and a shape layer's path
// are an image in the list, drawn again only when what they show changes.
// Plain rectangular backgrounds are colors, and rounded ones with nothing
// drawn over them are rounded rectangles the engine draws on the GPU,
// without an image. Clipping to bounds is a
// rectangular clip, opacity is an opacity effect on each drawing, and a
// layer that is turned is drawn through a transform. A layer that clips to
// rounded corners clips its sublayers to a rounded rectangle, which the
// engine cuts at the corners; turned or skewed, or with a mask, it is one
// image with its sublayers. GL and
// Metal frames are an external surface's: GL frames shared as GPU buffers
// the engine imports, or else pixels published to one.

// This file sees two families of geometry: Darwin's, laid out in C, which
// layers use, and Foundation's, which the display list uses.
private typealias CGRect = CPerryGeometry.CGRect
private typealias CGPoint = CPerryGeometry.CGPoint
private typealias CGSize = CPerryGeometry.CGSize
private typealias CGAffineTransform = CPerryGeometry.CGAffineTransform

extension Foundation.CGRect {
    fileprivate init(_ rect: CPerryGeometry.CGRect) {
        self.init(x: Double(rect.minX), y: Double(rect.minY), width: Double(rect.width), height: Double(rect.height))
    }
}

extension Transform2D {
    fileprivate init(_ transform: CPerryGeometry.CGAffineTransform) {
        self.init(a: Foundation.CGFloat(Double(transform.a)), b: Foundation.CGFloat(Double(transform.b)),
                  c: Foundation.CGFloat(Double(transform.c)), d: Foundation.CGFloat(Double(transform.d)),
                  tx: Foundation.CGFloat(Double(transform.tx)), ty: Foundation.CGFloat(Double(transform.ty)))
    }
}

final class DisplayListCompositor {
    nonisolated(unsafe) private static var current: DisplayListCompositor?

    static func shared(_ renderer: UnsafeMutableRawPointer, scale: CGFloat) -> DisplayListCompositor {
        if let current, current.renderer == renderer, current.scale == scale { return current }
        let compositor = DisplayListCompositor(renderer: renderer, scale: scale)
        current = compositor
        return compositor
    }

    /// The SDL_Renderer, which is UIKit's window's.
    let renderer: UnsafeMutableRawPointer
    let scale: CGFloat
    private let host: HostRenderer

    /// The parts of a layer that are items of their own.
    private enum Part: Int {
        case content, border, clip, backdrop, live, shadow
    }

    private struct Key: Hashable {
        let layer: UnsafeMutableRawPointer
        let part: Part
    }

    /// What a layer's image was drawn from: compared each frame.
    private struct Signature: Equatable {
        var size: CGSize
        var borderWidth: CGFloat = 0
        var cornerRadius: CGFloat
        var maskedCorners: UInt
        var color: CGRef?
        var backing: CGRef? = nil
        var backingSize = CGSize.zero
        var contents: UnsafeMutableRawPointer? = nil
        var contentsGravity = ""
        var contentsScale: CGFloat = 0
        var contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        var multiplyColor: CGRef? = nil
        var contentsSwizzle = ""
        var shape: ShapeSignature? = nil
    }

    private struct ShapeSignature: Equatable {
        var path, fillColor, strokeColor: CGRef?
        var lineWidth, strokeStart, strokeEnd, lineDashPhase: CGFloat
        var lineCap, lineJoin: String
    }

    private struct Entry {
        let image: ImageSource
        /// Counts the times the layer's image was drawn again.
        let version: Int
        /// Nil for a flattened layer's.
        let signature: Signature?
        var used: Bool
        /// A flattened layer's: its size and the generation it was drawn at.
        var flattened: (size: CGSize, generation: UInt)? = nil
    }

    private var images: [Key: Entry] = [:]

    /// The surfaces GL and Metal frames are published to, and the
    /// generation of each layer's frames last published.
    private var surfaces: [UnsafeMutableRawPointer: (surface: ExternalSurface, generation: Int, used: Bool)] = [:]

    private var versions = 0

    private init(renderer: UnsafeMutableRawPointer, scale: CGFloat) {
        (self.renderer, self.scale) = (renderer, scale)
        "perry: QuartzCore: compositing through Cacao's engine\n".withCString { _ = write(2, $0, strlen($0)) }
        // Compositing is on the main thread, where the engine draws.
        nonisolated(unsafe) let pointer = OpaquePointer(renderer)
        host = MainActor.assumeIsolated {
            let host = HostRenderer(renderer: pointer)
            host.backgroundColor = ResolvedColor(red: 0, green: 0, blue: 0)
            return host
        }
    }

    /// Composites the roots, each placed in the screen by its own
    /// transform, as a frame of `size` points. The frame is not presented.
    func draw(_ roots: [CALayer], size: CPerryGeometry.CGSize) {
        for key in images.keys { images[key]?.used = false }
        for key in surfaces.keys { surfaces[key]?.used = false }
        var items: [DisplayList.Item] = []
        for root in roots {
            let (state, _) = Presentation.presented(root)
            var toScreen = state.toSuperlayer(within: nil)
            if let turn = Compositor.displayTurn(screen: state.bounds.size) { toScreen = toScreen.concatenating(turn) }
            build(root, toScreen: toScreen, alpha: 1, into: &items)
        }
        for (key, entry) in images where !entry.used { images[key] = nil }
        for (key, entry) in surfaces where !entry.used { surfaces[key] = nil }
        let list = DisplayList(items: items)
        let frame = Foundation.CGSize(width: Double(size.width), height: Double(size.height))
        let scale = Foundation.CGFloat(Double(self.scale))
        let host = host
        let waiting = MainActor.assumeIsolated {
            host.render(list, size: frame, scale: scale)
            return host.hasNewExternalFrames
        }
        // A GL frame the GPU is still copying shows on a later pass.
        if waiting { Compositing.changed() }
    }

    private func identity(_ layer: CALayer, _ part: Part) -> Int {
        // Objects are aligned to sixteen bytes: the low bits are free.
        Int(bitPattern: layer.objcObject) | part.rawValue
    }

    /// A layer, then its sublayers, then its border; `toScreen` takes the
    /// layer's coordinates to the screen's, in points.
    private func build(_ layer: CALayer, toScreen: CGAffineTransform, alpha: CGFloat, into items: inout [DisplayList.Item]) {
        let (state, shape) = Presentation.presented(layer)
        layer.state.rendered = true
        guard !state.hidden, state.opacity > 0 else { return }
        let alpha = alpha * CGFloat(state.opacity)
        let frame = toScreen.apply(state.bounds)
        // A shadow is under all of the layer.
        if state.shadowOpacity > 0, let color = state.shadowColor, Self.isUniform(toScreen) {
            addShadow(of: layer, state: state, color: color, toScreen: toScreen, alpha: alpha, into: &items)
        }
        // A backdrop shows what is behind it, blurred, before its own fill.
        if layer.state.filters != nil, let backdrop = layer.as(CABackdropLayer.self) {
            addBackdrop(backdrop, of: layer, state: state, toScreen: toScreen, alpha: alpha, into: &items)
        }
        // A layer clipping to rounded corners, moved and scaled alike in
        // both directions, clips its sublayers to a rounded rectangle the
        // engine cuts at the corners on the GPU.
        let roundedClip = state.mask == nil && state.masksToBounds && state.cornerRadius > 0 && Self.isUniform(toScreen)
            && !Self.hasBackdrop(under: state)
        // A masked layer, or another clipping to rounded corners, and its
        // sublayers are one image, drawn again when anything changes.
        if !roundedClip, state.mask != nil || (state.masksToBounds && state.cornerRadius > 0) {
            addNestedBackdrops(in: layer, state: state, toScreen: toScreen, alpha: alpha, into: &items)
            if let entry = flattened(layer, state: state, shape: shape, toScreen: toScreen) {
                let extent = state.mask != nil ? CALayer.maskedExtent(of: state) : state.bounds
                add(entry, of: layer, part: .content, extent: extent, toScreen: toScreen, alpha: alpha, into: &items)
            }
            return
        }
        let aligned = toScreen.isAxisAligned
        let rounded = state.cornerRadius > 0 && state.backgroundColor != nil
        let textured = layer.state.backing != nil || state.contents != nil || rounded || shape != nil
            || (!aligned && state.backgroundColor != nil)
        if let shared = state.sharedFrames, !shared.hasFailed {
            if let background = state.backgroundColor, !shared.surface.isOpaque {
                addFill(frame, with: background, of: layer, alpha: alpha, into: &items)
            }
            FrameRate.glFrames += shared.takePublished()
            place(.external(ExternalContent(surface: shared.surface)), identity: identity(layer, .live), version: 0, extent: state.bounds,
                  toScreen: toScreen, alpha: alpha, into: &items)
        } else if let live = state.livePixels {
            if let background = state.backgroundColor, !live.opaque { addFill(frame, with: background, of: layer, alpha: alpha, into: &items) }
            addLive(live, of: layer, state: state, toScreen: toScreen, alpha: alpha, into: &items)
        } else if rounded, let rounding = roundedRectangle(of: layer, state: state, shape: shape, toScreen: toScreen, alpha: alpha) {
            items.append(DisplayList.Item(frame: Foundation.CGRect(frame), identity: identity(layer, .content), version: 0,
                                          value: .content(.roundedRectangle(rounding))))
        } else if textured {
            // A shape's image is of where its path draws, which may reach
            // outside the layer's bounds.
            let extent = shape.flatMap { Compositor.shapeExtent(of: layer, state: state, shape: $0) } ?? state.bounds
            if let entry = image(of: layer, state: state, shape: shape, border: false, extent: extent) {
                add(entry, of: layer, part: .content, extent: extent, toScreen: toScreen, alpha: alpha, into: &items)
            }
        } else if let background = state.backgroundColor {
            addFill(frame, with: background, of: layer, alpha: alpha, into: &items)
        }
        var inner: [DisplayList.Item] = []
        for sublayer in CALayer.orderedSublayers(of: state) {
            let presented = Presentation.state(of: sublayer)
            build(sublayer, toScreen: presented.toSuperlayer(within: state).concatenating(toScreen), alpha: alpha, into: &inner)
        }
        if state.masksToBounds, !inner.isEmpty {
            // To the layer's box on the screen, in the shape of its corners.
            let clip = roundedClip
                ? ClipEffect(roundedRectangleOf: Foundation.CGRect(frame).size, cornerRadius: Foundation.CGFloat(Double(state.cornerRadius * toScreen.a)),
                             corners: Self.corners(state.maskedCorners))
                : ClipEffect(path: Path(Foundation.CGRect(frame)), isRectangle: true)
            items.append(DisplayList.Item(frame: Foundation.CGRect(frame), identity: identity(layer, .clip), version: 0,
                                          value: .effect(.clip(clip), DisplayList(items: inner))))
        } else {
            items.append(contentsOf: inner)
        }
        if state.borderWidth > 0, state.borderColor != nil, let entry = image(of: layer, state: state, shape: nil, border: true, extent: state.bounds) {
            add(entry, of: layer, part: .border, extent: state.bounds, toScreen: toScreen, alpha: alpha, into: &items)
        }
    }

    // MARK: Items

    /// An item, faded if `alpha` is less than one. One drawing can't
    /// overlap itself, so the engine fades it without a group.
    private func append(_ item: DisplayList.Item, alpha: CGFloat, into items: inout [DisplayList.Item]) {
        guard alpha < 1 else {
            items.append(item)
            return
        }
        items.append(DisplayList.Item(frame: item.frame, identity: item.identity, version: item.version,
                                      value: .effect(.opacity(Double(alpha)), DisplayList(items: [item]))))
    }

    /// A gray or RGB color, faded by `alpha`, each part within 0 to 1: a
    /// spring animating a color overshoots them, and the engine makes
    /// bytes of them.
    private func resolved(_ color: CGRef, alpha: CGFloat) -> ResolvedColor? {
        guard let components = CG.colorGetComponents(color) else { return nil }
        let gray = CG.colorGetNumberOfComponents(color) == 2
        let (r, g, b, a) = gray ? (components[0], components[0], components[0], components[1])
            : (components[0], components[1], components[2], components[3])
        func unit(_ value: CGFloat) -> Float { value.isNaN ? 0 : Float(min(max(value, 0), 1)) }
        return ResolvedColor(red: unit(r), green: unit(g), blue: unit(b), opacity: unit(a * alpha))
    }

    private func addFill(_ rect: CGRect, with color: CGRef, of layer: CALayer, alpha: CGFloat, into items: inout [DisplayList.Item]) {
        guard let resolved = resolved(color, alpha: alpha) else { return }
        items.append(DisplayList.Item(frame: Foundation.CGRect(rect), identity: identity(layer, .content), version: 0,
                                      value: .content(.color(resolved))))
    }

    /// A layer whose only drawing is its rounded background, moved and
    /// scaled alike in both directions: a rounded rectangle, which the
    /// engine draws on the GPU. Nil for anything else, drawn as an image.
    private func roundedRectangle(of layer: CALayer, state: LayerState, shape: ShapeLayerState?, toScreen: CGAffineTransform,
                                  alpha: CGFloat) -> RoundedRectangleContent? {
        guard shape == nil, state.contents == nil, layer.state.backing == nil, Self.isUniform(toScreen), !layer.draws,
              let background = state.backgroundColor, let color = resolved(background, alpha: alpha) else { return nil }
        return RoundedRectangleContent(color: color, cornerRadius: Foundation.CGFloat(Double(state.cornerRadius * toScreen.a)),
                                       corners: Self.corners(state.maskedCorners))
    }

    /// Whether a transform only moves and scales, alike in both directions,
    /// so a rounded rectangle stays one, its corners circles.
    private static func isUniform(_ toScreen: CGAffineTransform) -> Bool {
        toScreen.b == 0 && toScreen.c == 0 && toScreen.a > 0 && toScreen.a == toScreen.d
    }

    /// CACornerMask's corners, min and max x and y (1, 2, 4 and 8), as
    /// Cacao's.
    private static func corners(_ mask: UInt) -> RoundedRectangleContent.Corners {
        var corners: RoundedRectangleContent.Corners = []
        if mask & 1 != 0 { corners.insert(.topLeading) }
        if mask & 2 != 0 { corners.insert(.topTrailing) }
        if mask & 4 != 0 { corners.insert(.bottomLeading) }
        if mask & 8 != 0 { corners.insert(.bottomTrailing) }
        return corners
    }

    /// Whether a visible backdrop layer is among the sublayers: what it
    /// blurs is the screen's, which a clip's offscreen drawing doesn't
    /// have, so such a layer is still drawn as one image over the backdrops.
    private static func hasBackdrop(under state: LayerState) -> Bool {
        state.sublayers.contains { sublayer in
            let presented = Presentation.state(of: sublayer)
            guard !presented.hidden, presented.opacity > 0 else { return false }
            if sublayer.state.filters != nil, sublayer.as(CABackdropLayer.self) != nil { return true }
            return hasBackdrop(under: presented)
        }
    }

    /// A drawing that fills `extent` of the layer, placed by `toScreen`: in
    /// its box on the screen when it is only moved and scaled, and through
    /// a transform when it is mirrored or turned.
    private func place(_ content: DisplayList.Content, identity: Int, version: Int, extent: CGRect, toScreen: CGAffineTransform, alpha: CGFloat,
                       into items: inout [DisplayList.Item]) {
        if toScreen.b == 0, toScreen.c == 0, toScreen.a > 0, toScreen.d > 0 {
            append(DisplayList.Item(frame: Foundation.CGRect(toScreen.apply(extent)), identity: identity, version: version,
                                    value: .content(content)), alpha: alpha, into: &items)
            return
        }
        let item = DisplayList.Item(frame: Foundation.CGRect(extent), identity: identity, version: version, value: .content(content))
        var inner: [DisplayList.Item] = []
        append(item, alpha: alpha, into: &inner)
        // The engine draws what is transformed into a layer of its own,
        // kept by an identity that is not the drawing's: the next free bit.
        items.append(DisplayList.Item(frame: Foundation.CGRect(toScreen.apply(extent)), identity: identity | 8, version: version,
                                      value: .effect(.transform(Transform2D(toScreen)), DisplayList(items: inner))))
    }

    private func add(_ entry: Entry, of layer: CALayer, part: Part, extent: CGRect, toScreen: CGAffineTransform, alpha: CGFloat,
                     into items: inout [DisplayList.Item]) {
        place(.image(ImageContent(source: entry.image, interpolation: .medium)), identity: identity(layer, part), version: entry.version,
              extent: extent, toScreen: toScreen, alpha: alpha, into: &items)
    }

    // MARK: Backdrops

    private func addBackdrop(_ backdrop: CABackdropLayer, of layer: CALayer, state: LayerState, toScreen: CGAffineTransform, alpha: CGFloat,
                             rounding: (radius: CGFloat, corners: UInt)? = nil, into items: inout [DisplayList.Item]) {
        guard !Compositor.blurDisabled, toScreen.isAxisAligned, alpha > 0 else { return }
        let (radius, saturation) = backdrop.backdropEffect
        let shown = radius * abs(toScreen.a)
        guard shown * scale >= 1 else { return }
        // CACornerMask's corners are min and max x and y: 1, 2, 4 and 8.
        var corners: BackdropContent.Corners = []
        let masked = rounding?.corners ?? state.maskedCorners
        if masked & 1 != 0 { corners.insert(.topLeading) }
        if masked & 2 != 0 { corners.insert(.topTrailing) }
        if masked & 4 != 0 { corners.insert(.bottomLeading) }
        if masked & 8 != 0 { corners.insert(.bottomTrailing) }
        let cornerRadius = (rounding?.radius ?? state.cornerRadius) * abs(toScreen.a)
        let content = BackdropContent(blurRadius: Foundation.CGFloat(Double(shown)), saturation: Double(saturation),
                                      cornerRadius: Foundation.CGFloat(Double(cornerRadius)), corners: corners)
        append(DisplayList.Item(frame: Foundation.CGRect(toScreen.apply(state.bounds)), identity: identity(layer, .backdrop), version: 0,
                                value: .content(.backdrop(content))), alpha: alpha, into: &items)
    }

    // MARK: Shadows

    /// The layer's shadow: its silhouette in the shadow's color, blurred and
    /// moved. The silhouette is the layer's box if it has a background or is
    /// a backdrop, and otherwise the boxes of the nearest layers under it
    /// that do, each with its rounded corners; what a layer draws itself
    /// (text, images, shapes) casts none yet. Under a backdrop the shadow
    /// is left out of the silhouette, so the backdrop doesn't blur its own
    /// shadow into itself.
    private func addShadow(of layer: CALayer, state: LayerState, color: CGRef, toScreen: CGAffineTransform, alpha: CGFloat,
                           into items: inout [DisplayList.Item]) {
        guard let tint = resolved(color, alpha: alpha * CGFloat(state.shadowOpacity)), tint.opacity > 0 else { return }
        var boxes: [(rect: Foundation.CGRect, radius: Double)] = []
        var overBackdrop = false
        func collect(_ layer: CALayer, _ state: LayerState, _ toScreen: CGAffineTransform, depth: Int) {
            let isBackdrop = layer.state.filters != nil && layer.as(CABackdropLayer.self) != nil
            let isFilled = state.backgroundColor.flatMap { resolved($0, alpha: 1) }.map { $0.opacity > 0.02 } ?? false
            if isBackdrop || isFilled {
                if isBackdrop { overBackdrop = true }
                boxes.append((Foundation.CGRect(toScreen.apply(state.bounds)), Double(state.cornerRadius * abs(toScreen.a))))
                return
            }
            guard depth < 4 else { return }
            for sublayer in CALayer.orderedSublayers(of: state) {
                let presented = Presentation.state(of: sublayer)
                guard !presented.hidden, presented.opacity > 0 else { continue }
                collect(sublayer, presented, presented.toSuperlayer(within: state).concatenating(toScreen), depth: depth + 1)
            }
        }
        collect(layer, state, toScreen, depth: 0)
        guard var extent = boxes.first?.rect else { return }
        for box in boxes.dropFirst() { extent = extent.union(box.rect) }
        guard extent.width >= 1, extent.height >= 1, extent.minX.isFinite, extent.minY.isFinite, extent.width.isFinite,
              extent.height.isFinite else { return }
        let radius = Double(max(state.shadowRadius, 0) * toScreen.a)
        let offset = Foundation.CGSize(width: Double(state.shadowOffset.width * toScreen.a), height: Double(state.shadowOffset.height * toScreen.a))
        let spread = radius * 3 + 1
        let frame = extent.union(extent.offsetBy(dx: offset.width, dy: offset.height)).insetBy(dx: -spread, dy: -spread)
        guard frame.width * Double(scale) <= 4096, frame.height * Double(scale) <= 4096 else { return }
        let outline = Path { path in
            for box in boxes {
                let corner = min(box.radius, Double(min(box.rect.width, box.rect.height)) / 2)
                path.addRoundedRect(in: box.rect.offsetBy(dx: -frame.minX, dy: -frame.minY),
                                    cornerSize: Foundation.CGSize(width: corner, height: corner), style: .circular)
            }
        }
        let silhouette = DrawingContent(operations: [
            .shape(ShapeContent(path: outline, color: ResolvedColor(red: 0, green: 0, blue: 0), drawing: .fill(FillStyle())), DrawingState())
        ])
        var shadowed = DrawingState()
        shadowed.filters = [.shadow(color: tint, radius: Foundation.CGFloat(radius), offset: offset, blendMode: .normal, placement: .only,
                                    invertsAlpha: false)]
        var drawing = DrawingContent(operations: [.layer(silhouette, shadowed)])
        if overBackdrop {
            var outside = DrawingState()
            outside.masks = [DrawingMask(content: silhouette, opacity: 1, isInverse: true)]
            drawing = DrawingContent(operations: [.layer(drawing, outside)])
        }
        items.append(DisplayList.Item(frame: frame, identity: identity(layer, .shadow), version: 0,
                                      value: .content(.drawing(drawing))))
    }

    /// The backdrops of the layers under one that is drawn flattened, drawn
    /// before it, within its rounded corners, as it is one image.
    private func addNestedBackdrops(in layer: CALayer, state: LayerState, toScreen: CGAffineTransform, alpha: CGFloat,
                                    into items: inout [DisplayList.Item]) {
        let rounding: (radius: CGFloat, corners: UInt)? = state.masksToBounds && state.cornerRadius > 0 && toScreen.isAxisAligned
            ? (state.cornerRadius, state.maskedCorners) : nil
        func descend(_ state: LayerState, toScreen: CGAffineTransform, alpha: CGFloat) {
            for sublayer in CALayer.orderedSublayers(of: state) {
                let presented = Presentation.state(of: sublayer)
                guard !presented.hidden, presented.opacity > 0 else { continue }
                let placed = presented.toSuperlayer(within: state).concatenating(toScreen)
                let faded = alpha * CGFloat(presented.opacity)
                if sublayer.state.filters != nil, let backdrop = sublayer.as(CABackdropLayer.self) {
                    addBackdrop(backdrop, of: sublayer, state: presented, toScreen: placed, alpha: faded, rounding: rounding, into: &items)
                }
                descend(presented, toScreen: placed, alpha: faded)
            }
        }
        descend(state, toScreen: toScreen, alpha: alpha)
    }

    // MARK: GL and Metal frames

    /// A GL or Metal frame, published to the layer's surface when it is new.
    private func addLive(_ live: LivePixels, of layer: CALayer, state: LayerState, toScreen: CGAffineTransform, alpha: CGFloat,
                         into items: inout [DisplayList.Item]) {
        let key = layer.objcObject
        var entry = surfaces[key] ?? (ExternalSurface(), live.generation &- 1, true)
        if entry.generation != live.generation {
            entry.surface.publish(pixels: UnsafeRawBufferPointer(start: live.data, count: live.width * live.height * 4),
                                  width: live.width, height: live.height, format: live.bgra ? .bgra : .rgba,
                                  rowOrder: live.topFirst ? .topFirst : .bottomFirst, isOpaque: live.opaque)
            FrameRate.glFrames += max(live.generation &- entry.generation, 1)
            entry.generation = live.generation
        }
        live.shown = live.generation
        entry.used = true
        surfaces[key] = entry
        place(.external(ExternalContent(surface: entry.surface)), identity: identity(layer, .live), version: 0, extent: state.bounds,
              toScreen: toScreen, alpha: alpha, into: &items)
    }

    // MARK: Images

    /// An image of premultiplied RGBA pixels from CoreGraphics' ARGB ones.
    private func makeImage(width: Int, height: Int, pixels: UnsafeRawPointer, pitch: Int) -> ImageSource {
        var data = Data(count: width * height * 4)
        data.withUnsafeMutableBytes { (target: UnsafeMutableRawBufferPointer) in
            let out = target.bindMemory(to: UInt32.self)
            for row in 0..<height {
                let source = (pixels + row * pitch).assumingMemoryBound(to: UInt32.self)
                for column in 0..<width {
                    // B, G, R, A bytes to R, G, B, A: red and blue exchanged.
                    // The bytes are read as a little-endian word whatever the
                    // machine's byte order (0xAARRGGBB), and written back so.
                    let pixel = UInt32(littleEndian: source[column])
                    let swapped = (pixel & 0xff00_ff00) | ((pixel & 0x00ff_0000) >> 16) | ((pixel & 0x0000_00ff) << 16)
                    out[row * width + column] = swapped.littleEndian
                }
            }
        }
        return ImageSource(pixels: ImageSource.Pixels(data: data, bytesPerRow: width * 4), width: width, height: height,
                           scale: Foundation.CGFloat(Double(scale)))
    }

    private func nextVersion() -> Int {
        versions &+= 1
        return versions
    }

    /// The image of `extent` of the layer (its bounds, or where its shape
    /// draws), drawn again when what it shows has changed.
    private func image(of layer: CALayer, state: LayerState, shape: ShapeLayerState?, border: Bool, extent: CGRect) -> Entry? {
        let key = Key(layer: layer.objcObject, part: border ? .border : .content)
        let model = layer.state
        var signature = Signature(size: extent.size, cornerRadius: state.cornerRadius, maskedCorners: state.maskedCorners,
                                  color: border ? state.borderColor : state.backgroundColor)
        if border {
            signature.borderWidth = state.borderWidth
        } else {
            (signature.backing, signature.backingSize, signature.contents) = (model.backing, model.backingSize, state.contents?.objcObject)
            (signature.contentsGravity, signature.contentsScale) = (state.contentsGravity, state.contentsScale)
            signature.contentsRect = state.contentsRect
            (signature.multiplyColor, signature.contentsSwizzle) = (state.contentsMultiplyColor, state.contentsSwizzle)
            if let shape {
                signature.shape = ShapeSignature(path: shape.path, fillColor: shape.fillColor, strokeColor: shape.strokeColor,
                                                 lineWidth: shape.lineWidth, strokeStart: shape.strokeStart, strokeEnd: shape.strokeEnd,
                                                 lineDashPhase: shape.lineDashPhase, lineCap: shape.lineCap, lineJoin: shape.lineJoin)
            }
        }
        if let entry = images[key], entry.signature == signature {
            images[key]?.used = true
            return entry
        }
        images[key] = nil
        // A layer laid out to a size that is not a number, or is endless,
        // has nothing to draw (and Int() of it would trap).
        let pixels = (extent.width * scale, extent.height * scale)
        guard pixels.0.isFinite, pixels.1.isFinite, pixels.0 < 1_048_576, pixels.1 < 1_048_576 else { return nil }
        let width = Int(pixels.0.rounded(.up)), height = Int(pixels.1.rounded(.up))
        guard width > 0, height > 0, let context = CG.makeContext(size: extent.size, scale: scale, opaque: false) else { return nil }
        defer { CG.release(context) }
        // The image is whole pixels and the layer may not be: what is drawn
        // is stretched to fill it, so that its last row and column are
        // covered, not left partly clear at the layer's edge.
        CG.scaleCTM(context, CGFloat(width) / (extent.width * scale), CGFloat(height) / (extent.height * scale))
        CG.translateCTM(context, -extent.minX, -extent.minY)
        if border {
            CALayer.drawBorder(of: state, in: context)
        } else {
            CALayer.drawBackground(of: state, in: context)
            CG.saveGState(context)
            if state.masksToBounds { CALayer.clip(to: state, in: context) }
            CALayer.drawContent(of: layer, state: state, shape: shape, in: context)
            CG.restoreGState(context)
        }
        guard let data = CG.bitmapContextGetData(context) else { return nil }
        let entry = Entry(image: makeImage(width: width, height: height, pixels: data, pitch: width * 4), version: nextVersion(),
                          signature: signature, used: true)
        images[key] = entry
        return entry
    }

    /// A layer and its sublayers as one image, within its mask or its
    /// rounded corners.
    private func flattened(_ layer: CALayer, state: LayerState, shape: ShapeLayerState?, toScreen: CGAffineTransform) -> Entry? {
        let key = Key(layer: layer.objcObject, part: .content)
        // What shows is the layer's bounds, or where its mask lets content
        // through when that reaches beyond them.
        let extent = state.mask != nil ? CALayer.maskedExtent(of: state) : state.bounds
        // Nothing has changed since it was drawn, and nothing in it moves
        // without changing: what was drawn still shows.
        if let entry = images[key], let flattened = entry.flattened, flattened.size == extent.size,
           flattened.generation == Compositing.generation, !Compositor.isAnimating(layer) {
            images[key]?.used = true
            return entry
        }
        let generation = Compositing.generation
        images[key] = nil
        // Drawn at the resolution it shows at: a layer scaled down on the
        // display needs only the pixels it takes up, not its own size's.
        let shown = (toScreen.a * toScreen.d - toScreen.b * toScreen.c).magnitude.squareRoot()
        let renderScale = scale * min(1, shown.isFinite ? max(shown, 0.05) : 1)
        let pixels = (extent.width * renderScale, extent.height * renderScale)
        guard pixels.0.isFinite, pixels.1.isFinite, pixels.0 < 1_048_576, pixels.1 < 1_048_576 else { return nil }
        let width = max(Int(pixels.0.rounded(.up)), 1), height = max(Int(pixels.1.rounded(.up)), 1)
        // A masked layer's image is made at this size: its pixels are the
        // image's. Drawing it again would shrink
        // it by the fraction of a pixel its extent has past a whole one.
        if state.mask != nil, let masked = CALayer.maskedImage(of: layer, state: state, shape: shape, scale: renderScale),
           CG.imageGetWidth(masked.object) == width, CG.imageGetHeight(masked.object) == height,
           let image = CG.withPixels(of: masked.object, { pixels, bytesPerRow -> ImageSource? in
               bytesPerRow >= width * 4 ? makeImage(width: width, height: height, pixels: pixels, pitch: bytesPerRow) : nil
           }) {
            let entry = Entry(image: image, version: nextVersion(), signature: nil, used: true, flattened: (extent.size, generation))
            images[key] = entry
            return entry
        }
        guard let context = CG.makeContext(size: extent.size, scale: renderScale, opaque: false) else { return nil }
        defer { CG.release(context) }
        if state.mask != nil {
            guard let image = CALayer.maskedImage(of: layer, state: state, shape: shape, scale: renderScale) else { return nil }
            CG.drawFlipped(image.object, in: CGRect(origin: .zero, size: extent.size), context: context)
        } else {
            CG.translateCTM(context, -state.bounds.minX, -state.bounds.minY)
            CALayer.drawTree(of: layer, state: state, shape: shape, in: context)
        }
        guard let data = CG.bitmapContextGetData(context) else { return nil }
        let entry = Entry(image: makeImage(width: width, height: height, pixels: data, pitch: width * 4), version: nextVersion(),
                          signature: nil, used: true, flattened: (extent.size, generation))
        images[key] = entry
        return entry
    }
}

import CPerryGeometry
import Glibc
import PerryObjCInterop
import SDL3Swift

// Compositing layer trees on the GPU, for UIKit's live view, through the
// SDL3 renderer UIKit's window draws with (SDL3Swift's, over the renderer's pointer). Each layer's own content (its
// background in the shape of its corners, what it displayed, its contents
// and a shape layer's path) and its border are textures, drawn with
// CoreGraphics only when they change; each frame places them as the layers
// present, by their geometry, opacity and clipping. Rotated layers turn
// about their centers. Plain rectangular backgrounds are filled without a
// texture. The GPU clips to rectangles, so a layer that clips to rounded
// corners, or has a mask, is drawn with its sublayers as one texture,
// through CoreGraphics, each frame.

/// Displays the visible layers in the trees that need it, as an app's
/// drawing for them happens before compositing.
@c(_PerryCADisplayLayers)
public func PerryCADisplayLayers(_ roots: UnsafePointer<UnsafeMutableRawPointer?>?, _ count: Int) {
    guard let roots else { return }
    for index in 0..<count {
        guard let root = roots[index] else { continue }
        Compositor.display(CALayer.wrap(root))
    }
}

/// Composites the layer trees, back to front, with the renderer, at
/// `scale` pixels a point, and shows the frame; false without a renderer.
@c(_PerryCAComposite)
public func PerryCAComposite(_ renderer: UnsafeMutableRawPointer?, _ scale: Double, _ roots: UnsafePointer<UnsafeMutableRawPointer?>?,
                             _ count: Int) -> Bool {
    guard let renderer else { return false }
    let compositor = Compositor.shared(renderer, scale: CGFloat(scale))
    let layers = (0..<count).compactMap { roots?[$0] }.map(CALayer.wrap)
    compositor.draw(layers)
    return true
}

final class Compositor {
    nonisolated(unsafe) private static var current: Compositor?

    static func shared(_ renderer: UnsafeMutableRawPointer, scale: CGFloat) -> Compositor {
        let pointer = OpaquePointer(renderer)
        if let current, current.renderer.unsafePointer == pointer, current.scale == scale { return current }
        let compositor = Compositor(renderer: SDLRenderer(unownedPointer: pointer), scale: scale)
        current = compositor
        return compositor
    }

    let renderer: SDLRenderer
    let scale: CGFloat

    /// A layer's texture, of its content or its border, and what it shows.
    private struct Key: Hashable {
        let layer: UnsafeMutableRawPointer
        let border: Bool
    }

    /// What a layer's texture was drawn from: compared each frame, so
    /// values rather than a description of them. Colors, paths, images and
    /// contents are compared as the objects they are.
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
        let texture: SDLTexture
        /// Nil for a flattened layer's.
        let signature: Signature?
        var used: Bool
        /// A flattened layer's: its size and the generation it was drawn at.
        var flattened: (size: CGSize, generation: UInt)? = nil
    }

    private var textures: [Key: Entry] = [:]

    init(renderer: SDLRenderer, scale: CGFloat) {
        (self.renderer, self.scale) = (renderer, scale)
    }

    /// The renderer that made the textures may be gone by now, and SDL
    /// freed its textures with it: they are left alone, not destroyed twice.
    deinit {
        for entry in textures.values { _ = Unmanaged.passRetained(entry.texture) }
        for entry in liveTextures.values { _ = Unmanaged.passRetained(entry.texture) }
        for shared in sharedTextures.values { for case let texture? in shared.textures { _ = Unmanaged.passRetained(texture) } }
    }

    /// Displays the visible layers that need it.
    static func display(_ layer: CALayer) {
        let state = layer.state
        guard !state.hidden, state.opacity > 0 else { return }
        CALayer.displayIfNeeded(layer)
        for sublayer in state.sublayers { display(sublayer) }
    }

    /// With PERRY_UIKIT_COMPOSITE_TRACE set, the layers composited, about
    /// every three seconds: each one's frame on the screen, opacity, whether
    /// it is hidden, its animations and what it is drawn with.
    nonisolated(unsafe) static let tracing = getenv("PERRY_UIKIT_COMPOSITE_TRACE") != nil
    nonisolated(unsafe) private static var lastTrace: Double = 0
    private var tracingFrame = false

    private func trace(_ layer: CALayer, state: LayerState, frame: CGRect, depth: Int, how: String) {
        typealias Get = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> UnsafeMutableRawPointer?
        let send = unsafeBitCast(ObjCRuntime.msgSend, to: Get.self)
        func className(_ object: UnsafeMutableRawPointer?) -> String {
            guard let object, let cls = send(object, ObjCRuntime.selector("class")),
                  let text = send(cls, ObjCRuntime.selector("description")) else { return "nil" }
            return String(objCArgument: text)
        }
        let name = className(layer.objcObject) + "/" + className(send(layer.objcObject, ObjCRuntime.selector("delegate")))
        let line = String(repeating: "  ", count: depth)
            + "\(name) \(frame) opacity \(state.opacity) hidden \(state.hidden) animations \(layer.state.animations.count) \(how)\n"
        line.withCString { _ = write(2, $0, strlen($0)) }
    }

    /// A color's components, for the trace.
    static func describe(_ color: CGRef) -> String {
        guard let components = CG.colorGetComponents(color) else { return "?" }
        let count = CG.colorGetNumberOfComponents(color)
        return (0..<count).map { "\((Double(components[$0]) * 100).rounded() / 100)" }.joined(separator: " ")
    }

    /// PERRY_UIKIT_DISPLAY_ROTATION set to 90 or 270 shows the app's screen
    /// turned a quarter clockwise or counterclockwise on the display, for an
    /// app that draws a landscape picture into a portrait screen, as a phone
    /// held sideways shows it. UIKit fits the turned screen to the window and
    /// turns touches back.
    nonisolated(unsafe) static let displayRotation: Int = {
        guard let setting = getenv("PERRY_UIKIT_DISPLAY_ROTATION").flatMap({ Int(String(cString: $0)) }) else { return 0 }
        return setting == 90 || setting == 270 || setting == -90 ? (setting + 360) % 360 : 0
    }()

    /// The quarter turn from a screen of `screen` points to the display's.
    static func displayTurn(screen: CGSize) -> CGAffineTransform? {
        switch displayRotation {
        case 90: return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: screen.height, ty: 0)
        case 270: return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: screen.width)
        default: return nil
        }
    }

    /// Composites the roots, each placed in the screen by its own transform.
    func draw(_ roots: [CALayer]) {
        tracingFrame = false
        if Compositor.tracing, Clock.now - Compositor.lastTrace > 3 {
            Compositor.lastTrace = Clock.now
            tracingFrame = true
            "perry: QuartzCore: composite\n".withCString { _ = write(2, $0, strlen($0)) }
        }
        for key in textures.keys { textures[key]?.used = false }
        for key in liveTextures.keys { liveTextures[key]?.used = false }
        for entry in sharedTextures.values { entry.used = false }
        try? renderer.setDrawColorFloat(red: 0, green: 0, blue: 0, alpha: 1)
        try? renderer.setClipRect(nil)
        do {
            try renderer.clear()
        } catch {
            if tracingFrame { "perry: QuartzCore: clearing failed: \(error)\n".withCString { _ = write(2, $0, strlen($0)) } }
        }
        for root in roots {
            let (state, _) = Presentation.presented(root)
            var toScreen = state.toSuperlayer(within: nil)
            if let turn = Compositor.displayTurn(screen: state.bounds.size) { toScreen = toScreen.concatenating(turn) }
            composite(root, toScreen: toScreen, alpha: 1, clip: nil)
        }
        for (key, entry) in textures where !entry.used { textures[key] = nil }
        for (key, entry) in liveTextures where !entry.used { liveTextures[key] = nil }
        for (key, entry) in sharedTextures where !entry.used {
            entry.destroy()
            sharedTextures[key] = nil
        }
        if FrameRate.on { FrameRate.frame(renderer: renderer) }
        renderer.present()
    }

    /// A layer, then its sublayers, then its border; `toScreen` takes the
    /// layer's coordinates to the screen's, in points.
    private func composite(_ layer: CALayer, toScreen: CGAffineTransform, alpha: CGFloat, clip: CGRect?, depth: Int = 0) {
        let (state, shape) = Presentation.presented(layer)
        layer.state.rendered = true
        if tracingFrame {
            trace(layer, state: state, frame: toScreen.apply(state.bounds), depth: depth,
                  how: (state.sharedFrames != nil ? "shared" : state.livePixels != nil ? "live" : (layer.state.backing != nil || state.contents != nil) ? "textured"
                      : state.backgroundColor != nil ? "filled" : "")
                      + (state.backgroundColor.map { " background " + Compositor.describe($0) } ?? ""))
        }
        guard !state.hidden, state.opacity > 0 else { return }
        let alpha = alpha * CGFloat(state.opacity)
        let frame = toScreen.apply(state.bounds)
        setClip(clip)
        // A masked layer, or one clipping to rounded corners, and its
        // sublayers are one texture, drawn again each frame.
        if state.mask != nil || (state.masksToBounds && state.cornerRadius > 0) {
            drawFlattened(layer, state: state, shape: shape, toScreen: toScreen, alpha: alpha)
            return
        }
        let aligned = toScreen.isAxisAligned
        let rounded = state.cornerRadius > 0 && state.backgroundColor != nil
        let textured = layer.state.backing != nil || state.contents != nil || rounded || shape != nil
            || (!aligned && state.backgroundColor != nil)
        if let shared = state.sharedFrames, !shared.hasFailed {
            if let background = state.backgroundColor, !shared.opaque { fill(frame, with: background, alpha: alpha) }
            _ = drawShared(shared, of: layer, state: state, toScreen: toScreen, alpha: alpha)
        } else if let live = state.livePixels {
            if let background = state.backgroundColor, !live.opaque { fill(frame, with: background, alpha: alpha) }
            drawLive(live, of: layer, state: state, toScreen: toScreen, alpha: alpha)
        } else if textured {
            drawTexture(of: layer, state: state, shape: shape, border: false, toScreen: toScreen, alpha: alpha)
        } else if let background = state.backgroundColor {
            fill(frame, with: background, alpha: alpha)
        }
        let inner = state.masksToBounds ? (clip.map { $0.intersection(frame) } ?? frame) : clip
        if inner.map({ $0.width > 0 && $0.height > 0 }) ?? true {
            for sublayer in CALayer.orderedSublayers(of: state) {
                let presented = Presentation.state(of: sublayer)
                composite(sublayer, toScreen: presented.toSuperlayer(within: state).concatenating(toScreen), alpha: alpha, clip: inner,
                          depth: depth + 1)
            }
        }
        if state.borderWidth > 0, state.borderColor != nil {
            setClip(clip)
            drawTexture(of: layer, state: state, shape: nil, border: true, toScreen: toScreen, alpha: alpha)
        }
    }

    private func setClip(_ clip: CGRect?) {
        guard let clip else {
            try? renderer.setClipRect(nil)
            return
        }
        try? renderer.setClipRect(SDLRect(x: Int32((clip.minX * scale).rounded(.down)), y: Int32((clip.minY * scale).rounded(.down)),
                                          width: Int32(max((clip.width * scale).rounded(.up), 0)), height: Int32(max((clip.height * scale).rounded(.up), 0))))
    }

    /// The rectangle on the display, its edges on whole pixels: layers that
    /// meet at an edge meet at the same pixel, whatever the scale, with no
    /// pixel between them that each covers in part.
    func pixels(_ rect: CGRect) -> SDLFRect {
        let left = (rect.minX * scale).rounded(), top = (rect.minY * scale).rounded()
        let right = (rect.maxX * scale).rounded(), bottom = (rect.maxY * scale).rounded()
        return SDLFRect(x: Float(left), y: Float(top), width: Float(right - left), height: Float(bottom - top))
    }

    private func fill(_ rect: CGRect, with color: CGRef, alpha: CGFloat) {
        guard let components = CG.colorGetComponents(color) else { return }
        let gray = CG.colorGetNumberOfComponents(color) == 2
        let (r, g, b, a) = gray ? (components[0], components[0], components[0], components[1])
            : (components[0], components[1], components[2], components[3])
        try? renderer.setDrawBlendMode([.alpha])
        try? renderer.setDrawColorFloat(red: Float(r), green: Float(g), blue: Float(b), alpha: Float(a * alpha))
        try? renderer.fill(pixels(rect))
    }

    private func drawFlattened(_ layer: CALayer, state: LayerState, shape: ShapeLayerState?, toScreen: CGAffineTransform, alpha: CGFloat) {
        let key = Key(layer: layer.objcObject, border: false)
        // Nothing has changed since it was drawn, and nothing in it moves
        // without changing: what was drawn still shows.
        if let entry = textures[key], let flattened = entry.flattened, flattened.size == state.bounds.size,
           flattened.generation == Compositing.generation, !Compositor.isAnimating(layer) {
            textures[key]?.used = true
            place(entry.texture, state: state, toScreen: toScreen, alpha: alpha)
            return
        }
        let generation = Compositing.generation
        textures[key] = nil
        let width = Int((state.bounds.width * scale).rounded(.up)), height = Int((state.bounds.height * scale).rounded(.up))
        guard width > 0, height > 0, let context = CG.makeContext(size: state.bounds.size, scale: scale, opaque: false) else { return }
        defer { CG.release(context) }
        if state.mask != nil {
            guard let image = CALayer.maskedImage(of: layer, state: state, shape: shape) else { return }
            CG.drawFlipped(image.object, in: CGRect(origin: .zero, size: state.bounds.size), context: context)
        } else {
            CG.translateCTM(context, -state.bounds.minX, -state.bounds.minY)
            CALayer.drawTree(of: layer, state: state, shape: shape, in: context)
        }
        guard let data = CG.bitmapContextGetData(context),
              let texture = makeTexture(width: width, height: height, pixels: data, pitch: width * 4) else { return }
        textures[key] = Entry(texture: texture, signature: nil, used: true, flattened: (state.bounds.size, generation))
        place(texture, state: state, toScreen: toScreen, alpha: alpha)
    }

    /// Whether the layer, its mask or anything under them has animations,
    /// which change what shows without changing the layers.
    private static func isAnimating(_ layer: CALayer) -> Bool {
        let state = layer.state
        if !state.animations.isEmpty { return true }
        if state.livePixels != nil || state.sharedFrames != nil { return true }
        if let mask = state.mask, isAnimating(mask) { return true }
        return state.sublayers.contains(where: isAnimating)
    }

    /// The texture placed by `toScreen`: as its bounding box when that
    /// keeps it upright, else turned about its center.
    private func drawTexture(of layer: CALayer, state: LayerState, shape: ShapeLayerState?, border: Bool, toScreen: CGAffineTransform,
                             alpha: CGFloat) {
        guard let texture = texture(of: layer, state: state, shape: shape, border: border) else { return }
        place(texture, state: state, toScreen: toScreen, alpha: alpha)
    }

    /// A static texture of premultiplied ARGB pixels, scaled linearly.
    private func makeTexture(width: Int, height: Int, pixels: UnsafeRawPointer, pitch: Int) -> SDLTexture? {
        guard let texture = try? SDLTexture(renderer: renderer, format: .argb8888, access: .static, width: width, height: height) else { return nil }
        try? texture.update(pixels: pixels, pitch: pitch)
        try? texture.setBlendMode([.alphaPremultiplied])
        try? texture.setScaleMode(.linear)
        return texture
    }

    private func place(_ texture: SDLTexture, state: LayerState, toScreen: CGAffineTransform, alpha: CGFloat) {
        let level = Float(alpha)
        try? texture.setAlphaModulation(level)
        try? texture.setColorModulation(red: level, green: level, blue: level)
        render(texture, bounds: state.bounds, toScreen: toScreen, flip: 0)
    }

    /// Draws `texture` into `bounds` taken to the screen by `toScreen`:
    /// scaled, mirrored or turned. `flip` flips the texture first
    /// (SDL_FLIP_VERTICAL 2 for rows bottom first).
    func render(_ texture: SDLTexture, bounds: CGRect, toScreen: CGAffineTransform, flip extra: Int32) {
        // What rounding leaves of a zero: a float CGFloat's quarter turn has
        // a cosine near 4e-8.
        let small: CGFloat = MemoryLayout<CGFloat>.size == 4 ? 1e-5 : 1e-9
        // Scaled only, perhaps mirrored: into the layer's box on the
        // display, flipped where a scale is negative (SDL_FLIP_HORIZONTAL
        // 1, SDL_FLIP_VERTICAL 2).
        if abs(toScreen.b) < small, abs(toScreen.c) < small {
            let target = pixels(toScreen.apply(bounds))
            let flip: Int32 = ((toScreen.a < 0 ? 1 : 0) | (toScreen.d < 0 ? 2 : 0)) ^ extra
            if flip == 0 {
                try? renderer.copy(texture, to: target)
            } else {
                try? renderer.copy(texture, to: target, angle: 0, flip: Self.flips(flip))
            }
            return
        }
        // A negative determinant mirrors: SDL_FLIP_HORIZONTAL, which SDL
        // does before it turns the texture. So the turn is the one that
        // takes the mirrored x axis, pointing left, to where the transform
        // takes the x axis.
        let mirrored = toScreen.a * toScreen.d - toScreen.b * toScreen.c < 0
        let degrees = (mirrored ? atan2(-toScreen.b, -toScreen.a) : atan2(toScreen.b, toScreen.a)) * 180 / .pi
        let flip: Int32 = (mirrored ? 1 : 0) ^ extra
        // A quarter turn: the layer's box on the display, with its sides
        // exchanged, turned about its center into that box.
        if abs(toScreen.a) < small, abs(toScreen.d) < small {
            let box = pixels(toScreen.apply(bounds))
            let target = SDLFRect(x: box.x + (box.width - box.height) / 2, y: box.y + (box.height - box.width) / 2, width: box.height, height: box.width)
            try? renderer.copy(texture, to: target, angle: Double(degrees), flip: Self.flips(flip))
            return
        }
        // Any other turn is placed as it falls, not on whole pixels.
        let center = toScreen.apply(CGPoint(x: bounds.midX, y: bounds.midY))
        let width = bounds.width * (toScreen.a * toScreen.a + toScreen.b * toScreen.b).squareRoot()
        let height = bounds.height * (toScreen.c * toScreen.c + toScreen.d * toScreen.d).squareRoot()
        let target = SDLFRect(x: Float((center.x - width / 2) * scale), y: Float((center.y - height / 2) * scale),
                              width: Float(width * scale), height: Float(height * scale))
        try? renderer.copy(texture, to: target, angle: Double(degrees), flip: Self.flips(flip))
    }

    /// SDL_FLIP_HORIZONTAL is 1 and SDL_FLIP_VERTICAL 2.
    private static func flips(_ flip: Int32) -> BitMaskOptionSet<SDLRenderer.Flip> {
        BitMaskOptionSet<SDLRenderer.Flip>(rawValue: UInt32(flip))
    }

    /// The imported buffers of layers whose GL frames are shared.
    var sharedTextures: [UnsafeMutableRawPointer: SharedTextures] = [:]

    /// The persistent streaming textures of layers showing GL frames, and
    /// the generation each last took.
    private var liveTextures: [UnsafeMutableRawPointer: (texture: SDLTexture, width: Int, height: Int, bgra: Bool, generation: Int, used: Bool)] = [:]

    /// A GL frame: its texture updated in place when the frame is new, and
    /// drawn flipped upright, as the rows are bottom first. A Metal
    /// drawable's, B, G, R, A rows top first, go up as they are.
    private func drawLive(_ live: LivePixels, of layer: CALayer, state: LayerState, toScreen: CGAffineTransform, alpha: CGFloat) {
        let key = layer.objcObject
        var entry = liveTextures[key]
        if let current = entry, current.width != live.width || current.height != live.height || current.bgra != live.bgra {
            entry = nil
        }
        if entry == nil {
            let format: SDLPixelFormat.Format = live.bgra ? .argb8888 : .abgr8888
            guard let texture = try? SDLTexture(renderer: renderer, format: format, access: .streaming,
                                                width: live.width, height: live.height) else { return }
            try? texture.setScaleMode(.linear)
            entry = (texture, live.width, live.height, live.bgra, live.generation &- 1, true)
        }
        guard var current = entry else { return }
        if current.generation != live.generation {
            try? current.texture.update(pixels: live.data, pitch: live.width * 4)
            FrameRate.glFrames += max(live.generation &- current.generation, 1)
            current.generation = live.generation
        }
        live.shown = live.generation
        current.used = true
        liveTextures[key] = current
        try? current.texture.setBlendMode(live.opaque && alpha >= 1 ? [] : [.alphaPremultiplied])
        let level = Float(alpha)
        try? current.texture.setAlphaModulation(level)
        try? current.texture.setColorModulation(red: level, green: level, blue: level)
        // SDL_FLIP_VERTICAL for rows bottom first.
        render(current.texture, bounds: state.bounds, toScreen: toScreen, flip: live.topFirst ? 0 : 2)
    }

    /// The layer's texture, drawn again when what it shows has changed.
    private func texture(of layer: CALayer, state: LayerState, shape: ShapeLayerState?, border: Bool) -> SDLTexture? {
        let key = Key(layer: layer.objcObject, border: border)
        let model = layer.state
        var signature = Signature(size: state.bounds.size, cornerRadius: state.cornerRadius, maskedCorners: state.maskedCorners,
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
        if let entry = textures[key], entry.signature == signature {
            textures[key]?.used = true
            return entry.texture
        }
        textures[key] = nil
        let width = Int((state.bounds.width * scale).rounded(.up)), height = Int((state.bounds.height * scale).rounded(.up))
        // A layer showing only what it drew, at the display's scale: its
        // backing's pixels are the texture's, without drawing them again.
        if !border, let texture = backingTexture(of: layer, state: state, shape: shape, width: width, height: height) {
            textures[key] = Entry(texture: texture, signature: signature, used: true)
            return texture
        }
        guard width > 0, height > 0, let context = CG.makeContext(size: state.bounds.size, scale: scale, opaque: false) else {
            return nil
        }
        defer { CG.release(context) }
        // The texture is whole pixels and the layer may not be: what is
        // drawn is stretched to fill it, so that its last row and column
        // are covered, not left partly clear at the layer's edge.
        CG.scaleCTM(context, CGFloat(width) / (state.bounds.width * scale), CGFloat(height) / (state.bounds.height * scale))
        CG.translateCTM(context, -state.bounds.minX, -state.bounds.minY)
        if border {
            CALayer.drawBorder(of: state, in: context)
        } else {
            CALayer.drawBackground(of: state, in: context)
            CG.saveGState(context)
            if state.masksToBounds { CALayer.clip(to: state, in: context) }
            CALayer.drawContent(of: layer, state: state, shape: shape, in: context)
            CG.restoreGState(context)
        }
        guard let data = CG.bitmapContextGetData(context),
              let texture = makeTexture(width: width, height: height, pixels: data, pitch: width * 4) else { return nil }
        textures[key] = Entry(texture: texture, signature: signature, used: true)
        return texture
    }
}

extension Compositor {
    /// The texture of a layer with nothing but its backing to show, made
    /// from the backing's pixels when they are the texture's size.
    fileprivate func backingTexture(of layer: CALayer, state: LayerState, shape: ShapeLayerState?, width: Int, height: Int) -> SDLTexture? {
        guard shape == nil, state.contents == nil, state.livePixels == nil, state.sharedFrames == nil, state.backgroundColor == nil,
              state.cornerRadius == 0, width > 0, height > 0 else { return nil }
        CALayer.displayIfNeeded(layer)
        let model = layer.state
        guard let backing = model.backing, model.backingSize == state.bounds.size,
              CG.imageGetWidth(backing) == width, CG.imageGetHeight(backing) == height else { return nil }
        return CG.withPixels(of: backing) { pixels, bytesPerRow -> SDLTexture? in
            guard bytesPerRow >= width * 4 else { return nil }
            return makeTexture(width: width, height: height, pixels: pixels, pitch: bytesPerRow)
        }
    }
}

/// With PERRY_UIKIT_FPS set, the frames composited each second, and the new
/// OpenGL ES frames among them (the app's own rate), drawn in the corner
/// and written to standard error.
enum FrameRate {
    nonisolated(unsafe) static let on = getenv("PERRY_UIKIT_FPS") != nil
    nonisolated(unsafe) static var glFrames = 0
    nonisolated(unsafe) private static var frames = 0
    nonisolated(unsafe) private static var since = now()
    nonisolated(unsafe) private static var text = "fps -"

    private static func now() -> Double {
        var time = timespec()
        clock_gettime(CLOCK_MONOTONIC, &time)
        return Double(time.tv_sec) + Double(time.tv_nsec) / 1e9
    }

    nonisolated(unsafe) private static var lastFrame = 0.0

    static func frame(renderer: SDLRenderer) {
        frames += 1
        let time = now()
        if lastFrame > 0, time - lastFrame > 0.15 {
            let line = "perry: UIKit: hitch \(Int((time - lastFrame) * 1000)) ms between frames at \(Int(time * 1000) % 1_000_000)\n"
            _ = line.withCString { write(2, $0, strlen($0)) }
        }
        lastFrame = time
        if time - since >= 1 {
            let elapsed = time - since
            text = "screen \(Int((Double(frames) / elapsed).rounded())) fps  GL \(Int((Double(glFrames) / elapsed).rounded())) fps"
            let line = "perry: UIKit: \(text)\n"
            _ = line.withCString { write(2, $0, strlen($0)) }
            (frames, glFrames, since) = (0, 0, time)
        }
        try? renderer.setClipRect(nil)
        try? renderer.setScale(x: 2, y: 2)
        try? renderer.setDrawBlendMode([.alpha])
        try? renderer.setDrawColorFloat(red: 0, green: 0, blue: 0, alpha: 0.6)
        try? renderer.fill(SDLFRect(x: 4, y: 4, width: Float(text.utf8.count * 8 + 8), height: 16))
        try? renderer.setDrawColorFloat(red: 1, green: 1, blue: 0.3, alpha: 1)
        try? renderer.debugText(text, x: 8, y: 8)
        try? renderer.setScale(x: 1, y: 1)
    }
}

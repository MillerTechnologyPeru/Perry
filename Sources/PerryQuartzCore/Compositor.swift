import CPerryGeometry
import Glibc
import PerryObjCInterop

// Compositing layer trees on the GPU, for UIKit's live view, through the
// SDL3 renderer UIKit's window draws with. Each layer's own content (its
// background in the shape of its corners, what it displayed, its contents
// and a shape layer's path) and its border are textures, drawn with
// CoreGraphics only when they change; each frame places them as the layers
// present, by their geometry, opacity and clipping. Rotated layers turn
// about their centers. Plain rectangular backgrounds are filled without a
// texture. The GPU clips to rectangles, so a layer that clips to rounded
// corners, or has a mask, is drawn with its sublayers as one texture,
// through CoreGraphics, each frame.

/// The SDL3 functions compositing calls, from the library UIKit loaded.
enum SDL {
    typealias Pointer = UnsafeMutableRawPointer

    struct FRect { var x, y, w, h: Float }
    struct Rect { var x, y, w, h: Int32 }

    nonisolated(unsafe) static var createTexture: (@convention(c) (Pointer?, UInt32, Int32, Int32, Int32) -> Pointer?)!
    nonisolated(unsafe) static var updateTexture: (@convention(c) (Pointer?, UnsafeRawPointer?, UnsafeRawPointer?, Int32) -> Bool)!
    nonisolated(unsafe) static var setTextureBlendMode: (@convention(c) (Pointer?, UInt32) -> Bool)!
    nonisolated(unsafe) static var setTextureAlphaMod: (@convention(c) (Pointer?, Float) -> Bool)!
    nonisolated(unsafe) static var setTextureColorMod: (@convention(c) (Pointer?, Float, Float, Float) -> Bool)!
    nonisolated(unsafe) static var setTextureScaleMode: (@convention(c) (Pointer?, Int32) -> Bool)!
    nonisolated(unsafe) static var destroyTexture: (@convention(c) (Pointer?) -> Void)!
    nonisolated(unsafe) static var renderTexture: (@convention(c) (Pointer?, Pointer?, UnsafeRawPointer?, UnsafeRawPointer?) -> Bool)!
    nonisolated(unsafe) static var renderTextureRotated: (@convention(c) (Pointer?, Pointer?, UnsafeRawPointer?, UnsafeRawPointer?, Double,
                                                                          UnsafeRawPointer?, Int32) -> Bool)!
    nonisolated(unsafe) static var setDrawColor: (@convention(c) (Pointer?, Float, Float, Float, Float) -> Bool)!
    nonisolated(unsafe) static var setDrawBlendMode: (@convention(c) (Pointer?, UInt32) -> Bool)!
    nonisolated(unsafe) static var fillRect: (@convention(c) (Pointer?, UnsafeRawPointer?) -> Bool)!
    nonisolated(unsafe) static var clear: (@convention(c) (Pointer?) -> Bool)!
    nonisolated(unsafe) static var present: (@convention(c) (Pointer?) -> Bool)!
    nonisolated(unsafe) static var setClipRect: (@convention(c) (Pointer?, UnsafeRawPointer?) -> Bool)!

    static let pixelFormatARGB8888: UInt32 = 0x1636_2004
    static let blendBlend: UInt32 = 0x1
    static let blendPremultiplied: UInt32 = 0x10

    nonisolated(unsafe) private static var loaded: Bool?

    static func loadOnce() -> Bool {
        if let loaded { return loaded }
        let result = load()
        loaded = result
        return result
    }

    private static func load() -> Bool {
        guard let library = dlopen("libSDL3.so.0", RTLD_NOW) else { return false }
        var complete = true
        func bind<T>(_ name: String) -> T? {
            guard let symbol = dlsym(library, name) else {
                complete = false
                return nil
            }
            return unsafeBitCast(symbol, to: T.self)
        }
        createTexture = bind("SDL_CreateTexture")
        updateTexture = bind("SDL_UpdateTexture")
        setTextureBlendMode = bind("SDL_SetTextureBlendMode")
        setTextureAlphaMod = bind("SDL_SetTextureAlphaModFloat")
        setTextureColorMod = bind("SDL_SetTextureColorModFloat")
        setTextureScaleMode = bind("SDL_SetTextureScaleMode")
        destroyTexture = bind("SDL_DestroyTexture")
        renderTexture = bind("SDL_RenderTexture")
        renderTextureRotated = bind("SDL_RenderTextureRotated")
        setDrawColor = bind("SDL_SetRenderDrawColorFloat")
        setDrawBlendMode = bind("SDL_SetRenderDrawBlendMode")
        fillRect = bind("SDL_RenderFillRect")
        clear = bind("SDL_RenderClear")
        present = bind("SDL_RenderPresent")
        setClipRect = bind("SDL_SetRenderClipRect")
        return complete
    }
}

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
/// `scale` pixels a point, and shows the frame; false without SDL.
@c(_PerryCAComposite)
public func PerryCAComposite(_ renderer: UnsafeMutableRawPointer?, _ scale: Double, _ roots: UnsafePointer<UnsafeMutableRawPointer?>?,
                             _ count: Int) -> Bool {
    guard let renderer, SDL.loadOnce() else { return false }
    let compositor = Compositor.shared(renderer, scale: scale)
    let layers = (0..<count).compactMap { roots?[$0] }.map(CALayer.wrap)
    compositor.draw(layers)
    return true
}

final class Compositor {
    nonisolated(unsafe) private static var current: Compositor?

    static func shared(_ renderer: SDL.Pointer, scale: CGFloat) -> Compositor {
        if let current, current.renderer == renderer, current.scale == scale { return current }
        let compositor = Compositor(renderer: renderer, scale: scale)
        current = compositor
        return compositor
    }

    let renderer: SDL.Pointer
    let scale: CGFloat

    /// A layer's texture, of its content or its border, and what it shows.
    private struct Key: Hashable {
        let layer: UnsafeMutableRawPointer
        let border: Bool
    }

    private struct Entry {
        let texture: SDL.Pointer
        let signature: String
        var used: Bool
    }

    private var textures: [Key: Entry] = [:]

    init(renderer: SDL.Pointer, scale: CGFloat) {
        (self.renderer, self.scale) = (renderer, scale)
    }

    /// Displays the visible layers that need it.
    static func display(_ layer: CALayer) {
        let state = layer.state
        guard !state.hidden, state.opacity > 0 else { return }
        CALayer.displayIfNeeded(layer)
        for sublayer in state.sublayers { display(sublayer) }
    }

    /// Composites the roots, each placed in the screen by its own transform.
    func draw(_ roots: [CALayer]) {
        for key in textures.keys { textures[key]?.used = false }
        _ = SDL.setDrawColor(renderer, 0, 0, 0, 1)
        _ = SDL.setClipRect(renderer, nil)
        _ = SDL.clear(renderer)
        for root in roots {
            let (state, _) = Presentation.presented(root)
            composite(root, toScreen: state.toSuperlayer(within: nil), alpha: 1, clip: nil)
        }
        for (key, entry) in textures where !entry.used {
            SDL.destroyTexture(entry.texture)
            textures[key] = nil
        }
        _ = SDL.present(renderer)
    }

    /// A layer, then its sublayers, then its border; `toScreen` takes the
    /// layer's coordinates to the screen's, in points.
    private func composite(_ layer: CALayer, toScreen: CGAffineTransform, alpha: CGFloat, clip: CGRect?) {
        let (state, shape) = Presentation.presented(layer)
        layer.state.rendered = true
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
        if textured {
            drawTexture(of: layer, state: state, shape: shape, border: false, toScreen: toScreen, alpha: alpha)
        } else if let background = state.backgroundColor {
            fill(frame, with: background, alpha: alpha)
        }
        let inner = state.masksToBounds ? (clip.map { $0.intersection(frame) } ?? frame) : clip
        if inner.map({ $0.width > 0 && $0.height > 0 }) ?? true {
            for sublayer in CALayer.orderedSublayers(of: state) {
                let presented = Presentation.state(of: sublayer)
                composite(sublayer, toScreen: presented.toSuperlayer(within: state).concatenating(toScreen), alpha: alpha, clip: inner)
            }
        }
        if state.borderWidth > 0, state.borderColor != nil {
            setClip(clip)
            drawTexture(of: layer, state: state, shape: nil, border: true, toScreen: toScreen, alpha: alpha)
        }
    }

    private func setClip(_ clip: CGRect?) {
        guard let clip else {
            _ = SDL.setClipRect(renderer, nil)
            return
        }
        var rect = SDL.Rect(x: Int32((clip.minX * scale).rounded(.down)), y: Int32((clip.minY * scale).rounded(.down)),
                            w: Int32(max((clip.width * scale).rounded(.up), 0)), h: Int32(max((clip.height * scale).rounded(.up), 0)))
        _ = SDL.setClipRect(renderer, &rect)
    }

    private func pixels(_ rect: CGRect) -> SDL.FRect {
        SDL.FRect(x: Float(rect.minX * scale), y: Float(rect.minY * scale), w: Float(rect.width * scale), h: Float(rect.height * scale))
    }

    private func fill(_ rect: CGRect, with color: CGRef, alpha: CGFloat) {
        guard let components = CG.colorGetComponents(color) else { return }
        let gray = CG.colorGetNumberOfComponents(color) == 2
        let (r, g, b, a) = gray ? (components[0], components[0], components[0], components[1])
            : (components[0], components[1], components[2], components[3])
        _ = SDL.setDrawBlendMode(renderer, SDL.blendBlend)
        _ = SDL.setDrawColor(renderer, Float(r), Float(g), Float(b), Float(a * alpha))
        var target = pixels(rect)
        _ = SDL.fillRect(renderer, &target)
    }

    private func drawFlattened(_ layer: CALayer, state: LayerState, shape: ShapeLayerState?, toScreen: CGAffineTransform, alpha: CGFloat) {
        let key = Key(layer: layer.objcObject, border: false)
        if let old = textures.removeValue(forKey: key) { SDL.destroyTexture(old.texture) }
        let width = Int32((state.bounds.width * scale).rounded(.up)), height = Int32((state.bounds.height * scale).rounded(.up))
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
              let texture = SDL.createTexture(renderer, SDL.pixelFormatARGB8888, 0, width, height) else { return }
        _ = SDL.updateTexture(texture, nil, data, width * 4)
        _ = SDL.setTextureBlendMode(texture, SDL.blendPremultiplied)
        _ = SDL.setTextureScaleMode(texture, 1)
        textures[key] = Entry(texture: texture, signature: "", used: true)
        place(texture, state: state, toScreen: toScreen, alpha: alpha)
    }

    /// The texture placed by `toScreen`: as its bounding box when that
    /// keeps it upright, else turned about its center.
    private func drawTexture(of layer: CALayer, state: LayerState, shape: ShapeLayerState?, border: Bool, toScreen: CGAffineTransform,
                             alpha: CGFloat) {
        guard let texture = texture(of: layer, state: state, shape: shape, border: border) else { return }
        place(texture, state: state, toScreen: toScreen, alpha: alpha)
    }

    private func place(_ texture: SDL.Pointer, state: LayerState, toScreen: CGAffineTransform, alpha: CGFloat) {
        let level = Float(alpha)
        _ = SDL.setTextureAlphaMod(texture, level)
        _ = SDL.setTextureColorMod(texture, level, level, level)
        if toScreen.isAxisAligned, toScreen.a >= 0, toScreen.d >= 0 {
            var target = pixels(toScreen.apply(state.bounds))
            _ = SDL.renderTexture(renderer, texture, nil, &target)
            return
        }
        let center = toScreen.apply(CGPoint(x: state.bounds.midX, y: state.bounds.midY))
        let width = state.bounds.width * (toScreen.a * toScreen.a + toScreen.b * toScreen.b).squareRoot()
        let height = state.bounds.height * (toScreen.c * toScreen.c + toScreen.d * toScreen.d).squareRoot()
        var target = pixels(CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height))
        let degrees = atan2(toScreen.b, toScreen.a) * 180 / .pi
        // A negative determinant mirrors: SDL_FLIP_HORIZONTAL.
        let flip: Int32 = toScreen.a * toScreen.d - toScreen.b * toScreen.c < 0 ? 1 : 0
        _ = SDL.renderTextureRotated(renderer, texture, nil, &target, degrees, nil, flip)
    }

    /// The layer's texture, drawn again when what it shows has changed.
    private func texture(of layer: CALayer, state: LayerState, shape: ShapeLayerState?, border: Bool) -> SDL.Pointer? {
        let key = Key(layer: layer.objcObject, border: border)
        let model = layer.state
        var signature = border
            ? "\(state.bounds.size) \(state.borderWidth) \(String(describing: state.borderColor)) \(state.cornerRadius) \(state.maskedCorners)"
            : "\(state.bounds.size) \(String(describing: state.backgroundColor)) \(state.cornerRadius) \(state.maskedCorners) "
                + "\(String(describing: model.backing)) \(model.backingSize) \(String(describing: state.contents?.objcObject)) "
                + "\(state.contentsGravity) \(state.contentsScale)"
        if let shape, !border {
            signature += " \(String(describing: shape.path)) \(String(describing: shape.fillColor)) \(String(describing: shape.strokeColor)) "
                + "\(shape.lineWidth) \(shape.strokeStart) \(shape.strokeEnd) \(shape.lineCap) \(shape.lineJoin) \(shape.lineDashPhase)"
        }
        if let entry = textures[key], entry.signature == signature {
            textures[key]?.used = true
            return entry.texture
        }
        if let old = textures.removeValue(forKey: key) { SDL.destroyTexture(old.texture) }
        let width = Int32((state.bounds.width * scale).rounded(.up)), height = Int32((state.bounds.height * scale).rounded(.up))
        guard width > 0, height > 0, let context = CG.makeContext(size: state.bounds.size, scale: scale, opaque: false) else {
            return nil
        }
        defer { CG.release(context) }
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
              let texture = SDL.createTexture(renderer, SDL.pixelFormatARGB8888, 0, width, height) else { return nil }
        _ = SDL.updateTexture(texture, nil, data, width * 4)
        _ = SDL.setTextureBlendMode(texture, SDL.blendPremultiplied)
        _ = SDL.setTextureScaleMode(texture, 1)
        textures[key] = Entry(texture: texture, signature: signature, used: true)
        return texture
    }
}

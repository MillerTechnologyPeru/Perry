import CPerryGeometry
import Glibc
import PerryObjCInterop

// The live view on the GPU, through SDL3's renderer, as Core Animation
// composites: each layer's own content (its background in the shape of its
// corners, what it displayed, its contents) and its border are textures,
// drawn with CoreGraphics only when they change; each frame places them by
// the layers' geometry, opacity and clipping. Plain rectangular
// backgrounds are filled without a texture. Clipping is to rectangles, so
// a layer that masks to rounded corners clips its sublayers square.
// libSDL3 is loaded at run time; without it the live view draws in
// software.

/// SDL3's C API, as the compositor calls it.
enum SDL {
    typealias Pointer = UnsafeMutableRawPointer

    struct FRect { var x, y, w, h: Float }
    struct Rect { var x, y, w, h: Int32 }

    nonisolated(unsafe) static var initialize: (@convention(c) (UInt32) -> Bool)!
    nonisolated(unsafe) static var createWindow: (@convention(c) (UnsafePointer<CChar>?, Int32, Int32, UInt64) -> Pointer?)!
    nonisolated(unsafe) static var createRenderer: (@convention(c) (Pointer?, UnsafePointer<CChar>?) -> Pointer?)!
    nonisolated(unsafe) static var rendererName: (@convention(c) (Pointer?) -> UnsafePointer<CChar>?)!
    nonisolated(unsafe) static var createTexture: (@convention(c) (Pointer?, UInt32, Int32, Int32, Int32) -> Pointer?)!
    nonisolated(unsafe) static var updateTexture: (@convention(c) (Pointer?, UnsafeRawPointer?, UnsafeRawPointer?, Int32) -> Bool)!
    nonisolated(unsafe) static var setTextureBlendMode: (@convention(c) (Pointer?, UInt32) -> Bool)!
    nonisolated(unsafe) static var setTextureAlphaMod: (@convention(c) (Pointer?, Float) -> Bool)!
    nonisolated(unsafe) static var setTextureColorMod: (@convention(c) (Pointer?, Float, Float, Float) -> Bool)!
    nonisolated(unsafe) static var setTextureScaleMode: (@convention(c) (Pointer?, Int32) -> Bool)!
    nonisolated(unsafe) static var destroyTexture: (@convention(c) (Pointer?) -> Void)!
    nonisolated(unsafe) static var renderTexture: (@convention(c) (Pointer?, Pointer?, UnsafeRawPointer?, UnsafeRawPointer?) -> Bool)!
    nonisolated(unsafe) static var setDrawColor: (@convention(c) (Pointer?, Float, Float, Float, Float) -> Bool)!
    nonisolated(unsafe) static var setDrawBlendMode: (@convention(c) (Pointer?, UInt32) -> Bool)!
    nonisolated(unsafe) static var fillRect: (@convention(c) (Pointer?, UnsafeRawPointer?) -> Bool)!
    nonisolated(unsafe) static var clear: (@convention(c) (Pointer?) -> Bool)!
    nonisolated(unsafe) static var present: (@convention(c) (Pointer?) -> Bool)!
    nonisolated(unsafe) static var setClipRect: (@convention(c) (Pointer?, UnsafeRawPointer?) -> Bool)!
    nonisolated(unsafe) static var pollEvent: (@convention(c) (Pointer?) -> Bool)!
    nonisolated(unsafe) static var error: (@convention(c) () -> UnsafePointer<CChar>?)!
    nonisolated(unsafe) static var setWindowMinimumSize: (@convention(c) (Pointer?, Int32, Int32) -> Bool)?
    nonisolated(unsafe) static var primaryDisplay: (@convention(c) () -> UInt32)?
    nonisolated(unsafe) static var displayContentScale: (@convention(c) (UInt32) -> Float)?
    nonisolated(unsafe) static var startTextInput: (@convention(c) (Pointer?) -> Bool)?
    nonisolated(unsafe) static var stopTextInput: (@convention(c) (Pointer?) -> Bool)?

    static let pixelFormatARGB8888: UInt32 = 0x1636_2004
    static let blendBlend: UInt32 = 0x1
    static let blendPremultiplied: UInt32 = 0x10

    static var lastError: String { error().map { String(cString: $0) } ?? "" }

    nonisolated(unsafe) private static var loaded: Bool?

    /// Before SDL starts: its renderer makes its GL contexts through EGL,
    /// as EAGLContext does, so the two can take turns being current on one
    /// thread, and renders with OpenGL ES 2.
    static func prepareEnvironment() {
        setenv("SDL_VIDEO_FORCE_EGL", "1", 0)
        setenv("SDL_RENDER_DRIVER", "opengles2", 0)
    }

    /// Binds SDL3 once; false without it.
    static func loadOnce() -> Bool {
        if let loaded { return loaded }
        let result = load()
        loaded = result
        return result
    }

    /// The desktop's scaling of the primary display (2 on a HiDPI desktop),
    /// starting SDL's video for the question; nil without SDL or a display.
    static func nativeScale() -> CGFloat? {
        prepareEnvironment()
        guard loadOnce(), initialize(0x20), let primaryDisplay, let displayContentScale else { return nil }
        let display = primaryDisplay()
        guard display != 0 else { return nil }
        let scale = displayContentScale(display)
        return scale > 0 ? CGFloat(scale) : nil
    }

    /// Binds SDL3's functions; false without libSDL3.
    static func load() -> Bool {
        guard let library = dlopen("libSDL3.so.0", RTLD_NOW) else { return false }
        var complete = true
        func bind<T>(_ name: String) -> T? {
            guard let symbol = dlsym(library, name) else {
                complete = false
                return nil
            }
            return unsafeBitCast(symbol, to: T.self)
        }
        initialize = bind("SDL_Init")
        createWindow = bind("SDL_CreateWindow")
        createRenderer = bind("SDL_CreateRenderer")
        rendererName = bind("SDL_GetRendererName")
        createTexture = bind("SDL_CreateTexture")
        updateTexture = bind("SDL_UpdateTexture")
        setTextureBlendMode = bind("SDL_SetTextureBlendMode")
        setTextureAlphaMod = bind("SDL_SetTextureAlphaModFloat")
        setTextureColorMod = bind("SDL_SetTextureColorModFloat")
        setTextureScaleMode = bind("SDL_SetTextureScaleMode")
        destroyTexture = bind("SDL_DestroyTexture")
        renderTexture = bind("SDL_RenderTexture")
        setDrawColor = bind("SDL_SetRenderDrawColorFloat")
        setDrawBlendMode = bind("SDL_SetRenderDrawBlendMode")
        fillRect = bind("SDL_RenderFillRect")
        clear = bind("SDL_RenderClear")
        present = bind("SDL_RenderPresent")
        setClipRect = bind("SDL_SetRenderClipRect")
        pollEvent = bind("SDL_PollEvent")
        error = bind("SDL_GetError")
        setWindowMinimumSize = dlsym(library, "SDL_SetWindowMinimumSize")
            .map { unsafeBitCast($0, to: (@convention(c) (Pointer?, Int32, Int32) -> Bool).self) }
        primaryDisplay = dlsym(library, "SDL_GetPrimaryDisplay").map { unsafeBitCast($0, to: (@convention(c) () -> UInt32).self) }
        displayContentScale = dlsym(library, "SDL_GetDisplayContentScale").map { unsafeBitCast($0, to: (@convention(c) (UInt32) -> Float).self) }
        startTextInput = dlsym(library, "SDL_StartTextInput").map { unsafeBitCast($0, to: (@convention(c) (Pointer?) -> Bool).self) }
        stopTextInput = dlsym(library, "SDL_StopTextInput").map { unsafeBitCast($0, to: (@convention(c) (Pointer?) -> Bool).self) }
        return complete
    }
}

final class Compositor {
    let window: SDL.Pointer
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
    /// SDL's renderer's EGL context, which an app's EAGLContext displaces
    /// when it draws on the same thread.
    private var rendererContext: EAGLContexts.Saved?

    /// A window `size` points across at `scale` pixels a point, on the GPU
    /// when SDL has a renderer for it. A resizable app's window can be
    /// resized, and its screen takes the window's size.
    init?(title: String, size: CGSize, scale: CGFloat) {
        guard SDL.initialize(0x20) else {
            uikitWarning("SDL could not start its video: \(SDL.lastError)")
            return nil
        }
        let width = Int32((size.width * scale).rounded()), height = Int32((size.height * scale).rounded())
        // SDL_WINDOW_RESIZABLE.
        guard let window = title.withCString({ SDL.createWindow($0, width, height, Screen.isResizable ? 0x20 : 0) }),
              let renderer = SDL.createRenderer(window, nil) else {
            uikitWarning("SDL could not make a window: \(SDL.lastError)")
            return nil
        }
        // The smallest an iPad app's window gets.
        if Screen.isResizable { _ = SDL.setWindowMinimumSize?(window, Int32(320 * scale), Int32(320 * scale)) }
        (self.window, self.renderer, self.scale) = (window, renderer, scale)
        rendererContext = EAGLContexts.save()
        let name = SDL.rendererName(renderer).map { String(cString: $0) } ?? "unknown"
        uikitWarning("live view composited by SDL's \(name) renderer")
    }

    /// Typed text arrives while text input is on, as for a keyboard on screen.
    func setTextInput(_ on: Bool) {
        _ = on ? SDL.startTextInput?(window) : SDL.stopTextInput?(window)
    }

    /// Mouse buttons, motion and the wheel as touches, and the keyboard's
    /// text and editing keys; true when the window was closed.
    func handleEvents() -> Bool {
        var event = [UInt64](repeating: 0, count: 16)
        var closed = false
        while event.withUnsafeMutableBytes({ SDL.pollEvent($0.baseAddress) }) {
            event.withUnsafeBytes { raw in
                let type = raw.load(fromByteOffset: 0, as: UInt32.self)
                func point() -> CGPoint {
                    CGPoint(x: CGFloat(raw.load(fromByteOffset: 28, as: Float.self)) / scale,
                            y: CGFloat(raw.load(fromByteOffset: 32, as: Float.self)) / scale)
                }
                switch type {
                case 0x100: // quit
                    closed = true
                case 0x400: // mouse motion
                    Touches.move(to: point())
                case 0x401, 0x402: // mouse button down and up
                    guard raw.load(fromByteOffset: 24, as: UInt8.self) == 1 else { break }
                    if type == 0x401 { Touches.down(at: point()) } else { Touches.up(at: point()) }
                    Display.markDirty()
                case 0x206: // window resized: its size at 20 and 24
                    let size = CGSize(width: CGFloat(raw.load(fromByteOffset: 20, as: Int32.self)) / scale,
                                      height: CGFloat(raw.load(fromByteOffset: 24, as: Int32.self)) / scale)
                    Screen.resize(to: size)
                case 0x300: // key down: SDL_Keycode at 28
                    switch raw.load(fromByteOffset: 28, as: UInt32.self) {
                    case 0x08: Keyboard.deleteBackward()
                    case 0x0D, 0x4000_0058: Keyboard.returnKey()   // return, keypad enter
                    case 0x1B: Keyboard.escape()
                    default: break
                    }
                case 0x303: // text input: UTF-8 at 24
                    if let text = raw.load(fromByteOffset: 24, as: UnsafePointer<CChar>?.self) {
                        Keyboard.insert(String(cString: text))
                    }
                case 0x403: // wheel: positive y scrolls up, unless flipped
                    let flipped = raw.load(fromByteOffset: 32, as: UInt32.self) == 1
                    let y = CGFloat(raw.load(fromByteOffset: 28, as: Float.self)) * (flipped ? -1 : 1)
                    let at = CGPoint(x: CGFloat(raw.load(fromByteOffset: 36, as: Float.self)) / scale,
                                     y: CGFloat(raw.load(fromByteOffset: 40, as: Float.self)) / scale)
                    Touches.wheel(at: at, by: -y * 40)
                    Display.markDirty()
                default:
                    Display.markDirty()
                }
            }
        }
        return closed
    }

    /// Composites the windows, back to front, and shows the frame.
    func draw(_ windows: [UIWindow]) {
        // Layers display first, as an app's OpenGL ES drawing for a layer
        // makes its own context current; then the renderer's is again.
        for window in windows { display(window.state.layer) }
        rendererContext?.restore()
        for key in textures.keys { textures[key]?.used = false }
        _ = SDL.setDrawColor(renderer, 0, 0, 0, 1)
        _ = SDL.setClipRect(renderer, nil)
        _ = SDL.clear(renderer)
        for window in windows {
            composite(window.state.layer, toScreen: window.state.geometry.toSuperlayer, alpha: 1, clip: nil)
        }
        for (key, entry) in textures where !entry.used {
            SDL.destroyTexture(entry.texture)
            textures[key] = nil
        }
        _ = SDL.present(renderer)
        // The renderer's context was current while it drew; the app's is
        // again.
        EAGLContexts.restore()
    }

    /// Displays the visible layers that need it.
    private func display(_ layer: CALayer) {
        let state = layer.state
        guard !state.hidden, state.opacity > 0 else { return }
        CALayer.displayIfNeeded(layer)
        for sublayer in state.sublayers { display(sublayer) }
    }

    /// A layer, then its sublayers, then its border; `toScreen` takes the
    /// layer's coordinates to the screen's, in points.
    private func composite(_ layer: CALayer, toScreen: CGAffineTransform, alpha: CGFloat, clip: CGRect?) {
        let state = layer.state
        guard !state.hidden, state.opacity > 0 else { return }
        let alpha = alpha * CGFloat(state.opacity)
        let frame = toScreen.apply(state.bounds)
        setClip(clip)
        let textured = state.backing != nil || state.contents != nil || (state.cornerRadius > 0 && state.backgroundColor != nil)
        if textured {
            drawTexture(of: layer, border: false, at: frame, alpha: alpha)
        } else if let background = state.backgroundColor {
            fill(frame, with: background, alpha: alpha)
        }
        let inner = state.masksToBounds ? (clip.map { $0.intersection(frame) } ?? frame) : clip
        if inner.map({ $0.width > 0 && $0.height > 0 }) ?? true {
            for sublayer in CALayer.orderedSublayers(of: state) {
                composite(sublayer, toScreen: sublayer.state.toSuperlayer.concatenating(toScreen), alpha: alpha, clip: inner)
            }
        }
        if state.borderWidth > 0, state.borderColor != nil {
            setClip(clip)
            drawTexture(of: layer, border: true, at: frame, alpha: alpha)
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

    private func drawTexture(of layer: CALayer, border: Bool, at frame: CGRect, alpha: CGFloat) {
        guard let texture = texture(of: layer, border: border) else { return }
        let level = Float(alpha)
        _ = SDL.setTextureAlphaMod(texture, level)
        _ = SDL.setTextureColorMod(texture, level, level, level)
        var target = pixels(frame)
        _ = SDL.renderTexture(renderer, texture, nil, &target)
    }

    /// The layer's texture, drawn again when what it shows has changed.
    private func texture(of layer: CALayer, border: Bool) -> SDL.Pointer? {
        let state = layer.state
        let key = Key(layer: layer.objcObject, border: border)
        let signature = border
            ? "\(state.bounds.size) \(state.borderWidth) \(String(describing: state.borderColor)) \(state.cornerRadius) \(state.maskedCorners)"
            : "\(state.bounds.size) \(String(describing: state.backgroundColor)) \(state.cornerRadius) \(state.maskedCorners) "
                + "\(String(describing: state.backing)) \(state.backingSize) \(String(describing: state.contents?.objcObject)) "
                + "\(state.contentsGravity) \(state.contentsScale)"
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
            CALayer.drawBackground(of: layer, in: context)
            CG.saveGState(context)
            if state.masksToBounds { CALayer.clip(to: state, in: context) }
            CALayer.drawContent(of: layer, in: context)
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

extension CGRect {
    func intersection(_ other: CGRect) -> CGRect {
        let x = max(minX, other.minX), y = max(minY, other.minY)
        return CGRect(x: x, y: y, width: max(min(maxX, other.maxX) - x, 0), height: max(min(maxY, other.maxY) - y, 0))
    }
}

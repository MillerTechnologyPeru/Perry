import CPerryGeometry
import Glibc
import PerryObjCInterop
import SDL3Swift

// Compositing layer trees on the GPU, for UIKit's live view, through
// Cacao's engine (DisplayList.swift), with the SDL3 renderer UIKit's
// window draws with.

/// Displays the visible layers in the trees that need it, as an app's
/// drawing for them happens before compositing.
@c(_PerryCADisplayLayers)
public func PerryCADisplayLayers(_ roots: UnsafePointer<UnsafeMutableRawPointer?>?, _ count: Int) {
    guard let roots else { return }
    for index in 0..<count {
        guard let root = roots[index] else { continue }
        // Layers marked for layout are laid out first, those with no view
        // among them, as a Core Animation commit does.
        CALayer.wrap(root).layoutIfNeeded()
        Compositor.display(CALayer.wrap(root))
    }
}

/// Composites the layer trees, back to front, through Cacao's engine with
/// the renderer, at `scale` pixels a point, and shows the frame; false
/// without a renderer.
@c(_PerryCAComposite)
public func PerryCAComposite(_ renderer: UnsafeMutableRawPointer?, _ scale: Double, _ roots: UnsafePointer<UnsafeMutableRawPointer?>?,
                             _ count: Int) -> Bool {
    guard let renderer else { return false }
    let sdl = Compositor.renderer(renderer)
    guard let output = sdl.outputSize else { return false }
    let layers = (0..<count).compactMap { roots?[$0] }.map(CALayer.wrap)
    let size = CGSize(width: CGFloat(output.width) / CGFloat(scale), height: CGFloat(output.height) / CGFloat(scale))
    DisplayListCompositor.shared(renderer, scale: CGFloat(scale)).draw(layers, size: size)
    Compositor.finishFrame(sdl)
    return true
}

/// What compositing needs besides the engine: which layers to display,
/// the display's turn, and the frame rate, dump and present after it.
enum Compositor {
    nonisolated(unsafe) private static var current: SDLRenderer?

    /// SDL3Swift's renderer over UIKit's window's, which it doesn't own.
    static func renderer(_ pointer: UnsafeMutableRawPointer) -> SDLRenderer {
        if let current, current.unsafePointer == OpaquePointer(pointer) { return current }
        let renderer = SDLRenderer(unownedPointer: OpaquePointer(pointer))
        current = renderer
        return renderer
    }

    /// Displays the visible layers that need it.
    static func display(_ layer: CALayer) {
        let state = layer.state
        guard !state.hidden, state.opacity > 0 else { return }
        CALayer.displayIfNeeded(layer)
        for sublayer in state.sublayers { display(sublayer) }
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

    /// The frame rate over the frame, the frame dumped when that is due,
    /// and the frame shown.
    static func finishFrame(_ renderer: SDLRenderer) {
        if FrameRate.on { FrameRate.frame(renderer: renderer) }
        dumpFrame(renderer)
        renderer.present()
    }

    /// Whether PERRY_UIKIT_NO_BLUR is set: backdrops show as their tint.
    nonisolated(unsafe) static let blurDisabled = getenv("PERRY_UIKIT_NO_BLUR") != nil

    /// PERRY_UIKIT_FRAME_DUMP, a path: the frame the GPU composited, about
    /// every second, as a PNG there, as the display shows it (the snapshots
    /// draw in software). PERRY_UIKIT_FRAME_DUMP_INTERVAL, in seconds, makes
    /// it more often.
    nonisolated(unsafe) static let frameDump: String? = getenv("PERRY_UIKIT_FRAME_DUMP").map { String(cString: $0) }
    nonisolated(unsafe) private static let dumpInterval: Double = getenv("PERRY_UIKIT_FRAME_DUMP_INTERVAL").flatMap { Double(String(cString: $0)) } ?? 1
    nonisolated(unsafe) private static var lastDump: Double = 0

    /// Writes the frame drawn so far, when a dump is asked for and is due.
    private static func dumpFrame(_ renderer: SDLRenderer) {
        guard let path = frameDump, Clock.now - lastDump > dumpInterval else { return }
        lastDump = Clock.now
        guard let surface = SDL_RenderReadPixels(renderer.unsafePointer, nil) else { return }
        if let SDL_SavePNG { _ = path.withCString { SDL_SavePNG(surface, $0) } }
        SDL_DestroySurface(surface)
    }

    /// Whether the layer, its mask or anything under them has animations,
    /// which change what shows without changing the layers.
    static func isAnimating(_ layer: CALayer) -> Bool {
        let state = layer.state
        // A kept animation that has finished holds its last value and
        // changes nothing more: it is not a reason to draw the layer again.
        if state.animations.contains(where: { $0.animation.state.values["__perry.stopped"] == nil }) { return true }
        if state.livePixels != nil || state.sharedFrames != nil { return true }
        if let mask = state.mask, isAnimating(mask) { return true }
        return state.sublayers.contains(where: isAnimating)
    }

    /// Where a layer that shows only a shape draws: the path's box and its
    /// stroke's, within the bounds when they clip. An animation made at
    /// 3840x2160 has layers that big with a shape the size of a letter, and
    /// drawing the whole layer each frame takes tens of megabytes.
    static func shapeExtent(of layer: CALayer, state: LayerState, shape: ShapeLayerState) -> CGRect? {
        guard state.backgroundColor == nil, state.contents == nil, state.livePixels == nil, state.sharedFrames == nil,
              state.cornerRadius == 0, layer.state.backing == nil, !layer.draws, let path = shape.path else { return nil }
        let box = CG.pathGetBoundingBox(path)
        guard box.minX.isFinite, box.minY.isFinite, box.width.isFinite, box.height.isFinite else { return nil }
        let pad = shape.strokeColor == nil ? 1 : shape.lineWidth * max(shape.miterLimit, 1) / 2 + 1
        var extent = CGRect(x: box.minX - pad, y: box.minY - pad, width: box.width + 2 * pad, height: box.height + 2 * pad)
        if state.masksToBounds { extent = extent.intersection(state.bounds) }
        guard extent.width > 0, extent.height > 0 else { return nil }
        // A shape shows outside its layer's bounds too (an animation's
        // shapes are drawn around their layers' origins), which a texture
        // of the bounds would cut off.
        let bounds = state.bounds
        if extent.minX < bounds.minX || extent.minY < bounds.minY || extent.maxX > bounds.maxX || extent.maxY > bounds.maxY {
            return extent
        }
        // Within them, only for layers much larger than their shape.
        return extent.width * extent.height * 4 < bounds.width * bounds.height ? extent : nil
    }
}

private struct PixelRect {
    var x, y, width, height: Int32
}

@_silgen_name("SDL_RenderReadPixels")
private func SDL_RenderReadPixels(_ renderer: OpaquePointer, _ rect: UnsafePointer<PixelRect>?) -> UnsafeMutableRawPointer?
@_silgen_name("SDL_DestroySurface")
private func SDL_DestroySurface(_ surface: UnsafeMutableRawPointer)

/// SDL_SavePNG, which SDL has had since 3.4: looked up when a frame is
/// dumped, so the provider loads with an older SDL (Debian's 3.2).
nonisolated(unsafe) private let SDL_SavePNG: (@convention(c) (UnsafeMutableRawPointer, UnsafePointer<CChar>) -> Bool)? =
    dlsym(UnsafeMutableRawPointer(bitPattern: 0), "SDL_SavePNG").map {
        unsafeBitCast($0, to: (@convention(c) (UnsafeMutableRawPointer, UnsafePointer<CChar>) -> Bool).self)
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

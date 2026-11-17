import CPerryGeometry
import Glibc
import PerryObjCInterop
import SDL3Swift

// What a backdrop layer shows: the frame so far, where the layer is,
// blurred. The renderer reads those pixels back; they are shrunk, so the
// blur is cheap, blurred by three box passes (which make a gaussian), given
// the filters' saturation and the layer's rounded corners, then drawn as a
// texture the size of the layer, which the GPU scales back up smoothly.

private struct PixelRect {
    var x, y, width, height: Int32
}

@_silgen_name("SDL_RenderReadPixels")
private func SDL_RenderReadPixels(_ renderer: OpaquePointer, _ rect: UnsafePointer<PixelRect>?) -> UnsafeMutableRawPointer?
@_silgen_name("SDL_ConvertSurface")
private func SDL_ConvertSurface(_ surface: UnsafeMutableRawPointer, _ format: UInt32) -> UnsafeMutableRawPointer?
@_silgen_name("SDL_DestroySurface")
private func SDL_DestroySurface(_ surface: UnsafeMutableRawPointer)

@_silgen_name("SDL_SavePNG")
private func SDL_SavePNG(_ surface: UnsafeMutableRawPointer, _ file: UnsafePointer<CChar>) -> Bool

extension Compositor {
    /// PERRY_UIKIT_FRAME_DUMP, a path: the frame the GPU composited, about
    /// every second, as a PNG there, as the display shows it (the snapshots
    /// draw in software).
    nonisolated(unsafe) static let frameDump: String? = getenv("PERRY_UIKIT_FRAME_DUMP").map { String(cString: $0) }
    nonisolated(unsafe) private static var lastDump: Double = 0

    /// Writes the frame drawn so far, when a dump is asked for and is due.
    func dumpFrame() {
        guard let path = Compositor.frameDump, Clock.now - Compositor.lastDump > 1 else { return }
        Compositor.lastDump = Clock.now
        guard let surface = SDL_RenderReadPixels(renderer.unsafePointer, nil) else { return }
        _ = path.withCString { SDL_SavePNG(surface, $0) }
        SDL_DestroySurface(surface)
    }

    /// SDL_PIXELFORMAT_ARGB8888.
    private static let argb8888: UInt32 = 0x1636_2004

    /// Whether PERRY_UIKIT_NO_BLUR is set: backdrops show as their tint.
    nonisolated(unsafe) static let blurDisabled = getenv("PERRY_UIKIT_NO_BLUR") != nil

    /// Draws the blurred backdrop of `layer`, which `toScreen` places, within
    /// `clip`.
    /// Rounded corners the backdrop is drawn within, in pixels: a rectangle
    /// the layer or an ancestor clips to.
    typealias Rounding = (frame: CGRect, radius: CGFloat, corners: UInt)

    /// Draws the backdrops of the layers under one that is drawn flattened,
    /// within its rounded corners, as the flattened texture is drawn over
    /// them.
    func drawNestedBackdrops(in layer: CALayer, state: LayerState, toScreen: CGAffineTransform, alpha: CGFloat, clip: CGRect?, rounding: Rounding?) {
        for sublayer in CALayer.orderedSublayers(of: state) {
            let presented = Presentation.state(of: sublayer)
            guard !presented.hidden, presented.opacity > 0 else { continue }
            let placed = presented.toSuperlayer(within: state).concatenating(toScreen)
            let faded = alpha * CGFloat(presented.opacity)
            if sublayer.state.filters != nil, let backdrop = sublayer.as(CABackdropLayer.self) {
                drawBackdrop(backdrop, state: presented, toScreen: placed, alpha: faded, clip: clip, rounding: rounding)
            }
            drawNestedBackdrops(in: sublayer, state: presented, toScreen: placed, alpha: faded, clip: clip, rounding: rounding)
        }
    }

    /// The rounded corners a layer that clips to them gives its sublayers.
    func rounding(of state: LayerState, toScreen: CGAffineTransform) -> Rounding? {
        guard state.masksToBounds, state.cornerRadius > 0, toScreen.isAxisAligned else { return nil }
        let frame = pixels(toScreen.apply(state.bounds))
        return (CGRect(x: CGFloat(frame.x), y: CGFloat(frame.y), width: CGFloat(frame.width), height: CGFloat(frame.height)),
                state.cornerRadius * scale * abs(toScreen.a), state.maskedCorners)
    }

    func drawBackdrop(_ backdrop: CABackdropLayer, state: LayerState, toScreen: CGAffineTransform, alpha: CGFloat, clip: CGRect?,
                      rounding: Rounding? = nil) {
        guard !Compositor.blurDisabled, toScreen.isAxisAligned, alpha > 0 else { return }
        let (radius, saturation) = backdrop.backdropEffect
        if tracingFrame {
            "perry: QuartzCore: backdrop \(toScreen.apply(state.bounds)) blur \(radius) saturation \(saturation)\n".withCString { _ = write(2, $0, strlen($0)) }
        }
        let sigma = radius * scale * abs(toScreen.a)
        guard sigma >= 1, let output = renderer.outputSize else { return }
        let frame = pixels(toScreen.apply(state.bounds))
        var visible = CGRect(x: CGFloat(frame.x), y: CGFloat(frame.y), width: CGFloat(frame.width), height: CGFloat(frame.height))
        if let clip {
            visible = visible.intersection(CGRect(x: clip.minX * scale, y: clip.minY * scale, width: clip.width * scale, height: clip.height * scale))
        }
        visible = visible.intersection(CGRect(x: 0, y: 0, width: CGFloat(output.width), height: CGFloat(output.height)))
        if let rounding { visible = visible.intersection(rounding.frame) }
        guard visible.width >= 1, visible.height >= 1 else { return }

        // The pixels shrink by this much, blurred by a box of this reach.
        let shrink = Int(min(max((sigma / 6).rounded(), 1), 8))
        // What the blur reads past the edges, and the edges aligned to the
        // shrinking.
        let reach = Int(sigma * 1.5)
        let left = max(Int(visible.minX) - reach, 0) / shrink * shrink
        let top = max(Int(visible.minY) - reach, 0) / shrink * shrink
        let right = min(Int(visible.maxX.rounded(.up)) + reach, output.width)
        let bottom = min(Int(visible.maxY.rounded(.up)) + reach, output.height)
        let width = right - left, height = bottom - top
        guard width > 0, height > 0 else { return }

        var rect = PixelRect(x: Int32(left), y: Int32(top), width: Int32(width), height: Int32(height))
        guard let read = SDL_RenderReadPixels(renderer.unsafePointer, &rect) else { return }
        guard let surface = SDL_ConvertSurface(read, Compositor.argb8888) else {
            SDL_DestroySurface(read)
            return
        }
        SDL_DestroySurface(read)
        defer { SDL_DestroySurface(surface) }
        let pitch = Int(surface.load(fromByteOffset: 16, as: Int32.self))
        guard let source = surface.load(fromByteOffset: 24, as: UnsafeMutableRawPointer?.self),
              Int(surface.load(fromByteOffset: 8, as: Int32.self)) == width, Int(surface.load(fromByteOffset: 12, as: Int32.self)) == height else { return }

        // Shrunk: the average of each block.
        let small = (width: (width + shrink - 1) / shrink, height: (height + shrink - 1) / shrink)
        var channels = [UInt8](repeating: 255, count: small.width * small.height * 4)
        for row in 0..<small.height {
            for column in 0..<small.width {
                var sums = (0, 0, 0), count = 0
                for y in (row * shrink)..<min((row + 1) * shrink, height) {
                    let line = source.advanced(by: y * pitch).assumingMemoryBound(to: UInt32.self)
                    for x in (column * shrink)..<min((column + 1) * shrink, width) {
                        let pixel = line[x]
                        sums.0 += Int((pixel >> 16) & 255)
                        sums.1 += Int((pixel >> 8) & 255)
                        sums.2 += Int(pixel & 255)
                        count += 1
                    }
                }
                let at = (row * small.width + column) * 4
                channels[at] = UInt8(sums.2 / count)
                channels[at + 1] = UInt8(sums.1 / count)
                channels[at + 2] = UInt8(sums.0 / count)
            }
        }

        // Three box passes in each direction: a gaussian of this sigma.
        let box = max(Int((sigma / CGFloat(shrink) - 0.5).rounded()), 1)
        for _ in 0..<3 {
            Compositor.boxBlur(&channels, width: small.width, height: small.height, radius: box, horizontal: true)
            Compositor.boxBlur(&channels, width: small.width, height: small.height, radius: box, horizontal: false)
        }

        // Saturated, in the layer's corners, and premultiplied.
        let ownRounding: Rounding? = state.cornerRadius > 0
            ? (CGRect(x: CGFloat(frame.x), y: CGFloat(frame.y), width: CGFloat(frame.width), height: CGFloat(frame.height)),
               state.cornerRadius * scale * abs(toScreen.a), state.maskedCorners) : nil
        let round = rounding ?? ownRounding
        var pixelsOut = [UInt32](repeating: 0, count: small.width * small.height)
        for row in 0..<small.height {
            let y = CGFloat(top) + (CGFloat(row) + 0.5) * CGFloat(shrink)
            for column in 0..<small.width {
                let x = CGFloat(left) + (CGFloat(column) + 0.5) * CGFloat(shrink)
                let at = (row * small.width + column) * 4
                var (r, g, b) = (Float(channels[at + 2]), Float(channels[at + 1]), Float(channels[at]))
                if saturation != 1 {
                    let gray = 0.2126 * r + 0.7152 * g + 0.0722 * b
                    let amount = Float(saturation)
                    r = min(max(gray + (r - gray) * amount, 0), 255)
                    g = min(max(gray + (g - gray) * amount, 0), 255)
                    b = min(max(gray + (b - gray) * amount, 0), 255)
                }
                var cover: CGFloat = 1
                if let round {
                    cover = Compositor.cornerCover(x: x, y: y, in: round.frame, radius: round.radius, corners: round.corners, soft: CGFloat(shrink))
                }
                let a = Float(cover)
                pixelsOut[row * small.width + column] = UInt32(255 * a) << 24 | UInt32(r * a) << 16 | UInt32(g * a) << 8 | UInt32(b * a)
            }
        }

        guard let texture = try? SDLTexture(renderer: renderer, format: .argb8888, access: .static, width: small.width, height: small.height) else { return }
        pixelsOut.withUnsafeMutableBytes { try? texture.update(pixels: $0.baseAddress!, pitch: small.width * 4) }
        try? texture.setBlendMode([.alphaPremultiplied])
        try? texture.setScaleMode(.linear)
        let level = Float(alpha)
        try? texture.setAlphaModulation(level)
        try? texture.setColorModulation(red: level, green: level, blue: level)
        try? renderer.setClipRect(SDLRect(x: Int32(visible.minX), y: Int32(visible.minY), width: Int32(visible.width.rounded(.up)),
                                          height: Int32(visible.height.rounded(.up))))
        try? renderer.copy(texture, to: SDLFRect(x: Float(left), y: Float(top), width: Float(small.width * shrink), height: Float(small.height * shrink)))
    }

    /// How much of the point is inside the rounded corners of `rect`: 1
    /// away from them.
    private static func cornerCover(x: CGFloat, y: CGFloat, in rect: CGRect, radius: CGFloat, corners: UInt, soft: CGFloat) -> CGFloat {
        // kCALayerMinXMinYCorner 1, MaxXMinYCorner 2, MinXMaxYCorner 4,
        // MaxXMaxYCorner 8.
        let left = x < rect.minX + radius, right = x > rect.maxX - radius
        let above = y < rect.minY + radius, below = y > rect.maxY - radius
        var center: CGPoint?
        if left, above, corners & 1 != 0 { center = CGPoint(x: rect.minX + radius, y: rect.minY + radius) }
        if right, above, corners & 2 != 0 { center = CGPoint(x: rect.maxX - radius, y: rect.minY + radius) }
        if left, below, corners & 4 != 0 { center = CGPoint(x: rect.minX + radius, y: rect.maxY - radius) }
        if right, below, corners & 8 != 0 { center = CGPoint(x: rect.maxX - radius, y: rect.maxY - radius) }
        guard let center else { return 1 }
        let distance = ((x - center.x) * (x - center.x) + (y - center.y) * (y - center.y)).squareRoot() - radius
        return min(max(0.5 - distance / soft, 0), 1)
    }

    /// One box blur of the pixels' three color channels along a direction,
    /// the edges repeating.
    private static func boxBlur(_ pixels: inout [UInt8], width: Int, height: Int, radius: Int, horizontal: Bool) {
        let (length, lines) = horizontal ? (width, height) : (height, width)
        let (step, lineStep) = horizontal ? (4, width * 4) : (width * 4, 4)
        let span = radius * 2 + 1
        var source = pixels
        pixels.withUnsafeMutableBufferPointer { out in
            source.withUnsafeMutableBufferPointer { input in
                for line in 0..<lines {
                    let base = line * lineStep
                    for channel in 0..<3 {
                        func value(_ index: Int) -> Int { Int(input[base + min(max(index, 0), length - 1) * step + channel]) }
                        var sum = 0
                        for index in -radius...radius { sum += value(index) }
                        for index in 0..<length {
                            out[base + index * step + channel] = UInt8(sum / span)
                            sum += value(index + radius + 1) - value(index - radius)
                        }
                    }
                }
            }
        }
    }
}

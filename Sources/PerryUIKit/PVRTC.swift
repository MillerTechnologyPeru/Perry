import Glibc

// PVRTC, the compressed texture format of iOS's PowerVR GPUs, which other
// GPUs can't sample: glCompressedTexImage2D decodes it to RGBA here and
// uploads that instead. Every other format goes to the host's function.
//
// PVRTC1 stores 64-bit blocks of 4×4 pixels (4 bits a pixel) or 8×4 (2
// bits), in Morton order. Each block has two colors, A and B, and a
// modulation value for each pixel; a pixel's A and B are interpolated from
// the four blocks whose centers surround it, then blended by its value.

enum PVRTC {
    static let rgb4: UInt32 = 0x8C00, rgb2: UInt32 = 0x8C01, rgba4: UInt32 = 0x8C02, rgba2: UInt32 = 0x8C03

    typealias TexImage = @convention(c) (UInt32, Int32, Int32, Int32, Int32, Int32, UInt32, UInt32, UnsafeRawPointer?) -> Void
    typealias TexSubImage = @convention(c) (UInt32, Int32, Int32, Int32, Int32, Int32, UInt32, UInt32, UnsafeRawPointer?) -> Void
    typealias CompressedImage = @convention(c) (UInt32, Int32, UInt32, Int32, Int32, Int32, Int32, UnsafeRawPointer?) -> Void
    typealias CompressedSubImage = @convention(c) (UInt32, Int32, Int32, Int32, Int32, Int32, UInt32, Int32, UnsafeRawPointer?) -> Void

    nonisolated(unsafe) static var texImage: TexImage?
    nonisolated(unsafe) static var texSubImage: TexSubImage?
    nonisolated(unsafe) static var compressedImage: CompressedImage?
    nonisolated(unsafe) static var compressedSubImage: CompressedSubImage?

    static func bind(_ host: (String) -> UnsafeMutableRawPointer?) {
        texImage = host("glTexImage2D").map { unsafeBitCast($0, to: TexImage.self) }
        texSubImage = host("glTexSubImage2D").map { unsafeBitCast($0, to: TexSubImage.self) }
        compressedImage = host("glCompressedTexImage2D").map { unsafeBitCast($0, to: CompressedImage.self) }
        compressedSubImage = host("glCompressedTexSubImage2D").map { unsafeBitCast($0, to: CompressedSubImage.self) }
    }

    static func isPVRTC(_ format: UInt32) -> Bool { format >= rgb4 && format <= rgba2 }

    static let compressedTexImage2D: CompressedImage = { target, level, format, width, height, border, size, data in
        guard isPVRTC(format) else {
            PVRTC.compressedImage?(target, level, format, width, height, border, size, data)
            return
        }
        let pixels = data.flatMap { decode($0, Int(size), width: Int(width), height: Int(height), twoBit: format == rgb2 || format == rgba2) }
        // GL_RGBA, GL_UNSIGNED_BYTE; rows of RGBA are 4-byte aligned.
        PVRTC.texImage?(target, level, 0x1908, width, height, 0, 0x1908, 0x1401, pixels)
        pixels?.deallocate()
    }

    static let compressedTexSubImage2D: CompressedSubImage = { target, level, x, y, width, height, format, size, data in
        guard isPVRTC(format) else {
            PVRTC.compressedSubImage?(target, level, x, y, width, height, format, size, data)
            return
        }
        guard let data, let pixels = decode(data, Int(size), width: Int(width), height: Int(height),
                                            twoBit: format == rgb2 || format == rgba2) else { return }
        PVRTC.texSubImage?(target, level, x, y, width, height, 0x1908, 0x1401, pixels)
        pixels.deallocate()
    }

    /// The block's index in Morton order, with y's bits below x's, and the
    /// longer side's extra bits above them.
    static func twiddle(_ x: Int, _ y: Int, blocksWide: Int, blocksHigh: Int) -> Int {
        var minimum = blocksWide, rest = y
        if blocksHigh < blocksWide { minimum = blocksHigh; rest = x }
        var result = 0, source = 1, destination = 1, shift = 0
        while source < minimum {
            if y & source != 0 { result |= destination }
            if x & source != 0 { result |= destination << 1 }
            source <<= 1
            destination <<= 2
            shift += 1
        }
        return result | ((rest >> shift) << (2 * shift))
    }

    /// Color A, from the color word's low half: 5-bit red, green and blue,
    /// 4-bit alpha.
    static func colorA(_ word: UInt32) -> (Int, Int, Int, Int) {
        let c = Int(word & 0xFFFF)
        if c & 0x8000 != 0 {
            return ((c >> 10) & 0x1F, (c >> 5) & 0x1F, (c & 0x1E) | ((c & 0x1E) >> 4), 0xF)
        }
        return (((c >> 7) & 0x1E) | ((c >> 11) & 0x1), ((c >> 3) & 0x1E) | ((c >> 7) & 0x1),
                ((c << 1) & 0x1C) | ((c >> 2) & 0x3), (c >> 11) & 0xE)
    }

    /// Color B, from the color word's high half.
    static func colorB(_ word: UInt32) -> (Int, Int, Int, Int) {
        let c = Int(word)
        if c & 0x8000_0000 != 0 {
            return ((c >> 26) & 0x1F, (c >> 21) & 0x1F, (c >> 16) & 0x1F, 0xF)
        }
        return (((c >> 23) & 0x1E) | ((c >> 27) & 0x1), ((c >> 19) & 0x1E) | ((c >> 23) & 0x1),
                ((c >> 15) & 0x1E) | ((c >> 19) & 0x1), (c >> 27) & 0xE)
    }

    /// RGBA pixels, top row first, allocated; nil if the data is short.
    static func decode(_ data: UnsafeRawPointer, _ size: Int, width: Int, height: Int, twoBit: Bool) -> UnsafeMutablePointer<UInt8>? {
        guard width > 0, height > 0 else { return nil }
        let blockWidth = twoBit ? 8 : 4, blockHeight = 4
        // Textures have at least two blocks each way.
        let blocksWide = max((width + blockWidth - 1) / blockWidth, 2), blocksHigh = max((height + blockHeight - 1) / blockHeight, 2)
        guard size >= blocksWide * blocksHigh * 8 else { return nil }
        let words = data.assumingMemoryBound(to: UInt32.self)
        func block(_ bx: Int, _ by: Int) -> (modulation: UInt32, color: UInt32) {
            let x = (bx % blocksWide + blocksWide) % blocksWide, y = (by % blocksHigh + blocksHigh) % blocksHigh
            let index = twiddle(x, y, blocksWide: blocksWide, blocksHigh: blocksHigh)
            return (UInt32(littleEndian: words[index * 2]), UInt32(littleEndian: words[index * 2 + 1]))
        }
        let out = UnsafeMutablePointer<UInt8>.allocate(capacity: width * height * 4)
        let area = blockWidth * blockHeight
        for py in 0..<height {
            for px in 0..<width {
                // The blocks whose centers surround the pixel, and its place
                // between them.
                let fx = px - blockWidth / 2, fy = py - blockHeight / 2
                let bx = fx >= 0 ? fx / blockWidth : (fx - blockWidth + 1) / blockWidth
                let by = fy >= 0 ? fy / blockHeight : (fy - blockHeight + 1) / blockHeight
                let u = fx - bx * blockWidth, v = fy - by * blockHeight
                let p = block(bx, by), q = block(bx + 1, by), r = block(bx, by + 1), s = block(bx + 1, by + 1)
                let wp = (blockWidth - u) * (blockHeight - v), wq = u * (blockHeight - v), wr = (blockWidth - u) * v, ws = u * v
                func mix(_ f: (UInt32) -> (Int, Int, Int, Int)) -> (Int, Int, Int, Int) {
                    let a = f(p.color), b = f(q.color), c = f(r.color), d = f(s.color)
                    return (a.0 * wp + b.0 * wq + c.0 * wr + d.0 * ws, a.1 * wp + b.1 * wq + c.1 * wr + d.1 * ws,
                            a.2 * wp + b.2 * wq + c.2 * wr + d.2 * ws, a.3 * wp + b.3 * wq + c.3 * wr + d.3 * ws)
                }
                let a = mix(colorA), b = mix(colorB)
                // The pixel's own block, and its modulation weight in eighths.
                let own = block(px / blockWidth, py / blockHeight)
                let lx = px % blockWidth, ly = py % blockHeight
                let punchThrough = own.color & 1 != 0
                var weight = 0, transparent = false
                if !twoBit {
                    let value = Int((own.modulation >> UInt32(2 * (ly * 4 + lx))) & 3)
                    if punchThrough {
                        weight = [0, 4, 4, 8][value]
                        transparent = value == 2
                    } else {
                        weight = [0, 3, 5, 8][value]
                    }
                } else if !punchThrough {
                    weight = (own.modulation >> UInt32(ly * 8 + lx)) & 1 != 0 ? 8 : 0
                } else {
                    // Half the pixels, in a checkerboard, have 2-bit values;
                    // the others take the average of their neighbors'.
                    func stored(_ x: Int, _ y: Int) -> Int {
                        let cx = (x + blockWidth) % blockWidth, cy = (y + blockHeight) % blockHeight
                        let bit = (cy * 8 + cx) / 2 * 2
                        return [0, 3, 5, 8][Int((own.modulation >> UInt32(bit)) & 3)]
                    }
                    weight = (lx + ly) % 2 == 0 ? stored(lx, ly) : (stored(lx - 1, ly) + stored(lx + 1, ly)) / 2
                }
                // A and B are in 5-bit (alpha 4-bit) units times the area.
                func channel(_ a: Int, _ b: Int, _ maximum: Int) -> UInt8 {
                    let value = (a * (8 - weight) + b * weight) / 8
                    return UInt8(clamping: value * 255 / (maximum * area))
                }
                let o = (py * width + px) * 4
                out[o] = channel(a.0, b.0, 31)
                out[o + 1] = channel(a.1, b.1, 31)
                out[o + 2] = channel(a.2, b.2, 31)
                out[o + 3] = transparent ? 0 : channel(a.3, b.3, 15)
            }
        }
        return out
    }
}

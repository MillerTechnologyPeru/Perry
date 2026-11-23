import CPerryGeometry
import Glibc
import PerryObjCInterop

// Core Image's images as Perry works them: each is a recipe, a node that
// renders any rectangle of itself on the CPU when a context asks for its
// pixels. Pixels are premultiplied RGBA floats in Core Image's space: y
// upwards, a pixel covering the unit square above and right of its
// coordinates. CoreGraphics draws and resamples bitmaps; the filters'
// arithmetic is done on the floats.

typealias RGBA = SIMD4<Float>

enum CoreImageGeometry {
    /// CGRectInfinite: the extent of an image without edges, such as a
    /// color's.
    static let infinite = CGRect(x: -CGFloat.greatestFiniteMagnitude / 2, y: -CGFloat.greatestFiniteMagnitude / 2,
                                 width: .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)

    static func isInfinite(_ rect: CGRect) -> Bool {
        rect.width >= CGFloat.greatestFiniteMagnitude / 4 || rect.height >= CGFloat.greatestFiniteMagnitude / 4
    }

    static func isEmpty(_ rect: CGRect) -> Bool { !(rect.width > 0 && rect.height > 0) }

    static func union(_ a: CGRect, _ b: CGRect) -> CGRect {
        if isInfinite(a) || isInfinite(b) { return infinite }
        if isEmpty(a) { return b }
        if isEmpty(b) { return a }
        let x = min(a.minX, b.minX), y = min(a.minY, b.minY)
        return CGRect(x: x, y: y, width: max(a.maxX, b.maxX) - x, height: max(a.maxY, b.maxY) - y)
    }

    static func intersection(_ a: CGRect, _ b: CGRect) -> CGRect {
        if isInfinite(a) { return b }
        if isInfinite(b) { return a }
        return a.intersection(b)
    }

    static func outset(_ rect: CGRect, by amount: CGFloat) -> CGRect {
        isInfinite(rect) || isEmpty(rect) ? rect
            : CGRect(x: rect.minX - amount, y: rect.minY - amount, width: rect.width + 2 * amount, height: rect.height + 2 * amount)
    }
}

/// A rectangle of whole pixels.
struct ImageRect: Equatable {
    var x = 0, y = 0, width = 0, height = 0

    var isEmpty: Bool { width <= 0 || height <= 0 }
    var maxX: Int { x + width }
    var maxY: Int { y + height }
    var count: Int { isEmpty ? 0 : width * height }
    var cgRect: CGRect { CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height)) }

    init() {}

    init(x: Int, y: Int, width: Int, height: Int) {
        (self.x, self.y, self.width, self.height) = (x, y, width, height)
    }

    /// The pixels `rect` touches; none for an empty or infinite one.
    init(covering rect: CGRect) {
        guard !CoreImageGeometry.isInfinite(rect), !CoreImageGeometry.isEmpty(rect),
              abs(Double(rect.minX)) < 1e8, abs(Double(rect.minY)) < 1e8, Double(rect.width) < 1e8, Double(rect.height) < 1e8
        else { return }
        // A rectangle off whole pixels by rounding error keeps its size.
        let minX = Int(floor(Double(rect.minX) + 1e-3)), minY = Int(floor(Double(rect.minY) + 1e-3))
        let maxX = Int(ceil(Double(rect.maxX) - 1e-3)), maxY = Int(ceil(Double(rect.maxY) - 1e-3))
        (x, y, width, height) = (minX, minY, maxX - minX, maxY - minY)
    }

    func intersection(_ other: ImageRect) -> ImageRect {
        let minX = max(x, other.x), minY = max(y, other.y)
        return ImageRect(x: minX, y: minY, width: max(0, min(maxX, other.maxX) - minX), height: max(0, min(maxY, other.maxY) - minY))
    }

    func outset(_ amount: Int) -> ImageRect {
        ImageRect(x: x - amount, y: y - amount, width: width + 2 * amount, height: height + 2 * amount)
    }
}

/// Pixels of a rectangle, premultiplied, in rows from the top as bitmaps
/// keep them.
struct Pixels {
    let rect: ImageRect
    var data: [RGBA]

    /// Transparent pixels.
    init(_ rect: ImageRect) {
        self.rect = rect
        data = Array(repeating: .zero, count: rect.count)
    }

    /// The index of the pixel at `x`, `y` in Core Image's space.
    @inline(__always) func index(_ x: Int, _ y: Int) -> Int { (rect.maxY - 1 - y) * rect.width + (x - rect.x) }

    /// The pixel at `x`, `y`; transparent outside the rectangle.
    @inline(__always) func at(_ x: Int, _ y: Int) -> RGBA {
        x >= rect.x && x < rect.maxX && y >= rect.y && y < rect.maxY ? data[index(x, y)] : .zero
    }

    /// The pixels where `other` overlaps these, copied over.
    mutating func copy(from other: Pixels) {
        let overlap = rect.intersection(other.rect)
        guard !overlap.isEmpty else { return }
        for y in overlap.y..<overlap.maxY {
            let to = index(overlap.x, y), from = other.index(overlap.x, y)
            for offset in 0..<overlap.width { data[to + offset] = other.data[from + offset] }
        }
    }
}

/// A CoreGraphics object kept while a recipe needs it.
final class RetainedCG {
    let ref: CGRef

    init(_ ref: CGRef) { self.ref = ObjCRuntime.retain(ref)! }
    /// Adopting a reference the caller made, +1.
    init(adopting ref: CGRef) { self.ref = ref }
    deinit { CG.release(ref) }
}

/// Bitmaps in CoreGraphics' format for Core Image: 8-bit BGRA in memory,
/// premultiplied, rows from the top.
enum Bitmaps {
    /// No more than 8192 by 8192 pixels at once.
    static let maximumPixels = 1 << 26

    /// A cleared bitmap context of the rectangle's pixels whose user space
    /// is Core Image's: drawing at a point lands on the same pixel.
    static func context(_ rect: ImageRect) -> CGRef? {
        guard !rect.isEmpty, rect.count <= maximumPixels, let space = CG.colorSpaceCreateDeviceRGB() else { return nil }
        defer { CG.release(space) }
        guard let context = CG.bitmapContextCreate(nil, rect.width, rect.height, 8, rect.width * 4, space, CG.bitmapInfo(opaque: false))
        else { return nil }
        if let data = CG.bitmapContextGetData(context) { memset(data, 0, rect.count * 4) }
        CG.translateCTM(context, CGFloat(-rect.x), CGFloat(-rect.y))
        return context
    }

    /// The rectangle's pixels as `draw` draws them in Core Image's space.
    static func drawing(_ rect: ImageRect, _ draw: (CGRef) -> Void) -> Pixels {
        var pixels = Pixels(rect)
        guard let context = context(rect) else { return pixels }
        defer { CG.release(context) }
        draw(context)
        guard let data = CG.bitmapContextGetData(context) else { return pixels }
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        let scale: Float = 1 / 255
        for i in 0..<rect.count {
            let at = i * 4
            pixels.data[i] = RGBA(Float(bytes[at + 2]), Float(bytes[at + 1]), Float(bytes[at]), Float(bytes[at + 3])) * scale
        }
        return pixels
    }

    /// A CGImage of the pixels, +1.
    static func image(_ pixels: Pixels) -> CGRef? {
        let rect = pixels.rect
        guard !rect.isEmpty, rect.count <= maximumPixels, let space = CG.colorSpaceCreateDeviceRGB() else { return nil }
        defer { CG.release(space) }
        guard let context = CG.bitmapContextCreate(nil, rect.width, rect.height, 8, rect.width * 4, space, CG.bitmapInfo(opaque: false))
        else { return nil }
        defer { CG.release(context) }
        guard let data = CG.bitmapContextGetData(context) else { return nil }
        write(pixels, to: data.assumingMemoryBound(to: UInt8.self), rowBytes: rect.width * 4, order: (2, 1, 0, 3))
        return CG.bitmapContextCreateImage(context)
    }

    /// The pixels as 8-bit samples, premultiplied, rows from the top; `order`
    /// gives the byte each of red, green, blue and alpha goes to.
    static func write(_ pixels: Pixels, to bytes: UnsafeMutablePointer<UInt8>, rowBytes: Int, order: (Int, Int, Int, Int)) {
        let rect = pixels.rect
        for row in 0..<rect.height {
            let line = bytes + row * rowBytes
            for column in 0..<rect.width {
                let c = simd_clamp(pixels.data[row * rect.width + column]) * 255 + 0.5
                let at = line + column * 4
                at[order.0] = UInt8(c.x)
                at[order.1] = UInt8(c.y)
                at[order.2] = UInt8(c.z)
                at[order.3] = UInt8(c.w)
            }
        }
    }

    /// Pixels read from 8-bit samples, premultiplied, rows from the top.
    static func read(_ bytes: UnsafePointer<UInt8>, rowBytes: Int, width: Int, height: Int, order: (Int, Int, Int, Int)) -> Pixels {
        var pixels = Pixels(ImageRect(x: 0, y: 0, width: width, height: height))
        let scale: Float = 1 / 255
        for row in 0..<height {
            let line = bytes + row * rowBytes
            for column in 0..<width {
                let at = line + column * 4
                pixels.data[row * width + column] = RGBA(Float(at[order.0]), Float(at[order.1]), Float(at[order.2]), Float(at[order.3])) * scale
            }
        }
        return pixels
    }

    /// Each component within 0...1; NaN, which a filter's arithmetic can
    /// make, as 0.
    @inline(__always) static func simd_clamp(_ c: RGBA) -> RGBA {
        c.replacing(with: 0, where: c .< 0 .| c .!= c).replacing(with: 1, where: c .> 1)
    }
}

/// An image's recipe: its extent and how to render a rectangle of it.
final class ImageNode {
    let extent: CGRect
    private let renderer: (ImageRect) -> Pixels

    init(extent: CGRect, _ renderer: @escaping (ImageRect) -> Pixels) {
        self.extent = extent
        self.renderer = renderer
    }

    /// The rectangle's pixels; transparent outside the extent.
    func render(_ rect: ImageRect) -> Pixels { rect.isEmpty ? Pixels(rect) : renderer(rect) }

    /// The pixels the extent covers; nil for an infinite one.
    var pixelExtent: ImageRect? { CoreImageGeometry.isInfinite(extent) ? nil : ImageRect(covering: extent) }

    /// The whole image as a CGImage, +1; nil for an empty or infinite one.
    func makeCGImage() -> CGRef? {
        guard let rect = pixelExtent, !rect.isEmpty else { return nil }
        return Bitmaps.image(render(rect))
    }

    nonisolated(unsafe) static let empty = ImageNode(extent: .zero) { Pixels($0) }

    /// A color without edges; `color` premultiplied.
    static func color(_ color: RGBA) -> ImageNode {
        ImageNode(extent: CoreImageGeometry.infinite) { rect in
            var pixels = Pixels(rect)
            for i in pixels.data.indices { pixels.data[i] = color }
            return pixels
        }
    }

    /// A CGImage with its lower left at the origin.
    static func bitmap(_ image: CGRef) -> ImageNode {
        let kept = RetainedCG(image)
        let width = CG.imageGetWidth(image), height = CG.imageGetHeight(image)
        let bounds = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        return ImageNode(extent: bounds) { rect in
            Bitmaps.drawing(rect) { CG.drawImage($0, bounds, kept.ref) }
        }
    }

    static func pixels(_ pixels: Pixels) -> ImageNode {
        ImageNode(extent: pixels.rect.cgRect) { rect in
            var out = Pixels(rect)
            out.copy(from: pixels)
            return out
        }
    }

    // MARK: Geometry

    /// The image transformed, CoreGraphics resampling it.
    func transformed(_ transform: CGAffineTransform) -> ImageNode {
        if transform.isIdentity { return self }
        let determinant = transform.a * transform.d - transform.b * transform.c
        guard determinant != 0 else { return .empty }
        let infinite = CoreImageGeometry.isInfinite(extent)
        let source = self
        return ImageNode(extent: infinite ? extent : transform.apply(extent)) { rect in
            // The pixels the rectangle samples, and a margin for filtering.
            var needed = ImageRect(covering: transform.inverted.apply(rect.cgRect)).outset(2)
            if let bounds = source.pixelExtent { needed = needed.intersection(bounds) }
            guard !needed.isEmpty, let image = Bitmaps.image(source.render(needed)) else { return Pixels(rect) }
            defer { CG.release(image) }
            return Bitmaps.drawing(rect) { context in
                CG.concatCTM(context, transform)
                CG.drawImage(context, needed.cgRect, image)
            }
        }
    }

    func cropped(to crop: CGRect) -> ImageNode {
        let extent = CoreImageGeometry.intersection(self.extent, crop)
        if CoreImageGeometry.isInfinite(crop) { return self }
        let source = self, bounds = ImageRect(covering: extent)
        return ImageNode(extent: extent) { rect in
            var out = Pixels(rect)
            let inside = rect.intersection(bounds)
            if !inside.isEmpty { out.copy(from: source.render(inside)) }
            return out
        }
    }

    /// The image's edge pixels repeated out to infinity.
    func clamped() -> ImageNode {
        guard let bounds = pixelExtent else { return self }
        guard !bounds.isEmpty else { return .empty }
        let source = self
        return ImageNode(extent: CoreImageGeometry.infinite) { rect in
            // The source's pixels the rectangle reaches, its edges included.
            func clampX(_ x: Int) -> Int { min(max(x, bounds.x), bounds.maxX - 1) }
            func clampY(_ y: Int) -> Int { min(max(y, bounds.y), bounds.maxY - 1) }
            let (left, bottom) = (clampX(rect.x), clampY(rect.y))
            let needed = ImageRect(x: left, y: bottom, width: clampX(rect.maxX - 1) - left + 1, height: clampY(rect.maxY - 1) - bottom + 1)
            let pixels = source.render(needed)
            var out = Pixels(rect)
            var i = 0
            for row in 0..<rect.height {
                let y = min(max(rect.maxY - 1 - row, needed.y), needed.maxY - 1)
                for column in 0..<rect.width {
                    let x = min(max(rect.x + column, needed.x), needed.maxX - 1)
                    out.data[i] = pixels.data[pixels.index(x, y)]
                    i += 1
                }
            }
            return out
        }
    }

    // MARK: Pixel arithmetic

    /// Each pixel's color worked by `body` unpremultiplied, and
    /// premultiplied again; transparent pixels stay so.
    func mapped(_ body: @escaping (RGBA) -> RGBA) -> ImageNode {
        let source = self
        return ImageNode(extent: extent) { rect in
            var pixels = source.render(rect)
            for i in pixels.data.indices {
                let c = pixels.data[i]
                guard c.w > 0 else { continue }
                let out = Bitmaps.simd_clamp(body(RGBA(c.x / c.w, c.y / c.w, c.z / c.w, c.w)))
                pixels.data[i] = RGBA(out.x * out.w, out.y * out.w, out.z * out.w, out.w)
            }
            return pixels
        }
    }

    /// Two images' pixels, premultiplied, combined by `body`.
    static func combined(_ a: ImageNode, _ b: ImageNode, extent: CGRect, _ body: @escaping (RGBA, RGBA, Int, Int) -> RGBA) -> ImageNode {
        ImageNode(extent: extent) { rect in
            let first = a.render(rect), second = b.render(rect)
            var out = Pixels(rect)
            var i = 0
            for row in 0..<rect.height {
                let y = rect.maxY - 1 - row
                for column in 0..<rect.width {
                    out.data[i] = Bitmaps.simd_clamp(body(first.data[i], second.data[i], rect.x + column, y))
                    i += 1
                }
            }
            return out
        }
    }

    // MARK: Blur

    /// The image blurred by a Gaussian of standard deviation `sigma`, as
    /// three box blurs; transparent beyond its extent.
    func blurred(sigma: Double) -> ImageNode {
        guard sigma >= 0.3 else { return self }
        let boxes = ImageNode.boxes(sigma: sigma)
        let margin = boxes.reduce(0) { $0 + $1 }
        let source = self
        return ImageNode(extent: CoreImageGeometry.outset(extent, by: CGFloat(margin))) { rect in
            let padded = rect.outset(margin)
            var pixels = source.render(padded)
            var scratch = [RGBA](repeating: .zero, count: max(padded.width, padded.height))
            for radius in boxes {
                ImageNode.boxBlur(&pixels.data, width: padded.width, height: padded.height, radius: radius, scratch: &scratch)
            }
            var out = Pixels(rect)
            out.copy(from: pixels)
            return out
        }
    }

    /// Three box radii whose blur together approximates the Gaussian.
    static func boxes(sigma: Double) -> [Int] {
        let passes = 3.0
        var lower = Int(sqrt(12 * sigma * sigma / passes + 1))
        if lower % 2 == 0 { lower -= 1 }
        let upper = lower + 2
        let l = Double(lower)
        let mIdeal = (12 * sigma * sigma - passes * l * l - 4 * passes * l - 3 * passes) / (-4 * l - 4)
        let m = Int(mIdeal.rounded())
        // Each box's width is odd: its radius is half the rest.
        return (0..<3).map { ($0 < m ? lower : upper) / 2 }
    }

    /// A box blur of `radius` across the rows, then down the columns.
    static func boxBlur(_ data: inout [RGBA], width: Int, height: Int, radius: Int, scratch: inout [RGBA]) {
        guard radius > 0 else { return }
        let scale = 1 / Float(2 * radius + 1)
        data.withUnsafeMutableBufferPointer { pixels in
            scratch.withUnsafeMutableBufferPointer { line in
                for row in 0..<height {
                    let base = row * width
                    var sum = RGBA.zero
                    for x in 0..<min(radius, width) { sum += pixels[base + x] }
                    for x in 0..<width {
                        if x + radius < width { sum += pixels[base + x + radius] }
                        if x - radius - 1 >= 0 { sum -= pixels[base + x - radius - 1] }
                        line[x] = sum * scale
                    }
                    for x in 0..<width { pixels[base + x] = line[x] }
                }
                for column in 0..<width {
                    var sum = RGBA.zero
                    for y in 0..<min(radius, height) { sum += pixels[y * width + column] }
                    for y in 0..<height {
                        if y + radius < height { sum += pixels[(y + radius) * width + column] }
                        if y - radius - 1 >= 0 { sum -= pixels[(y - radius - 1) * width + column] }
                        line[y] = sum * scale
                    }
                    for y in 0..<height { pixels[y * width + column] = line[y] }
                }
            }
        }
    }
}

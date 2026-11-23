import CoreGraphics
import CoreVideo
import Darwin

// The storage behind vImage.PixelBuffer: the vImage_Buffer of each plane
// and, for buffers the overlay allocated, an owner that frees their data
// with the last copy of the pixel buffer. Pixel buffers made over memory
// the caller owns (init(data:...), CVPixelBuffer references) have none.

final class _vImagePixelStorage {
    var allocations: [UnsafeMutableRawPointer] = []
    var retained: [AnyObject] = []

    init() {}

    init(allocation: UnsafeMutableRawPointer?) {
        if let allocation { allocations.append(allocation) }
    }

    deinit {
        for allocation in allocations { Darwin.free(allocation) }
    }
}

/// A vImage_Buffer of the size given whose data vImageBuffer_Init
/// allocated (rows aligned as vImage prefers).
func _vImageAllocateBuffer(width: Int, height: Int, bitsPerPixel: Int) -> vImage_Buffer {
    precondition(width >= 0 && height >= 0, "a pixel buffer's size can't be negative")
    var buffer = vImage_Buffer()
    let error = vImageBuffer_Init(&buffer, vImagePixelCount(max(height, 1)), vImagePixelCount(max(width, 1)),
                                  UInt32(bitsPerPixel), vImage_Flags(kvImageNoFlags))
    precondition(error == kvImageNoError, "vImage couldn't allocate a \(width)x\(height) buffer")
    buffer.width = vImagePixelCount(width)
    buffer.height = vImagePixelCount(height)
    return buffer
}

/// Runs a vImage function of a source and a destination buffer.
@discardableResult
func _vImageRun(_ source: vImage_Buffer, _ destination: vImage_Buffer,
                _ function: (UnsafePointer<vImage_Buffer>, UnsafePointer<vImage_Buffer>) -> vImage_Error) -> vImage_Error {
    var source = source
    var destination = destination
    return function(&source, &destination)
}

/// The buffer seen as `factor` times as wide: an interleaved buffer as a
/// planar one of its components, for the functions that work on any
/// component.
func _vImageWidened(_ buffer: vImage_Buffer, by factor: Int) -> vImage_Buffer {
    var buffer = buffer
    buffer.width *= vImagePixelCount(factor)
    return buffer
}

/// A 1x1 vImage_Buffer over a value, for converting single pixels.
func _vImageWithPixel<P, R>(_ pixel: inout P, _ body: (vImage_Buffer) -> R) -> R {
    withUnsafeMutableBytes(of: &pixel) { bytes in
        body(vImage_Buffer(data: bytes.baseAddress, height: 1, width: 1, rowBytes: bytes.count))
    }
}

/// The components of a pixel tuple (Pixel_8888, Pixel_FFFF...) as an array.
func _vImageComponents<P, C>(_ pixel: P, as type: C.Type) -> [C] {
    var pixel = pixel
    return withUnsafeBytes(of: &pixel) { Array($0.bindMemory(to: C.self)) }
}

/// A pixel tuple from its components.
func _vImagePixel<P, C>(_ components: [C], as type: P.Type, zero: P) -> P {
    var pixel = zero
    withUnsafeMutableBytes(of: &pixel) { bytes in
        let typed = bytes.bindMemory(to: C.self)
        for i in 0..<min(typed.count, components.count) { typed[i] = components[i] }
    }
    return pixel
}

func _vImageCheckSizes(_ a: vImage_Buffer, _ b: vImage_Buffer, _ function: String = #function) {
    precondition(a.width == b.width && a.height == b.height, "\(function): the source and destination buffers must be the same size")
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension vImage.Error {
    /// The cases after noError, in the order of their C codes from
    /// kvImageRoiLargerThanInputBuffer (-21766) down.
    static let _cases: [vImage.Error] = [
        .roiLargerThanInputBuffer, .invalidKernelSize, .invalidEdgeStyle, .invalidOffset_X, .invalidOffset_Y,
        .memoryAllocationError, .nullPointerArgument, .invalidParameter, .bufferSizeMismatch, .unknownFlagsBit,
        .internalError, .invalidRowBytes, .invalidImageFormat, .colorSyncIsAbsent, .outOfPlaceOperationRequired,
        .invalidImageObject, .invalidCVImageFormat, .unsupportedConversion, .coreVideoIsAbsent,
    ]

    /// The C code of the case (kvImageNoError, kvImageRoiLargerThanInputBuffer...).
    var _vImageCode: Int {
        switch self {
        case .noError: return 0
        case .roiLargerThanInputBuffer: return -21766
        case .invalidKernelSize: return -21767
        case .invalidEdgeStyle: return -21768
        case .invalidOffset_X: return -21769
        case .invalidOffset_Y: return -21770
        case .memoryAllocationError: return -21771
        case .nullPointerArgument: return -21772
        case .invalidParameter: return -21773
        case .bufferSizeMismatch: return -21774
        case .unknownFlagsBit: return -21775
        case .internalError: return -21776
        case .invalidRowBytes: return -21777
        case .invalidImageFormat: return -21778
        case .colorSyncIsAbsent: return -21779
        case .outOfPlaceOperationRequired: return -21780
        case .invalidImageObject: return -21781
        case .invalidCVImageFormat: return -21782
        case .unsupportedConversion: return -21783
        case .coreVideoIsAbsent: return -21784
        }
    }

    /// Throws the error a vImage function returned, if any.
    static func _check(_ error: vImage_Error) throws {
        if error < 0 { throw vImage.Error(vImageError: error) }
    }
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format: StaticPixelFormat {
    /// A buffer of the format's own, allocated by the overlay.
    init(_allocatingWidth width: Int, height: Int) {
        let buffer = _vImageAllocateBuffer(width: width, height: height, bitsPerPixel: Format.bitCountPerPixel)
        self.init(_buffers: [buffer], storage: _vImagePixelStorage(allocation: buffer.data))
    }

    /// The part of the buffer a rectangle in pixels covers, over the same memory.
    func _region(x: Int, y: Int, width: Int, height: Int) -> vImage_Buffer {
        precondition(x >= 0 && y >= 0 && width >= 0 && height >= 0 && x + width <= self.width && y + height <= self.height,
                     "the region must lie within the pixel buffer")
        var buffer = _vImageBuffers[0]
        buffer.data = buffer.data.map { $0 + y * buffer.rowBytes + x * (Format.bitCountPerPixel / 8) }
        buffer.width = vImagePixelCount(width)
        buffer.height = vImagePixelCount(height)
        return buffer
    }

    func _region(_ rect: CGRect) -> vImage_Buffer {
        let r = rect.integral
        return _region(x: Int(r.minX), y: Int(r.minY), width: Int(r.width), height: Int(r.height))
    }

    /// Whether rows follow each other without padding.
    var _isContiguous: Bool {
        let buffer = _vImageBuffers[0]
        return buffer.height <= 1 || buffer.rowBytes == Int(buffer.width) * (Format.bitCountPerPixel / 8)
    }

    /// The components row after row, without padding.
    func _componentArray() -> [Format.ComponentType] {
        let buffer = _vImageBuffers[0]
        let perRow = Int(buffer.width) * Format.channelCount
        let rows = Int(buffer.height)
        guard perRow > 0, rows > 0, let data = buffer.data else { return [] }
        return [Format.ComponentType](unsafeUninitializedCapacity: perRow * rows) { out, initialized in
            for row in 0..<rows {
                let source = (data + row * buffer.rowBytes).assumingMemoryBound(to: Format.ComponentType.self)
                (out.baseAddress! + row * perRow).initialize(from: source, count: perRow)
            }
            initialized = perRow * rows
        }
    }

    /// Writes components given row after row into the buffer.
    func _store(_ values: UnsafeBufferPointer<Format.ComponentType>) {
        let buffer = _vImageBuffers[0]
        let perRow = Int(buffer.width) * Format.channelCount
        let rows = Int(buffer.height)
        guard perRow > 0, rows > 0, let data = buffer.data, let base = values.baseAddress else { return }
        precondition(values.count >= perRow * rows, "too few pixel values for the buffer")
        for row in 0..<rows {
            let destination = (data + row * buffer.rowBytes).assumingMemoryBound(to: Format.ComponentType.self)
            destination.update(from: base + row * perRow, count: perRow)
        }
    }
}

/// The memory of a buffer pointer and its size in bytes; a buffer without
/// memory gets a byte of its own, so a pixel buffer can still be made over it.
func _vImageWithRawBuffer<T, R>(_ pointer: UnsafeMutableBufferPointer<T>, _ body: (UnsafeMutableRawPointer, Int) throws -> R) rethrows -> R {
    if let base = pointer.baseAddress {
        return try body(UnsafeMutableRawPointer(base), pointer.count * MemoryLayout<T>.stride)
    }
    let placeholder = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 16)
    defer { placeholder.deallocate() }
    return try body(placeholder, 0)
}

/// The CGImage format makePixelBufferAndCGImageFormat gives a pixel format:
/// its component and pixel sizes, the image's color space when it has the
/// format's channel count (else device gray or sRGB), alpha first for four
/// channels (premultiplied when the image's is), and the host's byte order.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func _vImageCGImageFormat<F: InitializableFromCGImage & StaticPixelFormat>(for format: F.Type, matching image: CGImage) throws -> vImage_CGImageFormat {
    let channels = F.channelCount
    let bits = F.bitCountPerComponent
    let colorChannels = channels >= 3 ? 3 : 1
    var colorSpace: CGColorSpace
    if let own = image.colorSpace, own.numberOfComponents == colorChannels {
        colorSpace = own
    } else {
        colorSpace = colorChannels == 1 ? CGColorSpaceCreateDeviceGray() : CGColorSpace(name: CGColorSpace.sRGB)!
    }
    var alpha: CGImageAlphaInfo
    switch channels {
    case 2, 4:
        switch image.alphaInfo {
        case .premultipliedFirst, .premultipliedLast: alpha = .premultipliedFirst
        case .first, .last, .alphaOnly: alpha = .first
        default: alpha = .noneSkipFirst
        }
        if channels == 2 { alpha = alpha == .noneSkipFirst ? .noneSkipFirst : alpha }
    default:
        alpha = .none
    }
    var info = CGBitmapInfo(rawValue: alpha.rawValue)
    switch bits {
    case 32: info.formUnion([.floatComponents, .byteOrder32Little])
    case 16:
        info.formUnion(.byteOrder16Little)
        if F.ComponentType.self == Pixel_16F.self && F.self != vImage.Interleaved16Ux2.self && F.self != vImage.Interleaved16Ux4.self {
            info.formUnion(.floatComponents)
        }
    default: break
    }
    guard let result = vImage_CGImageFormat(bitsPerComponent: bits, bitsPerPixel: F.bitCountPerPixel, colorSpace: colorSpace, bitmapInfo: info) else {
        throw vImage.Error.invalidImageFormat
    }
    return result
}

/// Calls `body` with a pointer to the components of a background pixel
/// (the default one when `color` is nil) and whether a color was given;
/// vImage takes multi-channel pixels (Pixel_8888, Pixel_FFFF...) by pointer.
func _vImageWithBackground<P, C, R>(_ color: P?, _ zero: P, as component: C.Type, _ body: (UnsafePointer<C>, Bool) -> R) -> R {
    var pixel = color ?? zero
    return withUnsafeBytes(of: &pixel) { bytes in
        body(bytes.bindMemory(to: C.self).baseAddress!, color != nil)
    }
}

/// The flags for a geometry operation's edges: fill with the background
/// color when there is one, extend the edges otherwise.
func _vImageEdgeFlags(hasBackground: Bool, useFloat16Accumulator: Bool = false) -> vImage_Flags {
    var flags = vImage_Flags(hasBackground ? kvImageBackgroundColorFill : kvImageEdgeExtend)
    if useFloat16Accumulator { flags |= vImage_Flags(kvImageUseFP16Accumulator) }
    return flags
}

/// Runs a vImage function on each plane of a source and a destination.
func _vImageEachPlane(_ sources: [vImage_Buffer], _ destinations: [vImage_Buffer],
                      _ function: (UnsafePointer<vImage_Buffer>, UnsafePointer<vImage_Buffer>) -> vImage_Error) {
    precondition(sources.count == destinations.count, "the source and destination must have the same planes")
    for (source, destination) in zip(sources, destinations) {
        _vImageCheckSizes(source, destination)
        _vImageRun(source, destination, function)
    }
}

/// The flags of an edge mode plus extra ones.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func _vImageFlags<P>(_ edgeMode: vImage.EdgeMode<P>, _ extra: vImage_Flags = 0) -> vImage_Flags {
    edgeMode.vImageFlags | extra
}

/// Pointers to each of a set of buffers, for the vImage functions that take
/// arrays of planes.
func _vImageWithBufferPointers<R>(_ buffers: [vImage_Buffer], _ body: (UnsafeMutablePointer<UnsafePointer<vImage_Buffer>?>) -> R) -> R {
    let storage = UnsafeMutablePointer<vImage_Buffer>.allocate(capacity: max(buffers.count, 1))
    storage.initialize(from: buffers, count: buffers.count)
    defer { storage.deinitialize(count: buffers.count); storage.deallocate() }
    var pointers: [UnsafePointer<vImage_Buffer>?] = (0..<buffers.count).map { UnsafePointer(storage + $0) }
    return pointers.withUnsafeMutableBufferPointer { body($0.baseAddress!) }
}

func _vImageInt16(_ value: Int) -> Int16 { Int16(clamping: value) }
func _vImageInt32(_ value: Int) -> Int32 { Int32(clamping: value) }

/// vImage's copy mask of channel indices: 0x8 for the first channel, 0x1 for the fourth.
func _vImageCopyMask(_ channels: [UInt8]) -> UInt8 {
    channels.reduce(UInt8(0)) { mask, channel in
        precondition(channel < 4, "channel indices go from 0 to 3")
        return mask | (0x8 >> channel)
    }
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.Gamma {
    /// The gamma value and the vImageCreateGammaFunction type of the case.
    var _function: (Float, Int32) {
        switch self {
        case .fullPrecision(let value): return (value, Int32(kvImageGamma_UseGammaValue))
        case .halfPrecision(let value): return (value, Int32(kvImageGamma_UseGammaValue_half_precision))
        case .fiveOverNineHalfPrecision: return (0, Int32(kvImageGamma_5_over_9_half_precision))
        case .nineOverFiveHalfPrecision: return (0, Int32(kvImageGamma_9_over_5_half_precision))
        case .fiveOverElevenHalfPrecision: return (0, Int32(kvImageGamma_5_over_11_half_precision))
        case .elevenOverFiveHalfPrecision: return (0, Int32(kvImageGamma_11_over_5_half_precision))
        case .sRGBForwardHalfPrecision: return (0, Int32(kvImageGamma_sRGB_forward_half_precision))
        case .sRGBReverseHalfPrecision: return (0, Int32(kvImageGamma_sRGB_reverse_half_precision))
        case .elevenOverNineHalfPrecision: return (0, Int32(kvImageGamma_11_over_9_half_precision))
        case .nineOverElevenHalfPrecision: return (0, Int32(kvImageGamma_9_over_11_half_precision))
        case .bt709ForwardHalfPrecision: return (0, Int32(kvImageGamma_BT709_forward_half_precision))
        case .bt709ReverseHalfPrecision: return (0, Int32(kvImageGamma_BT709_reverse_half_precision))
        }
    }

    func _withFunction<R>(_ body: (GammaFunction) -> R) -> R {
        let (value, type) = _function
        let function = vImageCreateGammaFunction(value, type, vImage_Flags(kvImageNoFlags))!
        defer { vImageDestroyGammaFunction(function) }
        return body(function)
    }
}

/// Runs a function over each element of float buffers of the same size
/// (all channels), for the operations vImage has no function for.
func _vImageMapFloats(_ sources: [vImage_Buffer], into destination: vImage_Buffer, components: Int, _ transform: ([Float]) -> Float) {
    let width = Int(destination.width) * components
    for y in 0..<Int(destination.height) {
        let out = (destination.data! + y * destination.rowBytes).assumingMemoryBound(to: Float.self)
        let rows = sources.map { ($0.data! + y * $0.rowBytes).assumingMemoryBound(to: Float.self) }
        for x in 0..<width { out[x] = transform(rows.map { $0[x] }) }
    }
}

/// Fills `count` histograms of `entries` bins each through a vImage
/// function that takes an array of histogram pointers.
func _vImageHistograms(count: Int, entries: Int, _ body: (UnsafeMutablePointer<UnsafeMutablePointer<vImagePixelCount>?>) -> vImage_Error) -> [[vImagePixelCount]] {
    let storage = UnsafeMutablePointer<vImagePixelCount>.allocate(capacity: count * entries)
    storage.initialize(repeating: 0, count: count * entries)
    defer { storage.deallocate() }
    var pointers: [UnsafeMutablePointer<vImagePixelCount>?] = (0..<count).map { storage + $0 * entries }
    _ = pointers.withUnsafeMutableBufferPointer { body($0.baseAddress!) }
    return (0..<count).map { Array(UnsafeBufferPointer(start: storage + $0 * entries, count: entries)) }
}

/// Calls `body` with an array of pointers to the histograms given.
func _vImageWithHistograms<R>(_ histograms: [[vImagePixelCount]], _ body: (UnsafeMutablePointer<UnsafePointer<vImagePixelCount>?>) -> R) -> R {
    let flat = histograms.flatMap { $0 }
    return flat.withUnsafeBufferPointer { all in
        var offset = 0
        var pointers = [UnsafePointer<vImagePixelCount>?]()
        for histogram in histograms {
            pointers.append(all.baseAddress.map { $0 + offset })
            offset += histogram.count
        }
        return pointers.withUnsafeMutableBufferPointer { body($0.baseAddress!) }
    }
}

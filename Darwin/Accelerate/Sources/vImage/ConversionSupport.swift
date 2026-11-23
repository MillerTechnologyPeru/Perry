import Darwin

// Conversions between component types, and between planar and interleaved
// layouts, as the PixelBuffer API's convert/interleave/deinterleave
// methods use them. An interleaved buffer converts as a planar buffer of
// its components (width times the channel count wide).

enum _vImageComponent {
    case uint8, uint16, float16, float32

    var size: Int {
        switch self {
        case .uint8: return 1
        case .uint16, .float16: return 2
        case .float32: return 4
        }
    }
}

/// Converts each component of `source` into `destination`, both of
/// `components` components per pixel: 8-bit and 16-bit integers stand for
/// 0...1, floating point values are clamped to it on the way to integers.
func _vImageConvertComponents(_ source: vImage_Buffer, _ from: _vImageComponent,
                              _ destination: vImage_Buffer, _ to: _vImageComponent, components: Int) {
    _vImageCheckSizes(source, destination)
    let s = _vImageWidened(source, by: components)
    let d = _vImageWidened(destination, by: components)
    let flags = vImage_Flags(kvImageNoFlags)
    _vImageRun(s, d) { src, dst in
        switch (from, to) {
        case (.uint8, .float32): return vImageConvert_Planar8toPlanarF(src, dst, 1, 0, flags)
        case (.float32, .uint8): return vImageConvert_PlanarFtoPlanar8(src, dst, 1, 0, flags)
        case (.uint8, .uint16): return vImageConvert_Planar8To16U(src, dst, flags)
        case (.uint16, .uint8): return vImageConvert_16UToPlanar8(src, dst, flags)
        case (.uint8, .float16): return vImageConvert_Planar8toPlanar16F(src, dst, flags)
        case (.float16, .uint8): return vImageConvert_Planar16FtoPlanar8(src, dst, flags)
        case (.uint16, .float32): return vImageConvert_16UToF(src, dst, 0, 1.0 / 65535, flags)
        case (.float32, .uint16): return vImageConvert_FTo16U(src, dst, 0, 1.0 / 65535, flags)
        case (.float16, .float32): return vImageConvert_Planar16FtoPlanarF(src, dst, flags)
        case (.float32, .float16): return vImageConvert_PlanarFtoPlanar16F(src, dst, flags)
        case (.uint16, .float16): return vImageConvert_16Uto16F(src, dst, flags)
        case (.float16, .uint16): return vImageConvert_16Fto16U(src, dst, flags)
        default:
            return vImageCopyBuffer(src, UnsafeMutablePointer(mutating: dst), from.size, flags)
        }
    }
}

/// Interleaves planar buffers of `componentSize`-byte components into one
/// buffer of as many channels.
func _vImageInterleave(_ planes: [vImage_Buffer], into destination: vImage_Buffer, componentSize: Int) {
    for plane in planes { _vImageCheckSizes(plane, destination) }
    let channels = planes.count
    let width = Int(destination.width)
    let height = Int(destination.height)
    guard width > 0, height > 0, channels > 0 else { return }
    for y in 0..<height {
        let row = destination.data! + y * destination.rowBytes
        for (c, plane) in planes.enumerated() {
            let source = plane.data! + y * plane.rowBytes
            for x in 0..<width {
                (row + (x * channels + c) * componentSize).copyMemory(from: source + x * componentSize, byteCount: componentSize)
            }
        }
    }
}

/// Splits an interleaved buffer into planar buffers, one per channel.
func _vImageDeinterleave(_ source: vImage_Buffer, into planes: [vImage_Buffer], componentSize: Int) {
    for plane in planes { _vImageCheckSizes(plane, source) }
    let channels = planes.count
    let width = Int(source.width)
    let height = Int(source.height)
    guard width > 0, height > 0, channels > 0 else { return }
    for y in 0..<height {
        let row = source.data! + y * source.rowBytes
        for (c, plane) in planes.enumerated() {
            let destination = plane.data! + y * plane.rowBytes
            for x in 0..<width {
                (destination + x * componentSize).copyMemory(from: row + (x * channels + c) * componentSize, byteCount: componentSize)
            }
        }
    }
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format: StaticPixelFormat {
    var _componentKind: _vImageComponent {
        let bits = Format.bitCountPerPixel / Format.channelCount
        switch bits {
        case 8: return .uint8
        case 32: return .float32
        default:
            let isHalf = Format.self == vImage.Planar16F.self || Format.self == vImage.Interleaved16Fx2.self || Format.self == vImage.Interleaved16Fx4.self
            return isHalf ? .float16 : .uint16
        }
    }

    /// Converts the components into a buffer of another component type and the same channels.
    func _convertComponents<D: StaticPixelFormat>(to destination: vImage.PixelBuffer<D>) {
        precondition(Format.channelCount == D.channelCount, "the buffers must have the same channels")
        _vImageConvertComponents(_vImageBuffers[0], _componentKind, destination._vImageBuffers[0], destination._componentKind, components: Format.channelCount)
    }

    /// Splits the buffer into new planar buffers of the planar format given.
    func _planarBuffers<P: StaticPixelFormat>(_ planar: P.Type) -> [vImage.PixelBuffer<P>] {
        let planes = (0..<Format.channelCount).map { _ in vImage.PixelBuffer<P>(width: width, height: height) }
        _deinterleave(into: planes.map { $0._vImageBuffers[0] }, as: P.self)
        return planes
    }

    /// Splits the buffer into planar buffers, converting the components if their type differs.
    func _deinterleave<P: StaticPixelFormat>(into planes: [vImage_Buffer], as planar: P.Type) {
        precondition(planes.count == Format.channelCount, "a \(Format.self) buffer splits into \(Format.channelCount) planar buffers")
        let componentBits = Format.bitCountPerPixel / Format.channelCount
        if componentBits == P.bitCountPerPixel {
            _vImageDeinterleave(_vImageBuffers[0], into: planes, componentSize: componentBits / 8)
            return
        }
        let own = planes.map { _ in _vImageAllocateBuffer(width: width, height: height, bitsPerPixel: componentBits) }
        defer { own.forEach { Darwin.free($0.data) } }
        _vImageDeinterleave(_vImageBuffers[0], into: own, componentSize: componentBits / 8)
        let target = vImage.PixelBuffer<P>(_buffers: [planes[0]], storage: nil)._componentKind
        for (source, plane) in zip(own, planes) {
            _vImageConvertComponents(source, _componentKind, plane, target, components: 1)
        }
    }

    /// Interleaves planar buffers into this one, converting the components if their type differs.
    func _interleave<P: StaticPixelFormat>(_ planes: [vImage.PixelBuffer<P>]) {
        precondition(planes.count == Format.channelCount, "a \(Format.self) buffer interleaves \(Format.channelCount) planar buffers")
        let componentBits = Format.bitCountPerPixel / Format.channelCount
        if componentBits == P.bitCountPerPixel {
            _vImageInterleave(planes.map { $0._vImageBuffers[0] }, into: _vImageBuffers[0], componentSize: componentBits / 8)
            return
        }
        let own = planes.map { _ in _vImageAllocateBuffer(width: width, height: height, bitsPerPixel: componentBits) }
        defer { own.forEach { Darwin.free($0.data) } }
        for (plane, target) in zip(planes, own) {
            _vImageConvertComponents(plane._vImageBuffers[0], plane._componentKind, target, _componentKind, components: 1)
        }
        _vImageInterleave(own, into: _vImageBuffers[0], componentSize: componentBits / 8)
    }

    /// A new buffer of the size of this one, made from planar buffers.
    init<P: StaticPixelFormat>(_interleaving planes: [vImage.PixelBuffer<P>]) {
        precondition(!planes.isEmpty, "no planar buffers")
        self.init(width: planes[0].width, height: planes[0].height)
        _interleave(planes)
    }
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format: MultiplePlanePixelFormat {
    /// Fills the planes from an interleaved buffer of as many channels.
    func _deinterleave<I: StaticPixelFormat>(from source: vImage.PixelBuffer<I>) {
        source._deinterleave(into: _vImageBuffers, as: Format.PlanarPixelFormat.self)
    }

    /// Interleaves the planes into a buffer of as many channels.
    func _interleave<I: StaticPixelFormat>(into destination: vImage.PixelBuffer<I>) {
        destination._interleave(pixelBuffers)
    }
}

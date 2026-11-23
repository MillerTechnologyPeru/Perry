import Swift
import _Concurrency
import _StringProcessing
import _SwiftConcurrencyShims
import simd
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.InterleavedFx2 {
  public init(planarBuffers: [vImage.PixelBuffer<vImage.PlanarF>]) {
    self.init(_interleaving: planarBuffers)
  }
  public func planarBuffers() -> [vImage.PixelBuffer<vImage.PlanarF>] {
    return _planarBuffers(vImage.PlanarF.self)
  }
  public func convert(to destination: vImage.PixelBuffer<vImage.Interleaved16Fx2>) {
    _convertComponents(to: destination)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.PlanarFx3 {
  public init(interleavedBuffer: vImage.PixelBuffer<vImage.InterleavedFx3>) {
    self.init(size: interleavedBuffer.size)
    _deinterleave(from: interleavedBuffer)
  }
  public func convert(to destination: vImage.PixelBuffer<vImage.InterleavedFx3>) {
    _interleave(into: destination)
  }
  public func interleave(destination: vImage.PixelBuffer<vImage.InterleavedFx3>) {
    _interleave(into: destination)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar8 {
  public func applyPolynomial(coefficientSegments: [[Float]], boundaries: [Float], destination: vImage.PixelBuffer<vImage.PlanarF>) {
    _applyPolynomial(coefficientSegments: coefficientSegments, boundaries: boundaries, destination: destination, polynomialFunc: vImagePiecewisePolynomial_Planar8toPlanarF, widthMultiplier: 1)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved8x2 {
  public func applyPolynomial(coefficientSegments: [[Float]], boundaries: [Float], destination: vImage.PixelBuffer<vImage.InterleavedFx2>) {
    _applyPolynomial(coefficientSegments: coefficientSegments, boundaries: boundaries, destination: destination, polynomialFunc: vImagePiecewisePolynomial_Planar8toPlanarF, widthMultiplier: 2)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved8x3 {
  public func applyPolynomial(coefficientSegments: [[Float]], boundaries: [Float], destination: vImage.PixelBuffer<vImage.InterleavedFx3>) {
    _applyPolynomial(coefficientSegments: coefficientSegments, boundaries: boundaries, destination: destination, polynomialFunc: vImagePiecewisePolynomial_Planar8toPlanarF, widthMultiplier: 3)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved8x4 {
  public func applyPolynomial(coefficientSegments: [[Float]], boundaries: [Float], destination: vImage.PixelBuffer<vImage.InterleavedFx4>) {
    _applyPolynomial(coefficientSegments: coefficientSegments, boundaries: boundaries, destination: destination, polynomialFunc: vImagePiecewisePolynomial_Planar8toPlanarF, widthMultiplier: 4)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.PlanarF {
  public func applyPolynomial(coefficientSegments: [[Float]], boundaries: [Float], destination: vImage.PixelBuffer<Format>) {
    _applyPolynomial(coefficientSegments: coefficientSegments, boundaries: boundaries, destination: destination, polynomialFunc: vImagePiecewisePolynomial_PlanarF, widthMultiplier: 1)
  }
  public func applyPolynomial(coefficientSegments: [[Float]], boundaries: [Float], destination: vImage.PixelBuffer<vImage.Planar8>) {
    _applyPolynomial(coefficientSegments: coefficientSegments, boundaries: boundaries, destination: destination, polynomialFunc: vImagePiecewisePolynomial_PlanarFtoPlanar8, widthMultiplier: 1)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.InterleavedFx2 {
  public func applyPolynomial(coefficientSegments: [[Float]], boundaries: [Float], destination: vImage.PixelBuffer<Format>) {
    _applyPolynomial(coefficientSegments: coefficientSegments, boundaries: boundaries, destination: destination, polynomialFunc: vImagePiecewisePolynomial_PlanarF, widthMultiplier: 2)
  }
  public func applyPolynomial(coefficientSegments: [[Float]], boundaries: [Float], destination: vImage.PixelBuffer<vImage.Interleaved8x2>) {
    _applyPolynomial(coefficientSegments: coefficientSegments, boundaries: boundaries, destination: destination, polynomialFunc: vImagePiecewisePolynomial_PlanarFtoPlanar8, widthMultiplier: 2)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.InterleavedFx3 {
  public func applyPolynomial(coefficientSegments: [[Float]], boundaries: [Float], destination: vImage.PixelBuffer<Format>) {
    _applyPolynomial(coefficientSegments: coefficientSegments, boundaries: boundaries, destination: destination, polynomialFunc: vImagePiecewisePolynomial_PlanarF, widthMultiplier: 3)
  }
  public func applyPolynomial(coefficientSegments: [[Float]], boundaries: [Float], destination: vImage.PixelBuffer<vImage.Interleaved8x3>) {
    _applyPolynomial(coefficientSegments: coefficientSegments, boundaries: boundaries, destination: destination, polynomialFunc: vImagePiecewisePolynomial_PlanarFtoPlanar8, widthMultiplier: 3)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.InterleavedFx4 {
  public func applyPolynomial(coefficientSegments: [[Float]], boundaries: [Float], destination: vImage.PixelBuffer<Format>) {
    _applyPolynomial(coefficientSegments: coefficientSegments, boundaries: boundaries, destination: destination, polynomialFunc: vImagePiecewisePolynomial_PlanarF, widthMultiplier: 4)
  }
  public func applyPolynomial(coefficientSegments: [[Float]], boundaries: [Float], destination: vImage.PixelBuffer<vImage.Interleaved8x4>) {
    _applyPolynomial(coefficientSegments: coefficientSegments, boundaries: boundaries, destination: destination, polynomialFunc: vImagePiecewisePolynomial_PlanarFtoPlanar8, widthMultiplier: 4)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : StaticPixelFormat {
  @usableFromInline
  internal typealias PiecewisePolynomialFunc = (UnsafePointer<vImage_Buffer>, UnsafePointer<vImage_Buffer>, UnsafeMutablePointer<UnsafePointer<Float>?>, UnsafePointer<Float>, UInt32, UInt32, vImage_Flags) -> vImage_Error
  @usableFromInline
  internal func _applyPolynomial<T>(coefficientSegments: [[Float]], boundaries: [Float], destination: vImage.PixelBuffer<T>, polynomialFunc: vImage.PixelBuffer<Format>.PiecewisePolynomialFunc, widthMultiplier: Int) where T : SinglePlanePixelFormat {
    let segments = coefficientSegments.count
    precondition(segments > 0 && segments & (segments - 1) == 0, "the number of polynomial segments must be a power of two")
    precondition(boundaries.count == segments + 1, "there must be one more boundary than segments")
    let order = coefficientSegments[0].count - 1
    precondition(order >= 0 && coefficientSegments.allSatisfy { $0.count == order + 1 }, "the segments must have the same number of coefficients")
    let log2Segments = UInt32(segments.trailingZeroBitCount)
    let flat = coefficientSegments.flatMap { $0 }
    flat.withUnsafeBufferPointer { coefficients in
      var pointers: [UnsafePointer<Float>?] = (0..<segments).map { coefficients.baseAddress! + $0 * (order + 1) }
      boundaries.withUnsafeBufferPointer { bounds in
        _vImageRun(_vImageWidened(_vImageBuffers[0], by: widthMultiplier), _vImageWidened(destination._vImageBuffers[0], by: widthMultiplier)) {
          polynomialFunc($0, $1, &pointers, bounds.baseAddress!, UInt32(order), log2Segments, vImage_Flags(kvImageNoFlags))
        }
      }
    }
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension vImage {
  public struct Options : OptionSet {
    public init(rawValue: vImage_Flags) {
      self.rawValue = rawValue
    }
    public let rawValue: vImage_Flags
    public static let noFlags: vImage.Options = vImage.Options(rawValue: vImage_Flags(kvImageNoFlags))
    public static let leaveAlphaUnchanged: vImage.Options = vImage.Options(rawValue: vImage_Flags(kvImageLeaveAlphaUnchanged))
    public static let copyInPlace: vImage.Options = vImage.Options(rawValue: vImage_Flags(kvImageCopyInPlace))
    public static let backgroundColorFill: vImage.Options = vImage.Options(rawValue: vImage_Flags(kvImageBackgroundColorFill))
    public static let imageExtend: vImage.Options = vImage.Options(rawValue: vImage_Flags(kvImageEdgeExtend))
    public static let doNotTile: vImage.Options = vImage.Options(rawValue: vImage_Flags(kvImageDoNotTile))
    public static let highQualityResampling: vImage.Options = vImage.Options(rawValue: vImage_Flags(kvImageHighQualityResampling))
    public static let truncateKernel: vImage.Options = vImage.Options(rawValue: vImage_Flags(kvImageTruncateKernel))
    public static let getTempBufferSize: vImage.Options = vImage.Options(rawValue: vImage_Flags(kvImageGetTempBufferSize))
    public static let printDiagnosticsToConsole: vImage.Options = vImage.Options(rawValue: vImage_Flags(kvImagePrintDiagnosticsToConsole))
    public static let noAllocate: vImage.Options = vImage.Options(rawValue: vImage_Flags(kvImageNoAllocate))
    public static let hdrContent: vImage.Options = vImage.Options(rawValue: vImage_Flags(kvImageHDRContent))
    public static let doNotClamp: vImage.Options = vImage.Options(rawValue: vImage_Flags(kvImageDoNotClamp))
    public var flags: vImage_Flags {
      get { rawValue }
    }
    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    public typealias ArrayLiteralElement = vImage.Options
    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    public typealias Element = vImage.Options
    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    public typealias RawValue = vImage_Flags
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : MultiplePlanePixelFormat, Format.ComponentType == UInt8 {
  public func multiply<Matrix, DestFormat>(by matrix: Matrix, divisor: Int, preBias: [Int], postBias: [Int], destination: vImage.PixelBuffer<DestFormat>) where Matrix : AccelerateBuffer, DestFormat : MultiplePlanePixelFormat, Matrix.Element == Int, DestFormat.ComponentType == UInt8 {
    precondition(matrix.count == Format.planeCount * DestFormat.planeCount, "the matrix needs source x destination planes elements")
    let m = matrix.withUnsafeBufferPointer { $0.map(_vImageInt16) }
    var pre = preBias.map(_vImageInt16)
    var post = postBias.map(_vImageInt32)
    _vImageWithBufferPointers(_vImageBuffers) { sources in
      _vImageWithBufferPointers(destination._vImageBuffers) { destinations in
        _ = pre.withUnsafeBufferPointer { p in
          post.withUnsafeBufferPointer { q in
            vImageMatrixMultiply_Planar8(sources, destinations, UInt32(Format.planeCount), UInt32(DestFormat.planeCount), m, _vImageInt32(divisor),
                 p.isEmpty ? nil : p.baseAddress, q.isEmpty ? nil : q.baseAddress, vImage_Flags(kvImageNoFlags))
          }
        }
      }
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : MultiplePlanePixelFormat, Format.ComponentType == Float {
  public func multiply<Matrix, DestFormat>(by matrix: Matrix, preBias: [Float], postBias: [Float], destination: vImage.PixelBuffer<DestFormat>) where Matrix : AccelerateBuffer, DestFormat : MultiplePlanePixelFormat, Matrix.Element == Float, DestFormat.ComponentType == Float {
    precondition(matrix.count == Format.planeCount * DestFormat.planeCount, "the matrix needs source x destination planes elements")
    let m = matrix.withUnsafeBufferPointer { Array($0) }
    var pre = preBias
    var post = postBias
    _vImageWithBufferPointers(_vImageBuffers) { sources in
      _vImageWithBufferPointers(destination._vImageBuffers) { destinations in
        _ = pre.withUnsafeBufferPointer { p in
          post.withUnsafeBufferPointer { q in
            vImageMatrixMultiply_PlanarF(sources, destinations, UInt32(Format.planeCount), UInt32(DestFormat.planeCount), m,
                 p.isEmpty ? nil : p.baseAddress, q.isEmpty ? nil : q.baseAddress, vImage_Flags(kvImageNoFlags))
          }
        }
      }
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar8 {
  public func multiply(by factor: Int, divisor: Int, preBias: Int, postBias: Int, destination: vImage.PixelBuffer<vImage.Planar8>) {
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    var m = [_vImageInt16(factor)]
    var pre = [_vImageInt16(preBias)]
    var post = [_vImageInt32(postBias)]
    _vImageWithBufferPointers(_vImageBuffers) { sources in
      _vImageWithBufferPointers(destination._vImageBuffers) { destinations in
        _ = vImageMatrixMultiply_Planar8(sources, destinations, 1, 1, &m, _vImageInt32(divisor), &pre, &post, vImage_Flags(kvImageNoFlags))
      }
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved8x4 {
  public func multiply(by matrix: (Int, Int, Int, Int), divisor: Int, preBias: (Int, Int, Int, Int), postBias: Int, destination: vImage.PixelBuffer<vImage.Planar8>) {
    var m = [matrix.0, matrix.1, matrix.2, matrix.3].map(_vImageInt16)
    var pre = [preBias.0, preBias.1, preBias.2, preBias.3].map(_vImageInt16)
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) {
      vImageMatrixMultiply_ARGB8888ToPlanar8($0, $1, &m, _vImageInt32(divisor), &pre, _vImageInt32(postBias), vImage_Flags(kvImageNoFlags))
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved8x4 {
  public func multiply<Matrix>(by matrix: Matrix, divisor: Int, preBias: (Int, Int, Int, Int), postBias: (Int, Int, Int, Int), destination: vImage.PixelBuffer<vImage.Interleaved8x4>) where Matrix : AccelerateBuffer, Matrix.Element == Int {
    precondition(matrix.count == 16, "the matrix needs 16 elements")
    var m = matrix.withUnsafeBufferPointer { $0.map(_vImageInt16) }
    var pre = [preBias.0, preBias.1, preBias.2, preBias.3].map(_vImageInt16)
    var post = [postBias.0, postBias.1, postBias.2, postBias.3].map(_vImageInt32)
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) {
      vImageMatrixMultiply_ARGB8888($0, $1, &m, _vImageInt32(divisor), &pre, &post, vImage_Flags(kvImageNoFlags))
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.PlanarF {
  public func multiply(by factor: Float, preBias: Float, postBias: Float, destination: vImage.PixelBuffer<vImage.PlanarF>) {
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    var m = [factor]
    var pre = [preBias]
    var post = [postBias]
    _vImageWithBufferPointers(_vImageBuffers) { sources in
      _vImageWithBufferPointers(destination._vImageBuffers) { destinations in
        _ = vImageMatrixMultiply_PlanarF(sources, destinations, 1, 1, &m, &pre, &post, vImage_Flags(kvImageNoFlags))
      }
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.InterleavedFx4 {
  public func multiply(by matrix: (Float, Float, Float, Float), preBias: (Float, Float, Float, Float), postBias: Float, destination: vImage.PixelBuffer<vImage.PlanarF>) {
    var m = [matrix.0, matrix.1, matrix.2, matrix.3]
    var pre = [preBias.0, preBias.1, preBias.2, preBias.3]
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) {
      vImageMatrixMultiply_ARGBFFFFToPlanarF($0, $1, &m, &pre, postBias, vImage_Flags(kvImageNoFlags))
    }
  }
  public func multiply<Matrix>(by matrix: Matrix, preBias: (Float, Float, Float, Float), postBias: (Float, Float, Float, Float), destination: vImage.PixelBuffer<vImage.InterleavedFx4>) where Matrix : AccelerateBuffer, Matrix.Element == Float {
    precondition(matrix.count == 16, "the matrix needs 16 elements")
    var m = matrix.withUnsafeBufferPointer { Array($0) }
    var pre = [preBias.0, preBias.1, preBias.2, preBias.3]
    var post = [postBias.0, postBias.1, postBias.2, postBias.3]
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) {
      vImageMatrixMultiply_ARGBFFFF($0, $1, &m, &pre, &post, vImage_Flags(kvImageNoFlags))
    }
  }
  public func multiply(by matrix: simd_float4x4, preBias: (Float, Float, Float, Float), postBias: (Float, Float, Float, Float), destination: vImage.PixelBuffer<vImage.InterleavedFx4>) {
    // A pixel is a row vector times the matrix: element [input][output], the matrix's columns in turn.
    let elements = [matrix.columns.0, matrix.columns.1, matrix.columns.2, matrix.columns.3].flatMap { [$0.x, $0.y, $0.z, $0.w] }
    multiply(by: elements, preBias: preBias, postBias: postBias, destination: destination)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved8x4 {
  public func extractChannel(at channelIndex: Int, destination: vImage.PixelBuffer<vImage.Planar8>) {
    _extractChannel(channelIndex: channelIndex, destination: destination, extractFunc: vImageExtractChannel_ARGB8888)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.InterleavedFx4 {
  public func extractChannel(at channelIndex: Int, destination: vImage.PixelBuffer<vImage.PlanarF>) {
    _extractChannel(channelIndex: channelIndex, destination: destination, extractFunc: vImageExtractChannel_ARGBFFFF)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved16Ux4 {
  public func extractChannel(at channelIndex: Int, destination: vImage.PixelBuffer<vImage.Planar16U>) {
    _extractChannel(channelIndex: channelIndex, destination: destination, extractFunc: vImageExtractChannel_ARGB16U)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : StaticPixelFormat {
  @usableFromInline
  internal typealias ExtractFunc = (UnsafePointer<vImage_Buffer>, UnsafePointer<vImage_Buffer>, Int, vImage_Flags) -> vImage_Error
  @usableFromInline
  internal func _extractChannel<T>(channelIndex: Int, destination: vImage.PixelBuffer<T>, extractFunc: vImage.PixelBuffer<Format>.ExtractFunc) where T : StaticPixelFormat {
    precondition(channelIndex >= 0 && channelIndex < Format.channelCount, "channel index out of range")
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { extractFunc($0, $1, channelIndex, vImage_Flags(kvImageNoFlags)) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved8x4 {
  public func flatten(channelOrdering: vImage.ChannelOrdering, backgroundColor: Pixel_8888, isPremultiplied: Bool, destination: vImage.PixelBuffer<vImage.Interleaved8x3>) {
    _vImageWithBackground(backgroundColor, backgroundColor, as: UInt8.self) { background, _ in
      _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) {
        channelOrdering == .ARGB
          ? vImageFlatten_ARGB8888ToRGB888($0, $1, background, isPremultiplied, vImage_Flags(kvImageNoFlags))
          : vImageFlatten_RGBA8888ToRGB888($0, $1, background, isPremultiplied, vImage_Flags(kvImageNoFlags))
      }
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.InterleavedFx4 {
  public func flatten(channelOrdering: vImage.ChannelOrdering, backgroundColor: Pixel_FFFF, isPremultiplied: Bool, destination: vImage.PixelBuffer<vImage.InterleavedFx3>) {
    _vImageWithBackground(backgroundColor, backgroundColor, as: Float.self) { background, _ in
      _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) {
        channelOrdering == .ARGB
          ? vImageFlatten_ARGBFFFFToRGBFFF($0, $1, background, isPremultiplied, vImage_Flags(kvImageNoFlags))
          : vImageFlatten_RGBAFFFFToRGBFFF($0, $1, background, isPremultiplied, vImage_Flags(kvImageNoFlags))
      }
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage {
  public enum ChannelOrdering : Equatable, Hashable {
    case ARGB
    case RGBA
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved16Fx2 {
  public func convert(to destination: vImage.PixelBuffer<vImage.Interleaved8x2>) {
    _convertComponents(to: destination)
  }
  public func convert(to destination: vImage.PixelBuffer<vImage.Interleaved16Ux2>) {
    _convertComponents(to: destination)
  }
  public func convert(to destination: vImage.PixelBuffer<vImage.InterleavedFx2>) {
    _convertComponents(to: destination)
  }
}
@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension vImage {
  public enum FloodFillConnectivity : Int32, Equatable, Hashable {
    case edges
    case edgesAndCorners
    public init?(rawValue: Int32) {
      switch rawValue {
      case 4: self = .edges
      case 8: self = .edgesAndCorners
      default: return nil
      }
    }
    @available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
    public typealias RawValue = Int32
    public var rawValue: Int32 {
      get {
        switch self {
        case .edges: return 4
        case .edgesAndCorners: return 8
        }
      }
    }
  }
}
@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar8 {
  public func floodFill(from seed: CGPoint, newColor: Pixel_8, connectivity: vImage.FloodFillConnectivity) {
    precondition(seed.x >= 0 && seed.y >= 0 && Int(seed.x) < width && Int(seed.y) < height, "the seed must lie within the buffer")
    var buffer = _vImageBuffers[0]
    _ = vImageFloodFill_Planar8(&buffer, nil, vImagePixelCount(seed.x), vImagePixelCount(seed.y), newColor, Int32(connectivity.rawValue), vImage_Flags(kvImageNoFlags))
  }
}
@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar16U {
  public func floodFill(from seed: CGPoint, newColor: Pixel_16U, connectivity: vImage.FloodFillConnectivity) {
    precondition(seed.x >= 0 && seed.y >= 0 && Int(seed.x) < width && Int(seed.y) < height, "the seed must lie within the buffer")
    var buffer = _vImageBuffers[0]
    _ = vImageFloodFill_Planar16U(&buffer, nil, vImagePixelCount(seed.x), vImagePixelCount(seed.y), newColor, Int32(connectivity.rawValue), vImage_Flags(kvImageNoFlags))
  }
}
@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved8x4 {
  public func floodFill(from seed: CGPoint, newColor: Pixel_8888, connectivity: vImage.FloodFillConnectivity) {
    precondition(seed.x >= 0 && seed.y >= 0 && Int(seed.x) < width && Int(seed.y) < height, "the seed must lie within the buffer")
    var buffer = _vImageBuffers[0]
    _vImageWithBackground(newColor, newColor, as: UInt8.self) { color, _ in
      _ = vImageFloodFill_ARGB8888(&buffer, nil, vImagePixelCount(seed.x), vImagePixelCount(seed.y), UnsafeMutablePointer(mutating: color), Int32(connectivity.rawValue), vImage_Flags(kvImageNoFlags))
    }
  }
}
@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved16Ux4 {
  public func floodFill(from seed: CGPoint, newColor: Pixel_ARGB_16U, connectivity: vImage.FloodFillConnectivity) {
    precondition(seed.x >= 0 && seed.y >= 0 && Int(seed.x) < width && Int(seed.y) < height, "the seed must lie within the buffer")
    var buffer = _vImageBuffers[0]
    _vImageWithBackground(newColor, newColor, as: UInt16.self) { color, _ in
      _ = vImageFloodFill_ARGB16U(&buffer, nil, vImagePixelCount(seed.x), vImagePixelCount(seed.y), UnsafeMutablePointer(mutating: color), Int32(connectivity.rawValue), vImage_Flags(kvImageNoFlags))
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.DynamicPixelFormat {
  public func makeArray<U>(of scalarType: U.Type, channelCount: Int) -> [U] {
    let buffer = _vImageBuffers[0]
    let perRow = Int(buffer.width) * channelCount
    let rows = Int(buffer.height)
    guard perRow > 0, rows > 0, let data = buffer.data else { return [] }
    precondition(perRow * MemoryLayout<U>.stride <= buffer.rowBytes, "the buffer's rows are narrower than width x channelCount values")
    return [U](unsafeUninitializedCapacity: perRow * rows) { out, initialized in
      for row in 0..<rows {
        (out.baseAddress! + row * perRow).initialize(from: (data + row * buffer.rowBytes).assumingMemoryBound(to: U.self), count: perRow)
      }
      initialized = perRow * rows
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar8x4 {
  public init(interleavedBuffer: vImage.PixelBuffer<vImage.Interleaved8x4>) {
    self.init(size: interleavedBuffer.size)
    _deinterleave(from: interleavedBuffer)
  }
  public func convert(to destination: vImage.PixelBuffer<vImage.Interleaved8x4>) {
    _interleave(into: destination)
  }
  public func interleave(destination: vImage.PixelBuffer<vImage.Interleaved8x4>) {
    _interleave(into: destination)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved8x4 {
  public func applyGamma(_ gamma: vImage.Gamma, intermediateBuffer: vImage.PixelBuffer<vImage.InterleavedFx4>? = nil, destination: vImage.PixelBuffer<vImage.Interleaved8x4>) {
    _applyGamma(gamma, intermediateBuffer: intermediateBuffer, destination: destination, widthMultiplier: 4, pixelFormat: vImage.Interleaved8x4.self)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved8x3 {
  public func applyGamma(_ gamma: vImage.Gamma, intermediateBuffer: vImage.PixelBuffer<vImage.InterleavedFx3>? = nil, destination: vImage.PixelBuffer<vImage.Interleaved8x3>) {
    _applyGamma(gamma, intermediateBuffer: intermediateBuffer, destination: destination, widthMultiplier: 3, pixelFormat: vImage.Interleaved8x3.self)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved8x2 {
  public func applyGamma(_ gamma: vImage.Gamma, intermediateBuffer: vImage.PixelBuffer<vImage.InterleavedFx2>? = nil, destination: vImage.PixelBuffer<vImage.Interleaved8x2>) {
    _applyGamma(gamma, intermediateBuffer: intermediateBuffer, destination: destination, widthMultiplier: 2, pixelFormat: vImage.Interleaved8x2.self)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar8 {
  public func applyGamma(_ gamma: vImage.Gamma, intermediateBuffer: vImage.PixelBuffer<vImage.PlanarF>? = nil, destination: vImage.PixelBuffer<vImage.Planar8>) {
    _applyGamma(gamma, intermediateBuffer: intermediateBuffer, destination: destination, widthMultiplier: 1, pixelFormat: vImage.Planar8.self)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : StaticPixelFormat, Format.ComponentType == UInt8 {
  @usableFromInline
  internal func _applyGamma<DEST, IB>(_ gamma: vImage.Gamma, intermediateBuffer: vImage.PixelBuffer<IB>? = nil, destination: vImage.PixelBuffer<DEST>, widthMultiplier: Int, pixelFormat: DEST.Type) where DEST : StaticPixelFormat, IB : StaticPixelFormat {
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    let intermediate = intermediateBuffer ?? vImage.PixelBuffer<IB>(width: width, height: height)
    let source = _vImageWidened(_vImageBuffers[0], by: widthMultiplier)
    let floats = _vImageWidened(intermediate._vImageBuffers[0], by: widthMultiplier)
    let target = _vImageWidened(destination._vImageBuffers[0], by: widthMultiplier)
    gamma._withFunction { function in
      _vImageRun(source, floats) { vImageGamma_Planar8toPlanarF($0, $1, function, vImage_Flags(kvImageNoFlags)) }
    }
    _vImageRun(floats, target) { vImageConvert_PlanarFtoPlanar8($0, $1, 1, 0, vImage_Flags(kvImageNoFlags)) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : StaticPixelFormat, Format.ComponentType == Float {
  public func applyGamma(_ gamma: vImage.Gamma, destination: vImage.PixelBuffer<Format>) {
    _applyGamma(gamma, destination: destination, widthMultiplier: Format.channelCount, pixelFormat: Format.self)
  }
  @usableFromInline
  internal func _applyGamma<DEST>(_ gamma: vImage.Gamma, destination: vImage.PixelBuffer<DEST>, widthMultiplier: Int, pixelFormat: DEST.Type) where DEST : StaticPixelFormat {
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    gamma._withFunction { function in
      _vImageRun(_vImageWidened(_vImageBuffers[0], by: widthMultiplier), _vImageWidened(destination._vImageBuffers[0], by: widthMultiplier)) {
        vImageGamma_PlanarF($0, $1, function, vImage_Flags(kvImageNoFlags))
      }
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage {
  public enum Gamma {
    case fullPrecision(_: Float)
    case halfPrecision(_: Float)
    case fiveOverNineHalfPrecision
    case nineOverFiveHalfPrecision
    case fiveOverElevenHalfPrecision
    case elevenOverFiveHalfPrecision
    case sRGBForwardHalfPrecision
    case sRGBReverseHalfPrecision
    case elevenOverNineHalfPrecision
    case nineOverElevenHalfPrecision
    case bt709ForwardHalfPrecision
    case bt709ReverseHalfPrecision
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : StaticPixelFormat, Format.ComponentType == Float {
  public func applyGamma(linearParameters: (scale: Float, bias: Float), exponentialParameters: (scale: Float, preBias: Float, gamma: Float, postBias: Float), boundary: Float, destination: vImage.PixelBuffer<Format>) {
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    var exponential = [exponentialParameters.scale, exponentialParameters.preBias, exponentialParameters.postBias]
    var linear = [linearParameters.scale, linearParameters.bias]
    _vImageRun(_vImageWidened(_vImageBuffers[0], by: Format.channelCount), _vImageWidened(destination._vImageBuffers[0], by: Format.channelCount)) {
      vImagePiecewiseGamma_PlanarF($0, $1, &exponential, exponentialParameters.gamma, &linear, boundary, vImage_Flags(kvImageNoFlags))
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : StaticPixelFormat, Format.ComponentType == UInt8 {
  public func applyGamma(linearParameters: (scale: Float, bias: Float), exponentialParameters: (scale: Float, preBias: Float, gamma: Float, postBias: Float), boundary: Pixel_8, destination: vImage.PixelBuffer<Format>) {
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    var exponential = [exponentialParameters.scale, exponentialParameters.preBias, exponentialParameters.postBias]
    var linear = [linearParameters.scale, linearParameters.bias]
    _vImageRun(_vImageWidened(_vImageBuffers[0], by: Format.channelCount), _vImageWidened(destination._vImageBuffers[0], by: Format.channelCount)) {
      vImagePiecewiseGamma_Planar8($0, $1, &exponential, exponentialParameters.gamma, &linear, boundary, vImage_Flags(kvImageNoFlags))
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar16U {
  public func convert(to destination: vImage.PixelBuffer<vImage.Planar16F>) {
    _convertComponents(to: destination)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.InterleavedFx4 {
  public init(planarBuffers: [vImage.PixelBuffer<vImage.PlanarF>]) {
    self.init(_interleaving: planarBuffers)
  }
  public init(interleavedBuffer: vImage.PixelBuffer<vImage.Interleaved8x4>) {
    self.init(size: interleavedBuffer.size)
    interleavedBuffer._convertComponents(to: self)
  }
  public func planarBuffers() -> [vImage.PixelBuffer<vImage.Planar8>] {
    return _planarBuffers(vImage.Planar8.self)
  }
  public func planarBuffers() -> [vImage.PixelBuffer<vImage.PlanarF>] {
    return _planarBuffers(vImage.PlanarF.self)
  }
  public func convert(to destination: vImage.PixelBuffer<vImage.InterleavedFx3>, channelOrdering: vImage.ChannelOrdering) {
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) {
      channelOrdering == .ARGB ? vImageConvert_ARGBFFFFtoRGBFFF($0, $1, vImage_Flags(kvImageNoFlags)) : vImageConvert_RGBAFFFFtoRGBFFF($0, $1, vImage_Flags(kvImageNoFlags))
    }
  }
  public func convert(to destination: vImage.PixelBuffer<vImage.Interleaved8x4>) {
    _convertComponents(to: destination)
  }
  public func convert(to destination: vImage.PixelBuffer<vImage.Interleaved16Ux4>) {
    _convertComponents(to: destination)
  }
  public func convert(to destination: vImage.PixelBuffer<vImage.Interleaved16Fx4>) {
    _convertComponents(to: destination)
  }
  public func interleave(planarSourceBuffers: [vImage.PixelBuffer<vImage.PlanarF>]) {
    _interleave(planarSourceBuffers)
  }
  public func deinterleave(planarDestinationBuffers: [vImage.PixelBuffer<vImage.PlanarF>]) {
    _deinterleave(into: planarDestinationBuffers.map { $0._vImageBuffers[0] }, as: vImage.PlanarF.self)
  }
  public func deinterleave(destination: vImage.PixelBuffer<vImage.PlanarFx4>) {
    destination._deinterleave(from: self)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved8x2 {
  public init(planarBuffers: [vImage.PixelBuffer<vImage.Planar8>]) {
    self.init(_interleaving: planarBuffers)
  }
  public func planarBuffers() -> [vImage.PixelBuffer<vImage.Planar8>] {
    return _planarBuffers(vImage.Planar8.self)
  }
  public func convert(to destination: vImage.PixelBuffer<vImage.Interleaved16Fx2>) {
    _convertComponents(to: destination)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar8 {
  public func overwriteChannels(withScalar scalar: Pixel_8) {
    var buffer = _vImageBuffers[0]
    _ = vImageOverwriteChannelsWithScalar_Planar8(scalar, &buffer, vImage_Flags(kvImageNoFlags))
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved8x4 {
  public func overwriteChannels(_ channels: [UInt8], withScalar scalar: Pixel_8, destination: vImage.PixelBuffer<Format>) {
    let mask = _vImageCopyMask(channels)
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImageOverwriteChannelsWithScalar_ARGB8888(scalar, $0, $1, mask, vImage_Flags(kvImageNoFlags)) }
  }
  public func overwriteChannels(_ channels: [UInt8], withPixel pixel: Pixel_8888, destination: vImage.PixelBuffer<Format>) {
    let mask = _vImageCopyMask(channels)
    _vImageWithBackground(pixel, pixel, as: UInt8.self) { color, _ in
      _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImageOverwriteChannelsWithPixel_ARGB8888(color, $0, $1, mask, vImage_Flags(kvImageNoFlags)) }
    }
  }
  public func overwriteChannels(_ channels: [UInt8], withInterleavedBuffer buffer: vImage.PixelBuffer<Format>, destination: vImage.PixelBuffer<Format>) {
    let mask = _vImageCopyMask(channels)
    var source = buffer._vImageBuffers[0]
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImageSelectChannels_ARGB8888(&source, $0, $1, mask, vImage_Flags(kvImageNoFlags)) }
  }
  public func overwriteChannels(_ channels: [UInt8], withPlanarBuffer buffer: vImage.PixelBuffer<vImage.Planar8>, destination: vImage.PixelBuffer<Format>) {
    let mask = _vImageCopyMask(channels)
    var source = buffer._vImageBuffers[0]
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImageOverwriteChannels_ARGB8888(&source, $0, $1, mask, vImage_Flags(kvImageNoFlags)) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar16F {
  public func overwriteChannels(withScalar scalar: Pixel_16F) {
    var buffer = _vImageBuffers[0]
    _ = vImageOverwriteChannelsWithScalar_Planar16F(scalar, &buffer, vImage_Flags(kvImageNoFlags))
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved16Ux4 {
  public func overwriteChannels(_ channels: [UInt8], withPixel pixel: Pixel_ARGB_16U, destination: vImage.PixelBuffer<Format>) {
    let mask = _vImageCopyMask(channels)
    _vImageWithBackground(pixel, pixel, as: UInt16.self) { color, _ in
      _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImageOverwriteChannelsWithPixel_ARGB16U(color, $0, $1, mask, vImage_Flags(kvImageNoFlags)) }
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.PlanarF {
  public func overwriteChannels(withScalar scalar: Pixel_F) {
    var buffer = _vImageBuffers[0]
    _ = vImageOverwriteChannelsWithScalar_PlanarF(scalar, &buffer, vImage_Flags(kvImageNoFlags))
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.InterleavedFx4 {
  public func overwriteChannels(_ channels: [UInt8], withScalar scalar: Pixel_F, destination: vImage.PixelBuffer<Format>) {
    let mask = _vImageCopyMask(channels)
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImageOverwriteChannelsWithScalar_ARGBFFFF(scalar, $0, $1, mask, vImage_Flags(kvImageNoFlags)) }
  }
  public func overwriteChannels(_ channels: [UInt8], withPixel pixel: Pixel_FFFF, destination: vImage.PixelBuffer<Format>) {
    let mask = _vImageCopyMask(channels)
    _vImageWithBackground(pixel, pixel, as: Float.self) { color, _ in
      _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImageOverwriteChannelsWithPixel_ARGBFFFF(color, $0, $1, mask, vImage_Flags(kvImageNoFlags)) }
    }
  }
  public func overwriteChannels(_ channels: [UInt8], withInterleavedBuffer buffer: vImage.PixelBuffer<Format>, destination: vImage.PixelBuffer<Format>) {
    let mask = _vImageCopyMask(channels)
    var source = buffer._vImageBuffers[0]
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImageSelectChannels_ARGBFFFF(&source, $0, $1, mask, vImage_Flags(kvImageNoFlags)) }
  }
  public func overwriteChannels(_ channels: [UInt8], withPlanarBuffer buffer: vImage.PixelBuffer<vImage.PlanarF>, destination: vImage.PixelBuffer<Format>) {
    let mask = _vImageCopyMask(channels)
    var source = buffer._vImageBuffers[0]
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImageOverwriteChannels_ARGBFFFF(&source, $0, $1, mask, vImage_Flags(kvImageNoFlags)) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved16Fx4 {
  public func convert(to destination: vImage.PixelBuffer<vImage.Interleaved16Ux4>) {
    _convertComponents(to: destination)
  }
  public func convert(to destination: vImage.PixelBuffer<vImage.Interleaved8x4>) {
    _convertComponents(to: destination)
  }
  public func convert(to destination: vImage.PixelBuffer<vImage.InterleavedFx4>) {
    _convertComponents(to: destination)
  }
  public func interleave(planarSourceBuffers: [vImage.PixelBuffer<vImage.Planar16F>]) {
    _interleave(planarSourceBuffers)
  }
  public func deinterleave(planarDestinationBuffers: [vImage.PixelBuffer<vImage.Planar16F>]) {
    _deinterleave(into: planarDestinationBuffers.map { $0._vImageBuffers[0] }, as: vImage.Planar16F.self)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar8 {
  public func convert(to destination: vImage.PixelBuffer<vImage.PlanarF>) {
    _convertComponents(to: destination)
  }
  public func convert(to destination: vImage.PixelBuffer<vImage.Planar16F>) {
    _convertComponents(to: destination)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved8x4 {
  public func permuteChannels(to permuteMap: (UInt8, UInt8, UInt8, UInt8), destination: vImage.PixelBuffer<Format>) {
    _permute(permuteArray: [permuteMap.0, permuteMap.1, permuteMap.2, permuteMap.3], destination: destination, permuteFunc: vImagePermuteChannels_ARGB8888)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved8x3 {
  public func permuteChannels(to permuteMap: (UInt8, UInt8, UInt8), destination: vImage.PixelBuffer<Format>) {
    _permute(permuteArray: [permuteMap.0, permuteMap.1, permuteMap.2], destination: destination, permuteFunc: vImagePermuteChannels_RGB888)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved16Ux4 {
  public func permuteChannels(to permuteMap: (UInt8, UInt8, UInt8, UInt8), destination: vImage.PixelBuffer<Format>) {
    _permute(permuteArray: [permuteMap.0, permuteMap.1, permuteMap.2, permuteMap.3], destination: destination, permuteFunc: vImagePermuteChannels_ARGB16U)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved16Fx4 {
  public func permuteChannels(to permuteMap: (UInt8, UInt8, UInt8, UInt8), destination: vImage.PixelBuffer<Format>) {
    _permute(permuteArray: [permuteMap.0, permuteMap.1, permuteMap.2, permuteMap.3], destination: destination, permuteFunc: vImagePermuteChannels_ARGB16F)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.InterleavedFx4 {
  public func permuteChannels(to permuteMap: (UInt8, UInt8, UInt8, UInt8), destination: vImage.PixelBuffer<Format>) {
    _permute(permuteArray: [permuteMap.0, permuteMap.1, permuteMap.2, permuteMap.3], destination: destination, permuteFunc: vImagePermuteChannels_ARGBFFFF)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : StaticPixelFormat {
  @usableFromInline
  internal typealias PermuteFunc = (UnsafePointer<vImage_Buffer>, UnsafePointer<vImage_Buffer>, UnsafePointer<UInt8>, vImage_Flags) -> vImage_Error
  @usableFromInline
  internal func _permute<T>(permuteArray: [UInt8], destination: vImage.PixelBuffer<T>, permuteFunc: vImage.PixelBuffer<Format>.PermuteFunc) where T : StaticPixelFormat {
    precondition(permuteArray.allSatisfy { Int($0) < Format.channelCount }, "permute map entries must be channel indices")
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    permuteArray.withUnsafeBufferPointer { map in
      _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { permuteFunc($0, $1, map.baseAddress!, vImage_Flags(kvImageNoFlags)) }
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage {
  public struct ConvolutionKernel {
    public static let gaussian1Dx3: [Float] = [1, 2, 1].map { Float($0) / 4 }
    public static let gaussian1Dx5: [Float] = [1, 4, 6, 4, 1].map { Float($0) / 16 }
    public static let gaussian1Dx7: [Float] = [1, 6, 15, 20, 15, 6, 1].map { Float($0) / 64 }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : MultiplePlanePixelFormat, Format.ComponentType == UInt8 {
  public func separableConvolve(horizontalKernel: [Float], verticalKernel: [Float], bias: Float = 0, edgeMode: vImage.EdgeMode<Pixel_16U>, destination: vImage.PixelBuffer<Format>) {
    let flags = edgeMode.vImageFlags
    let background = edgeMode.backgroundColor ?? 0
    horizontalKernel.withUnsafeBufferPointer { h in
      verticalKernel.withUnsafeBufferPointer { v in
        _vImageEachPlane(_vImageBuffers, destination._vImageBuffers) {
          vImageSepConvolve_Planar8($0, $1, nil, 0, 0, h.baseAddress, UInt32(h.count), v.baseAddress, UInt32(v.count), bias, background, flags)
        }
      }
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar8 {
  public func separableConvolve(horizontalKernel: [Float], verticalKernel: [Float], bias: Float = 0, edgeMode: vImage.EdgeMode<Pixel_16U>, destination: vImage.PixelBuffer<Format>) {
    let flags = edgeMode.vImageFlags
    let background = edgeMode.backgroundColor ?? 0
    horizontalKernel.withUnsafeBufferPointer { h in
      verticalKernel.withUnsafeBufferPointer { v in
        _vImageEachPlane(_vImageBuffers, destination._vImageBuffers) {
          vImageSepConvolve_Planar8($0, $1, nil, 0, 0, h.baseAddress, UInt32(h.count), v.baseAddress, UInt32(v.count), bias, background, flags)
        }
      }
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar16F {
  public func separableConvolve(horizontalKernel: [Float], verticalKernel: [Float], bias: Float = 0, edgeMode: vImage.EdgeMode<Pixel_16F>, useFloat16Accumulator: Bool = false, destination: vImage.PixelBuffer<Format>) {
    let flags = edgeMode.vImageFlags | (useFloat16Accumulator ? vImage_Flags(kvImageUseFP16Accumulator) : 0)
    let background = edgeMode.backgroundColor ?? 0
    horizontalKernel.withUnsafeBufferPointer { h in
      verticalKernel.withUnsafeBufferPointer { v in
        _vImageEachPlane(_vImageBuffers, destination._vImageBuffers) {
          vImageSepConvolve_Planar16F($0, $1, nil, 0, 0, h.baseAddress, UInt32(h.count), v.baseAddress, UInt32(v.count), bias, background, flags)
        }
      }
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : MultiplePlanePixelFormat, Format.ComponentType == Float {
  public func separableConvolve(horizontalKernel: [Float], verticalKernel: [Float], bias: Float = 0, edgeMode: vImage.EdgeMode<Pixel_F>, destination: vImage.PixelBuffer<Format>) {
    let flags = edgeMode.vImageFlags
    let background = edgeMode.backgroundColor ?? 0
    horizontalKernel.withUnsafeBufferPointer { h in
      verticalKernel.withUnsafeBufferPointer { v in
        _vImageEachPlane(_vImageBuffers, destination._vImageBuffers) {
          vImageSepConvolve_PlanarF($0, $1, nil, 0, 0, h.baseAddress, UInt32(h.count), v.baseAddress, UInt32(v.count), bias, background, flags)
        }
      }
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.PlanarF {
  public func separableConvolve(horizontalKernel: [Float], verticalKernel: [Float], bias: Float = 0, edgeMode: vImage.EdgeMode<Pixel_F>, destination: vImage.PixelBuffer<Format>) {
    let flags = edgeMode.vImageFlags
    let background = edgeMode.backgroundColor ?? 0
    horizontalKernel.withUnsafeBufferPointer { h in
      verticalKernel.withUnsafeBufferPointer { v in
        _vImageEachPlane(_vImageBuffers, destination._vImageBuffers) {
          vImageSepConvolve_PlanarF($0, $1, nil, 0, 0, h.baseAddress, UInt32(h.count), v.baseAddress, UInt32(v.count), bias, background, flags)
        }
      }
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar8 {
  public func boxConvolve(kernelSize: vImage.Size, edgeMode: vImage.EdgeMode<Pixel_8>, destination: vImage.PixelBuffer<Format>) {
    precondition(kernelSize.width % 2 == 1 && kernelSize.height % 2 == 1, "the kernel size must be odd")
    let flags = edgeMode.vImageFlags
    let background = edgeMode.backgroundColor ?? 0
    _vImageEachPlane(_vImageBuffers, destination._vImageBuffers) { vImageBoxConvolve_Planar8($0, $1, nil, 0, 0, UInt32(kernelSize.height), UInt32(kernelSize.width), background, flags) }
  }
  public func tentConvolve(kernelSize: vImage.Size, edgeMode: vImage.EdgeMode<Pixel_8>, destination: vImage.PixelBuffer<Format>) {
    precondition(kernelSize.width % 2 == 1 && kernelSize.height % 2 == 1, "the kernel size must be odd")
    let flags = edgeMode.vImageFlags
    let background = edgeMode.backgroundColor ?? 0
    _vImageEachPlane(_vImageBuffers, destination._vImageBuffers) { vImageTentConvolve_Planar8($0, $1, nil, 0, 0, UInt32(kernelSize.height), UInt32(kernelSize.width), background, flags) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved8x4 {
  public func boxConvolved(kernelSize: vImage.Size, edgeMode: vImage.EdgeMode<Pixel_8888>) -> vImage.PixelBuffer<Format> {
    let result = vImage.PixelBuffer<Format>(size: size)
    boxConvolve(kernelSize: kernelSize, edgeMode: edgeMode, destination: result)
    return result
  }
  public func boxConvolve(kernelSize: vImage.Size, edgeMode: vImage.EdgeMode<Pixel_8888>, destination: vImage.PixelBuffer<Format>) {
    precondition(kernelSize.width % 2 == 1 && kernelSize.height % 2 == 1, "the kernel size must be odd")
    let flags = edgeMode.vImageFlags
    _vImageWithBackground(edgeMode.backgroundColor, (0, 0, 0, 0) as Pixel_8888, as: UInt8.self) { background, _ in
      _vImageEachPlane(_vImageBuffers, destination._vImageBuffers) { vImageBoxConvolve_ARGB8888($0, $1, nil, 0, 0, UInt32(kernelSize.height), UInt32(kernelSize.width), background, flags) }
    }
  }
  public func tentConvolved(kernelSize: vImage.Size, edgeMode: vImage.EdgeMode<Pixel_8888>) -> vImage.PixelBuffer<Format> {
    let result = vImage.PixelBuffer<Format>(size: size)
    tentConvolve(kernelSize: kernelSize, edgeMode: edgeMode, destination: result)
    return result
  }
  public func tentConvolve(kernelSize: vImage.Size, edgeMode: vImage.EdgeMode<Pixel_8888>, destination: vImage.PixelBuffer<Format>) {
    precondition(kernelSize.width % 2 == 1 && kernelSize.height % 2 == 1, "the kernel size must be odd")
    let flags = edgeMode.vImageFlags
    _vImageWithBackground(edgeMode.backgroundColor, (0, 0, 0, 0) as Pixel_8888, as: UInt8.self) { background, _ in
      _vImageEachPlane(_vImageBuffers, destination._vImageBuffers) { vImageTentConvolve_ARGB8888($0, $1, nil, 0, 0, UInt32(kernelSize.height), UInt32(kernelSize.width), background, flags) }
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : MultiplePlanePixelFormat, Format.ComponentType == UInt8 {
  public func boxConvolve(kernelSize: vImage.Size, edgeMode: vImage.EdgeMode<Pixel_8>, destination: vImage.PixelBuffer<Format>) {
    precondition(kernelSize.width % 2 == 1 && kernelSize.height % 2 == 1, "the kernel size must be odd")
    let flags = edgeMode.vImageFlags
    let background = edgeMode.backgroundColor ?? 0
    _vImageEachPlane(_vImageBuffers, destination._vImageBuffers) { vImageBoxConvolve_Planar8($0, $1, nil, 0, 0, UInt32(kernelSize.height), UInt32(kernelSize.width), background, flags) }
  }
  public func tentConvolve(kernelSize: vImage.Size, edgeMode: vImage.EdgeMode<Pixel_8>, destination: vImage.PixelBuffer<Format>) {
    precondition(kernelSize.width % 2 == 1 && kernelSize.height % 2 == 1, "the kernel size must be odd")
    let flags = edgeMode.vImageFlags
    let background = edgeMode.backgroundColor ?? 0
    _vImageEachPlane(_vImageBuffers, destination._vImageBuffers) { vImageTentConvolve_Planar8($0, $1, nil, 0, 0, UInt32(kernelSize.height), UInt32(kernelSize.width), background, flags) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage {
  public struct ConvolutionKernel2D<ComponentType> {
    public let width: vImagePixelCount
    public let height: vImagePixelCount
    public let values: [ComponentType]
    public init(values: [ComponentType], width: Int, height: Int) {
      precondition(width > 0 && height > 0 && width % 2 == 1 && height % 2 == 1, "a kernel's width and height must be odd")
      precondition(values.count == width * height, "a kernel needs width x height values")
      self.width = vImagePixelCount(width)
      self.height = vImagePixelCount(height)
      self.values = values
    }
    public init(values: [ComponentType], size: vImage.Size) {
      self.init(values: values, width: size.width, height: size.height)
    }
  }
}
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved8x4 {
  public func convolve(with kernel: vImage.ConvolutionKernel2D<Float>, bias: Float? = nil, edgeMode: vImage.EdgeMode<Pixel_8888>, destination: vImage.PixelBuffer<Format>) {
    let flags = edgeMode.vImageFlags
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    _vImageWithBackground(edgeMode.backgroundColor, (0, 0, 0, 0) as Pixel_8888, as: UInt8.self) { background, _ in
      kernel.values.withUnsafeBufferPointer { values in
        _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) {
          vImageConvolveFloatKernel_ARGB8888($0, $1, nil, 0, 0, values.baseAddress, UInt32(kernel.height), UInt32(kernel.width), bias ?? 0, background, flags)
        }
      }
    }
  }
  public func separableConvolve(horizontalKernel: [Float], verticalKernel: [Float], bias: Float = 0, edgeMode: vImage.EdgeMode<Pixel_8888>, destination: vImage.PixelBuffer<Format>) {
    let flags = edgeMode.vImageFlags
    _vImageWithBackground(edgeMode.backgroundColor, (0, 0, 0, 0) as Pixel_8888, as: UInt8.self) { background, _ in
      horizontalKernel.withUnsafeBufferPointer { h in
        verticalKernel.withUnsafeBufferPointer { v in
          _vImageEachPlane(_vImageBuffers, destination._vImageBuffers) {
            vImageSepConvolve_ARGB8888($0, $1, nil, 0, 0, h.baseAddress, UInt32(h.count), v.baseAddress, UInt32(v.count), bias, background, flags)
          }
        }
      }
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved8x4 {
  public func convolve(with kernel: vImage.ConvolutionKernel2D<Int16>, divisor: Int32?, bias: Int32? = nil, edgeMode: vImage.EdgeMode<Pixel_8888>, destination: vImage.PixelBuffer<Format>) {
    let divisor = divisor ?? max(1, kernel.values.reduce(Int32(0)) { $0 + Int32($1) })
    _vImageWithBackground(edgeMode.backgroundColor, (0, 0, 0, 0) as Pixel_8888, as: UInt8.self) { background, _ in
      _convolve(kernel: kernel, divisor: divisor, bias: bias, backgroundColor: background, flags: edgeMode.vImageFlags, destination: destination,
                convolveFunc: vImageConvolve_ARGB8888, convolveWithBiasFunc: vImageConvolveWithBias_ARGB8888)
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar8 {
  public func convolve(with kernel: vImage.ConvolutionKernel2D<Int16>, divisor: Int32?, bias: Int32? = nil, edgeMode: vImage.EdgeMode<Pixel_8>, destination: vImage.PixelBuffer<Format>) {
    let divisor = divisor ?? max(1, kernel.values.reduce(Int32(0)) { $0 + Int32($1) })
    _convolve(kernel: kernel, divisor: divisor, bias: bias, backgroundColor: edgeMode.backgroundColor ?? 0, flags: edgeMode.vImageFlags, destination: destination,
              convolveFunc: vImageConvolve_Planar8, convolveWithBiasFunc: vImageConvolveWithBias_Planar8)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : MultiplePlanePixelFormat, Format.ComponentType == UInt8 {
  public func convolve(with kernel: vImage.ConvolutionKernel2D<Int16>, divisor: Int32?, bias: Int32? = nil, edgeMode: vImage.EdgeMode<Pixel_8>, destination: vImage.PixelBuffer<Format>) {
    for (source, target) in zip(_vImageBuffers, destination._vImageBuffers) {
      vImage.PixelBuffer<vImage.Planar8>(_buffers: [source], storage: nil).convolve(with: kernel, divisor: divisor, bias: bias, edgeMode: edgeMode,
        destination: vImage.PixelBuffer<vImage.Planar8>(_buffers: [target], storage: nil))
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.InterleavedFx4 {
  public func convolve(with kernel: vImage.ConvolutionKernel2D<Float>, bias: Float? = nil, edgeMode: vImage.EdgeMode<Pixel_FFFF>, destination: vImage.PixelBuffer<Format>) {
    _vImageWithBackground(edgeMode.backgroundColor, (0, 0, 0, 0) as Pixel_FFFF, as: Float.self) { background, _ in
      _convolve(kernel: kernel, divisor: Float(1), bias: bias, backgroundColor: background, flags: edgeMode.vImageFlags, destination: destination,
                convolveFunc: vImageConvolve_ARGBFFFF_wrapper, convolveWithBiasFunc: vImageConvolveWithBias_ARGBFFFF_wrapper)
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.PlanarF {
  public func convolve(with kernel: vImage.ConvolutionKernel2D<Float>, bias: Float? = nil, edgeMode: vImage.EdgeMode<Pixel_F>, destination: vImage.PixelBuffer<Format>) {
    _convolve(kernel: kernel, divisor: Float(1), bias: bias, backgroundColor: edgeMode.backgroundColor ?? 0, flags: edgeMode.vImageFlags, destination: destination,
              convolveFunc: vImageConvolve_PlanarF_wrapper, convolveWithBiasFunc: vImageConvolveWithBias_PlanarF_wrapper)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved16Fx4 {
  public func convolve(with kernel: vImage.ConvolutionKernel2D<Float>, bias: Float? = nil, edgeMode: vImage.EdgeMode<Pixel_ARGB_16F>, useFloat16Accumulator: Bool = false, destination: vImage.PixelBuffer<Format>) {
    let flags = edgeMode.vImageFlags | (useFloat16Accumulator ? vImage_Flags(kvImageUseFP16Accumulator) : 0)
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    _vImageWithBackground(edgeMode.backgroundColor, (0, 0, 0, 0) as Pixel_ARGB_16F, as: UInt16.self) { background, _ in
      kernel.values.withUnsafeBufferPointer { values in
        _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) {
          if let bias { return vImageConvolveWithBias_ARGB16F($0, $1, nil, 0, 0, values.baseAddress, UInt32(kernel.height), UInt32(kernel.width), bias, background, flags) }
          return vImageConvolve_ARGB16F($0, $1, nil, 0, 0, values.baseAddress, UInt32(kernel.height), UInt32(kernel.width), background, flags)
        }
      }
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar16F {
  public func convolve(with kernel: vImage.ConvolutionKernel2D<Float>, bias: Float? = nil, edgeMode: vImage.EdgeMode<Pixel_16F>, useFloat16Accumulator: Bool = false, destination: vImage.PixelBuffer<Format>) {
    let flags = edgeMode.vImageFlags | (useFloat16Accumulator ? vImage_Flags(kvImageUseFP16Accumulator) : 0)
    let background = edgeMode.backgroundColor ?? 0
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    kernel.values.withUnsafeBufferPointer { values in
      _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) {
        if let bias { return vImageConvolveWithBias_Planar16F($0, $1, nil, 0, 0, values.baseAddress, UInt32(kernel.height), UInt32(kernel.width), bias, background, flags) }
        return vImageConvolve_Planar16F($0, $1, nil, 0, 0, values.baseAddress, UInt32(kernel.height), UInt32(kernel.width), background, flags)
      }
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : MultiplePlanePixelFormat, Format.ComponentType == Float {
  public func convolve(with kernel: vImage.ConvolutionKernel2D<Float>, bias: Float? = nil, edgeMode: vImage.EdgeMode<Pixel_F>, destination: vImage.PixelBuffer<Format>) {
    let flags = edgeMode.vImageFlags
    let background = edgeMode.backgroundColor ?? 0
    kernel.values.withUnsafeBufferPointer { values in
      _vImageEachPlane(_vImageBuffers, destination._vImageBuffers) {
        if let bias { return vImageConvolveWithBias_PlanarF($0, $1, nil, 0, 0, values.baseAddress, UInt32(kernel.height), UInt32(kernel.width), bias, background, flags) }
        return vImageConvolve_PlanarF($0, $1, nil, 0, 0, values.baseAddress, UInt32(kernel.height), UInt32(kernel.width), background, flags)
      }
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : StaticPixelFormat {
  @usableFromInline
  internal typealias ConvolveFunc<K, BIAS_DIVISOR, BG> = (UnsafePointer<vImage_Buffer>, UnsafePointer<vImage_Buffer>, UnsafeMutableRawPointer?, vImagePixelCount, vImagePixelCount, UnsafePointer<K>?, UInt32, UInt32, BIAS_DIVISOR, BG, vImage_Flags) -> vImage_Error
  @usableFromInline
  internal typealias ConvolveWithBiasFunc<K, BIAS_DIVISOR, BG> = (UnsafePointer<vImage_Buffer>, UnsafePointer<vImage_Buffer>, UnsafeMutableRawPointer?, vImagePixelCount, vImagePixelCount, UnsafePointer<K>?, UInt32, UInt32, BIAS_DIVISOR, BIAS_DIVISOR, BG, vImage_Flags) -> vImage_Error
  @usableFromInline
  internal func _convolve<T, K, BIAS_DIVISOR, BG>(kernel: vImage.ConvolutionKernel2D<K>, divisor: BIAS_DIVISOR, bias: BIAS_DIVISOR? = nil, backgroundColor: BG, flags: vImage_Flags, destination: vImage.PixelBuffer<T>, convolveFunc: vImage.PixelBuffer<Format>.ConvolveFunc<K, BIAS_DIVISOR, BG>, convolveWithBiasFunc: vImage.PixelBuffer<Format>.ConvolveWithBiasFunc<K, BIAS_DIVISOR, BG>) where T : StaticPixelFormat {
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    let height = UInt32(kernel.height)
    let width = UInt32(kernel.width)
    kernel.values.withUnsafeBufferPointer { values in
      _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) {
        if let bias {
          return convolveWithBiasFunc($0, $1, nil, 0, 0, values.baseAddress, height, width, divisor, bias, backgroundColor, flags)
        }
        return convolveFunc($0, $1, nil, 0, 0, values.baseAddress, height, width, divisor, backgroundColor, flags)
      }
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format.ComponentType == Float {
  @usableFromInline
  internal func vImageConvolve_ARGBFFFF_wrapper(_ src: UnsafePointer<vImage_Buffer>, _ dest: UnsafePointer<vImage_Buffer>, _ tempBuffer: UnsafeMutableRawPointer!, _ srcOffsetToROI_X: vImagePixelCount, _ srcOffsetToROI_Y: vImagePixelCount, _ kernel: UnsafePointer<Float>!, _ kernel_height: UInt32, _ kernel_width: UInt32, unusedDivisor: Float, _ backgroundColor: UnsafePointer<Float>!, _ flags: vImage_Flags) -> vImage_Error {
    return vImageConvolve_ARGBFFFF(src, dest, tempBuffer, srcOffsetToROI_X, srcOffsetToROI_Y, kernel, kernel_height, kernel_width, backgroundColor, flags)
  }
  @usableFromInline
  internal func vImageConvolveWithBias_ARGBFFFF_wrapper(_ src: UnsafePointer<vImage_Buffer>, _ dest: UnsafePointer<vImage_Buffer>, _ tempBuffer: UnsafeMutableRawPointer!, _ srcOffsetToROI_X: vImagePixelCount, _ srcOffsetToROI_Y: vImagePixelCount, _ kernel: UnsafePointer<Float>!, _ kernel_height: UInt32, _ kernel_width: UInt32, unusedDivisor: Float, _ bias: Float, _ backgroundColor: UnsafePointer<Float>!, _ flags: vImage_Flags) -> vImage_Error {
    return vImageConvolveWithBias_ARGBFFFF(src, dest, tempBuffer, srcOffsetToROI_X, srcOffsetToROI_Y, kernel, kernel_height, kernel_width, bias, backgroundColor, flags)
  }
  @usableFromInline
  internal func vImageConvolve_PlanarF_wrapper(_ src: UnsafePointer<vImage_Buffer>, _ dest: UnsafePointer<vImage_Buffer>, _ tempBuffer: UnsafeMutableRawPointer!, _ srcOffsetToROI_X: vImagePixelCount, _ srcOffsetToROI_Y: vImagePixelCount, _ kernel: UnsafePointer<Float>!, _ kernel_height: UInt32, _ kernel_width: UInt32, unusedDivisor: Float, _ backgroundColor: Float!, _ flags: vImage_Flags) -> vImage_Error {
    return vImageConvolve_PlanarF(src, dest, tempBuffer, srcOffsetToROI_X, srcOffsetToROI_Y, kernel, kernel_height, kernel_width, backgroundColor, flags)
  }
  @usableFromInline
  internal func vImageConvolveWithBias_PlanarF_wrapper(_ src: UnsafePointer<vImage_Buffer>, _ dest: UnsafePointer<vImage_Buffer>, _ tempBuffer: UnsafeMutableRawPointer!, _ srcOffsetToROI_X: vImagePixelCount, _ srcOffsetToROI_Y: vImagePixelCount, _ kernel: UnsafePointer<Float>!, _ kernel_height: UInt32, _ kernel_width: UInt32, unusedDivisor: Float, _ bias: Float, _ backgroundColor: Float!, _ flags: vImage_Flags) -> vImage_Error {
    return vImageConvolveWithBias_PlanarF(src, dest, tempBuffer, srcOffsetToROI_X, srcOffsetToROI_Y, kernel, kernel_height, kernel_width, bias, backgroundColor, flags)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved8x4 {
  public func convolve(with kernels: (vImage.ConvolutionKernel2D<Int16>, vImage.ConvolutionKernel2D<Int16>, vImage.ConvolutionKernel2D<Int16>, vImage.ConvolutionKernel2D<Int16>), divisors: (Int32, Int32, Int32, Int32)?, biases: (Int32, Int32, Int32, Int32) = (0, 0, 0, 0), edgeMode: vImage.EdgeMode<Pixel_8888>, destination: vImage.PixelBuffer<Format>) {
    let all = [kernels.0, kernels.1, kernels.2, kernels.3]
    precondition(all.allSatisfy { $0.width == all[0].width && $0.height == all[0].height }, "the kernels must be the same size")
    var divisorArray: [Int32]
    if let divisors { divisorArray = [divisors.0, divisors.1, divisors.2, divisors.3] }
    else { divisorArray = all.map { kernel in max(1, kernel.values.reduce(Int32(0)) { $0 + Int32($1) }) } }
    var biasArray = [biases.0, biases.1, biases.2, biases.3]
    let flags = edgeMode.vImageFlags
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    let copies = all.map { kernel -> UnsafeMutablePointer<Int16> in
      let p = UnsafeMutablePointer<Int16>.allocate(capacity: kernel.values.count)
      p.initialize(from: kernel.values, count: kernel.values.count)
      return p
    }
    defer { copies.forEach { $0.deallocate() } }
    var pointers: [UnsafePointer<Int16>?] = copies.map { UnsafePointer($0) }
    _vImageWithBackground(edgeMode.backgroundColor, (0, 0, 0, 0) as Pixel_8888, as: UInt8.self) { background, _ in
      _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) {
        vImageConvolveMultiKernel_ARGB8888($0, $1, nil, 0, 0, &pointers, UInt32(all[0].height), UInt32(all[0].width), &divisorArray, &biasArray, background, flags)
      }
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage {
  public enum EdgeMode<PixelType> {
    case copyInPlace
    case truncateKernel
    case fill(backgroundColor: PixelType)
    case extend
    @usableFromInline
    internal var vImageFlags: vImage_Flags {
      get {
        switch self {
        case .copyInPlace: return vImage_Flags(kvImageCopyInPlace)
        case .truncateKernel: return vImage_Flags(kvImageTruncateKernel)
        case .fill: return vImage_Flags(kvImageBackgroundColorFill)
        case .extend: return vImage_Flags(kvImageEdgeExtend)
        }
      }
    }
    @usableFromInline
    internal var backgroundColor: PixelType? {
      get {
        if case .fill(let color) = self { return color }
        return nil
      }
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar16F {
  public func convert(to destination: vImage.PixelBuffer<vImage.Planar16U>) {
    _convertComponents(to: destination)
  }
  public func convert(to destination: vImage.PixelBuffer<vImage.Planar8>) {
    _convertComponents(to: destination)
  }
  public func convert(to destination: vImage.PixelBuffer<vImage.PlanarF>) {
    _convertComponents(to: destination)
  }
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
extension vImage_Buffer {
  public init(size: CGSize, bitsPerPixel: UInt32) throws {
    guard let width = Int(exactly: size.width.rounded(.up)), let height = Int(exactly: size.height.rounded(.up)) else {
      throw vImage.Error.invalidParameter
    }
    try self.init(width: width, height: height, bitsPerPixel: bitsPerPixel)
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension vImage_Buffer {
  public var size: CGSize {
    get { CGSize(width: CGFloat(width), height: CGFloat(height)) }
  }
  public static func preferredAlignmentAndRowBytes(width: Int, height: Int, bitsPerPixel: UInt32) throws -> (alignment: Int, rowBytes: Int) {
    var buffer = vImage_Buffer()
    let result = vImageBuffer_Init(&buffer, vImagePixelCount(height), vImagePixelCount(width), bitsPerPixel, vImage_Flags(kvImageNoAllocate))
    try vImage.Error._check(result)
    return (alignment: result, rowBytes: buffer.rowBytes)
  }
  public init(width: Int, height: Int, bitsPerPixel: UInt32) throws {
    guard width >= 0, height >= 0 else { throw vImage.Error.invalidParameter }
    self.init()
    try vImage.Error._check(vImageBuffer_Init(&self, vImagePixelCount(height), vImagePixelCount(width), bitsPerPixel, vImage_Flags(kvImageNoFlags)))
  }
  public func free() {
    Darwin.free(data)
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension vImage_Buffer {
  public init(cgImage: CGImage, flags options: vImage.Options = .noFlags) throws {
    guard let format = vImage_CGImageFormat(cgImage: cgImage) else { throw vImage.Error.invalidImageFormat }
    try self.init(cgImage: cgImage, format: format, flags: options)
  }
  public init(cgImage: CGImage, format: vImage_CGImageFormat, flags options: vImage.Options = .noFlags) throws {
    self.init()
    var format = format
    try vImage.Error._check(vImageBuffer_InitWithCGImage(&self, &format, nil, cgImage, options.flags))
  }
  public func createCGImage(format: vImage_CGImageFormat, flags options: vImage.Options = .noFlags) throws -> CGImage {
    var buffer = self
    var format = format
    var error = vImage_Error(kvImageNoError)
    let image = vImageCreateCGImageFromBuffer(&buffer, &format, nil, nil, options.flags, &error)
    try vImage.Error._check(error)
    guard let image else { throw vImage.Error.invalidImageObject }
    return image.takeRetainedValue()
  }
  public func copy(destinationBuffer: inout vImage_Buffer, pixelSize: Int, flags options: vImage.Options = .noFlags) throws {
    var source = self
    try vImage.Error._check(vImageCopyBuffer(&source, &destinationBuffer, pixelSize, options.flags))
  }
}
@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension vImage_PerpsectiveTransform : Equatable {
  public static func == (lhs: vImage_PerpsectiveTransform, rhs: vImage_PerpsectiveTransform) -> Bool {
    return lhs.a == rhs.a && lhs.b == rhs.b && lhs.c == rhs.c && lhs.d == rhs.d && lhs.tx == rhs.tx && lhs.ty == rhs.ty
      && lhs.vx == rhs.vx && lhs.vy == rhs.vy && lhs.v == rhs.v
  }
  public enum Interpolation : Equatable, Hashable {
    case nearest
    case linear
    @usableFromInline
    internal var vImageWarpInterpolation: vImage_WarpInterpolation {
      get {
        switch self {
        case .nearest: return vImage_WarpInterpolation(kvImageInterpolationNearest)
        case .linear: return vImage_WarpInterpolation(kvImageInterpolationLinear)
        }
      }
    }
  }
  public typealias QuadrilateralPoints = (CGPoint, CGPoint, CGPoint, CGPoint)
  public init?(source: vImage_PerpsectiveTransform.QuadrilateralPoints, destination: vImage_PerpsectiveTransform.QuadrilateralPoints) {
    let s = [source.0, source.1, source.2, source.3]
    let d = [destination.0, destination.1, destination.2, destination.3]
    var sourcePoints: [(Float, Float)] = s.map { (Float($0.x), Float($0.y)) }
    var destinationPoints: [(Float, Float)] = d.map { (Float($0.x), Float($0.y)) }
    var transform = vImage_PerpsectiveTransform()
    let error = sourcePoints.withUnsafeMutableBufferPointer { sp in
      destinationPoints.withUnsafeMutableBufferPointer { dp in
        vImageGetPerspectiveWarp(sp.baseAddress!, dp.baseAddress!, &transform, vImage_Flags(kvImageNoFlags))
      }
    }
    guard error == kvImageNoError else { return nil }
    self = transform
  }
}
@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar8 {
  public func transform(_ transform: vImage_PerpsectiveTransform, interpolation: vImage_PerpsectiveTransform.Interpolation, backgroundColor: Pixel_8, destination: vImage.PixelBuffer<Format>) {
    var matrix = transform
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImagePerspectiveWarp_Planar8($0, $1, nil, &matrix, interpolation.vImageWarpInterpolation, backgroundColor, vImage_Flags(kvImageNoFlags)) }
  }
}
@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar16F {
  public func transform(_ transform: vImage_PerpsectiveTransform, interpolation: vImage_PerpsectiveTransform.Interpolation, backgroundColor: Pixel_16F, destination: vImage.PixelBuffer<Format>) {
    var matrix = transform
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImagePerspectiveWarp_Planar16F($0, $1, nil, &matrix, interpolation.vImageWarpInterpolation, backgroundColor, vImage_Flags(kvImageNoFlags)) }
  }
}
@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar16U {
  public func transform(_ transform: vImage_PerpsectiveTransform, interpolation: vImage_PerpsectiveTransform.Interpolation, backgroundColor: Pixel_16U, destination: vImage.PixelBuffer<Format>) {
    var matrix = transform
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImagePerspectiveWarp_Planar16U($0, $1, nil, &matrix, interpolation.vImageWarpInterpolation, backgroundColor, vImage_Flags(kvImageNoFlags)) }
  }
}
@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved8x4 {
  public func transform(_ transform: vImage_PerpsectiveTransform, interpolation: vImage_PerpsectiveTransform.Interpolation, backgroundColor: Pixel_8888, destination: vImage.PixelBuffer<Format>) {
    var matrix = transform
    let mode = interpolation.vImageWarpInterpolation
    _vImageWithBackground(backgroundColor, (0, 0, 0, 0) as Pixel_8888, as: UInt8.self) { background, _ in
      _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImagePerspectiveWarp_ARGB8888($0, $1, nil, &matrix, mode, UnsafeMutablePointer(mutating: background), vImage_Flags(kvImageNoFlags)) }
    }
  }
}
@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved16Fx4 {
  public func transform(_ transform: vImage_PerpsectiveTransform, interpolation: vImage_PerpsectiveTransform.Interpolation, backgroundColor: Pixel_ARGB_16F, destination: vImage.PixelBuffer<Format>) {
    var matrix = transform
    let mode = interpolation.vImageWarpInterpolation
    _vImageWithBackground(backgroundColor, (0, 0, 0, 0) as Pixel_ARGB_16F, as: UInt16.self) { background, _ in
      _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImagePerspectiveWarp_ARGB16F($0, $1, nil, &matrix, mode, UnsafeMutablePointer(mutating: background), vImage_Flags(kvImageNoFlags)) }
    }
  }
}
@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved16Ux4 {
  public func transform(_ transform: vImage_PerpsectiveTransform, interpolation: vImage_PerpsectiveTransform.Interpolation, backgroundColor: Pixel_ARGB_16U, destination: vImage.PixelBuffer<Format>) {
    var matrix = transform
    let mode = interpolation.vImageWarpInterpolation
    _vImageWithBackground(backgroundColor, (0, 0, 0, 0) as Pixel_ARGB_16U, as: UInt16.self) { background, _ in
      _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImagePerspectiveWarp_ARGB16U($0, $1, nil, &matrix, mode, UnsafeMutablePointer(mutating: background), vImage_Flags(kvImageNoFlags)) }
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved8x4 {
  public init(lumaSource: vImage.PixelBuffer<vImage.Planar8>, chromaSource: vImage.PixelBuffer<vImage.Interleaved8x2>, conversionInfo: vImage_YpCbCrToARGB) {
    self.init(size: lumaSource.size)
    convert(lumaSource: lumaSource, chromaSource: chromaSource, conversionInfo: conversionInfo)
  }
  public init(planarBuffers: [vImage.PixelBuffer<vImage.Planar8>]) {
    self.init(_interleaving: planarBuffers)
  }
  public init(planarBuffers: [vImage.PixelBuffer<vImage.PlanarF>]) {
    self.init(_interleaving: planarBuffers)
  }
  public func planarBuffers() -> [vImage.PixelBuffer<vImage.Planar8>] {
    return _planarBuffers(vImage.Planar8.self)
  }
  public func planarBuffers() -> [vImage.PixelBuffer<vImage.PlanarF>] {
    return _planarBuffers(vImage.PlanarF.self)
  }
  public func convert(to destination: vImage.PixelBuffer<vImage.Interleaved8x3>, channelOrdering: vImage.ChannelOrdering) {
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) {
      channelOrdering == .ARGB ? vImageConvert_ARGB8888toRGB888($0, $1, vImage_Flags(kvImageNoFlags)) : vImageConvert_RGBA8888toRGB888($0, $1, vImage_Flags(kvImageNoFlags))
    }
  }
  public func convert(to destination: vImage.PixelBuffer<vImage.InterleavedFx4>) {
    _convertComponents(to: destination)
  }
  public func convert(to destination: vImage.PixelBuffer<vImage.Interleaved16Ux4>) {
    _convertComponents(to: destination)
  }
  public func convert(to destination: vImage.PixelBuffer<vImage.Interleaved16Fx4>) {
    _convertComponents(to: destination)
  }
  public func convert(lumaSource: vImage.PixelBuffer<vImage.Planar8>, chromaSource: vImage.PixelBuffer<vImage.Interleaved8x2>, conversionInfo: vImage_YpCbCrToARGB) {
    var info = conversionInfo
    var luma = lumaSource._vImageBuffers[0]
    var chroma = chromaSource._vImageBuffers[0]
    var target = _vImageBuffers[0]
    _ = vImageConvert_420Yp8_CbCr8ToARGB8888(&luma, &chroma, &target, &info, nil, 255, vImage_Flags(kvImageNoFlags))
  }
  public func withCVPixelBuffer(readOnly: Bool, body: (CVPixelBuffer) -> Void) {
    let buffer = _vImageBuffers[0]
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreateWithBytes(nil, Int(buffer.width), Int(buffer.height), kCVPixelFormatType_32ARGB, buffer.data!, buffer.rowBytes, nil, nil, nil, &pixelBuffer)
    guard status == kCVReturnSuccess, let pixelBuffer else { return }
    let lockFlags: CVPixelBufferLockFlags = readOnly ? .readOnly : []
    CVPixelBufferLockBaseAddress(pixelBuffer, lockFlags)
    body(pixelBuffer)
    CVPixelBufferUnlockBaseAddress(pixelBuffer, lockFlags)
  }
  public func interleave(planarSourceBuffers: [vImage.PixelBuffer<vImage.Planar8>]) {
    _interleave(planarSourceBuffers)
  }
  public func deinterleave(planarDestinationBuffers: [vImage.PixelBuffer<vImage.Planar8>]) {
    _deinterleave(into: planarDestinationBuffers.map { $0._vImageBuffers[0] }, as: vImage.Planar8.self)
  }
  public func deinterleave(destination: vImage.PixelBuffer<vImage.Planar8x4>) {
    destination._deinterleave(from: self)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved8x3 {
  public init(planarBuffers: [vImage.PixelBuffer<vImage.Planar8>]) {
    self.init(_interleaving: planarBuffers)
  }
  public func planarBuffers() -> [vImage.PixelBuffer<vImage.Planar8>] {
    return _planarBuffers(vImage.Planar8.self)
  }
  public func convert(to destination: vImage.PixelBuffer<vImage.InterleavedFx3>) {
    _convertComponents(to: destination)
  }
  public func interleave(planarSourceBuffers: [vImage.PixelBuffer<vImage.Planar8>]) {
    _interleave(planarSourceBuffers)
  }
  public func deinterleave(planarDestinationBuffers: [vImage.PixelBuffer<vImage.Planar8>]) {
    _deinterleave(into: planarDestinationBuffers.map { $0._vImageBuffers[0] }, as: vImage.Planar8.self)
  }
  public func deinterleave(destination: vImage.PixelBuffer<vImage.Planar8x3>) {
    destination._deinterleave(from: self)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage {
  public enum Rotation {
    case clockwise0Degrees
    case clockwise90Degrees
    case clockwise180Degrees
    case clockwise270Degrees
    case counterClockwise0Degrees
    case counterClockwise90Degrees
    case counterClockwise180Degrees
    case counterClockwise270Degrees
    case angleInRadians(_: Float)
    case angleInDegrees(_: Float)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar8 {
  public func rotate(_ rotation: vImage.Rotation, backgroundColor: Pixel_8? = Pixel_8(0), destination: vImage.PixelBuffer<Format>) {
    _rotate(rotation, destination: destination, backgroundColor: backgroundColor, nullBackgroundColor: 0, rotateFunc: vImageRotate_Planar8, rotate90Func: vImageRotate90_Planar8)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved8x4 {
  public func rotate(_ rotation: vImage.Rotation, backgroundColor: Pixel_8888? = (0, 0, 0, 0), destination: vImage.PixelBuffer<Format>) {
    _vImageWithBackground(backgroundColor, (0, 0, 0, 0) as Pixel_8888, as: UInt8.self) { background, given in
      _rotate(rotation, destination: destination, backgroundColor: given ? background : nil, nullBackgroundColor: background, rotateFunc: vImageRotate_ARGB8888, rotate90Func: vImageRotate90_ARGB8888)
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved16Ux4 {
  public func rotate(_ rotation: vImage.Rotation, backgroundColor: Pixel_ARGB_16U? = (0, 0, 0, 0), destination: vImage.PixelBuffer<Format>) {
    _vImageWithBackground(backgroundColor, (0, 0, 0, 0) as Pixel_ARGB_16U, as: UInt16.self) { background, given in
      _rotate(rotation, destination: destination, backgroundColor: given ? background : nil, nullBackgroundColor: background, rotateFunc: vImageRotate_ARGB16U, rotate90Func: vImageRotate90_ARGB16U)
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.InterleavedFx4 {
  public func rotate(_ rotation: vImage.Rotation, backgroundColor: Pixel_FFFF? = (0, 0, 0, 0), destination: vImage.PixelBuffer<Format>) {
    _vImageWithBackground(backgroundColor, (0, 0, 0, 0) as Pixel_FFFF, as: Float.self) { background, given in
      _rotate(rotation, destination: destination, backgroundColor: given ? background : nil, nullBackgroundColor: background, rotateFunc: vImageRotate_ARGBFFFF, rotate90Func: vImageRotate90_ARGBFFFF)
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.PlanarF {
  public func rotate(_ rotation: vImage.Rotation, backgroundColor: Pixel_F? = Pixel_F(0), destination: vImage.PixelBuffer<Format>) {
    _rotate(rotation, destination: destination, backgroundColor: backgroundColor, nullBackgroundColor: 0, rotateFunc: vImageRotate_PlanarF, rotate90Func: vImageRotate90_PlanarF)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar16F {
  public func rotate(_ rotation: vImage.Rotation, backgroundColor: Pixel_16F? = Pixel_16F(0), useFloat16Accumulator: Bool = false, destination: vImage.PixelBuffer<Format>) {
    _rotate(rotation, destination: destination, backgroundColor: backgroundColor, nullBackgroundColor: 0, rotateFunc: vImageRotate_Planar16F, rotate90Func: vImageRotate90_Planar16F, useFloat16Accumulator: useFloat16Accumulator)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved16Fx2 {
  public func rotate(_ rotation: vImage.Rotation, backgroundColor: Pixel_16F16F? = (0, 0), useFloat16Accumulator: Bool = false, destination: vImage.PixelBuffer<Format>) {
    _vImageWithBackground(backgroundColor, (0, 0) as Pixel_16F16F, as: UInt16.self) { background, given in
      _rotate(rotation, destination: destination, backgroundColor: given ? background : nil, nullBackgroundColor: background, rotateFunc: vImageRotate_CbCr16F, rotate90Func: vImageRotate90_CbCr16F, useFloat16Accumulator: useFloat16Accumulator)
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved16Fx4 {
  public func rotate(_ rotation: vImage.Rotation, backgroundColor: Pixel_ARGB_16F? = (0, 0, 0, 0), useFloat16Accumulator: Bool = false, destination: vImage.PixelBuffer<Format>) {
    _vImageWithBackground(backgroundColor, (0, 0, 0, 0) as Pixel_ARGB_16F, as: UInt16.self) { background, given in
      _rotate(rotation, destination: destination, backgroundColor: given ? background : nil, nullBackgroundColor: background, rotateFunc: vImageRotate_ARGB16F, rotate90Func: vImageRotate90_ARGB16F, useFloat16Accumulator: useFloat16Accumulator)
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : StaticPixelFormat {
  @usableFromInline
  internal typealias RotateFunc<BG> = (UnsafePointer<vImage_Buffer>, UnsafePointer<vImage_Buffer>, UnsafeMutableRawPointer?, Float, BG, vImage_Flags) -> vImage_Error
  @usableFromInline
  internal typealias Rotate90Func<BG> = (UnsafePointer<vImage_Buffer>, UnsafePointer<vImage_Buffer>, UInt8, BG, vImage_Flags) -> vImage_Error
  @usableFromInline
  internal func _rotate<T, BG>(_ rotation: vImage.Rotation, destination: vImage.PixelBuffer<T>, backgroundColor: BG?, nullBackgroundColor: BG, rotateFunc: vImage.PixelBuffer<Format>.RotateFunc<BG>, rotate90Func: vImage.PixelBuffer<Format>.Rotate90Func<BG>, useFloat16Accumulator: Bool = false) where T : StaticPixelFormat {
    var flags = _vImageEdgeFlags(hasBackground: backgroundColor != nil, useFloat16Accumulator: useFloat16Accumulator)
    let background = backgroundColor ?? nullBackgroundColor
    let quarter: UInt8?
    var angle: Float = 0
    switch rotation {
    case .clockwise0Degrees, .counterClockwise0Degrees: quarter = UInt8(kRotate0DegreesClockwise)
    case .clockwise90Degrees: quarter = UInt8(kRotate90DegreesClockwise)
    case .clockwise180Degrees, .counterClockwise180Degrees: quarter = UInt8(kRotate180DegreesClockwise)
    case .clockwise270Degrees: quarter = UInt8(kRotate270DegreesClockwise)
    case .counterClockwise90Degrees: quarter = UInt8(kRotate90DegreesCounterClockwise)
    case .counterClockwise270Degrees: quarter = UInt8(kRotate270DegreesCounterClockwise)
    case .angleInRadians(let radians): quarter = nil; angle = radians
    case .angleInDegrees(let degrees): quarter = nil; angle = degrees * .pi / 180
    }
    if let quarter {
      flags = useFloat16Accumulator ? vImage_Flags(kvImageUseFP16Accumulator) : vImage_Flags(kvImageNoFlags)
      _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { rotate90Func($0, $1, quarter, background, flags) }
    } else {
      _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { rotateFunc($0, $1, nil, angle, background, flags) }
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage {
  public enum ShearDirection : Equatable, Hashable {
    case vertical
    case horizontal
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved8x2 {
  public func shear(direction: vImage.ShearDirection, translate: Float, slope: Float, resamplingFilter: ResamplingFilter, backgroundColor: Pixel_88? = (0, 0), destination: vImage.PixelBuffer<Format>) {
    _vImageWithBackground(backgroundColor, (0, 0) as Pixel_88, as: UInt8.self) { background, given in
      _shear(direction: direction, translate: translate, slope: slope, resamplingFilter: resamplingFilter, destination: destination, backgroundColor: given ? background : nil, nullBackgroundColor: background, verticalShearFunc: vImageVerticalShear_CbCr8, horizontalShearFunc: vImageHorizontalShear_CbCr8)
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar16U {
  public func shear(direction: vImage.ShearDirection, translate: Float, slope: Float, resamplingFilter: ResamplingFilter, backgroundColor: Pixel_16U? = Pixel_16U(0), destination: vImage.PixelBuffer<Format>) {
    _shear(direction: direction, translate: translate, slope: slope, resamplingFilter: resamplingFilter, destination: destination, backgroundColor: backgroundColor, nullBackgroundColor: 0, verticalShearFunc: vImageVerticalShear_Planar16U, horizontalShearFunc: vImageHorizontalShear_Planar16U)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : StaticPixelFormat {
  @usableFromInline
  internal typealias ShearFunc<BG> = (UnsafePointer<vImage_Buffer>, UnsafePointer<vImage_Buffer>, vImagePixelCount, vImagePixelCount, Float, Float, ResamplingFilter, BG, vImage_Flags) -> vImage_Error
  @usableFromInline
  internal func _shear<T, BG>(direction: vImage.ShearDirection, translate: Float, slope: Float, resamplingFilter: ResamplingFilter, destination: vImage.PixelBuffer<T>, backgroundColor: BG?, nullBackgroundColor: BG, verticalShearFunc: vImage.PixelBuffer<Format>.ShearFunc<BG>, horizontalShearFunc: vImage.PixelBuffer<Format>.ShearFunc<BG>, useFloat16Accumulator: Bool = false) where T : StaticPixelFormat {
    let flags = _vImageEdgeFlags(hasBackground: backgroundColor != nil, useFloat16Accumulator: useFloat16Accumulator)
    let background = backgroundColor ?? nullBackgroundColor
    let function = direction == .horizontal ? horizontalShearFunc : verticalShearFunc
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { function($0, $1, 0, 0, translate, slope, resamplingFilter, background, flags) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved16Ux2 {
  public func shear<T>(direction: vImage.ShearDirection, translate: T, slope: T, resamplingFilter: ResamplingFilter, backgroundColor: Pixel_16U16U? = (0, 0), destination: vImage.PixelBuffer<Format>) where T : BinaryFloatingPoint {
    _vImageWithBackground(backgroundColor, (0, 0) as Pixel_16U16U, as: UInt16.self) { background, given in
      _shearD(direction: direction, translate: Double(translate), slope: Double(slope), resamplingFilter: resamplingFilter, destination: destination, backgroundColor: given ? background : nil, nullBackgroundColor: background, verticalShearFunc: vImageVerticalShearD_CbCr16U, horizontalShearFunc: vImageHorizontalShearD_CbCr16U)
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar8 {
  public func shear<T>(direction: vImage.ShearDirection, translate: T, slope: T, resamplingFilter: ResamplingFilter, backgroundColor: Pixel_8? = Pixel_8(0), destination: vImage.PixelBuffer<Format>) where T : BinaryFloatingPoint {
    _shearD(direction: direction, translate: Double(translate), slope: Double(slope), resamplingFilter: resamplingFilter, destination: destination, backgroundColor: backgroundColor, nullBackgroundColor: 0, verticalShearFunc: vImageVerticalShearD_Planar8, horizontalShearFunc: vImageHorizontalShearD_Planar8)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar16F {
  public func shear<T>(direction: vImage.ShearDirection, translate: T, slope: T, resamplingFilter: ResamplingFilter, backgroundColor: Pixel_16F? = Pixel_16F(0), useFloat16Accumulator: Bool = false, destination: vImage.PixelBuffer<Format>) where T : BinaryFloatingPoint {
    _shearD(direction: direction, translate: Double(translate), slope: Double(slope), resamplingFilter: resamplingFilter, destination: destination, backgroundColor: backgroundColor, nullBackgroundColor: 0, verticalShearFunc: vImageVerticalShearD_Planar16F, horizontalShearFunc: vImageHorizontalShearD_Planar16F, useFloat16Accumulator: useFloat16Accumulator)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved16Fx2 {
  public func shear<T>(direction: vImage.ShearDirection, translate: T, slope: T, resamplingFilter: ResamplingFilter, backgroundColor: Pixel_16F16F? = (0, 0), useFloat16Accumulator: Bool = false, destination: vImage.PixelBuffer<Format>) where T : BinaryFloatingPoint {
    _vImageWithBackground(backgroundColor, (0, 0) as Pixel_16F16F, as: UInt16.self) { background, given in
      _shearD(direction: direction, translate: Double(translate), slope: Double(slope), resamplingFilter: resamplingFilter, destination: destination, backgroundColor: given ? background : nil, nullBackgroundColor: background, verticalShearFunc: vImageVerticalShearD_CbCr16F, horizontalShearFunc: vImageHorizontalShearD_CbCr16F, useFloat16Accumulator: useFloat16Accumulator)
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved8x4 {
  public func shear<T>(direction: vImage.ShearDirection, translate: T, slope: T, resamplingFilter: ResamplingFilter, backgroundColor: Pixel_8888? = (0, 0, 0, 0), destination: vImage.PixelBuffer<Format>) where T : BinaryFloatingPoint {
    _vImageWithBackground(backgroundColor, (0, 0, 0, 0) as Pixel_8888, as: UInt8.self) { background, given in
      _shearD(direction: direction, translate: Double(translate), slope: Double(slope), resamplingFilter: resamplingFilter, destination: destination, backgroundColor: given ? background : nil, nullBackgroundColor: background, verticalShearFunc: vImageVerticalShearD_ARGB8888, horizontalShearFunc: vImageHorizontalShearD_ARGB8888)
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved16Fx4 {
  public func shear<T>(direction: vImage.ShearDirection, translate: T, slope: T, resamplingFilter: ResamplingFilter, backgroundColor: Pixel_ARGB_16F? = (0, 0, 0, 0), useFloat16Accumulator: Bool = false, destination: vImage.PixelBuffer<Format>) where T : BinaryFloatingPoint {
    _vImageWithBackground(backgroundColor, (0, 0, 0, 0) as Pixel_ARGB_16F, as: UInt16.self) { background, given in
      _shearD(direction: direction, translate: Double(translate), slope: Double(slope), resamplingFilter: resamplingFilter, destination: destination, backgroundColor: given ? background : nil, nullBackgroundColor: background, verticalShearFunc: vImageVerticalShearD_ARGB16F, horizontalShearFunc: vImageHorizontalShearD_ARGB16F, useFloat16Accumulator: useFloat16Accumulator)
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved16Ux4 {
  public func shear<T>(direction: vImage.ShearDirection, translate: T, slope: T, resamplingFilter: ResamplingFilter, backgroundColor: Pixel_ARGB_16U? = (0, 0, 0, 0), destination: vImage.PixelBuffer<Format>) where T : BinaryFloatingPoint {
    _vImageWithBackground(backgroundColor, (0, 0, 0, 0) as Pixel_ARGB_16U, as: UInt16.self) { background, given in
      _shearD(direction: direction, translate: Double(translate), slope: Double(slope), resamplingFilter: resamplingFilter, destination: destination, backgroundColor: given ? background : nil, nullBackgroundColor: background, verticalShearFunc: vImageVerticalShearD_ARGB16U, horizontalShearFunc: vImageHorizontalShearD_ARGB16U)
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.PlanarF {
  public func shear<T>(direction: vImage.ShearDirection, translate: T, slope: T, resamplingFilter: ResamplingFilter, backgroundColor: Pixel_F? = Pixel_F(0), destination: vImage.PixelBuffer<Format>) where T : BinaryFloatingPoint {
    _shearD(direction: direction, translate: Double(translate), slope: Double(slope), resamplingFilter: resamplingFilter, destination: destination, backgroundColor: backgroundColor, nullBackgroundColor: 0, verticalShearFunc: vImageVerticalShearD_PlanarF, horizontalShearFunc: vImageHorizontalShearD_PlanarF)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.InterleavedFx4 {
  public func shear<T>(direction: vImage.ShearDirection, translate: T, slope: T, resamplingFilter: ResamplingFilter, backgroundColor: Pixel_FFFF? = (0, 0, 0, 0), destination: vImage.PixelBuffer<Format>) where T : BinaryFloatingPoint {
    _vImageWithBackground(backgroundColor, (0, 0, 0, 0) as Pixel_FFFF, as: Float.self) { background, given in
      _shearD(direction: direction, translate: Double(translate), slope: Double(slope), resamplingFilter: resamplingFilter, destination: destination, backgroundColor: given ? background : nil, nullBackgroundColor: background, verticalShearFunc: vImageVerticalShearD_ARGBFFFF, horizontalShearFunc: vImageHorizontalShearD_ARGBFFFF)
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : StaticPixelFormat {
  @usableFromInline
  internal typealias ShearFuncD<BG> = (UnsafePointer<vImage_Buffer>, UnsafePointer<vImage_Buffer>, vImagePixelCount, vImagePixelCount, Double, Double, ResamplingFilter, BG, vImage_Flags) -> vImage_Error
  @usableFromInline
  internal func _shearD<T, BG>(direction: vImage.ShearDirection, translate: Double, slope: Double, resamplingFilter: ResamplingFilter, destination: vImage.PixelBuffer<T>, backgroundColor: BG?, nullBackgroundColor: BG, verticalShearFunc: vImage.PixelBuffer<Format>.ShearFuncD<BG>, horizontalShearFunc: vImage.PixelBuffer<Format>.ShearFuncD<BG>, useFloat16Accumulator: Bool = false) where T : StaticPixelFormat {
    let flags = _vImageEdgeFlags(hasBackground: backgroundColor != nil, useFloat16Accumulator: useFloat16Accumulator)
    let background = backgroundColor ?? nullBackgroundColor
    let function = direction == .horizontal ? horizontalShearFunc : verticalShearFunc
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { function($0, $1, 0, 0, translate, slope, resamplingFilter, background, flags) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage {
  public enum ReflectionAxis : Equatable, Hashable {
    case vertical
    case horizontal
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar8 {
  public func reflect(over axis: vImage.ReflectionAxis, destination: vImage.PixelBuffer<Format>) {
    if axis == .vertical {
      _reflect(reflectFunc: { vImageHorizontalReflect_Planar8($0, $1, $2) }, destination: destination)
    } else {
      _reflect(reflectFunc: { vImageVerticalReflect_Planar8($0, $1, $2) }, destination: destination)
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar16F {
  public func reflect(over axis: vImage.ReflectionAxis, destination: vImage.PixelBuffer<Format>) {
    if axis == .vertical {
      _reflect(reflectFunc: { vImageHorizontalReflect_Planar16F($0, $1, $2) }, destination: destination)
    } else {
      _reflect(reflectFunc: { vImageVerticalReflect_Planar16F($0, $1, $2) }, destination: destination)
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved16Fx2 {
  public func reflect(over axis: vImage.ReflectionAxis, destination: vImage.PixelBuffer<Format>) {
    if axis == .vertical {
      _reflect(reflectFunc: { vImageHorizontalReflect_CbCr16F($0, $1, $2) }, destination: destination)
    } else {
      _reflect(reflectFunc: { vImageVerticalReflect_CbCr16F($0, $1, $2) }, destination: destination)
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved16Fx4 {
  public func reflect(over axis: vImage.ReflectionAxis, destination: vImage.PixelBuffer<Format>) {
    if axis == .vertical {
      _reflect(reflectFunc: { vImageHorizontalReflect_ARGB16F($0, $1, $2) }, destination: destination)
    } else {
      _reflect(reflectFunc: { vImageVerticalReflect_ARGB16F($0, $1, $2) }, destination: destination)
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved8x4 {
  public func reflect(over axis: vImage.ReflectionAxis, destination: vImage.PixelBuffer<Format>) {
    if axis == .vertical {
      _reflect(reflectFunc: { vImageHorizontalReflect_ARGB8888($0, $1, $2) }, destination: destination)
    } else {
      _reflect(reflectFunc: { vImageVerticalReflect_ARGB8888($0, $1, $2) }, destination: destination)
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved16Ux4 {
  public func reflect(over axis: vImage.ReflectionAxis, destination: vImage.PixelBuffer<Format>) {
    if axis == .vertical {
      _reflect(reflectFunc: { vImageHorizontalReflect_ARGB16U($0, $1, $2) }, destination: destination)
    } else {
      _reflect(reflectFunc: { vImageVerticalReflect_ARGB16U($0, $1, $2) }, destination: destination)
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.PlanarF {
  public func reflect(over axis: vImage.ReflectionAxis, destination: vImage.PixelBuffer<Format>) {
    if axis == .vertical {
      _reflect(reflectFunc: { vImageHorizontalReflect_PlanarF($0, $1, $2) }, destination: destination)
    } else {
      _reflect(reflectFunc: { vImageVerticalReflect_PlanarF($0, $1, $2) }, destination: destination)
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.InterleavedFx4 {
  public func reflect(over axis: vImage.ReflectionAxis, destination: vImage.PixelBuffer<Format>) {
    if axis == .vertical {
      _reflect(reflectFunc: { vImageHorizontalReflect_ARGBFFFF($0, $1, $2) }, destination: destination)
    } else {
      _reflect(reflectFunc: { vImageVerticalReflect_ARGBFFFF($0, $1, $2) }, destination: destination)
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : StaticPixelFormat {
  @usableFromInline
  internal func _reflect(reflectFunc: (UnsafePointer<vImage_Buffer>, UnsafePointer<vImage_Buffer>, vImage_Flags) -> vImage_Error, destination: vImage.PixelBuffer<Format>) {
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { reflectFunc($0, $1, vImage_Flags(kvImageNoFlags)) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar8 {
  public func scale(destination: vImage.PixelBuffer<Format>) {
    let flags = vImage_Flags(kvImageHighQualityResampling)
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImageScale_Planar8($0, $1, nil, flags) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar16F {
  public func scale(useFloat16Accumulator: Bool = false, destination: vImage.PixelBuffer<Format>) {
    let flags = (useFloat16Accumulator ? vImage_Flags(kvImageUseFP16Accumulator) : 0) | vImage_Flags(kvImageHighQualityResampling)
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImageScale_Planar16F($0, $1, nil, flags) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved8x2 {
  public func scale(destination: vImage.PixelBuffer<Format>) {
    let flags = vImage_Flags(kvImageHighQualityResampling)
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImageScale_CbCr8($0, $1, nil, flags) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved16Fx2 {
  public func scale(useFloat16Accumulator: Bool = false, destination: vImage.PixelBuffer<Format>) {
    let flags = (useFloat16Accumulator ? vImage_Flags(kvImageUseFP16Accumulator) : 0) | vImage_Flags(kvImageHighQualityResampling)
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImageScale_CbCr16F($0, $1, nil, flags) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved8x4 {
  public func scale(destination: vImage.PixelBuffer<Format>) {
    let flags = vImage_Flags(kvImageHighQualityResampling)
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImageScale_ARGB8888($0, $1, nil, flags) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved16Fx4 {
  public func scale(useFloat16Accumulator: Bool, destination: vImage.PixelBuffer<Format>) {
    let flags = (useFloat16Accumulator ? vImage_Flags(kvImageUseFP16Accumulator) : 0) | vImage_Flags(kvImageHighQualityResampling)
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImageScale_ARGB16F($0, $1, nil, flags) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar16U {
  public func scale(destination: vImage.PixelBuffer<Format>) {
    let flags = vImage_Flags(kvImageHighQualityResampling)
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImageScale_Planar16U($0, $1, nil, flags) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved16Ux2 {
  public func scale(destination: vImage.PixelBuffer<Format>) {
    let flags = vImage_Flags(kvImageHighQualityResampling)
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImageScale_CbCr16U($0, $1, nil, flags) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved16Ux4 {
  public func scale(destination: vImage.PixelBuffer<Format>) {
    let flags = vImage_Flags(kvImageHighQualityResampling)
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImageScale_ARGB16U($0, $1, nil, flags) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.PlanarF {
  public func scale(destination: vImage.PixelBuffer<Format>) {
    let flags = vImage_Flags(kvImageHighQualityResampling)
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImageScale_PlanarF($0, $1, nil, flags) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.InterleavedFx4 {
  public func scale(destination: vImage.PixelBuffer<Format>) {
    let flags = vImage_Flags(kvImageHighQualityResampling)
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImageScale_ARGBFFFF($0, $1, nil, flags) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar8 {
  public func transform(_ transform: CGAffineTransform, backgroundColor: Pixel_8? = Pixel_8(0), destination: vImage.PixelBuffer<Format>) {
    _affineWarp(transform, destination: destination, backgroundColor: backgroundColor, nullBackgroundColor: 0, affineWarpFunc: vImageAffineWarpCG_Planar8)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar16F {
  public func transform(_ transform: CGAffineTransform, backgroundColor: Pixel_16F? = Pixel_16F(0), useFloat16Accumulator: Bool = false, destination: vImage.PixelBuffer<Format>) {
    _affineWarpD(transform, destination: destination, backgroundColor: backgroundColor, nullBackgroundColor: 0, affineWarpFunc: vImageAffineWarpD_Planar16F, useFloat16Accumulator: useFloat16Accumulator)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved16Fx2 {
  public func transform(_ transform: CGAffineTransform, backgroundColor: Pixel_16F16F? = (0, 0), useFloat16Accumulator: Bool = false, destination: vImage.PixelBuffer<Format>) {
    _vImageWithBackground(backgroundColor, (0, 0) as Pixel_16F16F, as: UInt16.self) { background, given in
      _affineWarpD(transform, destination: destination, backgroundColor: given ? background : nil, nullBackgroundColor: background, affineWarpFunc: vImageAffineWarpD_CbCr16F, useFloat16Accumulator: useFloat16Accumulator)
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved16Fx4 {
  public func transform(_ transform: CGAffineTransform, backgroundColor: Pixel_ARGB_16F? = (0, 0, 0, 0), useFloat16Accumulator: Bool = false, destination: vImage.PixelBuffer<Format>) {
    _vImageWithBackground(backgroundColor, (0, 0, 0, 0) as Pixel_ARGB_16F, as: UInt16.self) { background, given in
      _affineWarpD(transform, destination: destination, backgroundColor: given ? background : nil, nullBackgroundColor: background, affineWarpFunc: vImageAffineWarpD_ARGB16F, useFloat16Accumulator: useFloat16Accumulator)
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved8x4 {
  public func transform(_ transform: CGAffineTransform, backgroundColor: Pixel_8888? = (0, 0, 0, 0), destination: vImage.PixelBuffer<Format>) {
    _vImageWithBackground(backgroundColor, (0, 0, 0, 0) as Pixel_8888, as: UInt8.self) { background, given in
      _affineWarp(transform, destination: destination, backgroundColor: given ? background : nil, nullBackgroundColor: background, affineWarpFunc: vImageAffineWarpCG_ARGB8888)
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved16Ux4 {
  public func transform(_ transform: CGAffineTransform, backgroundColor: Pixel_ARGB_16U? = (0, 0, 0, 0), destination: vImage.PixelBuffer<Format>) {
    _vImageWithBackground(backgroundColor, (0, 0, 0, 0) as Pixel_ARGB_16U, as: UInt16.self) { background, given in
      _affineWarp(transform, destination: destination, backgroundColor: given ? background : nil, nullBackgroundColor: background, affineWarpFunc: vImageAffineWarpCG_ARGB16U)
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.PlanarF {
  public func transform(_ transform: CGAffineTransform, backgroundColor: Pixel_F? = Pixel_F(0), destination: vImage.PixelBuffer<Format>) {
    _affineWarp(transform, destination: destination, backgroundColor: backgroundColor, nullBackgroundColor: 0, affineWarpFunc: vImageAffineWarpCG_PlanarF)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.InterleavedFx4 {
  public func transform(_ transform: CGAffineTransform, backgroundColor: Pixel_FFFF? = (0, 0, 0, 0), destination: vImage.PixelBuffer<Format>) {
    _vImageWithBackground(backgroundColor, (0, 0, 0, 0) as Pixel_FFFF, as: Float.self) { background, given in
      _affineWarp(transform, destination: destination, backgroundColor: given ? background : nil, nullBackgroundColor: background, affineWarpFunc: vImageAffineWarpCG_ARGBFFFF)
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : StaticPixelFormat {
  @usableFromInline
  internal typealias AffineWarpFunc<BG> = (UnsafePointer<vImage_Buffer>, UnsafePointer<vImage_Buffer>, UnsafeMutableRawPointer?, UnsafePointer<vImage_CGAffineTransform>, BG, vImage_Flags) -> vImage_Error
  @usableFromInline
  internal func _affineWarp<BG>(_ transform: CGAffineTransform, destination: vImage.PixelBuffer<Format>, backgroundColor: BG?, nullBackgroundColor: BG, affineWarpFunc: vImage.PixelBuffer<Format>.AffineWarpFunc<BG>) {
    let flags = _vImageEdgeFlags(hasBackground: backgroundColor != nil)
    let background = backgroundColor ?? nullBackgroundColor
    var matrix = vImage_CGAffineTransform(a: Double(transform.a), b: Double(transform.b), c: Double(transform.c), d: Double(transform.d), tx: Double(transform.tx), ty: Double(transform.ty))
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { affineWarpFunc($0, $1, nil, &matrix, background, flags) }
  }
  @usableFromInline
  internal typealias AffineWarpFuncD<BG> = (UnsafePointer<vImage_Buffer>, UnsafePointer<vImage_Buffer>, UnsafeMutableRawPointer?, UnsafePointer<vImage_AffineTransform_Double>, BG, vImage_Flags) -> vImage_Error
  @usableFromInline
  internal func _affineWarpD<BG>(_ transform: CGAffineTransform, destination: vImage.PixelBuffer<Format>, backgroundColor: BG?, nullBackgroundColor: BG, affineWarpFunc: vImage.PixelBuffer<Format>.AffineWarpFuncD<BG>, useFloat16Accumulator: Bool = false) {
    let flags = _vImageEdgeFlags(hasBackground: backgroundColor != nil, useFloat16Accumulator: useFloat16Accumulator)
    let background = backgroundColor ?? nullBackgroundColor
    var matrix = vImage_AffineTransform_Double(a: transform.a, b: transform.b, c: transform.c, d: transform.d, tx: transform.tx, ty: transform.ty)
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { affineWarpFunc($0, $1, nil, &matrix, background, flags) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage_AffineTransform_Double {
  public init(a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat) {
    self.init(a: Double(a), b: Double(b), c: Double(c), d: Double(d), tx: Double(tx), ty: Double(ty))
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage_AffineTransform {
  public init(a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat) {
    self.init(a: Float(a), b: Float(b), c: Float(c), d: Float(d), tx: Float(tx), ty: Float(ty))
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : StaticPixelFormat, Format.ComponentType == Float {
  public func clip(to bounds: ClosedRange<Float>, destination: vImage.PixelBuffer<Format>) {
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    _vImageRun(_vImageWidened(_vImageBuffers[0], by: Format.channelCount), _vImageWidened(destination._vImageBuffers[0], by: Format.channelCount)) {
      vImageClip_PlanarF($0, $1, bounds.upperBound, bounds.lowerBound, vImage_Flags(kvImageNoFlags))
    }
  }
  public func colorThreshold(_ threshold: Float, destination: vImage.PixelBuffer<Format>) {
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    _vImageMapFloats([_vImageBuffers[0]], into: destination._vImageBuffers[0], components: Format.channelCount) { $0[0] >= threshold ? 1 : 0 }
  }
  public func linearInterpolate(bufferB: vImage.PixelBuffer<Format>, interpolationConstant: Float, destination: vImage.PixelBuffer<Format>) {
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    _vImageCheckSizes(bufferB._vImageBuffers[0], destination._vImageBuffers[0])
    _vImageMapFloats([_vImageBuffers[0], bufferB._vImageBuffers[0]], into: destination._vImageBuffers[0], components: Format.channelCount) {
      $0[0] + interpolationConstant * ($0[1] - $0[0])
    }
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension vImage {
  public enum Error : Int, Swift.Error, Equatable, Hashable {
    case noError
    case roiLargerThanInputBuffer
    case invalidKernelSize
    case invalidEdgeStyle
    case invalidOffset_X
    case invalidOffset_Y
    case memoryAllocationError
    case nullPointerArgument
    case invalidParameter
    case bufferSizeMismatch
    case unknownFlagsBit
    case internalError
    case invalidRowBytes
    case invalidImageFormat
    case colorSyncIsAbsent
    case outOfPlaceOperationRequired
    case invalidImageObject
    case invalidCVImageFormat
    case unsupportedConversion
    case coreVideoIsAbsent
    public init(vImageError: vImage_Error) {
      self = vImage.Error(rawValue: vImageError) ?? .internalError
    }
    public init?(rawValue: Int) {
      if rawValue == 0 { self = .noError; return }
      let index = -21766 - rawValue
      guard index >= 0 && index < vImage.Error._cases.count else { return nil }
      self = vImage.Error._cases[index]
    }
    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    public typealias RawValue = Int
    public var rawValue: Int {
      get {
        return _vImageCode
      }
    }
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension vImageConverter {
  public func sourceBuffers(colorSpace: CGColorSpace) -> [vImage.BufferType?] {
    guard let order = vImageConverter_GetSourceBufferOrder(self) else { return [] }
    return (0..<sourceBufferCount).map { vImage.BufferType(bufferTypeCode: Int(order[$0]), model: colorSpace.model) }
  }
  public func destinationBuffers(colorSpace: CGColorSpace) -> [vImage.BufferType?] {
    guard let order = vImageConverter_GetDestinationBufferOrder(self) else { return [] }
    return (0..<destinationBufferCount).map { vImage.BufferType(bufferTypeCode: Int(order[$0]), model: colorSpace.model) }
  }
  public var sourceBufferCount: Int {
    get { Int(vImageConverter_GetNumberOfSourceBuffers(self)) }
  }
  public var destinationBufferCount: Int {
    get { Int(vImageConverter_GetNumberOfDestinationBuffers(self)) }
  }
  public func mustOperateOutOfPlace(source: vImage_Buffer, destination: vImage_Buffer, flags options: vImage.Options = .noFlags) throws -> Bool {
    var source = source
    var destination = destination
    let error = vImageConverter_MustOperateOutOfPlace(self, &source, &destination, options.flags)
    if error == kvImageOutOfPlaceOperationRequired { return true }
    try vImage.Error._check(error)
    return false
  }
  public static func make(sourceFormat: vImage_CGImageFormat, destinationFormat: vImage_CGImageFormat, flags options: vImage.Options = .noFlags) throws -> vImageConverter {
    var source = sourceFormat
    var destination = destinationFormat
    var error = vImage_Error(kvImageNoError)
    let converter = vImageConverter_CreateWithCGImageFormat(&source, &destination, nil, options.flags, &error)
    try vImage.Error._check(error)
    guard let converter else { throw vImage.Error.unsupportedConversion }
    return converter.takeRetainedValue()
  }
  public static func make(sourceFormat: vImage_CGImageFormat, destinationFormat: vImageCVImageFormat, flags options: vImage.Options = .noFlags) throws -> vImageConverter {
    var source = sourceFormat
    var error = vImage_Error(kvImageNoError)
    let converter = vImageConverter_CreateForCGToCVImageFormat(&source, destinationFormat, nil, options.flags, &error)
    try vImage.Error._check(error)
    guard let converter else { throw vImage.Error.unsupportedConversion }
    return converter.takeRetainedValue()
  }
  public static func make(sourceFormat: vImageCVImageFormat, destinationFormat: vImage_CGImageFormat, flags options: vImage.Options = .noFlags) throws -> vImageConverter {
    var destination = destinationFormat
    var error = vImage_Error(kvImageNoError)
    let converter = vImageConverter_CreateForCVToCGImageFormat(sourceFormat, &destination, nil, options.flags, &error)
    try vImage.Error._check(error)
    guard let converter else { throw vImage.Error.unsupportedConversion }
    return converter.takeRetainedValue()
  }
  public func convert(source: vImage_Buffer, destination: inout vImage_Buffer, flags options: vImage.Options = .noFlags) throws {
    var source = source
    try vImage.Error._check(vImageConvert_AnyToAny(self, &source, &destination, nil, options.flags))
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved16Ux2 {
  public func convert(to destination: vImage.PixelBuffer<vImage.Interleaved16Fx2>) {
    _convertComponents(to: destination)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImageConverter {
  public func convert<Src, Dest>(from source: vImage.PixelBuffer<Src>, to destination: vImage.PixelBuffer<Dest>) throws where Src : SinglePlanePixelFormat, Dest : SinglePlanePixelFormat {
    var sources = source._vImageBuffers
    var destinations = destination._vImageBuffers
    try vImage.Error._check(vImageConvert_AnyToAny(self, &sources, &destinations, nil, vImage_Flags(kvImageNoFlags)))
  }
  public func convert<F1, F2>(from sources: [vImage.PixelBuffer<F1>], to destinations: [vImage.PixelBuffer<F2>]) throws where F1 : SinglePlanePixelFormat, F2 : SinglePlanePixelFormat {
    var sourceBuffers = sources.map { $0._vImageBuffers[0] }
    var destinationBuffers = destinations.map { $0._vImageBuffers[0] }
    try vImage.Error._check(vImageConvert_AnyToAny(self, &sourceBuffers, &destinationBuffers, nil, vImage_Flags(kvImageNoFlags)))
  }
  public static func make(sourceFormat: vImage_CGImageFormat, destinationFormat: vImage_CGImageFormat, colorConversionInfo: CGColorConversionInfo) throws -> vImageConverter {
    var source = sourceFormat
    var destination = destinationFormat
    var error = vImage_Error(kvImageNoError)
    let converter = vImageConverter_CreateWithCGColorConversionInfo(colorConversionInfo, &source, &destination, nil, vImage_Flags(kvImageNoFlags), &error)
    try vImage.Error._check(error)
    guard let converter else { throw vImage.Error.unsupportedConversion }
    return converter.takeRetainedValue()
  }
  public func makeCVToCGPixelBuffers(referencing lockedCVPixelBuffer: CVPixelBuffer) throws -> [vImage.PixelBuffer<vImage.DynamicPixelFormat>] {
    var buffers = [vImage_Buffer](repeating: vImage_Buffer(), count: sourceBufferCount)
    try vImage.Error._check(vImageBuffer_InitForCopyFromCVPixelBuffer(&buffers, self, lockedCVPixelBuffer, vImage_Flags(kvImageNoAllocate)))
    let storage = _vImagePixelStorage()
    storage.retained.append(lockedCVPixelBuffer)
    return buffers.map { vImage.PixelBuffer<vImage.DynamicPixelFormat>(_buffers: [$0], storage: storage) }
  }
  public func makeCGToCVPixelBuffers(referencing lockedCVPixelBuffer: CVPixelBuffer) throws -> [vImage.PixelBuffer<vImage.DynamicPixelFormat>] {
    var buffers = [vImage_Buffer](repeating: vImage_Buffer(), count: destinationBufferCount)
    try vImage.Error._check(vImageBuffer_InitForCopyToCVPixelBuffer(&buffers, self, lockedCVPixelBuffer, vImage_Flags(kvImageNoAllocate)))
    let storage = _vImagePixelStorage()
    storage.retained.append(lockedCVPixelBuffer)
    return buffers.map { vImage.PixelBuffer<vImage.DynamicPixelFormat>(_buffers: [$0], storage: storage) }
  }
}
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
extension AccelerateMutableBuffer where Self.Element == UInt8 {
  public mutating func withUnsafePixelBuffer<R>(body: (vImage.PixelBuffer<vImage.Planar8>) throws -> R) rethrows -> R {
    return try withUnsafeMutableBufferPointer { pointer in
      try _vImageWithRawBuffer(pointer) { try body(vImage.PixelBuffer<vImage.Planar8>(data: $0, width: pointer.count, height: 1, byteCountPerRow: $1)) }
    }
  }
}
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
extension AccelerateMutableBuffer where Self.Element == Float {
  public mutating func withUnsafePixelBuffer<R>(body: (vImage.PixelBuffer<vImage.PlanarF>) throws -> R) rethrows -> R {
    return try withUnsafeMutableBufferPointer { pointer in
      try _vImageWithRawBuffer(pointer) { try body(vImage.PixelBuffer<vImage.PlanarF>(data: $0, width: pointer.count, height: 1, byteCountPerRow: $1)) }
    }
  }
}
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
extension AccelerateMutableBuffer where Self.Element == UInt16 {
  public mutating func withUnsafePixelBuffer<R>(body: (vImage.PixelBuffer<vImage.Planar16U>) throws -> R) rethrows -> R {
    return try withUnsafeMutableBufferPointer { pointer in
      try _vImageWithRawBuffer(pointer) { try body(vImage.PixelBuffer<vImage.Planar16U>(data: $0, width: pointer.count, height: 1, byteCountPerRow: $1)) }
    }
  }
}
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
extension vImage.PixelBuffer : AccelerateMatrixBuffer where Format : StaticPixelFormat {
  public var rowCount: Int {
    get { height }
  }
  public var columnCount: Int {
    get { width * Format.channelCount }
  }
  public var accelerateMatrixOrder: AccelerateMatrixOrder {
    get { .rowMajor }
  }
  public var leadingDimension: Int {
    get { rowStride }
  }
}
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
extension vImage.PixelBuffer : AccelerateMutableMatrixBuffer where Format : StaticPixelFormat {
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.InterleavedFx3 {
  public init(planarBuffers: [vImage.PixelBuffer<vImage.PlanarF>]) {
    self.init(_interleaving: planarBuffers)
  }
  public func convert(to destination: vImage.PixelBuffer<vImage.Interleaved8x3>) {
    _convertComponents(to: destination)
  }
  public func planarBuffers() -> [vImage.PixelBuffer<vImage.PlanarF>] {
    return _planarBuffers(vImage.PlanarF.self)
  }
  public func interleave(planarSourceBuffers: [vImage.PixelBuffer<vImage.PlanarF>]) {
    _interleave(planarSourceBuffers)
  }
  public func deinterleave(planarDestinationBuffers: [vImage.PixelBuffer<vImage.PlanarF>]) {
    _deinterleave(into: planarDestinationBuffers.map { $0._vImageBuffers[0] }, as: vImage.PlanarF.self)
  }
  public func deinterleave(destination: vImage.PixelBuffer<vImage.PlanarFx3>) {
    destination._deinterleave(from: self)
  }
}
@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar8 {
  public func applyLookup(_ lookupTable: [Pixel_8], destination: vImage.PixelBuffer<vImage.Planar8>) {
    precondition(lookupTable.count == 256, "the lookup table has the wrong number of entries")
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    lookupTable.withUnsafeBufferPointer { table in
      _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImageTableLookUp_Planar8($0, $1, table.baseAddress!, vImage_Flags(kvImageNoFlags)) }
    }
  }
  public func applyLookup(_ lookupTable: [Pixel_16U], destination: vImage.PixelBuffer<vImage.Planar16U>) {
    precondition(lookupTable.count == 256, "the lookup table has the wrong number of entries")
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    lookupTable.withUnsafeBufferPointer { table in
      _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImageLookupTable_Planar8toPlanar16($0, $1, table.baseAddress!, vImage_Flags(kvImageNoFlags)) }
    }
  }
  public func applyLookup(_ lookupTable: [Pixel_F], destination: vImage.PixelBuffer<vImage.PlanarF>) {
    precondition(lookupTable.count == 256, "the lookup table has the wrong number of entries")
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    lookupTable.withUnsafeBufferPointer { table in
      _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImageLookupTable_Planar8toPlanarF($0, $1, table.baseAddress!, vImage_Flags(kvImageNoFlags)) }
    }
  }
  public func applyLookup(_ lookupTable: [Pixel_8888], destination: vImage.PixelBuffer<vImage.Interleaved8x3>) {
    precondition(lookupTable.count == 256, "the lookup table has the wrong number of entries")
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    lookupTable.withUnsafeBufferPointer { table in
      _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImageLookupTable_Planar8toPlanar24($0, $1, UnsafeRawPointer(table.baseAddress!).assumingMemoryBound(to: UInt32.self), vImage_Flags(kvImageNoFlags)) }
    }
  }
  public func applyLookup(_ lookupTable: [Pixel_FFFF], destination: vImage.PixelBuffer<vImage.InterleavedFx3>) {
    precondition(lookupTable.count == 256, "the lookup table has the wrong number of entries")
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    lookupTable.withUnsafeBufferPointer { table in
      _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImageLookupTable_Planar8toPlanar96($0, $1, table.baseAddress!, vImage_Flags(kvImageNoFlags)) }
    }
  }
}
@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved8x4 {
  public func applyLookup(alphaTable: [Pixel_8]?, redTable: [Pixel_8]?, greenTable: [Pixel_8]?, blueTable: [Pixel_8]?, destination: vImage.PixelBuffer<vImage.Interleaved8x4>) {
    let identity = (0..<256).map { Pixel_8($0) }
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    for table in [alphaTable, redTable, greenTable, blueTable] { precondition(table == nil || table!.count == 256, "a lookup table has 256 entries") }
    let a = alphaTable ?? identity, r = redTable ?? identity, g = greenTable ?? identity, bl = blueTable ?? identity
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImageTableLookUp_ARGB8888($0, $1, a, r, g, bl, vImage_Flags(kvImageNoFlags)) }
  }
}
@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension vImage.PixelBuffer where Format == vImage.PlanarF {
  public func applyLookup(_ lookupTable: [Pixel_8], destination: vImage.PixelBuffer<vImage.Planar8>) {
    precondition(lookupTable.count == 4096, "the lookup table has the wrong number of entries")
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    lookupTable.withUnsafeBufferPointer { table in
      _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImageLookupTable_PlanarFtoPlanar8($0, $1, table.baseAddress!, vImage_Flags(kvImageNoFlags)) }
    }
  }
  public func applyLookup(_ lookupTable: [Pixel_F], destination: vImage.PixelBuffer<vImage.PlanarF>) {
    precondition(lookupTable.count >= 2, "the lookup table has the wrong number of entries")
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    lookupTable.withUnsafeBufferPointer { table in
      _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImageInterpolatedLookupTable_PlanarF($0, $1, table.baseAddress!, vImagePixelCount(table.count), 1, 0, vImage_Flags(kvImageNoFlags)) }
    }
  }
}
@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar16U {
  public func applyLookup(_ lookupTable: [Pixel_16U], destination: vImage.PixelBuffer<vImage.Planar16U>) {
    precondition(lookupTable.count == 0x10000, "the lookup table has the wrong number of entries")
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    lookupTable.withUnsafeBufferPointer { table in
      _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImageLookupTable_Planar16($0, $1, table.baseAddress!, vImage_Flags(kvImageNoFlags)) }
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
public protocol PixelFormat {
  associatedtype ComponentType : Equatable
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
public protocol SinglePlanePixelFormat : PixelFormat {
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
public protocol MultiplePlanePixelFormat : PixelFormat {
  associatedtype PlanarPixelFormat : StaticPixelFormat
  static var planeCount: Int { get }
  static var bitCountPerPlanarPixel: Int { get }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
public protocol StaticPixelFormat : SinglePlanePixelFormat {
  static var bitCountPerPixel: Int { get }
  static var channelCount: Int { get }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
public protocol InitializableFromCGImage : SinglePlanePixelFormat {
  static var bitCountPerComponent: Int { get }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage {
  public struct Planar8x2 : PixelFormat, MultiplePlanePixelFormat {
    public typealias ComponentType = Pixel_8
    public typealias PlanarPixelFormat = vImage.Planar8
    public static var bitCountPerPlanarPixel: Int {
      get { 8 }
    }
    public static var planeCount: Int {
      get { 2 }
    }
  }
  public struct Planar8x3 : PixelFormat, MultiplePlanePixelFormat {
    public typealias ComponentType = Pixel_8
    public typealias PlanarPixelFormat = vImage.Planar8
    public static var bitCountPerPlanarPixel: Int {
      get { 8 }
    }
    public static var planeCount: Int {
      get { 3 }
    }
  }
  public struct Planar8x4 : PixelFormat, MultiplePlanePixelFormat {
    public typealias ComponentType = Pixel_8
    public typealias PlanarPixelFormat = vImage.Planar8
    public static var bitCountPerPlanarPixel: Int {
      get { 8 }
    }
    public static var planeCount: Int {
      get { 4 }
    }
  }
  public struct PlanarFx2 : PixelFormat, MultiplePlanePixelFormat {
    public typealias ComponentType = Pixel_F
    public typealias PlanarPixelFormat = vImage.PlanarF
    public static var bitCountPerPlanarPixel: Int {
      get { 32 }
    }
    public static var planeCount: Int {
      get { 2 }
    }
  }
  public struct PlanarFx3 : PixelFormat, MultiplePlanePixelFormat {
    public typealias ComponentType = Pixel_F
    public typealias PlanarPixelFormat = vImage.PlanarF
    public static var bitCountPerPlanarPixel: Int {
      get { 32 }
    }
    public static var planeCount: Int {
      get { 3 }
    }
  }
  public struct PlanarFx4 : PixelFormat, MultiplePlanePixelFormat {
    public typealias ComponentType = Pixel_F
    public typealias PlanarPixelFormat = vImage.PlanarF
    public static var bitCountPerPlanarPixel: Int {
      get { 32 }
    }
    public static var planeCount: Int {
      get { 4 }
    }
  }
  public struct DynamicPixelFormat : SinglePlanePixelFormat {
    public typealias ComponentType = Never
  }
  public struct Planar8 : InitializableFromCGImage, StaticPixelFormat {
    public typealias ComponentType = Pixel_8
    public static var channelCount: Int {
      get { 1 }
    }
    public static var bitCountPerComponent: Int {
      get { 8 }
    }
    public static var bitCountPerPixel: Int {
      get { 8 }
    }
  }
  public struct Interleaved8x2 : StaticPixelFormat {
    public typealias ComponentType = Pixel_8
    public static var channelCount: Int {
      get { 2 }
    }
    public static var bitCountPerPixel: Int {
      get { 16 }
    }
  }
  public struct Interleaved8x3 : InitializableFromCGImage, StaticPixelFormat {
    public typealias ComponentType = Pixel_8
    public static var channelCount: Int {
      get { 3 }
    }
    public static var bitCountPerComponent: Int {
      get { 8 }
    }
    public static var bitCountPerPixel: Int {
      get { 24 }
    }
  }
  public struct Interleaved8x4 : InitializableFromCGImage, StaticPixelFormat {
    public typealias ComponentType = Pixel_8
    public static var channelCount: Int {
      get { 4 }
    }
    public static var bitCountPerComponent: Int {
      get { 8 }
    }
    public static var bitCountPerPixel: Int {
      get { 32 }
    }
  }
  public struct Planar16F : InitializableFromCGImage, StaticPixelFormat {
    public typealias ComponentType = Pixel_16F
    public static var channelCount: Int {
      get { 1 }
    }
    public static var bitCountPerComponent: Int {
      get { 16 }
    }
    public static var bitCountPerPixel: Int {
      get { 16 }
    }
  }
  public struct Interleaved16Fx2 : StaticPixelFormat {
    public typealias ComponentType = Pixel_16F
    public static var channelCount: Int {
      get { 2 }
    }
    public static var bitCountPerPixel: Int {
      get { 32 }
    }
  }
  public struct Interleaved16Fx4 : InitializableFromCGImage, StaticPixelFormat {
    public typealias ComponentType = Pixel_16F
    public static var channelCount: Int {
      get { 4 }
    }
    public static var bitCountPerComponent: Int {
      get { 16 }
    }
    public static var bitCountPerPixel: Int {
      get { 64 }
    }
  }
  public struct PlanarF : InitializableFromCGImage, StaticPixelFormat {
    public typealias ComponentType = Pixel_F
    public static var channelCount: Int {
      get { 1 }
    }
    public static var bitCountPerComponent: Int {
      get { 32 }
    }
    public static var bitCountPerPixel: Int {
      get { 32 }
    }
  }
  public struct InterleavedFx2 : StaticPixelFormat {
    public typealias ComponentType = Pixel_F
    public static var channelCount: Int {
      get { 2 }
    }
    public static var bitCountPerPixel: Int {
      get { 64 }
    }
  }
  public struct InterleavedFx3 : InitializableFromCGImage, StaticPixelFormat {
    public typealias ComponentType = Pixel_F
    public static var channelCount: Int {
      get { 3 }
    }
    public static var bitCountPerComponent: Int {
      get { 32 }
    }
    public static var bitCountPerPixel: Int {
      get { 96 }
    }
  }
  public struct InterleavedFx4 : InitializableFromCGImage, StaticPixelFormat {
    public typealias ComponentType = Pixel_F
    public static var channelCount: Int {
      get { 4 }
    }
    public static var bitCountPerComponent: Int {
      get { 32 }
    }
    public static var bitCountPerPixel: Int {
      get { 128 }
    }
  }
  public struct Planar16U : StaticPixelFormat {
    public typealias ComponentType = Pixel_16U
    public static var channelCount: Int {
      get { 1 }
    }
    public static var bitCountPerPixel: Int {
      get { 16 }
    }
  }
  public struct Interleaved16Ux2 : InitializableFromCGImage, StaticPixelFormat {
    public typealias ComponentType = Pixel_16U
    public static var channelCount: Int {
      get { 2 }
    }
    public static var bitCountPerComponent: Int {
      get { 16 }
    }
    public static var bitCountPerPixel: Int {
      get { 32 }
    }
  }
  public struct Interleaved16Ux4 : InitializableFromCGImage, StaticPixelFormat {
    public typealias ComponentType = Pixel_16U
    public static var channelCount: Int {
      get { 4 }
    }
    public static var bitCountPerComponent: Int {
      get { 16 }
    }
    public static var bitCountPerPixel: Int {
      get { 64 }
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.Planar16F {
  public static func makePixel(_ source: Pixel_F) -> Pixel_16F {
    var result: Pixel_16F = 0
    convert(src: source, dest: &result, convertFunc: { vImageConvert_PlanarFtoPlanar16F($0, $1, $2) }, channelCount: 1)
    return result
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.Interleaved16Fx2 {
  public static func makePixel(_ source: Pixel_FF) -> Pixel_16F16F {
    var result: Pixel_16F16F = (0, 0)
    convert(src: source, dest: &result, convertFunc: { vImageConvert_PlanarFtoPlanar16F($0, $1, $2) }, channelCount: 2)
    return result
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.Interleaved16Fx4 {
  public static func makePixel(_ source: Pixel_FFFF) -> Pixel_ARGB_16F {
    var result: Pixel_ARGB_16F = (0, 0, 0, 0)
    convert(src: source, dest: &result, convertFunc: { vImageConvert_PlanarFtoPlanar16F($0, $1, $2) }, channelCount: 4)
    return result
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PlanarF {
  public static func makePixel(_ source: Pixel_16F) -> Pixel_F {
    var result: Pixel_F = 0
    convert(src: source, dest: &result, convertFunc: { vImageConvert_Planar16FtoPlanarF($0, $1, $2) }, channelCount: 1)
    return result
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.InterleavedFx2 {
  public static func makePixel(_ source: Pixel_16F16F) -> Pixel_FF {
    var result: Pixel_FF = (0, 0)
    convert(src: source, dest: &result, convertFunc: { vImageConvert_Planar16FtoPlanarF($0, $1, $2) }, channelCount: 2)
    return result
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.InterleavedFx4 {
  public static func makePixel(_ source: Pixel_ARGB_16F) -> Pixel_FFFF {
    var result: Pixel_FFFF = (0, 0, 0, 0)
    convert(src: source, dest: &result, convertFunc: { vImageConvert_Planar16FtoPlanarF($0, $1, $2) }, channelCount: 4)
    return result
  }
}
@usableFromInline
internal func convert<Src, Dest>(src: Src, dest: inout Dest, convertFunc: (UnsafePointer<vImage_Buffer>, UnsafePointer<vImage_Buffer>, vImage_Flags) -> Int, channelCount: Int) {
  var source = src
  withUnsafeMutableBytes(of: &source) { s in
    withUnsafeMutableBytes(of: &dest) { d in
      var input = vImage_Buffer(data: s.baseAddress, height: 1, width: vImagePixelCount(channelCount), rowBytes: s.count)
      var output = vImage_Buffer(data: d.baseAddress, height: 1, width: vImagePixelCount(channelCount), rowBytes: d.count)
      _ = convertFunc(&input, &output, vImage_Flags(kvImageNoFlags))
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved8x4 {
  public func applyMorphology(operation: vImage.MorphologyOperation<Pixel_8>, destination: vImage.PixelBuffer<Format>) {
    _applyMorphology(operation: operation, destination: destination, erodeFunc: vImageErode_ARGB8888, dilateFunc: vImageDilate_ARGB8888, minFunc: vImageMin_ARGB8888, maxFunc: vImageMax_ARGB8888)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar8 {
  public func applyMorphology(operation: vImage.MorphologyOperation<Pixel_8>, destination: vImage.PixelBuffer<Format>) {
    _applyMorphology(operation: operation, destination: destination, erodeFunc: vImageErode_Planar8, dilateFunc: vImageDilate_Planar8, minFunc: vImageMin_Planar8, maxFunc: vImageMax_Planar8)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : MultiplePlanePixelFormat, Format.ComponentType == UInt8, Format.PlanarPixelFormat.ComponentType == UInt8 {
  public func applyMorphology(operation: vImage.MorphologyOperation<Format.ComponentType>, destination: vImage.PixelBuffer<Format>) {
    for (source, target) in zip(_vImageBuffers, destination._vImageBuffers) {
      vImage.PixelBuffer<vImage.Planar8>(_buffers: [source], storage: nil).applyMorphology(operation: operation, destination: vImage.PixelBuffer<vImage.Planar8>(_buffers: [target], storage: nil))
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.InterleavedFx4 {
  public func applyMorphology(operation: vImage.MorphologyOperation<Pixel_F>, destination: vImage.PixelBuffer<Format>) {
    _applyMorphology(operation: operation, destination: destination, erodeFunc: vImageErode_ARGBFFFF, dilateFunc: vImageDilate_ARGBFFFF, minFunc: vImageMin_ARGBFFFF, maxFunc: vImageMax_ARGBFFFF)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.PlanarF {
  public func applyMorphology(operation: vImage.MorphologyOperation<Pixel_F>, destination: vImage.PixelBuffer<Format>) {
    _applyMorphology(operation: operation, destination: destination, erodeFunc: vImageErode_PlanarF, dilateFunc: vImageDilate_PlanarF, minFunc: vImageMin_PlanarF, maxFunc: vImageMax_PlanarF)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : MultiplePlanePixelFormat, Format.ComponentType == Float, Format.PlanarPixelFormat.ComponentType == Float {
  public func applyMorphology(operation: vImage.MorphologyOperation<Format.ComponentType>, destination: vImage.PixelBuffer<Format>) {
    for (source, target) in zip(_vImageBuffers, destination._vImageBuffers) {
      vImage.PixelBuffer<vImage.PlanarF>(_buffers: [source], storage: nil).applyMorphology(operation: operation, destination: vImage.PixelBuffer<vImage.PlanarF>(_buffers: [target], storage: nil))
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : StaticPixelFormat {
  @usableFromInline
  internal typealias MorphologyErodeDilateFunc<T> = (UnsafePointer<vImage_Buffer>, UnsafePointer<vImage_Buffer>, vImagePixelCount, vImagePixelCount, UnsafePointer<T>, vImagePixelCount, vImagePixelCount, vImage_Flags) -> vImage_Error
  @usableFromInline
  internal typealias MorphologyMinMaxFunc = (UnsafePointer<vImage_Buffer>, UnsafePointer<vImage_Buffer>, UnsafeMutableRawPointer?, vImagePixelCount, vImagePixelCount, vImagePixelCount, vImagePixelCount, vImage_Flags) -> vImage_Error
  @usableFromInline
  internal func _applyMorphology<T, U>(operation: vImage.MorphologyOperation<U>, destination: vImage.PixelBuffer<T>, erodeFunc: vImage.PixelBuffer<Format>.MorphologyErodeDilateFunc<U>, dilateFunc: vImage.PixelBuffer<Format>.MorphologyErodeDilateFunc<U>, minFunc: vImage.PixelBuffer<Format>.MorphologyMinMaxFunc, maxFunc: vImage.PixelBuffer<Format>.MorphologyMinMaxFunc) where T : StaticPixelFormat, U == T.ComponentType {
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    let flags = vImage_Flags(kvImageNoFlags)
    switch operation {
    case .maximize(let size):
      _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { maxFunc($0, $1, nil, 0, 0, vImagePixelCount(size.height), vImagePixelCount(size.width), flags) }
    case .minimize(let size):
      _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { minFunc($0, $1, nil, 0, 0, vImagePixelCount(size.height), vImagePixelCount(size.width), flags) }
    case .dilate(let element):
      element.values.withUnsafeBufferPointer { k in
        _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { dilateFunc($0, $1, 0, 0, k.baseAddress!, element.height, element.width, flags) }
      }
    case .erode(let element):
      element.values.withUnsafeBufferPointer { k in
        _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { erodeFunc($0, $1, 0, 0, k.baseAddress!, element.height, element.width, flags) }
      }
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage {
  public typealias StructuringElement = vImage.ConvolutionKernel2D
  public enum MorphologyOperation<ComponentType> {
    case maximize(kernelSize: vImage.Size)
    case minimize(kernelSize: vImage.Size)
    case dilate(structuringElement: vImage.ConvolutionKernel2D<ComponentType>)
    case erode(structuringElement: vImage.ConvolutionKernel2D<ComponentType>)
    public var structuringElement: vImage.ConvolutionKernel2D<ComponentType>? {
      get {
        switch self {
        case .dilate(let element), .erode(let element): return element
        default: return nil
        }
      }
    }
    public var width: vImagePixelCount {
      get {
        switch self {
        case .maximize(let size), .minimize(let size): return vImagePixelCount(size.width)
        case .dilate(let element), .erode(let element): return element.width
        }
      }
    }
    public var height: vImagePixelCount {
      get {
        switch self {
        case .maximize(let size), .minimize(let size): return vImagePixelCount(size.height)
        case .dilate(let element), .erode(let element): return element.height
        }
      }
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format.ComponentType == UInt8 {
  public typealias Histogram888 = ([vImagePixelCount], [vImagePixelCount], [vImagePixelCount])
  public typealias Histogram8888 = ([vImagePixelCount], [vImagePixelCount], [vImagePixelCount], [vImagePixelCount])
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format.ComponentType == Float {
  public typealias HistogramFFF = (binCount: Int, [vImagePixelCount], [vImagePixelCount], [vImagePixelCount])
  public typealias HistogramFFFF = (binCount: Int, [vImagePixelCount], [vImagePixelCount], [vImagePixelCount], [vImagePixelCount])
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved8x4 {
  public func histogram() -> vImage.PixelBuffer<Format>.Histogram8888 {
    let h = _vImageHistograms(count: 4, entries: 256) { pointers in
      var source = _vImageBuffers[0]
      return vImageHistogramCalculation_ARGB8888(&source, pointers, vImage_Flags(kvImageNoFlags))
    }
    return (h[0], h[1], h[2], h[3])
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.InterleavedFx4 {
  public func histogram(binCount: Int) -> vImage.PixelBuffer<Format>.HistogramFFFF {
    let h = _vImageHistograms(count: 4, entries: binCount) { pointers in
      var source = _vImageBuffers[0]
      return vImageHistogramCalculation_ARGBFFFF(&source, pointers, UInt32(binCount), 0, 1, vImage_Flags(kvImageNoFlags))
    }
    return (binCount, h[0], h[1], h[2], h[3])
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.InterleavedFx4 {
  public func specifyHistogram(_ histogram: vImage.PixelBuffer<Format>.HistogramFFFF, destination: vImage.PixelBuffer<Format>) {
    _vImageWithHistograms([histogram.1, histogram.2, histogram.3, histogram.4]) { pointers in
      _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImageHistogramSpecification_ARGBFFFF($0, $1, nil, pointers, UInt32(histogram.binCount), 0, 1, vImage_Flags(kvImageNoFlags)) }
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved8x4 {
  public func specifyHistogram(_ histogram: vImage.PixelBuffer<Format>.Histogram8888, destination: vImage.PixelBuffer<Format>) {
    _vImageWithHistograms([histogram.0, histogram.1, histogram.2, histogram.3]) { pointers in
      _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImageHistogramSpecification_ARGB8888($0, $1, pointers, vImage_Flags(kvImageNoFlags)) }
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar8 {
  public func equalizeHistogram(destination: vImage.PixelBuffer<vImage.Planar8>) {
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImageEqualization_Planar8($0, $1, vImage_Flags(kvImageNoFlags)) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : MultiplePlanePixelFormat, Format.ComponentType == UInt8 {
  public func equalizeHistogram(destination: vImage.PixelBuffer<Format>) {
    _vImageEachPlane(_vImageBuffers, destination._vImageBuffers) { vImageEqualization_Planar8($0, $1, vImage_Flags(kvImageNoFlags)) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved8x4 {
  public func equalizeHistogram(destination: vImage.PixelBuffer<Format>) {
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImageEqualization_ARGB8888($0, $1, vImage_Flags(kvImageNoFlags)) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.PlanarF {
  public func equalizeHistogram(binCount: Int, destination: vImage.PixelBuffer<vImage.PlanarF>) {
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImageEqualization_PlanarF($0, $1, nil, UInt32(binCount), 0, 1, vImage_Flags(kvImageNoFlags)) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : MultiplePlanePixelFormat, Format.ComponentType == Float {
  public func equalizeHistogram(binCount: Int, destination: vImage.PixelBuffer<Format>) {
    _vImageEachPlane(_vImageBuffers, destination._vImageBuffers) { vImageEqualization_PlanarF($0, $1, nil, UInt32(binCount), 0, 1, vImage_Flags(kvImageNoFlags)) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.InterleavedFx4 {
  public func equalizeHistogram(binCount: Int, destination: vImage.PixelBuffer<vImage.InterleavedFx4>) {
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImageEqualization_ARGBFFFF($0, $1, nil, UInt32(binCount), 0, 1, vImage_Flags(kvImageNoFlags)) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar8 {
  public func contrastStretch(destination: vImage.PixelBuffer<vImage.Planar8>) {
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImageContrastStretch_Planar8($0, $1, vImage_Flags(kvImageNoFlags)) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : MultiplePlanePixelFormat, Format.ComponentType == UInt8 {
  public func contrastStretch(destination: vImage.PixelBuffer<Format>) {
    _vImageEachPlane(_vImageBuffers, destination._vImageBuffers) { vImageContrastStretch_Planar8($0, $1, vImage_Flags(kvImageNoFlags)) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved8x4 {
  public func contrastStretch(destination: vImage.PixelBuffer<vImage.Interleaved8x4>) {
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImageContrastStretch_ARGB8888($0, $1, vImage_Flags(kvImageNoFlags)) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.PlanarF {
  public func contrastStretch(binCount: Int, destination: vImage.PixelBuffer<vImage.PlanarF>) {
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImageContrastStretch_PlanarF($0, $1, nil, UInt32(binCount), 0, 1, vImage_Flags(kvImageNoFlags)) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : MultiplePlanePixelFormat, Format.ComponentType == Float {
  public func contrastStretch(binCount: Int, destination: vImage.PixelBuffer<Format>) {
    _vImageEachPlane(_vImageBuffers, destination._vImageBuffers) { vImageContrastStretch_PlanarF($0, $1, nil, UInt32(binCount), 0, 1, vImage_Flags(kvImageNoFlags)) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.InterleavedFx4 {
  public func contrastStretch(binCount: Int, destination: vImage.PixelBuffer<vImage.InterleavedFx4>) {
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) { vImageContrastStretch_ARGBFFFF($0, $1, nil, UInt32(binCount), 0, 1, vImage_Flags(kvImageNoFlags)) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar8x3 {
  public func histogram() -> vImage.PixelBuffer<Format>.Histogram888 {
    let h = _calculateHistogram()
    return (h[0], h[1], h[2])
  }
  public func specifyHistogram(_ histogram: vImage.PixelBuffer<Format>.Histogram888, destination: vImage.PixelBuffer<Format>) {
    _specifyHistogram([histogram.0, histogram.1, histogram.2], destination: destination)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar8x4 {
  public func histogram() -> vImage.PixelBuffer<Format>.Histogram8888 {
    let h = _calculateHistogram()
    return (h[0], h[1], h[2], h[3])
  }
  public func specifyHistogram(_ histogram: vImage.PixelBuffer<Format>.Histogram8888, destination: vImage.PixelBuffer<Format>) {
    _specifyHistogram([histogram.0, histogram.1, histogram.2, histogram.3], destination: destination)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : MultiplePlanePixelFormat, Format.ComponentType == UInt8 {
  @usableFromInline
  internal func _calculateHistogram() -> [[vImagePixelCount]] {
    return _vImageBuffers.map { plane in
      _vImageHistograms(count: 1, entries: 256) { pointers in
        var source = plane
        return vImageHistogramCalculation_Planar8(&source, pointers[0]!, vImage_Flags(kvImageNoFlags))
      }[0]
    }
  }
  @usableFromInline
  internal func _specifyHistogram(_ histogram: [[vImagePixelCount]], destination: vImage.PixelBuffer<Format>) {
    precondition(histogram.count == _vImageBuffers.count, "one histogram per plane")
    for (i, (source, target)) in zip(_vImageBuffers, destination._vImageBuffers).enumerated() {
      histogram[i].withUnsafeBufferPointer { h in
        _vImageRun(source, target) { vImageHistogramSpecification_Planar8($0, $1, h.baseAddress!, vImage_Flags(kvImageNoFlags)) }
      }
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.PlanarFx3 {
  public func histogram(binCount: Int) -> vImage.PixelBuffer<Format>.HistogramFFF {
    let h = _calculateHistogram(binCount: binCount)
    return (binCount, h[0], h[1], h[2])
  }
  public func specifyHistogram(_ histogram: vImage.PixelBuffer<Format>.HistogramFFF, destination: vImage.PixelBuffer<Format>) {
    _specifyHistogram([histogram.1, histogram.2, histogram.3], binCount: histogram.binCount, destination: destination)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.PlanarFx4 {
  public func histogram(binCount: Int) -> vImage.PixelBuffer<Format>.HistogramFFFF {
    let h = _calculateHistogram(binCount: binCount)
    return (binCount, h[0], h[1], h[2], h[3])
  }
  public func specifyHistogram(_ histogram: vImage.PixelBuffer<Format>.HistogramFFFF, destination: vImage.PixelBuffer<Format>) {
    _specifyHistogram([histogram.1, histogram.2, histogram.3, histogram.4], binCount: histogram.binCount, destination: destination)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : MultiplePlanePixelFormat, Format.ComponentType == Float {
  @usableFromInline
  internal func _calculateHistogram(binCount: Int) -> [[vImagePixelCount]] {
    return _vImageBuffers.map { plane in
      _vImageHistograms(count: 1, entries: binCount) { pointers in
        var source = plane
        return vImageHistogramCalculation_PlanarF(&source, pointers[0]!, UInt32(binCount), 0, 1, vImage_Flags(kvImageNoFlags))
      }[0]
    }
  }
  @usableFromInline
  internal func _specifyHistogram(_ histogram: [[vImagePixelCount]], binCount: Int, destination: vImage.PixelBuffer<Format>) {
    precondition(histogram.count == _vImageBuffers.count, "one histogram per plane")
    for (i, (source, target)) in zip(_vImageBuffers, destination._vImageBuffers).enumerated() {
      histogram[i].withUnsafeBufferPointer { h in
        _vImageRun(source, target) { vImageHistogramSpecification_PlanarF($0, $1, nil, h.baseAddress!, UInt32(binCount), 0, 1, vImage_Flags(kvImageNoFlags)) }
      }
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage {
  public struct PixelBuffer<Format> where Format : PixelFormat {
    /// Each plane's buffer (one for a single-plane format).
    internal var _vImageBuffers: [vImage_Buffer]
    /// The owner of memory the overlay allocated, if any.
    internal var _storage: _vImagePixelStorage?

    internal init(_buffers: [vImage_Buffer], storage: _vImagePixelStorage?) {
      _vImageBuffers = _buffers
      _storage = storage
    }

    public var size: vImage.Size {
      get { vImage.Size(width: width, height: height) }
    }
    public var width: Int {
      get { Int(_vImageBuffers[0].width) }
    }
    public var height: Int {
      get { Int(_vImageBuffers[0].height) }
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : SinglePlanePixelFormat {
  @usableFromInline
  internal var vImageBuffer: vImage_Buffer {
    get { _vImageBuffers[0] }
  }
  public func withUnsafeVImageBuffer<R>(_ body: (vImage_Buffer) throws -> R) rethrows -> R {
    return try body(_vImageBuffers[0])
  }
  public func withUnsafePointerToVImageBuffer<R>(_ body: (UnsafePointer<vImage_Buffer>) throws -> R) rethrows -> R {
    var buffer = _vImageBuffers[0]
    return try withUnsafePointer(to: &buffer) { try body($0) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : MultiplePlanePixelFormat {
  @usableFromInline
  internal var vImageBuffers: [vImage_Buffer] {
    get { _vImageBuffers }
  }
  public func withUnsafeVImageBuffers<R>(_ body: ([vImage_Buffer]) throws -> R) rethrows -> R {
    return try body(_vImageBuffers)
  }
  public func withUnsafePixelBuffers<R>(_ body: ([vImage.PixelBuffer<Format.PlanarPixelFormat>]) throws -> R) rethrows -> R {
    return try body(pixelBuffers)
  }
  public func withUnsafePixelBuffer<R>(at index: Int, _ body: (vImage.PixelBuffer<Format.PlanarPixelFormat>) throws -> R) rethrows -> R {
    return try body(self[index])
  }
  @usableFromInline
  internal var pixelBuffers: [vImage.PixelBuffer<Format.PlanarPixelFormat>] {
    get { _vImageBuffers.map { vImage.PixelBuffer<Format.PlanarPixelFormat>(_buffers: [$0], storage: _storage) } }
  }
  @usableFromInline
  internal subscript(index: Int) -> vImage.PixelBuffer<Format.PlanarPixelFormat> {
    get { vImage.PixelBuffer<Format.PlanarPixelFormat>(_buffers: [_vImageBuffers[index]], storage: _storage) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : SinglePlanePixelFormat {
  public init(data: UnsafeMutableRawPointer, width: Int, height: Int, byteCountPerRow: Int, pixelFormat: Format.Type) {
    precondition(width >= 0 && height >= 0, "a pixel buffer's size can't be negative")
    self.init(_buffers: [vImage_Buffer(data: data, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: byteCountPerRow)], storage: nil)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : StaticPixelFormat {
  public init(data: UnsafeMutableRawPointer, width: Int, height: Int, byteCountPerRow: Int? = nil, pixelFormat: Format.Type = Format.self) {
    precondition(width >= 0 && height >= 0, "a pixel buffer's size can't be negative")
    let rowBytes = byteCountPerRow ?? width * (Format.bitCountPerPixel / 8)
    self.init(_buffers: [vImage_Buffer(data: data, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: rowBytes)], storage: nil)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : MultiplePlanePixelFormat {
  public init(size: vImage.Size, pixelFormat: Format.Type = Format.self) {
    let storage = _vImagePixelStorage()
    var buffers = [vImage_Buffer]()
    for _ in 0..<Format.planeCount {
      let buffer = _vImageAllocateBuffer(width: size.width, height: size.height, bitsPerPixel: Format.bitCountPerPlanarPixel)
      if let data = buffer.data { storage.allocations.append(data) }
      buffers.append(buffer)
    }
    self.init(_buffers: buffers, storage: storage)
  }
  public init(planarBuffers: [vImage.PixelBuffer<Format.PlanarPixelFormat>], pixelFormat: Format.Type = Format.self) {
    precondition(planarBuffers.count == Format.planeCount, "a \(Format.self) buffer needs \(Format.planeCount) planar buffers")
    precondition(planarBuffers.allSatisfy { $0.size == planarBuffers[0].size }, "the planar buffers must be the same size")
    let storage = _vImagePixelStorage()
    for plane in planarBuffers { if let owner = plane._storage { storage.retained.append(owner) } }
    self.init(_buffers: planarBuffers.map { $0._vImageBuffers[0] }, storage: storage)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : StaticPixelFormat {
  public init(width: Int, height: Int, pixelFormat: Format.Type = Format.self) {
    self.init(_allocatingWidth: width, height: height)
  }
  public init(size: vImage.Size, pixelFormat: Format.Type = Format.self) {
    self.init(_allocatingWidth: size.width, height: size.height)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : StaticPixelFormat {
  public var channelCount: Int {
    get { Format.channelCount }
  }
  public var byteCountPerPixel: Int {
    get { Format.bitCountPerPixel / 8 }
  }
  public func copy(to destinationBuffer: vImage.PixelBuffer<Format>) {
    _vImageCheckSizes(_vImageBuffers[0], destinationBuffer._vImageBuffers[0])
    _vImageRun(_vImageBuffers[0], destinationBuffer._vImageBuffers[0]) {
      vImageCopyBuffer($0, UnsafeMutablePointer(mutating: $1), Format.bitCountPerPixel / 8, vImage_Flags(kvImageNoFlags))
    }
  }
  public func cropped(to rect: CGRect) -> vImage.PixelBuffer<Format> {
    let region = _region(rect)
    let result = vImage.PixelBuffer<Format>(width: Int(region.width), height: Int(region.height))
    _vImageRun(region, result._vImageBuffers[0]) {
      vImageCopyBuffer($0, UnsafeMutablePointer(mutating: $1), Format.bitCountPerPixel / 8, vImage_Flags(kvImageNoFlags))
    }
    return result
  }
  public func crop(at origin: CGPoint, destination: vImage.PixelBuffer<Format>) {
    let region = _region(x: Int(origin.x.rounded(.down)), y: Int(origin.y.rounded(.down)), width: destination.width, height: destination.height)
    _vImageRun(region, destination._vImageBuffers[0]) {
      vImageCopyBuffer($0, UnsafeMutablePointer(mutating: $1), Format.bitCountPerPixel / 8, vImage_Flags(kvImageNoFlags))
    }
  }
  public func withUnsafeRegionOfInterest<R>(_ regionOfInterest: CGRect, _ body: (vImage.PixelBuffer<Format>) throws -> R) rethrows -> R {
    return try body(vImage.PixelBuffer<Format>(_buffers: [_region(regionOfInterest)], storage: _storage))
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.DynamicPixelFormat {
  public static func makeDynamicPixelBufferAndCGImageFormat(cgImage: CGImage) throws -> (pixelBuffer: vImage.PixelBuffer<vImage.DynamicPixelFormat>, cgImageFormat: vImage_CGImageFormat) {
    guard var format = vImage_CGImageFormat(cgImage: cgImage) else { throw vImage.Error.invalidImageFormat }
    var buffer = vImage_Buffer()
    try vImage.Error._check(vImageBuffer_InitWithCGImage(&buffer, &format, nil, cgImage, vImage_Flags(kvImageNoFlags)))
    return (vImage.PixelBuffer<vImage.DynamicPixelFormat>(_buffers: [buffer], storage: _vImagePixelStorage(allocation: buffer.data)), format)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : InitializableFromCGImage, Format : StaticPixelFormat {
  public static func makePixelBufferAndCGImageFormat(cgImage: CGImage, pixelFormat: Format.Type = Format.self) throws -> (pixelBuffer: vImage.PixelBuffer<Format>, cgImageFormat: vImage_CGImageFormat) {
    var format = try _vImageCGImageFormat(for: Format.self, matching: cgImage)
    let buffer = try vImage.PixelBuffer<Format>(cgImage: cgImage, cgImageFormat: &format)
    return (buffer, format)
  }
  public init(cgImage: CGImage, cgImageFormat: inout vImage_CGImageFormat, pixelFormat: Format.Type = Format.self) throws {
    guard Int(cgImageFormat.bitsPerPixel) == Format.bitCountPerPixel else { throw vImage.Error.invalidImageFormat }
    var buffer = vImage_Buffer()
    try vImage.Error._check(vImageBuffer_InitWithCGImage(&buffer, &cgImageFormat, nil, cgImage, vImage_Flags(kvImageNoFlags)))
    self.init(_buffers: [buffer], storage: _vImagePixelStorage(allocation: buffer.data))
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : StaticPixelFormat {
  public func makeCGImage(cgImageFormat: vImage_CGImageFormat) -> CGImage? {
    var buffer = _vImageBuffers[0]
    var format = cgImageFormat
    var error = vImage_Error(kvImageNoError)
    return vImageCreateCGImageFromBuffer(&buffer, &format, nil, nil, vImage_Flags(kvImageNoFlags), &error)?.takeRetainedValue()
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format : SinglePlanePixelFormat {
  public init(referencing lockedCVPixelBuffer: CVPixelBuffer, planeIndex: Int, overrideSize: vImage.Size? = nil, pixelFormat: Format.Type = Format.self) {
    let planar = CVPixelBufferIsPlanar(lockedCVPixelBuffer)
    let base = planar ? CVPixelBufferGetBaseAddressOfPlane(lockedCVPixelBuffer, planeIndex) : CVPixelBufferGetBaseAddress(lockedCVPixelBuffer)
    precondition(base != nil, "the CVPixelBuffer must be locked")
    var width = planar ? CVPixelBufferGetWidthOfPlane(lockedCVPixelBuffer, planeIndex) : CVPixelBufferGetWidth(lockedCVPixelBuffer)
    var height = planar ? CVPixelBufferGetHeightOfPlane(lockedCVPixelBuffer, planeIndex) : CVPixelBufferGetHeight(lockedCVPixelBuffer)
    let rowBytes = planar ? CVPixelBufferGetBytesPerRowOfPlane(lockedCVPixelBuffer, planeIndex) : CVPixelBufferGetBytesPerRow(lockedCVPixelBuffer)
    if let overrideSize {
      width = overrideSize.width
      height = overrideSize.height
    }
    let storage = _vImagePixelStorage()
    storage.retained.append(lockedCVPixelBuffer)
    self.init(_buffers: [vImage_Buffer(data: base, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: rowBytes)], storage: storage)
  }
  public init(copying cvPixelBuffer: CVPixelBuffer, cvImageFormat: vImageCVImageFormat, cgImageFormat: inout vImage_CGImageFormat, pixelFormat: Format.Type = Format.self) throws {
    var buffer = vImage_Buffer()
    try vImage.Error._check(vImageBuffer_InitWithCVPixelBuffer(&buffer, &cgImageFormat, cvPixelBuffer, cvImageFormat, nil, vImage_Flags(kvImageNoFlags)))
    self.init(_buffers: [buffer], storage: _vImagePixelStorage(allocation: buffer.data))
  }
  public init(referencing lockedCVPixelBuffer: CVPixelBuffer, converter: vImageConverter, destinationPixelFormat: Format.Type = Format.self) {
    let count = max(1, Int(vImageConverter_GetNumberOfDestinationBuffers(converter)), Int(vImageConverter_GetNumberOfSourceBuffers(converter)))
    var buffers = [vImage_Buffer](repeating: vImage_Buffer(), count: count)
    var error = vImageBuffer_InitForCopyToCVPixelBuffer(&buffers, converter, lockedCVPixelBuffer, vImage_Flags(kvImageNoAllocate))
    if error != kvImageNoError {
      error = vImageBuffer_InitForCopyFromCVPixelBuffer(&buffers, converter, lockedCVPixelBuffer, vImage_Flags(kvImageNoAllocate))
    }
    let storage = _vImagePixelStorage()
    storage.retained.append(lockedCVPixelBuffer)
    self.init(_buffers: [buffers[0]], storage: storage)
  }
  public func copy(to cvPixelBuffer: CVPixelBuffer, cvImageFormat: vImageCVImageFormat, cgImageFormat: vImage_CGImageFormat) throws {
    var buffer = _vImageBuffers[0]
    var format = cgImageFormat
    try vImage.Error._check(vImageBuffer_CopyToCVPixelBuffer(&buffer, &format, cvPixelBuffer, cvImageFormat, nil, vImage_Flags(kvImageNoFlags)))
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer : AccelerateBuffer, AccelerateMutableBuffer where Format : StaticPixelFormat {
  public typealias Element = Format.ComponentType
  public var count: Int {
    get { width * height * Format.channelCount }
  }
  public func withUnsafeBufferPointer<R>(_ body: (UnsafeBufferPointer<Format.ComponentType>) throws -> R) rethrows -> R {
    if _isContiguous, let data = _vImageBuffers[0].data {
      return try body(UnsafeBufferPointer(start: data.assumingMemoryBound(to: Format.ComponentType.self), count: count))
    }
    return try _componentArray().withUnsafeBufferPointer(body)
  }
  public func withUnsafeMutableBufferPointer<R>(_ body: (inout UnsafeMutableBufferPointer<Format.ComponentType>) throws -> R) rethrows -> R {
    if _isContiguous, let data = _vImageBuffers[0].data {
      var pointer = UnsafeMutableBufferPointer(start: data.assumingMemoryBound(to: Format.ComponentType.self), count: count)
      return try body(&pointer)
    }
    var values = _componentArray()
    let result = try values.withUnsafeMutableBufferPointer(body)
    values.withUnsafeBufferPointer { _store($0) }
    return result
  }
  public init<U>(pixelValues: U, size: vImage.Size, pixelFormat: Format.Type = Format.self) where U : AccelerateBuffer, Format.ComponentType == U.Element {
    self.init(_allocatingWidth: size.width, height: size.height)
    let buffer = self
    pixelValues.withUnsafeBufferPointer { buffer._store($0) }
  }
  public var array: [Format.ComponentType] {
    get { _componentArray() }
  }
  public var rowStride: Int {
    get { _vImageBuffers[0].rowBytes / MemoryLayout<Format.ComponentType>.stride }
  }
  public var bytesPerRow: Int {
    get { _vImageBuffers[0].rowBytes }
  }
}

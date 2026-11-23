import Swift
import _Concurrency
import _StringProcessing
import _SwiftConcurrencyShims
import simd
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImageCVImageFormat {
  public static func make(format: vImageCVImageFormat.Format, colorSpace: CGColorSpace, alphaIsOpaqueHint: Bool) -> vImageCVImageFormat? {
    return vImageCVImageFormat_Create(format._pixelFormatType, nil, nil, colorSpace, alphaIsOpaqueHint ? 1 : 0)?.takeRetainedValue()
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage {
  public struct Size : Equatable {
    public let width: Int
    public let height: Int
    public init?<T>(exactWidth: T, height: T) where T : BinaryInteger {
      guard let w = Int(exactly: exactWidth), let h = Int(exactly: height), w >= 0, h >= 0 else { return nil }
      self.width = w
      self.height = h
    }
    public init?<T>(exactWidth: T, height: T) where T : BinaryFloatingPoint {
      guard let w = Int(exactly: exactWidth), let h = Int(exactly: height), w >= 0, h >= 0 else { return nil }
      self.width = w
      self.height = h
    }
    public init(width: Int, height: Int) {
      precondition(width >= 0 && height >= 0, "a size can't be negative")
      self.width = width
      self.height = height
    }
    public init(width: vImagePixelCount, height: vImagePixelCount) {
      self.width = Int(width)
      self.height = Int(height)
    }
    public init?(exactly size: CGSize) {
      guard let w = Int(exactly: size.width), let h = Int(exactly: size.height), w >= 0, h >= 0 else { return nil }
      self.width = w
      self.height = h
    }
    public init(cvPixelBuffer: CVPixelBuffer) {
      self.width = CVPixelBufferGetWidth(cvPixelBuffer)
      self.height = CVPixelBufferGetHeight(cvPixelBuffer)
    }
    public static func == (a: vImage.Size, b: vImage.Size) -> Bool {
      return a.width == b.width && a.height == b.height
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage {
  public struct MultidimensionalLookupTable {
    @_hasMissingDesignatedInitializers @usableFromInline
    internal class LookupTableReference {
      init(lookupTable: vImage_MultidimensionalTable) {
        self.lookupTable = lookupTable
      }
      @usableFromInline
      final internal let lookupTable: vImage_MultidimensionalTable
      deinit { _ = vImageMultidimensionalTable_Release(lookupTable) }
    }
    @usableFromInline
    internal var lookupTableReference: vImage.MultidimensionalLookupTable.LookupTableReference!
    public let entryCountPerSourceChannel: [UInt8]
    public let sourceChannelCount: Int
    public let destinationChannelCount: Int
    public init<T>(entryCountPerSourceChannel: [UInt8], destinationChannelCount: Int, data: T) where T : AccelerateBuffer, T.Element == UInt16 {
      precondition(entryCountPerSourceChannel.count >= 1 && entryCountPerSourceChannel.count <= 8, "a table has 1 to 8 source channels")
      let entries = entryCountPerSourceChannel.reduce(1) { $0 * Int($1) }
      precondition(data.count == entries * destinationChannelCount, "the table data needs an entry per destination channel per grid point")
      self.entryCountPerSourceChannel = entryCountPerSourceChannel
      self.sourceChannelCount = entryCountPerSourceChannel.count
      self.destinationChannelCount = destinationChannelCount
      var error = vImage_Error(kvImageNoError)
      let table = data.withUnsafeBufferPointer { values in
        vImageMultidimensionalTable_Create(values.baseAddress!, UInt32(entryCountPerSourceChannel.count), UInt32(destinationChannelCount),
                                           entryCountPerSourceChannel, kvImageMDTableHint_Float, vImage_Flags(kvImageNoFlags), &error)
      }
      lookupTableReference = table.map { vImage.MultidimensionalLookupTable.LookupTableReference(lookupTable: $0) }
    }
    public enum InterpolationMethod : Equatable, Hashable {
      case none
      case full
      case half
      @usableFromInline
      internal var vImageInterpolationMethod: vImage_InterpolationMethod {
        get {
          switch self {
          case .none: return kvImageNoInterpolation
          case .full: return kvImageFullInterpolation
          case .half: return kvImageHalfInterpolation
          }
        }
      }
    }
    public func apply(sources: [vImage.PixelBuffer<vImage.PlanarF>], destinations: [vImage.PixelBuffer<vImage.PlanarF>], interpolation: vImage.MultidimensionalLookupTable.InterpolationMethod) {
      precondition(sources.count == sourceChannelCount && destinations.count == destinationChannelCount, "one buffer per table channel")
      guard let table = lookupTableReference?.lookupTable else { return }
      var sourceBuffers = sources.map { $0._vImageBuffers[0] }
      var destinationBuffers = destinations.map { $0._vImageBuffers[0] }
      _ = vImageMultiDimensionalInterpolatedLookupTable_PlanarF(&sourceBuffers, &destinationBuffers, nil, table, interpolation.vImageInterpolationMethod, vImage_Flags(kvImageNoFlags))
    }
    public func apply<SrcFormat, DestFormat>(source: vImage.PixelBuffer<SrcFormat>, destination: vImage.PixelBuffer<DestFormat>, interpolation: vImage.MultidimensionalLookupTable.InterpolationMethod) where SrcFormat : MultiplePlanePixelFormat, DestFormat : MultiplePlanePixelFormat, SrcFormat.ComponentType == Float, DestFormat.ComponentType == Float {
      apply(sources: source._vImageBuffers.map { vImage.PixelBuffer<vImage.PlanarF>(_buffers: [$0], storage: nil) },
            destinations: destination._vImageBuffers.map { vImage.PixelBuffer<vImage.PlanarF>(_buffers: [$0], storage: nil) },
            interpolation: interpolation)
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.PlanarFx4 {
  public init(interleavedBuffer: vImage.PixelBuffer<vImage.InterleavedFx4>) {
    self.init(size: interleavedBuffer.size)
    _deinterleave(from: interleavedBuffer)
  }
  public func convert(to destination: vImage.PixelBuffer<vImage.InterleavedFx4>) {
    _interleave(into: destination)
  }
  public func interleave(destination: vImage.PixelBuffer<vImage.InterleavedFx4>) {
    _interleave(into: destination)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved16Ux4 {
  public init(planarBuffers: [vImage.PixelBuffer<vImage.Planar16U>]) {
    self.init(_interleaving: planarBuffers)
  }
  public func planarBuffers() -> [vImage.PixelBuffer<vImage.Planar16U>] {
    return _planarBuffers(vImage.Planar16U.self)
  }
  public func convert(to destination: vImage.PixelBuffer<vImage.InterleavedFx4>) {
    _convertComponents(to: destination)
  }
  public func convert(to destination: vImage.PixelBuffer<vImage.Interleaved8x4>) {
    _convertComponents(to: destination)
  }
  public func convert(to destination: vImage.PixelBuffer<vImage.Interleaved16Fx4>) {
    _convertComponents(to: destination)
  }
  public func interleave(planarSourceBuffers: [vImage.PixelBuffer<vImage.Planar16U>]) {
    _interleave(planarSourceBuffers)
  }
  public func deinterleave(planarDestinationBuffers: [vImage.PixelBuffer<vImage.Planar16U>]) {
    _deinterleave(into: planarDestinationBuffers.map { $0._vImageBuffers[0] }, as: vImage.Planar16U.self)
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar8 {
  public func premultiply(alpha: vImage.PixelBuffer<Format>) {
    var a = alpha._vImageBuffers[0]
    _vImageCheckSizes(_vImageBuffers[0], a)
    _vImageRun(_vImageBuffers[0], _vImageBuffers[0]) { vImagePremultiplyData_Planar8($0, &a, $1, vImage_Flags(kvImageNoFlags)) }
  }
  public func unpremultiply(alpha: vImage.PixelBuffer<Format>) {
    var a = alpha._vImageBuffers[0]
    _vImageCheckSizes(_vImageBuffers[0], a)
    _vImageRun(_vImageBuffers[0], _vImageBuffers[0]) { vImageUnpremultiplyData_Planar8($0, &a, $1, vImage_Flags(kvImageNoFlags)) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved8x4 {
  public func premultiply(channelOrdering: vImage.ChannelOrdering) {
    _vImageRun(_vImageBuffers[0], _vImageBuffers[0]) { channelOrdering == .ARGB ? vImagePremultiplyData_ARGB8888($0, $1, vImage_Flags(kvImageNoFlags)) : vImagePremultiplyData_RGBA8888($0, $1, vImage_Flags(kvImageNoFlags)) }
  }
  public func unpremultiply(channelOrdering: vImage.ChannelOrdering) {
    _vImageRun(_vImageBuffers[0], _vImageBuffers[0]) { channelOrdering == .ARGB ? vImageUnpremultiplyData_ARGB8888($0, $1, vImage_Flags(kvImageNoFlags)) : vImageUnpremultiplyData_RGBA8888($0, $1, vImage_Flags(kvImageNoFlags)) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved16Ux4 {
  public func premultiply(channelOrdering: vImage.ChannelOrdering) {
    _vImageRun(_vImageBuffers[0], _vImageBuffers[0]) { channelOrdering == .ARGB ? vImagePremultiplyData_ARGB16U($0, $1, vImage_Flags(kvImageNoFlags)) : vImagePremultiplyData_RGBA16U($0, $1, vImage_Flags(kvImageNoFlags)) }
  }
  public func unpremultiply(channelOrdering: vImage.ChannelOrdering) {
    _vImageRun(_vImageBuffers[0], _vImageBuffers[0]) { channelOrdering == .ARGB ? vImageUnpremultiplyData_ARGB16U($0, $1, vImage_Flags(kvImageNoFlags)) : vImageUnpremultiplyData_RGBA16U($0, $1, vImage_Flags(kvImageNoFlags)) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved16Fx4 {
  public func premultiply() {
    _vImageRun(_vImageBuffers[0], _vImageBuffers[0]) { vImagePremultiplyData_RGBA16F($0, $1, vImage_Flags(kvImageNoFlags)) }
  }
  public func unpremultiply() {
    _vImageRun(_vImageBuffers[0], _vImageBuffers[0]) { vImageUnpremultiplyData_RGBA16F($0, $1, vImage_Flags(kvImageNoFlags)) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.PlanarF {
  public func premultiply(alpha: vImage.PixelBuffer<Format>) {
    var a = alpha._vImageBuffers[0]
    _vImageCheckSizes(_vImageBuffers[0], a)
    _vImageRun(_vImageBuffers[0], _vImageBuffers[0]) { vImagePremultiplyData_PlanarF($0, &a, $1, vImage_Flags(kvImageNoFlags)) }
  }
  public func unpremultiply(alpha: vImage.PixelBuffer<Format>) {
    var a = alpha._vImageBuffers[0]
    _vImageCheckSizes(_vImageBuffers[0], a)
    _vImageRun(_vImageBuffers[0], _vImageBuffers[0]) { vImageUnpremultiplyData_PlanarF($0, &a, $1, vImage_Flags(kvImageNoFlags)) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.InterleavedFx4 {
  public func premultiply(channelOrdering: vImage.ChannelOrdering) {
    _vImageRun(_vImageBuffers[0], _vImageBuffers[0]) { channelOrdering == .ARGB ? vImagePremultiplyData_ARGBFFFF($0, $1, vImage_Flags(kvImageNoFlags)) : vImagePremultiplyData_RGBAFFFF($0, $1, vImage_Flags(kvImageNoFlags)) }
  }
  public func unpremultiply(channelOrdering: vImage.ChannelOrdering) {
    _vImageRun(_vImageBuffers[0], _vImageBuffers[0]) { channelOrdering == .ARGB ? vImageUnpremultiplyData_ARGBFFFF($0, $1, vImage_Flags(kvImageNoFlags)) : vImageUnpremultiplyData_RGBAFFFF($0, $1, vImage_Flags(kvImageNoFlags)) }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Interleaved8x4 {
  public func premultipliedAlphaBlend(_ blendMode: vImage.BlendMode, topLayer: vImage.PixelBuffer<Format>, destination: vImage.PixelBuffer<Format>) {
    _vImageCheckSizes(_vImageBuffers[0], topLayer._vImageBuffers[0])
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    var top = topLayer._vImageBuffers[0]
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) {
      switch blendMode {
      case .multiply: return vImagePremultipliedAlphaBlendMultiply_RGBA8888(&top, $0, $1, vImage_Flags(kvImageNoFlags))
      case .screen: return vImagePremultipliedAlphaBlendScreen_RGBA8888(&top, $0, $1, vImage_Flags(kvImageNoFlags))
      case .darken: return vImagePremultipliedAlphaBlendDarken_RGBA8888(&top, $0, $1, vImage_Flags(kvImageNoFlags))
      case .lighten: return vImagePremultipliedAlphaBlendLighten_RGBA8888(&top, $0, $1, vImage_Flags(kvImageNoFlags))
      }
    }
  }
  public func alphaComposite(_ compositeMode: vImage.CompositeMode<Pixel_8>, topLayer: vImage.PixelBuffer<Format>, destination: vImage.PixelBuffer<Format>) {
    _vImageCheckSizes(_vImageBuffers[0], topLayer._vImageBuffers[0])
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    var top = topLayer._vImageBuffers[0]
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) {
      switch compositeMode {
      case .nonpremultiplied: return vImageAlphaBlend_ARGB8888(&top, $0, $1, vImage_Flags(kvImageNoFlags))
      case .premultiplied: return vImagePremultipliedAlphaBlend_ARGB8888(&top, $0, $1, vImage_Flags(kvImageNoFlags))
      case .nonpremultipliedToPremultiplied: return vImageAlphaBlend_NonpremultipliedToPremultiplied_ARGB8888(&top, $0, $1, vImage_Flags(kvImageNoFlags))
      case .premultipliedWithConstantAlpha(let alpha): return vImagePremultipliedConstAlphaBlend_ARGB8888(&top, alpha, $0, $1, vImage_Flags(kvImageNoFlags))
      }
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.InterleavedFx4 {
  public func alphaComposite(_ compositeMode: vImage.CompositeMode<Pixel_F>, topLayer: vImage.PixelBuffer<Format>, destination: vImage.PixelBuffer<Format>) {
    _vImageCheckSizes(_vImageBuffers[0], topLayer._vImageBuffers[0])
    _vImageCheckSizes(_vImageBuffers[0], destination._vImageBuffers[0])
    var top = topLayer._vImageBuffers[0]
    _vImageRun(_vImageBuffers[0], destination._vImageBuffers[0]) {
      switch compositeMode {
      case .nonpremultiplied: return vImageAlphaBlend_ARGBFFFF(&top, $0, $1, vImage_Flags(kvImageNoFlags))
      case .premultiplied: return vImagePremultipliedAlphaBlend_ARGBFFFF(&top, $0, $1, vImage_Flags(kvImageNoFlags))
      case .nonpremultipliedToPremultiplied: return vImageAlphaBlend_NonpremultipliedToPremultiplied_ARGBFFFF(&top, $0, $1, vImage_Flags(kvImageNoFlags))
      case .premultipliedWithConstantAlpha(let alpha): return vImagePremultipliedConstAlphaBlend_ARGBFFFF(&top, alpha, $0, $1, vImage_Flags(kvImageNoFlags))
      }
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage {
  public enum BlendMode : Equatable, Hashable {
    case multiply
    case screen
    case darken
    case lighten
  }
  public enum CompositeMode<ComponentType> {
    case nonpremultiplied
    case premultiplied
    case nonpremultipliedToPremultiplied
    case premultipliedWithConstantAlpha(_: ComponentType)
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension vImage_CGImageFormat {
  public init?(cgImage: CGImage) {
    guard let colorSpace = cgImage.colorSpace else { return nil }
    self.init(bitsPerComponent: UInt32(cgImage.bitsPerComponent), bitsPerPixel: UInt32(cgImage.bitsPerPixel),
              colorSpace: Unmanaged.passRetained(colorSpace), bitmapInfo: cgImage.bitmapInfo,
              version: 0, decode: nil, renderingIntent: cgImage.renderingIntent)
  }
  public init?(bitsPerComponent: Int, bitsPerPixel: Int, colorSpace: CGColorSpace, bitmapInfo: CGBitmapInfo, renderingIntent: CGColorRenderingIntent = .defaultIntent) {
    guard [1, 2, 4, 5, 8, 10, 16, 32].contains(bitsPerComponent), bitsPerPixel >= bitsPerComponent, bitsPerPixel <= 128 else { return nil }
    self.init(bitsPerComponent: UInt32(bitsPerComponent), bitsPerPixel: UInt32(bitsPerPixel),
              colorSpace: Unmanaged.passRetained(colorSpace), bitmapInfo: bitmapInfo,
              version: 0, decode: nil, renderingIntent: renderingIntent)
  }
  public var componentCount: Int {
    get {
      var format = self
      return Int(vImageCGImageFormat_GetComponentCount(&format))
    }
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.PlanarF {
  public func convert(to destination: vImage.PixelBuffer<vImage.Planar8>) {
    _convertComponents(to: destination)
  }
  public func convert(to destination: vImage.PixelBuffer<vImage.Planar16F>) {
    _convertComponents(to: destination)
  }
}
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
extension vImage_ARGBToYpCbCrMatrix {
  public static let itu_R_601_4: vImage_ARGBToYpCbCrMatrix = kvImage_ARGBToYpCbCrMatrix_ITU_R_601_4.pointee
  public static let itu_R_709_2: vImage_ARGBToYpCbCrMatrix = kvImage_ARGBToYpCbCrMatrix_ITU_R_709_2.pointee
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension vImageCVImageFormat {
  public static func make(format: vImageCVImageFormat.Format, matrix: vImage_ARGBToYpCbCrMatrix, chromaSiting: vImageCVImageFormat.ChromaSiting, colorSpace: CGColorSpace, alphaIsOpaqueHint: Bool) -> vImageCVImageFormat? {
    var matrix = matrix
    return vImageCVImageFormat_Create(format._pixelFormatType, &matrix, chromaSiting._location, colorSpace, alphaIsOpaqueHint ? 1 : 0)?.takeRetainedValue()
  }
  public static func make(buffer: CVPixelBuffer) -> vImageCVImageFormat? {
    return vImageCVImageFormat_CreateWithCVPixelBuffer(buffer)?.takeRetainedValue()
  }
  public var alphaIsOpaqueHint: Bool {
    get { vImageCVImageFormat_GetAlphaHint(_const) != 0 }
    set { _ = vImageCVImageFormat_SetAlphaHint(self, newValue ? 1 : 0) }
  }
  public var channelCount: UInt32 {
    get { vImageCVImageFormat_GetChannelCount(_const) }
  }
  public var channels: [vImage.BufferType] {
    get {
      guard let names = vImageCVImageFormat_GetChannelNames(_const) else { return [] }
      let model = vImageCVImageFormat_GetColorSpace(_const)?.takeUnretainedValue().model
      var result = [vImage.BufferType]()
      var i = 0
      while names[i] != vImageBufferTypeCode(kvImageBufferTypeCode_EndOfList) {
        if let type = vImage.BufferType(bufferTypeCode: Int(names[i]), model: model) { result.append(type) }
        i += 1
      }
      return result
    }
  }
  public func channelDescription(bufferType: vImage.BufferType) -> vImageChannelDescription? {
    return vImageCVImageFormat_GetChannelDescription(_const, bufferType.bufferTypeCode)?.pointee
  }
  public var chromaSiting: vImageCVImageFormat.ChromaSiting? {
    get {
      guard let location = vImageCVImageFormat_GetChromaSiting(_const)?.takeUnretainedValue() else { return nil }
      return vImageCVImageFormat.ChromaSiting(_location: location)
    }
    set { _ = vImageCVImageFormat_SetChromaSiting(self, newValue?._location) }
  }
  public var colorSpace: CGColorSpace? {
    get { vImageCVImageFormat_GetColorSpace(_const)?.takeUnretainedValue() }
    set { _ = vImageCVImageFormat_SetColorSpace(self, newValue) }
  }
  public var formatCode: UInt32 {
    get { vImageCVImageFormat_GetFormatCode(_const) }
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension vImage {
  public enum BufferType : Int, Equatable, Hashable {
    case alpha
    case coreGraphics
    case cmykBlack
    case cmykCyan
    case cmykMagenta
    case cmykYellow
    case YCbCr
    case Cb
    case Cr
    case chroma
    case chunky
    case indexed
    case labA
    case labB
    case labL
    case luminance
    case monochrome
    case rgbRed
    case rgbGreen
    case rgbBlue
    case xyzX
    case xyzY
    case xyzZ
    public init?(rawValue: Int) {
      guard rawValue >= 0 && rawValue < vImage.BufferType._allCases.count else { return nil }
      self = vImage.BufferType._allCases[rawValue]
    }
    public init?(bufferTypeCode: Int, model: CGColorSpaceModel?) {
      switch bufferTypeCode {
      case Int(kvImageBufferTypeCode_Alpha): self = .alpha
      case Int(kvImageBufferTypeCode_Indexed): self = .indexed
      case Int(kvImageBufferTypeCode_CVPixelBuffer_YCbCr): self = .YCbCr
      case Int(kvImageBufferTypeCode_Luminance): self = .luminance
      case Int(kvImageBufferTypeCode_Chroma): self = .chroma
      case Int(kvImageBufferTypeCode_Cb): self = .Cb
      case Int(kvImageBufferTypeCode_Cr): self = .Cr
      case Int(kvImageBufferTypeCode_CGFormat): self = .coreGraphics
      case Int(kvImageBufferTypeCode_Chunky): self = .chunky
      case Int(kvImageBufferTypeCode_ColorSpaceChannel1)...Int(kvImageBufferTypeCode_ColorSpaceChannel4):
        let channel = bufferTypeCode - Int(kvImageBufferTypeCode_ColorSpaceChannel1)
        let table: [vImage.BufferType]
        switch model {
        case .some(.monochrome): table = [.monochrome]
        case .some(.rgb): table = [.rgbRed, .rgbGreen, .rgbBlue]
        case .some(.cmyk): table = [.cmykCyan, .cmykMagenta, .cmykYellow, .cmykBlack]
        case .some(.lab): table = [.labL, .labA, .labB]
        case .some(.XYZ): table = [.xyzX, .xyzY, .xyzZ]
        default: return nil
        }
        guard channel < table.count else { return nil }
        self = table[channel]
      default: return nil
      }
    }
    public var bufferTypeCode: vImageBufferTypeCode {
      get {
        switch self {
        case .alpha: return vImageBufferTypeCode(kvImageBufferTypeCode_Alpha)
        case .coreGraphics: return vImageBufferTypeCode(kvImageBufferTypeCode_CGFormat)
        case .cmykBlack: return vImageBufferTypeCode(kvImageBufferTypeCode_CMYK_Black)
        case .cmykCyan: return vImageBufferTypeCode(kvImageBufferTypeCode_CMYK_Cyan)
        case .cmykMagenta: return vImageBufferTypeCode(kvImageBufferTypeCode_CMYK_Magenta)
        case .cmykYellow: return vImageBufferTypeCode(kvImageBufferTypeCode_CMYK_Yellow)
        case .YCbCr: return vImageBufferTypeCode(kvImageBufferTypeCode_CVPixelBuffer_YCbCr)
        case .Cb: return vImageBufferTypeCode(kvImageBufferTypeCode_Cb)
        case .Cr: return vImageBufferTypeCode(kvImageBufferTypeCode_Cr)
        case .chroma: return vImageBufferTypeCode(kvImageBufferTypeCode_Chroma)
        case .chunky: return vImageBufferTypeCode(kvImageBufferTypeCode_Chunky)
        case .indexed: return vImageBufferTypeCode(kvImageBufferTypeCode_Indexed)
        case .labA: return vImageBufferTypeCode(kvImageBufferTypeCode_LAB_A)
        case .labB: return vImageBufferTypeCode(kvImageBufferTypeCode_LAB_B)
        case .labL: return vImageBufferTypeCode(kvImageBufferTypeCode_LAB_L)
        case .luminance: return vImageBufferTypeCode(kvImageBufferTypeCode_Luminance)
        case .monochrome: return vImageBufferTypeCode(kvImageBufferTypeCode_Monochrome)
        case .rgbRed: return vImageBufferTypeCode(kvImageBufferTypeCode_RGB_Red)
        case .rgbGreen: return vImageBufferTypeCode(kvImageBufferTypeCode_RGB_Green)
        case .rgbBlue: return vImageBufferTypeCode(kvImageBufferTypeCode_RGB_Blue)
        case .xyzX: return vImageBufferTypeCode(kvImageBufferTypeCode_XYZ_X)
        case .xyzY: return vImageBufferTypeCode(kvImageBufferTypeCode_XYZ_Y)
        case .xyzZ: return vImageBufferTypeCode(kvImageBufferTypeCode_XYZ_Z)
        }
      }
    }
    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    public typealias RawValue = Int
    public var rawValue: Int {
      get { _ordinal }
    }
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension vImageCVImageFormat {
  public enum Format : Equatable, Hashable {
    case format1Monochrome
    case format2Indexed
    case format4Indexed
    case format8Indexed
    case format1IndexedGray_WhiteIsZero
    case format2IndexedGray_WhiteIsZero
    case format4IndexedGray_WhiteIsZero
    case format8IndexedGray_WhiteIsZero
    case format16BE555
    case format16LE555
    case format16LE5551
    case format16BE565
    case format16LE565
    case format24RGB
    case format24BGR
    case format32ARGB
    case format32BGRA
    case format32ABGR
    case format32RGBA
    case format64ARGB
    case format48RGB
    case format32AlphaGray
    case format16Gray
    case format30RGB
    case format422YpCbCr8
    case format4444YpCbCrA8
    case format4444YpCbCrA8R
    case format4444AYpCbCr8
    case format4444AYpCbCr16
    case format444YpCbCr8
    case format422YpCbCr16
    case format422YpCbCr10
    case format444YpCbCr10
    case format420YpCbCr8Planar
    case format420YpCbCr8PlanarFullRange
    case format422YpCbCr_4A_8BiPlanar
    case format420YpCbCr8BiPlanarVideoRange
    case format420YpCbCr8BiPlanarFullRange
    case format422YpCbCr8_yuvs
    case format422YpCbCr8FullRange
    case formatOneComponent8
    case formatTwoComponent8
    case format30RGBLEPackedWideGamut
    case formatARGB2101010LEPacked
    case formatOneComponent16Half
    case formatOneComponent32Float
    case formatTwoComponent16Half
    case formatTwoComponent32Float
    case format64RGBAHalf
    case format128RGBAFloat
    case format14Bayer_GRBG
    case format14Bayer_RGGB
    case format14Bayer_BGGR
    case format14Bayer_GBRG
    case formatDisparityFloat16
    case formatDisparityFloat32
    case formatDepthFloat16
    case formatDepthFloat32
    case format420YpCbCr10BiPlanarVideoRange
    case format422YpCbCr10BiPlanarVideoRange
    case format444YpCbCr10BiPlanarVideoRange
    case format420YpCbCr10BiPlanarFullRange
    case format422YpCbCr10BiPlanarFullRange
    case format444YpCbCr10BiPlanarFullRange
  }
  public enum ChromaSiting : Equatable, Hashable {
    case left
    case center
    case topLeft
    case top
    case bottomLeft
    case bottom
    case dv420
  }
}
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension vImage.PixelBuffer where Format == vImage.Planar8x3 {
  public init(interleavedBuffer: vImage.PixelBuffer<vImage.Interleaved8x3>) {
    self.init(size: interleavedBuffer.size)
    _deinterleave(from: interleavedBuffer)
  }
  public func convert(to destination: vImage.PixelBuffer<vImage.Interleaved8x3>) {
    _interleave(into: destination)
  }
  public func interleave(destination: vImage.PixelBuffer<vImage.Interleaved8x3>) {
    _interleave(into: destination)
  }
}

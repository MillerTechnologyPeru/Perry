import PerryObjCInterop

// CVPixelBufferCreateWithBytes: a pixel buffer over the program's own
// memory, as Darwin makes one: the pixels stay where the program put them,
// rows its stride apart, and when the buffer goes the memory is handed back
// through the program's release callback. And the chroma siting keys and
// values a buffer's attachments are described with.

/// void (*CVPixelBufferReleaseBytesCallback)(void *releaseRefCon, const void *baseAddress).
public typealias PixelBufferReleaseBytes = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> Void

private let cvSuccess: Int32 = 0, cvInvalidArgument: Int32 = -6661

/// CVReturn CVPixelBufferCreateWithBytes(CFAllocatorRef, size_t width,
/// size_t height, OSType pixelFormatType, void *baseAddress, size_t
/// bytesPerRow, CVPixelBufferReleaseBytesCallback, void *releaseRefCon,
/// CFDictionaryRef pixelBufferAttributes, CVPixelBufferRef *): the buffer
/// (+1) over the memory, in any format, which is taken as it is given.
@c(_CVPixelBufferCreateWithBytes)
public func CVPixelBufferCreateWithBytes(_ allocator: UnsafeRawPointer?, _ width: Int, _ height: Int, _ format: UInt32,
                                         _ baseAddress: UnsafeMutableRawPointer?, _ bytesPerRow: Int,
                                         _ releaseCallback: PixelBufferReleaseBytes?, _ releaseRefCon: UnsafeMutableRawPointer?,
                                         _ attributes: UnsafeRawPointer?,
                                         _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let out else { return cvInvalidArgument }
    out.pointee = nil
    guard let baseAddress, width > 0, height > 0, bytesPerRow > 0 else { return cvInvalidArgument }
    let buffer = NSObject(PixelBuffer.objCClass.pointer).newInstance()
    let state = PixelBufferState()
    (state.width, state.height, state.format) = (width, height, format)
    (state.bytes, state.count, state.bytesPerRow) = (baseAddress, bytesPerRow * height, bytesPerRow)
    state.release = { releaseCallback?(releaseRefCon, UnsafeRawPointer(baseAddress)) }
    PixelBuffer.states.set(buffer.objcObject, state)
    _ = ObjCRuntime.retain(buffer.objcObject)
    out.pointee = buffer.objcObject
    return cvSuccess
}

/// kCVImageBufferChromaLocationTopFieldKey and BottomFieldKey, and the
/// sitings they take, with Darwin's values.
@ObjCConstants
enum ChromaLocations {
    static let kCVImageBufferChromaLocationTopFieldKey = "CVImageBufferChromaLocationTopField"
    static let kCVImageBufferChromaLocationBottomFieldKey = "CVImageBufferChromaLocationBottomField"
    static let kCVImageBufferChromaLocation_Left = "Left"
    static let kCVImageBufferChromaLocation_Center = "Center"
    static let kCVImageBufferChromaLocation_TopLeft = "TopLeft"
    static let kCVImageBufferChromaLocation_Top = "Top"
    static let kCVImageBufferChromaLocation_BottomLeft = "BottomLeft"
    static let kCVImageBufferChromaLocation_Bottom = "Bottom"
    static let kCVImageBufferChromaLocation_DV420 = "DV 4:2:0"
}

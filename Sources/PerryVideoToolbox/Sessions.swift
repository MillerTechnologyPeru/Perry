// VideoToolbox's sessions. None can be made: creating one fails with the
// error for a missing decoder or encoder and leaves the session nil, and
// what is asked of a nil session fails as an invalid session. OSStatus codes
// are VTErrors.h's.

private enum Status {
    static let propertyNotSupported: Int32 = -12900
    static let parameter: Int32 = -12902
    static let invalidSession: Int32 = -12903
    static let couldNotFindDecoder: Int32 = -12906
    static let couldNotFindEncoder: Int32 = -12908
    static let couldNotCreateInstance: Int32 = -12911
}

public typealias Reference = UnsafeMutableRawPointer?
public typealias Result = UnsafeMutablePointer<UnsafeMutableRawPointer?>?

// MARK: - Decoding

@c(_VTIsHardwareDecodeSupported)
public func VTIsHardwareDecodeSupported(_ codecType: UInt32) -> UInt8 { 0 }

@c(_VTRegisterSupplementalVideoDecoderIfAvailable)
public func VTRegisterSupplementalVideoDecoderIfAvailable(_ codecType: UInt32) {}

@c(_VTDecompressionSessionCreate)
public func VTDecompressionSessionCreate(_ allocator: Reference, _ formatDescription: Reference, _ decoderSpecification: Reference,
                                         _ destinationImageBufferAttributes: Reference, _ outputCallback: Reference,
                                         _ session: Result) -> Int32 {
    session?.pointee = nil
    return Status.couldNotFindDecoder
}

@c(_VTDecompressionSessionDecodeFrame)
public func VTDecompressionSessionDecodeFrame(_ session: Reference, _ sampleBuffer: Reference, _ flags: UInt32,
                                              _ frameRefcon: Reference, _ infoFlagsOut: UnsafeMutablePointer<UInt32>?) -> Int32 {
    Status.invalidSession
}

@c(_VTDecompressionSessionDecodeFrameWithOutputHandler)
public func VTDecompressionSessionDecodeFrameWithOutputHandler(_ session: Reference, _ sampleBuffer: Reference, _ flags: UInt32,
                                                               _ infoFlagsOut: UnsafeMutablePointer<UInt32>?,
                                                               _ outputHandler: Reference) -> Int32 {
    Status.invalidSession
}

@c(_VTDecompressionSessionWaitForAsynchronousFrames)
public func VTDecompressionSessionWaitForAsynchronousFrames(_ session: Reference) -> Int32 { 0 }

@c(_VTDecompressionSessionInvalidate)
public func VTDecompressionSessionInvalidate(_ session: Reference) {}

// MARK: - Encoding

@c(_VTCompressionSessionCreate)
public func VTCompressionSessionCreate(_ allocator: Reference, _ width: Int32, _ height: Int32, _ codecType: UInt32,
                                       _ encoderSpecification: Reference, _ sourceImageBufferAttributes: Reference,
                                       _ compressedDataAllocator: Reference, _ outputCallback: Reference,
                                       _ outputCallbackRefCon: Reference, _ session: Result) -> Int32 {
    session?.pointee = nil
    return Status.couldNotFindEncoder
}

@c(_VTCompressionSessionEncodeFrame)
public func VTCompressionSessionEncodeFrame(_ session: Reference, _ imageBuffer: Reference, _ presentationTimeStamp: Reference,
                                            _ duration: Reference, _ frameProperties: Reference, _ sourceFrameRefcon: Reference,
                                            _ infoFlagsOut: UnsafeMutablePointer<UInt32>?) -> Int32 {
    Status.invalidSession
}

@c(_VTCompressionSessionEncodeFrameWithOutputHandler)
public func VTCompressionSessionEncodeFrameWithOutputHandler(_ session: Reference, _ imageBuffer: Reference,
                                                             _ presentationTimeStamp: Reference, _ duration: Reference,
                                                             _ frameProperties: Reference,
                                                             _ infoFlagsOut: UnsafeMutablePointer<UInt32>?,
                                                             _ outputHandler: Reference) -> Int32 {
    Status.invalidSession
}

@c(_VTCompressionSessionCompleteFrames)
public func VTCompressionSessionCompleteFrames(_ session: Reference, _ completeUntilPresentationTimeStamp: Reference) -> Int32 { 0 }

@c(_VTCompressionSessionGetPixelBufferPool)
public func VTCompressionSessionGetPixelBufferPool(_ session: Reference) -> UnsafeMutableRawPointer? { nil }

@c(_VTCompressionSessionInvalidate)
public func VTCompressionSessionInvalidate(_ session: Reference) {}

@c(_VTCopySupportedPropertyDictionaryForEncoder)
public func VTCopySupportedPropertyDictionaryForEncoder(_ width: Int32, _ height: Int32, _ codecType: UInt32,
                                                        _ encoderSpecification: Reference, _ encoderIDOut: Result,
                                                        _ supportedPropertiesOut: Result) -> Int32 {
    encoderIDOut?.pointee = nil
    supportedPropertiesOut?.pointee = nil
    return Status.couldNotFindEncoder
}

// MARK: - Pixel transfer, images and properties

@c(_VTPixelTransferSessionCreate)
public func VTPixelTransferSessionCreate(_ allocator: Reference, _ session: Result) -> Int32 {
    session?.pointee = nil
    return Status.couldNotCreateInstance
}

@c(_VTPixelTransferSessionTransferImage)
public func VTPixelTransferSessionTransferImage(_ session: Reference, _ source: Reference, _ destination: Reference) -> Int32 {
    Status.invalidSession
}

@c(_VTCreateCGImageFromCVPixelBuffer)
public func VTCreateCGImageFromCVPixelBuffer(_ pixelBuffer: Reference, _ options: Reference, _ image: Result) -> Int32 {
    image?.pointee = nil
    return Status.parameter
}

@c(_VTSessionSetProperty)
public func VTSessionSetProperty(_ session: Reference, _ key: Reference, _ value: Reference) -> Int32 { Status.propertyNotSupported }

@c(_VTSessionSetProperties)
public func VTSessionSetProperties(_ session: Reference, _ properties: Reference) -> Int32 { Status.propertyNotSupported }

@c(_VTSessionCopyProperty)
public func VTSessionCopyProperty(_ session: Reference, _ key: Reference, _ allocator: Reference, _ value: Result) -> Int32 {
    value?.pointee = nil
    return Status.propertyNotSupported
}

import Glibc
import PerryObjCInterop

// ImageIO's XMP metadata objects and lossless copies. Image destinations
// here write no metadata, so a metadata object holds no tags: it can be
// made, copied and handed to a destination, which leaves it out.
// CGImageDestinationCopyImageSource writes the source's bytes unchanged to
// a destination of the same type, as Darwin does when there is no metadata
// to change; the metadata options it takes change nothing here.

extension TypeIDs {
    static let imageMetadata: UInt = 99
}

/// kCFErrorDomainCGImageMetadata and CGImageMetadataErrors' codes.
@ObjCConstants
enum ImageMetadataConstants {
    static let kCFErrorDomainCGImageMetadata = "kCFErrorDomainCGImageMetadata"
}

private enum MetadataError {
    static let unknown = 0, unsupportedFormat = 1, badArgument = 2
}

final class ImageMetadataState {}

@ObjCClass("CGImageMetadata")
public final class CGImageMetadataObject: NSObject {
    static let states = StateTable<ImageMetadataState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        CGImageMetadataObject.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CGImageMetadataObject.objCClass.pointer)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { TypeIDs.imageMetadata }
}

@c(_CGImageMetadataGetTypeID) public func CGImageMetadataGetTypeID() -> UInt { TypeIDs.imageMetadata }

/// CGMutableImageMetadataRef CGImageMetadataCreateMutable(void): empty (+1).
@c(_CGImageMetadataCreateMutable)
public func CGImageMetadataCreateMutable() -> Ref? {
    makeObject(CGImageMetadataObject.objCClass, CGImageMetadataObject.states, ImageMetadataState())
}

@c(_CGImageMetadataCreateMutableCopy)
public func CGImageMetadataCreateMutableCopy(_ metadata: Ref?) -> Ref? {
    guard CGImageMetadataObject.states[metadata] != nil else { return nil }
    return CGImageMetadataCreateMutable()
}

/// bool CGImageDestinationCopyImageSource(CGImageDestinationRef,
/// CGImageSourceRef, CFDictionaryRef options, CFErrorRef *): the source's
/// file, written where the destination writes, which is then done; no
/// images may have been added to it. False, with an error in
/// kCFErrorDomainCGImageMetadata, when the types differ or it can't be
/// written.
@c(_CGImageDestinationCopyImageSource)
public func CGImageDestinationCopyImageSource(_ destination: Ref?, _ source: Ref?, _ options: Ref?,
                                              _ error: UnsafeMutablePointer<Ref?>?) -> Bool {
    func fail(_ code: Int, _ message: String) -> Bool {
        if let error {
            let info = NSMutableDictionary.of([("NSLocalizedDescription", NSObject.string(message))])
            error.pointee = FoundationError.make(domain: ImageMetadataConstants.kCFErrorDomainCGImageMetadata, code: code,
                                                 userInfo: info).objCOwnedReturnValue()
        }
        return false
    }
    guard let state = Destinations.state(destination), let image = Sources.state(source), state.images.isEmpty else {
        return fail(MetadataError.badArgument, "CGImageDestinationCopyImageSource: a destination with no images and a source are needed")
    }
    guard image.complete, let type = image.type, type == state.type else {
        return fail(MetadataError.unsupportedFormat, "CGImageDestinationCopyImageSource: the source isn't a complete image of the destination's type")
    }
    if let data = state.data {
        data.replace(with: image.bytes)
        return true
    }
    if let path = state.path, NSData.of(image.bytes).write(toFile: path, atomically: true) { return true }
    return fail(MetadataError.unknown, "CGImageDestinationCopyImageSource: the image couldn't be written")
}

import CPerryGeometry
import PerryObjCInterop

// MetalKit's texture loader: a picture from a file, data, a CGImage or an
// asset catalog as a 2D Metal texture of RGBA, in sRGB unless the options
// say it is linear, with a full chain of mipmaps when asked for. Its
// pixels are premultiplied, as the picture is drawn into them. A private
// texture is filled through a shared buffer on the GPU. The asynchronous
// forms load at once and then call their handlers.

extension PerryMetalRegion: ObjCScalar {
    public static var objCTypeEncoding: String { "{MTLRegion={MTLOrigin=QQQ}{MTLSize=QQQ}}" }
}

extension PerryMetalOrigin: ObjCScalar {
    public static var objCTypeEncoding: String { "{MTLOrigin=QQQ}" }
}

extension PerryMetalSize: ObjCScalar {
    public static var objCTypeEncoding: String { "{MTLSize=QQQ}" }
}

@ObjCConstants
enum TextureLoaderConstants {
    static let MTKTextureLoaderErrorDomain = "MTKTextureLoaderErrorDomain"
    static let MTKTextureLoaderErrorKey = "MTKTextureLoaderErrorKey"
    static let MTKTextureLoaderOptionAllocateMipmaps = "MTKTextureLoaderOptionAllocateMipmaps"
    static let MTKTextureLoaderOptionGenerateMipmaps = "MTKTextureLoaderOptionGenerateMipmaps"
    static let MTKTextureLoaderOptionSRGB = "MTKTextureLoaderOptionSRGB"
    static let MTKTextureLoaderOptionTextureUsage = "MTKTextureLoaderOptionTextureUsage"
    static let MTKTextureLoaderOptionTextureCPUCacheMode = "MTKTextureLoaderOptionTextureCPUCacheMode"
    static let MTKTextureLoaderOptionTextureStorageMode = "MTKTextureLoaderOptionTextureStorageMode"
    static let MTKTextureLoaderOptionCubeLayout = "MTKTextureLoaderOptionCubeLayout"
    static let MTKTextureLoaderCubeLayoutVertical = "MTKTextureLoaderCubeLayoutVertical"
    static let MTKTextureLoaderOptionOrigin = "MTKTextureLoaderOptionOrigin"
    static let MTKTextureLoaderOriginTopLeft = "MTKTextureLoaderOriginTopLeft"
    static let MTKTextureLoaderOriginBottomLeft = "MTKTextureLoaderOriginBottomLeft"
    static let MTKTextureLoaderOriginFlippedVertically = "MTKTextureLoaderOriginFlippedVertically"
    static let MTKTextureLoaderOptionLoadAsArray = "MTKTextureLoaderOptionLoadAsArray"
}

@ObjCClass("MTKTextureLoader")
open class MTKTextureLoader: NSObject {
    typealias Constants = TextureLoaderConstants
    typealias ErrorPointer = UnsafeMutablePointer<UnsafeMutableRawPointer?>?

    var deviceObject: NSObject?
    /// The queue mipmaps are made on, made when first needed.
    var queue: NSObject?

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("initWithDevice:") public init(device: NSObject?) {
        deviceObject = device
        super.init()
    }

    @ObjCMethod("device") func device() -> NSObject? { deviceObject }

    // MARK: Loading

    @ObjCMethod("newTextureWithContentsOfURL:options:error:")
    func newTexture(contentsOf url: NSObject?, options: NSObject?, error: ErrorPointer) -> NSObject? {
        guard let path = url?.texturePath(), let image = TextureImages.image(atPath: path) else {
            TextureImages.fail(error, domain: Constants.MTKTextureLoaderErrorDomain, "Could not load an image from \(url?.texturePath() ?? "no URL")")
            return nil
        }
        return texture(image.object, options: options, error: error)
    }

    @ObjCMethod("newTextureWithData:options:error:")
    func newTexture(data: NSObject?, options: NSObject?, error: ErrorPointer) -> NSObject? {
        guard let image = UIImage.decode(data) else {
            TextureImages.fail(error, domain: Constants.MTKTextureLoaderErrorDomain, "Could not decode the image data")
            return nil
        }
        return texture(image.object, options: options, error: error)
    }

    @ObjCMethod("newTextureWithCGImage:options:error:")
    func newTexture(cgImage: UnsafeMutableRawPointer?, options: NSObject?, error: ErrorPointer) -> NSObject? {
        guard let cgImage else {
            TextureImages.fail(error, domain: Constants.MTKTextureLoaderErrorDomain, "No image")
            return nil
        }
        return texture(cgImage, options: options, error: error)
    }

    /// An asset catalog's image by name; its scale factor picks nothing
    /// here, where a catalog's images have one scale.
    @ObjCMethod("newTextureWithName:scaleFactor:bundle:options:error:")
    func newTexture(name: String?, scaleFactor: CGFloat, bundle: NSObject?, options: NSObject?, error: ErrorPointer) -> NSObject? {
        guard let name, let image = TextureImages.image(named: name, in: bundle) else {
            TextureImages.fail(error, domain: Constants.MTKTextureLoaderErrorDomain, "No image named \(name ?? "nil")")
            return nil
        }
        return texture(image, options: options, error: error)
    }

    @ObjCMethod("newTexturesWithContentsOfURLs:options:error:")
    func newTextures(contentsOf urls: NSObject?, options: NSObject?, error: ErrorPointer) -> NSObject? {
        let urls = urls.map { $0.unsafeCast(to: NSArray.self).elements } ?? []
        return NSMutableArray.of(urls.compactMap { newTexture(contentsOf: $0, options: options, error: error) })
    }

    @ObjCMethod("newTextureWithContentsOfURL:options:completionHandler:")
    func newTexture(contentsOf url: NSObject?, options: NSObject?, completionHandler: ObjCBlock?) {
        var error: UnsafeMutableRawPointer?
        complete(completionHandler, newTexture(contentsOf: url, options: options, error: &error), error)
    }

    @ObjCMethod("newTextureWithData:options:completionHandler:")
    func newTexture(data: NSObject?, options: NSObject?, completionHandler: ObjCBlock?) {
        var error: UnsafeMutableRawPointer?
        complete(completionHandler, newTexture(data: data, options: options, error: &error), error)
    }

    @ObjCMethod("newTextureWithCGImage:options:completionHandler:")
    func newTexture(cgImage: UnsafeMutableRawPointer?, options: NSObject?, completionHandler: ObjCBlock?) {
        var error: UnsafeMutableRawPointer?
        complete(completionHandler, newTexture(cgImage: cgImage, options: options, error: &error), error)
    }

    @ObjCMethod("newTextureWithName:scaleFactor:bundle:options:completionHandler:")
    func newTexture(name: String?, scaleFactor: CGFloat, bundle: NSObject?, options: NSObject?, completionHandler: ObjCBlock?) {
        var error: UnsafeMutableRawPointer?
        complete(completionHandler, newTexture(name: name, scaleFactor: scaleFactor, bundle: bundle, options: options, error: &error), error)
    }

    /// Calls a handler with the texture or the error.
    private func complete(_ handler: ObjCBlock?, _ texture: NSObject?, _ error: UnsafeMutableRawPointer?) {
        guard let handler else { return }
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
        withExtendedLifetime(texture) { handler.function(as: Invoke.self)(handler.object, texture?.objcObject, error) }
    }

    // MARK: Textures

    /// The picture as a texture the options describe.
    private func texture(_ image: CGRef, options: NSObject?, error: ErrorPointer) -> NSObject? {
        guard let device = deviceObject else {
            TextureImages.fail(error, domain: Constants.MTKTextureLoaderErrorDomain, "No Metal device")
            return nil
        }
        let origin = TextureImages.option(options, Constants.MTKTextureLoaderOptionOrigin)
        let flipped = origin.map {
            $0.textureIsEqual(toString: Constants.MTKTextureLoaderOriginBottomLeft)
                || $0.textureIsEqual(toString: Constants.MTKTextureLoaderOriginFlippedVertically)
        } ?? false
        guard let pixels = TextureImages.pixels(of: image, flipped: flipped) else {
            TextureImages.fail(error, domain: Constants.MTKTextureLoaderErrorDomain, "Could not draw the image")
            return nil
        }
        let generate = TextureImages.bool(options, Constants.MTKTextureLoaderOptionGenerateMipmaps) ?? false
        let allocate = generate || (TextureImages.bool(options, Constants.MTKTextureLoaderOptionAllocateMipmaps) ?? false)
        let srgb = TextureImages.bool(options, Constants.MTKTextureLoaderOptionSRGB) ?? true
        let format: UInt = srgb ? 71 : 70   // MTLPixelFormatRGBA8Unorm_sRGB, RGBA8Unorm
        let width = UInt(pixels.width), height = UInt(pixels.height)
        let descriptor = NSObject(objCReturnValue: ObjCClass(named: "MTLTextureDescriptor").object
            .mtkTexture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: allocate))
        descriptor.mtkSetUsage(TextureImages.unsigned(options, Constants.MTKTextureLoaderOptionTextureUsage) ?? 1) // ShaderRead
        descriptor.mtkSetStorageMode(TextureImages.unsigned(options, Constants.MTKTextureLoaderOptionTextureStorageMode) ?? 0)
        guard let texture = device.mtkNewTexture(descriptor: descriptor) else {
            TextureImages.fail(error, domain: Constants.MTKTextureLoaderErrorDomain, "Could not make a \(width)×\(height) texture")
            return nil
        }
        let mipmaps = generate && TextureImages.mipmapLevels(width: pixels.width, height: pixels.height) > 1
        // A private texture can't be written directly: its pixels go
        // through a shared buffer, copied in on the GPU.
        var staging: NSObject?
        if texture.textureStorageMode() == 2 {
            staging = pixels.bytes.withUnsafeBytes {
                device.mtkNewBuffer(bytes: $0.baseAddress!, length: UInt($0.count), options: 0)
            }
            guard staging != nil else {
                TextureImages.fail(error, domain: Constants.MTKTextureLoaderErrorDomain, "Could not stage a \(width)×\(height) image")
                return nil
            }
        } else {
            let region = PerryMetalRegion(x: 0, y: 0, z: 0, width: width, height: height, depth: 1)
            pixels.bytes.withUnsafeBytes {
                texture.textureReplace(region: region, mipmapLevel: 0, bytes: $0.baseAddress, bytesPerRow: UInt(pixels.bytesPerRow))
            }
        }
        if staging != nil || mipmaps {
            blit(texture, from: staging, bytesPerRow: UInt(pixels.bytesPerRow), mipmaps: mipmaps, device: device)
        }
        return texture
    }

    /// Copies the staged pixels into the texture's first level, fills its
    /// smaller levels from that one, and waits.
    private func blit(_ texture: NSObject, from staging: NSObject?, bytesPerRow: UInt, mipmaps: Bool, device: NSObject) {
        if queue == nil { queue = device.textureNewCommandQueue() }
        guard let buffer = queue?.textureCommandBuffer(), let encoder = buffer.textureBlitCommandEncoder() else { return }
        if let staging {
            let size = PerryMetalSize(width: texture.mtkWidth(), height: texture.mtkHeight(), depth: 1)
            encoder.textureCopy(from: staging, sourceOffset: 0, sourceBytesPerRow: bytesPerRow, sourceBytesPerImage: bytesPerRow * size.height,
                                sourceSize: size, to: texture, destinationSlice: 0, destinationLevel: 0,
                                destinationOrigin: PerryMetalOrigin(x: 0, y: 0, z: 0))
        }
        if mipmaps { encoder.textureGenerateMipmaps(for: texture) }
        encoder.textureEndEncoding()
        buffer.textureCommit()
        buffer.textureWaitUntilCompleted()
    }
}

extension NSObject {
    @ObjCMethod("replaceRegion:mipmapLevel:withBytes:bytesPerRow:")
    func textureReplace(region: PerryMetalRegion, mipmapLevel: UInt, bytes: UnsafeRawPointer?, bytesPerRow: UInt)
    @ObjCMethod("copyFromBuffer:sourceOffset:sourceBytesPerRow:sourceBytesPerImage:sourceSize:toTexture:destinationSlice:destinationLevel:destinationOrigin:")
    func textureCopy(from buffer: NSObject, sourceOffset: UInt, sourceBytesPerRow: UInt, sourceBytesPerImage: UInt, sourceSize: PerryMetalSize,
                     to texture: NSObject, destinationSlice: UInt, destinationLevel: UInt, destinationOrigin: PerryMetalOrigin)
    @ObjCMethod("storageMode") func textureStorageMode() -> UInt
    @ObjCMethod("newCommandQueue") func textureNewCommandQueue() -> NSObject?
    @ObjCMethod("commandBuffer") func textureCommandBuffer() -> NSObject?
    @ObjCMethod("blitCommandEncoder") func textureBlitCommandEncoder() -> NSObject?
    @ObjCMethod("generateMipmapsForTexture:") func textureGenerateMipmaps(for texture: NSObject)
    @ObjCMethod("endEncoding") func textureEndEncoding()
    @ObjCMethod("commit") func textureCommit()
    @ObjCMethod("waitUntilCompleted") func textureWaitUntilCompleted()
}

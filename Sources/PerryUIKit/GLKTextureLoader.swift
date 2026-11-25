import CPerryGeometry
import PerryObjCInterop

// GLKit's texture loader: a picture from a file, data, a CGImage or an
// asset catalog as a 2D texture of the current OpenGL ES context, RGBA,
// with mipmaps when asked for, described by a GLKTextureInfo. Its pixels
// are premultiplied, as the picture is drawn into them. The texture
// binding is left as it was.

@ObjCConstants
enum GLKTextureLoaderConstants {
    static let GLKTextureLoaderErrorDomain = "GLKTextureLoaderErrorDomain"
    static let GLKTextureLoaderErrorKey = "GLKTextureLoaderErrorKey"
    static let GLKTextureLoaderGLErrorKey = "GLKTextureLoaderGLErrorKey"
    static let GLKTextureLoaderApplyPremultiplication = "GLKTextureLoaderApplyPremultiplication"
    static let GLKTextureLoaderGenerateMipmaps = "GLKTextureLoaderGenerateMipmaps"
    static let GLKTextureLoaderOriginBottomLeft = "GLKTextureLoaderOriginBottomLeft"
    static let GLKTextureLoaderGrayscaleAsAlpha = "GLKTextureLoaderGrayscaleAsAlpha"
    static let GLKTextureLoaderSRGB = "GLKTextureLoaderSRGB"
}

@ObjCClass("GLKTextureInfo")
open class GLKTextureInfo: NSObject {
    var textureName: UInt32 = 0
    var textureWidth: UInt32 = 0
    var textureHeight: UInt32 = 0
    var bottomLeft = false
    var mipmapLevels: UInt32 = 1

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }

    @ObjCMethod("name") func name() -> UInt32 { textureName }
    @ObjCMethod("target") func target() -> UInt32 { UInt32(GLES.texture2D) }
    @ObjCMethod("width") func width() -> UInt32 { textureWidth }
    @ObjCMethod("height") func height() -> UInt32 { textureHeight }
    @ObjCMethod("depth") func depth() -> UInt32 { 1 }
    /// GLKTextureInfoAlphaStatePremultiplied.
    @ObjCMethod("alphaState") func alphaState() -> Int32 { 2 }
    /// GLKTextureInfoOriginTopLeft 1, BottomLeft 2.
    @ObjCMethod("textureOrigin") func textureOrigin() -> Int32 { bottomLeft ? 2 : 1 }
    @ObjCMethod("containsMipmaps") func containsMipmaps() -> Bool { mipmapLevels > 1 }
    @ObjCMethod("mimapLevelCount") func mimapLevelCount() -> UInt32 { mipmapLevels }
    @ObjCMethod("arrayLength") func arrayLength() -> UInt32 { 1 }
}

@ObjCClass("GLKTextureLoader")
open class GLKTextureLoader: NSObject {
    typealias Constants = GLKTextureLoaderConstants
    typealias ErrorPointer = UnsafeMutablePointer<UnsafeMutableRawPointer?>?

    @ObjCMethod("init") public required override init() { super.init() }

    /// A loader for a share group's contexts; it loads into the current one.
    @ObjCMethod("initWithSharegroup:") public init(sharegroup: NSObject?) { super.init() }

    @ObjCClassMethod("textureWithContentsOfFile:options:error:")
    static func texture(contentsOfFile path: String?, options: NSObject?, error: ErrorPointer) -> NSObject? {
        guard let path, let image = TextureImages.image(atPath: path) else {
            TextureImages.fail(error, domain: Constants.GLKTextureLoaderErrorDomain, code: 1, "Could not load an image from \(path ?? "nil")")
            return nil
        }
        return texture(image.object, options: options, error: error)
    }

    @ObjCClassMethod("textureWithContentsOfURL:options:error:")
    static func texture(contentsOf url: NSObject?, options: NSObject?, error: ErrorPointer) -> NSObject? {
        texture(contentsOfFile: url?.texturePath(), options: options, error: error)
    }

    @ObjCClassMethod("textureWithContentsOfData:options:error:")
    static func texture(contentsOfData data: NSObject?, options: NSObject?, error: ErrorPointer) -> NSObject? {
        guard let image = UIImage.decode(data) else {
            TextureImages.fail(error, domain: Constants.GLKTextureLoaderErrorDomain, code: 1, "Could not decode the image data")
            return nil
        }
        return texture(image.object, options: options, error: error)
    }

    @ObjCClassMethod("textureWithCGImage:options:error:")
    static func texture(cgImage: UnsafeMutableRawPointer?, options: NSObject?, error: ErrorPointer) -> NSObject? {
        guard let cgImage else {
            TextureImages.fail(error, domain: Constants.GLKTextureLoaderErrorDomain, code: 1, "No image")
            return nil
        }
        return texture(cgImage, options: options, error: error)
    }

    @ObjCClassMethod("textureWithName:scaleFactor:bundle:options:error:")
    static func texture(name: String?, scaleFactor: CGFloat, bundle: NSObject?, options: NSObject?, error: ErrorPointer) -> NSObject? {
        guard let name, let image = TextureImages.image(named: name, in: bundle) else {
            TextureImages.fail(error, domain: Constants.GLKTextureLoaderErrorDomain, code: 1, "No image named \(name ?? "nil")")
            return nil
        }
        return texture(image, options: options, error: error)
    }

    /// The picture as a texture of the current context.
    private static func texture(_ image: CGRef, options: NSObject?, error: ErrorPointer) -> NSObject? {
        let bottomLeft = TextureImages.bool(options, Constants.GLKTextureLoaderOriginBottomLeft) ?? false
        guard GLES.getCurrentContext?() != nil, let genTextures = GLES.genTextures, let bindTexture = GLES.bindTexture,
              let texParameteri = GLES.texParameteri, let texImage2D = GLES.texImage2D else {
            TextureImages.fail(error, domain: Constants.GLKTextureLoaderErrorDomain, code: 8, "No current OpenGL ES context")
            return nil
        }
        // OpenGL's first row is its bottom one: the picture's last row
        // goes first when its origin is to be the bottom left.
        guard let pixels = TextureImages.pixels(of: image, flipped: bottomLeft) else {
            TextureImages.fail(error, domain: Constants.GLKTextureLoaderErrorDomain, code: 1, "Could not draw the image")
            return nil
        }
        let mipmaps = (TextureImages.bool(options, Constants.GLKTextureLoaderGenerateMipmaps) ?? false) && GLES.generateMipmap != nil
        let srgb = TextureImages.bool(options, Constants.GLKTextureLoaderSRGB) ?? false
        var previous: Int32 = 0
        GLES.getIntegerv(GLES.textureBinding2D, &previous)
        var name: UInt32 = 0
        genTextures(1, &name)
        bindTexture(GLES.texture2D, name)
        GLES.pixelStorei?(0x0CF5, 4)    // GL_UNPACK_ALIGNMENT
        let internalFormat: Int32 = srgb ? Int32(GLES.srgb8Alpha8) : 0x1908 // GL_RGBA
        pixels.bytes.withUnsafeBytes {
            texImage2D(GLES.texture2D, 0, internalFormat, Int32(pixels.width), Int32(pixels.height), 0, 0x1908, 0x1401, $0.baseAddress)
        }
        texParameteri(GLES.texture2D, 0x2800, 0x2601)  // MAG_FILTER, LINEAR
        if mipmaps {
            GLES.generateMipmap?(GLES.texture2D)
            texParameteri(GLES.texture2D, 0x2801, 0x2703)  // MIN_FILTER, LINEAR_MIPMAP_LINEAR
        } else {
            texParameteri(GLES.texture2D, 0x2801, 0x2601)  // MIN_FILTER, LINEAR
        }
        bindTexture(GLES.texture2D, UInt32(bitPattern: previous))
        let info = GLKTextureInfo()
        info.textureName = name
        info.textureWidth = UInt32(pixels.width)
        info.textureHeight = UInt32(pixels.height)
        info.bottomLeft = bottomLeft
        info.mipmapLevels = mipmaps ? UInt32(TextureImages.mipmapLevels(width: pixels.width, height: pixels.height)) : 1
        return info
    }
}

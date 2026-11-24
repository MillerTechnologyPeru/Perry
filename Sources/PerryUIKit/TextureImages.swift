import CPerryGeometry
import PerryObjCInterop

// MetalKit's and GLKit's texture loaders' pictures: a file's, some data's,
// a CGImage, or an asset catalog's image, drawn once into premultiplied
// RGBA, eight bits a channel, top row first, or bottom row first for a
// loader whose origin is the bottom left.

enum TextureImages {
    struct Pixels {
        let width: Int
        let height: Int
        var bytes: [UInt8]
        var bytesPerRow: Int { width * 4 }
    }

    /// The first image in a file.
    static func image(atPath path: String) -> Owned? { UIImage.decode(NSData.contents(ofFile: path)) }

    /// An asset catalog's image, or a file's by that name, in `bundle` or
    /// the main bundle.
    static func image(named name: String, in bundle: NSObject?) -> UnsafeMutableRawPointer? {
        let bundle = bundle?.as(NSBundle.self) ?? NSBundle.main()
        return UIImage.image(UIImage.objCClass, named: name, in: bundle, catalog: true)?.cgImage()
    }

    /// The picture's pixels, its last row first when `flipped`.
    static func pixels(of image: CGRef, flipped: Bool) -> Pixels? {
        let width = CG.imageGetWidth(image), height = CG.imageGetHeight(image)
        guard width > 0, height > 0, let space = CG.colorSpaceCreateDeviceRGB() else { return nil }
        defer { CG.release(space) }
        var pixels = Pixels(width: width, height: height, bytes: [UInt8](repeating: 0, count: width * height * 4))
        let rowBytes = pixels.bytesPerRow
        let drawn = pixels.bytes.withUnsafeMutableBytes { buffer -> Bool in
            // Premultiplied last, in byte order: R, G, B, A.
            guard let context = CG.bitmapContextCreate(buffer.baseAddress, width, height, 8, rowBytes, space, 1 | 0x4000) else {
                return false
            }
            defer { CG.release(context) }
            CG.drawImage(context, CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)), image)
            guard flipped, let base = buffer.baseAddress else { return true }
            var row = [UInt8](repeating: 0, count: rowBytes)
            for top in 0..<height / 2 {
                let a = base + top * rowBytes, b = base + (height - 1 - top) * rowBytes
                row.withUnsafeMutableBytes { $0.baseAddress!.copyMemory(from: a, byteCount: rowBytes) }
                a.copyMemory(from: b, byteCount: rowBytes)
                row.withUnsafeBytes { b.copyMemory(from: $0.baseAddress!, byteCount: rowBytes) }
            }
            return true
        }
        return drawn ? pixels : nil
    }

    /// The number of levels down to one pixel.
    static func mipmapLevels(width: Int, height: Int) -> Int {
        var size = max(width, height), levels = 1
        while size > 1 {
            size /= 2
            levels += 1
        }
        return levels
    }

    /// An options dictionary's value for a key, by the key's text.
    static func option(_ options: NSObject?, _ key: String) -> NSObject? {
        guard let options, options.responds(to: "objectForKey:") else { return nil }
        return options.unsafeCast(to: NSDictionary.self).object(forKey: key)
    }

    static func bool(_ options: NSObject?, _ key: String) -> Bool? {
        guard let value = option(options, key), value.responds(to: "boolValue") else { return nil }
        return value.textureBoolValue()
    }

    static func unsigned(_ options: NSObject?, _ key: String) -> UInt? {
        guard let value = option(options, key), value.responds(to: "unsignedIntegerValue") else { return nil }
        return value.mtkUnsignedIntegerValue()
    }

    /// An error in `domain` with `message` as its description, when the
    /// caller asked for one.
    static func fail(_ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, domain: String, code: Int = 0, _ message: String) {
        guard let error else { return }
        let info = NSDictionary.make(object: NSObject(objCReturnValue: message.objCArgument()), forKey: "NSLocalizedDescription")
        error.pointee = NSErrorObject.make(domain: domain, code: code, userInfo: info).objCReturnValue()
    }
}

extension NSObject {
    @ObjCMethod("boolValue") func textureBoolValue() -> Bool
    @ObjCMethod("isEqualToString:") func textureIsEqual(toString string: String) -> Bool
    @ObjCMethod("path") func texturePath() -> String?
}

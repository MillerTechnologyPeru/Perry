import CPerryGeometry
import Glibc
import PerryAssetCatalog
import PerryObjCInterop

// A bundle's compiled asset catalog, Assets.car, from which +imageNamed:,
// +colorNamed: and their variants for other bundles take what is not a
// loose file. The catalog is read by PerryAssetCatalog; UIKit makes its
// pixels images.

enum AssetCatalog {
    static func load(_ lookup: (String, String) -> UnsafeMutableRawPointer?) {
        CompiledAssetCatalog.decode = lookup("/usr/lib/libcompression.dylib", "_compression_decode_buffer")
            .map { unsafeBitCast($0, to: CompiledAssetCatalog.Decode.self) }
    }

    nonisolated(unsafe) static let main: CompiledAssetCatalog? =
        NSBundle.main().path(forResource: "Assets", ofType: "car").flatMap(CompiledAssetCatalog.init)

    /// The named color's components, for the dark appearance or the
    /// default one.
    static func color(named name: String, dark: Bool = false) -> [CGFloat]? { main?.components(named: name, dark: dark) }

    /// The named image at the scale nearest the screen's, for the dark
    /// appearance or the default one.
    static func image(named name: String, dark: Bool = false) -> (image: Owned, scale: CGFloat)? {
        main?.image(named: name, dark: dark)
    }

    /// Other bundles' catalogs (a Swift package's resource bundle, a
    /// framework's), by the bundle's path, read the first time one of their
    /// images is asked for.
    nonisolated(unsafe) private static var catalogs: [String: CompiledAssetCatalog?] = [:]
    private static let lock = Lock()

    static func catalog(in bundle: NSBundle) -> CompiledAssetCatalog? {
        guard let path = bundle.path(forResource: "Assets", ofType: "car") else { return nil }
        return lock.withLock {
            if let catalog = catalogs[path] { return catalog }
            let catalog = CompiledAssetCatalog(path: path)
            catalogs[path] = catalog
            return catalog
        }
    }
}

extension CompiledAssetCatalog {
    /// A named color's components as CGFloats.
    func components(named name: String, dark: Bool) -> [CGFloat]? {
        color(named: name, dark: dark)?.map { CGFloat($0) }
    }

    /// The named image at the screen's scale (see pixels(named:)), or an
    /// image extracted on a Mac for a rendition Perry can't decode.
    func image(named name: String, dark: Bool = false) -> (image: Owned, scale: CGFloat)? {
        let screen = Int(Screen.scale.rounded())
        if let (pixels, scale) = pixels(named: name, dark: dark, screenScale: screen), let image = makeImage(pixels) {
            return (image, CGFloat(scale))
        }
        for (file, scale) in extractedImageFiles(named: name, dark: dark, screenScale: screen) {
            guard let data = NSData.contents(ofFile: file), let image = UIImage.decode(data) else { continue }
            return (image, CGFloat(scale))
        }
        return nil
    }

    private func makeImage(_ pixels: Pixels) -> Owned? {
        guard pixels.width > 0, pixels.height > 0, let space = CG.colorSpaceCreateDeviceRGB() else { return nil }
        defer { CG.release(space) }
        let rowBytes = pixels.width * 4
        guard let context = CG.bitmapContextCreate(nil, pixels.width, pixels.height, 8, rowBytes, space, CG.bitmapInfo(opaque: false)) else {
            return nil
        }
        defer { CG.release(context) }
        guard let data = CG.bitmapContextGetData(context) else { return nil }
        pixels.bytes.withUnsafeBytes { data.copyMemory(from: $0.baseAddress!, byteCount: min($0.count, rowBytes * pixels.height)) }
        return CG.bitmapContextCreateImage(context).map(Owned.init)
    }
}

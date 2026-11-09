import Glibc
import CPerryGeometry
import PerryAssetCatalog
import PerryObjCInterop

// The main bundle's compiled asset catalog (Contents/Resources/Assets.car),
// which +[NSColor colorNamed:] and +[NSImage imageNamed:] fall back to for
// names that are neither system colors nor loose image files.

enum AppKitAssets {
    nonisolated(unsafe) static let main: CompiledAssetCatalog? = {
        if CompiledAssetCatalog.decode == nil {
            CompiledAssetCatalog.decode = Symbols.symbol("/usr/lib/libcompression.dylib", "_compression_decode_buffer")
                .map { unsafeBitCast($0, to: CompiledAssetCatalog.Decode.self) }
        }
        return CompiledAssetCatalog(path: NSBundle.main().bundlePath() + "/Contents/Resources/Assets.car")
    }()

    /// A named color, in the current appearance's variant.
    static func color(named name: String) -> NSColor? {
        guard let components = main?.color(named: name, dark: Appearances.currentIsDark) else { return nil }
        switch components.count {
        case 2: return NSColor(white: CGFloat(components[0]), alpha: CGFloat(components[1]))
        case 4...: return NSColor(red: CGFloat(components[0]), green: CGFloat(components[1]), blue: CGFloat(components[2]), alpha: CGFloat(components[3]))
        default: return nil
        }
    }

    /// The scale of the images picked for the display: its own, rounded up,
    /// from @1x to @3x, so an image is never shown larger than it was made
    /// (@2x for a desktop scaled by 166%).
    static var displayScale: Int { max(1, min(3, Int((Screens.display.density - 0.01).rounded(.up)))) }

    /// A named image's bitmap at the display's scale (see displayScale), and
    /// its size in points.
    static func image(named name: String) -> (image: CGRef, size: CGSize)? {
        guard CG.ready, let (pixels, scale) = main?.pixels(named: name, dark: Appearances.currentIsDark, screenScale: displayScale),
              let space = CG.colorSpaceCreateDeviceRGB() else { return nil }
        defer { CG.release(space) }
        var bytes = pixels.bytes
        let image: CGRef? = bytes.withUnsafeMutableBytes { buffer in
            // Premultiplied alpha first in 32-bit little-endian words: BGRA.
            guard let context = CG.bitmapContextCreate(buffer.baseAddress, pixels.width, pixels.height, 8, pixels.width * 4, space, 2 | 0x2000)
            else { return nil }
            defer { CG.release(context) }
            return CG.bitmapContextCreateImage(context)
        }
        guard let image else { return nil }
        return (image, CGSize(width: CGFloat(pixels.width) / CGFloat(scale), height: CGFloat(pixels.height) / CGFloat(scale)))
    }

    /// A PNG Scripts/extract-assets.sh decoded on a Mac for a rendition
    /// Perry can't decode (vector and deepmap ones), and its scale.
    static func extractedImage(named name: String) -> (path: String, scale: Int)? {
        main?.extractedImageFiles(named: name, dark: Appearances.currentIsDark, screenScale: displayScale)
            .first { access($0.path, R_OK) == 0 }
    }

    static func isTemplate(named name: String) -> Bool { main?.isTemplate(named: name) ?? false }
}

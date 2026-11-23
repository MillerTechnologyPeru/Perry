import CoreVideo

// vImageCVImageFormat.Format and ChromaSiting as CoreVideo has them.

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension vImageCVImageFormat.Format {
    /// The CoreVideo pixel format type of the case.
    var _pixelFormatType: OSType {
        switch self {
        case .format1Monochrome: return kCVPixelFormatType_1Monochrome
        case .format2Indexed: return kCVPixelFormatType_2Indexed
        case .format4Indexed: return kCVPixelFormatType_4Indexed
        case .format8Indexed: return kCVPixelFormatType_8Indexed
        case .format1IndexedGray_WhiteIsZero: return kCVPixelFormatType_1IndexedGray_WhiteIsZero
        case .format2IndexedGray_WhiteIsZero: return kCVPixelFormatType_2IndexedGray_WhiteIsZero
        case .format4IndexedGray_WhiteIsZero: return kCVPixelFormatType_4IndexedGray_WhiteIsZero
        case .format8IndexedGray_WhiteIsZero: return kCVPixelFormatType_8IndexedGray_WhiteIsZero
        case .format16BE555: return kCVPixelFormatType_16BE555
        case .format16LE555: return kCVPixelFormatType_16LE555
        case .format16LE5551: return kCVPixelFormatType_16LE5551
        case .format16BE565: return kCVPixelFormatType_16BE565
        case .format16LE565: return kCVPixelFormatType_16LE565
        case .format24RGB: return kCVPixelFormatType_24RGB
        case .format24BGR: return kCVPixelFormatType_24BGR
        case .format32ARGB: return kCVPixelFormatType_32ARGB
        case .format32BGRA: return kCVPixelFormatType_32BGRA
        case .format32ABGR: return kCVPixelFormatType_32ABGR
        case .format32RGBA: return kCVPixelFormatType_32RGBA
        case .format64ARGB: return kCVPixelFormatType_64ARGB
        case .format48RGB: return kCVPixelFormatType_48RGB
        case .format32AlphaGray: return kCVPixelFormatType_32AlphaGray
        case .format16Gray: return kCVPixelFormatType_16Gray
        case .format30RGB: return kCVPixelFormatType_30RGB
        case .format422YpCbCr8: return kCVPixelFormatType_422YpCbCr8
        case .format4444YpCbCrA8: return kCVPixelFormatType_4444YpCbCrA8
        case .format4444YpCbCrA8R: return kCVPixelFormatType_4444YpCbCrA8R
        case .format4444AYpCbCr8: return kCVPixelFormatType_4444AYpCbCr8
        case .format4444AYpCbCr16: return kCVPixelFormatType_4444AYpCbCr16
        case .format444YpCbCr8: return kCVPixelFormatType_444YpCbCr8
        case .format422YpCbCr16: return kCVPixelFormatType_422YpCbCr16
        case .format422YpCbCr10: return kCVPixelFormatType_422YpCbCr10
        case .format444YpCbCr10: return kCVPixelFormatType_444YpCbCr10
        case .format420YpCbCr8Planar: return kCVPixelFormatType_420YpCbCr8Planar
        case .format420YpCbCr8PlanarFullRange: return kCVPixelFormatType_420YpCbCr8PlanarFullRange
        case .format422YpCbCr_4A_8BiPlanar: return kCVPixelFormatType_422YpCbCr_4A_8BiPlanar
        case .format420YpCbCr8BiPlanarVideoRange: return kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        case .format420YpCbCr8BiPlanarFullRange: return kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        case .format422YpCbCr8_yuvs: return kCVPixelFormatType_422YpCbCr8_yuvs
        case .format422YpCbCr8FullRange: return kCVPixelFormatType_422YpCbCr8FullRange
        case .formatOneComponent8: return kCVPixelFormatType_OneComponent8
        case .formatTwoComponent8: return kCVPixelFormatType_TwoComponent8
        case .format30RGBLEPackedWideGamut: return kCVPixelFormatType_30RGBLEPackedWideGamut
        case .formatARGB2101010LEPacked: return kCVPixelFormatType_ARGB2101010LEPacked
        case .formatOneComponent16Half: return kCVPixelFormatType_OneComponent16Half
        case .formatOneComponent32Float: return kCVPixelFormatType_OneComponent32Float
        case .formatTwoComponent16Half: return kCVPixelFormatType_TwoComponent16Half
        case .formatTwoComponent32Float: return kCVPixelFormatType_TwoComponent32Float
        case .format64RGBAHalf: return kCVPixelFormatType_64RGBAHalf
        case .format128RGBAFloat: return kCVPixelFormatType_128RGBAFloat
        case .format14Bayer_GRBG: return kCVPixelFormatType_14Bayer_GRBG
        case .format14Bayer_RGGB: return kCVPixelFormatType_14Bayer_RGGB
        case .format14Bayer_BGGR: return kCVPixelFormatType_14Bayer_BGGR
        case .format14Bayer_GBRG: return kCVPixelFormatType_14Bayer_GBRG
        case .formatDisparityFloat16: return kCVPixelFormatType_DisparityFloat16
        case .formatDisparityFloat32: return kCVPixelFormatType_DisparityFloat32
        case .formatDepthFloat16: return kCVPixelFormatType_DepthFloat16
        case .formatDepthFloat32: return kCVPixelFormatType_DepthFloat32
        case .format420YpCbCr10BiPlanarVideoRange: return kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
        case .format422YpCbCr10BiPlanarVideoRange: return kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange
        case .format444YpCbCr10BiPlanarVideoRange: return kCVPixelFormatType_444YpCbCr10BiPlanarVideoRange
        case .format420YpCbCr10BiPlanarFullRange: return kCVPixelFormatType_420YpCbCr10BiPlanarFullRange
        case .format422YpCbCr10BiPlanarFullRange: return kCVPixelFormatType_422YpCbCr10BiPlanarFullRange
        case .format444YpCbCr10BiPlanarFullRange: return kCVPixelFormatType_444YpCbCr10BiPlanarFullRange
        }
    }
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension vImageCVImageFormat.ChromaSiting {
    var _location: CFString {
        switch self {
        case .left: return kCVImageBufferChromaLocation_Left
        case .center: return kCVImageBufferChromaLocation_Center
        case .topLeft: return kCVImageBufferChromaLocation_TopLeft
        case .top: return kCVImageBufferChromaLocation_Top
        case .bottomLeft: return kCVImageBufferChromaLocation_BottomLeft
        case .bottom: return kCVImageBufferChromaLocation_Bottom
        case .dv420: return kCVImageBufferChromaLocation_DV420
        }
    }

    init?(_location location: CFString) {
        for siting in [Self.left, .center, .topLeft, .top, .bottomLeft, .bottom, .dv420] where CFEqual(siting._location, location) {
            self = siting
            return
        }
        return nil
    }
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension vImage.BufferType {
    static let _allCases: [vImage.BufferType] = [
        .alpha, .coreGraphics, .cmykBlack, .cmykCyan, .cmykMagenta, .cmykYellow, .YCbCr, .Cb, .Cr, .chroma, .chunky,
        .indexed, .labA, .labB, .labL, .luminance, .monochrome, .rgbRed, .rgbGreen, .rgbBlue, .xyzX, .xyzY, .xyzZ,
    ]

    var _ordinal: Int {
        switch self {
        case .alpha: return 0
        case .coreGraphics: return 1
        case .cmykBlack: return 2
        case .cmykCyan: return 3
        case .cmykMagenta: return 4
        case .cmykYellow: return 5
        case .YCbCr: return 6
        case .Cb: return 7
        case .Cr: return 8
        case .chroma: return 9
        case .chunky: return 10
        case .indexed: return 11
        case .labA: return 12
        case .labB: return 13
        case .labL: return 14
        case .luminance: return 15
        case .monochrome: return 16
        case .rgbRed: return 17
        case .rgbGreen: return 18
        case .rgbBlue: return 19
        case .xyzX: return 20
        case .xyzY: return 21
        case .xyzZ: return 22
        }
    }
}

extension vImageCVImageFormat {
    /// The format as the read-only type vImage's getters take.
    var _const: vImageConstCVImageFormat { unsafeBitCast(self, to: vImageConstCVImageFormat.self) }
}

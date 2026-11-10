import CPerryCoreGraphics
import Glibc
import PerryObjCInterop

// Color spaces, colors, data providers and images. Pixels in any of the
// 8-bit formats CGImageCreate takes convert to and from premultiplied RGBA,
// in which contexts draw and codecs exchange images.

enum TypeIDs {
    static let colorSpace: UInt = 73, color: UInt = 74, image: UInt = 75, dataProvider: UInt = 76, context: UInt = 77
    static let imageSource: UInt = 78, imageDestination: UInt = 79
    static let font: UInt = 80
}

// MARK: - Pixel formats

/// A pixel layout: components per color, CGBitmapInfo's alpha and byte order.
struct PixelFormat: Equatable {
    var bitsPerComponent: Int
    var bitsPerPixel: Int
    var colorComponents: Int
    var bitmapInfo: UInt32

    /// CGImageAlphaInfo: none 0, premultiplied last 1, premultiplied first 2,
    /// last 3, first 4, skip last 5, skip first 6, only 7.
    var alphaInfo: UInt32 { bitmapInfo & 0x1f }
    var byteOrder: UInt32 { bitmapInfo & 0x7000 }
    var bytesPerPixel: Int { bitsPerPixel / 8 }
    var hasAlpha: Bool { [1, 2, 3, 4, 7].contains(alphaInfo) }

    static let rgbaPremultiplied = PixelFormat(bitsPerComponent: 8, bitsPerPixel: 32, colorComponents: 3, bitmapInfo: 1)
    static let rgbx = PixelFormat(bitsPerComponent: 8, bitsPerPixel: 32, colorComponents: 3, bitmapInfo: 5)

    var isSupported: Bool {
        guard bitsPerComponent == 8 || bitsPerComponent == 16 else { return false }
        let channels = colorComponents + (alphaInfo == 0 ? 0 : alphaInfo == 7 ? 1 - colorComponents : 1)
        return channels > 0 && channels * bitsPerComponent == bitsPerPixel
    }

    /// Byte positions in memory order of the channels as listed: the byte
    /// orders reverse each 16- or 32-bit word.
    private func memoryIndex(_ channel: Int) -> Int {
        let componentBytes = bitsPerComponent / 8
        let offset = channel * componentBytes
        switch byteOrder {
        case 0x2000: return bytesPerPixel - componentBytes - offset + (componentBytes == 2 ? 1 : 0)
        case 0x1000 where bytesPerPixel == 2: return 1 - offset
        default: return offset
        }
    }

    /// The pixel at `pointer` as premultiplied RGBA.
    func read(_ pointer: UnsafeRawPointer) -> (UInt8, UInt8, UInt8, UInt8) {
        func channel(_ index: Int) -> UInt8 { pointer.load(fromByteOffset: memoryIndex(index), as: UInt8.self) }
        var color: [UInt8] = []
        var alpha: UInt8 = 255
        switch alphaInfo {
        case 2, 4, 6:
            if alphaInfo != 6 { alpha = channel(0) }
            color = (0..<colorComponents).map { channel($0 + 1) }
        case 1, 3, 5:
            color = (0..<colorComponents).map(channel)
            if alphaInfo != 5 { alpha = channel(colorComponents) }
        case 7:
            alpha = channel(0)
            color = [0, 0, 0]
        default:
            color = (0..<colorComponents).map(channel)
        }
        if color.count == 1 { color = [color[0], color[0], color[0]] }
        if alphaInfo == 3 || alphaInfo == 4 {
            color = color.map { UInt8((Int($0) * Int(alpha) + 127) / 255) }
        }
        return (color[0], color[1], color[2], alpha)
    }

    /// Stores premultiplied RGBA at `pointer` in this format.
    func write(_ pixel: (UInt8, UInt8, UInt8, UInt8), to pointer: UnsafeMutableRawPointer) {
        let (r, g, b, a) = pixel
        var color: [UInt8]
        if colorComponents == 1 {
            color = [UInt8((Int(r) * 299 + Int(g) * 587 + Int(b) * 114 + 500) / 1000)]
        } else {
            color = [r, g, b]
        }
        if (alphaInfo == 3 || alphaInfo == 4) && a > 0 {
            color = color.map { UInt8(min(255, (Int($0) * 255 + Int(a) / 2) / Int(a))) }
        }
        var channels: [UInt8]
        switch alphaInfo {
        case 2, 4: channels = [a] + color
        case 6: channels = [255] + color
        case 1, 3: channels = color + [a]
        case 5: channels = color + [255]
        case 7: channels = [a]
        default: channels = color
        }
        for (index, value) in channels.enumerated() { pointer.storeBytes(of: value, toByteOffset: memoryIndex(index), as: UInt8.self) }
    }
}

/// Premultiplied RGBA pixels, rows from the top.
struct Bitmap {
    var width: Int
    var height: Int
    var pixels: [UInt8]

    init(width: Int, height: Int, pixels: [UInt8]? = nil) {
        self.width = width
        self.height = height
        self.pixels = pixels ?? [UInt8](repeating: 0, count: width * height * 4)
    }

    /// From straight RGBA, as codecs produce.
    init(width: Int, height: Int, straight: UnsafePointer<UInt8>) {
        self.init(width: width, height: height)
        for index in 0..<(width * height) {
            let a = Int(straight[index * 4 + 3])
            for c in 0..<3 { pixels[index * 4 + c] = UInt8((Int(straight[index * 4 + c]) * a + 127) / 255) }
            pixels[index * 4 + 3] = UInt8(a)
        }
    }

    /// Straight RGBA, for encoders.
    var straight: [UInt8] {
        var out = pixels
        for index in 0..<(width * height) {
            let a = Int(pixels[index * 4 + 3])
            guard a > 0, a < 255 else { continue }
            for c in 0..<3 { out[index * 4 + c] = UInt8(min(255, (Int(pixels[index * 4 + c]) * 255 + a / 2) / a)) }
        }
        return out
    }

    var isOpaque: Bool { stride(from: 3, to: pixels.count, by: 4).allSatisfy { pixels[$0] == 255 } }

    func pixel(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        let i = (y * width + x) * 4
        return (pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3])
    }

    /// Resized: averaging when shrinking, nearest pixel when growing.
    func resized(width newWidth: Int, height newHeight: Int) -> Bitmap {
        guard newWidth != width || newHeight != height else { return self }
        var out = Bitmap(width: newWidth, height: newHeight)
        let sx = Double(width) / Double(newWidth), sy = Double(height) / Double(newHeight)
        for y in 0..<newHeight {
            for x in 0..<newWidth {
                let x0 = Int(Double(x) * sx), y0 = Int(Double(y) * sy)
                let x1 = max(x0 + 1, min(width, Int((Double(x + 1) * sx).rounded(.up))))
                let y1 = max(y0 + 1, min(height, Int((Double(y + 1) * sy).rounded(.up))))
                var sums = [0, 0, 0, 0]
                for yy in y0..<min(y1, height) {
                    for xx in x0..<min(x1, width) {
                        let i = (yy * width + xx) * 4
                        for c in 0..<4 { sums[c] += Int(pixels[i + c]) }
                    }
                }
                let count = max(1, (min(y1, height) - y0) * (min(x1, width) - x0))
                let o = (y * newWidth + x) * 4
                for c in 0..<4 { out.pixels[o + c] = UInt8((sums[c] + count / 2) / count) }
            }
        }
        return out
    }
}

// MARK: - Color spaces

final class ColorSpaceState: @unchecked Sendable {
    /// CGColorSpaceModel: monochrome 0, RGB 1, CMYK 2.
    let model: Int32
    let name: String?

    init(model: Int32, name: String?) {
        self.model = model
        self.name = name
    }

    var components: Int { model == 0 ? 1 : model == 2 ? 4 : 3 }
}

@ObjCClass("CGColorSpace")
public final class CGColorSpaceObject: NSObject {
    static let states = StateTable<ColorSpaceState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        CGColorSpaceObject.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CGColorSpaceObject.objCClass.pointer)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { TypeIDs.colorSpace }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: NSObject?) -> Bool {
        guard let other = CGColorSpaceObject.states[other?.objcObject], let mine = CGColorSpaceObject.states[objcObject] else { return false }
        return other.model == mine.model && other.name == mine.name
    }
}

enum ColorSpaces {
    static func make(model: Int32, name: String?) -> Ref {
        makeObject(CGColorSpaceObject.objCClass, CGColorSpaceObject.states, ColorSpaceState(model: model, name: name))
    }

    static func state(_ space: Ref?) -> ColorSpaceState? { CGColorSpaceObject.states[space] }
}

/// Color space names.
@ObjCConstants
enum ColorSpaceNames {
    static let kCGColorWhite = "kCGColorWhite"
    static let kCGColorBlack = "kCGColorBlack"
    static let kCGColorClear = "kCGColorClear"
    static let kCGColorSpaceSRGB = "kCGColorSpaceSRGB"
    static let kCGColorSpaceLinearDisplayP3 = "kCGColorSpaceLinearDisplayP3"
    static let kCGColorSpaceExtendedLinearDisplayP3 = "kCGColorSpaceExtendedLinearDisplayP3"
    static let kCGColorSpaceITUR_2100_PQ = "kCGColorSpaceITUR_2100_PQ"
    static let kCGColorSpaceGenericRGB = "kCGColorSpaceGenericRGB"
    static let kCGColorSpaceGenericRGBLinear = "kCGColorSpaceGenericRGBLinear"
    static let kCGColorSpaceGenericGray = "kCGColorSpaceGenericGray"
    static let kCGColorSpaceGenericGrayGamma2_2 = "kCGColorSpaceGenericGrayGamma2_2"
    static let kCGColorSpaceLinearGray = "kCGColorSpaceLinearGray"
    static let kCGColorSpaceExtendedGray = "kCGColorSpaceExtendedGray"
    static let kCGColorSpaceLinearSRGB = "kCGColorSpaceLinearSRGB"
    static let kCGColorSpaceExtendedSRGB = "kCGColorSpaceExtendedSRGB"
    static let kCGColorSpaceExtendedLinearSRGB = "kCGColorSpaceExtendedLinearSRGB"
    static let kCGColorSpaceDisplayP3 = "kCGColorSpaceDisplayP3"
    static let kCGColorSpaceExtendedDisplayP3 = "kCGColorSpaceExtendedDisplayP3"
    static let kCGColorSpaceAdobeRGB1998 = "kCGColorSpaceAdobeRGB1998"
    static let kCGColorSpaceITUR_709 = "kCGColorSpaceITUR_709"
    static let kCGColorSpaceITUR_2020 = "kCGColorSpaceITUR_2020"
    static let kCGColorSpaceGenericCMYK = "kCGColorSpaceGenericCMYK"
}

@c(_CGColorSpaceGetTypeID) public func CGColorSpaceGetTypeID() -> UInt { TypeIDs.colorSpace }
@c(_CGColorSpaceCreateDeviceRGB) public func CGColorSpaceCreateDeviceRGB() -> Ref { ColorSpaces.make(model: 1, name: nil) }
@c(_CGColorSpaceCreateDeviceGray) public func CGColorSpaceCreateDeviceGray() -> Ref { ColorSpaces.make(model: 0, name: nil) }
@c(_CGColorSpaceCreateDeviceCMYK) public func CGColorSpaceCreateDeviceCMYK() -> Ref { ColorSpaces.make(model: 2, name: nil) }

/// Calibrated spaces, by white and black points, gamma and a matrix: drawn
/// as device RGB and gray are, colors passing through unconverted.
@c(_CGColorSpaceCreateCalibratedRGB)
public func CGColorSpaceCreateCalibratedRGB(_ whitePoint: UnsafePointer<CGFloat>?, _ blackPoint: UnsafePointer<CGFloat>?,
                                            _ gamma: UnsafePointer<CGFloat>?, _ matrix: UnsafePointer<CGFloat>?) -> Ref {
    ColorSpaces.make(model: 1, name: nil)
}

@c(_CGColorSpaceCreateCalibratedGray)
public func CGColorSpaceCreateCalibratedGray(_ whitePoint: UnsafePointer<CGFloat>?, _ blackPoint: UnsafePointer<CGFloat>?,
                                             _ gamma: CGFloat) -> Ref {
    ColorSpaces.make(model: 0, name: nil)
}

@c(_CGColorSpaceCreateWithName)
public func CGColorSpaceCreateWithName(_ name: Ref?) -> Ref? {
    guard let name else { return nil }
    let text = String(objCArgument: name)
    let model: Int32 = text.contains("Gray") ? 0 : text.contains("CMYK") ? 2 : 1
    return ColorSpaces.make(model: model, name: text)
}

@c(_CGColorSpaceGetNumberOfComponents)
public func CGColorSpaceGetNumberOfComponents(_ space: Ref?) -> Int { ColorSpaces.state(space)?.components ?? 0 }

@c(_CGColorSpaceGetModel) public func CGColorSpaceGetModel(_ space: Ref?) -> Int32 { ColorSpaces.state(space)?.model ?? -1 }

/// Whether the space uses an ITU-R BT.2100 transfer function, PQ or HLG,
/// as the spaces named for it do.
@c(_CGColorSpaceUsesITUR_2100TF)
public func CGColorSpaceUsesITUR_2100TF(_ space: Ref?) -> Bool {
    guard let name = ColorSpaces.state(space)?.name else { return false }
    return name.contains("2100_PQ") || name.contains("2100_HLG")
}

@c(_CGColorSpaceCopyName)
public func CGColorSpaceCopyName(_ space: Ref?) -> Ref? { ColorSpaces.state(space)?.name.flatMap { $0.objCOwnedReturnValue() } }

@c(_CGColorSpaceGetName)
public func CGColorSpaceGetName(_ space: Ref?) -> Ref? {
    ColorSpaces.state(space)?.name.flatMap { NSObject.string($0).objCReturnValue() }
}

@c(_CGColorSpaceRetain) public func CGColorSpaceRetain(_ space: Ref?) -> Ref? { ObjCRuntime.retain(space) }
@c(_CGColorSpaceRelease) public func CGColorSpaceRelease(_ space: Ref?) { ObjCRuntime.release(space) }

// MARK: - Colors

final class ColorState: @unchecked Sendable {
    let space: Ref
    let components: [Double]

    init(space: Ref, components: [Double]) {
        self.space = ObjCRuntime.retain(space)!
        self.components = components
    }

    deinit { ObjCRuntime.release(space) }

    /// As red, green, blue and alpha.
    var rgba: (Double, Double, Double, Double) {
        if components.count == 2 { return (components[0], components[0], components[0], components[1]) }
        if components.count >= 4 && ColorSpaces.state(space)?.model != 2 { return (components[0], components[1], components[2], components[3]) }
        if components.count == 5 {
            let k = components[3]
            return ((1 - components[0]) * (1 - k), (1 - components[1]) * (1 - k), (1 - components[2]) * (1 - k), components[4])
        }
        return (0, 0, 0, 1)
    }
}

@ObjCClass("CGColor")
public final class CGColorObject: NSObject {
    static let states = StateTable<ColorState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        CGColorObject.states.remove(objcObject)
        ComponentBuffers.remove(for: objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CGColorObject.objCClass.pointer)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { TypeIDs.color }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: NSObject?) -> Bool {
        guard let other = CGColorObject.states[other?.objcObject], let mine = CGColorObject.states[objcObject] else { return false }
        return other.components == mine.components && ColorSpaces.state(other.space)?.model == ColorSpaces.state(mine.space)?.model
    }
}

enum Colors {
    static func make(_ space: Ref, _ components: [Double]) -> Ref {
        makeObject(CGColorObject.objCClass, CGColorObject.states, ColorState(space: space, components: components))
    }

    static func state(_ color: Ref?) -> ColorState? { CGColorObject.states[color] }
}

@c(_CGColorGetTypeID) public func CGColorGetTypeID() -> UInt { TypeIDs.color }

@c(_CGColorCreate)
public func CGColorCreate(_ space: Ref?, _ components: UnsafePointer<CGFloat>?) -> Ref? {
    guard let space, let components, let state = ColorSpaces.state(space) else { return nil }
    return Colors.make(space, UnsafeBufferPointer(start: components, count: state.components + 1).map { Double($0) })
}

@DarwinC("_CGColorCreateGenericRGB")
public func CGColorCreateGenericRGB(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> Ref {
    let space = CGColorSpaceCreateWithName(NSObject.string("kCGColorSpaceSRGB").objcObject)!
    defer { ObjCRuntime.release(space) }
    return Colors.make(space, [Double(r), Double(g), Double(b), Double(a)])
}

@DarwinC("_CGColorCreateSRGB")
public func CGColorCreateSRGB(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> Ref { CGColorCreateGenericRGB(r, g, b, a) }

@DarwinC("_CGColorCreateGenericGray")
public func CGColorCreateGenericGray(_ gray: CGFloat, _ a: CGFloat) -> Ref {
    let space = CGColorSpaceCreateDeviceGray()
    defer { ObjCRuntime.release(space) }
    return Colors.make(space, [Double(gray), Double(a)])
}

/// The constant colors by name, kCGColorWhite, kCGColorBlack and
/// kCGColorClear, made once.
nonisolated(unsafe) private var constantColors: [String: Ref] = [:]

@c(_CGColorGetConstantColor)
public func CGColorGetConstantColor(_ name: UnsafeMutableRawPointer?) -> Ref? {
    guard let name else { return nil }
    let key = String(objCArgument: name)
    if let color = constantColors[key] { return color }
    let color: Ref
    switch key {
    case "kCGColorWhite": color = CGColorCreateGenericGray(1, 1)
    case "kCGColorBlack": color = CGColorCreateGenericGray(0, 1)
    case "kCGColorClear": color = CGColorCreateGenericGray(0, 0)
    default: return nil
    }
    constantColors[key] = color
    return color
}

@DarwinC("_CGColorCreateCopyWithAlpha")
public func CGColorCreateCopyWithAlpha(_ color: Ref?, _ alpha: CGFloat) -> Ref? {
    guard let state = Colors.state(color) else { return nil }
    return Colors.make(state.space, Array(state.components.dropLast()) + [Double(alpha)])
}

/// The color in another color space, its alpha kept: gray, RGB and CMYK
/// convert by their usual formulas, with no color management, so sRGB and
/// device RGB match; nil for a space of another model. SwiftUI resolves
/// every color that isn't already sRGB this way: a nil here is black.
@c(_CGColorCreateCopyByMatchingToColorSpace)
public func CGColorCreateCopyByMatchingToColorSpace(_ space: Ref?, _ intent: Int32, _ color: Ref?, _ options: Ref?) -> Ref? {
    guard let space, let target = ColorSpaces.state(space), let state = Colors.state(color),
          let source = ColorSpaces.state(state.space) else { return nil }
    let values = Array(state.components.dropLast()), alpha = state.components.last ?? 1
    // The color as RGB, then as the target's model.
    let rgb: [Double]
    switch source.model {
    case 0 where values.count == 1: rgb = [values[0], values[0], values[0]]
    case 1 where values.count == 3: rgb = values
    case 2 where values.count == 4:
        rgb = values.prefix(3).map { (1 - $0) * (1 - values[3]) }
    default: return nil
    }
    let converted: [Double]
    switch target.model {
    case 0: converted = [0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]]
    case 1: converted = rgb
    case 2:
        let black = 1 - (rgb.max() ?? 0)
        converted = black >= 1 ? [0, 0, 0, 1] : rgb.map { (1 - $0 - black) / (1 - black) } + [black]
    default: return nil
    }
    return Colors.make(space, converted + [alpha])
}

@c(_CGColorGetNumberOfComponents) public func CGColorGetNumberOfComponents(_ color: Ref?) -> Int { Colors.state(color)?.components.count ?? 0 }
@DarwinC("_CGColorGetAlpha") public func CGColorGetAlpha(_ color: Ref?) -> CGFloat { CGFloat(Colors.state(color)?.components.last ?? 0) }
@c(_CGColorGetColorSpace) public func CGColorGetColorSpace(_ color: Ref?) -> Ref? { Colors.state(color)?.space }

/// The components live as long as the color, as CGFloats.
@c(_CGColorGetComponents)
public func CGColorGetComponents(_ color: Ref?) -> UnsafePointer<CGFloat>? {
    guard let state = Colors.state(color) else { return nil }
    return ComponentBuffers.buffer(for: color!, state.components)
}

enum ComponentBuffers {
    static let lock = Lock()
    nonisolated(unsafe) static var buffers: [Ref: UnsafeMutablePointer<CGFloat>] = [:]

    static func buffer(for color: Ref, _ components: [Double]) -> UnsafePointer<CGFloat> {
        lock.withLock {
            if let buffer = buffers[color] { return UnsafePointer(buffer) }
            let buffer = UnsafeMutablePointer<CGFloat>.allocate(capacity: components.count)
            buffer.initialize(from: components.map { CGFloat($0) }, count: components.count)
            buffers[color] = buffer
            return UnsafePointer(buffer)
        }
    }

    /// Frees a color's buffer as the color goes, so a new color at its
    /// address has its own components.
    static func remove(for color: Ref) {
        let buffer = lock.withLock { buffers.removeValue(forKey: color) }
        buffer?.deallocate()
    }
}

@c(_CGColorEqualToColor) public func CGColorEqualToColor(_ a: Ref?, _ b: Ref?) -> Bool {
    a == b || (a != nil && b != nil && NSObject(a!).unsafeCast(to: CGColorObject.self).isEqual(NSObject(b!)))
}

@c(_CGColorRetain) public func CGColorRetain(_ color: Ref?) -> Ref? { ObjCRuntime.retain(color) }
@c(_CGColorRelease) public func CGColorRelease(_ color: Ref?) { ObjCRuntime.release(color) }

// MARK: - Data providers

final class DataProviderState: @unchecked Sendable {
    let bytes: [UInt8]
    let release: (() -> Void)?

    init(bytes: [UInt8], release: (() -> Void)? = nil) {
        self.bytes = bytes
        self.release = release
    }

    deinit { release?() }
}

@ObjCClass("CGDataProvider")
public final class CGDataProviderObject: NSObject {
    static let states = StateTable<DataProviderState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        CGDataProviderObject.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CGDataProviderObject.objCClass.pointer)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { TypeIDs.dataProvider }
}

enum DataProviders {
    static func make(_ bytes: [UInt8], release: (() -> Void)? = nil) -> Ref {
        makeObject(CGDataProviderObject.objCClass, CGDataProviderObject.states, DataProviderState(bytes: bytes, release: release))
    }

    static func bytes(_ provider: Ref?) -> [UInt8]? { CGDataProviderObject.states[provider]?.bytes }
}

@c(_CGDataProviderGetTypeID) public func CGDataProviderGetTypeID() -> UInt { TypeIDs.dataProvider }

/// The bytes are copied; the release callback runs when the provider goes.
@c(_CGDataProviderCreateWithData)
public func CGDataProviderCreateWithData(_ info: UnsafeMutableRawPointer?, _ data: UnsafeRawPointer?, _ size: Int,
                                         _ release: (@convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, Int) -> Void)?) -> Ref? {
    guard let data else { return nil }
    let bytes = Array(UnsafeRawBufferPointer(start: data, count: size))
    nonisolated(unsafe) let info = info
    return DataProviders.make(bytes, release: release.map { callback in { callback(info, data, size) } })
}

@c(_CGDataProviderCreateWithCFData)
public func CGDataProviderCreateWithCFData(_ data: Ref?) -> Ref? {
    guard let data else { return nil }
    return DataProviders.make(NSData(objCArgument: data).array)
}

@c(_CGDataProviderCreateWithFilename)
public func CGDataProviderCreateWithFilename(_ filename: UnsafePointer<CChar>?) -> Ref? {
    guard let filename, let data = NSData.make(contentsOfFile: String(cString: filename)) else { return nil }
    return DataProviders.make(data.array)
}

@c(_CGDataProviderCreateWithURL)
public func CGDataProviderCreateWithURL(_ url: Ref?) -> Ref? {
    guard let url, let path = NSURL(objCArgument: url).path(), let data = NSData.make(contentsOfFile: path) else { return nil }
    return DataProviders.make(data.array)
}

/// A provider that reads its bytes in order: CGDataProviderSequentialCallbacks,
/// a version then four function pointers (the version takes a word's room).
/// Its bytes are read through at once, so the provider answers like the others;
/// the release callback runs when the provider goes.
@c(_CGDataProviderCreateSequential)
public func CGDataProviderCreateSequential(_ info: UnsafeMutableRawPointer?, _ callbacks: UnsafeRawPointer?) -> Ref? {
    guard let callbacks else { return nil }
    typealias GetBytes = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int) -> Int
    typealias Rewind = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias ReleaseInfo = @convention(c) (UnsafeMutableRawPointer?) -> Void
    let word = MemoryLayout<UnsafeRawPointer>.size
    func function(_ index: Int) -> UnsafeRawPointer? {
        callbacks.load(fromByteOffset: word * (index + 1), as: UnsafeRawPointer?.self)
    }
    guard let getBytesPointer = function(0) else { return nil }
    let getBytes = unsafeBitCast(getBytesPointer, to: GetBytes.self)
    let rewind = function(2).map { unsafeBitCast($0, to: Rewind.self) }
    let releaseInfo = function(3).map { unsafeBitCast($0, to: ReleaseInfo.self) }
    rewind?(info)
    var bytes: [UInt8] = []
    var chunk = [UInt8](repeating: 0, count: 65536)
    while true {
        let count = chunk.withUnsafeMutableBytes { getBytes(info, $0.baseAddress, $0.count) }
        if count <= 0 { break }
        bytes.append(contentsOf: chunk[0..<min(count, chunk.count)])
    }
    nonisolated(unsafe) let info = info
    return DataProviders.make(bytes, release: releaseInfo.map { callback in { callback(info) } })
}

@c(_CGDataProviderCopyData)
public func CGDataProviderCopyData(_ provider: Ref?) -> Ref? {
    DataProviders.bytes(provider).map { NSData.of($0).objCOwnedReturnValue() } ?? nil
}

@c(_CGDataProviderRetain) public func CGDataProviderRetain(_ provider: Ref?) -> Ref? { ObjCRuntime.retain(provider) }
@c(_CGDataProviderRelease) public func CGDataProviderRelease(_ provider: Ref?) { ObjCRuntime.release(provider) }

// MARK: - Images

final class ImageState: @unchecked Sendable {
    let width: Int
    let height: Int
    let format: PixelFormat
    let bytesPerRow: Int
    let space: Ref?
    let provider: Ref
    let shouldInterpolate: Bool
    /// The UTType of the file it was read from.
    var typeIdentifier: String?
    private var cached: Bitmap?
    /// What a canvas made to draw the image, kept for the next draw.
    var renderCache: AnyObject?

    init(width: Int, height: Int, format: PixelFormat, bytesPerRow: Int, space: Ref?, provider: Ref, shouldInterpolate: Bool = true) {
        self.width = width
        self.height = height
        self.format = format
        self.bytesPerRow = bytesPerRow
        self.space = space.flatMap { ObjCRuntime.retain($0) }
        self.provider = ObjCRuntime.retain(provider)!
        self.shouldInterpolate = shouldInterpolate
    }

    deinit {
        ObjCRuntime.release(space)
        ObjCRuntime.release(provider)
    }

    /// Whether the pixels are 8-bit RGB with premultiplied or skipped alpha
    /// first in 32-bit little-endian words: B, G, R, A in memory, as bitmap
    /// contexts draw for layers and as Cairo's ARGB32 surfaces keep them.
    var isBGRA: Bool {
        format.bitsPerComponent == 8 && format.bitsPerPixel == 32 && format.colorComponents == 3
            && format.byteOrder == 0x2000 && (format.alphaInfo == 2 || format.alphaInfo == 6)
    }

    /// Whether the pixels are 8-bit premultiplied (or skipped) RGBA in memory
    /// order: the bitmap's own layout.
    var isRGBA: Bool {
        format.bitsPerComponent == 8 && format.bitsPerPixel == 32 && format.colorComponents == 3
            && (format.byteOrder == 0 || format.byteOrder == 0x4000) && (format.alphaInfo == 1 || format.alphaInfo == 5)
    }

    /// The pixels as premultiplied RGBA.
    var bitmap: Bitmap {
        if let cached { return cached }
        var bitmap = Bitmap(width: width, height: height)
        let bytes = DataProviders.bytes(provider) ?? []
        // The common layouts row by row, without reading each pixel's
        // channels one by one.
        if (isBGRA || isRGBA), bytes.count >= bytesPerRow * (height - 1) + width * 4 {
            let opaque = format.alphaInfo == 5 || format.alphaInfo == 6
            let swap = isBGRA
            bytes.withUnsafeBytes { raw in
                bitmap.pixels.withUnsafeMutableBytes { pixels in
                    guard let source = raw.baseAddress?.assumingMemoryBound(to: UInt8.self),
                          let destination = pixels.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                    for y in 0..<height {
                        let from = source + y * bytesPerRow, to = destination + y * width * 4
                        if !swap && !opaque {
                            to.update(from: from, count: width * 4)
                            continue
                        }
                        for x in 0..<width {
                            let i = x * 4
                            if swap {
                                (to[i], to[i + 1], to[i + 2]) = (from[i + 2], from[i + 1], from[i])
                            } else {
                                (to[i], to[i + 1], to[i + 2]) = (from[i], from[i + 1], from[i + 2])
                            }
                            to[i + 3] = opaque ? 255 : from[i + 3]
                        }
                    }
                }
            }
            cached = bitmap
            return bitmap
        }
        bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            for y in 0..<height {
                for x in 0..<width {
                    let offset = y * bytesPerRow + x * format.bytesPerPixel
                    guard offset + format.bytesPerPixel <= raw.count else { continue }
                    let (r, g, b, a) = format.read(base + offset)
                    let i = (y * width + x) * 4
                    (bitmap.pixels[i], bitmap.pixels[i + 1], bitmap.pixels[i + 2], bitmap.pixels[i + 3]) = (r, g, b, a)
                }
            }
        }
        cached = bitmap
        return bitmap
    }
}

@ObjCClass("CGImage")
public final class CGImageObject: NSObject {
    static let states = StateTable<ImageState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        CGImageObject.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CGImageObject.objCClass.pointer)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { TypeIDs.image }

    @ObjCMethod("description")
    func description() -> String {
        guard let state = Images.state(objcObject) else { return "<CGImage \(objcObject)>" }
        return "<CGImage \(objcObject)> (IP) <<CGColorSpace>> width = \(state.width), height = \(state.height), "
            + "bpc = \(state.format.bitsPerComponent), bpp = \(state.format.bitsPerPixel), row bytes = \(state.bytesPerRow)"
    }
}

enum Images {
    static func state(_ image: Ref?) -> ImageState? { CGImageObject.states[image] }

    /// A new image (+1) of premultiplied RGBA pixels, or RGBX when opaque
    /// and `opaqueSkipsAlpha`.
    static func make(_ bitmap: Bitmap, format: PixelFormat = .rgbaPremultiplied, typeIdentifier: String? = nil) -> Ref {
        let space = CGColorSpaceCreateDeviceRGB()
        defer { ObjCRuntime.release(space) }
        var bytes = bitmap.pixels
        if format.alphaInfo == 5 {
            for index in stride(from: 3, to: bytes.count, by: 4) { bytes[index] = 255 }
        }
        let provider = DataProviders.make(bytes)
        defer { ObjCRuntime.release(provider) }
        let state = ImageState(width: bitmap.width, height: bitmap.height, format: format, bytesPerRow: bitmap.width * 4,
                               space: space, provider: provider)
        state.typeIdentifier = typeIdentifier
        return makeObject(CGImageObject.objCClass, CGImageObject.states, state)
    }
}

@c(_CGImageGetTypeID) public func CGImageGetTypeID() -> UInt { TypeIDs.image }

@c(_CGImageCreate)
public func CGImageCreate(_ width: Int, _ height: Int, _ bitsPerComponent: Int, _ bitsPerPixel: Int, _ bytesPerRow: Int, _ space: Ref?,
                          _ bitmapInfo: UInt32, _ provider: Ref?, _ decode: UnsafePointer<CGFloat>?, _ shouldInterpolate: Bool,
                          _ intent: Int32) -> Ref? {
    guard let provider, width > 0, height > 0 else { return nil }
    let components = ColorSpaces.state(space)?.components ?? (bitmapInfo & 0x1f == 7 ? 0 : 3)
    let format = PixelFormat(bitsPerComponent: bitsPerComponent, bitsPerPixel: bitsPerPixel, colorComponents: max(components, 1),
                             bitmapInfo: bitmapInfo)
    guard format.isSupported || bitmapInfo & 0x1f == 7 else { return nil }
    return makeObject(CGImageObject.objCClass, CGImageObject.states,
                      ImageState(width: width, height: height, format: format, bytesPerRow: bytesPerRow, space: space, provider: provider,
                                 shouldInterpolate: shouldInterpolate))
}

@c(_CGImageMaskCreate)
public func CGImageMaskCreate(_ width: Int, _ height: Int, _ bitsPerComponent: Int, _ bitsPerPixel: Int, _ bytesPerRow: Int,
                              _ provider: Ref?, _ decode: UnsafePointer<CGFloat>?, _ shouldInterpolate: Bool) -> Ref? {
    CGImageCreate(width, height, bitsPerComponent, bitsPerPixel, bytesPerRow, nil, 7, provider, decode, shouldInterpolate, 0)
}

@c(_CGImageCreateCopy) public func CGImageCreateCopy(_ image: Ref?) -> Ref? { ObjCRuntime.retain(image) }

/// The image in another color space of the same model: the image itself,
/// as its samples stay what they are and colors are not matched here.
@c(_CGImageCreateCopyWithColorSpace)
public func CGImageCreateCopyWithColorSpace(_ image: Ref?, _ space: Ref?) -> Ref? { ObjCRuntime.retain(image) }

/// The rect is in pixels from the top-left, clipped to the image.
@DarwinC("_CGImageCreateWithImageInRect")
public func CGImageCreateWithImageInRect(_ image: Ref?, _ rect: CGRect) -> Ref? {
    guard let state = Images.state(image) else { return nil }
    let r = CGRectIntegral(CGRectIntersection(CGRectStandardize(rect), CGRect(origin: CGPoint(x: 0, y: 0),
                                                                              size: CGSize(width: CGFloat(state.width), height: CGFloat(state.height)))))
    guard !CGRectIsEmpty(r) else { return nil }
    let x0 = Int(r.origin.x), y0 = Int(r.origin.y), w = Int(r.size.width), h = Int(r.size.height)
    let source = state.bitmap
    var cropped = Bitmap(width: w, height: h)
    for y in 0..<h {
        for x in 0..<w {
            let s = ((y0 + y) * source.width + x0 + x) * 4, d = (y * w + x) * 4
            for c in 0..<4 { cropped.pixels[d + c] = source.pixels[s + c] }
        }
    }
    let format = state.format == .rgbx || state.format.alphaInfo == 5 ? PixelFormat.rgbx : .rgbaPremultiplied
    return Images.make(cropped, format: format)
}

@c(_CGImageGetWidth) public func CGImageGetWidth(_ image: Ref?) -> Int { Images.state(image)?.width ?? 0 }
@c(_CGImageGetHeight) public func CGImageGetHeight(_ image: Ref?) -> Int { Images.state(image)?.height ?? 0 }
@c(_CGImageGetBitsPerComponent) public func CGImageGetBitsPerComponent(_ image: Ref?) -> Int { Images.state(image)?.format.bitsPerComponent ?? 0 }
@c(_CGImageGetBitsPerPixel) public func CGImageGetBitsPerPixel(_ image: Ref?) -> Int { Images.state(image)?.format.bitsPerPixel ?? 0 }
@c(_CGImageGetBytesPerRow) public func CGImageGetBytesPerRow(_ image: Ref?) -> Int { Images.state(image)?.bytesPerRow ?? 0 }
@c(_CGImageGetColorSpace) public func CGImageGetColorSpace(_ image: Ref?) -> Ref? { Images.state(image)?.space }
@c(_CGImageGetAlphaInfo) public func CGImageGetAlphaInfo(_ image: Ref?) -> UInt32 { Images.state(image)?.format.alphaInfo ?? 0 }
@c(_CGImageGetBitmapInfo) public func CGImageGetBitmapInfo(_ image: Ref?) -> UInt32 { Images.state(image)?.format.bitmapInfo ?? 0 }
@c(_CGImageGetByteOrderInfo) public func CGImageGetByteOrderInfo(_ image: Ref?) -> UInt32 { (Images.state(image)?.format.byteOrder ?? 0) >> 12 }
@c(_CGImageGetPixelFormatInfo) public func CGImageGetPixelFormatInfo(_ image: Ref?) -> UInt32 { 0 }
@c(_CGImageGetDataProvider) public func CGImageGetDataProvider(_ image: Ref?) -> Ref? { Images.state(image)?.provider }
@c(_CGImageGetShouldInterpolate) public func CGImageGetShouldInterpolate(_ image: Ref?) -> Bool { Images.state(image)?.shouldInterpolate ?? false }
@c(_CGImageGetRenderingIntent) public func CGImageGetRenderingIntent(_ image: Ref?) -> Int32 { 0 }
@c(_CGImageGetDecode) public func CGImageGetDecode(_ image: Ref?) -> UnsafePointer<CGFloat>? { nil }
@c(_CGImageIsMask) public func CGImageIsMask(_ image: Ref?) -> Bool { Images.state(image)?.format.alphaInfo == 7 }

@c(_CGImageGetUTType)
public func CGImageGetUTType(_ image: Ref?) -> Ref? {
    Images.state(image)?.typeIdentifier.flatMap { NSObject.string($0).objCReturnValue() }
}

@c(_CGImageRetain) public func CGImageRetain(_ image: Ref?) -> Ref? { ObjCRuntime.retain(image) }
@c(_CGImageRelease) public func CGImageRelease(_ image: Ref?) { ObjCRuntime.release(image) }

import CPerryCoreGraphics
import Glibc
import PerryObjCInterop

// Color spaces as data: ICC profiles, property lists, and the indexed and
// pattern spaces with their base spaces and color tables.
//
// A space made from an ICC profile keeps the profile and gives it back. The
// named spaces have profiles made here: ICC v4 matrix/TRC display profiles
// (or a gray TRC profile) from each space's published primaries, adapted to
// the D50 white the profile connection space uses, and its transfer curve as
// a parametric curve. Spaces with no such simple description (CMYK, the PQ
// and HLG spaces, Lab) have none, as CoreGraphics answers for a space without
// a profile.

enum ICCProfiles {
    struct XYZ { var x, y, z: Double }

    /// A transfer curve: Y = (aX + b)^g for X >= d, else cX (ICC parametric
    /// function type 3); a pure power when only g is given (type 0).
    struct Curve {
        var g: Double
        var a = 1.0, b = 0.0, c = 0.0, d = 0.0
        var isPower = true

        static func power(_ g: Double) -> Curve { Curve(g: g) }
        static let sRGB = Curve(g: 2.4, a: 1 / 1.055, b: 0.055 / 1.055, c: 1 / 12.92, d: 0.04045, isPower: false)
        static let rec709 = Curve(g: 1 / 0.45, a: 1 / 1.099, b: 0.099 / 1.099, c: 1 / 4.5, d: 0.081, isPower: false)
    }

    static let d50 = XYZ(x: 0.9642, y: 1.0, z: 0.8249)

    /// Colorants (red, green, blue) adapted to D50, as profiles store them.
    static let sRGBColorants = (XYZ(x: 0.4360, y: 0.2225, z: 0.0139), XYZ(x: 0.3851, y: 0.7169, z: 0.0971),
                                XYZ(x: 0.1431, y: 0.0606, z: 0.7141))
    static let displayP3Colorants = (XYZ(x: 0.5151, y: 0.2412, z: -0.0011), XYZ(x: 0.2920, y: 0.6922, z: 0.0419),
                                     XYZ(x: 0.1571, y: 0.0666, z: 0.7841))
    static let adobeRGBColorants = (XYZ(x: 0.6097, y: 0.3111, z: 0.0195), XYZ(x: 0.2053, y: 0.6257, z: 0.0609),
                                    XYZ(x: 0.1492, y: 0.0632, z: 0.7446))
    static let rec2020Colorants = (XYZ(x: 0.6734, y: 0.2790, z: -0.0019), XYZ(x: 0.1656, y: 0.6753, z: 0.0299),
                                   XYZ(x: 0.1251, y: 0.0456, z: 0.7973))

    /// The profile for a space, or nil when it has none.
    static func profile(for state: ColorSpaceState) -> [UInt8]? {
        if let data = state.iccData { return data }
        let name = state.name ?? (state.model == 0 ? "kCGColorSpaceGenericGrayGamma2_2" : state.model == 1 ? "kCGColorSpaceSRGB" : "")
        switch name {
        case "kCGColorSpaceSRGB", "kCGColorSpaceExtendedSRGB", "kCGColorSpaceGenericRGB":
            return rgb("sRGB IEC61966-2.1", sRGBColorants, .sRGB)
        case "kCGColorSpaceLinearSRGB", "kCGColorSpaceExtendedLinearSRGB", "kCGColorSpaceGenericRGBLinear":
            return rgb("sRGB Linear", sRGBColorants, .power(1))
        case "kCGColorSpaceDisplayP3", "kCGColorSpaceExtendedDisplayP3":
            return rgb("Display P3", displayP3Colorants, .sRGB)
        case "kCGColorSpaceLinearDisplayP3", "kCGColorSpaceExtendedLinearDisplayP3":
            return rgb("Display P3 Linear", displayP3Colorants, .power(1))
        case "kCGColorSpaceAdobeRGB1998":
            return rgb("Adobe RGB (1998)", adobeRGBColorants, .power(563.0 / 256))
        case "kCGColorSpaceITUR_709":
            return rgb("ITU-R BT.709", sRGBColorants, .rec709)
        case "kCGColorSpaceITUR_2020":
            return rgb("ITU-R BT.2020", rec2020Colorants, .rec709)
        case "kCGColorSpaceGenericGrayGamma2_2", "kCGColorSpaceGenericGray", "kCGColorSpaceExtendedGray":
            return gray("Generic Gray Gamma 2.2", .power(2.2))
        case "kCGColorSpaceLinearGray", "kCGColorSpaceExtendedLinearGray":
            return gray("Linear Gray", .power(1))
        default:
            return nil
        }
    }

    static func rgb(_ description: String, _ colorants: (XYZ, XYZ, XYZ), _ curve: Curve) -> [UInt8] {
        let trc = parametric(curve)
        return build(space: "RGB ", tags: [("desc", text(description)), ("cprt", text("No copyright, use freely")),
                                           ("wtpt", xyz(d50)), ("rXYZ", xyz(colorants.0)), ("gXYZ", xyz(colorants.1)),
                                           ("bXYZ", xyz(colorants.2)), ("rTRC", trc), ("gTRC", trc), ("bTRC", trc)])
    }

    static func gray(_ description: String, _ curve: Curve) -> [UInt8] {
        build(space: "GRAY", tags: [("desc", text(description)), ("cprt", text("No copyright, use freely")),
                                    ("wtpt", xyz(d50)), ("kTRC", parametric(curve))])
    }

    // MARK: Encoding

    private static func append32(_ value: UInt32, to bytes: inout [UInt8]) {
        bytes += [UInt8(value >> 24), UInt8((value >> 16) & 0xff), UInt8((value >> 8) & 0xff), UInt8(value & 0xff)]
    }

    private static func append16(_ value: UInt16, to bytes: inout [UInt8]) { bytes += [UInt8(value >> 8), UInt8(value & 0xff)] }

    private static func signature(_ text: String, to bytes: inout [UInt8]) { bytes += Array(text.utf8.prefix(4)) }

    /// s15Fixed16Number.
    private static func fixed(_ value: Double, to bytes: inout [UInt8]) {
        append32(UInt32(bitPattern: Int32((value * 65536).rounded())), to: &bytes)
    }

    private static func xyz(_ value: XYZ) -> [UInt8] {
        var bytes: [UInt8] = []
        signature("XYZ ", to: &bytes)
        append32(0, to: &bytes)
        fixed(value.x, to: &bytes)
        fixed(value.y, to: &bytes)
        fixed(value.z, to: &bytes)
        return bytes
    }

    private static func parametric(_ curve: Curve) -> [UInt8] {
        var bytes: [UInt8] = []
        signature("para", to: &bytes)
        append32(0, to: &bytes)
        append16(curve.isPower ? 0 : 3, to: &bytes)
        append16(0, to: &bytes)
        fixed(curve.g, to: &bytes)
        if !curve.isPower { for value in [curve.a, curve.b, curve.c, curve.d] { fixed(value, to: &bytes) } }
        return bytes
    }

    /// multiLocalizedUnicodeType with one English record.
    private static func text(_ value: String) -> [UInt8] {
        var bytes: [UInt8] = []
        signature("mluc", to: &bytes)
        append32(0, to: &bytes)
        append32(1, to: &bytes)
        append32(12, to: &bytes)
        signature("enUS", to: &bytes)
        let units = Array(value.utf16)
        append32(UInt32(units.count * 2), to: &bytes)
        append32(28, to: &bytes)
        for unit in units { append16(unit, to: &bytes) }
        return bytes
    }

    /// A display profile: the 128-byte header, the tag table, and the tags,
    /// each on a 4-byte boundary.
    private static func build(space: String, tags: [(String, [UInt8])]) -> [UInt8] {
        let start = 128 + 4 + 12 * tags.count
        var body: [UInt8] = []
        var table: [UInt8] = []
        append32(UInt32(tags.count), to: &table)
        for (name, data) in tags {
            signature(name, to: &table)
            append32(UInt32(start + body.count), to: &table)
            append32(UInt32(data.count), to: &table)
            body += data
            while body.count % 4 != 0 { body.append(0) }
        }
        var header: [UInt8] = []
        append32(UInt32(start + body.count), to: &header)
        append32(0, to: &header)                  // preferred CMM
        append32(0x0430_0000, to: &header)        // version 4.3
        signature("mntr", to: &header)
        signature(space, to: &header)
        signature("XYZ ", to: &header)
        for value: UInt16 in [2026, 1, 1, 0, 0, 0] { append16(value, to: &header) }
        signature("acsp", to: &header)
        header += [UInt8](repeating: 0, count: 4 + 4 + 4 + 4 + 8)  // platform, flags, manufacturer, model, attributes
        append32(0, to: &header)                  // perceptual intent
        fixed(d50.x, to: &header)
        fixed(d50.y, to: &header)
        fixed(d50.z, to: &header)
        header += [UInt8](repeating: 0, count: 4 + 16 + 28)  // creator, profile ID, reserved
        return header + table + body
    }

    /// The model a profile describes, from its header's data color space,
    /// or nil if the data isn't an ICC profile.
    static func model(of data: [UInt8]) -> Int32? {
        guard data.count >= 132, Array(data[36..<40]) == Array("acsp".utf8) else { return nil }
        switch String(decoding: data[16..<20], as: UTF8.self) {
        case "GRAY": return 0
        case "RGB ": return 1
        case "CMYK": return 2
        case "Lab ": return 3
        default: return nil
        }
    }
}

/// Bytes from a CFData or a CGDataProvider.
private func bytes(of object: Ref?) -> [UInt8]? {
    guard let object else { return nil }
    if let bytes = DataProviders.bytes(object) { return bytes }
    let wrapped = NSObject(objCArgument: object)
    guard wrapped.isKind(of: ObjCClass(named: "NSData")) else { return nil }
    return wrapped.unsafeCast(to: NSData.self).array
}

@c(_CGColorSpaceCreateWithICCData)
public func CGColorSpaceCreateWithICCData(_ data: Ref?) -> Ref? {
    guard let profile = bytes(of: data), let model = ICCProfiles.model(of: profile) else { return nil }
    return ColorSpaces.make(ColorSpaceState(model: model, name: nil, iccData: profile))
}

/// The profile's space, or a retained alternate when the profile can't be
/// read; the component count must match the profile's.
@c(_CGColorSpaceCreateICCBased)
public func CGColorSpaceCreateICCBased(_ components: Int, _ range: UnsafePointer<CGFloat>?, _ profile: Ref?, _ alternate: Ref?) -> Ref? {
    if let space = CGColorSpaceCreateWithICCData(profile) {
        if ColorSpaces.state(space)?.components == components { return space }
        ObjCRuntime.release(space)
    }
    return alternate.flatMap { ObjCRuntime.retain($0) }
}

@c(_CGColorSpaceCopyICCData)
public func CGColorSpaceCopyICCData(_ space: Ref?) -> Ref? {
    guard let state = ColorSpaces.state(space), let profile = ICCProfiles.profile(for: state) else { return nil }
    return NSData.of(profile).objCOwnedReturnValue()
}

/// An indexed space: lastIndex + 1 colors, each the base's components as
/// bytes. At most 256 colors, of a base that isn't itself indexed or a
/// pattern.
@c(_CGColorSpaceCreateIndexed)
public func CGColorSpaceCreateIndexed(_ base: Ref?, _ lastIndex: Int, _ table: UnsafePointer<UInt8>?) -> Ref? {
    guard let base, let baseState = ColorSpaces.state(base), baseState.model != 5, baseState.model != 6,
          lastIndex >= 0, lastIndex <= 255, let table else { return nil }
    let entries = Array(UnsafeBufferPointer(start: table, count: (lastIndex + 1) * baseState.components))
    return ColorSpaces.make(ColorSpaceState(model: 5, name: nil, base: base, table: entries))
}

/// A pattern space, colored (no base) or uncolored (a base).
@c(_CGColorSpaceCreatePattern)
public func CGColorSpaceCreatePattern(_ base: Ref?) -> Ref? {
    ColorSpaces.make(ColorSpaceState(model: 6, name: nil, base: base))
}

@c(_CGColorSpaceGetBaseColorSpace)
public func CGColorSpaceGetBaseColorSpace(_ space: Ref?) -> Ref? { ColorSpaces.state(space)?.base }

@c(_CGColorSpaceCopyBaseColorSpace)
public func CGColorSpaceCopyBaseColorSpace(_ space: Ref?) -> Ref? { ObjCRuntime.retain(ColorSpaces.state(space)?.base) }

@c(_CGColorSpaceGetColorTableCount)
public func CGColorSpaceGetColorTableCount(_ space: Ref?) -> Int {
    guard let state = ColorSpaces.state(space), state.model == 5,
          let base = ColorSpaces.state(state.base), base.components > 0 else { return 0 }
    return state.table.count / base.components
}

@c(_CGColorSpaceGetColorTable)
public func CGColorSpaceGetColorTable(_ space: Ref?, _ table: UnsafeMutablePointer<UInt8>?) {
    guard let state = ColorSpaces.state(space), state.model == 5, let table else { return }
    table.update(from: state.table, count: state.table.count)
}

// MARK: Property lists

/// Keys of an indexed space's property list, as CoreGraphics names them.
private let baseKey = "kCGIndexedBaseColorSpaceKey", tableKey = "kCGIndexedColorTableKey", lastIndexKey = "kCGLastIndexKey"

/// A space as a property list (+1): its ICC profile as data if it was made
/// from one; a named space's name; a device space's name for it; an indexed
/// space as a dictionary of its base's property list, its table and its last
/// index. Nil for a pattern space, as CoreGraphics gives for special spaces.
@c(_CGColorSpaceCopyPropertyList)
public func CGColorSpaceCopyPropertyList(_ space: Ref?) -> Ref? {
    guard let state = ColorSpaces.state(space) else { return nil }
    if let profile = state.iccData { return NSData.of(profile).objCOwnedReturnValue() }
    if let name = state.name { return name.objCOwnedReturnValue() }
    switch state.model {
    case 0: return "kCGColorSpaceDeviceGray".objCOwnedReturnValue()
    case 1: return "kCGColorSpaceDeviceRGB".objCOwnedReturnValue()
    case 2: return "kCGColorSpaceDeviceCMYK".objCOwnedReturnValue()
    case 5:
        guard let base = state.base, let basePropertyList = CGColorSpaceCopyPropertyList(base) else { return nil }
        let entries: [(String, NSObject)] = [(baseKey, NSObject(objCOwned: basePropertyList)), (tableKey, NSData.of(state.table)),
                                             (lastIndexKey, NSObject.number(CGColorSpaceGetColorTableCount(space) - 1))]
        return NSMutableDictionary.of(entries).objCOwnedReturnValue()
    default:
        return nil
    }
}

/// The space a property list from CGColorSpaceCopyPropertyList describes;
/// ICC data and the names CGColorSpaceCreateWithName takes also work.
@c(_CGColorSpaceCreateWithPropertyList)
public func CGColorSpaceCreateWithPropertyList(_ propertyList: Ref?) -> Ref? {
    guard let propertyList else { return nil }
    let object = NSObject(objCArgument: propertyList)
    if object.isKind(of: ObjCClass(named: "NSString")) {
        switch String(objCArgument: propertyList) {
        case "kCGColorSpaceDeviceGray": return CGColorSpaceCreateDeviceGray()
        case "kCGColorSpaceDeviceRGB": return CGColorSpaceCreateDeviceRGB()
        case "kCGColorSpaceDeviceCMYK": return CGColorSpaceCreateDeviceCMYK()
        default: return CGColorSpaceCreateWithName(propertyList)
        }
    }
    if object.isKind(of: ObjCClass(named: "NSData")) { return CGColorSpaceCreateWithICCData(propertyList) }
    guard let dictionary = object.dictionary, let base = dictionary.object(baseKey).flatMap({ CGColorSpaceCreateWithPropertyList($0.objcObject) })
    else { return nil }
    defer { ObjCRuntime.release(base) }
    guard let tableObject = dictionary.object(tableKey), tableObject.isKind(of: ObjCClass(named: "NSData")),
          let lastIndex = dictionary.object(lastIndexKey)?.doubleValue else { return nil }
    let table = tableObject.unsafeCast(to: NSData.self).array
    let needed = (Int(lastIndex) + 1) * (ColorSpaces.state(base)?.components ?? 0)
    guard needed > 0, table.count >= needed else { return nil }
    return table.withUnsafeBufferPointer { CGColorSpaceCreateIndexed(base, Int(lastIndex), $0.baseAddress) }
}

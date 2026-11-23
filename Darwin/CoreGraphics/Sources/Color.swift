import Foundation

@available(macOS 10.9, iOS 7.0, tvOS 9.0, watchOS 2.0, visionOS 1.0, *)
extension CGColor {
    public var components: [CGFloat]? {
        guard let components = __unsafeComponents else { return nil }
        return Array(UnsafeBufferPointer(start: components, count: numberOfComponents))
    }

    public class var white: CGColor { CGColor.__constantColor(for: CGColor.__whiteColorName)! }
    public class var black: CGColor { CGColor.__constantColor(for: CGColor.__blackColorName)! }
    public class var clear: CGColor { CGColor.__constantColor(for: CGColor.__clearColorName)! }
}

/// How a color literal makes a CGColor: CGColor's initializer is the
/// generic RGB one, which a protocol lets the literal's reach.
@available(macOS 10.9, iOS 7.0, tvOS 9.0, watchOS 2.0, visionOS 1.0, *)
public protocol _CGColorInitTrampoline {
    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)
}

@available(macOS 10.9, iOS 7.0, tvOS 9.0, watchOS 2.0, visionOS 1.0, *)
extension _CGColorInitTrampoline {
    public init(_colorLiteralRed red: Float, green: Float, blue: Float, alpha: Float) {
        self.init(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }
}

@available(macOS 10.9, iOS 7.0, tvOS 9.0, watchOS 2.0, visionOS 1.0, *)
extension CGColor: _CGColorInitTrampoline, _ExpressibleByColorLiteral {}

@available(macOS 10.9, iOS 7.0, tvOS 9.0, watchOS 2.0, visionOS 1.0, *)
extension CGColor: @unchecked Sendable {}

// Coding. A color codes as its color space and its components; a color
// space as its name, or its ICC profile when it has no name. The property
// list forms below hold the same.

private enum ColorKey: String, CodingKey {
    case colorSpace, components
}

private enum ColorSpaceKey: String, CodingKey {
    case name, iccData
}

/// The color space's property-list form: its name, or else its ICC data.
private func propertyList(of space: CGColorSpace) -> CFPropertyList? {
    if let name = space.name { return name }
    return space.copyICCData()
}

/// The color space of a property-list form made by `propertyList(of:)`.
private func colorSpace(from plist: CFPropertyList) -> CGColorSpace? {
    if CFGetTypeID(plist) == CFStringGetTypeID() {
        return CGColorSpace(name: plist as! CFString)
    }
    if CFGetTypeID(plist) == CFDataGetTypeID() {
        return CGColorSpace(iccData: plist)
    }
    // A property list made by CoreGraphics itself.
    return CGColorSpace(propertyListPlist: plist)
}

@available(macOS 27.0, iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
@_marker public protocol _CGColorCoding {}

@available(macOS 27.0, iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
extension _CGColorCoding where Self: CGColor {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ColorKey.self)
        let space = try container.decode(CGColorSpace.self, forKey: .colorSpace)
        let components = try container.decode([CGFloat].self, forKey: .components)
        guard components.count == space.numberOfComponents + 1,
              let color = components.withUnsafeBufferPointer({ CGColor(colorSpace: space, components: $0.baseAddress!) }) else {
            throw DecodingError.dataCorruptedError(forKey: .components, in: container,
                                                   debugDescription: "The components do not fit the color space")
        }
        self = unsafeDowncast(color, to: Self.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ColorKey.self)
        guard let space = colorSpace, let components else {
            throw EncodingError.invalidValue(self, .init(codingPath: encoder.codingPath,
                                                         debugDescription: "A pattern color can't be encoded"))
        }
        try container.encode(space, forKey: .colorSpace)
        try container.encode(components, forKey: .components)
    }
}

@available(macOS 27.0, iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
extension CGColor: Codable, _CGColorCoding {}

@available(macOS 27.0, iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
@usableFromInline
@_cdecl("CGColorCreateWithPropertyList")
internal func CGColorCreateWithPropertyList(plist: CFPropertyList?) -> Unmanaged<CGColor>? {
    guard let plist, CFGetTypeID(plist) == CFDictionaryGetTypeID(),
          let dictionary = plist as? [String: Any],
          let spacePlist = dictionary[ColorKey.colorSpace.rawValue],
          let space = colorSpace(from: spacePlist as CFPropertyList),
          let numbers = dictionary[ColorKey.components.rawValue] as? [NSNumber],
          numbers.count == space.numberOfComponents + 1 else { return nil }
    let components = numbers.map { CGFloat($0.doubleValue) }
    guard let color = components.withUnsafeBufferPointer({ CGColor(colorSpace: space, components: $0.baseAddress!) }) else { return nil }
    return .passRetained(color)
}

@available(macOS 27.0, iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
@usableFromInline
@_cdecl("CGColorCopyPropertyList")
internal func CGColorCopyPropertyList(color: CGColor?) -> Unmanaged<CFPropertyList>? {
    guard let color, let space = color.colorSpace, let spacePlist = propertyList(of: space),
          let components = color.components else { return nil }
    let dictionary: NSDictionary = [
        ColorKey.colorSpace.rawValue: spacePlist,
        ColorKey.components.rawValue: components.map { NSNumber(value: Double($0)) },
    ]
    return .passRetained(dictionary)
}

extension CGColorSpace {
    public var colorTable: [UInt8]? {
        let count = __colorTableCount
        guard count > 0 else { return nil }
        // Each entry holds a value for each component of the base space.
        let width = baseColorSpace?.numberOfComponents ?? 1
        var table = [UInt8](repeating: 0, count: count * width)
        __unsafeGetColorTable(&table)
        return table
    }
}

extension CGColorSpace: @unchecked Sendable {}

@available(macOS 27.0, iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
@_marker public protocol _CGColorSpaceCoding {}

@available(macOS 27.0, iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
extension _CGColorSpaceCoding where Self: CGColorSpace {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ColorSpaceKey.self)
        var space: CGColorSpace?
        if let name = try container.decodeIfPresent(String.self, forKey: .name) {
            space = CGColorSpace(name: name as CFString)
        } else if let data = try container.decodeIfPresent(Data.self, forKey: .iccData) {
            space = CGColorSpace(iccData: data as CFData)
        }
        guard let space else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "No color space by that name or profile"))
        }
        self = unsafeDowncast(space, to: Self.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ColorSpaceKey.self)
        if let name {
            try container.encode(name as String, forKey: .name)
        } else if let data = copyICCData() {
            try container.encode(data as Data, forKey: .iccData)
        } else {
            throw EncodingError.invalidValue(self, .init(codingPath: encoder.codingPath,
                                                         debugDescription: "The color space has neither a name nor a profile"))
        }
    }
}

@available(macOS 27.0, iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
extension CGColorSpace: Codable, _CGColorSpaceCoding {}

// The color space ones are C functions the header declares, which
// CoreGraphics itself provides; these are the overlay's Swift entry points
// to them.

@available(macOS 27.0, iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
@usableFromInline
internal func CGColorSpaceCreateWithPropertyList(plist: CFPropertyList?) -> Unmanaged<CGColorSpace>? {
    guard let plist, let space = colorSpace(from: plist) else { return nil }
    return .passRetained(space)
}

@available(macOS 27.0, iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
@usableFromInline
internal func CGColorSpaceCopyPropertyList(space: CGColorSpace?) -> Unmanaged<CFPropertyList>? {
    guard let space else { return nil }
    if let plist = space.copyPropertyList() { return .passRetained(plist) }
    return propertyList(of: space).map { .passRetained($0) }
}

// The C forms of before.

@available(*, unavailable, message: "Use class var white/black/clear instead")
public func CGColorGetConstantColor(_ colorName: CFString?) -> CGColor? {
    colorName.flatMap { CGColor.__constantColor(for: $0) }
}

@available(*, unavailable, message: "Use == instead")
public func CGColorEqualToColor(_ color1: CGColor?, _ color2: CGColor?) -> Bool {
    guard let color1, let color2 else { return color1 == nil && color2 == nil }
    return color1.__equalTo(color2)
}

@available(*, unavailable, renamed: "getter:CGColor.components(self:)")
public func CGColorGetComponents(_ color: CGColor?) -> UnsafePointer<CGFloat> {
    color!.__unsafeComponents!
}

@available(*, unavailable, message: "Use colorTable.count instead")
public func CGColorSpaceGetColorTableCount(_ space: CGColorSpace?) -> Int {
    space?.__colorTableCount ?? 0
}

@available(*, unavailable, renamed: "CGColorSpace.colorTable(self:_:)")
public func CGColorSpaceGetColorTable(_ space: CGColorSpace?, _ table: UnsafeMutablePointer<UInt8>) {
    space?.__unsafeGetColorTable(table)
}

@available(*, unavailable, message: "Use CGColor.white")
public var kCGColorWhite: CFString { CGColor.__whiteColorName }

@available(*, unavailable, message: "Use CGColor.black")
public var kCGColorBlack: CFString { CGColor.__blackColorName }

@available(*, unavailable, message: "Use CGColor.clear")
public var kCGColorClear: CFString { CGColor.__clearColorName }

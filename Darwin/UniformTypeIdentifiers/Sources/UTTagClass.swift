import Foundation

/// A class of tags a type has: filename extensions or MIME types.
@available(macOS 11.0, macCatalyst 14.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
public struct UTTagClass: RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

@available(macOS 11.0, macCatalyst 14.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
extension UTTagClass {
    public static var filenameExtension: UTTagClass { UTTagClass(rawValue: "public.filename-extension") }
    public static var mimeType: UTTagClass { UTTagClass(rawValue: "public.mime-type") }
}

@available(macOS 11.0, macCatalyst 14.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
extension UTTagClass: Equatable, Hashable {
    public static func == (lhs: UTTagClass, rhs: UTTagClass) -> Bool { lhs.rawValue == rhs.rawValue }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}

@available(macOS 11.0, macCatalyst 14.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
extension UTTagClass: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { rawValue }
    public var debugDescription: String { rawValue }
}

@available(macOS 11.0, macCatalyst 14.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
extension UTTagClass: Codable {
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }
}

import Foundation
import UniformTypeIdentifiers
import _CoreTextPrivate

/// An image that sits in text as a glyph, scaling with the font: its image
/// data, with the identifier and description its metadata gives.
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
extension AttributedString {
    public struct AdaptiveImageGlyph: Codable, Hashable, Equatable, Sendable {
        public let imageContent: Data
        public let contentIdentifier: String
        public let contentDescription: String

        /// The identifier and description, which the image's metadata
        /// holds, are not read.
        public init(imageContent: Data) {
            self.imageContent = imageContent
            contentIdentifier = ""
            contentDescription = ""
        }

        /// Adaptive image glyphs are HEIC images.
        public static var contentType: UTType { .heic }

        public static func == (a: AdaptiveImageGlyph, b: AdaptiveImageGlyph) -> Bool {
            a.imageContent == b.imageContent
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(contentIdentifier)
        }

        private enum CodingKeys: String, CodingKey { case imageContent }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(imageContent, forKey: .imageContent)
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(imageContent: try container.decode(Data.self, forKey: .imageContent))
        }
    }
}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
extension CTAdaptiveImageGlyph {
    /// The CoreText glyph for an attributed string's, which SwiftUI draws.
    public static func _adaptiveImageGlyph(convertingFrom adaptiveImageGlyph: AttributedString.AdaptiveImageGlyph) -> CTAdaptiveImageGlyph {
        CTAdaptiveImageGlyph(imageContent: adaptiveImageGlyph.imageContent)
    }
}

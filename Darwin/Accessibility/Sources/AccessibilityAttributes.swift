// Accessibility's attribute scope for attributed strings: headings, text
// context and speech, by UIKit's attribute names. SwiftUI's scope holds it,
// so its type is needed wherever SwiftUI's attributes are; Markdown sets
// them with ^[…](accessibilityHeadingLevel: 2) and the like.

import Foundation

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension AttributeScopes {
    public var accessibility: AccessibilityAttributes.Type { AccessibilityAttributes.self }

    public struct AccessibilityAttributes: AttributeScope {
        public let accessibilityHeadingLevel: HeadingLevelAttribute
        public let accessibilityTextCustom: TextCustomAttribute
        public let accessibilityTextualContext: TextualContextAttribute
        public let accessibilitySpeechIncludesPunctuation: IncludesPunctuationAttribute
        public let accessibilitySpeechAdjustedPitch: AdjustedPitchAttribute
        public let accessibilitySpeechSpellsOutCharacters: SpellOutAttribute
        public let accessibilitySpeechAnnouncementsQueued: QueueAnnouncementAttribute
        public let accessibilitySpeechPhoneticNotation: IPANotationAttribute
        public let accessibilitySpeechAnnouncementPriority: AnnouncementPriorityAttribute
        @available(macOS 27, iOS 27, tvOS 27, watchOS 27, visionOS 27, *)
        public var accessibilitySpeechSSML: SpeechSSMLAttribute { fatalError("attribute keys have no values") }

        public typealias DecodingConfiguration = AttributeScopeCodableConfiguration
        public typealias EncodingConfiguration = AttributeScopeCodableConfiguration
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension AttributeDynamicLookup {
    public subscript<T: AttributedStringKey>(dynamicMember keyPath: KeyPath<AttributeScopes.AccessibilityAttributes, T>) -> T {
        self[T.self]
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension AttributeScopes.AccessibilityAttributes {
    @frozen public enum HeadingLevelAttribute: CodableAttributedStringKey, MarkdownDecodableAttributedStringKey,
        ObjectiveCConvertibleAttributedStringKey {
        public typealias Value = HeadingLevel
        public typealias ObjectiveCValue = NSNumber
        public static var name: String { "UIAccessibilityTextAttributeHeadingLevel" }
        public static let markdownName = "accessibilityHeadingLevel"

        public enum HeadingLevel: Int, Codable, Sendable {
            case unspecified, h1, h2, h3, h4, h5, h6
        }

        public static func decodeMarkdown(from decoder: any Decoder) throws -> HeadingLevel {
            let level = try decoder.singleValueContainer().decode(Int.self)
            guard let value = HeadingLevel(rawValue: level) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "No heading level \(level)"))
            }
            return value
        }

        public static func objectiveCValue(for value: HeadingLevel) throws -> NSNumber { NSNumber(value: value.rawValue) }

        public static func value(for object: NSNumber) throws -> HeadingLevel {
            guard let value = HeadingLevel(rawValue: object.intValue) else { throw CocoaError(.coderInvalidValue) }
            return value
        }
    }

    @frozen public enum TextCustomAttribute: CodableAttributedStringKey, MarkdownDecodableAttributedStringKey {
        public typealias Value = [String]
        public static var name: String { "UIAccessibilityTextAttributeCustom" }
        public static let markdownName = "accessibilityTextCustom"
    }

    @frozen public enum TextualContextAttribute: CodableAttributedStringKey, MarkdownDecodableAttributedStringKey,
        ObjectiveCConvertibleAttributedStringKey {
        public typealias Value = TextualContext
        public typealias ObjectiveCValue = NSString
        public static var name: String { "UIAccessibilityTextAttributeContext" }
        public static let markdownName = "accessibilityTextualContext"

        public enum TextualContext: String, Codable, Sendable {
            case plain, console, fileSystem, messaging, narrative, sourceCode, spreadsheet, wordProcessing
        }

        public static func decodeMarkdown(from decoder: any Decoder) throws -> TextualContext {
            try decoder.singleValueContainer().decode(TextualContext.self)
        }

        /// UIAccessibilityTextualContext's values: "UIAccessibilityTextualContextSourceCode".
        public static func objectiveCValue(for value: TextualContext) throws -> NSString {
            ("UIAccessibilityTextualContext" + value.rawValue.prefix(1).uppercased() + value.rawValue.dropFirst()) as NSString
        }

        public static func value(for object: NSString) throws -> TextualContext {
            let string = object as String
            guard string.hasPrefix("UIAccessibilityTextualContext") else { throw CocoaError(.coderInvalidValue) }
            let name = string.dropFirst("UIAccessibilityTextualContext".count)
            guard let value = TextualContext(rawValue: name.prefix(1).lowercased() + name.dropFirst()) else {
                throw CocoaError(.coderInvalidValue)
            }
            return value
        }
    }

    @frozen public enum IncludesPunctuationAttribute: CodableAttributedStringKey, MarkdownDecodableAttributedStringKey {
        public typealias Value = Bool
        public static var name: String { "UIAccessibilitySpeechAttributePunctuation" }
        public static let markdownName = "accessibilitySpeechIncludesPunctuation"
    }

    /// The pitch to speak at, from 0 to 2; UIKit's attribute counts from 1.
    @frozen public enum AdjustedPitchAttribute: CodableAttributedStringKey, MarkdownDecodableAttributedStringKey,
        ObjectiveCConvertibleAttributedStringKey {
        public typealias Value = Double
        public typealias ObjectiveCValue = NSNumber
        public static var name: String { "UIAccessibilitySpeechAttributePitch" }
        public static let markdownName = "accessibilitySpeechAdjustedPitch"

        public static func objectiveCValue(for value: Double) throws -> NSNumber { NSNumber(value: value + 1) }
        public static func value(for object: NSNumber) throws -> Double { object.doubleValue - 1 }
    }

    @frozen public enum SpellOutAttribute: CodableAttributedStringKey, MarkdownDecodableAttributedStringKey {
        public typealias Value = Bool
        public static var name: String { "UIAccessibilitySpeechAttributeSpellOut" }
        public static let markdownName = "accessibilitySpeechSpellsOutCharacters"
    }

    @frozen public enum QueueAnnouncementAttribute: CodableAttributedStringKey, MarkdownDecodableAttributedStringKey {
        public typealias Value = Bool
        public static var name: String { "UIAccessibilitySpeechAttributeQueueAnnouncement" }
        public static let markdownName = "accessibilitySpeechAnnouncementsQueued"
    }

    @frozen public enum IPANotationAttribute: CodableAttributedStringKey, MarkdownDecodableAttributedStringKey {
        public typealias Value = String
        public static var name: String { "UIAccessibilitySpeechAttributeIPANotation" }
        public static let markdownName = "accessibilitySpeechPhoneticNotation"
    }

    @frozen public enum AnnouncementPriorityAttribute: CodableAttributedStringKey, MarkdownDecodableAttributedStringKey,
        ObjectiveCConvertibleAttributedStringKey {
        public typealias Value = AnnouncementPriority
        public typealias ObjectiveCValue = NSString
        public static var name: String { "UIAccessibilitySpeechAttributeAnnouncementPriority" }
        public static let markdownName = "accessibilitySpeechAnnouncementPriority"

        public enum AnnouncementPriority: String, Codable, Sendable {
            case low
            case `default`
            case high
        }

        /// UIAccessibilityPriority's values: "UIAccessibilityPriorityHigh".
        public static func objectiveCValue(for value: AnnouncementPriority) throws -> NSString {
            ("UIAccessibilityPriority" + value.rawValue.prefix(1).uppercased() + value.rawValue.dropFirst()) as NSString
        }

        public static func value(for object: NSString) throws -> AnnouncementPriority {
            let string = object as String
            guard string.hasPrefix("UIAccessibilityPriority"),
                  let value = AnnouncementPriority(rawValue: string.dropFirst("UIAccessibilityPriority".count).lowercased()) else {
                throw CocoaError(.coderInvalidValue)
            }
            return value
        }
    }

    @available(macOS 27, iOS 27, tvOS 27, watchOS 27, visionOS 27, *)
    @frozen public enum SpeechSSMLAttribute: CodableAttributedStringKey, MarkdownDecodableAttributedStringKey {
        public typealias Value = String
        public static var name: String { "AXSpeechAttributeSSML" }
        public static let markdownName = "accessibilitySpeechSSML"
    }
}

// Accessibility's settings that SwiftUI reads, as a device without
// assistive features has them. They are Swift and C names of Apple's
// Objective-C declarations, given here by symbol.

/// AccessibilitySettings.animatedImagesEnabled: animated images play.
@_silgen_name("$sSo21AccessibilitySettingsV0A0E21animatedImagesEnabledSbvgZ")
public func _accessibilitySettingsAnimatedImagesEnabled() -> Bool { true }

/// AXAssistiveAccessEnabled(): Assistive Access is off.
@_cdecl("AXAssistiveAccessEnabled")
public func AXAssistiveAccessEnabled() -> Bool { false }

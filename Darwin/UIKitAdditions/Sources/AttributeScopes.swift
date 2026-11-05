// UIKit's attribute scope: the attributes an AttributedString styles text
// with for UIKit, under their NSAttributedString keys. Declarations are
// the SDK interface's, for its ABI.

public import Foundation

@available(iOS 15.0, tvOS 15.0, *)
@available(watchOS, unavailable)
extension Foundation.AttributeScopes {
  public var uiKit: Foundation.AttributeScopes.UIKitAttributes.Type {
    get { Foundation.AttributeScopes.UIKitAttributes.self }
  }
  public struct UIKitAttributes : Foundation.AttributeScope {
    public let font: Foundation.AttributeScopes.UIKitAttributes.FontAttribute
    public let paragraphStyle: Foundation.AttributeScopes.UIKitAttributes.ParagraphStyleAttribute
    public let foregroundColor: Foundation.AttributeScopes.UIKitAttributes.ForegroundColorAttribute
    public let backgroundColor: Foundation.AttributeScopes.UIKitAttributes.BackgroundColorAttribute
    public let ligature: Foundation.AttributeScopes.UIKitAttributes.LigatureAttribute
    public let kern: Foundation.AttributeScopes.UIKitAttributes.KernAttribute
    public let tracking: Foundation.AttributeScopes.UIKitAttributes.TrackingAttribute
    public let strikethroughStyle: Foundation.AttributeScopes.UIKitAttributes.StrikethroughStyleAttribute
    public let underlineStyle: Foundation.AttributeScopes.UIKitAttributes.UnderlineStyleAttribute
    public let strokeColor: Foundation.AttributeScopes.UIKitAttributes.StrokeColorAttribute
    public let strokeWidth: Foundation.AttributeScopes.UIKitAttributes.StrokeWidthAttribute
    public let shadow: Foundation.AttributeScopes.UIKitAttributes.ShadowAttribute
    public let attachment: Foundation.AttributeScopes.UIKitAttributes.AttachmentAttribute
    public let baselineOffset: Foundation.AttributeScopes.UIKitAttributes.BaselineOffsetAttribute
    public let underlineColor: Foundation.AttributeScopes.UIKitAttributes.UnderlineColorAttribute
    public let strikethroughColor: Foundation.AttributeScopes.UIKitAttributes.StrikethroughColorAttribute
    public let obliqueness: Foundation.AttributeScopes.UIKitAttributes.ObliquenessAttribute
    public let expansion: Foundation.AttributeScopes.UIKitAttributes.ExpansionAttribute
    public let textItemTag: Foundation.AttributeScopes.UIKitAttributes.TextItemTagAttribute
    public let foundation: Foundation.AttributeScopes.FoundationAttributes
    public typealias DecodingConfiguration = Foundation.AttributeScopeCodableConfiguration
    public typealias EncodingConfiguration = Foundation.AttributeScopeCodableConfiguration
  }
}

@available(iOS 6.0, *)
extension NSUnderlineStyle : Swift.Hashable {}

/// Values that aren't Codable can't be archived in an AttributedString's
/// encoding here; Apple's archive them with NSCoding.
struct _UIKitAttributeNotCodable : Swift.Error {}

@available(iOS 15.0, tvOS 15.0, *)
@available(watchOS, unavailable)
extension Foundation.AttributeScopes.UIKitAttributes {
  @frozen public enum FontAttribute : Foundation.CodableAttributedStringKey {
    public typealias Value = UIFont
    public static let name: Swift.String = "NSFont"
    public static func encode(_ value: Value, to encoder: any Swift.Encoder) throws { throw _UIKitAttributeNotCodable() }
    public static func decode(from decoder: any Swift.Decoder) throws -> Value { throw _UIKitAttributeNotCodable() }
  }
  @frozen public enum ParagraphStyleAttribute : Foundation.CodableAttributedStringKey {
    public typealias Value = NSParagraphStyle
    public static let name: Swift.String = "NSParagraphStyle"
    public static func encode(_ value: Value, to encoder: any Swift.Encoder) throws { throw _UIKitAttributeNotCodable() }
    public static func decode(from decoder: any Swift.Decoder) throws -> Value { throw _UIKitAttributeNotCodable() }
  }
  @frozen public enum ForegroundColorAttribute : Foundation.CodableAttributedStringKey {
    public typealias Value = UIColor
    public static let name: Swift.String = "NSColor"
    public static func encode(_ value: Value, to encoder: any Swift.Encoder) throws { throw _UIKitAttributeNotCodable() }
    public static func decode(from decoder: any Swift.Decoder) throws -> Value { throw _UIKitAttributeNotCodable() }
  }
  @frozen public enum BackgroundColorAttribute : Foundation.CodableAttributedStringKey {
    public typealias Value = UIColor
    public static let name: Swift.String = "NSBackgroundColor"
    public static func encode(_ value: Value, to encoder: any Swift.Encoder) throws { throw _UIKitAttributeNotCodable() }
    public static func decode(from decoder: any Swift.Decoder) throws -> Value { throw _UIKitAttributeNotCodable() }
  }
  @frozen public enum LigatureAttribute : Foundation.CodableAttributedStringKey {
    public typealias Value = Swift.Int
    public static let name: Swift.String = "NSLigature"
  }
  @frozen public enum KernAttribute : Foundation.CodableAttributedStringKey {
    public typealias Value = CoreFoundation.CGFloat
    public static let name: Swift.String = "NSKern"
  }
  @frozen public enum TrackingAttribute : Foundation.CodableAttributedStringKey {
    public typealias Value = CoreFoundation.CGFloat
    public static let name: Swift.String = "NSTracking"
  }
  @frozen public enum StrikethroughStyleAttribute : Foundation.CodableAttributedStringKey, Foundation.ObjectiveCConvertibleAttributedStringKey {
    public typealias Value = NSUnderlineStyle
    public static let name: Swift.String = "NSStrikethrough"
    public typealias ObjectiveCValue = NSNumber
    public static func encode(_ value: Value, to encoder: any Swift.Encoder) throws {
      var container = encoder.singleValueContainer()
      try container.encode(value.rawValue)
    }
    public static func decode(from decoder: any Swift.Decoder) throws -> Value {
      Value(rawValue: try decoder.singleValueContainer().decode(Int.self))
    }
    public static func objectiveCValue(for value: Value) throws -> NSNumber { NSNumber(value: value.rawValue) }
    public static func value(for object: NSNumber) throws -> Value { Value(rawValue: object.intValue) }
  }
  @frozen public enum UnderlineStyleAttribute : Foundation.CodableAttributedStringKey, Foundation.ObjectiveCConvertibleAttributedStringKey {
    public typealias Value = NSUnderlineStyle
    public static let name: Swift.String = "NSUnderline"
    public typealias ObjectiveCValue = NSNumber
    public static func encode(_ value: Value, to encoder: any Swift.Encoder) throws {
      var container = encoder.singleValueContainer()
      try container.encode(value.rawValue)
    }
    public static func decode(from decoder: any Swift.Decoder) throws -> Value {
      Value(rawValue: try decoder.singleValueContainer().decode(Int.self))
    }
    public static func objectiveCValue(for value: Value) throws -> NSNumber { NSNumber(value: value.rawValue) }
    public static func value(for object: NSNumber) throws -> Value { Value(rawValue: object.intValue) }
  }
  @frozen public enum StrokeColorAttribute : Foundation.CodableAttributedStringKey {
    public typealias Value = UIColor
    public static let name: Swift.String = "NSStrokeColor"
    public static func encode(_ value: Value, to encoder: any Swift.Encoder) throws { throw _UIKitAttributeNotCodable() }
    public static func decode(from decoder: any Swift.Decoder) throws -> Value { throw _UIKitAttributeNotCodable() }
  }
  @frozen public enum StrokeWidthAttribute : Foundation.CodableAttributedStringKey {
    public typealias Value = CoreFoundation.CGFloat
    public static let name: Swift.String = "NSStrokeWidth"
  }
  @frozen public enum ShadowAttribute : Foundation.CodableAttributedStringKey {
    public typealias Value = NSShadow
    public static let name: Swift.String = "NSShadow"
    public static func encode(_ value: Value, to encoder: any Swift.Encoder) throws { throw _UIKitAttributeNotCodable() }
    public static func decode(from decoder: any Swift.Decoder) throws -> Value { throw _UIKitAttributeNotCodable() }
  }
  @frozen public enum AttachmentAttribute : Foundation.CodableAttributedStringKey {
    public typealias Value = NSTextAttachment
    public static let name: Swift.String = "NSAttachment"
    public static func encode(_ value: Value, to encoder: any Swift.Encoder) throws { throw _UIKitAttributeNotCodable() }
    public static func decode(from decoder: any Swift.Decoder) throws -> Value { throw _UIKitAttributeNotCodable() }
  }
  @frozen public enum BaselineOffsetAttribute : Foundation.CodableAttributedStringKey {
    public typealias Value = CoreFoundation.CGFloat
    public static let name: Swift.String = "NSBaselineOffset"
  }
  @frozen public enum UnderlineColorAttribute : Foundation.CodableAttributedStringKey {
    public typealias Value = UIColor
    public static let name: Swift.String = "NSUnderlineColor"
    public static func encode(_ value: Value, to encoder: any Swift.Encoder) throws { throw _UIKitAttributeNotCodable() }
    public static func decode(from decoder: any Swift.Decoder) throws -> Value { throw _UIKitAttributeNotCodable() }
  }
  @frozen public enum StrikethroughColorAttribute : Foundation.CodableAttributedStringKey {
    public typealias Value = UIColor
    public static let name: Swift.String = "NSStrikethroughColor"
    public static func encode(_ value: Value, to encoder: any Swift.Encoder) throws { throw _UIKitAttributeNotCodable() }
    public static func decode(from decoder: any Swift.Decoder) throws -> Value { throw _UIKitAttributeNotCodable() }
  }
  @frozen public enum ObliquenessAttribute : Foundation.CodableAttributedStringKey {
    public typealias Value = CoreFoundation.CGFloat
    public static let name: Swift.String = "NSObliqueness"
  }
  @frozen public enum ExpansionAttribute : Foundation.CodableAttributedStringKey {
    public typealias Value = CoreFoundation.CGFloat
    public static let name: Swift.String = "NSExpansion"
  }
  @frozen public enum TextItemTagAttribute : Foundation.CodableAttributedStringKey {
    public typealias Value = Swift.String
    public static let name: Swift.String = "UITextItemTag"
  }
}

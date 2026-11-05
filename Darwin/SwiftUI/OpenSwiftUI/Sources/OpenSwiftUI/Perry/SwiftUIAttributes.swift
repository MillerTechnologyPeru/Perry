//
//  SwiftUIAttributes.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation
//
//  The attribute scope apps built against Apple's SDK name: SwiftUI's,
//  which OpenSwiftUI calls OpenSwiftUIAttributes. Its attributes have the
//  names of OpenSwiftUI's, so an attributed string an app builds with them
//  reads the same to Text.

#if os(iOS) || os(visionOS)
public import Foundation
public import OpenSwiftUICore

@available(OpenSwiftUI_v3_0, *)
extension AttributeScopes {
    /// A property for accessing the attribute scopes defined by SwiftUI.
    public var swiftUI: SwiftUIAttributes.Type {
        SwiftUIAttributes.self
    }

    /// Attribute scopes defined by SwiftUI.
    public struct SwiftUIAttributes: AttributeScope {
        public let font: FontAttribute
        public let foregroundColor: ForegroundColorAttribute
        public let backgroundColor: BackgroundColorAttribute
        public let strikethroughStyle: StrikethroughStyleAttribute
        public let underlineStyle: UnderlineStyleAttribute
        public let kern: KerningAttribute
        public let tracking: TrackingAttribute
        public let baselineOffset: BaselineOffsetAttribute
        public let foundation: FoundationAttributes
    }
}

@available(*, unavailable)
extension AttributeScopes.SwiftUIAttributes: Sendable {}

@available(OpenSwiftUI_v3_0, *)
extension AttributeScopes.SwiftUIAttributes {
    typealias Open = AttributeScopes.OpenSwiftUIAttributes

    @frozen
    public enum FontAttribute: AttributedStringKey {
        public typealias Value = Font
        public static let name = Open.FontAttribute.name
    }

    @frozen
    public enum ForegroundColorAttribute: AttributedStringKey {
        public typealias Value = Color
        public static let name = Open.ForegroundColorAttribute.name
    }

    @frozen
    public enum BackgroundColorAttribute: AttributedStringKey {
        public typealias Value = Color
        public static let name = Open.BackgroundColorAttribute.name
    }

    @frozen
    public enum StrikethroughStyleAttribute: AttributedStringKey {
        public typealias Value = Text.LineStyle
        public static let name = Open.StrikethroughStyleAttribute.name
    }

    @frozen
    public enum UnderlineStyleAttribute: AttributedStringKey {
        public typealias Value = Text.LineStyle
        public static let name = Open.UnderlineStyleAttribute.name
    }

    @frozen
    public enum KerningAttribute: CodableAttributedStringKey {
        public typealias Value = CGFloat
        public static let name = Open.KerningAttribute.name
    }

    @frozen
    public enum TrackingAttribute: CodableAttributedStringKey {
        public typealias Value = CGFloat
        public static let name = Open.TrackingAttribute.name
    }

    @frozen
    public enum BaselineOffsetAttribute: CodableAttributedStringKey {
        public typealias Value = CGFloat
        public static let name = Open.BaselineOffsetAttribute.name
    }
}
#endif

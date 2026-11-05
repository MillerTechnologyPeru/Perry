// DeveloperToolsSupport, the framework Xcode's tools use within apps: the
// resources asset catalogs generate symbols for, the items an app offers
// Xcode's library, previews and design-time values. Apps built with Xcode
// link it for those, though nothing at run time but the resources does
// anything: resources keep their name and bundle, which SwiftUI reads
// through Perry's SPI; design-time values are their fallbacks.

public import CoreGraphics
public import Foundation

// MARK: - Design-time values

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public func __designTimeBoolean<T>(_ key: String, fallback: T) -> T where T: ExpressibleByBooleanLiteral {
    fallback
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public func __designTimeFloat<T>(_ key: String, fallback: T) -> T where T: ExpressibleByFloatLiteral {
    fallback
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public func __designTimeInteger<T>(_ key: String, fallback: T) -> T where T: ExpressibleByIntegerLiteral {
    fallback
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public func __designTimeString<T>(_ key: String, fallback: T) -> T where T: ExpressibleByStringLiteral {
    fallback
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public func __designTimeString<T>(_ key: String, fallback: T) -> T where T: ExpressibleByExtendedGraphemeClusterLiteral {
    fallback
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public func __designTimeString(_ key: String, fallback: Unicode.Scalar) -> Unicode.Scalar {
    fallback
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public func __designTimeApplyIncrementalValues(_ updates: [[String: any Sendable]]) {}

// MARK: - Library content

/// A view or modifier an app offers Xcode's library.
@available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, visionOS 1.0, *)
public struct LibraryItem {
    /// The library's section for an item.
    public struct Category {
        var name: String

        public static let effect = Category(name: "effect")
        public static let layout = Category(name: "layout")
        public static let control = Category(name: "control")
        public static let other = Category(name: "other")
    }

    var title: String?
    var category: Category

    public init<SnippetExpressionType>(
        _ snippet: @autoclosure () -> SnippetExpressionType,
        visible: Bool = true,
        title: String? = nil,
        category: LibraryItem.Category = .other,
        matchingSignature: String? = nil
    ) {
        self.title = title
        self.category = category
    }
}

/// Builds an array of library items.
@available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, visionOS 1.0, *)
@resultBuilder
public struct LibraryContentBuilder {
    public static func buildBlock(_ segments: [LibraryItem]...) -> [LibraryItem] {
        segments.flatMap { $0 }
    }

    public static func buildExpression(_ item: LibraryItem) -> [LibraryItem] {
        [item]
    }

    public static func buildExpression(_ items: [LibraryItem]) -> [LibraryItem] {
        items
    }
}

/// A source of views and modifiers for Xcode's library.
@available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, visionOS 1.0, *)
public protocol LibraryContentProvider {
    associatedtype ModifierBase = Any

    @LibraryContentBuilder
    var views: [LibraryItem] { get }

    @LibraryContentBuilder
    func modifiers(base: ModifierBase) -> [LibraryItem]
}

@available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, visionOS 1.0, *)
extension LibraryContentProvider {
    public var views: [LibraryItem] { [] }

    public func modifiers(base: ModifierBase) -> [LibraryItem] { [] }
}

// MARK: - Previews

/// A preview, which Xcode shows; never made at run time.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
@MainActor
public struct Preview {}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension Preview: Sendable {}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension Preview {
    public enum ViewTraits {}
}

@available(iOS 26.0, macOS 27.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
public struct PreviewArguments<T> {}

@available(*, unavailable)
extension PreviewArguments: Sendable {}

@available(iOS 18.0, macOS 15.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
@resultBuilder
public struct PreviewBodyBuilder<Content> {
    public static func buildBlock(_ content: Content) -> Content { content }
}

@available(*, unavailable)
extension PreviewBodyBuilder: Sendable {}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
@resultBuilder
public struct PreviewMacroBodyBuilder<Content> {
    public static func buildBlock(_ content: Content) -> Content { content }
}

@available(*, unavailable)
extension PreviewMacroBodyBuilder: Sendable {}

/// A type the preview macro generates, which Xcode finds previews by.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
public protocol PreviewRegistry {
    static var fileID: String { get }
    static var line: Int { get }
    static var column: Int { get }
    @MainActor static func makePreview() throws -> Preview
    @available(*, deprecated, message: "This method is not called. Please implement makePreview() instead.")
    static var preview: Preview { get }
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension PreviewRegistry {
    public static var preview: Preview {
        MainActor.assumeIsolated { Preview() }
    }
}

/// An error a preview throws when it can't be made.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
public struct PreviewUnavailable: Error {
    public init() {}
}

/// A trait of a preview, such as its layout.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
@MainActor
public struct PreviewTrait<T> {
    @available(iOS 18.0, macOS 15.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    public init(_ traits: PreviewTrait<T>...) {}

    init() {}
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension PreviewTrait: Sendable {}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension PreviewTrait where T == Preview.ViewTraits {
    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public static var assistiveAccess: PreviewTrait<Preview.ViewTraits> { PreviewTrait() }
    public static var defaultLayout: PreviewTrait<Preview.ViewTraits> { PreviewTrait() }
    public static var sizeThatFitsLayout: PreviewTrait<Preview.ViewTraits> { PreviewTrait() }
    public static func fixedLayout(width: CGFloat, height: CGFloat) -> PreviewTrait<T> { PreviewTrait() }
    public static var portrait: PreviewTrait<Preview.ViewTraits> { PreviewTrait() }
    public static var landscapeLeft: PreviewTrait<Preview.ViewTraits> { PreviewTrait() }
    public static var landscapeRight: PreviewTrait<Preview.ViewTraits> { PreviewTrait() }
    public static var portraitUpsideDown: PreviewTrait<Preview.ViewTraits> { PreviewTrait() }
}

/// The size constraint for a preview.
@available(iOS 13.0, macCatalyst 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
@_originallyDefinedIn(module: "SwiftUI", iOS 17.0)
@_originallyDefinedIn(module: "SwiftUI", macCatalyst 17.0)
@_originallyDefinedIn(module: "SwiftUI", macOS 14.0)
@_originallyDefinedIn(module: "SwiftUI", tvOS 17.0)
@_originallyDefinedIn(module: "SwiftUI", watchOS 10.0)
public enum PreviewLayout: Sendable {
    case device
    case sizeThatFits
    case fixed(width: CGFloat, height: CGFloat)
    @available(iOS, unavailable)
    case fixed3D(width: CGFloat, height: CGFloat, depth: CGFloat)
}

// MARK: - Resources

/// A color in an asset catalog, by name.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
public struct ColorResource: Hashable, Sendable {
    @_spi(Perry) public let name: String
    @_spi(Perry) public let bundle: Bundle

    public init(name: String, bundle: Bundle) {
        self.name = name
        self.bundle = bundle
    }
}

/// An image in an asset catalog, by name.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
public struct ImageResource: Hashable, Sendable {
    @_spi(Perry) public let name: String
    @_spi(Perry) public let bundle: Bundle

    public init(name: String, bundle: Bundle) {
        self.name = name
        self.bundle = bundle
    }
}

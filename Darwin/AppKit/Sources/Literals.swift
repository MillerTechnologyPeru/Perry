import Foundation

// Color and image literals, and the quick looks playgrounds showed of
// AppKit's objects before CustomPlaygroundDisplayConvertible.

extension NSColor: _ExpressibleByColorLiteral {
    /// The sRGB color a #colorLiteral names.
    @nonobjc
    public required convenience init(_colorLiteralRed red: Float, green: Float, blue: Float, alpha: Float) {
        self.init(srgbRed: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }
}

public typealias _ColorLiteralType = NSColor

extension NSImage: _ExpressibleByImageLiteral {
    /// The image an #imageLiteral names, from the main bundle; empty when
    /// there is no image of the name.
    @nonobjc
    public required convenience init(imageLiteralResourceName name: String) {
        let named = NSImage(named: name)
        self.init(size: named?.size ?? .zero)
        if let named {
            for representation in named.representations { addRepresentation(representation) }
            isTemplate = named.isTemplate
        }
    }
}

public typealias _ImageLiteralType = NSImage

extension NSView: __DefaultCustomPlaygroundQuickLookable {
    @available(*, deprecated, message: "NSView._defaultCustomPlaygroundQuickLook will be removed in a future Swift version")
    @MainActor @preconcurrency
    public var _defaultCustomPlaygroundQuickLook: PlaygroundQuickLook {
        .view(self)
    }
}

extension NSCursor: __DefaultCustomPlaygroundQuickLookable {
    @available(*, deprecated, message: "NSCursor._defaultCustomPlaygroundQuickLook will be removed in a future Swift version")
    public var _defaultCustomPlaygroundQuickLook: PlaygroundQuickLook {
        .image(image)
    }
}

@available(macOS 10.12.2, *)
extension NSTouchBar: __DefaultCustomPlaygroundQuickLookable {
    @available(swift, deprecated: 4.2, message: "PlaygroundQuickLook will be removed in a future Swift version. For customizing how types are presented in playgrounds, use CustomPlaygroundDisplayConvertible instead.")
    @MainActor @preconcurrency
    public var _defaultCustomPlaygroundQuickLook: PlaygroundQuickLook {
        .text("\(type(of: self)): \(itemIdentifiers.map(\.rawValue).joined(separator: ", "))")
    }
}

@available(macOS 10.12.2, *)
extension NSTouchBarItem: __DefaultCustomPlaygroundQuickLookable {
    @available(swift, deprecated: 4.2, message: "PlaygroundQuickLook will be removed in a future Swift version. For customizing how types are presented in playgrounds, use CustomPlaygroundDisplayConvertible instead.")
    @MainActor @preconcurrency
    public var _defaultCustomPlaygroundQuickLook: PlaygroundQuickLook {
        if let view { return .view(view) }
        return .text(customizationLabel)
    }
}

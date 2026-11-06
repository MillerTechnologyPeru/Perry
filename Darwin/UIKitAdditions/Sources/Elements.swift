// Menus, actions, bar button items, images, text items, calendar
// decorations and sheet detents: UIKit's Swift initializers over its
// Objective-C ones, which iOS keeps in UIKit's Swift module. Declarations
// are the SDK interface's, for its ABI.

public import Foundation
public import _UIKitPrivate

// MARK: - Actions and menus

@available(iOS 13.0, tvOS 13.0, *)
@available(watchOS, unavailable)
extension UIAction {
  @_disfavoredOverload @_Concurrency.MainActor @preconcurrency convenience public init(title: Swift.String = "", image: UIImage? = nil, identifier: UIAction.Identifier? = nil, discoverabilityTitle: Swift.String? = nil, attributes: UIMenuElement.Attributes = [], state: UIMenuElement.State = .off, handler: @escaping UIActionHandler) {
    self.init(_perryTitle: title, image: image, identifier: identifier, handler: handler)
    self.discoverabilityTitle = discoverabilityTitle
    self.attributes = attributes
    self.state = state
  }
}

@available(iOS 13.0, tvOS 13.0, *)
@available(watchOS, unavailable)
extension UIMenu {
  @_disfavoredOverload @_Concurrency.MainActor @preconcurrency convenience public init(title: Swift.String = "", image: UIImage? = nil, identifier: UIMenu.Identifier? = nil, options: UIMenu.Options = [], children: [UIMenuElement] = []) {
    self.init(_perryTitle: title, image: image, identifier: identifier, options: options, children: children)
  }
}

// MARK: - Bar button items

@available(iOS 14.0, tvOS 14.0, *)
@available(watchOS, unavailable)
extension UIBarButtonItem {
  @_Concurrency.MainActor @preconcurrency convenience public init(systemItem: UIBarButtonItem.SystemItem, primaryAction: UIAction? = nil, menu: UIMenu? = nil) {
    self.init(__barButtonSystemItem: systemItem, primaryAction: primaryAction, menu: menu)
  }
  @_Concurrency.MainActor @preconcurrency convenience public init(title: Swift.String? = nil, image: UIImage? = nil, primaryAction: UIAction? = nil, menu: UIMenu? = nil) {
    self.init(__title: title, image: image, target: nil, action: nil, menu: menu)
    if let primaryAction { self.primaryAction = primaryAction }
  }
  @_Concurrency.MainActor @preconcurrency convenience public init(title: Swift.String?, image: UIImage?, target: Swift.AnyObject?, action: ObjectiveC.Selector?, menu: UIMenu? = nil) {
    self.init(__title: title, image: image, target: target, action: action, menu: menu)
  }
}

@available(iOS 16.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
extension UIBarButtonItemGroup {
  @_Concurrency.MainActor @preconcurrency public class func optionalGroup(customizationIdentifier: Swift.String, isInDefaultCustomization: Swift.Bool = true, representativeItem: UIBarButtonItem? = nil, items: [UIBarButtonItem]) -> UIBarButtonItemGroup {
    __optionalGroup(withCustomizationIdentifier: customizationIdentifier, inDefaultCustomization: isInDefaultCustomization,
                    representativeItem: representativeItem, items: items)
  }
}

// MARK: - Images

@available(iOS 13.0, tvOS 13.0, *)
extension UIImage {
  /// Where the image's baseline is above its bottom, if it has one.
  public var baselineOffsetFromBottom: CoreFoundation.CGFloat? {
    get { __hasBaseline ? __baselineOffsetFromBottom : nil }
  }
}

@available(iOS 16.0, tvOS 16.0, *)
extension UIImage {
  /// The symbol drawn for `variableValue`: Perry's symbols have no
  /// variable values, so it is the symbol itself.
  convenience public init?(systemName name: Swift.String, variableValue: Swift.Double, configuration: UIImage.Configuration? = nil) {
    guard let image = UIImage(systemName: name, withConfiguration: configuration), let cgImage = image.cgImage else { return nil }
    self.init(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
  }
  convenience public init?(named name: Swift.String, in bundle: Foundation.Bundle? = nil, variableValue: Swift.Double, configuration: UIImage.Configuration? = nil) {
    guard let image = UIImage(named: name, in: bundle, with: configuration), let cgImage = image.cgImage else { return nil }
    self.init(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
  }
}

// MARK: - Text items

@available(iOS 17.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
extension UITextItem {
  public enum Content {
    case link(Foundation.URL)
    case textAttachment(NSTextAttachment)
    case tag(Swift.String)
  }
  @_Concurrency.MainActor @preconcurrency public var content: UITextItem.Content {
    get {
      switch __contentType {
      case .link: return .link(__link ?? URL(string: "about:blank")!)
      case .textAttachment: return .textAttachment(__textAttachment ?? NSTextAttachment())
      default: return .tag(__tagIdentifier ?? "")
      }
    }
  }
}

// MARK: - Calendar decorations and sheet detents

@available(iOS 16.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
extension UICalendarView.Decoration {
  @_Concurrency.MainActor @preconcurrency public static func image(_ image: UIImage?, color: UIColor? = nil, size: UICalendarView.DecorationSize = .medium) -> UICalendarView.Decoration {
    UICalendarView.Decoration(__image: image, color: color, size: size)
  }
}

@available(iOS 16.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
extension UISheetPresentationController.Detent {
  @_Concurrency.MainActor @preconcurrency public static func custom(identifier: UISheetPresentationController.Detent.Identifier? = nil, resolver: @escaping (_ context: any UISheetPresentationControllerDetentResolutionContext) -> CoreFoundation.CGFloat?) -> UISheetPresentationController.Detent {
    let objectiveC: (any UISheetPresentationControllerDetentResolutionContext) -> CoreFoundation.CGFloat = { context in
      resolver(context) ?? __UISheetPresentationControllerDetentInactive
    }
    return __customDetent(withIdentifier: identifier, resolver: objectiveC)
  }
}

// MARK: - Glass, which SwiftUI's hosting views ask for

@available(iOS 26.0, *)
extension UIView {
  /// A material a view's background is drawn in: SPI.
  public protocol Material {}

  /// The view's background material. Perry draws no materials; the view
  /// keeps its background color.
  public var _background: (any UIView.Material)? {
    get { nil }
    set {}
  }
}

@available(iOS 26.0, *)
public struct _Glass : UIView.Material {
  public struct _GlassVariant {
    let rawValue: Int
    public static var regular: _Glass._GlassVariant { .init(rawValue: 0) }
  }
  let variant: _GlassVariant
  let smoothness: CoreGraphics.CGFloat

  public init(_ variant: _Glass._GlassVariant, smoothness: CoreGraphics.CGFloat) {
    self.variant = variant
    self.smoothness = smoothness
  }
}

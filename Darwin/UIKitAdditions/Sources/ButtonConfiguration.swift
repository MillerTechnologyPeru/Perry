// Button and background configurations, iOS 15's way of styling a button,
// which iOS keeps in UIKit's Swift module over a private Objective-C class.
// Here the configuration is a Swift value kept with its button and applied
// to it through the button's own title, image, colors and layer.
// Declarations are the SDK interface's, for its ABI.

public import Foundation
import ObjectiveC

// MARK: - Transformers

@available(iOS 15.0, tvOS 15.0, *)
@available(watchOS, unavailable)
public struct UIConfigurationTextAttributesTransformer {
  public let transform: (Foundation.AttributeContainer) -> Foundation.AttributeContainer
  public init(_ transform: @escaping (Foundation.AttributeContainer) -> Foundation.AttributeContainer) {
    self.transform = transform
  }
  public func callAsFunction(_ input: Foundation.AttributeContainer) -> Foundation.AttributeContainer { transform(input) }
}

@available(iOS 14.0, tvOS 14.0, *)
@available(watchOS, unavailable)
public struct UIConfigurationColorTransformer {
  public let transform: (UIColor) -> UIColor
  public init(_ transform: @escaping (UIColor) -> UIColor) { self.transform = transform }
  public func callAsFunction(_ input: UIColor) -> UIColor { transform(input) }
  public static let grayscale = UIConfigurationColorTransformer { color in
    var white: CGFloat = 0, alpha: CGFloat = 0
    return color.getWhite(&white, alpha: &alpha) ? UIColor(white: white, alpha: alpha) : color
  }
  public static let preferredTint = UIConfigurationColorTransformer { _ in .tintColor }
  public static let monochromeTint = UIConfigurationColorTransformer { _ in .tintColor }
}

/// Whether two insets are the same: their Equatable conformance is in
/// UIKit's overlay, which this module adds to.
func _insetsEqual(_ a: NSDirectionalEdgeInsets, _ b: NSDirectionalEdgeInsets) -> Bool {
  a.top == b.top && a.leading == b.leading && a.bottom == b.bottom && a.trailing == b.trailing
}

// MARK: - Background

@available(iOS 14.0, tvOS 14.0, *)
@available(watchOS, unavailable)
public struct UIBackgroundConfiguration : Swift.Hashable {
  public static func clear() -> UIKit.UIBackgroundConfiguration { .init() }
  public static func listCell() -> UIKit.UIBackgroundConfiguration {
    var configuration = UIBackgroundConfiguration()
    configuration.backgroundColor = .secondarySystemGroupedBackground
    return configuration
  }
  public static func listHeader() -> UIKit.UIBackgroundConfiguration { .init() }
  public static func listFooter() -> UIKit.UIBackgroundConfiguration { .init() }

  public var customView: UIView?
  public var cornerRadius: CoreFoundation.CGFloat = 0
  public var backgroundInsets: NSDirectionalEdgeInsets = .zero
  public var backgroundColor: UIColor?
  public var backgroundColorTransformer: UIKit.UIConfigurationColorTransformer?
  public func resolvedBackgroundColor(for tintColor: UIColor) -> UIColor {
    let color = backgroundColor ?? tintColor
    return backgroundColorTransformer.map { $0(color) } ?? color
  }
  public var image: UIImage?
  public var strokeColor: UIColor?
  public var strokeWidth: CoreFoundation.CGFloat = 0
  public var strokeOutset: CoreFoundation.CGFloat = 0

  init() {}

  public static func == (a: UIKit.UIBackgroundConfiguration, b: UIKit.UIBackgroundConfiguration) -> Swift.Bool {
    a.customView === b.customView && a.cornerRadius == b.cornerRadius && _insetsEqual(a.backgroundInsets, b.backgroundInsets)
      && a.backgroundColor == b.backgroundColor && a.image == b.image && a.strokeColor == b.strokeColor
      && a.strokeWidth == b.strokeWidth && a.strokeOutset == b.strokeOutset
  }
  public func hash(into hasher: inout Swift.Hasher) {
    hasher.combine(cornerRadius)
    hasher.combine(backgroundColor)
    hasher.combine(strokeWidth)
  }
}

// MARK: - Button

@available(iOS 15.0, tvOS 15.0, *)
@available(watchOS, unavailable)
extension UIButton {
  public struct Configuration : Swift.Hashable {
    public enum Size {
      case mini
      case small
      case medium
      case large
    }
    public enum TitleAlignment {
      case automatic
      case leading
      case center
      case trailing
    }
    public enum CornerStyle {
      case fixed
      case dynamic
      case small
      case medium
      case large
      case capsule
    }
    public enum MacIdiomStyle {
      case automatic
      case bordered
      case borderless
      case borderlessTinted
    }
    public enum Indicator {
      case automatic
      case none
      case popup
    }

    /// Which of iOS's styles the configuration started from.
    enum Style { case plain, tinted, gray, filled, borderless, bordered, borderedTinted, borderedProminent }
    var style: Style

    init(style: Style) {
      self.style = style
      switch style {
      case .filled, .borderedProminent, .tinted, .gray, .bordered, .borderedTinted:
        cornerStyle = .dynamic
        background.cornerRadius = 8
      case .plain, .borderless:
        break
      }
    }

    public static func plain() -> UIButton.Configuration { .init(style: .plain) }
    public static func tinted() -> UIButton.Configuration { .init(style: .tinted) }
    public static func gray() -> UIButton.Configuration { .init(style: .gray) }
    public static func filled() -> UIButton.Configuration { .init(style: .filled) }
    public static func borderless() -> UIButton.Configuration { .init(style: .borderless) }
    public static func bordered() -> UIButton.Configuration { .init(style: .bordered) }
    public static func borderedTinted() -> UIButton.Configuration { .init(style: .borderedTinted) }
    public static func borderedProminent() -> UIButton.Configuration { .init(style: .borderedProminent) }
    public func updated(for button: UIButton) -> UIButton.Configuration { self }

    public var background: UIKit.UIBackgroundConfiguration = .clear()
    public var cornerStyle: UIButton.Configuration.CornerStyle = .dynamic
    public var buttonSize: UIButton.Configuration.Size = .medium
    public var macIdiomStyle: UIButton.Configuration.MacIdiomStyle = .automatic
    public var baseForegroundColor: UIColor?
    public var baseBackgroundColor: UIColor?
    public var image: UIImage?
    public var imageColorTransformer: UIKit.UIConfigurationColorTransformer?
    public var preferredSymbolConfigurationForImage: UIImage.SymbolConfiguration?
    public var showsActivityIndicator: Swift.Bool = false
    public var activityIndicatorColorTransformer: UIKit.UIConfigurationColorTransformer?
    public var title: Swift.String?
    public var attributedTitle: Foundation.AttributedString?
    public var titleTextAttributesTransformer: UIKit.UIConfigurationTextAttributesTransformer?
    public var subtitle: Swift.String?
    public var attributedSubtitle: Foundation.AttributedString?
    public var subtitleTextAttributesTransformer: UIKit.UIConfigurationTextAttributesTransformer?
    public var indicator: UIButton.Configuration.Indicator = .automatic
    public var indicatorColorTransformer: UIKit.UIConfigurationColorTransformer?
    public var contentInsets: NSDirectionalEdgeInsets = NSDirectionalEdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12)
    public mutating func setDefaultContentInsets() {
      contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12)
    }
    public var imagePlacement: NSDirectionalRectEdge = .leading
    public var imagePadding: CoreFoundation.CGFloat = 0
    public var titlePadding: CoreFoundation.CGFloat = 0
    public var titleAlignment: UIButton.Configuration.TitleAlignment = .automatic
    public var automaticallyUpdateForSelection: Swift.Bool = true
    /// The title's NSLineBreakMode: truncating its tail, as iOS's.
    var _lineBreakModeRaw: Int = NSLineBreakMode.byTruncatingTail.rawValue

    public static func == (a: UIButton.Configuration, b: UIButton.Configuration) -> Swift.Bool {
      a.style == b.style && a.background == b.background && a.cornerStyle == b.cornerStyle && a.buttonSize == b.buttonSize
        && a.baseForegroundColor == b.baseForegroundColor && a.baseBackgroundColor == b.baseBackgroundColor
        && a.image == b.image && a.title == b.title && a.attributedTitle == b.attributedTitle && a.subtitle == b.subtitle
        && _insetsEqual(a.contentInsets, b.contentInsets) && a.imagePlacement == b.imagePlacement && a.imagePadding == b.imagePadding
        && a.titlePadding == b.titlePadding && a.titleAlignment == b.titleAlignment
    }
    public func hash(into hasher: inout Swift.Hasher) {
      hasher.combine(title)
      hasher.combine(cornerStyle)
      hasher.combine(baseBackgroundColor)
    }

    // The colors iOS's styles give.
    func foregroundColor(tint: UIColor) -> UIColor {
      if let baseForegroundColor { return baseForegroundColor }
      switch style {
      case .filled, .borderedProminent: return .white
      default: return tint
      }
    }

    func backgroundColor(tint: UIColor) -> UIColor? {
      if let color = background.backgroundColor { return color }
      switch style {
      case .filled, .borderedProminent: return baseBackgroundColor ?? tint
      case .tinted, .borderedTinted: return (baseBackgroundColor ?? tint).withAlphaComponent(0.15)
      case .gray, .bordered: return baseBackgroundColor ?? .secondarySystemFill
      case .plain, .borderless: return baseBackgroundColor
      }
    }

    func cornerRadius(height: CoreFoundation.CGFloat) -> CoreFoundation.CGFloat {
      switch cornerStyle {
      case .fixed: return background.cornerRadius
      case .dynamic: return background.cornerRadius > 0 ? background.cornerRadius : 6
      case .small: return 4
      case .medium: return 8
      case .large: return 12
      case .capsule: return height / 2
      }
    }

    /// The title with the transformer's attributes, and its font.
    func resolvedTitle(color: UIColor) -> NSAttributedString? {
      var text: Foundation.AttributedString
      if let attributedTitle {
        text = attributedTitle
      } else if let title {
        text = Foundation.AttributedString(title)
      } else {
        return nil
      }
      var container = Foundation.AttributeContainer()
      container.uiKit.foregroundColor = color
      container.uiKit.font = .systemFont(ofSize: 17, weight: style == .filled || style == .borderedProminent ? .semibold : .regular)
      if let titleTextAttributesTransformer { container = titleTextAttributesTransformer(container) }
      text.mergeAttributes(container, mergePolicy: .keepCurrent)
      return (try? NSAttributedString(text, including: \.uiKit)) ?? NSAttributedString(text)
    }
  }

  @_Concurrency.MainActor @preconcurrency convenience public init(configuration: UIButton.Configuration, primaryAction: UIAction? = nil) {
    self.init(type: .system)
    self.configuration = configuration
    if let primaryAction { addAction(primaryAction, for: .primaryActionTriggered) }
  }

  @_Concurrency.MainActor @preconcurrency public var configuration: UIButton.Configuration? {
    get { _ButtonConfigurations.configuration(of: self) }
    set {
      _ButtonConfigurations.set(newValue, of: self)
      if let newValue { _ButtonConfigurations.apply(newValue, to: self) }
    }
  }
}

@available(iOS 15.0, tvOS 15.0, *)
@available(watchOS, unavailable)
extension UIButton.Configuration {
  public var titleLineBreakMode: NSLineBreakMode {
    get { _titleLineBreakMode }
    set { _titleLineBreakMode = newValue }
  }
  public var subtitleLineBreakMode: NSLineBreakMode {
    get { .byTruncatingTail }
    set {}
  }
  public var imageReservation: CoreFoundation.CGFloat {
    get { 0 }
    set {}
  }
}

@available(iOS 15.0, tvOS 15.0, *)
extension UIButton.Configuration {
  /// The title's line break mode: kept with the other values.
  var _titleLineBreakMode: NSLineBreakMode {
    get { NSLineBreakMode(rawValue: _lineBreakModeRaw) ?? .byTruncatingTail }
    set { _lineBreakModeRaw = newValue.rawValue }
  }
}

/// The configurations of buttons, kept with them, and their application.
@available(iOS 15.0, tvOS 15.0, *)
@MainActor
enum _ButtonConfigurations {
  final class Box { let value: UIButton.Configuration; init(_ value: UIButton.Configuration) { self.value = value } }
  nonisolated(unsafe) private static var key: UInt8 = 0

  static func configuration(of button: UIButton) -> UIButton.Configuration? {
    (objc_getAssociatedObject(button, &key) as? Box)?.value
  }

  static func set(_ configuration: UIButton.Configuration?, of button: UIButton) {
    objc_setAssociatedObject(button, &key, configuration.map(Box.init), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
  }

  static func apply(_ configuration: UIButton.Configuration, to button: UIButton) {
    let tint = button.tintColor ?? .systemBlue
    let foreground = configuration.foregroundColor(tint: tint)
    if let title = configuration.resolvedTitle(color: foreground) {
      button.setAttributedTitle(title, for: .normal)
    } else {
      button.setAttributedTitle(nil, for: .normal)
      button.setTitle(nil, for: .normal)
    }
    button.setTitleColor(foreground, for: .normal)
    var image = configuration.image
    if let symbol = configuration.preferredSymbolConfigurationForImage, let configured = image?.applyingSymbolConfiguration(symbol) {
      image = configured
    }
    button.setImage(image, for: .normal)
    button.tintColor = foreground
    button.titleLabel?.lineBreakMode = configuration._titleLineBreakMode
    switch configuration.titleAlignment {
    case .leading: button.contentHorizontalAlignment = .leading
    case .trailing: button.contentHorizontalAlignment = .trailing
    case .center, .automatic: button.contentHorizontalAlignment = .center
    }
    let insets = configuration.contentInsets
    button.contentEdgeInsets = UIEdgeInsets(top: insets.top, left: insets.leading, bottom: insets.bottom, right: insets.trailing)
    if image != nil, configuration.imagePadding > 0 {
      button.titleEdgeInsets = UIEdgeInsets(top: 0, left: configuration.imagePadding, bottom: 0, right: -configuration.imagePadding)
    }
    button.backgroundColor = configuration.backgroundColor(tint: tint)
    let height = max(button.bounds.height, button.sizeThatFits(.zero).height)
    button.layer.cornerRadius = configuration.cornerRadius(height: height)
    button.layer.masksToBounds = button.layer.cornerRadius > 0
    if let stroke = configuration.background.strokeColor, configuration.background.strokeWidth > 0 {
      button.layer.borderColor = stroke.cgColor
      button.layer.borderWidth = configuration.background.strokeWidth
    }
  }
}

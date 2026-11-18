// UIKit's content configurations (iOS 14), which iOS keeps in UIKit's Swift
// module and Perry's UIKit, whose Swift overlay predates them, lacks: the
// configuration states, the content view and configuration protocols, the
// list content configuration with a view that shows it, the cells' content
// and background configurations, and the collection view's cell and
// supplementary registrations. Declarations are the SDK interface's, for
// its ABI. A cell keeps its configurations with it and shows the content
// configuration's view over its content view; it does not ask for a new
// configuration when its state changes.

public import Foundation
public import CoreGraphics
public import _UIKitPrivate

// MARK: - Configuration states

@available(iOS 14.0, tvOS 14.0, *)
@available(watchOS, unavailable)
public protocol UIConfigurationState {
  init(traitCollection: UITraitCollection)
  var traitCollection: UITraitCollection { get set }
  subscript(key: UIConfigurationStateCustomKey) -> Swift.AnyHashable? { get set }
}

@available(iOS 14.0, tvOS 14.0, *)
@available(watchOS, unavailable)
public struct UIViewConfigurationState : UIKit.UIConfigurationState, Swift.Hashable {
  public var traitCollection: UITraitCollection
  public var isDisabled: Swift.Bool = false
  public var isHighlighted: Swift.Bool = false
  public var isSelected: Swift.Bool = false
  public var isFocused: Swift.Bool = false
  public var isPinned: Swift.Bool = false
  var custom: [UIConfigurationStateCustomKey: Swift.AnyHashable] = [:]

  public subscript(key: UIConfigurationStateCustomKey) -> Swift.AnyHashable? {
    get { custom[key] }
    set { custom[key] = newValue }
  }
  public init(traitCollection: UITraitCollection) {
    self.traitCollection = traitCollection
  }
}

@available(iOS 14.0, tvOS 14.0, *)
@available(watchOS, unavailable)
public struct UICellConfigurationState : UIKit.UIConfigurationState, Swift.Hashable {
  public enum DragState : Swift.Hashable {
    case none
    case lifting
    case dragging
  }
  public enum DropState : Swift.Hashable {
    case none
    case notTargeted
    case targeted
  }
  public var traitCollection: UITraitCollection
  public var isDisabled: Swift.Bool = false
  public var isHighlighted: Swift.Bool = false
  public var isSelected: Swift.Bool = false
  public var isFocused: Swift.Bool = false
  public var isPinned: Swift.Bool = false
  public var isEditing: Swift.Bool = false
  public var isExpanded: Swift.Bool = false
  public var isSwiped: Swift.Bool = false
  public var isReordering: Swift.Bool = false
  public var cellDragState: UIKit.UICellConfigurationState.DragState = .none
  public var cellDropState: UIKit.UICellConfigurationState.DropState = .none
  var custom: [UIConfigurationStateCustomKey: Swift.AnyHashable] = [:]

  public subscript(key: UIConfigurationStateCustomKey) -> Swift.AnyHashable? {
    get { custom[key] }
    set { custom[key] = newValue }
  }
  public init(traitCollection: UITraitCollection) {
    self.traitCollection = traitCollection
  }
}

/// A state from the Objective-C object UIKit passes one as. Perry's UIKit
/// passes none; one made elsewhere gives its selection and highlight.
@available(iOS 14.0, tvOS 14.0, *)
@available(watchOS, unavailable)
extension UIKit.UICellConfigurationState : Swift._ObjectiveCBridgeable {
  @_semantics("convertToObjectiveC") public func _bridgeToObjectiveC() -> __UICellConfigurationState {
    let state = __UICellConfigurationState(traitCollection: traitCollection)
    state.isSelected = isSelected
    state.isHighlighted = isHighlighted
    state.isDisabled = isDisabled
    return state
  }
  public static func _forceBridgeFromObjectiveC(_ input: __UICellConfigurationState, result: inout UIKit.UICellConfigurationState?) {
    result = _unconditionallyBridgeFromObjectiveC(input)
  }
  public static func _conditionallyBridgeFromObjectiveC(_ input: __UICellConfigurationState, result: inout UIKit.UICellConfigurationState?) -> Swift.Bool {
    result = _unconditionallyBridgeFromObjectiveC(input)
    return true
  }
  @_effects(readonly) public static func _unconditionallyBridgeFromObjectiveC(_ _state: __UICellConfigurationState?) -> UIKit.UICellConfigurationState {
    guard let _state else { return UICellConfigurationState(traitCollection: UITraitCollection.current) }
    var state = UICellConfigurationState(traitCollection: _state.traitCollection)
    state.isSelected = _state.isSelected
    state.isHighlighted = _state.isHighlighted
    state.isDisabled = _state.isDisabled
    return state
  }
  public typealias _ObjectiveCType = __UICellConfigurationState
}

// MARK: - Content views and configurations

@available(iOS 14.0, tvOS 14.0, *)
@available(watchOS, unavailable)
@_Concurrency.MainActor public protocol UIContentView : ObjectiveC.NSObjectProtocol {
  @_Concurrency.MainActor var configuration: any UIKit.UIContentConfiguration { get set }
  @available(iOS 16.0, tvOS 16.0, *)
  @_Concurrency.MainActor func supports(_ configuration: any UIKit.UIContentConfiguration) -> Swift.Bool
}

@available(iOS 16.0, tvOS 16.0, *)
@available(watchOS, unavailable)
extension UIKit.UIContentView {
  /// A content view takes any configuration of the type it shows now.
  @_Concurrency.MainActor public func supports(_ configuration: any UIKit.UIContentConfiguration) -> Swift.Bool {
    type(of: configuration) == type(of: self.configuration)
  }
}

@available(iOS 14.0, tvOS 14.0, *)
@available(watchOS, unavailable)
public protocol UIContentConfiguration {
  @_Concurrency.MainActor func makeContentView() -> any UIView & UIKit.UIContentView
  func updated(for state: any UIKit.UIConfigurationState) -> Self
}

// MARK: - List content

@available(iOS 14.0, tvOS 14.0, *)
@available(watchOS, unavailable)
public struct UIListContentConfiguration : UIKit.UIContentConfiguration, Swift.Hashable {
  public struct ImageProperties : Swift.Hashable {
    public var preferredSymbolConfiguration: UIImage.SymbolConfiguration?
    public var tintColor: UIColor?
    public var tintColorTransformer: UIKit.UIConfigurationColorTransformer?
    public func resolvedTintColor(for tintColor: UIColor) -> UIColor {
      let color = self.tintColor ?? tintColor
      return tintColorTransformer.map { $0(color) } ?? color
    }
    public var cornerRadius: CoreFoundation.CGFloat = 0
    public var maximumSize: CoreFoundation.CGSize = .zero
    public var reservedLayoutSize: CoreFoundation.CGSize = .zero
    public var accessibilityIgnoresInvertColors: Swift.Bool = false
    public static let standardDimension: CoreFoundation.CGFloat = -1

    public static func == (a: UIKit.UIListContentConfiguration.ImageProperties, b: UIKit.UIListContentConfiguration.ImageProperties) -> Swift.Bool {
      a.tintColor == b.tintColor && a.cornerRadius == b.cornerRadius && a.maximumSize == b.maximumSize
        && a.reservedLayoutSize == b.reservedLayoutSize && a.preferredSymbolConfiguration == b.preferredSymbolConfiguration
    }
    public func hash(into hasher: inout Swift.Hasher) {
      hasher.combine(tintColor)
      hasher.combine(cornerRadius)
    }
  }

  public struct TextProperties : Swift.Hashable {
    public enum TextAlignment : Swift.Hashable {
      case natural
      case center
      case justified
    }
    public enum TextTransform : Swift.Hashable {
      case none
      case uppercase
      case lowercase
      case capitalized
    }
    public var font: UIFont
    public var color: UIColor
    public var colorTransformer: UIKit.UIConfigurationColorTransformer?
    public func resolvedColor() -> UIColor { colorTransformer.map { $0(color) } ?? color }
    public var alignment: UIKit.UIListContentConfiguration.TextProperties.TextAlignment = .natural
    public var lineBreakMode: NSLineBreakMode = .byTruncatingTail
    public var numberOfLines: Swift.Int = 0
    public var adjustsFontSizeToFitWidth: Swift.Bool = false
    public var minimumScaleFactor: CoreFoundation.CGFloat = 0
    public var allowsDefaultTighteningForTruncation: Swift.Bool = false
    public var adjustsFontForContentSizeCategory: Swift.Bool = true
    public var showsExpansionTextWhenTruncated: Swift.Bool = false
    public var transform: UIKit.UIListContentConfiguration.TextProperties.TextTransform = .none

    init(font: UIFont, color: UIColor) {
      self.font = font
      self.color = color
    }

    public static func == (a: UIKit.UIListContentConfiguration.TextProperties, b: UIKit.UIListContentConfiguration.TextProperties) -> Swift.Bool {
      a.font == b.font && a.color == b.color && a.alignment == b.alignment && a.lineBreakMode == b.lineBreakMode
        && a.numberOfLines == b.numberOfLines && a.transform == b.transform
    }
    public func hash(into hasher: inout Swift.Hasher) {
      hasher.combine(font)
      hasher.combine(color)
      hasher.combine(numberOfLines)
    }

    /// The text as the transform has it.
    func transformed(_ text: Swift.String) -> Swift.String {
      switch transform {
      case .none: return text
      case .uppercase: return text.uppercased()
      case .lowercase: return text.lowercased()
      case .capitalized: return text.capitalized
      }
    }
  }

  /// Text over secondary text, or side by side when the secondary text is a value.
  private static func make(text: UIFont.TextStyle = .body, secondary: UIFont.TextStyle = .footnote, sideBySide: Swift.Bool = false,
                           secondaryColor: UIColor = .secondaryLabel) -> UIKit.UIListContentConfiguration {
    var configuration = UIListContentConfiguration(
      textProperties: TextProperties(font: .preferredFont(forTextStyle: text), color: .label),
      secondaryTextProperties: TextProperties(font: .preferredFont(forTextStyle: secondary), color: secondaryColor))
    configuration.prefersSideBySideTextAndSecondaryText = sideBySide
    return configuration
  }

  public static func cell() -> UIKit.UIListContentConfiguration { make() }
  public static func subtitleCell() -> UIKit.UIListContentConfiguration { make(secondary: .caption1) }
  public static func valueCell() -> UIKit.UIListContentConfiguration { make(secondary: .body, sideBySide: true) }
  public static func header() -> UIKit.UIListContentConfiguration { make(text: .footnote, secondary: .footnote) }
  public static func footer() -> UIKit.UIListContentConfiguration { make(text: .footnote, secondary: .footnote) }
  public static func prominentInsetGroupedHeader() -> UIKit.UIListContentConfiguration { make(text: .headline) }
  public static func extraProminentInsetGroupedHeader() -> UIKit.UIListContentConfiguration { make(text: .title2) }
  public static func accompaniedSidebarCell() -> UIKit.UIListContentConfiguration { make() }
  public static func accompaniedSidebarSubtitleCell() -> UIKit.UIListContentConfiguration { make(secondary: .caption1) }

  @_Concurrency.MainActor public func makeContentView() -> any UIView & UIKit.UIContentView {
    _PerryListContentView(self)
  }
  /// The configuration is the same in every state.
  public func updated(for state: any UIKit.UIConfigurationState) -> UIKit.UIListContentConfiguration { self }

  public var image: UIImage?
  public var imageProperties = UIKit.UIListContentConfiguration.ImageProperties()
  public var text: Swift.String?
  public var attributedText: Foundation.NSAttributedString?
  public var textProperties: UIKit.UIListContentConfiguration.TextProperties
  public var secondaryText: Swift.String?
  public var secondaryAttributedText: Foundation.NSAttributedString?
  public var secondaryTextProperties: UIKit.UIListContentConfiguration.TextProperties
  public var axesPreservingSuperviewLayoutMargins: UIAxis = [.horizontal]
  public var directionalLayoutMargins = NSDirectionalEdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 16)
  public var prefersSideBySideTextAndSecondaryText: Swift.Bool = false
  public var imageToTextPadding: CoreFoundation.CGFloat = 16
  public var textToSecondaryTextHorizontalPadding: CoreFoundation.CGFloat = 12
  public var textToSecondaryTextVerticalPadding: CoreFoundation.CGFloat = 2
  public var alpha: CoreFoundation.CGFloat = 1

  init(textProperties: TextProperties, secondaryTextProperties: TextProperties) {
    self.textProperties = textProperties
    self.secondaryTextProperties = secondaryTextProperties
  }

  public static func == (a: UIKit.UIListContentConfiguration, b: UIKit.UIListContentConfiguration) -> Swift.Bool {
    a.image == b.image && a.imageProperties == b.imageProperties && a.text == b.text && a.attributedText == b.attributedText
      && a.textProperties == b.textProperties && a.secondaryText == b.secondaryText
      && a.secondaryAttributedText == b.secondaryAttributedText && a.secondaryTextProperties == b.secondaryTextProperties
      && a.prefersSideBySideTextAndSecondaryText == b.prefersSideBySideTextAndSecondaryText && a.alpha == b.alpha
  }
  public func hash(into hasher: inout Swift.Hasher) {
    hasher.combine(text)
    hasher.combine(secondaryText)
    hasher.combine(image)
  }
}

@available(iOS 14.0, tvOS 14.0, *)
@available(watchOS, unavailable)
extension UIKit.UIListContentConfiguration {
  public static func plainHeader() -> UIKit.UIListContentConfiguration { header() }
  public static func plainFooter() -> UIKit.UIListContentConfiguration { footer() }
  public static func groupedHeader() -> UIKit.UIListContentConfiguration { header() }
  public static func groupedFooter() -> UIKit.UIListContentConfiguration { footer() }
  public static func sidebarCell() -> UIKit.UIListContentConfiguration { cell() }
  public static func sidebarSubtitleCell() -> UIKit.UIListContentConfiguration { subtitleCell() }
  public static func sidebarHeader() -> UIKit.UIListContentConfiguration { prominentInsetGroupedHeader() }
}

/// The view of a list content configuration: an image, then the text over
/// (or beside) the secondary text, inside the configuration's margins.
@available(iOS 14.0, tvOS 14.0, *)
final class _PerryListContentView : UIView, UIKit.UIContentView {
  private var current: UIListContentConfiguration
  private let imageView = UIImageView()
  private let textLabel = UILabel()
  private let secondaryLabel = UILabel()

  var configuration: any UIKit.UIContentConfiguration {
    get { current }
    set {
      guard let configuration = newValue as? UIListContentConfiguration else { return }
      current = configuration
      apply()
    }
  }

  init(_ configuration: UIListContentConfiguration) {
    current = configuration
    super.init(frame: .zero)
    imageView.contentMode = .scaleAspectFit
    addSubview(imageView)
    addSubview(textLabel)
    addSubview(secondaryLabel)
    apply()
  }

  required init?(coder: NSCoder) { nil }

  private func show(_ text: Swift.String?, _ attributed: NSAttributedString?, _ properties: UIListContentConfiguration.TextProperties,
                    in label: UILabel) {
    label.font = properties.font
    label.textColor = properties.resolvedColor()
    label.numberOfLines = properties.numberOfLines
    label.lineBreakMode = properties.lineBreakMode
    switch properties.alignment {
    case .natural: label.textAlignment = .natural
    case .center: label.textAlignment = .center
    case .justified: label.textAlignment = .justified
    }
    if let attributed {
      label.attributedText = attributed
    } else {
      label.text = text.map(properties.transformed)
    }
    label.isHidden = attributed == nil && (text ?? "").isEmpty
  }

  private func apply() {
    imageView.image = current.image
    imageView.isHidden = current.image == nil
    if let tint = current.imageProperties.tintColor { imageView.tintColor = tint }
    show(current.text, current.attributedText, current.textProperties, in: textLabel)
    show(current.secondaryText, current.secondaryAttributedText, current.secondaryTextProperties, in: secondaryLabel)
    alpha = current.alpha
    invalidateIntrinsicContentSize()
    setNeedsLayout()
  }

  /// The image's size within the configuration's limits.
  private var imageSize: CGSize {
    guard let image = current.image else { return .zero }
    var size = image.size
    let limit = current.imageProperties.maximumSize
    if limit.width > 0, size.width > limit.width { size = CGSize(width: limit.width, height: size.height * limit.width / size.width) }
    if limit.height > 0, size.height > limit.height { size = CGSize(width: size.width * limit.height / size.height, height: limit.height) }
    return size
  }

  /// The frames of the image and the two labels at a width, and the height they take.
  private func arrange(width: CGFloat) -> (image: CGRect, text: CGRect, secondary: CGRect, height: CGFloat) {
    let margins = current.directionalLayoutMargins
    let image = imageSize
    var x = margins.leading
    if image.width > 0 { x += image.width + current.imageToTextPadding }
    let room = max(width - x - margins.trailing, 0)
    let fitting = CGSize(width: room, height: .greatestFiniteMagnitude)
    var text = CGRect.zero, secondary = CGRect.zero
    var textHeight: CGFloat = 0
    if current.prefersSideBySideTextAndSecondaryText, !secondaryLabel.isHidden {
      let secondarySize = secondaryLabel.sizeThatFits(fitting)
      let secondaryWidth = min(secondarySize.width, room / 2)
      let primaryWidth = max(room - secondaryWidth - current.textToSecondaryTextHorizontalPadding, 0)
      let primarySize = textLabel.isHidden ? .zero : textLabel.sizeThatFits(CGSize(width: primaryWidth, height: .greatestFiniteMagnitude))
      textHeight = max(primarySize.height, secondarySize.height)
      text = CGRect(x: x, y: margins.top, width: primaryWidth, height: textHeight)
      secondary = CGRect(x: x + room - secondaryWidth, y: margins.top, width: secondaryWidth, height: textHeight)
    } else {
      var y = margins.top
      if !textLabel.isHidden {
        let size = textLabel.sizeThatFits(fitting)
        text = CGRect(x: x, y: y, width: room, height: size.height)
        y += size.height
      }
      if !secondaryLabel.isHidden {
        if !textLabel.isHidden { y += current.textToSecondaryTextVerticalPadding }
        let size = secondaryLabel.sizeThatFits(fitting)
        secondary = CGRect(x: x, y: y, width: room, height: size.height)
        y += size.height
      }
      textHeight = y - margins.top
    }
    let content = max(textHeight, image.height)
    let height = max(content + margins.top + margins.bottom, 44)
    // The text and the image are centered in the height.
    let shift = (height - margins.top - margins.bottom - textHeight) / 2
    text.origin.y += shift
    secondary.origin.y += shift
    let imageFrame = CGRect(x: margins.leading, y: (height - image.height) / 2, width: image.width, height: image.height)
    return (imageFrame, text, secondary, height)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let frames = arrange(width: bounds.width)
    let shift = (bounds.height - frames.height) / 2
    imageView.frame = frames.image.offsetBy(dx: 0, dy: shift)
    textLabel.frame = frames.text.offsetBy(dx: 0, dy: shift)
    secondaryLabel.frame = frames.secondary.offsetBy(dx: 0, dy: shift)
  }

  override func sizeThatFits(_ size: CGSize) -> CGSize {
    CGSize(width: size.width, height: arrange(width: size.width).height)
  }

  override var intrinsicContentSize: CGSize {
    CGSize(width: UIView.noIntrinsicMetric, height: arrange(width: bounds.width > 0 ? bounds.width : 320).height)
  }
}

// MARK: - Cells

/// What a cell was configured with, kept with the cell.
@available(iOS 14.0, tvOS 14.0, *)
@_Concurrency.MainActor private enum _PerryCellConfigurations {
  final class Box {
    var content: (any UIKit.UIContentConfiguration)?
    var contentView: (any UIView & UIKit.UIContentView)?
    var background: UIKit.UIBackgroundConfiguration?
  }
  nonisolated(unsafe) static var key: UInt8 = 0

  static func box(of cell: UIView) -> Box {
    if let box = objc_getAssociatedObject(cell, &key) as? Box { return box }
    let box = Box()
    objc_setAssociatedObject(cell, &key, box, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    return box
  }

  /// Shows the configuration's content view over `container`: the one
  /// there takes the configuration if it can, else another replaces it.
  static func setContent(_ configuration: (any UIKit.UIContentConfiguration)?, of cell: UIView, in container: UIView) {
    let box = box(of: cell)
    box.content = configuration
    guard let configuration else {
      box.contentView?.removeFromSuperview()
      box.contentView = nil
      return
    }
    if let view = box.contentView, view.supports(configuration) {
      view.configuration = configuration
      return
    }
    box.contentView?.removeFromSuperview()
    let view = configuration.makeContentView()
    view.frame = container.bounds
    view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    container.addSubview(view)
    box.contentView = view
  }

  /// Keeps the background configuration and shows its color and corners on the cell.
  static func setBackground(_ configuration: UIKit.UIBackgroundConfiguration?, of cell: UIView) {
    box(of: cell).background = configuration
    guard let configuration else { return }
    if let color = configuration.backgroundColor { cell.backgroundColor = color }
    if configuration.cornerRadius > 0 {
      cell.layer.cornerRadius = configuration.cornerRadius
      cell.layer.masksToBounds = true
    }
  }
}

@available(iOS 14.0, tvOS 14.0, *)
@available(watchOS, unavailable)
extension UICollectionViewCell {
  @_Concurrency.MainActor @preconcurrency public var contentConfiguration: (any UIKit.UIContentConfiguration)? {
    get { _PerryCellConfigurations.box(of: self).content }
    set(config) { _PerryCellConfigurations.setContent(config, of: self, in: contentView) }
  }
  @_Concurrency.MainActor @preconcurrency public var backgroundConfiguration: UIKit.UIBackgroundConfiguration? {
    get { _PerryCellConfigurations.box(of: self).background }
    set { _PerryCellConfigurations.setBackground(newValue, of: self) }
  }
  @_Concurrency.MainActor @preconcurrency public func defaultBackgroundConfiguration() -> UIKit.UIBackgroundConfiguration { .clear() }
}

@available(iOS 14.0, tvOS 14.0, *)
@available(watchOS, unavailable)
extension UITableViewCell {
  @_Concurrency.MainActor @preconcurrency public var contentConfiguration: (any UIKit.UIContentConfiguration)? {
    get { _PerryCellConfigurations.box(of: self).content }
    set(config) { _PerryCellConfigurations.setContent(config, of: self, in: contentView) }
  }
  @_Concurrency.MainActor @preconcurrency public func defaultContentConfiguration() -> UIKit.UIListContentConfiguration { .cell() }
  @_Concurrency.MainActor @preconcurrency public var backgroundConfiguration: UIKit.UIBackgroundConfiguration? {
    get { _PerryCellConfigurations.box(of: self).background }
    set { _PerryCellConfigurations.setBackground(newValue, of: self) }
  }
  @_Concurrency.MainActor @preconcurrency public func defaultBackgroundConfiguration() -> UIKit.UIBackgroundConfiguration { .listCell() }
}

// MARK: - Registrations

@available(iOS 14.0, tvOS 14.0, *)
@available(watchOS, unavailable)
extension UICollectionView {
  /// A cell class with the handler that configures its cells; the
  /// collection view registers the class the first time it dequeues one.
  public struct CellRegistration<Cell, Item> where Cell : UICollectionViewCell {
    public typealias Handler = (_ cell: Cell, _ indexPath: Foundation.IndexPath, _ itemIdentifier: Item) -> Swift.Void
    let identifier = "perry.registration." + UUID().uuidString
    let handler: Handler
    public init(handler: @escaping UICollectionView.CellRegistration<Cell, Item>.Handler) {
      self.handler = handler
    }
  }

  public struct SupplementaryRegistration<Supplementary> where Supplementary : UICollectionReusableView {
    public typealias Handler = (_ supplementaryView: Supplementary, _ elementKind: Swift.String, _ indexPath: Foundation.IndexPath) -> Swift.Void
    let identifier = "perry.registration." + UUID().uuidString
    let elementKind: Swift.String
    let handler: Handler
    public init(elementKind: Swift.String, handler: @escaping UICollectionView.SupplementaryRegistration<Supplementary>.Handler) {
      self.elementKind = elementKind
      self.handler = handler
    }
  }

  /// Whether the identifier is new to the collection view, which is then noted.
  @_Concurrency.MainActor private func _perryNeedsRegistration(_ identifier: Swift.String) -> Swift.Bool {
    let registered: NSMutableSet
    if let set = objc_getAssociatedObject(self, &_perryRegistrationsKey) as? NSMutableSet {
      registered = set
    } else {
      registered = NSMutableSet()
      objc_setAssociatedObject(self, &_perryRegistrationsKey, registered, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    guard !registered.contains(identifier) else { return false }
    registered.add(identifier)
    return true
  }

  @_Concurrency.MainActor @preconcurrency public func dequeueConfiguredReusableCell<Cell, Item>(using registration: UICollectionView.CellRegistration<Cell, Item>, for indexPath: Foundation.IndexPath, item: Item?) -> Cell where Cell : UICollectionViewCell {
    if _perryNeedsRegistration(registration.identifier) {
      register(Cell.self, forCellWithReuseIdentifier: registration.identifier)
    }
    let cell = dequeueReusableCell(withReuseIdentifier: registration.identifier, for: indexPath) as? Cell ?? Cell(frame: .zero)
    if let item { registration.handler(cell, indexPath, item) }
    return cell
  }

  @_Concurrency.MainActor @preconcurrency public func dequeueConfiguredReusableSupplementary<Supplementary>(using registration: UICollectionView.SupplementaryRegistration<Supplementary>, for indexPath: Foundation.IndexPath) -> Supplementary where Supplementary : UICollectionReusableView {
    if _perryNeedsRegistration(registration.identifier) {
      register(Supplementary.self, forSupplementaryViewOfKind: registration.elementKind, withReuseIdentifier: registration.identifier)
    }
    let view = dequeueReusableSupplementaryView(ofKind: registration.elementKind, withReuseIdentifier: registration.identifier,
                                                for: indexPath) as? Supplementary ?? Supplementary(frame: .zero)
    registration.handler(view, registration.elementKind, indexPath)
    return view
  }
}

nonisolated(unsafe) private var _perryRegistrationsKey: UInt8 = 0

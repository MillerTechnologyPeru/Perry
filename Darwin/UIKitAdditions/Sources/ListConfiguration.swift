// Collection view list layouts (iOS 14): the configuration a list section is
// made from and the compositional layouts and sections made from it, which
// iOS keeps in UIKit's Swift module. A list is a compositional section of
// full-width items as tall as their cells measure, with a header and footer
// when the configuration has them, inset by its appearance. Declarations are
// the SDK interface's, for its ABI.

public import Foundation

// MARK: - Separators

@available(iOS 14.5, *)
@available(watchOS, unavailable)
@available(tvOS, unavailable)
public struct UIListSeparatorConfiguration : Swift.Hashable {
  public enum Visibility : Swift.Hashable {
    case automatic
    case visible
    case hidden
    public static func == (a: UIListSeparatorConfiguration.Visibility, b: UIListSeparatorConfiguration.Visibility) -> Swift.Bool {
      switch (a, b) {
      case (.automatic, .automatic), (.visible, .visible), (.hidden, .hidden): return true
      default: return false
      }
    }
    public func hash(into hasher: inout Swift.Hasher) {
      switch self {
      case .automatic: hasher.combine(0)
      case .visible: hasher.combine(1)
      case .hidden: hasher.combine(2)
      }
    }
    public var hashValue: Swift.Int {
      var hasher = Swift.Hasher()
      hash(into: &hasher)
      return hasher.finalize()
    }
  }
  public var topSeparatorVisibility: UIListSeparatorConfiguration.Visibility = .automatic
  public var bottomSeparatorVisibility: UIListSeparatorConfiguration.Visibility = .automatic
  public static let automaticInsets: NSDirectionalEdgeInsets = NSDirectionalEdgeInsets(top: -1, leading: -1, bottom: -1, trailing: -1)
  public var topSeparatorInsets: NSDirectionalEdgeInsets = UIListSeparatorConfiguration.automaticInsets
  public var bottomSeparatorInsets: NSDirectionalEdgeInsets = UIListSeparatorConfiguration.automaticInsets
  public var color: UIColor = .separator
  public var multipleSelectionColor: UIColor = .separator
  @available(iOS 15.0, *)
  @available(watchOS, unavailable)
  @available(tvOS, unavailable)
  public var visualEffect: UIVisualEffect? = nil
  public init(listAppearance: UICollectionLayoutListConfiguration.Appearance) {}
  public static func == (a: UIListSeparatorConfiguration, b: UIListSeparatorConfiguration) -> Swift.Bool {
    a.topSeparatorVisibility == b.topSeparatorVisibility && a.bottomSeparatorVisibility == b.bottomSeparatorVisibility
      && _insetsEqual(a.topSeparatorInsets, b.topSeparatorInsets) && _insetsEqual(a.bottomSeparatorInsets, b.bottomSeparatorInsets)
      && a.color == b.color && a.multipleSelectionColor == b.multipleSelectionColor
  }
  public func hash(into hasher: inout Swift.Hasher) {
    hasher.combine(topSeparatorVisibility)
    hasher.combine(bottomSeparatorVisibility)
    hasher.combine(topSeparatorInsets.top)
    hasher.combine(bottomSeparatorInsets.top)
    hasher.combine(color)
  }
  public var hashValue: Swift.Int {
    var hasher = Swift.Hasher()
    hash(into: &hasher)
    return hasher.finalize()
  }
}

@available(iOS 14.5, *)
@available(watchOS, unavailable)
@available(tvOS, unavailable)
extension UIListSeparatorConfiguration : Swift.CustomStringConvertible, Swift.CustomDebugStringConvertible, Swift.CustomReflectable {
  public var description: Swift.String { "<UIListSeparatorConfiguration top: \(topSeparatorVisibility) bottom: \(bottomSeparatorVisibility)>" }
  public var debugDescription: Swift.String { description }
  public var customMirror: Swift.Mirror { Swift.Mirror(self, children: [], displayStyle: .struct) }
}

// MARK: - The configuration

@available(iOS 14.0, tvOS 14.0, *)
@available(watchOS, unavailable)
public struct UICollectionLayoutListConfiguration {
  public enum Appearance {
    case plain
    case grouped
    @available(tvOS, unavailable)
    case insetGrouped
    @available(tvOS, unavailable)
    case sidebar
    @available(tvOS, unavailable)
    case sidebarPlain
    public static func == (a: UICollectionLayoutListConfiguration.Appearance, b: UICollectionLayoutListConfiguration.Appearance) -> Swift.Bool {
      a.index == b.index
    }
    public func hash(into hasher: inout Swift.Hasher) { hasher.combine(index) }
    public var hashValue: Swift.Int {
      var hasher = Swift.Hasher()
      hash(into: &hasher)
      return hasher.finalize()
    }
    var index: Int {
      switch self {
      case .plain: return 0
      case .grouped: return 1
      case .insetGrouped: return 2
      case .sidebar: return 3
      case .sidebarPlain: return 4
      }
    }
  }
  public enum HeaderMode {
    case none, supplementary, firstItemInSection
    public static func == (a: UICollectionLayoutListConfiguration.HeaderMode, b: UICollectionLayoutListConfiguration.HeaderMode) -> Swift.Bool {
      a.index == b.index
    }
    public func hash(into hasher: inout Swift.Hasher) { hasher.combine(index) }
    public var hashValue: Swift.Int {
      var hasher = Swift.Hasher()
      hash(into: &hasher)
      return hasher.finalize()
    }
    var index: Int {
      switch self {
      case .none: return 0
      case .supplementary: return 1
      case .firstItemInSection: return 2
      }
    }
  }
  public enum FooterMode {
    case none, supplementary
    public static func == (a: UICollectionLayoutListConfiguration.FooterMode, b: UICollectionLayoutListConfiguration.FooterMode) -> Swift.Bool {
      a.index == b.index
    }
    public func hash(into hasher: inout Swift.Hasher) { hasher.combine(index) }
    public var hashValue: Swift.Int {
      var hasher = Swift.Hasher()
      hash(into: &hasher)
      return hasher.finalize()
    }
    var index: Int {
      switch self {
      case .none: return 0
      case .supplementary: return 1
      }
    }
  }
  @available(tvOS, unavailable)
  public typealias SwipeActionsConfigurationProvider = (_ indexPath: Foundation.IndexPath) -> UISwipeActionsConfiguration?
  @available(iOS 14.5, *)
  @available(watchOS, unavailable)
  @available(tvOS, unavailable)
  public typealias ItemSeparatorHandler = (_ itemIndexPath: Foundation.IndexPath, _ sectionSeparatorConfiguration: UIListSeparatorConfiguration) -> UIListSeparatorConfiguration

  public init(appearance: UICollectionLayoutListConfiguration.Appearance) {
    self.appearance = appearance
    if #available(iOS 14.5, *) { separatorConfiguration = UIListSeparatorConfiguration(listAppearance: appearance) }
  }
  public private(set) var appearance: UICollectionLayoutListConfiguration.Appearance
  @available(tvOS, unavailable)
  public var showsSeparators: Swift.Bool = true
  @available(iOS 14.5, *)
  @available(watchOS, unavailable)
  @available(tvOS, unavailable)
  public var separatorConfiguration: UIListSeparatorConfiguration {
    get { _separatorConfiguration ?? UIListSeparatorConfiguration(listAppearance: appearance) }
    set { _separatorConfiguration = newValue }
  }
  var _separatorConfiguration: UIListSeparatorConfiguration?
  @available(iOS 14.5, *)
  @available(watchOS, unavailable)
  @available(tvOS, unavailable)
  public var itemSeparatorHandler: UICollectionLayoutListConfiguration.ItemSeparatorHandler? = nil
  public var backgroundColor: UIColor? = nil
  @available(tvOS, unavailable)
  public var leadingSwipeActionsConfigurationProvider: UICollectionLayoutListConfiguration.SwipeActionsConfigurationProvider? = nil
  @available(tvOS, unavailable)
  public var trailingSwipeActionsConfigurationProvider: UICollectionLayoutListConfiguration.SwipeActionsConfigurationProvider? = nil
  public var headerMode: UICollectionLayoutListConfiguration.HeaderMode = .none
  public var footerMode: UICollectionLayoutListConfiguration.FooterMode = .none
  @available(iOS 15.0, tvOS 15.0, *)
  @available(watchOS, unavailable)
  public var headerTopPadding: CoreFoundation.CGFloat? = nil
}

@available(iOS 18.0, tvOS 18.0, visionOS 2.0, *)
@available(watchOS, unavailable)
extension UICollectionLayoutListConfiguration {
  public struct ContentHuggingElements : Swift.OptionSet {
    public let rawValue: Swift.Int
    public init(rawValue: Swift.Int) { self.rawValue = rawValue }
    public static let supplementaryHeader: UICollectionLayoutListConfiguration.ContentHuggingElements = .init(rawValue: 1)
    @available(iOS 18.0, tvOS 18.0, visionOS 2.0, *)
    @available(watchOS, unavailable)
    public typealias ArrayLiteralElement = UICollectionLayoutListConfiguration.ContentHuggingElements
    @available(iOS 18.0, tvOS 18.0, visionOS 2.0, *)
    @available(watchOS, unavailable)
    public typealias Element = UICollectionLayoutListConfiguration.ContentHuggingElements
    @available(iOS 18.0, tvOS 18.0, visionOS 2.0, *)
    @available(watchOS, unavailable)
    public typealias RawValue = Swift.Int
  }
  /// Kept nowhere: lists here always size their supplementary headers as
  /// they measure.
  public var contentHuggingElements: UICollectionLayoutListConfiguration.ContentHuggingElements {
    get { [] }
    set {}
  }
}

// MARK: - Layouts and sections

/// The block a list section asks for a row's separators: the top one's
/// leading and trailing insets as the result's top and left, the bottom's as
/// its bottom and right, a leading inset of -1 for none.
private func listSeparators(_ configuration: UICollectionLayoutListConfiguration) -> @convention(block) (Int, Int, Int) -> UIEdgeInsets {
  { section, item, count in
    var separators = configuration.separatorConfiguration
    if let handler = configuration.itemSeparatorHandler {
      separators = handler(IndexPath(indexes: [section, item]), separators)
    }
    let sidebar = configuration.appearance == .sidebar || configuration.appearance == .sidebarPlain
    func leading(_ visibility: UIListSeparatorConfiguration.Visibility, _ automatic: Bool, _ insets: NSDirectionalEdgeInsets) -> CGFloat {
      switch visibility {
      case .hidden: return -1
      case .automatic where !automatic || !configuration.showsSeparators || sidebar: return -1
      default: return insets.leading < 0 ? 16 : insets.leading
      }
    }
    let top = separators.topSeparatorInsets, bottom = separators.bottomSeparatorInsets
    return UIEdgeInsets(
      top: leading(separators.topSeparatorVisibility, false, top), left: max(top.trailing, 0),
      bottom: leading(separators.bottomSeparatorVisibility, item < count - 1, bottom), right: max(bottom.trailing, 0))
  }
}

@available(iOS 14.0, tvOS 14.0, *)
@available(watchOS, unavailable)
extension UICollectionViewCompositionalLayout {
  @_Concurrency.MainActor @preconcurrency public static func list(using configuration: UICollectionLayoutListConfiguration) -> UICollectionViewCompositionalLayout {
    UICollectionViewCompositionalLayout { _, environment in
      NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
    }
  }
}

@available(iOS 14.0, tvOS 14.0, *)
@available(watchOS, unavailable)
extension NSCollectionLayoutSection {
  @_Concurrency.MainActor @preconcurrency public static func list(using configuration: UICollectionLayoutListConfiguration, layoutEnvironment: any NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
    let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(44))
    let item = NSCollectionLayoutItem(layoutSize: size)
    let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [item])
    let section = NSCollectionLayoutSection(group: group)
    switch configuration.appearance {
    case .insetGrouped:
      section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 16, trailing: 16)
    case .sidebar, .sidebarPlain:
      section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
    case .plain, .grouped:
      section.contentInsets = .zero
    @unknown default:
      section.contentInsets = .zero
    }
    var supplementaries: [NSCollectionLayoutBoundarySupplementaryItem] = []
    let supplementarySize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(44))
    if configuration.headerMode == .supplementary {
      supplementaries.append(NSCollectionLayoutBoundarySupplementaryItem(
        layoutSize: supplementarySize, elementKind: UICollectionView.elementKindSectionHeader, alignment: .top))
    }
    if configuration.footerMode == .supplementary {
      supplementaries.append(NSCollectionLayoutBoundarySupplementaryItem(
        layoutSize: supplementarySize, elementKind: UICollectionView.elementKindSectionFooter, alignment: .bottom))
    }
    section.boundarySupplementaryItems = supplementaries
    if configuration.appearance == .insetGrouped { section.perform(NSSelectorFromString("_perrySetListRounded")) }
    section.perform(NSSelectorFromString("_perrySetListSeparators:"), with: unsafeBitCast(listSeparators(configuration), to: AnyObject.self))
    return section
  }
}

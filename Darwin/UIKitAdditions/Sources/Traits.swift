// UIKit's trait API from iOS 17, which iOS keeps in UIKit's Swift module
// and Perry's UIKit, whose Swift overlay predates it, lacks: the traits as
// types (UITraitDefinition), the mutable traits a trait collection is made
// from, and the SPI SwiftUI makes its hosting views' trait collections
// with. Declarations are the SDK interface's, for its ABI; a trait
// collection is made from Perry's UITraitCollection, trait by trait.

public import Foundation
public import CoreGraphics
public import _UIKitPrivate

// MARK: - Definitions

@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
public protocol UITraitDefinition {
  associatedtype Value
  static var defaultValue: Self.Value { get }
  static var identifier: Swift.String { get }
  static var name: Swift.String { get }
  static var affectsColorAppearance: Swift.Bool { get }
  static var _defaultValueRepresentsUnspecified: Swift.Bool { get }
  static var _isPrivate: Swift.Bool { get }
}

@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
public typealias UITrait = any UIKit.UITraitDefinition.Type

@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UITraitDefinition {
  public static var identifier: Swift.String { "\(Self.self)" }
  public static var name: Swift.String { "\(Self.self)" }
  public static var affectsColorAppearance: Swift.Bool { false }
  public static var _defaultValueRepresentsUnspecified: Swift.Bool { false }
  public static var _isPrivate: Swift.Bool { false }
}

@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
public protocol _UICustomRawRepresentableTraitDefinition : UIKit.UITraitDefinition {
  associatedtype _CustomRawValue
  static func _customRawValue(for value: Self.Value) -> Self._CustomRawValue
  static func _value(from customRawValue: Self._CustomRawValue) -> Self.Value?
}

// MARK: - Mutable traits

@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
public protocol UIMutableTraits {
  subscript<T>(trait: T.Type) -> T.Value where T : UIKit.UITraitDefinition { get set }
  subscript<T>(trait: T.Type) -> T.Value where T : UIKit.UITraitDefinition, T.Value == CoreFoundation.CGFloat { get set }
  subscript<T>(trait: T.Type) -> T.Value where T : UIKit.UITraitDefinition, T.Value == CoreFoundation.CGFloat? { get set }
  subscript<T>(trait: T.Type) -> T.Value where T : UIKit.UITraitDefinition, T.Value == Swift.Double { get set }
  subscript<T>(trait: T.Type) -> T.Value where T : UIKit.UITraitDefinition, T.Value == Swift.Double? { get set }
  subscript<T>(trait: T.Type) -> T.Value where T : UIKit.UITraitDefinition, T.Value == Swift.Int { get set }
  subscript<T>(trait: T.Type) -> T.Value where T : UIKit.UITraitDefinition, T.Value == Swift.Int? { get set }
  subscript<T>(trait: T.Type) -> T.Value where T : UIKit.UITraitDefinition, T.Value == Swift.Bool { get set }
  subscript<T>(trait: T.Type) -> T.Value where T : UIKit._UICustomRawRepresentableTraitDefinition { get set }
  subscript<T>(trait: T.Type) -> T.Value where T : UIKit._UICustomRawRepresentableTraitDefinition, T._CustomRawValue == CoreFoundation.CGFloat { get set }
  subscript<T>(trait: T.Type) -> T.Value where T : UIKit._UICustomRawRepresentableTraitDefinition, T._CustomRawValue == Swift.Double { get set }
  subscript<T>(trait: T.Type) -> T.Value where T : UIKit._UICustomRawRepresentableTraitDefinition, T._CustomRawValue == Swift.Int { get set }
  subscript<T>(trait: T.Type) -> T.Value where T : UIKit.UITraitDefinition, T.Value : Swift.RawRepresentable { get set }
  subscript<T>(trait: T.Type) -> T.Value where T : UIKit.UITraitDefinition, T.Value : Swift.RawRepresentable, T.Value.RawValue == CoreFoundation.CGFloat { get set }
  subscript<T>(trait: T.Type) -> T.Value where T : UIKit.UITraitDefinition, T.Value : Swift.RawRepresentable, T.Value.RawValue == Swift.Double { get set }
  subscript<T>(trait: T.Type) -> T.Value where T : UIKit.UITraitDefinition, T.Value : Swift.RawRepresentable, T.Value.RawValue == Swift.Int { get set }
}

/// Traits being changed: each by its identifier, over a collection's.
@available(iOS 17.0, tvOS 17.0, *)
struct _PerryMutableTraits : UIKit.UIMutableTraits {
  var values: [Swift.String: Any] = [:]

  private func value<T: UIKit.UITraitDefinition>(_ trait: T.Type) -> T.Value {
    values[T.identifier] as? T.Value ?? T.defaultValue
  }
  private mutating func set<T: UIKit.UITraitDefinition>(_ trait: T.Type, _ value: T.Value) {
    values[T.identifier] = value
  }

  subscript<T>(trait: T.Type) -> T.Value where T : UIKit.UITraitDefinition {
    get { value(trait) }
    set { set(trait, newValue) }
  }
  subscript<T>(trait: T.Type) -> T.Value where T : UIKit.UITraitDefinition, T.Value == CoreFoundation.CGFloat {
    get { value(trait) }
    set { set(trait, newValue) }
  }
  subscript<T>(trait: T.Type) -> T.Value where T : UIKit.UITraitDefinition, T.Value == CoreFoundation.CGFloat? {
    get { value(trait) }
    set { set(trait, newValue) }
  }
  subscript<T>(trait: T.Type) -> T.Value where T : UIKit.UITraitDefinition, T.Value == Swift.Double {
    get { value(trait) }
    set { set(trait, newValue) }
  }
  subscript<T>(trait: T.Type) -> T.Value where T : UIKit.UITraitDefinition, T.Value == Swift.Double? {
    get { value(trait) }
    set { set(trait, newValue) }
  }
  subscript<T>(trait: T.Type) -> T.Value where T : UIKit.UITraitDefinition, T.Value == Swift.Int {
    get { value(trait) }
    set { set(trait, newValue) }
  }
  subscript<T>(trait: T.Type) -> T.Value where T : UIKit.UITraitDefinition, T.Value == Swift.Int? {
    get { value(trait) }
    set { set(trait, newValue) }
  }
  subscript<T>(trait: T.Type) -> T.Value where T : UIKit.UITraitDefinition, T.Value == Swift.Bool {
    get { value(trait) }
    set { set(trait, newValue) }
  }
  subscript<T>(trait: T.Type) -> T.Value where T : UIKit._UICustomRawRepresentableTraitDefinition {
    get { value(trait) }
    set { set(trait, newValue) }
  }
  subscript<T>(trait: T.Type) -> T.Value where T : UIKit._UICustomRawRepresentableTraitDefinition, T._CustomRawValue == CoreFoundation.CGFloat {
    get { value(trait) }
    set { set(trait, newValue) }
  }
  subscript<T>(trait: T.Type) -> T.Value where T : UIKit._UICustomRawRepresentableTraitDefinition, T._CustomRawValue == Swift.Double {
    get { value(trait) }
    set { set(trait, newValue) }
  }
  subscript<T>(trait: T.Type) -> T.Value where T : UIKit._UICustomRawRepresentableTraitDefinition, T._CustomRawValue == Swift.Int {
    get { value(trait) }
    set { set(trait, newValue) }
  }
  subscript<T>(trait: T.Type) -> T.Value where T : UIKit.UITraitDefinition, T.Value : Swift.RawRepresentable {
    get { value(trait) }
    set { set(trait, newValue) }
  }
  subscript<T>(trait: T.Type) -> T.Value where T : UIKit.UITraitDefinition, T.Value : Swift.RawRepresentable, T.Value.RawValue == CoreFoundation.CGFloat {
    get { value(trait) }
    set { set(trait, newValue) }
  }
  subscript<T>(trait: T.Type) -> T.Value where T : UIKit.UITraitDefinition, T.Value : Swift.RawRepresentable, T.Value.RawValue == Swift.Double {
    get { value(trait) }
    set { set(trait, newValue) }
  }
  subscript<T>(trait: T.Type) -> T.Value where T : UIKit.UITraitDefinition, T.Value : Swift.RawRepresentable, T.Value.RawValue == Swift.Int {
    get { value(trait) }
    set { set(trait, newValue) }
  }
}

// MARK: - System traits

@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
public struct UITraitUserInterfaceStyle : UIKit.UITraitDefinition {
  public static let defaultValue: UIUserInterfaceStyle = .unspecified
  public static let name: Swift.String = "UserInterfaceStyle"
  public static let identifier: Swift.String = "UITraitUserInterfaceStyle"
  public static let affectsColorAppearance: Swift.Bool = true
  public static let _defaultValueRepresentsUnspecified: Swift.Bool = true
  public static let _isPrivate: Swift.Bool = false
  @available(iOS 17.0, tvOS 17.0, *)
  @available(watchOS, unavailable)
  public typealias Value = UIUserInterfaceStyle
}
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIMutableTraits {
  public var userInterfaceStyle: UIUserInterfaceStyle {
    get { self[UITraitUserInterfaceStyle.self] }
    set { self[UITraitUserInterfaceStyle.self] = newValue }
  }
}

@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
public struct UITraitLayoutDirection : UIKit.UITraitDefinition {
  public static let defaultValue: UITraitEnvironmentLayoutDirection = .unspecified
  public static let name: Swift.String = "LayoutDirection"
  public static let identifier: Swift.String = "UITraitLayoutDirection"
  public static let affectsColorAppearance: Swift.Bool = false
  public static let _defaultValueRepresentsUnspecified: Swift.Bool = true
  public static let _isPrivate: Swift.Bool = false
  @available(iOS 17.0, tvOS 17.0, *)
  @available(watchOS, unavailable)
  public typealias Value = UITraitEnvironmentLayoutDirection
}
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIMutableTraits {
  public var layoutDirection: UITraitEnvironmentLayoutDirection {
    get { self[UITraitLayoutDirection.self] }
    set { self[UITraitLayoutDirection.self] = newValue }
  }
}

@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
public struct UITraitDisplayScale : UIKit.UITraitDefinition {
  public static let defaultValue: CoreFoundation.CGFloat = 0
  public static let name: Swift.String = "DisplayScale"
  public static let identifier: Swift.String = "UITraitDisplayScale"
  public static let affectsColorAppearance: Swift.Bool = false
  public static let _defaultValueRepresentsUnspecified: Swift.Bool = true
  public static let _isPrivate: Swift.Bool = false
  @available(iOS 17.0, tvOS 17.0, *)
  @available(watchOS, unavailable)
  public typealias Value = CoreFoundation.CGFloat
}
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIMutableTraits {
  public var displayScale: CoreFoundation.CGFloat {
    get { self[UITraitDisplayScale.self] }
    set { self[UITraitDisplayScale.self] = newValue }
  }
}

@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
public struct UITraitHorizontalSizeClass : UIKit.UITraitDefinition {
  public static let defaultValue: UIUserInterfaceSizeClass = .unspecified
  public static let name: Swift.String = "HorizontalSizeClass"
  public static let identifier: Swift.String = "UITraitHorizontalSizeClass"
  public static let affectsColorAppearance: Swift.Bool = false
  public static let _defaultValueRepresentsUnspecified: Swift.Bool = true
  public static let _isPrivate: Swift.Bool = false
  @available(iOS 17.0, tvOS 17.0, *)
  @available(watchOS, unavailable)
  public typealias Value = UIUserInterfaceSizeClass
}
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIMutableTraits {
  public var horizontalSizeClass: UIUserInterfaceSizeClass {
    get { self[UITraitHorizontalSizeClass.self] }
    set { self[UITraitHorizontalSizeClass.self] = newValue }
  }
}

@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
public struct UITraitVerticalSizeClass : UIKit.UITraitDefinition {
  public static let defaultValue: UIUserInterfaceSizeClass = .unspecified
  public static let name: Swift.String = "VerticalSizeClass"
  public static let identifier: Swift.String = "UITraitVerticalSizeClass"
  public static let affectsColorAppearance: Swift.Bool = false
  public static let _defaultValueRepresentsUnspecified: Swift.Bool = true
  public static let _isPrivate: Swift.Bool = false
  @available(iOS 17.0, tvOS 17.0, *)
  @available(watchOS, unavailable)
  public typealias Value = UIUserInterfaceSizeClass
}
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIMutableTraits {
  public var verticalSizeClass: UIUserInterfaceSizeClass {
    get { self[UITraitVerticalSizeClass.self] }
    set { self[UITraitVerticalSizeClass.self] = newValue }
  }
}

@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
public struct UITraitPreferredContentSizeCategory : UIKit.UITraitDefinition {
  public static let defaultValue: UIContentSizeCategory = .unspecified
  public static let name: Swift.String = "PreferredContentSizeCategory"
  public static let identifier: Swift.String = "UITraitPreferredContentSizeCategory"
  public static let affectsColorAppearance: Swift.Bool = false
  public static let _defaultValueRepresentsUnspecified: Swift.Bool = true
  public static let _isPrivate: Swift.Bool = false
  @available(iOS 17.0, tvOS 17.0, *)
  @available(watchOS, unavailable)
  public typealias Value = UIContentSizeCategory
}
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIMutableTraits {
  public var preferredContentSizeCategory: UIContentSizeCategory {
    get { self[UITraitPreferredContentSizeCategory.self] }
    set { self[UITraitPreferredContentSizeCategory.self] = newValue }
  }
}

@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
public struct UITraitDisplayGamut : UIKit.UITraitDefinition {
  public static let defaultValue: UIDisplayGamut = .unspecified
  public static let name: Swift.String = "DisplayGamut"
  public static let identifier: Swift.String = "UITraitDisplayGamut"
  public static let affectsColorAppearance: Swift.Bool = true
  public static let _defaultValueRepresentsUnspecified: Swift.Bool = true
  public static let _isPrivate: Swift.Bool = false
  @available(iOS 17.0, tvOS 17.0, *)
  @available(watchOS, unavailable)
  public typealias Value = UIDisplayGamut
}
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIMutableTraits {
  public var displayGamut: UIDisplayGamut {
    get { self[UITraitDisplayGamut.self] }
    set { self[UITraitDisplayGamut.self] = newValue }
  }
}

@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
public struct UITraitAccessibilityContrast : UIKit.UITraitDefinition {
  public static let defaultValue: UIAccessibilityContrast = .unspecified
  public static let name: Swift.String = "AccessibilityContrast"
  public static let identifier: Swift.String = "UITraitAccessibilityContrast"
  public static let affectsColorAppearance: Swift.Bool = true
  public static let _defaultValueRepresentsUnspecified: Swift.Bool = true
  public static let _isPrivate: Swift.Bool = false
  @available(iOS 17.0, tvOS 17.0, *)
  @available(watchOS, unavailable)
  public typealias Value = UIAccessibilityContrast
}
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIMutableTraits {
  public var accessibilityContrast: UIAccessibilityContrast {
    get { self[UITraitAccessibilityContrast.self] }
    set { self[UITraitAccessibilityContrast.self] = newValue }
  }
}

@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
public struct UITraitUserInterfaceLevel : UIKit.UITraitDefinition {
  public static let defaultValue: UIUserInterfaceLevel = .unspecified
  public static let name: Swift.String = "UserInterfaceLevel"
  public static let identifier: Swift.String = "UITraitUserInterfaceLevel"
  public static let affectsColorAppearance: Swift.Bool = true
  public static let _defaultValueRepresentsUnspecified: Swift.Bool = true
  public static let _isPrivate: Swift.Bool = false
  @available(iOS 17.0, tvOS 17.0, *)
  @available(watchOS, unavailable)
  public typealias Value = UIUserInterfaceLevel
}
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIMutableTraits {
  public var userInterfaceLevel: UIUserInterfaceLevel {
    get { self[UITraitUserInterfaceLevel.self] }
    set { self[UITraitUserInterfaceLevel.self] = newValue }
  }
}

@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
public struct UITraitActiveAppearance : UIKit.UITraitDefinition {
  public static let defaultValue: UIUserInterfaceActiveAppearance = .unspecified
  public static let name: Swift.String = "ActiveAppearance"
  public static let identifier: Swift.String = "UITraitActiveAppearance"
  public static let affectsColorAppearance: Swift.Bool = true
  public static let _defaultValueRepresentsUnspecified: Swift.Bool = true
  public static let _isPrivate: Swift.Bool = false
  @available(iOS 17.0, tvOS 17.0, *)
  @available(watchOS, unavailable)
  public typealias Value = UIUserInterfaceActiveAppearance
}
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIMutableTraits {
  public var activeAppearance: UIUserInterfaceActiveAppearance {
    get { self[UITraitActiveAppearance.self] }
    set { self[UITraitActiveAppearance.self] = newValue }
  }
}

@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
public struct UITraitTypesettingLanguage : UIKit.UITraitDefinition {
  public static let defaultValue: Foundation.Locale.Language? = nil
  public static let name: Swift.String = "TypesettingLanguage"
  public static let identifier: Swift.String = "UITraitTypesettingLanguage"
  public static let _defaultValueRepresentsUnspecified: Swift.Bool = true
  public static let _isPrivate: Swift.Bool = false
  @available(iOS 17.0, tvOS 17.0, *)
  @available(watchOS, unavailable)
  public typealias Value = Foundation.Locale.Language?
}
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UITraitCollection {
  /// Perry's trait collections have no typesetting language.
  public var typesettingLanguage: Foundation.Locale.Language? {
    get { nil }
  }
  convenience public init(typesettingLanguage: Foundation.Locale.Language?) {
    self.init(traitsFrom: [])
  }
}
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UITraitTypesettingLanguage : UIKit._UICustomRawRepresentableTraitDefinition {
  public static func _customRawValue(for value: Foundation.Locale.Language?) -> Swift.String? { value?.minimalIdentifier }
  public static func _value(from customRawValue: Swift.String?) -> Foundation.Locale.Language?? {
    .some(customRawValue.map { Foundation.Locale.Language(identifier: $0) })
  }
  @available(iOS 17.0, tvOS 17.0, *)
  @available(watchOS, unavailable)
  public typealias _CustomRawValue = Swift.String?
}
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIMutableTraits {
  public var typesettingLanguage: Foundation.Locale.Language? {
    get { self[UITraitTypesettingLanguage.self] }
    set { self[UITraitTypesettingLanguage.self] = newValue }
  }
}

// MARK: - SPI SwiftUI uses

/// The vibrancy a trait collection's colors take: SwiftUI's hosting views set it.
@available(iOS 17.0, tvOS 17.0, *)
struct _UITraitVibrancy : UIKit.UITraitDefinition {
  static let defaultValue: _UIUserInterfaceVibrancy = .init(rawValue: 0)!
}
@available(iOS 17.0, tvOS 17.0, *)
extension UIKit.UIMutableTraits {
  public var _vibrancy: _UIUserInterfaceVibrancy {
    get { self[_UITraitVibrancy.self] }
    set { self[_UITraitVibrancy.self] = newValue }
  }
}

@available(iOS 17.0, tvOS 17.0, *)
extension UITraitCollection {
  /// The collection with `mutations` made: its traits Perry's
  /// UITraitCollection holds, then the changed ones over them.
  public func _modifyingTraits(environmentWrapper: NSObject?, mutations: (inout any UIKit.UIMutableTraits) -> Swift.Void) -> UITraitCollection {
    var traits: any UIKit.UIMutableTraits = _PerryMutableTraits()
    mutations(&traits)
    let changed = (traits as? _PerryMutableTraits)?.values ?? [:]
    guard !changed.isEmpty else { return self }
    var collections = [self]
    if let style = changed[UITraitUserInterfaceStyle.identifier] as? UIUserInterfaceStyle {
      collections.append(UITraitCollection(userInterfaceStyle: style))
    }
    if let direction = changed[UITraitLayoutDirection.identifier] as? UITraitEnvironmentLayoutDirection {
      collections.append(UITraitCollection(layoutDirection: direction))
    }
    if let scale = changed[UITraitDisplayScale.identifier] as? CoreFoundation.CGFloat, scale > 0 {
      collections.append(UITraitCollection(displayScale: scale))
    }
    if let size = changed[UITraitHorizontalSizeClass.identifier] as? UIUserInterfaceSizeClass {
      collections.append(UITraitCollection(horizontalSizeClass: size))
    }
    if let size = changed[UITraitVerticalSizeClass.identifier] as? UIUserInterfaceSizeClass {
      collections.append(UITraitCollection(verticalSizeClass: size))
    }
    if let category = changed[UITraitPreferredContentSizeCategory.identifier] as? UIContentSizeCategory {
      collections.append(UITraitCollection(preferredContentSizeCategory: category))
    }
    return UITraitCollection(traitsFrom: collections)
  }
}

// UIKit's newer Swift API on views and menus that iOS keeps in UIKit's
// Swift module: corner configurations, the regions a view's surroundings
// reserve, the spring animation with a duration and bounce, and smaller
// members. Declarations are the SDK interface's, for its ABI.

public import Foundation
public import CoreGraphics
public import _UIKitPrivate

// MARK: - Corners

/// A corner's radius: a number of points, or as much as keeps the corner
/// concentric with the view's container, which Perry does not work out and
/// takes as the minimum given (or nothing).
@available(iOS 26.0, tvOS 26.0, *)
@available(watchOS, unavailable)
public struct UICornerRadius : Swift.Equatable, Swift.Hashable, Swift.ExpressibleByFloatLiteral, Swift.ExpressibleByIntegerLiteral, Swift.CustomStringConvertible {
  var points: Swift.Double
  var concentric = false

  public static func fixed(_ radius: Swift.Double) -> UIKit.UICornerRadius { UICornerRadius(points: radius) }
  public static func containerConcentric(minimum: CoreFoundation.CGFloat? = nil) -> UIKit.UICornerRadius {
    UICornerRadius(points: Swift.Double(minimum ?? 0), concentric: true)
  }
  public init(floatLiteral value: Swift.FloatLiteralType) { points = value }
  public init(integerLiteral value: Swift.IntegerLiteralType) { points = Swift.Double(value) }
  init(points: Swift.Double, concentric: Swift.Bool = false) {
    self.points = points
    self.concentric = concentric
  }
  public var description: Swift.String { concentric ? "containerConcentric(minimum: \(points))" : "fixed(\(points))" }
  public typealias FloatLiteralType = Swift.FloatLiteralType
  public typealias IntegerLiteralType = Swift.IntegerLiteralType
}

/// The radii of a view's four corners, or a capsule's.
@available(iOS 26.0, tvOS 26.0, *)
@available(watchOS, unavailable)
public struct UICornerConfiguration : Swift.Equatable, Swift.Hashable, Swift.CustomStringConvertible {
  var topLeft: UIKit.UICornerRadius?
  var topRight: UIKit.UICornerRadius?
  var bottomLeft: UIKit.UICornerRadius?
  var bottomRight: UIKit.UICornerRadius?
  /// A capsule: half the shorter side, up to this radius when one is given.
  var capsule = false
  var capsuleMaximum: Swift.Double?

  public static func corners(radius: UIKit.UICornerRadius) -> UIKit.UICornerConfiguration {
    UICornerConfiguration(topLeft: radius, topRight: radius, bottomLeft: radius, bottomRight: radius)
  }
  public static func corners(topLeftRadius: UIKit.UICornerRadius?, topRightRadius: UIKit.UICornerRadius?, bottomLeftRadius: UIKit.UICornerRadius?, bottomRightRadius: UIKit.UICornerRadius?) -> UIKit.UICornerConfiguration {
    UICornerConfiguration(topLeft: topLeftRadius, topRight: topRightRadius, bottomLeft: bottomLeftRadius, bottomRight: bottomRightRadius)
  }
  public static func capsule(maximumRadius: Swift.Double? = nil) -> UIKit.UICornerConfiguration {
    UICornerConfiguration(capsule: true, capsuleMaximum: maximumRadius)
  }
  public static func uniformCorners(radius: UIKit.UICornerRadius) -> UIKit.UICornerConfiguration { corners(radius: radius) }
  public static func uniformEdges(topRadius: UIKit.UICornerRadius, bottomRadius: UIKit.UICornerRadius) -> UIKit.UICornerConfiguration {
    UICornerConfiguration(topLeft: topRadius, topRight: topRadius, bottomLeft: bottomRadius, bottomRight: bottomRadius)
  }
  public static func uniformEdges(leftRadius: UIKit.UICornerRadius, rightRadius: UIKit.UICornerRadius) -> UIKit.UICornerConfiguration {
    UICornerConfiguration(topLeft: leftRadius, topRight: rightRadius, bottomLeft: leftRadius, bottomRight: rightRadius)
  }
  public static func uniformTopRadius(_ topRadius: UIKit.UICornerRadius, bottomLeftRadius: UIKit.UICornerRadius? = nil, bottomRightRadius: UIKit.UICornerRadius? = nil) -> UIKit.UICornerConfiguration {
    UICornerConfiguration(topLeft: topRadius, topRight: topRadius, bottomLeft: bottomLeftRadius, bottomRight: bottomRightRadius)
  }
  public static func uniformBottomRadius(_ bottomRadius: UIKit.UICornerRadius, topLeftRadius: UIKit.UICornerRadius? = nil, topRightRadius: UIKit.UICornerRadius? = nil) -> UIKit.UICornerConfiguration {
    UICornerConfiguration(topLeft: topLeftRadius, topRight: topRightRadius, bottomLeft: bottomRadius, bottomRight: bottomRadius)
  }
  public static func uniformLeftRadius(_ leftRadius: UIKit.UICornerRadius, topRightRadius: UIKit.UICornerRadius? = nil, bottomRightRadius: UIKit.UICornerRadius? = nil) -> UIKit.UICornerConfiguration {
    UICornerConfiguration(topLeft: leftRadius, topRight: topRightRadius, bottomLeft: leftRadius, bottomRight: bottomRightRadius)
  }
  public static func uniformRightRadius(_ rightRadius: UIKit.UICornerRadius, topLeftRadius: UIKit.UICornerRadius? = nil, bottomLeftRadius: UIKit.UICornerRadius? = nil) -> UIKit.UICornerConfiguration {
    UICornerConfiguration(topLeft: topLeftRadius, topRight: rightRadius, bottomLeft: bottomLeftRadius, bottomRight: rightRadius)
  }
  public var description: Swift.String {
    capsule ? "capsule" : "corners(\(String(describing: topLeft)), \(String(describing: topRight)), \(String(describing: bottomLeft)), \(String(describing: bottomRight)))"
  }
}

@available(iOS 26.0, tvOS 26.0, *)
private final class _PerryCornerBox { var configuration = UICornerConfiguration() }
nonisolated(unsafe) private var _perryCornerKey: UInt8 = 0

@available(iOS 26.0, tvOS 26.0, *)
@available(watchOS, unavailable)
extension UIView {
  /// The view's corners. The layer has one radius: it takes the largest of
  /// the four, on the corners that have one; a capsule takes half the
  /// view's shorter side as it is when set, and does not follow its size.
  @_Concurrency.MainActor @preconcurrency public var cornerConfiguration: UIKit.UICornerConfiguration {
    get { (objc_getAssociatedObject(self, &_perryCornerKey) as? _PerryCornerBox)?.configuration ?? UICornerConfiguration() }
    set {
      let box = _PerryCornerBox()
      box.configuration = newValue
      objc_setAssociatedObject(self, &_perryCornerKey, box, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
      if newValue.capsule {
        let half = Swift.Double(min(bounds.width, bounds.height)) / 2
        layer.cornerRadius = CGFloat(newValue.capsuleMaximum.map { min($0, half) } ?? half)
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        return
      }
      let corners: [(UICornerRadius?, CACornerMask)] = [
        (newValue.topLeft, .layerMinXMinYCorner), (newValue.topRight, .layerMaxXMinYCorner),
        (newValue.bottomLeft, .layerMinXMaxYCorner), (newValue.bottomRight, .layerMaxXMaxYCorner),
      ]
      var mask: CACornerMask = []
      var radius = 0.0
      for (corner, bit) in corners {
        guard let corner, corner.points > 0 else { continue }
        mask.insert(bit)
        radius = max(radius, corner.points)
      }
      layer.cornerRadius = CGFloat(radius)
      if !mask.isEmpty { layer.maskedCorners = mask }
    }
  }
}

// MARK: - Reserved regions

@available(iOS 26.0, tvOS 26.0, *)
@available(watchOS, unavailable)
extension UIView {
  /// A part of a view that something outside it covers or divides. Perry
  /// has no such regions: a view is asked and has none.
  public struct ReservedRegion : Swift.Equatable, Swift.Hashable, Swift.Identifiable {
    public let id: UIView.ReservedRegion.ID
    public let kind: UIView.ReservedRegion.Kind
    public let frame: CoreFoundation.CGRect
    public let margins: UIEdgeInsets
    public let isActive: Swift.Bool

    public static func == (a: UIView.ReservedRegion, b: UIView.ReservedRegion) -> Swift.Bool {
      a.id == b.id && a.kind == b.kind && a.frame == b.frame && a.isActive == b.isActive
    }
    public func hash(into hasher: inout Swift.Hasher) {
      hasher.combine(id)
      hasher.combine(kind)
    }
  }

  @_Concurrency.MainActor @preconcurrency public func reservedRegions(kind: UIView.ReservedRegion.Kind, options: UIView.ReservedRegion.QueryOptions = []) -> [UIView.ReservedRegion] {
    []
  }
}

@available(iOS 26.0, tvOS 26.0, *)
@available(watchOS, unavailable)
extension UIView.ReservedRegion {
  public struct ID : Swift.Equatable, Swift.Hashable {
    var value: Swift.Int
  }
  public struct Kind : Swift.Equatable, Swift.Hashable {
    var value: Swift.Int
    public static let occlusion = UIView.ReservedRegion.Kind(value: 0)
    public static let division = UIView.ReservedRegion.Kind(value: 1)
  }
  public struct QueryOptions : Swift.OptionSet {
    public static let includeInactive = UIView.ReservedRegion.QueryOptions(rawValue: 1)
    public init(rawValue: Swift.UInt) { self.rawValue = rawValue }
    public let rawValue: Swift.UInt
    public typealias ArrayLiteralElement = UIView.ReservedRegion.QueryOptions
    public typealias Element = UIView.ReservedRegion.QueryOptions
    public typealias RawValue = Swift.UInt
  }
}

// MARK: - Animation

@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIView {
  /// A spring animation by its duration and bounce. The changes are made
  /// at once, without the spring, and the completion told so afterwards.
  @_Concurrency.MainActor @preconcurrency public class func animate(springDuration duration: Foundation.TimeInterval = 0.5, bounce: CoreFoundation.CGFloat = 0.0, initialSpringVelocity: CoreFoundation.CGFloat = 0.0, delay: Foundation.TimeInterval = 0.0, options: UIView.AnimationOptions = [], animations: () -> Swift.Void, completion: ((Swift.Bool) -> Swift.Void)? = nil) {
    animations()
    if let completion {
      DispatchQueue.main.async { completion(true) }
    }
  }
}

// MARK: - Smaller members

@available(iOS 15.0, tvOS 15.0, *)
@available(watchOS, unavailable)
extension UIFocusSystem {
  /// The focus system of an environment: none here, where nothing has focus by a remote or keyboard.
  @_Concurrency.MainActor @preconcurrency public class func focusSystem(for environment: any UIFocusEnvironment) -> UIFocusSystem? { nil }
}

@available(iOS 16.0, *)
@available(watchOS, unavailable)
extension UIApplication {
  /// The URL that opens the app's notification settings.
  nonisolated public static let openNotificationSettingsURLString: Swift.String = "app-settings:notifications"
}

@available(iOS 17.0, *)
@available(tvOS, unavailable)
extension UIPopoverPresentationControllerSourceItem {
  /// The item's frame in a view's coordinates: a view's own; unknown for any other item.
  public func frame(in referenceView: UIView) -> CoreFoundation.CGRect? {
    guard let view = self as? UIView else { return nil }
    return view.convert(view.bounds, to: referenceView)
  }
}

@available(iOS 15.0, tvOS 15.0, *)
@available(watchOS, unavailable)
extension UIAction {
  /// An action with a subtitle, which Perry's menus do not show.
  @_disfavoredOverload @_Concurrency.MainActor @preconcurrency convenience public init(title: Swift.String = "", subtitle: Swift.String? = nil, image: UIImage? = nil, identifier: UIAction.Identifier? = nil, discoverabilityTitle: Swift.String? = nil, attributes: UIMenuElement.Attributes = [], state: UIMenuElement.State = .off, handler: @escaping UIActionHandler) {
    self.init(_perryTitle: title, image: image, identifier: identifier, handler: handler)
    self.discoverabilityTitle = discoverabilityTitle
    self.attributes = attributes
    self.state = state
  }
}

@available(iOS 16.0, tvOS 16.0, *)
@available(watchOS, unavailable)
extension UIMenu {
  /// A menu with a subtitle and an element size, neither of which Perry's menus show.
  @_disfavoredOverload @_Concurrency.MainActor @preconcurrency convenience public init(title: Swift.String = "", subtitle: Swift.String? = nil, image: UIImage? = nil, identifier: UIMenu.Identifier? = nil, options: UIMenu.Options = [], preferredElementSize: UIMenu.ElementSize = .automatic, children: [UIMenuElement] = []) {
    self.init(_perryTitle: title, image: image, identifier: identifier, options: options, children: children)
  }
}

// MARK: - Pointer shapes

/// The shape a pointer takes over a region. Perry draws no pointer.
@available(iOS 13.4, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
public enum UIPointerShape {
  case path(_: UIBezierPath)
  case roundedRect(_: CoreFoundation.CGRect, radius: CoreFoundation.CGFloat = UIPointerShape.defaultCornerRadius)
  case verticalBeam(length: CoreFoundation.CGFloat)
  case horizontalBeam(length: CoreFoundation.CGFloat)
  public static let defaultCornerRadius: CoreFoundation.CGFloat = 8
}

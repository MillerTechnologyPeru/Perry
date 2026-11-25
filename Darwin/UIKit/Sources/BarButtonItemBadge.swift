// UIBarButtonItem.Badge, iOS 26's count, text or dot on a bar button, which
// iOS keeps in UIKit's Swift module. Here a badge is kept with its item and
// read back; the bar button does not draw it.
// Declarations are the SDK interface's, for its ABI.

public import Foundation
public import CoreGraphics
public import _UIKitPrivate

@available(iOS 26.0, *)
@available(visionOS, unavailable)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
extension UIBarButtonItem {
  @MainActor
  public struct Badge : Equatable {
    public var foregroundColor: UIColor?
    public var backgroundColor: UIColor?
    public var font: UIFont?

    /// The text, nil for an indicator.
    let text: String?

    init(text: String?) { self.text = text }

    public static func count(_ count: Int) -> UIBarButtonItem.Badge { Badge(text: String(count)) }
    public static func string(_ string: String) -> UIBarButtonItem.Badge { Badge(text: string) }
    public static func indicator() -> UIBarButtonItem.Badge { Badge(text: nil) }

    public var stringValue: String? { text }

    nonisolated public static func == (a: UIBarButtonItem.Badge, b: UIBarButtonItem.Badge) -> Bool {
      a.text == b.text && a.foregroundColor == b.foregroundColor && a.backgroundColor == b.backgroundColor && a.font == b.font
    }
  }

  @MainActor @preconcurrency
  public var badge: UIBarButtonItem.Badge? {
    get { _BarButtonItemBadges.badge(of: self) }
    set { _BarButtonItemBadges.set(newValue, of: self) }
  }
}

/// The badges of bar button items, kept with them.
@available(iOS 26.0, *)
@MainActor
enum _BarButtonItemBadges {
  final class Box { let value: UIBarButtonItem.Badge; init(_ value: UIBarButtonItem.Badge) { self.value = value } }
  nonisolated(unsafe) private static var key: UInt8 = 0

  static func badge(of item: UIBarButtonItem) -> UIBarButtonItem.Badge? {
    (objc_getAssociatedObject(item, &key) as? Box)?.value
  }

  static func set(_ badge: UIBarButtonItem.Badge?, of item: UIBarButtonItem) {
    objc_setAssociatedObject(item, &key, badge.map(Box.init), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
  }
}

// UIView.LayoutRegion, iOS 26's way to name the part of a view its content
// is laid out in (the safe area, the margins, the readable content, a bar
// along an edge) and ask for its guide and insets, which iOS keeps in
// UIKit's Swift module. Here a region is one of the guides and insets the
// view already has: its corner adaptation changes nothing without the
// rounded corners of iOS 26's windows, and a bar is the safe area.
// Declarations are the SDK interface's, for its ABI.

public import Foundation
public import CoreGraphics
public import _UIKitPrivate

@available(iOS 26.0, tvOS 26.0, visionOS 26.0, *)
@available(watchOS, unavailable)
extension UIView {
  public struct LayoutRegion : Hashable, Equatable {
    public enum AdaptivityAxis : Equatable {
      case horizontal
      case vertical
    }

    enum Kind : Hashable {
      case safeArea
      case margins
      case readableContent
      case bar
    }

    let kind: Kind
    let cornerAdaptation: AdaptivityAxis?
    let edge: UInt
    let extent: CGFloat?

    public static func safeArea(cornerAdaptation: UIView.LayoutRegion.AdaptivityAxis? = nil) -> UIView.LayoutRegion {
      LayoutRegion(kind: .safeArea, cornerAdaptation: cornerAdaptation, edge: 0, extent: nil)
    }

    public static func margins(cornerAdaptation: UIView.LayoutRegion.AdaptivityAxis? = nil) -> UIView.LayoutRegion {
      LayoutRegion(kind: .margins, cornerAdaptation: cornerAdaptation, edge: 0, extent: nil)
    }

    public static func readableContent(cornerAdaptation: UIView.LayoutRegion.AdaptivityAxis? = nil) -> UIView.LayoutRegion {
      LayoutRegion(kind: .readableContent, cornerAdaptation: cornerAdaptation, edge: 0, extent: nil)
    }

    @available(iOS 27.1, tvOS 27.1, visionOS 27.1, *)
    public static func bar(onEdge edge: UIRectEdge, extent: CGFloat) -> UIView.LayoutRegion {
      LayoutRegion(kind: .bar, cornerAdaptation: nil, edge: edge.rawValue, extent: extent)
    }

    @available(iOS 27.1, tvOS 27.1, visionOS 27.1, *)
    public static func bar(onEdge edge: NSDirectionalRectEdge, extent: CGFloat) -> UIView.LayoutRegion {
      LayoutRegion(kind: .bar, cornerAdaptation: nil, edge: edge.rawValue, extent: extent)
    }

    @available(iOS 27.2, tvOS 27.2, visionOS 27.2, *)
    public static func bar(onEdge edge: UIRectEdge) -> UIView.LayoutRegion {
      LayoutRegion(kind: .bar, cornerAdaptation: nil, edge: edge.rawValue, extent: nil)
    }

    @available(iOS 27.2, tvOS 27.2, visionOS 27.2, *)
    public static func bar(onEdge edge: NSDirectionalRectEdge) -> UIView.LayoutRegion {
      LayoutRegion(kind: .bar, cornerAdaptation: nil, edge: edge.rawValue, extent: nil)
    }
  }

  @_Concurrency.MainActor @preconcurrency public func layoutGuide(for region: UIView.LayoutRegion) -> UILayoutGuide {
    switch region.kind {
    case .margins: return layoutMarginsGuide
    case .readableContent: return readableContentGuide
    case .safeArea, .bar: return safeAreaLayoutGuide
    }
  }

  @_Concurrency.MainActor @preconcurrency public func edgeInsets(for region: UIView.LayoutRegion) -> UIEdgeInsets {
    switch region.kind {
    case .margins, .readableContent: return layoutMargins
    case .safeArea, .bar: return safeAreaInsets
    }
  }

  @_Concurrency.MainActor @preconcurrency public func directionalEdgeInsets(for region: UIView.LayoutRegion) -> NSDirectionalEdgeInsets {
    switch region.kind {
    case .margins, .readableContent: return directionalLayoutMargins
    case .safeArea, .bar:
      let insets = safeAreaInsets
      let leftToRight = effectiveUserInterfaceLayoutDirection == .leftToRight
      return NSDirectionalEdgeInsets(top: insets.top, leading: leftToRight ? insets.left : insets.right,
                                     bottom: insets.bottom, trailing: leftToRight ? insets.right : insets.left)
    }
  }
}

@available(iOS 26.0, tvOS 26.0, visionOS 26.0, *)
@available(watchOS, unavailable)
extension UIView.LayoutRegion.AdaptivityAxis : Hashable {}

// A list cell's accessories (iOS 14): what a cell shows beside its
// content, where, in which editing states, and what tapping one does.
// iOS keeps them in UIKit's Swift module. Declarations are the SDK
// interface's, for its ABI; an accessory here keeps what it was made with.
// Perry's UIKit has no list cell to show them in.

public import Foundation

@available(iOS 14.0, tvOS 14.0, *)
@available(watchOS, unavailable)
public struct UICellAccessory {
  public typealias ActionHandler = () -> Swift.Void

  public enum DisplayedState : Swift.Hashable {
    case always
    case whenEditing
    case whenNotEditing
  }

  public enum LayoutDimension {
    case actual
    case standard
    case custom(CoreFoundation.CGFloat)
  }

  public struct DisclosureIndicatorOptions {
    public var isHidden: Swift.Bool
    public var reservedLayoutWidth: UIKit.UICellAccessory.LayoutDimension
    public var tintColor: UIColor?
    public init(isHidden: Swift.Bool? = nil, reservedLayoutWidth: UIKit.UICellAccessory.LayoutDimension? = nil, tintColor: UIColor? = nil) {
      self.isHidden = isHidden ?? false
      self.reservedLayoutWidth = reservedLayoutWidth ?? .standard
      self.tintColor = tintColor
    }
  }
  public static func disclosureIndicator(displayed: UIKit.UICellAccessory.DisplayedState = .always, options: UIKit.UICellAccessory.DisclosureIndicatorOptions = DisclosureIndicatorOptions()) -> UIKit.UICellAccessory {
    UICellAccessory(.disclosureIndicator, displayed: displayed, isHidden: options.isHidden, reservedLayoutWidth: options.reservedLayoutWidth, tintColor: options.tintColor)
  }

  @available(iOS 15.4, tvOS 15.4, *)
  @available(watchOS, unavailable)
  public struct DetailOptions {
    public var isHidden: Swift.Bool
    public var reservedLayoutWidth: UIKit.UICellAccessory.LayoutDimension
    public var tintColor: UIColor?
    public init(isHidden: Swift.Bool? = nil, reservedLayoutWidth: UIKit.UICellAccessory.LayoutDimension? = nil, tintColor: UIColor? = nil) {
      self.isHidden = isHidden ?? false
      self.reservedLayoutWidth = reservedLayoutWidth ?? .standard
      self.tintColor = tintColor
    }
  }
  @available(iOS 15.4, tvOS 15.4, *)
  @available(watchOS, unavailable)
  public static func detail(displayed: UIKit.UICellAccessory.DisplayedState = .always, options: UIKit.UICellAccessory.DetailOptions = DetailOptions(), actionHandler: UIKit.UICellAccessory.ActionHandler? = nil) -> UIKit.UICellAccessory {
    UICellAccessory(.detail, displayed: displayed, isHidden: options.isHidden, reservedLayoutWidth: options.reservedLayoutWidth, tintColor: options.tintColor, actionHandler: actionHandler)
  }

  public struct CheckmarkOptions {
    public var isHidden: Swift.Bool
    public var reservedLayoutWidth: UIKit.UICellAccessory.LayoutDimension
    public var tintColor: UIColor?
    public init(isHidden: Swift.Bool? = nil, reservedLayoutWidth: UIKit.UICellAccessory.LayoutDimension? = nil, tintColor: UIColor? = nil) {
      self.isHidden = isHidden ?? false
      self.reservedLayoutWidth = reservedLayoutWidth ?? .standard
      self.tintColor = tintColor
    }
  }
  public static func checkmark(displayed: UIKit.UICellAccessory.DisplayedState = .always, options: UIKit.UICellAccessory.CheckmarkOptions = CheckmarkOptions()) -> UIKit.UICellAccessory {
    UICellAccessory(.checkmark, displayed: displayed, isHidden: options.isHidden, reservedLayoutWidth: options.reservedLayoutWidth, tintColor: options.tintColor)
  }

  public struct DeleteOptions {
    public var isHidden: Swift.Bool
    public var reservedLayoutWidth: UIKit.UICellAccessory.LayoutDimension
    public var tintColor: UIColor?
    public var backgroundColor: UIColor?
    public init(isHidden: Swift.Bool? = nil, reservedLayoutWidth: UIKit.UICellAccessory.LayoutDimension? = nil, tintColor: UIColor? = nil, backgroundColor: UIColor? = nil) {
      self.isHidden = isHidden ?? false
      self.reservedLayoutWidth = reservedLayoutWidth ?? .standard
      self.tintColor = tintColor
      self.backgroundColor = backgroundColor
    }
  }
  public static func delete(displayed: UIKit.UICellAccessory.DisplayedState = .whenEditing, options: UIKit.UICellAccessory.DeleteOptions = DeleteOptions(), actionHandler: UIKit.UICellAccessory.ActionHandler? = nil) -> UIKit.UICellAccessory {
    UICellAccessory(.delete, displayed: displayed, isHidden: options.isHidden, reservedLayoutWidth: options.reservedLayoutWidth, tintColor: options.tintColor,
                    backgroundColor: options.backgroundColor, actionHandler: actionHandler)
  }

  public struct InsertOptions {
    public var isHidden: Swift.Bool
    public var reservedLayoutWidth: UIKit.UICellAccessory.LayoutDimension
    public var tintColor: UIColor?
    public var backgroundColor: UIColor?
    public init(isHidden: Swift.Bool? = nil, reservedLayoutWidth: UIKit.UICellAccessory.LayoutDimension? = nil, tintColor: UIColor? = nil, backgroundColor: UIColor? = nil) {
      self.isHidden = isHidden ?? false
      self.reservedLayoutWidth = reservedLayoutWidth ?? .standard
      self.tintColor = tintColor
      self.backgroundColor = backgroundColor
    }
  }
  public static func insert(displayed: UIKit.UICellAccessory.DisplayedState = .whenEditing, options: UIKit.UICellAccessory.InsertOptions = InsertOptions(), actionHandler: UIKit.UICellAccessory.ActionHandler? = nil) -> UIKit.UICellAccessory {
    UICellAccessory(.insert, displayed: displayed, isHidden: options.isHidden, reservedLayoutWidth: options.reservedLayoutWidth, tintColor: options.tintColor,
                    backgroundColor: options.backgroundColor, actionHandler: actionHandler)
  }

  public struct ReorderOptions {
    public var isHidden: Swift.Bool
    public var reservedLayoutWidth: UIKit.UICellAccessory.LayoutDimension
    public var tintColor: UIColor?
    public var showsVerticalSeparator: Swift.Bool
    public init(isHidden: Swift.Bool? = nil, reservedLayoutWidth: UIKit.UICellAccessory.LayoutDimension? = nil, tintColor: UIColor? = nil, showsVerticalSeparator: Swift.Bool? = nil) {
      self.isHidden = isHidden ?? false
      self.reservedLayoutWidth = reservedLayoutWidth ?? .standard
      self.tintColor = tintColor
      self.showsVerticalSeparator = showsVerticalSeparator ?? true
    }
  }
  public static func reorder(displayed: UIKit.UICellAccessory.DisplayedState = .whenEditing, options: UIKit.UICellAccessory.ReorderOptions = ReorderOptions()) -> UIKit.UICellAccessory {
    UICellAccessory(.reorder, displayed: displayed, isHidden: options.isHidden, reservedLayoutWidth: options.reservedLayoutWidth, tintColor: options.tintColor)
  }

  public struct MultiselectOptions {
    public var isHidden: Swift.Bool
    public var reservedLayoutWidth: UIKit.UICellAccessory.LayoutDimension
    public var tintColor: UIColor?
    public var backgroundColor: UIColor?
    public init(isHidden: Swift.Bool? = nil, reservedLayoutWidth: UIKit.UICellAccessory.LayoutDimension? = nil, tintColor: UIColor? = nil, backgroundColor: UIColor? = nil) {
      self.isHidden = isHidden ?? false
      self.reservedLayoutWidth = reservedLayoutWidth ?? .standard
      self.tintColor = tintColor
      self.backgroundColor = backgroundColor
    }
  }
  public static func multiselect(displayed: UIKit.UICellAccessory.DisplayedState = .whenEditing, options: UIKit.UICellAccessory.MultiselectOptions = MultiselectOptions()) -> UIKit.UICellAccessory {
    UICellAccessory(.multiselect, displayed: displayed, isHidden: options.isHidden, reservedLayoutWidth: options.reservedLayoutWidth, tintColor: options.tintColor,
                    backgroundColor: options.backgroundColor)
  }

  public struct OutlineDisclosureOptions {
    public enum Style : Swift.Hashable {
      case automatic
      case header
      case cell
    }
    public var style: UIKit.UICellAccessory.OutlineDisclosureOptions.Style
    public var isHidden: Swift.Bool
    public var reservedLayoutWidth: UIKit.UICellAccessory.LayoutDimension
    public var tintColor: UIColor?
    public init(style: UIKit.UICellAccessory.OutlineDisclosureOptions.Style? = nil, isHidden: Swift.Bool? = nil, reservedLayoutWidth: UIKit.UICellAccessory.LayoutDimension? = nil, tintColor: UIColor? = nil) {
      self.style = style ?? .automatic
      self.isHidden = isHidden ?? false
      self.reservedLayoutWidth = reservedLayoutWidth ?? .standard
      self.tintColor = tintColor
    }
  }
  public static func outlineDisclosure(displayed: UIKit.UICellAccessory.DisplayedState = .always, options: UIKit.UICellAccessory.OutlineDisclosureOptions = OutlineDisclosureOptions(), actionHandler: UIKit.UICellAccessory.ActionHandler? = nil) -> UIKit.UICellAccessory {
    var accessory = UICellAccessory(.outlineDisclosure, displayed: displayed, isHidden: options.isHidden, reservedLayoutWidth: options.reservedLayoutWidth,
                                    tintColor: options.tintColor, actionHandler: actionHandler)
    accessory.outlineStyle = options.style
    return accessory
  }

  public typealias MenuSelectedElementDidChangeHandler = (UIMenu) -> Swift.Void

  @available(iOS 16.0, *)
  public struct PopUpMenuOptions {
    public var isHidden: Swift.Bool
    public var reservedLayoutWidth: UIKit.UICellAccessory.LayoutDimension
    public var tintColor: UIColor?
    public init(isHidden: Swift.Bool? = nil, reservedLayoutWidth: UIKit.UICellAccessory.LayoutDimension? = nil, tintColor: UIColor? = nil) {
      self.isHidden = isHidden ?? false
      self.reservedLayoutWidth = reservedLayoutWidth ?? .standard
      self.tintColor = tintColor
    }
  }
  @available(iOS 16.0, *)
  public static func popUpMenu(_ menu: UIMenu, displayed: UIKit.UICellAccessory.DisplayedState = .always, options: UIKit.UICellAccessory.PopUpMenuOptions = PopUpMenuOptions(), selectedElementDidChangeHandler: UIKit.UICellAccessory.MenuSelectedElementDidChangeHandler? = nil) -> UIKit.UICellAccessory {
    var accessory = UICellAccessory(.popUpMenu, displayed: displayed, isHidden: options.isHidden, reservedLayoutWidth: options.reservedLayoutWidth, tintColor: options.tintColor)
    accessory.menu = menu
    accessory.menuHandler = selectedElementDidChangeHandler
    return accessory
  }

  public struct LabelOptions {
    public var isHidden: Swift.Bool
    public var reservedLayoutWidth: UIKit.UICellAccessory.LayoutDimension
    public var tintColor: UIColor?
    public var font: UIFont
    public var adjustsFontForContentSizeCategory: Swift.Bool
    public init(isHidden: Swift.Bool? = nil, reservedLayoutWidth: UIKit.UICellAccessory.LayoutDimension? = nil, tintColor: UIColor? = nil, font: UIFont? = nil, adjustsFontForContentSizeCategory: Swift.Bool? = nil) {
      self.isHidden = isHidden ?? false
      self.reservedLayoutWidth = reservedLayoutWidth ?? .actual
      self.tintColor = tintColor
      self.font = font ?? UIFont.preferredFont(forTextStyle: .body)
      self.adjustsFontForContentSizeCategory = adjustsFontForContentSizeCategory ?? true
    }
  }
  public static func label(text: Swift.String, displayed: UIKit.UICellAccessory.DisplayedState = .always, options: UIKit.UICellAccessory.LabelOptions = LabelOptions()) -> UIKit.UICellAccessory {
    var accessory = UICellAccessory(.label, displayed: displayed, isHidden: options.isHidden, reservedLayoutWidth: options.reservedLayoutWidth, tintColor: options.tintColor)
    accessory.text = text
    accessory.font = options.font
    return accessory
  }

  public enum Placement {
    public typealias Position = (_ accessories: [UIKit.UICellAccessory]) -> Swift.Int
    /// Just before the first accessory of the same kind, or at the end without one.
    public static func position(before accessory: UIKit.UICellAccessory) -> UIKit.UICellAccessory.Placement.Position {
      let type = accessory.accessoryType
      return { accessories in accessories.firstIndex { $0.accessoryType == type } ?? accessories.count }
    }
    /// Just after the first accessory of the same kind, or at the end without one.
    public static func position(after accessory: UIKit.UICellAccessory) -> UIKit.UICellAccessory.Placement.Position {
      let type = accessory.accessoryType
      return { accessories in accessories.firstIndex { $0.accessoryType == type }.map { $0 + 1 } ?? accessories.count }
    }
    case leading(displayed: UIKit.UICellAccessory.DisplayedState = .always, at: UIKit.UICellAccessory.Placement.Position = { $0.count })
    case trailing(displayed: UIKit.UICellAccessory.DisplayedState = .always, at: UIKit.UICellAccessory.Placement.Position = { _ in 0 })
  }

  public struct CustomViewConfiguration {
    public let customView: UIView
    public let placement: UIKit.UICellAccessory.Placement
    public var isHidden: Swift.Bool
    public var reservedLayoutWidth: UIKit.UICellAccessory.LayoutDimension
    public var tintColor: UIColor?
    public var maintainsFixedSize: Swift.Bool
    public init(customView: UIView, placement: UIKit.UICellAccessory.Placement, isHidden: Swift.Bool? = nil, reservedLayoutWidth: UIKit.UICellAccessory.LayoutDimension? = nil, tintColor: UIColor? = nil, maintainsFixedSize: Swift.Bool? = nil) {
      self.customView = customView
      self.placement = placement
      self.isHidden = isHidden ?? false
      self.reservedLayoutWidth = reservedLayoutWidth ?? .actual
      self.tintColor = tintColor
      self.maintainsFixedSize = maintainsFixedSize ?? false
    }
  }
  public static func customView(configuration: UIKit.UICellAccessory.CustomViewConfiguration) -> UIKit.UICellAccessory {
    let displayed: DisplayedState
    switch configuration.placement {
    case .leading(let state, _), .trailing(let state, _): displayed = state
    }
    var accessory = UICellAccessory(.customView(configuration.customView), displayed: displayed, isHidden: configuration.isHidden,
                                    reservedLayoutWidth: configuration.reservedLayoutWidth, tintColor: configuration.tintColor)
    accessory.placement = configuration.placement
    accessory.maintainsFixedSize = configuration.maintainsFixedSize
    return accessory
  }

  public enum AccessoryType : Swift.Hashable {
    case disclosureIndicator
    case outlineDisclosure
    case checkmark
    case delete
    case insert
    case reorder
    case multiselect
    case label
    case customView(UIView)
    @available(iOS 15.4, tvOS 15.4, *)
    @available(watchOS, unavailable)
    case detail
    @available(iOS 16.0, *)
    case popUpMenu
  }

  public let accessoryType: UIKit.UICellAccessory.AccessoryType

  // What the accessory was made with.
  var displayed: UIKit.UICellAccessory.DisplayedState
  var isHidden: Swift.Bool
  var reservedLayoutWidth: UIKit.UICellAccessory.LayoutDimension
  var tintColor: UIColor?
  var backgroundColor: UIColor?
  var actionHandler: UIKit.UICellAccessory.ActionHandler?
  var outlineStyle: UIKit.UICellAccessory.OutlineDisclosureOptions.Style = .automatic
  var text: Swift.String?
  var font: UIFont?
  var menu: UIMenu?
  var menuHandler: UIKit.UICellAccessory.MenuSelectedElementDidChangeHandler?
  var placement: UIKit.UICellAccessory.Placement?
  var maintainsFixedSize = false

  init(_ type: UIKit.UICellAccessory.AccessoryType, displayed: UIKit.UICellAccessory.DisplayedState, isHidden: Swift.Bool,
       reservedLayoutWidth: UIKit.UICellAccessory.LayoutDimension, tintColor: UIColor?, backgroundColor: UIColor? = nil,
       actionHandler: UIKit.UICellAccessory.ActionHandler? = nil) {
    self.accessoryType = type
    self.displayed = displayed
    self.isHidden = isHidden
    self.reservedLayoutWidth = reservedLayoutWidth
    self.tintColor = tintColor
    self.backgroundColor = backgroundColor
    self.actionHandler = actionHandler
  }
}

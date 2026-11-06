import CPerryGeometry
import PerryObjCInterop

// The Touch Bar: there is none. Apps' bars and items are kept as built,
// and their delegates are never asked for items.

@ObjCClass("NSTouchBar")
open class NSTouchBar: NSObject {
    var delegate: UnsafeMutableRawPointer?
    var defaultItemIdentifiers: NSObject?
    var customizationIdentifier: String?
    var principalItemIdentifier: String?
    var templateItems: NSObject?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCClassMethod("isAutomaticCustomizeTouchBarMenuItemEnabled") static func isAutomaticCustomizeEnabled() -> Bool { false }
    @ObjCClassMethod("setAutomaticCustomizeTouchBarMenuItemEnabled:") static func setAutomaticCustomizeEnabled(_ value: Bool) {}

    @ObjCMethod("delegate") func barDelegate() -> NSObject? { delegate.map(NSObject.init) }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { self.delegate = delegate?.objcObject }
    @ObjCMethod("defaultItemIdentifiers") func barDefaultItemIdentifiers() -> NSObject? { defaultItemIdentifiers }
    @ObjCMethod("setDefaultItemIdentifiers:") func setDefaultItemIdentifiers(_ identifiers: NSObject?) { defaultItemIdentifiers = identifiers }
    @ObjCMethod("customizationIdentifier") func barCustomizationIdentifier() -> String? { customizationIdentifier }
    @ObjCMethod("setCustomizationIdentifier:") func setCustomizationIdentifier(_ identifier: String?) { customizationIdentifier = identifier }
    @ObjCMethod("setCustomizationAllowedItemIdentifiers:") func setCustomizationAllowedItemIdentifiers(_ identifiers: NSObject?) {}
    @ObjCMethod("setCustomizationRequiredItemIdentifiers:") func setCustomizationRequiredItemIdentifiers(_ identifiers: NSObject?) {}
    @ObjCMethod("principalItemIdentifier") func barPrincipalItemIdentifier() -> String? { principalItemIdentifier }
    @ObjCMethod("setPrincipalItemIdentifier:") func setPrincipalItemIdentifier(_ identifier: String?) { principalItemIdentifier = identifier }
    @ObjCMethod("setEscapeKeyReplacementItemIdentifier:") func setEscapeKeyReplacementItemIdentifier(_ identifier: String?) {}
    @ObjCMethod("templateItems") func barTemplateItems() -> NSObject? { templateItems }
    @ObjCMethod("setTemplateItems:") func setTemplateItems(_ items: NSObject?) { templateItems = items }
    @ObjCMethod("itemForIdentifier:") func item(forIdentifier identifier: String?) -> NSObject? { nil }
    @ObjCMethod("itemIdentifiers") func itemIdentifiers() -> NSObject? { defaultItemIdentifiers }
    @ObjCMethod("isVisible") func isVisible() -> Bool { false }
}

@ObjCClass("NSTouchBarItem")
open class NSTouchBarItem: NSObject {
    var identifier = ""
    var visibilityPriority: Float = 0

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithIdentifier:")
    public required init(identifier: String?) {
        super.init()
        self.identifier = identifier ?? ""
    }

    @ObjCMethod("identifier") func itemIdentifier() -> String { identifier }
    @ObjCMethod("visibilityPriority") func itemVisibilityPriority() -> Float { visibilityPriority }
    @ObjCMethod("setVisibilityPriority:") func setVisibilityPriority(_ priority: Float) { visibilityPriority = priority }
    @ObjCMethod("view") func view() -> NSObject? { nil }
    @ObjCMethod("isVisible") func isVisible() -> Bool { false }
}

@ObjCClass("NSCustomTouchBarItem")
open class NSCustomTouchBarItem: NSTouchBarItem {
    var customView: NSObject?
    var customizationLabel: String?

    @ObjCMethod("view") override func view() -> NSObject? { customView }
    @ObjCMethod("setView:") func setView(_ view: NSObject?) { customView = view }
    @ObjCMethod("customizationLabel") func itemCustomizationLabel() -> String? { customizationLabel }
    @ObjCMethod("setCustomizationLabel:") func setCustomizationLabel(_ label: String?) { customizationLabel = label }
    @ObjCMethod("setViewController:") func setViewController(_ controller: NSObject?) {}
}

@ObjCClass("NSGroupTouchBarItem")
open class NSGroupTouchBarItem: NSTouchBarItem {
    var groupTouchBar: NSTouchBar?

    @ObjCClassMethod("groupItemWithIdentifier:items:")
    static func groupItem(identifier: String?, items: NSObject?) -> NSGroupTouchBarItem {
        let item = NSGroupTouchBarItem(identifier: identifier)
        let bar = NSTouchBar()
        bar.templateItems = items
        item.groupTouchBar = bar
        return item
    }

    @ObjCMethod("groupTouchBar") func itemGroupTouchBar() -> NSTouchBar? { groupTouchBar }
    @ObjCMethod("setGroupTouchBar:") func setGroupTouchBar(_ bar: NSTouchBar?) { groupTouchBar = bar }
    @ObjCMethod("setCustomizationLabel:") func setCustomizationLabel(_ label: String?) {}
    @ObjCMethod("setGroupUserInterfaceLayoutDirection:") func setGroupUserInterfaceLayoutDirection(_ direction: Int) {}
    @ObjCMethod("setPrefersEqualWidths:") func setPrefersEqualWidths(_ value: Bool) {}
}

/// NSScrubber: a Touch Bar's scrolling list, a view that shows nothing here.
@ObjCClass("NSScrubber")
open class NSScrubber: NSView {
    var dataSource: UnsafeMutableRawPointer?
    var scrubberDelegate: UnsafeMutableRawPointer?
    var scrubberLayout: NSObject?
    var selectedIndex = -1

    @ObjCMethod("dataSource") func scrubberDataSource() -> NSObject? { dataSource.map(NSObject.init) }
    @ObjCMethod("setDataSource:") func setDataSource(_ source: NSObject?) { dataSource = source?.objcObject }
    @ObjCMethod("delegate") func delegate() -> NSObject? { scrubberDelegate.map(NSObject.init) }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { scrubberDelegate = delegate?.objcObject }
    @ObjCMethod("scrubberLayout") func layoutObject() -> NSObject? { scrubberLayout }
    @ObjCMethod("setScrubberLayout:") func setScrubberLayout(_ layout: NSObject?) { scrubberLayout = layout }
    @ObjCMethod("selectedIndex") func scrubberSelectedIndex() -> Int { selectedIndex }
    @ObjCMethod("setSelectedIndex:") func setSelectedIndex(_ index: Int) { selectedIndex = index }
    @ObjCMethod("numberOfItems") func numberOfItems() -> Int { 0 }
    @ObjCMethod("reloadData") func reloadData() {}
    @ObjCMethod("registerClass:forItemIdentifier:") func register(_ cls: ObjCClass?, forItemIdentifier identifier: String?) {}
    @ObjCMethod("makeItemWithIdentifier:owner:") func makeItem(identifier: String?, owner: NSObject?) -> NSObject? { nil }
    @ObjCMethod("setMode:") func setMode(_ mode: Int) {}
    @ObjCMethod("setSelectionBackgroundStyle:") func setSelectionBackgroundStyle(_ style: NSObject?) {}
    @ObjCMethod("setSelectionOverlayStyle:") func setSelectionOverlayStyle(_ style: NSObject?) {}
    @ObjCMethod("setShowsArrowButtons:") func setShowsArrowButtons(_ value: Bool) {}
    @ObjCMethod("setContinuous:") func setContinuous(_ value: Bool) {}
    @ObjCMethod("setFloatsSelectionViews:") func setFloatsSelectionViews(_ value: Bool) {}
    @ObjCMethod("setItemAlignment:") func setItemAlignment(_ alignment: Int) {}
    @ObjCMethod("setBackgroundColor:") func setBackgroundColor(_ color: NSObject?) {}
    @ObjCMethod("scrollItemAtIndex:toAlignment:") func scrollItem(at index: Int, toAlignment alignment: Int) {}
}

@ObjCClass("NSScrubberLayout")
open class NSScrubberLayout: NSObject {
    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("invalidateLayout") func invalidateLayout() {}
}

@ObjCClass("NSScrubberFlowLayout")
open class NSScrubberFlowLayout: NSScrubberLayout {
    var itemSpacing: CGFloat = 0
    var itemSize = CGSize(width: 50, height: 30)

    @ObjCMethod("itemSpacing") func layoutItemSpacing() -> CGFloat { itemSpacing }
    @ObjCMethod("setItemSpacing:") func setItemSpacing(_ spacing: CGFloat) { itemSpacing = spacing }
    @ObjCMethod("itemSize") func layoutItemSize() -> CGSize { itemSize }
    @ObjCMethod("setItemSize:") func setItemSize(_ size: CGSize) { itemSize = size }
}

@ObjCClass("NSScrubberArrangedView")
open class NSScrubberArrangedView: NSView {
    var selected = false
    var highlighted = false

    @ObjCMethod("isSelected") func isSelected() -> Bool { selected }
    @ObjCMethod("setSelected:") func setSelected(_ value: Bool) { selected = value }
    @ObjCMethod("isHighlighted") func isHighlighted() -> Bool { highlighted }
    @ObjCMethod("setHighlighted:") func setHighlighted(_ value: Bool) { highlighted = value }
    @ObjCMethod("applyLayoutAttributes:") func applyLayoutAttributes(_ attributes: NSObject?) {}
}

@ObjCClass("NSScrubberItemView")
open class NSScrubberItemView: NSScrubberArrangedView {}

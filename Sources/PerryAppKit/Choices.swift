import CPerryGeometry
import PerryObjCInterop

// Controls that choose among values: pop-up buttons (a menu's items; with
// no menus drawn here, a click moves to the next item), segmented controls,
// search fields and combo boxes (text fields of their own cells) and color
// wells.

@ObjCClass("NSPopUpButton")
open class NSPopUpButton: NSButton {
    var popUpCell: NSPopUpButtonCell? { cellObject?.as(NSPopUpButtonCell.self) }

    @ObjCClassMethod("cellClass") static func popUpCellClass() -> ObjCClass? { NSPopUpButtonCell.objCClass }

    @ObjCMethod("initWithFrame:pullsDown:")
    public required init(frame: CGRect, pullsDown: Bool) {
        super.init(frame: frame)
        popUpCell?.pullsDown = pullsDown
    }

    public required init() { super.init() }
    @ObjCMethod("initWithFrame:")
    public required init(frame: CGRect) { super.init(frame: frame) }
    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) { super.init(coder: coder) }

    var items: [NSMenuItem] { popUpCell?.items ?? [] }

    @ObjCMethod("menu") func popUpMenu() -> NSObject? { popUpCell?.menu }
    @ObjCMethod("setMenu:") func setPopUpMenu(_ menu: NSObject?) { popUpCell?.setMenu(menu); valueChanged() }
    @ObjCMethod("pullsDown") func pullsDown() -> Bool { popUpCell?.pullsDown ?? false }
    @ObjCMethod("setPullsDown:") func setPullsDown(_ value: Bool) { popUpCell?.pullsDown = value; setNeedsDisplay(true) }
    @ObjCMethod("autoenablesItems") func autoenablesItems() -> Bool { popUpCell?.autoenablesItems ?? true }
    @ObjCMethod("setAutoenablesItems:") func setAutoenablesItems(_ value: Bool) { popUpCell?.autoenablesItems = value }
    @ObjCMethod("preferredEdge") func preferredEdge() -> UInt { popUpCell?.preferredEdge ?? 1 }
    @ObjCMethod("setPreferredEdge:") func setPreferredEdge(_ value: UInt) { popUpCell?.preferredEdge = value }
    @ObjCMethod("numberOfItems") func numberOfItems() -> Int { items.count }
    @ObjCMethod("itemArray") func itemArray() -> NSObject { NSMutableArray.of(items) }
    @ObjCMethod("itemTitles") func itemTitles() -> NSObject { NSMutableArray.of(items.compactMap { $0.title.objCArgument().map(NSObject.init) }) }
    @ObjCMethod("itemAtIndex:") func item(at index: Int) -> NSMenuItem? { items.indices.contains(index) ? items[index] : nil }
    @ObjCMethod("itemWithTitle:") func item(withTitle title: String?) -> NSMenuItem? { items.first { $0.title == title } }
    @ObjCMethod("itemTitleAtIndex:") func itemTitle(at index: Int) -> String { item(at: index)?.title ?? "" }
    @ObjCMethod("indexOfItem:") func index(of item: NSMenuItem?) -> Int { items.firstIndex { $0 === item } ?? -1 }
    @ObjCMethod("indexOfItemWithTitle:") func indexOfItem(withTitle title: String?) -> Int { items.firstIndex { $0.title == title } ?? -1 }
    @ObjCMethod("indexOfItemWithTag:") func indexOfItem(withTag tag: Int) -> Int { items.firstIndex { $0.tag == tag } ?? -1 }
    @ObjCMethod("indexOfItemWithRepresentedObject:")
    func indexOfItem(withRepresentedObject object: NSObject?) -> Int { items.firstIndex { $0.representedObject?.objcObject == object?.objcObject } ?? -1 }
    @ObjCMethod("lastItem") func lastItem() -> NSMenuItem? { items.last }
    @ObjCMethod("selectedItem") func selectedItem() -> NSMenuItem? { popUpCell?.selectedItem }
    @ObjCMethod("indexOfSelectedItem") func indexOfSelectedItem() -> Int { popUpCell?.selectedIndex ?? -1 }
    @ObjCMethod("titleOfSelectedItem") func titleOfSelectedItem() -> String? { popUpCell?.selectedItem?.title }
    @ObjCMethod("selectedTag") override func selectedTag() -> Int { popUpCell?.selectedItem?.tag ?? -1 }
    @ObjCMethod("selectItemAtIndex:") func selectItem(at index: Int) { popUpCell?.selectItem(at: index); setNeedsDisplay(true) }
    @ObjCMethod("selectItem:") func selectItem(_ item: NSMenuItem?) { selectItem(at: index(of: item)) }
    @ObjCMethod("selectItemWithTitle:") func selectItem(withTitle title: String?) { selectItem(at: indexOfItem(withTitle: title)) }
    @ObjCMethod("selectItemWithTag:")
    func selectItem(withTag tag: Int) -> Bool {
        let index = indexOfItem(withTag: tag)
        selectItem(at: index)
        return index >= 0
    }
    @ObjCMethod("addItemWithTitle:")
    func addItem(withTitle title: String?) {
        guard let menu = popUpCell?.menu else { return }
        _ = menu.addItem(title: title, action: nil, keyEquivalent: "")
        if popUpCell?.selectedIndex == -1 { popUpCell?.selectedIndex = 0 }
        valueChanged()
    }
    @ObjCMethod("addItemsWithTitles:")
    func addItems(withTitles titles: NSObject?) { for title in titles?.as(NSArray.self)?.elements ?? [] { addItem(withTitle: title.stringValue) } }
    @ObjCMethod("insertItemWithTitle:atIndex:")
    func insertItem(withTitle title: String?, at index: Int) {
        _ = popUpCell?.menu?.insertItem(title: title, action: nil, keyEquivalent: "", at: index)
        valueChanged()
    }
    @ObjCMethod("removeItemWithTitle:") func removeItem(withTitle title: String?) { popUpCell?.menu?.removeItem(item(withTitle: title)); valueChanged() }
    @ObjCMethod("removeItemAtIndex:") func removeItem(at index: Int) { popUpCell?.menu?.removeItem(at: index); valueChanged() }
    @ObjCMethod("removeAllItems")
    func removeAllItems() {
        popUpCell?.menu?.removeAllItems()
        popUpCell?.selectedIndex = -1
        valueChanged()
    }
    @ObjCMethod("synchronizeTitleAndSelectedItem") func synchronizeTitleAndSelectedItem() { setNeedsDisplay(true) }
    /// A pull-down's title is its first item's; a pop-up selects the item
    /// with the title, added when there is none.
    @ObjCMethod("setTitle:") override func setTitle(_ title: String?) {
        if pullsDown() {
            if let first = items.first { first.title = title ?? "" } else { addItem(withTitle: title) }
            popUpCell?.shownItemChanged()
            return
        }
        if let index = items.firstIndex(where: { $0.title == title }) { selectItem(at: index) } else { addItem(withTitle: title); selectItem(at: items.count - 1) }
    }
    @ObjCMethod("objectValue") override func objectValue() -> NSObject? { NSNumber.make(integer: indexOfSelectedItem()) }

    /// A click shows the menu: a pop-up's with the selected item over the
    /// button, a pull-down's below it.
    override func clicked() {
        guard let cell = popUpCell else { return }
        // Observers fill the menu now, as TextMate's status bar does.
        NSNotificationCenter.defaultCenter().post(NSNotification.make(name: "NSPopUpButtonCellWillPopUpNotification", object: cell))
        NSNotificationCenter.defaultCenter().post(NSNotification.make(name: "NSPopUpButtonWillPopUpNotification", object: self))
        guard let menu = cell.menu else { return }
        let flipped = self.flipped
        let chosen: NSMenuItem?
        if cell.pullsDown {
            chosen = MenuTracking.popUp(menu, positioning: nil, at: CGPoint(x: 0, y: flipped ? bounds.maxY : 0), in: self,
                                        minimumWidth: bounds.width, font: font?.as(NSFont.self), skipsFirstItem: true, performs: false)
        } else {
            chosen = MenuTracking.popUp(menu, positioning: cell.selectedItem, at: CGPoint(x: 0, y: bounds.midY), in: self,
                                        minimumWidth: bounds.width + 20, font: font?.as(NSFont.self), performs: false)
        }
        guard let chosen else { return }
        // An item of the button's own menu becomes a pop-up's selection; one
        // from a submenu only sends its action.
        if !cell.pullsDown, let index = cell.items.firstIndex(where: { $0 === chosen }) { cell.selectItem(at: index) }
        setNeedsDisplay(true)
        perform(chosen)
    }

    /// The item's action, or without one the button's.
    private func perform(_ item: NSMenuItem) {
        if item.action != nil {
            MenuTracking.perform(item)
        } else {
            _ = sendAction(action, to: target.map(NSObject.init))
        }
    }

    @ObjCMethod("performClick:")
    override func performClick(_ sender: NSObject?) { clicked() }
}

@ObjCClass("NSSegmentedControl")
open class NSSegmentedControl: NSControl {
    var segmentedCell: NSSegmentedCell? { cellObject?.as(NSSegmentedCell.self) }

    @ObjCClassMethod("cellClass") static func segmentedCellClass() -> ObjCClass? { NSSegmentedCell.objCClass }

    @ObjCClassMethod("segmentedControlWithLabels:trackingMode:target:action:")
    static func segmentedControl(labels: NSObject?, trackingMode: UInt, target: NSObject?, action: ObjCSelector?) -> NSSegmentedControl {
        let control = NSSegmentedControl(frame: .zero)
        let labels = labels?.as(NSArray.self)?.elements.map(\.stringValue) ?? []
        control.segmentedCell?.setSegmentCount(labels.count)
        for (index, label) in labels.enumerated() { control.segmentedCell?.setLabel(label, forSegment: index) }
        control.segmentedCell?.trackingMode = trackingMode
        control.target = target?.objcObject
        control.action = action
        control.sizeToFit()
        return control
    }

    @ObjCClassMethod("segmentedControlWithImages:trackingMode:target:action:")
    static func segmentedControl(images: NSObject?, trackingMode: UInt, target: NSObject?, action: ObjCSelector?) -> NSSegmentedControl {
        let control = NSSegmentedControl(frame: .zero)
        let images = images?.as(NSArray.self)?.elements.compactMap { $0.as(NSImage.self) } ?? []
        control.segmentedCell?.setSegmentCount(images.count)
        for (index, image) in images.enumerated() { control.segmentedCell?.setImage(image, forSegment: index) }
        control.segmentedCell?.trackingMode = trackingMode
        control.target = target?.objcObject
        control.action = action
        control.sizeToFit()
        return control
    }

    @ObjCMethod("segmentCount") func segmentCount() -> Int { segmentedCell?.segmentCount() ?? 0 }
    @ObjCMethod("setSegmentCount:") func setSegmentCount(_ count: Int) { segmentedCell?.setSegmentCount(count); valueChanged() }
    @ObjCMethod("selectedSegment") func selectedSegment() -> Int { segmentedCell?.selectedSegment() ?? -1 }
    @ObjCMethod("setSelectedSegment:") func setSelectedSegment(_ index: Int) { segmentedCell?.setSelectedSegment(index) }
    @ObjCMethod("selectSegmentWithTag:") func selectSegment(withTag tag: Int) -> Bool { segmentedCell?.selectSegment(withTag: tag) ?? false }
    @ObjCMethod("setLabel:forSegment:") func setLabel(_ label: String?, forSegment index: Int) { segmentedCell?.setLabel(label, forSegment: index); valueChanged() }
    @ObjCMethod("labelForSegment:") func label(forSegment index: Int) -> String? { segmentedCell?.label(forSegment: index) }
    @ObjCMethod("setImage:forSegment:") func setImage(_ image: NSImage?, forSegment index: Int) { segmentedCell?.setImage(image, forSegment: index) }
    @ObjCMethod("imageForSegment:") func image(forSegment index: Int) -> NSImage? { segmentedCell?.image(forSegment: index) }
    @ObjCMethod("setWidth:forSegment:") func setWidth(_ width: CGFloat, forSegment index: Int) { segmentedCell?.setWidth(width, forSegment: index) }
    @ObjCMethod("widthForSegment:") func width(forSegment index: Int) -> CGFloat { segmentedCell?.width(forSegment: index) ?? 0 }
    @ObjCMethod("setSelected:forSegment:") func setSelected(_ selected: Bool, forSegment index: Int) { segmentedCell?.setSelected(selected, forSegment: index) }
    @ObjCMethod("isSelectedForSegment:") func isSelected(forSegment index: Int) -> Bool { segmentedCell?.isSelected(forSegment: index) ?? false }
    @ObjCMethod("setEnabled:forSegment:") func setEnabled(_ enabled: Bool, forSegment index: Int) { segmentedCell?.setEnabled(enabled, forSegment: index) }
    @ObjCMethod("isEnabledForSegment:") func isEnabled(forSegment index: Int) -> Bool { segmentedCell?.isEnabled(forSegment: index) ?? false }
    @ObjCMethod("setTag:forSegment:") func setTag(_ tag: Int, forSegment index: Int) { segmentedCell?.setTag(tag, forSegment: index) }
    @ObjCMethod("tagForSegment:") func tag(forSegment index: Int) -> Int { segmentedCell?.tag(forSegment: index) ?? 0 }
    @ObjCMethod("setToolTip:forSegment:") func setToolTip(_ tip: String?, forSegment index: Int) { segmentedCell?.setToolTip(tip, forSegment: index) }
    @ObjCMethod("setMenu:forSegment:") func setMenu(_ menu: NSObject?, forSegment index: Int) { segmentedCell?.setMenu(menu, forSegment: index) }
    @ObjCMethod("trackingMode") func trackingMode() -> UInt { segmentedCell?.trackingMode ?? 0 }
    @ObjCMethod("setTrackingMode:") func setTrackingMode(_ mode: UInt) { segmentedCell?.trackingMode = mode }
    @ObjCMethod("segmentStyle") func segmentStyle() -> Int { segmentedCell?.segmentStyle ?? 0 }
    @ObjCMethod("setSegmentStyle:") func setSegmentStyle(_ style: Int) { segmentedCell?.segmentStyle = style }
    @ObjCMethod("selectedSegmentBezelColor") func selectedSegmentBezelColor() -> NSObject? { nil }
    @ObjCMethod("setSelectedSegmentBezelColor:") func setSelectedSegmentBezelColor(_ color: NSObject?) {}
    @ObjCMethod("setSegmentDistribution:") func setSegmentDistribution(_ value: Int) {}
    @ObjCMethod("setImageScaling:forSegment:") func setImageScaling(_ scaling: UInt, forSegment index: Int) {}
    @ObjCMethod("intrinsicContentSize")
    override func intrinsicContentSize() -> CGSize {
        guard let cell = segmentedCell else { return super.intrinsicContentSize() }
        let width = cell.segments.reduce(CGFloat(0)) { total, segment in
            total + (segment.width > 0 ? segment.width : Text.width(segment.label, font: cell.effectiveFont) + 18)
        }
        return CGSize(width: width.rounded(.up) + 2, height: 22)
    }
    @ObjCMethod("sizeToFit") override func sizeToFit() { Send.void(objcObject, "setFrameSize:", size: intrinsicContentSize()) }

    override var tracksClicks: Bool { true }

    /// The click's segment: selected (or toggled, selecting any), then the
    /// action.
    @ObjCMethod("mouseUp:")
    override func mouseUp(_ eventObject: NSObject?) {
        guard tracking, let event = eventObject?.as(NSEvent.self), let cell = segmentedCell else { return super.mouseUp(eventObject) }
        tracking = false
        cell.setHighlighted(false)
        let point = convert(event.locationInWindow, from: nil)
        guard let index = cell.frames(in: bounds).firstIndex(where: { $0.contains(point) }), cell.isEnabled(forSegment: index) else { return }
        switch cell.trackingMode {
        case 1: cell.setSelected(!cell.isSelected(forSegment: index), forSegment: index)
        case 2: cell.setSelectedSegment(index)
        default: cell.setSelectedSegment(index)
        }
        _ = sendAction(action, to: target.map(NSObject.init))
        if cell.trackingMode == 2 { cell.setSelected(false, forSegment: index) }
    }
}

@ObjCClass("NSSearchField")
open class NSSearchField: NSTextField {
    var recentSearches: NSObject?
    var recentsAutosaveName: String?
    var sendsSearchStringImmediately = false
    var sendsWholeSearchString = false

    @ObjCClassMethod("cellClass") static func searchCellClass() -> ObjCClass? { NSSearchFieldCell.objCClass }

    @ObjCMethod("recentSearches") func searchRecentSearches() -> NSObject { recentSearches ?? NSMutableArray.empty() }
    @ObjCMethod("setRecentSearches:") func setRecentSearches(_ value: NSObject?) { recentSearches = value }
    @ObjCMethod("recentsAutosaveName") func searchRecentsAutosaveName() -> String? { recentsAutosaveName }
    @ObjCMethod("setRecentsAutosaveName:") func setRecentsAutosaveName(_ value: String?) { recentsAutosaveName = value }
    @ObjCMethod("sendsSearchStringImmediately") func searchSendsSearchStringImmediately() -> Bool { sendsSearchStringImmediately }
    @ObjCMethod("setSendsSearchStringImmediately:") func setSendsSearchStringImmediately(_ value: Bool) { sendsSearchStringImmediately = value }
    @ObjCMethod("sendsWholeSearchString") func searchSendsWholeSearchString() -> Bool { sendsWholeSearchString }
    @ObjCMethod("setSendsWholeSearchString:") func setSendsWholeSearchString(_ value: Bool) { sendsWholeSearchString = value }
    @ObjCMethod("setMaximumRecents:") func setMaximumRecents(_ value: Int) {}
    @ObjCMethod("setSearchMenuTemplate:") func setSearchMenuTemplate(_ menu: NSObject?) {}
    @ObjCMethod("searchMenuTemplate") func searchMenuTemplate() -> NSObject? { nil }
    @ObjCMethod("searchTextBounds") func searchTextBounds() -> CGRect { fieldCell?.titleRect(forBounds: bounds) ?? bounds }
    @ObjCMethod("searchButtonBounds") func searchButtonBounds() -> CGRect { CGRect(x: 4, y: 0, width: 16, height: bounds.height) }
    @ObjCMethod("cancelButtonBounds") func cancelButtonBounds() -> CGRect { CGRect(x: bounds.width - 20, y: 0, width: 16, height: bounds.height) }

    /// A search field sends its action as its text changes, unless it
    /// waits for the whole string.
    @ObjCMethod("keyDown:")
    override func keyDown(_ eventObject: NSObject?) {
        let before = controlStringValue()
        super.keyDown(eventObject)
        if !sendsWholeSearchString, controlStringValue() != before, cellObject?.continuous != true {
            _ = sendAction(action, to: target.map(NSObject.init))
        }
    }

    @ObjCMethod("mouseDown:")
    override func mouseDown(_ event: NSObject?) {
        // The cancel button clears the field.
        if let event = event?.as(NSEvent.self), !controlStringValue().isEmpty,
           cancelButtonBounds().contains(convert(event.locationInWindow, from: nil)) {
            setStringValue("")
            _ = sendAction(action, to: target.map(NSObject.init))
            return
        }
        super.mouseDown(event)
    }
}

@ObjCClass("NSComboBox")
open class NSComboBox: NSTextField {
    var comboCell: NSComboBoxCell? { cellObject?.as(NSComboBoxCell.self) }
    /// Not retained.
    var dataSourceObject: UnsafeMutableRawPointer?
    var usesDataSource = false
    var completes = false
    var visibleItems = 5

    @ObjCClassMethod("cellClass") static func comboCellClass() -> ObjCClass? { NSComboBoxCell.objCClass }

    var items: [NSObject] { comboCell?.items ?? [] }

    @ObjCMethod("numberOfItems")
    func numberOfItems() -> Int {
        if usesDataSource, let dataSourceObject { return Send.integer(dataSourceObject, "numberOfItemsInComboBox:", objcObject) }
        return items.count
    }
    @ObjCMethod("itemObjectValueAtIndex:")
    func itemObjectValue(at index: Int) -> NSObject? {
        if usesDataSource, let dataSourceObject {
            return Send.object(dataSourceObject, "comboBox:objectValueForItemAtIndex:", objcObject, nil, index, skipSecond: true).map(NSObject.init)
        }
        return items.indices.contains(index) ? items[index] : nil
    }
    @ObjCMethod("objectValues") func objectValues() -> NSObject { NSMutableArray.of(items) }
    @ObjCMethod("addItemWithObjectValue:") func addItem(withObjectValue value: NSObject?) { if let value { comboCell?.items.append(value) } }
    @ObjCMethod("addItemsWithObjectValues:")
    func addItems(withObjectValues values: NSObject?) { comboCell?.items += values?.as(NSArray.self)?.elements ?? [] }
    @ObjCMethod("insertItemWithObjectValue:atIndex:")
    func insertItem(withObjectValue value: NSObject?, at index: Int) {
        guard let value, let cell = comboCell else { return }
        cell.items.insert(value, at: max(0, min(index, cell.items.count)))
    }
    @ObjCMethod("removeItemAtIndex:") func removeItem(at index: Int) { if comboCell?.items.indices.contains(index) == true { comboCell?.items.remove(at: index) } }
    @ObjCMethod("removeAllItems") func removeAllItems() { comboCell?.items = [] }
    @ObjCMethod("indexOfSelectedItem") func indexOfSelectedItem() -> Int { items.firstIndex { $0.stringValue == controlStringValue() } ?? -1 }
    @ObjCMethod("selectItemAtIndex:") func selectItem(at index: Int) { if let value = itemObjectValue(at: index) { setObjectValue(value) } }
    @ObjCMethod("selectItemWithObjectValue:") func selectItem(withObjectValue value: NSObject?) { setObjectValue(value) }
    @ObjCMethod("objectValueOfSelectedItem") func objectValueOfSelectedItem() -> NSObject? { itemObjectValue(at: indexOfSelectedItem()) }
    @ObjCMethod("usesDataSource") func comboUsesDataSource() -> Bool { usesDataSource }
    @ObjCMethod("setUsesDataSource:") func setUsesDataSource(_ value: Bool) { usesDataSource = value }
    @ObjCMethod("dataSource") func comboDataSource() -> NSObject? { dataSourceObject.map(NSObject.init) }
    @ObjCMethod("setDataSource:") func setDataSource(_ value: NSObject?) { dataSourceObject = value?.objcObject }
    @ObjCMethod("completes") func comboCompletes() -> Bool { completes }
    @ObjCMethod("setCompletes:") func setCompletes(_ value: Bool) { completes = value }
    @ObjCMethod("numberOfVisibleItems") func numberOfVisibleItems() -> Int { visibleItems }
    @ObjCMethod("setNumberOfVisibleItems:") func setNumberOfVisibleItems(_ value: Int) { visibleItems = value }
    @ObjCMethod("setHasVerticalScroller:") func setHasVerticalScroller(_ value: Bool) {}
    @ObjCMethod("setItemHeight:") func setItemHeight(_ value: CGFloat) {}
    @ObjCMethod("setButtonBordered:") func setButtonBordered(_ value: Bool) {}
    @ObjCMethod("reloadData") func reloadData() {}
    @ObjCMethod("noteNumberOfItemsChanged") func noteNumberOfItemsChanged() {}
    @ObjCMethod("scrollItemAtIndexToVisible:") func scrollItemAtIndexToVisible(_ index: Int) {}

    /// Its button, on the right, moves to the next item.
    @ObjCMethod("mouseDown:")
    override func mouseDown(_ event: NSObject?) {
        if let event = event?.as(NSEvent.self), convert(event.locationInWindow, from: nil).x > bounds.width - 22 {
            let count = numberOfItems()
            guard count > 0 else { return }
            selectItem(at: (indexOfSelectedItem() + 1) % count)
            _ = sendAction(action, to: target.map(NSObject.init))
            return
        }
        super.mouseDown(event)
    }
}

@ObjCClass("NSColorWell")
open class NSColorWell: NSControl {
    var color: NSColor = NSColor.whiteColor()
    var bordered = true
    var active = false

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init(coder: coder)
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        color = decoded.object("NSColor")?.as(NSColor.self) ?? color
        if decoded.has("NSIsBordered") { bordered = decoded.bool("NSIsBordered") }
    }

    public required init() { super.init() }
    @ObjCMethod("initWithFrame:")
    public required init(frame: CGRect) { super.init(frame: frame) }

    @ObjCMethod("color") func wellColor() -> NSColor { color }
    @ObjCMethod("setColor:") func setColor(_ value: NSColor?) { color = value ?? color; setNeedsDisplay(true) }
    @ObjCMethod("isBordered") func isBordered() -> Bool { bordered }
    @ObjCMethod("setBordered:") func setBordered(_ value: Bool) { bordered = value; setNeedsDisplay(true) }
    @ObjCMethod("isActive") func isActive() -> Bool { active }
    @ObjCMethod("activate:") func activate(_ exclusive: Bool) { active = true }
    @ObjCMethod("deactivate") func deactivate() { active = false }
    @ObjCMethod("objectValue") override func objectValue() -> NSObject? { color }
    @ObjCMethod("setColorWellStyle:") func setColorWellStyle(_ value: Int) {}
    @ObjCMethod("setSupportsAlpha:") func setSupportsAlpha(_ value: Bool) {}

    @ObjCMethod("drawRect:")
    override func draw(_ rect: CGRect) {
        guard let context = NSGraphicsContext.currentCG else { return }
        let well = bounds.insetBy(dx: bordered ? 4 : 0, dy: bordered ? 4 : 0)
        if bordered {
            CG.fill(CG.roundedRect(bounds.insetBy(dx: 0.5, dy: 0.5), radius: 4), NSColor.whiteColor(), in: context)
            CG.stroke(CG.roundedRect(bounds.insetBy(dx: 0.5, dy: 0.5), radius: 4), NSColor(white: 0, alpha: 0.2), in: context)
        }
        CG.fill(CG.roundedRect(well, radius: 2), color, in: context)
    }
}

import CPerryGeometry
import Glibc
import PerryObjCInterop
import SDL3Swift

// NSControl and the basic controls: a control keeps its values in its cell
// (made from +cellClass, or decoded from its nib) and draws it in its
// bounds. Buttons highlight while pressed and send their action when
// released over them, toggling their state first when they show one; text
// fields take keys while they are the first responder and tell their
// delegate as their text changes. NSAlert shows its message in an SDL
// message box (and on stderr) and answers with its first button; save and
// open panels answer Cancel.

@ObjCClass("NSControl")
open class NSControl: NSView {
    /// Not retained.
    var target: UnsafeMutableRawPointer?
    var action: ObjCSelector?
    var cellObject: NSCell?
    /// What template images take as their color, the label color without one.
    var tintColor: NSColor?
    /// A control without a cell keeps its values here.
    private var ownEnabled = true
    var ignoresMultiClick = false
    var refusesFirstResponder = false
    /// The mouse is down in the control and was last inside it.
    var tracking = false

    public required init() {
        super.init()
        makeCell()
    }

    @ObjCMethod("initWithFrame:")
    public required init(frame: CGRect) {
        super.init(frame: frame)
        makeCell()
    }

    /// NSControl's archive: its cell ("NSCell"), whether it is enabled, and
    /// a target and action it was archived with (as a scroller's).
    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init(coder: coder)
        guard let coder else {
            makeCell()
            return
        }
        let decoded = Coder(coder: coder)
        if let cell = decoded.object("NSCell")?.as(NSCell.self) {
            adopt(cell)
        } else {
            makeCell()
        }
        if decoded.has("NSEnabled") { enabled = decoded.bool("NSEnabled") }
        if let target = decoded.object("NSControlTarget") ?? decoded.object("NSTarget") { self.target = target.objcObject }
        if let action = decoded.string("NSControlAction") ?? decoded.string("NSAction") { self.action = ObjCSelector(action) }
        refusesFirstResponder = decoded.bool("NSControlRefusesFirstResponder")
        if let cell = cellObject {
            tag = cell.tag
            if decoded.has("NSControlUsesSingleLineMode"), decoded.bool("NSControlUsesSingleLineMode") { cell.usesSingleLineMode = true }
        } else {
            tag = decoded.integer("NSTag")
        }
    }

    /// The cell of the control's +cellClass.
    private func makeCell() {
        guard let cls = Send.object(ObjCRuntime.objectClass(objcObject), "cellClass"),
              let allocated = Send.object(cls, "alloc"), let made = Send.object(allocated, "init") else { return }
        adopt(NSCell.objCInstance(made, ownership: .adopt))
        cellDidAppear()
    }

    private func adopt(_ cell: NSCell) {
        cellObject = cell
        cell.controlViewObject = objcObject
    }

    /// A control class's own settings for a cell it made.
    func cellDidAppear() {}

    @ObjCClassMethod("cellClass") static func cellClass() -> ObjCClass? { Classes.named("NSActionCell") }
    @ObjCClassMethod("setCellClass:") static func setCellClass(_ cls: ObjCClass?) {}

    // MARK: Values, kept by the cell

    var text: String {
        get { cellObject?.cellString ?? "" }
        set { cellObject?.setStringValue(newValue) }
    }
    var doubleValue: Double {
        get { cellObject?.doubleValue() ?? 0 }
        set { cellObject?.setDoubleValue(newValue) }
    }
    var font: NSObject? {
        get { cellObject?.font }
        set { cellObject?.font = newValue?.as(NSFont.self) }
    }
    var alignment: Int {
        get { cellObject?.alignment ?? 4 }
        set { cellObject?.alignment = newValue }
    }
    var enabled: Bool {
        get { cellObject?.enabled ?? ownEnabled }
        set {
            ownEnabled = newValue
            cellObject?.enabled = newValue
        }
    }

    @ObjCMethod("cell") func cell() -> NSCell? { cellObject }
    @ObjCMethod("setCell:")
    func setCell(_ cell: NSCell?) {
        cellObject = cell
        cell?.controlViewObject = objcObject
        setNeedsDisplay(true)
    }
    @ObjCMethod("selectedCell") func selectedCell() -> NSCell? { cellObject }
    @ObjCMethod("selectedTag") func selectedTag() -> Int { cellObject?.tag ?? tag }
    @ObjCMethod("target") func controlTarget() -> NSObject? { target.map(NSObject.init) }
    @ObjCMethod("setTarget:") func setTarget(_ target: NSObject?) { self.target = target?.objcObject }
    @ObjCMethod("action") func controlAction() -> ObjCSelector? { action }
    @ObjCMethod("setAction:") func setAction(_ action: ObjCSelector?) { self.action = action }
    @ObjCMethod("isEnabled") func isEnabled() -> Bool { enabled }
    @ObjCMethod("setEnabled:")
    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        setNeedsDisplay(true)
    }
    @ObjCMethod("objectValue") func objectValue() -> NSObject? { cellObject.flatMap { Send.object($0.objcObject, "objectValue") }.map(NSObject.init) }
    @ObjCMethod("setObjectValue:")
    func setObjectValue(_ value: NSObject?) {
        Send.void(cellObject?.objcObject, "setObjectValue:", value?.objcObject)
        valueChanged()
    }
    @ObjCMethod("stringValue")
    func controlStringValue() -> String { cellObject.flatMap { Send.object($0.objcObject, "stringValue") }.map { String(objCArgument: $0) } ?? "" }
    @ObjCMethod("setStringValue:")
    func setStringValue(_ value: String?) {
        Send.void(cellObject?.objcObject, "setStringValue:", (value ?? "").objCArgument())
        valueChanged()
    }
    @ObjCMethod("attributedStringValue") func attributedStringValue() -> NSObject? { cellObject?.attributedStringValue() }
    @ObjCMethod("setAttributedStringValue:")
    func setAttributedStringValue(_ value: NSObject?) {
        cellObject?.setObjectValue(value)
        valueChanged()
    }
    @ObjCMethod("doubleValue") func controlDoubleValue() -> Double { cellObject.map { Send.double($0.objcObject, "doubleValue") } ?? 0 }
    @ObjCMethod("setDoubleValue:")
    func setDoubleValue(_ value: Double) {
        setObjectValue(NSNumber.make(double: value))
    }
    @ObjCMethod("intValue") func intValue() -> Int32 { Int32(truncatingIfNeeded: integerValue()) }
    @ObjCMethod("setIntValue:") func setIntValue(_ value: Int32) { setIntegerValue(Int(value)) }
    @ObjCMethod("integerValue") func integerValue() -> Int { cellObject.map { Send.integer($0.objcObject, "integerValue") } ?? 0 }
    @ObjCMethod("setIntegerValue:") func setIntegerValue(_ value: Int) { setObjectValue(NSNumber.make(integer: value)) }
    @ObjCMethod("floatValue") func floatValue() -> Float { Float(controlDoubleValue()) }
    @ObjCMethod("setFloatValue:") func setFloatValue(_ value: Float) { setDoubleValue(Double(value)) }
    @ObjCMethod("boolValue") func boolValue() -> Bool { integerValue() != 0 }
    @ObjCMethod("takeObjectValueFrom:") func takeObjectValue(from sender: NSObject?) { setObjectValue(sender.flatMap { Send.object($0.objcObject, "objectValue") }.map(NSObject.init)) }
    @ObjCMethod("takeStringValueFrom:") func takeStringValue(from sender: NSObject?) { setObjectValue(sender.flatMap { Send.object($0.objcObject, "stringValue") }.map(NSObject.init)) }
    @ObjCMethod("takeIntValueFrom:") func takeIntValue(from sender: NSObject?) { setIntegerValue(sender.map { Send.integer($0.objcObject, "integerValue") } ?? 0) }
    @ObjCMethod("takeDoubleValueFrom:") func takeDoubleValue(from sender: NSObject?) { setDoubleValue(sender.map { Send.double($0.objcObject, "doubleValue") } ?? 0) }
    @ObjCMethod("font") func controlFont() -> NSObject? { cellObject?.font }
    @ObjCMethod("setFont:")
    func setFont(_ font: NSObject?) {
        // The same font again changes nothing: views that set their fields'
        // fonts as they lay out would otherwise lay out every frame.
        let font = font?.as(NSFont.self)
        if let old = cellObject?.font, let font, old === font || old.isEqual(font) { return }
        cellObject?.font = font
        valueChanged()
    }
    @ObjCMethod("alignment") func controlAlignment() -> Int { alignment }
    @ObjCMethod("setAlignment:") func setAlignment(_ alignment: Int) { self.alignment = alignment; setNeedsDisplay(true) }
    @ObjCMethod("formatter") func controlFormatter() -> NSObject? { cellObject?.formatter }
    @ObjCMethod("setFormatter:") func setFormatter(_ formatter: NSObject?) { cellObject?.formatter = formatter; valueChanged() }
    @ObjCMethod("controlSize") func controlControlSize() -> UInt { cellObject?.controlSize ?? 0 }
    @ObjCMethod("setControlSize:") func setControlSize(_ size: UInt) { cellObject?.controlSize = size }
    @ObjCMethod("isContinuous") func isContinuous() -> Bool { cellObject?.continuous ?? false }
    @ObjCMethod("setContinuous:") func setContinuous(_ value: Bool) { cellObject?.continuous = value }
    @ObjCMethod("lineBreakMode") func controlLineBreakMode() -> Int { cellObject?.lineBreakMode ?? 0 }
    @ObjCMethod("setLineBreakMode:") func setLineBreakMode(_ mode: Int) { cellObject?.setLineBreakMode(mode); setNeedsDisplay(true) }
    @ObjCMethod("usesSingleLineMode") func usesSingleLineMode() -> Bool { cellObject?.usesSingleLineMode ?? false }
    @ObjCMethod("setUsesSingleLineMode:") func setUsesSingleLineMode(_ value: Bool) { cellObject?.usesSingleLineMode = value }
    @ObjCMethod("ignoresMultiClick") func controlIgnoresMultiClick() -> Bool { ignoresMultiClick }
    @ObjCMethod("setIgnoresMultiClick:") func setIgnoresMultiClick(_ value: Bool) { ignoresMultiClick = value }
    @ObjCMethod("refusesFirstResponder") func controlRefusesFirstResponder() -> Bool { refusesFirstResponder }
    @ObjCMethod("setRefusesFirstResponder:") func setRefusesFirstResponder(_ value: Bool) { refusesFirstResponder = value }
    @ObjCMethod("isHighlighted") func isHighlighted() -> Bool { cellObject?.highlighted ?? false }
    @ObjCMethod("setHighlighted:") func setHighlighted(_ value: Bool) { cellObject?.setHighlighted(value) }
    @ObjCMethod("allowsExpansionToolTips") func allowsExpansionToolTips() -> Bool { false }
    @ObjCMethod("setAllowsExpansionToolTips:") func setAllowsExpansionToolTips(_ value: Bool) {}
    @ObjCMethod("currentEditor") func currentEditor() -> NSObject? { nil }
    @ObjCMethod("abortEditing") func abortEditing() -> Bool { false }
    @ObjCMethod("validateEditing") func validateEditing() {}
    @ObjCMethod("updateCell:") func updateCell(_ cell: NSObject?) { setNeedsDisplay(true) }
    @ObjCMethod("updateCellInside:") func updateCellInside(_ cell: NSObject?) { setNeedsDisplay(true) }
    @ObjCMethod("drawCell:") func drawCell(_ cell: NSObject?) { setNeedsDisplay(true) }
    @ObjCMethod("drawCellInside:") func drawCellInside(_ cell: NSObject?) { setNeedsDisplay(true) }
    @ObjCMethod("calcSize") func calcSize() {}
    @ObjCMethod("sendActionOn:") func sendAction(on mask: UInt) -> Int { 0 }

    /// The value changed: drawn again, and laid out for its new size.
    func valueChanged() {
        setNeedsDisplay(true)
        invalidateIntrinsicContentSize()
    }

    @ObjCMethod("sizeToFit")
    func sizeToFit() {
        guard let cell = cellObject else { return }
        let size = Send.size(cell.objcObject, "cellSize")
        Send.void(objcObject, "setFrameSize:", size: CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up)))
    }

    @ObjCMethod("sizeThatFits:") func size(thatFits size: CGSize) -> CGSize { cellObject.map { Send.size($0.objcObject, "cellSize") } ?? size }

    @ObjCMethod("intrinsicContentSize")
    override func intrinsicContentSize() -> CGSize {
        guard let cell = cellObject else { return CGSize(width: -1, height: -1) }
        return Send.size(cell.objcObject, "cellSize")
    }

    @ObjCMethod("isFlipped") override func isFlipped() -> Bool { true }

    @ObjCMethod("drawRect:")
    override func draw(_ rect: CGRect) {
        guard let cell = cellObject else { return }
        typealias F = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, CGRect, UnsafeMutableRawPointer?) -> Void
        unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(cell.objcObject, ObjCRuntime.selector("drawWithFrame:inView:"), bounds, objcObject)
    }

    /// Sends the action to the target, or along the responder chain.
    @ObjCMethod("sendAction:to:")
    func sendAction(_ action: ObjCSelector?, to target: NSObject?) -> Bool {
        guard let action, let app = App.shared else { return false }
        return app.sendAction(action, to: target, from: self)
    }

    @ObjCMethod("performClick:")
    func performClick(_ sender: NSObject?) { _ = sendAction(action, to: target.map(NSObject.init)) }

    /// Whether the control acts on a click: buttons, sliders and the like.
    var tracksClicks: Bool { false }

    @ObjCMethod("mouseDown:")
    override func mouseDown(_ event: NSObject?) {
        guard enabled, tracksClicks else { return super.mouseDown(event) }
        tracking = true
        cellObject?.setHighlighted(true)
    }

    @ObjCMethod("mouseDragged:")
    override func mouseDragged(_ event: NSObject?) {
        guard tracking, let event = event?.as(NSEvent.self) else { return super.mouseDragged(event) }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if cellObject?.highlighted != inside { cellObject?.setHighlighted(inside) }
    }

    @ObjCMethod("mouseUp:")
    override func mouseUp(_ event: NSObject?) {
        guard tracking else { return super.mouseUp(event) }
        tracking = false
        cellObject?.setHighlighted(false)
        guard let event = event?.as(NSEvent.self), bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        clicked()
    }

    /// A click was released over the control.
    func clicked() { Send.void(objcObject, "performClick:", nil) }

    @ObjCMethod("acceptsFirstMouse:") override func acceptsFirstMouse(_ event: NSObject?) -> Bool { true }
}

@ObjCClass("NSButton")
open class NSButton: NSControl {
    var buttonCell: NSButtonCell? { cellObject?.as(NSButtonCell.self) }

    static func make(title: String?, image: NSObject?, target: NSObject?, action: ObjCSelector?) -> NSButton {
        let button = NSButton(frame: CGRect(x: 0, y: 0, width: 80, height: 32))
        button.title = title ?? ""
        button.image = image
        button.target = target?.objcObject
        button.action = action
        if image != nil && (title ?? "").isEmpty { button.buttonCell?.imagePosition = 1 }
        button.sizeToFit()
        return button
    }

    @ObjCClassMethod("cellClass") static func buttonCellClass() -> ObjCClass? { NSButtonCell.objCClass }

    var title: String {
        get { buttonCell?.title ?? "" }
        set { buttonCell?.setTitle(newValue); valueChanged() }
    }
    var alternateTitle: String {
        get { buttonCell?.alternateTitle ?? "" }
        set { buttonCell?.alternateTitle = newValue }
    }
    var state: Int {
        get { cellObject?.state ?? 0 }
        set { cellObject?.setState(newValue) }
    }
    var keyEquivalent: String {
        get { buttonCell?.keyEquivalentValue ?? "" }
        set { buttonCell?.keyEquivalentValue = newValue }
    }
    var keyEquivalentModifierMask: UInt {
        get { buttonCell?.keyEquivalentModifierMask ?? 0 }
        set { buttonCell?.keyEquivalentModifierMask = newValue }
    }
    var image: NSObject? {
        get { cellObject?.image }
        set {
            // A button that showed no image shows the one it is given, as
            // AppKit's do.
            if newValue != nil, let cell = buttonCell, cell.imagePosition == 0 { cell.setImagePosition(1) }
            cellObject?.setImage(newValue?.as(NSImage.self))
            valueChanged()
        }
    }
    var buttonType: UInt {
        get { buttonCell?.buttonType ?? 7 }
        set { buttonCell?.setButtonType(newValue) }
    }
    var bezelStyle: UInt {
        get { buttonCell?.bezelStyle ?? 1 }
        set { buttonCell?.setBezelStyle(newValue) }
    }
    var bordered: Bool {
        get { cellObject?.bordered ?? true }
        set { cellObject?.setBordered(newValue) }
    }

    @ObjCClassMethod("buttonWithTitle:target:action:")
    static func button(title: String?, target: NSObject?, action: ObjCSelector?) -> NSButton { make(title: title, image: nil, target: target, action: action) }
    @ObjCClassMethod("buttonWithImage:target:action:")
    static func button(image: NSObject?, target: NSObject?, action: ObjCSelector?) -> NSButton { make(title: "", image: image, target: target, action: action) }
    @ObjCClassMethod("buttonWithTitle:image:target:action:")
    static func button(title: String?, image: NSObject?, target: NSObject?, action: ObjCSelector?) -> NSButton {
        make(title: title, image: image, target: target, action: action)
    }
    @ObjCClassMethod("checkboxWithTitle:target:action:")
    static func checkbox(title: String?, target: NSObject?, action: ObjCSelector?) -> NSButton {
        let button = make(title: title, image: nil, target: target, action: action)
        button.buttonType = 3
        button.sizeToFit()
        return button
    }
    @ObjCClassMethod("radioButtonWithTitle:target:action:")
    static func radioButton(title: String?, target: NSObject?, action: ObjCSelector?) -> NSButton {
        let button = make(title: title, image: nil, target: target, action: action)
        button.buttonType = 4
        button.sizeToFit()
        return button
    }

    @ObjCMethod("title") func buttonTitle() -> String { title }
    @ObjCMethod("setTitle:") func setTitle(_ title: String?) { self.title = title ?? "" }
    @ObjCMethod("alternateTitle") func buttonAlternateTitle() -> String { alternateTitle }
    @ObjCMethod("setAlternateTitle:") func setAlternateTitle(_ title: String?) { alternateTitle = title ?? "" }
    @ObjCMethod("attributedTitle") func attributedTitle() -> NSObject? { buttonCell?.cellAttributedTitle() }
    @ObjCMethod("setAttributedTitle:") func setAttributedTitle(_ title: NSObject?) { buttonCell?.setAttributedTitle(title); valueChanged() }
    @ObjCMethod("setAttributedAlternateTitle:") func setAttributedAlternateTitle(_ title: NSObject?) {}
    @ObjCMethod("state") func buttonState() -> Int { state }
    @ObjCMethod("setState:") func setState(_ state: Int) { self.state = state }
    @ObjCMethod("keyEquivalent") func buttonKeyEquivalent() -> String { keyEquivalent }
    @ObjCMethod("setKeyEquivalent:") func setKeyEquivalent(_ key: String?) { keyEquivalent = key ?? "" }
    @ObjCMethod("keyEquivalentModifierMask") func buttonKeyEquivalentModifierMask() -> UInt { keyEquivalentModifierMask }
    @ObjCMethod("setKeyEquivalentModifierMask:") func setKeyEquivalentModifierMask(_ mask: UInt) { keyEquivalentModifierMask = mask }
    @ObjCMethod("image") func buttonImage() -> NSObject? { image }
    @ObjCMethod("setImage:") func setImage(_ image: NSObject?) { self.image = image }
    @ObjCMethod("alternateImage") func alternateImage() -> NSObject? { buttonCell?.alternateImage }
    @ObjCMethod("setAlternateImage:") func setAlternateImage(_ image: NSObject?) { buttonCell?.setAlternateImage(image?.as(NSImage.self)) }
    @ObjCMethod("imagePosition") func imagePosition() -> UInt { buttonCell?.imagePosition ?? 0 }
    @ObjCMethod("setImagePosition:") func setImagePosition(_ position: UInt) { buttonCell?.setImagePosition(position) }
    @ObjCMethod("imageScaling") func imageScaling() -> UInt { buttonCell?.imageScaling ?? 0 }
    @ObjCMethod("setImageScaling:") func setImageScaling(_ scaling: UInt) { buttonCell?.setImageScaling(scaling) }
    @ObjCMethod("setImageHugsTitle:") func setImageHugsTitle(_ value: Bool) {}
    @ObjCMethod("setButtonType:") func setButtonType(_ type: UInt) { buttonType = type }
    @ObjCMethod("bezelStyle") func buttonBezelStyle() -> UInt { bezelStyle }
    @ObjCMethod("setBezelStyle:") func setBezelStyle(_ style: UInt) { bezelStyle = style }
    @ObjCMethod("isBordered") func isBordered() -> Bool { bordered }
    @ObjCMethod("setBordered:") func setBordered(_ value: Bool) { bordered = value }
    @ObjCMethod("isTransparent") func isTransparent() -> Bool { buttonCell?.transparent ?? false }
    @ObjCMethod("setTransparent:") func setTransparent(_ value: Bool) { buttonCell?.setTransparent(value) }
    @ObjCMethod("bezelColor") func bezelColor() -> NSObject? { buttonCell?.bezelColor }
    @ObjCMethod("setBezelColor:") func setBezelColor(_ color: NSObject?) { buttonCell?.setBezelColor(color?.as(NSColor.self)) }
    @ObjCMethod("contentTintColor") func contentTintColor() -> NSColor? { tintColor }
    @ObjCMethod("setContentTintColor:") func setContentTintColor(_ color: NSColor?) { tintColor = color; setNeedsDisplay(true) }
    @ObjCMethod("allowsMixedState") func allowsMixedState() -> Bool { cellObject?.allowsMixedState ?? false }
    @ObjCMethod("setAllowsMixedState:") func setAllowsMixedState(_ value: Bool) { cellObject?.allowsMixedState = value }
    @ObjCMethod("showsBorderOnlyWhileMouseInside") func showsBorderOnlyWhileMouseInside() -> Bool { buttonCell?.showsBorderOnlyWhileMouseInside ?? false }
    @ObjCMethod("setShowsBorderOnlyWhileMouseInside:") func setShowsBorderOnlyWhileMouseInside(_ value: Bool) { buttonCell?.showsBorderOnlyWhileMouseInside = value }
    @ObjCMethod("setNextState") func setNextState() { cellObject?.setNextState() }
    @ObjCMethod("highlight:") func highlight(_ value: Bool) { cellObject?.setHighlighted(value) }
    @ObjCMethod("setPeriodicDelay:interval:") func setPeriodicDelay(_ delay: Float, interval: Float) {}
    @ObjCMethod("setSound:") func setSound(_ sound: NSObject?) {}
    @ObjCMethod("setSpringLoaded:") func setSpringLoaded(_ value: Bool) {}
    @ObjCMethod("setMaxAcceleratorLevel:") func setMaxAcceleratorLevel(_ value: Int) {}
    @ObjCMethod("setHasDestructiveAction:") func setHasDestructiveAction(_ value: Bool) {}
    @ObjCMethod("setSymbolConfiguration:") func setSymbolConfiguration(_ value: NSObject?) {}

    override var tracksClicks: Bool { true }

    /// Toggles a state the button shows, then sends the action.
    @ObjCMethod("performClick:")
    override func performClick(_ sender: NSObject?) {
        guard enabled else { return }
        if let cell = buttonCell {
            if cell.buttonType == 4 {
                cell.setState(1)
                // The radio buttons sharing its action and superview turn off.
                for sibling in superview?.subviews ?? [] where sibling !== self {
                    guard let other = sibling.as(NSButton.self), other.buttonType == 4, other.action == action else { continue }
                    other.state = 0
                }
            } else if cell.showsState {
                cell.setState(cell.state == 0 ? 1 : 0)
            }
        }
        _ = sendAction(action, to: target.map(NSObject.init))
    }

    @ObjCMethod("performKeyEquivalent:")
    override func performKeyEquivalent(_ event: NSObject?) -> Bool {
        guard let event = event?.as(NSEvent.self), enabled, !keyEquivalent.isEmpty, !hidden,
              event.charactersIgnoringModifiers == keyEquivalent,
              event.modifierFlags & 0xffff_0000 & ~ModifierFlags.capsLock == keyEquivalentModifierMask & 0xffff_0000 else { return false }
        performClick(nil)
        return true
    }
}

@ObjCClass("NSTextField")
open class NSTextField: NSControl {
    /// Not retained.
    var delegate: UnsafeMutableRawPointer?
    var editing = false
    var edited = false
    var preferredMaxLayoutWidth: CGFloat = 0
    var maximumNumberOfLines = 0

    var fieldCell: NSTextFieldCell? { cellObject?.as(NSTextFieldCell.self) }

    @ObjCClassMethod("cellClass") static func textFieldCellClass() -> ObjCClass? { NSTextFieldCell.objCClass }

    /// A field made in code is an editable, bezeled box.
    override func cellDidAppear() {
        guard let cell = fieldCell else { return }
        (cell.editable, cell.selectable, cell.bezeled, cell.drawsBackground) = (true, true, true, true)
        cell.backgroundColor = NSColor.textBackgroundColor()
        cell.usesSingleLineMode = false
        cell.wraps = false
        cell.lineBreakMode = 2
    }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init(coder: coder)
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        preferredMaxLayoutWidth = decoded.double("NSPreferredMaxLayoutWidth")
        maximumNumberOfLines = decoded.integer("NSTextFieldMaximumNumberOfLines")
    }

    public required init() { super.init() }

    @ObjCMethod("initWithFrame:")
    public required init(frame: CGRect) { super.init(frame: frame) }

    static func make(_ text: String?, editable: Bool, wrapping: Bool = false) -> NSTextField {
        let field = NSTextField(frame: CGRect(x: 0, y: 0, width: 200, height: 22))
        field.text = text ?? ""
        if !editable, let cell = field.fieldCell {
            (cell.editable, cell.selectable, cell.bezeled, cell.bordered, cell.drawsBackground) = (false, false, false, false, false)
            cell.wraps = wrapping
            cell.lineBreakMode = wrapping ? 0 : 2
        }
        field.sizeToFit()
        return field
    }

    @ObjCClassMethod("labelWithString:") static func label(string: String?) -> NSTextField { make(string, editable: false) }
    @ObjCClassMethod("wrappingLabelWithString:") static func wrappingLabel(string: String?) -> NSTextField { make(string, editable: false, wrapping: true) }
    @ObjCClassMethod("labelWithAttributedString:")
    static func label(attributedString: NSObject?) -> NSTextField {
        let field = make(nil, editable: false)
        field.setAttributedStringValue(attributedString)
        field.sizeToFit()
        return field
    }
    @ObjCClassMethod("textFieldWithString:") static func textField(string: String?) -> NSTextField { make(string, editable: true) }

    @ObjCMethod("isEditable") func isEditable() -> Bool { fieldCell?.editable ?? false }
    @ObjCMethod("setEditable:") func setEditable(_ value: Bool) { fieldCell?.editable = value }
    @ObjCMethod("isSelectable") func isSelectable() -> Bool { fieldCell?.isSelectable() ?? false }
    @ObjCMethod("setSelectable:") func setSelectable(_ value: Bool) { fieldCell?.selectable = value }
    @ObjCMethod("placeholderString") func placeholderString() -> String? { fieldCell?.placeholderString() }
    @ObjCMethod("setPlaceholderString:") func setPlaceholderString(_ text: String?) { fieldCell?.setPlaceholderString(text) }
    @ObjCMethod("placeholderAttributedString") func placeholderAttributedString() -> NSObject? { fieldCell?.placeholder }
    @ObjCMethod("setPlaceholderAttributedString:") func setPlaceholderAttributedString(_ text: NSObject?) { fieldCell?.setPlaceholderAttributedString(text) }
    @ObjCMethod("textColor") func fieldTextColor() -> NSObject? { fieldCell?.cellTextColor() }
    @ObjCMethod("setTextColor:") func setTextColor(_ color: NSObject?) { fieldCell?.setTextColor(color?.as(NSColor.self)) }
    @ObjCMethod("backgroundColor") func backgroundColor() -> NSObject? { fieldCell?.backgroundColor }
    @ObjCMethod("setBackgroundColor:") func setBackgroundColor(_ color: NSObject?) { fieldCell?.setBackgroundColor(color?.as(NSColor.self)) }
    @ObjCMethod("drawsBackground") func drawsBackground() -> Bool { fieldCell?.drawsBackground ?? false }
    @ObjCMethod("setDrawsBackground:") func setDrawsBackground(_ value: Bool) { fieldCell?.setDrawsBackground(value) }
    @ObjCMethod("isBezeled") func isBezeled() -> Bool { cellObject?.bezeled ?? false }
    @ObjCMethod("setBezeled:") func setBezeled(_ value: Bool) { cellObject?.setBezeled(value); invalidateIntrinsicContentSize() }
    @ObjCMethod("isBordered") func isBordered() -> Bool { cellObject?.bordered ?? false }
    @ObjCMethod("setBordered:") func setBordered(_ value: Bool) { cellObject?.setBordered(value) }
    @ObjCMethod("bezelStyle") func bezelStyle() -> UInt { fieldCell?.bezelStyle ?? 0 }
    @ObjCMethod("setBezelStyle:") func setBezelStyle(_ style: UInt) { fieldCell?.setBezelStyle(style) }
    @ObjCMethod("delegate") func fieldDelegate() -> NSObject? { delegate.map(NSObject.init) }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { self.delegate = delegate?.objcObject }
    @ObjCMethod("maximumNumberOfLines") func fieldMaximumNumberOfLines() -> Int { maximumNumberOfLines }
    @ObjCMethod("setMaximumNumberOfLines:") func setMaximumNumberOfLines(_ lines: Int) { maximumNumberOfLines = lines; setNeedsDisplay(true) }
    @ObjCMethod("preferredMaxLayoutWidth") func fieldPreferredMaxLayoutWidth() -> CGFloat { preferredMaxLayoutWidth }
    @ObjCMethod("setPreferredMaxLayoutWidth:") func setPreferredMaxLayoutWidth(_ width: CGFloat) { preferredMaxLayoutWidth = width; invalidateIntrinsicContentSize() }
    @ObjCMethod("allowsEditingTextAttributes") func allowsEditingTextAttributes() -> Bool { cellObject?.allowsEditingTextAttributes ?? false }
    @ObjCMethod("setAllowsEditingTextAttributes:") func setAllowsEditingTextAttributes(_ value: Bool) { cellObject?.allowsEditingTextAttributes = value }
    @ObjCMethod("setImportsGraphics:") func setImportsGraphics(_ value: Bool) {}
    @ObjCMethod("setAllowsDefaultTighteningForTruncation:") func setAllowsDefaultTighteningForTruncation(_ value: Bool) {}
    @ObjCMethod("setLineBreakStrategy:") func setLineBreakStrategy(_ value: UInt) {}
    @ObjCMethod("setAutomaticTextCompletionEnabled:") func setAutomaticTextCompletionEnabled(_ value: Bool) {}
    @ObjCMethod("setAllowsCharacterPickerTouchBarItem:") func setAllowsCharacterPickerTouchBarItem(_ value: Bool) {}
    @ObjCMethod("setTextContentType:") func setTextContentType(_ value: NSObject?) {}
    @ObjCMethod("selectText:")
    func selectText(_ sender: NSObject?) { _ = window?.makeFirstResponder(self) }

    @ObjCMethod("intrinsicContentSize")
    override func intrinsicContentSize() -> CGSize {
        guard let cell = fieldCell else { return super.intrinsicContentSize() }
        let lineHeight = Text.lineHeight(cell.effectiveFont)
        if cell.editable && cell.bezeled { return CGSize(width: -1, height: lineHeight + 6) }
        let width = preferredMaxLayoutWidth > 0 ? preferredMaxLayoutWidth - 4 : cell.wraps && frame.width > 0 && !translatesAutoresizingMask ? frame.width - 4 : .infinity
        var style = cell.textStyle
        if maximumNumberOfLines > 0 { style.maximumLines = maximumNumberOfLines }
        let size = Text.size(cell.textRuns(color: nil), width: cell.wraps ? width : .infinity, style: style)
        return CGSize(width: (size.width + 4).rounded(.up), height: max(size.height, lineHeight) + (cell.bezeled ? 6 : cell.bordered ? 2 : 0))
    }

    @ObjCMethod("acceptsFirstResponder") override func acceptsFirstResponder() -> Bool { (fieldCell?.isSelectable() ?? false) && enabled && !refusesFirstResponder }

    @ObjCMethod("becomeFirstResponder")
    override func becomeFirstResponder() -> Bool {
        guard fieldCell?.editable == true else { return true }
        editing = true
        edited = false
        setNeedsDisplay(true)
        return true
    }

    @ObjCMethod("resignFirstResponder")
    override func resignFirstResponder() -> Bool {
        guard editing else { return true }
        editing = false
        setNeedsDisplay(true)
        if edited {
            notify("controlTextDidEndEditing:", "NSControlTextDidEndEditingNotification")
            if fieldCell?.sendsActionOnEndEditing == true { _ = sendAction(action, to: target.map(NSObject.init)) }
        }
        return true
    }

    /// The delegate hears of editing as AppKit's text fields tell it.
    private func notify(_ selector: String, _ name: String) {
        let notification = NSNotification.make(name: name, object: self)
        if let delegate, Send.responds(delegate, selector) { Send.void(delegate, selector, notification.objcObject) }
        NSNotificationCenter.defaultCenter().post(notification)
    }

    @ObjCMethod("keyDown:")
    override func keyDown(_ eventObject: NSObject?) {
        guard editing, let event = eventObject?.as(NSEvent.self) else { return super.keyDown(eventObject) }
        var value = controlStringValue()
        let typed = event.characters
        switch typed {
        case "\r", "\u{3}":
            edited = true
            _ = sendAction(action, to: target.map(NSObject.init))
            return
        case "\t", "\u{19}":
            if let next = nextKeyView { _ = window?.makeFirstResponder(next) } else { _ = window?.makeFirstResponder(nil) }
            return
        case "\u{1b}":
            return
        case "\u{7f}", "\u{8}":
            guard !value.isEmpty else { return }
            value.removeLast()
        default:
            // Arrow and function keys come as characters of the private use area.
            guard !typed.isEmpty, event.modifierFlags & ModifierFlags.command == 0,
                  typed.unicodeScalars.allSatisfy({ $0.value >= 0x20 && !(0xF700...0xF8FF).contains($0.value) }) else {
                return super.keyDown(eventObject)
            }
            value += typed
        }
        if !edited { notify("controlTextDidBeginEditing:", "NSControlTextDidBeginEditingNotification") }
        edited = true
        cellObject?.setStringValue(value)
        valueChanged()
        notify("controlTextDidChange:", "NSControlTextDidChangeNotification")
        if cellObject?.continuous == true { _ = sendAction(action, to: target.map(NSObject.init)) }
    }

    @ObjCMethod("performKeyEquivalent:")
    override func performKeyEquivalent(_ event: NSObject?) -> Bool { false }
}

@ObjCClass("NSSecureTextField")
open class NSSecureTextField: NSTextField {
    @ObjCClassMethod("cellClass") static func secureCellClass() -> ObjCClass? { NSSecureTextFieldCell.objCClass }
}

@ObjCClass("NSImageView")
open class NSImageView: NSControl {
    var imageCell: NSImageCell? { cellObject?.as(NSImageCell.self) }
    var image: NSObject? {
        get { cellObject?.image }
        set {
            cellObject?.image = newValue?.as(NSImage.self)
            valueChanged()
        }
    }

    @ObjCClassMethod("cellClass") static func imageCellClass() -> ObjCClass? { NSImageCell.objCClass }

    @ObjCClassMethod("imageViewWithImage:")
    static func imageView(image: NSObject?) -> NSImageView {
        let size = image?.as(NSImage.self)?.size ?? CGSize(width: 32, height: 32)
        let view = NSImageView(frame: CGRect(origin: .zero, size: size))
        view.image = image
        return view
    }

    @ObjCMethod("image") func viewImage() -> NSObject? { image }
    @ObjCMethod("setImage:") func setImage(_ image: NSObject?) { self.image = image }
    @ObjCMethod("imageScaling") func imageScaling() -> UInt { imageCell?.imageScaling ?? 0 }
    @ObjCMethod("setImageScaling:") func setImageScaling(_ scaling: UInt) { imageCell?.setImageScaling(scaling) }
    @ObjCMethod("imageAlignment") func imageAlignment() -> UInt { imageCell?.imageAlignment ?? 0 }
    @ObjCMethod("setImageAlignment:") func setImageAlignment(_ alignment: UInt) { imageCell?.setImageAlignment(alignment) }
    @ObjCMethod("imageFrameStyle") func imageFrameStyle() -> UInt { imageCell?.imageFrameStyle ?? 0 }
    @ObjCMethod("setImageFrameStyle:") func setImageFrameStyle(_ style: UInt) { imageCell?.setImageFrameStyle(style) }
    @ObjCMethod("setAnimates:") func setAnimates(_ value: Bool) {}
    @ObjCMethod("setEditable:") func setEditable(_ value: Bool) {}
    @ObjCMethod("isEditable") func isEditable() -> Bool { false }
    @ObjCMethod("contentTintColor") func contentTintColor() -> NSColor? { tintColor }
    @ObjCMethod("setContentTintColor:") func setContentTintColor(_ color: NSColor?) { tintColor = color; setNeedsDisplay(true) }
    @ObjCMethod("setSymbolConfiguration:") func setSymbolConfiguration(_ value: NSObject?) {}

    @ObjCMethod("intrinsicContentSize")
    override func intrinsicContentSize() -> CGSize { cellObject?.image?.size ?? CGSize(width: -1, height: -1) }
}

/// NSProgressIndicator: a bar, filled as far as its value, or a spinner.
/// NSProgressIndicatorStyle: bar 0, spinning 1.
@ObjCClass("NSProgressIndicator")
open class NSProgressIndicator: NSView {
    var indeterminate = true
    var minValue: Double = 0
    var maxValue: Double = 100
    var value: Double = 0
    var style: UInt = 0
    var animating = false
    var displayedWhenStopped = true
    var controlSize: UInt = 0

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init(coder: coder)
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        let flags = decoded.integer("NSpiFlags")
        indeterminate = flags & 2 != 0
        style = flags & 0x1000 != 0 ? 1 : 0
        displayedWhenStopped = flags & 0x2000 == 0
        if decoded.has("NSMinValue") { minValue = decoded.double("NSMinValue") }
        if decoded.has("NSMaxValue") { maxValue = decoded.double("NSMaxValue") }
    }

    public required init() { super.init() }

    @ObjCMethod("initWithFrame:")
    public required init(frame: CGRect) { super.init(frame: frame) }

    @ObjCMethod("isIndeterminate") func isIndeterminate() -> Bool { indeterminate }
    @ObjCMethod("setIndeterminate:") func setIndeterminate(_ value: Bool) { indeterminate = value; setNeedsDisplay(true) }
    @ObjCMethod("minValue") func progressMinValue() -> Double { minValue }
    @ObjCMethod("setMinValue:") func setMinValue(_ value: Double) { minValue = value; setNeedsDisplay(true) }
    @ObjCMethod("maxValue") func progressMaxValue() -> Double { maxValue }
    @ObjCMethod("setMaxValue:") func setMaxValue(_ value: Double) { maxValue = value; setNeedsDisplay(true) }
    @ObjCMethod("doubleValue") func doubleValue() -> Double { value }
    @ObjCMethod("setDoubleValue:") func setDoubleValue(_ value: Double) { self.value = value; setNeedsDisplay(true) }
    @ObjCMethod("incrementBy:") func increment(by delta: Double) { setDoubleValue(value + delta) }
    @ObjCMethod("style") func progressStyle() -> UInt { style }
    @ObjCMethod("setStyle:") func setStyle(_ style: UInt) { self.style = style; setNeedsDisplay(true) }
    @ObjCMethod("controlSize") func progressControlSize() -> UInt { controlSize }
    @ObjCMethod("setControlSize:") func setControlSize(_ size: UInt) { controlSize = size }
    @ObjCMethod("setUsesThreadedAnimation:") func setUsesThreadedAnimation(_ value: Bool) {}
    @ObjCMethod("isDisplayedWhenStopped") func isDisplayedWhenStopped() -> Bool { displayedWhenStopped }
    @ObjCMethod("setDisplayedWhenStopped:") func setDisplayedWhenStopped(_ value: Bool) { displayedWhenStopped = value; setNeedsDisplay(true) }
    @ObjCMethod("startAnimation:") func startAnimation(_ sender: NSObject?) { animating = true; setNeedsDisplay(true) }
    @ObjCMethod("stopAnimation:") func stopAnimation(_ sender: NSObject?) { animating = false; setNeedsDisplay(true) }
    @ObjCMethod("sizeToFit") func sizeToFit() {}
    @ObjCMethod("isFlipped") override func isFlipped() -> Bool { true }

    @ObjCMethod("drawRect:")
    override func draw(_ rect: CGRect) {
        guard let context = NSGraphicsContext.currentCG, animating || displayedWhenStopped else { return }
        if style == 1 {
            // Twelve spokes around the center, fading.
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            let radius = min(bounds.width, bounds.height) / 2
            for spoke in 0..<12 {
                let angle = CGFloat(spoke) * .pi / 6
                let (c, s) = (cos(angle), sin(angle))
                let line = Arrows.polyline([CGPoint(x: center.x + c * radius * 0.45, y: center.y + s * radius * 0.45),
                                            CGPoint(x: center.x + c * radius * 0.9, y: center.y + s * radius * 0.9)])
                CG.stroke(line, NSColor(white: 0, alpha: 0.15 + 0.6 * CGFloat(spoke) / 11), width: max(1.5, radius / 6), in: context)
            }
            return
        }
        let track = CGRect(x: bounds.minX, y: bounds.midY - 3, width: bounds.width, height: 6)
        CG.fill(CG.roundedRect(track, radius: 3), NSColor(white: 0, alpha: 0.1), in: context)
        let fraction = indeterminate ? (animating ? 0.35 : 0) : max(0, min(1, (value - minValue) / max(maxValue - minValue, .ulpOfOne)))
        guard fraction > 0 else { return }
        CG.fill(CG.roundedRect(CGRect(x: track.minX, y: track.minY, width: track.width * CGFloat(fraction), height: track.height), radius: 3),
                NSColor.controlAccentColor(), in: context)
    }
}

@ObjCClass("NSAlert")
open class NSAlert: NSObject {
    var messageText = ""
    var informativeText = ""
    var style: UInt = 0
    var buttons: [NSButton] = []
    var showsSuppressionButton = false
    var suppressionButton: NSButton?
    var accessoryView: NSObject?
    var icon: NSObject?
    var showsHelp = false
    var delegate: UnsafeMutableRawPointer?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCClassMethod("alertWithError:")
    static func alert(error: NSObject?) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = Send.object(error?.objcObject, "localizedDescription").map { String(objCArgument: $0) } ?? "An error occurred."
        alert.informativeText = Send.object(error?.objcObject, "localizedRecoverySuggestion").map { String(objCArgument: $0) } ?? ""
        return alert
    }

    @ObjCMethod("messageText") func alertMessageText() -> String { messageText }
    @ObjCMethod("setMessageText:") func setMessageText(_ text: String?) { messageText = text ?? "" }
    @ObjCMethod("informativeText") func alertInformativeText() -> String { informativeText }
    @ObjCMethod("setInformativeText:") func setInformativeText(_ text: String?) { informativeText = text ?? "" }
    /// NSAlertStyle: warning 0, informational 1, critical 2.
    @ObjCMethod("alertStyle") func alertStyle() -> UInt { style }
    @ObjCMethod("setAlertStyle:") func setAlertStyle(_ style: UInt) { self.style = style }
    @ObjCMethod("buttons") func alertButtons() -> NSObject { NSMutableArray.of(buttons) }

    /// Buttons answer NSAlertFirstButtonReturn (1000) and on, in order.
    @ObjCMethod("addButtonWithTitle:")
    func addButton(title: String?) -> NSButton {
        let button = NSButton.make(title: title, image: nil, target: nil, action: nil)
        button.tag = 1000 + buttons.count
        buttons.append(button)
        return button
    }

    @ObjCMethod("showsSuppressionButton") func alertShowsSuppressionButton() -> Bool { showsSuppressionButton }
    @ObjCMethod("setShowsSuppressionButton:") func setShowsSuppressionButton(_ value: Bool) { showsSuppressionButton = value }
    @ObjCMethod("suppressionButton")
    func alertSuppressionButton() -> NSButton? {
        if suppressionButton == nil {
            suppressionButton = NSButton.make(title: "Do not show this message again", image: nil, target: nil, action: nil)
            suppressionButton?.buttonType = 3
        }
        return suppressionButton
    }
    @ObjCMethod("accessoryView") func alertAccessoryView() -> NSObject? { accessoryView }
    @ObjCMethod("setAccessoryView:") func setAccessoryView(_ view: NSObject?) { accessoryView = view }
    @ObjCMethod("icon") func alertIcon() -> NSObject? { icon }
    @ObjCMethod("setIcon:") func setIcon(_ icon: NSObject?) { self.icon = icon }
    @ObjCMethod("showsHelp") func alertShowsHelp() -> Bool { showsHelp }
    @ObjCMethod("setShowsHelp:") func setShowsHelp(_ value: Bool) { showsHelp = value }
    @ObjCMethod("delegate") func alertDelegate() -> NSObject? { delegate.map(NSObject.init) }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { self.delegate = delegate?.objcObject }
    @ObjCMethod("layout") func layout() {}
    @ObjCMethod("window") func window() -> NSObject? { nil }

    /// Shows the message with the alert's buttons, the first one the default
    /// (Return) and a Cancel one Escape's, and answers with the one chosen:
    /// NSAlertFirstButtonReturn (1000) and on. With no display, or one
    /// button and PERRY_APPKIT_QUIET_ALERTS, it is only logged and the first
    /// button answers.
    @ObjCMethod("runModal")
    func runModal() -> Int {
        let titles = buttons.map(\.title)
        appKitWarning("alert: \(messageText)\(informativeText.isEmpty ? "" : " — \(informativeText)")"
                      + (titles.isEmpty ? "" : " [\(titles.joined(separator: ", "))]"))
        // PERRY_APPKIT_QUIET_ALERTS: an alert with no choice to make (one
        // button or none) is only logged, so a game showing one runs on.
        let quiet = getenv("PERRY_APPKIT_QUIET_ALERTS") != nil && titles.count <= 1
        guard !quiet, SDLSession.start() else { return 1000 }
        let flags: MessageBoxFlags = style == 2 ? .error : style == 1 ? .information : .warning
        let message = Self.wrapped(informativeText)
        guard !titles.isEmpty else {
            try? SDL.showSimpleMessageBox(flags: flags, title: messageText, message: message, window: Windows.key?.sdlWindow)
            return 1000
        }
        let cancel = titles.firstIndex { $0 == "Cancel" }
        let chosen = try? SDL.showMessageBox(flags: flags, title: messageText, message: message, buttons: titles,
                                             escapeIndex: cancel, window: Windows.key?.sdlWindow)
        // Closing the box answers as Escape would: with Cancel, if there is
        // one, else the first button.
        let index = chosen.flatMap { $0 } ?? (cancel ?? 0)
        return 1000 + index
    }

    /// Text broken into lines of at most about 80 characters at spaces, as
    /// SDL's boxes don't wrap it.
    static func wrapped(_ text: String, width: Int = 80) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { paragraph -> String in
            var lines: [String] = []
            var line = ""
            for word in paragraph.split(separator: " ", omittingEmptySubsequences: false) {
                if !line.isEmpty, line.count + 1 + word.count > width {
                    lines.append(line)
                    line = String(word)
                } else {
                    line += line.isEmpty ? String(word) : " " + word
                }
            }
            lines.append(line)
            return lines.joined(separator: "\n")
        }.joined(separator: "\n")
    }

    @ObjCMethod("beginSheetModalForWindow:completionHandler:")
    func beginSheetModal(for window: NSObject?, completionHandler: ObjCBlock?) {
        let response = runModal()
        if let completionHandler { Dispatch.onMain { Blocks.call(completionHandler, response) } }
    }

    @ObjCMethod("beginSheetModalForWindow:modalDelegate:didEndSelector:contextInfo:")
    func beginSheetModal(for window: NSObject?, modalDelegate: NSObject?, didEndSelector: ObjCSelector?, contextInfo: UnsafeMutableRawPointer?) {
        _ = runModal()
    }
}

/// NSSavePanel and NSOpenPanel: there is no file browser; they answer
/// Cancel (NSModalResponseCancel, 0) with no URL.
@ObjCClass("NSSavePanel")
open class NSSavePanel: NSPanel {
    var directoryURL: NSObject?
    var nameFieldStringValue = ""
    var message = ""
    var prompt = ""
    var accessory: NSObject?

    @ObjCClassMethod("savePanel")
    static func savePanel() -> NSSavePanel { NSSavePanel(contentRect: CGRect(x: 0, y: 0, width: 480, height: 320), styleMask: 3, backing: 2, defer: true) }

    @ObjCMethod("runModal")
    func runModal() -> Int {
        appKitWarning("\(type(of: self).objCClassName): no file browser here; answering Cancel")
        return 0
    }
    @ObjCMethod("beginSheetModalForWindow:completionHandler:")
    func beginSheetModal(for window: NSObject?, completionHandler: ObjCBlock?) {
        _ = runModal()
        if let completionHandler { Dispatch.onMain { Blocks.call(completionHandler, 0) } }
    }
    @ObjCMethod("beginWithCompletionHandler:")
    func begin(completionHandler: ObjCBlock?) { beginSheetModal(for: nil, completionHandler: completionHandler) }
    @ObjCMethod("URL") func url() -> NSObject? { nil }
    @ObjCMethod("directoryURL") func panelDirectoryURL() -> NSObject? { directoryURL }
    @ObjCMethod("setDirectoryURL:") func setDirectoryURL(_ url: NSObject?) { directoryURL = url }
    @ObjCMethod("nameFieldStringValue") func panelNameFieldStringValue() -> String { nameFieldStringValue }
    @ObjCMethod("setNameFieldStringValue:") func setNameFieldStringValue(_ value: String?) { nameFieldStringValue = value ?? "" }
    @ObjCMethod("setMessage:") func setMessage(_ message: String?) { self.message = message ?? "" }
    @ObjCMethod("setPrompt:") func setPrompt(_ prompt: String?) { self.prompt = prompt ?? "" }
    @ObjCMethod("setAllowedFileTypes:") func setAllowedFileTypes(_ types: NSObject?) {}
    @ObjCMethod("setAllowedContentTypes:") func setAllowedContentTypes(_ types: NSObject?) {}
    @ObjCMethod("setAllowsOtherFileTypes:") func setAllowsOtherFileTypes(_ value: Bool) {}
    @ObjCMethod("setCanCreateDirectories:") func setCanCreateDirectories(_ value: Bool) {}
    @ObjCMethod("setShowsHiddenFiles:") func setShowsHiddenFiles(_ value: Bool) {}
    @ObjCMethod("setExtensionHidden:") func setExtensionHidden(_ value: Bool) {}
    @ObjCMethod("setTreatsFilePackagesAsDirectories:") func setTreatsFilePackagesAsDirectories(_ value: Bool) {}
    @ObjCMethod("accessoryView") func panelAccessoryView() -> NSObject? { accessory }
    @ObjCMethod("setAccessoryView:") func setAccessoryView(_ view: NSObject?) { accessory = view }
}

@ObjCClass("NSOpenPanel")
open class NSOpenPanel: NSSavePanel {
    @ObjCClassMethod("openPanel")
    static func openPanel() -> NSOpenPanel { NSOpenPanel(contentRect: CGRect(x: 0, y: 0, width: 480, height: 320), styleMask: 3, backing: 2, defer: true) }

    @ObjCMethod("URLs") func urls() -> NSObject { NSMutableArray.empty() }
    @ObjCMethod("setCanChooseFiles:") func setCanChooseFiles(_ value: Bool) {}
    @ObjCMethod("setCanChooseDirectories:") func setCanChooseDirectories(_ value: Bool) {}
    @ObjCMethod("setAllowsMultipleSelection:") func setAllowsMultipleSelection(_ value: Bool) {}
    @ObjCMethod("setResolvesAliases:") func setResolvesAliases(_ value: Bool) {}
}

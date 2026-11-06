import CPerryGeometry
import Glibc
import PerryObjCInterop

// Cells: what a control shows, and the values it keeps. A control asks its
// cell to draw in its bounds, and forwards its values to it, as AppKit's
// controls do; table columns draw their rows with their data cells. Text
// cells draw their string or attributed string, in light text on a dark
// (emphasized) background as a selected table row is; button cells draw a
// push button, check box, radio button or image; header cells a column's
// title. A nib's cells decode "NSContents", "NSSupport" (the font) and the
// flags Interface Builder packs into "NSCellFlags" and "NSCellFlags2".

/// NSTextAlignment, as arm64 Macs number it: left 0, center 1, right 2,
/// justified 3, natural 4. Archives use the Intel numbering, where right
/// is 1 and center 2.
enum Alignment {
    static func fromArchive(_ value: Int) -> Int { value == 1 ? 2 : value == 2 ? 1 : value }
}

@ObjCClass("NSCell")
open class NSCell: NSObject {
    var objectValue: NSObject?
    var font: NSFont?
    var alignment = 4
    var enabled = true
    var editable = false
    var selectable = false
    var scrollable = false
    var bordered = false
    var bezeled = false
    var state = 0
    var highlighted = false
    var image: NSImage?
    var tag = 0
    var controlSize: UInt = 0
    /// NSLineBreakMode, word wrapping by default.
    var lineBreakMode = 0
    var wraps = false
    var truncatesLastVisibleLine = false
    var usesSingleLineMode = false
    /// NSBackgroundStyle: normal 0, emphasized 1, raised 2, lowered 3.
    var backgroundStyle = 0
    var representedObject: NSObject?
    var formatter: NSObject?
    var continuous = false
    var allowsMixedState = false
    var refusesFirstResponder = false
    var sendsActionOnEndEditing = false
    var focusRingType: UInt = 0
    var showsFirstResponder = false
    var allowsEditingTextAttributes = false
    var title = ""
    /// Not retained.
    var controlViewObject: UnsafeMutableRawPointer?
    /// NSCellType: null 0, text 1, image 2.
    var type = 1

    @ObjCMethod("init")
    public required override init() {
        super.init()
        font = NSFont.system(size: 13)
    }

    @ObjCMethod("initTextCell:")
    public required init(textCell text: String?) {
        super.init()
        font = NSFont.system(size: 13)
        objectValue = text?.objCArgument().map(NSObject.init)
    }

    @ObjCMethod("initImageCell:")
    public required init(imageCell image: NSImage?) {
        super.init()
        self.image = image
        type = 2
    }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init()
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        let flags = UInt32(truncatingIfNeeded: decoded.integer("NSCellFlags"))
        if decoded.has("NSCellFlags") {
            state = flags & 0x8000_0000 != 0 ? 1 : 0
            highlighted = flags & 0x4000_0000 != 0
            enabled = flags & 0x2000_0000 == 0
            editable = flags & 0x1000_0000 != 0
            type = Int(flags >> 26 & 3)
            bordered = flags & 0x80_0000 != 0
            bezeled = flags & 0x40_0000 != 0
            selectable = flags & 0x20_0000 != 0
            scrollable = flags & 0x10_0000 != 0
            continuous = flags & 0x8_0000 != 0
            lineBreakMode = Int(flags >> 12 & 7)
            usesSingleLineMode = flags & 0x200 != 0
            truncatesLastVisibleLine = flags & 0x40 != 0
            showsFirstResponder = flags & 0x4 != 0
            focusRingType = UInt(flags & 3)
            wraps = lineBreakMode <= 1 && !usesSingleLineMode
        }
        if decoded.has("NSCellFlags2") {
            let flags2 = UInt32(truncatingIfNeeded: decoded.integer("NSCellFlags2"))
            sendsActionOnEndEditing = flags2 & 0x40_0000 != 0
            allowsMixedState = flags2 & 0x100_0000 != 0
            refusesFirstResponder = flags2 & 0x200_0000 != 0
            alignment = Alignment.fromArchive(Int(flags2 >> 26 & 7))
            allowsEditingTextAttributes = flags2 & 0x4000_0000 != 0
        }
        if decoded.has("NSControlSize2") { controlSize = UInt(decoded.integer("NSControlSize2")) }
        let contents = decoded.object("NSContents")
        if let image = contents?.as(NSImage.self) {
            self.image = image
        } else {
            objectValue = contents
        }
        font = decoded.object("NSSupport")?.as(NSFont.self) ?? NSFont.system(size: 13)
        formatter = decoded.object("NSFormatter")
        tag = decoded.integer("NSTag")
        controlViewObject = decoded.object("NSControlView")?.objcObject
    }

    var controlView: NSView? { controlViewObject.map(NSView.wrap) }

    // MARK: Values

    var cellString: String {
        guard let objectValue else { return "" }
        if objectValue.responds(to: "UTF8String") { return objectValue.stringValue }
        if objectValue.responds(to: "string"), let string = Send.object(objectValue.objcObject, "string") { return String(objCArgument: string) }
        if let formatter, let text = Send.object(formatter.objcObject, "stringForObjectValue:", objectValue.objcObject) {
            return String(objCArgument: text)
        }
        return objectValue.describedByObject() ?? ""
    }

    /// The attributed string the cell holds, if it holds one.
    var attributedValue: NSObject? {
        guard let objectValue, !objectValue.responds(to: "UTF8String"), objectValue.responds(to: "attributesAtIndex:effectiveRange:") else { return nil }
        return objectValue
    }

    func changed() {
        controlView?.setNeedsDisplay(true)
        controlView?.superview?.setNeedsLayout(true)
    }

    @ObjCMethod("objectValue") func cellObjectValue() -> NSObject? { objectValue }
    @ObjCMethod("setObjectValue:")
    func setObjectValue(_ value: NSObject?) {
        objectValue = value.map { NSObject(Send.object($0.objcObject, "copy") ?? $0.objcObject) }
        changed()
    }
    @ObjCMethod("stringValue") func cellStringValue() -> String { cellString }
    @ObjCMethod("setStringValue:")
    func setStringValue(_ value: String?) {
        objectValue = (value ?? "").objCArgument().map(NSObject.init)
        changed()
    }
    @ObjCMethod("attributedStringValue")
    func attributedStringValue() -> NSObject? {
        if let attributedValue { return attributedValue }
        let attributes = NSMutableDictionary.empty()
        if let font { attributes.set(font, forKey: "NSFont") }
        guard let cls = Classes.named("NSAttributedString"), let allocated = Send.object(cls.pointer, "alloc") else { return nil }
        typealias F = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
        let made = unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(allocated, ObjCRuntime.selector("initWithString:attributes:"),
                                                                  cellString.objCArgument(), attributes.objcObject)
        return made.map { NSObject(objcObject: $0, ownership: .adopt) }
    }
    @ObjCMethod("setAttributedStringValue:") func setAttributedStringValue(_ value: NSObject?) { setObjectValue(value) }
    @ObjCMethod("doubleValue") func doubleValue() -> Double { objectValue.map { Send.double($0.objcObject, "doubleValue") } ?? 0 }
    @ObjCMethod("setDoubleValue:") func setDoubleValue(_ value: Double) { setObjectValue(NSNumber.make(double: value)) }
    @ObjCMethod("floatValue") func floatValue() -> Float { Float(doubleValue()) }
    @ObjCMethod("setFloatValue:") func setFloatValue(_ value: Float) { setDoubleValue(Double(value)) }
    @ObjCMethod("intValue") func intValue() -> Int32 { Int32(truncatingIfNeeded: integerValue()) }
    @ObjCMethod("setIntValue:") func setIntValue(_ value: Int32) { setObjectValue(NSNumber.make(integer: Int(value))) }
    @ObjCMethod("integerValue") func integerValue() -> Int { objectValue.map { Send.integer($0.objcObject, "integerValue") } ?? 0 }
    @ObjCMethod("setIntegerValue:") func setIntegerValue(_ value: Int) { setObjectValue(NSNumber.make(integer: value)) }
    @ObjCMethod("boolValue") func boolValue() -> Bool { integerValue() != 0 }
    @ObjCMethod("takeObjectValueFrom:") func takeObjectValue(from sender: NSObject?) { setObjectValue(sender.flatMap { Send.object($0.objcObject, "objectValue") }.map(NSObject.init)) }
    @ObjCMethod("takeStringValueFrom:") func takeStringValue(from sender: NSObject?) { setObjectValue(sender.flatMap { Send.object($0.objcObject, "stringValue") }.map(NSObject.init)) }
    @ObjCMethod("hasValidObjectValue") func hasValidObjectValue() -> Bool { true }

    // MARK: Attributes

    @ObjCMethod("font") func cellFont() -> NSFont? { font }
    @ObjCMethod("setFont:") func setFont(_ font: NSFont?) { self.font = font; changed() }
    @ObjCMethod("alignment") func cellAlignment() -> Int { alignment }
    @ObjCMethod("setAlignment:") func setAlignment(_ value: Int) { alignment = value; changed() }
    @ObjCMethod("isEnabled") func isEnabled() -> Bool { enabled }
    @ObjCMethod("setEnabled:") func setEnabled(_ value: Bool) { enabled = value; changed() }
    @ObjCMethod("isEditable") func isEditable() -> Bool { editable }
    @ObjCMethod("setEditable:") func setEditable(_ value: Bool) { editable = value }
    @ObjCMethod("isSelectable") func isSelectable() -> Bool { selectable || editable }
    @ObjCMethod("setSelectable:") func setSelectable(_ value: Bool) { selectable = value }
    @ObjCMethod("isScrollable") func isScrollable() -> Bool { scrollable }
    @ObjCMethod("setScrollable:") func setScrollable(_ value: Bool) { scrollable = value }
    @ObjCMethod("isBordered") func isBordered() -> Bool { bordered }
    @ObjCMethod("setBordered:") func setBordered(_ value: Bool) { bordered = value; changed() }
    @ObjCMethod("isBezeled") func isBezeled() -> Bool { bezeled }
    @ObjCMethod("setBezeled:") func setBezeled(_ value: Bool) { bezeled = value; changed() }
    @ObjCMethod("state") func cellState() -> Int { state }
    @ObjCMethod("setState:") func setState(_ value: Int) { state = value; changed() }
    @ObjCMethod("nextState") func nextState() -> Int { state == 0 ? 1 : 0 }
    @ObjCMethod("setNextState") func setNextState() { setState(nextState()) }
    @ObjCMethod("isHighlighted") func isHighlighted() -> Bool { highlighted }
    @ObjCMethod("setHighlighted:") func setHighlighted(_ value: Bool) { highlighted = value; changed() }
    @ObjCMethod("highlight:withFrame:inView:") func highlight(_ value: Bool, withFrame frame: CGRect, in view: NSView?) { setHighlighted(value) }
    @ObjCMethod("image") func cellImage() -> NSImage? { image }
    @ObjCMethod("setImage:") func setImage(_ image: NSImage?) { self.image = image; changed() }
    @ObjCMethod("tag") func cellTag() -> Int { tag }
    @ObjCMethod("setTag:") func setTag(_ value: Int) { tag = value }
    @ObjCMethod("title") func cellTitle() -> String { cellString }
    @ObjCMethod("setTitle:") func setTitle(_ value: String?) { setStringValue(value) }
    @ObjCMethod("controlSize") func cellControlSize() -> UInt { controlSize }
    @ObjCMethod("setControlSize:") func setControlSize(_ value: UInt) { controlSize = value }
    @ObjCMethod("lineBreakMode") func cellLineBreakMode() -> Int { lineBreakMode }
    @ObjCMethod("setLineBreakMode:") func setLineBreakMode(_ value: Int) { lineBreakMode = value; wraps = value <= 1; changed() }
    @ObjCMethod("wraps") func cellWraps() -> Bool { wraps }
    @ObjCMethod("setWraps:") func setWraps(_ value: Bool) { wraps = value; changed() }
    @ObjCMethod("truncatesLastVisibleLine") func cellTruncatesLastVisibleLine() -> Bool { truncatesLastVisibleLine }
    @ObjCMethod("setTruncatesLastVisibleLine:") func setTruncatesLastVisibleLine(_ value: Bool) { truncatesLastVisibleLine = value }
    @ObjCMethod("usesSingleLineMode") func cellUsesSingleLineMode() -> Bool { usesSingleLineMode }
    @ObjCMethod("setUsesSingleLineMode:") func setUsesSingleLineMode(_ value: Bool) { usesSingleLineMode = value }
    @ObjCMethod("backgroundStyle") func cellBackgroundStyle() -> Int { backgroundStyle }
    @ObjCMethod("setBackgroundStyle:") func setBackgroundStyle(_ value: Int) { backgroundStyle = value; changed() }
    @ObjCMethod("interiorBackgroundStyle") func interiorBackgroundStyle() -> Int { backgroundStyle }
    @ObjCMethod("representedObject") func cellRepresentedObject() -> NSObject? { representedObject }
    @ObjCMethod("setRepresentedObject:") func setRepresentedObject(_ value: NSObject?) { representedObject = value }
    @ObjCMethod("formatter") func cellFormatter() -> NSObject? { formatter }
    @ObjCMethod("setFormatter:") func setFormatter(_ value: NSObject?) { formatter = value; changed() }
    @ObjCMethod("isContinuous") func isContinuous() -> Bool { continuous }
    @ObjCMethod("setContinuous:") func setContinuous(_ value: Bool) { continuous = value }
    @ObjCMethod("allowsMixedState") func cellAllowsMixedState() -> Bool { allowsMixedState }
    @ObjCMethod("setAllowsMixedState:") func setAllowsMixedState(_ value: Bool) { allowsMixedState = value }
    @ObjCMethod("refusesFirstResponder") func cellRefusesFirstResponder() -> Bool { refusesFirstResponder }
    @ObjCMethod("setRefusesFirstResponder:") func setRefusesFirstResponder(_ value: Bool) { refusesFirstResponder = value }
    @ObjCMethod("acceptsFirstResponder") func acceptsFirstResponder() -> Bool { enabled && !refusesFirstResponder }
    @ObjCMethod("sendsActionOnEndEditing") func cellSendsActionOnEndEditing() -> Bool { sendsActionOnEndEditing }
    @ObjCMethod("setSendsActionOnEndEditing:") func setSendsActionOnEndEditing(_ value: Bool) { sendsActionOnEndEditing = value }
    @ObjCMethod("focusRingType") func cellFocusRingType() -> UInt { focusRingType }
    @ObjCMethod("setFocusRingType:") func setFocusRingType(_ value: UInt) { focusRingType = value }
    @ObjCMethod("showsFirstResponder") func cellShowsFirstResponder() -> Bool { showsFirstResponder }
    @ObjCMethod("setShowsFirstResponder:") func setShowsFirstResponder(_ value: Bool) { showsFirstResponder = value }
    @ObjCMethod("allowsEditingTextAttributes") func cellAllowsEditingTextAttributes() -> Bool { allowsEditingTextAttributes }
    @ObjCMethod("setAllowsEditingTextAttributes:") func setAllowsEditingTextAttributes(_ value: Bool) { allowsEditingTextAttributes = value }
    @ObjCMethod("setImportsGraphics:") func setImportsGraphics(_ value: Bool) {}
    @ObjCMethod("setAllowsUndo:") func setAllowsUndo(_ value: Bool) {}
    @ObjCMethod("setScrollable:withDefault:") func setScrollable(_ value: Bool, withDefault: Bool) { scrollable = value }
    @ObjCMethod("type") func cellType() -> Int { type }
    @ObjCMethod("setType:") func setType(_ value: Int) { type = value }
    @ObjCMethod("controlView") func cellControlView() -> NSView? { controlView }
    @ObjCMethod("setControlView:") func setControlView(_ view: NSView?) { controlViewObject = view?.objcObject }
    @ObjCMethod("menu") func cellMenu() -> NSObject? { nil }
    @ObjCMethod("setMenu:") func setMenu(_ menu: NSObject?) {}
    @ObjCMethod("keyEquivalent") func keyEquivalent() -> String { "" }
    @ObjCMethod("mouseDownFlags") func mouseDownFlags() -> Int { 0 }
    @ObjCMethod("isOpaque") func isOpaque() -> Bool { false }
    @ObjCMethod("userInterfaceLayoutDirection") func userInterfaceLayoutDirection() -> Int { 0 }
    @ObjCMethod("setUserInterfaceLayoutDirection:") func setUserInterfaceLayoutDirection(_ value: Int) {}
    @ObjCMethod("setBaseWritingDirection:") func setBaseWritingDirection(_ value: Int) {}
    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
        // Another cell of the class, with the same values: a table's data
        // cell is copied for each row it edits.
        let copy = NSCell.objCInstance(Send.object(Send.object(ObjCRuntime.objectClass(objcObject), "alloc"), "init")!, ownership: .adopt)
        copyValues(to: copy)
        return ObjCRuntime.retain(copy.objcObject)!
    }

    func copyValues(to copy: NSCell) {
        (copy.objectValue, copy.font, copy.alignment, copy.enabled, copy.editable, copy.selectable) =
            (objectValue, font, alignment, enabled, editable, selectable)
        (copy.bordered, copy.bezeled, copy.state, copy.image, copy.tag, copy.lineBreakMode, copy.wraps) =
            (bordered, bezeled, state, image, tag, lineBreakMode, wraps)
        (copy.truncatesLastVisibleLine, copy.backgroundStyle, copy.formatter, copy.type, copy.title) =
            (truncatesLastVisibleLine, backgroundStyle, formatter, type, title)
    }

    // MARK: Geometry and drawing

    var effectiveFont: NSFont { font ?? NSFont.system(size: 13) }

    /// The text the cell shows, as runs in its font and color.
    func textRuns(color: NSColor?) -> [TextRun] {
        let font = effectiveFont
        if let attributed = attributedValue { return Text.runs(attributed, font: font, color: color).runs }
        return [TextRun(text: cellString, font: font, color: color)]
    }

    var textStyle: TextStyle {
        var style = TextStyle()
        style.alignment = alignment
        style.lineBreakMode = wraps ? 0 : (lineBreakMode <= 1 ? 4 : lineBreakMode)
        if let attributed = attributedValue {
            var paragraph = Text.runs(attributed, font: effectiveFont, color: nil).paragraph
            if paragraph != nil { Text.style(paragraph, into: &style) }
            paragraph = nil
        }
        return style
    }

    @ObjCMethod("cellSize") func cellSize() -> CGSize { cellSize(forBounds: CGRect(x: 0, y: 0, width: 10_000, height: 10_000)) }

    @ObjCMethod("cellSizeForBounds:")
    func cellSize(forBounds rect: CGRect) -> CGSize {
        if type == 2, let image { return image.size }
        let text = Text.size(textRuns(color: nil), width: wraps ? rect.width - 4 : .infinity, style: textStyle)
        let inset: CGFloat = bezeled ? 6 : bordered ? 4 : 4
        return CGSize(width: text.width + inset, height: max(text.height, Text.lineHeight(effectiveFont)) + (bezeled ? 6 : 0))
    }

    @ObjCMethod("titleRectForBounds:")
    func titleRect(forBounds rect: CGRect) -> CGRect {
        let dx: CGFloat = bezeled ? 3 : 2, dy: CGFloat = bezeled ? 3 : bordered ? 1 : 0
        return CGRect(x: rect.minX + dx, y: rect.minY + dy, width: max(0, rect.width - 2 * dx), height: max(0, rect.height - 2 * dy))
    }

    @ObjCMethod("drawingRectForBounds:") func drawingRect(forBounds rect: CGRect) -> CGRect { titleRect(forBounds: rect) }
    @ObjCMethod("imageRectForBounds:") func imageRect(forBounds rect: CGRect) -> CGRect { rect }

    /// Text color on the cell's background: light text on an emphasized
    /// one, as in a selected table row, for the system's text colors.
    func displayColor(_ color: NSColor?) -> NSColor {
        let base = color ?? NSColor.controlTextColor()
        if !enabled { return NSColor.disabledControlTextColor() }
        if backgroundStyle == 1, base.catalogName != nil || base.alpha < 1 || (base.red + base.green + base.blue) < 0.5 {
            return NSColor.whiteColor()
        }
        return base
    }

    @ObjCMethod("drawWithFrame:inView:")
    func draw(withFrame frame: CGRect, in view: NSView?) {
        if bezeled || bordered, let context = NSGraphicsContext.currentCG {
            CG.saveGState(context)
            if bezeled {
                CG.setFillColorWithColor(context, NSColor.textBackgroundColor().cgColorRef)
                CG.fillRect(context, frame)
            }
            CG.setFillColorWithColor(context, NSColor(white: 0.72, alpha: 1).cgColorRef)
            NSFrameRect(frame)
            CG.restoreGState(context)
        }
        typealias F = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, CGRect, UnsafeMutableRawPointer?) -> Void
        unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(objcObject, ObjCRuntime.selector("drawInteriorWithFrame:inView:"), frame, view?.objcObject)
    }

    @ObjCMethod("drawInteriorWithFrame:inView:")
    func drawInterior(withFrame frame: CGRect, in view: NSView?) {
        if type == 2 || (image != nil && cellString.isEmpty) {
            image.map { ImageDrawing.draw($0, fitting: frame) }
            return
        }
        let rect = titleRect(forBounds: frame)
        var style = textStyle
        if truncatesLastVisibleLine || !wraps { style.maximumLines = max(1, Int((rect.height / Text.lineHeight(effectiveFont)).rounded(.down))) }
        if !wraps { style.maximumLines = 1 }
        Text.draw(textRuns(color: displayColor(nil)), in: rect, style: style)
    }

    @ObjCMethod("drawFocusRingMaskWithFrame:inView:") func drawFocusRingMask(withFrame frame: CGRect, in view: NSView?) {}
    @ObjCMethod("focusRingMaskBoundsForFrame:inView:") func focusRingMaskBounds(forFrame frame: CGRect, in view: NSView?) -> CGRect { frame }
    @ObjCMethod("calcDrawInfo:") func calcDrawInfo(_ rect: CGRect) {}

    @ObjCMethod("trackMouse:inRect:ofView:untilMouseUp:")
    func trackMouse(_ event: NSObject?, in rect: CGRect, of view: NSView?, untilMouseUp: Bool) -> Bool { true }
    @ObjCMethod("hitTestForEvent:inRect:ofView:") func hitTest(for event: NSObject?, in rect: CGRect, of view: NSView?) -> UInt { 1 }
    @ObjCMethod("expansionFrameWithFrame:inView:") func expansionFrame(withFrame frame: CGRect, in view: NSView?) -> CGRect { .zero }
    @ObjCMethod("editWithFrame:inView:editor:delegate:event:")
    func edit(withFrame frame: CGRect, in view: NSView?, editor: NSObject?, delegate: NSObject?, event: NSObject?) {}
    @ObjCMethod("selectWithFrame:inView:editor:delegate:start:length:")
    func select(withFrame frame: CGRect, in view: NSView?, editor: NSObject?, delegate: NSObject?, start: Int, length: Int) {}
    @ObjCMethod("endEditing:") func endEditing(_ editor: NSObject?) {}
}

/// Images drawn inside a rectangle: scaled down proportionally to fit,
/// centered.
enum ImageDrawing {
    static func draw(_ image: NSImage, fitting frame: CGRect, scaleUp: Bool = false) {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return }
        var scale = min(frame.width / size.width, frame.height / size.height)
        if !scaleUp { scale = min(scale, 1) }
        let drawn = CGSize(width: size.width * scale, height: size.height * scale)
        image.draw(in: CGRect(x: frame.midX - drawn.width / 2, y: frame.midY - drawn.height / 2, width: drawn.width, height: drawn.height))
    }
}

extension CGRect {
    var midX: CGFloat { origin.x + size.width / 2 }
    var midY: CGFloat { origin.y + size.height / 2 }
    func insetBy(dx: CGFloat, dy: CGFloat) -> CGRect {
        CGRect(x: minX + dx, y: minY + dy, width: max(0, width - 2 * dx), height: max(0, height - 2 * dy))
    }
}

@ObjCClass("NSActionCell")
open class NSActionCell: NSCell {
    /// Not retained.
    var target: UnsafeMutableRawPointer?
    var action: ObjCSelector?

    @ObjCMethod("target") func cellTarget() -> NSObject? { target.map(NSObject.init) }
    @ObjCMethod("setTarget:") func setTarget(_ value: NSObject?) { target = value?.objcObject }
    @ObjCMethod("action") func cellAction() -> ObjCSelector? { action }
    @ObjCMethod("setAction:") func setAction(_ value: ObjCSelector?) { action = value }
}

@ObjCClass("NSTextFieldCell")
open class NSTextFieldCell: NSActionCell {
    var textColor: NSColor?
    var backgroundColor: NSColor?
    var drawsBackground = false
    var placeholder: NSObject?
    /// NSTextFieldBezelStyle: square 0, rounded 1.
    var bezelStyle: UInt = 0

    @ObjCMethod("init")
    public required init() {
        super.init()
        editable = true
        selectable = true
    }

    @ObjCMethod("initTextCell:")
    public required init(textCell text: String?) { super.init(textCell: text) }

    @ObjCMethod("initImageCell:")
    public required init(imageCell image: NSImage?) { super.init(imageCell: image) }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init(coder: coder)
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        textColor = decoded.object("NSTextColor")?.as(NSColor.self)
        backgroundColor = decoded.object("NSBackgroundColor")?.as(NSColor.self)
        drawsBackground = decoded.bool("NSDrawsBackground")
        placeholder = decoded.object("NSPlaceholderString")
        bezelStyle = UInt(decoded.integer("NSTextBezelStyle"))
        type = 1
    }

    @ObjCMethod("textColor") func cellTextColor() -> NSColor? { textColor ?? NSColor.controlTextColor() }
    @ObjCMethod("setTextColor:") func setTextColor(_ color: NSColor?) { textColor = color; changed() }
    @ObjCMethod("backgroundColor") func cellBackgroundColor() -> NSColor? { backgroundColor }
    @ObjCMethod("setBackgroundColor:") func setBackgroundColor(_ color: NSColor?) { backgroundColor = color; changed() }
    @ObjCMethod("drawsBackground") func cellDrawsBackground() -> Bool { drawsBackground }
    @ObjCMethod("setDrawsBackground:") func setDrawsBackground(_ value: Bool) { drawsBackground = value; changed() }
    @ObjCMethod("placeholderString")
    func placeholderString() -> String? { placeholder.map { $0.responds(to: "UTF8String") ? $0.stringValue : (Send.object($0.objcObject, "string").map { String(objCArgument: $0) } ?? "") } }
    @ObjCMethod("setPlaceholderString:") func setPlaceholderString(_ value: String?) { placeholder = value?.objCArgument().map(NSObject.init); changed() }
    @ObjCMethod("placeholderAttributedString") func placeholderAttributedString() -> NSObject? { placeholder }
    @ObjCMethod("setPlaceholderAttributedString:") func setPlaceholderAttributedString(_ value: NSObject?) { placeholder = value; changed() }
    @ObjCMethod("bezelStyle") func cellBezelStyle() -> UInt { bezelStyle }
    @ObjCMethod("setBezelStyle:") func setBezelStyle(_ value: UInt) { bezelStyle = value; changed() }
    @ObjCMethod("setUpFieldEditorAttributes:") func setUpFieldEditorAttributes(_ editor: NSObject?) -> NSObject? { editor }
    @ObjCMethod("allowedInputSourceLocales") func allowedInputSourceLocales() -> NSObject? { nil }

    override func copyValues(to copy: NSCell) {
        super.copyValues(to: copy)
        guard let copy = copy.as(NSTextFieldCell.self) else { return }
        (copy.textColor, copy.backgroundColor, copy.drawsBackground, copy.placeholder, copy.bezelStyle) =
            (textColor, backgroundColor, drawsBackground, placeholder, bezelStyle)
    }

    @ObjCMethod("drawWithFrame:inView:")
    override func draw(withFrame frame: CGRect, in view: NSView?) {
        guard let context = NSGraphicsContext.currentCG else { return }
        CG.saveGState(context)
        if bezeled {
            CG.setFillColorWithColor(context, (drawsBackground ? backgroundColor : nil)?.cgColorRef ?? NSColor.textBackgroundColor().cgColorRef)
            if bezelStyle == 1 {
                CG.fill(CG.roundedRect(frame.insetBy(dx: 0.5, dy: 0.5), radius: frame.height / 2), backgroundColor ?? NSColor.textBackgroundColor(), in: context)
                CG.stroke(CG.roundedRect(frame.insetBy(dx: 0.5, dy: 0.5), radius: frame.height / 2), NSColor(white: 0.75, alpha: 1), in: context)
            } else {
                CG.fillRect(context, frame)
                CG.setFillColorWithColor(context, NSColor(white: 0.75, alpha: 1).cgColorRef)
                NSFrameRect(frame)
            }
        } else if drawsBackground, let backgroundColor {
            CG.setFillColorWithColor(context, backgroundColor.cgColorRef)
            CG.fillRect(context, frame)
        }
        if bordered && !bezeled {
            CG.setFillColorWithColor(context, NSColor(white: 0.6, alpha: 1).cgColorRef)
            NSFrameRect(frame)
        }
        CG.restoreGState(context)
        typealias F = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, CGRect, UnsafeMutableRawPointer?) -> Void
        unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(objcObject, ObjCRuntime.selector("drawInteriorWithFrame:inView:"), frame, view?.objcObject)
    }

    @ObjCMethod("drawInteriorWithFrame:inView:")
    override func drawInterior(withFrame frame: CGRect, in view: NSView?) {
        let rect = titleRect(forBounds: frame)
        var style = textStyle
        let lineHeight = Text.lineHeight(effectiveFont)
        if !wraps || usesSingleLineMode { style.maximumLines = 1 } else if truncatesLastVisibleLine {
            style.maximumLines = max(1, Int((rect.height / lineHeight).rounded(.down)))
        }
        var runs = textRuns(color: displayColor(textColor))
        let editing = view?.as(NSTextField.self)?.editing == true
        if runs.allSatisfy({ $0.text.isEmpty }), let placeholder, !editing {
            if placeholder.responds(to: "UTF8String") {
                runs = [TextRun(text: placeholder.stringValue, font: effectiveFont, color: NSColor.placeholderTextColor())]
            } else {
                runs = Text.runs(placeholder, font: effectiveFont, color: NSColor.placeholderTextColor()).runs
            }
        }
        // One line centered in a bezeled field's height.
        var textRect = rect
        if bezeled, style.maximumLines == 1 {
            let top = ((rect.height - lineHeight) / 2).rounded(.down)
            textRect = CGRect(x: rect.minX, y: rect.minY + max(0, top), width: rect.width, height: lineHeight)
            if view?.flipped == false { textRect.origin.y = rect.maxY - max(0, top) - lineHeight }
        }
        let lines = Text.layout(runs, width: textRect.width > 0 ? textRect.width : .infinity, style: style)
        Text.draw(lines, in: textRect, style: style)
        if editing, let context = NSGraphicsContext.currentCG {
            // The insertion point, after the text.
            let width = lines.last?.width ?? 0
            let x: CGFloat = style.alignment == 2 ? textRect.maxX : style.alignment == 1 ? textRect.midX + width / 2 : textRect.minX + width
            let lineTop = CGFloat(max(0, lines.count - 1)) * lineHeight
            let flipped = NSGraphicsContext.current?.flipped ?? false
            let y = flipped ? textRect.minY + lineTop : textRect.maxY - lineTop - lineHeight
            CG.saveGState(context)
            CG.setFillColorWithColor(context, NSColor.textColor().cgColorRef)
            CG.fillRect(context, CGRect(x: min(x, textRect.maxX - 1), y: y, width: 1, height: lineHeight))
            CG.restoreGState(context)
        }
    }
}

@ObjCClass("NSSecureTextFieldCell")
open class NSSecureTextFieldCell: NSTextFieldCell {
    override func textRuns(color: NSColor?) -> [TextRun] {
        [TextRun(text: String(repeating: "•", count: cellString.count), font: effectiveFont, color: color)]
    }
}

@ObjCClass("NSSearchFieldCell")
open class NSSearchFieldCell: NSTextFieldCell {
    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init(coder: coder)
        bezeled = true
        bezelStyle = 1
    }

    @ObjCMethod("init")
    public required init() {
        super.init()
        bezeled = true
        bezelStyle = 1
    }

    @ObjCMethod("initTextCell:")
    public required init(textCell text: String?) { super.init(textCell: text) }

    @ObjCMethod("initImageCell:")
    public required init(imageCell image: NSImage?) { super.init(imageCell: image) }

    /// Room for the magnifying glass on the left.
    @ObjCMethod("titleRectForBounds:")
    override func titleRect(forBounds rect: CGRect) -> CGRect {
        CGRect(x: rect.minX + 22, y: rect.minY + 3, width: max(0, rect.width - 44), height: max(0, rect.height - 6))
    }

    @ObjCMethod("searchTextRectForBounds:") func searchTextRect(forBounds rect: CGRect) -> CGRect { titleRect(forBounds: rect) }
    @ObjCMethod("searchButtonRectForBounds:") func searchButtonRect(forBounds rect: CGRect) -> CGRect { CGRect(x: rect.minX + 4, y: rect.minY, width: 16, height: rect.height) }
    @ObjCMethod("cancelButtonRectForBounds:") func cancelButtonRect(forBounds rect: CGRect) -> CGRect { CGRect(x: rect.maxX - 20, y: rect.minY, width: 16, height: rect.height) }
    @ObjCMethod("setSendsWholeSearchString:") func setSendsWholeSearchString(_ value: Bool) {}
    @ObjCMethod("setSendsSearchStringImmediately:") func setSendsSearchStringImmediately(_ value: Bool) {}
    @ObjCMethod("setMaximumRecents:") func setMaximumRecents(_ value: Int) {}
    @ObjCMethod("setRecentsAutosaveName:") func setRecentsAutosaveName(_ value: NSObject?) {}
    @ObjCMethod("setSearchMenuTemplate:") func setSearchMenuTemplate(_ value: NSObject?) {}
    @ObjCMethod("searchMenuTemplate") func searchMenuTemplate() -> NSObject? { nil }
    @ObjCMethod("cancelButtonCell") func cancelButtonCell() -> NSObject? { nil }
    @ObjCMethod("searchButtonCell") func searchButtonCell() -> NSObject? { nil }

    @ObjCMethod("drawWithFrame:inView:")
    override func draw(withFrame frame: CGRect, in view: NSView?) {
        super.draw(withFrame: frame, in: view)
        guard let context = NSGraphicsContext.currentCG else { return }
        // The magnifying glass: a circle and its handle.
        let flipped = NSGraphicsContext.current?.flipped ?? false
        let cy = frame.midY + (flipped ? -1 : 1)
        let circle = CGRect(x: frame.minX + 7, y: cy - 4.5, width: 8, height: 8)
        CG.stroke(CG.ready ? { let p = CG.pathCreateMutable(); CG.pathAddEllipseInRect(p, nil, circle); return p }() : nil,
                  NSColor.secondaryLabelColor(), width: 1.3, in: context)
        let handleY = flipped ? circle.maxY : circle.minY
        CG.stroke(CG.polygon([CGPoint(x: circle.maxX - 1.2, y: handleY + (flipped ? -1.2 : 1.2)), CGPoint(x: circle.maxX + 2.5, y: handleY + (flipped ? 2.5 : -2.5))]),
                  NSColor.secondaryLabelColor(), width: 1.5, in: context)
    }
}

@ObjCClass("NSComboBoxCell")
open class NSComboBoxCell: NSTextFieldCell {
    var items: [NSObject] = []

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init(coder: coder)
        if let coder { items = Coder(coder: coder).array("NSPopUpListData") }
        bezeled = true
    }

    @ObjCMethod("init")
    public required init() { super.init() }
    @ObjCMethod("initTextCell:")
    public required init(textCell text: String?) { super.init(textCell: text) }
    @ObjCMethod("initImageCell:")
    public required init(imageCell image: NSImage?) { super.init(imageCell: image) }

    @ObjCMethod("titleRectForBounds:")
    override func titleRect(forBounds rect: CGRect) -> CGRect {
        CGRect(x: rect.minX + 3, y: rect.minY + 3, width: max(0, rect.width - 26), height: max(0, rect.height - 6))
    }

    @ObjCMethod("drawWithFrame:inView:")
    override func draw(withFrame frame: CGRect, in view: NSView?) {
        super.draw(withFrame: frame, in: view)
        guard let context = NSGraphicsContext.currentCG else { return }
        let button = CGRect(x: frame.maxX - 20, y: frame.minY + 2, width: 18, height: frame.height - 4)
        CG.fill(CG.roundedRect(button, radius: 4), NSColor.controlAccentColor(), in: context)
        Arrows.draw(in: button, color: NSColor.whiteColor(), context: context, double: false)
    }
}

/// The chevrons of pop-up buttons and combo boxes.
enum Arrows {
    static func draw(in rect: CGRect, color: NSColor, context: CGRef, double: Bool) {
        let flipped = NSGraphicsContext.current?.flipped ?? false
        let cx = rect.midX, cy = rect.midY
        func chevron(_ dy: CGFloat, up: Bool) {
            let tip = cy + (flipped ? -dy : dy)
            let sign: CGFloat = (up != flipped) ? -1 : 1
            CG.stroke(polyline([CGPoint(x: cx - 3, y: tip + sign * 2.5), CGPoint(x: cx, y: tip), CGPoint(x: cx + 3, y: tip + sign * 2.5)]),
                      color, width: 1.4, in: context)
        }
        if double {
            chevron(4, up: true)
            chevron(-4, up: false)
        } else {
            chevron(-1.5, up: false)
        }
    }

    static func polyline(_ points: [CGPoint]) -> CGRef? {
        guard CG.ready, let first = points.first, let path = CG.pathCreateMutable() else { return nil }
        CG.pathMoveToPoint(path, nil, first.x, first.y)
        for point in points.dropFirst() { CG.pathAddLineToPoint(path, nil, point.x, point.y) }
        return path
    }
}

/// The image a check box or radio button shows, by its system name:
/// "NSSwitch" or "NSRadioButton".
@ObjCClass("NSButtonImageSource")
open class NSButtonImageSource: NSObject {
    var name = ""

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init()
        if let coder { name = Coder(coder: coder).string("NSImageName") ?? "" }
    }
}

/// NSButtonType: momentary light 0, push on/off 1, toggle 2, switch (check
/// box) 3, radio 4, momentary change 5, on/off 6, momentary push in 7.
/// NSBezelStyle: rounded 1, regular square 2, disclosure 5, shadowless
/// square 6, circular 7, textured square 8, help 9, small square 10,
/// textured rounded 11, round rect 12, recessed 13, rounded disclosure 14,
/// inline 15.
@ObjCClass("NSButtonCell")
open class NSButtonCell: NSActionCell {
    var alternateTitle = ""
    var alternateImage: NSImage?
    var keyEquivalentValue = ""
    var keyEquivalentModifierMask: UInt = 0
    var buttonType: UInt = 7
    var bezelStyle: UInt = 1
    var imagePosition: UInt = 0
    var imageScaling: UInt = 0
    var transparent = false
    var showsBorderOnlyWhileMouseInside = false
    var bezelColor: NSColor?
    var attributedTitle: NSObject?

    @ObjCMethod("init")
    public required init() {
        super.init()
        bordered = true
        title = "Button"
    }

    @ObjCMethod("initTextCell:")
    public required init(textCell text: String?) {
        super.init(textCell: text)
        bordered = true
        title = text ?? ""
    }

    @ObjCMethod("initImageCell:")
    public required init(imageCell image: NSImage?) {
        super.init(imageCell: image)
        bordered = true
    }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init(coder: coder)
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        title = cellString
        if attributedValue != nil { attributedTitle = objectValue }
        objectValue = nil
        alternateTitle = decoded.string("NSAlternateContents") ?? ""
        keyEquivalentValue = decoded.string("NSKeyEquivalent") ?? ""
        keyEquivalentModifierMask = UInt(decoded.integer("NSKeyEquivModMask"))
        let flags = UInt32(truncatingIfNeeded: decoded.integer("NSButtonFlags"))
        let flags2 = UInt32(truncatingIfNeeded: decoded.integer("NSButtonFlags2"))
        bordered = flags & 0x80_0000 != 0
        transparent = flags & 0x8000 != 0
        bezelStyle = UInt(flags2 & 0x7 | (flags2 & 0x20) >> 2)
        // The image position: NSImageOnly 1, left 2, right 3, below 4,
        // above 5, overlaps 6.
        if flags & 0x40_0000 != 0 {
            imagePosition = flags & 0x8_0000 != 0 ? 1 : flags & 0x10_0000 != 0 ? 6 : flags & 0x20_0000 != 0 ? 3 : 2
        }
        let normal = decoded.object("NSNormalImage")
        if let source = normal?.as(NSButtonImageSource.self) {
            buttonType = source.name == "NSRadioButton" ? 4 : 3
            image = nil
        } else if let picture = normal?.as(NSImage.self) {
            image = picture
        }
        alternateImage = decoded.object("NSAlternateImage")?.as(NSImage.self)
        if buttonType == 7, flags & 0x4000_0000 != 0 || flags & 0x2000_0000 != 0, decoded.has("NSAlternateContents") || alternateImage != nil {
            buttonType = 6
        }
        if let color = decoded.object("NSBezelColor")?.as(NSColor.self) { bezelColor = color }
        type = 1
    }

    var isCheckLike: Bool { buttonType == 3 || buttonType == 4 }
    var showsState: Bool { isCheckLike || buttonType == 1 || buttonType == 2 || buttonType == 6 }

    @ObjCMethod("title") override func cellTitle() -> String { title }
    @ObjCMethod("setTitle:")
    override func setTitle(_ value: String?) {
        title = value ?? ""
        attributedTitle = nil
        changed()
    }
    @ObjCMethod("stringValue") override func cellStringValue() -> String { objectValue == nil ? String(state) : cellString }
    @ObjCMethod("objectValue") override func cellObjectValue() -> NSObject? { NSNumber.make(integer: state) }
    @ObjCMethod("setObjectValue:")
    override func setObjectValue(_ value: NSObject?) {
        state = value.map { Send.integer($0.objcObject, "integerValue") } ?? 0
        changed()
    }
    @ObjCMethod("setIntegerValue:") override func setIntegerValue(_ value: Int) { setState(value) }
    @ObjCMethod("integerValue") override func integerValue() -> Int { state }
    @ObjCMethod("attributedTitle")
    func cellAttributedTitle() -> NSObject? {
        if let attributedTitle { return attributedTitle }
        let saved = objectValue
        objectValue = title.objCArgument().map(NSObject.init)
        defer { objectValue = saved }
        return attributedStringValue()
    }
    @ObjCMethod("setAttributedTitle:")
    func setAttributedTitle(_ value: NSObject?) {
        attributedTitle = value
        title = value.flatMap { Send.object($0.objcObject, "string") }.map { String(objCArgument: $0) } ?? ""
        changed()
    }
    @ObjCMethod("alternateTitle") func cellAlternateTitle() -> String { alternateTitle }
    @ObjCMethod("setAlternateTitle:") func setAlternateTitle(_ value: String?) { alternateTitle = value ?? "" }
    @ObjCMethod("alternateImage") func cellAlternateImage() -> NSImage? { alternateImage }
    @ObjCMethod("setAlternateImage:") func setAlternateImage(_ value: NSImage?) { alternateImage = value; changed() }
    @ObjCMethod("keyEquivalent") override func keyEquivalent() -> String { keyEquivalentValue }
    @ObjCMethod("setKeyEquivalent:") func setKeyEquivalent(_ value: String?) { keyEquivalentValue = value ?? "" }
    @ObjCMethod("keyEquivalentModifierMask") func cellKeyEquivalentModifierMask() -> UInt { keyEquivalentModifierMask }
    @ObjCMethod("setKeyEquivalentModifierMask:") func setKeyEquivalentModifierMask(_ value: UInt) { keyEquivalentModifierMask = value }
    @ObjCMethod("setButtonType:")
    func setButtonType(_ value: UInt) {
        buttonType = value
        changed()
    }
    @ObjCMethod("bezelStyle") func cellBezelStyle() -> UInt { bezelStyle }
    @ObjCMethod("setBezelStyle:") func setBezelStyle(_ value: UInt) { bezelStyle = value; changed() }
    @ObjCMethod("imagePosition") func cellImagePosition() -> UInt { imagePosition }
    @ObjCMethod("setImagePosition:") func setImagePosition(_ value: UInt) { imagePosition = value; changed() }
    @ObjCMethod("imageScaling") func cellImageScaling() -> UInt { imageScaling }
    @ObjCMethod("setImageScaling:") func setImageScaling(_ value: UInt) { imageScaling = value; changed() }
    @ObjCMethod("isTransparent") func isTransparent() -> Bool { transparent }
    @ObjCMethod("setTransparent:") func setTransparent(_ value: Bool) { transparent = value; changed() }
    @ObjCMethod("showsBorderOnlyWhileMouseInside") func cellShowsBorderOnlyWhileMouseInside() -> Bool { showsBorderOnlyWhileMouseInside }
    @ObjCMethod("setShowsBorderOnlyWhileMouseInside:") func setShowsBorderOnlyWhileMouseInside(_ value: Bool) { showsBorderOnlyWhileMouseInside = value }
    @ObjCMethod("bezelColor") func cellBezelColor() -> NSColor? { bezelColor }
    @ObjCMethod("setBezelColor:") func setBezelColor(_ value: NSColor?) { bezelColor = value; changed() }
    @ObjCMethod("setHighlightsBy:") func setHighlightsBy(_ value: Int) {}
    @ObjCMethod("setShowsStateBy:") func setShowsStateBy(_ value: Int) {}
    @ObjCMethod("setPeriodicDelay:interval:") func setPeriodicDelay(_ delay: Float, interval: Float) {}
    @ObjCMethod("setImageDimsWhenDisabled:") func setImageDimsWhenDisabled(_ value: Bool) {}

    override func copyValues(to copy: NSCell) {
        super.copyValues(to: copy)
        guard let copy = copy.as(NSButtonCell.self) else { return }
        (copy.alternateTitle, copy.alternateImage, copy.buttonType, copy.bezelStyle, copy.imagePosition, copy.transparent) =
            (alternateTitle, alternateImage, buttonType, bezelStyle, imagePosition, transparent)
    }

    @ObjCMethod("cellSize")
    override func cellSize() -> CGSize {
        let font = effectiveFont
        let text = Text.width(title, font: font)
        if isCheckLike { return CGSize(width: (text + 22).rounded(.up), height: 18) }
        if let image, title.isEmpty { return CGSize(width: image.size.width + (bordered ? 16 : 0), height: max(image.size.height, bordered ? 21 : 0)) }
        return CGSize(width: (text + (bordered ? 28 : 4)).rounded(.up), height: bordered ? 21 : Text.lineHeight(font))
    }

    @ObjCMethod("drawWithFrame:inView:")
    override func draw(withFrame frame: CGRect, in view: NSView?) {
        guard !transparent, let context = NSGraphicsContext.currentCG else { return }
        if isCheckLike {
            drawCheck(frame, context: context)
            return
        }
        let on = showsState && state != 0
        if bordered {
            // A push button: rounded, white, with a gray edge, darker while
            // pressed; a default button (Return) is accent-colored.
            let bezel = CGRect(x: frame.minX + 1, y: frame.midY - min(frame.height, 22) / 2 + 0.5, width: frame.width - 2,
                               height: min(frame.height, 22) - 1)
            let isDefault = keyEquivalentValue == "\r"
            let fill: NSColor = highlighted ? NSColor(white: 0.82, alpha: 1)
                : isDefault || on ? (bezelColor ?? NSColor.controlAccentColor()) : (bezelColor ?? NSColor.whiteColor())
            let radius: CGFloat = bezelStyle == 7 ? bezel.height / 2 : bezelStyle == 6 || bezelStyle == 2 || bezelStyle == 10 ? 0 : 5
            CG.fill(CG.roundedRect(bezel, radius: radius), fill, in: context)
            CG.stroke(CG.roundedRect(bezel, radius: radius), NSColor(white: 0, alpha: 0.2), width: 0.5, in: context)
            drawContents(in: bezel.insetBy(dx: 6, dy: 0), light: (isDefault || on) && !highlighted)
        } else {
            if highlighted, let context = NSGraphicsContext.currentCG {
                CG.fill(CG.roundedRect(frame, radius: 4), NSColor(white: 0, alpha: 0.1), in: context)
            }
            drawContents(in: frame, light: false)
        }
    }

    /// The title and image, side by side as the image position puts them.
    private func drawContents(in frame: CGRect, light: Bool) {
        let shown = showsState && state != 0
        let picture = shown ? (alternateImage ?? image) : image
        let text = shown && !alternateTitle.isEmpty ? alternateTitle : title
        let color = light ? NSColor.whiteColor() : displayColor(nil)
        var runs: [TextRun]
        if let attributedTitle, !shown { runs = Text.runs(attributedTitle, font: effectiveFont, color: color).runs } else {
            runs = [TextRun(text: text, font: effectiveFont, color: color)]
        }
        if imagePosition == 1 || text.isEmpty, let picture {
            ImageDrawing.draw(picture, fitting: frame)
            return
        }
        var textFrame = frame
        if let picture, imagePosition == 2 || imagePosition == 3 {
            let size = CGSize(width: min(picture.size.width, frame.height), height: min(picture.size.height, frame.height))
            let textWidth = Text.width(text, font: effectiveFont)
            let total = size.width + 4 + textWidth
            let start = frame.midX - total / 2
            let imageX = imagePosition == 2 ? start : start + textWidth + 4
            picture.draw(in: CGRect(x: imageX, y: frame.midY - size.height / 2, width: size.width, height: size.height))
            textFrame = CGRect(x: imagePosition == 2 ? start + size.width + 4 : start, y: frame.minY, width: textWidth + 1, height: frame.height)
        }
        let lineHeight = Text.lineHeight(effectiveFont)
        var style = TextStyle()
        style.alignment = alignment == 4 ? 1 : alignment
        style.maximumLines = 1
        style.lineBreakMode = 4
        let top = (textFrame.height - lineHeight) / 2
        Text.draw(runs, in: CGRect(x: textFrame.minX, y: textFrame.minY + top.rounded(.down), width: textFrame.width, height: lineHeight), style: style)
    }

    /// A check box or radio button, and its title to the right.
    private func drawCheck(_ frame: CGRect, context: CGRef) {
        let box = CGRect(x: frame.minX + 2, y: frame.midY - 7, width: 14, height: 14)
        let on = state != 0
        let radio = buttonType == 4
        let path = radio ? { () -> CGRef? in
            guard let p = CG.pathCreateMutable() else { return nil }
            CG.pathAddEllipseInRect(p, nil, box.insetBy(dx: 0.5, dy: 0.5))
            return p
        }() : CG.roundedRect(box.insetBy(dx: 0.5, dy: 0.5), radius: 3)
        let pathCopy = path.flatMap { CG.pathCreateMutableCopy($0) }
        CG.fill(path, on ? NSColor.controlAccentColor() : NSColor.whiteColor(), in: context)
        CG.stroke(pathCopy, NSColor(white: 0, alpha: on ? 0 : 0.3), width: 0.8, in: context)
        if on {
            if radio {
                guard let dot = CG.pathCreateMutable() else { return }
                CG.pathAddEllipseInRect(dot, nil, CGRect(x: box.midX - 3, y: box.midY - 3, width: 6, height: 6))
                CG.fill(dot, NSColor.whiteColor(), in: context)
            } else {
                let flipped = NSGraphicsContext.current?.flipped ?? false
                func y(_ dy: CGFloat) -> CGFloat { box.midY + (flipped ? dy : -dy) }
                CG.stroke(Arrows.polyline([CGPoint(x: box.minX + 3.5, y: y(0)), CGPoint(x: box.minX + 6, y: y(3)), CGPoint(x: box.maxX - 3, y: y(-3.5))]),
                          NSColor.whiteColor(), width: 1.8, in: context)
            }
        }
        var style = TextStyle()
        style.maximumLines = 1
        style.lineBreakMode = 4
        let lineHeight = Text.lineHeight(effectiveFont)
        let runs = attributedTitle.map { Text.runs($0, font: effectiveFont, color: displayColor(nil)).runs }
            ?? [TextRun(text: title, font: effectiveFont, color: displayColor(nil))]
        Text.draw(runs, in: CGRect(x: box.maxX + 5, y: frame.midY - lineHeight / 2, width: max(0, frame.maxX - box.maxX - 5), height: lineHeight), style: style)
    }
}

@ObjCClass("NSImageCell")
open class NSImageCell: NSCell {
    /// NSImageScaling: proportionally down 0, axes independently 1, none 2,
    /// proportionally up or down 3.
    var imageScaling: UInt = 0
    var imageAlignment: UInt = 0
    var imageFrameStyle: UInt = 0

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init(coder: coder)
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        imageScaling = UInt(decoded.integer("NSScale"))
        imageAlignment = UInt(decoded.integer("NSAlign"))
        imageFrameStyle = UInt(decoded.integer("NSStyle"))
        type = 2
    }

    @ObjCMethod("init")
    public required init() { super.init(); type = 2 }
    @ObjCMethod("initTextCell:")
    public required init(textCell text: String?) { super.init(textCell: text) }
    @ObjCMethod("initImageCell:")
    public required init(imageCell image: NSImage?) { super.init(imageCell: image) }

    @ObjCMethod("objectValue") override func cellObjectValue() -> NSObject? { image }
    @ObjCMethod("setObjectValue:")
    override func setObjectValue(_ value: NSObject?) {
        image = value?.as(NSImage.self)
        changed()
    }
    @ObjCMethod("imageScaling") func cellImageScaling() -> UInt { imageScaling }
    @ObjCMethod("setImageScaling:") func setImageScaling(_ value: UInt) { imageScaling = value; changed() }
    @ObjCMethod("imageAlignment") func cellImageAlignment() -> UInt { imageAlignment }
    @ObjCMethod("setImageAlignment:") func setImageAlignment(_ value: UInt) { imageAlignment = value; changed() }
    @ObjCMethod("imageFrameStyle") func cellImageFrameStyle() -> UInt { imageFrameStyle }
    @ObjCMethod("setImageFrameStyle:") func setImageFrameStyle(_ value: UInt) { imageFrameStyle = value }

    @ObjCMethod("drawInteriorWithFrame:inView:")
    override func drawInterior(withFrame frame: CGRect, in view: NSView?) {
        guard let image else { return }
        switch imageScaling {
        case 1: image.draw(in: frame)
        case 2:
            let size = image.size
            image.draw(in: CGRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height))
        case 3: ImageDrawing.draw(image, fitting: frame, scaleUp: true)
        default: ImageDrawing.draw(image, fitting: frame)
        }
    }
}

/// A table column's title, on the header's background with a separator to
/// its right.
@ObjCClass("NSTableHeaderCell")
open class NSTableHeaderCell: NSTextFieldCell {
    @ObjCMethod("drawWithFrame:inView:")
    override func draw(withFrame frame: CGRect, in view: NSView?) {
        guard let context = NSGraphicsContext.currentCG else { return }
        CG.saveGState(context)
        CG.setFillColorWithColor(context, NSColor.headerColor().cgColorRef)
        CG.fillRect(context, frame)
        CG.setFillColorWithColor(context, NSColor.separatorColor().cgColorRef)
        CG.fillRect(context, CGRect(x: frame.maxX - 1, y: frame.minY + 3, width: 1, height: frame.height - 6))
        CG.restoreGState(context)
        drawInterior(withFrame: frame, in: view)
    }

    @ObjCMethod("drawInteriorWithFrame:inView:")
    override func drawInterior(withFrame frame: CGRect, in view: NSView?) {
        let rect = CGRect(x: frame.minX + 4, y: frame.minY, width: max(0, frame.width - 8), height: frame.height)
        var style = textStyle
        style.maximumLines = 1
        style.lineBreakMode = 4
        let lineHeight = Text.lineHeight(effectiveFont)
        let top = ((rect.height - lineHeight) / 2).rounded(.down)
        Text.draw(textRuns(color: textColor ?? NSColor.headerTextColor()), in: CGRect(x: rect.minX, y: rect.minY + top, width: rect.width, height: lineHeight),
                  style: style)
    }

    @ObjCMethod("drawSortIndicatorWithFrame:inView:ascending:priority:")
    func drawSortIndicator(withFrame frame: CGRect, in view: NSView?, ascending: Bool, priority: Int) {}
    @ObjCMethod("sortIndicatorRectForBounds:") func sortIndicatorRect(forBounds rect: CGRect) -> CGRect { .zero }
}

/// NSPopUpButtonCell: a menu, the item it shows, and a bezel with arrows.
@ObjCClass("NSPopUpButtonCell")
open class NSPopUpButtonCell: NSButtonCell {
    var menu: NSMenu?
    var selectedIndex = -1
    var pullsDown = false
    var autoenablesItems = true
    var preferredEdge: UInt = 1

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init(coder: coder)
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        menu = decoded.object("NSMenu")?.as(NSMenu.self)
        pullsDown = decoded.bool("NSPullDown")
        if let item = decoded.object("NSMenuItem")?.as(NSMenuItem.self), let menu {
            selectedIndex = menu.index(of: item)
        }
        if selectedIndex < 0, let menu, !menu.items.isEmpty { selectedIndex = decoded.has("NSSelectedIndex") ? decoded.integer("NSSelectedIndex") : 0 }
        bordered = true
    }

    @ObjCMethod("init")
    public required init() {
        super.init()
        menu = NSMenu(title: "")
    }

    @ObjCMethod("initTextCell:")
    public required init(textCell text: String?) {
        super.init(textCell: text)
        menu = NSMenu(title: "")
    }

    @ObjCMethod("initImageCell:")
    public required init(imageCell image: NSImage?) { super.init(imageCell: image) }

    @ObjCMethod("initTextCell:pullsDown:")
    public required init(textCell text: String?, pullsDown: Bool) {
        super.init(textCell: text)
        menu = NSMenu(title: "")
        self.pullsDown = pullsDown
    }

    var items: [NSMenuItem] { menu?.items ?? [] }
    var selectedItem: NSMenuItem? { items.indices.contains(selectedIndex) ? items[selectedIndex] : nil }

    @ObjCMethod("menu") override func cellMenu() -> NSObject? { menu }
    @ObjCMethod("setMenu:") override func setMenu(_ value: NSObject?) { menu = value?.as(NSMenu.self); changed() }
    @ObjCMethod("pullsDown") func cellPullsDown() -> Bool { pullsDown }
    @ObjCMethod("setPullsDown:") func setPullsDown(_ value: Bool) { pullsDown = value }
    @ObjCMethod("autoenablesItems") func cellAutoenablesItems() -> Bool { autoenablesItems }
    @ObjCMethod("setAutoenablesItems:") func setAutoenablesItems(_ value: Bool) { autoenablesItems = value }
    @ObjCMethod("preferredEdge") func cellPreferredEdge() -> UInt { preferredEdge }
    @ObjCMethod("setPreferredEdge:") func setPreferredEdge(_ value: UInt) { preferredEdge = value }
    @ObjCMethod("selectedItem") func cellSelectedItem() -> NSMenuItem? { selectedItem }
    @ObjCMethod("indexOfSelectedItem") func indexOfSelectedItem() -> Int { selectedIndex }
    @ObjCMethod("selectItemAtIndex:") func selectItem(at index: Int) { selectedIndex = items.indices.contains(index) ? index : -1; changed() }
    @ObjCMethod("selectItem:") func selectItem(_ item: NSMenuItem?) { selectItem(at: items.firstIndex { $0 === item } ?? -1) }
    @ObjCMethod("numberOfItems") func numberOfItems() -> Int { items.count }
    @ObjCMethod("itemArray") func itemArray() -> NSObject { NSMutableArray.of(items) }
    @ObjCMethod("itemAtIndex:") func item(at index: Int) -> NSMenuItem? { items.indices.contains(index) ? items[index] : nil }
    @ObjCMethod("titleOfSelectedItem") func titleOfSelectedItem() -> String? { selectedItem?.title }
    @ObjCMethod("objectValue") override func cellObjectValue() -> NSObject? { NSNumber.make(integer: selectedIndex) }
    @ObjCMethod("setObjectValue:")
    override func setObjectValue(_ value: NSObject?) { selectItem(at: value.map { Send.integer($0.objcObject, "integerValue") } ?? -1) }
    @ObjCMethod("title") override func cellTitle() -> String { selectedItem?.title ?? "" }

    @ObjCMethod("drawWithFrame:inView:")
    override func draw(withFrame frame: CGRect, in view: NSView?) {
        guard let context = NSGraphicsContext.currentCG else { return }
        let bezel = CGRect(x: frame.minX + 1, y: frame.midY - min(frame.height, 22) / 2 + 0.5, width: frame.width - 2, height: min(frame.height, 22) - 1)
        if bordered {
            CG.fill(CG.roundedRect(bezel, radius: 5), NSColor.whiteColor(), in: context)
            CG.stroke(CG.roundedRect(bezel, radius: 5), NSColor(white: 0, alpha: 0.2), width: 0.5, in: context)
            let button = CGRect(x: bezel.maxX - 17, y: bezel.minY + 2, width: 15, height: bezel.height - 4)
            CG.fill(CG.roundedRect(button, radius: 3.5), NSColor.controlAccentColor(), in: context)
            Arrows.draw(in: button, color: NSColor.whiteColor(), context: context, double: !pullsDown)
        } else {
            Arrows.draw(in: CGRect(x: frame.maxX - 14, y: frame.minY, width: 12, height: frame.height), color: NSColor.secondaryLabelColor(),
                        context: context, double: !pullsDown)
        }
        let text = pullsDown ? (items.first?.title ?? title) : (selectedItem?.title ?? "")
        var style = TextStyle()
        style.maximumLines = 1
        style.lineBreakMode = 4
        let lineHeight = Text.lineHeight(effectiveFont)
        let rect = CGRect(x: bezel.minX + 8, y: bezel.midY - lineHeight / 2, width: max(0, bezel.width - 30), height: lineHeight)
        Text.draw([TextRun(text: text, font: effectiveFont, color: displayColor(nil))], in: rect, style: style)
    }

    @ObjCMethod("cellSize")
    override func cellSize() -> CGSize {
        let widest = items.map { Text.width($0.title, font: effectiveFont) }.max() ?? 40
        return CGSize(width: (widest + 40).rounded(.up), height: 21)
    }
}

/// NSSegmentedCell: its segments' labels, images, widths and which are
/// selected. NSSegmentSwitchTracking: select one 0, select any 1,
/// momentary 2.
@ObjCClass("NSSegmentedCell")
open class NSSegmentedCell: NSActionCell {
    struct Segment {
        var label = ""
        var image: NSImage?
        var width: CGFloat = 0
        var selected = false
        var enabled = true
        var tag = 0
        var toolTip: String?
        var menu: NSObject?
    }

    var segments: [Segment] = []
    var trackingMode: UInt = 0
    var segmentStyle = 0

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init(coder: coder)
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        segments = decoded.array("NSSegmentImages").map { item in
            var segment = Segment()
            if let source = item.as(NSSegmentItem.self) {
                segment = source.segment
            }
            return segment
        }
        trackingMode = UInt(decoded.integer("NSTrackingMode"))
        segmentStyle = decoded.integer("NSSegmentStyle")
        if decoded.has("NSSelectedSegment"), segments.indices.contains(decoded.integer("NSSelectedSegment")) {
            segments[decoded.integer("NSSelectedSegment")].selected = true
        }
    }

    @ObjCMethod("init")
    public required init() { super.init() }
    @ObjCMethod("initTextCell:")
    public required init(textCell text: String?) { super.init(textCell: text) }
    @ObjCMethod("initImageCell:")
    public required init(imageCell image: NSImage?) { super.init(imageCell: image) }

    func checked(_ index: Int) -> Bool { segments.indices.contains(index) }

    @ObjCMethod("segmentCount") func segmentCount() -> Int { segments.count }
    @ObjCMethod("setSegmentCount:")
    func setSegmentCount(_ count: Int) {
        if count < segments.count { segments.removeLast(segments.count - count) }
        while segments.count < count { segments.append(Segment()) }
        changed()
    }
    @ObjCMethod("selectedSegment") func selectedSegment() -> Int { segments.firstIndex { $0.selected } ?? -1 }
    @ObjCMethod("setSelectedSegment:")
    func setSelectedSegment(_ index: Int) {
        for i in segments.indices { segments[i].selected = trackingMode == 1 ? segments[i].selected : false }
        if checked(index) { segments[index].selected = true }
        changed()
    }
    @ObjCMethod("selectSegmentWithTag:")
    func selectSegment(withTag tag: Int) -> Bool {
        guard let index = segments.firstIndex(where: { $0.tag == tag }) else { return false }
        setSelectedSegment(index)
        return true
    }
    @ObjCMethod("setLabel:forSegment:") func setLabel(_ label: String?, forSegment index: Int) { if checked(index) { segments[index].label = label ?? ""; changed() } }
    @ObjCMethod("labelForSegment:") func label(forSegment index: Int) -> String? { checked(index) ? segments[index].label : nil }
    @ObjCMethod("setImage:forSegment:") func setImage(_ image: NSImage?, forSegment index: Int) { if checked(index) { segments[index].image = image; changed() } }
    @ObjCMethod("imageForSegment:") func image(forSegment index: Int) -> NSImage? { checked(index) ? segments[index].image : nil }
    @ObjCMethod("setWidth:forSegment:") func setWidth(_ width: CGFloat, forSegment index: Int) { if checked(index) { segments[index].width = width; changed() } }
    @ObjCMethod("widthForSegment:") func width(forSegment index: Int) -> CGFloat { checked(index) ? segments[index].width : 0 }
    @ObjCMethod("setSelected:forSegment:")
    func setSelected(_ selected: Bool, forSegment index: Int) {
        guard checked(index) else { return }
        if selected && trackingMode != 1 { for i in segments.indices { segments[i].selected = false } }
        segments[index].selected = selected
        changed()
    }
    @ObjCMethod("isSelectedForSegment:") func isSelected(forSegment index: Int) -> Bool { checked(index) && segments[index].selected }
    @ObjCMethod("setEnabled:forSegment:") func setEnabled(_ enabled: Bool, forSegment index: Int) { if checked(index) { segments[index].enabled = enabled; changed() } }
    @ObjCMethod("isEnabledForSegment:") func isEnabled(forSegment index: Int) -> Bool { checked(index) && segments[index].enabled }
    @ObjCMethod("setTag:forSegment:") func setTag(_ tag: Int, forSegment index: Int) { if checked(index) { segments[index].tag = tag } }
    @ObjCMethod("tagForSegment:") func tag(forSegment index: Int) -> Int { checked(index) ? segments[index].tag : 0 }
    @ObjCMethod("setToolTip:forSegment:") func setToolTip(_ tip: String?, forSegment index: Int) { if checked(index) { segments[index].toolTip = tip } }
    @ObjCMethod("setMenu:forSegment:") func setMenu(_ menu: NSObject?, forSegment index: Int) { if checked(index) { segments[index].menu = menu } }
    @ObjCMethod("menuForSegment:") func menu(forSegment index: Int) -> NSObject? { checked(index) ? segments[index].menu : nil }
    @ObjCMethod("trackingMode") func cellTrackingMode() -> UInt { trackingMode }
    @ObjCMethod("setTrackingMode:") func setTrackingMode(_ value: UInt) { trackingMode = value }
    @ObjCMethod("segmentStyle") func cellSegmentStyle() -> Int { segmentStyle }
    @ObjCMethod("setSegmentStyle:") func setSegmentStyle(_ value: Int) { segmentStyle = value }
    @ObjCMethod("setImageScaling:forSegment:") func setImageScaling(_ scaling: UInt, forSegment index: Int) {}

    /// Each segment's frame in `frame`: its own width, or a share of what
    /// is left.
    func frames(in frame: CGRect) -> [CGRect] {
        let fixed = segments.reduce(0) { $0 + $1.width }
        let open = segments.filter { $0.width <= 0 }.count
        let share = open > 0 ? max(0, frame.width - fixed) / CGFloat(open) : 0
        var x = frame.minX
        return segments.map { segment in
            let width = segment.width > 0 ? segment.width : share
            defer { x += width }
            return CGRect(x: x, y: frame.minY, width: width, height: frame.height)
        }
    }

    @ObjCMethod("drawWithFrame:inView:")
    override func draw(withFrame frame: CGRect, in view: NSView?) {
        guard let context = NSGraphicsContext.currentCG else { return }
        let bezel = CGRect(x: frame.minX + 1, y: frame.midY - min(frame.height, 22) / 2 + 0.5, width: frame.width - 2, height: min(frame.height, 22) - 1)
        CG.fill(CG.roundedRect(bezel, radius: 5), NSColor.whiteColor(), in: context)
        CG.stroke(CG.roundedRect(bezel, radius: 5), NSColor(white: 0, alpha: 0.2), width: 0.5, in: context)
        let lineHeight = Text.lineHeight(effectiveFont)
        for (index, rect) in frames(in: bezel).enumerated() {
            let segment = segments[index]
            if segment.selected { CG.fill(CG.roundedRect(rect.insetBy(dx: 1, dy: 1), radius: 4), NSColor.controlAccentColor(), in: context) }
            if index > 0 {
                CG.saveGState(context)
                CG.setFillColorWithColor(context, NSColor.separatorColor().cgColorRef)
                CG.fillRect(context, CGRect(x: rect.minX, y: rect.minY + 4, width: 1, height: rect.height - 8))
                CG.restoreGState(context)
            }
            if let image = segment.image, segment.label.isEmpty {
                ImageDrawing.draw(image, fitting: rect.insetBy(dx: 4, dy: 3))
            } else {
                var style = TextStyle()
                style.alignment = 1
                style.maximumLines = 1
                style.lineBreakMode = 4
                let color = segment.selected ? NSColor.whiteColor() : segment.enabled ? NSColor.controlTextColor() : NSColor.disabledControlTextColor()
                Text.draw([TextRun(text: segment.label, font: effectiveFont, color: color)],
                          in: CGRect(x: rect.minX + 4, y: rect.midY - lineHeight / 2, width: max(0, rect.width - 8), height: lineHeight), style: style)
            }
        }
    }
}

/// One segment as a nib archives it.
@ObjCClass("NSSegmentItem")
open class NSSegmentItem: NSObject {
    var segment = NSSegmentedCell.Segment()

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init()
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        segment.label = decoded.string("NSSegmentItemLabel") ?? ""
        segment.image = decoded.object("NSSegmentItemImage")?.as(NSImage.self)
        segment.width = decoded.double("NSSegmentItemWidth")
        segment.selected = decoded.bool("NSSegmentItemSelected")
        segment.enabled = !decoded.bool("NSSegmentItemDisabled")
        segment.tag = decoded.integer("NSSegmentItemTag")
        segment.toolTip = decoded.string("NSSegmentItemTooltip")
        segment.menu = decoded.object("NSSegmentItemMenu")
    }
}

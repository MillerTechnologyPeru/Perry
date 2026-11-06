import CPerryGeometry
import PerryObjCInterop

// NSTextView: text in a text storage (an attributed string), laid out in
// its width and drawn from its top; typing adds to the end while it is
// editable and the first responder. Its height follows its text in a
// scroll view. NSTextStorage is an attributed string the text view
// observes: it forwards the messages it doesn't answer itself to one, so
// it answers NSMutableAttributedString's. NSTextContainer and
// NSLayoutManager are kept for the apps that set them up.

@ObjCClass("NSTextStorage")
open class NSTextStorage: NSObject {
    var contents: NSObject = NSTextStorage.makeContents(nil)
    /// Not retained.
    var delegateObject: UnsafeMutableRawPointer?
    var layoutManagers: [NSLayoutManager] = []
    var editing = 0

    static func makeContents(_ string: String?) -> NSObject {
        let cls = Classes.named("NSMutableAttributedString")?.pointer
        let allocated = Send.object(cls, "alloc")
        let made = Send.object(allocated, "initWithString:", (string ?? "").objCArgument())
        return NSObject(objcObject: made!, ownership: .adopt)
    }

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithString:")
    public required init(string: String?) {
        super.init()
        contents = NSTextStorage.makeContents(string)
    }

    @ObjCMethod("initWithAttributedString:")
    public required init(attributedString: NSObject?) {
        super.init()
        if let attributedString, let copy = Send.object(attributedString.objcObject, "mutableCopy") {
            contents = NSObject(objcObject: copy, ownership: .adopt)
        }
    }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init()
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        if let string = decoded.object("NSString") {
            if string.responds(to: "UTF8String") { contents = NSTextStorage.makeContents(string.stringValue) } else if let copy = Send.object(string.objcObject, "mutableCopy") {
                contents = NSObject(objcObject: copy, ownership: .adopt)
            }
        }
        delegateObject = decoded.object("NSDelegate")?.objcObject
    }

    /// Everything else is the attributed string's.
    @ObjCMethod("forwardingTargetForSelector:")
    func forwardingTarget(for selector: ObjCSelector?) -> NSObject? { contents }

    var string: String { Send.object(contents.objcObject, "string").map { String(objCArgument: $0) } ?? "" }

    /// The text changed: its layout managers' text views show it again.
    func edited() {
        guard editing == 0 else { return }
        if Send.responds(delegateObject, "textStorageDidProcessEditing:") {
            Send.void(delegateObject, "textStorageDidProcessEditing:", NSNotification.make(name: "NSTextStorageDidProcessEditingNotification", object: self).objcObject)
        }
        for manager in layoutManagers { manager.textChanged() }
    }

    @ObjCMethod("string") func storageString() -> String { string }
    @ObjCMethod("length") func length() -> UInt { UInt(Send.integer(contents.objcObject, "length")) }
    @ObjCMethod("mutableString") func mutableString() -> NSObject? { Send.object(contents.objcObject, "mutableString").map(NSObject.init) }
    @ObjCMethod("delegate") func storageDelegate() -> NSObject? { delegateObject.map(NSObject.init) }
    @ObjCMethod("setDelegate:") func setDelegate(_ value: NSObject?) { delegateObject = value?.objcObject }
    @ObjCMethod("layoutManagers") func storageLayoutManagers() -> NSObject { NSMutableArray.of(layoutManagers) }
    @ObjCMethod("addLayoutManager:")
    func addLayoutManager(_ manager: NSLayoutManager?) {
        guard let manager else { return }
        layoutManagers.append(manager)
        manager.textStorage = self
    }
    @ObjCMethod("removeLayoutManager:") func removeLayoutManager(_ manager: NSLayoutManager?) { layoutManagers.removeAll { $0 === manager } }
    @ObjCMethod("beginEditing") func beginEditing() { editing += 1 }
    @ObjCMethod("endEditing")
    func endEditing() {
        editing = max(0, editing - 1)
        edited()
    }
    @ObjCMethod("edited:range:changeInLength:") func edited(_ mask: UInt, range: NSRange, changeInLength delta: Int) { edited() }
    @ObjCMethod("processEditing") func processEditing() { edited() }
    @ObjCMethod("setAttributedString:")
    func setAttributedString(_ value: NSObject?) {
        Send.void(contents.objcObject, "setAttributedString:", value?.objcObject)
        edited()
    }
    @ObjCMethod("appendAttributedString:")
    func appendAttributedString(_ value: NSObject?) {
        Send.void(contents.objcObject, "appendAttributedString:", value?.objcObject)
        edited()
    }
    @ObjCMethod("replaceCharactersInRange:withString:")
    func replaceCharacters(in range: NSRange, with string: String?) {
        typealias F = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, NSRange, UnsafeMutableRawPointer?) -> Void
        unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(contents.objcObject, ObjCRuntime.selector("replaceCharactersInRange:withString:"), range,
                                                       (string ?? "").objCArgument())
        edited()
    }
    @ObjCMethod("replaceCharactersInRange:withAttributedString:")
    func replaceCharacters(in range: NSRange, withAttributedString string: NSObject?) {
        typealias F = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, NSRange, UnsafeMutableRawPointer?) -> Void
        unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(contents.objcObject, ObjCRuntime.selector("replaceCharactersInRange:withAttributedString:"), range,
                                                       string?.objcObject)
        edited()
    }
    @ObjCMethod("deleteCharactersInRange:")
    func deleteCharacters(in range: NSRange) {
        typealias F = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, NSRange) -> Void
        unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(contents.objcObject, ObjCRuntime.selector("deleteCharactersInRange:"), range)
        edited()
    }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { Send.object(contents.objcObject, "copy") }
    @ObjCMethod("mutableCopyWithZone:") func mutableCopy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { Send.object(contents.objcObject, "mutableCopy") }
    @ObjCMethod("description") func storageDescription() -> String { string }
}

@ObjCClass("NSLayoutManager")
open class NSLayoutManager: NSObject {
    /// Not retained.
    var textStorageObject: UnsafeMutableRawPointer?
    var containers: [NSTextContainer] = []
    /// Not retained.
    var delegateObject: UnsafeMutableRawPointer?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init()
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        containers = decoded.array("NSTextContainers").compactMap { $0.as(NSTextContainer.self) }
        if let storage = decoded.object("NSTextStorage")?.as(NSTextStorage.self) {
            textStorageObject = storage.objcObject
            if !storage.layoutManagers.contains(where: { $0 === self }) { storage.layoutManagers.append(self) }
        }
        delegateObject = decoded.object("NSDelegate")?.objcObject
    }

    var textStorage: NSTextStorage? {
        get { textStorageObject.map { NSTextStorage.objCInstance($0, ownership: .retain) } }
        set { textStorageObject = newValue?.objcObject }
    }

    func textChanged() {
        for container in containers { container.textView?.textChanged() }
    }

    @ObjCMethod("textStorage") func managerTextStorage() -> NSTextStorage? { textStorage }
    @ObjCMethod("setTextStorage:") func setTextStorage(_ value: NSTextStorage?) { textStorage = value }
    @ObjCMethod("replaceTextStorage:") func replaceTextStorage(_ value: NSTextStorage?) { value?.addLayoutManager(self) }
    @ObjCMethod("textContainers") func textContainers() -> NSObject { NSMutableArray.of(containers) }
    @ObjCMethod("addTextContainer:")
    func addTextContainer(_ container: NSTextContainer?) {
        guard let container else { return }
        containers.append(container)
        container.layoutManagerObject = objcObject
    }
    @ObjCMethod("removeTextContainerAtIndex:") func removeTextContainer(at index: Int) { if containers.indices.contains(index) { containers.remove(at: index) } }
    @ObjCMethod("delegate") func managerDelegate() -> NSObject? { delegateObject.map(NSObject.init) }
    @ObjCMethod("setDelegate:") func setDelegate(_ value: NSObject?) { delegateObject = value?.objcObject }
    @ObjCMethod("ensureLayoutForTextContainer:") func ensureLayout(for container: NSTextContainer?) {}
    @ObjCMethod("ensureLayoutForCharacterRange:") func ensureLayout(forCharacterRange range: NSRange) {}
    @ObjCMethod("usedRectForTextContainer:")
    func usedRect(for container: NSTextContainer?) -> CGRect {
        guard let view = container?.textView else { return .zero }
        return CGRect(origin: .zero, size: view.textSize(width: container?.size.width ?? view.bounds.width))
    }
    @ObjCMethod("numberOfGlyphs") func numberOfGlyphs() -> UInt { textStorage?.length() ?? 0 }
    @ObjCMethod("setAllowsNonContiguousLayout:") func setAllowsNonContiguousLayout(_ value: Bool) {}
    @ObjCMethod("setBackgroundLayoutEnabled:") func setBackgroundLayoutEnabled(_ value: Bool) {}
    @ObjCMethod("setShowsInvisibleCharacters:") func setShowsInvisibleCharacters(_ value: Bool) {}
    @ObjCMethod("setShowsControlCharacters:") func setShowsControlCharacters(_ value: Bool) {}
    @ObjCMethod("setUsesFontLeading:") func setUsesFontLeading(_ value: Bool) {}
    @ObjCMethod("defaultLineHeightForFont:") func defaultLineHeight(for font: NSFont?) -> CGFloat { Text.lineHeight(font ?? NSFont.system(size: 12)) }
    @ObjCMethod("glyphRangeForTextContainer:") func glyphRange(for container: NSTextContainer?) -> NSRange { NSRange(location: 0, length: numberOfGlyphs()) }
}

@ObjCClass("NSTextContainer")
open class NSTextContainer: NSObject {
    var size = CGSize(width: 10_000_000, height: 10_000_000)
    var lineFragmentPadding: CGFloat = 5
    var widthTracksTextView = true
    var heightTracksTextView = false
    /// Not retained.
    var textViewObject: UnsafeMutableRawPointer?
    /// Not retained.
    var layoutManagerObject: UnsafeMutableRawPointer?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithSize:")
    public required init(size: CGSize) {
        super.init()
        self.size = size
    }

    @ObjCMethod("initWithContainerSize:")
    public required init(containerSize: CGSize) {
        super.init()
        size = containerSize
    }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init()
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        if decoded.has("NSWidth") { size.width = decoded.double("NSWidth") }
        textViewObject = decoded.object("NSTextView")?.objcObject
        layoutManagerObject = decoded.object("NSLayoutManager")?.objcObject
        let flags = decoded.integer("NSTCFlags")
        widthTracksTextView = flags & 1 != 0
        heightTracksTextView = flags & 2 != 0
    }

    var textView: NSTextView? { textViewObject.map { NSTextView.objCInstance($0, ownership: .retain) } }
    var layoutManager: NSLayoutManager? { layoutManagerObject.map { NSLayoutManager.objCInstance($0, ownership: .retain) } }

    @ObjCMethod("size") func containerSize() -> CGSize { size }
    @ObjCMethod("setSize:") func setSize(_ value: CGSize) { size = value; textView?.textChanged() }
    @ObjCMethod("containerSize") func legacyContainerSize() -> CGSize { size }
    @ObjCMethod("setContainerSize:") func setContainerSize(_ value: CGSize) { setSize(value) }
    @ObjCMethod("lineFragmentPadding") func containerLineFragmentPadding() -> CGFloat { lineFragmentPadding }
    @ObjCMethod("setLineFragmentPadding:") func setLineFragmentPadding(_ value: CGFloat) { lineFragmentPadding = value }
    @ObjCMethod("widthTracksTextView") func containerWidthTracksTextView() -> Bool { widthTracksTextView }
    @ObjCMethod("setWidthTracksTextView:") func setWidthTracksTextView(_ value: Bool) { widthTracksTextView = value }
    @ObjCMethod("heightTracksTextView") func containerHeightTracksTextView() -> Bool { heightTracksTextView }
    @ObjCMethod("setHeightTracksTextView:") func setHeightTracksTextView(_ value: Bool) { heightTracksTextView = value }
    @ObjCMethod("textView") func containerTextView() -> NSTextView? { textView }
    @ObjCMethod("setTextView:") func setTextView(_ view: NSTextView?) { textViewObject = view?.objcObject }
    @ObjCMethod("layoutManager") func containerLayoutManager() -> NSLayoutManager? { layoutManager }
    @ObjCMethod("setMaximumNumberOfLines:") func setMaximumNumberOfLines(_ value: Int) {}
    @ObjCMethod("setLineBreakMode:") func setLineBreakMode(_ value: Int) {}
}

/// What a nib's text views share: their colors and flags.
@ObjCClass("NSTextViewSharedData")
open class NSTextViewSharedData: NSObject {
    var backgroundColor: NSColor?
    var insertionColor: NSColor?
    var flags = 0
    var defaultParagraphStyle: NSObject?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init()
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        backgroundColor = decoded.object("NSBackgroundColor")?.as(NSColor.self)
        insertionColor = decoded.object("NSInsertionColor")?.as(NSColor.self)
        flags = decoded.integer("NSFlags")
        defaultParagraphStyle = decoded.object("NSDefaultParagraphStyle")
    }
}

/// NSText: text's settings, which NSTextView adds to.
@ObjCClass("NSText")
open class NSText: NSView {
    var editable = true
    var selectable = true
    var richText = true
    var drawsBackground = true
    var backgroundColor: NSColor = NSColor.textBackgroundColor()
    var textColor: NSColor?
    var font: NSFont?
    var alignment = 4
    var verticallyResizable = true
    var horizontallyResizable = false
    var minSize = CGSize.zero
    var maxSize = CGSize(width: 10_000_000, height: 10_000_000)
    /// Not retained.
    var delegateObject: UnsafeMutableRawPointer?
    var fieldEditor = false
    var editing = false
}

@ObjCClass("NSTextView")
open class NSTextView: NSText {
    var storage: NSTextStorage?
    var container: NSTextContainer?
    var manager: NSLayoutManager?
    var textContainerInset = CGSize.zero
    var selectedRange = NSRange(location: 0, length: 0)
    var insertionPointColor: NSColor?
    var allowsUndo = false
    var usesFindBar = false

    public required init() {
        super.init()
        setUpText(size: frame.size)
    }

    @ObjCMethod("initWithFrame:")
    public required init(frame: CGRect) {
        super.init(frame: frame)
        setUpText(size: frame.size)
    }

    @ObjCMethod("initWithFrame:textContainer:")
    public required init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame)
        if let textContainer {
            container = textContainer
            manager = textContainer.layoutManager
            storage = manager?.textStorage
            textContainer.textViewObject = objcObject
        }
        if storage == nil { setUpText(size: frame.size) }
    }

    /// A nib's text view: its container, the container's layout manager and
    /// the text storage, and its shared data's settings ("NSTVFlags":
    /// vertically resizable 0x1, horizontally 0x2... the editability in the
    /// shared data's "NSFlags": editable 0x2, selectable 0x1, rich 0x4).
    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init(coder: coder)
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        container = decoded.object("NSTextContainer")?.as(NSTextContainer.self)
        container?.textViewObject = objcObject
        manager = container?.layoutManager
        storage = manager?.textStorage
        if decoded.has("NSMaxSize") { maxSize = decoded.size("NSMaxSize") }
        textColor = decoded.object("NSTextViewTextColor")?.as(NSColor.self)
        delegateObject = decoded.object("NSDelegate")?.objcObject
        let flags = decoded.integer("NSTVFlags")
        verticallyResizable = flags & 1 != 0 || !decoded.has("NSTVFlags")
        horizontallyResizable = flags & 2 != 0
        if let shared = decoded.object("NSSharedData")?.as(NSTextViewSharedData.self) {
            backgroundColor = shared.backgroundColor ?? backgroundColor
            insertionPointColor = shared.insertionColor
            editable = shared.flags & 2 != 0
            selectable = shared.flags & 1 != 0
            richText = shared.flags & 4 != 0
            drawsBackground = shared.flags & 0x800 != 0 || shared.backgroundColor != nil
        }
        if storage == nil { setUpText(size: frame.size) }
    }

    private func setUpText(size: CGSize) {
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: size.width, height: 10_000_000))
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        container.textViewObject = objcObject
        (self.storage, self.manager, self.container) = (storage, manager, container)
    }

    @ObjCClassMethod("scrollableTextView")
    static func scrollableTextView() -> NSScrollView {
        let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        scroll.setHasVerticalScroller(true)
        let text = NSTextView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        text.autoresizingMask = 2
        scroll.setDocumentView(text)
        return scroll
    }

    var string: String { storage?.string ?? "" }

    // MARK: Text

    @ObjCMethod("string") func textString() -> String { string }
    @ObjCMethod("setString:")
    func setString(_ value: String?) {
        storage?.contents = NSTextStorage.makeContents(value)
        textChanged()
    }
    @ObjCMethod("textStorage") func textStorage() -> NSTextStorage? { storage }
    @ObjCMethod("layoutManager") func layoutManager() -> NSLayoutManager? { manager }
    @ObjCMethod("textContainer") func textContainer() -> NSTextContainer? { container }
    @ObjCMethod("setTextContainer:")
    func setTextContainer(_ value: NSTextContainer?) {
        container = value
        value?.textViewObject = objcObject
        manager = value?.layoutManager
        storage = manager?.textStorage ?? storage
        textChanged()
    }
    @ObjCMethod("replaceTextContainer:") func replaceTextContainer(_ value: NSTextContainer?) { setTextContainer(value) }
    @ObjCMethod("textContainerInset") func viewTextContainerInset() -> CGSize { textContainerInset }
    @ObjCMethod("setTextContainerInset:") func setTextContainerInset(_ value: CGSize) { textContainerInset = value; textChanged() }
    @ObjCMethod("textContainerOrigin") func textContainerOrigin() -> CGPoint { CGPoint(x: textContainerInset.width, y: textContainerInset.height) }
    @ObjCMethod("insertText:")
    func insertText(_ value: NSObject?) {
        guard let value else { return }
        let end = NSRange(location: storage?.length() ?? 0, length: 0)
        if value.responds(to: "UTF8String") { storage?.replaceCharacters(in: end, with: value.stringValue) } else {
            storage?.replaceCharacters(in: end, withAttributedString: value)
        }
        didChangeText()
    }
    @ObjCMethod("insertText:replacementRange:") func insertText(_ value: NSObject?, replacementRange: NSRange) { insertText(value) }
    @ObjCMethod("didChangeText")
    func didChangeText() {
        let notification = NSNotification.make(name: Constants.NSTextDidChangeNotification, object: self)
        if Send.responds(delegateObject, "textDidChange:") { Send.void(delegateObject, "textDidChange:", notification.objcObject) }
        NSNotificationCenter.defaultCenter().post(notification)
    }
    @ObjCMethod("shouldChangeTextInRange:replacementString:") func shouldChangeText(in range: NSRange, replacementString: String?) -> Bool { editable }
    @ObjCMethod("selectedRange") func viewSelectedRange() -> NSRange { selectedRange }
    @ObjCMethod("setSelectedRange:") func setSelectedRange(_ range: NSRange) { selectedRange = range }
    @ObjCMethod("selectedRanges") func selectedRanges() -> NSObject { NSMutableArray.empty() }
    @ObjCMethod("setSelectedRanges:") func setSelectedRanges(_ ranges: NSObject?) {}
    @ObjCMethod("scrollRangeToVisible:")
    func scrollRangeToVisible(_ range: NSRange) {
        // The end of the text: as apps scroll a log to its last line.
        _ = scrollRectToVisible(CGRect(x: 0, y: max(0, bounds.height - 1), width: 1, height: 1))
    }
    @ObjCMethod("scrollToEndOfDocument:") func scrollToEndOfDocument(_ sender: NSObject?) { scrollRangeToVisible(NSRange(location: 0, length: 0)) }
    @ObjCMethod("scrollToBeginningOfDocument:") func scrollToBeginningOfDocument(_ sender: NSObject?) { _ = scrollRectToVisible(CGRect(x: 0, y: 0, width: 1, height: 1)) }
    @ObjCMethod("selectAll:") func selectAll(_ sender: NSObject?) { selectedRange = NSRange(location: 0, length: storage?.length() ?? 0) }
    @ObjCMethod("copy:")
    func copyText(_ sender: NSObject?) { _ = NSPasteboard.generalPasteboard().setString(string, forType: Constants.NSPasteboardTypeString) }
    @ObjCMethod("delete:") func deleteText(_ sender: NSObject?) {}

    // MARK: Settings

    @ObjCMethod("isEditable") func isEditable() -> Bool { editable }
    @ObjCMethod("setEditable:") func setEditable(_ value: Bool) { editable = value }
    @ObjCMethod("isSelectable") func isSelectable() -> Bool { selectable }
    @ObjCMethod("setSelectable:") func setSelectable(_ value: Bool) { selectable = value }
    @ObjCMethod("isRichText") func isRichText() -> Bool { richText }
    @ObjCMethod("setRichText:") func setRichText(_ value: Bool) { richText = value }
    @ObjCMethod("drawsBackground") func textDrawsBackground() -> Bool { drawsBackground }
    @ObjCMethod("setDrawsBackground:") func setDrawsBackground(_ value: Bool) { drawsBackground = value; setNeedsDisplay(true) }
    @ObjCMethod("backgroundColor") func textBackgroundColor() -> NSColor { backgroundColor }
    @ObjCMethod("setBackgroundColor:") func setBackgroundColor(_ value: NSColor?) { backgroundColor = value ?? backgroundColor; setNeedsDisplay(true) }
    @ObjCMethod("textColor") func viewTextColor() -> NSColor? { textColor }
    @ObjCMethod("setTextColor:") func setTextColor(_ value: NSColor?) { textColor = value; setNeedsDisplay(true) }
    @ObjCMethod("font") func viewFont() -> NSFont? { font }
    @ObjCMethod("setFont:") func setFont(_ value: NSFont?) { font = value; textChanged() }
    @ObjCMethod("alignment") func viewAlignment() -> Int { alignment }
    @ObjCMethod("setAlignment:") func setAlignment(_ value: Int) { alignment = value; setNeedsDisplay(true) }
    @ObjCMethod("delegate") func textDelegate() -> NSObject? { delegateObject.map(NSObject.init) }
    @ObjCMethod("setDelegate:") func setDelegate(_ value: NSObject?) { delegateObject = value?.objcObject }
    @ObjCMethod("isVerticallyResizable") func isVerticallyResizable() -> Bool { verticallyResizable }
    @ObjCMethod("setVerticallyResizable:") func setVerticallyResizable(_ value: Bool) { verticallyResizable = value }
    @ObjCMethod("isHorizontallyResizable") func isHorizontallyResizable() -> Bool { horizontallyResizable }
    @ObjCMethod("setHorizontallyResizable:") func setHorizontallyResizable(_ value: Bool) { horizontallyResizable = value }
    @ObjCMethod("minSize") func textMinSize() -> CGSize { minSize }
    @ObjCMethod("setMinSize:") func setMinSize(_ value: CGSize) { minSize = value }
    @ObjCMethod("maxSize") func textMaxSize() -> CGSize { maxSize }
    @ObjCMethod("setMaxSize:") func setMaxSize(_ value: CGSize) { maxSize = value }
    @ObjCMethod("isFieldEditor") func isFieldEditor() -> Bool { fieldEditor }
    @ObjCMethod("setFieldEditor:") func setFieldEditor(_ value: Bool) { fieldEditor = value }
    @ObjCMethod("insertionPointColor") func viewInsertionPointColor() -> NSColor? { insertionPointColor }
    @ObjCMethod("setInsertionPointColor:") func setInsertionPointColor(_ value: NSColor?) { insertionPointColor = value }
    @ObjCMethod("allowsUndo") func viewAllowsUndo() -> Bool { allowsUndo }
    @ObjCMethod("setAllowsUndo:") func setAllowsUndo(_ value: Bool) { allowsUndo = value }
    @ObjCMethod("usesFindBar") func viewUsesFindBar() -> Bool { usesFindBar }
    @ObjCMethod("setUsesFindBar:") func setUsesFindBar(_ value: Bool) { usesFindBar = value }
    @ObjCMethod("setUsesFontPanel:") func setUsesFontPanel(_ value: Bool) {}
    @ObjCMethod("setUsesRuler:") func setUsesRuler(_ value: Bool) {}
    @ObjCMethod("setImportsGraphics:") func setImportsGraphics(_ value: Bool) {}
    @ObjCMethod("setAutomaticQuoteSubstitutionEnabled:") func setAutomaticQuoteSubstitutionEnabled(_ value: Bool) {}
    @ObjCMethod("setAutomaticDashSubstitutionEnabled:") func setAutomaticDashSubstitutionEnabled(_ value: Bool) {}
    @ObjCMethod("setAutomaticTextReplacementEnabled:") func setAutomaticTextReplacementEnabled(_ value: Bool) {}
    @ObjCMethod("setAutomaticSpellingCorrectionEnabled:") func setAutomaticSpellingCorrectionEnabled(_ value: Bool) {}
    @ObjCMethod("setContinuousSpellCheckingEnabled:") func setContinuousSpellCheckingEnabled(_ value: Bool) {}
    @ObjCMethod("setGrammarCheckingEnabled:") func setGrammarCheckingEnabled(_ value: Bool) {}
    @ObjCMethod("setAutomaticLinkDetectionEnabled:") func setAutomaticLinkDetectionEnabled(_ value: Bool) {}
    @ObjCMethod("setAutomaticDataDetectionEnabled:") func setAutomaticDataDetectionEnabled(_ value: Bool) {}
    @ObjCMethod("setSmartInsertDeleteEnabled:") func setSmartInsertDeleteEnabled(_ value: Bool) {}
    @ObjCMethod("setLinkTextAttributes:") func setLinkTextAttributes(_ value: NSObject?) {}
    @ObjCMethod("setTypingAttributes:") func setTypingAttributes(_ value: NSObject?) {}
    @ObjCMethod("typingAttributes") func typingAttributes() -> NSObject { NSMutableDictionary.empty() }
    @ObjCMethod("setDefaultParagraphStyle:") func setDefaultParagraphStyle(_ value: NSObject?) {}
    @ObjCMethod("sizeToFit") func sizeToFit() { textChanged() }
    @ObjCMethod("isFlipped") override func isFlipped() -> Bool { true }
    @ObjCMethod("acceptsFirstResponder") override func acceptsFirstResponder() -> Bool { selectable || editable }

    // MARK: Layout and drawing

    var effectiveFont: NSFont { font ?? NSFont(name: "Helvetica", size: 12) }

    func runs() -> (runs: [TextRun], style: TextStyle) {
        guard let storage else { return ([], TextStyle()) }
        let (runs, paragraph) = Text.runs(storage.contents, font: effectiveFont, color: textColor ?? NSColor.textColor())
        var style = TextStyle()
        style.alignment = alignment
        Text.style(paragraph, into: &style)
        return (runs, style)
    }

    /// The text's size laid out in `width`.
    func textSize(width: CGFloat) -> CGSize {
        let padding = container?.lineFragmentPadding ?? 5
        let (runs, style) = runs()
        let size = Text.size(runs, width: max(1, width - 2 * padding - 2 * textContainerInset.width), style: style)
        return CGSize(width: size.width + 2 * padding, height: max(size.height, Text.lineHeight(effectiveFont)))
    }

    /// The text changed: a vertically resizable view grows to hold it (at
    /// least as tall as its clip view), and draws again.
    func textChanged() {
        if verticallyResizable {
            let height = textSize(width: frame.width).height + 2 * textContainerInset.height
            let clip = superview?.as(NSClipView.self)?.bounds.height ?? 0
            let target = min(maxSize.height, max(minSize.height, max(height, clip)))
            if abs(target - frame.height) > 0.5 { Send.void(objcObject, "setFrameSize:", size: CGSize(width: frame.width, height: target)) }
        }
        setNeedsDisplay(true)
    }

    @ObjCMethod("viewDidMoveToSuperview") override func viewDidMoveToSuperview() { textChanged() }

    @ObjCMethod("drawRect:")
    override func draw(_ rect: CGRect) {
        guard let context = NSGraphicsContext.currentCG else { return }
        if drawsBackground {
            CG.saveGState(context)
            CG.setFill(context, backgroundColor)
            CG.fillRect(context, bounds)
            CG.restoreGState(context)
        }
        let padding = container?.lineFragmentPadding ?? 5
        let (runs, style) = runs()
        let area = CGRect(x: textContainerInset.width + padding, y: textContainerInset.height,
                          width: max(1, bounds.width - 2 * (textContainerInset.width + padding)), height: bounds.height)
        Text.draw(runs, in: area, style: style)
    }

    @ObjCMethod("becomeFirstResponder")
    override func becomeFirstResponder() -> Bool {
        editing = editable
        return true
    }

    @ObjCMethod("resignFirstResponder")
    override func resignFirstResponder() -> Bool {
        editing = false
        return true
    }

    @ObjCMethod("keyDown:")
    override func keyDown(_ eventObject: NSObject?) {
        guard editing, let event = eventObject?.as(NSEvent.self), let storage else { return super.keyDown(eventObject) }
        let typed = event.characters
        let length = storage.length()
        switch typed {
        case "\u{7f}", "\u{8}":
            guard length > 0 else { return }
            storage.deleteCharacters(in: NSRange(location: length - 1, length: 1))
        case "\r", "\u{3}":
            storage.replaceCharacters(in: NSRange(location: length, length: 0), with: "\n")
        default:
            guard !typed.isEmpty, event.modifierFlags & ModifierFlags.command == 0,
                  typed.unicodeScalars.allSatisfy({ $0.value >= 0x20 && !(0xF700...0xF8FF).contains($0.value) }) else { return super.keyDown(eventObject) }
            storage.replaceCharacters(in: NSRange(location: length, length: 0), with: typed)
        }
        didChangeText()
    }
}

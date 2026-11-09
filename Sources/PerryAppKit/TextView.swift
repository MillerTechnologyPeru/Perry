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

    // MARK: Geometry
    //
    // A glyph is a UTF-16 unit of the text. Rectangles are in the container's
    // coordinates: the view's, less its text container's origin.

    private var view: NSTextView? { containers.first?.textView }

    private static func store(_ range: NSRange, _ pointer: UnsafeMutableRawPointer?) {
        pointer?.storeBytes(of: range, as: NSRange.self)
    }

    private func toContainer(_ rect: CGRect) -> CGRect {
        guard let view else { return rect }
        return CGRect(x: rect.minX - view.textContainerInset.width, y: rect.minY - view.textContainerInset.height, width: rect.width, height: rect.height)
    }

    @ObjCMethod("glyphRangeForBoundingRect:inTextContainer:")
    func glyphRange(forBoundingRect rect: CGRect, in container: NSTextContainer?) -> NSRange {
        guard let view else { return NSRange(location: 0, length: 0) }
        let seen = view.fragments.filter { toContainer($0.rect).maxY >= rect.minY && toContainer($0.rect).minY <= rect.maxY }
        guard let first = seen.first, let last = seen.last else { return NSRange(location: 0, length: 0) }
        return NSRange(location: UInt(first.range.lowerBound), length: UInt(last.range.upperBound - first.range.lowerBound))
    }

    @ObjCMethod("glyphRangeForBoundingRectWithoutAdditionalLayout:inTextContainer:")
    func glyphRangeWithoutLayout(forBoundingRect rect: CGRect, in container: NSTextContainer?) -> NSRange { glyphRange(forBoundingRect: rect, in: container) }

    @ObjCMethod("characterRangeForGlyphRange:actualGlyphRange:")
    func characterRange(forGlyphRange range: NSRange, actual: UnsafeMutableRawPointer?) -> NSRange {
        NSLayoutManager.store(range, actual)
        return range
    }

    @ObjCMethod("glyphRangeForCharacterRange:actualCharacterRange:")
    func glyphRange(forCharacterRange range: NSRange, actual: UnsafeMutableRawPointer?) -> NSRange {
        NSLayoutManager.store(range, actual)
        return range
    }

    @ObjCMethod("characterIndexForGlyphAtIndex:") func characterIndex(forGlyphAt index: UInt) -> UInt { index }
    @ObjCMethod("glyphIndexForCharacterAtIndex:") func glyphIndex(forCharacterAt index: UInt) -> UInt { index }

    @ObjCMethod("boundingRectForGlyphRange:inTextContainer:")
    func boundingRect(forGlyphRange range: NSRange, in container: NSTextContainer?) -> CGRect {
        view.map { toContainer($0.rect(forCharacters: Int(range.location)..<Int(range.location + range.length))) } ?? .zero
    }

    @ObjCMethod("lineFragmentRectForGlyphAtIndex:effectiveRange:")
    func lineFragmentRect(forGlyphAt index: UInt, effectiveRange: UnsafeMutableRawPointer?) -> CGRect {
        guard let view, let fragment = view.fragment(containing: Int(index)) else { return .zero }
        NSLayoutManager.store(NSRange(location: UInt(fragment.range.lowerBound), length: UInt(fragment.range.count)), effectiveRange)
        var rect = toContainer(fragment.rect)
        rect.origin.x = 0
        rect.size.width = view.frame.width - 2 * view.textContainerInset.width
        return rect
    }

    @ObjCMethod("lineFragmentUsedRectForGlyphAtIndex:effectiveRange:")
    func lineFragmentUsedRect(forGlyphAt index: UInt, effectiveRange: UnsafeMutableRawPointer?) -> CGRect {
        guard let view, let fragment = view.fragment(containing: Int(index)) else { return .zero }
        NSLayoutManager.store(NSRange(location: UInt(fragment.range.lowerBound), length: UInt(fragment.range.count)), effectiveRange)
        return toContainer(fragment.rect)
    }

    @ObjCMethod("invalidateDisplayForCharacterRange:") func invalidateDisplay(forCharacterRange range: NSRange) { view?.setNeedsDisplay(true) }
    @ObjCMethod("invalidateLayoutForCharacterRange:actualCharacterRange:")
    func invalidateLayout(forCharacterRange range: NSRange, actual: UnsafeMutableRawPointer?) { view?.textChanged() }
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
    /// The automatic substitution, spelling and the like switches set, by name.
    var switches: [String: Bool] = [:]
    var checkingTypes: UInt64 = 0
    var storage: NSTextStorage?
    var container: NSTextContainer?
    var manager: NSLayoutManager?
    var textContainerInset = CGSize.zero
    var selectedRange = NSRange(location: 0, length: 0)
    var insertionPointColor: NSColor?
    var allowsUndo = false
    var usesFindBar = false
    /// Where a selection being extended started.
    var selectionAnchor = 0
    var typingAttributesObject: NSObject?
    var defaultParagraphStyleObject: NSObject?
    var selectedTextAttributesObject: NSObject?
    var linkTextAttributesObject: NSObject?
    var cachedFragments: [Fragment]?

    /// A line of the laid-out text: the characters it holds, with what ends
    /// it, and where it is in the view.
    struct Fragment {
        var range: Range<Int>
        var rect: CGRect
        var line: Text.Line
    }

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
        insert(value, replacing: selectedRange)
    }
    @ObjCMethod("insertText:replacementRange:")
    func insertText(_ value: NSObject?, replacementRange: NSRange) {
        guard let value else { return }
        insert(value, replacing: replacementRange.location == UInt(Int.max) ? selectedRange : replacementRange)
    }

    /// Replaces a range as typing does, asking first and telling after,
    /// leaving the insertion point after the new text.
    private func insert(_ value: NSObject, replacing range: NSRange) {
        guard let storage else { return }
        let isString = value.responds(to: "UTF8String")
        let text = isString ? value.stringValue : Send.object(value.objcObject, "string").map { NSObject($0).stringValue } ?? ""
        typealias Ask = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, NSRange, UnsafeMutableRawPointer?) -> Bool
        let ask = unsafeBitCast(ObjCRuntime.msgSend, to: Ask.self)
        let replacement = NSObject(objCReturnValue: text.objCReturnValue())
        guard ask(objcObject, ObjCRuntime.selector("shouldChangeTextInRange:replacementString:"), range, replacement.objcObject) else { return }
        if isString { storage.replaceCharacters(in: range, with: text) } else { storage.replaceCharacters(in: range, withAttributedString: value) }
        moveInsertionPoint(to: Int(range.location) + text.utf16.count)
        Send.void(objcObject, "didChangeText")
    }

    @ObjCMethod("replaceCharactersInRange:withString:")
    func replaceCharacters(in range: NSRange, with text: String?) {
        storage?.replaceCharacters(in: range, with: text ?? "")
        textChanged()
    }

    @ObjCMethod("didChangeText")
    func didChangeText() {
        let notification = NSNotification.make(name: Constants.NSTextDidChangeNotification, object: self)
        if Send.responds(delegateObject, "textDidChange:") { Send.void(delegateObject, "textDidChange:", notification.objcObject) }
        NSNotificationCenter.defaultCenter().post(notification)
    }
    @ObjCMethod("shouldChangeTextInRange:replacementString:")
    func shouldChangeText(in range: NSRange, replacementString: String?) -> Bool {
        guard editable else { return false }
        guard Send.responds(delegateObject, "textView:shouldChangeTextInRange:replacementString:") else { return true }
        typealias Ask = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer, UnsafeMutableRawPointer, NSRange, UnsafeMutableRawPointer?) -> Bool
        let replacement = replacementString.map { NSObject(objCReturnValue: $0.objCReturnValue()).objcObject }
        return unsafeBitCast(ObjCRuntime.msgSend, to: Ask.self)(delegateObject, ObjCRuntime.selector("textView:shouldChangeTextInRange:replacementString:"),
                                                                objcObject, range, replacement)
    }
    @ObjCMethod("selectedRange") func viewSelectedRange() -> NSRange { selectedRange }
    @ObjCMethod("setSelectedRange:")
    func setSelectedRange(_ range: NSRange) {
        let length = storage?.length() ?? 0
        let location = min(range.location, length)
        selectedRange = NSRange(location: location, length: min(range.length, length - location))
        selectionAnchor = Int(selectedRange.location)
        selectionChanged()
    }
    @ObjCMethod("setSelectedRange:affinity:stillSelecting:")
    func setSelectedRange(_ range: NSRange, affinity: UInt, stillSelecting: Bool) { setSelectedRange(range) }
    @ObjCMethod("selectedRanges")
    func selectedRanges() -> NSObject {
        typealias Make = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer, NSRange) -> UnsafeMutableRawPointer?
        let value = unsafeBitCast(ObjCRuntime.msgSend, to: Make.self)(Classes.named("NSValue")?.pointer, ObjCRuntime.selector("valueWithRange:"), selectedRange)
        let array = NSMutableArray.empty()
        Send.void(array.objcObject, "addObject:", value)
        return array
    }
    @ObjCMethod("setSelectedRanges:")
    func setSelectedRanges(_ ranges: NSObject?) {
        guard let first = ranges.flatMap({ Send.object($0.objcObject, "firstObject") }) else { return }
        typealias Read = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer) -> NSRange
        setSelectedRange(unsafeBitCast(ObjCRuntime.msgSend, to: Read.self)(first, ObjCRuntime.selector("rangeValue")))
    }
    @ObjCMethod("scrollRangeToVisible:")
    func scrollRangeToVisible(_ range: NSRange) {
        _ = scrollRectToVisible(rect(forCharacters: Int(range.location)..<Int(range.location + range.length)))
    }
    @ObjCMethod("scrollToEndOfDocument:") func scrollToEndOfDocument(_ sender: NSObject?) { _ = scrollRectToVisible(CGRect(x: 0, y: max(0, bounds.height - 1), width: 1, height: 1)) }
    @ObjCMethod("scrollToBeginningOfDocument:") func scrollToBeginningOfDocument(_ sender: NSObject?) { _ = scrollRectToVisible(CGRect(x: 0, y: 0, width: 1, height: 1)) }
    @ObjCMethod("selectAll:")
    func selectAll(_ sender: NSObject?) { setSelectedRange(NSRange(location: 0, length: storage?.length() ?? 0)) }

    private var selectedText: String {
        let utf16 = Array(string.utf16)
        let start = Int(selectedRange.location)
        return String(decoding: utf16[start..<start + Int(selectedRange.length)], as: UTF16.self)
    }

    @ObjCMethod("copy:")
    func copyText(_ sender: NSObject?) {
        guard selectedRange.length > 0 else { return }
        _ = NSPasteboard.generalPasteboard().setString(selectedText, forType: Constants.NSPasteboardTypeString)
    }
    @ObjCMethod("cut:")
    func cut(_ sender: NSObject?) {
        copyText(sender)
        deleteText(sender)
    }
    @ObjCMethod("paste:")
    func paste(_ sender: NSObject?) {
        guard let text = NSPasteboard.generalPasteboard().string(forType: Constants.NSPasteboardTypeString) else { return }
        typeText(text)
    }
    @ObjCMethod("delete:")
    func deleteText(_ sender: NSObject?) { if selectedRange.length > 0 { typeText("") } }

    private func typeText(_ text: String) {
        Send.void(objcObject, "insertText:", NSObject(objCReturnValue: text.objCReturnValue()).objcObject)
    }

    private func deleteTo(_ other: Int) {
        guard selectedRange.length == 0 else { return deleteText(nil) }
        let caret = Int(selectedRange.location)
        guard other != caret else { return }
        selectedRange = NSRange(location: UInt(min(caret, other)), length: UInt(abs(other - caret)))
        typeText("")
    }

    // MARK: Moving the insertion point

    /// Sends the selection's changes to the delegate and observers.
    private func selectionChanged() {
        setNeedsDisplay(true)
        let notification = NSNotification.make(name: "NSTextViewDidChangeSelectionNotification", object: self)
        if Send.responds(delegateObject, "textViewDidChangeSelection:") { Send.void(delegateObject, "textViewDidChangeSelection:", notification.objcObject) }
        NSNotificationCenter.defaultCenter().post(notification)
    }

    private func moveInsertionPoint(to index: Int, extending: Bool = false) {
        let length = Int(storage?.length() ?? 0)
        let target = max(0, min(length, index))
        if !extending { selectionAnchor = target }
        selectedRange = NSRange(location: UInt(min(selectionAnchor, target)), length: UInt(abs(selectionAnchor - target)))
        selectionChanged()
        scrollRangeToVisible(NSRange(location: UInt(target), length: 0))
    }

    private var movingEnd: Int {
        let start = Int(selectedRange.location)
        return selectionAnchor == start ? start + Int(selectedRange.length) : start
    }

    private func vertical(_ lines: Int) -> Int {
        let all = fragments
        guard let current = fragment(containing: movingEnd), let index = all.firstIndex(where: { $0.range == current.range }) else { return movingEnd }
        let target = index + lines
        if target < 0 { return 0 }
        if target >= all.count { return Int(storage?.length() ?? 0) }
        return characterIndex(at: CGPoint(x: x(of: movingEnd, in: current), y: all[target].rect.midY))
    }

    private func word(from index: Int, forward: Bool) -> Int {
        let units = Array(string.utf16)
        func isWord(_ unit: UInt16) -> Bool { Unicode.Scalar(unit).map { $0.properties.isAlphabetic || $0.properties.numericType != nil } ?? false }
        var at = index
        if forward {
            while at < units.count, !isWord(units[at]) { at += 1 }
            while at < units.count, isWord(units[at]) { at += 1 }
        } else {
            while at > 0, !isWord(units[at - 1]) { at -= 1 }
            while at > 0, isWord(units[at - 1]) { at -= 1 }
        }
        return at
    }

    private var lineStart: Int { fragment(containing: movingEnd)?.range.lowerBound ?? 0 }
    private var lineEnd: Int {
        guard let line = fragment(containing: movingEnd) else { return 0 }
        return line.range.lowerBound + line.line.text.utf16.count
    }

    private func moved(left: Bool) -> Int {
        guard selectedRange.length == 0 else { return Int(selectedRange.location) + (left ? 0 : Int(selectedRange.length)) }
        let units = Array(string.utf16)
        var at = movingEnd + (left ? -1 : 1)
        // Not between the halves of a surrogate pair.
        if at > 0, at < units.count, UTF16.isTrailSurrogate(units[at]) { at += left ? -1 : 1 }
        return at
    }

    private func steppedOneCharacter(left: Bool) -> Int {
        let units = Array(string.utf16)
        var at = movingEnd + (left ? -1 : 1)
        if at > 0, at < units.count, UTF16.isTrailSurrogate(units[at]) { at += left ? -1 : 1 }
        return at
    }

    @ObjCMethod("moveLeft:") func moveLeft(_ s: NSObject?) { moveInsertionPoint(to: moved(left: true)) }
    @ObjCMethod("moveRight:") func moveRight(_ s: NSObject?) { moveInsertionPoint(to: moved(left: false)) }
    @ObjCMethod("moveBackward:") func moveBackward(_ s: NSObject?) { moveLeft(s) }
    @ObjCMethod("moveForward:") func moveForward(_ s: NSObject?) { moveRight(s) }
    @ObjCMethod("moveUp:") func moveUp(_ s: NSObject?) { moveInsertionPoint(to: vertical(-1)) }
    @ObjCMethod("moveDown:") func moveDown(_ s: NSObject?) { moveInsertionPoint(to: vertical(1)) }
    @ObjCMethod("pageUp:") func pageUp(_ s: NSObject?) { moveInsertionPoint(to: vertical(-30)) }
    @ObjCMethod("pageDown:") func pageDown(_ s: NSObject?) { moveInsertionPoint(to: vertical(30)) }
    @ObjCMethod("moveWordLeft:") func moveWordLeft(_ s: NSObject?) { moveInsertionPoint(to: word(from: movingEnd, forward: false)) }
    @ObjCMethod("moveWordRight:") func moveWordRight(_ s: NSObject?) { moveInsertionPoint(to: word(from: movingEnd, forward: true)) }
    @ObjCMethod("moveToLeftEndOfLine:") func moveToLeftEndOfLine(_ s: NSObject?) { moveInsertionPoint(to: lineStart) }
    @ObjCMethod("moveToRightEndOfLine:") func moveToRightEndOfLine(_ s: NSObject?) { moveInsertionPoint(to: lineEnd) }
    @ObjCMethod("moveToBeginningOfLine:") func moveToBeginningOfLine(_ s: NSObject?) { moveInsertionPoint(to: lineStart) }
    @ObjCMethod("moveToEndOfLine:") func moveToEndOfLine(_ s: NSObject?) { moveInsertionPoint(to: lineEnd) }
    @ObjCMethod("moveToBeginningOfDocument:") func moveToBeginningOfDocument(_ s: NSObject?) { moveInsertionPoint(to: 0) }
    @ObjCMethod("moveToEndOfDocument:") func moveToEndOfDocument(_ s: NSObject?) { moveInsertionPoint(to: Int.max) }
    @ObjCMethod("moveLeftAndModifySelection:") func moveLeftExtending(_ s: NSObject?) { moveInsertionPoint(to: steppedOneCharacter(left: true), extending: true) }
    @ObjCMethod("moveRightAndModifySelection:") func moveRightExtending(_ s: NSObject?) { moveInsertionPoint(to: steppedOneCharacter(left: false), extending: true) }
    @ObjCMethod("moveUpAndModifySelection:") func moveUpExtending(_ s: NSObject?) { moveInsertionPoint(to: vertical(-1), extending: true) }
    @ObjCMethod("moveDownAndModifySelection:") func moveDownExtending(_ s: NSObject?) { moveInsertionPoint(to: vertical(1), extending: true) }
    @ObjCMethod("moveWordLeftAndModifySelection:") func moveWordLeftExtending(_ s: NSObject?) { moveInsertionPoint(to: word(from: movingEnd, forward: false), extending: true) }
    @ObjCMethod("moveWordRightAndModifySelection:") func moveWordRightExtending(_ s: NSObject?) { moveInsertionPoint(to: word(from: movingEnd, forward: true), extending: true) }
    @ObjCMethod("moveToLeftEndOfLineAndModifySelection:") func moveToLeftEndExtending(_ s: NSObject?) { moveInsertionPoint(to: lineStart, extending: true) }
    @ObjCMethod("moveToRightEndOfLineAndModifySelection:") func moveToRightEndExtending(_ s: NSObject?) { moveInsertionPoint(to: lineEnd, extending: true) }
    @ObjCMethod("moveToBeginningOfDocumentAndModifySelection:") func moveToDocumentStartExtending(_ s: NSObject?) { moveInsertionPoint(to: 0, extending: true) }
    @ObjCMethod("moveToEndOfDocumentAndModifySelection:") func moveToDocumentEndExtending(_ s: NSObject?) { moveInsertionPoint(to: Int.max, extending: true) }

    @ObjCMethod("deleteBackward:") func deleteBackward(_ s: NSObject?) { deleteTo(steppedOneCharacter(left: true)) }
    @ObjCMethod("deleteForward:") func deleteForward(_ s: NSObject?) { deleteTo(steppedOneCharacter(left: false)) }
    @ObjCMethod("deleteWordBackward:") func deleteWordBackward(_ s: NSObject?) { deleteTo(word(from: movingEnd, forward: false)) }
    @ObjCMethod("deleteWordForward:") func deleteWordForward(_ s: NSObject?) { deleteTo(word(from: movingEnd, forward: true)) }
    @ObjCMethod("deleteToBeginningOfLine:") func deleteToBeginningOfLine(_ s: NSObject?) { deleteTo(lineStart) }
    @ObjCMethod("deleteToEndOfLine:") func deleteToEndOfLine(_ s: NSObject?) { deleteTo(lineEnd) }
    @ObjCMethod("insertNewline:") func insertNewline(_ s: NSObject?) { typeText("\n") }
    @ObjCMethod("insertTab:") func insertTab(_ s: NSObject?) { typeText("\t") }
    @ObjCMethod("insertBacktab:") func insertBacktab(_ s: NSObject?) {}
    @ObjCMethod("insertNewlineIgnoringFieldEditor:") func insertNewlineIgnoringFieldEditor(_ s: NSObject?) { typeText("\n") }
    @ObjCMethod("insertTabIgnoringFieldEditor:") func insertTabIgnoringFieldEditor(_ s: NSObject?) { typeText("\t") }
    @ObjCMethod("doCommandBySelector:")
    func doCommand(by selector: ObjCSelector?) {
        guard let selector else { return }
        typealias Run = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, UnsafeMutableRawPointer?) -> Void
        unsafeBitCast(ObjCRuntime.msgSend, to: Run.self)(objcObject, selector.pointer, objcObject)
    }
    @ObjCMethod("hasMarkedText") func hasMarkedText() -> Bool { false }
    @ObjCMethod("markedRange") func markedRange() -> NSRange { NSRange(location: UInt(Int.max), length: 0) }

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
    @ObjCMethod("setAutomaticQuoteSubstitutionEnabled:") func setAutomaticQuoteSubstitutionEnabled(_ value: Bool) { switches["AutomaticQuoteSubstitution"] = value }
    @ObjCMethod("isAutomaticQuoteSubstitutionEnabled") func isAutomaticQuoteSubstitutionEnabled() -> Bool { switches["AutomaticQuoteSubstitution"] ?? false }
    @ObjCMethod("setAutomaticDashSubstitutionEnabled:") func setAutomaticDashSubstitutionEnabled(_ value: Bool) { switches["AutomaticDashSubstitution"] = value }
    @ObjCMethod("isAutomaticDashSubstitutionEnabled") func isAutomaticDashSubstitutionEnabled() -> Bool { switches["AutomaticDashSubstitution"] ?? false }
    @ObjCMethod("setAutomaticTextReplacementEnabled:") func setAutomaticTextReplacementEnabled(_ value: Bool) { switches["AutomaticTextReplacement"] = value }
    @ObjCMethod("isAutomaticTextReplacementEnabled") func isAutomaticTextReplacementEnabled() -> Bool { switches["AutomaticTextReplacement"] ?? false }
    @ObjCMethod("setAutomaticSpellingCorrectionEnabled:") func setAutomaticSpellingCorrectionEnabled(_ value: Bool) { switches["AutomaticSpellingCorrection"] = value }
    @ObjCMethod("isAutomaticSpellingCorrectionEnabled") func isAutomaticSpellingCorrectionEnabled() -> Bool { switches["AutomaticSpellingCorrection"] ?? false }
    @ObjCMethod("setContinuousSpellCheckingEnabled:") func setContinuousSpellCheckingEnabled(_ value: Bool) { switches["ContinuousSpellChecking"] = value }
    @ObjCMethod("isContinuousSpellCheckingEnabled") func isContinuousSpellCheckingEnabled() -> Bool { switches["ContinuousSpellChecking"] ?? false }
    @ObjCMethod("setGrammarCheckingEnabled:") func setGrammarCheckingEnabled(_ value: Bool) { switches["GrammarChecking"] = value }
    @ObjCMethod("isGrammarCheckingEnabled") func isGrammarCheckingEnabled() -> Bool { switches["GrammarChecking"] ?? false }
    @ObjCMethod("setAutomaticLinkDetectionEnabled:") func setAutomaticLinkDetectionEnabled(_ value: Bool) { switches["AutomaticLinkDetection"] = value }
    @ObjCMethod("isAutomaticLinkDetectionEnabled") func isAutomaticLinkDetectionEnabled() -> Bool { switches["AutomaticLinkDetection"] ?? false }
    @ObjCMethod("setAutomaticDataDetectionEnabled:") func setAutomaticDataDetectionEnabled(_ value: Bool) { switches["AutomaticDataDetection"] = value }
    @ObjCMethod("isAutomaticDataDetectionEnabled") func isAutomaticDataDetectionEnabled() -> Bool { switches["AutomaticDataDetection"] ?? false }
    @ObjCMethod("enabledTextCheckingTypes") func enabledTextCheckingTypes() -> UInt64 { checkingTypes }
    @ObjCMethod("setEnabledTextCheckingTypes:") func setEnabledTextCheckingTypes(_ types: UInt64) { checkingTypes = types }
    /// A text view's many options without an effect here are accepted when
    /// set by key (nibs and bindings do) and read as nil.
    @ObjCMethod("setValue:forUndefinedKey:") func setValue(_ value: NSObject?, forUndefinedKey key: String) {
        appKitWarning("NSTextView: ignoring \(key)")
    }
    @ObjCMethod("valueForUndefinedKey:") func value(forUndefinedKey key: String) -> NSObject? { nil }
    @ObjCMethod("setSmartInsertDeleteEnabled:") func setSmartInsertDeleteEnabled(_ value: Bool) { switches["SmartInsertDelete"] = value }
    @ObjCMethod("isSmartInsertDeleteEnabled") func isSmartInsertDeleteEnabled() -> Bool { switches["SmartInsertDelete"] ?? true }
    @ObjCMethod("linkTextAttributes") func linkTextAttributes() -> NSObject? { linkTextAttributesObject }
    @ObjCMethod("setLinkTextAttributes:") func setLinkTextAttributes(_ value: NSObject?) { linkTextAttributesObject = value }
    @ObjCMethod("selectedTextAttributes") func selectedTextAttributes() -> NSObject? { selectedTextAttributesObject }
    @ObjCMethod("setSelectedTextAttributes:") func setSelectedTextAttributes(_ value: NSObject?) { selectedTextAttributesObject = value; setNeedsDisplay(true) }
    @ObjCMethod("setTypingAttributes:") func setTypingAttributes(_ value: NSObject?) { typingAttributesObject = value }
    @ObjCMethod("typingAttributes") func typingAttributes() -> NSObject { typingAttributesObject ?? NSMutableDictionary.empty() }
    @ObjCMethod("defaultParagraphStyle") func defaultParagraphStyle() -> NSObject? { defaultParagraphStyleObject }
    @ObjCMethod("setDefaultParagraphStyle:") func setDefaultParagraphStyle(_ value: NSObject?) { defaultParagraphStyleObject = value }
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
        cachedFragments = nil
        if verticallyResizable {
            let height = textSize(width: frame.width).height + 2 * textContainerInset.height
            let clip = superview?.as(NSClipView.self)?.bounds.height ?? 0
            let target = min(maxSize.height, max(minSize.height, max(height, clip)))
            if abs(target - frame.height) > 0.5 { Send.void(objcObject, "setFrameSize:", size: CGSize(width: frame.width, height: target)) }
        }
        setNeedsDisplay(true)
    }

    @ObjCMethod("viewDidMoveToSuperview") override func viewDidMoveToSuperview() { textChanged() }

    @ObjCMethod("setFrameSize:")
    override func setFrameSize(_ size: CGSize) {
        if abs(size.width - frame.width) > 0.5 { cachedFragments = nil }
        super.setFrameSize(size)
    }

    // MARK: Layout

    /// The text's lines, each with the characters it holds.
    var fragments: [Fragment] {
        if let cachedFragments { return cachedFragments }
        let padding = container?.lineFragmentPadding ?? 5
        let width = max(1, frame.width - 2 * (textContainerInset.width + padding))
        let (runs, style) = runs()
        let units = Array(string.utf16)
        let minimumHeight = Text.lineHeight(effectiveFont)
        var made: [Fragment] = []
        var position = 0
        var top = textContainerInset.height
        func add(_ line: Text.Line, upTo end: Int) {
            let height = max(line.height, minimumHeight)
            made.append(Fragment(range: position..<end, rect: CGRect(x: textContainerInset.width + padding, y: top, width: line.width, height: height), line: line))
            top += height + style.lineSpacing
            position = end
        }
        for line in Text.layout(runs, width: width, style: style) {
            var end = min(units.count, position + line.text.utf16.count)
            while end < units.count, units[end] == 32 { end += 1 }
            if end < units.count, units[end] == 10 { end += 1 }
            add(line, upTo: end)
        }
        // After a last newline there is one more, empty line, for the caret.
        if units.last == 10 { add(Text.Line(), upTo: units.count) }
        cachedFragments = made
        return made
    }

    func fragment(containing index: Int) -> Fragment? {
        fragments.last { $0.range.lowerBound <= index } ?? fragments.first
    }

    /// The x of the place before a character in its line.
    func x(of index: Int, in fragment: Fragment) -> CGFloat {
        var remaining = index - fragment.range.lowerBound
        var x = fragment.rect.minX
        for piece in fragment.line.pieces {
            let units = Array(piece.run.text.utf16)
            if remaining < units.count {
                return x + Text.width(String(decoding: units.prefix(max(0, remaining)), as: UTF16.self), font: piece.run.font)
            }
            remaining -= units.count
            x += piece.width
        }
        return x
    }

    /// The character boundary nearest a point in the view.
    func characterIndex(at point: CGPoint) -> Int {
        let all = fragments
        guard let line = all.first(where: { point.y < $0.rect.maxY }) ?? all.last else { return 0 }
        var low = line.range.lowerBound
        var high = low + line.line.text.utf16.count
        let end = high
        while low < high {
            let middle = (low + high) / 2
            if x(of: middle, in: line) < point.x { low = middle + 1 } else { high = middle }
        }
        if low > line.range.lowerBound, low <= end, point.x - x(of: low - 1, in: line) < x(of: low, in: line) - point.x { return low - 1 }
        return low
    }

    /// The rectangle around characters, in the view, or an insertion point's.
    func rect(forCharacters range: Range<Int>) -> CGRect {
        let touched = fragments.filter { $0.range.overlaps(range) || $0.range.lowerBound == range.lowerBound }
        guard let first = touched.first ?? fragment(containing: range.lowerBound), let last = touched.last ?? fragment(containing: range.lowerBound) else {
            return CGRect(x: textContainerInset.width, y: textContainerInset.height, width: 1, height: Text.lineHeight(effectiveFont))
        }
        if first.range == last.range {
            let start = x(of: range.lowerBound, in: first)
            return CGRect(x: start, y: first.rect.minY, width: max(1, x(of: range.upperBound, in: first) - start), height: first.rect.height)
        }
        let left = touched.map(\.rect.minX).min() ?? first.rect.minX
        let right = touched.map(\.rect.maxX).max() ?? first.rect.maxX
        return CGRect(x: left, y: first.rect.minY, width: right - left, height: last.rect.maxY - first.rect.minY)
    }

    private var selectionColor: NSColor {
        let attributes = selectedTextAttributesObject?.as(NSDictionary.self)
        return attributes?.object(forKey: "NSBackgroundColor")?.as(NSColor.self) ?? NSColor.selectedTextBackgroundColor()
    }

    @ObjCMethod("drawRect:")
    override func draw(_ rect: CGRect) {
        guard let context = NSGraphicsContext.currentCG else { return }
        if drawsBackground {
            CG.saveGState(context)
            CG.setFill(context, backgroundColor)
            CG.fillRect(context, bounds)
            CG.restoreGState(context)
        }
        let selection = Int(selectedRange.location)..<Int(selectedRange.location + selectedRange.length)
        CG.saveGState(context)
        if !selection.isEmpty {
            CG.setFill(context, selectionColor)
            for line in fragments where line.range.overlaps(selection) {
                let start = x(of: max(selection.lowerBound, line.range.lowerBound), in: line)
                let end = selection.upperBound >= line.range.upperBound ? line.rect.maxX + 4 : x(of: selection.upperBound, in: line)
                CG.fillRect(context, CGRect(x: start, y: line.rect.minY, width: max(1, end - start), height: line.rect.height))
            }
        } else if editing, let line = fragment(containing: selection.lowerBound) {
            CG.setFill(context, insertionPointColor ?? textColor ?? NSColor.textColor())
            CG.fillRect(context, CGRect(x: x(of: selection.lowerBound, in: line), y: line.rect.minY, width: 1, height: line.rect.height))
        }
        CG.restoreGState(context)
        let padding = container?.lineFragmentPadding ?? 5
        let (runs, style) = runs()
        let area = CGRect(x: textContainerInset.width + padding, y: textContainerInset.height,
                          width: max(1, bounds.width - 2 * (textContainerInset.width + padding)), height: bounds.height)
        Text.draw(runs, in: area, style: style)
    }

    // MARK: Mouse

    private func point(of event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    @ObjCMethod("mouseDown:")
    override func mouseDown(_ eventObject: NSObject?) {
        guard selectable || editable, let event = eventObject?.as(NSEvent.self) else { return }
        if let window = Send.object(objcObject, "window") { _ = Send.bool(window, "makeFirstResponder:", objcObject) }
        let index = characterIndex(at: point(of: event))
        switch event.clickCount {
        case 2:
            let start = word(from: min(index + 1, Int(storage?.length() ?? 0)), forward: false)
            setSelectedRange(NSRange(location: UInt(start), length: UInt(max(start, word(from: start, forward: true)) - start)))
        case 3...:
            if let line = fragment(containing: index) { setSelectedRange(NSRange(location: UInt(line.range.lowerBound), length: UInt(line.range.count))) }
        default:
            moveInsertionPoint(to: index)
        }
    }

    @ObjCMethod("mouseDragged:")
    override func mouseDragged(_ eventObject: NSObject?) {
        guard selectable || editable, let event = eventObject?.as(NSEvent.self) else { return }
        moveInsertionPoint(to: characterIndex(at: point(of: event)), extending: true)
    }

    @ObjCMethod("becomeFirstResponder")
    override func becomeFirstResponder() -> Bool {
        editing = editable
        setNeedsDisplay(true)
        return true
    }

    @ObjCMethod("resignFirstResponder")
    override func resignFirstResponder() -> Bool {
        editing = false
        return true
    }

    @ObjCMethod("keyDown:")
    override func keyDown(_ eventObject: NSObject?) {
        guard editable || selectable, let event = eventObject?.as(NSEvent.self) else { return super.keyDown(eventObject) }
        let flags = event.modifierFlags
        let shift = flags & ModifierFlags.shift != 0, command = flags & ModifierFlags.command != 0, option = flags & ModifierFlags.option != 0
        let typed = event.characters
        let suffix = shift ? "AndModifySelection:" : ":"
        var action: String?
        switch typed.unicodeScalars.first?.value {
        case 0xF702: action = (command ? "moveToLeftEndOfLine" : option ? "moveWordLeft" : "moveLeft") + suffix
        case 0xF703: action = (command ? "moveToRightEndOfLine" : option ? "moveWordRight" : "moveRight") + suffix
        case 0xF700: action = (command ? "moveToBeginningOfDocument" : "moveUp") + suffix
        case 0xF701: action = (command ? "moveToEndOfDocument" : "moveDown") + suffix
        case 0xF729: action = "moveToLeftEndOfLine" + suffix
        case 0xF72B: action = "moveToRightEndOfLine" + suffix
        case 0xF72C: action = "pageUp:"
        case 0xF72D: action = "pageDown:"
        case 0xF728: action = option ? "deleteWordForward:" : "deleteForward:"
        case 0x7f, 0x8: action = command ? "deleteToBeginningOfLine:" : option ? "deleteWordBackward:" : "deleteBackward:"
        case 0xD, 0x3: action = "insertNewline:"
        case 0x9: action = shift ? "insertBacktab:" : "insertTab:"
        case 0x19: action = "insertBacktab:"
        default: break
        }
        if let action {
            if Send.responds(objcObject, action) { Send.void(objcObject, action, objcObject) }
            return
        }
        guard editing, !command, !typed.isEmpty,
              typed.unicodeScalars.allSatisfy({ $0.value >= 0x20 && !(0xF700...0xF8FF).contains($0.value) }) else { return super.keyDown(eventObject) }
        Send.void(objcObject, "insertText:", NSObject(objCReturnValue: typed.objCReturnValue()).objcObject)
    }
}

@ObjCCategory("TextEditing")
extension NSAttributedString {
    /// Sets or clears NSBoldFontMask (2), NSItalicFontMask (1), NSUnboldFontMask (4)
    /// and NSUnitalicFontMask (0x1000000) on the font of each run in a range.
    @ObjCMethod("applyFontTraits:range:")
    func applyFontTraits(_ traits: UInt, range: NSRange) {
        typealias Read = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, UnsafeMutableRawPointer?, UInt, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
        typealias Write = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, NSRange) -> Void
        let read = unsafeBitCast(ObjCRuntime.msgSend, to: Read.self), write = unsafeBitCast(ObjCRuntime.msgSend, to: Write.self)
        let key = NSObject(objCReturnValue: "NSFont".objCReturnValue()).objcObject
        var index = range.location
        let end = range.location + range.length
        while index < end {
            var run = NSRange(location: index, length: 1)
            let value = read(objcObject, ObjCRuntime.selector("attribute:atIndex:effectiveRange:"), key, index, &run)
            let next = min(end, run.location + max(run.length, 1))
            if let value, let font = NSObject(value).as(NSFont.self) {
                let bold: Bool? = traits & 2 != 0 ? true : traits & 4 != 0 ? false : nil
                let italic: Bool? = traits & 1 != 0 ? true : traits & 0x1000000 != 0 ? false : nil
                write(objcObject, ObjCRuntime.selector("addAttribute:value:range:"), key, font.with(bold: bold, italic: italic).objcObject,
                      NSRange(location: index, length: next - index))
            }
            index = next
        }
    }
}

import CPerryGeometry
import PerryObjCInterop

// NSDatePicker and NSDatePickerCell, NSFormCell, NSColorList and
// NSColorPanel, and NSSpellChecker: classes Interface Builder's tools load
// and set up. They keep their values and settings; none of them is drawn
// as AppKit draws it yet.

@ObjCClass("NSDatePickerCell")
open class NSDatePickerCell: NSActionCell {
    var minDate: NSObject?
    var maxDate: NSObject?
    /// NSDatePickerStyle: text field and stepper 0, clock and calendar 1, text field 2.
    var pickerStyle: UInt = 0
    var elements: UInt = 0xe
    var mode: UInt = 0
    var timeInterval: Double = 0
    var calendar: NSObject?
    var locale: NSObject?
    var timeZone: NSObject?
    var textColor: NSColor?
    var backgroundColor: NSColor?
    var drawsBackground = false

    @ObjCMethod("dateValue") func dateValue() -> NSObject? { objectValue }
    @ObjCMethod("setDateValue:") func setDateValue(_ value: NSObject?) { objectValue = value }
    @ObjCMethod("minDate") func cellMinDate() -> NSObject? { minDate }
    @ObjCMethod("setMinDate:") func setMinDate(_ value: NSObject?) { minDate = value }
    @ObjCMethod("maxDate") func cellMaxDate() -> NSObject? { maxDate }
    @ObjCMethod("setMaxDate:") func setMaxDate(_ value: NSObject?) { maxDate = value }
    @ObjCMethod("datePickerStyle") func datePickerStyle() -> UInt { pickerStyle }
    @ObjCMethod("setDatePickerStyle:") func setDatePickerStyle(_ value: UInt) { pickerStyle = value }
    @ObjCMethod("datePickerElements") func datePickerElements() -> UInt { elements }
    @ObjCMethod("setDatePickerElements:") func setDatePickerElements(_ value: UInt) { elements = value }
    @ObjCMethod("datePickerMode") func datePickerMode() -> UInt { mode }
    @ObjCMethod("setDatePickerMode:") func setDatePickerMode(_ value: UInt) { mode = value }
    @ObjCMethod("timeInterval") func cellTimeInterval() -> Double { timeInterval }
    @ObjCMethod("setTimeInterval:") func setTimeInterval(_ value: Double) { timeInterval = value }
    @ObjCMethod("calendar") func cellCalendar() -> NSObject? { calendar }
    @ObjCMethod("setCalendar:") func setCalendar(_ value: NSObject?) { calendar = value }
    @ObjCMethod("locale") func cellLocale() -> NSObject? { locale }
    @ObjCMethod("setLocale:") func setLocale(_ value: NSObject?) { locale = value }
    @ObjCMethod("timeZone") func cellTimeZone() -> NSObject? { timeZone }
    @ObjCMethod("setTimeZone:") func setTimeZone(_ value: NSObject?) { timeZone = value }
    @ObjCMethod("textColor") func cellTextColor() -> NSColor? { textColor }
    @ObjCMethod("setTextColor:") func setTextColor(_ value: NSColor?) { textColor = value }
    @ObjCMethod("backgroundColor") func cellBackgroundColor() -> NSColor? { backgroundColor }
    @ObjCMethod("setBackgroundColor:") func setBackgroundColor(_ value: NSColor?) { backgroundColor = value }
    @ObjCMethod("drawsBackground") func cellDrawsBackground() -> Bool { drawsBackground }
    @ObjCMethod("setDrawsBackground:") func setDrawsBackground(_ value: Bool) { drawsBackground = value }
}

/// NSDatePicker: its values are its cell's.
@ObjCClass("NSDatePicker")
open class NSDatePicker: NSControl {
    @ObjCClassMethod("cellClass") static func datePickerCellClass() -> UnsafeMutableRawPointer? { Classes.named("NSDatePickerCell")?.pointer }

    private var pickerCell: NSDatePickerCell? { cellObject?.as(NSDatePickerCell.self) }

    @ObjCMethod("dateValue") func dateValue() -> NSObject? { pickerCell?.objectValue }
    @ObjCMethod("setDateValue:") func setDateValue(_ value: NSObject?) { pickerCell?.objectValue = value; setNeedsDisplay(true) }
    @ObjCMethod("minDate") func pickerMinDate() -> NSObject? { pickerCell?.minDate }
    @ObjCMethod("setMinDate:") func setMinDate(_ value: NSObject?) { pickerCell?.minDate = value }
    @ObjCMethod("maxDate") func pickerMaxDate() -> NSObject? { pickerCell?.maxDate }
    @ObjCMethod("setMaxDate:") func setMaxDate(_ value: NSObject?) { pickerCell?.maxDate = value }
    @ObjCMethod("datePickerStyle") func datePickerStyle() -> UInt { pickerCell?.pickerStyle ?? 0 }
    @ObjCMethod("setDatePickerStyle:") func setDatePickerStyle(_ value: UInt) { pickerCell?.pickerStyle = value }
    @ObjCMethod("datePickerElements") func datePickerElements() -> UInt { pickerCell?.elements ?? 0 }
    @ObjCMethod("setDatePickerElements:") func setDatePickerElements(_ value: UInt) { pickerCell?.elements = value }
    @ObjCMethod("datePickerMode") func datePickerMode() -> UInt { pickerCell?.mode ?? 0 }
    @ObjCMethod("setDatePickerMode:") func setDatePickerMode(_ value: UInt) { pickerCell?.mode = value }
    @ObjCMethod("delegate") func pickerDelegate() -> NSObject? { nil }
    @ObjCMethod("setDelegate:") func setDelegate(_ value: NSObject?) {}
}

/// NSFormCell: a title beside an editable field, a cell of a form.
@ObjCClass("NSFormCell")
open class NSFormCell: NSActionCell {
    var titleWidth: CGFloat = -1
    var titleFont: NSFont?
    var titleAlignment = 2
    var placeholder: NSObject?

    /// The title, beside the cell's own value.
    @ObjCMethod("title") override func cellTitle() -> String { title }
    @ObjCMethod("setTitle:") override func setTitle(_ value: String?) { title = value ?? "" }
    @ObjCMethod("titleWidth") func cellTitleWidth() -> CGFloat { titleWidth >= 0 ? titleWidth : CGFloat(title.count) * 7 }
    @ObjCMethod("setTitleWidth:") func setTitleWidth(_ value: CGFloat) { titleWidth = value }
    @ObjCMethod("titleWidth:") func titleWidth(_ size: CGSize) -> CGFloat { cellTitleWidth() }
    @ObjCMethod("titleFont") func cellTitleFont() -> NSFont? { titleFont ?? font }
    @ObjCMethod("setTitleFont:") func setTitleFont(_ value: NSFont?) { titleFont = value }
    @ObjCMethod("titleAlignment") func cellTitleAlignment() -> Int { titleAlignment }
    @ObjCMethod("setTitleAlignment:") func setTitleAlignment(_ value: Int) { titleAlignment = value }
    @ObjCMethod("placeholderString") func placeholderString() -> NSObject? { placeholder }
    @ObjCMethod("setPlaceholderString:") func setPlaceholderString(_ value: NSObject?) { placeholder = value }
    @ObjCMethod("placeholderAttributedString") func placeholderAttributedString() -> NSObject? { placeholder }
    @ObjCMethod("setPlaceholderAttributedString:") func setPlaceholderAttributedString(_ value: NSObject?) { placeholder = value }
}

/// NSColorList: named colors, in order.
@ObjCClass("NSColorList")
open class NSColorList: NSObject {
    var name = ""
    var keys: [String] = []
    var colors: [String: NSColor] = [:]

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithName:")
    public required init(name: String?) {
        super.init()
        self.name = name ?? ""
    }

    @ObjCMethod("initWithName:fromFile:")
    public required init(name: String?, fromFile path: String?) {
        super.init()
        self.name = name ?? ""
    }

    @ObjCClassMethod("availableColorLists") static func availableColorLists() -> NSObject { NSMutableArray.of([]) }
    @ObjCClassMethod("colorListNamed:") static func colorList(named name: String?) -> NSObject? { nil }

    @ObjCMethod("name") func listName() -> String { name }
    @ObjCMethod("allKeys") func allKeys() -> NSObject { NSMutableArray.of(keys.map { NSObject(objCReturnValue: $0.objCReturnValue()) }) }
    @ObjCMethod("colorWithKey:") func color(withKey key: String?) -> NSColor? { key.flatMap { colors[$0] } }
    @ObjCMethod("setColor:forKey:")
    func setColor(_ color: NSColor?, forKey key: String?) {
        guard let key else { return }
        if !keys.contains(key) { keys.append(key) }
        colors[key] = color
    }
    @ObjCMethod("insertColor:key:atIndex:")
    func insertColor(_ color: NSColor?, key: String?, at index: Int) {
        guard let key else { return }
        keys.removeAll { $0 == key }
        keys.insert(key, at: min(max(index, 0), keys.count))
        colors[key] = color
    }
    @ObjCMethod("removeColorWithKey:") func removeColor(withKey key: String?) { keys.removeAll { $0 == key }; if let key { colors[key] = nil } }
    @ObjCMethod("isEditable") func isEditable() -> Bool { true }
    @ObjCMethod("writeToFile:") func write(toFile path: String?) -> Bool { false }
}

/// NSColorPanel: the shared color panel. It keeps a color and its
/// settings; it isn't shown.
@ObjCClass("NSColorPanel")
open class NSColorPanel: NSPanel {
    nonisolated(unsafe) private static var shared: NSColorPanel?

    var panelColor: NSColor = NSColor.whiteColor()
    var showsAlpha = false
    var continuous = true
    var mode = 0
    /// Not retained.
    var colorTarget: UnsafeMutableRawPointer?
    var colorAction: ObjCSelector?

    @ObjCClassMethod("sharedColorPanel")
    static func sharedColorPanel() -> NSColorPanel {
        if let shared { return shared }
        let panel = NSColorPanel(contentRect: CGRect(x: 0, y: 0, width: 220, height: 300), styleMask: 0xb, backing: 2, defer: true)
        shared = panel
        return panel
    }
    @ObjCClassMethod("sharedColorPanelExists") static func sharedColorPanelExists() -> Bool { shared != nil }
    @ObjCClassMethod("setPickerMask:") static func setPickerMask(_ mask: UInt) {}
    @ObjCClassMethod("setPickerMode:") static func setPickerMode(_ mode: Int) {}
    @ObjCClassMethod("dragColor:withEvent:fromView:") static func dragColor(_ color: NSColor?, with event: NSObject?, from view: NSView?) -> Bool { false }

    @ObjCMethod("color") func color() -> NSColor { panelColor }
    @ObjCMethod("setColor:")
    func setColor(_ value: NSColor?) {
        panelColor = value ?? panelColor
        if let colorAction, let colorTarget { Send.void(colorTarget, colorAction.name, objcObject) }
    }
    @ObjCMethod("alpha") func alpha() -> CGFloat { panelColor.alpha }
    @ObjCMethod("showsAlpha") func panelShowsAlpha() -> Bool { showsAlpha }
    @ObjCMethod("setShowsAlpha:") func setShowsAlpha(_ value: Bool) { showsAlpha = value }
    @ObjCMethod("isContinuous") func isContinuous() -> Bool { continuous }
    @ObjCMethod("setContinuous:") func setContinuous(_ value: Bool) { continuous = value }
    @ObjCMethod("mode") func panelMode() -> Int { mode }
    @ObjCMethod("setMode:") func setMode(_ value: Int) { mode = value }
    @ObjCMethod("setTarget:") func setTarget(_ value: NSObject?) { colorTarget = value?.objcObject }
    @ObjCMethod("setAction:") func setAction(_ value: ObjCSelector?) { colorAction = value }
    @ObjCMethod("setAccessoryView:") func setAccessoryView(_ value: NSView?) {}
    @ObjCMethod("attachColorList:") func attachColorList(_ list: NSObject?) {}
    @ObjCMethod("detachColorList:") func detachColorList(_ list: NSObject?) {}
}

/// NSSpellChecker: the shared spelling checker. It finds no misspellings
/// and offers no guesses.
@ObjCClass("NSSpellChecker")
open class NSSpellChecker: NSObject {
    nonisolated(unsafe) private static var shared: NSSpellChecker?
    var language = "en"

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCClassMethod("sharedSpellChecker")
    static func sharedSpellChecker() -> NSSpellChecker {
        if let shared { return shared }
        let checker = NSSpellChecker()
        shared = checker
        return checker
    }
    @ObjCClassMethod("sharedSpellCheckerExists") static func sharedSpellCheckerExists() -> Bool { shared != nil }
    @ObjCClassMethod("uniqueSpellDocumentTag") static func uniqueSpellDocumentTag() -> Int {
        tag += 1
        return tag
    }
    nonisolated(unsafe) private static var tag = 0

    @ObjCMethod("language") func checkerLanguage() -> String { language }
    @ObjCMethod("setLanguage:") func setLanguage(_ value: String?) -> Bool { language = value ?? language; return true }
    @ObjCMethod("availableLanguages") func availableLanguages() -> NSObject { NSMutableArray.of([NSObject(objCReturnValue: language.objCReturnValue())]) }
    @ObjCMethod("checkSpellingOfString:startingAt:")
    func checkSpelling(of string: String?, startingAt start: Int) -> NSRange { NSRange(location: UInt(Int.max), length: 0) }
    @ObjCMethod("checkSpellingOfString:startingAt:language:wrap:inSpellDocumentWithTag:wordCount:")
    func checkSpelling(of string: String?, startingAt start: Int, language: String?, wrap: Bool, inSpellDocumentWithTag tag: Int,
                       wordCount: UnsafeMutablePointer<Int>?) -> NSRange {
        wordCount?.pointee = string.map { $0.split(whereSeparator: \.isWhitespace).count } ?? 0
        return NSRange(location: UInt(Int.max), length: 0)
    }
    @ObjCMethod("guessesForWordRange:inString:language:inSpellDocumentWithTag:")
    func guesses(forWordRange range: NSRange, in string: String?, language: String?, inSpellDocumentWithTag tag: Int) -> NSObject {
        NSMutableArray.of([])
    }
    @ObjCMethod("closeSpellDocumentWithTag:") func closeSpellDocument(withTag tag: Int) {}
    @ObjCMethod("ignoreWord:inSpellDocumentWithTag:") func ignoreWord(_ word: String?, inSpellDocumentWithTag tag: Int) {}
    @ObjCMethod("setIgnoredWords:inSpellDocumentWithTag:") func setIgnoredWords(_ words: NSObject?, inSpellDocumentWithTag tag: Int) {}
    @ObjCMethod("spellingPanel") func spellingPanel() -> NSObject? { nil }
    @ObjCMethod("substitutionsPanel") func substitutionsPanel() -> NSObject? { nil }
}

import CPerryGeometry
import Glibc
import PerryObjCInterop

// NSControl and the controls apps build alerts and panels with: they keep
// their values and actions, and are views like any other, but draw
// nothing. NSAlert shows its message in an SDL message box (and on stderr)
// and answers with its first button; save and open panels answer Cancel.

@ObjCClass("NSControl")
open class NSControl: NSView {
    /// Not retained.
    var target: UnsafeMutableRawPointer?
    var action: ObjCSelector?
    var enabled = true
    var text = ""
    var doubleValue: Double = 0
    var font: NSObject?
    var alignment = 0
    var controlSize: UInt = 0
    var continuous = false

    @ObjCMethod("target") func controlTarget() -> NSObject? { target.map(NSObject.init) }
    @ObjCMethod("setTarget:") func setTarget(_ target: NSObject?) { self.target = target?.objcObject }
    @ObjCMethod("action") func controlAction() -> ObjCSelector? { action }
    @ObjCMethod("setAction:") func setAction(_ action: ObjCSelector?) { self.action = action }
    @ObjCMethod("isEnabled") func isEnabled() -> Bool { enabled }
    @ObjCMethod("setEnabled:") func setEnabled(_ enabled: Bool) { self.enabled = enabled }
    @ObjCMethod("stringValue") func controlStringValue() -> String { text }
    @ObjCMethod("setStringValue:") func setStringValue(_ value: String?) { text = value ?? "" }
    @ObjCMethod("attributedStringValue") func attributedStringValue() -> NSObject? { nil }
    @ObjCMethod("setAttributedStringValue:")
    func setAttributedStringValue(_ value: NSObject?) { text = Send.object(value?.objcObject, "string").map { String(objCArgument: $0) } ?? "" }
    @ObjCMethod("doubleValue") func controlDoubleValue() -> Double { doubleValue }
    @ObjCMethod("setDoubleValue:") func setDoubleValue(_ value: Double) { doubleValue = value }
    @ObjCMethod("intValue") func intValue() -> Int32 { Int32(doubleValue) }
    @ObjCMethod("setIntValue:") func setIntValue(_ value: Int32) { doubleValue = Double(value) }
    @ObjCMethod("integerValue") func integerValue() -> Int { Int(doubleValue) }
    @ObjCMethod("setIntegerValue:") func setIntegerValue(_ value: Int) { doubleValue = Double(value) }
    @ObjCMethod("floatValue") func floatValue() -> Float { Float(doubleValue) }
    @ObjCMethod("setFloatValue:") func setFloatValue(_ value: Float) { doubleValue = Double(value) }
    @ObjCMethod("font") func controlFont() -> NSObject? { font }
    @ObjCMethod("setFont:") func setFont(_ font: NSObject?) { self.font = font }
    @ObjCMethod("alignment") func controlAlignment() -> Int { alignment }
    @ObjCMethod("setAlignment:") func setAlignment(_ alignment: Int) { self.alignment = alignment }
    @ObjCMethod("controlSize") func controlControlSize() -> UInt { controlSize }
    @ObjCMethod("setControlSize:") func setControlSize(_ size: UInt) { controlSize = size }
    @ObjCMethod("isContinuous") func isContinuous() -> Bool { continuous }
    @ObjCMethod("setContinuous:") func setContinuous(_ value: Bool) { continuous = value }
    @ObjCMethod("cell") func cell() -> NSObject? { nil }
    @ObjCMethod("sizeToFit") func sizeToFit() {}
    @ObjCMethod("setLineBreakMode:") func setLineBreakMode(_ mode: UInt) {}
    @ObjCMethod("setUsesSingleLineMode:") func setUsesSingleLineMode(_ value: Bool) {}

    /// Sends the action to the target, or along the responder chain.
    @ObjCMethod("sendAction:to:")
    func sendAction(_ action: ObjCSelector?, to target: NSObject?) -> Bool {
        guard let action, let app = App.shared else { return false }
        return app.sendAction(action, to: target, from: self)
    }

    @ObjCMethod("performClick:")
    func performClick(_ sender: NSObject?) { _ = sendAction(action, to: target.map(NSObject.init)) }
}

@ObjCClass("NSButton")
open class NSButton: NSControl {
    var title = "Button"
    var alternateTitle = ""
    var state = 0
    var keyEquivalent = ""
    var keyEquivalentModifierMask: UInt = 0
    var image: NSObject?
    var buttonType: UInt = 0
    var bezelStyle: UInt = 1
    var bordered = true

    static func make(title: String?, image: NSObject?, target: NSObject?, action: ObjCSelector?) -> NSButton {
        let button = NSButton(frame: CGRect(x: 0, y: 0, width: 80, height: 32))
        button.title = title ?? ""
        button.image = image
        button.target = target?.objcObject
        button.action = action
        return button
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
        return button
    }
    @ObjCClassMethod("radioButtonWithTitle:target:action:")
    static func radioButton(title: String?, target: NSObject?, action: ObjCSelector?) -> NSButton {
        let button = make(title: title, image: nil, target: target, action: action)
        button.buttonType = 4
        return button
    }

    @ObjCMethod("title") func buttonTitle() -> String { title }
    @ObjCMethod("setTitle:") func setTitle(_ title: String?) { self.title = title ?? "" }
    @ObjCMethod("alternateTitle") func buttonAlternateTitle() -> String { alternateTitle }
    @ObjCMethod("setAlternateTitle:") func setAlternateTitle(_ title: String?) { alternateTitle = title ?? "" }
    @ObjCMethod("attributedTitle") func attributedTitle() -> NSObject? { nil }
    @ObjCMethod("setAttributedTitle:") func setAttributedTitle(_ title: NSObject?) {}
    @ObjCMethod("state") func buttonState() -> Int { state }
    @ObjCMethod("setState:") func setState(_ state: Int) { self.state = state }
    @ObjCMethod("keyEquivalent") func buttonKeyEquivalent() -> String { keyEquivalent }
    @ObjCMethod("setKeyEquivalent:") func setKeyEquivalent(_ key: String?) { keyEquivalent = key ?? "" }
    @ObjCMethod("keyEquivalentModifierMask") func buttonKeyEquivalentModifierMask() -> UInt { keyEquivalentModifierMask }
    @ObjCMethod("setKeyEquivalentModifierMask:") func setKeyEquivalentModifierMask(_ mask: UInt) { keyEquivalentModifierMask = mask }
    @ObjCMethod("image") func buttonImage() -> NSObject? { image }
    @ObjCMethod("setImage:") func setImage(_ image: NSObject?) { self.image = image }
    @ObjCMethod("setAlternateImage:") func setAlternateImage(_ image: NSObject?) {}
    @ObjCMethod("setImagePosition:") func setImagePosition(_ position: UInt) {}
    @ObjCMethod("setImageScaling:") func setImageScaling(_ scaling: UInt) {}
    @ObjCMethod("setButtonType:") func setButtonType(_ type: UInt) { buttonType = type }
    @ObjCMethod("bezelStyle") func buttonBezelStyle() -> UInt { bezelStyle }
    @ObjCMethod("setBezelStyle:") func setBezelStyle(_ style: UInt) { bezelStyle = style }
    @ObjCMethod("isBordered") func isBordered() -> Bool { bordered }
    @ObjCMethod("setBordered:") func setBordered(_ value: Bool) { bordered = value }
    @ObjCMethod("setBezelColor:") func setBezelColor(_ color: NSObject?) {}
    @ObjCMethod("setContentTintColor:") func setContentTintColor(_ color: NSObject?) {}
    @ObjCMethod("setAllowsMixedState:") func setAllowsMixedState(_ value: Bool) {}
    @ObjCMethod("setShowsBorderOnlyWhileMouseInside:") func setShowsBorderOnlyWhileMouseInside(_ value: Bool) {}
    @ObjCMethod("highlight:") func highlight(_ value: Bool) {}
}

@ObjCClass("NSTextField")
open class NSTextField: NSControl {
    var editable = true
    var selectable = true
    var placeholder: String?
    var textColor: NSObject?
    /// Not retained.
    var delegate: UnsafeMutableRawPointer?

    static func make(_ text: String?, editable: Bool) -> NSTextField {
        let field = NSTextField(frame: CGRect(x: 0, y: 0, width: 200, height: 22))
        field.text = text ?? ""
        field.editable = editable
        field.selectable = editable
        return field
    }

    @ObjCClassMethod("labelWithString:") static func label(string: String?) -> NSTextField { make(string, editable: false) }
    @ObjCClassMethod("wrappingLabelWithString:") static func wrappingLabel(string: String?) -> NSTextField { make(string, editable: false) }
    @ObjCClassMethod("labelWithAttributedString:")
    static func label(attributedString: NSObject?) -> NSTextField {
        make(Send.object(attributedString?.objcObject, "string").map { String(objCArgument: $0) }, editable: false)
    }
    @ObjCClassMethod("textFieldWithString:") static func textField(string: String?) -> NSTextField { make(string, editable: true) }

    @ObjCMethod("isEditable") func isEditable() -> Bool { editable }
    @ObjCMethod("setEditable:") func setEditable(_ value: Bool) { editable = value }
    @ObjCMethod("isSelectable") func isSelectable() -> Bool { selectable }
    @ObjCMethod("setSelectable:") func setSelectable(_ value: Bool) { selectable = value }
    @ObjCMethod("placeholderString") func placeholderString() -> String? { placeholder }
    @ObjCMethod("setPlaceholderString:") func setPlaceholderString(_ text: String?) { placeholder = text }
    @ObjCMethod("textColor") func fieldTextColor() -> NSObject? { textColor }
    @ObjCMethod("setTextColor:") func setTextColor(_ color: NSObject?) { textColor = color }
    @ObjCMethod("delegate") func fieldDelegate() -> NSObject? { delegate.map(NSObject.init) }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { self.delegate = delegate?.objcObject }
    @ObjCMethod("setBezeled:") func setBezeled(_ value: Bool) {}
    @ObjCMethod("setBordered:") func setBordered(_ value: Bool) {}
    @ObjCMethod("setDrawsBackground:") func setDrawsBackground(_ value: Bool) {}
    @ObjCMethod("setBackgroundColor:") func setBackgroundColor(_ color: NSObject?) {}
    @ObjCMethod("setMaximumNumberOfLines:") func setMaximumNumberOfLines(_ lines: Int) {}
    @ObjCMethod("setPreferredMaxLayoutWidth:") func setPreferredMaxLayoutWidth(_ width: CGFloat) {}
    @ObjCMethod("setAllowsEditingTextAttributes:") func setAllowsEditingTextAttributes(_ value: Bool) {}
    @ObjCMethod("setBezelStyle:") func setBezelStyle(_ style: UInt) {}
    @ObjCMethod("selectText:") func selectText(_ sender: NSObject?) {}
    @ObjCMethod("acceptsFirstResponder") override func acceptsFirstResponder() -> Bool { editable || selectable }
}

@ObjCClass("NSSecureTextField")
open class NSSecureTextField: NSTextField {}

@ObjCClass("NSImageView")
open class NSImageView: NSControl {
    var image: NSObject?

    @ObjCClassMethod("imageViewWithImage:")
    static func imageView(image: NSObject?) -> NSImageView {
        let size = image?.as(NSImage.self)?.size ?? CGSize(width: 32, height: 32)
        let view = NSImageView(frame: CGRect(origin: .zero, size: size))
        view.image = image
        return view
    }

    @ObjCMethod("image") func viewImage() -> NSObject? { image }
    @ObjCMethod("setImage:") func setImage(_ image: NSObject?) { self.image = image }
    @ObjCMethod("setImageScaling:") func setImageScaling(_ scaling: UInt) {}
    @ObjCMethod("setImageAlignment:") func setImageAlignment(_ alignment: UInt) {}
    @ObjCMethod("setImageFrameStyle:") func setImageFrameStyle(_ style: UInt) {}
    @ObjCMethod("setAnimates:") func setAnimates(_ value: Bool) {}
    @ObjCMethod("setEditable:") func setEditable(_ value: Bool) {}
    @ObjCMethod("setContentTintColor:") func setContentTintColor(_ color: NSObject?) {}
}

@ObjCClass("NSProgressIndicator")
open class NSProgressIndicator: NSView {
    var indeterminate = true
    var minValue: Double = 0
    var maxValue: Double = 100
    var value: Double = 0
    var style: UInt = 0

    @ObjCMethod("isIndeterminate") func isIndeterminate() -> Bool { indeterminate }
    @ObjCMethod("setIndeterminate:") func setIndeterminate(_ value: Bool) { indeterminate = value }
    @ObjCMethod("minValue") func progressMinValue() -> Double { minValue }
    @ObjCMethod("setMinValue:") func setMinValue(_ value: Double) { minValue = value }
    @ObjCMethod("maxValue") func progressMaxValue() -> Double { maxValue }
    @ObjCMethod("setMaxValue:") func setMaxValue(_ value: Double) { maxValue = value }
    @ObjCMethod("doubleValue") func doubleValue() -> Double { value }
    @ObjCMethod("setDoubleValue:") func setDoubleValue(_ value: Double) { self.value = value }
    @ObjCMethod("incrementBy:") func increment(by delta: Double) { value += delta }
    @ObjCMethod("style") func progressStyle() -> UInt { style }
    @ObjCMethod("setStyle:") func setStyle(_ style: UInt) { self.style = style }
    @ObjCMethod("setControlSize:") func setControlSize(_ size: UInt) {}
    @ObjCMethod("setUsesThreadedAnimation:") func setUsesThreadedAnimation(_ value: Bool) {}
    @ObjCMethod("setDisplayedWhenStopped:") func setDisplayedWhenStopped(_ value: Bool) {}
    @ObjCMethod("startAnimation:") func startAnimation(_ sender: NSObject?) {}
    @ObjCMethod("stopAnimation:") func stopAnimation(_ sender: NSObject?) {}
    @ObjCMethod("sizeToFit") func sizeToFit() {}
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

    /// Shows the message and answers with the first button.
    @ObjCMethod("runModal")
    func runModal() -> Int {
        let titles = buttons.map(\.title)
        appKitWarning("alert: \(messageText)\(informativeText.isEmpty ? "" : " — \(informativeText)")"
                      + (titles.isEmpty ? "" : " [\(titles.joined(separator: ", "))]"))
        if SDL.start() {
            // SDL_MESSAGEBOX_ERROR 0x10, WARNING 0x20, INFORMATION 0x40.
            let flags: UInt32 = style == 2 ? 0x10 : style == 1 ? 0x40 : 0x20
            _ = messageText.withCString { title in
                informativeText.withCString { SDL.showSimpleMessageBox(flags, title, $0, Windows.key?.sdlWindow) }
            }
        }
        return 1000
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

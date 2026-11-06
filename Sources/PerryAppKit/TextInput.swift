import CPerryGeometry
import PerryObjCInterop

// Key events as text and editing commands, as macOS's input manager makes
// them: printable characters go to the client's -insertText:(…), editing
// keys to -doCommandBySelector: with the selector the standard key
// bindings give them. NSTextInputContext does it for views that adopt
// NSTextInputClient; -interpretKeyEvents: for any responder.

enum KeyBindings {
    /// The command for a key, by virtual key code and modifiers, as
    /// StandardKeyBinding.dict binds it.
    static func command(keyCode: UInt16, flags: UInt) -> String? {
        let shift = flags & ModifierFlags.shift != 0
        let option = flags & ModifierFlags.option != 0
        let command = flags & ModifierFlags.command != 0
        let control = flags & ModifierFlags.control != 0
        func select(_ name: String) -> String { shift ? name + "AndModifySelection:" : name + ":" }
        switch keyCode {
        case 0x24, 0x4C: return option ? "insertNewlineIgnoringFieldEditor:" : "insertNewline:"
        case 0x30: return shift ? "insertBacktab:" : "insertTab:"
        case 0x33: return option ? "deleteWordBackward:" : command ? "deleteToBeginningOfLine:" : "deleteBackward:"
        case 0x75: return option ? "deleteWordForward:" : "deleteForward:"
        case 0x35: return "cancelOperation:"
        case 0x7B: return command ? select("moveToBeginningOfLine") : option ? select("moveWordLeft") : select("moveLeft")
        case 0x7C: return command ? select("moveToEndOfLine") : option ? select("moveWordRight") : select("moveRight")
        case 0x7E: return command ? select("moveToBeginningOfDocument") : option ? select("moveToBeginningOfParagraph") : select("moveUp")
        case 0x7D: return command ? select("moveToEndOfDocument") : option ? select("moveToEndOfParagraph") : select("moveDown")
        case 0x73: return shift ? "moveToBeginningOfDocumentAndModifySelection:" : "scrollToBeginningOfDocument:"
        case 0x77: return shift ? "moveToEndOfDocumentAndModifySelection:" : "scrollToEndOfDocument:"
        case 0x74: return shift ? "pageUpAndModifySelection:" : "scrollPageUp:"
        case 0x79: return shift ? "pageDownAndModifySelection:" : "scrollPageDown:"
        default:
            // Emacs bindings with control.
            guard control, !command else { return nil }
            switch keyCode {
            case 0x00: return select("moveToBeginningOfParagraph")
            case 0x0E: return select("moveToEndOfParagraph")
            case 0x03: return select("moveForward")
            case 0x0B: return select("moveBackward")
            case 0x2D: return select("moveDown")
            case 0x23: return select("moveUp")
            case 0x02: return "deleteForward:"
            case 0x04: return "deleteBackward:"
            case 0x28: return "deleteToEndOfParagraph:"
            case 0x10: return "yank:"
            case 0x11: return "transpose:"
            case 0x25: return "centerSelectionInVisibleArea:"
            default: return nil
            }
        }
    }

    /// The text a key types, if it types any: none with command or
    /// control held, or for function keys.
    static func text(_ event: NSEvent) -> String? {
        guard event.modifierFlags & (ModifierFlags.command | ModifierFlags.control) == 0 else { return nil }
        let text = event.characters
        guard !text.isEmpty, text.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F && !(0xF700...0xF8FF).contains($0.value) })
        else { return nil }
        return text
    }

    static func send(_ receiver: UnsafeMutableRawPointer, command: String) {
        typealias F = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, UnsafeRawPointer) -> Void
        unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector("doCommandBySelector:"), ObjCRuntime.selector(command))
    }

    /// Text inserted where the client's selection is.
    static func insert(_ receiver: UnsafeMutableRawPointer, text: String) {
        let string = NSObject(objCReturnValue: text.objCReturnValue())
        if Send.responds(receiver, "insertText:replacementRange:") {
            typealias F = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, UnsafeMutableRawPointer, PerryRange) -> Void
            // NSNotFound: the selection.
            unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector("insertText:replacementRange:"), string.objcObject,
                                                           PerryRange(location: UInt(Int.max), length: 0))
        } else if Send.responds(receiver, "insertText:") {
            Send.void(receiver, "insertText:", string.objcObject)
        }
    }

    /// Sends one key down's text or command to `receiver`; whether it was
    /// one of either.
    @discardableResult
    static func handle(_ event: NSEvent, for receiver: UnsafeMutableRawPointer) -> Bool {
        guard event.type == .keyDown else { return false }
        if let command = command(keyCode: event.keyCode, flags: event.modifierFlags) {
            if Send.responds(receiver, "doCommandBySelector:") { send(receiver, command: command) } else {
                Send.void(receiver, command, event.objcObject)
            }
            return true
        }
        guard let text = text(event) else { return false }
        insert(receiver, text: text)
        return true
    }
}

/// The input context of a view that adopts NSTextInputClient.
@ObjCClass("NSTextInputContext")
open class NSTextInputContext: NSObject {
    nonisolated(unsafe) static var current: NSTextInputContext?
    /// Not retained: the client owns its context.
    var client: UnsafeMutableRawPointer?
    var acceptsGlyphInfo = false
    var allowedInputSourceLocales: NSObject?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithClient:")
    public required init(client: NSObject?) {
        super.init()
        self.client = client?.objcObject
    }

    @ObjCClassMethod("currentInputContext") static func currentInputContext() -> NSTextInputContext? { current }
    @ObjCMethod("client") func clientValue() -> NSObject? { client.map { NSObject($0) } }
    @ObjCMethod("activate") func activate() { NSTextInputContext.current = self }
    @ObjCMethod("deactivate") func deactivate() { if NSTextInputContext.current === self { NSTextInputContext.current = nil } }

    /// A key down as text or a command for the client; other events are
    /// not the context's.
    @ObjCMethod("handleEvent:")
    func handleEvent(_ event: NSObject?) -> Bool {
        guard let client, let event = event?.as(NSEvent.self) else { return false }
        return KeyBindings.handle(event, for: client)
    }

    /// No text is being composed, so there is nothing to discard.
    @ObjCMethod("discardMarkedText") func discardMarkedText() {}
    @ObjCMethod("invalidateCharacterCoordinates") func invalidateCharacterCoordinates() {}
    @ObjCMethod("acceptsGlyphInfo") func acceptsGlyphInfoValue() -> Bool { acceptsGlyphInfo }
    @ObjCMethod("setAcceptsGlyphInfo:") func setAcceptsGlyphInfo(_ value: Bool) { acceptsGlyphInfo = value }
    @ObjCMethod("allowedInputSourceLocales") func allowedInputSourceLocalesValue() -> NSObject? { allowedInputSourceLocales }
    @ObjCMethod("setAllowedInputSourceLocales:") func setAllowedInputSourceLocales(_ value: NSObject?) { allowedInputSourceLocales = value }
    @ObjCMethod("keyboardInputSources") func keyboardInputSources() -> NSObject { NSMutableArray.empty() }
    @ObjCMethod("selectedKeyboardInputSource") func selectedKeyboardInputSource() -> NSObject? {
        NSObject(objCReturnValue: "com.apple.keylayout.US".objCReturnValue())
    }
    @ObjCMethod("setSelectedKeyboardInputSource:") func setSelectedKeyboardInputSource(_ value: NSObject?) {}
}

enum InputContexts {
    /// Each client's context, made when first asked for.
    nonisolated(unsafe) static var contexts: [UnsafeMutableRawPointer: NSTextInputContext] = [:]

    static func context(for view: NSView) -> NSTextInputContext? {
        let object = view.objcObject
        guard Send.responds(object, "insertText:replacementRange:") else { return nil }
        if let context = contexts[object] { return context }
        let context = NSTextInputContext(client: view)
        contexts[object] = context
        return context
    }
}

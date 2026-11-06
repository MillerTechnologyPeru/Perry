import CPerryGeometry
import PerryObjCInterop

// NSResponder: the responder chain. Each event method passes the event to
// the next responder, as AppKit's do, until a responder handles it or the
// chain ends; key events nobody takes are dropped (AppKit beeps).

@ObjCClass("NSResponder")
open class NSResponder: NSObject {
    /// Not retained, as AppKit's.
    var nextResponderObject: UnsafeMutableRawPointer?
    var menu: NSObject?
    var touchBar: NSObject?
    var touchBarMade = false

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("nextResponder") func nextResponder() -> NSObject? { nextResponderObject.map(NSObject.init) }
    @ObjCMethod("setNextResponder:") func setNextResponder(_ responder: NSObject?) { nextResponderObject = responder?.objcObject }

    @ObjCMethod("acceptsFirstResponder") func acceptsFirstResponder() -> Bool { false }
    @ObjCMethod("becomeFirstResponder") func becomeFirstResponder() -> Bool { true }
    @ObjCMethod("resignFirstResponder") func resignFirstResponder() -> Bool { true }
    @ObjCMethod("validateProposedFirstResponder:forEvent:")
    func validateProposedFirstResponder(_ responder: NSObject?, for event: NSObject?) -> Bool { true }

    @ObjCMethod("menu") func responderMenu() -> NSObject? { menu }
    @ObjCMethod("setMenu:") func setMenu(_ menu: NSObject?) { self.menu = menu }
    @ObjCMethod("undoManager") func undoManager() -> NSObject? { nil }

    /// There's no Touch Bar to show it on: kept, and made by -makeTouchBar
    /// the first time it is asked for.
    @ObjCMethod("touchBar")
    func responderTouchBar() -> NSObject? {
        if touchBar == nil, !touchBarMade {
            touchBarMade = true
            touchBar = Send.object(objcObject, "makeTouchBar").map(NSObject.init)
        }
        return touchBar
    }
    @ObjCMethod("setTouchBar:") func setTouchBar(_ touchBar: NSObject?) { self.touchBar = touchBar }
    @ObjCMethod("makeTouchBar") func makeTouchBar() -> NSObject? { nil }

    /// Passes `event` on to the next responder.
    func forward(_ selector: String, _ event: NSObject?) {
        guard let next = nextResponderObject else { return }
        Send.void(next, selector, event?.objcObject)
    }

    @ObjCMethod("mouseDown:") func mouseDown(_ event: NSObject?) { forward("mouseDown:", event) }
    @ObjCMethod("mouseUp:") func mouseUp(_ event: NSObject?) { forward("mouseUp:", event) }
    @ObjCMethod("mouseDragged:") func mouseDragged(_ event: NSObject?) { forward("mouseDragged:", event) }
    @ObjCMethod("mouseMoved:") func mouseMoved(_ event: NSObject?) { forward("mouseMoved:", event) }
    @ObjCMethod("mouseEntered:") func mouseEntered(_ event: NSObject?) { forward("mouseEntered:", event) }
    @ObjCMethod("mouseExited:") func mouseExited(_ event: NSObject?) { forward("mouseExited:", event) }
    @ObjCMethod("rightMouseDown:") func rightMouseDown(_ event: NSObject?) { forward("rightMouseDown:", event) }
    @ObjCMethod("rightMouseUp:") func rightMouseUp(_ event: NSObject?) { forward("rightMouseUp:", event) }
    @ObjCMethod("rightMouseDragged:") func rightMouseDragged(_ event: NSObject?) { forward("rightMouseDragged:", event) }
    @ObjCMethod("otherMouseDown:") func otherMouseDown(_ event: NSObject?) { forward("otherMouseDown:", event) }
    @ObjCMethod("otherMouseUp:") func otherMouseUp(_ event: NSObject?) { forward("otherMouseUp:", event) }
    @ObjCMethod("otherMouseDragged:") func otherMouseDragged(_ event: NSObject?) { forward("otherMouseDragged:", event) }
    @ObjCMethod("scrollWheel:") func scrollWheel(_ event: NSObject?) { forward("scrollWheel:", event) }
    @ObjCMethod("keyDown:") func keyDown(_ event: NSObject?) { forward("keyDown:", event) }
    @ObjCMethod("keyUp:") func keyUp(_ event: NSObject?) { forward("keyUp:", event) }
    @ObjCMethod("flagsChanged:") func flagsChanged(_ event: NSObject?) { forward("flagsChanged:", event) }
    @ObjCMethod("cursorUpdate:") func cursorUpdate(_ event: NSObject?) { forward("cursorUpdate:", event) }
    @ObjCMethod("noResponderFor:") func noResponder(for selector: ObjCSelector?) {}

    @ObjCMethod("performKeyEquivalent:") func performKeyEquivalent(_ event: NSObject?) -> Bool { false }

    /// Text the keys type goes to -insertText:, and editing keys to
    /// -doCommandBySelector:, as the input manager sends them.
    @ObjCMethod("interpretKeyEvents:")
    func interpretKeyEvents(_ events: NSObject?) {
        guard let events = events?.as(NSArray.self) else { return }
        for object in events.elements {
            guard let event = object.as(NSEvent.self), event.type == .keyDown else { continue }
            let commands: [UInt16: String] = [0x24: "insertNewline:", 0x4C: "insertNewline:", 0x30: "insertTab:", 0x33: "deleteBackward:",
                                              0x75: "deleteForward:", 0x35: "cancelOperation:", 0x7B: "moveLeft:", 0x7C: "moveRight:",
                                              0x7D: "moveDown:", 0x7E: "moveUp:"]
            if let command = commands[event.keyCode] {
                if Send.responds(objcObject, "doCommandBySelector:") {
                    typealias F = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, UnsafeRawPointer) -> Void
                    unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(objcObject, ObjCRuntime.selector("doCommandBySelector:"),
                                                                   ObjCRuntime.selector(command))
                }
                continue
            }
            let text = event.characters
            guard !text.isEmpty, text.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value < 0xF700 && $0.value != 0x7F }),
                  Send.responds(objcObject, "insertText:") else { continue }
            Send.void(objcObject, "insertText:", text.objCArgument())
        }
    }

    /// Sends the action to the first responder along the chain that
    /// implements it.
    @ObjCMethod("tryToPerform:with:")
    func tryToPerform(_ action: ObjCSelector?, with object: NSObject?) -> Bool {
        guard let action else { return false }
        let name = String(cString: action.pointer.assumingMemoryBound(to: CChar.self))
        var responder: UnsafeMutableRawPointer? = objcObject
        while let current = responder {
            if Send.responds(current, name) {
                Send.void(current, name, object?.objcObject)
                return true
            }
            responder = Send.object(current, "nextResponder")
        }
        return false
    }
}

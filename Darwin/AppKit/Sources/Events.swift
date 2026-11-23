import Foundation

// NSEvent.SpecialKey: the function keys and the control characters a key
// event's characters can hold, from the constants of NSEvent.h and NSText.h.

extension NSEvent {
    public struct SpecialKey: RawRepresentable, Equatable, Hashable {
        public typealias RawValue = Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public let rawValue: Int

        /// The key's character.
        public var unicodeScalar: Unicode.Scalar {
            Unicode.Scalar(UInt32(rawValue)) ?? "\u{FFFD}"
        }
    }

    /// The special key a key event is for, if it is for one: a function key
    /// (Unicode's private-use range AppKit gives them) or a control character.
    public var specialKey: SpecialKey? {
        guard type == .keyDown || type == .keyUp,
              let scalar = charactersIgnoringModifiers?.unicodeScalars.first else { return nil }
        let key = NSEvent.SpecialKey(rawValue: Int(scalar.value))
        switch scalar.value {
        case 0xF700...0xF8FF:
            return key
        default:
            return SpecialKey.characters.contains(key) ? key : nil
        }
    }
}

extension NSEvent.SpecialKey {
    public static let upArrow = NSEvent.SpecialKey(rawValue: NSUpArrowFunctionKey)
    public static let downArrow = NSEvent.SpecialKey(rawValue: NSDownArrowFunctionKey)
    public static let leftArrow = NSEvent.SpecialKey(rawValue: NSLeftArrowFunctionKey)
    public static let rightArrow = NSEvent.SpecialKey(rawValue: NSRightArrowFunctionKey)
    public static let f1 = NSEvent.SpecialKey(rawValue: NSF1FunctionKey)
    public static let f2 = NSEvent.SpecialKey(rawValue: NSF2FunctionKey)
    public static let f3 = NSEvent.SpecialKey(rawValue: NSF3FunctionKey)
    public static let f4 = NSEvent.SpecialKey(rawValue: NSF4FunctionKey)
    public static let f5 = NSEvent.SpecialKey(rawValue: NSF5FunctionKey)
    public static let f6 = NSEvent.SpecialKey(rawValue: NSF6FunctionKey)
    public static let f7 = NSEvent.SpecialKey(rawValue: NSF7FunctionKey)
    public static let f8 = NSEvent.SpecialKey(rawValue: NSF8FunctionKey)
    public static let f9 = NSEvent.SpecialKey(rawValue: NSF9FunctionKey)
    public static let f10 = NSEvent.SpecialKey(rawValue: NSF10FunctionKey)
    public static let f11 = NSEvent.SpecialKey(rawValue: NSF11FunctionKey)
    public static let f12 = NSEvent.SpecialKey(rawValue: NSF12FunctionKey)
    public static let f13 = NSEvent.SpecialKey(rawValue: NSF13FunctionKey)
    public static let f14 = NSEvent.SpecialKey(rawValue: NSF14FunctionKey)
    public static let f15 = NSEvent.SpecialKey(rawValue: NSF15FunctionKey)
    public static let f16 = NSEvent.SpecialKey(rawValue: NSF16FunctionKey)
    public static let f17 = NSEvent.SpecialKey(rawValue: NSF17FunctionKey)
    public static let f18 = NSEvent.SpecialKey(rawValue: NSF18FunctionKey)
    public static let f19 = NSEvent.SpecialKey(rawValue: NSF19FunctionKey)
    public static let f20 = NSEvent.SpecialKey(rawValue: NSF20FunctionKey)
    public static let f21 = NSEvent.SpecialKey(rawValue: NSF21FunctionKey)
    public static let f22 = NSEvent.SpecialKey(rawValue: NSF22FunctionKey)
    public static let f23 = NSEvent.SpecialKey(rawValue: NSF23FunctionKey)
    public static let f24 = NSEvent.SpecialKey(rawValue: NSF24FunctionKey)
    public static let f25 = NSEvent.SpecialKey(rawValue: NSF25FunctionKey)
    public static let f26 = NSEvent.SpecialKey(rawValue: NSF26FunctionKey)
    public static let f27 = NSEvent.SpecialKey(rawValue: NSF27FunctionKey)
    public static let f28 = NSEvent.SpecialKey(rawValue: NSF28FunctionKey)
    public static let f29 = NSEvent.SpecialKey(rawValue: NSF29FunctionKey)
    public static let f30 = NSEvent.SpecialKey(rawValue: NSF30FunctionKey)
    public static let f31 = NSEvent.SpecialKey(rawValue: NSF31FunctionKey)
    public static let f32 = NSEvent.SpecialKey(rawValue: NSF32FunctionKey)
    public static let f33 = NSEvent.SpecialKey(rawValue: NSF33FunctionKey)
    public static let f34 = NSEvent.SpecialKey(rawValue: NSF34FunctionKey)
    public static let f35 = NSEvent.SpecialKey(rawValue: NSF35FunctionKey)
    public static let insert = NSEvent.SpecialKey(rawValue: NSInsertFunctionKey)
    public static let deleteForward = NSEvent.SpecialKey(rawValue: NSDeleteFunctionKey)
    public static let home = NSEvent.SpecialKey(rawValue: NSHomeFunctionKey)
    public static let begin = NSEvent.SpecialKey(rawValue: NSBeginFunctionKey)
    public static let end = NSEvent.SpecialKey(rawValue: NSEndFunctionKey)
    public static let pageUp = NSEvent.SpecialKey(rawValue: NSPageUpFunctionKey)
    public static let pageDown = NSEvent.SpecialKey(rawValue: NSPageDownFunctionKey)
    public static let printScreen = NSEvent.SpecialKey(rawValue: NSPrintScreenFunctionKey)
    public static let scrollLock = NSEvent.SpecialKey(rawValue: NSScrollLockFunctionKey)
    public static let pause = NSEvent.SpecialKey(rawValue: NSPauseFunctionKey)
    public static let sysReq = NSEvent.SpecialKey(rawValue: NSSysReqFunctionKey)
    public static let `break` = NSEvent.SpecialKey(rawValue: NSBreakFunctionKey)
    public static let reset = NSEvent.SpecialKey(rawValue: NSResetFunctionKey)
    public static let stop = NSEvent.SpecialKey(rawValue: NSStopFunctionKey)
    public static let menu = NSEvent.SpecialKey(rawValue: NSMenuFunctionKey)
    public static let user = NSEvent.SpecialKey(rawValue: NSUserFunctionKey)
    public static let system = NSEvent.SpecialKey(rawValue: NSSystemFunctionKey)
    public static let print = NSEvent.SpecialKey(rawValue: NSPrintFunctionKey)
    public static let clearLine = NSEvent.SpecialKey(rawValue: NSClearLineFunctionKey)
    public static let clearDisplay = NSEvent.SpecialKey(rawValue: NSClearDisplayFunctionKey)
    public static let insertLine = NSEvent.SpecialKey(rawValue: NSInsertLineFunctionKey)
    public static let deleteLine = NSEvent.SpecialKey(rawValue: NSDeleteLineFunctionKey)
    public static let insertCharacter = NSEvent.SpecialKey(rawValue: NSInsertCharFunctionKey)
    public static let deleteCharacter = NSEvent.SpecialKey(rawValue: NSDeleteCharFunctionKey)
    public static let prev = NSEvent.SpecialKey(rawValue: NSPrevFunctionKey)
    public static let next = NSEvent.SpecialKey(rawValue: NSNextFunctionKey)
    public static let select = NSEvent.SpecialKey(rawValue: NSSelectFunctionKey)
    public static let execute = NSEvent.SpecialKey(rawValue: NSExecuteFunctionKey)
    public static let undo = NSEvent.SpecialKey(rawValue: NSUndoFunctionKey)
    public static let redo = NSEvent.SpecialKey(rawValue: NSRedoFunctionKey)
    public static let find = NSEvent.SpecialKey(rawValue: NSFindFunctionKey)
    public static let help = NSEvent.SpecialKey(rawValue: NSHelpFunctionKey)
    public static let modeSwitch = NSEvent.SpecialKey(rawValue: NSModeSwitchFunctionKey)
    public static let enter = NSEvent.SpecialKey(rawValue: NSEnterCharacter)
    public static let backspace = NSEvent.SpecialKey(rawValue: NSBackspaceCharacter)
    public static let tab = NSEvent.SpecialKey(rawValue: NSTabCharacter)
    public static let newline = NSEvent.SpecialKey(rawValue: NSNewlineCharacter)
    public static let formFeed = NSEvent.SpecialKey(rawValue: NSFormFeedCharacter)
    public static let carriageReturn = NSEvent.SpecialKey(rawValue: NSCarriageReturnCharacter)
    public static let backTab = NSEvent.SpecialKey(rawValue: NSBackTabCharacter)
    public static let delete = NSEvent.SpecialKey(rawValue: NSDeleteCharacter)
    public static let lineSeparator = NSEvent.SpecialKey(rawValue: NSLineSeparatorCharacter)
    public static let paragraphSeparator = NSEvent.SpecialKey(rawValue: NSParagraphSeparatorCharacter)

    /// The control characters that are special keys.
    static let characters: Set<NSEvent.SpecialKey> = [
        .enter, .backspace, .tab, .newline, .formFeed, .carriageReturn, .backTab, .delete,
        .lineSeparator, .paragraphSeparator,
    ]
}

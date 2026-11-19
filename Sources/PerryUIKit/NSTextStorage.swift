import CPerryGeometry
import PerryObjCInterop

// NSTextStorage, TextKit's attributed string: it keeps the layout managers
// that lay it out and tells its delegate when it was edited. It holds an
// NSMutableAttributedString and forwards the messages it doesn't answer
// itself to it, so it answers NSMutableAttributedString's. A subclass that
// keeps its own characters overrides -string and
// -attributesAtIndex:effectiveRange:, which layout managers send it.

final class TextStorageState: ObjectState {
    /// The attributed string, retained.
    var contents: NSObject?
    /// Not retained, as TextKit's.
    var delegate: UnsafeMutableRawPointer?
    /// Retained: the storage owns its layout managers.
    var layoutManagers: [NSObject] = []
    var editing = 0
    var editedMask: UInt = 0
    var editedRange = PerryRange(location: UInt(Int.max), length: 0)
    var changeInLength = 0
}

@ObjCClass("NSTextStorage")
open class NSTextStorage: NSObject {
    static let states = StateTable<TextStorageState>()
    var storage: TextStorageState { NSTextStorage.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        NSTextStorage.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSTextStorage.objCClass.pointer)
    }

    /// The attributed string, made empty when first needed.
    var contents: NSObject {
        if let contents = storage.contents { return contents }
        let made = ObjCClass(named: "NSMutableAttributedString").object.newInstance()
        storage.contents = made
        return made
    }

    @ObjCMethod("init") func initialize() -> Self { self }

    @ObjCMethod("initWithString:")
    func initialize(string: NSObject?) -> Self {
        let made = ObjCClass(named: "NSMutableAttributedString").object.allocated().sendInitializeStorage(string: string ?? NSObject(("").objCArgument()!))
        storage.contents = made
        return self
    }

    @ObjCMethod("initWithString:attributes:")
    func initialize(string: NSObject?, attributes: NSObject?) -> Self {
        let made = ObjCClass(named: "NSMutableAttributedString").object.allocated()
            .sendInitializeStorage(string: string ?? NSObject(("").objCArgument()!), attributes: attributes)
        storage.contents = made
        return self
    }

    @ObjCMethod("initWithAttributedString:")
    func initialize(attributedString: NSObject?) -> Self {
        if let attributedString { storage.contents = attributedString.mutableCopied() }
        return self
    }

    /// Everything else is the attributed string's.
    @ObjCMethod("forwardingTargetForSelector:")
    func forwardingTarget(for selector: ObjCSelector?) -> NSObject? { contents }

    // The primitives, which a subclass overrides.
    @ObjCMethod("string") func string() -> NSObject? { contents.sendStringObject() }
    @ObjCMethod("length") func length() -> UInt { contents.sendLength() }
    @ObjCMethod("attributesAtIndex:effectiveRange:")
    func attributes(at index: UInt, effectiveRange: UnsafeMutableRawPointer?) -> NSObject? {
        contents.sendAttributes(at: index, effectiveRange: effectiveRange)
    }

    @ObjCMethod("replaceCharactersInRange:withString:")
    func replaceCharacters(in range: PerryRange, with string: NSObject?) {
        contents.sendReplaceCharacters(in: range, with: string)
        sendEdited(2, range: range, changeInLength: Int(string?.sendLength() ?? 0) - Int(range.length))
    }

    @ObjCMethod("setAttributes:range:")
    func setAttributes(_ attributes: NSObject?, range: PerryRange) {
        contents.sendSetAttributes(attributes, range: range)
        sendEdited(1, range: range, changeInLength: 0)
    }

    // MARK: Layout managers

    @ObjCMethod("layoutManagers") func layoutManagers() -> NSObject { NSMutableArray.of(storage.layoutManagers) }

    @ObjCMethod("addLayoutManager:")
    func addLayoutManager(_ manager: NSObject?) {
        guard let manager, !storage.layoutManagers.contains(where: { $0.objcObject == manager.objcObject }) else { return }
        storage.layoutManagers.append(manager)
        manager.sendSetTextStorage(self)
    }

    @ObjCMethod("removeLayoutManager:")
    func removeLayoutManager(_ manager: NSObject?) {
        guard let manager else { return }
        storage.layoutManagers.removeAll { $0.objcObject == manager.objcObject }
        manager.sendSetTextStorage(nil)
    }

    // MARK: Editing

    @ObjCMethod("delegate") func delegate() -> NSObject? { storage.delegate.map { NSObject($0) } }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { storage.delegate = delegate?.objcObject }
    @ObjCMethod("editedMask") func editedMask() -> UInt { storage.editedMask }
    @ObjCMethod("editedRange") func editedRange() -> PerryRange { storage.editedRange }
    @ObjCMethod("changeInLength") func changeInLength() -> Int { storage.changeInLength }

    @ObjCMethod("beginEditing") func beginEditing() { storage.editing += 1 }

    @ObjCMethod("endEditing")
    func endEditing() {
        storage.editing = max(0, storage.editing - 1)
        if storage.editing == 0, storage.editedMask != 0 { sendProcessEditing() }
    }

    /// An edit: the ranges add up until the edits are processed, at once
    /// or when the outermost -endEditing comes.
    @ObjCMethod("edited:range:changeInLength:")
    func edited(_ mask: UInt, range: PerryRange, changeInLength delta: Int) {
        let state = storage
        if state.editedMask == 0 {
            state.editedRange = range
        } else {
            let start = min(state.editedRange.location, range.location)
            let end = max(state.editedRange.location + state.editedRange.length, range.location + range.length)
            state.editedRange = PerryRange(location: start, length: end - start)
        }
        state.editedMask |= mask
        state.changeInLength += delta
        if state.editing == 0 { sendProcessEditing() }
    }

    /// The delegate and observers hear of the edits, which then end.
    @ObjCMethod("processEditing")
    func processEditing() {
        let state = storage
        let center = NSNotificationCenter.defaultCenter()
        center.post(name: "NSTextStorageWillProcessEditingNotification", object: self)
        if let delegate = state.delegate.map({ NSObject($0) }),
           delegate.responds(to: "textStorage:didProcessEditing:range:changeInLength:") {
            delegate.sendTextStorage(self, didProcessEditing: state.editedMask, range: state.editedRange, changeInLength: state.changeInLength)
        }
        center.post(name: "NSTextStorageDidProcessEditingNotification", object: self)
        state.editedMask = 0
        state.changeInLength = 0
        state.editedRange = PerryRange(location: UInt(Int.max), length: 0)
    }
}

/// The notifications and edit actions' names.
@ObjCConstants
enum TextStorageNames {
    static let NSTextStorageWillProcessEditingNotification = "NSTextStorageWillProcessEditingNotification"
    static let NSTextStorageDidProcessEditingNotification = "NSTextStorageDidProcessEditingNotification"
}

extension NSObject {
    @ObjCMethod("initWithString:") func sendInitializeStorage(string: NSObject) -> NSObject
    @ObjCMethod("initWithString:attributes:") func sendInitializeStorage(string: NSObject, attributes: NSObject?) -> NSObject
    @ObjCMethod("string") func sendStringObject() -> NSObject?
    @ObjCMethod("attributesAtIndex:effectiveRange:")
    func sendAttributes(at index: UInt, effectiveRange: UnsafeMutableRawPointer?) -> NSObject?
    @ObjCMethod("replaceCharactersInRange:withString:") func sendReplaceCharacters(in range: PerryRange, with string: NSObject?)
    @ObjCMethod("setAttributes:range:") func sendSetAttributes(_ attributes: NSObject?, range: PerryRange)
    @ObjCMethod("setTextStorage:") func sendSetTextStorage(_ storage: NSObject?)
    @ObjCMethod("edited:range:changeInLength:") func sendEdited(_ mask: UInt, range: PerryRange, changeInLength delta: Int)
    @ObjCMethod("processEditing") func sendProcessEditing()
    @ObjCMethod("textStorage:didProcessEditing:range:changeInLength:")
    func sendTextStorage(_ storage: NSObject, didProcessEditing mask: UInt, range: PerryRange, changeInLength delta: Int)
}

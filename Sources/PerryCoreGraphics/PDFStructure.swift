import CPerryCoreGraphics
import Glibc
import PerryObjCInterop

// Tagged PDF's structure elements: a tag type, the text properties a
// structure element carries (title, language, alternative, expansion and
// actual text), and its children, structure elements and marked-content
// items, in the order added. Perry has no PDF context to write them into;
// they hold what they are given.

final class StructureElementState: @unchecked Sendable {
    /// CGPDFTagType.
    let type: Int32
    var title: String?
    var languageIdentifier: String?
    var alternativeText: String?
    var expansionText: String?
    var actualText: String?
    /// Child structure elements and marked-content items, retained.
    private(set) var children: [Ref] = []
    private(set) var markedContentItems: [Ref] = []
    private let lock = Lock()

    init(type: Int32) { self.type = type }

    func add(child: Ref) { lock.withLock { children.append(ObjCRuntime.retain(child)!) } }
    func add(markedContentItem: Ref) { lock.withLock { markedContentItems.append(ObjCRuntime.retain(markedContentItem)!) } }

    deinit {
        children.forEach { ObjCRuntime.release($0) }
        markedContentItems.forEach { ObjCRuntime.release($0) }
    }
}

@ObjCClass("CGPDFStructureElement")
public final class CGPDFStructureElementObject: NSObject {
    static let states = StateTable<StructureElementState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        CGPDFStructureElementObject.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CGPDFStructureElementObject.objCClass.pointer)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { TypeIDs.pdfStructureElement }

    @ObjCMethod("description")
    func description() -> String {
        guard let state = CGPDFStructureElementObject.states[objcObject] else { return "<CGPDFStructureElement \(objcObject)>" }
        var text = "<CGPDFStructureElement \(objcObject)> type \(state.type)"
        for (key, value) in [("title", state.title), ("language", state.languageIdentifier), ("alternativeText", state.alternativeText),
                             ("expansionText", state.expansionText), ("actualText", state.actualText)] {
            if let value { text += ", \(key) \"\(value)\"" }
        }
        return text + ", \(state.children.count) children, \(state.markedContentItems.count) marked-content items"
    }
}

private func element(_ object: Ref?) -> StructureElementState? { CGPDFStructureElementObject.states[object] }

private func text(_ string: Ref?) -> String? { string.map { String(objCArgument: $0) } }

@c(_CGPDFStructureElementGetTypeID) public func CGPDFStructureElementGetTypeID() -> UInt { TypeIDs.pdfStructureElement }

@c(_CGPDFStructureElementCreate)
public func CGPDFStructureElementCreate(_ type: Int32) -> Ref {
    makeObject(CGPDFStructureElementObject.objCClass, CGPDFStructureElementObject.states, StructureElementState(type: type))
}

@c(_CGPDFStructureElementRetain) public func CGPDFStructureElementRetain(_ element: Ref?) -> Ref? { ObjCRuntime.retain(element) }
@c(_CGPDFStructureElementRelease) public func CGPDFStructureElementRelease(_ element: Ref?) { ObjCRuntime.release(element) }

@c(_CGPDFStructureElementSetTitle)
public func CGPDFStructureElementSetTitle(_ structureElement: Ref?, _ title: Ref?) { element(structureElement)?.title = text(title) }

@c(_CGPDFStructureElementSetLanguageIdentifier)
public func CGPDFStructureElementSetLanguageIdentifier(_ structureElement: Ref?, _ language: Ref?) {
    element(structureElement)?.languageIdentifier = text(language)
}

@c(_CGPDFStructureElementSetAlternativeText)
public func CGPDFStructureElementSetAlternativeText(_ structureElement: Ref?, _ alternativeText: Ref?) {
    element(structureElement)?.alternativeText = text(alternativeText)
}

@c(_CGPDFStructureElementSetExpansionText)
public func CGPDFStructureElementSetExpansionText(_ structureElement: Ref?, _ expansionText: Ref?) {
    element(structureElement)?.expansionText = text(expansionText)
}

@c(_CGPDFStructureElementSetActualText)
public func CGPDFStructureElementSetActualText(_ structureElement: Ref?, _ actualText: Ref?) {
    element(structureElement)?.actualText = text(actualText)
}

/// noErr, or paramErr (-50) for an argument that isn't a structure element
/// or an element added to itself.
@c(_CGPDFStructureElementAddStructureElement)
public func CGPDFStructureElementAddStructureElement(_ structureElement: Ref?, _ child: Ref?) -> Int32 {
    guard let parent = element(structureElement), let child, element(child) != nil, child != structureElement else { return -50 }
    parent.add(child: child)
    return 0
}

@c(_CGPDFStructureElementAddMarkedContentItem)
public func CGPDFStructureElementAddMarkedContentItem(_ structureElement: Ref?, _ item: Ref?) -> Int32 {
    guard let parent = element(structureElement), let item else { return -50 }
    parent.add(markedContentItem: item)
    return 0
}

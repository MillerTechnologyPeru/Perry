import CPerryGeometry
import PerryObjCInterop

// NSPathControl, NSPathCell and NSPathComponentCell: a file path shown as
// its components, which Interface Builder's tools subclass. The control
// keeps its URL and style, and its cell a component cell for each part of
// the path; it draws as a plain control.

@ObjCClass("NSPathControl")
open class NSPathControl: NSControl {
    @ObjCClassMethod("cellClass") static func pathCellClass() -> UnsafeMutableRawPointer? { Classes.named("NSPathCell")?.pointer }

    private var pathCell: NSPathCell? { cellObject?.as(NSPathCell.self) }

    @ObjCMethod("URL") func controlURL() -> NSObject? { pathCell?.url }
    @ObjCMethod("setURL:") func setURL(_ value: NSObject?) { pathCell?.setURL(value); setNeedsDisplay(true) }
    @ObjCMethod("pathStyle") func controlPathStyle() -> Int { pathCell?.pathStyle ?? 0 }
    @ObjCMethod("setPathStyle:") func setPathStyle(_ value: Int) { pathCell?.pathStyle = value; setNeedsDisplay(true) }
    @ObjCMethod("backgroundColor") func controlBackgroundColor() -> NSColor? { pathCell?.backgroundColor }
    @ObjCMethod("setBackgroundColor:") func setBackgroundColor(_ value: NSColor?) { pathCell?.backgroundColor = value; setNeedsDisplay(true) }
    @ObjCMethod("delegate") func controlDelegate() -> NSObject? { pathCell?.delegateObject.map(NSObject.init) }
    @ObjCMethod("setDelegate:") func setDelegate(_ value: NSObject?) { pathCell?.delegateObject = value?.objcObject }
    @ObjCMethod("pathComponentCells") func pathComponentCells() -> NSObject { NSMutableArray.of(pathCell?.components ?? []) }
    @ObjCMethod("setPathComponentCells:") func setPathComponentCells(_ value: NSObject?) { pathCell?.setPathComponentCells(value) }
    @ObjCMethod("clickedPathComponentCell") func clickedPathComponentCell() -> NSObject? { nil }
    @ObjCMethod("doubleAction") func controlDoubleAction() -> ObjCSelector? { pathCell?.doubleAction }
    @ObjCMethod("setDoubleAction:") func setDoubleAction(_ value: ObjCSelector?) { pathCell?.doubleAction = value }
}

@ObjCClass("NSPathCell")
open class NSPathCell: NSActionCell {
    var url: NSObject?
    /// NSPathStyle: standard 0, navigation bar 1, pop-up 2.
    var pathStyle = 0
    var backgroundColor: NSColor?
    /// Not retained.
    var delegateObject: UnsafeMutableRawPointer?
    var components: [NSObject] = []
    var doubleAction: ObjCSelector?
    var placeholder: NSObject?

    @ObjCClassMethod("pathComponentCellClass")
    static func pathComponentCellClass() -> UnsafeMutableRawPointer? { Classes.named("NSPathComponentCell")?.pointer }

    @ObjCMethod("URL") func cellURL() -> NSObject? { url }
    /// The URL, and a component cell for each part of its path.
    @ObjCMethod("setURL:")
    func setURL(_ value: NSObject?) {
        url = value
        let path = value.flatMap { Send.object($0.objcObject, "path") }.map { String(objCArgument: $0) } ?? ""
        components = path.split(separator: "/").map { NSPathComponentCell(textCell: String($0)) }
    }
    @ObjCMethod("pathStyle") func cellPathStyle() -> Int { pathStyle }
    @ObjCMethod("setPathStyle:") func setPathStyle(_ value: Int) { pathStyle = value }
    @ObjCMethod("backgroundColor") func cellBackgroundColor() -> NSColor? { backgroundColor }
    @ObjCMethod("setBackgroundColor:") func setBackgroundColor(_ value: NSColor?) { backgroundColor = value }
    @ObjCMethod("delegate") func cellDelegate() -> NSObject? { delegateObject.map(NSObject.init) }
    @ObjCMethod("setDelegate:") func setDelegate(_ value: NSObject?) { delegateObject = value?.objcObject }
    @ObjCMethod("pathComponentCells") func pathComponentCells() -> NSObject { NSMutableArray.of(components) }
    @ObjCMethod("setPathComponentCells:")
    func setPathComponentCells(_ value: NSObject?) {
        components = value?.as(NSArray.self)?.elements ?? []
    }
    @ObjCMethod("clickedPathComponentCell") func clickedPathComponentCell() -> NSObject? { nil }
    @ObjCMethod("doubleAction") func cellDoubleAction() -> ObjCSelector? { doubleAction }
    @ObjCMethod("setDoubleAction:") func setDoubleAction(_ value: ObjCSelector?) { doubleAction = value }
    @ObjCMethod("placeholderString") func placeholderString() -> NSObject? { placeholder }
    @ObjCMethod("setPlaceholderString:") func setPlaceholderString(_ value: NSObject?) { placeholder = value }
    @ObjCMethod("placeholderAttributedString") func placeholderAttributedString() -> NSObject? { placeholder }
    @ObjCMethod("setPlaceholderAttributedString:") func setPlaceholderAttributedString(_ value: NSObject?) { placeholder = value }
}

@ObjCClass("NSPathComponentCell")
open class NSPathComponentCell: NSTextFieldCell {
    var url: NSObject?

    @ObjCMethod("URL") func cellURL() -> NSObject? { url }
    @ObjCMethod("setURL:") func setURL(_ value: NSObject?) { url = value }
}

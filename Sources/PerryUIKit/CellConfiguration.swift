import CPerryGeometry
import PerryObjCInterop

// Configuration states and the configuration update of cells (iOS 14): a
// cell asks for a new configuration in its next layout pass after
// -setNeedsUpdateConfiguration, after its selection or highlight changes,
// and before it first shows. It is sent -updateConfigurationUsingState:
// (an Objective-C override's) and then, if it has one,
// -_bridgedUpdateConfigurationUsingState:, which the Swift overlay
// declares for updateConfiguration(using:) and Swift cells override, with
// a UICellConfigurationState of its trait collection, selection and
// highlight. The states' custom keys aren't kept.

final class ConfigurationStateValues: ObjectState {
    var traitCollection: UITraitCollection?
    var disabled = false
    var highlighted = false
    var selected = false
    var focused = false
    var pinned = false
    var editing = false
    var expanded = false
    var swiped = false
    var reordering = false
    /// UICellConfigurationDragState and DropState: none 0.
    var dragState = 0
    var dropState = 0

    func copy(to other: ConfigurationStateValues) {
        (other.traitCollection, other.disabled, other.highlighted) = (traitCollection, disabled, highlighted)
        (other.selected, other.focused, other.pinned) = (selected, focused, pinned)
        (other.editing, other.expanded, other.swiped, other.reordering) = (editing, expanded, swiped, reordering)
        (other.dragState, other.dropState) = (dragState, dropState)
    }
}

@ObjCClass("UIViewConfigurationState")
open class UIViewConfigurationState: NSObject {
    static let values = StateTable<ConfigurationStateValues>()
    var stateValues: ConfigurationStateValues { UIViewConfigurationState.values[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        UIViewConfigurationState.values.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIViewConfigurationState.objCClass.pointer)
    }

    @ObjCMethod("initWithTraitCollection:")
    func initialize(traitCollection: UITraitCollection?) -> NSObject {
        stateValues.traitCollection = traitCollection
        return self
    }

    /// A state of the receiver's class with the same values.
    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UIViewConfigurationState {
        let copy = ObjCClass(ObjCRuntime.objectClass(objcObject)!).object.newInstance().unsafeCast(to: UIViewConfigurationState.self)
        stateValues.copy(to: copy.stateValues)
        return copy
    }

    @ObjCMethod("traitCollection") func traitCollection() -> UITraitCollection? { stateValues.traitCollection }
    @ObjCMethod("setTraitCollection:") func setTraitCollection(_ traits: UITraitCollection?) { stateValues.traitCollection = traits }
    @ObjCMethod("isDisabled") func isDisabled() -> Bool { stateValues.disabled }
    @ObjCMethod("setDisabled:") func setDisabled(_ value: Bool) { stateValues.disabled = value }
    @ObjCMethod("isHighlighted") func isHighlighted() -> Bool { stateValues.highlighted }
    @ObjCMethod("setHighlighted:") func setHighlighted(_ value: Bool) { stateValues.highlighted = value }
    @ObjCMethod("isSelected") func isSelected() -> Bool { stateValues.selected }
    @ObjCMethod("setSelected:") func setSelected(_ value: Bool) { stateValues.selected = value }
    @ObjCMethod("isFocused") func isFocused() -> Bool { stateValues.focused }
    @ObjCMethod("setFocused:") func setFocused(_ value: Bool) { stateValues.focused = value }
    @ObjCMethod("isPinned") func isPinned() -> Bool { stateValues.pinned }
    @ObjCMethod("setPinned:") func setPinned(_ value: Bool) { stateValues.pinned = value }
    /// Custom states aren't kept.
    @ObjCMethod("objectForKeyedSubscript:") func object(forKeyedSubscript key: NSObject?) -> NSObject? { nil }
    @ObjCMethod("setObject:forKeyedSubscript:") func setObject(_ object: NSObject?, forKeyedSubscript key: NSObject?) {}
}

@ObjCClass("UICellConfigurationState")
open class UICellConfigurationState: UIViewConfigurationState {
    @ObjCMethod("isEditing") func isEditing() -> Bool { stateValues.editing }
    @ObjCMethod("setEditing:") func setEditing(_ value: Bool) { stateValues.editing = value }
    @ObjCMethod("isExpanded") func isExpanded() -> Bool { stateValues.expanded }
    @ObjCMethod("setExpanded:") func setExpanded(_ value: Bool) { stateValues.expanded = value }
    @ObjCMethod("isSwiped") func isSwiped() -> Bool { stateValues.swiped }
    @ObjCMethod("setSwiped:") func setSwiped(_ value: Bool) { stateValues.swiped = value }
    @ObjCMethod("isReordering") func isReordering() -> Bool { stateValues.reordering }
    @ObjCMethod("setReordering:") func setReordering(_ value: Bool) { stateValues.reordering = value }
    @ObjCMethod("cellDragState") func cellDragState() -> Int { stateValues.dragState }
    @ObjCMethod("setCellDragState:") func setCellDragState(_ value: Int) { stateValues.dragState = value }
    @ObjCMethod("cellDropState") func cellDropState() -> Int { stateValues.dropState }
    @ObjCMethod("setCellDropState:") func setCellDropState(_ value: Int) { stateValues.dropState = value }

    /// A cell's state: its trait collection, selection and highlight.
    static func of(_ cell: UIView, selected: Bool, highlighted: Bool) -> UICellConfigurationState {
        let made = objCClass.object.allocated().initialized().unsafeCast(to: UICellConfigurationState.self)
        let values = made.stateValues
        values.traitCollection = cell.sendTraitCollection()
        (values.selected, values.highlighted) = (selected, highlighted)
        return made
    }
}

/// The cells whose configuration is to be updated in their next layout.
enum CellConfigurations {
    nonisolated(unsafe) private static var pending: Set<UnsafeMutableRawPointer> = []

    /// Asks for the cell's configuration to be updated in its next layout.
    static func setNeeded(_ cell: UIView) {
        pending.insert(cell.objcObject)
        cell.setNeedsLayout()
    }

    static func forget(_ cell: UIView) { pending.remove(cell.objcObject) }

    /// Updates the cell's configuration if it was asked for.
    static func updateIfNeeded(_ cell: UIView, selected: Bool, highlighted: Bool) {
        guard pending.remove(cell.objcObject) != nil else { return }
        let state = UICellConfigurationState.of(cell, selected: selected, highlighted: highlighted)
        withExtendedLifetime(state) {
            cell.sendUpdateConfiguration(using: state)
            if cell.responds(to: "_bridgedUpdateConfigurationUsingState:") { cell.sendBridgedUpdateConfiguration(using: state) }
        }
    }
}

extension NSObject {
    @ObjCMethod("traitCollection") func sendTraitCollection() -> UITraitCollection?
    @ObjCMethod("updateConfigurationUsingState:") func sendUpdateConfiguration(using state: NSObject?)
    @ObjCMethod("_bridgedUpdateConfigurationUsingState:") func sendBridgedUpdateConfiguration(using state: NSObject?)
}

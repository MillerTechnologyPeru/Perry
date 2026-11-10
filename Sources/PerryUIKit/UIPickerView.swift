import CPerryGeometry
import PerryObjCInterop

// UIPickerView: wheels of rows. Nothing draws the wheels yet; the view
// keeps its data source, delegate and selected rows, so a program that
// makes one runs.

final class PickerViewState: ObjectState {
    var dataSource: UnsafeMutableRawPointer?
    var delegate: UnsafeMutableRawPointer?
    var selected: [Int: Int] = [:]
}

@ObjCClass("UIPickerView")
open class UIPickerView: UIView {
    static let pickerStates = StateTable<PickerViewState>()
    var picker: PickerViewState { UIPickerView.pickerStates[objcObject] }

    @ObjCMethod("dealloc")
    override func dealloc() {
        UIPickerView.pickerStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCMethod("dataSource") func dataSource() -> NSObject? { picker.dataSource.map { NSObject($0) } }
    @ObjCMethod("setDataSource:") func setDataSource(_ source: NSObject?) { picker.dataSource = source?.objcObject }
    @ObjCMethod("delegate") func pickerDelegate() -> NSObject? { picker.delegate.map { NSObject($0) } }
    @ObjCMethod("setDelegate:") func setPickerDelegate(_ delegate: NSObject?) { picker.delegate = delegate?.objcObject }

    /// Nothing asks the data source: no wheel is drawn.
    @ObjCMethod("numberOfComponents") func numberOfComponents() -> Int { 0 }
    @ObjCMethod("numberOfRowsInComponent:") func numberOfRows(inComponent component: Int) -> Int { 0 }
    @ObjCMethod("selectedRowInComponent:") func selectedRow(inComponent component: Int) -> Int { picker.selected[component] ?? 0 }
    @ObjCMethod("selectRow:inComponent:animated:")
    func selectRow(_ row: Int, inComponent component: Int, animated: Bool) { picker.selected[component] = row }
    @ObjCMethod("reloadAllComponents") func reloadAllComponents() {}
    @ObjCMethod("reloadComponent:") func reloadComponent(_ component: Int) {}
    @ObjCMethod("showsSelectionIndicator") func showsSelectionIndicator() -> Bool { true }
    @ObjCMethod("setShowsSelectionIndicator:") func setShowsSelectionIndicator(_ shows: Bool) {}
}

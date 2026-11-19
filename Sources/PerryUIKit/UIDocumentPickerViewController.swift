import PerryObjCInterop

// UIDocumentPickerViewController, the Files picker. There are no document
// providers here to browse, so a picker keeps what it was made with and,
// once shown, closes again and tells its delegate it was cancelled, as when
// the user taps Cancel.

final class DocumentPickerState: ObjectState {
    /// Not retained, as UIKit's delegate is weak.
    var delegate: UnsafeMutableRawPointer?
    var allowsMultipleSelection = false
    var shouldShowFileExtensions = false
    /// Retained.
    var directoryURL: NSObject?
    var cancelled = false
}

@ObjCClass("UIDocumentPickerViewController")
open class UIDocumentPickerViewController: UIViewController {
    static let pickerStates = StateTable<DocumentPickerState>()
    var picker: DocumentPickerState { UIDocumentPickerViewController.pickerStates[objcObject] }

    @ObjCMethod("dealloc")
    override func dealloc() {
        UIDocumentPickerViewController.pickerStates.remove(objcObject)
        super.dealloc()
    }

    /// Each initializer is UIViewController's, as a super call.
    private func initializePicker() -> NSObject { initialize(nibName: nil, bundle: nil) }

    @ObjCMethod("initForOpeningContentTypes:") func initialize(openingContentTypes types: NSObject?) -> NSObject { initializePicker() }
    @ObjCMethod("initForOpeningContentTypes:asCopy:")
    func initialize(openingContentTypes types: NSObject?, asCopy: Bool) -> NSObject { initializePicker() }
    @ObjCMethod("initForExportingURLs:") func initialize(exportingURLs urls: NSObject?) -> NSObject { initializePicker() }
    @ObjCMethod("initForExportingURLs:asCopy:")
    func initialize(exportingURLs urls: NSObject?, asCopy: Bool) -> NSObject { initializePicker() }
    @ObjCMethod("initWithDocumentTypes:inMode:")
    func initialize(documentTypes types: NSObject?, mode: UInt) -> NSObject { initializePicker() }
    @ObjCMethod("initWithURL:inMode:") func initialize(url: NSObject?, mode: UInt) -> NSObject { initializePicker() }
    @ObjCMethod("initWithURLs:inMode:") func initialize(urls: NSObject?, mode: UInt) -> NSObject { initializePicker() }

    @ObjCMethod("delegate") func delegate() -> NSObject? { picker.delegate.map { NSObject($0) } }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { picker.delegate = delegate?.objcObject }
    @ObjCMethod("allowsMultipleSelection") func allowsMultipleSelection() -> Bool { picker.allowsMultipleSelection }
    @ObjCMethod("setAllowsMultipleSelection:") func setAllowsMultipleSelection(_ allows: Bool) { picker.allowsMultipleSelection = allows }
    @ObjCMethod("shouldShowFileExtensions") func shouldShowFileExtensions() -> Bool { picker.shouldShowFileExtensions }
    @ObjCMethod("setShouldShowFileExtensions:") func setShouldShowFileExtensions(_ shows: Bool) { picker.shouldShowFileExtensions = shows }
    @ObjCMethod("directoryURL") func directoryURL() -> NSObject? { picker.directoryURL }
    @ObjCMethod("setDirectoryURL:") func setDirectoryURL(_ url: NSObject?) { picker.directoryURL = url }

    /// Nothing to pick: the picker closes and its delegate hears it was
    /// cancelled, once.
    @ObjCMethod("viewDidAppear:")
    override func viewDidAppear(_ animated: Bool) {
        guard !picker.cancelled else { return }
        picker.cancelled = true
        sendDismiss(animated: false, completion: nil)
        if let delegate = picker.delegate.map({ NSObject($0) }), delegate.responds(to: "documentPickerWasCancelled:") {
            delegate.sendDocumentPickerWasCancelled(self)
        }
    }
}

extension NSObject {
    @ObjCMethod("documentPickerWasCancelled:") func sendDocumentPickerWasCancelled(_ picker: NSObject)
    @ObjCMethod("dismissViewControllerAnimated:completion:") func sendDismiss(animated: Bool, completion: NSObject?)
}

import CPerryGeometry
import Glibc
import PerryObjCInterop

// The document architecture: NSDocument, a file's model and its windows, and
// NSDocumentController, which makes and keeps an app's documents from the
// document types its Info.plist declares (CFBundleDocumentTypes: type name,
// extensions, NSDocumentClass). Documents read and write through the
// subclass's readFromData:ofType:error: and dataOfType:error: (or the URL
// forms), show in the windows controllers its makeWindowControllers makes
// (by default one loading windowNibName with the document as owner), and
// are untitled until saved. There is no file browser here (the panels answer
// Cancel), so saving an untitled document, and Open..., do nothing; files
// to open at launch come from PERRY_APPKIT_OPEN, paths joined by ":".

@ObjCWrapper("NSData")
class DocumentData: NSObject {
    @ObjCClassMethod("dataWithContentsOfFile:") static func contents(ofFile path: String) -> DocumentData?
    @ObjCMethod("writeToFile:atomically:") func write(toFile path: String, atomically: Bool) -> Bool
}

@ObjCWrapper("NSURL")
class DocumentURL: NSObject {
    @ObjCClassMethod("fileURLWithPath:") static func make(path: String) -> DocumentURL?
    @ObjCMethod("path") func path() -> String?
    @ObjCMethod("lastPathComponent") func lastPathComponent() -> String?
    @ObjCMethod("pathExtension") func pathExtension() -> String?
}

@ObjCWrapper("NSError")
class DocumentError: NSObject {
    @ObjCClassMethod("errorWithDomain:code:userInfo:") static func make(domain: String, code: Int, userInfo: NSObject?) -> DocumentError
}

extension NSObject {
    @ObjCMethod("readFromData:ofType:error:")
    func sendReadFromData(_ data: NSObject?, _ type: String?, _ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool
    @ObjCMethod("dataOfType:error:")
    func sendDataOfType(_ type: String?, _ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> NSObject?
    @ObjCMethod("readFromURL:ofType:error:")
    func sendReadFromURL(_ url: NSObject?, _ type: String?, _ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool
    @ObjCMethod("writeToURL:ofType:error:")
    func sendWriteToURL(_ url: NSObject?, _ type: String?, _ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool
    @ObjCMethod("initWithType:error:")
    func sendInitWithType(_ type: String?, _ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> NSObject?
    @ObjCMethod("makeWindowControllers") func sendMakeWindowControllers()
    @ObjCMethod("showWindows") func sendShowWindows()
    @ObjCMethod("windowControllerDidLoadNib:") func sendWindowControllerDidLoadNib(_ controller: NSObject?)
    @ObjCMethod("windowControllerWillLoadNib:") func sendWindowControllerWillLoadNib(_ controller: NSObject?)
    @ObjCMethod("addWindowController:") func sendAddWindowController(_ controller: NSObject?)
    @ObjCMethod("windowNibName") func sendWindowNibName() -> String?
}

/// A document type from the Info.plist.
struct DocumentType {
    var name: String
    var extensions: [String]
    var className: String
    var role: String
}

@ObjCClass("NSDocument")
open class NSDocument: NSObject {
    var fileURL: NSObject?
    var fileType: String?
    var customDisplayName: String?
    var changeCount = 0
    var controllers: [NSWindowController] = []
    var undoManager: NSObject?
    var draft = false
    var closed = false

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithType:error:")
    public required init(type: String?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) {
        fileType = type
        super.init()
    }

    // MARK: Class properties

    @ObjCClassMethod("autosavesInPlace") class func autosavesInPlace() -> Bool { false }
    @ObjCClassMethod("autosavesDrafts") class func autosavesDrafts() -> Bool { false }
    @ObjCClassMethod("preservesVersions") class func preservesVersions() -> Bool { false }
    @ObjCClassMethod("canConcurrentlyReadDocumentsOfType:") class func canConcurrentlyRead(ofType type: String?) -> Bool { false }
    @ObjCClassMethod("isNativeType:") class func isNativeType(_ type: String?) -> Bool { true }
    @ObjCClassMethod("readableTypes") class func readableTypes() -> NSObject { Documents.types(className: className()) }
    @ObjCClassMethod("writableTypes") class func writableTypes() -> NSObject { Documents.types(className: className()) }
    private class func className() -> String { objCClassName }

    // MARK: Properties

    @ObjCMethod("fileURL") func documentFileURL() -> NSObject? { fileURL }
    @ObjCMethod("setFileURL:") func setFileURL(_ url: NSObject?) { fileURL = url }
    @ObjCMethod("fileType") func documentFileType() -> String? { fileType }
    @ObjCMethod("setFileType:") func setFileType(_ type: String?) { fileType = type }
    @ObjCMethod("fileModificationDate") func fileModificationDate() -> NSObject? { nil }
    @ObjCMethod("setFileModificationDate:") func setFileModificationDate(_ date: NSObject?) {}
    @ObjCMethod("displayName") func displayName() -> String {
        if let customDisplayName { return customDisplayName }
        if let name = (fileURL.map { $0.unsafeCast(to: DocumentURL.self) })?.lastPathComponent() { return name }
        return "Untitled"
    }
    @ObjCMethod("setDisplayName:") func setDisplayName(_ name: String?) { customDisplayName = name }
    @ObjCMethod("isDraft") func isDraft() -> Bool { draft }
    @ObjCMethod("setDraft:") func setDraft(_ value: Bool) { draft = value }
    @ObjCMethod("isInViewingMode") func isInViewingMode() -> Bool { false }
    @ObjCMethod("isEntireFileLoaded") func isEntireFileLoaded() -> Bool { true }
    @ObjCMethod("autosavingFileType") func autosavingFileType() -> String? { fileType }
    @ObjCMethod("autosavesInPlace") func instanceAutosavesInPlace() -> Bool { Send.bool(ObjCRuntime.classObject(type(of: self).objCClassName), "autosavesInPlace") }
    @ObjCMethod("hasUnautosavedChanges") func hasUnautosavedChanges() -> Bool { changeCount != 0 }
    @ObjCMethod("isDocumentEdited") func isDocumentEdited() -> Bool { changeCount != 0 }
    @ObjCMethod("updateChangeCount:") func updateChangeCount(_ change: Int) {
        // NSChangeDone 0, NSChangeUndone 1, NSChangeCleared 2.
        switch change {
        case 0: changeCount += 1
        case 1: changeCount = max(changeCount - 1, 0)
        case 2: changeCount = 0
        default: break
        }
    }
    @ObjCMethod("undoManager") func documentUndoManager() -> NSObject? {
        if undoManager == nil {
            undoManager = Send.object(Send.object(ObjCRuntime.classObject("NSUndoManager"), "alloc"), "init").map(NSObject.init)
        }
        return undoManager
    }
    @ObjCMethod("setUndoManager:") func setUndoManager(_ manager: NSObject?) { undoManager = manager }
    @ObjCMethod("hasUndoManager") func hasUndoManager() -> Bool { true }
    @ObjCMethod("setHasUndoManager:") func setHasUndoManager(_ value: Bool) {}
    @ObjCMethod("printInfo") func printInfo() -> NSObject? { nil }
    @ObjCMethod("setPrintInfo:") func setPrintInfo(_ info: NSObject?) {}

    // MARK: Windows

    @ObjCMethod("windowNibName") func windowNibName() -> String? { nil }
    @ObjCMethod("windowControllers") func windowControllers() -> NSObject { NSMutableArray.of(controllers.map { NSObject($0.objcObject) }) }
    @ObjCMethod("addWindowController:") func addWindowController(_ controller: NSObject?) {
        guard let controller = controller?.as(NSWindowController.self), !controllers.contains(where: { $0 === controller }) else { return }
        controllers.append(controller)
        if controller.document !== self { controller.document = self }
    }
    @ObjCMethod("removeWindowController:") func removeWindowController(_ controller: NSObject?) {
        guard let controller = controller?.as(NSWindowController.self) else { return }
        controllers.removeAll { $0 === controller }
        if controller.document === self { controller.document = nil }
    }
    @ObjCMethod("makeWindowControllers") func makeWindowControllers() {
        let nibName = self.sendWindowNibName()
        Trace.log("documents: makeWindowControllers nib \(nibName ?? "nil")")
        guard let name = nibName else { return }
        let cls = ObjCRuntime.classObject("NSWindowController")
        let controller = Send.object(cls, "alloc").flatMap { allocated in
            typealias F = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
            return unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(allocated, ObjCRuntime.selector("initWithWindowNibName:owner:"), name.objCArgument(), objcObject)
        }
        Trace.log("documents: nib \(name), controller \(controller.map { "\($0)" } ?? "nil")")
        if let controller { Send.void(objcObject, "addWindowController:", controller) }
    }
    @ObjCMethod("showWindows") func showWindows() {
        for controller in controllers { Send.void(controller.objcObject, "showWindow:", objcObject) }
    }
    @ObjCMethod("windowForSheet") func windowForSheet() -> NSWindow? { controllers.compactMap { $0.window }.first }
    @ObjCMethod("windowControllerWillLoadNib:") func windowControllerWillLoadNib(_ controller: NSObject?) {}
    @ObjCMethod("windowControllerDidLoadNib:") func windowControllerDidLoadNib(_ controller: NSObject?) {}
    @ObjCMethod("setWindow:") func setWindow(_ window: NSWindow?) {}

    // MARK: Reading and writing

    @ObjCMethod("readFromURL:ofType:error:")
    func read(from url: NSObject?, type: String?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        guard let path = url?.unsafeCast(to: DocumentURL.self).path(), let data = DocumentData.contents(ofFile: path) else {
            // NSFileReadNoSuchFileError.
            error?.pointee = DocumentError.make(domain: "NSCocoaErrorDomain", code: 260, userInfo: nil).objcObject
            return false
        }
        return self.sendReadFromData(data, type, error)
    }

    @ObjCMethod("readFromData:ofType:error:")
    func read(fromData data: NSObject?, type: String?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        // NSFeatureUnsupportedError.
        error?.pointee = DocumentError.make(domain: "NSCocoaErrorDomain", code: 3328, userInfo: nil).objcObject
        return false
    }

    @ObjCMethod("dataOfType:error:")
    func data(ofType type: String?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> NSObject? {
        error?.pointee = DocumentError.make(domain: "NSCocoaErrorDomain", code: 3328, userInfo: nil).objcObject
        return nil
    }

    @ObjCMethod("writeToURL:ofType:error:")
    func write(to url: NSObject?, type: String?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        guard let data = self.sendDataOfType(type, error), let path = url?.unsafeCast(to: DocumentURL.self).path() else { return false }
        guard data.unsafeCast(to: DocumentData.self).write(toFile: path, atomically: true) else {
            // NSFileWriteUnknownError.
            error?.pointee = DocumentError.make(domain: "NSCocoaErrorDomain", code: 512, userInfo: nil).objcObject
            return false
        }
        return true
    }

    @ObjCMethod("prepareSavePanel:") func prepareSavePanel(_ panel: NSObject?) -> Bool { true }

    /// Saves to the file the document has; an untitled one has none and, with
    /// no file browser, stays unsaved.
    @ObjCMethod("saveDocument:") func saveDocument(_ sender: NSObject?) {
        guard let url = fileURL else {
            appKitWarning("NSDocument: \(displayName()) is untitled, and there is no file browser to name it")
            return
        }
        var error: UnsafeMutableRawPointer?
        if self.sendWriteToURL(url, fileType, &error) { changeCount = 0 }
    }
    @ObjCMethod("saveDocumentAs:") func saveDocumentAs(_ sender: NSObject?) { saveDocument(sender) }
    @ObjCMethod("saveToURL:ofType:forSaveOperation:completionHandler:")
    func save(to url: NSObject?, type: String?, operation: Int, completionHandler: ObjCBlock?) {
        var error: UnsafeMutableRawPointer?
        let saved = self.sendWriteToURL(url, type, &error)
        if saved, operation != 3 { changeCount = 0 }
        if let completionHandler {
            Dispatch.onMain {
                typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?) -> Void
                completionHandler.function(as: Invoke.self)(completionHandler.object, error)
            }
        }
    }
    @ObjCMethod("revertDocumentToSaved:") func revertDocumentToSaved(_ sender: NSObject?) {}
    @ObjCMethod("validateUserInterfaceItem:") func validateUserInterfaceItem(_ item: NSObject?) -> Bool { true }

    // MARK: Closing

    @ObjCMethod("canCloseDocumentWithDelegate:shouldCloseSelector:contextInfo:")
    func canClose(delegate: NSObject?, shouldCloseSelector: ObjCSelector?, contextInfo: UnsafeMutableRawPointer?) {
        guard let delegate, let selector = shouldCloseSelector else { return }
        typealias F = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, UnsafeMutableRawPointer, Bool, UnsafeMutableRawPointer?) -> Void
        unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(delegate.objcObject, selector.pointer, objcObject, true, contextInfo)
    }

    @ObjCMethod("close") func close() {
        guard !closed else { return }
        closed = true
        for controller in controllers {
            controller.document = nil
            controller.window.map { Send.void($0.objcObject, "close") }
        }
        controllers = []
        NSDocumentController.shared().remove(self)
    }
}

enum Documents {
    /// The Info.plist's document types.
    nonisolated(unsafe) static var declared: [DocumentType] = {
        guard let types = NSBundle.main().infoObject(forKey: "CFBundleDocumentTypes")?.as(NSArray.self) else { return [] }
        return types.elements.compactMap { entry in
            guard let entry = entry.as(NSDictionary.self) else { return nil }
            func string(_ key: String) -> String? { entry.object(forKeyObject: key.objCObject)?.stringValue }
            let extensions = (entry.object(forKeyObject: "CFBundleTypeExtensions".objCObject)?.as(NSArray.self)?.elements ?? []).map(\.stringValue)
            return DocumentType(name: string("CFBundleTypeName") ?? "", extensions: extensions,
                                className: string("NSDocumentClass") ?? "", role: string("CFBundleTypeRole") ?? "")
        }
    }()

    /// The names of the types a document class handles.
    static func types(className: String) -> NSObject {
        NSMutableArray.of(declared.filter { $0.className == className || className == "NSDocument" }.map { $0.name.objCObject })
    }
}

extension String {
    /// An NSString of the string, as an object.
    var objCObject: NSObject { NSObject(objCArgument()!) }
}

@ObjCClass("NSDocumentController")
open class NSDocumentController: NSObject {
    nonisolated(unsafe) static var sharedController: NSDocumentController?
    var documents: [NSDocument] = []
    var current: NSDocument?
    var recent: [NSObject] = []

    @ObjCMethod("init")
    public required override init() {
        super.init()
        if NSDocumentController.sharedController == nil { NSDocumentController.sharedController = self }
    }

    @ObjCClassMethod("sharedDocumentController")
    static func shared() -> NSDocumentController {
        if let controller = sharedController { return controller }
        return NSDocumentController.objCClass.object.newInstance().unsafeCast(to: NSDocumentController.self)
    }

    func remove(_ document: NSDocument) {
        documents.removeAll { $0 === document }
        if current === document { current = documents.last }
    }

    @ObjCMethod("documents") func allDocuments() -> NSObject { NSMutableArray.of(documents.map { NSObject($0.objcObject) }) }
    @ObjCMethod("currentDocument") func currentDocument() -> NSObject? { (current ?? documents.last).map { NSObject($0.objcObject) } }
    @ObjCMethod("addDocument:") func addDocument(_ document: NSObject?) {
        guard let document = document?.as(NSDocument.self), !documents.contains(where: { $0 === document }) else { return }
        documents.append(document)
        current = document
    }
    @ObjCMethod("removeDocument:") func removeDocument(_ document: NSObject?) { document?.as(NSDocument.self).map { remove($0) } }
    @ObjCMethod("hasEditedDocuments") func hasEditedDocuments() -> Bool { documents.contains { $0.changeCount != 0 } }
    @ObjCMethod("documentForURL:") func document(for url: NSObject?) -> NSObject? {
        guard let path = url?.unsafeCast(to: DocumentURL.self).path() else { return nil }
        return documents.first { ($0.fileURL?.unsafeCast(to: DocumentURL.self).path()) == path }.map { NSObject($0.objcObject) }
    }
    @ObjCMethod("documentForWindow:") func document(forWindow window: NSObject?) -> NSObject? {
        documents.first { $0.controllers.contains { $0.window?.objcObject == window?.objcObject } }.map { NSObject($0.objcObject) }
    }

    // MARK: Types

    @ObjCMethod("defaultType") func defaultType() -> String? { Documents.declared.first { $0.role != "Viewer" }?.name ?? Documents.declared.first?.name }
    @ObjCMethod("documentClassNames") func documentClassNames() -> NSObject { NSMutableArray.of(Documents.declared.map { $0.className.objCObject }) }
    @ObjCMethod("displayNameForType:") func displayName(forType type: String?) -> String? { type }
    @ObjCMethod("documentClassForType:") func documentClass(forType type: String?) -> ObjCClass? {
        guard let entry = Documents.declared.first(where: { $0.name == type }) else { return nil }
        return ObjCClass(named: entry.className)
    }
    @ObjCMethod("typeForContentsOfURL:error:")
    func type(forContentsOf url: NSObject?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> String? {
        let ext = url?.unsafeCast(to: DocumentURL.self).pathExtension()?.lowercased() ?? ""
        if let match = Documents.declared.first(where: { $0.extensions.contains { $0.lowercased() == ext } }) { return match.name }
        if let any = defaultType() { return any }
        // NSFileReadUnknownError.
        error?.pointee = DocumentError.make(domain: "NSCocoaErrorDomain", code: 256, userInfo: nil).objcObject
        return nil
    }

    // MARK: Making and opening

    @ObjCMethod("makeUntitledDocumentOfType:error:")
    func makeUntitledDocument(ofType type: String?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> NSObject? {
        guard let cls = documentClass(forType: type) else {
            // NSFileReadUnknownError.
            error?.pointee = DocumentError.make(domain: "NSCocoaErrorDomain", code: 256, userInfo: nil).objcObject
            return nil
        }
        let allocated = Send.object(cls.pointer, "alloc")
        return allocated.flatMap { NSObject($0).sendInitWithType(type, error) }
    }

    @ObjCMethod("makeDocumentWithContentsOfURL:ofType:error:")
    func makeDocument(contentsOf url: NSObject?, type: String?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> NSObject? {
        guard let cls = documentClass(forType: type) else {
            error?.pointee = DocumentError.make(domain: "NSCocoaErrorDomain", code: 256, userInfo: nil).objcObject
            return nil
        }
        guard let document = Send.object(cls.pointer, "alloc").flatMap({ Send.object($0, "init") }).map({ NSObject($0) }) else { return nil }
        document.as(NSDocument.self)?.fileType = type
        guard document.sendReadFromURL(url, type, error) else { return nil }
        document.as(NSDocument.self)?.fileURL = url
        return document
    }

    @ObjCMethod("makeDocumentForURL:withContentsOfURL:ofType:error:")
    func makeDocument(forURL url: NSObject?, contentsOf contents: NSObject?, type: String?,
                      error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> NSObject? {
        makeDocument(contentsOf: contents ?? url, type: type, error: error)
    }

    /// Adds the document and, to display it, makes its windows and shows them.
    func present(_ document: NSObject, display: Bool) {
        addDocument(document)
        Trace.log("documents: presenting \(document) display \(display)")
        guard display else { return }
        document.sendMakeWindowControllers()
        Trace.log("documents: \(document.as(NSDocument.self)?.controllers.count ?? -1) window controllers")
        document.sendShowWindows()
    }

    @ObjCMethod("openUntitledDocumentAndDisplay:error:")
    func openUntitledDocument(display: Bool, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> NSObject? {
        guard let type = defaultType(), let document = makeUntitledDocument(ofType: type, error: error) else { return nil }
        document.as(NSDocument.self)?.draft = true
        present(document, display: display)
        return document
    }

    @ObjCMethod("openDocumentWithContentsOfURL:display:error:")
    func openDocument(contentsOf url: NSObject?, display: Bool, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> NSObject? {
        if let open = document(for: url) {
            if display { open.sendShowWindows() }
            return open
        }
        guard let type = type(forContentsOf: url, error: error),
              let document = makeDocument(contentsOf: url, type: type, error: error) else { return nil }
        present(document, display: display)
        noteNewRecentDocumentURL(url)
        return document
    }

    @ObjCMethod("openDocumentWithContentsOfURL:display:completionHandler:")
    func openDocument(contentsOf url: NSObject?, display: Bool, completionHandler: ObjCBlock?) {
        var error: UnsafeMutableRawPointer?
        let document = openDocument(contentsOf: url, display: display, error: &error)
        guard let completionHandler else { return }
        let alreadyOpen = false
        Dispatch.onMain {
            typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, Bool, UnsafeMutableRawPointer?) -> Void
            completionHandler.function(as: Invoke.self)(completionHandler.object, document?.objcObject, alreadyOpen, error)
        }
    }

    @ObjCMethod("openUntitledDocumentOfType:display:") func openUntitledDocument(ofType type: String?, display: Bool) -> NSObject? {
        guard let document = makeUntitledDocument(ofType: type, error: nil) else { return nil }
        present(document, display: display)
        return document
    }

    @ObjCMethod("newDocument:") func newDocument(_ sender: NSObject?) {
        var error: UnsafeMutableRawPointer?
        _ = openUntitledDocument(display: true, error: &error)
    }

    /// No file browser, so the open panel answers Cancel.
    @ObjCMethod("openDocument:") func openDocument(_ sender: NSObject?) {
        appKitWarning("NSDocumentController: no file browser here; Open does nothing")
    }

    @ObjCMethod("saveAllDocuments:") func saveAllDocuments(_ sender: NSObject?) {
        for document in documents { document.saveDocument(sender) }
    }
    @ObjCMethod("closeAllDocumentsWithDelegate:didCloseAllSelector:contextInfo:")
    func closeAll(delegate: NSObject?, didCloseAllSelector: ObjCSelector?, contextInfo: UnsafeMutableRawPointer?) {
        for document in documents { document.close() }
    }
    @ObjCMethod("reviewUnsavedDocumentsWithAlertTitle:cancellable:delegate:didReviewAllSelector:contextInfo:")
    func reviewUnsaved(title: String?, cancellable: Bool, delegate: NSObject?, selector: ObjCSelector?, contextInfo: UnsafeMutableRawPointer?) {
        guard let delegate, let selector else { return }
        typealias F = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, UnsafeMutableRawPointer, Bool, UnsafeMutableRawPointer?) -> Void
        unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(delegate.objcObject, selector.pointer, objcObject, true, contextInfo)
    }

    // MARK: Recent documents

    @ObjCMethod("noteNewRecentDocumentURL:") func noteNewRecentDocumentURL(_ url: NSObject?) {
        guard let url else { return }
        recent.removeAll { $0.objcObject == url.objcObject }
        recent.insert(url, at: 0)
    }
    @ObjCMethod("noteNewRecentDocument:") func noteNewRecentDocument(_ document: NSObject?) { noteNewRecentDocumentURL(document?.as(NSDocument.self)?.fileURL) }
    @ObjCMethod("recentDocumentURLs") func recentDocumentURLs() -> NSObject { NSMutableArray.of(recent) }
    @ObjCMethod("clearRecentDocuments:") func clearRecentDocuments(_ sender: NSObject?) { recent = [] }
    @ObjCMethod("maximumRecentDocumentCount") func maximumRecentDocumentCount() -> Int { 10 }
    @ObjCMethod("validateUserInterfaceItem:") func validateUserInterfaceItem(_ item: NSObject?) -> Bool { true }
    @ObjCMethod("autosavingDelay") func autosavingDelay() -> Double { 0 }
    @ObjCMethod("setAutosavingDelay:") func setAutosavingDelay(_ delay: Double) {}
    @ObjCMethod("currentDirectory") func currentDirectory() -> String? { nil }

    // MARK: Launching

    /// What an app with document types does when it finishes launching: opens
    /// the files named in PERRY_APPKIT_OPEN or, unless the delegate declines,
    /// an untitled document.
    static func openAtLaunch(delegate: UnsafeMutableRawPointer?) {
        Trace.log("documents: \(Documents.declared.count) types \(Documents.declared.map(\.name))")
        guard !Documents.declared.isEmpty else { return }
        let controller = shared()
        if let list = getenv("PERRY_APPKIT_OPEN").map({ String(cString: $0) }), !list.isEmpty {
            for path in list.split(separator: ":") {
                var error: UnsafeMutableRawPointer?
                _ = controller.openDocument(contentsOf: DocumentURL.make(path: String(path)).map { NSObject($0.objcObject) }, display: true, error: &error)
            }
        }
        guard controller.documents.isEmpty else { return }
        if Send.responds(delegate, "applicationShouldOpenUntitledFile:"),
           !Send.bool(delegate, "applicationShouldOpenUntitledFile:", App.shared?.objcObject) { return }
        if Send.responds(delegate, "applicationOpenUntitledFile:") {
            _ = Send.bool(delegate, "applicationOpenUntitledFile:", App.shared?.objcObject)
            return
        }
        var error: UnsafeMutableRawPointer?
        _ = controller.openUntitledDocument(display: true, error: &error)
    }
}

/// The application forwards the document actions, as it is in their
/// responder chain.
@ObjCCategory("NSDocumentActions")
extension NSApplication {
    @ObjCMethod("newDocument:") func newDocument(_ sender: NSObject?) { NSDocumentController.shared().newDocument(sender) }
    @ObjCMethod("openDocument:") func openDocument(_ sender: NSObject?) { NSDocumentController.shared().openDocument(sender) }
}

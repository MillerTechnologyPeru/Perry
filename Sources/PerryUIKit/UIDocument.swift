import Glibc
import PerryObjCInterop

// UIDocument: a document kept in a file. There is no file coordination or
// iCloud here: -openWithCompletionHandler: reads the file and hands its data
// to -loadFromContents:ofType:error:, and -saveToURL:... writes what
// -contentsForType:error: returns, when that is data. An app's subclass
// overrides those two.

final class DocumentState: ObjectState {
    var fileURL: NSObject?
    var hasUnsavedChanges = false
    var isClosed = true
}

@ObjCClass("UIDocument")
open class UIDocument: NSObject {
    static let states = StateTable<DocumentState>()
    var document: DocumentState { UIDocument.states[objcObject] }

    @ObjCMethod("initWithFileURL:")
    func initialize(fileURL: NSObject) -> Self {
        document.fileURL = fileURL
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        UIDocument.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIDocument.objCClass.pointer)
    }

    @ObjCMethod("fileURL") func fileURL() -> NSObject? { document.fileURL }

    @ObjCMethod("localizedName") func localizedName() -> String {
        (document.fileURL?.documentPath ?? "").split(separator: "/").last.map(String.init) ?? ""
    }

    @ObjCMethod("fileType") func fileType() -> String? { nil }
    @ObjCMethod("fileModificationDate") func fileModificationDate() -> NSObject? { nil }

    /// 0 is normal, 1 closed, 4 has unsaved changes.
    @ObjCMethod("documentState") func documentState() -> UInt {
        (document.isClosed ? 1 : 0) | (document.hasUnsavedChanges ? 4 : 0)
    }

    @ObjCMethod("hasUnsavedChanges") func hasUnsavedChanges() -> Bool { document.hasUnsavedChanges }

    @ObjCMethod("updateChangeCount:") func updateChangeCount(_ change: Int) {
        // UIDocumentChangeDone 0, Undone 1, Redone 2, Cleared 3.
        document.hasUnsavedChanges = change != 3
    }

    @ObjCMethod("undoManager") func undoManager() -> NSObject? { nil }

    @ObjCMethod("openWithCompletionHandler:")
    func open(completionHandler: ObjCBlock?) {
        // The file is read off the main queue, as UIDocument does (an app's
        // reading code may insist on it), and the completion runs on main.
        let state = document
        let receiver = Unmanaged.passRetained(self)
        let url = document.fileURL
        let block = completionHandler.map { Unmanaged.passRetained($0) }
        DocumentReads.run {
            let succeeded = url.map { receiver.takeUnretainedValue().sendRead(from: $0, error: nil) } ?? false
            DocumentReads.onMain {
                state.isClosed = !succeeded
                if let block { Blocks.call(block.takeRetainedValue(), succeeded) }
                receiver.release()
            }
        }
    }

    /// What -open reads with: the file's data, given to -loadFromContents.
    @ObjCMethod("readFromURL:error:")
    func read(from url: NSObject, error: UnsafeMutableRawPointer?) -> Bool {
        guard let path = url.documentPath, let data = NSData.contents(ofFile: path) else { return false }
        return sendLoad(contents: data, ofType: nil, error: error)
    }

    /// What saving writes with: the data -contentsForType returns.
    @ObjCMethod("writeContents:andAttributes:safelyToURL:forSaveOperation:error:")
    func write(contents: NSObject?, attributes: NSObject?, safelyTo url: NSObject, operation: Int,
               error: UnsafeMutableRawPointer?) -> Bool {
        guard let contents, let path = url.documentPath else { return false }
        return contents.documentWrite(toFile: path, atomically: true)
    }

    @ObjCMethod("closeWithCompletionHandler:")
    func close(completionHandler: ObjCBlock?) {
        document.isClosed = true
        completionHandler.map { Blocks.call($0, true) }
    }

    @ObjCMethod("saveToURL:forSaveOperation:completionHandler:")
    func save(to url: NSObject, operation: Int, completionHandler: ObjCBlock?) {
        var succeeded = false
        if let contents = sendContents(ofType: nil, error: nil) {
            succeeded = sendWrite(contents: contents, to: url, operation: operation, error: nil)
        }
        if succeeded { document.hasUnsavedChanges = false }
        completionHandler.map { Blocks.call($0, succeeded) }
    }

    @ObjCMethod("autosaveWithCompletionHandler:")
    func autosave(completionHandler: ObjCBlock?) {
        completionHandler.map { Blocks.call($0, true) }
    }

    @ObjCMethod("loadFromContents:ofType:error:")
    func load(contents: NSObject, ofType typeName: String?, error: UnsafeMutableRawPointer?) -> Bool { true }

    @ObjCMethod("contentsForType:error:")
    func contents(ofType typeName: String, error: UnsafeMutableRawPointer?) -> NSObject? { nil }

    @ObjCMethod("disableEditing") func disableEditing() {}
    @ObjCMethod("enableEditing") func enableEditing() {}
}

/// UIDocument's messages, sent so subclasses' overrides run.
extension NSObject {
    @ObjCMethod("loadFromContents:ofType:error:")
    func sendLoad(contents: NSObject, ofType typeName: String?, error: UnsafeMutableRawPointer?) -> Bool
    @ObjCMethod("contentsForType:error:")
    func sendContents(ofType typeName: String?, error: UnsafeMutableRawPointer?) -> NSObject?
    @ObjCMethod("readFromURL:error:")
    func sendRead(from url: NSObject, error: UnsafeMutableRawPointer?) -> Bool
    @ObjCMethod("writeContents:andAttributes:safelyToURL:forSaveOperation:error:")
    func sendWrite(contents: NSObject, attributes: NSObject? = nil, to url: NSObject, operation: Int,
                   error: UnsafeMutableRawPointer?) -> Bool
    @ObjCMethod("path") func sendPath() -> String?
    @ObjCMethod("writeToFile:atomically:") func documentWrite(toFile path: String, atomically: Bool) -> Bool
}

extension NSObject {
    var documentPath: String? { sendPath() }
}

/// Document reads run on a thread of their own, and finish on the main queue.
enum DocumentReads {
    private final class Work { let body: () -> Void; init(_ body: @escaping () -> Void) { self.body = body } }

    static func run(_ body: @escaping () -> Void) {
        var thread = pthread_t()
        let work = Unmanaged.passRetained(Work(body)).toOpaque()
        pthread_create(&thread, nil, { raw in
            Unmanaged<Work>.fromOpaque(raw!).takeRetainedValue().body()
            return nil
        }, work)
        pthread_detach(thread)
    }

    static func onMain(_ body: @escaping () -> Void) {
        let work = Unmanaged.passRetained(Work(body)).toOpaque()
        Updates.dispatchAsync(Updates.mainQueue, work) { raw in
            Unmanaged<Work>.fromOpaque(raw!).takeRetainedValue().body()
        }
    }
}

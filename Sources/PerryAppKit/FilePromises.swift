import CPerryGeometry
import PerryObjCInterop

// NSFilePromiseProvider, which writes a file promise to a pasteboard for
// a drag: the types and property lists it gives are Darwin's, so a
// subclass that adds its own types and asks its superclass for the rest
// gets what it would on a Mac. Perry's pasteboard holds text only and
// nothing receives promised files here, so no file is ever asked for.
// And NSDraggingItem, which describes one thing being dragged.

/// The pasteboard types of a file promise.
enum FilePromiseTypes {
    static let metadata = "com.apple.NSFilePromiseItemMetaData"
    static let fileName = "com.apple.pasteboard.promised-file-name"
    static let suggestedFileName = "com.apple.pasteboard.promised-suggested-file-name"
    static let contentType = "com.apple.pasteboard.promised-file-content-type"
    static let promiseID = "com.apple.pasteboard.NSFilePromiseID"
    static let all = [metadata, fileName, suggestedFileName, contentType, promiseID]
}

@ObjCClass("NSFilePromiseProvider")
open class NSFilePromiseProvider: NSObject {
    var fileType: String?
    /// Not retained.
    var delegateObject: UnsafeMutableRawPointer?
    var userInfo: NSObject?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithFileType:delegate:")
    public required init(fileType: String?, delegate: NSObject?) {
        super.init()
        self.fileType = fileType
        delegateObject = delegate?.objcObject
    }

    @ObjCMethod("fileType") func providerFileType() -> String? { fileType }
    @ObjCMethod("setFileType:") func setFileType(_ value: String?) { fileType = value }
    @ObjCMethod("delegate") func providerDelegate() -> NSObject? { delegateObject.map(NSObject.init) }
    @ObjCMethod("setDelegate:") func setDelegate(_ value: NSObject?) { delegateObject = value?.objcObject }
    @ObjCMethod("userInfo") func providerUserInfo() -> NSObject? { userInfo }
    @ObjCMethod("setUserInfo:") func setUserInfo(_ value: NSObject?) { userInfo = value }

    // MARK: NSPasteboardWriting

    @ObjCMethod("writableTypesForPasteboard:")
    func writableTypes(for pasteboard: NSObject?) -> NSObject { NSMutableArray.of(FilePromiseTypes.all.map(NSFilePromiseProvider.string)) }

    /// NSPasteboardWritingPromised (1 << 9) for the file's names, which
    /// come when a drop asks for them; nothing for the others.
    @ObjCMethod("writingOptionsForType:pasteboard:")
    func writingOptions(forType type: String?, pasteboard: NSObject?) -> UInt {
        type == FilePromiseTypes.fileName || type == FilePromiseTypes.suggestedFileName ? 1 << 9 : 0
    }

    /// The content type, alone and in the metadata dictionary; the name
    /// the delegate suggests (-filePromiseProvider:fileNameForType:); and
    /// the promise's identity, the provider's address. The file's own name
    /// comes from the drop's destination, which there is none of.
    @ObjCMethod("pasteboardPropertyListForType:")
    func pasteboardPropertyList(forType type: String?) -> NSObject? {
        switch type ?? "" {
        case FilePromiseTypes.metadata:
            let metadata = NSMutableDictionary.empty()
            if let fileType { metadata.set(NSFilePromiseProvider.string(fileType), forKey: FilePromiseTypes.contentType) }
            return metadata
        case FilePromiseTypes.contentType:
            return fileType.map(NSFilePromiseProvider.string)
        case FilePromiseTypes.suggestedFileName:
            guard let delegateObject, Send.responds(delegateObject, "filePromiseProvider:fileNameForType:") else { return nil }
            typealias FileName = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, UnsafeMutableRawPointer, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
            let name = unsafeBitCast(ObjCRuntime.msgSend, to: FileName.self)(delegateObject, ObjCRuntime.selector("filePromiseProvider:fileNameForType:"),
                                                                           objcObject, fileType?.objCArgument())
            return name.map { NSObject(objcObject: $0, ownership: .retain) }
        case FilePromiseTypes.promiseID:
            var address = UInt64(UInt(bitPattern: objcObject))
            typealias Make = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer, UnsafeRawPointer, UInt) -> UnsafeMutableRawPointer?
            let data = withUnsafeBytes(of: &address) { bytes in
                unsafeBitCast(ObjCRuntime.msgSend, to: Make.self)(Classes.named("NSData")?.pointer, ObjCRuntime.selector("dataWithBytes:length:"),
                                                               bytes.baseAddress!, UInt(bytes.count))
            }
            return data.map { NSObject(objcObject: $0, ownership: .retain) }
        default:
            return nil
        }
    }
}

@ObjCClass("NSDraggingItem")
open class NSDraggingItem: NSObject {
    var item: NSObject?
    var draggingFrame = CGRect.zero
    var imageComponentsProvider: ObjCBlock?
    var contents: NSObject?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithPasteboardWriter:")
    public required init(pasteboardWriter: NSObject?) {
        super.init()
        item = pasteboardWriter
    }

    @ObjCMethod("item") func draggedItem() -> NSObject? { item }
    @ObjCMethod("draggingFrame") func itemDraggingFrame() -> CGRect { draggingFrame }
    @ObjCMethod("setDraggingFrame:") func setDraggingFrame(_ value: CGRect) { draggingFrame = value }
    @ObjCMethod("imageComponentsProvider") func itemImageComponentsProvider() -> ObjCBlock? { imageComponentsProvider }
    @ObjCMethod("setImageComponentsProvider:") func setImageComponentsProvider(_ value: ObjCBlock?) { imageComponentsProvider = value }

    /// The frame, and the image (or other contents) to drag; the provider
    /// that was set goes, as on Darwin.
    @ObjCMethod("setDraggingFrame:contents:")
    func setDraggingFrame(_ frame: CGRect, contents: NSObject?) {
        draggingFrame = frame
        self.contents = contents
        imageComponentsProvider = nil
    }

    /// What the provider gives. Contents set with the frame would be one
    /// icon component, but there are no dragging image components here.
    @ObjCMethod("imageComponents")
    func imageComponents() -> NSObject? {
        guard let imageComponentsProvider else { return nil }
        typealias Provide = @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?
        return imageComponentsProvider.function(as: Provide.self)(imageComponentsProvider.object).map { NSObject(objcObject: $0, ownership: .retain) }
    }
}

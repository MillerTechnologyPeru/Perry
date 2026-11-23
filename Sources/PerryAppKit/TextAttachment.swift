import CPerryGeometry
import PerryObjCInterop

// NSTextAttachment: a file or image in attributed text, as the object
// replacement character (U+FFFC) with the attachment as its NSAttachment
// attribute. An attachment made from a file wrapper shows the file's image
// through its attachment cell, an NSTextAttachmentCell; Perry's text layout
// leaves the attachment's place empty for now.

@ObjCClass("NSTextAttachment")
open class NSTextAttachment: NSObject {
    var fileWrapper: NSObject?
    var contents: NSObject?
    var fileType: String?
    var image: NSImage?
    var bounds = CGRect.zero
    var cell: NSObject?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithFileWrapper:")
    public required init(fileWrapper: NSObject?) {
        super.init()
        self.fileWrapper = fileWrapper
    }

    @ObjCMethod("initWithData:ofType:")
    public required init(data: NSObject?, ofType type: String?) {
        super.init()
        (contents, fileType) = (data, type)
    }

    @ObjCMethod("fileWrapper") func fileWrapperObject() -> NSObject? { fileWrapper }
    @ObjCMethod("setFileWrapper:") func setFileWrapper(_ wrapper: NSObject?) { fileWrapper = wrapper; image = nil }
    @ObjCMethod("contents") func contentsObject() -> NSObject? { contents }
    @ObjCMethod("setContents:") func setContents(_ value: NSObject?) { contents = value }
    @ObjCMethod("fileType") func fileTypeString() -> String? { fileType }
    @ObjCMethod("setFileType:") func setFileType(_ value: String?) { fileType = value }
    @ObjCMethod("bounds") func attachmentBounds() -> CGRect { bounds }
    @ObjCMethod("setBounds:") func setBounds(_ value: CGRect) { bounds = value }

    /// Its image: the one set, else its file's or its contents' as an image.
    @ObjCMethod("image")
    func attachmentImage() -> NSImage? {
        if let image { return image }
        let data = contents ?? fileWrapper.flatMap { wrapper in
            Send.responds(wrapper.objcObject, "regularFileContents")
                ? Send.object(wrapper.objcObject, "regularFileContents").map(NSObject.init) : nil
        }
        guard let data else { return nil }
        image = NSImage(data: data)
        return image
    }

    @ObjCMethod("setImage:") func setImage(_ value: NSImage?) { image = value }

    /// Its cell, an NSTextAttachmentCell showing its image unless one was set.
    @ObjCMethod("attachmentCell")
    func attachmentCell() -> NSObject? {
        if cell == nil {
            let made = NSTextAttachmentCell(imageCell: attachmentImage())
            made.attachment = objcObject
            cell = made
        }
        return cell
    }

    @ObjCMethod("setAttachmentCell:")
    func setAttachmentCell(_ value: NSObject?) {
        cell = value
        if let value, Send.responds(value.objcObject, "setAttachment:") { Send.void(value.objcObject, "setAttachment:", objcObject) }
    }
}

@ObjCClass("NSTextAttachmentCell")
open class NSTextAttachmentCell: NSCell {
    /// Not retained: the attachment has its cell.
    var attachment: UnsafeMutableRawPointer?

    @ObjCMethod("attachment") func attachmentObject() -> NSObject? { attachment.map { NSObject($0) } }
    @ObjCMethod("setAttachment:") func setAttachment(_ value: NSObject?) { attachment = value?.objcObject }
    @ObjCMethod("cellSize") func attachmentCellSize() -> CGSize { image?.size ?? .zero }
    @ObjCMethod("cellBaselineOffset") func cellBaselineOffset() -> CGPoint { .zero }
    @ObjCMethod("wantsToTrackMouse") func wantsToTrackMouse() -> Bool { false }
}

/// An attributed string of one attachment, as AppKit's category on
/// NSAttributedString makes it.
@ObjCCategory("NSAttributedStringAttachmentConveniences")
extension NSAttributedString {
    @ObjCClassMethod("attributedStringWithAttachment:")
    static func make(_ cls: ObjCClass, attachment: NSObject?) -> NSObject? {
        typealias Dictionary = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeMutableRawPointer?,
                                               UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
        typealias Initialize = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeMutableRawPointer?,
                                               UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
        let attributes = attachment.flatMap { attachment in
            unsafeBitCast(ObjCRuntime.msgSend, to: Dictionary.self)(
                ObjCRuntime.classObject("NSDictionary"), ObjCRuntime.selector("dictionaryWithObject:forKey:"),
                attachment.objcObject, "NSAttachment".objCArgument())
        }
        let allocated = Send.object(cls.pointer, "alloc")
        let made = unsafeBitCast(ObjCRuntime.msgSend, to: Initialize.self)(
            allocated, ObjCRuntime.selector("initWithString:attributes:"), "\u{FFFC}".objCArgument(), attributes)
        return made.map { NSObject(objCOwned: $0) }
    }
}

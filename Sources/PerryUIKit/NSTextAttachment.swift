import CPerryGeometry
import PerryObjCInterop

// NSTextAttachment: an image or file in attributed text, as the object
// replacement character with the attachment as its NSAttachment attribute.
// Perry's text layout leaves the attachment's place empty for now.

final class TextAttachmentState: ObjectState {
    var image: UIImage?
    var contents: NSObject?
    var fileType: String?
    var bounds = CGRect.zero
}

@ObjCClass("NSTextAttachment")
open class NSTextAttachment: NSObject {
    static let states = StateTable<TextAttachmentState>()
    var attachment: TextAttachmentState { NSTextAttachment.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        NSTextAttachment.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSTextAttachment.objCClass.pointer)
    }

    @ObjCMethod("initWithData:ofType:")
    func initialize(data: NSObject?, ofType type: String?) -> Self {
        (attachment.contents, attachment.fileType) = (data, type)
        return self
    }

    /// An attachment showing `image`.
    @ObjCClassMethod("textAttachmentWithImage:")
    static func make(_ cls: ObjCClass, image: UIImage) -> NSTextAttachment {
        let made = cls.object.allocated().unsafeCast(to: NSTextAttachment.self)
        made.attachment.image = image
        return made
    }

    @ObjCMethod("image") func image() -> UIImage? { attachment.image }
    @ObjCMethod("setImage:") func setImage(_ image: UIImage?) { attachment.image = image }
    @ObjCMethod("contents") func contents() -> NSObject? { attachment.contents }
    @ObjCMethod("setContents:") func setContents(_ contents: NSObject?) { attachment.contents = contents }
    @ObjCMethod("fileType") func fileType() -> String? { attachment.fileType }
    @ObjCMethod("setFileType:") func setFileType(_ type: String?) { attachment.fileType = type }
    @ObjCMethod("bounds") func bounds() -> CGRect { attachment.bounds }
    @ObjCMethod("setBounds:") func setBounds(_ bounds: CGRect) { attachment.bounds = bounds }
}

/// An attributed string of one attachment, as text attachments' category on
/// NSAttributedString makes it.
@ObjCCategory("NSAttributedStringAttachmentConveniences")
extension NSAttributedString {
    @ObjCClassMethod("attributedStringWithAttachment:")
    static func make(_ cls: ObjCClass, attachment: NSTextAttachment) -> NSObject {
        let attributes = NSDictionary.make(object: attachment, forKey: KeyInputs.NSAttachmentAttributeName)
        return cls.object.allocated().sendInitialize(string: "\u{FFFC}", attributes: attributes)
    }
}

extension NSObject {
    @ObjCMethod("initWithString:attributes:")
    func sendInitialize(string: String, attributes: NSDictionary?) -> NSObject
}

import PerryObjCInterop

// MessageUI's compose view controllers. There is no mail or message account
// here, which is what an app is told when it asks before making one; a
// controller made anyway is a navigation controller with nothing in it.

@ObjCClass("MFMailComposeViewController")
open class MFMailComposeViewController: UINavigationController {
    @ObjCClassMethod("canSendMail") static func canSendMail(_ cls: ObjCClass) -> Bool { false }

    @ObjCMethod("mailComposeDelegate") func mailComposeDelegate() -> NSObject? { nil }
    @ObjCMethod("setMailComposeDelegate:") func setMailComposeDelegate(_ delegate: NSObject?) {}
    @ObjCMethod("setSubject:") func setSubject(_ subject: NSObject?) {}
    @ObjCMethod("setToRecipients:") func setToRecipients(_ recipients: NSObject?) {}
    @ObjCMethod("setCcRecipients:") func setCcRecipients(_ recipients: NSObject?) {}
    @ObjCMethod("setBccRecipients:") func setBccRecipients(_ recipients: NSObject?) {}
    @ObjCMethod("setMessageBody:isHTML:") func setMessageBody(_ body: NSObject?, isHTML: Bool) {}
    @ObjCMethod("addAttachmentData:mimeType:fileName:") func addAttachment(data: NSObject?, mimeType: NSObject?, fileName: NSObject?) {}
    @ObjCMethod("setPreferredSendingEmailAddress:") func setPreferredSendingEmailAddress(_ address: NSObject?) {}
}

@ObjCClass("MFMessageComposeViewController")
open class MFMessageComposeViewController: UINavigationController {
    @ObjCClassMethod("canSendText") static func canSendText(_ cls: ObjCClass) -> Bool { false }
    @ObjCClassMethod("canSendSubject") static func canSendSubject(_ cls: ObjCClass) -> Bool { false }
    @ObjCClassMethod("canSendAttachments") static func canSendAttachments(_ cls: ObjCClass) -> Bool { false }

    @ObjCMethod("messageComposeDelegate") func messageComposeDelegate() -> NSObject? { nil }
    @ObjCMethod("setMessageComposeDelegate:") func setMessageComposeDelegate(_ delegate: NSObject?) {}
    @ObjCMethod("setRecipients:") func setRecipients(_ recipients: NSObject?) {}
    @ObjCMethod("setBody:") func setBody(_ body: NSObject?) {}
    @ObjCMethod("setSubject:") func setSubject(_ subject: NSObject?) {}
}

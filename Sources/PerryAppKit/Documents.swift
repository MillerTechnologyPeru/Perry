import PerryObjCInterop

// What legacy document-based Mac apps ask of NSDocument beyond its core, and
// the constants their printing and web views use.

@ObjCConstants
enum DocumentConstants {
    static let NSPrintJobDisposition = "NSPrintJobDisposition"
    static let NSPrintSaveJob = "NSPrintSaveJob"
    static let NSPrintJobSavingURL = "NSJobSavingURL"
    static let WebActionNavigationTypeKey = "WebActionNavigationTypeKey"
}

@ObjCCategory("LegacyDocuments")
extension NSDocument {
    @ObjCMethod("presentedItemURL") func presentedItemURL() -> NSObject? { Send.object(objcObject, "fileURL").map(NSObject.init) }
    @ObjCMethod("autosavedContentsFileURL") func autosavedContentsFileURL() -> NSObject? { nil }
    @ObjCMethod("isLocked") func isLocked() -> Bool { false }
    @ObjCMethod("saveDocumentTo:") func saveDocumentTo(_ sender: NSObject?) { Send.void(objcObject, "saveDocumentAs:", sender?.objcObject) }
    @ObjCMethod("runPageLayout:") func runPageLayout(_ sender: NSObject?) {}
    @ObjCMethod("printDocument:") func printDocument(_ sender: NSObject?) {}
}

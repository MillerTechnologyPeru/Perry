import PerryObjCInterop

// UIActivityViewController, the share sheet, and
// UIDocumentBrowserViewController, the Files browser. Neither has anything
// to show here: they are view controllers with empty views, which keep what
// they were given, so that an app's subclasses of them exist.

@ObjCClass("UIActivityViewController")
open class UIActivityViewController: UIViewController {
    @ObjCMethod("initWithActivityItems:applicationActivities:")
    func initialize(activityItems: NSObject?, applicationActivities: NSObject?) -> NSObject { initialized() }

    @ObjCMethod("completionWithItemsHandler") func completionWithItemsHandler() -> NSObject? { nil }
    @ObjCMethod("setCompletionWithItemsHandler:") func setCompletionWithItemsHandler(_ handler: NSObject?) {}
    @ObjCMethod("completionHandler") func completionHandler() -> NSObject? { nil }
    @ObjCMethod("setCompletionHandler:") func setCompletionHandler(_ handler: NSObject?) {}
    @ObjCMethod("excludedActivityTypes") func excludedActivityTypes() -> NSObject? { nil }
    @ObjCMethod("setExcludedActivityTypes:") func setExcludedActivityTypes(_ types: NSObject?) {}
    @ObjCMethod("allowsProminentActivity") func allowsProminentActivity() -> Bool { true }
    @ObjCMethod("setAllowsProminentActivity:") func setAllowsProminentActivity(_ allows: Bool) {}
}

@ObjCClass("UIDocumentBrowserViewController")
open class UIDocumentBrowserViewController: UIViewController {
    @ObjCMethod("initForOpeningContentTypes:")
    func initialize(openingContentTypes: NSObject?) -> NSObject { initialized() }

    @ObjCMethod("initForOpeningFilesWithContentTypes:")
    func initialize(openingFilesWithContentTypes: NSObject?) -> NSObject { initialized() }

    @ObjCMethod("delegate") func browserDelegate() -> NSObject? { nil }
    @ObjCMethod("setDelegate:") func setBrowserDelegate(_ delegate: NSObject?) {}
    @ObjCMethod("allowsDocumentCreation") func allowsDocumentCreation() -> Bool { false }
    @ObjCMethod("setAllowsDocumentCreation:") func setAllowsDocumentCreation(_ allows: Bool) {}
    @ObjCMethod("allowsPickingMultipleItems") func allowsPickingMultipleItems() -> Bool { false }
    @ObjCMethod("setAllowsPickingMultipleItems:") func setAllowsPickingMultipleItems(_ allows: Bool) {}
}

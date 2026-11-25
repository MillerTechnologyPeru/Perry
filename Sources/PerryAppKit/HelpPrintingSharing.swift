import CPerryGeometry
import PerryObjCInterop

// Services of the Mac that Linux doesn't have, as AppKit answers without
// them: NSHelpManager (there is no Help Viewer, so help books neither
// register nor open), NSPrinter and NSPrintPanel (there are no printers,
// as NSPrintOperation says: the panel is cancelled), and NSSharingService
// and its picker (there are no share services; an app's own services,
// made with a handler, still perform).

// MARK: - Help

@ObjCClass("NSHelpManager")
open class NSHelpManager: NSObject {
    nonisolated(unsafe) private static var shared: NSHelpManager?
    nonisolated(unsafe) private static var contextHelpModeActive = false

    /// Context help, by object (not retained, as AppKit's table holds it).
    var helpByObject: [UnsafeMutableRawPointer: NSObject] = [:]

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCClassMethod("sharedHelpManager")
    static func sharedHelpManager() -> NSHelpManager {
        if let shared { return shared }
        let manager = NSHelpManager()
        shared = manager
        return manager
    }
    @ObjCClassMethod("isContextHelpModeActive") static func isContextHelpModeActive() -> Bool { contextHelpModeActive }
    @ObjCClassMethod("setContextHelpModeActive:") static func setContextHelpModeActive(_ value: Bool) { contextHelpModeActive = value }

    @ObjCMethod("setContextHelp:forObject:")
    func setContextHelp(_ help: NSObject?, forObject object: NSObject?) {
        guard let object else { return }
        helpByObject[object.objcObject] = help
    }
    @ObjCMethod("removeContextHelpForObject:")
    func removeContextHelp(forObject object: NSObject?) { if let object { helpByObject[object.objcObject] = nil } }
    @ObjCMethod("contextHelpForObject:")
    func contextHelp(forObject object: NSObject?) -> NSObject? { object.flatMap { helpByObject[$0.objcObject] } }
    /// There is no help window to show it in.
    @ObjCMethod("showContextHelpForObject:locationHint:")
    func showContextHelp(forObject object: NSObject?, locationHint point: CGPoint) -> Bool { false }
    @ObjCMethod("contextHelpForKey:") func contextHelp(forKey key: String?) -> NSObject? { nil }

    @ObjCMethod("openHelpAnchor:inBook:")
    func openHelpAnchor(_ anchor: String?, inBook book: String?) {
        appKitWarning("NSHelpManager: no Help Viewer here; help anchor \(anchor ?? "") in \(book ?? "the app's book") not opened")
    }
    @ObjCMethod("findString:inBook:")
    func find(_ query: String?, inBook book: String?) {
        appKitWarning("NSHelpManager: no Help Viewer here; \"\(query ?? "")\" not searched for")
    }
    /// No help books register without a Help Viewer.
    @ObjCMethod("registerBooksInBundle:") func registerBooks(in bundle: NSObject?) -> Bool { false }
    @ObjCMethod("activateContextHelpMode:") func activateContextHelpMode(_ sender: NSObject?) { NSHelpManager.contextHelpModeActive = true }
    @ObjCMethod("showHelp:") func showHelp(_ sender: NSObject?) { appKitWarning("NSHelpManager: no Help Viewer here; help not shown") }
}

// MARK: - Printing

@ObjCClass("NSPrinter")
open class NSPrinter: NSObject {
    var name = ""
    var type = ""

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCClassMethod("printerNames") static func printerNames() -> NSObject { NSMutableArray.empty() }
    @ObjCClassMethod("printerTypes") static func printerTypes() -> NSObject { NSMutableArray.empty() }
    @ObjCClassMethod("printerWithName:") static func printer(name: String?) -> NSPrinter? { nil }
    @ObjCClassMethod("printerWithType:") static func printer(type: String?) -> NSPrinter? { nil }
    @ObjCClassMethod("printerWithName:domain:includeUnavailable:")
    static func printer(name: String?, domain: String?, includeUnavailable: Bool) -> NSPrinter? { nil }

    @ObjCMethod("name") func printerName() -> String { name }
    @ObjCMethod("type") func printerType() -> String { type }
    @ObjCMethod("languageLevel") func languageLevel() -> Int { 0 }
    @ObjCMethod("pageSizeForPaper:") func pageSize(forPaper paper: String?) -> CGSize { .zero }
    @ObjCMethod("imageRectForPaper:") func imageRect(forPaper paper: String?) -> CGRect { .zero }
    @ObjCMethod("deviceDescription") func deviceDescription() -> NSObject { NSMutableDictionary.empty() }
    /// NSPrinterTableNotFound: no printer has tables here.
    @ObjCMethod("statusForTable:") func status(forTable table: String?) -> UInt { 2 }
    @ObjCMethod("isKey:inTable:") func isKey(_ key: String?, inTable table: String?) -> Bool { false }
    @ObjCMethod("isColor") func isColor() -> Bool { false }
    @ObjCMethod("acceptsBinary") func acceptsBinary() -> Bool { false }
    @ObjCMethod("isFontAvailable:") func isFontAvailable(_ face: String?) -> Bool { false }
    @ObjCMethod("isOutputStackInReverseOrder") func isOutputStackInReverseOrder() -> Bool { false }
    @ObjCMethod("domain") func domain() -> String { "" }
    @ObjCMethod("host") func host() -> String { "" }
    @ObjCMethod("note") func note() -> String { "" }
}

@ObjCClass("NSPrintPanel")
open class NSPrintPanel: NSObject {
    var accessoryControllers: [NSObject] = []
    /// NSPrintPanelOptions: copies 1 and page range 2, as AppKit starts.
    var options: UInt = 3
    var defaultButtonTitle: String?
    var helpAnchor: String?
    var jobStyleHint: String?
    var accessoryView: NSView?
    var printInfo: NSPrintInfo?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCClassMethod("printPanel") static func printPanel() -> NSPrintPanel { NSPrintPanel() }

    @ObjCMethod("addAccessoryController:")
    func addAccessoryController(_ controller: NSObject?) { if let controller { accessoryControllers.append(controller) } }
    @ObjCMethod("removeAccessoryController:")
    func removeAccessoryController(_ controller: NSObject?) { accessoryControllers.removeAll { $0.objcObject == controller?.objcObject } }
    @ObjCMethod("accessoryControllers") func panelAccessoryControllers() -> NSObject { NSMutableArray.of(accessoryControllers) }
    @ObjCMethod("options") func panelOptions() -> UInt { options }
    @ObjCMethod("setOptions:") func setOptions(_ value: UInt) { options = value }
    @ObjCMethod("defaultButtonTitle") func panelDefaultButtonTitle() -> String? { defaultButtonTitle }
    @ObjCMethod("setDefaultButtonTitle:") func setDefaultButtonTitle(_ value: String?) { defaultButtonTitle = value }
    @ObjCMethod("helpAnchor") func panelHelpAnchor() -> String? { helpAnchor }
    @ObjCMethod("setHelpAnchor:") func setHelpAnchor(_ value: String?) { helpAnchor = value }
    @ObjCMethod("jobStyleHint") func panelJobStyleHint() -> String? { jobStyleHint }
    @ObjCMethod("setJobStyleHint:") func setJobStyleHint(_ value: String?) { jobStyleHint = value }
    @ObjCMethod("accessoryView") func panelAccessoryView() -> NSView? { accessoryView }
    @ObjCMethod("setAccessoryView:") func setAccessoryView(_ value: NSView?) { accessoryView = value }
    @ObjCMethod("printInfo") func panelPrintInfo() -> NSPrintInfo { printInfo ?? NSPrintInfo.sharedPrintInfo() }
    @ObjCMethod("updateFromPrintInfo") func updateFromPrintInfo() {}
    @ObjCMethod("finalWritePrintInfo") func finalWritePrintInfo() {}

    /// NSPrintPanelResult: cancelled (0), as there is nothing to print to.
    @ObjCMethod("runModalWithPrintInfo:")
    func runModal(with info: NSPrintInfo?) -> Int {
        printInfo = info
        appKitWarning("NSPrintPanel: no printer here; the print panel is cancelled")
        return 0
    }
    @ObjCMethod("runModal") func runModal() -> Int { runModal(with: NSPrintInfo.sharedPrintInfo()) }

    /// Ends cancelled on the main queue's next turn, as a sheet the user
    /// cancelled would: -printPanelDidEnd:returnCode:contextInfo: and kin.
    @ObjCMethod("beginSheetWithPrintInfo:modalForWindow:delegate:didEndSelector:contextInfo:")
    func beginSheet(with info: NSPrintInfo?, modalFor window: NSObject?, delegate: NSObject?, didEndSelector: ObjCSelector?,
                    contextInfo: UnsafeMutableRawPointer?) {
        let code = runModal(with: info)
        guard let delegate, let didEndSelector else { return }
        Dispatch.onMain { [self] in
            typealias DidEnd = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, UnsafeMutableRawPointer, Int, UnsafeMutableRawPointer?) -> Void
            unsafeBitCast(ObjCRuntime.msgSend, to: DidEnd.self)(delegate.objcObject, didEndSelector.pointer, objcObject, code, contextInfo)
        }
    }

    @ObjCMethod("beginSheetUsingPrintInfo:onWindow:completionHandler:")
    func beginSheet(using info: NSPrintInfo?, on window: NSObject?, completionHandler: ObjCBlock?) {
        let code = runModal(with: info)
        guard let completionHandler else { return }
        Dispatch.onMain { Blocks.call(completionHandler, code) }
    }
}

// MARK: - Sharing

@ObjCClass("NSSharingService")
open class NSSharingService: NSObject {
    var title = ""
    var image: NSObject?
    var alternateImage: NSObject?
    var handler: ObjCBlock?
    /// Not retained.
    var delegateObject: UnsafeMutableRawPointer?
    var menuItemTitle: String?
    var recipients: NSObject?
    var subject: String?

    @ObjCMethod("init")
    public required override init() { super.init() }

    /// An app's own service, which runs `handler` to share.
    @ObjCMethod("initWithTitle:image:alternateImage:handler:")
    public required init(title: String?, image: NSObject?, alternateImage: NSObject?, handler: ObjCBlock?) {
        super.init()
        self.title = title ?? ""
        self.image = image
        self.alternateImage = alternateImage
        self.handler = handler
    }

    /// The system's services for the items: none here.
    @ObjCClassMethod("sharingServicesForItems:") static func sharingServices(forItems items: NSObject?) -> NSObject { NSMutableArray.empty() }
    @ObjCClassMethod("sharingServiceNamed:") static func sharingService(named name: String?) -> NSSharingService? { nil }

    @ObjCMethod("title") func serviceTitle() -> String { title }
    @ObjCMethod("image") func serviceImage() -> NSObject? { image }
    @ObjCMethod("alternateImage") func serviceAlternateImage() -> NSObject? { alternateImage }
    @ObjCMethod("menuItemTitle") func serviceMenuItemTitle() -> String { menuItemTitle ?? title }
    @ObjCMethod("setMenuItemTitle:") func setMenuItemTitle(_ value: String?) { menuItemTitle = value }
    @ObjCMethod("delegate") func serviceDelegate() -> NSObject? { delegateObject.map(NSObject.init) }
    @ObjCMethod("setDelegate:") func setDelegate(_ value: NSObject?) { delegateObject = value?.objcObject }
    @ObjCMethod("recipients") func serviceRecipients() -> NSObject? { recipients }
    @ObjCMethod("setRecipients:") func setRecipients(_ value: NSObject?) { recipients = value }
    @ObjCMethod("subject") func serviceSubject() -> String? { subject }
    @ObjCMethod("setSubject:") func setSubject(_ value: String?) { subject = value }
    @ObjCMethod("messageBody") func messageBody() -> String? { nil }
    @ObjCMethod("permanentLink") func permanentLink() -> NSObject? { nil }
    @ObjCMethod("accountName") func accountName() -> String? { nil }
    @ObjCMethod("attachmentFileURLs") func attachmentFileURLs() -> NSObject? { nil }

    @ObjCMethod("canPerformWithItems:") func canPerform(withItems items: NSObject?) -> Bool { handler != nil }

    /// Runs the handler, between the delegate's will- and did-share.
    @ObjCMethod("performWithItems:")
    func perform(withItems items: NSObject?) {
        guard let handler else {
            appKitWarning("NSSharingService: no share services here; \(title) not performed")
            return
        }
        if Send.responds(delegateObject, "sharingService:willShareItems:") {
            Send.void(delegateObject, "sharingService:willShareItems:", objcObject, items?.objcObject)
        }
        Blocks.call(handler)
        if Send.responds(delegateObject, "sharingService:didShareItems:") {
            Send.void(delegateObject, "sharingService:didShareItems:", objcObject, items?.objcObject)
        }
    }
}

@ObjCClass("NSSharingServicePicker")
open class NSSharingServicePicker: NSObject {
    var items: NSObject?
    /// Not retained.
    var delegateObject: UnsafeMutableRawPointer?
    var shareMenuItem: NSMenuItem?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithItems:")
    public required init(items: NSObject?) {
        super.init()
        self.items = items
    }

    @ObjCMethod("delegate") func pickerDelegate() -> NSObject? { delegateObject.map(NSObject.init) }
    @ObjCMethod("setDelegate:") func setDelegate(_ value: NSObject?) { delegateObject = value?.objcObject }

    /// There are no services to choose from: the picker closes at once,
    /// on the main queue's next turn, with none chosen, as one the user
    /// dismissed does (-sharingServicePicker:didChooseSharingService: nil).
    @ObjCMethod("showRelativeToRect:ofView:preferredEdge:")
    func show(relativeTo rect: CGRect, of view: NSView?, preferredEdge: UInt) {
        Dispatch.onMain { [self] in
            guard Send.responds(delegateObject, "sharingServicePicker:didChooseSharingService:") else { return }
            Send.void(delegateObject, "sharingServicePicker:didChooseSharingService:", objcObject, nil)
        }
    }
    @ObjCMethod("close") func close() {}

    /// A "Share" item whose submenu lists the services: none, so it is
    /// disabled.
    @ObjCMethod("standardShareMenuItem")
    func standardShareMenuItem() -> NSMenuItem {
        if let shareMenuItem { return shareMenuItem }
        let item = NSMenuItem(title: "Share", action: nil, keyEquivalent: "")
        item.setSubmenu(NSMenu(title: "Share"))
        item.enabled = false
        shareMenuItem = item
        return item
    }
}

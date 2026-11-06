import CPerryGeometry
import PerryObjCInterop

// Cocoa bindings' controllers: an object controller holds its content, an
// array controller its arranged objects (sorted by its sort descriptors and
// filtered by its predicate) and selection, and the user defaults
// controller the defaults, by key path "values.<key>". They keep these for
// the app's code; views bound to them in nibs read their values once.
// And printing: there are no printers, so print operations run without
// one and say they didn't print.

@ObjCClass("NSController")
open class NSController: NSObject {
    var editing = false

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) { super.init() }

    @ObjCMethod("commitEditing") func commitEditing() -> Bool { true }
    @ObjCMethod("discardEditing") func discardEditing() {}
    @ObjCMethod("isEditing") func isEditing() -> Bool { editing }
    @ObjCMethod("objectDidBeginEditing:") func objectDidBeginEditing(_ editor: NSObject?) { editing = true }
    @ObjCMethod("objectDidEndEditing:") func objectDidEndEditing(_ editor: NSObject?) { editing = false }
}

@ObjCClass("NSObjectController")
open class NSObjectController: NSController {
    var content: NSObject?
    var objectClassName = "NSMutableDictionary"
    var editable = true
    var automaticallyPreparesContent = false
    var entityName: String?

    @ObjCMethod("init")
    public required init() { super.init() }

    @ObjCMethod("initWithContent:")
    public required init(content: NSObject?) {
        super.init()
        self.content = content
    }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init(coder: coder)
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        objectClassName = decoded.string("NSObjectClassName") ?? objectClassName
        if decoded.has("NSEditable") { editable = decoded.bool("NSEditable") }
        automaticallyPreparesContent = decoded.bool("NSAutomaticallyPreparesContent")
        entityName = decoded.string("NSEntityName")
    }

    @ObjCMethod("content") func controllerContent() -> NSObject? { content }
    @ObjCMethod("setContent:") func setContent(_ value: NSObject?) { content = value }
    @ObjCMethod("selection") func selection() -> NSObject? { content }
    @ObjCMethod("selectedObjects") func selectedObjects() -> NSObject { NSMutableArray.of(content.map { [$0] } ?? []) }
    @ObjCMethod("objectClass") func objectClass() -> ObjCClass? { Classes.named(objectClassName) }
    @ObjCMethod("setObjectClass:") func setObjectClass(_ cls: ObjCClass?) { if let cls, let name = NSObject(cls.pointer).describedByObject() { objectClassName = name } }
    @ObjCMethod("isEditable") func isEditable() -> Bool { editable }
    @ObjCMethod("setEditable:") func setEditable(_ value: Bool) { editable = value }
    @ObjCMethod("automaticallyPreparesContent") func controllerAutomaticallyPreparesContent() -> Bool { automaticallyPreparesContent }
    @ObjCMethod("setAutomaticallyPreparesContent:") func setAutomaticallyPreparesContent(_ value: Bool) { automaticallyPreparesContent = value }
    @ObjCMethod("entityName") func controllerEntityName() -> String? { entityName }
    @ObjCMethod("setEntityName:") func setEntityName(_ value: String?) { entityName = value }
    @ObjCMethod("managedObjectContext") func managedObjectContext() -> NSObject? { nil }
    @ObjCMethod("setManagedObjectContext:") func setManagedObjectContext(_ value: NSObject?) {}
    @ObjCMethod("newObject")
    func newObject() -> UnsafeMutableRawPointer? {
        guard let cls = Classes.named(objectClassName) else { return nil }
        return Send.object(Send.object(cls.pointer, "alloc"), "init")
    }
    @ObjCMethod("canAdd") func canAdd() -> Bool { editable }
    @ObjCMethod("canRemove") func canRemove() -> Bool { editable && content != nil }
    @ObjCMethod("add:")
    func add(_ sender: NSObject?) {
        if let made = newObject() { content = NSObject(objcObject: made, ownership: .adopt) }
    }
    @ObjCMethod("remove:") func remove(_ sender: NSObject?) { content = nil }
    @ObjCMethod("prepareContent") func prepareContent() {}
    @ObjCMethod("fetch:") func fetch(_ sender: NSObject?) {}
}

@ObjCClass("NSArrayController")
open class NSArrayController: NSObjectController {
    var arranged: [NSObject] = []
    var selectionIndexes: [Int] = []
    var sortDescriptors: NSObject?
    var filterPredicate: NSObject?
    var avoidsEmptySelection = true
    var preservesSelection = true
    var selectsInsertedObjects = true
    var clearsFilterPredicateOnInsertion = true
    var automaticallyRearrangesObjects = false

    @ObjCMethod("init")
    public required init() { super.init() }

    @ObjCMethod("initWithContent:")
    public required init(content: NSObject?) {
        super.init(content: content)
        rearrangeObjects()
    }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init(coder: coder)
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        if decoded.has("NSAvoidsEmptySelection") { avoidsEmptySelection = decoded.bool("NSAvoidsEmptySelection") }
        if decoded.has("NSPreservesSelection") { preservesSelection = decoded.bool("NSPreservesSelection") }
        if decoded.has("NSSelectsInsertedObjects") { selectsInsertedObjects = decoded.bool("NSSelectsInsertedObjects") }
        if decoded.has("NSClearsFilterPredicateOnInsertion") { clearsFilterPredicateOnInsertion = decoded.bool("NSClearsFilterPredicateOnInsertion") }
        sortDescriptors = decoded.object("NSSortDescriptors")
    }

    var contentArray: [NSObject] {
        guard let content else { return [] }
        if let array = content.as(NSArray.self) { return array.elements }
        if content.responds(to: "allObjects"), let all = Send.object(content.objcObject, "allObjects") { return NSObject(all).as(NSArray.self)?.elements ?? [] }
        return [content]
    }

    @ObjCMethod("setContent:")
    override func setContent(_ value: NSObject?) {
        content = value
        rearrangeObjects()
    }

    /// The content, filtered and sorted.
    @ObjCMethod("rearrangeObjects")
    func rearrangeObjects() {
        var objects = NSMutableArray.of(contentArray)
        if let filterPredicate, let filtered = Send.object(objects.objcObject, "filteredArrayUsingPredicate:", filterPredicate.objcObject) {
            objects = NSObject(filtered).unsafeCast(to: NSMutableArray.self)
        }
        if let sortDescriptors, Send.integer(sortDescriptors.objcObject, "count") > 0,
           let sorted = Send.object(objects.objcObject, "sortedArrayUsingDescriptors:", sortDescriptors.objcObject) {
            objects = NSObject(sorted).unsafeCast(to: NSMutableArray.self)
        }
        Send.void(objcObject, "willChangeValueForKey:", "arrangedObjects".objCArgument())
        arranged = objects.elements
        Send.void(objcObject, "didChangeValueForKey:", "arrangedObjects".objCArgument())
        selectionIndexes = selectionIndexes.filter { $0 < arranged.count }
        if selectionIndexes.isEmpty, avoidsEmptySelection, !arranged.isEmpty { selectionIndexes = [0] }
    }

    @ObjCMethod("arrangedObjects") func arrangedObjects() -> NSObject { NSMutableArray.of(arranged) }
    @ObjCMethod("arrangeObjects:")
    func arrange(_ objects: NSObject?) -> NSObject {
        let saved = content
        content = objects
        rearrangeObjects()
        content = saved
        return NSMutableArray.of(arranged)
    }
    @ObjCMethod("selection") override func selection() -> NSObject? { selectionIndexes.first.map { arranged[$0] } }
    @ObjCMethod("selectedObjects") override func selectedObjects() -> NSObject { NSMutableArray.of(selectionIndexes.map { arranged[$0] }) }
    @ObjCMethod("setSelectedObjects:")
    func setSelectedObjects(_ objects: NSObject?) -> Bool {
        let wanted = objects?.as(NSArray.self)?.elements.map(\.objcObject) ?? []
        selectionIndexes = arranged.indices.filter { wanted.contains(arranged[$0].objcObject) }
        return true
    }
    @ObjCMethod("selectionIndex") func selectionIndex() -> Int { selectionIndexes.first ?? Int.max }
    @ObjCMethod("setSelectionIndex:") func setSelectionIndex(_ index: Int) -> Bool { selectionIndexes = arranged.indices.contains(index) ? [index] : []; return true }
    @ObjCMethod("selectionIndexes") func controllerSelectionIndexes() -> NSObject { IndexSets.make(selectionIndexes) }
    @ObjCMethod("setSelectionIndexes:")
    func setSelectionIndexes(_ indexes: NSObject?) -> Bool {
        selectionIndexes = IndexSets.indexes(indexes).filter { $0 < arranged.count }
        return true
    }
    @ObjCMethod("addSelectionIndexes:")
    func addSelectionIndexes(_ indexes: NSObject?) -> Bool {
        for index in IndexSets.indexes(indexes) where index < arranged.count && !selectionIndexes.contains(index) { selectionIndexes.append(index) }
        return true
    }
    @ObjCMethod("removeSelectionIndexes:")
    func removeSelectionIndexes(_ indexes: NSObject?) -> Bool {
        let removed = IndexSets.indexes(indexes)
        selectionIndexes.removeAll { removed.contains($0) }
        return true
    }
    @ObjCMethod("selectNext:") func selectNext(_ sender: NSObject?) { if let index = selectionIndexes.last, index + 1 < arranged.count { selectionIndexes = [index + 1] } }
    @ObjCMethod("selectPrevious:") func selectPrevious(_ sender: NSObject?) { if let index = selectionIndexes.first, index > 0 { selectionIndexes = [index - 1] } }
    @ObjCMethod("canSelectNext") func canSelectNext() -> Bool { (selectionIndexes.last ?? arranged.count) + 1 < arranged.count }
    @ObjCMethod("canSelectPrevious") func canSelectPrevious() -> Bool { (selectionIndexes.first ?? 0) > 0 }
    @ObjCMethod("sortDescriptors") func controllerSortDescriptors() -> NSObject { sortDescriptors ?? NSMutableArray.empty() }
    @ObjCMethod("setSortDescriptors:") func setSortDescriptors(_ value: NSObject?) { sortDescriptors = value; rearrangeObjects() }
    @ObjCMethod("filterPredicate") func controllerFilterPredicate() -> NSObject? { filterPredicate }
    @ObjCMethod("setFilterPredicate:") func setFilterPredicate(_ value: NSObject?) { filterPredicate = value; rearrangeObjects() }
    @ObjCMethod("avoidsEmptySelection") func controllerAvoidsEmptySelection() -> Bool { avoidsEmptySelection }
    @ObjCMethod("setAvoidsEmptySelection:") func setAvoidsEmptySelection(_ value: Bool) { avoidsEmptySelection = value }
    @ObjCMethod("preservesSelection") func controllerPreservesSelection() -> Bool { preservesSelection }
    @ObjCMethod("setPreservesSelection:") func setPreservesSelection(_ value: Bool) { preservesSelection = value }
    @ObjCMethod("selectsInsertedObjects") func controllerSelectsInsertedObjects() -> Bool { selectsInsertedObjects }
    @ObjCMethod("setSelectsInsertedObjects:") func setSelectsInsertedObjects(_ value: Bool) { selectsInsertedObjects = value }
    @ObjCMethod("clearsFilterPredicateOnInsertion") func controllerClearsFilterPredicateOnInsertion() -> Bool { clearsFilterPredicateOnInsertion }
    @ObjCMethod("setClearsFilterPredicateOnInsertion:") func setClearsFilterPredicateOnInsertion(_ value: Bool) { clearsFilterPredicateOnInsertion = value }
    @ObjCMethod("automaticallyRearrangesObjects") func controllerAutomaticallyRearrangesObjects() -> Bool { automaticallyRearrangesObjects }
    @ObjCMethod("setAutomaticallyRearrangesObjects:") func setAutomaticallyRearrangesObjects(_ value: Bool) { automaticallyRearrangesObjects = value }

    /// The content's array changes: objects added, inserted or removed.
    private func mutate(_ body: (NSMutableArray) -> Void) {
        let array = NSMutableArray.of(contentArray)
        body(array)
        content = array
        rearrangeObjects()
    }

    @ObjCMethod("addObject:")
    func addObject(_ object: NSObject?) {
        guard let object else { return }
        if clearsFilterPredicateOnInsertion { filterPredicate = nil }
        mutate { $0.add(object) }
        if selectsInsertedObjects, let index = arranged.firstIndex(where: { $0 === object || $0.objcObject == object.objcObject }) { selectionIndexes = [index] }
    }
    @ObjCMethod("addObjects:") func addObjects(_ objects: NSObject?) { for object in objects?.as(NSArray.self)?.elements ?? [] { addObject(object) } }
    @ObjCMethod("insertObject:atArrangedObjectIndex:")
    func insert(_ object: NSObject?, atArrangedObjectIndex index: Int) {
        guard let object else { return }
        mutate { array in
            typealias F = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, UnsafeMutableRawPointer, Int) -> Void
            unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(array.objcObject, ObjCRuntime.selector("insertObject:atIndex:"), object.objcObject,
                                                           max(0, min(index, Int(array.count()))))
        }
    }
    @ObjCMethod("removeObject:")
    func removeObject(_ object: NSObject?) {
        guard let object else { return }
        mutate { Send.void($0.objcObject, "removeObject:", object.objcObject) }
    }
    @ObjCMethod("removeObjects:")
    func removeObjects(_ objects: NSObject?) {
        guard let objects else { return }
        mutate { Send.void($0.objcObject, "removeObjectsInArray:", objects.objcObject) }
    }
    @ObjCMethod("removeObjectAtArrangedObjectIndex:")
    func removeObject(atArrangedObjectIndex index: Int) {
        guard arranged.indices.contains(index) else { return }
        removeObject(arranged[index])
    }
    @ObjCMethod("remove:") override func remove(_ sender: NSObject?) { for index in selectionIndexes.sorted(by: >) { removeObject(atArrangedObjectIndex: index) } }
    @ObjCMethod("add:")
    override func add(_ sender: NSObject?) {
        if let made = newObject() { addObject(NSObject(objcObject: made, ownership: .adopt)) }
    }
    @ObjCMethod("canInsert") func canInsert() -> Bool { editable }
    @ObjCMethod("insert:") func insert(_ sender: NSObject?) { add(sender) }
}

/// The shared user defaults controller: "values.<key>" are the defaults'.
@ObjCClass("NSUserDefaultsController")
open class NSUserDefaultsController: NSController {
    nonisolated(unsafe) static var shared: NSUserDefaultsController?
    var initialValues: NSObject?
    var appliesImmediately = true

    @ObjCClassMethod("sharedUserDefaultsController")
    static func sharedUserDefaultsController() -> NSUserDefaultsController {
        if let shared { return shared }
        let controller = NSUserDefaultsController()
        shared = controller
        return controller
    }

    var defaults: NSObject? { Send.object(Classes.named("NSUserDefaults")?.pointer, "standardUserDefaults").map(NSObject.init) }

    @ObjCMethod("defaults") func controllerDefaults() -> NSObject? { defaults }
    /// The defaults, for "values.<key>" key paths.
    @ObjCMethod("values") func values() -> NSObject? { defaults }
    @ObjCMethod("initialValues") func controllerInitialValues() -> NSObject? { initialValues }
    @ObjCMethod("setInitialValues:") func setInitialValues(_ value: NSObject?) { initialValues = value }
    @ObjCMethod("appliesImmediately") func controllerAppliesImmediately() -> Bool { appliesImmediately }
    @ObjCMethod("setAppliesImmediately:") func setAppliesImmediately(_ value: Bool) { appliesImmediately = value }
    @ObjCMethod("hasUnappliedChanges") func hasUnappliedChanges() -> Bool { false }
    @ObjCMethod("save:") func save(_ sender: NSObject?) { _ = defaults.map { Send.bool($0.objcObject, "synchronize") } }
    @ObjCMethod("revert:") func revert(_ sender: NSObject?) {}
    @ObjCMethod("revertToInitialValues:") func revertToInitialValues(_ sender: NSObject?) {}
}

// MARK: - Printing

@ObjCClass("NSPrintInfo")
open class NSPrintInfo: NSObject {
    nonisolated(unsafe) static var shared: NSPrintInfo?
    var paperSize = CGSize(width: 612, height: 792)
    var margins = NSEdgeInsets(top: 72, left: 72, bottom: 72, right: 72)
    var orientation = 0
    var horizontalPagination = 0
    var verticalPagination = 0
    var horizontallyCentered = true
    var verticallyCentered = true

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCClassMethod("sharedPrintInfo")
    static func sharedPrintInfo() -> NSPrintInfo {
        if let shared { return shared }
        let info = NSPrintInfo()
        shared = info
        return info
    }
    @ObjCClassMethod("setSharedPrintInfo:") static func setSharedPrintInfo(_ info: NSPrintInfo?) { shared = info }

    @ObjCMethod("paperSize") func infoPaperSize() -> CGSize { paperSize }
    @ObjCMethod("setPaperSize:") func setPaperSize(_ value: CGSize) { paperSize = value }
    @ObjCMethod("imageablePageBounds")
    func imageablePageBounds() -> CGRect { CGRect(x: 18, y: 18, width: paperSize.width - 36, height: paperSize.height - 36) }
    @ObjCMethod("topMargin") func topMargin() -> CGFloat { margins.top }
    @ObjCMethod("setTopMargin:") func setTopMargin(_ value: CGFloat) { margins.top = value }
    @ObjCMethod("bottomMargin") func bottomMargin() -> CGFloat { margins.bottom }
    @ObjCMethod("setBottomMargin:") func setBottomMargin(_ value: CGFloat) { margins.bottom = value }
    @ObjCMethod("leftMargin") func leftMargin() -> CGFloat { margins.left }
    @ObjCMethod("setLeftMargin:") func setLeftMargin(_ value: CGFloat) { margins.left = value }
    @ObjCMethod("rightMargin") func rightMargin() -> CGFloat { margins.right }
    @ObjCMethod("setRightMargin:") func setRightMargin(_ value: CGFloat) { margins.right = value }
    @ObjCMethod("orientation") func infoOrientation() -> Int { orientation }
    @ObjCMethod("setOrientation:") func setOrientation(_ value: Int) { orientation = value }
    @ObjCMethod("horizontalPagination") func infoHorizontalPagination() -> Int { horizontalPagination }
    @ObjCMethod("setHorizontalPagination:") func setHorizontalPagination(_ value: Int) { horizontalPagination = value }
    @ObjCMethod("verticalPagination") func infoVerticalPagination() -> Int { verticalPagination }
    @ObjCMethod("setVerticalPagination:") func setVerticalPagination(_ value: Int) { verticalPagination = value }
    @ObjCMethod("isHorizontallyCentered") func isHorizontallyCentered() -> Bool { horizontallyCentered }
    @ObjCMethod("setHorizontallyCentered:") func setHorizontallyCentered(_ value: Bool) { horizontallyCentered = value }
    @ObjCMethod("isVerticallyCentered") func isVerticallyCentered() -> Bool { verticallyCentered }
    @ObjCMethod("setVerticallyCentered:") func setVerticallyCentered(_ value: Bool) { verticallyCentered = value }
    @ObjCMethod("dictionary") func dictionary() -> NSObject { NSMutableDictionary.empty() }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }
}

/// NSPrintOperation: there are no printers; running one answers that it
/// didn't print.
@ObjCClass("NSPrintOperation")
open class NSPrintOperation: NSObject {
    var view: NSView?
    var printInfo: NSPrintInfo = NSPrintInfo.sharedPrintInfo()
    var showsPrintPanel = true
    var showsProgressPanel = true
    var jobTitle: String?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCClassMethod("printOperationWithView:")
    static func printOperation(view: NSView?) -> NSPrintOperation {
        let operation = NSPrintOperation()
        operation.view = view
        return operation
    }

    @ObjCClassMethod("printOperationWithView:printInfo:")
    static func printOperation(view: NSView?, printInfo: NSPrintInfo?) -> NSPrintOperation {
        let operation = printOperation(view: view)
        if let printInfo { operation.printInfo = printInfo }
        return operation
    }

    @ObjCMethod("view") func operationView() -> NSView? { view }
    @ObjCMethod("printInfo") func operationPrintInfo() -> NSPrintInfo { printInfo }
    @ObjCMethod("setPrintInfo:") func setPrintInfo(_ value: NSPrintInfo?) { if let value { printInfo = value } }
    @ObjCMethod("showsPrintPanel") func operationShowsPrintPanel() -> Bool { showsPrintPanel }
    @ObjCMethod("setShowsPrintPanel:") func setShowsPrintPanel(_ value: Bool) { showsPrintPanel = value }
    @ObjCMethod("showsProgressPanel") func operationShowsProgressPanel() -> Bool { showsProgressPanel }
    @ObjCMethod("setShowsProgressPanel:") func setShowsProgressPanel(_ value: Bool) { showsProgressPanel = value }
    @ObjCMethod("jobTitle") func operationJobTitle() -> String? { jobTitle }
    @ObjCMethod("setJobTitle:") func setJobTitle(_ value: String?) { jobTitle = value }
    @ObjCMethod("printPanel") func printPanel() -> NSObject? { nil }
    @ObjCMethod("runOperation")
    func runOperation() -> Bool {
        appKitWarning("NSPrintOperation: no printer here; nothing printed")
        return false
    }
    @ObjCMethod("runOperationModalForWindow:delegate:didRunSelector:contextInfo:")
    func runOperationModal(for window: NSObject?, delegate: NSObject?, didRunSelector: ObjCSelector?, contextInfo: UnsafeMutableRawPointer?) {
        _ = runOperation()
    }
}

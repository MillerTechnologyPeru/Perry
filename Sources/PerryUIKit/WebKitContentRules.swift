import PerryObjCInterop

// WebKit's content rule lists: compiled sets of content-blocking rules.
// Pages here don't apply them (there is no rule compiler), but apps that
// compile and add lists at launch get lists back, and a controller keeps
// those added to it.

private typealias Invoke1 = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?) -> Void
private typealias Invoke2 = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void

@ObjCClass("WKContentRuleList")
open class WKContentRuleList: NSObject {
    var identifier = ""
    var encoded = ""

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("identifier") func ruleListIdentifier() -> String { identifier }
}

@ObjCClass("WKContentRuleListStore")
open class WKContentRuleListStore: NSObject {
    nonisolated(unsafe) private static let shared = WKContentRuleListStore()
    private var lists: [String: WKContentRuleList] = [:]

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCClassMethod("defaultStore") class func defaultStore() -> WKContentRuleListStore { shared }
    @ObjCClassMethod("storeWithURL:") class func store(url: NSObject?) -> WKContentRuleListStore { WKContentRuleListStore() }

    @ObjCMethod("compileContentRuleListForIdentifier:encodedContentRuleList:completionHandler:")
    func compile(identifier: String?, encoded: String?, completionHandler: ObjCBlock?) {
        let list = WKContentRuleList()
        list.identifier = identifier ?? ""
        list.encoded = encoded ?? ""
        lists[list.identifier] = list
        guard let completionHandler else { return }
        Updates.afterPass { completionHandler.function(as: Invoke2.self)(completionHandler.object, list.objcObject, nil) }
    }

    @ObjCMethod("lookUpContentRuleListForIdentifier:completionHandler:")
    func lookUp(identifier: String?, completionHandler: ObjCBlock?) {
        let list = identifier.flatMap { lists[$0] }
        guard let completionHandler else { return }
        Updates.afterPass {
            // WKErrorContentRuleListStoreLookUpFailed: no list by that name.
            completionHandler.function(as: Invoke2.self)(
                completionHandler.object, list?.objcObject,
                list == nil ? NSErrorObject.make(domain: "WKErrorDomain", code: 8, userInfo: nil).objcObject : nil)
        }
    }

    @ObjCMethod("removeContentRuleListForIdentifier:completionHandler:")
    func remove(identifier: String?, completionHandler: ObjCBlock?) {
        if let identifier { lists[identifier] = nil }
        if let completionHandler { Updates.afterPass { completionHandler.function(as: Invoke1.self)(completionHandler.object, nil) } }
    }

    @ObjCMethod("getAvailableContentRuleListIdentifiers:")
    func availableIdentifiers(completionHandler: ObjCBlock?) {
        let identifiers = NSMutableArray.of(lists.keys.sorted().compactMap { $0.objCArgument().map(NSObject.init) })
        if let completionHandler { Updates.afterPass { completionHandler.function(as: Invoke1.self)(completionHandler.object, identifiers.objcObject) } }
    }
}
